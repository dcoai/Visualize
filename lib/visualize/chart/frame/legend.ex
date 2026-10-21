defmodule Visualize.Chart.Frame.Legend do
  @moduledoc false
  # The legend of a frame (spec/14 §4.5): one entry per tick of the realized scale, a
  # swatch in the scale's color beside the value's label, stacked or in rows at one of
  # the eight positions inside the plot area — or, with `inside: false`, in the margin the
  # position names (#136). A top or bottom legend wraps to the plot's width, and in its
  # margin grows that margin to hold its rows (#630, D-169). Below its `min_entries` it is
  # not drawn and takes no margin (D-223).

  alias Visualize.{Axis, Scale, Theme}
  alias Visualize.Chart.Frame
  alias Visualize.Chart.{Schema, Style, Text, Var}
  alias Visualize.Chart.Style.{Defaults, Generated}
  alias Visualize.IR.{Element, Transform}

  @swatch 12
  @gap 16
  @row 16
  @inset 8
  @right [:top_right, :bottom_right, :right]
  @horizontal [:top, :bottom]

  @doc false
  # The legend group, or `[]` when the frame has no legend or its legend is below its
  # `min_entries` (D-223); stamped `frames.<name>.legend` when `paths?` (spec/14 §4.7).
  @spec generate(map(), atom(), boolean()) :: [Element.t()]
  def generate(frame, mode, paths? \\ false)

  def generate(%{legend: nil}, _mode, _paths?), do: []

  def generate(frame, mode, paths?) do
    case layout(frame, mode) do
      :below ->
        []

      layout ->
        {x, y} = place(layout, frame.plot)

        [
          Element.group(layout.elements,
            style: Map.put(layout.group_style, :class, "legend"),
            transform: Transform.translate(x, y)
          )
          |> Frame.stamp([:frames, frame.name, :legend], paths?)
        ]
    end
  end

  @doc false
  # The box the legend is laid out in, `%{width:, height:}` (spec/14 §4.5, D-169): the
  # widest row and its rows for a top or bottom legend, the estimated width and its rows
  # for a stacked one; the 8 between it and the plot is not counted. No box with no legend,
  # nor below the legend's `min_entries` (D-223).
  @spec extent(map()) :: %{width: number(), height: number()}
  def extent(%{legend: nil}), do: %{width: 0, height: 0}

  def extent(frame) do
    case layout(frame, :literal) do
      :below -> %{width: 0, height: 0}
      layout -> layout.extent
    end
  end

  @doc false
  # The margin a frame takes for its legend (spec/14 §4.5, D-169): the given one, with a top
  # or bottom margin `inside: false` grown to the legend's rows when it is smaller. Raises
  # `ArgumentError` for what cannot be fitted — a side margin narrower than the legend's
  # estimated width, a top or bottom margin grown past the box (D-222), a row too wide for
  # the plot with `wrap: false`, a single cell wider than the plot — naming the side and
  # the size needed. A legend below its `min_entries` takes no margin and raises nothing
  # (D-223).
  @spec fit!(map(), map()) :: map()
  def fit!(%{legend: nil}, margin), do: margin

  def fit!(%{legend: node, scales: scales, plot: plot, theme: theme} = frame, margin) do
    layout = layout(node, scales, plot.width, styles(frame), theme, :literal)

    cond do
      layout == :below ->
        margin

      layout.inside? ->
        margin

      layout.position in @horizontal ->
        needs = layout.extent.height + @inset
        given = Map.fetch!(margin, layout.position)

        if given < needs,
          do: grow!(margin, layout.position, needs, plot.height + given),
          else: margin

      true ->
        side = if layout.position in @right, do: :right, else: :left
        needs = @inset + layout.extent.width
        room = Map.fetch!(margin, side)

        if room < needs do
          raise ArgumentError,
                "the legend at #{inspect(layout.position)} outside the plot needs #{needs} in the " <>
                  "#{side} margin, which is #{room} (spec/14 §4.5)"
        end

        margin
    end
  end

  # A top or bottom margin grown to the legend's need, which must leave the plot some height
  # (spec/14 §4.5, D-222): `room` is the plot's height and the margin given on that side,
  # what the need is taken from. A margin the author gave is not judged here.
  defp grow!(margin, side, needs, room) do
    if needs >= room do
      box = room + Map.fetch!(margin, opposite(side))

      raise ArgumentError,
            "the legend at #{inspect(side)} outside the plot needs #{needs} in the #{side} " <>
              "margin, which leaves the plot no height in a box #{box} high (spec/14 §4.5)"
    end

    Map.put(margin, side, needs)
  end

  defp opposite(:top), do: :bottom
  defp opposite(:bottom), do: :top

  # -- layout ---------------------------------------------------------------------------

  # The frame's styles, and the defaults its containers lay under the legend's style: the
  # part defaults alone, a legend being furniture (spec/14 §3.8).
  # A generator in the legend's style is resolved with no datum (spec/14 §3.13).
  defp styles(frame) do
    pick = Generated.pick(frame, [:frames, Map.get(frame, :name), :legend, :style])
    {frame.styles, Defaults.at(frame, nil, nil), pick}
  end

  # The legend laid out against the plot's width: its elements, where it sits and its
  # extent — or `:below`, when it has fewer entries than its `min_entries` and is neither
  # drawn nor given margin (D-223). The one place every question about the legend's shape
  # is answered, so the frame's margin and the drawing cannot disagree.
  defp layout(frame, mode),
    do: layout(frame.legend, frame.scales, frame.plot.width, styles(frame), frame.theme, mode)

  defp layout(node, scales, plot_width, {styles, _base, _pick} = styled, theme, mode) do
    entries = entries(node, scales, styles, theme, mode)

    if length(entries) < min_entries(node),
      do: :below,
      else: lay_out(node, entries, plot_width, styled, theme, mode)
  end

  defp lay_out(node, entries, plot_width, {styles, base, pick}, theme, mode) do
    stack = Map.get(node, :style, Schema.default(:legend, :style))
    style_node = Style.over(base, styles, stack, pick)
    style = Style.resolve(style_node, theme, mode)
    title = text(Map.get(node, :title, []))
    position = Map.get(node, :position, Schema.default(:legend, :position))
    inside? = Map.get(node, :inside, Schema.default(:legend, :inside))
    font_size = font_size(style_node, theme)

    base = %{
      position: position,
      inside?: inside?,
      group_style: Map.take(style, [:font_family, :font_size, :opacity])
    }

    if position in @horizontal do
      wrap? = Map.get(node, :wrap, Schema.default(:legend, :wrap))

      {elements, rows, widest} =
        rows(entries, title, font_size, style, plot_width, wrap?, position)

      Map.merge(base, %{
        elements: elements,
        rows: rows,
        width: widest,
        extent: %{width: widest, height: (rows - 1) * @row + @swatch}
      })
    else
      # Outside there is room, so every position reads swatch-then-label (spec/14 §4.5).
      right? = inside? and position in @right
      count = length(entries) + if(title, do: 1, else: 0)
      width = width(entries, title, font_size)

      Map.merge(base, %{
        elements: stack(entries, title, right?, style),
        rows: count,
        width: width,
        extent: %{width: width, height: if(count == 0, do: 0, else: (count - 1) * @row + @swatch)}
      })
    end
  end

  # The fewest entries the legend is drawn with, a count at least 1 (spec/14 §4.5, D-223).
  defp min_entries(node) do
    case Map.get(node, :min_entries, Schema.default(:legend, :min_entries)) do
      n when is_integer(n) and n >= 1 ->
        n

      other ->
        raise ArgumentError,
              "a legend's min_entries is a count of entries of at least 1, not " <>
                "#{inspect(other)} (spec/14 §4.5)"
    end
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
  # (spec/14 §4.5, #135) cut to `max_label` (D-169), the full label when it was cut, and
  # its swatch.
  defp entries(%{values: values} = node, _scales, styles, theme, mode) when is_list(values) do
    values(values, node, styles, theme, mode)
  end

  defp entries(node, scales, _styles, theme, mode),
    do: entries(Map.fetch!(scales, node.scale), node, theme, mode)

  # A legend of declared values (spec/14 §4.5, D-194): one entry per value, in order,
  # swatched by the fill of the style the value names, else its stroke, else the series'.
  defp values(values, node, styles, theme, mode) do
    prefix = Map.get(node, :prefix) || ""
    unit = Map.get(node, :unit) || ""
    max_label = Map.get(node, :max_label, Schema.default(:legend, :max_label))
    names = Map.keys(styles) ++ Theme.style_names(theme)

    values
    |> Enum.with_index(1)
    |> Enum.map(fn {value, i} ->
      {label, full} = cut(prefix <> to_string(value) <> unit, max_label)
      {value, label, full, named_swatch(named(names, value), styles, i, theme, mode)}
    end)
  end

  # A value names a style by its spelling, whichever each is (D-195).
  defp named(names, value) when (is_atom(value) and value != nil) or is_binary(value),
    do: Enum.find(names, &Visualize.Chart.Names.same?(&1, value))

  defp named(_names, _value), do: nil

  defp named_swatch(nil, _styles, i, theme, mode), do: Theme.resolve(theme, {:series, i}, mode)

  defp named_swatch(name, styles, i, theme, mode) do
    resolved = %{} |> Style.over(styles, name) |> Style.resolve(theme, mode)

    # A swatch is one color: a fill that is a paint (a hatch, a gradient) gives way to the
    # stroke's color, and that to the series'.
    case {Map.get(resolved, :fill), Map.get(resolved, :stroke)} do
      {fill, _stroke} when is_binary(fill) -> fill
      {_fill, stroke} when is_binary(stroke) -> stroke
      _neither -> Theme.resolve(theme, {:series, i}, mode)
    end
  end

  defp entries(scale, node, theme, mode) do
    prefix = Map.get(node, :prefix) || ""
    unit = Map.get(node, :unit) || ""
    max_label = Map.get(node, :max_label, Schema.default(:legend, :max_label))

    scale
    |> Scale.ticks(5)
    |> Enum.with_index(1)
    |> Enum.map(fn {value, i} ->
      {label, full} = cut(prefix <> Axis.default_label(value) <> unit, max_label)
      {value, label, full, swatch(Scale.apply(scale, value), i, theme, mode)}
    end)
  end

  # A label longer than `max_label` characters is its first `max_label − 1` and "…"; the
  # full text is kept for the entry's title and `aria-label` (spec/14 §4.5, D-169).
  defp cut(label, nil), do: {label, nil}

  defp cut(label, max) when is_integer(max) and max >= 1 do
    if String.length(label) > max,
      do: {String.slice(label, 0, max - 1) <> "…", label},
      else: {label, nil}
  end

  defp cut(_label, max) do
    raise ArgumentError,
          "a legend's max_label is a count of characters of at least 1, not #{inspect(max)} " <>
            "(spec/14 §4.5)"
  end

  defp swatch(color, i, theme, mode) do
    if color?(color, theme),
      do: Style.color(color, theme, mode),
      else: Theme.resolve(theme, {:series, i}, mode)
  end

  defp color?(value, _theme) when is_binary(value), do: true
  defp color?({:series, i}, _theme), do: is_integer(i) and i >= 1
  defp color?({:ramp, name, t}, _theme), do: name in Theme.ramp_names() and is_number(t)
  defp color?({:color, name}, theme), do: Theme.color_name?(theme, name)
  defp color?(value, _theme) when is_tuple(value), do: Visualize.Color.value?(value)
  defp color?(value, theme) when is_atom(value), do: value in Theme.slots(theme)
  defp color?(_value, _theme), do: false

  # An entry's group: the swatch and the label, with the full label as its first child and
  # its `aria-label` when `max_label` cut it (D-169).
  defp item({value, label, full, color}, swatch_x, label_x, anchor, fill, at) do
    named = if full, do: [Element.title(full)], else: []
    attrs = if full, do: Map.put(series(value), "aria-label", full), else: series(value)

    Element.group(
      named ++
        [
          Element.rect(swatch_x, 0, @swatch, @swatch, %{fill: color}),
          Element.text(label,
            x: label_x,
            y: @swatch / 2,
            dy: "0.32em",
            style: Map.put(fill, :text_anchor, anchor)
          )
        ],
      style: %{class: "legend-item"},
      attrs: attrs,
      transform: at
    )
  end

  # -- layouts --------------------------------------------------------------------------

  # Entries stacked downward; the right-hand layout puts the swatch at the origin's left
  # and the label before it, so no text width is needed.
  defp stack(entries, title, right?, style) do
    fill = Map.take(style, [:fill])
    offset = if title, do: @row, else: 0

    title_element =
      if title,
        do: [title(title, 0, if(right?, do: :end, else: :start), fill)],
        else: []

    items =
      Enum.with_index(entries, fn entry, i ->
        if right?,
          do: item(entry, -@swatch, -@gap, :end, fill, Transform.translate(0, offset + i * @row)),
          else: item(entry, 0, @gap, :start, fill, Transform.translate(0, offset + i * @row))
      end)

    title_element ++ items
  end

  # The title, when given, and the entries as cells in rows no wider than the plot (D-169):
  # each cell as wide as its estimated text (an entry's swatch and gap before it), 8 between
  # cells, a cell that would end past the plot starting the next row 16 below. One row is
  # placed exactly as the single row was before wrapping; several are each centered on the
  # widest. Returns `{elements, rows, widest row's width}`.
  defp rows(entries, title, font_size, style, plot_width, wrap?, position) do
    fill = Map.take(style, [:fill])
    title_cell = if title, do: [{:title, title, Text.width(title, font_size)}], else: []
    entry_cells = Enum.map(entries, &{:entry, &1, Text.width(elem(&1, 1), font_size)})
    cells = title_cell ++ entry_cells

    rows =
      if wrap?,
        do: wrap(cells, plot_width, position),
        else: unwrapped(cells, plot_width, position)

    laid = Enum.map(rows, &lay/1)
    widest = laid |> Enum.map(&elem(&1, 1)) |> Enum.max(fn -> 0 end)
    several? = length(laid) > 1

    elements =
      laid
      |> Enum.with_index()
      |> Enum.flat_map(fn {{cells, width}, i} ->
        shift = if several?, do: (widest - width) / 2, else: 0

        Enum.map(cells, fn
          {:title, title, x} ->
            title(title, if(several?, do: x + shift, else: x), :start, fill)

          {:entry, entry, x} ->
            at = if several?, do: {x + shift, i * @row}, else: {x, 0}
            item(entry, 0, @gap, :start, fill, Transform.translate(elem(at, 0), elem(at, 1)))
        end)
      end)

    {elements, max(length(laid), 1), widest}
  end

  # Each cell's x in its row, accumulated as the single row always was (the title's width
  # and 8, an entry's 16, label and 8), and the row's width: the last cell's end.
  defp lay(cells) do
    {placed, x} =
      Enum.map_reduce(cells, 0, fn
        {:title, title, width}, x -> {{:title, title, x}, x + (width + @inset)}
        {:entry, entry, label_width}, x -> {{:entry, entry, x}, x + @gap + label_width + @inset}
      end)

    {placed, max(x - @inset, 0)}
  end

  # Greedy rows: a cell joins the row unless it would end past the plot; a cell wider than
  # the plot on its own cannot be placed at all (spec/14 §4.5, D-169).
  defp wrap(cells, plot_width, position) do
    cells
    |> Enum.reduce([], fn cell, rows ->
      width = cell_width(cell)

      if width > plot_width do
        raise ArgumentError,
              "a #{cell_name(cell)} of the legend at #{inspect(position)} needs " <>
                "#{round_to(width)} across the #{position} on its own, and the plot is " <>
                "#{round_to(plot_width)} wide; #{remedy(cell)} (spec/14 §4.5)"
      end

      case rows do
        [{row, end_x} | rest] when end_x + @inset + width <= plot_width ->
          [{[cell | row], end_x + @inset + width} | rest]

        _other ->
          [{[cell], width} | rows]
      end
    end)
    |> Enum.reverse()
    |> Enum.map(fn {row, _end_x} -> Enum.reverse(row) end)
  end

  # `wrap: false`: one row, which must fit the plot (spec/14 §4.5, D-169).
  defp unwrapped(cells, plot_width, position) do
    {_placed, width} = lay(cells)

    if width > plot_width do
      raise ArgumentError,
            "the legend at #{inspect(position)} with wrap: false needs #{round_to(width)} " <>
              "across the #{position}, and the plot is #{round_to(plot_width)} wide " <>
              "(spec/14 §4.5)"
    end

    [cells]
  end

  # A cell's own width, without the 8 after it: the title's text, an entry's swatch, gap
  # and label.
  defp cell_width({:title, _title, width}), do: width
  defp cell_width({:entry, _entry, label_width}), do: @gap + label_width

  defp cell_name({:title, _title, _width}), do: "title"
  defp cell_name({:entry, _entry, _width}), do: "single entry"

  defp remedy({:title, _title, _width}), do: "a shorter title fits"
  defp remedy({:entry, _entry, _width}), do: "a max_label cuts its labels"

  defp round_to(n) when is_integer(n), do: n
  defp round_to(n), do: Float.round(n * 1.0, 1)

  # An entry names what it explains, the string a series path carries (spec/14 §4.5, D-77).
  defp series(value), do: %{"data-series" => to_string(value)}

  defp title(title, x, anchor, fill) do
    Element.text(title,
      x: x,
      y: @swatch / 2,
      dy: "0.32em",
      style: Map.merge(fill, %{font_weight: :bold, text_anchor: anchor})
    )
  end

  # The estimated width of a stacked legend: the swatch, the gap and the longest label
  # (the title counted as one) at its estimated width, `Text.width/2`.
  defp width(entries, title, font_size) do
    labels = Enum.map(entries, &elem(&1, 1)) ++ List.wrap(title)
    @gap + (labels |> Enum.map(&Text.width(&1, font_size)) |> Enum.max(fn -> 0.0 end))
  end

  # -- position -------------------------------------------------------------------------

  defp place(%{inside?: true} = layout, plot), do: origin(layout.position, plot, layout)
  defp place(layout, plot), do: outside(layout.position, plot, layout)

  # In the margin the position names, 8 out from the plot's edge (spec/14 §4.5, #136); a
  # top legend's last row and a bottom legend's first sit there (D-169).
  defp outside(:top_left, _plot, %{width: width}), do: {-@inset - width, @inset}
  defp outside(:top_right, plot, _layout), do: {plot.width + @inset, @inset}

  defp outside(:bottom_left, plot, %{rows: rows, width: width}),
    do: {-@inset - width, plot.height - rows * @row}

  defp outside(:bottom_right, plot, %{rows: rows}),
    do: {plot.width + @inset, plot.height - rows * @row}

  defp outside(:left, plot, %{rows: rows, width: width}),
    do: {-@inset - width, plot.height / 2 - rows * @row / 2}

  defp outside(:right, plot, %{rows: rows}),
    do: {plot.width + @inset, plot.height / 2 - rows * @row / 2}

  defp outside(:top, plot, %{rows: rows, width: width}),
    do: {plot.width / 2 - width / 2, -@inset - @swatch - (rows - 1) * @row}

  defp outside(:bottom, plot, %{width: width}),
    do: {plot.width / 2 - width / 2, plot.height + @inset}

  defp origin(:top_left, _plot, _layout), do: {@inset, @inset}
  defp origin(:top_right, plot, _layout), do: {plot.width - @inset, @inset}

  defp origin(:bottom_left, plot, %{rows: rows}),
    do: {@inset, plot.height - @inset - rows * @row}

  defp origin(:bottom_right, plot, %{rows: rows}),
    do: {plot.width - @inset, plot.height - @inset - rows * @row}

  defp origin(:left, plot, %{rows: rows}), do: {@inset, plot.height / 2 - rows * @row / 2}

  defp origin(:right, plot, %{rows: rows}),
    do: {plot.width - @inset, plot.height / 2 - rows * @row / 2}

  defp origin(:top, plot, %{width: width}), do: {plot.width / 2 - width / 2, @inset}

  defp origin(:bottom, plot, %{rows: rows, width: width}),
    do: {plot.width / 2 - width / 2, plot.height - @inset - @swatch - (rows - 1) * @row}
end
