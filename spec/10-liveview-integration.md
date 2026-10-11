# LiveView Integration

**Status:** Implemented

Visualize reaches the browser through Phoenix LiveView in three ways: HEEx function components (`Visualize.Components`, `Visualize.Components.Tree`) that build a complete chart from assigns; JavaScript hooks — `Visualize.Hooks.Zoom` and `Visualize.Hooks.Brush` add zoom/pan and brush selection to any SVG and report back to the LiveView as events, and `Visualize.Hooks.Canvas`, `Visualize.Hooks.CanvasBinary` and `Visualize.Hooks.CanvasIncremental` replay the Canvas outputs of spec/09 on a `<canvas>`, `Visualize.Hooks.Resize` reports a container's size so the server can re-render at it, `Visualize.Hooks.Tooltip` shows a datum's fields under the pointer from attributes the server wrote, `Visualize.Hooks.Crosshair` snaps a rule and markers to the nearest x of an array the server wrote once, `Visualize.Hooks.Legend` hides a series from its legend entry, and `Visualize.Hooks.Builder` drags a layer of the chart builder into place and takes a click on an inspector row — with `Visualize.Hooks` bundling them into one installable file and re-exporting the server-side helpers; and the `Phoenix.HTML.Safe` implementations that let element structs be interpolated into a template directly. This document is the contract for each: every assign a component reads, every data attribute and event a hook uses, and the maths of the helpers.

## 1. Scope

### 1.1 Modules covered

| Module | Compiled when | Role |
|---|---|---|
| `Visualize.Components` | `Phoenix.Component` is loaded (the host has `phoenix_live_view`) | Line, bar, horizontal bar, pie, scatter, area and stacked bar chart components |
| `Visualize.Components.Tree` | `Phoenix.Component` is loaded (the host has `phoenix_live_view`) | Tree, treemap and sunburst components |
| `Visualize.Hooks` | always | JS bundle, install path, helper re-exports |
| `Visualize.Hooks.Zoom` | always | `ZoomHook` JS and transform helpers |
| `Visualize.Hooks.Brush` | always | `BrushHook` JS and selection helpers |
| `Visualize.Hooks.Canvas` | always | `CanvasChart` JS: Canvas command and script replay |
| `Visualize.Hooks.CanvasBinary` | always | `CanvasBinaryChart` JS and the shared binary decoder |
| `Visualize.Hooks.CanvasIncremental` | always | `CanvasIncrementalChart` JS: scroll-and-copy updates |
| `Visualize.Hooks.Resize` | always | `ResizeHook` JS: the container's size pushed to the LiveView once per settle |
| `Visualize.Hooks.Sync` | always | `VisualizeSync` JS: the bus a sync group's tooltips and crosshairs share hover over (4.3) |
| `Visualize.Hooks.Tooltip` | always | `TooltipHook` JS: a tooltip from the datum attributes of an element, with no round trip |
| `Visualize.Hooks.Crosshair` | always | `CrosshairHook` JS and the server-side `attrs/3`: a rule and markers snapped to the data over SVG or canvas |
| `Visualize.Hooks.Legend` | always | `LegendHook` JS: a legend entry hides and shows the series it names |
| `Visualize.Hooks.Builder` | always | `BuilderHook` JS: a layer dragged into place, an inspector row clicked |
| `Visualize.Chart.Builder` | `Phoenix.Component` is loaded (the host has `phoenix_live_view`) | The embeddable builder for a stack of design fragments (spec/14 §18) |
| `Visualize.Chart.Builder.Store` | `Phoenix.Component` is loaded | The behaviour a host's library of saved fragments implements |
| `Visualize.Chart.Builder.Preview` | `Phoenix.Component` is loaded | The builder's preview pane: the stacked design drawn, or its faults |
| `Visualize.Chart.Builder.Editor` | `Phoenix.Component` is loaded | The fragment editor: the nodes of a fragment, the widget of a type, and one form per node |
| `Visualize.Chart.Builder.Layers` | `Phoenix.Component` is loaded | The stack panel: the layers in precedence order, with select, move, disable and drag |
| `Visualize.Chart.Builder.Inspector` | `Phoenix.Component` is loaded | The inspector: `Visualize.Chart.explain/1` as a row per leaf path of the stack |
| `Visualize.Chart.Builder.Params` | `Phoenix.Component` is loaded | The parameters form: `Visualize.Chart.free_vars/1` as a control per variable still open |
| `Visualize.Chart.Builder.Document` | `Phoenix.Component` is loaded | Import and export: the design's JSON form, in and out |

Both component modules, and every module of the builder ([14-declarative-chart](14-declarative-chart.md) §18), are wrapped in `if Code.ensure_loaded?(Phoenix.Component)`. For that guard to be true in a host, `phoenix_live_view` MUST be a declared dependency of this library: Mix prunes the code path to a dependency's own declared deps while compiling it, so a guard over an undeclared module is always false in a host, whatever the host itself depends on. It is therefore declared `optional: true` (D-45): a host that has LiveView compiles the components, one that does not never fetches Phoenix, and `scripts/consumer_check.exs` proves the second claim on every pipeline ([12-testing-and-conformance](12-testing-and-conformance.md) §4). The library's own builds carry the optional dependency, so the components compile, are documented and are rendered under test here.

### 1.2 Conventions shared by every component

- Every component is a function component `name/1` taking an assigns map and returning rendered HEEx; it is used as `<.name … />` after `import Visualize.Components` (or `Visualize.Components.Tree`).
- Every component is a *preset design* of [14-declarative-chart](14-declarative-chart.md) §15 plus an assign mapping (D-64): the component's assigns go to `Visualize.Chart.Presets.design/2` for the design and to `Visualize.Chart.Presets.sources/2` for the rows its source binds to; `Visualize.Chart.Frame.new/2` realises the frame over them and `Visualize.Chart.Frame.generate/2` draws it, and the component prints the elements the layer returns in the markup this document declares — its HEEx template is the `<svg>` shell and the attribute order of each mark, nothing more. Every coordinate, path and paint below is therefore the layer's, and the render goldens of `test/support/components/` hold each component to what it drew before it was a preset.
- Every component declares its assigns with `attr/3`, so an unknown assign or a missing required one is a compile-time warning in the caller, and each listed default is applied by `Phoenix.Component`.
- Every component renders one `<svg width={width} height={height} role="img" viewBox="0 0 {width} {height}">`.
- `responsive` (`:boolean`, default `false`) is accepted by every component; when true the `<svg>` also carries `preserveAspectRatio="xMidYMid meet"` and `style="width:100%;height:auto"`, the CSS-scaled case of D-54, exactly as `Visualize.IR.Element.root/3` under `responsive: true` (spec/02 §2.1); when false neither attribute is present. The round-trip case is `ResizeHook` (§10) on the container, with the pushed size assigned to `width` and `height`.
- `class` (`:string`, default `nil`) is accepted by every component and placed on the `<svg>` as `class={class}`; when `nil` the attribute is absent.
- `title` and `description` (`:string`, default `nil`) are accepted by every component (D-56). When either is given, a `<title id>` and/or a `<desc id>` are the first children of the `<svg>`, and it carries `aria-labelledby` naming the title and `aria-describedby` the description (D-142; a description with no title is named by `aria-labelledby`), with the ids `Visualize.IR.Element.root/3` derives from the two texts (spec/02 §2.1); when neither is given no child and no `aria-labelledby` are present. Every chart SHOULD be given a title: without one a screen reader announces an unnamed image.
- `theme` (`:any`, default `nil`) is accepted by every component: a `Visualize.Theme` ([08-utilities](08-utilities.md) §7), `nil` meaning `Visualize.Theme.default/0`. Every colour, font and size a component draws with that is not an explicit assign is a slot of that theme resolved with `Visualize.Theme.resolve/3` in `:css` mode, so the markup carries `var(--vis-…, literal)` references a stylesheet can override (D-55) — save a label on a fill, the pie's and the sunburst's, which is inked by contrast with its element's fill as a literal (2.5, 3.4, D-123); the `<svg>` carries `font-family={resolve(:font_family)}` so every text inherits the theme's font; the axes take the theme through `Visualize.Axis.theme/2`. A colour assign (`fill`, `stroke`, `node_fill`, `node_stroke`, `link_stroke`) defaults to `nil`, which resolves to the slot named in the component's table; a string is used as given.
- `animate` (`:boolean`, default `false`) is accepted by every component; when true, every data mark carries `style="transition: all 0.3s ease-in-out;"` so DOM patches animate via CSS, the `<svg>`'s class gains `vis-animated`, and a `<style>` after the `<title>` and `<desc>` stops it for a reader who asks for less motion — `@media (prefers-reduced-motion: reduce) { svg.vis-animated * { transition: none !important; } }`, which beats the inline style (D-142, [14-declarative-chart](14-declarative-chart.md) §21.6); when false a mark carries no `style` attribute and there is no `<style>`.
- `margin` is merged over the component's default margin with `Map.merge/2`, so a partial map such as `%{left: 60}` overrides one side only. `inner_width = width − left − right`, `inner_height = height − top − bottom`, and the plot area is a `<g transform="translate(left, top)">`.
- Axes are the frame's (spec/14 §4.4) — byte for byte `Visualize.Axis.bottom/1` and `Visualize.Axis.left/1` over the realised scales, rendered with `Visualize.Render.to_string/2` — placed by the template into `<g class="x-axis" transform="translate(0, inner_height)">` and `<g class="y-axis">` through `Phoenix.HTML.raw/1`.
- `data` is `:any`: a row list, or any other source `Visualize.Data.Table.rows/1` accepts ([08-utilities](08-utilities.md) §6) — a column map, a keyword list of columns, an Explorer DataFrame. The component reads it through `rows/1` once, before anything else; a row list is used as given.
- Accessor assigns (`x`, `y`, `value`, `label`, `size`) are `:any` and hold one-argument functions applied to each row of `data`.
- Every computed coordinate and length prints through `Visualize.IR.Path.format_number/1` (at most four decimals, never `-0`), as the axes and paths already do; assigns such as `width` and `margin` print as given.
- Empty `data` renders the frame — the `<svg>` and, where the chart has them, its axes — with no marks; it never raises (1.3).

### 1.3 Scale and colour rules the components depend on

Every coordinate is the frame's scale applied by the mark that draws it (spec/14 §5.2), every path the generator the mark names (spec/14 §5.6, D-61), the axes section 1.2's. Three conventions are shared by every component that has the assign (D-45, D-64):

- **Colours.** A `colors` atom names a scheme of `Visualize.Scale.Color.schemes/0`; it is the `range` of the design's `color` scale, a `Visualize.Scale.Ordinal` over the mark indexes `0..n−1` (spec/14 §4.3), so the i-th mark takes the i-th colour and the list cycles when there are more marks than colours. A `colors` list is used the same way, as given. An unknown scheme atom raises `ArgumentError` naming `schemes/0`; an empty list raises `ArgumentError`.
- **Continuous domains.** Every domain is inferred by the frame from the whole bound column (spec/14 §4.3): the extent of the values, time values ordered chronologically, `[0, max]` where a table below says so. A domain whose ends coincide — one datum, or every value zero on a `[0, max]` axis — stays `[v, v]`: the frame never widens (D-60), the scale maps every value to the range midpoint (D-49) and the axis draws one tick, so a single datum sits mid-axis, as it does in d3. A line or an area over a band x scale sits at the band centres (spec/14 §5.2); a band domain is the distinct categories in order of first appearance, so a repeated category is one band.
- **Empty data.** With no data every continuous domain is `[0, 1]` and every band domain is `[]`, so the axes render with their `0…1` ticks (or bare domain line) and the chart draws no mark.

## 2. Visualize.Components

Each function is the preset of the same name in `Visualize.Chart.Presets` (spec/14 §15.3), drawn entirely by the layer: the frame's axes and labels and the preset's marks, whose elements the component prints as the tables below say. The preset's defaults are `Visualize.Chart.Presets.defaults/1`, which the `attr/3` declarations read.

### 2.1 Functions

| Function | Contract |
|---|---|
| `Visualize.Components.line_chart/1` | Renders a single-series line chart with bottom and left axes from `data`, `x` and `y` (2.2): the `line_chart` preset. |
| `Visualize.Components.bar_chart/1` | Renders vertical bars on a band x-scale and a linear y-scale from 0 (2.3): the `bar_chart` preset. |
| `Visualize.Components.horizontal_bar_chart/1` | Renders horizontal bars on a band y-scale and a linear x-scale from 0 (2.4): the `horizontal_bar_chart` preset. |
| `Visualize.Components.pie_chart/1` | Renders a pie or donut from `data` and `value`, with optional centroid labels (2.5): the `pie_chart` preset. |
| `Visualize.Components.scatter_plot/1` | Renders one circle per datum on two linear scales (2.6): the `scatter_plot` preset. |
| `Visualize.Components.area_chart/1` | Renders a filled area from the baseline plus its top line (2.7): the `area_chart` preset. |
| `Visualize.Components.stacked_bar_chart/1` | Renders one stacked bar per category from `keys` (2.8): the `stacked_bar_chart` preset. |

### 2.2 `line_chart/1`

| Assign | Type | Default | Meaning |
|---|---|---|---|
| `data` | `:any` | required | data points; MAY be empty (1.3) |
| `x` | `:any` | required | accessor to the x value: a `DateTime`, `NaiveDateTime` or `Date` (time scale), a number (linear scale) or anything else (band scale with padding 0.1) — decided by the first datum |
| `y` | `:any` | required | accessor to a numeric y value |
| `width` | `:integer` | `600` | |
| `height` | `:integer` | `400` | |
| `margin` | `:map` | `%{top: 20, right: 20, bottom: 30, left: 40}` | |
| `curve` | `:atom` | `:linear` | any curve type of spec/04 |
| `stroke` | `:string` | `nil` | line colour, also the point fill; `nil` → `:series_1` |
| `stroke_width` | `:integer` | `2` | |
| `show_points` | `:boolean` | `false` | draw an `r="4"` circle at each datum |
| `x_label` | `:string` | `nil` | centred `<text class="axis-label">` below the x axis at `y = inner_height + margin.bottom − 5`, filled `:text` at `:label_size` |
| `y_label` | `:string` | `nil` | rotated −90° `<text class="axis-label">` at `y = −margin.left + 15`, filled `:text` at `:label_size` |
| `animate`, `class`, `responsive`, `theme`, `title`, `description` | | | per 1.2 |

The y domain is the extent of the y values (1.3) with range `[inner_height, 0]`. The line is the preset's `:line` mark — `Visualize.Shape.Line` in `curve` through the frame's scales (spec/14 §5.6) — printed as the `d` of a `<path fill="none" stroke={stroke} stroke-width={stroke_width}>`, drawn only when `data` is non-empty; the points are its `:circle` mark; the axis titles are the frame's labels at `{:axis, :x}` and `{:axis, :y}` (spec/14 §6.3); the axes and labels are drawn regardless.

### 2.3 `bar_chart/1`

| Assign | Type | Default | Meaning |
|---|---|---|---|
| `data` | `:any` | required | MAY be empty (1.3) |
| `x` | `:any` | required | accessor to the category |
| `y` | `:any` | required | accessor to a non-negative number |
| `width` | `:integer` | `600` | |
| `height` | `:integer` | `400` | |
| `margin` | `:map` | `%{top: 20, right: 20, bottom: 30, left: 40}` | |
| `fill` | `:string` | `nil` | `nil` → `:series_1` |
| `padding` | `:float` | `0.1` | band padding 0–1 |
| `animate`, `class`, `responsive`, `theme`, `title`, `description` | | | per 1.2 |

x is a band scale over the categories in data order with range `[0, inner_width]`; y is linear over `[0, max(y)]` — `[0, 1]` when there is no datum (1.3) — with range `[inner_height, 0]`. Each datum is a `<rect x={band start} y={scaled y} width={bandwidth} height={inner_height − scaled y} fill={fill}>`.

### 2.4 `horizontal_bar_chart/1`

Same assigns as 2.3 with `margin` defaulting to `%{top: 20, right: 20, bottom: 30, left: 100}`, and the roles swapped: `y` is the category accessor (band scale, range `[0, inner_height]`), `x` the numeric accessor (linear over `[0, max(x)]`, range `[0, inner_width]`). Each datum is a `<rect x="0" y={band start} width={scaled x} height={bandwidth} fill={fill}>`. The axes are still `Axis.bottom(x_scale)` and `Axis.left(y_scale)`.

### 2.5 `pie_chart/1`

| Assign | Type | Default | Meaning |
|---|---|---|---|
| `data` | `:any` | required | |
| `value` | `:any` | required | accessor to the slice value |
| `label` | `:any` | `nil` | accessor to the label text; labels are drawn only when both `show_labels` and `label` are set |
| `width` | `:integer` | `400` | |
| `height` | `:integer` | `400` | |
| `inner_radius` | `:integer` | `0` | `> 0` makes a donut |
| `outer_radius` | `:integer` | `nil` | `nil` → `min(width, height)/2 − 10` |
| `pad_angle` | `:float` | `0.02` | radians between slices |
| `colors` | `:any` | `:category10` | scheme atom or explicit colour list; the i-th slice takes the i-th colour (1.3) |
| `show_labels` | `:boolean` | `true` | |
| `animate`, `class`, `responsive`, `theme`, `title`, `description` | | | per 1.2 |

Slices are the preset's `:arc` mark — `Visualize.Shape.Pie` over `value` with `pad_angle`, then `Visualize.Shape.Arc` (spec/14 §5.6) — each a `<path d={arc} fill={colour} stroke={:background} stroke-width="2">` inside `<g transform="translate(width/2, height/2)">`; with no data the group is empty. A label is a `<text text-anchor="middle" dominant-baseline="middle" font-size={:label_size} fill={ink}>` at `Visualize.Shape.Arc.centroid/2` of the slice — the mid-radius `(inner + outer)/2` at the slice's mid angle, which is the D3 convention `x = r·sin(a)`, `y = −r·cos(a)`. Its `ink` is the preset's `:contrast` (spec/14 §15.3, D-123): the theme's `text` or `background`, whichever reads on that slice's fill, as a literal — the one colour a component draws that is not a `var(--vis-…)` reference (1.2), because it is chosen between literals. A slice too narrow for its whole label at the label's radius, by the layer's estimate of 0.6 em a character (spec/14 §5.5), draws no label (`fit: :hide`). The labels follow every slice in the group, in slice order, as the layer draws a labelled mark (#494).

### 2.6 `scatter_plot/1`

| Assign | Type | Default | Meaning |
|---|---|---|---|
| `data` | `:any` | required | MAY be empty (1.3) |
| `x`, `y` | `:any` | required | numeric accessors; both scales are linear over the value extents (1.3) |
| `width` | `:integer` | `600` | |
| `height` | `:integer` | `400` | |
| `margin` | `:map` | `%{top: 20, right: 20, bottom: 30, left: 40}` | |
| `fill` | `:string` | `nil` | `nil` → `:series_1` |
| `size` | `:any` | `5` | a number (radius) or a one-argument function of the datum returning the radius |
| `animate`, `class`, `responsive`, `theme`, `title`, `description` | | | per 1.2 |

Each datum is a `<circle cx cy r={size} fill={fill} opacity="0.7">`. Unlike `line_chart/1`, the x scale is always linear, so `x` MUST return numbers.

### 2.7 `area_chart/1`

| Assign | Type | Default | Meaning |
|---|---|---|---|
| `data` | `:any` | required | MAY be empty (1.3) |
| `x` | `:any` | required | as in 2.2 (time, linear or band by first datum) |
| `y` | `:any` | required | numeric; y domain is `[0, max(y)]` as in 2.3 |
| `width` | `:integer` | `600` | |
| `height` | `:integer` | `400` | |
| `margin` | `:map` | `%{top: 20, right: 20, bottom: 30, left: 40}` | |
| `fill` | `:string` | `nil` | area fill; `nil` → `:series_1` |
| `fill_opacity` | `:float` | `0.3` | |
| `stroke` | `:string` | `nil` | top-line colour; `nil` → `:series_1` |
| `stroke_width` | `:integer` | `2` | |
| `curve` | `:atom` | `:linear` | applied to both the area and the line |
| `animate`, `class`, `responsive`, `theme`, `title`, `description` | | | per 1.2 |

Two paths are drawn when `data` is non-empty: the preset's `:area` mark (`Visualize.Shape.Area` from the y scale's zero, spec/14 §5.6) as `<path fill={fill} fill-opacity={fill_opacity}>`, then its `:line` mark as `<path fill="none" stroke={stroke} stroke-width={stroke_width}>`.

### 2.8 `stacked_bar_chart/1`

| Assign | Type | Default | Meaning |
|---|---|---|---|
| `data` | `:any` | required | one map per category; MAY be empty (1.3) |
| `x` | `:any` | required | accessor to the category, applied to each point's `data` |
| `keys` | `:list` | required | the series keys read from each datum by `Visualize.Shape.stack/0` |
| `width` | `:integer` | `600` | |
| `height` | `:integer` | `400` | |
| `margin` | `:map` | `%{top: 20, right: 20, bottom: 30, left: 40}` | |
| `colors` | `:any` | `:category10` | scheme atom or colour list, one per key in order (1.3) |
| `padding` | `:float` | `0.1` | |
| `animate`, `class`, `responsive`, `theme`, `title`, `description` | | | per 1.2 |

The preset's `:stack` transform yields one row per key per datum with `key`, `y0` and `y1` (spec/14 §5.4.1); the y domain is `[0, max(y1)]`, `[0, 1]` when there are no points (1.3). Each point is a `<rect x={band of x.(data)} y={scaled y1} width={bandwidth} height={scaled y0 − scaled y1} fill={series colour}>`.

## 3. Visualize.Components.Tree

### 3.1 Functions

| Function | Contract |
|---|---|
| `Visualize.Components.Tree.tree_diagram/1` | Renders a node-link tree from nested data using the tidy tree layout (3.2): the `tree_diagram` preset. |
| `Visualize.Components.Tree.treemap_chart/1` | Renders a treemap of the hierarchy's leaves coloured by the child of the root above each (3.3): the `treemap_chart` preset. |
| `Visualize.Components.Tree.sunburst_chart/1` | Renders a radial partition with one arc per non-root node of positive value, labelled (3.4): the `sunburst_chart` preset. |

Each function is the preset of the same name in `Visualize.Chart.Presets` (spec/14 §15.4), drawn by the layer as the components of §2 are: the assign mapping flattens the nested map into one row per node (spec/14 §15.2), the preset's transforms — `:tree`, `:treemap` or `:partition` over `Visualize.Layout.Hierarchy.stratify/2`, then the `:filter` steps that keep the rows this section draws — yield the laid-out rows, the marks draw them through `Visualize.Chart.Frame.generate/2`, and the component prints the markup below from the elements it returns, reading the rows (`Visualize.Chart.Mark.rows/3`) beside them for what depends on the node: the tree's node group (D-70). The treemap's and the sunburst's labels are their marks', fitted and inked by the layer (3.3, 3.4, #494, #497). `data` MUST be a map whose children are under `:children` or `"children"`; node labels default to `:name` or `"name"`, leaf values to `:value` or `"value"` (missing → 0). A root-only hierarchy is the empty case: the tree draws its one node, the treemap one cell, the sunburst no arc. `colors` follows 1.3 with one rule for which mark takes which index: the i-th child of the root takes the i-th colour and every descendant of that child inherits it, so a whole top-level branch shares a colour however deep it goes (D-46) — the design's `color` scale over the row's `branch`, bound through `Visualize.Chart.Style.bind/4`; the root itself, where drawn, is the theme's `:grid`. Coordinates print as in 1.2.

### 3.2 `tree_diagram/1`

| Assign | Type | Default | Meaning |
|---|---|---|---|
| `data` | `:map` | required | nested map |
| `width` | `:integer` | `800` | |
| `height` | `:integer` | `600` | |
| `margin` | `:map` | `%{top: 20, right: 120, bottom: 20, left: 120}` | merged over that default |
| `orientation` | `:atom` | `:horizontal` | `:horizontal` (root at left, depth along x) or `:vertical` (root at top) |
| `node_radius` | `:integer` | `6` | |
| `node_fill` | `:string` | `nil` | fill of leaf circles; `nil` → `:background` |
| `node_stroke` | `:string` | `nil` | circle stroke; also the fill of internal nodes; `nil` → `:series_1` |
| `link_stroke` | `:string` | `nil` | `nil` → `:grid` |
| `label` | `:any` | `nil` | accessor of a node's `data`; `nil` → `:name`/`"name"` |
| `animate`, `class`, `responsive`, `theme`, `title`, `description` | | | per 1.2 |

Layout is `Visualize.Layout.Tree` sized `[inner_height, inner_width]` for horizontal and `[inner_width, inner_height]` for vertical. Links are cubic Béziers between parent and child with both control points at the midpoint of the depth axis, `fill="none" stroke={link_stroke} stroke-width="1.5"`, drawn before the nodes. Each link is the `:path` mark's element — the row's `path` of the `:tree` transform, the link of the design's orientation (spec/14 §5.4.2, D-70) — and its `d` is `Visualize.IR.Path.to_string/1` of that path, the one `d` serialiser of spec/02 §2.2 (D-34): commands concatenated, coordinates comma-separated, `M0,280C140,280,140,70,280,70`, never a form of the component's own (D-71). Each node is a `<g transform="translate(…)">` (horizontal swaps the layout's `x`/`y`) holding a `<circle r={node_radius} stroke={node_stroke} stroke-width="2">` filled `node_stroke` for an internal node and `node_fill` for a leaf (a node whose `children` is `nil` or `[]`), and a `<text dy="0.31em" font-size={:label_size} fill={:text}>`: horizontal labels sit at `x = −10` with `text-anchor="end"` for internal nodes and `x = 10`/`"start"` for leaves; vertical labels are centred at `x = 0`. A root-only hierarchy is one node at the origin of the plot area and no link.

### 3.3 `treemap_chart/1`

| Assign | Type | Default | Meaning |
|---|---|---|---|
| `data` | `:map` | required | nested map with leaf values |
| `width` | `:integer` | `800` | |
| `height` | `:integer` | `600` | |
| `value` | `:any` | `nil` | leaf value accessor; `nil` → `:value`/`"value"` (missing → 0) |
| `label` | `:any` | `nil` | as 3.2 |
| `tile` | `:atom` | `:squarify` | any `Visualize.Layout.Treemap.tile/2` algorithm (spec/06) |
| `padding` | `:integer` | `2` | uniform cell padding |
| `colors` | `:any` | `:category10` | scheme atom or colour list, by child of the root (3.1); the root itself, drawn only when it is the whole hierarchy, takes `:grid` |
| `animate`, `class`, `responsive`, `theme`, `title`, `description` | | | per 1.2 |

The hierarchy is summed with `value`, laid out with `Visualize.Layout.Treemap` at `{width, height}`, and only leaves are drawn, in hierarchy order: `<rect x={x0} y={y0} width={max(0, x1−x0)} height={max(0, y1−y0)} fill={colour} stroke={:background} stroke-width="1">`. A zero-valued leaf keeps its zero-area cell (D-41). A label is a `<text x y dy="0.32em" text-anchor="middle" font-size={:label_size} fill={ink}>` at the centre of its cell — the preset's mark label, `anchor: :middle` (spec/14 §5.5) — `ink` the preset's `:contrast` against the cell's fill as for the pie (2.5), and fitted by the layer (`fit: :truncate`): cut with `…` to the characters that fit the cell's width at 0.6 em a character, and not drawn when not even one character does or when the cell is shorter than the label's font size, so a zero-area cell has none (spec/14 §5.5, #497). The labels follow every cell, in cell order (#494). The root-only cell's fill in the layer is `:none` (D-122), so its label is inked against the background — on both built-in themes the theme's `text`, 9.6:1 against the `:grid` the component fills that cell with. Until #497 the component kept its own rule — a `fill={:background}` label with a text shadow at `(x0 + 4, y0 + 14)` in a cell wider than 30 and taller than 15, cut to `trunc((cell width − 8) / 7)` characters — the white-on-a-pale-fill defect D-123 names, which the shadow only half hid; the layer's fit replaced the rule and `:contrast` the ink, as #494 did for the pie and the sunburst. A root-only hierarchy is one cell the size of the `<svg>`.

### 3.4 `sunburst_chart/1`

| Assign | Type | Default | Meaning |
|---|---|---|---|
| `data` | `:map` | required | |
| `width` | `:integer` | `600` | |
| `height` | `:integer` | `600` | |
| `value` | `:any` | `nil` | as 3.3 |
| `label` | `:any` | `nil` | as 3.2; drawn at the arc's centroid when the arc can hold text (below) |
| `colors` | `:any` | `:category10` | as 3.3 |
| `animate`, `class`, `responsive`, `theme`, `title`, `description` | | | per 1.2 |

The radius is `min(width, height)/2`. The summed hierarchy is laid out by `Visualize.Layout.Partition` sized `{2π, radius}` (spec/06 §4): the root spans `[0, 2π]`, each child a share of its parent's arc proportional to its summed value, and a node whose value is not positive a zero-width slot (D-41); ring radii are `depth / (height + 1) · radius` with `height` the root's. Every node of depth ≥ 1 whose angular extent is positive is a `<path fill={colour} stroke={:background} stroke-width="1">` whose `d` is `Visualize.Shape.Arc` with `x0`/`x1` as the start and end angles — clockwise from 12 o'clock, the arc's own convention (spec/04 §7) — and `y0`/`y1` as the inner and outer radii, inside `<g transform="translate(width/2, height/2)">`. The root is not drawn, and a zero-extent node draws nothing. A label is a `<text text-anchor="middle" dominant-baseline="middle" font-size={:label_size} fill={ink}>` at `Visualize.Shape.Arc.centroid/2` of the arc, `ink` the preset's `:contrast` against the arc's fill as for the pie (2.5), and fitted by the layer (`fit: :truncate`, spec/14 §5.5): cut with `…` to the characters that fit the arc's length at mid-radius, `(x1 − x0) · (y0 + y1) / 2`, at 0.6 em a character, and not drawn when not even one character does. The labels follow every arc in the group, in arc order (#494). Until #494 the component kept its own rule — thicker than 15, longer than 30, `trunc((length − 8) / 7)` characters — and inked `:background`; the layer's fit replaced the one and `:contrast` the other, so a sunburst's label reads and fits by the same rule as every other mark label.

## 4. Visualize.Hooks

### 4.1 Functions

| Function | Contract |
|---|---|
| `Visualize.Hooks.js_code/0` | Returns the complete ES-module source: a header comment, `ZoomHook`, the sync bus `VisualizeSync` (`Visualize.Hooks.Sync.js_bus/0`, 4.3) — before every hook that uses it — `BrushHook`, the binary decoder (`Visualize.Hooks.CanvasBinary.js_decoder/0`), `CanvasChart`, `CanvasBinaryChart`, `CanvasIncrementalChart`, `ResizeHook`, `TooltipHook`, `CrosshairHook`, `LegendHook`, `BuilderHook`, `KeyboardHook`, then one `export default { … }` object listing the eleven hooks — each name is exported exactly once (D-40, D-48). |
| `Visualize.Hooks.Sync.js_bus/0` | Returns the source of `const VisualizeSync = {…}`, the bus of 4.3 that `TooltipHook`, `CrosshairHook` and `BrushHook` share. It is not exported: it is the hooks' own, and a host joins a group through a design key, not through it. |
| `Visualize.Hooks.default_path/0` | Returns `"assets/js/visualize_hooks.js"`, relative to the current working directory. |
| `Visualize.Hooks.install!/0` | Creates the directory of `default_path/0` and overwrites that file with `js_code/0`; returns `{:ok, path}`; raises `File.Error` on failure. |
| `Visualize.Hooks.transform_point/2` | Delegates to `Visualize.Hooks.Zoom.transform_point/2`. |
| `Visualize.Hooks.inverse_transform_point/2` | Delegates to `Visualize.Hooks.Zoom.inverse_transform_point/2`. |
| `Visualize.Hooks.identity_transform/0` | Delegates to `Visualize.Hooks.Zoom.identity_transform/0`. |
| `Visualize.Hooks.scale_transform/3` | Delegates to `Visualize.Hooks.Zoom.scale_transform/3`. |
| `Visualize.Hooks.translate_transform/3` | Delegates to `Visualize.Hooks.Zoom.translate_transform/3`. |
| `Visualize.Hooks.filter_selection/3` | Delegates to `Visualize.Hooks.Brush.filter_selection/3`: the data within the selection on the axes whose scale is given (6.3). |
| `Visualize.Hooks.selection_to_domain/2` | Delegates to `Visualize.Hooks.Brush.selection_to_domain/2`: a `{start, stop}` pair for a one-axis brush, the four-key map for both axes (6.3). |

### 4.2 Installation contract

The host application writes the bundle (`install!/0`, or `File.write!/2` of `js_code/0`), imports the hooks it uses (or the default export) from it, and registers them in the `hooks:` option of `LiveSocket`. `install!/0` is the supported programmatic path; no Mix task ships. The bundle is one ES module: the decoder functions the canvas hooks call are defined before them and exported, so a host MAY import `executeVisualizeBinary` for its own hooks. `test/visualize/hooks/canvas_hooks_test.exs` holds the bundle to this shape.

### 4.3 The sync bus

**Implemented** (#466, D-116; the brush #467, D-117). Charts in one **sync group** share hover and the brush. A design joins one with `interaction: %{sync: "<group>"}` ([14-declarative-chart](14-declarative-chart.md) §2.9), and the markup then carries `data-vis-sync` and `data-vis-sync-x`. `TooltipHook` (12.4), `CrosshairHook` (13.4) and `BrushHook` (6.4) honour them with no host JavaScript, through one bus defined once in the bundle, `VisualizeSync`. The bus is plain DOM `CustomEvent`s on `document`, with no library.

**Membership.** A hook element is a member when it carries `data-vis-sync`, or else when its first descendant with `data-vis-sync` does. That element's `data-vis-sync-x` must hold five numbers, `d0,d1,x0,x1,width`: the x domain, the chart pixels of its two ends, and the chart's `viewBox` width. An element without them, or with a malformed `data-vis-sync-x`, is in no group and the hook behaves exactly as without the bus. A hook reads its membership on `mounted()` and again on `updated()`.

**The event.** Its name is `vis:sync:<group>`, and its `detail` is `{x, source}`:

- `x` is the pointer's x in the domain units of `data-vis-sync-x`: the number itself for a linear scale, milliseconds since the Unix epoch for a time scale. `null` clears the group.
- `source` is the hook element that published it.

**Publishing.** A member publishes on a pointer move over its own element. The chart x is `(clientX − rect.left) · width / rect.width`, with `rect` the hook element's bounding rectangle, and the value is `d0 + (chartX − x0) / (x1 − x0) · (d1 − d0)`. `mouseleave` and `touchend` publish `x: null`, and so does the crosshair when the pointer leaves the plot area. A clear is published once, after a hover the chart published, so a pointer moving through a margin does not flood the bus.

**Receiving.** A member ignores an event whose `source` is its own element, contains it, or is contained by it. Such an event comes from the same chart, from itself or from the other hook on it, and the chart has already drawn from its own pointer. Any other member does this:

- `null` hides what the hook drew for the group.
- A value outside `[min(d0, d1), max(d0, d1)]` hides it too: a member whose domain does not contain the value draws nothing.
- Any other value is mapped to the member's own chart x, `x0 + (x − d0) / (d1 − d0) · (x1 − x0)`, or the midpoint of `x0` and `x1` for a collapsed domain. The hook draws there.

So members may differ in width, margin and domain. A received hover never publishes and never calls `pushEvent`: one hover is one event on the bus, and only the chart under the pointer talks to its server.

**The brush event** (#467, D-117). A brush travels on its own event, `vis:sync-brush:<group>`, so a crosshair or a tooltip never hears one and a brush never hears a hover. The prefix differs from the hover's rather than extending it, so no group name can spell another group's brush event. Its `detail` is `{extent, source}`:

- `extent` is `[lo, hi]`, the brushed x extent in the same domain units as a hover's `x`, with `lo ≤ hi`. `null` clears the group's band.
- `source` is the brush's hook element, and a member ignores its own echo by the same rule as a hover.

A member maps a received extent through its own five numbers, **clipped to its domain**. With `[m0, m1] = [min(d0, d1), max(d0, d1)]`, the clipped extent is `[max(lo, m0), min(hi, m1)]`. When that is empty (`max(lo, m0) > min(hi, m1)`), the extent and the domain are disjoint and the member shows no band. Otherwise both ends map through `toChart`, and the band spans the two chart x values, the smaller first. An extent that covers the whole domain fills it. One that touches the domain at a single value is a band of zero width.

| Function of `VisualizeSync` | Does |
|---|---|
| `read(el)` | the membership of an element: `{group, d0, d1, x0, x1, width}`, or `null` |
| `eventName(group, channel)` | `'vis:sync:' + group` for a hover, the `channel` omitted; `'vis:sync-brush:' + group` for `channel` `'brush'` |
| `toDomain(sync, chartX)` | the domain value at a chart x |
| `toChart(sync, x)` | the chart x of a domain value, or `null` outside the domain or for `null` |
| `toChartExtent(sync, extent)` | the chart x pair `[c0, c1]`, `c0 ≤ c1`, of an extent clipped to the domain; `null` for a `null` extent or one disjoint from the domain |
| `publish(sync, source, x)` | dispatches a hover on `document` |
| `publishBrush(sync, source, extent)` | dispatches a brush on `document` |
| `attach(hook, channel)` | reads `hook.el`, keeps `hook.sync`, and moves the hook's `onSync` listener to the group's event of that channel |
| `detach(hook)` | removes the listener |
| `own(el, source)` | whether an event from `source` is the element's own echo |

**Lifecycle.** Each hook binds its listener once and keeps the reference (D-47). `updated()` moves the listener to the new event name when the group changed and removes it when the element left its group. `destroyed()` removes it. A remounted hook therefore listens once, and a destroyed one hears nothing.

`test/visualize/hooks/executed_hooks_test.exs` executes all of this (spec/12 §6): three crosshairs of different widths in one group and a tooltip in it, a chart outside the group, a member whose domain does not hold the value, a clear, and teardown and remount; and three brushes of different widths in one group, one brushed (6.4).

## 5. Visualize.Hooks.Zoom

### 5.1 Functions

| Function | Contract |
|---|---|
| `Visualize.Hooks.Zoom.js_hook/0` | Returns the source of `export const ZoomHook = {…}` (5.2). |
| `Visualize.Hooks.Zoom.transform_point/2` | `transform_point({x, y}, %{k:, x: tx, y: ty})` returns `{x·k + tx, y·k + ty}`: data space to screen space. |
| `Visualize.Hooks.Zoom.inverse_transform_point/2` | `inverse_transform_point({x, y}, %{k:, x: tx, y: ty})` returns `{(x − tx)/k, (y − ty)/k}`: screen space to data space. |
| `Visualize.Hooks.Zoom.identity_transform/0` | Returns `%{k: 1, x: 0, y: 0}`. |
| `Visualize.Hooks.Zoom.scale_transform/3` | `scale_transform(t, s, {cx, cy})` returns `%{k: t.k·s, x: cx − (cx − t.x)·s, y: cy − (cy − t.y)·s}`: zoom by factor `s` about the screen point `{cx, cy}`. |
| `Visualize.Hooks.Zoom.translate_transform/3` | `translate_transform(t, dx, dy)` returns `%{k: t.k, x: t.x + dx, y: t.y + dy}`. |

A transform is a map with exactly the keys `k` (scale), `x` and `y` (translation, in screen pixels), and corresponds to the SVG attribute `translate(x, y) scale(k)`.

### 5.2 `ZoomHook` behaviour

Attach with `phx-hook="ZoomHook"` and an `id` on an `<svg>` (or any element) that contains the content to transform, and set `phx-update="ignore"` on it so LiveView does not overwrite the client-side transform.

Data attributes read on `mounted()`:

| Attribute | Default | Meaning |
|---|---|---|
| `data-min-zoom` | `0.1` | lower bound on `k` (a value that parses to `0` also falls back to the default) |
| `data-max-zoom` | `10` | upper bound on `k` |
| `data-zoom-event` | `"zoom"` | name of the event pushed to the LiveView |
| `data-disable-wheel` | unset | `"true"` disables wheel zoom |
| `data-disable-drag` | unset | `"true"` disables mouse and touch panning |

On `updated()` the hook reads `data-transform-k`, `data-transform-x`, `data-transform-y`; when all three parse as numbers it adopts them as the current transform and re-applies it, which is how the server pushes a transform to the client.

The transformed container is the first descendant matching `.zoom-container`, or the element's first child when none matches. The hook sets its `transform` attribute to `translate(x, y) scale(k)` on mount and after every change.

Interaction:

- Wheel (unless disabled; `preventDefault` is called): with the pointer at `(mx, my)` relative to the element's bounding box, `k' = clamp(k · (1 − 0.001·deltaY), min, max)`, then `x' = mx − (mx − x)·(k'/k)`, `y' = my − (my − y)·(k'/k)` — a zoom about the pointer, identical to `scale_transform/3` with `s = k'/k`. The event is pushed after every wheel step.
- Drag (left button only, or a single touch): the translation follows the pointer; the cursor becomes `grabbing` while dragging and `grab` afterwards; the event is pushed once on release (mouseup, mouseleave or touchend), not during the drag.

Event: `pushEvent(eventName, {k, x, y})`, arriving in the LiveView as `handle_event("zoom", %{"k" => k, "x" => x, "y" => y}, socket)` with JSON numbers. `destroyed()` performs no clean-up.

## 6. Visualize.Hooks.Brush

### 6.1 Functions

| Function | Contract |
|---|---|
| `Visualize.Hooks.Brush.js_hook/0` | Returns the source of `export const BrushHook = {…}` (6.2). |
| `Visualize.Hooks.Brush.filter_selection/3` | Keeps the data whose scaled coordinates lie within the selection on every axis whose scale is given, bounds inclusive (6.3). |
| `Visualize.Hooks.Brush.selection_to_domain/2` | Inverts the selection edges through the given scales: a `{start, stop}` pair for one axis, a four-key map for both (6.3). |

### 6.2 `BrushHook` behaviour

Attach with `phx-hook="BrushHook"` and an `id` on an `<svg>`, or on a container whose first `<svg>` descendant is the chart — the `<div>` a page puts around a server-rendered SVG, as the other hooks take it (#467). That `<svg>` is the hook's SVG: the hook calls `createSVGPoint` and `getScreenCTM` on it, measures it, and draws in it, so an element that is neither an `<svg>` nor holds one is not a brush. Data attributes read on `mounted()`, from the hook element:

| Attribute | Default | Meaning |
|---|---|---|
| `data-brush-type` | `"xy"` | `"xy"` rectangle; `"x"` horizontal band; `"y"` vertical band |
| `data-brush-event` | `"brush_select"` | event pushed when a selection ends |
| `data-brush-clear-event` | `"brush_clear"` | event pushed when the selection is cleared |
| `data-brush-extent` | unset | `"x0,y0,x1,y1"`: clamps pointer positions and sizes the capture area; also supplies the full-height/width edges for 1-D brushes |
| `data-brush-color` | `"rgba(119, 119, 119, 0.2)"` | selection rectangle fill |
| `data-brush-stroke` | `"#666"` | selection rectangle stroke |

On mount the hook finds or appends a `<g class="brush-overlay">`, inserts into it a transparent `<rect class="brush-capture" cursor="crosshair">` covering the extent (or the SVG's bounding box) that receives pointer events, and a hidden `<rect class="brush-selection" stroke-width="1">` that displays the selection. Move and release listeners are attached to `document` so a drag may leave the SVG.

Coordinates are in the SVG's user coordinate system (`getScreenCTM().inverse()`), i.e. `viewBox` units — equal to CSS pixels only when the `viewBox` matches the rendered size. A brush starts on left-button mousedown or single-touch start on the capture rect; while brushing, `x1`/`y1` follow the pointer (`"x"` keeps `y0/y1` at the extent's edges, `"y"` keeps `x0/x1`). On release the selection is normalised so `x0 ≤ x1` and `y0 ≤ y1`; if either side exceeds 5 units it is pushed as `pushEvent(selectEvent, {x0, y0, x1, y1})` — with `domain` too in a sync group (6.4) — otherwise the gesture is treated as a click and cleared. Double-click on the capture rect clears. Clearing hides the rectangle and pushes `pushEvent(clearEvent, {})`.

On `updated()` the hook re-reads its sync group (6.4), then reads `data-selection-x0`, `-y0`, `-x1`, `-y1`; when all four parse it shows that selection (server-driven selection), without publishing it; else if `data-selection-clear="true"` it clears.

Events arrive as `handle_event("brush_select", %{"x0" => x0, "y0" => y0, "x1" => x1, "y1" => y1}, socket)` and `handle_event("brush_clear", %{}, socket)`. `mounted()` binds each handler once and stores the bound function on the hook (`onMouseDown`, `onMouseMove`, `onMouseUp`, `onTouchStart`, `onTouchMove`, `onTouchEnd`, `onClear`, and `onSync`, the bus listener of 6.4) before adding it as a listener, and `destroyed()` removes the four `document` listeners (`mousemove`, `mouseup`, `touchmove`, `touchend`) with those same references, and the bus listener (`VisualizeSync.detach`), so nothing outlives the element; the capture rect's own listeners are discarded with it (D-47). `test/visualize/hooks/brush_test.exs` holds the source to this shape.

### 6.3 Server-side helpers

A *selection* is a map with atom keys `x0`, `y0`, `x1`, `y1` in the hook's coordinate space; the string-keyed event params MUST be converted by the caller. Both helpers work on the axes whose scale they are given, so an `"x"` brush needs no y scale and a `"y"` brush no x scale (D-29). A selection MAY omit the keys of an axis that is not in use.

`filter_selection(data, selection, opts)` — `opts` is a keyword list:

| Key | Meaning |
|---|---|
| `:x_accessor` | `(datum -> domain x)`; required with `:x_scale` |
| `:x_scale` | any scale struct accepted by `Visualize.Scale.apply/2` |
| `:y_accessor` | `(datum -> domain y)`; required with `:y_scale` |
| `:y_scale` | likewise |

At least one of `:x_scale`, `:y_scale` MUST be given; neither raises `ArgumentError`. A datum is kept when, for every axis given, `p0 ≤ apply(scale, accessor(d)) ≤ p1` with `p0`/`p1` that axis's selection edges. With both scales this is the rectangle test; with one it is a band test that ignores the other axis entirely, so an `"x"` brush without a `data-brush-extent` no longer needs its degenerate `y0 = y1` widened.

`selection_to_domain(selection, opts)` — `opts` takes `:x_scale` and/or `:y_scale`, each of which MUST support `Visualize.Scale.invert/2` (continuous scales: linear, time, log, power, symlog):

- both scales: `%{x0: invert(x_scale, x0), x1: invert(x_scale, x1), y0: invert(y_scale, y0), y1: invert(y_scale, y1)}`, as before;
- `:x_scale` only: `{invert(x_scale, x0), invert(x_scale, x1)}` — the `{start, stop}` of an x brush in domain units, ascending for an ascending range;
- `:y_scale` only: `{invert(y_scale, y0), invert(y_scale, y1)}` in pixel order; because SVG y grows downward, `start` is the larger domain value under the usual flipped range;
- neither: `ArgumentError`.

### 6.4 In a sync group

**Implemented** (#467, D-117). A brush in a sync group (4.3) shares its x extent: brushing a window on one chart shows it as a band on every member at once, and **only the chart brushed talks to its server**, so one window change is one request.

**Membership.** The hook reads its group with `VisualizeSync.read` from the hook element, so the group is that element's `data-vis-sync` or that of its first descendant carrying one: for a chart rendered by `Visualize.Chart.render/2`, the sync frame's group inside the SVG ([14-declarative-chart](14-declarative-chart.md) §2.9). It reads it on `mounted()` and again on `updated()`, and listens on `vis:sync-brush:<group>` (`attach(hook, 'brush')`). A `"y"` brush joins no group: the group shares x, and a `"y"` brush selects none. Without a group the hook behaves exactly as 6.2 says.

The SVG's user units are the chart's coordinates of `data-vis-sync-x` when its `viewBox` is the chart's, as `Visualize.Chart.render/2` writes it with `root: true`, so the hook maps a selection edge to the domain with `toDomain` directly.

**Publishing.** The chart brushed publishes its extent, `[lo, hi]` in domain units, the two ends of `[toDomain(x0), toDomain(x1)]` in ascending order:

- on every pointer move of a brush in progress, so the members follow the rubber band as it is drawn; and
- on release, once more, the normalised selection's extent — the gesture's last event is the final window;
- a clear publishes `null`: a double-click, a release too small to be a selection (6.2), and a clear by `data-selection-clear` on `updated()`.

Only the chart under the pointer publishes. A selection the server sets through `data-selection-*` on `updated()` is not published, because the server set it on the chart it chose.

**Receiving.** A member ignores its own echo (4.3). It ignores any event while a brush of its own is in progress. Otherwise:

- `null` hides the band and forgets the selection.
- An extent is mapped by `toChartExtent` through the member's own numbers, clipped to its domain. A disjoint extent hides the band. Any other extent becomes the selection `{x0: c0, x1: c1}`, shown at once. Its `y0`/`y1` are the capture area's top and bottom (`data-brush-extent`'s, else the SVG's box), so the band spans the plot's height whatever the brush type.

A received extent **never calls `pushEvent`** and never publishes. The `brush_select` and `brush_clear` of a window change are pushed once, by the chart that was brushed, on release — never during the drag. A group of `n` charts therefore costs one server request per window, and the server learns of the window once.

**The pushed event.** In a sync group the chart brushed adds `domain: [lo, hi]` to `brush_select`'s payload, the same extent it published, so the server reads the window in domain units without knowing which chart sent it or holding its scale: `handle_event("brush_select", %{"domain" => [lo, hi]}, socket)`, `lo` and `hi` numbers (milliseconds since the Unix epoch for a time x). `x0`, `y0`, `x1`, `y1` are the chart's pixels as before. A member that shows a received band and is then double-clicked clears the group and pushes its own `brush_clear`: it is the chart that was acted on.

**Lifecycle.** `onSync` is bound once (D-47). `updated()` moves it when the group changed, and `destroyed()` removes it, so a remounted brush hears each event once and a destroyed one hears nothing.

`test/visualize/hooks/executed_hooks_test.exs` executes this (spec/12 §6): three brushes of different widths in one group, a fourth whose domain is disjoint from the window and a fifth whose domain holds part of it. Brushing one draws the band on every member at the same domain extent, at each member's own pixels, clips the partial member, shows nothing on the disjoint one, leaves another group untouched, and pushes exactly one `brush_select`, from the chart brushed, carrying the domain. A clear propagates with one `brush_clear`. `destroyed()` leaves no listener, and a remount hears once. The gallery's *Synced dashboard* page (`examples/lib/examples_web/live/dashboard_live.ex`) is three panels over one time axis, each joined to one group by one design key, with crosshairs and brushes synced.

## 7. Visualize.Hooks.Canvas

### 7.1 Functions

| Function | Contract |
|---|---|
| `Visualize.Hooks.Canvas.js_hook/0` | Returns the source of `export const CanvasChart = {…}` (7.2). |

### 7.2 `CanvasChart` behaviour

Attach with `phx-hook="CanvasChart"`, an `id` and `phx-update="ignore"` on a container holding a `<canvas>`; when the container has none, `mounted()` appends one sized from `data-width`/`data-height` (defaults `800`/`600`). The hook renders on `mounted()`, on `updated()`, and on a `canvas_commands` event whose payload MAY carry `commands` and/or `script`, each stored into the matching data attribute before rendering.

Rendering reads `data-commands` — the `:json` output of `Visualize.Backend.Canvas` (spec/09 §3.5) — or, when that is absent, `data-script` — its `:js` output (spec/09 §3.4), which is what `Visualize.Backend.Hybrid` emits under each attribute name (spec/09 §6.3). A value equal to the last one rendered is skipped. The hook resets the transform, clears the canvas, then for JSON executes each `{"cmd", "args"}` object as `ctx[cmd](...args)`, or as the property assignment `ctx[name] = args[0]` when `cmd` starts with `set_`; for a script it calls `new Function('ctx', script)(ctx)`. Because every command tuple names a Canvas 2D method (D-37), no other case exists.

## 8. Visualize.Hooks.CanvasBinary

### 8.1 Functions

| Function | Contract |
|---|---|
| `Visualize.Hooks.CanvasBinary.js_decoder/0` | Returns the source of three exported functions: `decodeBase64(base64)` (standard Base64 to a `Uint8Array`), `drawSvgArc(ctx, x1, y1, rx, ry, phi, fA, fS, x2, y2)` (the SVG endpoint-to-centre conversion, as `Visualize.Backend.Canvas.Arc` on the server) and `executeVisualizeBinary(ctx, bytes, startOffset, endOffset)` (8.3). |
| `Visualize.Hooks.CanvasBinary.js_hook/0` | Returns the source of `export const CanvasBinaryChart = {…}` (8.2); requires `js_decoder/0` in the same module. |

### 8.2 `CanvasBinaryChart` behaviour

Attach as for `CanvasChart` (7.2). The hook renders on `mounted()`, on `updated()`, and on a `canvas_update` event with a `binary` key, which it stores into `data-binary` first. Rendering reads `data-binary` (a `Visualize.Backend.CanvasBinary.to_base64/1` string), skips a value equal to the last rendered, resets the transform, clears the canvas and calls `executeVisualizeBinary(ctx, decodeBase64(value))`. **The canvas is transparent where the stream draws nothing** (#476): the clear is `clearRect`, and neither the hook nor the stream paints a background, so a page's backdrop stacked beneath the canvas — a basemap's tiles (spec/14 §12.4) — shows through it. `CanvasIncrementalChart` clears the same way (9.2). **A canvas draws only what is its own** (#432). A design has one plot per frame (spec/14 §12.1) and a page therefore has one canvas per frame, all of them hearing every pushed event: an element carrying `data-frame="<name>"` ignores a payload whose `frame` is another name. An element without `data-frame`, or a payload without one, draws as it always did, so a page with a single canvas is unchanged.

**The canvas follows its element's size** (#456, #455). The canvas's drawing size is its element's `data-width` × `data-height` at every draw: on `mounted()`, on `updated()` and before drawing a pushed payload, the hook compares `canvas.width`/`canvas.height` with the two attributes read as integers and, where they differ, sets them; an attribute that is missing or not a positive integer leaves the canvas as it is. Setting the size clears the canvas, so a size change redraws the current `data-binary` even when it equals the last value rendered — the skip applies to an unchanged value on an unchanged canvas only. The reason: a page that measures itself (10.2, #434) re-renders the chart at the measured size, and a canvas sized once, when the hook first created it, kept its mount size of 600×400 while the stream it replayed was laid out for about 1336×890 and the SVG layers over it grew — most of the data drawn off the canvas, under an overlay at the large size. The hook only created a canvas when the element held none, and the markup a page renders always holds one, so the size the page gave was never read.

**The hook acknowledges `canvas_update` frames when asked** (#322), exactly as `CanvasIncrementalChart` does (9.2, D-107): a payload may carry a `seq`, and an element carrying `data-ack="<event>"` pushes `<event>` with `%{seq, drawn, at}` at most once per `data-ack-interval` ms (default 100), with a trailing flush — so a page streaming whole frames to the binary canvas at a rate can see and bound what the browser has drawn, as a page streaming increments can.

### 8.3 The decoder

`executeVisualizeBinary(ctx, bytes, startOffset, endOffset)` replays the records of spec/09 §4 from `startOffset` (default `0`) up to `endOffset` (default `bytes.length`) and returns the offset reached. Per opcode: `path` begins a path, `moveTo` the first point and `lineTo` the rest; `path_cubic` begins a path and executes each sub-opcode against a tracked current point and subpath start (`Z` returns to the start; `A`/`a` go through `drawSvgArc`); `path32` and `path_cubic32` are the same two cases reading each coordinate with `getFloat32` and advancing by its 4 bytes (spec/09 §4.3.8–4.3.9), the sub-opcode table shared between the two command-stream records so a command is decoded by one function taking the width; `cubic_run` begins a path, `moveTo` the start point and `bezierCurveTo` each six-f32 entry in turn (spec/09 §4.3.10); `circles` and `rects` begin one path holding every entry (each circle a `moveTo` to its rightmost point then a full `arc`), left for the following `fill`/`stroke` records; `style` assigns `fillStyle`/`strokeStyle` as `rgba(r,g,b,a/255)`, `lineWidth` and `globalAlpha` per its flags; `transform` kind `0x01` is `ctx.translate`, `0x03` `ctx.translate` then `ctx.scale`, `0xFF` `ctx.transform(a, b, c, d, e, f)` — composed onto the current transform, never `setTransform` (spec/09 §4.3.6); `save`, `restore`, `fill`, `stroke` are the calls. An unknown opcode, sub-opcode or transform kind throws an `Error` naming the byte and offset: a mismatch with the encoder is a bug, not something to draw past. `test/visualize/hooks/canvas_hooks_test.exs` checks that the source has a `case` for every byte of `Visualize.Backend.CanvasBinary.Opcodes`, every sub-opcode `0x01`–`0x0F` and every transform kind, and that the `path32` and `path_cubic32` cases read `getFloat32`.

## 9. Visualize.Hooks.CanvasIncremental

### 9.1 Functions

| Function | Contract |
|---|---|
| `Visualize.Hooks.CanvasIncremental.js_hook/0` | Returns the source of `export const CanvasIncrementalChart = {…}` (9.2); requires `Visualize.Hooks.CanvasBinary.js_decoder/0` in the same module. |

### 9.2 `CanvasIncrementalChart` behaviour

Attach as for `CanvasChart` (7.2). On `mounted()` the hook also creates an offscreen canvas of the same size for the copy. It renders only on `canvas_incremental` events, whose payload is the map `Visualize.Incremental` builds (spec/09 §7.3): mode `"none"` is ignored; mode `"full"` resets the transform, clears the canvas, checks the `0x60` header and replays the stream from byte 27 (spec/09 §5.6); any scroll mode reads the record's viewport at bytes 10–25, copies the current pixels to the offscreen canvas, then — clipped to the viewport — clears it and draws the viewport's pixels back shifted by `(−round(dx), −round(dy))` (integer shifts, since a sub-pixel copy blurs; a source-rectangle `drawImage`, so nothing outside the viewport is read or written, D-106), then reads the `region_count` at byte 26 and, for each region, saves, clips to its bounds, replays its `data_length` bytes with `executeVisualizeBinary` and restores (spec/09 §5.5). A payload without the `0x60` header throws.

**A canvas draws only what is its own** (#432), as `CanvasBinaryChart` does (8.2): a `canvas_incremental` payload carries the `frame` its plot is named by, and an element carrying `data-frame` ignores another frame's.

**The canvas follows its element's size** (#456, #455), as `CanvasBinaryChart`'s does (8.2): its drawing size is its element's `data-width` × `data-height` at every draw — on `mounted()`, on `updated()` and before handling a `canvas_incremental` payload — and the offscreen canvas of the copy is resized with it. A size change clears the canvas, so it holds no pixels a scroll could copy: until a `"full"` payload has been drawn, the hook draws no scroll payload — it does not shift cleared pixels and paint strips onto a blank canvas — and a `"full"` payload, which replays the whole stream, makes it current again. A payload that is skipped this way is still handled, and so acknowledged. The producer's half is that a resize starts the stream again from a full record: a compiled chart drawn at a new size is compiled again and its window starts afresh, so its first tick is `"full"` (spec/14 §12.5).

**The hook acknowledges frames when asked** (#304, D-107). A `canvas_incremental` payload may carry a `seq`, an integer the producer assigns in order. When the hook's element carries `data-ack="<event>"`, the hook, after handling a payload with a `seq` — a `"none"` included, since it was received and dealt with — pushes `<event>` to the view with `%{"seq" => last, "drawn" => n, "at" => ms}`: the last sequence handled, the payloads handled since the previous ack, and the client's monotonic time (`performance.now()`). It pushes at most once per `data-ack-interval` milliseconds (default `100`): the first frame in an interval schedules a flush, later frames in it only advance the numbers, and the flush sends them, so the last frame is always reported. An element without `data-ack`, or a payload without a `seq`, changes nothing. The reason: a producer streaming frames at a rate has no view of the consumer — LiveView's channel applies no backpressure, so frames the browser cannot draw in time queue in its message loop, the canvas falls behind and every click waits behind the backlog — and the ack is what lets it see the lag and bound it (spec/14 §12.6).

**A host registers the library's hooks and defines none of its own by their names** (#270). The examples' layout once spread `VisualizeHooks` into the socket's `hooks` and then overrode `CanvasChart`, `CanvasBinaryChart` and `CanvasIncrementalChart` with page-local copies whose decoder knew the opcodes of §4 before D-73 — so every canvas page ran a decoder that did not know the f32 records the encoder writes by default, the High-Performance page logged *Unknown command: 6* (a `path_cubic32`) for every frame and drew nothing, and the library's decoder in the module it imported never ran. A host's hooks map takes the library's hooks whole; a hook a host writes for itself takes a name of its own. `examples/test/examples_web/layout_test.exs` holds the examples to it.

**A decode failure is visible on the page** (#270). `CanvasBinaryChart` and `CanvasIncrementalChart` replay a stream inside a guard that, on any throw — an unknown opcode, a truncated record, a header mismatch — writes the message to `data-vis-error` on the hook element, appends one `<p class="vis-canvas-error">` under the canvas carrying it, and rethrows, so the console still has the stack and the page says what the console said. A stream that replays clears the attribute and the message. The reason: the page's counters are the server's — the bytes it encoded — and a client that throws leaves a blank canvas indistinguishable from one that was never sent anything; the High-Performance page sat like that with sound bytes (`Visualize.Backend.CanvasBinary.Decoder.decode/1` reads them, and the page's stream test held it — `examples/test/examples/scrolling_series_test.exs` since #327) and nothing on the page to say why.

## 10. Visualize.Hooks.Resize

### 10.1 Functions

| Function | Contract |
|---|---|
| `Visualize.Hooks.Resize.js_hook/0` | Returns the source of `export const ResizeHook = {…}` (10.2). |

### 10.2 `ResizeHook` behaviour

Attach with `phx-hook="ResizeHook"` and an `id` on the container whose size the chart should follow — the element CSS sizes, not the `<svg>` inside it, which the server re-renders at the pushed size. **This is the ordinary path for a declarative chart** (spec/14 §4.2, #427): a design records no size, so the pushed size is what `Visualize.Chart.apply/2` is given as `size:`. Before the first push the chart renders at the documented default `{600, 400}` — a disconnected mount has no container to measure and must still draw — and the first measured render replaces it. Data attributes read on `mounted()`:

| Attribute | Default | Meaning |
|---|---|---|
| `data-resize-event` | `"resize"` | name of the event pushed to the LiveView |
| `data-resize-debounce` | `150` | milliseconds the size must hold before it is pushed |

On mount the hook creates a `ResizeObserver` on the element. Every observation records the element's content box (`contentRect.width` and `contentRect.height`, each rounded to an integer) and restarts a timer of `debounce` milliseconds; when the timer fires — once per settle, however many observations a drag produced — the hook pushes `pushEvent(eventName, {width, height, reduced_motion})` unless that size equals the last size pushed; `reduced_motion` is whether `matchMedia('(prefers-reduced-motion: reduce)')` matches (`false` where `matchMedia` is absent). The hook listens for that query's `change` and pushes `{width, height, reduced_motion}` with the last size pushed whenever the answer changes, so a page compiles with `motion: :reduce` (spec/14 §21.6, D-142) from the first push on and follows the reader's setting live; `destroyed()` removes the listener. The first observation, which `ResizeObserver` delivers on `observe()`, therefore pushes the initial size after one debounce period, so a LiveView learns its container's width without a round trip of its own. `destroyed()` disconnects the observer and clears a pending timer, so nothing outlives the element (D-47). A browser without `ResizeObserver` gets no events: `mounted()` returns without observing.

Event: `handle_event("resize", %{"width" => w, "height" => h, "reduced_motion" => rm}, socket)`, the two sizes integers and `rm` a boolean.

**The width is the measurement; the height is the design's aspect** (#434). A container's height is usually its content's, so a chart whose height follows the container it is drawn in observes its own output and never settles. A page therefore takes the pushed **width** and keeps the aspect the chart was designed at — the gallery's `size/0` — deriving the height from it. A page that genuinely has a fixed-height container may use the pushed height; a page whose chart sets its own height must not. **A page may cap the measured width** (#457): the hook reports the container and the page decides what to draw at, so a page that wants a chart no larger than it was designed takes the smaller of the pushed width and its own, the height again at the aspect. The gallery caps at the design size — `size/0`, `{600, 400}` where a module has none — through one function, `Examples.Charts.Design.fitted/2`: a narrow container shrinks a chart, and a wide one never grows it past its design (decided with the user, 2026-10-08). The cap is the page's rule, not the hook's: `ResizeHook` still pushes the container's width, and a host whose chart should fill its container does not cap.

The hook is the round-trip half of responsive sizing (D-54); the CSS-scaled half needs no hook: a root built with `Visualize.IR.Element.root/3` under `responsive: true` (spec/02 §2.1), or a component with `responsive={true}` (1.2), follows its container by `viewBox` and `preserveAspectRatio` alone. `test/visualize/hooks/resize_test.exs` holds the source to this shape.

## 11. Elements in HEEx

### 11.1 Safe implementations

`Visualize.SVG.Element` implements `Phoenix.HTML.Safe` (defined in `Visualize.SVG.Renderer`, compiled only when `Phoenix.HTML.Safe` is loaded) with `to_iodata/1 = Visualize.SVG.Renderer.render/1`, so an element built with `Visualize.svg/1`, `Visualize.SVG.Element.new/2` or `Visualize.SVG.Element.from_ir/1` MAY be interpolated directly: `<%= @element %>` or `{@element}` in HEEx renders its markup without `raw/1`. It also implements `String.Chars`.

`Visualize.IR.Element` likewise implements `Phoenix.HTML.Safe` (defined in `Visualize.Backend.SVG`, same compile condition) with `to_iodata/1 = Visualize.Backend.SVG.render_element/1`, and `String.Chars` unconditionally. An IR element interpolated into HEEx is therefore rendered as SVG by the SVG backend regardless of the configured default backend; to render it with another backend, or with options, the template MUST call `Visualize.Render.to_string/2` (spec/02) and wrap the result in `raw/1`, or convert with `Visualize.SVG.Element.from_ir/1` first.

`Visualize.IR.Path` implements `String.Chars` only (its `d` string); it MUST be interpolated as an attribute value (`d={@path}`), never as markup.

### 11.2 Strings

`Visualize.Axis.render/2`, `Visualize.Render.to_string/2` and `Visualize.SVG.to_string/1` return plain binaries, which HEEx escapes; they MUST be wrapped in `Phoenix.HTML.raw/1` to be emitted as markup, as the components in section 2 do for axes.

## 12. Visualize.Hooks.Tooltip

### 12.1 Functions

| Function | Contract |
|---|---|
| `Visualize.Hooks.Tooltip.js_hook/0` | Returns the source of `export const TooltipHook = {…}` (12.3). |

### 12.2 The datum attributes

The tooltip needs no round trip because the server writes each datum's fields onto the element that draws it, as data attributes, and the hook reads them under the pointer. `Visualize.IR.Element.datum/2` (spec/02 §2.1) is the writer, and every mark with a `tooltip` node ([14-declarative-chart](14-declarative-chart.md) §5.7) writes them through it; a hand-built chart calls it directly. The attributes are the contract (D-75):

| Attribute | On | Value |
|---|---|---|
| `data-datum` | every element that carries a datum | the field names, space-separated, in the order the fields were given — the order the tooltip lists them in |
| `data-datum-<field>` | the same element, one per field | the field's name with every `_` as `-` after `data-datum-`, and `to_string/1` of the value; a `nil` value writes no attribute, and the template reads it as `""` |
| `data-tooltip-template` | the element or any ancestor of it up to the hook element — a mark's group | the tooltip's text with `{field}` placeholders; the nearest one to the element wins |
| `data-tooltip-event` | likewise | the event pushed on click; absent, a click pushes nothing |

`Visualize.IR.Element.datum/2` takes the element and the fields as a map or a keyword list of `{field, value}` — a map's fields are written in `Enum.sort/1` order, a keyword list's in its own — and merges the attributes over the element's `attrs` under string keys (`"data-datum"`, `"data-datum-v"`), which `Visualize.SVG.Renderer.attribute_name/1` prints as given (spec/09 §2.4); an existing attribute of the same name is replaced. A field is an atom or a string; the value is any term `to_string/1` accepts, so a `DateTime` prints in ISO 8601 and a float with its decimals — the formatting a chart wants is the template's job, or the server's before it builds the map.

### 12.3 `TooltipHook` behaviour

Attach with `phx-hook="TooltipHook"` and an `id` on the `<svg>`, or on any ancestor of the elements that carry `data-datum`; one hook serves every mark under it. Data attributes read on `mounted()`:

| Attribute | Default | Meaning |
|---|---|---|
| `data-tooltip-class` | `"vis-tooltip"` | the class of the tooltip element the hook creates, for a stylesheet |

On `mounted()` the hook creates one `<div>` with that class, `position: absolute`, `pointer-events: none`, `white-space: pre` and `display: none`, appends it to `document.body`, and binds `mousemove`, `mouseleave`, `touchmove`, `touchend` and `click` on the element, each handler bound once and kept on the hook (D-47). On a move the *datum element* is the event target's nearest ancestor-or-self with `data-datum` (`closest`); none under the pointer hides the tooltip. Otherwise the text is built without a round trip: with a `data-tooltip-template` on the datum element or an ancestor of it — the nearest wins, searched no further than the hook element — every `{field}` becomes that field's `data-datum-<field>` value (`_` as `-`), `""` when the element has no such attribute; without a template, one line per field of `data-datum` in its order, `field: value`, joined with newlines. The text is set with `textContent`, never as markup, so a value is never interpreted. The tooltip is shown at 12 CSS pixels right of and below the pointer's page position, flipped to the left of the pointer when its width would cross the viewport's right edge and above it when its height would cross the bottom. A touch move uses its first touch; `touchend` and `mouseleave` hide. In a sync group (4.3) every move also publishes the pointer's x, and `touchend` and `mouseleave` publish a clear.

A click on a datum element whose nearest `data-tooltip-event` is set pushes `pushEvent(event, fields)` with one key per field of `data-datum` and the attribute strings as values, arriving as `handle_event("point_click", %{"t" => "2024-01-01T00:00:00Z", "v" => "4"}, socket)` — strings, since the attributes are strings; the server parses what it needs. A click elsewhere, or without an event, pushes nothing. `updated()` re-reads the sync group (4.3). `destroyed()` removes the five listeners with the kept references, and the bus listener, and removes the tooltip element from the document. `test/visualize/hooks/tooltip_test.exs` holds the source to this shape.

### 12.4 In a sync group

**Implemented** (#466). A tooltip in a sync group (4.3) shows the datum nearest to another member's hover. On a received value the hook finds the value's client x, `rect.left + chartX · rect.width / width`, with `rect` the hook element's bounding rectangle. It then takes the `[data-datum]` element under the hook element whose bounding rectangle has its horizontal centre nearest to that x, the first of two at the same distance. Its text is built as 12.3 builds it, and the tooltip is placed as for a pointer at that centre and at the element's top, in page coordinates. With no datum element, a `null`, or a value outside the member's domain, the tooltip is hidden. Over a canvas there is no datum element, so a synced tooltip there shows nothing, and the crosshair is what shows the hover (13.4).

## 13. Visualize.Hooks.Crosshair

### 13.1 Functions

| Function | Contract |
|---|---|
| `Visualize.Hooks.Crosshair.js_hook/0` | Returns the source of `export const CrosshairHook = {…}` (13.3). |
| `Visualize.Hooks.Crosshair.attrs/2` | As `attrs/3` with no options: the first mark. |
| `Visualize.Hooks.Crosshair.attrs/3` | `attrs(frame, sources, opts)`: the attributes of 13.2 for one mark of a realised `Visualize.Chart.Frame`, with the frame's sync attributes (`Visualize.Chart.Frame.sync_attrs/1`) merged in when it is the frame of a sync group (13.4), as a map from attribute name (string) to value (string), computed once on the server. `:mark` is the one-based position of the mark among the frame's marks (default `1`). Raises `ArgumentError` when the frame is a `:facet` or a `:polar` one — the crosshair is a cartesian interaction over one plot area — or when the mark has no `x` and `y` channels. |

### 13.2 The data arrays

The crosshair snaps to the data without a DOM: the server writes the mark's x pixels once, and the hook finds the nearest one to the pointer in that array. It therefore works over a mark the compiler sent to the canvas layer (spec/14 §12.3), which has no element per datum, exactly as over an SVG (D-76). `Visualize.Hooks.Crosshair.attrs/3` builds them from the rows a mark draws — `Visualize.Chart.Mark.rows/3` through the mark's channels and the frame's scales, the placed rows only (spec/14 §5.2) — and the host puts them on the hook element:

| Attribute | Value |
|---|---|
| `data-xs` | a JSON array of the distinct x pixels of the placed rows, ascending, in the plot area's coordinates — the array the pointer snaps to |
| `data-ys` | a JSON array with one entry per series — the `series` channel's distinct values in order of first appearance, one unnamed series without the channel — each an array parallel to `data-xs` of the series' y pixel at that x, the first row's when the series has several there, `null` where it has none |
| `data-plot` | `left,top,width,height`: the plot area inside the chart — the frame's margins and plot size — so the hook converts a pointer position into plot coordinates and spans the rule over the plot's height |
| `data-size` | `width,height`: the frame's size, the chart's `viewBox`, so a CSS-scaled chart maps the pointer correctly; absent, the hook takes the chart's own pixel size (13.3). Over a canvas it is also the canvas's drawing size: the host gives the canvas hook's `data-width` and `data-height` from the same realised frame (13.3) |
| `data-vis-sync`, `data-vis-sync-x` | only for the frame a sync group reads: the group and its x mapping, `Visualize.Chart.Frame.sync_attrs/1` ([14-declarative-chart](14-declarative-chart.md) §2.9, 4.3) |

Every number prints through `Visualize.IR.Path.format_number/1` (at most four decimals, never `-0`), and the arrays are built by the library, so the attributes need no JSON library. A chart of `n` distinct x values and `s` series costs `n` numbers plus `n × s` numbers once per render, whatever the render target.

### 13.3 `CrosshairHook` behaviour

Attach with `phx-hook="CrosshairHook"` and an `id` on a *container* holding the chart — the `<div>` around an `<svg>`, or the canvas hook's container — with the attributes of 13.2 on it. Data attributes read on `mounted()` and again on `updated()`, so a chart re-rendered with new data snaps to the new arrays:

| Attribute | Default | Meaning |
|---|---|---|
| `data-xs`, `data-ys`, `data-plot`, `data-size` | required, `data-ys` and `data-size` optional | 13.2 |
| `data-crosshair-event` | unset | when set, the event pushed with `{index}` — the index into `data-xs` — each time the nearest index changes; unset, the hook pushes nothing |
| `data-crosshair-color` | `"#666"` | the rule's stroke, and the markers' fill for a series `data-crosshair-colors` does not cover |
| `data-crosshair-colors` | unset | a JSON array of one fill per series of `data-ys`, in order |

On `mounted()` the hook creates an overlay `<svg class="crosshair">` with `position: absolute` and `pointer-events: none`, appends it to `document.body` — never inside the container, so a LiveView patch of the chart neither removes it nor sees it — and inside it a group translated to the plot's origin holding a `<line class="crosshair-rule">` from `0` to the plot's height and one `<circle class="crosshair-marker" r="4">` per series of `data-ys`; the overlay is hidden until a move. It binds `mousemove`, `mouseleave`, `touchmove` and `touchend` on the container, each handler bound once and kept (D-47). On a move the hook reads the bounding rectangle of the *chart*, sizes and places the overlay over it with the chart's `viewBox` (`0 0 width height` of `data-size`, else the rectangle's size), converts the pointer into chart units by the ratio of the two, subtracts the plot's origin, and hides the overlay when the point is outside the plot area (in a sync group publishing a clear, 4.3); otherwise, in a sync group, it publishes the pointer's x, and it finds the nearest x by binary search over `data-xs` — the lower of two equidistant neighbours — moves the rule to it, moves each series' marker to its y there and hides a marker whose y is `null`, and, when `data-crosshair-event` is set and the index differs from the last pushed, pushes `pushEvent(event, {index})`, arriving as `handle_event("hover", %{"index" => 3}, socket)` with an integer. A touch move uses its first touch; `touchend` and `mouseleave` hide the overlay and, in a sync group, publish a clear. `updated()` re-reads the four arrays and the sync group, and rebuilds the markers when the series count changed; `destroyed()` removes the four listeners with the kept references, and the bus listener, and the overlay from the document. `test/visualize/hooks/crosshair_test.exs` holds the source to this shape.

**The chart, not the container** (#507). The chart is the container's first `<svg>` or `<canvas>` descendant in document order — the drawing the arrays describe — and the container itself when it holds neither. It is looked up on every move, since a patch may replace it. The pointer is still read on the container, which is where the listeners are. The container is measured no longer because a page lays it out, and its box is not the chart's. An `<svg>` or a `<canvas>` is an inline element: it sits on the text baseline, and the line's descender space below it makes the container a few pixels taller than the drawing. Through the container's rectangle, that gap became a vertical scale and an offset. On `/interaction` (16 px type, line height 1.6) the container was about 7 px taller than its 600 × 400 chart, and every marker sat about 3.7 px below its datum. A container wider than its chart would shift every marker sideways the same way.

**One size for the canvas and the arrays** (#507). A canvas stream draws at one canvas pixel per chart unit. A canvas whose drawing size is not the frame's `data-size` therefore crops the drawing or leaves part of the canvas empty. The overlay still maps the whole canvas onto the frame, so the markers land away from the series. The host gives the canvas hook's `data-width` and `data-height` from the same realised frame `attrs/3` reads (`applied.frame.size`), never from a constant kept beside the design. Before #507, `/interaction` drew a frame realised at the default 600 × 400 into a 720 × 380 canvas, a size its design had lost in #427. A marker landed up to 86 px from its datum, the pointer snapped to the wrong hour (19 for 23), and over the first hour it was read as outside the plot.

`test/visualize/hooks/executed_hooks_test.exs` executes the placement (spec/12 §6). A container taller than its `<svg>`, and one holding a CSS-scaled `<canvas>`, are mounted, and the pointer is put on a drawn vertex. The marker must then land on that vertex, in client pixels through the overlay's `viewBox`, within a pixel. The example page's guard, `examples/test/examples_web/interaction_live_test.exs`, holds both of `/interaction`'s crosshairs to their drawing at two sizes. Every point of the arrays must equal, within a pixel, the vertex the SVG path draws and the vertex the canvas stream draws for the same row, and the canvas's size must equal `data-size`.

### 13.4 In a sync group

**Implemented** (#466). A crosshair in a sync group (4.3) draws another member's hover as if its own pointer stood at the same domain x. The received value's chart x, less the plot's left edge, is a plot x. The hook places the overlay over the chart exactly as a move does (13.3), finds the nearest index of `data-xs` to that plot x with the same binary search, and moves the rule and every marker there. That is the nearest datum to the shared instant, through this chart's own scale. A `null`, or a value outside the member's domain, hides the overlay. A synced draw pushes no `data-crosshair-event`. That event is the chart's own hover, and a group of `n` charts sending `n` events for one movement is what the bus exists to avoid.

`attrs/3` writes the frame's `data-vis-sync` and `data-vis-sync-x` on the container (13.2), so a crosshair over a canvas, whose static SVG may sit beside rather than around the drawing, still has them. A container without them is in a group when the chart markup inside it carries them.

## 14. Visualize.Hooks.Legend

### 14.1 Functions

| Function | Contract |
|---|---|
| `Visualize.Hooks.Legend.js_hook/0` | Returns the source of `export const LegendHook = {…}` (14.3). |

### 14.2 The series attributes

A legend entry names what it explains and a series element names its series, with the same string, so a hook can join the two without a lookup table (D-77). The frame writes both; nothing on the server is configured:

| Attribute | On | Value |
|---|---|---|
| `data-series` | every `legend-item` group of a frame's legend ([14-declarative-chart](14-declarative-chart.md) §4.5) | `to_string/1` of the entry's value — a tick of the legend's scale |
| `data-series` | every element a mark with a `series` channel draws for a series, and every inline label drawn for it (spec/14 §5.2, §5.6, D-126): a `:line` or an `:area` series' path and its `line-fill`; the datum's own element on every other type, such as the circles or symbols that draw a series' points; a `:rule`, `:x_band` or `:needle` datum's group | `to_string/1` of the series value; absent where the series reading is `nil` |
| `data-legend-event` | the hook element, set by the host | the event pushed on every toggle; absent, the hook pushes nothing |

The two strings coincide when the legend explains the `color` scale the series channel reads through — the usual case, where the scale's domain is the series values — and an entry whose string no element carries toggles nothing. A hand-built chart writes the same two attributes to take part.

**A toggle hides everything the series draws, or the series is not whole** (#508). The hook hides by the attribute, so each element of a series must carry it. A series drawn by several marks gives each of those marks the `series` channel. A line and its points are two marks, a `:line` and a `:circle` or a `:symbol`, each with `series`. Their elements then name the same series and take the same colour (spec/14 §5.6). A mark that only colours its elements by the field, with a `{:field, f}` fill and no `series` channel, names no series. Its elements stay drawn when the legend hides the series.

### 14.3 `LegendHook` behaviour

Attach with `phx-hook="LegendHook"` and an `id` on the `<svg>`, or on any ancestor holding both the legend and the marks. On `mounted()` the hook gives every `.legend-item[data-series]` under the element `cursor: pointer` and binds one `click` listener on the element, bound once and kept (D-47); the hidden set starts empty. A click whose target is inside a `.legend-item[data-series]` toggles that series: when it becomes hidden, every element matching `.mark [data-series="<value>"]` under the hook element gets `display="none"` and the entry's group gets `class` `legend-item legend-item-hidden` and `opacity="0.35"`; when it becomes shown again, the `display` attribute is removed from those elements and the entry's class and opacity are restored. `display` is an SVG presentation attribute and applies in the SVG namespace, which the HTML `hidden` attribute does not (D-77). `updated()` re-applies the hidden set after a LiveView patch — the server re-renders the chart without knowing what the client hid, and the patch would otherwise show every series again — and re-sets the cursor on entries the patch replaced. When `data-legend-event` is set, every toggle pushes `pushEvent(event, {series, hidden})`, arriving as `handle_event("legend_toggle", %{"series" => "west", "hidden" => true}, socket)`; unset, nothing is pushed. `destroyed()` removes the click listener with the kept reference; the attributes it set stay on elements the DOM will discard with the hook's element. `test/visualize/hooks/legend_test.exs` holds the source to this shape, and `test/visualize/hooks/executed_legend_hook_test.exs` executes it (spec/12 §6, #508). That test runs the hook over the markup a chart with a `:line` and a `:circle` mark renders. Toggling an entry hides every element of that series, the path and each point, and no element of any other series. Toggling it again shows them all, and a patch keeps the series hidden.

## 15. Visualize.Chart.Builder

The embeddable builder for a stack of design fragments. What it is, what its host owns and what each panel shows is [14-declarative-chart](14-declarative-chart.md) §18; this section is its LiveView surface — the functions, the assigns and the markup contract the panels' goldens hold.

### 15.1 Functions

| Function | Contract |
|---|---|
| `Visualize.Chart.Builder.Preview.panel/1` | Renders the preview pane (spec/14 §18.4): `Visualize.Chart.render/2` of `Visualize.Chart.apply/2` of the `design` assign over `sources`, `vars` and `theme`, or the faults of application, each line `Visualize.Chart.Validator.format/1` of one error. |
| `Visualize.Chart.Builder.Editor.nodes/1` | The editable nodes of a fragment (spec/14 §18.5): one `%{path, kind, label}` per node the schema's walk reaches, the root first. |
| `Visualize.Chart.Builder.Editor.widget/1` | The control a `t:Visualize.Chart.Schema.type/0` gets (spec/14 §18.6): `:checkbox`, `:number`, `:text`, `:textarea` or `{:select, allowed}`. |
| `Visualize.Chart.Builder.Editor.parse/2` | `parse(type, string)`: `{:ok, value}` for a submitted string read back as a value of the type (spec/14 §18.6), `:error` for a blank string and for anything the type cannot take. |
| `Visualize.Chart.Builder.Editor.panel/1` | Renders one form for one node (spec/14 §18.7): the facets of the node's keys as tabs, the keys of the open tab in table order, each with its control and its errors. |
| `Visualize.Chart.Builder.Layers.panel/1` | Renders the stack panel (spec/14 §18.8): the layers in precedence order, each with its name, a select, a move up and down, a disable and a drag handle. |
| `Visualize.Chart.Builder.Inspector.panel/1` | Renders the inspector (spec/14 §18.9): one row per entry of `Visualize.Chart.explain/1` of the layers, with the path, the value, the layer that set it and the layers it overrode. |
| `Visualize.Chart.Builder.Params.panel/1` | Renders the parameters form (spec/14 §18.11): one control per entry of `Visualize.Chart.free_vars/1` of the layers, chosen by `Visualize.Chart.Builder.Editor.widget/1` of the first use's `expects`, with the variable's default, whether it is required, and the paths it stands at. |
| `Visualize.Chart.Builder.Document.panel/1` | Renders import and export (spec/14 §18.12): `Visualize.Chart.to_json/1` of the stacked design, or the faults that stop it, and a form that reads a pasted document back through `Visualize.Chart.from_json/1`. |

`Visualize.Chart.Builder` itself exports no function: it is a `Phoenix.LiveComponent`, and `mount/1`, `update/2`, `handle_event/3` and `render/1` are its callbacks, called by LiveView and by nothing else. `Visualize.Chart.Builder.Store` exports none either — it is a behaviour, and its three callbacks are spec/14 §18.3.

### 15.2 Assigns

The component's assigns are spec/14 §18.2, each declared with `attr/3` as every component's are (§1.2), and `id` is required as it is for any LiveComponent. The panels are function components of their own and take only what they draw, so each is rendered alone under `Phoenix.LiveViewTest.render_component/2`:

| Panel | Assigns |
|---|---|
| `Visualize.Chart.Builder.Preview.panel/1` | `design` (`:map`, required), `sources` (`:map`, `%{}`), `vars` (`:map`, `%{}`), `theme` (`:any`, `nil`), `class` (`:string`, `nil`) |
| `Visualize.Chart.Builder.Editor.panel/1` | `id` (`:string`, `nil` — the editor's id, which its form carries as `<id>-form`; `nil` derives it from the node, below), `kind` (`:atom`, required), `node` (`:map`, required), `path` (`:list`, `[]`), `facet` (`:atom`, `nil` — the first facet the node carries), `errors` (`:list`, `[]` — the `{path, reason}` pairs of spec/14 §10.1), `target` (`:any`, `nil` — the `phx-target` of the form's events), `class` (`:string`, `nil`) |
| `Visualize.Chart.Builder.Layers.panel/1` | `id` (`:string`, required — the hook element's), `layers` (`:list`, required), `selected` (`:integer`, `0`), `disabled` (`:any`, an empty `MapSet` — the positions dropped from the stack), `target` (`:any`, `nil`), `class` (`:string`, `nil`) |
| `Visualize.Chart.Builder.Inspector.panel/1` | `id` (`:string`, required — the hook element's), `layers` (`:list`, required), `target` (`:any`, `nil`), `class` (`:string`, `nil`) |
| `Visualize.Chart.Builder.Params.panel/1` | `id` (`:string`, `"vis-builder-params"` — the parameters form's id, the stem of its site forms' and its datalist's), `layers` (`:list`, required), `vars` (`:map`, `%{}` — the values now bound), `target` (`:any`, `nil`), `class` (`:string`, `nil`) |
| `Visualize.Chart.Builder.Document.panel/1` | `id` (`:string`, `"vis-builder-document"` — the panel's id, the stem of its import form's), `design` (`:map`, required — the stacked design), `target` (`:any`, `nil`), `class` (`:string`, `nil`) |

### 15.3 The markup

Every element the builder renders carries a class beginning `vis-builder`, and it ships no stylesheet: a host styles the tool as it styles the rest of its page, and a class is the contract a stylesheet holds. The root is a `<div class="vis-builder">`, with the `class` assign appended when it is given; it has no toolbar (#365): **the *New* form sits in the charts column under its title** — `<form class="vis-builder-new" phx-submit="new_fragment">` with its kind `<select class="vis-builder-new-kind">` and its `vis-builder-new-submit` button, directly after the `<h2 class="vis-builder-sidebar-title">` *Charts* and before the `<ol class="vis-builder-charts">`, when a store is given (spec/14 §19.8) — beside the column it fills, and the title's `+` stays as the chart-only shortcut. **The chart's own controls sit just above the chart** (#364): `<div class="vis-builder-chart-bar">`, the first child of `<main class="vis-builder-main">`, holds the name form (`<form class="vis-builder-keep" phx-submit="put_design">`: the `vis-builder-name` input, whose `aria-label` is *save the chart as* — *save as* for an entry opened from the library — and its placeholder `Group:sub-group:name`, then the `vis-builder-put` button *Save to library*; no label element and no layer count, #367; when a store is given), the save button `<button type="button" phx-click="save" phx-target={@myself} class="vis-builder-save">` and the deploy button (`vis-builder-deploy`), in that order and nothing else. Save and Deploy render when the middle column has a chart to act on — a composite; a style opened from the library has no chart, and its bar offers only *Save as* for the entry.

The panels sit in `<div class="vis-builder-panels">`, which opens with the node picker: `<nav class="vis-builder-nodes">` holding one `<button class="vis-builder-node">` per entry of `Visualize.Chart.Builder.Editor.nodes/1` of the selected layer, its `phx-value-node` the entry's label and the open one also `vis-builder-node-open`.

The editor is `<div class="vis-builder-editor">`, holding `<nav class="vis-builder-tabs">` with one `<button class="vis-builder-tab">` per facet the node carries — the open one also `vis-builder-tab-open` — and `<form id class="vis-builder-form" phx-change="edit">`. **The form carries an id** (#444), because LiveView recovers a form's state after a crash or a reconnect only by its id, and an edit in progress is otherwise lost: `<id>-form`, where `id` is the assign when one is given and is otherwise derived from the node — `vis-builder-editor-<node>`, `<node>` being the node's label when the form carries one, else its path as `Visualize.Chart.Builder.Editor.label/1` spells it, else, at the root path, its kind, with every run of characters other than ASCII letters and digits written as one `-` so the id is a valid HTML id. Two node forms on one page are two nodes, so their ids differ. Each key is a `<label class="vis-builder-field">` holding `<span class="vis-builder-key">` with the key's name, one control whose `name` is the key, and, where the key has faults, `<ul class="vis-builder-key-errors">` with one `<li class="vis-builder-error">` each. The control is `<input type="checkbox">`, `<input type="number">`, `<input type="text">`, `<select>` or `<textarea>` as `Visualize.Chart.Builder.Editor.widget/1` says, carrying the node's value and, where the node does not carry the key, the schema's default as its `placeholder`. The form changes as a whole, so LiveView's `_target` names the key that moved.

The stack panel is `<ol class="vis-builder-layers" id phx-hook="BuilderHook" data-builder-target data-builder-stack>` holding one `<li class="vis-builder-layer" data-builder-layer="<position>" draggable="true">` per layer, in the order `Visualize.Chart.stack/1` reads them; the selected layer's element also carries `vis-builder-layer-selected` and a disabled one `vis-builder-layer-disabled`. **The row is the control**: the `<li>` itself pushes `select_layer` with the layer's position as `phx-value-index`, and is the drag surface. It holds `<span class="vis-builder-layer-name">` with the layer's name and one `<button type="button" draggable="false" class="vis-builder-layer-toggle">` pushing `toggle_layer`. The button says `draggable="false"` because a control inside a draggable row is itself a drag source unless it says otherwise, and a mousedown that moves a pixel becomes a drag whose click never fires. `data-builder-stack` marks the element that accepts a drop (spec/14 §18.17).

The inspector is `<table class="vis-builder-inspector" id phx-hook="BuilderHook" data-builder-target>` whose body holds one `<tr class="vis-builder-entry" data-builder-path data-builder-layer>` per entry of `Visualize.Chart.explain/1`, in its order, with four cells: `vis-builder-entry-path`, `vis-builder-entry-value` (the value as `inspect/1` writes it), `vis-builder-entry-layer` and `vis-builder-entry-overrode` (the overridden layers, lowest first, comma-separated, empty where none).

The parameters form is `<form id class="vis-builder-params" phx-change="set_var">`, its id the `id` assign — `vis-builder-params` unless the host gives one, as it must where two panels share a page — for the same recovery as the editor's (#444); each site form below it, `<form class="vis-builder-site" phx-change="bind_site">`, carries `<id>-site-<index>`, `<index>` the site's position in the stack. The parameters form holds one `<label class="vis-builder-param">` per variable, also `vis-builder-param-required` where the variable has no default. Each holds `<span class="vis-builder-param-name">` with the variable's name, the control `Visualize.Chart.Builder.Editor.widget/1` chose with `name` the variable's name, the declared default as its `placeholder`, and `<span class="vis-builder-param-uses">` with the paths it stands at, comma-separated. A stack with no free variable renders the form empty.

The import and export panel is `<div class="vis-builder-document">` holding `<textarea class="vis-builder-export" readonly>` with the JSON document — absent, and `<ul class="vis-builder-errors">` in its place, where the design does not encode — and `<form id class="vis-builder-import" phx-submit="import">`, its id `<id>-import`, with `<textarea name="document">` and a submit button.

**Every form the builder renders carries an id** (#461, generalising #444). LiveView recovers a form's state after a crash or a reconnect only by its id, warns of a `phx-change` form without one, and patches the page by id, so an id must be unique on the page. The rule therefore holds for every `<form>` with `phx-change` or `phx-submit`, not only the editor's and the parameters': each id is **derived from the panel's own id** — the `id` assign, which a host may give and must where two panels share a page — with a suffix naming the form, and, for a form repeated per row, the row's position on the page, so two forms on one page never share one and the same state renders the same ids. The forms and their ids, `<id>` being the panel's:

| Form | Id |
|---|---|
| the editor's node form, `vis-builder-form` | `<id>-form`, or derived from the node (above, #444) |
| the parameters form, `vis-builder-params`, and its site forms | `<id>`, and `<id>-site-<index>` (above, #444) |
| the import form, `vis-builder-import` | `<id>-import` |
| the builder's *New* form, `vis-builder-new`, and its name form, `vis-builder-keep` | `<builder id>-new-form`, `<builder id>-keep-form` |
| the palette's add form, `vis-builder-palette-new` | `<id>-new`, `id` defaulting to `vis-builder-palette` |
| the style stack's add form, `vis-builder-style-add` | `<id>-add` |
| the font form, `vis-builder-fonts` | `<id>-form` |
| a layer's mask form, `vis-builder-masks` | `<id>-row-<position>-mask`, under the row `<id>-row-<position>` |
| the masks panel's key and *save as* forms | `<id>-declared`, `<id>-save` |
| the colour picker, `vis-builder-picker` | `<id>` |
| the variable panel's find and create forms | `<id>-find`, `<id>-create` |
| an expanded variable's default, value and site forms | `<id>-var-<n>-default`, `<id>-var-<n>-value`, `<id>-var-<n>-site-<index>`, `<n>` the variable's position in the list, `<index>` the site's in the stack |
| a source's name, generator, signal and host-default forms, and its add-column form | `<id>-source-<n>-name`, `-generator`, `-signal`, `-default`, `-add-column`, `<n>` the source's position on the page |
| a column's name and type forms | `<id>-source-<n>-column-<m>-name`, `-type`, `<m>` the column's position in the source |
| the tick's period form, `vis-builder-tick-period` | `<id>-tick` |

LiveView's own check runs only where `Phoenix.LiveViewTest` drives a page through `live/2` or `live_isolated/3`, as it parses the HTML; a component rendered with `render_component/2` is never parsed, so the library's suite, which renders every panel that way, never sees the warning. A test of the library's own therefore holds the rule: every `<form>` tag in the library's source carries an `id`, and the builder rendered in every state that renders a form has no form without an id and no id twice on a page.

The preview pane is `<div class="vis-builder-preview">`. When the design applies it holds `<svg class="vis-builder-chart" width height role="img" viewBox="0 0 width height">` at the realised frame's own size, with the frame's group inside it: `Visualize.Chart.Frame.render/2` draws a group and the `<svg>` shell is the pane's, exactly as it is a component's (§1.2), and the markup is a string emitted through `Phoenix.HTML.raw/1` as §11.2 requires. Otherwise it holds `<ul class="vis-builder-errors">` with one `<li class="vis-builder-error">` per fault, in the validator's order. Exactly one of the two is present, so a test that asks whether the design applied asks for `vis-builder-errors`.

## 16. Visualize.Hooks.Builder

### 16.1 Functions

| Function | Contract |
|---|---|
| `Visualize.Hooks.Builder.js_hook/0` | Returns the source of `export const BuilderHook = {…}` (16.3). |

### 16.2 The attributes

`BuilderHook` serves the chart builder's two browser gestures ([14-declarative-chart](14-declarative-chart.md) §18.10) and is attached to two elements, the stack panel's list and the inspector's table. Everything it needs is on the element or on the elements under it:

| Attribute | On | Value |
|---|---|---|
| `data-builder-target` | the hook element | the `phx-target` the hook pushes to — a LiveComponent's `@myself` printed — so the events reach the builder and not its host; absent, the hook pushes to the LiveView |
| `data-builder-layer` | a row of the stack panel, a row of a style stack, and a row of the inspector | on a stack panel row, the site's **flat position** — its zero-based index in `Visualize.Chart.Builder.Stack.all/1`, the tree depth first, where the rows under a closed group are counted though not drawn (spec/14 §18.8, #380); on a style stack row, the entry's index in the stack; on an inspector row, the position of the layer that set the value |
| `data-builder-end` | a row of the stack panel, and a row of a style stack | the flat position **past everything the row holds**: its own position plus one for an object or an entry, the position after its last descendant for a group, drawn or not — so `end − position` is how many rows a move of it lifts out (#468) |
| `data-builder-path` | a row of the inspector | the entry's path, spelled as `Visualize.Chart.Validator.format/1` spells one (`frames.main.axes[0].scale`) |
| `data-builder-scope` | the hook element | which list or region this instance serves; absent for the layer stack, `graph` for the builder's graph ([14-declarative-chart](14-declarative-chart.md) §18.16), and the others §18.18 and §18.16 name |
| `data-node` | an element of the chart under a `graph` hook | the design node the element draws, spelled as `Visualize.Chart.Validator.format_path/1` spells one (`marks[0]`), rendered with `paths: true` ([14-declarative-chart](14-declarative-chart.md) §4.7) |
| `data-builder-selected` | the `<svg>` of the chart under a `graph` hook | the open node's label, which the hook outlines |

A `draggable="true"` element carrying `data-builder-layer` is a layer that can be dragged; a row carrying `data-builder-path` is one that can be clicked. An element carrying neither takes part in neither gesture, which is how one hook serves two panels without knowing which it is on.

### 16.3 `BuilderHook` behaviour

Attach with `phx-hook="BuilderHook"` and an `id`. On `mounted()` the hook binds `dragstart`, `dragover`, `drop`, `dragend` and `click` on its element, each handler bound once and kept on the hook (D-47), and reads `data-builder-target` once.

A `dragstart` on an element whose nearest `[data-builder-layer]` ancestor-or-self is inside the hook element records that position and its `data-builder-end`, and gives the element the class `vis-builder-layer-dragging`. A `dragover` calls `preventDefault()`, which is what makes a drop possible, and marks the gap under the pointer: the row whose position it is gets `vis-builder-layer-over`, and the last row `vis-builder-layer-over-end` for the gap at the end. A `drop` reads the gap under the pointer as a flat position ([14-declarative-chart](14-declarative-chart.md) §18.17) and pushes `reorder` with `{from, to}`, both integers, when the two differ and nothing when they do not. **Every position the hook sends is one the server wrote**: the gap before a drawn row is that row's `data-builder-layer`, the gap at the end is the last drawn row's `data-builder-end`, and the hook never counts elements — a closed group's rows are not drawn, so a count of drawn rows is not a flat position (#468, D-75); `dragend` clears both classes whether or not a drop happened. The hook moves nothing itself: the server owns the list, and the next render is the move.

A `click` whose target's nearest `[data-builder-path]` ancestor-or-self is inside the hook element pushes `inspect` with `{path, layer}`, the two attributes as strings, and marks that row `vis-builder-entry-open`, removing the class from every other row under the element — the highlight is the browser's because it needs no server round trip, and the selection is the server's because it changes what the editor edits. A click on anything else pushes nothing.

Both pushes go through `pushEventTo(target, …)` when `data-builder-target` is set and through `pushEvent(…)` when it is not. `destroyed()` removes the five listeners with the kept references. `test/visualize/hooks/builder_test.exs` holds the source to this shape.

**In scope `graph`** ([14-declarative-chart](14-declarative-chart.md) §18.16) a `click` whose target's nearest `[data-node]` ancestor-or-self is inside the hook element pushes `pick` with `{node}`, the attribute as a string, and pushes nothing for a click on anything else; no class is set by the click, because the server's answer re-renders the chart. On `mounted()` and on every `updated()` the hook reads `data-builder-selected` from the `<svg>` under it and gives `vis-builder-graph-selected` to every element whose `data-node` is the longest prefix of that label — equal to it, or followed in it by `.` or `[` — and to no other; with no `<svg>`, no label, or no element that fits, nothing is marked. The prefix rule is what lets the open form be a facet of a node the graph draws whole. The graph also **accepts a library drag and a component drag**: `dragover` with `application/x-visualize-fragment` or `application/x-visualize-component` among the types is allowed with `dropEffect` `copy`, and the `drop` pushes `place` — `{name, as}` for an entry, `{component}` for a palette row — with `x` and `y` in **chart coordinates**: the drop's client position relative to the `<svg class="vis-builder-chart">`, scaled by its `viewBox` width and height over its client width and height, so a 400×200 chart drawn at 800×400 reports half the pixel offset ([14-declarative-chart](14-declarative-chart.md) §18.16, §18.17). A `dragstart` on an element carrying `data-builder-component` sets that type with the component's word. **A drawn node is moved with the pointer, not with an HTML5 drag** (#277): `draggable` is an attribute of `HTMLElement`, and a browser does not start an HTML5 drag from an SVG element, which every drawn node is. So a `pointerdown` on a `[data-node]` element of the chart whose label is movable — an axis or the legend of any frame (`frames.<name>.axes[`, `frames.<name>.legend`), `labels[` ([14-declarative-chart](14-declarative-chart.md) §18.16) — captures the pointer and remembers the label and the start point; a `pointermove` more than four pixels from it marks the graph element `vis-builder-moving` and `vis-builder-region-<region>` for the region under the pointer, computed from `chartPoint` against `data-builder-frame` — the frame's `size` and `margin` the render carries on the `<svg>` as `w h top right bottom left`; `pointerup` releases the capture, clears both marks and, when the pointer had moved, pushes `move` with `{node, x, y}` — and when it had not, does nothing, so the click that follows selects the node as §16.3 above says. The palette's and the library's drags remain HTML5 drags, since their sources are HTML rows. With the graph focused, `Shift+ArrowUp/Down/Left/Right` push `move` with `{node, region}` for the `<svg>`'s `data-builder-selected` when it is movable, and `Shift+Enter` the `plot` region. Every `insert` a drop raises on the stack, and every `place` of an entry, carries `as`: `"link"` when `altKey` was held at the drop, `"copy"` otherwise.

## 17. Visualize.Hooks.Keyboard

**Implemented** (#558, D-142). A chart's points reached from the keyboard ([14-declarative-chart](14-declarative-chart.md) §21.5): the server writes every point once, with its readout and position, and the hook moves a focus marker and reads the point aloud. Like the crosshair (§13, D-76) it never reads the chart's DOM, so it serves an SVG and a canvas alike.

### 17.1 Functions

| Function | Contract |
|---|---|
| `Visualize.Hooks.Keyboard.js_hook/0` | Returns the source of `export const KeyboardHook = {…}` (17.3). |
| `Visualize.Hooks.Keyboard.attrs/1` | `attrs(applied)`: the attributes of 17.2 for an applied chart, as a map from attribute name (string) to value (string), computed once on the server. |

### 17.2 The attributes

| Attribute | Value |
|---|---|
| `data-keyboard-name` | the chart's name, `Visualize.Chart.Summary`'s (spec/14 §21.1) |
| `data-keyboard-points` | a JSON array with one entry per series, in the summary's order: `{"name": series, "points": [[x, y, readout], …]}`, `x` and `y` the point's position in the chart's pixels (`null` for a point with none) and `readout` its text (spec/14 §21.5) |
| `data-size` | `width,height`: the chart's size, its `viewBox`, so a CSS-scaled chart places the marker correctly; as `CrosshairHook` reads it (§13.2) |

The arrays are built by the library: every number prints through `Visualize.IR.Path.format_number/1` and every string is escaped for JSON here, so the attribute needs no JSON library.

### 17.3 `KeyboardHook` behaviour

Attach with `phx-hook="KeyboardHook"` and an `id` on a *container* holding the chart, with the attributes of 17.2 on it; they are read on `mounted()` and again on `updated()`, the position clamped to the new points. Set by the host: `data-keyboard-event`, the event pushed with `{series, index}` (zero-based) each time the focused point changes; unset, nothing is pushed.

On `mounted()` the hook makes the container focusable — `tabindex="0"` — and gives it `role="group"` and an `aria-label` of `<name>, chart: arrow keys move between points`, each only where the host set none and again on every `updated()`, since a patch drops an attribute the server did not render; it appends to `document.body` — never inside the container, so a LiveView patch neither removes nor sees them — a visually hidden `<div class="vis-keyboard-readout" aria-live="polite">` and an overlay `<svg class="vis-keyboard-focus">` (`position: absolute`, `pointer-events: none`, hidden) holding one `<circle r="6">` with no fill and a 2-pixel stroke. It binds `keydown`, `focus` and `blur` on the container, each bound once and kept (D-47).

- **focus** reads, in the live region, `<name>: <s> series, <n> points.` — the series and the points of all of them — and marks nothing until a key is pressed.
- **ArrowRight** and **ArrowLeft** move to the next and the previous point of the series, **ArrowDown** and **ArrowUp** to the next and the previous series at the same index, clamped to its points, **Home** and **End** to the series' first and last point; the first such key after focus starts at the first point of the first series. Each stops at the ends rather than wrapping, calls `preventDefault()`, writes the point's readout to the live region, places the marker over the chart — its first `<svg>` or `<canvas>`, as the crosshair finds it (§13.3), through `data-size` — at the point's position, hidden for a point with none, and pushes `data-keyboard-event` when it is set.
- **Escape** hides the marker and forgets the point; when the container sits inside an element carrying `data-vis-cell`, focus moves to that element (spec/14 §21.5).
- **Tab** is never handled: the chart is one stop, and the page's order — a board's cells — goes on past it.
- **blur** hides the marker and keeps the point, so focus coming back resumes there.

`destroyed()` removes the three listeners with the kept references and the two elements it appended. `test/visualize/hooks/keyboard_test.exs` executes it under the harness of spec/12 §6.
