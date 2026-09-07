if Code.ensure_loaded?(Phoenix.Component) do
  defmodule Visualize.Components.Support do
    @moduledoc false
    # What every component shares (spec/10 §1.2): the frame arithmetic, the colour palette
    # behind a `colors` assign, the one-unit span of a collapsed domain, and the label
    # truncation of the hierarchy components.

    alias Visualize.Scale

    @transition "transition: all 0.3s ease-in-out;"

    @doc false
    # `{margin, inner_width, inner_height}`: the assign merged over the component's default.
    def frame(assigns, default_margin) do
      margin = Map.merge(default_margin, assigns.margin || %{})

      {margin, assigns.width - margin.left - margin.right,
       assigns.height - margin.top - margin.bottom}
    end

    @doc false
    # The attribute list a mark spreads: the CSS transition when animating, nothing
    # otherwise, so a mark without animation carries no `style` at all.
    def transition(true), do: [style: @transition]
    def transition(false), do: []

    @doc false
    # The `class` attribute of the `<svg>` as an attribute list: absent when `nil`.
    def class(nil), do: []
    def class(class), do: [class: class]

    @doc false
    # Coordinates print through the one number formatter of every serialiser (spec/02 §3):
    # at most four decimals, never `-0`, so a golden does not record float noise.
    defdelegate fmt(number), to: Visualize.IR.Path, as: :format_number

    @doc false
    # An ordinal scale from `0..n-1` to the colours of a scheme atom or an explicit list;
    # `Visualize.Scale.Ordinal.apply/2` cycles when the list is shorter than `n`.
    def palette(colors, n) when is_list(colors) and colors != [] do
      Scale.ordinal() |> Scale.domain(Enum.to_list(0..(n - 1)//1)) |> Scale.range(colors)
    end

    def palette([], _n), do: raise(ArgumentError, "colors: an empty list has no colour to draw")

    def palette(scheme, n) when is_atom(scheme) do
      case Scale.Color.scheme(scheme) do
        nil ->
          raise ArgumentError,
                "colors: unknown scheme #{inspect(scheme)}; see Visualize.Scale.Color.schemes/0"

        stops ->
          palette(stops, n)
      end
    end

    @doc false
    # A two-element domain for a continuous scale. Equal ends would divide by zero in
    # `apply/2`, so a collapsed domain spans one unit (one second for times) from its value.
    def span([lo, hi]) when lo == hi, do: [lo, step(lo)]
    def span([lo, hi]), do: [lo, hi]

    defp step(%DateTime{} = t), do: DateTime.add(t, 1, :second)
    defp step(%NaiveDateTime{} = t), do: NaiveDateTime.add(t, 1, :second)
    defp step(%Date{} = d), do: Date.add(d, 1)
    defp step(n) when is_number(n), do: n + 1

    @doc false
    # `[lo, hi]` of the accessor over `data`, or `[0, 1]` when there is no data. Time values
    # are ordered by their own module: term order on a `DateTime` compares its fields
    # alphabetically, day before year.
    def extent([], _accessor), do: [0, 1]

    def extent(data, accessor) do
      values = Enum.map(data, accessor)

      {lo, hi} =
        case hd(values) do
          %mod{} when mod in [DateTime, NaiveDateTime, Date] -> Enum.min_max(values, mod)
          _ -> Visualize.Data.extent(values)
        end

      span([lo, hi])
    end

    @doc false
    # The x scale of a series chart, decided by the first datum: a time scale for
    # `DateTime`, `NaiveDateTime` or `Date`, linear for a number, a band scale with padding
    # 0.1 for anything else; linear over `[0, 1]` with no data.
    def x_scale([], _accessor, width),
      do: Scale.linear() |> Scale.domain([0, 1]) |> Scale.range([0, width])

    def x_scale(data, accessor, width) do
      case accessor.(hd(data)) do
        %mod{} when mod in [DateTime, NaiveDateTime, Date] ->
          Scale.time() |> Scale.domain(extent(data, accessor)) |> Scale.range([0, width])

        n when is_number(n) ->
          Scale.linear() |> Scale.domain(extent(data, accessor)) |> Scale.range([0, width])

        _ ->
          Scale.band()
          |> Scale.domain(Enum.map(data, accessor))
          |> Scale.range([0, width])
          |> Scale.padding(0.1)
      end
    end

    @doc false
    # `[0, max]` of the accessor over `data`, `[0, 1]` when there is no data or the maximum
    # is not positive.
    def from_zero([], _accessor), do: [0, 1]
    def from_zero(data, accessor), do: span([0, max(0, Enum.max(Enum.map(data, accessor)))])

    @doc false
    # Cuts `label` to the characters that fit `max_width` pixels at seven pixels each,
    # ending a cut label with an ellipsis.
    def truncate(label, max_width) do
      label = to_string(label)
      chars = trunc(max_width / 7)

      if String.length(label) > chars do
        String.slice(label, 0, max(chars - 1, 0)) <> "…"
      else
        label
      end
    end
  end
end
