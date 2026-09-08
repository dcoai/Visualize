# Declarative chart layer

**Status:** Agreed

A chart is a nested map — a *design* — that names its data, its coordinate frame, its marks and its labels without a function anywhere in it, so that a design can be stored, diffed, shared, built by a tool and rendered against different data. This document is the contract for the whole layer: the map at every level with every key's type, facet, default and merge rule; the style grammar; sources as typed slots and variables as terms; version and migration; the validator and its error shape; the JSON form; and, as agreed prose, application, composition and compilation. Vega-Lite is the precedent for a stored design and its flat several-hundred-key specification is the warning: the map keeps the three-noun nesting of theme, style and frame (D-57).

Each section states what is implemented. The schema, the validator, the `Visualize.Chart` struct with its map and JSON round-trips, variables and version handling are **Implemented**; the frame's rendering, the marks and transforms, application, composition and compilation are **Agreed** and land in the following work items of proposal #53.

## 1. The map

### 1.1 The design is the primary representation

**Implemented.** The nested map is the chart; every other form — the `Visualize.Chart` struct, a JSON document, the builder's forms, the pipeline API of the earlier documents — is a view of it or sugar that builds one. Four requirements make the map an asset rather than a liability, and every section below is held to them:

1. **No functions.** Fields, transforms, formats, curves, styles and scales are named; where the pipeline API takes a closure the map takes a name or a literal. An escape hatch that needs code is applied to the struct after `Visualize.Chart.from_map/1`, never stored.
2. **Design separate from data.** A design names its sources (`data: :primary`); rows arrive at application (§7.3). The same design binds to any source with the fields it declares.
3. **A schema with a validator.** Every key is declared once, as data (§14.2), and `Visualize.Chart.Validator.validate/1` reports each fault by path and reason (§10).
4. **A `version` key** from the first design, with a migration path per version (§9).

The three nouns of the design are the *theme* (visual constants as named slots, [08-utilities](08-utilities.md) §7), the *style* (per-mark presentation, declared once under `styles` and referenced by name, §3) and the *frame* (the coordinate system and its furniture: size, margins, scales, axes, legend, §4). The frame owns the scales and injects them into the marks it holds, so a mark declares channels and never applies a scale itself.

### 1.2 Four levels

**Implemented.** The map has four levels and nothing deeper; every builder struct in the library decomposes into one of these nodes.

| Level | Nodes | Node kinds (§14.2) |
|---|---|---|
| 1 | the design | `:design` |
| 2 | meta, sources, vars, theme, styles, frame, marks, labels | `:meta`, `:source`, `:var`, `:theme`, `:style`, `:frame`, `:mark`, `:label` |
| 3 | size, margin, scales, axes, legend, projection, facet, viewport; a mark's data, channels, options and inline label; a style's curve options | `:size`, `:margin`, `:scale`, `:axis`, `:legend`, `:projection`, `:facet`, `:viewport`, `:data`, `:channels`, `:options`, `:mark_label`, `:curve_opts` |
| 4 | tick specs; transforms; text parts | `:ticks`, `:transform`, and the `text` type of §1.4 |

Collections are lists (`marks`, `axes`, `labels`, `transforms`); named declarations are maps keyed by name (`sources`, `vars`, `styles`, `scales`). A name is an atom. Marks reference scales, styles and sources by name, never by nesting: that is what makes fragments composable (§8) and the map diffable.

### 1.3 Facets

**Implemented.** Every key carries a *facet*, one of five, and nothing in the library keeps a hand-written list of "which keys are style": the builder's style panel (#54), the theme's overridable slots (#57) and the compiler (§12) all read `Visualize.Chart.Schema.keys/1`.

| Facet | Keys that |
|---|---|
| `:binding` | name a source, a slot, a variable, or a field of a source: `sources`, `vars`, `data`, `source`, `transforms`, `field`, `by` |
| `:channel` | map a field onto a scale: `marks`, `channels` and every key of the channels node |
| `:geometry` | fix a size, position, extent, angle, scale or tick geometry: `frame`, `kind`, `size`, `margin`, `scales`, `axes`, `side`, `ticks`, `options`, `render` |
| `:style` | choose presentation: `theme`, `styles`, `style` and every key of the style grammar (§3) |
| `:content` | carry text, formats and identification: `version`, `meta`, `labels`, `text`, `format`, `label` |

A container's facet is the facet of what it holds: `marks` is `:channel` because a mark exists to bind fields to scales, `frame` is `:geometry`, `labels` is `:content`.

### 1.4 Types

**Implemented.** The schema types every key with one of these terms; `Visualize.Chart.Schema.describe/1` returns them as data (`t:Visualize.Chart.Schema.type/0`).

| Type | Accepts |
|---|---|
| `:integer`, `:number`, `:boolean`, `:string` | the Elixir term of that name (`:number` is an integer or a float) |
| `:name` | an atom naming a source, scale, style, variable or field |
| `{:enum, [a, b, …]}` | one of the listed atoms |
| `{:list, t}` | a list whose every element is a `t` |
| `{:map, t}` | a map whose keys are names and whose values are `t` |
| `{:node, kind}` | a map of the node kind `kind` (§1.2), validated recursively |
| `{:one_of, [t, u, …]}` | any of the listed types |
| `{:ref, :scale | :style | :source | :var}` | a name declared under `frame.scales`, `styles`, `sources` or `vars` (§10.2) |
| `:field` | an atom naming a field of the mark's source (§5.4) |
| `:field_ref` | `{:field, f}` with `f` a `:field`; how a per-datum value reaches a style or a text |
| `:channel` | a `:field`, a number (a constant channel) or a `:field_ref` |
| `:extent` | `:auto`; a two-element list of numbers, `DateTime`s or `:auto`; or a list of categories (numbers, strings, atoms) |
| `:text` | a list whose elements are strings, variables and `:field_ref`s — never a parsed string |
| `:anchor` | `:title`, `:subtitle`, `:caption`, or `{:axis, s}` with `s` a `{:ref, :scale}` |
| `:colour` | a colour string, `:none`, or a theme slot |
| `:size` | a number or a theme slot |
| `:font` | a string or a theme slot |
| `:slot` | a slot of the design's theme: `:series_k`, `{:series, i}`, `:axis`, `:grid`, `:text`, `:background`, `:font_family`, `:font_size`, `:label_size`, `:title_size` ([08-utilities](08-utilities.md) §7.1) |
| `:term` | any JSON-representable term: a number, string, boolean, `nil`, atom or `DateTime`, or a list or name-keyed map of those |

A `%Visualize.Chart.Var{}` (§7.1) is accepted wherever a value of any type is expected, including in place of a whole node; its value is typed at application. A field name is an atom in the map form even for a source whose columns are strings: `Visualize.Data.Table.get/2` reads either spelling (D-52), so `:v` reaches a column named `"v"` and the map never carries a string where a name belongs (D-57).

### 1.5 Merge rules

**Implemented** as data; the composition that applies them is **Agreed** (§8). Every key declares how two fragments combine under it:

| Rule | Keys | Effect |
|---|---|---|
| `:concat` | every list of nodes: `marks`, `labels`, `axes`, `transforms` | the later fragment's elements follow the earlier's |
| `:union` | every name-keyed declaration: `sources`, `vars`, `styles`, `scales` | the union of the two maps; the same name declared differently in both is an error at that path |
| `:override` | every scalar and every other node: `version`, `theme`, `size`, `kind`, `type`, `text`, … | the later fragment's value replaces the earlier's; a node is replaced whole, not merged key by key |

## 2. The design node

### 2.1 Keys

**Implemented.** The `:design` node is the top level. `version` and `frame` are the only required keys.

| Key | Type | Facet | Default | Merge |
|---|---|---|---|---|
| `version` | `:integer` | `:content` | required (§9) | `:override` |
| `meta` | `{:node, :meta}` | `:content` | `%{}` | `:override` |
| `sources` | `{:map, {:node, :source}}` | `:binding` | `%{}` | `:union` |
| `vars` | `{:map, {:node, :var}}` | `:binding` | `%{}` | `:union` |
| `theme` | `{:one_of, [:name, {:node, :theme}]}` | `:style` | `:default` | `:override` |
| `styles` | `{:map, {:node, :style}}` | `:style` | `%{}` | `:union` |
| `frame` | `{:node, :frame}` | `:geometry` | required | `:override` |
| `marks` | `{:list, {:node, :mark}}` | `:channel` | `[]` | `:concat` |
| `labels` | `{:list, {:node, :label}}` | `:content` | `[]` | `:concat` |

### 2.2 Meta

**Implemented.** `:meta` identifies the design; nothing renders from it except through a label that quotes it.

| Key | Type | Facet | Default | Merge |
|---|---|---|---|---|
| `name` | `:string` | `:content` | `nil` | `:override` |
| `description` | `:text` | `:content` | `[]` | `:override` |

### 2.3 Sources

**Implemented.** A `:source` is a typed slot (§7.2): the fields the design reads from it, and the name of the source that fills it when application supplies none.

| Key | Type | Facet | Default | Merge |
|---|---|---|---|---|
| `fields` | `{:list, :field}` | `:binding` | required | `:override` |
| `default` | `:name` | `:binding` | `nil` | `:override` |

### 2.4 Vars

**Implemented.** A `:var` declaration gives a variable its default. The default is declared here and only here; the `%Visualize.Chart.Var{}` term that uses it carries the name alone (§7.1, D-59).

| Key | Type | Facet | Default | Merge |
|---|---|---|---|---|
| `default` | `:term` | `:binding` | `nil` (the variable MUST be supplied at application) | `:override` |

### 2.5 Theme

**Implemented.** `theme` names a theme — `:default` or `:dark` for the built-in ones of [08-utilities](08-utilities.md) §7.2 — or gives one inline as a `:theme` node whose keys are the fields of `Visualize.Theme`: `name` (`:name`), `series` (`{:list, :string}`, non-empty), `axis`, `grid`, `text`, `background` (`:string`), `font_family` (`:string`), `font_size`, `label_size`, `title_size` (`:number`), every key `:style` and `:override`, defaults those of `Visualize.Theme.default/0`. A name that is neither built-in nor known to the consumer is resolved at application, which takes a `theme:` option; the validator accepts any name. Slots referenced from styles (§3.2) are checked against the theme when it is built-in or inline.

### 2.6 Styles

**Implemented.** `styles` declares named style nodes (§3). A mark, axis, legend or label references one by name through its `style` key; no other node carries a colour, a font or a curve.

## 3. The style grammar

### 3.1 Keys

**Implemented.** A `:style` node has eighteen keys, every one `:style` and `:override`, every one optional with no default: an absent key is decided by the theme and the mark at compilation (§12), never by the schema.

| Key | Type | Notes |
|---|---|---|
| `fill` | `:colour` | |
| `stroke` | `:colour` | |
| `stroke_width` | `:size` | user units |
| `stroke_dasharray` | `{:one_of, [:string, {:list, :number}]}` | |
| `stroke_linecap` | `{:enum, [:butt, :round, :square]}` | |
| `stroke_linejoin` | `{:enum, [:miter, :round, :bevel]}` | |
| `opacity` | `:size` | `0` to `1` |
| `fill_opacity` | `:size` | |
| `stroke_opacity` | `:size` | |
| `font_family` | `:font` | |
| `font_size` | `:size` | |
| `font_weight` | `{:one_of, [:integer, {:enum, [:normal, :bold]}]}` | |
| `text_anchor` | `{:enum, [:start, :middle, :end]}` | |
| `class` | `:string` | a CSS class added to the mark's element |
| `curve` | `{:enum, curve types}` | the types of [04-shapes-and-curves](04-shapes-and-curves.md) §5.1 |
| `curve_opts` | `{:node, :curve_opts}` | `tension` and `alpha`, both `:number`, `:style`, `:override` |
| `symbol` | `{:enum, symbol types}` | the types of [04-shapes-and-curves](04-shapes-and-curves.md) §9.2 |
| `symbol_size` | `:size` | area in square user units |

### 3.2 Values

**Implemented.** A style value is one of four things, and which of them a key accepts follows from its type:

- a **literal** of the key's type — `"#3b6fa8"`, `2`, `:step_after`;
- a **theme slot** (`:slot`) for the `:colour`, `:size` and `:font` keys — `:series_1`, `{:series, 3}`, `:axis`, `:font_size` — resolved through `Visualize.Theme.resolve/3` in the mode of the render target, so the SVG output carries `var(--vis-axis, #666666)` and a canvas the literal (D-55);
- a **variable** (§7.1) for any key;
- a **channel binding** `{:field, f}` for any key, which is how `Visualize.Shape.Band`'s per-datum fill is expressed: the value is read from the datum at render and, for a `:colour` key, passed through the mark's colour scale when the frame declares one.

For an enumerated key an atom is the literal; for a `:colour`, `:size` or `:font` key an atom is a slot, and `:none` is the literal "no paint". The validator checks a slot against the theme's `Visualize.Theme.slots/1` when the theme is built-in or inline (§2.5) and reports `{:undeclared, :slot, name}` otherwise.

### 3.3 Built-in styles

**Agreed.** Four style names are always declared, derived from the theme's slots by the compiler, and a `styles` entry of the same name replaces one: `:axis` (`stroke: :axis`, `fill: :text`, `font_family: :font_family`, `font_size: :font_size`), `:grid` (`stroke: :grid`), `:label` (`fill: :text`, `font_family: :font_family`, `font_size: :label_size`) and `:title` (as `:label` with `font_size: :title_size`, `font_weight: :bold`). `Visualize.Chart.Schema.builtin_styles/0` lists them, and a `{:ref, :style}` resolves against the union of the built-in and the declared names (**Implemented**). A mark with no `style` takes the theme's `{:series, i}` for its one-based position among the marks.

## 4. The frame

### 4.1 Keys

**Implemented** as schema; the rendering of the furniture is **Agreed** (work item 2 of #53).

| Key | Type | Facet | Default | Merge |
|---|---|---|---|---|
| `kind` | `{:enum, [:cartesian, :polar, :geo, :facet]}` | `:geometry` | required | `:override` |
| `size` | `{:node, :size}` | `:geometry` | `%{width: 600, height: 400}` | `:override` |
| `margin` | `{:node, :margin}` | `:geometry` | `%{top: 20, right: 20, bottom: 30, left: 40}` | `:override` |
| `scales` | `{:map, {:node, :scale}}` | `:geometry` | `%{}` | `:union` |
| `axes` | `{:list, {:node, :axis}}` | `:geometry` | `[]` | `:concat` |
| `legend` | `{:node, :legend}` | `:geometry` | `nil` | `:override` |
| `projection` | `{:node, :projection}` | `:geometry` | `nil` | `:override` |
| `facet` | `{:node, :facet}` | `:binding` | `nil` | `:override` |
| `viewport` | `{:node, :viewport}` | `:geometry` | `nil` | `:override` |

### 4.2 Size and margin

**Implemented.** `:size` has `width` and `height`, both `:number`, `:geometry`, required. `:margin` has `top`, `right`, `bottom` and `left`, each `:number`, `:geometry`, default `0`. The plot area is the size less the margins; `Visualize.Chart.Schema.default/2` gives the frame's defaults so a consumer never repeats them.

### 4.3 Scales

**Implemented** as schema; inference is **Agreed**. A `:scale` node is one of the fourteen kinds `Visualize.Scale` constructs ([03-scales](03-scales.md) §2) with the kind's parameters; every key is `:geometry` and `:override`.

| Key | Type | Default | Applies to |
|---|---|---|---|
| `kind` | `{:enum, [:linear, :log, :power, :sqrt, :symlog, :time, :ordinal, :band, :quantize, :quantile, :threshold, :sequential, :diverging, :radial]}` | required | every scale |
| `domain` | `:extent` | `:auto` | every scale |
| `range` | `{:one_of, [:extent, :name]}` | `:auto` | every scale; a name is a colour scheme of `Visualize.Scale.Color.schemes/0` |
| `nice` | `:boolean` | `false` | continuous |
| `clamp` | `:boolean` | `false` | continuous, colour |
| `base` | `:number` | `10` | `:log` |
| `exponent` | `:number` | `1` | `:power` |
| `constant` | `:number` | `1` | `:symlog` |
| `padding` | `:number` | `0` | `:band` |
| `padding_inner` | `:number` | `nil` | `:band` |
| `padding_outer` | `:number` | `nil` | `:band` |
| `align` | `:number` | `0.5` | `:band` |
| `round` | `:boolean` | `false` | `:band` |
| `unknown` | `:term` | `nil` | `:ordinal` |

`domain: :auto` is inferred at application from every mark channel that names the scale: the extent of the bound columns by `Visualize.Data.extent/2`, the whole column read (Tucan's first-row rule is the documented limit, D-52). `[0, :auto]` fixes one end. `range: :auto` is the plot area's extent along the scale's axis — the scale named `x` runs left to right, `y` bottom to top, `angle` the turn, `r` the radius; a colour scale's `:auto` range is the theme's series. A scale name is any atom; the names `x`, `y`, `angle`, `r` and `color` carry the meanings above, so an axis or a legend on any other name MUST say which axis it follows through `side` and `position`.

### 4.4 Axes and tick specs

**Implemented** as schema. An `:axis` node draws a scale on one side of the plot area; tick geometry is a `:ticks` node, the fourth level.

| Key | Type | Facet | Default | Merge |
|---|---|---|---|---|
| `scale` | `{:ref, :scale}` | `:geometry` | required | `:override` |
| `side` | `{:enum, [:top, :right, :bottom, :left]}` | `:geometry` | required | `:override` |
| `ticks` | `{:one_of, [:integer, {:list, :term}, {:node, :ticks}]}` | `:geometry` | `nil` | `:override` |
| `format` | `:string` | `:content` | `nil` | `:override` |
| `grid` | `:boolean` | `:geometry` | `false` | `:override` |
| `offset` | `:number` | `:geometry` | `0` | `:override` |
| `style` | `{:ref, :style}` | `:style` | `:axis` | `:override` |

`ticks` as an integer is the count hint, as a list the explicit values, as a `:ticks` node both with the sizes: `count` (`:integer`, `:geometry`), `values` (`{:list, :term}`, `:content`), `size_inner` and `size_outer` (`:number`, `:geometry`, `6`) and `padding` (`:number`, `:geometry`, `3`) — the setters of [05-axes-and-formatting](05-axes-and-formatting.md) §1.2 by name. `format` is a `Visualize.Format` specifier applied to every tick value. `grid: true` extends each tick across the plot area in the `:grid` style, `aria-hidden` like the axis (D-56). The axis's line, ticks and labels draw in its `style`; tick sizes stay geometry.

### 4.5 Legend

**Implemented** as schema. A `:legend` node explains one scale, normally the colour scale.

| Key | Type | Facet | Default | Merge |
|---|---|---|---|---|
| `scale` | `{:ref, :scale}` | `:geometry` | required | `:override` |
| `position` | `{:enum, [:top_left, :top_right, :bottom_left, :bottom_right, :top, :bottom, :left, :right]}` | `:geometry` | `:top_right` | `:override` |
| `title` | `:text` | `:content` | `[]` | `:override` |
| `style` | `{:ref, :style}` | `:style` | `:label` | `:override` |

### 4.6 Kind-specific nodes

**Implemented** as schema; semantics **Agreed**.

- `:cartesian` reads `scales`, `axes` and `legend`; `:polar` the same, with `angle` and `r` as its position scales and axes drawn as rings and spokes.
- `:geo` takes a `:projection` node in place of position scales: `type` (`:name`, required, a type of `Visualize.Geo.Projection`), `scale` (`:number`), `translate`, `center`, `rotate`, `parallels` (`{:list, :number}`) and `clip_angle` (`:number`), every key `:geometry` and `:override`, defaults those of `Visualize.Geo.Projection.new/1`. Delaunay, Voronoi and contours are transforms (§5.4).
- `:facet` repeats the frame over a grouping: a `:facet` node with `by` (`:field`, `:binding`, required) and `columns` (`:integer`, `:geometry`, `nil` for one row). Every panel shares the frame's scales and axes; the facet's data contract beyond that is settled by work item 2.
- `viewport` makes a streaming window: `scale` (`{:ref, :scale}`, required) and `span` (`:number`, required), both `:geometry`. A compiled chart over a design with a viewport is stateful (§12).

## 5. Marks

### 5.1 Keys

**Implemented** as schema; rendering is **Agreed** (work item 3 of #53).

| Key | Type | Facet | Default | Merge |
|---|---|---|---|---|
| `type` | `{:enum, mark types}` | `:channel` | required | `:override` |
| `data` | `{:one_of, [{:ref, :source}, {:node, :data}]}` | `:binding` | required | `:override` |
| `channels` | `{:node, :channels}` | `:channel` | `%{}` | `:override` |
| `options` | `{:node, :options}` | `:geometry` | `%{}` | `:override` |
| `style` | `{:ref, :style}` | `:style` | `nil` (§3.3) | `:override` |
| `label` | `{:node, :mark_label}` | `:content` | `nil` | `:override` |
| `render` | `{:enum, [:auto, :svg, :canvas, :binary]}` | `:geometry` | `:auto` | `:override` |

### 5.2 Types and channels

**Implemented.** The mark types are the data-shaped generators of [04-shapes-and-curves](04-shapes-and-curves.md) and four generic marks. A `:channels` node's keys are the channels; every key is `:channel`, `:override`, of type `:channel`. Which channels a mark takes is a function of its type, and the validator reports a channel the type does not read as `{:invalid_for, type}`:

| Type | Required | Optional | Draws |
|---|---|---|---|
| `:line` | `x`, `y` | | `Visualize.Shape.Line` |
| `:area` | `x`, `y` | `x0`, `x1`, `y0`, `y1` | `Visualize.Shape.Area` |
| `:band` | `x0`, `x1` | `y` | `Visualize.Shape.Band` |
| `:rule` | `x` | | `Visualize.Shape.Rule`, spanning the plot height |
| `:x_band` | `x0`, `x1` | | `Visualize.Shape.XBand` |
| `:percentile_band` | `x`, `median`, `inner`, `outer` | | `Visualize.Shape.PercentileBand` |
| `:rose` | `angle` | `value` | `Visualize.Shape.Rose`; `value` is the petal's outer radius |
| `:symbol` | `x`, `y` | `value` | `Visualize.Shape.Symbol` at each datum; `value` sizes it |
| `:arc` | `value` | `inner`, `outer` | `Visualize.Shape.Arc` over `Visualize.Shape.Pie` |
| `:path` | `x`, `y` | | a path through the points, in the style's `curve` |
| `:rect` | `x0`, `x1`, `y0`, `y1` | `value` | a rectangle per datum; `value` reaches the colour scale |
| `:circle` | `x`, `y` | `value` | a circle per datum; `value` is the radius |

`Visualize.Chart.Schema.channels/1` returns the two lists for a type. A channel names a field of the mark's data; the frame maps `x` through the scale named `x`, `y` through `y`, `angle` and `value` through `angle` and `r` in a polar frame, and `x0`/`x1` and `y0`/`y1` through `x` and `y`. A number is a constant in the scale's domain.

### 5.3 Options

**Implemented.** An `:options` node holds a mark's geometry scalars, every key `:number`, `:geometry`, `:override`; the validator reports a key the type does not read as `{:invalid_for, type}`. `Visualize.Chart.Schema.options/1` returns a type's keys.

| Type | Keys |
|---|---|
| `:band` | `height` |
| `:rose` | `width`, `inner_radius`, `outer_radius`, `pad_angle` |
| `:arc` | `inner_radius`, `outer_radius`, `corner_radius`, `pad_angle`, `start_angle`, `end_angle` |
| `:rect` | `corner_radius` |
| `:circle` | `radius` |
| every other type | none |

Angles are radians and sizes user units, as in [11-public-api](11-public-api.md) §3.3.

### 5.4 Data and transforms

**Implemented** as schema; the transforms themselves are **Agreed**. `data` is a source name, or a `:data` node with `source` (`{:ref, :source}`, `:binding`, required) and `transforms` (`{:list, {:node, :transform}}`, `:binding`, `[]`, `:concat`). Layouts, binning, stacking, aggregation and the geo algorithms are transforms — steps in a mark's data pipeline that yield rows — never marks: a treemap is a `:treemap` transform producing rows with `x0 y0 x1 y1` that a `:rect` draws.

A `:transform` node has `op` (`{:enum, ops}`, `:binding`, required) and the keys its op reads; every key is `:override`:

| Key | Type | Facet | Read by |
|---|---|---|---|
| `field` | `:field` | `:binding` | `:bin`, `:sum`, `:sort`, `:density`, `:contour` |
| `fields` | `{:list, :field}` | `:binding` | `:stack` (the series), `:delaunay`, `:voronoi` (the coordinates) |
| `by` | `:field` | `:binding` | `:sum`, `:sort`, `:tree`, `:cluster`, `:pack`, `:partition`, `:treemap` (the parent), `:chord`, `:sankey` |
| `as` | `:name` | `:binding` | `:bin`, `:sum` (the output field) |
| `thresholds` | `{:one_of, [:integer, {:list, :number}]}` | `:geometry` | `:bin`, `:contour` |
| `order` | `{:enum, [:none, :ascending, :descending, :inside_out, :reverse, :appearance]}` | `:geometry` | `:stack`, `:sort` |
| `offset` | `{:enum, [:none, :expand, :silhouette, :wiggle, :diverging]}` | `:geometry` | `:stack` |
| `size` | `{:list, :number}` | `:geometry` | the layouts |
| `padding` | `:number` | `:geometry` | the layouts |

The ops are `:bin`, `:stack`, `:sum`, `:sort`, `:tree`, `:cluster`, `:pack`, `:partition`, `:treemap`, `:chord`, `:sankey`, `:force`, `:contour`, `:density`, `:delaunay` and `:voronoi` (`Visualize.Chart.Schema.transform_ops/0`). Which keys each op requires is settled with the op's implementation; the validator checks the type of every key present and that `op` is known.

A field named in a mark's `channels`, in its inline label's text or in its transforms is checked against the source's declared `fields` when the mark reads the source directly. After a transform the columns are the transform's, and a `{:field, f}` in a style is shared by every mark that references the style; those references are checked at application, when the rows exist.

### 5.5 Inline label

**Implemented** as schema. A `:mark_label` node labels the mark from its own data: `text` (`:text`, `:content`, required), `anchor` (`{:enum, [:top, :bottom, :left, :right, :start, :middle, :end]}`, `:geometry`, `:top`), `style` (`{:ref, :style}`, `:style`, `:label`), `dx` and `dy` (`:number`, `:geometry`, `0`); every key `:override`. A `{:field, f}` in its text reads the datum, which is how a rule labels itself with the deploy's `sha`.

## 6. Labels

### 6.1 Keys

**Implemented** as schema. A `:label` node is a text of the frame — a title, a caption, an axis title — rather than of a datum.

| Key | Type | Facet | Default | Merge |
|---|---|---|---|---|
| `anchor` | `:anchor` | `:content` | required | `:override` |
| `text` | `:text` | `:content` | required | `:override` |
| `style` | `{:ref, :style}` | `:style` | `:label` (`:title` for the `:title` anchor) | `:override` |
| `dx` | `:number` | `:geometry` | `0` | `:override` |
| `dy` | `:number` | `:geometry` | `0` | `:override` |

`{:axis, s}` anchors the label as the title of the axis drawn for scale `s`; `s` is a scale reference and is checked as one.

### 6.2 Text

**Implemented.** A text is a list, never a parsed string: `["Uptime — ", var(:unit)]`, `["deploy ", {:field, :sha}]`. Strings are literal, a variable resolves at application, a field reference reads the datum (inline labels) or is an error (frame labels, which have no datum: `{:invalid_for, :label}`). A `"{{unit}}"` string form MAY be added later as sugar that compiles to the list.

## 7. Variables and slots

### 7.1 Variables

**Implemented.** `Visualize.Chart.var/1` builds `%Visualize.Chart.Var{name: name}`, a term allowed wherever a value can appear — a style value, a text part, a channel, a whole node (`style: var(:style)`). The term carries only the name; the default is declared once under `vars` (§2.4), so two fragments cannot disagree about it (D-59). The validator requires every variable used to be declared (`{:undeclared, :var, name}`) and does not type the value, which is unknown until application.

### 7.2 Sources as slots

**Implemented** as schema. A source declaration is a slot: the fields the design reads are the contract, and binding maps slot to source at application — "made for `{a, b, c}` but showing `{d, e, f}`" is one rebinding. A source with a `default` is filled by the source of that name when application supplies none. A dashboard picker validates a candidate source against `fields` before offering it.

### 7.3 Application

**Agreed** (work item 5 of #53). `Chart.apply(design, sources: %{name => source}, vars: %{name => value})` resolves every variable (an unresolved one without a default is reported by path), binds each slot to its source and checks the source has the slot's fields (`sources.primary: has no field :v`, by path), infers every `:auto` domain from the bound columns, validates the result against the schema, and returns the concrete chart. A source is anything `Visualize.Data.Table.rows/1` reads; a rank-1 `Nx` tensor bound to a dense slot stays a tensor and reaches `Visualize.Shape.LineNx` without becoming rows (D-52). The design, its fragments and a binding are storable; the applied chart is not.

## 8. Composition

**Agreed** (work item 5 of #53). `Chart.compose(fragments)` merges a list of designs or partial designs into one by the merge rule of every key (§1.5), in order: collections concatenate, declarations union, scalars are overridden by the later fragment. A `:union` key declared with different values in two fragments is an error at the name's path; a fragment need not carry `version` or `frame`, and the result MUST validate. A standard label set, a house style sheet and a chart-specific fragment compose into one design.

## 9. Version and migration

**Implemented.** `version` is required and is the integer `Visualize.Chart.Migration.current/0`, which is `1`. `Visualize.Chart.from_map/1` calls `Visualize.Chart.Migration.migrate/1` before validation: a design at the current version passes through unchanged; one at an older version is stepped forward one version at a time through the migration registered for each step, so a stored design never goes stale; a version above the current one, or that is not an integer, is `{:error, [{[:version], reason}]}` with `{:unsupported_version, v}` or `:required`. No migration is registered yet — the hook exists so that the first schema change ships with its step, not with a breaking change. Every migration MUST be pure and MUST produce a map that validates at its target version.

## 10. Validation

### 10.1 Error shape

**Implemented.** `Visualize.Chart.Validator.validate/1` takes a map and returns `:ok` or `{:error, errors}` with every fault found, not the first: each error is `{path, reason}` (`t:Visualize.Chart.Validator.error/0`). The path is the list of keys and list indexes from the design to the faulty value — `[:marks, 1, :channels, :y]`, `[:styles, :series, :stroke]`, `[:frame, :axes, 0, :scale]`, `[:version]` — and `[]` is the design itself. Errors are ordered by path, as a reader would walk the map.

| Reason | Meaning |
|---|---|
| `:required` | the key at the path is missing |
| `:unknown_key` | the key at the path is not in the node's schema |
| `{:type, type}` | the value is not of the type (§1.4) |
| `{:enum, allowed}` | the atom is not one of the allowed |
| `{:undeclared, kind, name}` | a reference of `kind` (`:scale`, `:style`, `:source`, `:var`, `:field`, `:slot`) to a name nothing declares |
| `{:invalid_for, type}` | a channel, option or text part that the mark type, transform or label does not read |
| `{:unsupported_version, v}` | §9 |
| `{:json, message}` | `Visualize.Chart.from_json/1` could not parse the document |
| `{:missing_dependency, :jason}` | the JSON functions were called without `Jason` (§11) |

`Visualize.Chart.Validator.format/1` renders one error as a line a person reads, `marks[1].channels.y: field :temp is not declared by the mark's source`.

### 10.2 Checks

**Implemented.** For every node, in this order: unknown keys; required keys; the type of every present value, recursing into nodes, lists and maps; enumerations; then references. A reference is resolved against the design being validated — `frame.scales` for `:scale`, `styles` and the built-in names for `:style`, `sources` for `:source`, `vars` for `:var`, the mark's source's `fields` for `:field`, the theme's slots for `:slot` — so a design is self-contained or it does not validate. A `%Visualize.Chart.Var{}` in any position is accepted after its declaration is checked, and nothing under it is examined.

## 11. JSON

### 11.1 Encoding

**Implemented.** `Visualize.Chart.to_json/1` and `Visualize.Chart.from_json/1` are the map round-trip over a JSON document, behind the optional `Jason` dependency: `mix.exs` declares `{:jason, "~> 1.4", optional: true}`, `Visualize.Chart` declares `@compile {:no_warn_undefined, Jason}` (D-50), and without Jason both return `{:error, {:missing_dependency, :jason}}` while everything else works. `scripts/consumer_check.exs` asserts that `Jason` is absent from a bare consumer. The encoding is schema-driven: keys are strings, a `:name`, `:field`, `:slot` or enumerated atom is its string, and `from_json/1` reads each string back as the atom the schema says it is. A design is authored, not data — its names are the author's vocabulary — so decoding creates the atoms a design names; a consumer that loads designs from an untrusted source bounds them itself.

### 11.2 Tagged terms

**Implemented.** Terms JSON has no form for are objects with one `$`-prefixed key, and nothing else in a design starts a key with `$`:

| Term | JSON |
|---|---|
| `%Visualize.Chart.Var{name: :unit}` | `{"$var": "unit"}` |
| `{:field, :sha}` | `{"$field": "sha"}` |
| `{:series, 3}` | `{"$series": 3}` |
| `{:axis, :y}` | `{"$axis": "y"}` |
| `:none` as a colour | `"none"` |
| `:auto` in an extent | `"auto"` (so a category spelled `"auto"` reads back as `:auto`) |
| a `DateTime` | `{"$time": "2026-09-08T00:00:00Z"}` (ISO 8601, UTC) |
| an atom in a `:term` position | `{"$atom": "series_1"}` |
| `nil` | `null` |

Everything else — numbers, strings, booleans, lists, maps — is its JSON self. `from_json(to_json(chart))` is `chart` for every valid chart.

## 12. Compilation

**Agreed** (work item 6 of #53). `Chart.compile(design)` compiles a design the way HEEx compiles a template: the design is validated once, theme and styles are resolved, everything data-independent is precomputed, and the result is a compiled struct with one closure per dynamic region taking the bound sources. Rendering the compiled chart per tick pays no validation.

- **The static/dynamic split is computed, not assumed.** The frame — axes, grid, labels, legend — is static for a design, a size and a theme; mark paths are dynamic. A fixed domain makes an axis static, an inferred (`:auto`) one makes it dynamic, and the compiled struct reports which regions are dynamic and why, so an author trades a fixed axis for a smaller diff knowingly.
- **The render target is a compiler decision per mark**, never a design property beyond the `render` override (§5.1): `:auto` picks SVG paths below the point-count ceiling of [00-prior-art](00-prior-art.md) and the canvas/binary path above it from the *bound* data, so rebinding a slot moves a mark between SVG and canvas without touching the design. Static furniture is always SVG. The compiled struct reports the target chosen per mark.
- **Style resolves to two outputs from one node**: classes and CSS custom properties for SVG, literal colours and widths for canvas, both through `Visualize.Theme.resolve/3`. Text and per-element data attributes do not exist on canvas, so labels, annotations and DOM-hit tooltips stay in the SVG layer; layering is fixed, canvas under SVG, mark order within each layer.
- **The split targets the hybrid backend's chart map** ([09-rendering-backends](09-rendering-backends.md) §6) as it stands. A design with a `viewport` compiles to a stateful chart holding `Visualize.Incremental` state between ticks and emitting scroll-and-fill payloads.
- **Two entry points, one compiler.** Runtime compilation of stored designs (closures, never code evaluation) is primary; a macro or sigil for literal designs runs the same compiler at compile time for HEEx-style compile-time errors. A compiled design is a value: recompile on design change, not data change, and one compiled design serves many bindings.
- **Acceptance is measured**: the gallery's live-update page records the diff payload before and after, and item 6 ships with the number.

## 13. Worked example

**Implemented** as a valid design (`test/visualize/chart/example_test.exs` holds it and round-trips it). Every construct of the layer appears once:

```elixir
import Visualize.Chart, only: [var: 1]

%{
  version: 1,
  meta: %{name: "Uptime", description: ["Uptime in ", var(:unit)]},
  sources: %{
    primary: %{fields: [:t, :v], default: :gitlab_uptime},
    deploys: %{fields: [:at, :sha]}
  },
  vars: %{unit: %{default: "%"}, accent: %{default: :series_1}},
  theme: :default,
  styles: %{
    series: %{stroke: var(:accent), stroke_width: 2, curve: :step_after},
    muted: %{stroke: :axis, stroke_width: 1, opacity: 0.6}
  },
  frame: %{
    kind: :cartesian,
    size: %{width: 600, height: 300},
    margin: %{top: 20, right: 20, bottom: 30, left: 40},
    scales: %{
      x: %{kind: :time, domain: :auto},
      y: %{kind: :linear, domain: [0, :auto], nice: true},
      color: %{kind: :ordinal, range: :category10}
    },
    axes: [
      %{scale: :x, side: :bottom, ticks: 6, format: "%H:%M"},
      %{scale: :y, side: :left, ticks: 5, grid: true}
    ],
    legend: %{scale: :color, position: :top_right}
  },
  marks: [
    %{type: :line, data: :primary, channels: %{x: :t, y: :v}, style: :series},
    %{
      type: :rule,
      data: :deploys,
      channels: %{x: :at},
      label: %{text: ["deploy ", {:field, :sha}], anchor: :top},
      style: :muted
    },
    %{
      type: :rect,
      data: %{source: :primary, transforms: [%{op: :bin, field: :v, thresholds: 20}]},
      channels: %{x0: :x0, x1: :x1, y0: :y0, y1: :count},
      style: :series
    }
  ],
  labels: [
    %{anchor: :title, text: ["Uptime — ", var(:unit)]},
    %{anchor: {:axis, :y}, text: ["unit: ", var(:unit)]}
  ]
}
```

Its application, once item 5 lands, is `Chart.apply(design, sources: %{primary: idle, deploys: deploys}, vars: %{unit: "mg/hr"})`; `Chart.compile/1` then splits it into the static frame and the dynamic marks.

## 14. Functions

### 14.1 `Visualize.Chart`

**Implemented.** `%Visualize.Chart{}` has one field per key of the design node (§2.1) with the schema's defaults; the nested levels are maps as given. `from_map/1` migrates (§9), validates (§10) and builds the struct without filling any nested default — the struct stores what the author wrote, and a reader takes defaults from the schema — so `to_map/1` is its exact inverse and `from_map(to_map(chart)) == chart` for every chart (D-59).

| Function | Contract |
|---|---|
| `Visualize.Chart.from_map/1` | `{:ok, chart}` for a valid design map after migration, else `{:error, errors}` as §10.1; the design-level keys absent from the map take the defaults of §2.1. |
| `Visualize.Chart.from_map!/1` | As `from_map/1`, raising `ArgumentError` with the formatted errors (§10.1) on the error branch. |
| `Visualize.Chart.to_map/1` | The design map of a chart: every design-level key, nested nodes as stored. |
| `Visualize.Chart.from_json/1` | `from_map/1` over a JSON document decoded as §11; `{:error, [{[], {:json, message}}]}` for a document that does not parse, `{:error, {:missing_dependency, :jason}}` without Jason. |
| `Visualize.Chart.to_json/1` | `{:ok, json}` for `to_map/1` encoded as §11, `{:error, {:missing_dependency, :jason}}` without Jason. |
| `Visualize.Chart.var/1` | `%Visualize.Chart.Var{name: name}` for an atom (§7.1). |

### 14.2 `Visualize.Chart.Schema`

**Implemented.** The schema as data. A key spec (`t:Visualize.Chart.Schema.key_spec/0`) is `%{key, type, facet, default, required, merge}`; `nil` as a default means "none".

| Function | Contract |
|---|---|
| `Visualize.Chart.Schema.kinds/0` | Every node kind of §1.2, the design first. |
| `Visualize.Chart.Schema.describe/1` | The key specs of a node kind in the order of its table, for introspection and the builder's forms. |
| `Visualize.Chart.Schema.key/2` | `key(kind, key)`: the key spec, or `nil` when the node has no such key. |
| `Visualize.Chart.Schema.keys/1` | Every `{kind, key}` pair carrying the facet, over every node kind (§1.3). |
| `Visualize.Chart.Schema.keys/2` | `keys(kind, facet)`: the keys of one node kind carrying the facet, in table order. |
| `Visualize.Chart.Schema.default/2` | `default(kind, key)`: the key's default, `nil` when it has none or is required. |
| `Visualize.Chart.Schema.mark_types/0` | The mark types of §5.2, in table order. |
| `Visualize.Chart.Schema.channels/1` | `%{required: [...], optional: [...]}` for a mark type (§5.2). |
| `Visualize.Chart.Schema.options/1` | The option keys a mark type reads (§5.3). |
| `Visualize.Chart.Schema.transform_ops/0` | The transform ops of §5.4. |
| `Visualize.Chart.Schema.scale_kinds/0` | The scale kinds of §4.3. |
| `Visualize.Chart.Schema.builtin_styles/0` | The always-declared style names of §3.3. |

### 14.3 `Visualize.Chart.Validator`

**Implemented.**

| Function | Contract |
|---|---|
| `Visualize.Chart.Validator.validate/1` | `:ok`, or `{:error, errors}` with every fault of §10 by path, ordered by path. |
| `Visualize.Chart.Validator.format/1` | One error as a line: the path in `a[1].b` form, a colon, the reason in words. |

### 14.4 `Visualize.Chart.Migration`

**Implemented.**

| Function | Contract |
|---|---|
| `Visualize.Chart.Migration.current/0` | The schema version this library writes: `1`. |
| `Visualize.Chart.Migration.migrate/1` | `{:ok, map}` at the current version after stepping an older design forward, else `{:error, [{[:version], reason}]}` (§9). |
