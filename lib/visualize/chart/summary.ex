defmodule Visualize.Chart.Summary do
  @moduledoc """
  A chart's text alternative (spec/14 §21, D-142): what a screen reader says for a chart,
  generated from the design and the data it was applied to.

  `new/1` reads an applied chart into a summary: its **name** — the design's `meta.name`,
  else its kind — and, frame by frame, the chart's **kind** (a line chart, a gauge, a
  treemap), the **series** its marks draw and how many rows, each **axis** with the range
  or the categories its scale holds, and the **extremes** of the values the marks draw.
  `text/1` is that summary as sentences, which `Visualize.Chart.generate/2` writes into
  the root's `<desc>` (§21.2). A value is written as its axis writes it — the axis's
  `format`, its `measure`'s display unit, its `prefix` and `unit` (§4.4) — to four
  significant digits rather than at the ticks' step, so an extreme is not rounded to a
  tick.

  `table/2` is the other half of the text alternative (§21.3): the rows each mark draws
  as an HTML `<table>`, visually hidden, for a host to place beside the chart. A
  `role="img"` root hides its children from assistive technology, so the table cannot
  live inside the `<svg>`.

  `attrs/2` and `description/2` name an element that stands for the chart — a `<canvas>`,
  or the wrapper of a hybrid chart's layers (§21.4).

  ## Examples

      iex> design = %{
      ...>   version: 2,
      ...>   meta: %{name: "Load"},
      ...>   sources: %{primary: %{fields: [:t, :v]}},
      ...>   frames: %{main: %{
      ...>     kind: :cartesian,
      ...>     scales: %{x: %{kind: :linear}, y: %{kind: :linear}},
      ...>     axes: [%{scale: :x, side: :bottom}, %{scale: :y, side: :left}]
      ...>   }},
      ...>   marks: [%{type: :line, data: :primary, channels: %{x: :t, y: :v}}]
      ...> }
      iex> {:ok, applied} = Visualize.Chart.apply(design, sources: %{primary: %{t: [1, 2, 3], v: [4, 9, 2]}})
      iex> summary = Visualize.Chart.Summary.new(applied)
      iex> summary.name
      "Load"
      iex> Visualize.Chart.Summary.text(summary)
      "Line chart, 1 series (v) of 3 points. Bottom axis t, from 1 to 3. Left axis v, from 2 to 9. Highest v 9 at t 2; lowest v 2 at t 3."

  """

  alias Visualize.Chart.{Applied, Frame, Mark, Text, Var}
  alias Visualize.Chart.Frame.{Furniture, Scales}
  alias Visualize.Chart.Mark.Channels
  alias Visualize.Data.Table
  alias Visualize.{Format, Quantity, Scale, Unit}
  alias Visualize.IR.Path

  defstruct [:name, frames: []]

  @typedoc "An axis as the summary says it: its scale's range, or its categories."
  @type axis :: %{
          scale: atom(),
          side: atom(),
          title: String.t(),
          range: {String.t(), String.t()} | nil,
          categories: [String.t()] | nil
        }

  @typedoc """
  The highest and the lowest value one mark draws, each with where it is; `rows` is how
  many values there were, and a mark of one says its value alone.
  """
  @type extreme :: %{
          field: String.t(),
          rows: non_neg_integer(),
          high: {String.t(), String.t() | nil},
          low: {String.t(), String.t() | nil}
        }

  @typedoc "One frame of the summary."
  @type frame :: %{
          name: atom() | nil,
          kind: String.t(),
          series: [String.t()],
          rows: non_neg_integer(),
          unit: String.t(),
          axes: [axis()],
          extremes: [extreme()]
        }

  @type t :: %__MODULE__{name: String.t(), frames: [frame()]}

  # The marks that annotate data rather than draw it: a rule, a band, a text and a
  # basemap say nothing a summary counts.
  @auxiliary [:rule, :band, :x_band, :text, :tiles]

  # A layout's name for the chart it draws (spec/14 §5.4.2): the first a frame's marks run
  # names the chart, whatever mark draws it. A partition is a sunburst under an arc.
  @layouts %{
    tree: "tree diagram",
    cluster: "dendrogram",
    pack: "circle packing",
    partition: "icicle",
    treemap: "treemap",
    chord: "chord diagram",
    sankey: "Sankey diagram",
    force: "network graph",
    contour: "contour plot",
    density: "density contour plot",
    hexbin: "hexbin chart",
    voronoi: "Voronoi diagram",
    delaunay: "triangulation",
    spectrum: "spectrum",
    bin: "histogram"
  }

  # The hierarchy layouts, whose `field` is the value each node is sized by.
  @hierarchies [:tree, :cluster, :pack, :partition, :treemap]

  # The channels whose fields title an axis, in the order one is preferred within a mark.
  @titling [:x, :y, :angle, :r, :x0, :y0, :x1, :y1, :value, :median]

  # The categories, series and values a sentence lists before it says how many more.
  @listed 10

  # The points of one series a keyboard reaches (§21.5): a series of more is sampled.
  @reachable 1000

  @doc """
  The summary of an applied chart: its name and, per frame in drawing order (`z`, ties
  by name, §4.2), its kind, series, axes and extremes.
  """
  @spec new(Applied.t()) :: t()
  def new(%Applied{chart: chart, sources: sources} = applied) do
    frames =
      applied
      |> realised()
      |> Enum.sort_by(&{&1.z, to_string(&1.name)})
      |> Enum.map(&frame(&1, sources))

    %__MODULE__{name: name(chart.meta, frames), frames: frames}
  end

  @doc """
  The summary as sentences: per frame, the kind with its series, one sentence per axis,
  then the extremes; a design of several frames says each frame's name first.
  """
  @spec text(t() | Applied.t()) :: String.t()
  def text(%Applied{} = applied), do: applied |> new() |> text()

  def text(%__MODULE__{frames: frames}) do
    many? = length(frames) > 1
    Enum.map_join(frames, " ", &frame_text(&1, many?))
  end

  @doc """
  The data-table fallback (§21.3): the rows each data mark draws, one HTML `<table>` per
  mark — a mark repeating another's table is left out — in a `<div>` that is visually
  hidden and still read. Each table has a `<caption>` — the chart's name, and the
  source's name when there are several — `<th scope="col">` headers named by field, and
  every value written as the summary writes it. All text is escaped.

  ## Options

    * `:hidden` - visually hide the tables (default `true`)
    * `:id` - the `<div>`'s id (default none)
    * `:class` - the `<div>`'s class (default `"vis-data-table"`)
    * `:caption` - the caption (default the summary's name)
    * `:limit` - the rows a table holds; a table cut short says how many it left out
      (default `1000`)
  """
  @spec table(Applied.t(), keyword()) :: String.t()
  def table(%Applied{} = applied, opts \\ []),
    do: Visualize.Chart.Summary.Table.html(applied, opts)

  @doc """
  The attributes that make an element stand for the chart (§21.4) — a `<canvas>`, or the
  wrapper of a hybrid chart's layers: `role="img"`, the name as `aria-label`, and
  `aria-describedby` the id of `description/2`'s element, which the page renders with
  the same `id`. A keyword list, to spread into a HEEx tag.
  """
  @spec attrs(t(), String.t()) :: keyword()
  def attrs(%__MODULE__{name: name}, id) when is_binary(id),
    do: [role: "img", "aria-label": name, "aria-describedby": id <> "-summary"]

  @doc """
  The element `attrs/2` points `aria-describedby` at: the summary's text in a `<p>` with
  the id `<id>-summary` and the `hidden` attribute, read as a description and never
  shown. Inside a `<canvas>` it is also the canvas's fallback content.
  """
  @spec description(t(), String.t()) :: String.t()
  def description(%__MODULE__{} = summary, id) when is_binary(id) do
    escape = &Visualize.Chart.Summary.Table.escape/1
    ~s(<p id="#{escape.(id)}-summary" hidden>#{escape.(text(summary))}</p>)
  end

  @doc false
  # The points a keyboard reaches (§21.5): per series in the summary's order, every row of
  # the data marks that draw a value, in data order, with its readout and its position in
  # the chart's pixels (`nil` in a polar or geographic frame, or where the row is not
  # placed). Series of one name across marks are one series. A series of more than
  # `@reachable` points is sampled to that many, evenly, its first and last kept, and each
  # readout counts the series' own rows. `Visualize.Hooks.Keyboard` writes them; each point
  # also carries the `row` behind it and the `mark` that drew it, which a board's cell
  # reads to answer a pick (spec/15 §13.2).
  @spec points(Applied.t()) :: [%{name: String.t(), points: [map()]}]
  def points(%Applied{sources: sources} = applied) do
    all =
      applied
      |> realised()
      |> Enum.sort_by(&{&1.z, to_string(&1.name)})
      |> Enum.flat_map(&frame_points(&1, sources))

    grouped = Enum.group_by(all, &elem(&1, 0), &elem(&1, 1))

    all
    |> Enum.map(&elem(&1, 0))
    |> Enum.uniq()
    |> Enum.map(fn name ->
      rows = Map.fetch!(grouped, name)
      n = length(rows)

      points =
        for {{ctx, value, row, reading, position}, i} <- sampled(rows, n) do
          said = "#{value.label} #{formatter(ctx.frame, value.scale).(reading)}"
          where = Enum.join(Enum.reject([place(ctx, value.where, row), said], &is_nil/1), ", ")
          {x, y} = position || {nil, nil}
          %{text: "#{name}, #{i} of #{n}: #{where}", x: x, y: y, row: row, mark: ctx.mark}
        end

      %{name: name, points: points}
    end)
  end

  # The rows with their one-based positions, at most `@reachable` of them evenly spaced,
  # the first and the last always among them.
  defp sampled(rows, n) when n <= @reachable, do: Enum.with_index(rows, 1)

  defp sampled(rows, n) do
    keep = MapSet.new(0..(@reachable - 1), &round(&1 * (n - 1) / (@reachable - 1)))
    for {row, i} <- Enum.with_index(rows), MapSet.member?(keep, i), do: {row, i + 1}
  end

  defp frame_points(frame, sources) do
    for mark <- frame.marks,
        Map.get(mark, :type) not in @auxiliary,
        ctx = %{frame: frame, mark: mark},
        value = value(ctx),
        value != nil,
        rows = Mark.rows(frame, mark, sources),
        {row, position} <- Enum.zip(rows, positions(frame, mark, rows)),
        reading = value.read.(row),
        is_number(reading) do
      name =
        case Channels.reading(ctx, :series, row) || stacked_key(mark, row) do
          nil -> value.label
          series -> plain(series)
        end

      {name, {ctx, value, row, reading, position}}
    end
  end

  # Where each row is drawn, in the chart's pixels (§21.5): the middle of its `x` — of `x0`
  # and `x1` for a rectangle — and its `y`, or `y1`, moved by the frame's margin and box; no
  # position in a frame whose marks bend or project.
  defp positions(%Frame{kind: kind}, _mark, rows) when kind != :cartesian,
    do: Enum.map(rows, fn _row -> nil end)

  defp positions(frame, mark, rows) do
    [bx, by, _w, _h] = frame.box
    left = bx * frame.size.width + frame.margin.left
    top = by * frame.size.height + frame.margin.top

    %{frame: frame, mark: mark, rows: rows}
    |> Channels.pixels()
    |> Enum.map(fn pixel ->
      with x when is_number(x) <- centre(pixel, :x, :x0, :x1),
           y when is_number(y) <- centre(pixel, :y, :y1, :y1) do
        {left + x, top + y}
      else
        _unplaced -> nil
      end
    end)
  end

  defp centre(pixel, one, a, b) do
    case {Map.get(pixel, one), Map.get(pixel, a), Map.get(pixel, b)} do
      {v, _, _} when is_number(v) -> v
      {_, v0, v1} when is_number(v0) and is_number(v1) -> (v0 + v1) / 2
      _none -> nil
    end
  end

  # -- the frame --------------------------------------------------------------------------

  defp realised(%Applied{frames: frames, frame: frame}) when frames == %{} or is_nil(frames),
    do: [frame]

  defp realised(%Applied{frames: frames}), do: Map.values(frames)

  defp frame(%Frame{} = frame, sources) do
    marks = for mark <- frame.marks, Map.get(mark, :type) not in @auxiliary, do: mark

    drawn =
      for mark <- marks do
        ctx = %{frame: frame, mark: mark}
        rows = Mark.rows(frame, mark, sources)
        value = value(ctx)
        %{ctx: ctx, rows: rows, value: value, readings: readings(value, rows)}
      end

    # The marks that draw a value: at least one number to say.
    valued = Enum.filter(drawn, &(&1.readings != []))
    counted = List.first(valued) || Enum.max_by(drawn, &length(&1.rows), fn -> nil end)

    %{
      name: frame.name,
      kind: kind(frame, marks),
      series: series(drawn),
      rows: if(counted, do: length(counted.rows), else: 0),
      unit: unit(frame, counted && counted.ctx.mark),
      axes: Enum.flat_map(frame.axes, &axis(frame, &1, valued)),
      extremes: extremes(valued)
    }
  end

  defp readings(nil, _rows), do: []

  defp readings(value, rows),
    do: for(row <- rows, v = value.read.(row), is_number(v), do: {v, row})

  # The design's name, else the first frame's kind: every chart is named (§21.2).
  defp name(meta, frames) do
    case text_of(Map.get(meta || %{}, :name)) do
      nil -> frames |> List.first(%{kind: "chart"}) |> Map.fetch!(:kind) |> capitalise()
      name -> name
    end
  end

  # -- kind -------------------------------------------------------------------------------

  # The chart's kind (§21.1): a geographic frame is a map, a needle makes a gauge, a
  # layout names what it lays out, and otherwise the first data mark's type says it.
  defp kind(%Frame{kind: :geo}, _marks), do: "map"
  defp kind(_frame, []), do: "chart"

  defp kind(frame, [first | _] = marks) do
    cond do
      Enum.any?(marks, &(&1.type == :needle)) -> "gauge"
      layout = Enum.find_value(marks, &layout/1) -> layout_kind(layout, marks)
      true -> mark_kind(frame, first)
    end
  end

  defp layout(mark),
    do: Enum.find_value(steps(mark), &if(Map.has_key?(@layouts, &1.op), do: &1.op))

  defp layout_kind(:partition, marks) do
    if Enum.any?(marks, &(&1.type == :arc)),
      do: "sunburst",
      else: Map.fetch!(@layouts, :partition)
  end

  defp layout_kind(op, _marks), do: Map.fetch!(@layouts, op)

  defp steps(%{data: %{transforms: steps}}) when is_list(steps), do: steps
  defp steps(_mark), do: []

  defp stack(mark), do: Enum.find(steps(mark), &(&1.op == :stack))

  defp mark_kind(%Frame{kind: :polar}, %{type: type}) when type in [:line, :area],
    do: "radar chart"

  defp mark_kind(%Frame{kind: :polar}, %{type: :rect}), do: "radial bar chart"
  defp mark_kind(_frame, %{type: :line}), do: "line chart"

  defp mark_kind(_frame, %{type: :area} = mark) do
    case stack(mark) do
      nil -> "area chart"
      %{offset: offset} when offset in [:wiggle, :silhouette] -> "streamgraph"
      _stack -> "stacked area chart"
    end
  end

  defp mark_kind(frame, %{type: :rect} = mark) do
    cond do
      not bar?(frame, mark) -> if channel?(mark, :value), do: "heatmap", else: "rectangle chart"
      Map.get(mark, :offset, %{}) != %{} -> "grouped bar chart"
      stack(mark) != nil -> "stacked bar chart"
      true -> "bar chart"
    end
  end

  defp mark_kind(_frame, %{type: type} = mark) when type in [:symbol, :circle] do
    if channel?(mark, :value), do: "bubble chart", else: "scatter plot"
  end

  defp mark_kind(_frame, %{type: :arc} = mark) do
    inner = mark |> Map.get(:options, %{}) |> Map.get(:inner_radius, 0)
    if inner > 0 or channel?(mark, :inner), do: "donut chart", else: "pie chart"
  end

  defp mark_kind(_frame, %{type: :rose}), do: "rose chart"
  defp mark_kind(_frame, %{type: :percentile_band}), do: "percentile band chart"
  defp mark_kind(_frame, _mark), do: "chart"

  # The edge channel of a rectangle that reads a band scale — its category — or `nil`.
  defp band(frame, mark) do
    Enum.find([:x0, :y0], fn channel ->
      match?(%Scale.Band{}, Channels.scale(%{frame: frame, mark: mark}, channel))
    end)
  end

  # A rectangle is a bar when one edge reads a band and the other family starts at a
  # baseline — a constant, a scale's end — or is stacked: a heatmap's cells read a field
  # at both ends of both families.
  defp bar?(frame, mark) do
    case band(frame, mark) do
      nil -> false
      edge -> stack(mark) != nil or field(Map.get(mark.channels, opposite(edge))) == nil
    end
  end

  defp opposite(:x0), do: :y0
  defp opposite(:y0), do: :x0

  defp channel?(mark, channel), do: Map.has_key?(Map.get(mark, :channels, %{}), channel)

  # -- the value a mark draws -------------------------------------------------------------

  # What a mark's extremes are of (§21.1): `label` names it, `read` reads it from a row,
  # `scale` writes it, and `where` is the channel that says where a row is, or `:name`.
  # A stacked mark's value is the row's own, not its stacked top; a hierarchy's is the
  # field its layout sizes by; any other's is its value channel, when that reads a field
  # through a scale the frame declares — a position a layout computed in pixels is not a
  # value — or is the share of an arc or a rose.
  defp value(%{frame: frame, mark: mark} = ctx) do
    cond do
      stack(mark) != nil ->
        {_channel, where} = channel_pair(frame, mark) || {nil, nil}
        %{label: "value", read: &Table.get(&1, :value), scale: scale_of(ctx, :y1), where: where}

      (layout = Enum.find(steps(mark), &(&1.op in @hierarchies))) && Map.get(layout, :field) ->
        %{
          label: humanise(layout.field),
          read: &Table.get(&1, layout.field),
          scale: nil,
          where: :name
        }

      pair = channel_pair(frame, mark) ->
        reading(ctx, pair)

      true ->
        nil
    end
  end

  defp reading(%{frame: frame, mark: mark} = ctx, {channel, where}) do
    spec = Map.get(mark.channels, channel)
    scale = scale_of(ctx, channel)
    share? = mark.type in [:arc, :rose] and channel == :value

    if field(spec) && (share? or Map.has_key?(frame.scales, scale)) do
      %{
        label: humanise(field(spec)),
        read: &Channels.reading(ctx, channel, &1),
        scale: if(share?, do: nil, else: scale),
        where: where
      }
    end
  end

  defp channel_pair(frame, %{type: type} = mark) do
    case type do
      t when t in [:line, :area, :symbol, :circle] -> {:y, :x}
      :percentile_band -> {:median, :x}
      :needle -> {:x, nil}
      :rose -> {:value, :angle}
      :arc -> {:value, :name}
      :rect -> rect_pair(mark, if(bar?(frame, mark), do: band(frame, mark)))
      _other -> nil
    end
  end

  defp rect_pair(_mark, :x0), do: {:y1, :x0}
  defp rect_pair(_mark, :y0), do: {:x1, :y0}

  defp rect_pair(mark, nil) do
    if channel?(mark, :value), do: {:value, [:x0, :y0]}
  end

  defp scale_of(%{frame: frame, mark: mark}, channel),
    do: Scales.scale_for(frame.kind, mark, channel)

  # -- series -----------------------------------------------------------------------------

  # The series the marks draw (§21.1): each `series` channel's values in order of first
  # appearance, and one more for each mark without the channel that draws a value, named
  # by it.
  defp series(drawn) do
    drawn
    |> Enum.flat_map(fn %{ctx: ctx, rows: rows, value: value, readings: readings} ->
      cond do
        channel?(ctx.mark, :series) ->
          for row <- rows, s = Channels.reading(ctx, :series, row), s != nil, do: plain(s)

        stack(ctx.mark) != nil ->
          for row <- rows, key = Table.get(row, :key), key != nil, do: plain(key)

        readings != [] ->
          [value.label]

        true ->
          []
      end
    end)
    |> Enum.uniq()
  end

  # What a frame's rows are called, by its first data mark.
  defp unit(_frame, nil), do: "items"
  defp unit(%Frame{kind: :geo}, _mark), do: "shapes"

  defp unit(frame, mark) do
    case mark.type do
      :arc -> "slices"
      :needle -> "readings"
      :rect -> if bar?(frame, mark), do: "bars", else: "cells"
      :path -> "shapes"
      _other -> "points"
    end
  end

  # -- axes -------------------------------------------------------------------------------

  # An axis as its scale's range, or its categories (§21.1). A scale whose domain holds no
  # value — an empty chart — says nothing.
  defp axis(frame, node, valued) do
    scale = Map.fetch!(frame.scales, node.scale)
    title = axis_title(frame, node, valued)
    said = %{scale: node.scale, side: node.side, title: title, range: nil, categories: nil}

    case Map.get(scale, :domain) do
      [_ | _] = domain ->
        if categorical?(scale) or not Enum.all?(domain, &orderable?/1) do
          [%{said | categories: Enum.map(domain, &plain/1)}]
        else
          {lo, hi} = Enum.min_max_by(domain, &order/1)
          format = formatter(frame, node.scale)
          [%{said | range: {format.(lo), format.(hi)}}]
        end

      _empty ->
        []
    end
  end

  defp categorical?(%struct{}), do: struct in [Scale.Band, Scale.Ordinal]

  # An axis's title: the label the design anchors at it, else its measure's label, else the
  # fields the marks bind to its scale — the marks that draw a value when one of them does
  # — else the scale's name.
  defp axis_title(frame, node, valued) do
    Enum.find_value(frame.labels, &if(&1.anchor == {:axis, node.scale}, do: text_of(&1.text))) ||
      measure_label(node) ||
      bound(frame, Enum.map(valued, & &1.ctx.mark), node.scale) ||
      bound(frame, frame.marks, node.scale) ||
      to_string(node.scale)
  end

  defp measure_label(%{measure: measure}) when is_map(measure), do: Quantity.label(measure)
  defp measure_label(_node), do: nil

  defp bound(frame, marks, scale) do
    titles =
      for mark <- marks,
          Map.get(mark, :type) not in @auxiliary,
          title = mark_title(frame, mark, scale),
          uniq: true,
          do: title

    if titles != [], do: words(titles)
  end

  # The field a mark binds to the scale on its most telling channel; a stacked mark's
  # stacked edges are its rows' value.
  defp mark_title(frame, mark, scale) do
    Enum.find_value(@titling, fn channel ->
      spec = Map.get(Map.get(mark, :channels, %{}), channel)

      cond do
        field(spec) == nil -> nil
        Scales.scale_for(frame.kind, mark, channel) != scale -> nil
        stack(mark) && field(spec) in [:y0, :y1] -> "value"
        true -> humanise(field(spec))
      end
    end)
  end

  # -- extremes ---------------------------------------------------------------------------

  # The extremes of the marks that draw a value, one per value they draw: the marks that
  # draw the same field on the same scale — the layers of a ridgeline, the bands of a
  # scrolling series — are one value, and say one highest and one lowest.
  defp extremes(valued) do
    valued
    |> Enum.group_by(&{&1.value.label, &1.value.scale})
    |> Enum.sort_by(fn {_key, [first | _]} -> Enum.find_index(valued, &(&1 == first)) end)
    |> Enum.map(fn {_key, group} -> extreme(group) end)
  end

  defp extreme([%{ctx: %{frame: frame}, value: value} | _] = group) do
    readings =
      for %{ctx: ctx, readings: readings} <- group, {v, row} <- readings, do: {v, row, ctx}

    format = formatter(frame, value.scale)
    {hi, hi_row, hi_ctx} = Enum.max_by(readings, &elem(&1, 0))
    {lo, lo_row, lo_ctx} = Enum.min_by(readings, &elem(&1, 0))

    %{
      field: value.label,
      rows: length(readings),
      high: {format.(hi), where(hi_ctx, value.where, hi_row)},
      low: {format.(lo), where(lo_ctx, value.where, lo_row)}
    }
  end

  # Where a row is: its partner channel as the chart writes it, then its series; or its
  # name — its series, else the first field its inline label reads.
  defp where(ctx, channel, row) when is_atom(channel) and channel not in [nil, :name] do
    case placed(ctx, channel, row) do
      nil ->
        place(ctx, :name, row)

      at ->
        case Channels.reading(ctx, :series, row) || stacked_key(ctx.mark, row) do
          nil -> at
          series -> "#{at} in #{plain(series)}"
        end
    end
  end

  defp where(ctx, where, row), do: place(ctx, where, row)

  # Where a row is without its series: its partner channels as the chart writes them, else
  # its name — its series, else the first field its inline label reads.
  defp place(_ctx, nil, _row), do: nil

  defp place(ctx, channels, row) when is_list(channels) do
    case for(channel <- channels, at = placed(ctx, channel, row), do: at) do
      [] -> place(ctx, :name, row)
      places -> Enum.join(places, ", ")
    end
  end

  defp place(ctx, :name, row) do
    case Channels.reading(ctx, :series, row) || label_field(ctx.mark, row) do
      nil -> nil
      name -> plain(name)
    end
  end

  defp place(ctx, channel, row), do: placed(ctx, channel, row) || place(ctx, :name, row)

  # A channel's reading of a row as the chart writes it, after the field's name.
  defp placed(%{frame: frame, mark: mark} = ctx, channel, row) do
    case Channels.reading(ctx, channel, row) do
      nil ->
        nil

      at ->
        written = formatter(frame, scale_of(ctx, channel)).(at)
        if name = field_name(mark, channel), do: "#{name} #{written}", else: written
    end
  end

  defp stacked_key(mark, row), do: if(stack(mark), do: Table.get(row, :key))

  defp label_field(%{label: %{text: text}}, row) do
    Enum.find_value(Text.parse!(text), fn
      {:field, field} -> Table.get(row, field)
      _part -> nil
    end)
  end

  defp label_field(_mark, _row), do: nil

  # -- writing values ---------------------------------------------------------------------

  @doc false
  # How the chart writes a value on a scale (§21.1): a time scale's through its axis's
  # format, which says the instant; a number on a scale with an axis to four significant
  # digits in the axis's terms — its explicit `format`, else its measure's display unit
  # and symbol — inside its `prefix` and `unit`; anything else as plain text.
  @spec formatter(Frame.t(), atom() | nil) :: (term() -> String.t())
  def formatter(frame, scale_name) do
    node = scale_name && Enum.find(frame.axes, &(&1.scale == scale_name))
    scale = scale_name && Map.get(frame.scales, scale_name)

    case {node, scale} do
      {nil, _scale} -> &plain/1
      {node, %Scale.Time{}} -> tick_format(frame, node)
      {node, scale} -> wrapped(node, number_format(node, scale))
    end
  end

  defp tick_format(frame, node) do
    case Furniture.axis(frame, node).tick_format do
      nil -> &Visualize.Axis.default_label/1
      format -> format
    end
  end

  defp number_format(%{format: :duration}, _scale), do: numbers(&Format.duration/1)

  defp number_format(%{format: spec}, _scale) when is_binary(spec),
    do: numbers(Format.formatter(spec))

  defp number_format(%{measure: measure}, %{domain: domain}) when is_map(measure) do
    {:ok, %{unit: unit} = resolved} = Quantity.resolve(measure)
    display = Quantity.display_unit(domain, resolved)

    numbers(fn value ->
      scaled =
        if unit && display && unit != display, do: Unit.convert(value, unit, display), else: value

      plain(scaled) <> Quantity.suffix(display)
    end)
  end

  defp number_format(_node, _scale), do: &plain/1

  defp numbers(format) do
    fn
      value when is_number(value) -> format.(value)
      value -> plain(value)
    end
  end

  defp wrapped(node, format) do
    case {Map.get(node, :prefix), Map.get(node, :unit)} do
      {nil, nil} -> format
      {prefix, unit} -> &((prefix || "") <> format.(&1) <> (unit || ""))
    end
  end

  @doc false
  # A value as plain text: a number to four significant digits, anything else as itself.
  @spec plain(term()) :: String.t()
  def plain(value) when is_number(value), do: Format.formatter(",.4~r").(value)
  def plain(value) when is_binary(value), do: value
  def plain(value) when is_atom(value), do: Atom.to_string(value)
  def plain(%Path{}), do: "shape"
  def plain(%Date{} = value), do: Date.to_iso8601(value)
  def plain(%DateTime{} = value), do: DateTime.to_iso8601(value)
  def plain(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  def plain(value), do: inspect(value)

  defp field(field) when is_atom(field) and field not in [nil, true, false], do: field
  defp field({:field, field}) when is_atom(field), do: field
  defp field(_spec), do: nil

  defp field_name(mark, channel) do
    case field(Map.get(Map.get(mark, :channels, %{}), channel)) do
      nil -> nil
      field -> humanise(field)
    end
  end

  defp humanise(atom), do: atom |> Atom.to_string() |> String.replace("_", " ")

  defp orderable?(value),
    do:
      is_number(value) or is_struct(value, DateTime) or
        is_struct(value, NaiveDateTime) or is_struct(value, Date)

  defp order(%DateTime{} = value), do: DateTime.to_unix(value, :microsecond)

  defp order(%NaiveDateTime{} = value),
    do: NaiveDateTime.diff(value, ~N[1970-01-01 00:00:00], :microsecond)

  defp order(%Date{} = value), do: Date.to_gregorian_days(value)
  defp order(value), do: value

  # A text with no hole left in it as one string, `nil` when absent or empty; an applied
  # chart has no hole left, so a variable here is the unresolved-variable fault.
  defp text_of(nil), do: nil

  defp text_of(text) do
    string =
      Enum.map_join(Text.parse!(text), "", fn
        string when is_binary(string) -> string
        %Var{name: name} -> Visualize.Chart.Style.unresolved!(name)
      end)

    if string != "", do: string
  end

  # -- sentences --------------------------------------------------------------------------

  defp frame_text(frame, many?) do
    lead = if many? and frame.name, do: "#{capitalise(humanise(frame.name))}: ", else: ""

    sentences =
      [series_sentence(frame)] ++
        Enum.map(frame.axes, &axis_sentence/1) ++ Enum.map(frame.extremes, &extreme_sentence/1)

    lead <> Enum.join(sentences, " ")
  end

  defp series_sentence(%{kind: kind, series: series, rows: rows, unit: unit}) do
    kind = capitalise(kind)

    case series do
      [] -> "#{kind}, #{count(rows, unit)}."
      [one] -> "#{kind}, 1 series (#{one}) of #{count(rows, unit)}."
      many -> "#{kind}, #{length(many)} series: #{listed(many)}."
    end
  end

  defp count(1, unit), do: "1 " <> String.trim_trailing(unit, "s")
  defp count(n, unit), do: "#{n} #{unit}"

  defp listed(list) when length(list) > @listed,
    do: Enum.join(Enum.take(list, @listed), ", ") <> " and #{length(list) - @listed} more"

  defp listed(list), do: words(list)

  defp axis_sentence(%{side: side, scale: scale, title: title} = axis) do
    lead = "#{axis_name(side, scale)} #{title}"

    case axis do
      %{range: {lo, hi}} ->
        "#{lead}, from #{lo} to #{hi}."

      %{categories: [one]} ->
        "#{lead}, 1 category: #{one}."

      %{categories: categories} when length(categories) > @listed ->
        "#{lead}, #{length(categories)} categories from #{hd(categories)} to #{List.last(categories)}."

      %{categories: categories} ->
        "#{lead}, #{length(categories)} categories: #{words(categories)}."
    end
  end

  defp axis_name(_side, :angle), do: "Angle axis"
  defp axis_name(_side, :r), do: "Radius axis"
  defp axis_name(side, _scale), do: capitalise(Atom.to_string(side)) <> " axis"

  defp extreme_sentence(%{field: field, rows: 1, high: {value, at}}),
    do: "#{capitalise(field)} #{value}#{at(at)}."

  defp extreme_sentence(%{field: field, high: {hi, hi_at}, low: {lo, lo_at}}),
    do: "Highest #{field} #{hi}#{at(hi_at)}; lowest #{field} #{lo}#{at(lo_at)}."

  defp at(nil), do: ""
  defp at(where), do: " at " <> where

  defp words([one]), do: one
  defp words(list), do: Enum.join(Enum.drop(list, -1), ", ") <> " and " <> List.last(list)

  defp capitalise(<<first::utf8, rest::binary>>), do: String.upcase(<<first::utf8>>) <> rest
  defp capitalise(""), do: ""
end
