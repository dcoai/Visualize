defmodule Visualize.Chart.Frame.Legend do
  @moduledoc false
  # The legend of a frame (spec/14 §4.5): one entry per tick of the realised scale, a
  # swatch in the scale's colour beside the value's label, stacked or in a row at one of
  # the eight positions inside the plot area — or, with `inside: false`, in the margin the
  # position names (#136).

  alias Visualize.{Axis, Scale, Theme}
  alias Visualize.Chart.Frame
  alias Visualize.Chart.{Schema, Style, Text, Var}
  alias Visualize.IR.{Element, Transform}

  @swatch 12
  @gap 16
  @row 16
  @inset 8
  @per_char 0.6
  @right [:top_right, :bottom_right, :right]
  @left [:top_left, :bottom_left, :left]

  @doc false
  # The legend group, or `[]` when the frame has no legend; stamped `frame.legend` when
  # `paths?` (spec/14 §4.7).
  @spec generate(map(), atom(), boolean()) :: [Element.t()]
  def generate(frame, mode, paths? \\ false)

  def generate(%{legend: nil}, _mode, _paths?), do: []

  def generate(frame, mode, paths?) do
    node = frame.legend
    scale = Map.fetch!(frame.scales, node.scale)
    style_node = Style.node(frame.styles, Map.get(node, :style, Schema.default(:legend, :style)))
    style = Style.resolve(style_node, frame.theme, mode)
    title = text(Map.get(node, :title, []))
    position = Map.get(node, :position, Schema.default(:legend, :position))
    inside? = Map.get(node, :inside, Schema.default(:legend, :inside))
    entries = entries(scale, node, frame.theme, mode)
    font_size = font_size(style_node, frame.theme)
    # Outside there is room, so every position reads swatch-then-label (spec/14 §4.5).
    right? = inside? and position in @right
    horizontal? = position in [:top, :bottom]

    rows =
      if horizontal?,
        do: row(entries, title, font_size, style),
        else: stack(entries, title, right?, style)

    count = length(entries) + if(title, do: 1, else: 0)

    {x, y} =
      if inside?,
        do: origin(position, frame.plot, count, rows),
        else: outside(position, frame.plot, count, rows, width(entries, title, font_size))

    group_style = Map.take(style, [:font_family, :font_size, :opacity])

    [
      Element.group(elem(rows, 0),
        style: Map.put(group_style, :class, "legend"),
        transform: Transform.translate(x, y)
      )
      |> Frame.stamp([:frames, frame.name, :legend], paths?)
    ]
  end

  defp text(text) do
    case Text.parse!(text) do
      [] -> nil
      parts -> Enum.map_join(parts, "", &part/1)
    end
  end

  defp part(string) when is_binary(string), do: string
  defp part(%Var{name: name}), do: Style.unresolved!(name)

  defp font_size(style_node, theme) do
    case Style.value(:font_size, Map.get(style_node, :font_size, :label_size), theme, :literal) do
      n when is_number(n) -> n
      _other -> theme.label_size
    end
  end

  # -- entries --------------------------------------------------------------------------

  # One entry per tick: the value, its label with the legend's prefix and unit around it
  # (spec/14 §4.5, #135), and its swatch.
  defp entries(scale, node, theme, mode) do
    prefix = Map.get(node, :prefix) || ""
    unit = Map.get(node, :unit) || ""

    scale
    |> Scale.ticks(5)
    |> Enum.with_index(1)
    |> Enum.map(fn {value, i} ->
      label = prefix <> Axis.default_label(value) <> unit
      {value, label, swatch(Scale.apply(scale, value), i, theme, mode)}
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
      Enum.with_index(entries, fn {value, label, colour}, i ->
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
          attrs: series(value),
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
      Enum.reduce(entries, {[], title_width}, fn {value, label, colour}, {acc, x} ->
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
            attrs: series(value),
            transform: Transform.translate(x, 0)
          )

        {[item | acc], x + @gap + @per_char * font_size * String.length(label) + @inset}
      end)

    title_element = if title, do: [title(title, :start, fill)], else: []
    {title_element ++ Enum.reverse(items), max(width - @inset, 0)}
  end

  # An entry names what it explains, the string a series path carries (spec/14 §4.5, D-77).
  defp series(value), do: %{"data-series" => to_string(value)}

  defp title(title, anchor, fill) do
    Element.text(title,
      x: 0,
      y: @swatch / 2,
      dy: "0.32em",
      style: Map.merge(fill, %{font_weight: :bold, text_anchor: anchor})
    )
  end

  @doc false
  # The fault of a legend that does not fit the margin `inside: false` puts it in (spec/14
  # §4.5): `ArgumentError` naming the margin and the size the legend needs — its estimated
  # width for a side margin, the swatch and the inset for a top or bottom one. `:ok` for a
  # legend inside the plot, or one that fits.
  @spec check!(map() | nil, map(), map(), map(), Theme.t()) :: :ok
  def check!(nil, _scales, _margin, _styles, _theme), do: :ok

  def check!(node, scales, margin, styles, theme) do
    if Map.get(node, :inside, Schema.default(:legend, :inside)) do
      :ok
    else
      position = Map.get(node, :position, Schema.default(:legend, :position))
      style_node = Style.node(styles, Map.get(node, :style, Schema.default(:legend, :style)))
      title = text(Map.get(node, :title, []))
      entries = entries(Map.fetch!(scales, node.scale), node, theme, :literal)
      width = width(entries, title, font_size(style_node, theme))

      {side, needs} =
        cond do
          position in @right -> {:right, @inset + width}
          position in @left -> {:left, @inset + width}
          position == :top -> {:top, @inset + @swatch}
          true -> {:bottom, @inset + @swatch}
        end

      room = Map.fetch!(margin, side)

      if room < needs do
        raise ArgumentError,
              "the legend at #{inspect(position)} outside the plot needs #{needs} in the " <>
                "#{side} margin, which is #{room} (spec/14 §4.5)"
      end

      :ok
    end
  end

  # The estimated width of a stacked legend: the swatch, the gap and the longest label
  # (the title counted as one) at 0.6 × the font size per character.
  defp width(entries, title, font_size) do
    labels = Enum.map(entries, &elem(&1, 1)) ++ List.wrap(title)
    longest = labels |> Enum.map(&String.length/1) |> Enum.max(fn -> 0 end)
    @gap + @per_char * font_size * longest
  end

  # -- position -------------------------------------------------------------------------

  # In the margin the position names, 8 out from the plot's edge (spec/14 §4.5, #136).
  defp outside(:top_left, _plot, _rows, _layout, width), do: {-@inset - width, @inset}
  defp outside(:top_right, plot, _rows, _layout, _width), do: {plot.width + @inset, @inset}

  defp outside(:bottom_left, plot, rows, _layout, width),
    do: {-@inset - width, plot.height - rows * @row}

  defp outside(:bottom_right, plot, rows, _layout, _width),
    do: {plot.width + @inset, plot.height - rows * @row}

  defp outside(:left, plot, rows, _layout, width),
    do: {-@inset - width, plot.height / 2 - rows * @row / 2}

  defp outside(:right, plot, rows, _layout, _width),
    do: {plot.width + @inset, plot.height / 2 - rows * @row / 2}

  defp outside(:top, plot, _rows, {_, width}, _w),
    do: {plot.width / 2 - width / 2, -@inset - @swatch}

  defp outside(:bottom, plot, _rows, {_, width}, _w),
    do: {plot.width / 2 - width / 2, plot.height + @inset}

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
