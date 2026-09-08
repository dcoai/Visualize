# LiveView Integration

**Status:** Implemented

Visualize reaches the browser through Phoenix LiveView in three ways: HEEx function components (`Visualize.Components`, `Visualize.Components.Tree`) that build a complete chart from assigns; JavaScript hooks — `Visualize.Hooks.Zoom` and `Visualize.Hooks.Brush` add zoom/pan and brush selection to any SVG and report back to the LiveView as events, and `Visualize.Hooks.Canvas`, `Visualize.Hooks.CanvasBinary` and `Visualize.Hooks.CanvasIncremental` replay the Canvas outputs of spec/09 on a `<canvas>`, `Visualize.Hooks.Resize` reports a container's size so the server can re-render at it, `Visualize.Hooks.Tooltip` shows a datum's fields under the pointer from attributes the server wrote, and `Visualize.Hooks.Crosshair` snaps a rule and markers to the nearest x of an array the server wrote once — with `Visualize.Hooks` bundling them into one installable file and re-exporting the server-side helpers; and the `Phoenix.HTML.Safe` implementations that let element structs be interpolated into a template directly. This document is the contract for each: every assign a component reads, every data attribute and event a hook uses, and the maths of the helpers.

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
| `Visualize.Hooks.Tooltip` | always | `TooltipHook` JS: a tooltip from the datum attributes of an element, with no round trip |
| `Visualize.Hooks.Crosshair` | always | `CrosshairHook` JS and the server-side `attrs/3`: a rule and markers snapped to the data over SVG or canvas |

Both component modules are wrapped in `if Code.ensure_loaded?(Phoenix.Component)`. For that guard to be true in a host, `phoenix_live_view` MUST be a declared dependency of this library: Mix prunes the code path to a dependency's own declared deps while compiling it, so a guard over an undeclared module is always false in a host, whatever the host itself depends on. It is therefore declared `optional: true` (D-45): a host that has LiveView compiles the components, one that does not never fetches Phoenix, and `scripts/consumer_check.exs` proves the second claim on every pipeline ([12-testing-and-conformance](12-testing-and-conformance.md) §4). The library's own builds carry the optional dependency, so the components compile, are documented and are rendered under test here.

### 1.2 Conventions shared by every component

- Every component is a function component `name/1` taking an assigns map and returning rendered HEEx; it is used as `<.name … />` after `import Visualize.Components` (or `Visualize.Components.Tree`).
- Every component is a *preset design* of [14-declarative-chart](14-declarative-chart.md) §15 plus an assign mapping (D-64): the component's assigns go to `Visualize.Chart.Presets.design/2` for the design and to `Visualize.Chart.Presets.sources/2` for the rows its source binds to; `Visualize.Chart.Frame.new/2` realises the frame over them and `Visualize.Chart.Frame.generate/2` draws it, and the component prints the elements the layer returns in the markup this document declares — its HEEx template is the `<svg>` shell and the attribute order of each mark, nothing more. Every coordinate, path and paint below is therefore the layer's, and the render goldens of `test/support/components/` hold each component to what it drew before it was a preset.
- Every component declares its assigns with `attr/3`, so an unknown assign or a missing required one is a compile-time warning in the caller, and each listed default is applied by `Phoenix.Component`.
- Every component renders one `<svg width={width} height={height} role="img" viewBox="0 0 {width} {height}">`.
- `responsive` (`:boolean`, default `false`) is accepted by every component; when true the `<svg>` also carries `preserveAspectRatio="xMidYMid meet"` and `style="width:100%;height:auto"`, the CSS-scaled case of D-54, exactly as `Visualize.IR.Element.root/3` under `responsive: true` (spec/02 §2.1); when false neither attribute is present. The round-trip case is `ResizeHook` (§10) on the container, with the pushed size assigned to `width` and `height`.
- `class` (`:string`, default `nil`) is accepted by every component and placed on the `<svg>` as `class={class}`; when `nil` the attribute is absent.
- `title` and `description` (`:string`, default `nil`) are accepted by every component (D-56). When either is given, a `<title id>` and/or a `<desc id>` are the first children of the `<svg>`, and it carries `aria-labelledby` naming them, with the ids `Visualize.IR.Element.root/3` derives from the two texts (spec/02 §2.1); when neither is given no child and no `aria-labelledby` are present. Every chart SHOULD be given a title: without one a screen reader announces an unnamed image.
- `theme` (`:any`, default `nil`) is accepted by every component: a `Visualize.Theme` ([08-utilities](08-utilities.md) §7), `nil` meaning `Visualize.Theme.default/0`. Every colour, font and size a component draws with that is not an explicit assign is a slot of that theme resolved with `Visualize.Theme.resolve/3` in `:css` mode, so the markup carries `var(--vis-…, literal)` references a stylesheet can override (D-55); the `<svg>` carries `font-family={resolve(:font_family)}` so every text inherits the theme's font; the axes take the theme through `Visualize.Axis.theme/2`. A colour assign (`fill`, `stroke`, `node_fill`, `node_stroke`, `link_stroke`) defaults to `nil`, which resolves to the slot named in the component's table; a string is used as given.
- `animate` (`:boolean`, default `false`) is accepted by every component; when true, every data mark carries `style="transition: all 0.3s ease-in-out;"` so DOM patches animate via CSS; when false a mark carries no `style` attribute.
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

Slices are the preset's `:arc` mark — `Visualize.Shape.Pie` over `value` with `pad_angle`, then `Visualize.Shape.Arc` (spec/14 §5.6) — each a `<path d={arc} fill={colour} stroke={:background} stroke-width="2">` inside `<g transform="translate(width/2, height/2)">`; with no data the group is empty. A label is a `<text text-anchor="middle" dominant-baseline="middle" font-size={:label_size} fill={:background}>` — a label over a mark takes the background slot (1.2) — at `Visualize.Shape.Arc.centroid/2` of the slice — the mid-radius `(inner + outer)/2` at the slice's mid angle, which is the D3 convention `x = r·sin(a)`, `y = −r·cos(a)`.

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

Each function is the preset of the same name in `Visualize.Chart.Presets` (spec/14 §15.4), drawn by the layer as the components of §2 are: the assign mapping flattens the nested map into one row per node (spec/14 §15.2), the preset's transforms — `:tree`, `:treemap` or `:partition` over `Visualize.Layout.Hierarchy.stratify/2`, then the `:filter` steps that keep the rows this section draws — yield the laid-out rows, the marks draw them through `Visualize.Chart.Frame.generate/2`, and the component prints the markup below from the elements it returns, reading the rows (`Visualize.Chart.Mark.rows/3`) beside them for what depends on the node: the tree's node group, and the two label rules of 3.3 and 3.4 (D-70). `data` MUST be a map whose children are under `:children` or `"children"`; node labels default to `:name` or `"name"`, leaf values to `:value` or `"value"` (missing → 0). A root-only hierarchy is the empty case: the tree draws its one node, the treemap one cell, the sunburst no arc. `colors` follows 1.3 with one rule for which mark takes which index: the i-th child of the root takes the i-th colour and every descendant of that child inherits it, so a whole top-level branch shares a colour however deep it goes (D-46) — the design's `color` scale over the row's `branch`, bound through `Visualize.Chart.Style.bind/4`; the root itself, where drawn, is the theme's `:grid`. Coordinates print as in 1.2.

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

The hierarchy is summed with `value`, laid out with `Visualize.Layout.Treemap` at `{width, height}`, and only leaves are drawn, in hierarchy order: `<rect x={x0} y={y0} width={max(0, x1−x0)} height={max(0, y1−y0)} fill={colour} stroke={:background} stroke-width="1">`. A zero-valued leaf keeps its zero-area cell (D-41). A `font-size={:label_size} fill={:background}` label with a text shadow is drawn at `(x0 + 4, y0 + 14)` when the cell is wider than 30 and taller than 15, truncated with `…` to `trunc((cell width − 8) / 7)` characters. A root-only hierarchy is one cell the size of the `<svg>`.

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

The radius is `min(width, height)/2`. The summed hierarchy is laid out by `Visualize.Layout.Partition` sized `{2π, radius}` (spec/06 §4): the root spans `[0, 2π]`, each child a share of its parent's arc proportional to its summed value, and a node whose value is not positive a zero-width slot (D-41); ring radii are `depth / (height + 1) · radius` with `height` the root's. Every node of depth ≥ 1 whose angular extent is positive is a `<path fill={colour} stroke={:background} stroke-width="1">` whose `d` is `Visualize.Shape.Arc` with `x0`/`x1` as the start and end angles — clockwise from 12 o'clock, the arc's own convention (spec/04 §7) — and `y0`/`y1` as the inner and outer radii, inside `<g transform="translate(width/2, height/2)">`. The root is not drawn, and a zero-extent node draws nothing. A label is a `<text text-anchor="middle" dominant-baseline="middle" font-size={:label_size} fill={:background}>` at `Visualize.Shape.Arc.centroid/2` of the arc, drawn when the ring is thicker than 15 and the arc's length at mid-radius, `(x1 − x0) · (y0 + y1) / 2`, exceeds 30, and truncated as in 3.3 to that length − 8.

## 4. Visualize.Hooks

### 4.1 Functions

| Function | Contract |
|---|---|
| `Visualize.Hooks.js_code/0` | Returns the complete ES-module source: a header comment, `ZoomHook`, `BrushHook`, the binary decoder (`Visualize.Hooks.CanvasBinary.js_decoder/0`), `CanvasChart`, `CanvasBinaryChart`, `CanvasIncrementalChart`, `ResizeHook`, `TooltipHook`, `CrosshairHook`, then one `export default { … }` object listing the eight hooks — each name is exported exactly once (D-40, D-48). |
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

Attach with `phx-hook="BrushHook"` and an `id` on an `<svg>`. The hook uses `createSVGPoint` and `getScreenCTM` on the element, so it MUST be an `<svg>`. Data attributes read on `mounted()`:

| Attribute | Default | Meaning |
|---|---|---|
| `data-brush-type` | `"xy"` | `"xy"` rectangle; `"x"` horizontal band; `"y"` vertical band |
| `data-brush-event` | `"brush_select"` | event pushed when a selection ends |
| `data-brush-clear-event` | `"brush_clear"` | event pushed when the selection is cleared |
| `data-brush-extent` | unset | `"x0,y0,x1,y1"`: clamps pointer positions and sizes the capture area; also supplies the full-height/width edges for 1-D brushes |
| `data-brush-color` | `"rgba(119, 119, 119, 0.2)"` | selection rectangle fill |
| `data-brush-stroke` | `"#666"` | selection rectangle stroke |

On mount the hook finds or appends a `<g class="brush-overlay">`, inserts into it a transparent `<rect class="brush-capture" cursor="crosshair">` covering the extent (or the element's bounding box) that receives pointer events, and a hidden `<rect class="brush-selection" stroke-width="1">` that displays the selection. Move and release listeners are attached to `document` so a drag may leave the SVG.

Coordinates are in the SVG's user coordinate system (`getScreenCTM().inverse()`), i.e. `viewBox` units — equal to CSS pixels only when the `viewBox` matches the rendered size. A brush starts on left-button mousedown or single-touch start on the capture rect; while brushing, `x1`/`y1` follow the pointer (`"x"` keeps `y0/y1` at the extent's edges, `"y"` keeps `x0/x1`). On release the selection is normalised so `x0 ≤ x1` and `y0 ≤ y1`; if either side exceeds 5 units it is pushed as `pushEvent(selectEvent, {x0, y0, x1, y1})`, otherwise the gesture is treated as a click and cleared. Double-click on the capture rect clears. Clearing hides the rectangle and pushes `pushEvent(clearEvent, {})`.

On `updated()` the hook reads `data-selection-x0`, `-y0`, `-x1`, `-y1`; when all four parse it shows that selection (server-driven selection); else if `data-selection-clear="true"` it clears.

Events arrive as `handle_event("brush_select", %{"x0" => x0, "y0" => y0, "x1" => x1, "y1" => y1}, socket)` and `handle_event("brush_clear", %{}, socket)`. `mounted()` binds each handler once and stores the bound function on the hook (`onMouseDown`, `onMouseMove`, `onMouseUp`, `onTouchStart`, `onTouchMove`, `onTouchEnd`, `onClear`) before adding it as a listener, and `destroyed()` removes the four `document` listeners (`mousemove`, `mouseup`, `touchmove`, `touchend`) with those same references, so nothing outlives the element; the capture rect's own listeners are discarded with it (D-47). `test/visualize/hooks/brush_test.exs` holds the source to this shape.

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

Attach as for `CanvasChart` (7.2). The hook renders on `mounted()`, on `updated()`, and on a `canvas_update` event with a `binary` key, which it stores into `data-binary` first. Rendering reads `data-binary` (a `Visualize.Backend.CanvasBinary.to_base64/1` string), skips a value equal to the last rendered, resets the transform, clears the canvas and calls `executeVisualizeBinary(ctx, decodeBase64(value))`.

### 8.3 The decoder

`executeVisualizeBinary(ctx, bytes, startOffset, endOffset)` replays the records of spec/09 §4 from `startOffset` (default `0`) up to `endOffset` (default `bytes.length`) and returns the offset reached. Per opcode: `path` begins a path, `moveTo` the first point and `lineTo` the rest; `path_cubic` begins a path and executes each sub-opcode against a tracked current point and subpath start (`Z` returns to the start; `A`/`a` go through `drawSvgArc`); `path32` and `path_cubic32` are the same two cases reading each coordinate with `getFloat32` and advancing by its 4 bytes (spec/09 §4.3.8–4.3.9), the sub-opcode table shared between the two command-stream records so a command is decoded by one function taking the width; `cubic_run` begins a path, `moveTo` the start point and `bezierCurveTo` each six-f32 entry in turn (spec/09 §4.3.10); `circles` and `rects` begin one path holding every entry (each circle a `moveTo` to its rightmost point then a full `arc`), left for the following `fill`/`stroke` records; `style` assigns `fillStyle`/`strokeStyle` as `rgba(r,g,b,a/255)`, `lineWidth` and `globalAlpha` per its flags; `transform` kind `0x01` is `ctx.translate`, `0x03` `ctx.translate` then `ctx.scale`, `0xFF` `ctx.transform(a, b, c, d, e, f)` — composed onto the current transform, never `setTransform` (spec/09 §4.3.6); `save`, `restore`, `fill`, `stroke` are the calls. An unknown opcode, sub-opcode or transform kind throws an `Error` naming the byte and offset: a mismatch with the encoder is a bug, not something to draw past. `test/visualize/hooks/canvas_hooks_test.exs` checks that the source has a `case` for every byte of `Visualize.Backend.CanvasBinary.Opcodes`, every sub-opcode `0x01`–`0x0F` and every transform kind, and that the `path32` and `path_cubic32` cases read `getFloat32`.

## 9. Visualize.Hooks.CanvasIncremental

### 9.1 Functions

| Function | Contract |
|---|---|
| `Visualize.Hooks.CanvasIncremental.js_hook/0` | Returns the source of `export const CanvasIncrementalChart = {…}` (9.2); requires `Visualize.Hooks.CanvasBinary.js_decoder/0` in the same module. |

### 9.2 `CanvasIncrementalChart` behaviour

Attach as for `CanvasChart` (7.2). On `mounted()` the hook also creates an offscreen canvas of the same size for the copy. It renders only on `canvas_incremental` events, whose payload is the map `Visualize.Incremental` builds (spec/09 §7.3): mode `"none"` is ignored; mode `"full"` resets the transform, clears the canvas, checks the `0x60` header and replays the stream from byte 11 (spec/09 §5.6); any scroll mode copies the current pixels to the offscreen canvas, clears, draws them back shifted by `(−round(dx), −round(dy))` (integer shifts, since a sub-pixel copy blurs), then reads the `0x60` record's `region_count` at byte 10 and, for each region, saves, clips to its bounds, replays its `data_length` bytes with `executeVisualizeBinary` and restores (spec/09 §5.5). A payload without the `0x60` header throws.

## 10. Visualize.Hooks.Resize

### 10.1 Functions

| Function | Contract |
|---|---|
| `Visualize.Hooks.Resize.js_hook/0` | Returns the source of `export const ResizeHook = {…}` (10.2). |

### 10.2 `ResizeHook` behaviour

Attach with `phx-hook="ResizeHook"` and an `id` on the container whose size the chart should follow — the element CSS sizes, not the `<svg>` inside it, which the server re-renders at the pushed size. Data attributes read on `mounted()`:

| Attribute | Default | Meaning |
|---|---|---|
| `data-resize-event` | `"resize"` | name of the event pushed to the LiveView |
| `data-resize-debounce` | `150` | milliseconds the size must hold before it is pushed |

On mount the hook creates a `ResizeObserver` on the element. Every observation records the element's content box (`contentRect.width` and `contentRect.height`, each rounded to an integer) and restarts a timer of `debounce` milliseconds; when the timer fires — once per settle, however many observations a drag produced — the hook pushes `pushEvent(eventName, {width, height})` unless that size equals the last size pushed. The first observation, which `ResizeObserver` delivers on `observe()`, therefore pushes the initial size after one debounce period, so a LiveView learns its container's width without a round trip of its own. `destroyed()` disconnects the observer and clears a pending timer, so nothing outlives the element (D-47). A browser without `ResizeObserver` gets no events: `mounted()` returns without observing.

Event: `handle_event("resize", %{"width" => w, "height" => h}, socket)` with integers.

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

On `mounted()` the hook creates one `<div>` with that class, `position: absolute`, `pointer-events: none`, `white-space: pre` and `display: none`, appends it to `document.body`, and binds `mousemove`, `mouseleave`, `touchmove`, `touchend` and `click` on the element, each handler bound once and kept on the hook (D-47). On a move the *datum element* is the event target's nearest ancestor-or-self with `data-datum` (`closest`); none under the pointer hides the tooltip. Otherwise the text is built without a round trip: with a `data-tooltip-template` on the datum element or an ancestor of it — the nearest wins, searched no further than the hook element — every `{field}` becomes that field's `data-datum-<field>` value (`_` as `-`), `""` when the element has no such attribute; without a template, one line per field of `data-datum` in its order, `field: value`, joined with newlines. The text is set with `textContent`, never as markup, so a value is never interpreted. The tooltip is shown at 12 CSS pixels right of and below the pointer's page position, flipped to the left of the pointer when its width would cross the viewport's right edge and above it when its height would cross the bottom. A touch move uses its first touch; `touchend` and `mouseleave` hide.

A click on a datum element whose nearest `data-tooltip-event` is set pushes `pushEvent(event, fields)` with one key per field of `data-datum` and the attribute strings as values, arriving as `handle_event("point_click", %{"t" => "2024-01-01T00:00:00Z", "v" => "4"}, socket)` — strings, since the attributes are strings; the server parses what it needs. A click elsewhere, or without an event, pushes nothing. `destroyed()` removes the five listeners with the kept references and removes the tooltip element from the document. `test/visualize/hooks/tooltip_test.exs` holds the source to this shape.

## 13. Visualize.Hooks.Crosshair

### 13.1 Functions

| Function | Contract |
|---|---|
| `Visualize.Hooks.Crosshair.js_hook/0` | Returns the source of `export const CrosshairHook = {…}` (13.3). |
| `Visualize.Hooks.Crosshair.attrs/2` | As `attrs/3` with no options: the first mark. |
| `Visualize.Hooks.Crosshair.attrs/3` | `attrs(frame, sources, opts)`: the attributes of 13.2 for one mark of a realised `Visualize.Chart.Frame`, as a map from attribute name (string) to value (string), computed once on the server. `:mark` is the one-based position of the mark among the frame's marks (default `1`). Raises `ArgumentError` when the frame is a `:facet` or a `:polar` one — the crosshair is a cartesian interaction over one plot area — or when the mark has no `x` and `y` channels. |

### 13.2 The data arrays

The crosshair snaps to the data without a DOM: the server writes the mark's x pixels once, and the hook finds the nearest one to the pointer in that array. It therefore works over a mark the compiler sent to the canvas layer (spec/14 §12.3), which has no element per datum, exactly as over an SVG (D-76). `Visualize.Hooks.Crosshair.attrs/3` builds them from the rows a mark draws — `Visualize.Chart.Mark.rows/3` through the mark's channels and the frame's scales, the placed rows only (spec/14 §5.2) — and the host puts them on the hook element:

| Attribute | Value |
|---|---|
| `data-xs` | a JSON array of the distinct x pixels of the placed rows, ascending, in the plot area's coordinates — the array the pointer snaps to |
| `data-ys` | a JSON array with one entry per series — the `series` channel's distinct values in order of first appearance, one unnamed series without the channel — each an array parallel to `data-xs` of the series' y pixel at that x, the first row's when the series has several there, `null` where it has none |
| `data-plot` | `left,top,width,height`: the plot area inside the chart — the frame's margins and plot size — so the hook converts a pointer position into plot coordinates and spans the rule over the plot's height |
| `data-size` | `width,height`: the frame's size, the chart's `viewBox`, so a CSS-scaled chart maps the pointer correctly; absent, the hook takes the container's own pixel size |

Every number prints through `Visualize.IR.Path.format_number/1` (at most four decimals, never `-0`), and the arrays are built by the library, so the attributes need no JSON library. A chart of `n` distinct x values and `s` series costs `n` numbers plus `n × s` numbers once per render, whatever the render target.

### 13.3 `CrosshairHook` behaviour

Attach with `phx-hook="CrosshairHook"` and an `id` on a *container* holding the chart — the `<div>` around an `<svg>`, or the canvas hook's container — with the attributes of 13.2 on it. Data attributes read on `mounted()` and again on `updated()`, so a chart re-rendered with new data snaps to the new arrays:

| Attribute | Default | Meaning |
|---|---|---|
| `data-xs`, `data-ys`, `data-plot`, `data-size` | required, `data-ys` and `data-size` optional | 13.2 |
| `data-crosshair-event` | unset | when set, the event pushed with `{index}` — the index into `data-xs` — each time the nearest index changes; unset, the hook pushes nothing |
| `data-crosshair-color` | `"#666"` | the rule's stroke, and the markers' fill for a series `data-crosshair-colors` does not cover |
| `data-crosshair-colors` | unset | a JSON array of one fill per series of `data-ys`, in order |

On `mounted()` the hook creates an overlay `<svg class="crosshair">` with `position: absolute` and `pointer-events: none`, appends it to `document.body` — never inside the container, so a LiveView patch of the chart neither removes it nor sees it — and inside it a group translated to the plot's origin holding a `<line class="crosshair-rule">` from `0` to the plot's height and one `<circle class="crosshair-marker" r="4">` per series of `data-ys`; the overlay is hidden until a move. It binds `mousemove`, `mouseleave`, `touchmove` and `touchend` on the container, each handler bound once and kept (D-47). On a move the hook reads the container's bounding rectangle, sizes and places the overlay over it with the chart's `viewBox` (`0 0 width height` of `data-size`, else the rectangle's size), converts the pointer into chart units by the ratio of the two, subtracts the plot's origin, and hides the overlay when the point is outside the plot area; otherwise it finds the nearest x by binary search over `data-xs` — the lower of two equidistant neighbours — moves the rule to it, moves each series' marker to its y there and hides a marker whose y is `null`, and, when `data-crosshair-event` is set and the index differs from the last pushed, pushes `pushEvent(event, {index})`, arriving as `handle_event("hover", %{"index" => 3}, socket)` with an integer. A touch move uses its first touch; `touchend` and `mouseleave` hide the overlay. `updated()` re-reads the four arrays and rebuilds the markers when the series count changed; `destroyed()` removes the four listeners with the kept references and the overlay from the document. `test/visualize/hooks/crosshair_test.exs` holds the source to this shape.
