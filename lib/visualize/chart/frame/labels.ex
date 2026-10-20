defmodule Visualize.Chart.Frame.Labels do
  @moduledoc false
  # The frame's labels (spec/14 §6.3): one text element per label at its anchor's
  # position, in its style, `dx` and `dy` added.

  alias Visualize.Chart.Frame
  alias Visualize.Chart.Frame.Position
  alias Visualize.Chart.Label.Polar
  alias Visualize.Chart.{Schema, Style, Var}
  alias Visualize.Chart.Style.{Defaults, Generated}
  alias Visualize.Chart.Text
  alias Visualize.Geo.Projection
  alias Visualize.IR.{Element, Transform}
  alias Visualize.Scale

  @inset 4

  @doc false
  # One text per label that has a place, each stamped with its path among `labels` when
  # `paths?` (spec/14 §4.7) — the index is the design's, so a label with no place skips
  # its number.
  @spec generate(map(), atom(), boolean()) :: [Element.t()]
  def generate(frame, mode, paths? \\ false) do
    frame.labels
    |> Enum.with_index()
    |> Enum.flat_map(fn {node, i} ->
      path = [:labels, Enum.at(frame.paths.labels, i, i)]
      frame |> label(node, mode) |> Enum.map(&Frame.stamp(&1, path, paths?))
    end)
  end

  @doc false
  # An axis's title from its measure (spec/14 §4.4, D-138): the text placed and styled as
  # a label anchored at that axis is, by the axis's own side, in plot coordinates.
  @spec axis_title(map(), atom(), String.t(), atom()) :: [Element.t()]
  def axis_title(frame, side, text, mode),
    do: label(frame, %{anchor: {:side, side}, text: Text.unparse([text])}, mode)

  # A label's style's path in the design, for a generator's faults (spec/14 §3.13).
  defp label_path(frame, node) do
    case Enum.find_index(frame.labels, &(&1 == node)) do
      nil -> [:style]
      i -> [:labels, Enum.at(frame.paths.labels, i, i), :style]
    end
  end

  defp label(frame, node, mode) do
    default_style = if node.anchor == :title, do: "title", else: Schema.default(:label, :style)
    base = Defaults.at(frame, Map.get(node, :defaults), :text)
    stack = Map.get(node, :style, default_style)
    pick = Generated.pick(frame, label_path(frame, node))
    style_node = Style.over(base, frame.styles, stack, pick)
    style = Style.resolve(style_node, frame.theme, mode)
    dx = Map.get(node, :dx, 0)
    dy = Map.get(node, :dy, 0)

    case place(frame, node.anchor) do
      nil ->
        []

      %{x: x, y: y} = placement ->
        attrs = %{x: x + dx, y: y + dy} |> put_unless_nil(:dy, Map.get(placement, :dy))
        center = {frame.plot.width / 2, frame.plot.height / 2}

        {rotation, text_anchor} =
          Polar.rotation(Map.get(node, :rotate), {x + dx, y + dy}, center, placement.anchor)

        base = %{class: "label", text_anchor: text_anchor}

        [
          Element.new(:text,
            attrs: attrs,
            style: Map.merge(base, style),
            content: text(node.text),
            transform: Map.get(placement, :transform)
          )
          |> Polar.rotate(rotation)
          |> Position.apply(
            style_node,
            outward(frame, node.anchor),
            {frame.plot.width, frame.plot.height}
          )
        ]
    end
  end

  defp put_unless_nil(map, _key, nil), do: map
  defp put_unless_nil(map, key, value), do: Map.put(map, key, value)

  defp text(text), do: text |> Text.parse!() |> Enum.map_join("", &part/1)

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
  defp place(frame, {:side, side}), do: axis_title(frame, side)

  defp place(_frame, {:frame, :top_left}),
    do: %{x: @inset, y: @inset, dy: "0.71em", anchor: :start}

  defp place(%{plot: p}, {:frame, :top_right}),
    do: %{x: p.width - @inset, y: @inset, dy: "0.71em", anchor: :end}

  defp place(%{plot: p}, {:frame, :bottom_left}),
    do: %{x: @inset, y: p.height - @inset, anchor: :start}

  defp place(%{plot: p}, {:frame, :bottom_right}),
    do: %{x: p.width - @inset, y: p.height - @inset, anchor: :end}

  # The plot's center (#489): in a `:polar` frame the origin the centered group is
  # translated to — `[0, 0]` inside it, where a centered mark is drawn — while the labels
  # are drawn in the plot's own coordinates, so it is the plot's middle in every kind,
  # whatever the `r` scale's range.
  defp place(%{plot: p}, {:frame, :center}),
    do: %{x: p.width / 2, y: p.height / 2, anchor: :middle}

  defp place(frame, {:data, [x, y]}) do
    case point(frame, x, y) do
      nil -> nil
      {px, py} -> %{x: px, y: py, anchor: :start}
    end
  end

  # The outward direction of an anchor (spec/14 §6.3): away from the plot for the titles
  # and the caption, into the plot for a corner, none for a data point or the center.
  defp outward(_frame, anchor) when anchor in [:title, :subtitle], do: {0, -1}
  defp outward(_frame, :caption), do: {0, 1}
  defp outward(_frame, {:frame, :top_left}), do: {1, 1}
  defp outward(_frame, {:frame, :top_right}), do: {-1, 1}
  defp outward(_frame, {:frame, :bottom_left}), do: {1, -1}
  defp outward(_frame, {:frame, :bottom_right}), do: {-1, -1}
  defp outward(_frame, {:frame, :center}), do: nil
  defp outward(_frame, {:data, _point}), do: nil

  defp outward(frame, {:axis, scale}), do: outward(frame, {:side, axis_side(frame, scale)})
  defp outward(_frame, {:side, :bottom}), do: {0, 1}
  # A side title is rotated; further from the plot is −y in its own frame.
  defp outward(_frame, {:side, _top_left_right}), do: {0, -1}

  defp axis_side(frame, scale) do
    case Enum.find(frame.axes, &(&1.scale == scale)) do
      %{side: side} -> side
      nil -> if scale == "y", do: :left, else: :bottom
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
    Map.get(frame.scales, Visualize.Chart.Names.name(name)) ||
      raise ArgumentError,
            "a {:data, [x, y]} anchor needs the frame to declare a scale named #{inspect(name)}"
  end
end
