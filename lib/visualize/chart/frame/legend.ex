defmodule Visualize.Chart.Frame.Legend do
  @moduledoc false
  # The legend of a frame (spec/14 §4.5): one entry per tick of the realised scale, a
  # swatch in the scale's colour beside the value's label, stacked or in a row at one of
  # the eight positions inside the plot area.

  alias Visualize.{Axis, Scale, Theme}
  alias Visualize.Chart.{Schema, Style, Var}
  alias Visualize.IR.{Element, Transform}

  @swatch 12
  @gap 16
  @row 16
  @inset 8
  @per_char 0.6

  @doc false
  # The legend group, or `[]` when the frame has no legend.
  @spec generate(map(), atom()) :: [Element.t()]
  def generate(%{legend: nil}, _mode), do: []

  def generate(frame, mode) do
    node = frame.legend
    scale = Map.fetch!(frame.scales, node.scale)
    style_node = Style.node(frame.styles, Map.get(node, :style, Schema.default(:legend, :style)))
    style = Style.resolve(style_node, frame.theme, mode)
    title = text(Map.get(node, :title, []))
    position = Map.get(node, :position, Schema.default(:legend, :position))
    entries = entries(scale, frame.theme, mode)
    font_size = font_size(style_node, frame.theme)
    right? = position in [:top_right, :bottom_right, :right]
    horizontal? = position in [:top, :bottom]

    rows =
      if horizontal?,
        do: row(entries, title, font_size, style),
        else: stack(entries, title, right?, style)

    {x, y} = origin(position, frame.plot, length(entries) + if(title, do: 1, else: 0), rows)
    group_style = Map.take(style, [:font_family, :font_size, :opacity])

    [
      Element.group(elem(rows, 0),
        style: Map.put(group_style, :class, "legend"),
        transform: Transform.translate(x, y)
      )
    ]
  end

  defp text([]), do: nil
  defp text(parts), do: Enum.map_join(parts, "", &part/1)

  defp part(string) when is_binary(string), do: string
  defp part(%Var{name: name}), do: Style.unresolved!(name)

  defp font_size(style_node, theme) do
    case Style.value(:font_size, Map.get(style_node, :font_size, :label_size), theme, :literal) do
      n when is_number(n) -> n
      _other -> theme.label_size
    end
  end

  # -- entries --------------------------------------------------------------------------

  defp entries(scale, theme, mode) do
    scale
    |> Scale.ticks(5)
    |> Enum.with_index(1)
    |> Enum.map(fn {value, i} ->
      {Axis.default_label(value), swatch(Scale.apply(scale, value), i, theme, mode)}
    end)
  end

  defp swatch(colour, i, theme, mode) do
    if colour?(colour, theme),
      do: Style.colour(colour, theme, mode),
      else: Theme.resolve(theme, {:series, i}, mode)
  end

  defp colour?(value, _theme) when is_binary(value), do: true
  defp colour?({:series, i}, _theme), do: is_integer(i) and i >= 1
  defp colour?(value, theme) when is_atom(value), do: value in Theme.slots(theme)
  defp colour?(_value, _theme), do: false

  # -- layouts --------------------------------------------------------------------------

  # Entries stacked downward; the right-hand layout puts the swatch at the origin's left
  # and the label before it, so no text width is needed. Returns `{elements, width}`.
  defp stack(entries, title, right?, style) do
    fill = Map.take(style, [:fill])
    offset = if title, do: @row, else: 0

    title_element =
      if title,
        do: [title(title, if(right?, do: :end, else: :start), fill)],
        else: []

    items =
      Enum.with_index(entries, fn {label, colour}, i ->
        Element.group(
          [
            Element.rect(if(right?, do: -@swatch, else: 0), 0, @swatch, @swatch, %{fill: colour}),
            Element.text(label,
              x: if(right?, do: -@gap, else: @gap),
              y: @swatch / 2,
              dy: "0.32em",
              style: Map.put(fill, :text_anchor, if(right?, do: :end, else: :start))
            )
          ],
          style: %{class: "legend-item"},
          transform: Transform.translate(0, offset + i * @row)
        )
      end)

    {title_element ++ items, 0}
  end

  # Entries in one row, each as wide as its swatch, gap and estimated label; the title,
  # when given, is the first cell. Returns `{elements, total width}`.
  defp row(entries, title, font_size, style) do
    fill = Map.take(style, [:fill])
    title_width = if title, do: @per_char * font_size * String.length(title) + @inset, else: 0

    {items, width} =
      Enum.reduce(entries, {[], title_width}, fn {label, colour}, {acc, x} ->
        item =
          Element.group(
            [
              Element.rect(0, 0, @swatch, @swatch, %{fill: colour}),
              Element.text(label,
                x: @gap,
                y: @swatch / 2,
                dy: "0.32em",
                style: Map.put(fill, :text_anchor, :start)
              )
            ],
            style: %{class: "legend-item"},
            transform: Transform.translate(x, 0)
          )

        {[item | acc], x + @gap + @per_char * font_size * String.length(label) + @inset}
      end)

    title_element = if title, do: [title(title, :start, fill)], else: []
    {title_element ++ Enum.reverse(items), max(width - @inset, 0)}
  end

  defp title(title, anchor, fill) do
    Element.text(title,
      x: 0,
      y: @swatch / 2,
      dy: "0.32em",
      style: Map.merge(fill, %{font_weight: :bold, text_anchor: anchor})
    )
  end

  # -- position -------------------------------------------------------------------------

  defp origin(:top_left, _plot, _rows, _layout), do: {@inset, @inset}
  defp origin(:top_right, plot, _rows, _layout), do: {plot.width - @inset, @inset}
  defp origin(:bottom_left, plot, rows, _layout), do: {@inset, plot.height - @inset - rows * @row}

  defp origin(:bottom_right, plot, rows, _layout),
    do: {plot.width - @inset, plot.height - @inset - rows * @row}

  defp origin(:left, plot, rows, _layout), do: {@inset, plot.height / 2 - rows * @row / 2}

  defp origin(:right, plot, rows, _layout),
    do: {plot.width - @inset, plot.height / 2 - rows * @row / 2}

  defp origin(:top, plot, _rows, {_, width}), do: {plot.width / 2 - width / 2, @inset}

  defp origin(:bottom, plot, _rows, {_, width}),
    do: {plot.width / 2 - width / 2, plot.height - @inset - @swatch}
end
