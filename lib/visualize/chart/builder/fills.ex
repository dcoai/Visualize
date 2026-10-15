if Code.ensure_loaded?(Phoenix.Component) do
  defmodule Visualize.Chart.Builder.Fills do
    @moduledoc """
    A fill as a fill style (spec/14 §18.6): none, solid, a linear or a radial gradient.

    A style's `fill` is one key, but a person writes it as a choice among four, two of
    which are a gradient the design declares under `defs` (spec/14 §2.7). This module is
    the pure part: what the controls of the fill group mean — `fill_style`, `fill.stop.<i>`,
    `fill.stop.<i>.slot`, `fill.stop.<i>.opacity`, `fill.angle`, `fill.centre.x`,
    `fill.centre.y` — as writes to the style's `fill` and to the gradient named for the
    style, and what the form shows for a fill. The builder applies the writes, since only
    it knows which site declares what.

    This module compiles only when `Phoenix.Component` is loaded (spec/10 §1.1, D-45, D-85).
    """

    alias Visualize.Chart.Builder.Editor
    alias Visualize.Chart.{Schema, Var}

    @styles [:none, :solid, :linear, :radial]

    @typedoc "A write the fill group asks for."
    @type write ::
            {:fill, {:ok, term()} | :error}
            | {:declare, atom(), map()}
            | {:gradient, atom(), (map() -> map())}

    @doc """
    Whether a control of the form belongs to the fill group rather than to a key.

        iex> Visualize.Chart.Builder.Fills.control?("fill_style")
        true

        iex> Visualize.Chart.Builder.Fills.control?("fill.stop.1.slot")
        true

        iex> Visualize.Chart.Builder.Fills.control?("fill.slot")
        false
    """
    @spec control?(String.t()) :: boolean()
    def control?("fill_style"), do: true
    def control?("fill.stop." <> _rest), do: true
    def control?("fill.angle"), do: true
    def control?("fill.angle.range"), do: true
    def control?("fill.centre." <> _rest), do: true
    def control?(_other), do: false

    @doc """
    The name of the gradient a style at a path fills with (spec/14 §18.6): the style's
    name, or its path spelt with underscores, and `_fill`.

        iex> Visualize.Chart.Builder.Fills.name([:styles, :series])
        :series_fill

        iex> Visualize.Chart.Builder.Fills.name([:marks, 0, :style])
        :marks_0_style_fill

        iex> Visualize.Chart.Builder.Fills.name([:style])
        :style_fill
    """
    @spec name([term()]) :: atom()
    def name(path) do
      case path do
        [:styles, name] -> :"#{name}_fill"
        _other -> :"#{Enum.map_join(path, "_", &to_string/1)}_fill"
      end
    end

    @doc """
    The fill style a value shows as: `:none`, `:solid`, or the kind of the gradient a paint
    names — `:linear` when the gradient is not declared, so the choice still reads.

        iex> Visualize.Chart.Builder.Fills.style_of(:none, %{})
        :none

        iex> Visualize.Chart.Builder.Fills.style_of({:paint, :g}, %{g: %{type: :radial}})
        :radial

        iex> Visualize.Chart.Builder.Fills.style_of("#abc", %{})
        :solid

        iex> Visualize.Chart.Builder.Fills.style_of(nil, %{})
        :solid
    """
    @spec style_of(term(), map()) :: :none | :solid | :linear | :radial
    def style_of(:none, _defs), do: :none

    def style_of({:paint, name}, defs) do
      case Map.get(defs, name) do
        %{type: :radial} -> :radial
        _other -> :linear
      end
    end

    def style_of(_value, _defs), do: :solid

    @doc "The four fill styles in order."
    @spec styles() :: [atom()]
    def styles, do: @styles

    @doc """
    What a control of the fill group writes (spec/14 §18.6), given the fill's current value,
    the design's `defs`, the gradient's name for this style, and the colour the well shows.
    `fill.angle.range` is the angle's scrubber and writes as `fill.angle` does.

        iex> Visualize.Chart.Builder.Fills.writes("fill_style", "none", "#abc", %{}, :s_fill, "#abc")
        [fill: {:ok, :none}]

        iex> Visualize.Chart.Builder.Fills.writes("fill_style", "solid", {:paint, :s_fill}, %{s_fill: %{type: :linear, stops: [%{at: 0, color: "#123"}]}}, :s_fill, "#123")
        [fill: {:ok, "#123"}]

        iex> [{:declare, :s_fill, gradient}, {:fill, {:ok, {:paint, :s_fill}}}] =
        ...>   Visualize.Chart.Builder.Fills.writes("fill_style", "linear", "#abc", %{}, :s_fill, "#abc")
        iex> gradient
        %{type: :linear, stops: [%{at: 0, color: "#abc", opacity: 0.8}, %{at: 1, color: "#abc", opacity: 0.1}]}

        iex> [{:gradient, :s_fill, fun}] = Visualize.Chart.Builder.Fills.writes("fill.angle", "90", nil, %{}, :s_fill, nil)
        iex> fun.(%{type: :linear, stops: []})
        %{type: :linear, stops: [], angle: 90}

        iex> Visualize.Chart.Builder.Fills.writes("fill.nonsense", "1", nil, %{}, :s_fill, nil)
        []
    """
    @spec writes(String.t(), String.t() | nil, term(), map(), atom(), String.t() | nil) :: [
            write()
          ]
    def writes("fill_style", picked, value, defs, name, well) do
      case Enum.find(@styles, &(to_string(&1) == picked)) do
        :none ->
          [fill: {:ok, :none}]

        :solid ->
          [fill: {:ok, solid(value, defs, well)}]

        kind when kind in [:linear, :radial] ->
          gradient =
            case Map.get(defs, name) do
              nil -> fresh(kind, solid(value, defs, well))
              declared -> Map.put(declared, :type, kind)
            end

          [{:declare, name, gradient}, {:fill, {:ok, {:paint, name}}}]

        nil ->
          []
      end
    end

    def writes("fill.stop." <> rest, submitted, _value, _defs, name, _well) do
      case String.split(rest, ".") do
        [i] -> stop(name, i, :color, Editor.submitted(:colour, submitted))
        [i, "slot"] -> stop(name, i, :color, Editor.submitted(:slot, submitted))
        [i, "opacity"] -> stop(name, i, :opacity, Editor.submitted(:size, submitted))
        _other -> []
      end
    end

    def writes(angle, submitted, _value, _defs, name, _well)
        when angle in ["fill.angle", "fill.angle.range"],
        do: key(name, :angle, Editor.submitted(:number, submitted))

    def writes("fill.centre." <> axis, submitted, _value, _defs, name, _well)
        when axis in ["x", "y"] do
      case Editor.submitted(:number, submitted) do
        {:ok, n} ->
          at = if axis == "x", do: 0, else: 1

          [
            {:gradient, name,
             fn g ->
               center = Map.get(g, :center, Schema.default(:paint, :center))
               Map.put(g, :center, List.replace_at(center, at, n))
             end}
          ]

        :error ->
          []
      end
    end

    def writes(_other, _submitted, _value, _defs, _name, _well), do: []

    # The colour a solid fill takes: the well's, the paint's first stop, or the first series.
    defp solid({:paint, name}, defs, _well) do
      case Map.get(defs, name) do
        %{stops: [%{color: colour} | _]} -> colour
        _other -> :series_1
      end
    end

    defp solid(value, _defs, _well) when value in [nil, :none], do: :series_1
    defp solid(value, _defs, _well) when is_binary(value) or is_atom(value), do: value

    defp solid(_value, _defs, _well), do: :series_1

    # A new gradient: the colour at 0.8 fading to 0.1, the area chart's convention.
    defp fresh(kind, colour) do
      colour = if colour == :none, do: :series_1, else: colour

      %{
        type: kind,
        stops: [
          %{at: 0, color: colour, opacity: 0.8},
          %{at: 1, color: colour, opacity: 0.1}
        ]
      }
    end

    defp key(name, key, {:ok, value}), do: [{:gradient, name, &Map.put(&1, key, value)}]
    defp key(_name, _key, :error), do: []

    defp stop(name, i, key, parsed) do
      case {Integer.parse(i), parsed} do
        {{index, ""}, {:ok, value}} ->
          [
            {:gradient, name,
             fn g ->
               stops = Map.get(g, :stops, [])

               if index < length(stops),
                 do: Map.put(g, :stops, List.update_at(stops, index, &Map.put(&1, key, value))),
                 else: g
             end}
          ]

        _other ->
          []
      end
    end

    @doc """
    What the form shows for a fill (spec/14 §18.6): the fill style, and for a gradient its
    stops as wells, its angle or its centre.
    """
    @spec view(term(), map(), atom()) :: map()
    def view(value, defs, name) do
      style = style_of(value, defs)

      gradient =
        case value do
          {:paint, paint} -> Map.get(defs, paint)
          _other -> nil
        end

      %{
        style: style,
        paint: paint_name(value),
        name: name,
        gradient: gradient,
        stops: stops(gradient),
        angle: gradient && Map.get(gradient, :angle, Schema.default(:paint, :angle)),
        centre: gradient && Map.get(gradient, :center, Schema.default(:paint, :center))
      }
    end

    defp paint_name({:paint, name}), do: name
    defp paint_name(_value), do: nil

    defp stops(nil), do: []

    defp stops(%{stops: stops}) when is_list(stops) do
      stops
      |> Enum.with_index()
      |> Enum.map(fn {stop, i} ->
        %{
          index: i,
          colour: colour(Map.get(stop, :color)),
          opacity: Map.get(stop, :opacity, Schema.default(:stop, :opacity))
        }
      end)
    end

    defp stops(_other), do: []

    defp colour(%Var{}), do: nil
    defp colour(value), do: value
  end
end
