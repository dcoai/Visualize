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
      ...>     version: 1,
      ...>     sources: %{primary: %{fields: [:t, :v]}},
      ...>     frame: %{
      ...>       kind: :cartesian,
      ...>       size: %{width: 300, height: 200},
      ...>       margin: %{top: 0, right: 0, bottom: 0, left: 0},
      ...>       scales: %{x: %{kind: :linear}, y: %{kind: :linear}}
      ...>     },
      ...>     marks: [%{type: :line, data: :primary, channels: %{x: :t, y: :v}}]
      ...>   })
      iex> sources = %{primary: [%{t: 0, v: 0}, %{t: 1, v: 1}]}
      iex> frame = Visualize.Chart.Frame.new(chart, sources: sources)
      iex> group = Visualize.Chart.Mark.generate(frame, hd(chart.marks), sources: sources)
      iex> group.style
      %{class: "mark mark-line", fill: :none, stroke: "var(--vis-series-1, #3b6fa8)"}
      iex> [path] = group.children
      iex> Visualize.Backend.SVG.path_data(path.path)
      "M0,200L300,0"

  """

  alias Visualize.Chart.Frame
  alias Visualize.Chart.Frame.Scales
  alias Visualize.Chart.Mark.{Generic, Label, Shapes, Strokes}
  alias Visualize.Chart.{Style, Var}
  alias Visualize.Data.Table
  alias Visualize.IR.{Element, Transform}
  alias Visualize.Theme

  @shapes [:line, :area, :band, :rule, :x_band, :percentile_band, :rose, :symbol]
  @stroked [:line, :rule]
  @centred [:rose, :arc]

  @typedoc """
  What the element builders see of a mark: the frame, the mark node, its rows, its
  resolved style split into the static part and the `{:field, f}` bindings, its paint
  as `{key, colour}`, its options, inline label and tooltip node, and the render mode.
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
          tooltip: map() | nil
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

  Raises `ArgumentError` for an unresolved variable, a `:path` row without a
  `Visualize.IR.Path`, or a pipeline step it cannot run.
  """
  @spec generate(Frame.t(), map(), keyword()) :: Element.t()
  def generate(%Frame{} = frame, %{type: type} = mark, opts) do
    sources = Keyword.get(opts, :sources, %{})
    mode = Keyword.get(opts, :resolve, :css)
    index = Keyword.get_lazy(opts, :index, fn -> position(frame, mark) end)
    rows = frame |> rows(mark, sources) |> panel(frame, Keyword.fetch(opts, :panel))
    style_node = Style.node(frame.styles, Map.get(mark, :style))
    {static, bound} = split(Style.resolve(style_node, frame.theme, mode))

    ctx = %{
      frame: frame,
      mark: mark,
      type: type,
      rows: rows,
      mode: mode,
      style_node: style_node,
      static: static,
      bound: bound,
      paint: paint(type, style_node, index, frame.theme, mode),
      options: options(mark),
      label: label(mark),
      tooltip: node(mark, :tooltip)
    }

    children = if type in @shapes, do: Shapes.elements(ctx), else: Generic.elements(ctx)
    elements = children |> Enum.map(&bind(&1, ctx)) |> Strokes.apply(ctx)

    Element.group(elements ++ Label.elements(children, ctx),
      style: group_style(ctx),
      attrs: tooltip_attrs(ctx)
    )
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
    ctx = %{size: [plot.width, plot.height], projection: frame.projection}
    Scales.mark_rows(mark, sources, ctx)
  end

  # -- construction ---------------------------------------------------------------------

  defp position(frame, mark) do
    case Enum.find_index(frame.marks, &(&1 == mark)) do
      nil -> 1
      i -> i + 1
    end
  end

  defp panel(rows, %{facet: %{by: by}}, {:ok, value}) do
    Enum.filter(rows, &(Table.get(&1, by) == value))
  end

  defp panel(rows, _frame, _panel), do: rows

  defp split(style) do
    {bound, static} = Enum.split_with(style, fn {_key, value} -> match?({:field, _}, value) end)
    {Map.new(static), Map.new(bound)}
  end

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

  # The group's `data-tooltip-template` and `data-tooltip-event` (spec/14 §5.7).
  defp tooltip_attrs(%{tooltip: nil}), do: %{}

  defp tooltip_attrs(%{tooltip: tooltip}) do
    for {key, name} <- [template: "data-tooltip-template", event: "data-tooltip-event"],
        value = Map.get(tooltip, key),
        value != nil,
        into: %{},
        do: {name, to_string(value)}
  end

  # The datum attributes of spec/10 §12.2 on an element: the tooltip's fields read from
  # the datum, or every column of the datum in sorted order when it names none.
  defp datum_attrs(element, _datum, %{tooltip: nil}), do: element

  defp datum_attrs(element, datum, %{tooltip: tooltip}) do
    fields =
      case Map.get(tooltip, :fields, []) do
        [] -> datum |> Map.keys() |> Enum.sort() |> Enum.map(&{&1, Map.get(datum, &1)})
        fields -> Enum.map(fields, &{&1, Table.get(datum, &1)})
      end

    Element.datum(element, fields)
  end

  # The paint: the style's value for the paint key, else the theme's series colour for
  # the mark's position (spec/14 §5.6). A `{:field, f}` there is bound per element.
  defp paint(type, style_node, index, theme, mode) do
    key = if type in @stroked, do: :stroke, else: :fill

    case Map.get(style_node, key) do
      nil -> {key, Theme.resolve(theme, {:series, index}, mode)}
      {:field, _} = ref -> {key, ref}
      value -> {key, Style.value(key, value, theme, mode)}
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

  # An element's own style: the generator's, the series paint, and the bindings read
  # from its datum (spec/14 §3.4).
  defp bind(%{element: element, datum: datum, style: style}, ctx) do
    bound = Style.bind(ctx.bound, datum, ctx.frame, ctx.mode)

    paint =
      case ctx.paint do
        {key, {:field, _} = ref} -> Style.bind(%{key => ref}, datum, ctx.frame, ctx.mode)
        _ -> %{}
      end

    element
    |> Element.set_style(style |> Map.merge(paint) |> Map.merge(bound))
    |> datum_attrs(datum, ctx)
  end

  defp centre(group, %{type: type, frame: %{kind: kind, plot: plot}})
       when type in @centred and kind != :polar do
    Element.set_transform(group, Transform.translate(plot.width / 2, plot.height / 2))
  end

  defp centre(group, _ctx), do: group
end
