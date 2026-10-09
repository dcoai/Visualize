defmodule Visualize.Chart.Mark.Shapes do
  @moduledoc false
  # The data-shaped marks (spec/14 §5.6, D-61): each one the generator of spec/04 it names,
  # fed the pixels `Visualize.Chart.Mark.Channels` computed, so its geometry is byte for
  # byte the direct call. Every builder returns children as
  # `%{element, datum, style, anchor}` — the element, the datum it was drawn from, the
  # element's own style over the generator's, and the inline label's anchor point.

  alias Visualize.Chart.Mark.{Channels, Label, Series}
  alias Visualize.Chart.Style
  alias Visualize.IR.{Element, Transform}
  alias Visualize.Scale
  alias Visualize.Shape.{Arc, Area, Band, Line, Needle, PercentileBand, Rose, Rule, Symbol, XBand}

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
  def elements(%{type: :needle} = ctx), do: needle(ctx)

  # -- line and area: one path per series ------------------------------------------------

  defp line(ctx) do
    filled? = filled?(ctx)
    baseline = Channels.baseline(ctx)

    ctx
    |> Channels.pixels()
    |> series(ctx)
    |> closed(ctx)
    |> Enum.flat_map(fn rows ->
      path =
        Line.new()
        |> Line.x(:x)
        |> Line.y(:y)
        |> curve(ctx, &Line.curve/3)
        |> defined(rows, [:x, :y], &Line.defined/2)
        |> Line.generate_path(rows)

      anchor = last_point(rows, :x, :y)

      # A filled line is the area under it (spec/14 §5.6): the area to the baseline first,
      # then the line itself, unfilled. The series' paint and `data-series` are the mark's
      # (`Visualize.Chart.Mark.Series`), as on every type.
      if filled? do
        [
          child(under(rows, baseline, ctx), rows, %{class: "line-fill", stroke: :none}, anchor),
          child(Element.path(path), rows, %{fill: :none}, anchor)
        ]
      else
        [child(Element.path(path), rows, %{}, anchor)]
      end
    end)
  end

  # Whether the style gives the line a fill: a static one other than none, or a binding.
  defp filled?(%{static: static, bound: bound}) do
    Map.has_key?(bound, :fill) or (Map.has_key?(static, :fill) and static.fill != :none)
  end

  # The area from a series' line down to the baseline, in the line's curve.
  defp under(rows, baseline, ctx) do
    rows = Enum.map(rows, &Map.merge(&1, %{x0: &1.x, x1: &1.x, y0: baseline, y1: &1.y}))

    Area.new()
    |> Area.x0(:x0)
    |> Area.x1(:x1)
    |> Area.y0(:y0)
    |> Area.y1(:y1)
    |> curve(ctx, &Area.curve/3)
    |> defined(rows, [:x0, :x1, :y0, :y1], &Area.defined/2)
    |> Area.generate_path(rows)
    |> Element.path()
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
    |> closed(ctx)
    |> Enum.map(fn rows ->
      path =
        Area.new()
        |> Area.x0(:x0)
        |> Area.x1(:x1)
        |> Area.y0(:y0)
        |> Area.y1(:y1)
        |> curve(ctx, &Area.curve/3)
        |> defined(rows, [:x0, :x1, :y0, :y1], &Area.defined/2)
        |> Area.generate_path(rows)

      child(Element.path(path), rows, %{}, last_point(rows, :x1, :y1))
    end)
  end

  # A closed loop (spec/14 §5.2, #393): the first row appended after the last at its angle
  # plus the sweep, so the closing segment runs forward round the ring — by the `closed`
  # option, else on a full turn over a categorical angle; a closed curve closes itself.
  defp closed(series, ctx) do
    if closed?(ctx) and not closed_curve?(ctx) do
      turn = turn(ctx)

      Enum.map(series, fn
        [first | _] = rows -> rows ++ [wrapped(first, turn)]
        empty -> empty
      end)
    else
      series
    end
  end

  defp closed?(%{frame: frame} = ctx) do
    case option(ctx, :closed, nil) do
      nil ->
        frame.kind == :polar and match?(%Visualize.Scale.Band{}, Map.get(frame.scales, :angle)) and
          full_turn?(ctx)

      closed ->
        closed == true
    end
  end

  defp closed_curve?(%{style_node: style_node}),
    do: Map.get(style_node, :curve) in [:cardinal_closed, :basis_closed]

  defp full_turn?(ctx) do
    {a0, a1} = sweep(ctx)
    abs(a1 - a0) >= 2 * :math.pi() - 1.0e-9
  end

  # What the closing row's angle advances by: the sweep in a polar frame, nothing else.
  defp turn(%{frame: %{kind: :polar}} = ctx) do
    {a0, a1} = sweep(ctx)
    a1 - a0
  end

  defp turn(_ctx), do: 0

  defp wrapped(row, turn) do
    for key <- [:x, :x0, :x1], is_number(Map.get(row, key)), reduce: row do
      acc -> Map.update!(acc, key, &(&1 + turn))
    end
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

  # The rows split by the `series` channel in order of first appearance: one path per
  # series (spec/14 §5.2); all the rows as one without the channel.
  defp series(rows, ctx) do
    if Channels.has?(ctx, :series) do
      rows
      |> Enum.map(& &1.series)
      |> Enum.uniq()
      |> Enum.map(fn value -> Enum.filter(rows, &(&1.series == value)) end)
    else
      [rows]
    end
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

  # In a polar frame a rule spans the r band — a spoke — or, given `y`, stands at that
  # radius across the sweep: a line in (angle, r) that the bend makes an arc (§5.2, #391).
  defp rule(%{frame: %{kind: :polar}} = ctx) do
    {r0, r1} = radii(ctx)
    {a0, a1} = sweep(ctx)

    if Channels.has?(ctx, :y) do
      rows = ctx |> Channels.pixels() |> Channels.placed([:y])

      Enum.map(rows, fn row ->
        line = Element.line(a0, row.y, a1, row.y, stroke_style(ctx, row.datum))
        %{element: line, datum: row.datum, style: %{}, anchor: nil}
      end)
    else
      rows = ctx |> Channels.pixels() |> Channels.placed([:x])

      elements =
        Rule.new()
        |> Rule.x(:x)
        |> Rule.y0(r0)
        |> Rule.y1(r1)
        |> Rule.label(label_accessor(ctx))
        |> Rule.generate(rows)

      rule_children(elements, rows, ctx)
    end
  end

  defp rule(ctx) do
    rows = ctx |> Channels.pixels() |> Channels.placed([:x])

    elements =
      Rule.new()
      |> Rule.x(:x)
      |> Rule.y0(0)
      |> Rule.y1(ctx.frame.plot.height)
      |> Rule.label(label_accessor(ctx))
      |> Rule.generate(rows)

    rule_children(elements, rows, ctx)
  end

  defp rule_children(elements, rows, ctx) do
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
    {y0, y1} = if ctx.frame.kind == :polar, do: radii(ctx), else: {0, ctx.frame.plot.height}

    elements =
      XBand.new()
      |> XBand.x0(:x0)
      |> XBand.x1(:x1)
      |> XBand.y0(y0)
      |> XBand.y1(y1)
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

  # The stroke keys of the mark's style and its paint — the series' colour with a `series`
  # channel (spec/14 §5.6, D-126) — bound to the datum, replacing the generator's
  # `current_color`.
  defp stroke_style(%{static: static, paint: {:stroke, paint}} = ctx, datum) do
    static
    |> Map.take(@stroke_keys)
    |> Map.put(:stroke, Series.over(ctx, datum, paint))
    |> Map.merge(Map.take(ctx.bound, @stroke_keys))
    |> Style.bind(datum, ctx.frame, ctx.mode)
  end

  defp fill_style(%{static: static, paint: {:fill, paint}} = ctx, datum) do
    static
    |> Map.take([:fill, :fill_opacity])
    |> Map.put(:fill, Series.over(ctx, datum, paint))
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

      %{
        element: Element.path(path),
        datum: row.datum,
        style: %{},
        anchor: anchor,
        radii: {inner, row.outer},
        span: a1 - a0
      }
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

  # -- needle ----------------------------------------------------------------------------

  # A pointer from the hub to the value's angle (spec/14 §5.2, #392): the angle already
  # in radians through the frame's scale, the length through `r` or the outer radius; the
  # pointer and its hub as one group per row, the label at the tip.
  defp needle(ctx) do
    inner = option(ctx, :inner_radius, 0)
    width = option(ctx, :width, 6)
    tail = option(ctx, :tail, 0)
    hub = option(ctx, :hub, width)
    cap = option(ctx, :cap, :point)
    {_r0, r1} = radii(ctx)
    rows = ctx |> Channels.pixels() |> Channels.placed([:x])

    generator =
      Needle.new()
      |> Needle.angle(:x)
      |> Needle.length(fn row -> Map.get(row, :y) || r1 end)
      |> Needle.inner_radius(inner)
      |> Needle.width(width)
      |> Needle.tail(tail)
      |> Needle.hub(hub)
      |> Needle.cap(cap)

    paths = Needle.generate_path(generator, rows)

    Enum.zip_with(paths, rows, fn path, row ->
      length = Map.get(row, :y) || r1

      %{
        element:
          Element.group([Element.path(path), Element.path(Needle.hub_path(generator, row))],
            style: %{class: "needle"}
          ),
        datum: row.datum,
        style: %{},
        anchor: {crisp(length * :math.sin(row.x)), crisp(-length * :math.cos(row.x))},
        radii: {inner, length}
      }
    end)
  end

  defp crisp(x) do
    case Float.round(x * 1.0, 6) do
      r when r == 0 -> 0.0
      r -> r
    end
  end

  # -- helpers ---------------------------------------------------------------------------

  @doc false
  @spec option(map(), atom(), term()) :: term()
  def option(%{options: options}, key, default), do: Map.get(options, key, default)

  @doc false
  # The plot's outer radius `R` (spec/14 §5.3).
  @spec outer_radius(map()) :: number()
  def outer_radius(%{frame: %{plot: plot}}), do: min(plot.width, plot.height) / 2

  # The r scale's range, the band a polar mark spans: `[0, R]` when the frame has none.
  defp radii(%{frame: frame} = ctx) do
    case Map.get(frame.scales, :r) do
      %{range: [r0, r1]} -> {min(r0, r1), max(r0, r1)}
      _none -> {0, outer_radius(ctx)}
    end
  end

  # The angle scale's range, the sweep: the full turn when the frame has none.
  defp sweep(%{frame: frame}) do
    case Map.get(frame.scales, :angle) do
      %{range: [a0, a1]} -> {a0, a1}
      _none -> {0, 2 * :math.pi()}
    end
  end
end
