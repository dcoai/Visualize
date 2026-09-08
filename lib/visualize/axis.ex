defmodule Visualize.Axis do
  @moduledoc """
  Axis generator for creating reference marks and labels.

  Creates element groups containing tick marks, labels, and axis lines. Colours, font and
  size come from a `Visualize.Theme` (`theme/2`, default `Visualize.Theme.default/0`),
  resolved as CSS references for SVG and as literals for a canvas (spec/05 §1.4, D-55).

  ## Examples

      x_scale = Visualize.Scale.linear()
        |> Visualize.Scale.domain([0, 100])
        |> Visualize.Scale.range([0, 500])

      x_axis = Visualize.Axis.bottom(x_scale)
        |> Visualize.Axis.ticks(5)
        |> Visualize.Axis.tick_format(fn v -> "\#{v}%" end)

      element = Visualize.Axis.generate(x_axis)

  """

  alias Visualize.IR.{Element, Path, Transform}
  alias Visualize.{Scale, Theme}

  defstruct scale: nil,
            orient: :bottom,
            ticks: nil,
            tick_values: nil,
            tick_format: nil,
            tick_size_inner: 6,
            tick_size_outer: 6,
            tick_padding: 3,
            offset: 0,
            theme: nil

  @type orientation :: :top | :right | :bottom | :left
  @type t :: %__MODULE__{
          scale: struct(),
          orient: orientation(),
          ticks: integer() | nil,
          tick_values: [any()] | nil,
          tick_format: (any() -> String.t()) | nil,
          tick_size_inner: number(),
          tick_size_outer: number(),
          tick_padding: number(),
          offset: number(),
          theme: Theme.t() | nil
        }

  @doc "Creates a bottom-oriented axis"
  @spec bottom(struct()) :: t()
  def bottom(scale), do: %__MODULE__{scale: scale, orient: :bottom}

  @doc "Creates a top-oriented axis"
  @spec top(struct()) :: t()
  def top(scale), do: %__MODULE__{scale: scale, orient: :top}

  @doc "Creates a left-oriented axis"
  @spec left(struct()) :: t()
  def left(scale), do: %__MODULE__{scale: scale, orient: :left}

  @doc "Creates a right-oriented axis"
  @spec right(struct()) :: t()
  def right(scale), do: %__MODULE__{scale: scale, orient: :right}

  @doc "Sets the approximate number of ticks"
  @spec ticks(t(), integer()) :: t()
  def ticks(%__MODULE__{} = axis, count) when is_integer(count) do
    %{axis | ticks: count}
  end

  @doc "Sets explicit tick values"
  @spec tick_values(t(), [any()]) :: t()
  def tick_values(%__MODULE__{} = axis, values) when is_list(values) do
    %{axis | tick_values: values}
  end

  @doc "Sets the tick format function"
  @spec tick_format(t(), (any() -> String.t())) :: t()
  def tick_format(%__MODULE__{} = axis, formatter) when is_function(formatter, 1) do
    %{axis | tick_format: formatter}
  end

  @doc "Sets the inner tick size (length of tick lines)"
  @spec tick_size_inner(t(), number()) :: t()
  def tick_size_inner(%__MODULE__{} = axis, size) do
    %{axis | tick_size_inner: size}
  end

  @doc "Sets the outer tick size (length of domain line extensions)"
  @spec tick_size_outer(t(), number()) :: t()
  def tick_size_outer(%__MODULE__{} = axis, size) do
    %{axis | tick_size_outer: size}
  end

  @doc "Sets both inner and outer tick sizes"
  @spec tick_size(t(), number()) :: t()
  def tick_size(%__MODULE__{} = axis, size) do
    %{axis | tick_size_inner: size, tick_size_outer: size}
  end

  @doc "Sets the padding between tick and label"
  @spec tick_padding(t(), number()) :: t()
  def tick_padding(%__MODULE__{} = axis, padding) do
    %{axis | tick_padding: padding}
  end

  @doc "Sets the pixel offset for crisp edges"
  @spec offset(t(), number()) :: t()
  def offset(%__MODULE__{} = axis, offset) do
    %{axis | offset: offset}
  end

  @doc "Sets the theme the axis's colours, font and size resolve from"
  @spec theme(t(), Theme.t()) :: t()
  def theme(%__MODULE__{} = axis, %Theme{} = theme) do
    %{axis | theme: theme}
  end

  @doc """
  Generates the axis as an IR Element tree.

  Returns a group element containing the domain line and tick groups.

  ## Options

    * `:resolve` - how the theme's slots render: `:css` (default) for references a
      stylesheet can override, `:literal` for the plain values a canvas needs
  """
  @spec generate(t(), keyword()) :: Element.t()
  def generate(%__MODULE__{} = axis, opts \\ []) do
    mode = Keyword.get(opts, :resolve, :css)
    theme = axis.theme || Theme.default()
    slot = fn name -> Theme.resolve(theme, name, mode) end
    tick_vals = get_tick_values(axis)
    {k, _x_attr, y_attr, transform_attr} = orient_params(axis.orient)

    # An axis is decoration a screen reader skips; the chart's title names it (D-56).
    group =
      Element.group([],
        style: %{
          fill: :none,
          font_size: slot.(:font_size),
          font_family: slot.(:font_family),
          text_anchor: text_anchor_atom(axis.orient)
        },
        attrs: %{aria_hidden: "true"}
      )

    domain_line = create_domain_line(axis, k, slot.(:axis))
    group = Element.append(group, domain_line)

    tick_groups =
      Enum.map(tick_vals, fn value ->
        create_tick_group(axis, value, k, y_attr, transform_attr, slot.(:axis), slot.(:text))
      end)

    Element.append(group, tick_groups)
  end

  @doc """
  Renders the axis to a string using the specified backend.

  ## Options

    * `:backend` - The backend to use (`:svg`, `:canvas`, or a module). Defaults to `:svg`.
    * `:resolve` - the theme mode of `generate/2`; defaults to `Visualize.Theme.mode/1` of
      the backend, so an SVG axis carries CSS references and a canvas axis literals

  """
  @spec render(t(), keyword()) :: String.t()
  def render(%__MODULE__{} = axis, opts \\ []) do
    {mode, opts} = Keyword.pop_lazy(opts, :resolve, fn -> Theme.mode(opts[:backend]) end)

    axis
    |> generate(resolve: mode)
    |> Visualize.Render.to_string(opts)
  end

  # Get tick values from explicit values, scale, or default
  defp get_tick_values(%__MODULE__{tick_values: values}) when is_list(values), do: values

  defp get_tick_values(%__MODULE__{scale: scale, ticks: count}) do
    Scale.ticks(scale, count || 10)
  end

  # Get orientation-specific parameters
  # Returns {direction_multiplier, position_attr, tick_attr, transform_type}
  defp orient_params(:top), do: {-1, :x, :y2, :x}
  defp orient_params(:bottom), do: {1, :x, :y2, :x}
  defp orient_params(:left), do: {-1, :y, :x2, :y}
  defp orient_params(:right), do: {1, :y, :x2, :y}

  defp text_anchor_atom(:left), do: :end
  defp text_anchor_atom(:right), do: :start
  defp text_anchor_atom(_), do: :middle

  # Create the domain line as an IR.Element
  defp create_domain_line(
         %__MODULE__{scale: scale, orient: orient, tick_size_outer: outer},
         k,
         stroke
       ) do
    [r0, r1] = get_range(scale)

    path =
      case orient do
        o when o in [:top, :bottom] ->
          Path.new()
          |> Path.move_to(r0, k * outer)
          |> Path.vertical_to(0)
          |> Path.horizontal_to(r1)
          |> Path.vertical_to(k * outer)

        o when o in [:left, :right] ->
          Path.new()
          |> Path.move_to(k * outer, r0)
          |> Path.horizontal_to(0)
          |> Path.vertical_to(r1)
          |> Path.horizontal_to(k * outer)
      end

    Element.path(path, %{stroke: stroke})
  end

  # Create a tick group with line and label
  defp create_tick_group(axis, value, k, y_attr, transform_attr, stroke, fill) do
    pos = tick_position(axis, value)
    label = format_tick(axis, value)

    transform =
      case transform_attr do
        :x -> Transform.translate(pos, 0)
        :y -> Transform.translate(0, pos)
      end

    # Create tick line
    tick_line =
      case y_attr do
        :y2 -> Element.line(0, 0, 0, k * axis.tick_size_inner, %{stroke: stroke})
        :x2 -> Element.line(0, 0, k * axis.tick_size_inner, 0, %{stroke: stroke})
      end

    # Create tick text with position
    tick_text = create_tick_text(axis, label, k, fill)

    Element.group([tick_line, tick_text],
      style: %{class: "tick"},
      transform: transform
    )
  end

  defp create_tick_text(axis, label, k, fill) do
    case axis.orient do
      :top ->
        Element.text(label,
          y: k * (axis.tick_size_inner + axis.tick_padding),
          dy: "0em",
          style: %{fill: fill}
        )

      :bottom ->
        Element.text(label,
          y: k * axis.tick_size_inner + axis.tick_padding,
          dy: "0.71em",
          style: %{fill: fill}
        )

      :left ->
        Element.text(label,
          x: k * axis.tick_size_inner - axis.tick_padding,
          dy: "0.32em",
          style: %{fill: fill}
        )

      :right ->
        Element.text(label,
          x: k * axis.tick_size_inner + axis.tick_padding,
          dy: "0.32em",
          style: %{fill: fill}
        )
    end
  end

  @doc false
  # The position of a tick value along the axis: the scale's value plus the pixel offset
  # and the band centring of spec/05 §1.3. The frame's grid lines are drawn at these
  # positions, so the arithmetic lives here once.
  @spec tick_position(t(), any()) :: number()
  def tick_position(%__MODULE__{scale: scale, offset: offset} = axis, value) do
    Scale.apply(scale, value) + offset + band_centre(axis)
  end

  @doc false
  # The default tick label of spec/05 §1.5: a float rounded to six places with trailing
  # zeros and point removed, anything else `to_string/1`. The frame's legend labels its
  # entries the same way.
  @spec default_label(any()) :: String.t()
  def default_label(value) when is_float(value) do
    value
    |> Float.round(6)
    |> Float.to_string()
    |> String.trim_trailing("0")
    |> String.trim_trailing(".")
  end

  def default_label(value), do: to_string(value)

  # d3-axis's `center`: a tick on a band scale sits at the middle of its band. The centring
  # offset shrinks by the pixel offset on each side (so `offset` still lands the tick on a
  # pixel centre) and is rounded when the band scale rounds, as d3 does; on every other
  # scale the bandwidth is 0 and this adds nothing.
  defp band_centre(%__MODULE__{scale: scale, offset: offset}) do
    centre = max(0, Scale.bandwidth(scale) - 2 * offset) / 2
    if match?(%{round?: true}, scale), do: round(centre), else: centre
  end

  defp format_tick(%__MODULE__{tick_format: nil}, value), do: default_label(value)
  defp format_tick(%__MODULE__{tick_format: formatter}, value), do: formatter.(value)

  defp get_range(scale) do
    # Access the range from various scale types
    case scale do
      %{range: [r0, r1]} -> [r0, r1]
      _ -> [0, 1]
    end
  end
end
