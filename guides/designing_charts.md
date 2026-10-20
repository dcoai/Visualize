# Designing charts

A chart in visualize is a **design**: a plain nested map that names its data, its
coordinate frames, its marks and its labels, with no function anywhere in it. Because it is
data, a design can be stored, diffed, validated, sent as JSON, built by a tool and bound to
different rows. This guide is a tour of that declarative layer for someone meeting it for
the first time. Each topic is short, has an example you can paste into IEx, and ends with
the section of [the declarative chart spec](https://github.com/dcoai/Visualize/blob/main/spec/14-declarative-chart.md) that is its
contract.

Every example builds on the one before, so run them in order.

## A design is a map built from fragments

`Visualize.Chart.Build` is a module to import. Each of its functions returns a
**fragment**: a small design map that sets one thing and nothing else. A design is the fold
of its fragments through `Visualize.Chart.compose/1`.

```elixir
import Visualize.Chart.Build

readings = [
  %{t: ~U[2026-10-01 00:00:00Z], v: 99.1},
  %{t: ~U[2026-10-02 00:00:00Z], v: 99.7},
  %{t: ~U[2026-10-03 00:00:00Z], v: 98.4},
  %{t: ~U[2026-10-04 00:00:00Z], v: 99.9}
]

{:ok, design} =
  Visualize.Chart.compose([
    chart(meta: %{name: "Uptime"}),
    source(:uptime, [:t, :v]),
    cartesian(),
    time_scale(:x),
    linear_scale(:y, domain: [:auto, 100]),
    axis(:x, :bottom, ticks: 4),
    axis(:y, :left),
    line(:uptime, %{x: :t, y: :v}),
    title(["Uptime"])
  ])

design.marks
```

The result is just a map (`design.frames["main"].scales` is
`%{"x" => %{kind: :time}, "y" => %{kind: :linear, domain: [:auto, 100]}}`: a name the design
declares is a string, whichever spelling it was written in). The builder adds
only schema checks: a misspelled option raises `ArgumentError` at the call.

A design becomes a picture in three steps:

1. **Compose** the fragments into a design map. Nothing is validated yet.
2. **Apply** it to data with `Visualize.Chart.apply/2`. This validates the design, binds
   its sources to rows, resolves its variables and realizes its frames (infers domains,
   builds the scales). The result is a `Visualize.Chart.Applied`.
3. **Render** the applied chart with `Visualize.Chart.render/2`.

```elixir
{:ok, applied} = Visualize.Chart.apply(design, sources: %{uptime: readings}, size: {600, 300})

svg = Visualize.Chart.render(applied, root: true)
String.starts_with?(svg, "<svg")
```

`root: true` wraps the chart in an accessible `<svg>` document whose title is `meta.name`.
Leave it out to get a bare `<g>` for embedding in a template. A design records no size;
the render gives it (`size:`, `{600, 400}` by default).

For live data, `Visualize.Chart.compile/2` turns an applied chart into one
`Visualize.Chart.Compiled` per frame. A compiled chart splits static furniture from the
dynamic marks and draws each tick cheaply (see the LiveView guide).

`Visualize.Chart.from_map/1` and `Visualize.Chart.to_map/1` convert between the map and
the `%Visualize.Chart{}` struct; `Visualize.Chart.to_json/1` needs Jason.

Contract: [spec/14 §1](https://github.com/dcoai/Visualize/blob/main/spec/14-declarative-chart.md#1-the-map),
[§7.3](https://github.com/dcoai/Visualize/blob/main/spec/14-declarative-chart.md#73-application),
[§12](https://github.com/dcoai/Visualize/blob/main/spec/14-declarative-chart.md#12-compilation) and
[§16](https://github.com/dcoai/Visualize/blob/main/spec/14-declarative-chart.md#16-the-builder).

## Sources and typed columns

A source is a **slot**, not data: it names the fields the design reads. Rows arrive at
`apply/2` in a pool keyed by slot name, so one design draws any table with those fields.
A source can also give each field a type (`:time`, `:number`, `:category` or `:text`) and a
`default:` pool entry to bind when none has the slot's own name. Here the `:uptime` slot
is redeclared over the design with `Visualize.Chart.stack/1`, which lets a later layer
override a declaration (see "Composition" below):

```elixir
import Visualize.Chart.Build

typed =
  Visualize.Chart.stack([
    design,
    source(:uptime, [:t, :v], types: %{t: :time, v: :number}, default: :gitlab)
  ])

Visualize.Chart.column_type(typed, :uptime, :t)
```

The slot now binds to the pool entry `:gitlab` because no entry is named `:uptime`. Rows
can be a list of maps, a map of columns, a keyword list of columns, an Explorer frame or an
Nx tensor (anything `Visualize.Data.Table.rows/1` reads):

```elixir
columns = %{t: Enum.map(readings, & &1.t), v: Enum.map(readings, & &1.v)}
{:ok, _} = Visualize.Chart.apply(typed, sources: %{gitlab: columns})

# Every declared field must be in the rows.
{:error, [{[:sources, "uptime"], {:missing_field, "v"}}]} =
  Visualize.Chart.apply(typed, sources: %{gitlab: [%{t: ~U[2026-10-01 00:00:00Z]}]})
```

Contract: [spec/14 §2.3](https://github.com/dcoai/Visualize/blob/main/spec/14-declarative-chart.md#23-sources) and
[§7.2](https://github.com/dcoai/Visualize/blob/main/spec/14-declarative-chart.md#72-sources-as-slots).

## Frames

A frame is a coordinate system with its furniture: scales, axes, a legend and margins. The
kinds are `cartesian/1`, `polar/1`, `geo/1` and `facet/1`. A design holds its frames by
name. The one-frame builders all write the frame `:main`.

A **polar** frame maps `x` through its `angle` scale and `y` through `r`, and bends every
ordinary mark around the center. A **geo** frame takes a projection instead of position
scales.

Several frames are built with `in_frame/2`, which renames each fragment's frame and tags
its marks and labels. Place them with fractional `box:`es, or on a `layout/1` grid with
`cell:`. A frame with a higher `z` draws over the others, so an inset is a frame with a
small box, a `z` and a `background`.

```elixir
import Visualize.Chart.Build

{:ok, dashboard} =
  Visualize.Chart.compose(
    [chart(), source(:uptime, [:t, :v]), layout(columns: [3, 1], gap: 8)] ++
      in_frame(:history, [
        cartesian(cell: [0, 0]),
        time_scale(:x),
        linear_scale(:y),
        axis(:x, :bottom, ticks: 3),
        line(:uptime, %{x: :t, y: :v})
      ]) ++
      in_frame(:latest, [
        polar(cell: [1, 0]),
        linear_scale(:angle, domain: [95, 100], start: -120, sweep: 240),
        axis(:angle, :top, ticks: 5),
        # The newest reading only: a transform step (see "Data transforms" below).
        needle(take(from(:uptime), 1), %{x: :v})
      ]) ++
      in_frame(:inset, [
        cartesian(box: [0.08, 0.05, 0.25, 0.3], z: 1, background: :surface),
        # The history frame's x scale: one shared domain, this frame's own range.
        adopt(:x, :history),
        linear_scale(:y, domain: [0, 100]),
        axis(:y, :left, ticks: 2),
        area(:uptime, %{x: :t, y: :v})
      ])
  )

{:ok, applied} = Visualize.Chart.apply(dashboard, sources: %{uptime: readings})
Map.keys(applied.frames)
```

Contract: [spec/14 §4](https://github.com/dcoai/Visualize/blob/main/spec/14-declarative-chart.md#4-the-frame) (frames, boxes and
`z` in §4.2, kinds in §4.6) and [§2.8](https://github.com/dcoai/Visualize/blob/main/spec/14-declarative-chart.md#28-layout).

## Scales

A scale belongs to its frame and is declared by name, one function per kind:
`linear_scale/2`, `time_scale/2`, `log_scale/2`, `band_scale/2`, `ordinal_scale/2`,
`sequential_scale/2` and eight more (the cheatsheet lists them). Every kind has the
`_scale` suffix because `band` is also a mark.

Channels find their scale by name. In a cartesian frame `x`, `x0` and `x1` read `x`;
`y`, `y0` and `y1` read `y`; and `series` reads `color`. In a polar frame the position
scales are `angle` and `r`.

- `domain:` defaults to `:auto`, inferred from every channel that names the scale.
  `[0, :auto]` fixes the low end and infers the high one.
- `nice: true` rounds a continuous domain out to tidy ticks.
- `range:` defaults to the plot area. On a color scale it can name a color scheme.
- `adopt/2` shares another frame's scale: one domain over both frames' data, each frame
  with its own range.

```elixir
import Visualize.Chart.Build

{:ok, applied} =
  Visualize.Chart.apply(
    Visualize.Chart.stack([design, linear_scale(:y, domain: [0, :auto], nice: true)]),
    sources: %{uptime: readings}
  )

Visualize.Chart.Frame.scale(applied.frame, :y).domain
```

**Derived scales.** A channel whose scale the frame does not declare is read as raw
pixels. `Visualize.Chart.Builder.Scales.derive/2` returns the scales a design's channels
need and its frame lacks, each kind read from the column's type (time to `:time`, number
to `:linear`, category to `:band` or `:ordinal`). The chart builder uses it, and like the
builder it needs Phoenix.

```elixir
import Visualize.Chart.Build

{:ok, bare} =
  Visualize.Chart.compose([
    chart(),
    source(:uptime, [:t, :v], types: %{t: :time, v: :number}),
    cartesian(),
    line(:uptime, %{x: :t, y: :v})
  ])

Visualize.Chart.Builder.Scales.derive(bare, %{})
```

Contract: [spec/14 §4.3](https://github.com/dcoai/Visualize/blob/main/spec/14-declarative-chart.md#43-scales).

## Marks and channels

A mark binds fields of its data to channels. There is one builder per mark type:
`line/3`, `area/3`, `rect/3`, `circle/3`, `symbol/3`, `rule/3`, `band/3`, `x_band/3`,
`percentile_band/3`, `arc/3`, `rose/3`, `needle/3`, `path/3`, `text/3` and `tiles/3`.
Each one checks its channels against the type, so `line(:s, %{value: :v})` raises.

A channel's value is a field name, a constant number, `{:field, f}`, or
`{:scale, :min}` / `{:scale, :max}` for an end of the channel's scale's domain. Options
specific to a type (an arc's `inner_radius`, a rect's `corner_radius`) go under
`options:`.

**`series` works on every mark** (except `:percentile_band` and `:tiles`). It names the
group a row belongs to. On a `:line` or `:area` it also splits the rows into one path per
series. Either way, each element is painted its series' color and carries a
`data-series` attribute, so a legend toggle hides every mark of that series together:
the line and its dots below hide as one.

```elixir
import Visualize.Chart.Build

hosts = [
  %{t: 1, v: 3, host: "a"}, %{t: 2, v: 5, host: "a"}, %{t: 3, v: 4, host: "a"},
  %{t: 1, v: 2, host: "b"}, %{t: 2, v: 2, host: "b"}, %{t: 3, v: 6, host: "b"}
]

{:ok, by_host} =
  Visualize.Chart.compose([
    chart(),
    source(:load, [:t, :v, :host]),
    cartesian(),
    linear_scale(:x),
    linear_scale(:y, domain: [0, :auto]),
    ordinal_scale(:color, domain: ["a", "b"]),
    legend(:color),
    line(:load, %{x: :t, y: :v, series: :host}),
    circle(:load, %{x: :t, y: :v, series: :host}, options: %{radius: 4})
  ])

{:ok, applied} = Visualize.Chart.apply(by_host, sources: %{load: hosts})
Visualize.Chart.render(applied) =~ ~s(data-series="b")
```

Contract: [spec/14 §5.1–§5.3](https://github.com/dcoai/Visualize/blob/main/spec/14-declarative-chart.md#5-marks) (`series` in §5.2,
decision D-126 in [spec/13](https://github.com/dcoai/Visualize/blob/main/spec/13-decisions.md)).

## Axes, legends and labels

- `axis/3` draws a scale on a side: `ticks:` (a count or a list), `format:` (a
  `Visualize.Format` specifier such as `".1%"` or `"%H:%M"`), `unit:` and `grid: true`.
- `legend/2` explains a scale (usually `:color`): `position:`, `title:`, and
  `inside: false` to sit in the margin.
- `label/3` places a text in the frame at an anchor: `:title`, `:subtitle`, `:caption`,
  `{:axis, :y}` for an axis title, `{:frame, :top_left}` (or any corner, or `:center`),
  or `{:data, [x, y]}`. `title/2` is the `:title` anchor.
- A mark's `label:` option labels each datum (or each series' last point) from its own
  row, with `{:field, f}` in the text.

```elixir
import Visualize.Chart.Build

{:ok, annotated} =
  Visualize.Chart.compose([
    by_host,
    axis(:x, :bottom, ticks: 3),
    axis(:y, :left, ticks: 4, unit: "%", grid: true),
    label({:axis, :y}, ["load"]),
    label({:frame, :top_left}, ["two hosts"]),
    label(:caption, ["source: telemetry"]),
    text(:load, %{x: :t, y: :v}, label: %{text: [{:field, :v}], anchor: :top})
  ])

{:ok, _} = Visualize.Chart.apply(annotated, sources: %{load: hosts})
```

Contract: [spec/14 §4.4](https://github.com/dcoai/Visualize/blob/main/spec/14-declarative-chart.md#44-axes-and-tick-specs),
[§4.5](https://github.com/dcoai/Visualize/blob/main/spec/14-declarative-chart.md#45-legend),
[§5.5](https://github.com/dcoai/Visualize/blob/main/spec/14-declarative-chart.md#55-inline-label) and
[§6](https://github.com/dcoai/Visualize/blob/main/spec/14-declarative-chart.md#6-labels).

## Styles, themes and the style grammar

A color, a font or a curve lives in a **style** and nowhere else. `style/2` declares a
named style under `styles`, and a mark, axis, legend or label refers to it with
`style:`. A style is written in **parts**: `fill` and `stroke` (each a paint: a `type`,
then a `color` or gradient stops, then an `opacity`; a stroke adds its `width`, `dash`,
`join`, `cap` and `placement`), `font`, `text`, `effect`, `marker` and `curve`, beside
`opacity`, `blend` and `class` for the whole element. `fill: :series_1` is short for
`fill: %{type: :solid, color: :series_1}`, and `:none` is no paint. A value inside a part
can be a literal (`"#3b6fa8"`, `2`), a **theme slot** (`:series_1`, `:axis`,
`:background`, `:font_size`), `{:field, f}` read per datum (a color through the `color`
scale), a variable, or `:contrast` for text that stays readable on whatever it sits on. A
fill can be a gradient written in place (`%{type: :linear, color: [a, b]}`) or one declared
once with `gradient/3` and named with `paint/1`.

- `extends:` derives one style from another, such as a built-in (`:axis`, `:grid`,
  `:label`, `:title`). The parent's parts are kept key by key: `%{extends: :axis, stroke:
  %{width: 2}}` keeps the axis stroke's color.
- `style: [:series, :emphasis]` stacks styles at one site, the later winning, part by part.
  The theme's modifiers (`:bold`, `:italic`, `:thin`, `:thick`, `:dashed`, `:dotted`,
  `:outline`) each change one thing, to stack on a look: `[:bad, :outline]`.
- `theme/1` names the theme (`:default` or `:dark`) or gives one inline. Slots render as CSS
  custom properties in SVG (`var(--vis-series-1, …)`), so a stylesheet can re-theme a page,
  and as literal colors on a canvas.

```elixir
import Visualize.Chart.Build

{:ok, styled} =
  Visualize.Chart.compose([
    chart(),
    theme(:dark),
    source(:uptime, [:t, :v]),
    style(:series, stroke: %{color: :series_2, width: 2}, curve: :monotone_x),
    style(:heavy_title, extends: :title, font: %{size: 20}),
    gradient(:fade, :linear, stops: [{0, :series_2, 0.6}, {1, :series_2, 0}]),
    style(:under, fill: paint(:fade), stroke: :none),
    cartesian(),
    time_scale(:x),
    linear_scale(:y, domain: [95, 100]),
    area(:uptime, %{x: :t, y: :v, y0: {:scale, :min}}, style: :under),
    line(:uptime, %{x: :t, y: :v}, style: :series),
    title(["Uptime"], style: :heavy_title)
  ])

{:ok, applied} = Visualize.Chart.apply(styled, sources: %{uptime: readings})
Visualize.Chart.render(applied) =~ "var(--vis-series-2"
```

Contract: [spec/14 §3](https://github.com/dcoai/Visualize/blob/main/spec/14-declarative-chart.md#3-the-style-grammar),
[§2.5](https://github.com/dcoai/Visualize/blob/main/spec/14-declarative-chart.md#25-theme) and
[§2.7](https://github.com/dcoai/Visualize/blob/main/spec/14-declarative-chart.md#27-defs).

## Data transforms on a mark

Layouts, binning, stacking and aggregation are steps in a mark's data pipeline, not marks
of their own. `from/1` starts a data node from a source and each transform function
appends a step; the mark draws the rows the last step yields. There is one function per
op: data steps (`filter/3`, `bin/3`, `stack/3`, `fold/3`, `sum/3`, `sort/3`, `take/3`,
`window/3`, `lttb/4`, `m4/4`, `spectrum/3`), layouts (`treemap/2`, `tree/2`,
`sankey/4`, …) and geo algorithms (`projection/3`, `contour/4`, `hexbin/3`, …). The
positional arguments after the data are the op's required keys.

```elixir
import Visualize.Chart.Build

sales = [
  %{month: 1, apples: 10, pears: 4},
  %{month: 2, apples: 12, pears: 7},
  %{month: 3, apples: 9, pears: 11}
]

{:ok, transformed} =
  Visualize.Chart.compose([
    chart(),
    source(:sales, [:month, :apples, :pears]),
    cartesian(),
    linear_scale(:x),
    linear_scale(:y, domain: [0, :auto]),
    ordinal_scale(:color, domain: [:apples, :pears]),
    # Wide columns to stacked layers: one row per series per month, with y0 and y1.
    area(stack(from(:sales), [:apples, :pears]), %{x: :month, y: :y1, y0: :y0, series: :key}),
    # Long rows, then only the large ones, as dots.
    circle(
      from(:sales) |> fold([:apples, :pears], as: [:fruit, :n]) |> filter(:n, test: :gte, value: 10),
      %{x: :month, y: :n, series: :fruit}
    )
  ])

{:ok, _} = Visualize.Chart.apply(transformed, sources: %{sales: sales})
```

A domain is inferred from the transformed rows, so a stack's `y1` sets the `y` axis.

Contract: [spec/14 §5.4](https://github.com/dcoai/Visualize/blob/main/spec/14-declarative-chart.md#54-data-and-transforms) and
[§16.5](https://github.com/dcoai/Visualize/blob/main/spec/14-declarative-chart.md#165-data-nodes-and-transforms).

## Overlays: events, thresholds and the brush

What a dashboard draws over a chart is marks fed from sources, so every host that applies
the design draws them. An event at an instant is a `rule/3` at `x`, an event that lasted
an `x_band/3`, and a threshold a `rule/3` at `y`, a horizontal line across the plot. In a
cartesian frame both are cut to the plot, so an event that began before the window does
not cross the axis.

Color them by meaning, not by series. A mark's `scales: %{color: name}` gives it a color
scale of its own, so the lines keep their series' colors. An `:ordinal` scale whose
`range` is a map pins each severity to a role, which every theme draws in its own tones.
A feed's schema can supply that map, `range: fact(:events, :severity, :status)`, and a
target line, `y: fact(:primary, :latency, :target)`.

```elixir
import Visualize.Chart.Build

events = [
  %{at: 2, ends: nil, title: "deploy", severity: "info"},
  %{at: 0, ends: 1.5, title: "maintenance", severity: "warning"}
]

{:ok, overlaid} =
  Visualize.Chart.compose([
    chart(),
    source(:load, [:t, :v, :host]),
    source(:events, [:at, :ends, :title, :severity]),
    source(:limits, [:value, :severity]),
    cartesian(),
    linear_scale(:x),
    linear_scale(:y, domain: [0, :auto]),
    ordinal_scale(:severity, range: %{"info" => :info, "warning" => :warning, "critical" => :bad}),
    line(:load, %{x: :t, y: :v, series: :host}),
    rule(filter(from(:events), :ends, test: :absent), %{x: :at},
      scales: %{color: :severity},
      style: %{stroke: %{color: {:field, :severity}, dash: [3, 3]}},
      label: %{text: "\#{field(:title)}"}
    ),
    x_band(filter(from(:events), :ends, test: :present), %{x0: :at, x1: :ends},
      scales: %{color: :severity},
      style: %{fill: %{color: {:field, :severity}, opacity: 0.15}}
    ),
    rule(:limits, %{y: :value}, scales: %{color: :severity}, style: %{stroke: {:field, :severity}})
  ])

limits = [%{value: 5.5, severity: "critical"}]
pool = %{load: hosts, events: events, limits: limits}
{:ok, applied} = Visualize.Chart.apply(overlaid, sources: pool)
Visualize.Chart.render(applied) =~ "var(--vis-bad"
#=> true
```

A threshold feeds the `y` domain, so it is always in view. `polarity:` on a color scale over
a ramp (`range: {:ramp, :status}`) places the good end at the better end of the domain: a
`:threshold` scale at a feed's target with `polarity: fact(:primary, :latency, :polarity)`
colors a reading beyond the target `:bad`.

The brush belongs to the design too. With `interaction(brush: :x)` the chart writes its plot
area and its `x` mapping. `BrushHook` on a container around the rendered chart then pushes
`brush_select` with `"domain" => [lo, hi]` (milliseconds for a time `x`), so the handler
needs no margins and no scale to invert:

```elixir
Visualize.Chart.Build.interaction(brush: :x)
#=> %{interaction: %{brush: :x}}
```

Contract: [spec/14 §5.2](https://github.com/dcoai/Visualize/blob/main/spec/14-declarative-chart.md#52-types-and-channels),
[§4.3](https://github.com/dcoai/Visualize/blob/main/spec/14-declarative-chart.md#43-scales) and
[§2.9](https://github.com/dcoai/Visualize/blob/main/spec/14-declarative-chart.md#29-interaction); the hook in
[spec/10 §6.5](https://github.com/dcoai/Visualize/blob/main/spec/10-liveview-integration.md#65-the-designs-brush).

## Composition and validation

There are two ways to merge fragments, and they differ on purpose:

- `Visualize.Chart.compose/2` is a **union** of parts meant to be disjoint. Lists (marks,
  labels, axes) append, frames merge key by key, and a name two fragments declare
  differently is a `:conflict`.
- `Visualize.Chart.stack/1` is a **cascade** of layers meant to overlap, such as a house
  theme, a shared frame or a panel's overrides. The higher layer wins. A mark or label
  with the same `id:`, or an axis on the same `{scale, side}`, is replaced in place.
  `Visualize.Chart.explain/1` says which layer set each value, and
  `Visualize.Chart.free_vars/1` lists the variables still open.

```elixir
import Visualize.Chart.Build

{:ok, house} = Visualize.Chart.compose([theme(:dark), style(:series, stroke: %{width: 1})])
{:ok, panel} = Visualize.Chart.compose([style(:series, stroke: %{width: 3}), axis(:x, :bottom, ticks: 8)])

# The union refuses the second :series; the cascade takes the higher layer's word.
{:error, [{[:styles, "series"], :conflict}]} = Visualize.Chart.compose(house, panel)
%{stroke: %{width: 3}} = Visualize.Chart.stack([house, panel]).styles["series"]

Visualize.Chart.explain([{:house, house}, {:panel, panel}])
```

Derivation inside one style is `extends:` (above), not the cascade.

**Variables** make a design a template. `var/2` declares one with a default;
`Visualize.Chart.var/1` uses it anywhere a value can go; `apply/2` takes `vars:`.

```elixir
import Visualize.Chart.Build

{:ok, template} =
  Visualize.Chart.compose([
    design,
    var(:unit, "%"),
    label({:axis, :y}, ["uptime (", Visualize.Chart.var(:unit), ")"])
  ])

{:ok, applied} = Visualize.Chart.apply(template, sources: %{uptime: readings}, vars: %{unit: "pct"})
List.last(applied.chart.labels).text
```

**Composites** are what the chart builder stores. A composite is a fragment whose content
is a list of `Visualize.Chart.Use` sites, each referring to a stored fragment by id, with
a local override, a mask and variable bindings. `Visualize.Chart.flatten/2` resolves it
through any lookup function into a flat design:

```elixir
alias Visualize.Chart.Use

store = %{{:design, 1} => design, {:style, 1} => %{styles: %{series: %{stroke: %{width: 4}}}}}
uses = [Use.new({:design, 1}), %Use{id: {:use, 2}, ref: {:style, 1}}]
composite = %{composite: %{uses: uses, vars: %{}}}

{:ok, flat, %{missing: []}} = Visualize.Chart.flatten(composite, &Map.fetch(store, &1))
flat.styles["series"]
```

**Validation** happens at `Visualize.Chart.from_map/1` and `apply/2`. It reports every
fault at once as `{path, reason}`, and `Visualize.Chart.Validator.format/1` puts one into
words:

```elixir
import Visualize.Chart.Build

{:ok, broken} =
  Visualize.Chart.compose([
    chart(),
    source(:uptime, [:t, :v]),
    cartesian(),
    axis(:x, :bottom),
    line(:uptime, %{x: :t, y: :v}, style: :missing)
  ])

{:error, errors} = Visualize.Chart.from_map(broken)
Enum.map(errors, &Visualize.Chart.Validator.format/1)
```

Contract: [spec/14 §8](https://github.com/dcoai/Visualize/blob/main/spec/14-declarative-chart.md#8-composition-and-the-stack),
[§7](https://github.com/dcoai/Visualize/blob/main/spec/14-declarative-chart.md#7-variables-and-slots),
[§10](https://github.com/dcoai/Visualize/blob/main/spec/14-declarative-chart.md#10-validation),
[§17](https://github.com/dcoai/Visualize/blob/main/spec/14-declarative-chart.md#17-inspecting-a-stack) and
[§19](https://github.com/dcoai/Visualize/blob/main/spec/14-declarative-chart.md#19-typed-fragments-identity-use-sites-and-one-composer-at-every-level).

## Where next

- The [cheatsheet](https://hexdocs.pm/visualize/cheatsheet.html) has every builder function and a recipe for each
  common chart.
- The gallery in `examples/` has every chart as a design, with the builder calls that make
  it (`./run.sh` in `examples/`).
- [spec/14](https://github.com/dcoai/Visualize/blob/main/spec/14-declarative-chart.md) is the contract for the whole layer, with
  every key's type, default and merge rule.
