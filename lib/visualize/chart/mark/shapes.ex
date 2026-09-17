defmodule Visualize.Chart.Mark.Shapes do
  @moduledoc false
  # The data-shaped marks (spec/14 §5.6, D-61): each one the generator of spec/04 it names,
  # fed the pixels `Visualize.Chart.Mark.Channels` computed, so its geometry is byte for
  # byte the direct call. Every builder returns children as
  # `%{element, datum, style, anchor}` — the element, the datum it was drawn from, the
  # element's own style over the generator's, and the inline label's anchor point.

  alias Visualize.Chart.Mark.{Channels, Label}
  alias Visualize.Chart.Style
  alias Visualize.IR.{Element, Transform}
  alias Visualize.Scale
  alias Visualize.Shape.{Arc, Area, Band, Line, PercentileBand, Rose, Rule, Symbol, XBand}
  alias Visualize.Theme

  @stroke_keys [
    :stroke,
    :stroke_width,
    :stroke_dasharray,
    :stroke_linecap,
    :stroke_linejoin,
    :stroke_opacity
  ]

  @doc false
  @spec elements(map()) :: [map()]
  def elements(%{type: :line} = ctx), do: line(ctx)
  def elements(%{type: :area} = ctx), do: area(ctx)
  def elements(%{type: :band} = ctx), do: band(ctx)
  def elements(%{type: :rule} = ctx), do: rule(ctx)
  def elements(%{type: :x_band} = ctx), do: x_band(ctx)
  def elements(%{type: :percentile_band} = ctx), do: percentile_band(ctx)
  def elements(%{type: :rose} = ctx), do: rose(ctx)
  def elements(%{type: :symbol} = ctx), do: symbol(ctx)

  # -- line and area: one path per series ------------------------------------------------

  defp line(ctx) do
    filled? = filled?(ctx)
    baseline = Channels.baseline(ctx)

    ctx
    |> Channels.pixels()
    |> series(ctx)
    |> Enum.flat_map(fn {value, rows, j} ->
      path =
        Line.new()
        |> Line.x(:x)
        |> Line.y(:y)
        |> curve(ctx, &Line.curve/3)
        |> defined(rows, [:x, :y], &Line.defined/2)
        |> Line.generate_path(rows)

      style = series_style(ctx, value, j)
      anchor = last_point(rows, :x, :y)

      # A filled line is the area under it (spec/14 §5.6): the area to the baseline first,
      # then the line itself, unfilled.
      if filled? do
        [
          child(
            under(rows, baseline, ctx, value),
            rows,
            %{class: "line-fill", stroke: :none},
            anchor
          ),
          child(series_path(path, value), rows, Map.put(style, :fill, :none), anchor)
        ]
      else
        [child(series_path(path, value), rows, style, anchor)]
      end
    end)
  end

  # Whether the style gives the line a fill: a static one other than none, or a binding.
  defp filled?(%{static: static, bound: bound}) do
    Map.has_key?(bound, :fill) or (Map.has_key?(static, :fill) and static.fill != :none)
  end

  # The area from a series' line down to the baseline, in the line's curve.
  defp under(rows, baseline, ctx, value) do
    rows = Enum.map(rows, &Map.merge(&1, %{x0: &1.x, x1: &1.x, y0: baseline, y1: &1.y}))

    Area.new()
    |> Area.x0(:x0)
    |> Area.x1(:x1)
    |> Area.y0(:y0)
    |> Area.y1(:y1)
    |> curve(ctx, &Area.curve/3)
    |> defined(rows, [:x0, :x1, :y0, :y1], &Area.defined/2)
    |> Area.generate_path(rows)
    |> series_path(value)
  end

  defp area(ctx) do
    baseline = Channels.baseline(ctx)

    ctx
    |> Channels.pixels()
    |> Enum.map(fn row ->
      Map.merge(row, %{
        x0: edge(ctx, row, :x0, row.x),
        x1: edge(ctx, row, :x1, row.x),
        y0: edge(ctx, row, :y0, baseline),
        y1: edge(ctx, row, :y1, row.y)
      })
    end)
    |> series(ctx)
    |> Enum.map(fn {value, rows, j} ->
      path =
        Area.new()
        |> Area.x0(:x0)
        |> Area.x1(:x1)
        |> Area.y0(:y0)
        |> Area.y1(:y1)
        |> curve(ctx, &Area.curve/3)
        |> defined(rows, [:x0, :x1, :y0, :y1], &Area.defined/2)
        |> Area.generate_path(rows)

      child(
        series_path(path, value),
        rows,
        series_style(ctx, value, j),
        last_point(rows, :x1, :y1)
      )
    end)
  end

  # An optional edge channel: its pixel when the mark declares it, else the fallback.
  defp edge(ctx, row, channel, fallback) do
    if Channels.has?(ctx, channel), do: Map.get(row, channel), else: fallback
  end

  defp curve(shape, %{style_node: style_node, frame: frame}, setter) do
    curve = Style.value(:curve, Map.get(style_node, :curve, :linear), frame.theme, :literal)

    opts =
      style_node |> Map.get(:curve_opts, %{}) |> Map.take([:tension, :alpha]) |> Map.to_list()

    setter.(shape, curve, opts)
  end

  # `defined/2` breaks the path at a datum a scale could not place; set only when one is.
  defp defined(shape, rows, channels, setter) do
    if Enum.all?(rows, &Channels.placed?(&1, channels)),
      do: shape,
      else: setter.(shape, &Channels.placed?(&1, channels))
  end

  # The rows split by the `series` channel in order of first appearance, with the series'
  # one-based position; one unnamed series without the channel.
  defp series(rows, ctx) do
    if Channels.has?(ctx, :series) do
      rows
      |> Enum.map(& &1.series)
      |> Enum.uniq()
      |> Enum.with_index(1)
      |> Enum.map(fn {value, j} -> {value, Enum.filter(rows, &(&1.series == value)), j} end)
    else
      [{nil, rows, nil}]
    end
  end

  # A series' path names its series, the string the legend's entries carry (spec/14 §5.6,
  # D-77); a mark without the channel names none.
  defp series_path(path, nil), do: Element.path(path)

  defp series_path(path, value),
    do: Element.set_attrs(Element.path(path), %{"data-series" => to_string(value)})

  # A series' paint: the colour scale's value for the series, else the theme's series
  # colour for its position (spec/14 §5.6).
  defp series_style(_ctx, _value, nil), do: %{}

  defp series_style(%{frame: frame, mode: mode, paint: {key, _}}, value, j) do
    colour =
      case Map.get(frame.scales, :color) do
        nil -> nil
        scale -> Scale.apply(scale, value)
      end

    if colour == nil,
      do: %{key => Theme.resolve(frame.theme, {:series, j}, mode)},
      else: %{key => Style.colour(colour, frame.theme, mode)}
  end

  defp last_point(rows, xk, yk) do
    case Enum.reverse(Channels.placed(rows, [xk, yk])) do
      [last | _] -> {Map.get(last, xk), Map.get(last, yk)}
      [] -> nil
    end
  end

  defp child(element, rows, style, anchor) do
    datum =
      case rows do
        [first | _] -> first.datum
        [] -> %{}
      end

    %{element: element, datum: datum, style: style, anchor: anchor}
  end

  # -- band ----------------------------------------------------------------------------

  defp band(ctx) do
    height = option(ctx, :height, 10)

    rows =
      ctx
      |> Channels.pixels()
      |> Enum.map(&Map.put_new(&1, :y, 0))
      |> Enum.map(&Map.update!(&1, :y, fn y -> y || 0 end))
      |> Channels.placed([:x0, :x1])

    elements =
      Band.new()
      |> Band.x0(:x0)
      |> Band.x1(:x1)
      |> Band.y(:y)
      |> Band.height(height)
      |> Band.generate(rows)

    Enum.zip_with(elements, rows, fn element, row ->
      %{x: x, y: y, width: w, height: h} = element.attrs

      %{
        element: element,
        datum: row.datum,
        style: %{},
        anchor: {x + w / 2, y + h / 2},
        bounds: {x, y, w, h}
      }
    end)
  end

  # -- rule and x-band: the generator's own label ----------------------------------------

  defp rule(ctx) do
    rows = ctx |> Channels.pixels() |> Channels.placed([:x])

    elements =
      Rule.new()
      |> Rule.x(:x)
      |> Rule.y0(0)
      |> Rule.y1(ctx.frame.plot.height)
      |> Rule.label(label_accessor(ctx))
      |> Rule.generate(rows)

    Enum.zip_with(elements, rows, fn group, row ->
      [line | text] = group.children
      line = Element.set_style(line, stroke_style(ctx, row.datum))

      %{
        element: %{group | children: [line | label_text(text, ctx)]},
        datum: row.datum,
        style: %{},
        anchor: nil
      }
    end)
  end

  defp x_band(ctx) do
    rows = ctx |> Channels.pixels() |> Channels.placed([:x0, :x1])

    elements =
      XBand.new()
      |> XBand.x0(:x0)
      |> XBand.x1(:x1)
      |> XBand.y0(0)
      |> XBand.y1(ctx.frame.plot.height)
      |> XBand.label(label_accessor(ctx))
      |> XBand.generate(rows)

    Enum.zip_with(elements, rows, fn group, row ->
      [rect | text] = group.children
      rect = Element.set_style(rect, fill_style(ctx, row.datum))

      %{
        element: %{group | children: [rect | label_text(text, ctx)]},
        datum: row.datum,
        style: %{},
        anchor: nil
      }
    end)
  end

  defp label_accessor(%{label: nil}), do: nil
  defp label_accessor(%{label: label}), do: fn row -> Label.text(label.text, row.datum) end

  defp label_text([], _ctx), do: []
  defp label_text([text], ctx), do: [Element.set_style(text, Label.style(ctx))]

  # The stroke keys of the mark's style and its paint, bound to the datum, replacing the
  # generator's `current_color`.
  defp stroke_style(%{static: static, paint: {:stroke, paint}} = ctx, datum) do
    static
    |> Map.take(@stroke_keys)
    |> Map.put(:stroke, paint)
    |> Map.merge(Map.take(ctx.bound, @stroke_keys))
    |> Style.bind(datum, ctx.frame, ctx.mode)
  end

  defp fill_style(%{static: static, paint: {:fill, paint}} = ctx, datum) do
    static
    |> Map.take([:fill, :fill_opacity])
    |> Map.put(:fill, paint)
    |> Map.merge(Map.take(ctx.bound, [:fill, :fill_opacity]))
    |> Style.bind(datum, ctx.frame, ctx.mode)
  end

  # -- percentile band --------------------------------------------------------------------

  defp percentile_band(ctx) do
    rows = Channels.pixels(ctx)
    inner? = Channels.has?(ctx, :inner_lo) and Channels.has?(ctx, :inner_hi)
    outer? = Channels.has?(ctx, :outer_lo) and Channels.has?(ctx, :outer_hi)

    channels =
      [:x, :median] ++
        if(inner?, do: [:inner_lo, :inner_hi], else: []) ++
        if(outer?, do: [:outer_lo, :outer_hi], else: [])

    paths =
      PercentileBand.new()
      |> PercentileBand.x(:x)
      |> PercentileBand.median(:median)
      |> PercentileBand.inner(if inner?, do: {:inner_lo, :inner_hi})
      |> PercentileBand.outer(if outer?, do: {:outer_lo, :outer_hi})
      |> curve(ctx, &PercentileBand.curve/3)
      |> defined(rows, channels, &PercentileBand.defined/2)
      |> PercentileBand.generate_path(rows)

    {_, paint} = ctx.paint
    anchor = last_point(rows, :x, :median)

    [
      {paths.outer, %{class: "outer", fill: paint, fill_opacity: 0.2, stroke: :none}},
      {paths.inner, %{class: "inner", fill: paint, fill_opacity: 0.4, stroke: :none}},
      {paths.median, %{class: "median", fill: :none, stroke: paint}}
    ]
    |> Enum.reject(fn {path, _} -> path == nil end)
    |> Enum.map(fn {path, style} -> child(Element.path(path), rows, style, anchor) end)
  end

  # -- rose ----------------------------------------------------------------------------

  defp rose(ctx) do
    scale = Map.get(ctx.frame.scales, :angle)
    width = option(ctx, :width, 1)
    inner = option(ctx, :inner_radius, 0)
    pad = option(ctx, :pad_angle, 0)
    outer_default = option(ctx, :outer_radius, outer_radius(ctx))
    rows = ctx |> Channels.pixels([:angle]) |> Channels.placed([:angle])
    rows = Enum.map(rows, &Map.put(&1, :outer, Map.get(&1, :value) || outer_default))

    paths =
      Rose.new()
      |> Rose.scale(scale)
      |> Rose.angle(:angle)
      |> Rose.width(width)
      |> Rose.inner_radius(inner)
      |> Rose.outer_radius(:outer)
      |> Rose.pad_angle(pad)
      |> Rose.generate_path(rows)

    Enum.zip_with(paths, rows, fn path, row ->
      half = width / 2
      a0 = angle(scale, row.angle - half)
      a1 = angle(scale, row.angle + half)

      anchor =
        Arc.new()
        |> Arc.inner_radius(inner)
        |> Arc.outer_radius(row.outer)
        |> Arc.start_angle(a0)
        |> Arc.end_angle(a1)
        |> Arc.centroid(row)

      %{element: Element.path(path), datum: row.datum, style: %{}, anchor: anchor}
    end)
  end

  defp angle(nil, value), do: value
  defp angle(scale, value), do: Scale.apply(scale, value)

  # -- symbol ----------------------------------------------------------------------------

  defp symbol(ctx) do
    %{style_node: style_node, frame: frame} = ctx
    type = Map.get(style_node, :symbol, :circle)
    size = Style.value(:symbol_size, Map.get(style_node, :symbol_size, 64), frame.theme, :literal)
    rows = ctx |> Channels.pixels() |> Channels.placed([:x, :y])

    Enum.map(rows, fn row ->
      path =
        Symbol.new()
        |> Symbol.type(type)
        |> Symbol.size(Map.get(row, :value) || size)
        |> Symbol.generate_path(row.datum)

      element = Element.path(path) |> Element.set_transform(Transform.translate(row.x, row.y))
      %{element: element, datum: row.datum, style: %{}, anchor: {row.x, row.y}}
    end)
  end

  # -- helpers ---------------------------------------------------------------------------

  @doc false
  @spec option(map(), atom(), term()) :: term()
  def option(%{options: options}, key, default), do: Map.get(options, key, default)

  @doc false
  # The plot's outer radius `R` (spec/14 §5.3).
  @spec outer_radius(map()) :: number()
  def outer_radius(%{frame: %{plot: plot}}), do: min(plot.width, plot.height) / 2
end
