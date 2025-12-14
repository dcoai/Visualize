defmodule Visualize.Axis do
  @moduledoc """
  Axis generator for creating reference marks and labels.

  Creates SVG groups containing tick marks, labels, and axis lines.

  ## Examples

      x_scale = Visualize.Scale.linear()
        |> Visualize.Scale.domain([0, 100])
        |> Visualize.Scale.range([0, 500])

      x_axis = Visualize.Axis.bottom(x_scale)
        |> Visualize.Axis.ticks(5)
        |> Visualize.Axis.tick_format(fn v -> "\#{v}%" end)

      svg_element = Visualize.Axis.generate(x_axis)

  """

  alias Visualize.SVG.Element
  alias Visualize.Scale

  defstruct scale: nil,
            orient: :bottom,
            ticks: nil,
            tick_values: nil,
            tick_format: nil,
            tick_size_inner: 6,
            tick_size_outer: 6,
            tick_padding: 3,
            offset: 0

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
          offset: number()
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

  @doc "Generates the axis as an SVG Element"
  @spec generate(t()) :: Element.t()
  def generate(%__MODULE__{} = axis) do
    tick_vals = get_tick_values(axis)
    {k, x_attr, y_attr, transform_attr} = orient_params(axis.orient)

    # Create axis group
    group = Element.g(%{
      fill: "none",
      font_size: 10,
      font_family: "sans-serif",
      text_anchor: text_anchor(axis.orient)
    })

    # Add domain line
    domain_line = create_domain_line(axis, k)
    group = Element.append(group, domain_line)

    # Add tick groups
    tick_groups = Enum.map(tick_vals, fn value ->
      create_tick_group(axis, value, k, x_attr, y_attr, transform_attr)
    end)

    Element.append(group, tick_groups)
  end

  @doc "Renders the axis directly to an SVG string"
  @spec render(t()) :: String.t()
  def render(%__MODULE__{} = axis) do
    axis
    |> generate()
    |> Visualize.SVG.Renderer.render_to_string()
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

  defp text_anchor(:left), do: "end"
  defp text_anchor(:right), do: "start"
  defp text_anchor(_), do: "middle"

  # Create the domain line
  defp create_domain_line(%__MODULE__{scale: scale, orient: orient, tick_size_outer: outer}, k) do
    [r0, r1] = get_range(scale)

    case orient do
      o when o in [:top, :bottom] ->
        Element.path(%{
          stroke: "currentColor",
          d: "M#{r0},#{k * outer}V0H#{r1}V#{k * outer}"
        })

      o when o in [:left, :right] ->
        Element.path(%{
          stroke: "currentColor",
          d: "M#{k * outer},#{r0}H0V#{r1}H#{k * outer}"
        })
    end
  end

  # Create a tick group with line and label
  defp create_tick_group(axis, value, k, _x_attr, y_attr, transform_attr) do
    pos = Scale.apply(axis.scale, value) + axis.offset
    label = format_tick(axis, value)

    transform =
      case transform_attr do
        :x -> "translate(#{pos},0)"
        :y -> "translate(0,#{pos})"
      end

    tick_line_attrs =
      %{stroke: "currentColor"}
      |> Map.put(y_attr, k * axis.tick_size_inner)

    text_attrs =
      case axis.orient do
        :top ->
          %{fill: "currentColor", y: -k * axis.tick_size_inner - axis.tick_padding, dy: "0em"}

        :bottom ->
          %{fill: "currentColor", y: k * axis.tick_size_inner + axis.tick_padding, dy: "0.71em"}

        :left ->
          %{fill: "currentColor", x: -k * axis.tick_size_inner - axis.tick_padding, dy: "0.32em"}

        :right ->
          %{fill: "currentColor", x: k * axis.tick_size_inner + axis.tick_padding, dy: "0.32em"}
      end

    tick_group = Element.g(%{class: "tick", transform: transform})

    tick_line = Element.line(tick_line_attrs)
    tick_text = Element.text(text_attrs) |> Element.content(label)

    tick_group
    |> Element.append(tick_line)
    |> Element.append(tick_text)
  end

  defp format_tick(%__MODULE__{tick_format: nil}, value) when is_float(value) do
    value
    |> Float.round(6)
    |> Float.to_string()
    |> String.trim_trailing("0")
    |> String.trim_trailing(".")
  end

  defp format_tick(%__MODULE__{tick_format: nil}, value) do
    to_string(value)
  end

  defp format_tick(%__MODULE__{tick_format: formatter}, value) do
    formatter.(value)
  end

  defp get_range(scale) do
    # Access the range from various scale types
    case scale do
      %{range: [r0, r1]} -> [r0, r1]
      _ -> [0, 1]
    end
  end
end
