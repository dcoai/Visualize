# LiveView Integration

**Status:** Implemented

Visualize reaches the browser through Phoenix LiveView in three ways: HEEx function components (`Visualize.Components`, `Visualize.Components.Tree`) that build a complete chart from assigns; JavaScript hooks — `Visualize.Hooks.Zoom` and `Visualize.Hooks.Brush` add zoom/pan and brush selection to any SVG and report back to the LiveView as events, and `Visualize.Hooks.Canvas`, `Visualize.Hooks.CanvasBinary` and `Visualize.Hooks.CanvasIncremental` replay the Canvas outputs of spec/09 on a `<canvas>` — with `Visualize.Hooks` bundling them into one installable file and re-exporting the server-side helpers; and the `Phoenix.HTML.Safe` implementations that let element structs be interpolated into a template directly. This document is the contract for each: every assign a component reads, every data attribute and event a hook uses, and the maths of the helpers.

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

Both component modules are wrapped in `if Code.ensure_loaded?(Phoenix.Component)`. For that guard to be true in a host, `phoenix_live_view` MUST be a declared dependency of this library: Mix prunes the code path to a dependency's own declared deps while compiling it, so a guard over an undeclared module is always false in a host, whatever the host itself depends on. It is therefore declared `optional: true` (D-45): a host that has LiveView compiles the components, one that does not never fetches Phoenix, and `scripts/consumer_check.exs` proves the second claim on every pipeline ([12-testing-and-conformance](12-testing-and-conformance.md) §4). The library's own builds carry the optional dependency, so the components compile, are documented and are rendered under test here.

### 1.2 Conventions shared by every component

- Every component is a function component `name/1` taking an assigns map and returning rendered HEEx; it is used as `<.name … />` after `import Visualize.Components` (or `Visualize.Components.Tree`).
- Every component declares its assigns with `attr/3`, so an unknown assign or a missing required one is a compile-time warning in the caller, and each listed default is applied by `Phoenix.Component`.
- Every component renders one `<svg width={width} height={height} viewBox="0 0 {width} {height}">`.
- `class` (`:string`, default `nil`) is accepted by every component and placed on the `<svg>` as `class={class}`; when `nil` the attribute is absent.
- `animate` (`:boolean`, default `false`) is accepted by every component; when true, every data mark carries `style="transition: all 0.3s ease-in-out;"` so DOM patches animate via CSS; when false a mark carries no `style` attribute.
- `margin` is merged over the component's default margin with `Map.merge/2`, so a partial map such as `%{left: 60}` overrides one side only. `inner_width = width − left − right`, `inner_height = height − top − bottom`, and the plot area is a `<g transform="translate(left, top)">`.
- Axes are `Visualize.Axis.bottom/1` and `Visualize.Axis.left/1` over the component's scales, rendered with `Visualize.Axis.render/1` into `<g class="x-axis" transform="translate(0, inner_height)">` and `<g class="y-axis">` through `Phoenix.HTML.raw/1`.
- Accessor assigns (`x`, `y`, `value`, `label`, `size`) are `:any` and hold one-argument functions applied to each element of `data`.
- Every computed coordinate and length prints through `Visualize.IR.Path.format_number/1` (at most four decimals, never `-0`), as the axes and paths already do; assigns such as `width` and `margin` print as given.
- Empty `data` renders the frame — the `<svg>` and, where the chart has them, its axes — with no marks; it never raises (1.3).

### 1.3 Scale and colour calls the components depend on

Every coordinate is `Visualize.Scale.apply/2` over the component's scale; every path is `Visualize.Shape.generate/2`; the axes are section 1.2's. Three conventions are shared by every component that has the assign (D-45):

- **Colours.** A `colors` atom names a scheme of `Visualize.Scale.Color.schemes/0`; its stop list from `Visualize.Scale.Color.scheme/1` is the range of a `Visualize.Scale.Ordinal` over the indexes `0..n−1`, so the i-th mark takes the i-th colour and the list cycles when there are more marks than colours. A `colors` list is used the same way, as given. An unknown scheme atom raises `ArgumentError` naming `schemes/0`; an empty list raises `ArgumentError`.
- **Continuous domains.** An extent from `Visualize.Data.extent/1` (or, for `DateTime`, `NaiveDateTime` and `Date` values, `Enum.min_max/2` with the value's module, since term order on a `DateTime` is not chronological) becomes the two-element list `[min, max]` that `Visualize.Scale.domain/2` takes. A domain whose ends coincide — one datum, or every value zero on a `[0, max]` axis — spans one unit from its value: `[v, v + 1]` for numbers, one second for `DateTime` and `NaiveDateTime`, one day for `Date`; the datum then sits at the start of the range. Without it `Visualize.Scale.apply/2` would divide by zero.
- **Empty data.** With no data every continuous domain is `[0, 1]` and every band domain is `[]`, so the axes render with their `0…1` ticks (or bare domain line) and the chart draws no mark.

## 2. Visualize.Components

### 2.1 Functions

| Function | Contract |
|---|---|
| `Visualize.Components.line_chart/1` | Renders a single-series line chart with bottom and left axes from `data`, `x` and `y` (2.2). |
| `Visualize.Components.bar_chart/1` | Renders vertical bars on a band x-scale and a linear y-scale from 0 (2.3). |
| `Visualize.Components.horizontal_bar_chart/1` | Renders horizontal bars on a band y-scale and a linear x-scale from 0 (2.4). |
| `Visualize.Components.pie_chart/1` | Renders a pie or donut from `data` and `value`, with optional centroid labels (2.5). |
| `Visualize.Components.scatter_plot/1` | Renders one circle per datum on two linear scales (2.6). |
| `Visualize.Components.area_chart/1` | Renders a filled area from the baseline plus its top line (2.7). |
| `Visualize.Components.stacked_bar_chart/1` | Renders one stacked bar per category from `keys` (2.8). |

### 2.2 `line_chart/1`

| Assign | Type | Default | Meaning |
|---|---|---|---|
| `data` | `:list` | required | data points; MAY be empty (1.3) |
| `x` | `:any` | required | accessor to the x value: a `DateTime`, `NaiveDateTime` or `Date` (time scale), a number (linear scale) or anything else (band scale with padding 0.1) — decided by the first datum |
| `y` | `:any` | required | accessor to a numeric y value |
| `width` | `:integer` | `600` | |
| `height` | `:integer` | `400` | |
| `margin` | `:map` | `%{top: 20, right: 20, bottom: 30, left: 40}` | |
| `curve` | `:atom` | `:linear` | any curve type of spec/04 |
| `stroke` | `:string` | `"steelblue"` | line colour, also the point fill |
| `stroke_width` | `:integer` | `2` | |
| `show_points` | `:boolean` | `false` | draw an `r="4"` circle at each datum |
| `x_label` | `:string` | `nil` | centred `<text class="axis-label">` below the x axis at `y = inner_height + margin.bottom − 5` |
| `y_label` | `:string` | `nil` | rotated −90° `<text class="axis-label">` at `y = −margin.left + 15` |
| `animate`, `class` | | | per 1.2 |

The y domain is the extent of the y values (1.3) with range `[inner_height, 0]`. The line is `Visualize.Shape.line/0` with the scaled accessors and `curve`, generated with `Visualize.Shape.generate/2` into the `d` of a `<path fill="none" stroke={stroke} stroke-width={stroke_width}>`, drawn only when `data` is non-empty; the axes and labels are drawn regardless.

### 2.3 `bar_chart/1`

| Assign | Type | Default | Meaning |
|---|---|---|---|
| `data` | `:list` | required | MAY be empty (1.3) |
| `x` | `:any` | required | accessor to the category |
| `y` | `:any` | required | accessor to a non-negative number |
| `width` | `:integer` | `600` | |
| `height` | `:integer` | `400` | |
| `margin` | `:map` | `%{top: 20, right: 20, bottom: 30, left: 40}` | |
| `fill` | `:string` | `"steelblue"` | |
| `padding` | `:float` | `0.1` | band padding 0–1 |
| `animate`, `class` | | | per 1.2 |

x is a band scale over the categories in data order with range `[0, inner_width]`; y is linear over `[0, max(y)]` — `[0, 1]` when there is no datum or the maximum is not positive (1.3) — with range `[inner_height, 0]`. Each datum is a `<rect x={band start} y={scaled y} width={bandwidth} height={inner_height − scaled y} fill={fill}>`.

### 2.4 `horizontal_bar_chart/1`

Same assigns as 2.3 with `margin` defaulting to `%{top: 20, right: 20, bottom: 30, left: 100}`, and the roles swapped: `y` is the category accessor (band scale, range `[0, inner_height]`), `x` the numeric accessor (linear over `[0, max(x)]`, range `[0, inner_width]`). Each datum is a `<rect x="0" y={band start} width={scaled x} height={bandwidth} fill={fill}>`. The axes are still `Axis.bottom(x_scale)` and `Axis.left(y_scale)`.

### 2.5 `pie_chart/1`

| Assign | Type | Default | Meaning |
|---|---|---|---|
| `data` | `:list` | required | |
| `value` | `:any` | required | accessor to the slice value |
| `label` | `:any` | `nil` | accessor to the label text; labels are drawn only when both `show_labels` and `label` are set |
| `width` | `:integer` | `400` | |
| `height` | `:integer` | `400` | |
| `inner_radius` | `:integer` | `0` | `> 0` makes a donut |
| `outer_radius` | `:integer` | `nil` | `nil` → `min(width, height)/2 − 10` |
| `pad_angle` | `:float` | `0.02` | radians between slices |
| `colors` | `:any` | `:category10` | scheme atom or explicit colour list; the i-th slice takes the i-th colour (1.3) |
| `show_labels` | `:boolean` | `true` | |
| `animate`, `class` | | | per 1.2 |

Slices come from `Visualize.Shape.pie/0` with `value` and `pad_angle`; each is a `<path d={arc} fill={colour} stroke="white" stroke-width="2">` inside `<g transform="translate(width/2, height/2)">`; with no data the group is empty. A label is a `<text text-anchor="middle" dominant-baseline="middle" font-size="12">` at `Visualize.Shape.Arc.centroid/2` of the slice — the mid-radius `(inner + outer)/2` at the slice's mid angle, which is the D3 convention `x = r·sin(a)`, `y = −r·cos(a)`.

### 2.6 `scatter_plot/1`

| Assign | Type | Default | Meaning |
|---|---|---|---|
| `data` | `:list` | required | MAY be empty (1.3) |
| `x`, `y` | `:any` | required | numeric accessors; both scales are linear over the value extents (1.3) |
| `width` | `:integer` | `600` | |
| `height` | `:integer` | `400` | |
| `margin` | `:map` | `%{top: 20, right: 20, bottom: 30, left: 40}` | |
| `fill` | `:string` | `"steelblue"` | |
| `size` | `:any` | `5` | a number (radius) or a one-argument function of the datum returning the radius |
| `animate`, `class` | | | per 1.2 |

Each datum is a `<circle cx cy r={size} fill={fill} opacity="0.7">`. Unlike `line_chart/1`, the x scale is always linear, so `x` MUST return numbers.

### 2.7 `area_chart/1`

| Assign | Type | Default | Meaning |
|---|---|---|---|
| `data` | `:list` | required | MAY be empty (1.3) |
| `x` | `:any` | required | as in 2.2 (time, linear or band by first datum) |
| `y` | `:any` | required | numeric; y domain is `[0, max(y)]` as in 2.3 |
| `width` | `:integer` | `600` | |
| `height` | `:integer` | `400` | |
| `margin` | `:map` | `%{top: 20, right: 20, bottom: 30, left: 40}` | |
| `fill` | `:string` | `"steelblue"` | area fill |
| `fill_opacity` | `:float` | `0.3` | |
| `stroke` | `:string` | `"steelblue"` | top-line colour |
| `stroke_width` | `:integer` | `2` | |
| `curve` | `:atom` | `:linear` | applied to both the area and the line |
| `animate`, `class` | | | per 1.2 |

Two paths are drawn when `data` is non-empty: the area (`Visualize.Shape.area/0`, `y0 = inner_height`, `y1` = scaled y) as `<path fill={fill} fill-opacity={fill_opacity}>`, then the line as `<path fill="none" stroke={stroke} stroke-width={stroke_width}>`.

### 2.8 `stacked_bar_chart/1`

| Assign | Type | Default | Meaning |
|---|---|---|---|
| `data` | `:list` | required | one map per category; MAY be empty (1.3) |
| `x` | `:any` | required | accessor to the category, applied to each point's `data` |
| `keys` | `:list` | required | the series keys read from each datum by `Visualize.Shape.stack/0` |
| `width` | `:integer` | `600` | |
| `height` | `:integer` | `400` | |
| `margin` | `:map` | `%{top: 20, right: 20, bottom: 30, left: 40}` | |
| `colors` | `:any` | `:category10` | scheme atom or colour list, one per key in order (1.3) |
| `padding` | `:float` | `0.1` | |
| `animate`, `class` | | | per 1.2 |

The stack yields one series per key with points `%{data, y0, y1}`; the y domain is `[0, max(y1)]`, `[0, 1]` when there are no points or the maximum is not positive (1.3). Each point is a `<rect x={band of x.(data)} y={scaled y1} width={bandwidth} height={scaled y0 − scaled y1} fill={series colour}>`.

## 3. Visualize.Components.Tree

### 3.1 Functions

| Function | Contract |
|---|---|
| `Visualize.Components.Tree.tree_diagram/1` | Renders a node-link tree from nested data using the tidy tree layout (3.2). |
| `Visualize.Components.Tree.treemap_chart/1` | Renders a treemap of the hierarchy's leaves coloured by the child of the root above each (3.3). |
| `Visualize.Components.Tree.sunburst_chart/1` | Renders a radial partition with one arc per non-root node of positive value, labelled (3.4). |

All three build the hierarchy with `Visualize.Layout.Hierarchy.new/1`, so `data` MUST be a map whose children are under `:children` or `"children"`; node labels default to `:name` or `"name"`, leaf values to `:value` or `"value"` (missing → 0). A root-only hierarchy is the empty case: the tree draws its one node, the treemap one cell, the sunburst no arc. `colors` follows 1.3 with one rule for which mark takes which index: the i-th child of the root takes the i-th colour and every descendant of that child inherits it, so a whole top-level branch shares a colour however deep it goes (D-46); the root itself, where drawn, is `"#ddd"`. Coordinates print as in 1.2.

### 3.2 `tree_diagram/1`

| Assign | Type | Default | Meaning |
|---|---|---|---|
| `data` | `:map` | required | nested map |
| `width` | `:integer` | `800` | |
| `height` | `:integer` | `600` | |
| `margin` | `:map` | `%{top: 20, right: 120, bottom: 20, left: 120}` | merged over that default |
| `orientation` | `:atom` | `:horizontal` | `:horizontal` (root at left, depth along x) or `:vertical` (root at top) |
| `node_radius` | `:integer` | `6` | |
| `node_fill` | `:string` | `"#fff"` | fill of leaf circles |
| `node_stroke` | `:string` | `"steelblue"` | circle stroke; also the fill of internal nodes |
| `link_stroke` | `:string` | `"#ccc"` | |
| `label` | `:any` | `nil` | accessor of a node's `data`; `nil` → `:name`/`"name"` |
| `animate`, `class` | | | per 1.2 |

Layout is `Visualize.Layout.Tree` sized `[inner_height, inner_width]` for horizontal and `[inner_width, inner_height]` for vertical. Links are cubic Béziers between parent and child with both control points at the midpoint of the depth axis, `fill="none" stroke={link_stroke} stroke-width="1.5"`, drawn before the nodes. Each node is a `<g transform="translate(…)">` (horizontal swaps the layout's `x`/`y`) holding a `<circle r={node_radius} stroke={node_stroke} stroke-width="2">` filled `node_stroke` for an internal node and `node_fill` for a leaf (a node whose `children` is `nil` or `[]`), and a `<text dy="0.31em" font-size="12">`: horizontal labels sit at `x = −10` with `text-anchor="end"` for internal nodes and `x = 10`/`"start"` for leaves; vertical labels are centred at `x = 0`. A root-only hierarchy is one node at the origin of the plot area and no link.

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
| `colors` | `:any` | `:category10` | scheme atom or colour list, by child of the root (3.1) |
| `animate`, `class` | | | per 1.2 |

The hierarchy is summed with `value`, laid out with `Visualize.Layout.Treemap` at `{width, height}`, and only leaves are drawn, in hierarchy order: `<rect x={x0} y={y0} width={max(0, x1−x0)} height={max(0, y1−y0)} fill={colour} stroke="white" stroke-width="1">`. A zero-valued leaf keeps its zero-area cell (D-41). A white `font-size="11"` label with a text shadow is drawn at `(x0 + 4, y0 + 14)` when the cell is wider than 30 and taller than 15, truncated with `…` to `trunc((cell width − 8) / 7)` characters. A root-only hierarchy is one cell the size of the `<svg>`.

### 3.4 `sunburst_chart/1`

| Assign | Type | Default | Meaning |
|---|---|---|---|
| `data` | `:map` | required | |
| `width` | `:integer` | `600` | |
| `height` | `:integer` | `600` | |
| `value` | `:any` | `nil` | as 3.3 |
| `label` | `:any` | `nil` | as 3.2; drawn at the arc's centroid when the arc can hold text (below) |
| `colors` | `:any` | `:category10` | as 3.3 |
| `animate`, `class` | | | per 1.2 |

The radius is `min(width, height)/2`. The summed hierarchy is laid out by `Visualize.Layout.Partition` sized `{2π, radius}` (spec/06 §4): the root spans `[0, 2π]`, each child a share of its parent's arc proportional to its summed value, and a node whose value is not positive a zero-width slot (D-41); ring radii are `depth / (height + 1) · radius` with `height` the root's. Every node of depth ≥ 1 whose angular extent is positive is a `<path fill={colour} stroke="white" stroke-width="1">` whose `d` is `Visualize.Shape.Arc` with `x0`/`x1` as the start and end angles — clockwise from 12 o'clock, the arc's own convention (spec/04 §7) — and `y0`/`y1` as the inner and outer radii, inside `<g transform="translate(width/2, height/2)">`. The root is not drawn, and a zero-extent node draws nothing. A label is a `<text text-anchor="middle" dominant-baseline="middle" font-size="11">` at `Visualize.Shape.Arc.centroid/2` of the arc, drawn when the ring is thicker than 15 and the arc's length at mid-radius, `(x1 − x0) · (y0 + y1) / 2`, exceeds 30, and truncated as in 3.3 to that length − 8.

## 4. Visualize.Hooks

### 4.1 Functions

| Function | Contract |
|---|---|
| `Visualize.Hooks.js_code/0` | Returns the complete ES-module source: a header comment, `ZoomHook`, `BrushHook`, the binary decoder (`Visualize.Hooks.CanvasBinary.js_decoder/0`), `CanvasChart`, `CanvasBinaryChart`, `CanvasIncrementalChart`, then `export { ZoomHook, BrushHook, CanvasChart, CanvasBinaryChart, CanvasIncrementalChart };` and the same as the default export (D-40). |
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
| `data-brush-color` | `"rgba(119, 119, 119, 0.2)"` | selection rectangle fill (the module doc states `rgba(0,0,0,0.1)`; the JS default is normative) |
| `data-brush-stroke` | `"#666"` | selection rectangle stroke |

On mount the hook finds or appends a `<g class="brush-overlay">`, inserts into it a transparent `<rect class="brush-capture" cursor="crosshair">` covering the extent (or the element's bounding box) that receives pointer events, and a hidden `<rect class="brush-selection" stroke-width="1">` that displays the selection. Move and release listeners are attached to `document` so a drag may leave the SVG.

Coordinates are in the SVG's user coordinate system (`getScreenCTM().inverse()`), i.e. `viewBox` units — equal to CSS pixels only when the `viewBox` matches the rendered size. A brush starts on left-button mousedown or single-touch start on the capture rect; while brushing, `x1`/`y1` follow the pointer (`"x"` keeps `y0/y1` at the extent's edges, `"y"` keeps `x0/x1`). On release the selection is normalised so `x0 ≤ x1` and `y0 ≤ y1`; if either side exceeds 5 units it is pushed as `pushEvent(selectEvent, {x0, y0, x1, y1})`, otherwise the gesture is treated as a click and cleared. Double-click on the capture rect clears. Clearing hides the rectangle and pushes `pushEvent(clearEvent, {})`.

On `updated()` the hook reads `data-selection-x0`, `-y0`, `-x1`, `-y1`; when all four parse it shows that selection (server-driven selection); else if `data-selection-clear="true"` it clears.

Events arrive as `handle_event("brush_select", %{"x0" => x0, "y0" => y0, "x1" => x1, "y1" => y1}, socket)` and `handle_event("brush_clear", %{}, socket)`. `destroyed()` calls `removeEventListener` with freshly bound functions, which does not match the listeners added in `mounted()`, so the `document` listeners persist after the element is removed; the intended behaviour is that the bound handlers are stored on mount and those same references removed.

> Decision: see spec/13 — BrushHook listener clean-up.

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

`executeVisualizeBinary(ctx, bytes, startOffset, endOffset)` replays the records of spec/09 §4 from `startOffset` (default `0`) up to `endOffset` (default `bytes.length`) and returns the offset reached. Per opcode: `path` begins a path, `moveTo` the first point and `lineTo` the rest; `path_cubic` begins a path and executes each sub-opcode against a tracked current point and subpath start (`Z` returns to the start; `A`/`a` go through `drawSvgArc`); `circles` and `rects` begin one path holding every entry (each circle a `moveTo` to its rightmost point then a full `arc`), left for the following `fill`/`stroke` records; `style` assigns `fillStyle`/`strokeStyle` as `rgba(r,g,b,a/255)`, `lineWidth` and `globalAlpha` per its flags; `transform` kind `0x01` is `ctx.translate`, `0x03` `ctx.translate` then `ctx.scale`, `0xFF` `ctx.transform(a, b, c, d, e, f)` — composed onto the current transform, never `setTransform` (spec/09 §4.3.6); `save`, `restore`, `fill`, `stroke` are the calls. An unknown opcode, sub-opcode or transform kind throws an `Error` naming the byte and offset: a mismatch with the encoder is a bug, not something to draw past. `test/visualize/hooks/canvas_hooks_test.exs` checks that the source has a `case` for every byte of `Visualize.Backend.CanvasBinary.Opcodes`, every sub-opcode `0x01`–`0x0F` and every transform kind.

## 9. Visualize.Hooks.CanvasIncremental

### 9.1 Functions

| Function | Contract |
|---|---|
| `Visualize.Hooks.CanvasIncremental.js_hook/0` | Returns the source of `export const CanvasIncrementalChart = {…}` (9.2); requires `Visualize.Hooks.CanvasBinary.js_decoder/0` in the same module. |

### 9.2 `CanvasIncrementalChart` behaviour

Attach as for `CanvasChart` (7.2). On `mounted()` the hook also creates an offscreen canvas of the same size for the copy. It renders only on `canvas_incremental` events, whose payload is the map `Visualize.Incremental` builds (spec/09 §7.3): mode `"none"` is ignored; mode `"full"` resets the transform, clears the canvas, checks the `0x60` header and replays the stream from byte 11 (spec/09 §5.6); any scroll mode copies the current pixels to the offscreen canvas, clears, draws them back shifted by `(−round(dx), −round(dy))` (integer shifts, since a sub-pixel copy blurs), then reads the `0x60` record's `region_count` at byte 10 and, for each region, saves, clips to its bounds, replays its `data_length` bytes with `executeVisualizeBinary` and restores (spec/09 §5.5). A payload without the `0x60` header throws.

## 10. Elements in HEEx

### 10.1 Safe implementations

`Visualize.SVG.Element` implements `Phoenix.HTML.Safe` (defined in `Visualize.SVG.Renderer`, compiled only when `Phoenix.HTML.Safe` is loaded) with `to_iodata/1 = Visualize.SVG.Renderer.render/1`, so an element built with `Visualize.svg/1`, `Visualize.SVG.Element.new/2` or `Visualize.SVG.Element.from_ir/1` MAY be interpolated directly: `<%= @element %>` or `{@element}` in HEEx renders its markup without `raw/1`. It also implements `String.Chars`.

`Visualize.IR.Element` likewise implements `Phoenix.HTML.Safe` (defined in `Visualize.Backend.SVG`, same compile condition) with `to_iodata/1 = Visualize.Backend.SVG.render_element/1`, and `String.Chars` unconditionally. An IR element interpolated into HEEx is therefore rendered as SVG by the SVG backend regardless of the configured default backend; to render it with another backend, or with options, the template MUST call `Visualize.Render.to_string/2` (spec/02) and wrap the result in `raw/1`, or convert with `Visualize.SVG.Element.from_ir/1` first.

`Visualize.IR.Path` implements `String.Chars` only (its `d` string); it MUST be interpolated as an attribute value (`d={@path}`), never as markup.

### 10.2 Strings

`Visualize.Axis.render/2`, `Visualize.Render.to_string/2` and `Visualize.SVG.to_string/1` return plain binaries, which HEEx escapes; they MUST be wrapped in `Phoenix.HTML.raw/1` to be emitted as markup, as the components in section 2 do for axes.
