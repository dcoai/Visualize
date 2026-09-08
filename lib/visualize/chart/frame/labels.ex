defmodule Visualize.Chart.Frame.Labels do
  @moduledoc false
  # The frame's labels (spec/14 §6.3): one text element per label at its anchor's
  # position, in its style, `dx` and `dy` added.

  alias Visualize.Chart.{Schema, Style, Var}
  alias Visualize.Geo.Projection
  alias Visualize.IR.{Element, Transform}
  alias Visualize.Scale

  @inset 4

  @doc false
  @spec generate(map(), atom()) :: [Element.t()]
  def generate(frame, mode), do: Enum.flat_map(frame.labels, &label(frame, &1, mode))

  defp label(frame, node, mode) do
    default_style = if node.anchor == :title, do: :title, else: Schema.default(:label, :style)
    style_node = Style.node(frame.styles, Map.get(node, :style, default_style))
    style = Style.resolve(style_node, frame.theme, mode)
    dx = Map.get(node, :dx, 0)
    dy = Map.get(node, :dy, 0)

    case place(frame, node.anchor) do
      nil ->
        []

      %{x: x, y: y} = placement ->
        attrs = %{x: x + dx, y: y + dy} |> put_unless_nil(:dy, Map.get(placement, :dy))
        base = %{class: "label", text_anchor: placement.anchor}

        [
          Element.new(:text,
            attrs: attrs,
            style: Map.merge(base, style),
            content: text(node.text),
            transform: Map.get(placement, :transform)
          )
        ]
    end
  end

  defp put_unless_nil(map, _key, nil), do: map
  defp put_unless_nil(map, key, value), do: Map.put(map, key, value)

  defp text(parts), do: Enum.map_join(parts, "", &part/1)

  defp part(string) when is_binary(string), do: string
  defp part(%Var{name: name}), do: Style.unresolved!(name)

  defp part({:field, field}) do
    raise ArgumentError, "a frame label has no datum to read #{inspect(field)} from"
  end

  # -- placement (spec/14 §6.3) ---------------------------------------------------------

  defp place(%{plot: p, margin: m}, :title),
    do: %{x: p.width / 2, y: -m.top / 2, dy: "0.32em", anchor: :middle}

  defp place(%{plot: p}, :subtitle), do: %{x: p.width / 2, y: -@inset, anchor: :middle}

  defp place(%{plot: p, margin: m}, :caption),
    do: %{x: 0, y: p.height + m.bottom - @inset, anchor: :start}

  defp place(frame, {:axis, scale}), do: axis_title(frame, axis_side(frame, scale))

  defp place(_frame, {:frame, :top_left}),
    do: %{x: @inset, y: @inset, dy: "0.71em", anchor: :start}

  defp place(%{plot: p}, {:frame, :top_right}),
    do: %{x: p.width - @inset, y: @inset, dy: "0.71em", anchor: :end}

  defp place(%{plot: p}, {:frame, :bottom_left}),
    do: %{x: @inset, y: p.height - @inset, anchor: :start}

  defp place(%{plot: p}, {:frame, :bottom_right}),
    do: %{x: p.width - @inset, y: p.height - @inset, anchor: :end}

  defp place(frame, {:data, [x, y]}) do
    case point(frame, x, y) do
      nil -> nil
      {px, py} -> %{x: px, y: py, anchor: :start}
    end
  end

  defp axis_side(frame, scale) do
    case Enum.find(frame.axes, &(&1.scale == scale)) do
      %{side: side} -> side
      nil -> if scale == :y, do: :left, else: :bottom
    end
  end

  defp axis_title(%{plot: p, margin: m}, :bottom),
    do: %{x: p.width / 2, y: p.height + m.bottom - 5, anchor: :middle}

  defp axis_title(%{plot: p, margin: m}, :top),
    do: %{x: p.width / 2, y: -m.top + 5, dy: "0.71em", anchor: :middle}

  defp axis_title(%{plot: p, margin: m}, :left) do
    %{x: -p.height / 2, y: -m.left + 15, anchor: :middle, transform: Transform.rotate(-90)}
  end

  defp axis_title(%{plot: p, margin: m}, :right) do
    %{
      x: p.height / 2,
      y: -(p.width + m.right - 15),
      anchor: :middle,
      transform: Transform.rotate(90)
    }
  end

  # A data anchor through the frame's position scales, by kind.
  defp point(%{kind: :polar} = frame, angle, radius) do
    a = Scale.apply(scale!(frame, :angle), angle)
    r = Scale.apply(scale!(frame, :r), radius)

    {crisp(frame.plot.width / 2 + r * :math.sin(a)),
     crisp(frame.plot.height / 2 - r * :math.cos(a))}
  end

  defp point(%{kind: :geo, projection: projection}, lon, lat) do
    Projection.project(projection, lon, lat)
  end

  defp point(frame, x, y) do
    {Scale.apply(scale!(frame, :x), x), Scale.apply(scale!(frame, :y), y)}
  end

  # Six decimals, negative zero folded (D-6), as the polar furniture prints.
  defp crisp(x) do
    case Float.round(x * 1.0, 6) do
      r when r == 0 -> 0.0
      r -> r
    end
  end

  defp scale!(frame, name) do
    Map.get(frame.scales, name) ||
      raise ArgumentError,
            "a {:data, [x, y]} anchor needs the frame to declare a scale named #{inspect(name)}"
  end
end
