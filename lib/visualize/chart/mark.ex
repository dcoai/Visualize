defmodule Visualize.Chart.Mark do
  @moduledoc """
  The marks of a design drawn through the frame's scales (spec/14 §5, D-61).

  `generate/3` is one mark node as one `Visualize.IR.Element` group in the plot area's
  coordinates: its rows are the bound source through the mark's pipeline (`rows/3`,
  spec/14 §5.4), each channel is read from the rows and mapped through the scale it
  names in `Visualize.Chart.Frame.scales/1` — the frame kind's table, renamed by the
  mark's `scales` node (spec/14 §5.1) — and every element is the generator's own —
  `Visualize.Shape.Line`, `Visualize.Shape.Area`, `Visualize.Shape.Band`,
  `Visualize.Shape.Rule`, `Visualize.Shape.XBand`, `Visualize.Shape.PercentileBand`,
  `Visualize.Shape.Rose`, `Visualize.Shape.Symbol`, `Visualize.Shape.Pie` over
  `Visualize.Shape.Arc` — fed the pixels the mark computed, so a mark is byte for byte
  the direct call with the same numbers. The four generic marks (`path`, `rect`, `circle`,
  `arc`) draw what a layout's rows carry. The mark's style resolves through
  `Visualize.Chart.Style` in the mode of the render target, and its paint, when the style
  gives none, is the theme's series colour for its position (spec/14 §5.6).

  ## Examples

      iex> chart =
      ...>   Visualize.Chart.from_map!(%{
      ...>     version: 2,
      ...>     sources: %{primary: %{fields: [:t, :v]}},
      ...>     frames: %{main: %{
      ...>       kind: :cartesian,
      ...>       margin: %{top: 0, right: 0, bottom: 0, left: 0},
      ...>       scales: %{x: %{kind: :linear}, y: %{kind: :linear}}
      ...>     }},
      ...>     marks: [%{type: :line, data: :primary, channels: %{x: :t, y: :v}}]
      ...>   })
      iex> sources = %{primary: [%{t: 0, v: 0}, %{t: 1, v: 1}]}
      iex> frame = Visualize.Chart.Frame.new(chart, sources: sources, size: {300, 200})
      iex> group = Visualize.Chart.Mark.generate(frame, hd(chart.marks), sources: sources)
      iex> group.style
      %{class: "mark mark-line", fill: :none, stroke: "var(--vis-series-1, #3b6fa8)"}
      iex> [path] = group.children
      iex> Visualize.Backend.SVG.path_data(path.path)
      "M0,200L300,0"

  """

  alias Visualize.Chart.Frame
  alias Visualize.Chart.Frame.Scales
  alias Visualize.Chart.Mark.{Bend, Generic, Label, Series, Shapes, Strokes, Styled, Tiles}
  alias Visualize.Chart.{Style, Var}
  alias Visualize.Data.Table
  alias Visualize.IR.{Element, Transform}
  alias Visualize.Theme

  @shapes [:line, :area, :band, :rule, :x_band, :percentile_band, :rose, :symbol, :needle]
  @stroked [:line, :rule]
  @centred [:rose, :arc, :needle]
  # Drawn as they are in a polar frame: polar already, or geometry in plot pixels (§5.2).
  @unbent [:rose, :arc, :path, :needle]

  @typedoc """
  What the element builders see of a mark: the frame, the mark node, its rows, its
  resolved style split into the static part and the `{:field, f}` bindings, its paint
  as `{key, colour}`, its options, inline label and tooltip node, the render mode, and
  its series values by position when it has a `series` channel (spec/14 §5.2, D-126), the
  keys a mark with an event writes on its elements (§5.7, D-170), its one-based position
  among the marks, and the styles a stack's `{:field, f}` entries name by data (§3.6,
  #644), `nil` for a stack that names none.
  """
  @type context :: %{
          frame: Frame.t(),
          mark: map(),
          type: atom(),
          rows: [map()],
          mode: Theme.mode(),
          style_node: map(),
          static: map(),
          bound: map(),
          paint: {:fill | :stroke, term()},
          options: map(),
          label: map() | nil,
          tooltip: map() | nil,
          series: %{term() => pos_integer()} | nil,
          keys:
            %{frame: atom(), mark: non_neg_integer(), ordinals: %{map() => non_neg_integer()}}
            | nil,
          index: pos_integer(),
          by_data: %{entries: [{:field, atom()}], names: map(), table: map()} | nil
        }

  @doc "As `generate/3` with `[]` options: no source bound, an empty mark group."
  @spec generate(Frame.t(), map()) :: Element.t()
  def generate(%Frame{} = frame, mark), do: generate(frame, mark, [])

  @doc """
  One mark as the `Visualize.IR.Element` group of spec/14 §5.6.

  ## Options

    * `:sources` - a map from source name to anything `Visualize.Data.Table.rows/1`
      reads, as `Visualize.Chart.Frame.new/2` takes (default `%{}`)
    * `:resolve` - the theme mode: `:css` (default) or `:literal`
    * `:index` - the mark's one-based position among the design's marks, for its paint;
      defaults to its position among the frame's marks, `1` when it is not one of them
    * `:panel` - in a `:facet` frame, the panel value the rows are restricted to

  Raises `ArgumentError` for an unresolved variable, a `:path` row whose `path` is neither
  a `Visualize.IR.Path` nor `nil` (a `nil` path, such as a row a `:projection` clips, draws
  nothing — D-130), or a pipeline step it cannot run.
  """
  @spec generate(Frame.t(), map(), keyword()) :: Element.t()
  def generate(%Frame{} = frame, %{type: :tiles} = mark, opts) do
    Tiles.generate(frame, mark, Keyword.get(opts, :resolve, :css))
  end

  def generate(%Frame{} = frame, %{type: type} = mark, opts) do
    frame = coloured(frame, mark)
    sources = Keyword.get(opts, :sources, %{})
    mode = Keyword.get(opts, :resolve, :css)
    index = Keyword.get_lazy(opts, :index, fn -> position(frame, mark) end)
    realised = rows(frame, mark, sources)
    rows = panel(realised, frame, Keyword.fetch(opts, :panel))
    style_node = Style.node(frame.styles, Map.get(mark, :style))

    ctx =
      %{
        frame: frame,
        mark: mark,
        type: type,
        rows: rows,
        mode: mode,
        index: index,
        options: options(mark),
        label: label(mark),
        tooltip: node(mark, :tooltip)
      }
      |> Map.merge(Styled.parts(style_node, type, index, frame.theme, mode))
      |> Styled.prepare()

    ctx = Map.merge(ctx, %{series: Series.index(ctx), keys: keys(ctx, realised)})

    children = if type in @shapes, do: Shapes.elements(ctx), else: Generic.elements(ctx)
    # Every element and label a series draws names it (spec/14 §5.6, D-126).
    children = children |> Series.annotate(ctx) |> bent(ctx)
    bound = Enum.map(children, &bind(&1, ctx))
    elements = strokes(children, bound, ctx)
    # A label inked by contrast reads its element's bound fill (spec/14 §5.5, D-123).
    labelled = Label.under(children, bound, ctx)

    ctx
    |> group(elements, Label.elements(labelled, ctx))
    |> centre(ctx)
  end

  @doc """
  The rows a mark draws: its source's rows through its transforms with the frame's plot
  area and projection as the pipeline's context (spec/14 §5.4), `[]` when the source is
  not bound.
  """
  @spec rows(Frame.t(), map(), map()) :: [map()]
  def rows(%Frame{} = frame, mark, sources) do
    plot = frame.plot

    ctx = %{
      size: [plot.width, plot.height],
      centre: Frame.centre(frame.kind, plot),
      projection: frame.projection,
      now: frame.now,
      schemas: frame.schemas,
      forces: frame.forces
    }

    Scales.mark_rows(mark, sources, ctx)
  end

  @doc false
  # The order a frame draws its marks in (spec/14 §5.2, D-119): the `:tiles` marks first,
  # in design order among themselves, then every other mark in design order. Takes and
  # returns `{mark, anything}` pairs, so a caller keeps each mark's design position.
  @spec drawing_order([{map(), term()}]) :: [{map(), term()}]
  def drawing_order(pairs) do
    {tiles, others} = Enum.split_with(pairs, fn {mark, _} -> tiles?(mark) end)
    tiles ++ others
  end

  @doc false
  # Whether a mark is a basemap (spec/14 §5.2).
  @spec tiles?(map()) :: boolean()
  def tiles?(mark), do: Map.get(mark, :type) == :tiles

  # -- construction ---------------------------------------------------------------------

  defp position(frame, mark) do
    case Enum.find_index(frame.marks, &(&1 == mark)) do
      nil -> 1
      i -> i + 1
    end
  end

  # A mark's colour scale is `color` renamed by its `scales` node (spec/14 §4.3, D-143), so
  # within the mark that scale stands under `color`: its series' paint, its style's colour
  # bindings and its labels' ink all read the one scale, and an overlay that renames it
  # leaves the series' colours to the marks that keep `color`.
  defp coloured(frame, mark) do
    case Scales.colour_scale(mark) do
      :color ->
        frame

      name ->
        case Map.fetch(frame.scales, name) do
          {:ok, scale} -> %{frame | scales: Map.put(frame.scales, :color, scale)}
          :error -> %{frame | scales: Map.delete(frame.scales, :color)}
        end
    end
  end

  defp panel(rows, %{facet: %{by: by}}, {:ok, value}) do
    Enum.filter(rows, &(Table.get(&1, by) == value))
  end

  defp panel(rows, _frame, _panel), do: rows

  defp options(mark) do
    case Map.get(mark, :options, %{}) do
      %Var{name: name} -> Style.unresolved!(name)
      options -> options
    end
  end

  defp label(mark), do: node(mark, :label)

  defp node(mark, key) do
    case Map.get(mark, key) do
      %Var{name: name} -> Style.unresolved!(name)
      node -> node
    end
  end

  # The mark's group (spec/14 §5.6). Without an inline label it is one group carrying the
  # mark's style. With one it is a wrapper — the class, the tooltip's attributes, and later
  # `data-node` and the centring transform, everything the hooks read (D-75) — holding the
  # styled elements' group and, beside it, the labels' group with no style, so a label is
  # drawn in its own style and never outlined by the mark's stroke (#485). A `:text` mark
  # is its label and keeps its own style.
  defp group(%{label: label, type: type} = ctx, elements, _labels)
       when label == nil or type == :text do
    Element.group(elements, style: group_style(ctx), attrs: tooltip_attrs(ctx))
  end

  defp group(ctx, elements, labels) do
    {elements, own} = Label.lift(elements, ctx)

    Element.group(
      [
        Element.group(elements, style: %{group_style(ctx) | class: "mark-elements"}),
        Element.group(own ++ labels, style: %{class: "mark-labels"})
      ],
      style: %{class: class(ctx)},
      attrs: tooltip_attrs(ctx)
    )
  end

  # The group's `data-tooltip-template` and `data-tooltip-event` (spec/14 §5.7), and the
  # frame's name and the mark's position when it keys its elements (D-170).
  defp tooltip_attrs(%{tooltip: nil}), do: %{}

  defp tooltip_attrs(%{tooltip: tooltip} = ctx) do
    for {key, name} <- [template: "data-tooltip-template", event: "data-tooltip-event"],
        value = Map.get(tooltip, key),
        value != nil,
        into: key_attrs(ctx.keys),
        do: {name, to_string(value)}
  end

  defp key_attrs(nil), do: %{}

  defp key_attrs(%{frame: frame, mark: position}),
    do: %{"data-frame" => to_string(frame), "data-mark" => Integer.to_string(position)}

  # What a mark with an event keys its elements by (spec/14 §5.7, D-170): its frame's name,
  # its position among the frame's marks, and each datum's ordinal in the mark's realised
  # rows — all of them, before a facet's panel is taken, as `rows/3` gives them. Equal rows
  # are one row to a click, so the first ordinal names them. `nil` for a mark without an
  # event, or one drawn outside its frame's marks, which cannot be resolved.
  defp keys(%{tooltip: %{event: event}, frame: frame, mark: mark}, rows) when event != nil do
    case Enum.find_index(frame.marks, &(&1 == mark)) do
      nil ->
        nil

      position ->
        ordinals = rows |> Enum.with_index() |> Enum.reverse() |> Map.new()
        %{frame: frame.name, mark: position, ordinals: ordinals}
    end
  end

  defp keys(_ctx, _rows), do: nil

  # The datum attributes of spec/10 §12.2 on an element: the tooltip's fields read from
  # the datum, or every column of the datum in sorted order when it names none.
  defp datum_attrs(element, _datum, %{tooltip: nil}), do: element

  defp datum_attrs(element, datum, %{tooltip: tooltip} = ctx) do
    fields =
      case Map.get(tooltip, :fields, []) do
        [] -> datum |> Map.keys() |> Enum.sort() |> Enum.map(&{&1, Map.get(datum, &1)})
        fields -> Enum.map(fields, &{&1, Table.get(datum, &1)})
      end

    element |> Element.datum(fields) |> row_key(datum, ctx.keys)
  end

  # The datum's ordinal in the mark's realised rows, as `data-row` (D-170).
  defp row_key(element, _datum, nil), do: element

  defp row_key(element, datum, %{ordinals: ordinals}) do
    case Map.fetch(ordinals, datum) do
      {:ok, ordinal} -> Element.put_attr(element, "data-row", Integer.to_string(ordinal))
      :error -> element
    end
  end

  # The group's style: the static part, the paint (a bound one stays per element), and
  # `fill: :none` for a stroked type the style leaves unfilled.
  defp group_style(%{type: type, static: static, paint: {key, colour}} = ctx) do
    static
    |> then(&if(match?({:field, _}, colour), do: &1, else: Map.put(&1, key, colour)))
    |> then(
      &if(type in @stroked and not Map.has_key?(&1, :fill),
        do: Map.put(&1, :fill, :none),
        else: &1
      )
    )
    |> Map.put(:class, class(ctx))
  end

  defp class(%{type: type, style_node: style_node}) do
    case Map.get(style_node, :class) do
      nil -> "mark mark-#{type}"
      class -> "mark mark-#{type} #{class}"
    end
  end

  # An element's own style: the series' paint, then what a style named by its datum
  # changes (spec/14 §3.6), under the generator's, then the bindings read from its datum
  # (spec/14 §3.4, §5.6); and its series' `data-series` (D-126).
  defp bind(%{element: element, datum: datum, style: style} = child, ctx) do
    own = Styled.at(ctx, datum)
    bound = Style.bind(own.bound, datum, own.frame, own.mode)

    paint =
      case own.paint do
        {key, {:field, _} = ref} -> Style.bind(%{key => ref}, datum, own.frame, own.mode)
        _ -> %{}
      end

    element
    |> Element.set_style(
      child
      |> Series.paint(own)
      |> Map.merge(Styled.over(ctx, own))
      |> Map.merge(style)
      |> Map.merge(paint)
      |> Map.merge(bound)
    )
    |> Series.stamp(Map.get(child, :series))
    |> datum_attrs(datum, ctx)
  end

  # The stroke style of the bound elements (spec/14 §5.6): the mark's, or — a per-series
  # key — each child's own where its stack lays a style by data (§3.6).
  defp strokes(_children, bound, %{by_data: nil} = ctx), do: Strokes.apply(bound, ctx)

  defp strokes(children, bound, ctx) do
    children
    |> Enum.zip(bound)
    |> Enum.flat_map(fn {child, element} ->
      Strokes.apply([element], Styled.at(ctx, child.datum))
    end)
  end

  # In a polar frame every ordinary mark is laid out in (angle, r) and bent around the
  # arc (spec/14 §5.2, #391): its elements, its label anchors, and its bounds read as the
  # sector's radii.
  # A symbol's glyph is drawn in pixels about its point: only the point bends, so the glyph
  # keeps its shape on the arc (spec/14 §5.2, §21.7).
  defp bent(children, %{frame: %{kind: :polar}, type: :symbol}) do
    Enum.map(children, fn child ->
      child
      |> Map.update!(:element, &Bend.place/1)
      |> Map.update(:anchor, nil, fn
        {a, r} -> Bend.point({a, r})
        other -> other
      end)
    end)
  end

  defp bent(children, %{frame: %{kind: :polar} = frame, type: type}) when type not in @unbent do
    # Over a categorical angle a straight segment is a chord (§5.2, #393).
    opts = [chords: match?(%Visualize.Scale.Band{}, Map.get(frame.scales, :angle))]

    Enum.map(children, fn child ->
      child
      |> Map.update!(:element, &Bend.bend(&1, opts))
      |> Map.update(:anchor, nil, fn
        {a, r} -> Bend.point({a, r})
        other -> other
      end)
      |> then(fn
        %{bounds: {_x, y, _w, h}} = c -> c |> Map.delete(:bounds) |> Map.put(:radii, {y, y + h})
        c -> c
      end)
    end)
  end

  defp bent(children, _ctx), do: children

  # A centred mark's group about the frame's centre: the point a `:chord` step's paths are
  # drawn about too (spec/14 §5.6, #488). A polar frame's group is already there.
  defp centre(group, %{type: type, frame: %{kind: kind, plot: plot}}) when type in @centred do
    case Frame.centre(kind, plot) do
      [0, 0] -> group
      [x, y] -> Element.set_transform(group, Transform.translate(x, y))
    end
  end

  defp centre(group, _ctx), do: group
end
