# LiveView Integration

**Status:** Implemented

Visualize reaches the browser through Phoenix LiveView in three ways: HEEx function components (`Visualize.Components`, `Visualize.Components.Tree`) that build a complete chart from assigns; JavaScript hooks — `Visualize.Hooks.Zoom` and `Visualize.Hooks.Brush` add zoom/pan and brush selection to any SVG and report back to the LiveView as events, and `Visualize.Hooks.Canvas`, `Visualize.Hooks.CanvasBinary` and `Visualize.Hooks.CanvasIncremental` replay the Canvas outputs of spec/09 on a `<canvas>`, `Visualize.Hooks.Resize` reports a container's size so the server can re-render at it, `Visualize.Hooks.Tooltip` shows a datum's fields under the pointer from attributes the server wrote, `Visualize.Hooks.Crosshair` snaps a rule and markers to the nearest x of an array the server wrote once, `Visualize.Hooks.Legend` hides a series from its legend entry, and `Visualize.Hooks.Builder` drags a layer of the chart builder into place and takes a click on an inspector row — with `Visualize.Hooks` bundling them into one installable file and re-exporting the server-side helpers; and the `Phoenix.HTML.Safe` implementations that let element structs be interpolated into a template directly. This document is the contract for each: every assign a component reads, every data attribute and event a hook uses, and the maths of the helpers.

## 1. Scope

### 1.1 Modules covered

| Module | Compiled when | Role |
|---|---|---|
| `Visualize.Components` | `Phoenix.Component` is loaded (the host has `phoenix_live_view`) | Line, bar, horizontal bar, pie, scatter, area and stacked bar chart components |
| `Visualize.Components.Tree` | `Phoenix.Component` is loaded (the host has `phoenix_live_view`) | Tree, treemap and sunburst components |
| `Visualize.Components.Chart` | `Phoenix.Component` is loaded | A chart whose marks declare events: its SVG under `TooltipHook`, a click resolved to the row drawn and sent to the page as a `Visualize.Event` (19) |
| `Visualize.Event` | always | The one shape of every interaction event, and the decoding and resolution of a click (19) |
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
- Every component is a *preset design* of [14-declarative-chart](14-declarative-chart.md) §15 plus an assign mapping (D-64): the component's assigns go to `Visualize.Chart.Presets.design/2` for the design and to `Visualize.Chart.Presets.sources/2` for the rows its source binds to; `Visualize.Chart.Frame.new/2` realizes the frame over them and `Visualize.Chart.Frame.generate/2` draws it, and the component prints the elements the layer returns in the markup this document declares — its HEEx template is the `<svg>` shell and the attribute order of each mark, nothing more. Every coordinate, path and paint below is therefore the layer's, and the render goldens of `test/support/components/` hold each component to what it drew before it was a preset.
- Every component declares its assigns with `attr/3`, so an unknown assign or a missing required one is a compile-time warning in the caller, and each listed default is applied by `Phoenix.Component`.
- Every component renders one `<svg width={width} height={height} role="img" viewBox="0 0 {width} {height}">`.
- `responsive` (`:boolean`, default `false`) is accepted by every component; when true the `<svg>` also carries `preserveAspectRatio="xMidYMid meet"` and `style="width:100%;height:auto"`, the CSS-scaled case of D-54, exactly as `Visualize.IR.Element.root/3` under `responsive: true` (spec/02 §2.1); when false neither attribute is present. The round-trip case is `ResizeHook` (§10) on the container, with the pushed size assigned to `width` and `height`.
- `class` (`:string`, default `nil`) is accepted by every component and placed on the `<svg>` as `class={class}`; when `nil` the attribute is absent.
- `title` and `description` (`:string`, default `nil`) are accepted by every component (D-56). When `title` is given the `<svg>` carries it as `aria-label`, and when `description` is given a `<desc id>` is its first child and `aria-describedby` names it (D-142; a description with no title is named by `aria-labelledby`, pointing at the `<desc>`), with the id `Visualize.IR.Element.root/3` derives from the two texts (spec/02 §2.1); when neither is given no child, no `aria-label` and no `aria-labelledby` are present. **The name is never a `<title>` child** (#803, D-201): a browser shows an SVG's `<title>` as a native tooltip under the pointer, so a name there would follow every reader's cursor over the chart, and `aria-label` names a `role="img"` element to every major screen reader without one. Every chart SHOULD be given a title: without one a screen reader announces an unnamed image.
- `theme` (`:any`, default `nil`) is accepted by every component: a `Visualize.Theme` ([08-utilities](08-utilities.md) §7), `nil` meaning `Visualize.Theme.default/0`. Every color, font and size a component draws with that is not an explicit assign is a slot of that theme resolved with `Visualize.Theme.resolve/3` in `:css` mode, so the markup carries `var(--vis-…, literal)` references a stylesheet can override (D-55) — save a label on a fill, the pie's and the sunburst's, which is inked by contrast with its element's fill as a literal (2.5, 3.4, D-123); the `<svg>` carries `font-family={resolve(:font_family)}` so every text inherits the theme's font; the axes take the theme through `Visualize.Axis.theme/2`. A color assign (`fill`, `stroke`, `node_fill`, `node_stroke`, `link_stroke`) defaults to `nil`, which resolves to the slot named in the component's table; a string is used as given.
- `animate` (`:boolean`, default `false`) is accepted by every component; when true, every data mark carries `style="transition: all 0.3s ease-in-out;"` so DOM patches animate via CSS, the `<svg>`'s class gains `vis-animated`, and a `<style>` after the `<desc>` stops it for a reader who asks for less motion — `@media (prefers-reduced-motion: reduce) { svg.vis-animated * { transition: none !important; } }`, which beats the inline style (D-142, [14-declarative-chart](14-declarative-chart.md) §21.6); when false a mark carries no `style` attribute and there is no `<style>`.
- `margin` is merged over the component's default margin with `Map.merge/2`, so a partial map such as `%{left: 60}` overrides one side only. `inner_width = width − left − right`, `inner_height = height − top − bottom`, and the plot area is a `<g transform="translate(left, top)">`.
- Axes are the frame's (spec/14 §4.4) — byte for byte `Visualize.Axis.bottom/1` and `Visualize.Axis.left/1` over the realized scales, rendered with `Visualize.Render.to_string/2` — placed by the template into `<g class="x-axis" transform="translate(0, inner_height)">` and `<g class="y-axis">` through `Phoenix.HTML.raw/1`.
- `data` is `:any`: a row list, or any other source `Visualize.Data.Table.rows/1` accepts ([08-utilities](08-utilities.md) §6) — a column map, a keyword list of columns, an Explorer DataFrame. The component reads it through `rows/1` once, before anything else; a row list is used as given.
- Accessor assigns (`x`, `y`, `value`, `label`, `size`) are `:any` and hold one-argument functions applied to each row of `data`.
- Every computed coordinate and length prints through `Visualize.IR.Path.format_number/1` (at most four decimals, never `-0`), as the axes and paths already do; assigns such as `width` and `margin` print as given.
- Empty `data` renders the frame — the `<svg>` and, where the chart has them, its axes — with no marks; it never raises (1.3).

### 1.3 Scale and color rules the components depend on

Every coordinate is the frame's scale applied by the mark that draws it (spec/14 §5.2), every path the generator the mark names (spec/14 §5.6, D-61), the axes section 1.2's. Three conventions are shared by every component that has the assign (D-45, D-64):

- **Colors.** A `colors` atom names a scheme of `Visualize.Scale.Color.schemes/0`; it is the `range` of the design's `color` scale, a `Visualize.Scale.Ordinal` over the mark indexes `0..n−1` (spec/14 §4.3), so the i-th mark takes the i-th color and the list cycles when there are more marks than colors. A `colors` list is used the same way, as given. An unknown scheme atom raises `ArgumentError` naming `schemes/0`; an empty list raises `ArgumentError`.
- **Continuous domains.** Every domain is inferred by the frame from the whole bound column (spec/14 §4.3): the extent of the values, time values ordered chronologically, `[0, max]` where a table below says so. A domain whose ends coincide — one datum, or every value zero on a `[0, max]` axis — stays `[v, v]`: the frame never widens (D-60), the scale maps every value to the range midpoint (D-49) and the axis draws one tick, so a single datum sits mid-axis, as it does in d3. A line or an area over a band x scale sits at the band centers (spec/14 §5.2); a band domain is the distinct categories in order of first appearance, so a repeated category is one band.
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
| `stroke` | `:string` | `nil` | line color, also the point fill; `nil` → `:series_1` |
| `stroke_width` | `:integer` | `2` | |
| `show_points` | `:boolean` | `false` | draw an `r="4"` circle at each datum |
| `x_label` | `:string` | `nil` | centered `<text class="axis-label">` below the x axis at `y = inner_height + margin.bottom − 5`, filled `:text` at `:label_size` |
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
| `colors` | `:any` | `:category10` | scheme atom or explicit color list; the i-th slice takes the i-th color (1.3) |
| `show_labels` | `:boolean` | `true` | |
| `animate`, `class`, `responsive`, `theme`, `title`, `description` | | | per 1.2 |

Slices are the preset's `:arc` mark — `Visualize.Shape.Pie` over `value` with `pad_angle`, then `Visualize.Shape.Arc` (spec/14 §5.6) — each a `<path d={arc} fill={color} stroke={:background} stroke-width="2">` inside `<g transform="translate(width/2, height/2)">`; with no data the group is empty. A label is a `<text text-anchor="middle" dominant-baseline="middle" font-size={:label_size} fill={ink}>` at `Visualize.Shape.Arc.centroid/2` of the slice — the mid-radius `(inner + outer)/2` at the slice's mid angle, which is the D3 convention `x = r·sin(a)`, `y = −r·cos(a)`. Its `ink` is the preset's `:contrast` (spec/14 §15.3, D-123): the theme's `text` or `background`, whichever reads on that slice's fill, as a literal — the one color a component draws that is not a `var(--vis-…)` reference (1.2), because it is chosen between literals. A slice too narrow for its whole label at the label's radius, by the layer's estimate of 0.6 em a character (spec/14 §5.5), draws no label (`fit: :hide`). The labels follow every slice in the group, in slice order, as the layer draws a labeled mark (#494).

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
| `stroke` | `:string` | `nil` | top-line color; `nil` → `:series_1` |
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
| `colors` | `:any` | `:category10` | scheme atom or color list, one per key in order (1.3) |
| `padding` | `:float` | `0.1` | |
| `animate`, `class`, `responsive`, `theme`, `title`, `description` | | | per 1.2 |

The preset's `:stack` transform yields one row per key per datum with `key`, `y0` and `y1` (spec/14 §5.4.1); the y domain is `[0, max(y1)]`, `[0, 1]` when there are no points (1.3). Each point is a `<rect x={band of x.(data)} y={scaled y1} width={bandwidth} height={scaled y0 − scaled y1} fill={series color}>`.

## 3. Visualize.Components.Tree

### 3.1 Functions

| Function | Contract |
|---|---|
| `Visualize.Components.Tree.tree_diagram/1` | Renders a node-link tree from nested data using the tidy tree layout (3.2): the `tree_diagram` preset. |
| `Visualize.Components.Tree.treemap_chart/1` | Renders a treemap of the hierarchy's leaves colored by the child of the root above each (3.3): the `treemap_chart` preset. |
| `Visualize.Components.Tree.sunburst_chart/1` | Renders a radial partition with one arc per non-root node of positive value, labeled (3.4): the `sunburst_chart` preset. |

Each function is the preset of the same name in `Visualize.Chart.Presets` (spec/14 §15.4), drawn by the layer as the components of §2 are: the assign mapping flattens the nested map into one row per node (spec/14 §15.2), the preset's transforms — `:tree`, `:treemap` or `:partition` over `Visualize.Layout.Hierarchy.stratify/2`, then the `:filter` steps that keep the rows this section draws — yield the laid-out rows, the marks draw them through `Visualize.Chart.Frame.generate/2`, and the component prints the markup below from the elements it returns, reading the rows (`Visualize.Chart.Mark.rows/3`) beside them for what depends on the node: the tree's node group (D-70). The treemap's and the sunburst's labels are their marks', fitted and inked by the layer (3.3, 3.4, #494, #497). `data` MUST be a map whose children are under `:children` or `"children"`; node labels default to `:name` or `"name"`, leaf values to `:value` or `"value"` (missing → 0). A root-only hierarchy is the empty case: the tree draws its one node, the treemap one cell, the sunburst no arc. `colors` follows 1.3 with one rule for which mark takes which index: the i-th child of the root takes the i-th color and every descendant of that child inherits it, so a whole top-level branch shares a color however deep it goes (D-46) — the design's `color` scale over the row's `branch`, bound through `Visualize.Chart.Style.bind/4`; the root itself, where drawn, is the theme's `:grid`. Coordinates print as in 1.2.

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

Layout is `Visualize.Layout.Tree` sized `[inner_height, inner_width]` for horizontal and `[inner_width, inner_height]` for vertical. Links are cubic Béziers between parent and child with both control points at the midpoint of the depth axis, `fill="none" stroke={link_stroke} stroke-width="1.5"`, drawn before the nodes. Each link is the `:path` mark's element — the row's `path` of the `:tree` transform, the link of the design's orientation (spec/14 §5.4.2, D-70) — and its `d` is `Visualize.IR.Path.to_string/1` of that path, the one `d` serializer of spec/02 §2.2 (D-34): commands concatenated, coordinates comma-separated, `M0,280C140,280,140,70,280,70`, never a form of the component's own (D-71). Each node is a `<g transform="translate(…)">` (horizontal swaps the layout's `x`/`y`) holding a `<circle r={node_radius} stroke={node_stroke} stroke-width="2">` filled `node_stroke` for an internal node and `node_fill` for a leaf (a node whose `children` is `nil` or `[]`), and a `<text dy="0.31em" font-size={:label_size} fill={:text}>`: horizontal labels sit at `x = −10` with `text-anchor="end"` for internal nodes and `x = 10`/`"start"` for leaves; vertical labels are centered at `x = 0`. A root-only hierarchy is one node at the origin of the plot area and no link.

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
| `colors` | `:any` | `:category10` | scheme atom or color list, by child of the root (3.1); the root itself, drawn only when it is the whole hierarchy, takes `:grid` |
| `animate`, `class`, `responsive`, `theme`, `title`, `description` | | | per 1.2 |

The hierarchy is summed with `value`, laid out with `Visualize.Layout.Treemap` at `{width, height}`, and only leaves are drawn, in hierarchy order: `<rect x={x0} y={y0} width={max(0, x1−x0)} height={max(0, y1−y0)} fill={color} stroke={:background} stroke-width="1">`. A zero-valued leaf keeps its zero-area cell (D-41). A label is a `<text x y dy="0.32em" text-anchor="middle" font-size={:label_size} fill={ink}>` at the center of its cell — the preset's mark label, `anchor: :middle` (spec/14 §5.5) — `ink` the preset's `:contrast` against the cell's fill as for the pie (2.5), and fitted by the layer (`fit: :truncate`): cut with `…` to the characters that fit the cell's width at 0.6 em a character, and not drawn when not even one character does or when the cell is shorter than the label's font size, so a zero-area cell has none (spec/14 §5.5, #497). The labels follow every cell, in cell order (#494). The root-only cell's fill in the layer is `:none` (D-122), so its label is inked against the background — on both built-in themes the theme's `text`, 9.6:1 against the `:grid` the component fills that cell with. Until #497 the component kept its own rule — a `fill={:background}` label with a text shadow at `(x0 + 4, y0 + 14)` in a cell wider than 30 and taller than 15, cut to `trunc((cell width − 8) / 7)` characters — the white-on-a-pale-fill defect D-123 names, which the shadow only half hid; the layer's fit replaced the rule and `:contrast` the ink, as #494 did for the pie and the sunburst. A root-only hierarchy is one cell the size of the `<svg>`.

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

The radius is `min(width, height)/2`. The summed hierarchy is laid out by `Visualize.Layout.Partition` sized `{2π, radius}` (spec/06 §4): the root spans `[0, 2π]`, each child a share of its parent's arc proportional to its summed value, and a node whose value is not positive a zero-width slot (D-41); ring radii are `depth / (height + 1) · radius` with `height` the root's. Every node of depth ≥ 1 whose angular extent is positive is a `<path fill={color} stroke={:background} stroke-width="1">` whose `d` is `Visualize.Shape.Arc` with `x0`/`x1` as the start and end angles — clockwise from 12 o'clock, the arc's own convention (spec/04 §7) — and `y0`/`y1` as the inner and outer radii, inside `<g transform="translate(width/2, height/2)">`. The root is not drawn, and a zero-extent node draws nothing. A label is a `<text text-anchor="middle" dominant-baseline="middle" font-size={:label_size} fill={ink}>` at `Visualize.Shape.Arc.centroid/2` of the arc, `ink` the preset's `:contrast` against the arc's fill as for the pie (2.5), and fitted by the layer (`fit: :truncate`, spec/14 §5.5): cut with `…` to the characters that fit the arc's length at mid-radius, `(x1 − x0) · (y0 + y1) / 2`, at 0.6 em a character, and not drawn when not even one character does. The labels follow every arc in the group, in arc order (#494). Until #494 the component kept its own rule — thicker than 15, longer than 30, `trunc((length − 8) / 7)` characters — and inked `:background`; the layer's fit replaced the one and `:contrast` the other, so a sunburst's label reads and fits by the same rule as every other mark label.

## 4. Visualize.Hooks

### 4.1 Functions

| Function | Contract |
|---|---|
| `Visualize.Hooks.js_code/0` | Returns the complete ES-module source: a header comment, `ZoomHook`, the sync bus `VisualizeSync` (`Visualize.Hooks.Sync.js_bus/0`, 4.3) — before every hook that uses it — `BrushHook`, the motion loop `VisualizeMotion` (`Visualize.Hooks.Motion.js_motion/0`, 4.5), the binary decoder (`Visualize.Hooks.CanvasBinary.js_decoder/0`), `CanvasChart`, `CanvasBinaryChart`, `CanvasIncrementalChart`, `ResizeHook`, the hit index's reader `VisualizeItems` (`Visualize.Hooks.Tooltip.js_items/0`, 12.5), `TooltipHook`, `CrosshairHook`, `LegendHook`, `BuilderHook`, `KeyboardHook`, `BoardHook`, `MotionHook`, then one `export default { … }` object listing the thirteen hooks — each name is exported exactly once (D-40, D-48). |
| `Visualize.Hooks.Sync.js_bus/0` | Returns the source of `const VisualizeSync = {…}`, the bus of 4.3 that `TooltipHook`, `CrosshairHook` and `BrushHook` share. It is not exported: it is the hooks' own, and a host joins a group through a design key, not through it. |
| `Visualize.Hooks.Motion.js_motion/0` | Returns the source of `const VisualizeMotion = {…}`, the frame loop of 4.5 that `CanvasChart` and `CanvasBinaryChart` share. Like the bus it is the hooks' own and not exported. |
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

**Implemented** (#466, D-116; the brush #467, D-117). Charts in one **sync group** share hover and the brush. A design joins one with `interaction: %{sync: "<group>"}` ([14-declarative-chart](14-declarative-chart.md) §2.9), and the markup then carries `data-vis-sync` and `data-vis-sync-x`. `TooltipHook` (12.4), `CrosshairHook` (13.4) and `BrushHook` (6.4) honor them with no host JavaScript, through one bus defined once in the bundle, `VisualizeSync`. The bus is plain DOM `CustomEvent`s on `document`, with no library.

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

### 4.4 View states as data

**Implemented** (#638, D-171). A hook draws a view state — the crosshair's and the tooltip's **hover**, the keyboard's **focus** — in an overlay of its own, outside the patched subtree, so the style stack that draws the chart (spec/14 §3.6) cannot reach it. The server therefore **resolves the state's style and hands it to the hook as data**, as it hands it every other thing the hook draws (D-75); the hook never resolves a style, a slot or a theme in the browser.

| Attribute | Written by | Drawn as |
|---|---|---|
| `data-vis-hover` | `Visualize.Hooks.Crosshair.attrs/3` (13.2) and `Visualize.Hooks.Tooltip.attrs/1` (12.1) | the palette's `:hover` |
| `data-vis-focused` | `Visualize.Hooks.Keyboard.attrs/1` (17.2) | the palette's `:focused` |

**The value** is a JSON object from an SVG presentation attribute's name to its value as a string, `{"stroke":"#333333","stroke-width":"2"}`:

- **The style** is the state's name looked up as every palette name is (spec/14 §3.3) against the frame the attributes are written for: the design's own `styles` entry of that name first, then the palette of the theme the frame is drawn with, the default theme's entry where that theme lacks one. A design that declares `hover:` restyles its hooks' hover, and a theme swap restyles every other design's.
- **It is resolved in `:literal` mode** (`Visualize.Chart.Style.resolve/3`), since an overlay outside the chart sits under no stylesheet that defines the theme's custom properties: a slot is its color, a dash list its string.
- **Only the keys an overlay shape draws are written:** `fill`, `fill_opacity`, `stroke`, `stroke_width`, `stroke_opacity`, `stroke_dasharray`, `stroke_linecap`, `stroke_linejoin` and `opacity`, each under its SVG name (`Visualize.SVG.Renderer.attribute_name/1`). A key whose value is a binding (`{:field, f}`) or a paint (`{:paint, name}`) is left out: the overlay has no datum and no `defs`. `:none` is `"none"`, a number prints through `Visualize.IR.Path.format_number/1`, an atom is its name.
- **The library writes the JSON**, every string escaped, so the attribute needs no JSON library.

**The hook lays the keys over its own defaults** on the overlay shape it draws the state with, and re-reads them on `updated()`, so a patch that changes the theme or the design restyles the next hover or focus. A key the object lacks keeps the hook's default. **A hook element without the attribute draws as before** — the marker's fixed look, or no hover outline at all for `TooltipHook` — so a host that mounts a hook over markup of its own, without the attribute helpers, sees no change.

### 4.5 Motion: the frame loop

**Implemented** (#653, work item #676, D-176). A canvas has no CSS, so a style's motion (spec/14 §3.10) is run by the hook that draws it, in a frame loop over `requestAnimationFrame`. `VisualizeMotion` is that loop's state and arithmetic, defined once in the bundle and used by `CanvasChart` (7.2) and `CanvasBinaryChart` (8.2).

**The state** is per hook: `VisualizeMotion.create()` answers `{shown, now, seen, span, active, reduced}`, where `shown` maps a key — an identity, the draw (`fill` or `stroke`) and a context property — to its motion `{from, to, start, duration, samples}`.

**A draw.** A hook replays a stream with the state: `begin(state, now)` before it (the clock, `reduced` read from `matchMedia('(prefers-reduced-motion: reduce)')` when the page has one, nothing active); the `motion` command or record sets `state.span` to `{id, box, transitions}` and `motionEnd` clears it; and every `fill` and `stroke` inside a span is made through `draw(state, ctx, op, fn)`. For a `fill` the properties are `fillStyle` (the transition's `fill`) and `globalAlpha` (its `opacity`); for a `stroke`, `strokeStyle` and `lineWidth` (its `stroke`) and `globalAlpha`. For each, the context's current value is the **target**:

- an identity's first draw shows its target, and starts nothing;
- a target that differs from the motion's `to` starts a motion from the value **shown now** — so a change in the middle of one goes on from where it stands — to the target, over the property's duration, unless the property does not move (no entry, a duration of `0`), the reader prefers reduced motion, or the two values cannot be mixed (a gradient, a hatch, a color it cannot parse), when it shows the target at once;
- the value shown is `from` mixed with `to` at the eased fraction of the time gone: the samples read piecewise linearly — the curve CSS's `linear()` draws — numbers mixed linearly and colors in OKLab, written `rgba(r, g, b, a)`; a color is read from `#rgb`, `#rrggbb`, `#rrggbbaa`, `rgb()` and `rgba()`, the forms a context answers.

`draw` sets the shown values, calls `fn`, and puts the targets back, so a draw after the span is untouched. `end(state)` drops every motion whose key the replay did not draw — an identity gone from the stream — and answers whether any motion is still running.

**The loop.** After a replay that leaves a motion running, the hook requests one animation frame, and that frame replays the same stream — its parsed commands or decoded bytes, kept — with the clock advanced; a new stream arriving meanwhile is drawn at once and the loop goes on with it. A replay that leaves nothing running requests nothing, so **a stream without a span costs one draw and no frame**, as before #653. `destroyed()` cancels a pending frame.

**Animations** (#677, spec/14 §3.11). `open` saves the context; when the span carries an animation and the reader does not prefer reduced motion, it reads the values at the time since the identity first drew it with that animation, less its delay — each property between the two keyframes about the fraction through the iteration that name it, the segment eased by the samples — translates by `x` and `y`, turns by `rotate` and scales by `scale` about the box's center, and keeps `opacity` as a factor `draw` multiplies `globalAlpha` by; `close` restores. A running animation keeps `active`, so the loop runs while any has iterations left. `VisualizeMotion.register(name, keyframes)` registers a host's keyframes — `[[offset, {opacity, x, y, rotate, scale}], …]`, a property absent where a keyframe does not name it — under the name a design's `animation.name` gives as a string; the hooks look a span's `null` keyframes up there, and run nothing for a name nobody registered.

**Enter and exit** (#678, spec/14 §3.12). A span's enter starts the first time the hook draws its identity — a key it has not shown — and runs once, its keyframes' values applied as an animation's are and composed with them. A span with an exit is recorded at `close`: the transform, the paint, the stroke, the width and the alpha the span opened with, its box, and a function that draws its commands again (`CanvasChart`: the parsed commands between the span's `motion` and `motionEnd`; `CanvasBinaryChart`: `executeVisualizeBinary` over the span's bytes, without motion). `end(state, ctx)` turns every recorded identity the replay did not draw into a **ghost** and draws every ghost over the stream: under the recorded state, its keyframes' values for `:fade`, `:shrink` and a registered name, and for `:explode` the sixteen pieces of spec/14 §3.12, each clipped to its cell; a finished ghost is dropped, and a running one keeps the loop. A reader who prefers reduced motion gets no enter and no ghost.

**Reduced motion** is read at every replay, so a reader who turns it on mid-motion sees the targets on the next frame, and no animation.



`test/visualize/hooks/motion_test.exs` executes it under the harness of spec/12 §6, whose stub runs `requestAnimationFrame` on its manual clock: a fill moving from one color to another through OKLab and reaching its end, a width moving numerically, a change in the middle, reduced motion, and a stream without a span requesting no frame; a pulse changing the alpha over time and repeating, a finite blink stopping, a spin turning about the box's center, a registered keyframe running, and reduced motion running none (#677).

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
| `data-brush-target` | unset | the `phx-target` both events are pushed to with `pushEventTo` — a LiveComponent's `@myself`, as a board's cell names its board (spec/15 §9.2); unset, they go to the LiveView with `pushEvent` |
| `data-brush-extent` | unset | `"x0,y0,x1,y1"`: clamps pointer positions and sizes the capture area; also supplies the full-height/width edges for 1-D brushes |
| `data-brush-color` | `"rgba(119, 119, 119, 0.2)"` | selection rectangle fill |
| `data-brush-stroke` | `"#666"` | selection rectangle stroke |

On mount the hook finds or appends a `<g class="brush-overlay">`, inserts into it a transparent `<rect class="brush-capture" cursor="crosshair">` covering the extent (or the SVG's bounding box) that receives pointer events, and a hidden `<rect class="brush-selection" stroke-width="1">` that displays the selection. Move and release listeners are attached to `document` so a drag may leave the SVG.

Coordinates are in the SVG's user coordinate system (`getScreenCTM().inverse()`), i.e. `viewBox` units — equal to CSS pixels only when the `viewBox` matches the rendered size. A brush starts on left-button mousedown or single-touch start on the capture rect; while brushing, `x1`/`y1` follow the pointer (`"x"` keeps `y0/y1` at the extent's edges, `"y"` keeps `x0/x1`). On release the selection is normalized so `x0 ≤ x1` and `y0 ≤ y1`; if either side exceeds 5 units it is pushed as `pushEvent(selectEvent, {x0, y0, x1, y1})` — with `domain` too in a sync group (6.4) or under a design's brush (6.5) — otherwise the gesture is treated as a click and cleared. Double-click on the capture rect clears. Clearing hides the rectangle and pushes `pushEvent(clearEvent, {})`.

On `updated()` the hook first finds its `<svg>` again: a server that redraws the chart replaces the `<svg>` or its children, which removes the overlay the hook drew there, so the hook takes the container's present `<svg>` and appends its overlay to it again when the overlay is no longer inside it. The capture rect, the selection and the listeners are the same elements, carried over (spec/15 §9.1, D-146). It then re-reads its sync group (6.4), then reads `data-selection-x0`, `-y0`, `-x1`, `-y1`; when all four parse it shows that selection (server-driven selection), without publishing it; else if `data-selection-clear="true"` it clears.

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
- on release, once more, the normalized selection's extent — the gesture's last event is the final window;
- a clear publishes `null`: a double-click, a release too small to be a selection (6.2), and a clear by `data-selection-clear` on `updated()`.

Only the chart under the pointer publishes. A selection the server sets through `data-selection-*` on `updated()` is not published, because the server set it on the chart it chose.

**Receiving.** A member ignores its own echo (4.3). It ignores any event while a brush of its own is in progress. Otherwise:

- `null` hides the band and forgets the selection.
- An extent is mapped by `toChartExtent` through the member's own numbers, clipped to its domain. A disjoint extent hides the band. Any other extent becomes the selection `{x0: c0, x1: c1}`, shown at once. Its `y0`/`y1` are the capture area's top and bottom (`data-brush-extent`'s, else the SVG's box), so the band spans the plot's height whatever the brush type.

A received extent **never calls `pushEvent`** and never publishes. The `brush_select` and `brush_clear` of a window change are pushed once, by the chart that was brushed, on release — never during the drag. A group of `n` charts therefore costs one server request per window, and the server learns of the window once.

**The pushed event.** In a sync group the chart brushed adds `domain: [lo, hi]` to `brush_select`'s payload, the same extent it published, so the server reads the window in domain units without knowing which chart sent it or holding its scale: `handle_event("brush_select", %{"domain" => [lo, hi]}, socket)`, `lo` and `hi` numbers (milliseconds since the Unix epoch for a time x). `x0`, `y0`, `x1`, `y1` are the chart's pixels as before. A member that shows a received band and is then double-clicked clears the group and pushes its own `brush_clear`: it is the chart that was acted on.

**Lifecycle.** `onSync` is bound once (D-47). `updated()` moves it when the group changed, and `destroyed()` removes it, so a remounted brush hears each event once and a destroyed one hears nothing.

`test/visualize/hooks/executed_hooks_test.exs` executes this (spec/12 §6): three brushes of different widths in one group, a fourth whose domain is disjoint from the window and a fifth whose domain holds part of it. Brushing one draws the band on every member at the same domain extent, at each member's own pixels, clips the partial member, shows nothing on the disjoint one, leaves another group untouched, and pushes exactly one `brush_select`, from the chart brushed, carrying the domain. A clear propagates with one `brush_clear`. `destroyed()` leaves no listener, and a remount hears once. The gallery's *Synced dashboard* page (`examples/lib/examples_web/live/dashboard_live.ex`) is three panels over one time axis, each joined to one group by one design key, with crosshairs and brushes synced. Each design also says `brush: :x` (spec/14 §2.9, #754, work item #771), so the page wraps each chart in a bare `BrushHook` element — no `data-brush-type`, no `data-brush-extent` — and the hook reads the brush's kind, the plot area and the `x` mapping from the chart itself. Its *Zone* links show the day in UTC, New York or Tokyo (spec/03 §7.4), and the brushed window is written in that zone with its length in the compound style (spec/05 §2.9, work item #773). Its *Requests* panel carries a two-line note in italic at a line height of its own (`font: %{style: :italic, line_height: 1.4}`, a newline breaking the text; spec/14 §7.1, work item #774).

### 6.5 The design's brush

**Implemented** (#565, D-143). A design that says `interaction: %{brush: :x}` ([14-declarative-chart](14-declarative-chart.md) §2.9) carries its brush on the brush frame's group: `data-vis-brush` (the kind), `data-vis-brush-x` (`d0,d1,x0,x1,width`, as `data-vis-sync-x`) and `data-vis-brush-extent` (`x0,y0,x1,y1`, the plot area in the chart's coordinates), from `Visualize.Chart.Frame.brush_attrs/1`. The hook reads them from its own element when it carries `data-vis-brush`, else from its first descendant that does — the frame's group inside the `<svg>` that `Visualize.Chart.render/2` writes with `root: true`, or the container a canvas page puts them on — on `mounted()` and again on `updated()`, since a chart re-rendered for a new window or a new width has new numbers:

- **Type.** The element's own `data-brush-type` wins; without one the brush is the design's kind, `"x"`.
- **Extent.** The element's own `data-brush-extent` wins; without one it is the design's `data-vis-brush-extent`, so the capture area and a `"x"` band span the plot and nothing else. `updated()` moves the capture area to the extent it reads.
- **Domain.** The hook maps a selection's x edges to the domain through `toDomain` (4.3) over the design's `d0,d1,x0,x1` — the sync group's numbers when the chart is in one, which are the same — and adds `domain: [lo, hi]`, ascending, to **every** `brush_select` it pushes, not only in a sync group: `handle_event("brush_select", %{"domain" => [lo, hi]}, socket)`, `lo` and `hi` numbers, milliseconds since the Unix epoch for a time x. `x0`, `y0`, `x1`, `y1` are the chart's pixels as before.

A host therefore attaches `phx-hook="BrushHook"` with a `data-brush-event` to a container around the rendered chart and reads the window from `domain`: it holds no margin, no plot width and no scale to invert. A design without `brush` writes nothing, and a hook with no design brush and no sync group behaves exactly as 6.2 says. `test/visualize/hooks/executed_hooks_test.exs` executes it: a design-brushed chart with no sync group captures its plot area and pushes the window in domain units, a re-render to a new window is read on `updated()`, and an element's own type and extent win over the design's.

## 7. Visualize.Hooks.Canvas

### 7.1 Functions

| Function | Contract |
|---|---|
| `Visualize.Hooks.Canvas.js_hook/0` | Returns the source of `export const CanvasChart = {…}` (7.2). |

### 7.2 `CanvasChart` behaviour

Attach with `phx-hook="CanvasChart"`, an `id` and `phx-update="ignore"` on a container holding a `<canvas>`; when the container has none, `mounted()` appends one sized from `data-width`/`data-height` (defaults `800`/`600`). The hook renders on `mounted()`, on `updated()`, and on a `canvas_commands` event whose payload MAY carry `commands` and/or `script`, each stored into the matching data attribute before rendering.

**The commands may arrive in segments** (#813, D-203): an element carrying `data-stream` reads, in place of `data-commands`, the `data-c` of every child of the element beside it carrying `data-vis-stream`, in order — the segments of `Visualize.Render.Segments.json/2` — joined by commas and bracketed, and skips the drawing named by `data-drawn` when it is the one last drawn. `Visualize.Components.Chart` draws this way (19.3).

Rendering reads `data-commands` — the `:json` output of `Visualize.Backend.Canvas` (spec/09 §3.5) — or, when that is absent, `data-script` — its `:js` output (spec/09 §3.4), which is what `Visualize.Backend.Hybrid` emits under each attribute name (spec/09 §6.3). A value equal to the last one rendered is skipped. The hook resets the transform, clears the canvas, then for JSON executes each `{"cmd", "args"}` object as `ctx[cmd](...args)`, or as the property assignment `ctx[name] = args[0]` when `cmd` starts with `set_`; for a script it calls `new Function('ctx', script)(ctx)`. Every command tuple names a Canvas 2D method (D-37) but four: `nonScalingLineWidth` sets `lineWidth` to its argument divided by `√|a·d − b·c|` of `ctx.getTransform()`, a stroke that keeps its width on screen (spec/09 §3.3.3, spec/14 §3.9, #651); and `linearGradient` and `radialGradient` set `fillStyle` or `strokeStyle`, as their first argument names, to the gradient `visualizeGradient` (8.1) builds from the rest — the geometry in user units and the stops — so a gradient fill draws as SVG's does (spec/09 §3.3.3, #652). `hatchPattern` sets the style its first argument names to the `CanvasPattern` `visualizePattern` (8.1) makes (#673). `motion` and `motionEnd` begin and end a motion span (spec/09 §3.3.5, #653): the hook draws every `fill` and `stroke` inside one through `VisualizeMotion` (4.5) and runs its frame loop while a motion is running, replaying the parsed commands of the last value each frame; a `data-script` draws without motion.

## 8. Visualize.Hooks.CanvasBinary

### 8.1 Functions

| Function | Contract |
|---|---|
| `Visualize.Hooks.CanvasBinary.js_decoder/0` | Returns the source of the exported functions `decodeBase64(base64)` (standard Base64 to a `Uint8Array`), `drawSvgArc(ctx, x1, y1, rx, ry, phi, fA, fS, x2, y2)` (the SVG endpoint-to-center conversion, as `Visualize.Backend.Canvas.Arc` on the server), `visualizeGradient(ctx, target, kind, geometry, stops)` (sets `ctx[target + 'Style']` to a `createLinearGradient(x0, y0, x1, y1)` or a `createRadialGradient(cx, cy, 0, cx, cy, r)` with one `addColorStop(at, color)` per `[at, color]`), `visualizePattern(ctx, target, pattern, angle, spacing, width, color, background)` (sets `ctx[target + 'Style']` to a hatch's `CanvasPattern`: an offscreen tile `⌈4·spacing⌉` pixels square drawn as spec/09 §3.3.3 draws it, the pattern's transform `rotate(angle)` and `scale(spacing / n)`), `drawVisualizePaint(ctx, op, paint, box)` (draws the current path's fill or stroke, `op`, with a paint in box units over a box: spec/09 §3.3.3's mapping, in a `save`/`restore`, nothing on a box without area) — a hatch drawn whatever the box and `executeVisualizeBinary(ctx, bytes, startOffset, endOffset, motion)` (8.3). |
| `Visualize.Hooks.CanvasBinary.js_hook/0` | Returns the source of `export const CanvasBinaryChart = {…}` (8.2); requires `js_decoder/0` in the same module. |

### 8.2 `CanvasBinaryChart` behaviour

Attach as for `CanvasChart` (7.2). The hook renders on `mounted()`, on `updated()`, and on a `canvas_update` event with a `binary` key, which it stores into `data-binary` first. Rendering reads `data-binary` (a `Visualize.Backend.CanvasBinary.to_base64/1` string), skips a value equal to the last rendered, resets the transform, clears the canvas and calls `executeVisualizeBinary(ctx, decodeBase64(value))`. **Motion** (spec/14 §3.10, #653): a stream with motion spans is replayed in the frame loop of 4.5, the decoded bytes of the last value kept for its frames, `executeVisualizeBinary(ctx, bytes, 0, bytes.length, motion)`; a stream without one is drawn once. **The canvas is transparent where the stream draws nothing** (#476): the clear is `clearRect`, and neither the hook nor the stream paints a background, so a page's backdrop stacked beneath the canvas — a basemap's tiles (spec/14 §12.4) — shows through it. `CanvasIncrementalChart` clears the same way (9.2). **A canvas draws only what is its own** (#432). A design has one plot per frame (spec/14 §12.1) and a page therefore has one canvas per frame, all of them hearing every pushed event: an element carrying `data-frame="<name>"` ignores a payload whose `frame` is another name. An element without `data-frame`, or a payload without one, draws as it always did, so a page with a single canvas is unchanged.

**The stream may arrive in segments** (#813, D-203): an element carrying `data-stream` reads, in place of `data-binary`, the `data-c` of every child of the element beside it carrying `data-vis-stream`, in order — the base64 segments of `Visualize.Render.Segments.binary/2` — each decoded and the bytes concatenated, and skips the drawing named by `data-drawn` when it is the one last drawn; a resize forgets it, as it forgets the last `data-binary`. `Visualize.Components.Chart` draws this way (19.3).

**The canvas follows its element's size** (#456, #455). The canvas's drawing size is its element's `data-width` × `data-height` at every draw: on `mounted()`, on `updated()` and before drawing a pushed payload, the hook compares `canvas.width`/`canvas.height` with the two attributes read as integers and, where they differ, sets them; an attribute that is missing or not a positive integer leaves the canvas as it is. Setting the size clears the canvas, so a size change redraws the current `data-binary` even when it equals the last value rendered — the skip applies to an unchanged value on an unchanged canvas only. The reason: a page that measures itself (10.2, #434) re-renders the chart at the measured size, and a canvas sized once, when the hook first created it, kept its mount size of 600×400 while the stream it replayed was laid out for about 1336×890 and the SVG layers over it grew — most of the data drawn off the canvas, under an overlay at the large size. The hook only created a canvas when the element held none, and the markup a page renders always holds one, so the size the page gave was never read.

**The hook acknowledges `canvas_update` frames when asked** (#322), exactly as `CanvasIncrementalChart` does (9.2, D-107): a payload may carry a `seq`, and an element carrying `data-ack="<event>"` pushes `<event>` with `%{seq, drawn, at}` at most once per `data-ack-interval` ms (default 100), with a trailing flush — so a page streaming whole frames to the binary canvas at a rate can see and bound what the browser has drawn, as a page streaming increments can.

### 8.3 The decoder

`executeVisualizeBinary(ctx, bytes, startOffset, endOffset, motion)` replays the records of spec/09 §4 from `startOffset` (default `0`) up to `endOffset` (default `bytes.length`) and returns the offset reached. Per opcode: `path` begins a path, `moveTo` the first point and `lineTo` the rest; `path_cubic` begins a path and executes each sub-opcode against a tracked current point and subpath start (`Z` returns to the start; `A`/`a` go through `drawSvgArc`); `path32` and `path_cubic32` are the same two cases reading each coordinate with `getFloat32` and advancing by its 4 bytes (spec/09 §4.3.8–4.3.9), the sub-opcode table shared between the two command-stream records so a command is decoded by one function taking the width; `cubic_run` begins a path, `moveTo` the start point and `bezierCurveTo` each six-f32 entry in turn (spec/09 §4.3.10); `circles` and `rects` begin one path holding every entry (each circle a `moveTo` to its rightmost point then a full `arc`), left for the following `fill`/`stroke` records; `style` assigns `fillStyle`/`strokeStyle` as `rgba(r,g,b,a/255)`, `lineWidth` and `globalAlpha` per its flags; `transform` kind `0x01` is `ctx.translate`, `0x03` `ctx.translate` then `ctx.scale`, `0xFF` `ctx.transform(a, b, c, d, e, f)` — composed onto the current transform, never `setTransform` (spec/09 §4.3.6); `save`, `restore`, `fill`, `stroke` are the calls. **The version 2 records** (spec/09 §4.2, #652): `version` reads its byte and throws on one above `4`; `clip` (version 4, spec/09 §4.3.18, #788) clips to the current path — `ctx.clip()` for inside, and for outside the ±100000 rectangle added to the path and `ctx.clip('evenodd')` — and `blend` (spec/09 §4.3.19) sets `globalCompositeOperation` to its word, each throwing on a byte it does not know, both context state that `save` and `restore` scope; `paint_state` (version 3, spec/09 §4.3.17, #675) sets `lineCap`, `lineJoin` and `setLineDash` and keeps the fill's and the stroke's own alpha, which `save` and `restore` push and pop with the paints, a `fill` or `stroke` drawn at `globalAlpha` times its alpha and the context's alpha set back after it; `paint` stores the paint of its index, its stops as `rgba()` strings; `box` keeps the box for the draws after it; `effect` (#674) sets `shadowColor`, `shadowBlur` and the two shadow offsets, or `filter`, as its kind says; `motion` (#653) parses its JSON, cached by its text, into the span of the fifth argument `motion`, a `VisualizeMotion` state, and `motion_end` ends it — without that argument both are skipped, so `CanvasIncrementalChart`'s strips draw their end state — and a `fill` or `stroke` inside a span is drawn through `VisualizeMotion.draw` (4.5); `style` bits 5 and 6 make the fill or the stroke that paint, bits 0 and 1 a color again, and the decoder keeps the two as state that `save` and `restore` push and pop beside the context's; a `fill` or `stroke` while a paint is current is `drawVisualizePaint(ctx, op, paint, box)` (8.1). The state is the call's own, so every stream — a region of an incremental record included — starts with no paint. An unknown opcode, sub-opcode or transform kind throws an `Error` naming the byte and offset: a mismatch with the encoder is a bug, not something to draw past. `test/visualize/hooks/canvas_hooks_test.exs` checks that the source has a `case` for every byte of `Visualize.Backend.CanvasBinary.Opcodes`, every sub-opcode `0x01`–`0x0F` and every transform kind, and that the `path32` and `path_cubic32` cases read `getFloat32`.

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
| `data-resize-target` | none | the `phx-target` the event is pushed to with `pushEventTo(target, eventName, payload)`, so a `Phoenix.LiveComponent` can host the hook — the chart builder's graph does (spec/14 §18.4, #613); absent, the event is pushed to the LiveView with `pushEvent` |

On mount the hook creates a `ResizeObserver` on the element. Every observation records the element's content box (`contentRect.width` and `contentRect.height`, each rounded to an integer) and restarts a timer of `debounce` milliseconds; when the timer fires — once per settle, however many observations a drag produced — the hook pushes `{width, height, reduced_motion}` under `eventName` — through `pushEventTo` when `data-resize-target` is set, `pushEvent` otherwise — unless that size equals the last size pushed; `reduced_motion` is whether `matchMedia('(prefers-reduced-motion: reduce)')` matches (`false` where `matchMedia` is absent). The hook listens for that query's `change` and pushes `{width, height, reduced_motion}` with the last size pushed whenever the answer changes, so a page compiles with `motion: :reduce` (spec/14 §21.6, D-142) from the first push on and follows the reader's setting live; `destroyed()` removes the listener. The first observation, which `ResizeObserver` delivers on `observe()`, therefore pushes the initial size after one debounce period, so a LiveView learns its container's width without a round trip of its own. `destroyed()` disconnects the observer and clears a pending timer, so nothing outlives the element (D-47). A browser without `ResizeObserver` gets no events: `mounted()` returns without observing.

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
| `Visualize.Hooks.Tooltip.attrs/1` | `attrs(frame)`: the hook element's `data-vis-hover` (4.4) for a realized `Visualize.Chart.Frame` — the palette's `:hover` as the frame's design and theme resolve it — as a map from attribute name (string) to value (string). `Visualize.Components.Chart` writes it (19.3). |
| `Visualize.Hooks.Tooltip.items/1` | `items(tree)`: the hook element's `data-vis-items` (12.5) for a chart's generated element (`Visualize.Chart.generate/2`), the drawing's hit index as JSON. `Visualize.Components.Chart` writes it on a canvas (19.3). |
| `Visualize.Hooks.Tooltip.js_items/0` | Returns the source of `const VisualizeItems = {…}`, the index's reader (12.5), which the bundle defines before `TooltipHook` and does not export. |

### 12.2 The datum attributes

The tooltip needs no round trip because the server writes each datum's fields onto the element that draws it, as data attributes, and the hook reads them under the pointer. `Visualize.IR.Element.datum/2` (spec/02 §2.1) is the writer, and every mark with a `tooltip` node ([14-declarative-chart](14-declarative-chart.md) §5.7) writes them through it; a hand-built chart calls it directly. The attributes are the contract (D-75):

| Attribute | On | Value |
|---|---|---|
| `data-datum` | every element that carries a datum | the field names, space-separated, in the order the fields were given — the order the tooltip lists them in |
| `data-datum-<field>` | the same element, one per field | the field's name with every `_` as `-` after `data-datum-`, and `to_string/1` of the value; a `nil` value writes no attribute, and the template reads it as `""` |
| `data-tooltip-template` | the element or any ancestor of it up to the hook element — a mark's group | the tooltip's text with `{field}` placeholders; the nearest one to the element wins |
| `data-tooltip-event` | likewise | the declared event a click delivers (19); absent, a click pushes nothing |
| `data-tooltip-context-event` | likewise | the declared event a secondary gesture delivers — a right-click, a long-press, the Menu key (#767, D-199); absent, the browser's menu shows and nothing is pushed |
| `data-tooltip-show` | likewise | `"false"` from a mark whose tooltip says `show: false` (#803, D-200): the hook shows no tooltip and no outline for the element; absent, it shows them |
| `data-frame` | a mark's group, with `data-tooltip-event` or `data-tooltip-context-event` | the name of the frame the mark is drawn in |
| `data-mark` | likewise | the mark's zero-based position among its frame's marks |
| `data-row` | every element that carries a datum, under a mark with an event or a context event | the datum's zero-based ordinal in the mark's realized rows ([14-declarative-chart](14-declarative-chart.md) §5.7) |

`Visualize.IR.Element.datum/2` takes the element and the fields as a map or a keyword list of `{field, value}` — a map's fields are written in `Enum.sort/1` order, a keyword list's in its own — and merges the attributes over the element's `attrs` under string keys (`"data-datum"`, `"data-datum-v"`), which `Visualize.SVG.Renderer.attribute_name/1` prints as given (spec/09 §2.4); an existing attribute of the same name is replaced. A field is an atom or a string; the value is any term `to_string/1` accepts, so a `DateTime` prints in ISO 8601 and a float with its decimals — the formatting a chart wants is the template's job, or the server's before it builds the map.

### 12.3 `TooltipHook` behaviour

Attach with `phx-hook="TooltipHook"` and an `id` on the `<svg>`, or on any ancestor of the elements that carry `data-datum`; one hook serves every mark under it. Data attributes read on `mounted()`:

| Attribute | Default | Meaning |
|---|---|---|
| `data-tooltip-class` | `"vis-tooltip"` | the class of the tooltip element the hook creates, for a stylesheet |
| `data-tooltip-target` | unset | the `phx-target` a click's event goes to with `pushEventTo`, as a board's cell and `Visualize.Components.Chart` name their own component (spec/15 §9.1, D-161, 19); unset, it goes to the LiveView. Read at each click, so a patch may change it |
| `data-tooltip-drawn` | unset | the holder's token for the drawing on screen (19, D-170), sent with a click; `null` when unset. Read at each click, so it is always the token of the SVG the click landed on |
| `data-vis-hover` | unset | the hover's style (4.4); set, the hook outlines the datum element it shows; unset, it draws no outline. Read on `mounted()` and `updated()` |

On `mounted()` the hook creates one `<div>` with that class, `position: absolute`, `pointer-events: none`, `white-space: pre` and `display: none`, appends it to `document.body`, and binds `mousemove`, `mouseleave`, `touchmove`, `touchend` and `click` on the element, each handler bound once and kept on the hook (D-47). On a move the *datum element* is the event target's nearest ancestor-or-self with `data-datum` (`closest`); none under the pointer hides the tooltip. Otherwise the text is built without a round trip: with a `data-tooltip-template` on the datum element or an ancestor of it — the nearest wins, searched no further than the hook element — every `{field}` becomes that field's `data-datum-<field>` value (`_` as `-`), `""` when the element has no such attribute; without a template, one line per field of `data-datum` in its order, `field: value`, joined with newlines. The text is set with `textContent`, never as markup, so a value is never interpreted. The tooltip is shown at 12 CSS pixels right of and below the pointer's page position, flipped to the left of the pointer when its width would cross the viewport's right edge and above it when its height would cross the bottom. A touch move uses its first touch; `touchend` and `mouseleave` hide. In a sync group (4.3) every move also publishes the pointer's x, and `touchend` and `mouseleave` publish a clear.

**The hover outline** (#638). With `data-vis-hover` on the hook element, the datum element the tooltip shows — under the pointer, or nearest another member's hover (12.4) — is outlined as the palette's `:hover`. The hook appends to `document.body`, once it first has a style to draw, an overlay `<svg class="vis-tooltip-hover">` (`position: absolute`, `pointer-events: none`, `overflow: visible`) holding one `<rect>`, placed over the element's bounding rectangle in page coordinates and padded by its stroke width plus 2 pixels, so the outline surrounds the element rather than covering it. The rectangle's defaults are `fill="none"`, `stroke="currentColor"` and `stroke-width="2"`, and the attribute's keys are laid over them (4.4). It is hidden whenever the tooltip is. An element without the attribute, or a patch that removes it, draws no outline, as before #638.

**Nothing under the pointer** (#803, D-200). A datum element whose nearest `data-tooltip-show` is `"false"`, searched as the template is, is shown as none is: a move over it hides the tooltip and the outline, and a sync group's hover (12.4) never picks it. Everything else the element carries is read as before — a click, a secondary gesture and the keyboard's keys (17) are unchanged.

A click on a datum element whose nearest `data-tooltip-event` is set, and which carries `data-row` under a nearest `data-mark`, pushes **one wire event, `visualize_event`** (#627, D-170): `pushEventTo(target, "visualize_event", payload)` when the hook element carries `data-tooltip-target`, else `pushEvent("visualize_event", payload)`. The payload is `{event, frame, mark, row, drawn, at, modifiers}`: `event` the nearest `data-tooltip-event`; `frame` the nearest `data-frame`, `null` without one; `mark` and `row` the nearest `data-mark` and the element's `data-row` as integers; `drawn` the hook element's `data-tooltip-drawn`, `null` without one; `at` the pointer in the user units of the element's nearest `<svg>` (`createSVGPoint` through `getScreenCTM().inverse()`), `{x, y}`, or `null` where there is no such `<svg>`; and `modifiers` the names of the held keys among `"shift"`, `"alt"`, `"ctrl"` and `"meta"`, in that order. **The hook sends no datum string**: the row is the server's to resolve, from the key, against the drawing it holds (19). A click on an element without an event, or on one without a key, pushes nothing; a click whose target has no datum element is resolved through the drawing's hit index when the hook element carries one (12.5, D-197), and pushes nothing otherwise. `updated()` re-reads the sync group (4.3). `updated()` also re-reads `data-vis-hover`. `destroyed()` removes the five listeners with the kept references, and the bus listener, and removes the tooltip element and the hover overlay from the document. `test/visualize/hooks/tooltip_test.exs` holds the source to this shape and executes the outline under the harness of spec/12 §6.

**A secondary gesture** (#767, D-199). The hook also binds `contextmenu` and `touchstart` on the element. A `contextmenu` whose target is an item a mark's `data-tooltip-context-event` keys — resolved as a click is, the datum element's key on an SVG, the hit index's item on a canvas (12.5) — calls `preventDefault()`, so the browser's menu does not open, and pushes `visualize_event` with that name in place of the click's, the rest of the payload as a click's; over an item whose mark declares none, or over nothing, the event is left alone and the browser's menu opens. A **long-press** is a single touch held for 500 ms without moving more than 10 CSS pixels from where it began: the hook resolves the touch's position — the element under it through `document.elementFromPoint` on an SVG, its client point on a canvas — and pushes the same context event; a move past 10 pixels, a second touch, `touchend` or `touchcancel` before then cancels it, and once it has fired the next `click` and `contextmenu` within 800 ms are swallowed (`preventDefault()`, nothing pushed), since a browser follows a long-press with one or both. `destroyed()` removes these listeners too, and clears a pending long-press.

### 12.4 In a sync group

**Implemented** (#466). A tooltip in a sync group (4.3) shows the datum nearest to another member's hover. On a received value the hook finds the value's client x, `rect.left + chartX · rect.width / width`, with `rect` the hook element's bounding rectangle. It then takes the `[data-datum]` element under the hook element — one a `data-tooltip-show="false"` hides is not a candidate (12.3, D-200) — whose bounding rectangle has its horizontal center nearest to that x, the first of two at the same distance. Its text is built as 12.3 builds it, and the tooltip is placed as for a pointer at that center and at the element's top, in page coordinates. With no datum element, a `null`, or a value outside the member's domain, the tooltip is hidden. Over a canvas there is no datum element, so a synced tooltip there shows nothing, and the crosshair is what shows the hover (13.4).

### 12.5 The hit index: a click on a canvas

**Implemented** (#764, D-197). A canvas draws no element per datum, so a click on it lands on nothing the hook can read a key from. The drawing therefore carries its **hit index** beside its stream: `data-vis-items` on the hook element, from `Visualize.Hooks.Tooltip.items/1`, with `data-size` (`width,height`, the chart's user units). It is built on the server from the **same generated tree** the canvas stream and the SVG are drawn from, and from the same attributes the SVG keys its elements by (12.2): every element carrying `data-row` under a mark's group carrying `data-tooltip-event` and `data-mark`. So the index names exactly the keys the SVG's elements carry, and a click resolves on the server as it does there (19.2).

The value is a JSON array with one entry per mark with an event or a context event, in drawing order, `{"event", "context", "frame", "mark", "items"}` — `event` and `context` the two declared names, either `null` where the mark declares none (#767, D-199) — and each item, also in drawing order, is its row's ordinal and its shape in the chart's user units, every group transform above it composed in:

| Item | Shape |
|---|---|
| `[row, "r", x, y, w, h]` | a rectangle, axis-aligned: a `rect` under no rotation or skew, or any other shape's bounding box |
| `[row, "c", cx, cy, r]` | a disc: a `circle` under a scale equal on both axes |
| `[row, "p", x, y, w, h, d, [a, b, c, d, e, f], fill, width]` | a path: its box in the chart's units, its `d` in its own units, the matrix from those to the chart's, `1` when it is filled and `0` when not, and its stroke's width (`0` for none) |

A rectangle and a disc take the pointer over their stroke too, so each is grown by half its stroke width, as SVG's `visiblePainted` hit area is; a path's box is grown the same way. A path is filled unless its fill, its own or the one its groups set, is `none`, as SVG inherits it. A rectangle under a rotation or a skew is written as the path it is. Numbers print through `Visualize.IR.Path.format_number/1`. A drawing with no keyed element carries `[]`.

**`VisualizeItems`**, defined before `TooltipHook` and not exported, reads it. The index is parsed once per value the attribute holds and kept on the hook. A client point is read on the chart — the hook element's first `<canvas>`, else its `<svg>` — through `data-size` as `KeyboardHook` places its marker (17.3), and a point outside the chart's rectangle is no point. The item under it is the **topmost**: the last entry, and in it the last item, whose shape holds the point — a rectangle by its box, a disc by its radius, a path by its box and then, where the browser has `Path2D`, by `isPointInPath` for a filled path and `isPointInStroke` at its stroke's width, on a context of the hook's own under the item's matrix; without `Path2D`, by its box.

**A click resolves through it** (12.3). When a click's target has no datum element and the hook element carries the index, the hook takes the item under the pointer and pushes `visualize_event` with the payload 12.3 gives, `{event, frame, mark, row, drawn, at, modifiers}`, `event`, `frame`, `mark` and `row` the item's entry's and its own, `at` the point in the chart's units. On an SVG drawing `at` is in the root `<svg>`'s user units, which are the chart's, so a click at one point of one chart pushes **the same payload on every backend**, and `Visualize.Event.resolve/3` makes the same event of it. A click over no item pushes nothing. The SVG carries no index: its elements are the keys. The resolution and the push are `VisualizeItems`' own, so a second hook resolves a click exactly as the tooltip does (#765, D-198): `key(root, cache, e)` is the key under a pointer event inside the tooltip's element `root` — the datum element's (12.3), else the index's item, `cache` keeping the parsed index — or `null`; and `send(hook, root, key, e)` pushes `visualize_event` for a key through `hook`, with `root`'s `data-tooltip-drawn` and `data-tooltip-target`.

## 13. Visualize.Hooks.Crosshair

### 13.1 Functions

| Function | Contract |
|---|---|
| `Visualize.Hooks.Crosshair.js_hook/0` | Returns the source of `export const CrosshairHook = {…}` (13.3). |
| `Visualize.Hooks.Crosshair.attrs/2` | As `attrs/3` with no options: the first mark. |
| `Visualize.Hooks.Crosshair.attrs/3` | `attrs(frame, sources, opts)`: the attributes of 13.2 for one mark of a realized `Visualize.Chart.Frame`, its `data-vis-hover` (4.4) among them, with the frame's sync attributes (`Visualize.Chart.Frame.sync_attrs/1`) merged in when it is the frame of a sync group (13.4), as a map from attribute name (string) to value (string), computed once on the server. `:mark` is the one-based position of the mark among the frame's marks (default `1`). Raises `ArgumentError` when the frame is a `:facet` or a `:polar` one — the crosshair is a cartesian interaction over one plot area — or when the mark has no `x` and `y` channels. |

### 13.2 The data arrays

The crosshair snaps to the data without a DOM: the server writes the mark's x pixels once, and the hook finds the nearest one to the pointer in that array. It therefore works over a mark the compiler sent to the canvas layer (spec/14 §12.3), which has no element per datum, exactly as over an SVG (D-76). `Visualize.Hooks.Crosshair.attrs/3` builds them from the rows a mark draws — `Visualize.Chart.Mark.rows/3` through the mark's channels and the frame's scales, the placed rows only (spec/14 §5.2) — and the host puts them on the hook element:

| Attribute | Value |
|---|---|
| `data-xs` | a JSON array of the distinct x pixels of the placed rows, ascending, in the plot area's coordinates — the array the pointer snaps to |
| `data-ys` | a JSON array with one entry per series — the `series` channel's distinct values in order of first appearance, one unnamed series without the channel — each an array parallel to `data-xs` of the series' y pixel at that x, the first row's when the series has several there, `null` where it has none |
| `data-plot` | `left,top,width,height`: the plot area inside the chart — the frame's margins and plot size — so the hook converts a pointer position into plot coordinates and spans the rule over the plot's height |
| `data-size` | `width,height`: the frame's size, the chart's `viewBox`, so a CSS-scaled chart maps the pointer correctly; absent, the hook takes the chart's own pixel size (13.3). Over a canvas it is also the canvas's drawing size: the host gives the canvas hook's `data-width` and `data-height` from the same realized frame (13.3) |
| `data-vis-hover` | the palette's `:hover` as the frame resolves it, the markers' style (4.4, 13.3) |
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
| `data-vis-hover` | unset | the hover's style (4.4), laid over each marker |

On `mounted()` the hook creates an overlay `<svg class="crosshair">` with `position: absolute` and `pointer-events: none`, appends it to `document.body` — never inside the container, so a LiveView patch of the chart neither removes it nor sees it — and inside it a group translated to the plot's origin holding a `<line class="crosshair-rule">` from `0` to the plot's height and one `<circle class="crosshair-marker" r="4">` per series of `data-ys`; the overlay is hidden until a move. It binds `mousemove`, `mouseleave`, `touchmove` and `touchend` on the container, each handler bound once and kept (D-47). On a move the hook reads the bounding rectangle of the *chart*, sizes and places the overlay over it with the chart's `viewBox` (`0 0 width height` of `data-size`, else the rectangle's size), converts the pointer into chart units by the ratio of the two, subtracts the plot's origin, and hides the overlay when the point is outside the plot area (in a sync group publishing a clear, 4.3); otherwise, in a sync group, it publishes the pointer's x, and it finds the nearest x by binary search over `data-xs` — the lower of two equidistant neighbors — moves the rule to it, moves each series' marker to its y there and hides a marker whose y is `null`, and, when `data-crosshair-event` is set and the index differs from the last pushed, pushes `pushEvent(event, {index})`, arriving as `handle_event("hover", %{"index" => 3}, socket)` with an integer. A touch move uses its first touch; `touchend` and `mouseleave` hide the overlay and, in a sync group, publish a clear. **The markers are the hover** (#638): each marker's fill is its series' color as above, and the keys of `data-vis-hover` are laid over it (4.4) — the built-in `:hover` rings each marker with a 2-unit stroke in the theme's `:text` — with the series' fill kept unless the style names one; the rule is the crosshair's own and keeps `data-crosshair-color`. Without the attribute a marker is its fill alone, as before. `updated()` re-reads the four arrays, the hover's style and the sync group, and rebuilds the markers when the series count changed; `destroyed()` removes the four listeners with the kept references, and the bus listener, and the overlay from the document. `test/visualize/hooks/crosshair_test.exs` holds the source to this shape.

**The chart, not the container** (#507). The chart is the container's first `<svg>` or `<canvas>` descendant in document order — the drawing the arrays describe — and the container itself when it holds neither. It is looked up on every move, since a patch may replace it. The pointer is still read on the container, which is where the listeners are. The container is measured no longer because a page lays it out, and its box is not the chart's. An `<svg>` or a `<canvas>` is an inline element: it sits on the text baseline, and the line's descender space below it makes the container a few pixels taller than the drawing. Through the container's rectangle, that gap became a vertical scale and an offset. On `/interaction` (16 px type, line height 1.6) the container was about 7 px taller than its 600 × 400 chart, and every marker sat about 3.7 px below its datum. A container wider than its chart would shift every marker sideways the same way.

**One size for the canvas and the arrays** (#507). A canvas stream draws at one canvas pixel per chart unit. A canvas whose drawing size is not the frame's `data-size` therefore crops the drawing or leaves part of the canvas empty. The overlay still maps the whole canvas onto the frame, so the markers land away from the series. The host gives the canvas hook's `data-width` and `data-height` from the same realized frame `attrs/3` reads (`applied.frame.size`), never from a constant kept beside the design. Before #507, `/interaction` drew a frame realized at the default 600 × 400 into a 720 × 380 canvas, a size its design had lost in #427. A marker landed up to 86 px from its datum, the pointer snapped to the wrong hour (19 for 23), and over the first hour it was read as outside the plot.

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
| `data-series` | every element a mark with a `series` channel draws for a series, and every inline label drawn for it (spec/14 §5.2, §5.6, D-126): a `:line` or an `:area` series' path; the datum's own element on every other type, such as the circles or symbols that draw a series' points; a `:rule`, `:x_band` or `:needle` datum's group | `to_string/1` of the series value; absent where the series reading is `nil` |
| `data-legend-event` | the hook element, set by the host | the event pushed on every toggle; absent, the hook pushes nothing |

The two strings coincide when the legend explains the `color` scale the series channel reads through — the usual case, where the scale's domain is the series values — and an entry whose string no element carries toggles nothing. A hand-built chart writes the same two attributes to take part.

**A toggle hides everything the series draws, or the series is not whole** (#508). The hook hides by the attribute, so each element of a series must carry it. A series drawn by several marks gives each of those marks the `series` channel. A line and its points are two marks, a `:line` and a `:circle` or a `:symbol`, each with `series`. Their elements then name the same series and take the same color (spec/14 §5.6). A mark that only colors its elements by the field, with a `{:field, f}` fill and no `series` channel, names no series. Its elements stay drawn when the legend hides the series.

### 14.3 `LegendHook` behaviour

Attach with `phx-hook="LegendHook"` and an `id` on the `<svg>`, or on any ancestor holding both the legend and the marks. On `mounted()` the hook gives every `.legend-item[data-series]` under the element `cursor: pointer` and binds one `click` listener on the element, bound once and kept (D-47); the hidden set starts empty. A click whose target is inside a `.legend-item[data-series]` toggles that series: when it becomes hidden, every element matching `.mark [data-series="<value>"]` under the hook element gets `display="none"` and the entry's group gets `class` `legend-item legend-item-hidden` and `opacity="0.35"`; when it becomes shown again, the `display` attribute is removed from those elements and the entry's class and opacity are restored. `display` is an SVG presentation attribute and applies in the SVG namespace, which the HTML `hidden` attribute does not (D-77). `updated()` re-applies the hidden set after a LiveView patch — the server re-renders the chart without knowing what the client hid, and the patch would otherwise show every series again — and re-sets the cursor on entries the patch replaced. When `data-legend-event` is set, every toggle pushes `pushEvent(event, {series, hidden})`, arriving as `handle_event("legend_toggle", %{"series" => "west", "hidden" => true}, socket)`; unset, nothing is pushed. `destroyed()` removes the click listener with the kept reference; the attributes it set stay on elements the DOM will discard with the hook's element. `test/visualize/hooks/legend_test.exs` holds the source to this shape, and `test/visualize/hooks/executed_legend_hook_test.exs` executes it (spec/12 §6, #508). That test runs the hook over the markup a chart with a `:line` and a `:circle` mark renders. Toggling an entry hides every element of that series, the path and each point, and no element of any other series. Toggling it again shows them all, and a patch keeps the series hidden.

## 15. Visualize.Chart.Builder

The embeddable builder for a stack of design fragments. What it is, what its host owns and what each panel shows is [14-declarative-chart](14-declarative-chart.md) §18; this section is its LiveView surface — the functions, the assigns and the markup contract the panels' goldens hold.

### 15.1 Functions

| Function | Contract |
|---|---|
| `Visualize.Chart.Builder.Preview.panel/1` | Renders the preview pane (spec/14 §18.4): `Visualize.Chart.render/2` of `Visualize.Chart.apply/2` of the `design` assign over `sources`, `vars` and `theme`, or the faults of application, each line `Visualize.Chart.Validator.format/1` of one error; a binding `Visualize.Chart.check_types/2` refuses is not applied and is drawn as the fault panel, `<div class="vis-builder-fault">` (spec/14 §18.4, D-153). |
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
| `Visualize.Chart.Builder.Preview.panel/1` | `design` (`:map`, required), `sources` (`:map`, `%{}`), `vars` (`:map`, `%{}`), `theme` (`:any`, `nil`), `catalog` (`:map`, `nil`: the connector catalog, whose schemas type a slot bound to one of its feeds), `class` (`:string`, `nil`) |
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

**Every form the builder renders carries an id** (#461, generalizing #444). LiveView recovers a form's state after a crash or a reconnect only by its id, warns of a `phx-change` form without one, and patches the page by id, so an id must be unique on the page. The rule therefore holds for every `<form>` with `phx-change` or `phx-submit`, not only the editor's and the parameters': each id is **derived from the panel's own id** — the `id` assign, which a host may give and must where two panels share a page — with a suffix naming the form, and, for a form repeated per row, the row's position on the page, so two forms on one page never share one and the same state renders the same ids. The forms and their ids, `<id>` being the panel's:

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
| the color picker, `vis-builder-picker` | `<id>` |
| the variable panel's find and create forms | `<id>-find`, `<id>-create` |
| an expanded variable's default, value and site forms | `<id>-var-<n>-default`, `<id>-var-<n>-value`, `<id>-var-<n>-site-<index>`, `<n>` the variable's position in the list, `<index>` the site's in the stack |
| a source's name, generator, signal and host-default forms, and its add-column form | `<id>-source-<n>-name`, `-generator`, `-signal`, `-default`, `-add-column`, `<n>` the source's position on the page |
| a column's name and type forms | `<id>-source-<n>-column-<m>-name`, `-type`, `<m>` the column's position in the source |
| the tick's period form, `vis-builder-tick-period` | `<id>-tick` |

LiveView's own check runs only where `Phoenix.LiveViewTest` drives a page through `live/2` or `live_isolated/3`, as it parses the HTML; a component rendered with `render_component/2` is never parsed, so the library's suite, which renders every panel that way, never sees the warning. A test of the library's own therefore holds the rule: every `<form>` tag in the library's source carries an `id`, and the builder rendered in every state that renders a form has no form without an id and no id twice on a page.

The preview pane is `<div class="vis-builder-preview">`. When the design applies it holds `<svg class="vis-builder-chart" width height role="img" viewBox="0 0 width height">` at the realized frame's own size, with the frame's group inside it: `Visualize.Chart.Frame.render/2` draws a group and the `<svg>` shell is the pane's, exactly as it is a component's (§1.2), and the markup is a string emitted through `Phoenix.HTML.raw/1` as §11.2 requires. Otherwise it holds `<ul class="vis-builder-errors">` with one `<li class="vis-builder-error">` per fault, in the validator's order. Exactly one of the two is present, so a test that asks whether the design applied asks for `vis-builder-errors`.

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
| `data-builder-frames` | the `<svg>` of the chart under a `graph` hook | every frame the chart draws as `name x y w h top right bottom left` — its pixel box in the chart's coordinates and its margins — the frames joined by `;` in drawing order, the last on top ([14-declarative-chart](14-declarative-chart.md) §18.4, #613) |
| `data-builder-frame-box` | the open frame's overlay in the chart under a `graph` hook | the frame's name: the outline and handles drawn over it while it is the open node ([14-declarative-chart](14-declarative-chart.md) §18.16, #614) |
| `data-builder-frame-cell` | the open frame's overlay | `c r a d`, the frame's cell and span, when it is placed by a cell of the layout (#617) |
| `data-builder-grid` | the open frame's overlay | the layout's columns and rows as fractions, `x w,x w;y h,y h`, when the design has a layout (#617) |
| `data-builder-frame-handle` | a corner handle of that overlay | `nw`, `ne`, `sw` or `se`: the corner a drag of it moves |
| `data-board-cell` | a cell of the grid under a `board` hook | the cell's name, which `board_place` carries ([14-declarative-chart](14-declarative-chart.md) §22.3) |
| `data-board-x`, `data-board-y`, `data-board-w`, `data-board-h` | a cell of the grid under a `board` hook | the cell's rectangle as the server placed it, the start of every drag |
| `data-board-handle` | a handle of a cell | `e`, `s` or `se`: which edges a drag of it resizes |
| `data-board-gap`, `data-board-row-height` | the grid under a `board` hook | the board's gap and row height in pixels, from which a pointer's travel is read as squares |

A `draggable="true"` element carrying `data-builder-layer` is a layer that can be dragged; a row carrying `data-builder-path` is one that can be clicked. An element carrying neither takes part in neither gesture, which is how one hook serves two panels without knowing which it is on.

### 16.3 `BuilderHook` behaviour

Attach with `phx-hook="BuilderHook"` and an `id`. On `mounted()` the hook binds `dragstart`, `dragover`, `drop`, `dragend` and `click` on its element, each handler bound once and kept on the hook (D-47), and reads `data-builder-target` once.

A `dragstart` on an element whose nearest `[data-builder-layer]` ancestor-or-self is inside the hook element records that position and its `data-builder-end`, and gives the element the class `vis-builder-layer-dragging`. A `dragover` calls `preventDefault()`, which is what makes a drop possible, and marks the gap under the pointer: the row whose position it is gets `vis-builder-layer-over`, and the last row `vis-builder-layer-over-end` for the gap at the end. A `drop` reads the gap under the pointer as a flat position ([14-declarative-chart](14-declarative-chart.md) §18.17) and pushes `reorder` with `{from, to}`, both integers, when the two differ and nothing when they do not. **Every position the hook sends is one the server wrote**: the gap before a drawn row is that row's `data-builder-layer`, the gap at the end is the last drawn row's `data-builder-end`, and the hook never counts elements — a closed group's rows are not drawn, so a count of drawn rows is not a flat position (#468, D-75); `dragend` clears both classes whether or not a drop happened. The hook moves nothing itself: the server owns the list, and the next render is the move.

A `click` whose target's nearest `[data-builder-path]` ancestor-or-self is inside the hook element pushes `inspect` with `{path, layer}`, the two attributes as strings, and marks that row `vis-builder-entry-open`, removing the class from every other row under the element — the highlight is the browser's because it needs no server round trip, and the selection is the server's because it changes what the editor edits. A click on anything else pushes nothing.

Both pushes go through `pushEventTo(target, …)` when `data-builder-target` is set and through `pushEvent(…)` when it is not. `destroyed()` removes the five listeners with the kept references. `test/visualize/hooks/builder_test.exs` holds the source to this shape.

**In scope `graph`** ([14-declarative-chart](14-declarative-chart.md) §18.16) a `click` whose target's nearest `[data-node]` ancestor-or-self is inside the hook element pushes `pick` with `{node}`, the attribute as a string, and pushes nothing for a click on anything else; no class is set by the click, because the server's answer re-renders the chart. On `mounted()` and on every `updated()` the hook reads `data-builder-selected` from the `<svg>` under it and gives `vis-builder-graph-selected` to every element whose `data-node` is the longest prefix of that label — equal to it, or followed in it by `.` or `[` — and to no other; with no `<svg>`, no label, or no element that fits, nothing is marked. The prefix rule is what lets the open form be a facet of a node the graph draws whole. The graph also **accepts a library drag and a component drag**: `dragover` with `application/x-visualize-fragment` or `application/x-visualize-component` among the types is allowed with `dropEffect` `copy`, and the `drop` pushes `place` — `{name, as}` for an entry, `{component}` for a palette row — with `x` and `y` in **chart coordinates**: the drop's client position relative to the `<svg class="vis-builder-chart">`, scaled by its `viewBox` width and height over its client width and height, so a 400×200 chart drawn at 800×400 reports half the pixel offset ([14-declarative-chart](14-declarative-chart.md) §18.16, §18.17). A `dragstart` on an element carrying `data-builder-component` sets that type with the component's word. **A drawn node is moved with the pointer, not with an HTML5 drag** (#277): `draggable` is an attribute of `HTMLElement`, and a browser does not start an HTML5 drag from an SVG element, which every drawn node is. So a `pointerdown` on a `[data-node]` element of the chart whose label is movable — an axis or the legend of any frame (`frames.<name>.axes[`, `frames.<name>.legend`), `labels[` ([14-declarative-chart](14-declarative-chart.md) §18.16) — captures the pointer and remembers the label and the start point; a `pointermove` more than four pixels from it marks the graph element `vis-builder-moving` and `vis-builder-region-<region>` for the region under the pointer, computed from `chartPoint` in the frame under it — the topmost frame of `data-builder-frames` whose box holds the point, else the nearest, the point taken into that frame's coordinates and classified against its size and margins, as `Visualize.Chart.Builder.Place.spot/3` and `region/2` do on the server (#613); `pointerup` releases the capture, clears both marks and, when the pointer had moved, pushes `move` with `{node, x, y}` — and when it had not, does nothing, so the click that follows selects the node as §16.3 above says. The palette's and the library's drags remain HTML5 drags, since their sources are HTML rows. With the graph focused, `Shift+ArrowUp/Down/Left/Right` push `move` with `{node, region}` for the `<svg>`'s `data-builder-selected` when it is movable, and `Shift+Enter` the `plot` region. Every `insert` a drop raises on the stack, and every `place` of an entry, carries `as`: `"link"` when `altKey` was held at the drop, `"copy"` otherwise.

**Frames in scope `graph`** (#614). A `click` whose target has no `[data-node]` ancestor-or-self inside the hook element pushes `pick` with `{node: "frames.<name>"}` for the topmost frame of `data-builder-frames` whose box holds the click's chart point, and nothing when none does. While the `<svg>`'s `data-builder-selected` is a frame itself (`frames.<name>`, nothing after the name), a `pointerdown` with the primary button that is not on a movable node starts a **move** when its chart point is inside that frame's box, and a **resize** of the two edges its corner names when it is on a `[data-builder-frame-handle]`; the pointer is captured on the hook element when the browser offers `setPointerCapture`, and `pointermove` and `pointerup` listeners are added to the hook element for the drag and removed at `pointerup`. Past four pixels of travel the hook marks the element `vis-builder-moving` and sets the outline's `x`, `y`, `width` and `height` and each handle's `x` and `y` to the box the drag gives — the fractions of the chart, its `viewBox`, that the pointer's travel adds, each moving edge snapped to the nearest of 0, ⅓, ½, ⅔, 1 and the other frames' edges within 8 pixels, a side kept at least 0.05 and the box inside [0, 1]. `pointerup` clears the mark, puts the overlay back where the server holds it, and, when the box changed, pushes `frame_box` with `{frame, box}`, the box `[x, y, w, h]` rounded to four places; when the pointer had not traveled it pushes nothing, so the click that follows picks, and the click that follows a drag is ignored. With the graph focused and a frame open, `ArrowLeft/Right/Up/Down` push `frame_box` with the box moved a twelfth that way, kept inside, and with Shift the right or bottom edge moved a twelfth instead, the side at least 0.05.

**On a layout** (#617), with `data-builder-grid` on the overlay, a frame whose overlay carries `data-builder-frame-cell` is dragged by cells instead: a body drag moves its cell to the column and row whose start is nearest the traveled edge, the span kept and the cell kept on the grid; a corner drag moves the named edges to the nearest cell start or end, a span at least one; the outline is drawn at the cells' box as it goes, and `pointerup` pushes `frame_cell` with `{frame, cell: [c, r], span: [a, d]}` when they changed. The keys step the cell, or with Shift the span, by one, kept on the grid, through the same push. A frame without a cell snaps, in addition to the lines above, to every column's and row's edges.

**In scope `board`** ([14-declarative-chart](14-declarative-chart.md) §22.3) the hook element is the board mode's grid, 12 columns wide. A `pointerdown` with the primary button on a `[data-board-cell]` inside it — not on a control of the cell, a `button`, `select` or `input` — starts a **move**, and on a `[data-board-handle]` a **resize** of the edges the handle names. A column's pitch is `(width + gap) / 12` of the grid's client width, and a row's `row_height + gap`, so a pointer's travel is a number of squares, rounded. While the pointer moves, the cell is marked `vis-builder-board-dragging` and drawn at the rectangle it would take — its `grid-column` and `grid-row` set — clamped to the grid: `x` from 0 to `12 − w`, `w` from 1 to `12 − x`, `y` and `h` not below 0 and 1. `pointerup` clears the mark and, when the rectangle changed, pushes `board_place` with `{cell, x, y, w, h}`, integers; when it did not, it pushes nothing, so the click that follows selects the cell. The hook never decides that a placement is allowed: an overlap is the server's to refuse, and the next render puts the cell where the server holds it. With a cell focused, an arrow key pushes `board_place` with the cell moved one square that way, and Shift with an arrow with it grown or shrunk by one on its right or bottom edge. The move and resize listeners are added to the hook element for the drag and removed at `pointerup`, with the pointer captured on it when the browser offers `setPointerCapture`.

## 17. Visualize.Hooks.Keyboard

**Implemented** (#558, D-142). A chart's points reached from the keyboard ([14-declarative-chart](14-declarative-chart.md) §21.5): the server writes every point once, with its readout and position, and the hook moves a focus marker and reads the point aloud. Like the crosshair (§13, D-76) it never reads the chart's DOM, so it serves an SVG and a canvas alike.

### 17.1 Functions

| Function | Contract |
|---|---|
| `Visualize.Hooks.Keyboard.js_hook/0` | Returns the source of `export const KeyboardHook = {…}` (17.3). |
| `Visualize.Hooks.Keyboard.attrs/2` | `attrs(applied, opts)`: as `attrs/1`; with `placements:`, `Visualize.Chart.placements/1` of the same chart, the points' positions are read from it rather than placed again (spec/14 §21.5, #811). |
| `Visualize.Hooks.Keyboard.listed/1` | As `listed/2` with `[]` options. |
| `Visualize.Hooks.Keyboard.listed/2` | `listed(applied, opts)`: the attributes of 17.2 with the points one element each (D-204), `{attrs, points, cache}`: `attrs` with `data-keyboard-series` in place of `data-keyboard-points`, `points` every point in series order as `{key, json}` — `key` the series' position and the point's, `"0.17"`, and `json` the point as `data-keyboard-points` writes it — and `cache` for the next call. `placements:` as `attrs/2`; `cache:` the last call's, so a point the same as last time is not written again. |
| `Visualize.Hooks.Keyboard.attrs/1` | `attrs(applied)`: the attributes of 17.2 for an applied chart, `data-vis-focused` (4.4) among them, as a map from attribute name (string) to value (string), computed once on the server. |

### 17.2 The attributes

| Attribute | Value |
|---|---|
| `data-keyboard-name` | the chart's name, `Visualize.Chart.Summary`'s (spec/14 §21.1) |
| `data-keyboard-points` | a JSON array with one entry per series, in the summary's order: `{"name": series, "points": [[x, y, readout], …]}`, `x` and `y` the point's position in the chart's pixels (`null` for a point with none) and `readout` its text (spec/14 §21.5). A point of a mark that declares an event, or of a grid, has two more entries, `[x, y, readout, key, cell]` (#765, D-198): `key` what a click on it sends, `{"event", "context", "frame", "mark", "row"}` — the mark's declared event and context event (either `null` where it declares none, #767), its frame's name, its position among the frame's marks and the row's ordinal in its realized rows, the key of 12.3 — or `null`; and `cell` its `[column, row]` in a grid, or `null`. A grid's series carries `"grid": true` |
| `data-keyboard-series` | from `listed/2`, in place of `data-keyboard-points` (D-204): a JSON array with one entry per series, `{"name", "count"}` and `"grid": true` for a grid, and each point the `data-p` of one child of the element inside the hook's carrying `data-keyboard-list`, in series order, as `data-keyboard-points` writes a point |
| `data-size` | `width,height`: the chart's size, its `viewBox`, so a CSS-scaled chart places the marker correctly; as `CrosshairHook` reads it (§13.2) |
| `data-vis-focused` | the palette's `:focused` as the applied chart's frame resolves it, the focus marker's style (4.4) |

The arrays are built by the library: every number prints through `Visualize.IR.Path.format_number/1` and every string is escaped for JSON here, so the attribute needs no JSON library.

### 17.3 `KeyboardHook` behaviour

Attach with `phx-hook="KeyboardHook"` and an `id` on a *container* holding the chart, with the attributes of 17.2 on it; they are read on `mounted()` and again on `updated()`, the position clamped to the new points. Set by the host: `data-keyboard-event`, the event pushed with `{series, index}` (zero-based) each time the focused point changes; unset, nothing is pushed. `data-keyboard-pick-event`, the event pushed with `{series, index}` when a point is **picked** (below); unset, nothing is picked. `data-keyboard-target`, the `phx-target` both events go to with `pushEventTo`, as a board's cell names its own component (spec/15 §9.1); unset, they go to the LiveView.

On `mounted()` the hook makes the container focusable — `tabindex="0"` — and gives it `role="group"` and an `aria-label` of `<name>, chart: arrow keys move between points`, each only where the host set none and again on every `updated()`, since a patch drops an attribute the server did not render; it appends to `document.body` — never inside the container, so a LiveView patch neither removes nor sees them — a visually hidden `<div class="vis-keyboard-readout" aria-live="polite">` and an overlay `<svg class="vis-keyboard-focus">` (`position: absolute`, `pointer-events: none`, hidden) holding one `<circle r="6">` with no fill and a 2-pixel stroke in `currentColor`. **The marker is the focus** (#638): the keys of `data-vis-focused` are laid over those defaults (4.4) — the built-in `:focused` is a 2-unit stroke in the theme's `:text`, dashed `4 2` — and re-read on every `updated()`; a key the style lacks keeps its default, and without the attribute the marker looks as it did before. It binds `keydown`, `focus` and `blur` on the container, each bound once and kept (D-47).

- **focus** reads, in the live region, `<name>: <s> series, <n> points.` — the series and the points of all of them — and marks nothing until a key is pressed.
- **ArrowRight** and **ArrowLeft** move to the next and the previous point of the series, **ArrowDown** and **ArrowUp** to the next and the previous series at the same index, clamped to its points, **Home** and **End** to the series' first and last point; the first such key after focus starts at the first point of the first series. Each stops at the ends rather than wrapping, calls `preventDefault()`, writes the point's readout to the live region, places the marker over the chart — its first `<svg>` or `<canvas>`, as the crosshair finds it (§13.3), through `data-size` — at the point's position, hidden for a point with none, and pushes `data-keyboard-event` when it is set.
- **In a grid** (a series with `"grid": true`, #765, D-198) the arrows move in its two dimensions instead: **ArrowRight** and **ArrowLeft** to the nearest point of the same row to the right and the left, **ArrowDown** and **ArrowUp** to the nearest point of the same column below and above, a cell without a point skipped; at the grid's edge the point stays, read again. Home and End are still the series' first and last point, which in a grid are its top-left and bottom-right cells.
- **The Menu key** (`ContextMenu`) or **Shift+F10** at a reached point whose `key` carries a `context` name pushes `visualize_event` with that name, the rest as Enter's click (#767, D-199) — Shift+F10's Shift is the gesture's, not among the `modifiers` — and calls `preventDefault()`; at any other point, or before one is reached, the key is left to the browser.
- **Escape** hides the marker and forgets the point; when the container sits inside an element carrying `data-vis-cell`, focus moves to that element (spec/14 §21.5).
- **Tab** is never handled: the chart is one stop, and the page's order — a board's cells — goes on past it.
- **blur** hides the marker and keeps the point, so focus coming back resumes there.
- **Enter** at a reached point picks it. A point with a `key` is **clicked** (#765, D-198): the hook pushes `visualize_event` as `TooltipHook` pushes a click (12.3), the key's `event`, `frame`, `mark` and `row`, `at` the point's position (`null` for a point with none), `modifiers` the keys held, and `drawn` and the target from the tooltip's element — the container's first descendant carrying `data-tooltip-drawn`, else `data-tooltip-target`, else the container — through `VisualizeItems.send` (12.5); so the host receives the `Visualize.Event` a click at the point's position sends. A point without a key is picked: with `data-keyboard-pick-event` set the hook pushes `{series, index}`. Either calls `preventDefault()`. Before any point is reached, Enter does nothing.
- **A click on a keyed item is the tooltip's** (#765, D-198). Before it picks, the hook asks `VisualizeItems.key` (12.5) of the tooltip's element whether the click lands on an item a mark's event keys — a datum element with `data-row` on an SVG, an item of the hit index on a canvas. If it does, `TooltipHook` sends it, and this hook pushes nothing: the point that item keys becomes the reached point. So one click is one event, with a pick event set or not; before #765 a board's cell sent both the mark's event and a pick.
- **A click** on the container picks the point nearest to it (#545). The click's position is read on the chart, its first `<svg>` or `<canvas>`, through `data-size` as the marker is placed. The nearest point is the one with the least horizontal distance, and of points within half a unit of that distance the one with the least vertical distance: the crosshair's snapping (§13.3), then the series nearest the pointer. Points with no position, and a click outside the chart's rectangle, pick nothing. A click that ends a drag is no pick: the hook keeps where the last `mousedown` was, and a click more than 3 CSS pixels from it is a brush, not a click (§6.2). A picked point becomes the reached point, so the arrow keys go on from it.

`destroyed()` removes the five listeners — `keydown`, `focus`, `blur`, `mousedown` and `click` — with the kept references and the two elements it appended. `test/visualize/hooks/keyboard_test.exs` executes it under the harness of spec/12 §6.

## 18. Visualize.Hooks.Board

**Implemented** (#575, D-146). The container of a live board (spec/15 §9): it tells the board's component how wide the board is, and it moves focus across the board's cells (spec/14 §21.5).

### 18.1 Functions

| Function | Contract |
|---|---|
| `Visualize.Hooks.Board.js_hook/0` | Returns the source of `export const BoardHook = {…}` (18.2). |

### 18.2 `BoardHook` behaviour

Attach with `phx-hook="BoardHook"` and an `id` on the board's container. The cells are its descendants carrying `data-vis-cell`, and their order in the document is their reading order. Data attributes, read on `mounted()`:

| Attribute | Default | Meaning |
|---|---|---|
| `data-board-event` | `"resize"` | the event pushed with `{width}` |
| `data-board-debounce` | `150` | milliseconds the width must hold before it is pushed |
| `data-board-clear-event` | `"select_clear"` | the event pushed when Escape clears the board's selection |
| `data-board-selection` | unset | set by the board's component while the board holds a selection (spec/15 §9.2) |

- **The width.** On `mounted()` the hook pushes the container's width: its bounding rectangle's, rounded, else its `offsetWidth`. Where the browser has `ResizeObserver`, it observes the container and pushes the width again once it has held for the debounce period. A width that is not positive, or the same as the last pushed, is not pushed. The push is `pushEventTo(this.el, event, {width})`, so it reaches the LiveComponent that rendered the container. A page with the board's component handles nothing.
- **The cells.** One `keydown` listener on the container acts only when the event's target is a cell itself (`data-vis-cell`). A key pressed inside a chart bubbles up with the chart's element as its target and is left to the chart's own hook. **ArrowRight** and **ArrowDown** move focus to the next cell, **ArrowLeft** and **ArrowUp** to the previous one, each stopping at the ends. **Home** and **End** move to the first and the last cell, and **Enter** moves focus to the cell's first descendant carrying a `tabindex`, its chart's `KeyboardHook` container. Each calls `preventDefault()`. **Tab** is never handled, so a cell stays one stop in the page's order. **Escape** inside a chart is `KeyboardHook`'s, which moves focus back to the nearest `data-vis-cell` (17.3).
- **The selection** (spec/15 §13.2, #545). Before the cell keys are read, an **Escape** whose target is anywhere in the container, a cell or a chart inside one, pushes `pushEventTo(this.el, clearEvent, {})` while the container carries `data-board-selection`, and nothing when it does not. It does not call `preventDefault()`, so the chart's own hook still hands focus back to the cell: one Escape inside a chart clears the selection and returns focus.

`destroyed()` removes the listener with the kept reference, disconnects the observer and clears a pending push. `test/visualize/hooks/board_test.exs` executes it under the harness of spec/12 §6, over cells carrying `data-vis-cell`.

## 19. Visualize.Event and Visualize.Components.Chart

**Implemented** (#627, D-170). Every interaction the library delivers to a host is one value, a `%Visualize.Event{}`, sent to the page's process as `{:visualize_event, id, event}`. A plain chart's mark click arrives so through `Visualize.Components.Chart`, and a board's click, drill, brush and selection through `Visualize.Components.Board` (spec/15 §9.2).

### 19.1 The event

| Field | Value |
|---|---|
| `event` | the name: a string for an event a design declares (a mark's tooltip `event`, [14-declarative-chart](14-declarative-chart.md) §5.7, an atom there delivered as its string), an atom for an event the runtime raises — `:drill`, `:brush`, `:select` (spec/15 §9.2) |
| `cell` | the board cell's name; `nil` outside a board, and for an event of the whole board (`:brush`, `:select`) |
| `frame` | the name of the design's frame the item was drawn in; `nil` where there is none |
| `item` | `{mark, identity}`: `mark` the mark's `id`, else its type; `identity` the source's declared identity of the row (spec/08 §10.1, D-167), bare for one field and a map for several, else the inference a board's pick uses (the mark's `series` field, else the first `:category` field of the slot's schema, spec/15 §13.2); `nil` when the row names nothing, or where there is no row |
| `path` | the items from the innermost out to the frame: `[item]`, or `[]` without one |
| `row` | the row the clicked element was drawn from, typed as the source holds it — a `DateTime` a `DateTime` — or the picked row of a drill; `nil` where there is none |
| `at` | the pointer in the frame's plot area, `%{x, y}` in pixels from its top-left; `nil` where there was no pointer |
| `value` | the event's data: `%{}` for a declared event; `%{board, vars}` for `:drill`, `%{domain}` for `:brush`, `%{identity}` for `:select` |
| `modifiers` | the keys held, `[]` or a list of `:shift`, `:alt`, `:ctrl` and `:meta` in that order |

Every field is always present. An event is a value: it holds no pid and no closure.

### 19.2 The wire and the resolution

`TooltipHook` pushes a click as `visualize_event` with the key of the element (12.3): the declared name, the frame's name, the mark's position, the row's ordinal, the drawing's token, the pointer and the modifiers. The server turns it into an event in two public steps, so a host that holds a chart's drawing itself can do what the component does:

- **`Visualize.Event.decode(params)`** reads the wire's params into a click map, `{:ok, click}`, or `:error` for params of any other shape. It creates no atom: the frame stays the string it was sent as, a modifier outside the four is dropped.
- **`Visualize.Event.resolve(click, applied, opts)`** resolves a click against the `%Visualize.Chart.Applied{}` that was drawn: `{:ok, event}`, or `:error` when the click's `drawn` is not the `drawn:` option (the token of the drawing held, `nil` by default), when the applied chart has no frame of that name, no mark at that position, or no row at that ordinal of the mark's realized rows (`Visualize.Chart.Mark.rows/3` over the applied chart's sources), or when that mark declares no event of that name. `cell:` sets the event's `cell`. The row is the realized row, so it is the row the element was drawn from, and `at` is the pointer less the frame's box and margins.

**A click is resolved against the drawing it landed on, or dropped** (D-170). Each holder keeps a token for its drawing, written on the hook element as `data-tooltip-drawn` in the same patch as the SVG, and new at each drawing. A click carrying another token was made on a drawing the holder no longer holds: it is dropped, never resolved against the newer rows, where its ordinal may name another row. An undeclared name, a key the drawing lacks, or params of another shape are dropped as well, so the client cannot invent an event, a row or a name.

### 19.3 `Visualize.Components.Chart`

A `Phoenix.LiveComponent`, compiled when `Phoenix.Component` is loaded:

```heex
<.live_component module={Visualize.Components.Chart} id="sales" chart={@applied} />
```

| Assign | Default | Meaning |
|---|---|---|
| `id` | required | the component's id, its hook element's DOM id, and the `id` of the events it sends |
| `chart` | required | the `%Visualize.Chart.Applied{}` drawn, from `Visualize.Chart.apply/2` |
| `render` | `[]` | options for `Visualize.Chart.render/2` (`title:`, `description:`, `responsive:` …); the SVG is always a root |
| `tooltip_class` | `"vis-tooltip"` | the hook's `data-tooltip-class` |
| `backend` | `:svg` | `:svg`, or `:canvas` to draw on a canvas with the drawing's hit index (12.5, D-197); anything else raises `ArgumentError` |
| `canvas_format` | `:binary` | on a canvas, `:binary` for `CanvasBinaryChart` or `:json` for `CanvasChart` |

It renders the chart's SVG, the markup of `Visualize.Chart.render(chart, [root: true] ++ render)` in keyed segments (below), inside a `<div phx-hook="TooltipHook">` carrying `data-tooltip-target` naming the component, `data-tooltip-drawn`, its token for the drawing, and `Visualize.Hooks.Tooltip.attrs/1` of the chart's frame, so the datum under the pointer is outlined as the palette's `:hover` (12.3, 4.4). A new `chart` or `render` is a new drawing with a new token; an update with the same ones keeps both. It handles one event, `visualize_event`: `decode/1`, then `resolve/3` with its drawing and token, then `send(self(), {:visualize_event, id, event})` to the page's process, whose one clause takes it:

**Reached from the keyboard** (#765, D-198). On every backend the component's `TooltipHook` element sits inside a `<div id="<id>-keys" phx-hook="KeyboardHook">` carrying `Visualize.Hooks.Keyboard.attrs/2` of the chart (17.2) — placed by the same pass as the drawing, `Visualize.Chart.placements/1` handed to both (spec/14 §21.5, #811) — so the chart is one tab stop whose points — every mark with an identity, a band grid's cells in two dimensions — the arrows reach, and Enter on a point a mark's event keys sends the page that event (17.3). The component sets no `data-keyboard-pick-event`.

```elixir
def handle_info({:visualize_event, "sales", %Visualize.Event{event: "point_click", row: row}}, socket) do
  {:noreply, assign(socket, picked: row)}
end
```

**On a canvas** (#764, D-197). With `backend: :canvas` the component generates the chart's tree once, `Visualize.Chart.generate(chart, resolve: :literal)`, and draws from it: the stream in the `canvas_format` — `Visualize.Render.to_string/2` with `backend: :canvas` and `format: :binary_base64` or `:json` — in a `<div phx-hook="CanvasBinaryChart">` or `<div phx-hook="CanvasChart">` with `phx-update="ignore"`, the stream in keyed segments beside it (below; before #813, whole in `data-binary` or `data-commands`), and `data-width` and `data-height` at the chart's size; and the hit index, `Visualize.Hooks.Tooltip.items/1` of the same tree, as `data-vis-items` with `data-size` on the `TooltipHook` element. The layers sit in a `<div class="vis-chart-layers">` of the chart's size, `position: relative`, which stands for the chart as `Visualize.Chart.Summary.attrs/2` makes it, with `Summary.description/2` inside: its name is the `render`'s `title:` when given, else the summary's. **The binary stream carries no text** (spec/09 §4.5), so on it the tree's text — every `text` element, with the groups above it — is laid over the canvas as an SVG of the chart's size, `aria-hidden`, in a `<div class="vis-chart-text">` at the layers' top left with `pointer-events: none`, so a click goes through it to the canvas; a chart with no text has no such layer, and the JSON stream draws its own text. A canvas drawing plays no motion through `MotionHook`: a canvas plays a style's motion itself (4.5). A new `backend` or `canvas_format` is a new drawing with a new token.

A click it cannot resolve sends nothing. A chart whose marks declare no event needs no component:
 it renders as SVG as before, under a `TooltipHook` of the page's own for its tooltips.

**What a move sends** (#813, D-202 – D-206). An update that changes a few items of a large drawing sends those items and no others, on every backend:
- **The drawing is keyed segments** (D-203). The SVG is `Visualize.Render.Segments.svg/2` of the root `Visualize.Chart.render/2` would serialize, rendered as a keyed LiveView comprehension, each segment written raw, so the markup is byte for byte the same as before; on a canvas the stream is `Segments.binary/2` or `Segments.json/2` of the tree, each segment the `data-c` of an `<i>` in a hidden `<div data-vis-stream>` beside the canvas hook's element, which carries `data-stream` and `data-drawn` in place of `data-binary` or `data-commands` (7.2, 8.2); the binary stream's text layer is `Segments.svg/2` of its SVG. LiveView sends a comprehension's changed entries only, so a move on a 2,500-cell grid sends one to three kilobytes where it sent 1.3 to 2.8 MB.
- **The keyboard's points are one element each** (D-204): the component writes `Visualize.Hooks.Keyboard.listed/2`, each point the `data-p` of an `<i>` in a hidden `<div data-keyboard-list>` first inside the keyboard's element, keyed, and `data-keyboard-drawn` with the drawing's token on that element.
- **Every other part is an assign of its own** (D-205) — the hit index, the summary, the canvas's size — so one a move does not change is not sent again; and the parts written per item keep a cache of what they wrote, so an item that did not change is not written again: the segments' (spec/09 §1.4) and the points' (`listed/2`). The hit index is computed whole: cached, it saved its 0.6 M reductions and cost as much again in copying its cache in and out of the drawing's process (D-206).
- **The drawing is made in a process of its own** (D-206), linked to the LiveView, sized by the heap the last drawing used and with a binary heap no drawing reaches, so it collects nothing; what it returns is copied into the LiveView's process and its heap is freed whole. A large chart allocates tens of megabytes per update, and collecting them in the LiveView's process, around its state, tripled the time of a move.
- **The drawing's heap is bounded** (#850, D-216). The process measures nothing about itself. A process that reads its own `garbage_collection_info` gets its heap block back as `heap_size`, not the words it used. Once the drawing has sent its parts and is waiting, the LiveView reads that info from outside and then lets the drawing end. The next drawing's minimum heap is a function of that one measurement. It never depends on the heap the drawing was given:
  - a drawing that did not collect is given the words it used, plus a quarter;
  - one that collected is given 16 times the data its collections kept, which is its old heap plus what the last collection left on its young heap (`old_heap_size` + `recent_size`). What it used is then only a lower bound;
  - the first drawing is sized by the BEAM.
  The minimum heap never exceeds the **bound**: 512 MiB in the system's words (`:erlang.system_info(:wordsize)`), 67,108,864 words on a 64-bit system. That is about 15 times what a 2,500-cell move needs (4.4 M words; about 1,800 words a cell). A drawing whose next size would pass the bound is spawned unsized, and the BEAM grows its heap as it does any process's. A drawing whose heap passes four times the bound is killed (`max_heap_size` with `kill: true`, reported to the logger). Being linked, it takes the component's LiveView with it, not the node. The sizes are not options: a host cannot raise them. The settled size of a chart is flat across moves, so a page can play for as long as it likes.
- **Socket compression is a host's option** and is not needed for the budget: Phoenix's `socket "/live", Phoenix.LiveView.Socket, websocket: [compress: true]` deflates every frame, which shrank the whole-drawing patch of #808 from 1.7 MB to 54 KB and shrinks a move's segments further, at the cost of a deflate context per connection; the budget of spec/12 §6 (D-202) is met uncompressed.

**Motion** (#678, spec/14 §3.12): when the drawing names identities — it holds `data-vis-id` — the SVG sits inside a `<div id="<id>-motion" phx-hook="MotionHook">` within the tooltip's element, so a row that leaves plays its exit (20); a drawing without one renders as before.

### 19.4 Functions

| Function | Contract |
|---|---|
| `Visualize.Event.decode/1` | `decode(params)`: the wire's `visualize_event` params as a click, `{:ok, %{event, frame, mark, row, drawn, at, modifiers}}`, or `:error` (19.2). |
| `Visualize.Event.resolve/2` | As `resolve/3` with `[]` options. |
| `Visualize.Event.resolve/3` | `resolve(click, applied, opts)`: the click resolved against the drawing of an applied chart, `{:ok, %Visualize.Event{}}` or `:error`; `drawn:` and `cell:` (19.2). |
| `Visualize.Event.declared/1` | The event names a chart's marks declare, as strings, sorted and unique: from a `%Visualize.Chart{}` or a `%Visualize.Chart.Applied{}`. |
| `Visualize.Event.name/1` | A declared name, an atom or a string, as the event's string. |
| `Visualize.Event.identity/3` | `identity(mark, row, schema)`: the row's identity in the board's selection form — `{field, value}`, a map for a composite declared identity, or `nil` — by the declared identity, else the inference (spec/15 §13.2); `schema` a `Visualize.Data.Schema` or `nil`. |
| `Visualize.Event.item/2` | `item(mark, identity)`: `{mark's id or type, identity}` with the identity bare for one field, or `nil` for a `nil` identity (19.1). |

## 20. Visualize.Hooks.Motion: MotionHook

**Implemented** (#653, work item #678, D-176 amended). The hook that plays a chart's exits and restarts its enters (spec/14 §3.12). It draws outside the patched subtree, as every hook does (D-75): a leaving element is no longer in the markup a patch leaves.

### 20.1 Functions

| Function | Contract |
|---|---|
| `Visualize.Hooks.Motion.js_hook/0` | Returns the source of `export const MotionHook = {…}` (20.2). |

### 20.2 `MotionHook` behaviour

Attach with `phx-hook="MotionHook"` and an `id` on an element holding a chart's `<svg>`. It reads no attribute of its own: the elements carry `data-vis-id` and, with an exit, `data-vis-exit` (spec/14 §3.12).

- **Before a patch** (`beforeUpdate()`): every element under the hook element carrying `data-vis-id` is recorded with the identity it carries; one that also carries `data-vis-exit` is copied — deeply, inside shallow copies of each ancestor up to the chart's `<svg>`, which bring its transforms and inherited paint — with the `<svg>`'s `viewBox` and bounding rectangle.
- **After a patch** (`updated()`): each recorded identity with an exit that no element carries now is played in the overlay; and each element that carried another identity before the patch has its nearest `vis-enter-` wrapper's class taken off and put back, after a layout read, so the browser runs its enter again.
- **The overlay** is one `<svg>` appended to `document.body` the first time an exit plays, positioned absolutely over the chart's rectangle (page coordinates, the page's scroll added), `pointer-events: none`, of the chart's `viewBox`. An exit's copy is appended under a wrapper `<g>`; the hook's frame loop (`requestAnimationFrame`) sets the wrapper's `opacity` and `transform` from the built-in's keyframes at the eased fraction of the time gone (spec/10 §4.5), or, for `:explode`, sixteen pieces — each a moving `<g>` over a `<g clip-path>` of its cell's `<clipPath>` holding a copy — moved, turned and faded as spec/14 §3.12 says; a host's name runs as `animation: <name> <duration>ms <easing> forwards` on the wrapper. At its end the wrapper is removed.
- **Reduced motion** (`matchMedia('(prefers-reduced-motion: reduce)')`): nothing is recorded or played, and no enter is restarted.
- `destroyed()` cancels the frame loop and removes the overlay.

`test/visualize/hooks/motion_hook_test.exs` executes it under the harness of spec/12 §6, over markup a board's cell rendered before and after its rows lost one: the gone row's copy is placed and exploded, its pieces moving outward and fading, and removed at the end; a `:fade` and a `:shrink`; an element that a patch gave another identity restarting its enter; and reduced motion placing nothing.
