defmodule Visualize.Chart.Frame.Legend do
  @moduledoc false
  # The legend of a frame (spec/14 §4.5): one entry per tick of the realized scale, a
  # swatch in the scale's color beside the value's label, stacked or in rows at one of
  # the eight positions inside the plot area — or, with `inside: false`, in the margin the
  # position names (#136). A top or bottom legend wraps to the plot's width, and in its
  # margin grows that margin to hold its rows (#630, D-169). Below its `min_entries`, or
  # with no room for it, it is omitted: not drawn and no margin taken, and `status/1`
  # says why (D-223, D-231).

  import Visualize.Chart.Names, only: [is_name: 1]

  alias Visualize.{Axis, Event, Scale, Theme}
  alias Visualize.Chart.{Coverage, Frame, Names, Schema, Style, Text, Var}
  alias Visualize.Chart.Frame.Scales
  alias Visualize.Chart.Style.{Defaults, Generated}
  alias Visualize.Data.Schema, as: FeedSchema
  alias Visualize.IR.{Element, Transform}

  @swatch 12
  @gap 16
  @row 16
  @inset 8
  @right [:top_right, :bottom_right, :right]
  @horizontal [:top, :bottom]

  @doc false
  # The legend group, or `[]` when the frame has no legend or its legend is omitted
  # (D-223, D-231); stamped `frames.<name>.legend` when `paths?` (spec/14 §4.7).
  @spec generate(map(), atom(), boolean()) :: [Element.t()]
  def generate(frame, mode, paths? \\ false)

  def generate(%{legend: nil}, _mode, _paths?), do: []

  def generate(frame, mode, paths?) do
    case layout(frame, mode) do
      {:omitted, _reason, _count} ->
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
  # nor for an omitted one (D-223, D-231).
  @spec extent(map()) :: %{width: number(), height: number()}
  def extent(%{legend: nil}), do: %{width: 0, height: 0}

  def extent(frame) do
    case layout(frame, :literal) do
      {:omitted, _reason, _count} -> %{width: 0, height: 0}
      layout -> layout.extent
    end
  end

  @doc false
  # Whether the frame's legend is drawn, and with how many entries; or why it is omitted
  # (spec/14 §4.5, D-231). `nil` with no legend.
  @spec status(map()) :: Frame.legend_fit()
  def status(%{legend: nil}), do: nil

  def status(frame) do
    case layout(frame, :literal) do
      {:omitted, reason, count} -> %{status: :omitted, reason: reason, entries: count}
      layout -> %{status: :drawn, entries: layout.entries}
    end
  end

  @doc false
  # The margin a frame takes for its legend (spec/14 §4.5, D-169): its own, with a top or
  # bottom margin `inside: false` grown to the legend's rows when it is smaller. An omitted
  # legend takes none (D-223, D-231), so nothing that depends on the entries raises here;
  # an invalid `min_entries` or `max_label` does, being the design's.
  @spec fit(map()) :: map()
  def fit(%{legend: nil, margin: margin}), do: margin

  def fit(%{margin: margin} = frame) do
    case layout(frame, :literal) do
      %{inside?: false, position: side} = layout when side in @horizontal ->
        Map.update!(margin, side, &max(&1, height_needed(layout)))

      _drawn_or_omitted ->
        margin
    end
  end

  # -- layout ---------------------------------------------------------------------------

  # The frame's styles, and the defaults its containers lay under the legend's style: the
  # part defaults alone, a legend being furniture (spec/14 §3.8).
  # A generator in the legend's style is resolved with no datum (spec/14 §3.13).
  defp styles(frame) do
    pick = Generated.pick(frame, [:frames, Map.get(frame, :name), :legend, :style])
    {frame.styles, Defaults.at(frame, nil, nil), pick}
  end

  # The legend laid out against the plot's width: its elements, where it sits, its extent
  # and its entry count — or `{:omitted, reason, count}`, when it is neither drawn nor given
  # margin (D-223, D-231): below its `min_entries`, else with a cell or a row wider than
  # the plot, else with no room in its margin. The one place every question about the
  # legend's shape is answered, so the frame's margin, the drawing, the extent and the
  # status cannot disagree.
  defp layout(%{legend: node, theme: theme} = frame, mode) do
    {styles, _base, _pick} = styled = styles(frame)
    entries = entries(node, frame.scales, namer(frame), {styles, theme, mode})
    count = length(entries)

    with :ok <- at_least(count, min_entries(node)),
         %{} = layout <- lay_out(node, entries, frame.plot.width, styled, theme, mode),
         layout = Map.put(layout, :entries, count),
         :ok <- room(layout, frame) do
      layout
    else
      {:omitted, reason} -> {:omitted, reason, count}
    end
  end

  defp at_least(count, min) when count < min, do: {:omitted, :min_entries}
  defp at_least(_count, _min), do: :ok

  # Whether the legend has room where it sits (spec/14 §4.5, D-231). Inside the plot it
  # always has, its rows having been fitted to the plot's width. A top or bottom margin
  # may grow to the rows, but must leave the plot some height (D-222): the room is the
  # plot's height and that margin, which the growth moves between them, so a frame
  # realized over the grown margin answers as the one before it did. A margin the author
  # gave that already holds the rows is not judged. A side margin is the author's, and
  # must hold the legend's estimated width.
  defp room(%{inside?: true}, _frame), do: :ok

  defp room(%{position: side} = layout, %{margin: margin, plot: plot}) when side in @horizontal do
    needs = height_needed(layout)
    given = Map.fetch!(margin, side)

    if given < needs and needs >= plot.height + given,
      do: {:omitted, :height},
      else: :ok
  end

  defp room(layout, %{margin: margin}) do
    side = if layout.position in @right, do: :right, else: :left

    if Map.fetch!(margin, side) < @inset + layout.extent.width,
      do: {:omitted, :width},
      else: :ok
  end

  # A top or bottom legend's need of its margin: its rows and the 8 (D-169).
  defp height_needed(layout), do: layout.extent.height + @inset

  # The layout, or `{:omitted, reason}` when its cells cannot be placed in rows no wider
  # than the plot (`:cell`, `:row`).
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

      with {:ok, {elements, rows, widest}} <-
             rows(entries, title, font_size, style, plot_width, wrap?) do
        Map.merge(base, %{
          elements: elements,
          rows: rows,
          width: widest,
          extent: %{width: widest, height: (rows - 1) * @row + @swatch}
        })
      end
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
  # its swatch. A value with a declared name is labeled by it (D-225).
  defp entries(%{values: values} = node, _scales, named, {styles, theme, mode})
       when is_list(values) do
    values(values, node, named, styles, theme, mode)
  end

  defp entries(node, scales, named, {_styles, theme, mode}),
    do: entries(Map.fetch!(scales, node.scale), node, named, theme, mode)

  # The declared name of a value the legend shows, or `nil` (spec/14 §4.5, D-225): looked up
  # through the frame's schemas in the fields its marks show the legend's values by — each
  # read through the legend's scale, and for a legend of `values` each mapped by — in the
  # schema of the slot the mark reads, the first in design order that names the value.
  defp namer(%{schemas: schemas, marks: marks} = frame) when map_size(schemas) > 0 do
    node = frame.legend
    styles = {frame.styles, frame.defaults}

    maps =
      for mark <- marks,
          %FeedSchema{} = schema <- [Event.schema_of(schemas, mark)],
          field <- shown(mark, node, frame.kind, styles),
          names = FeedSchema.value_names(schema, field),
          map_size(names) > 0,
          do: names

    # A value is a declared one by its spelling (spec/14 §9.4).
    fn value ->
      Enum.find_value(maps, fn names ->
        case Names.fetch(names, value) do
          {:ok, name} -> name
          :error -> nil
        end
      end)
    end
  end

  defp namer(_frame), do: fn _value -> nil end

  defp shown(mark, node, kind, styles) do
    scale = Map.get(node, :scale)

    read =
      for {name, read} <- Scales.reads(mark, kind, styles),
          scale != nil and Names.same?(name, scale),
          field = field(read),
          field != nil,
          do: field

    mapped =
      if is_list(Map.get(node, :values)),
        do: for({_kind, field} <- Coverage.fields(mark), do: field),
        else: []

    read ++ mapped
  end

  defp field({:field, field}) when is_name(field), do: field
  defp field(field) when is_name(field), do: field
  defp field(_read), do: nil

  # A legend of declared values (spec/14 §4.5, D-194): one entry per value, in order,
  # swatched by the fill of the style the value names, else its stroke, else the series'.
  defp values(values, node, named, styles, theme, mode) do
    prefix = Map.get(node, :prefix) || ""
    unit = Map.get(node, :unit) || ""
    max_label = Map.get(node, :max_label, Schema.default(:legend, :max_label))
    names = Map.keys(styles) ++ Theme.style_names(theme)

    values
    |> Enum.with_index(1)
    |> Enum.map(fn {value, i} ->
      {label, full} = cut(prefix <> (named.(value) || to_string(value)) <> unit, max_label)
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

  defp entries(scale, node, named, theme, mode) do
    prefix = Map.get(node, :prefix) || ""
    unit = Map.get(node, :unit) || ""
    max_label = Map.get(node, :max_label, Schema.default(:legend, :max_label))

    scale
    |> Scale.ticks(5)
    |> Enum.with_index(1)
    |> Enum.map(fn {value, i} ->
      label = named.(value) || Axis.default_label(value)
      {label, full} = cut(prefix <> label <> unit, max_label)
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
  # widest. Returns `{:ok, {elements, rows, widest row's width}}`, or `{:omitted, reason}`
  # when the cells cannot be placed (D-231).
  defp rows(entries, title, font_size, style, plot_width, wrap?) do
    title_cell = if title, do: [{:title, title, Text.width(title, font_size)}], else: []
    entry_cells = Enum.map(entries, &{:entry, &1, Text.width(elem(&1, 1), font_size)})
    cells = title_cell ++ entry_cells

    placed = if wrap?, do: wrap(cells, plot_width), else: unwrapped(cells, plot_width)

    with {:ok, rows} <- placed do
      {:ok, laid_out(rows, Map.take(style, [:fill]))}
    end
  end

  defp laid_out(rows, fill) do
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

  # Greedy rows: a cell joins the row unless it would end past the plot. A cell wider than
  # the plot on its own cannot be placed at all, and the legend is omitted (spec/14 §4.5,
  # D-169, D-231).
  defp wrap(cells, plot_width) do
    if Enum.any?(cells, &(cell_width(&1) > plot_width)),
      do: {:omitted, :cell},
      else: {:ok, greedy(cells, plot_width)}
  end

  defp greedy(cells, plot_width) do
    cells
    |> Enum.reduce([], fn cell, rows ->
      width = cell_width(cell)

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

  # `wrap: false`: one row, which must fit the plot, else the legend is omitted (spec/14
  # §4.5, D-169, D-231).
  defp unwrapped(cells, plot_width) do
    {_placed, width} = lay(cells)
    if width > plot_width, do: {:omitted, :row}, else: {:ok, [cells]}
  end

  # A cell's own width, without the 8 after it: the title's text, an entry's swatch, gap
  # and label.
  defp cell_width({:title, _title, width}), do: width
  defp cell_width({:entry, _entry, label_width}), do: @gap + label_width

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
