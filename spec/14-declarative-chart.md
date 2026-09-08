# Declarative chart layer

**Status:** Agreed

A chart is a nested map — a *design* — that names its data, its coordinate frame, its marks and its labels without a function anywhere in it, so that a design can be stored, diffed, shared, built by a tool and rendered against different data. This document is the contract for the whole layer: the map at every level with every key's type, facet, default and merge rule; the style grammar; sources as typed slots and variables as terms; version and migration; the validator and its error shape; the JSON form; and, as agreed prose, application, composition and compilation. Vega-Lite is the precedent for a stored design and its flat several-hundred-key specification is the warning: the map keeps the three-noun nesting of theme, style and frame (D-57).

Each section states what is implemented. The schema, the validator, the `Visualize.Chart` struct with its map and JSON round-trips, variables and version handling, and the frame — its scales, inference, axes, grid, legend and labels, rendered as the static furniture — are **Implemented**; the marks and transforms, application, composition and compilation are **Agreed** and land in the following work items of proposal #53.

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
| `:anchor` | `:title`, `:subtitle`, `:caption`; `{:axis, s}` with `s` a `{:ref, :scale}`; `{:frame, c}` with `c` one of `:top_left`, `:top_right`, `:bottom_left`, `:bottom_right`; or `{:data, [x, y]}` with `x` and `y` values in the domains of the frame's position scales (§6.3) |
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

**Implemented.** Four style names are always declared, derived from the theme's slots, and a `styles` entry of the same name replaces one whole: `:axis` (`stroke: :axis`, `fill: :text`, `font_family: :font_family`, `font_size: :font_size`), `:grid` (`stroke: :grid`), `:label` (`fill: :text`, `font_family: :font_family`, `font_size: :label_size`) and `:title` (as `:label` with `font_size: :title_size`, `font_weight: :bold`). `Visualize.Chart.Schema.builtin_styles/0` lists them, a `{:ref, :style}` resolves against the union of the built-in and the declared names, and the frame resolves a style to an element's style map by `Visualize.Theme.resolve/3` for every slot in it (§4.7). A mark with no `style` takes the theme's `{:series, i}` for its one-based position among the marks (**Agreed**, work item 3 of #53).

## 4. The frame

### 4.1 Keys

**Implemented.** The frame node is the coordinate system and its furniture. `Visualize.Chart.Frame.new/2` realises a chart's frame into a `%Visualize.Chart.Frame{}` (§4.7) — every scale built once, the theme resolved — and `Visualize.Chart.Frame.generate/2` renders the furniture: grid, axes, legend and labels, the static part of a chart that a data change never touches (§12).

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

**Implemented.** `:size` has `width` and `height`, both `:number`, `:geometry`, required. `:margin` has `top`, `right`, `bottom` and `left`, each `:number`, `:geometry`, default `0`. The plot area is the size less the margins; `Visualize.Chart.Schema.default/2` gives the frame's defaults so a consumer never repeats them, and the frame struct carries the plot area as `plot` (§4.7).

### 4.3 Scales

**Implemented.** A `:scale` node is one of the fourteen kinds `Visualize.Scale` constructs ([03-scales](03-scales.md) §2) with the kind's parameters; every key is `:geometry` and `:override`.

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

**Realisation.** `Visualize.Chart.Frame.new/2` builds one scale struct per entry through the constructors of `Visualize.Scale` — `:linear` by `Visualize.Scale.linear/0`; `:log` by `Visualize.Scale.log/1` with `base`; `:power` by `Visualize.Scale.power/0` with `exponent`; `:sqrt`; `:symlog` with `constant`; `:time`; `:radial`; `:ordinal` with `unknown`; `:band` with `padding` or, when either is given, `padding_inner` and `padding_outer`, then `align` and `round`; `:quantize`, `:quantile` and `:threshold`; `:sequential` and `:diverging` by `Visualize.Scale.Color` over the range — then the domain, the range, and `Visualize.Scale.nice/1` and `Visualize.Scale.clamp/2` when the flags are true. The realised scales are cached on the frame and read through `Visualize.Chart.Frame.scales/1`, the escape hatch for annotations, brush conversion and custom marks; `Visualize.Chart.Frame.put_scale/3` replaces one after construction, which is the code-level override of §1.1 — an axis drawn for that name follows the replacement (D-60).

**Inference.** `domain: :auto`, or an extent with `:auto` at one end, is inferred at construction from every mark channel that names the scale, over the sources given to `new/2`, whole column (Tucan's first-row rule is the documented limit, D-52):

- A channel names a scale by the frame's kind. In a `:cartesian` (and a `:facet`) frame `x`, `x0` and `x1` name `x`; `y`, `y0`, `y1`, `median`, `inner` and `outer` name `y`; `value` names `color`. In a `:polar` frame `angle` names `angle`; `value`, `inner` and `outer` name `r`. In a `:geo` frame `value` names `color`. A `{:field, f}` on a `:colour` key of a mark's style names `color` in every kind (§3.2).
- The values are the channel's column of the mark's source through `Visualize.Data.Table.get/2` — the field itself, or the `f` of a `{:field, f}` — with `nil`s dropped; a number channel contributes the number. A mark whose source is not among the bound sources contributes nothing, and a mark that reads its source through transforms contributes the named column of the untransformed source when it has one (the transformed columns exist at application, §7.3).
- The domain follows the kind. Continuous scales (`:linear`, `:log`, `:power`, `:sqrt`, `:symlog`, `:radial`, `:quantize`, `:threshold`, `:sequential`) take the extent `[lo, hi]` of `Visualize.Data.extent/2`; `:diverging` takes `[lo, (lo + hi) / 2, hi]`. `:time` takes the extent under the values' own ordering (`DateTime`, `Date` or `NaiveDateTime` compare by their module, never by term order), an ISO 8601 string read as `Visualize.Data.Table.temporal?/1` reads it, and a value that is not temporal raises `ArgumentError` naming the scale. `:quantile` takes every value as its samples. `:ordinal` and `:band` take the distinct values in order of first appearance.
- `[0, :auto]` fixes the lower end and infers the upper; `[:auto, hi]` the reverse.
- A collapsed extent — one distinct value — stays `[v, v]`: every continuous scale maps it to the range midpoint and its axis draws one tick (D-49). The frame never widens a domain; an author who wants a readable axis fixes an end.
- Nothing bound gives the unit domain: `[0, 1]` for a continuous scale (`[1, 10]` for `:log`, whose domain excludes zero), `[0, 0.5, 1]` diverging, one day from the Unix epoch for `:time`, `[]` for the discrete and quantile scales. A frame therefore renders without any source, over its unit domains, which is what the static split needs (§12).

**Range.** `range: :auto` follows the scale's name. `x` is `[0, width]` of the plot area and `y` is `[height, 0]`; `angle` is `[0, 2π]`, radians clockwise from 12 o'clock ([04-shapes-and-curves](04-shapes-and-curves.md) §6.2); `r` is `[0, min(width, height) / 2]`; `color` on a discrete scale is the theme's series as slot atoms, `[:series_1, …, :series_n]`, which the legend and the marks resolve through `Visualize.Theme.resolve/3` in the mode of their render target, so a theme swap recolours the scale's output. A `:sequential` scale, whatever its name, runs from the theme's `background` to its first series colour and a `:diverging` one from the second series colour through the background to the first: a colour scale's output is a colour, and the plot area has nothing to offer it. Any other name follows the first axis that names it — `:top` or `:bottom` as `x`, `:left` or `:right` as `y` — and is `[0, 1]` when no axis does. A range given as a list is used as it is; a scheme name is `Visualize.Scale.Color.scheme/1`'s stops, the colours of a discrete scale or the interpolator of a colour scale. A scale name is any atom; the names `x`, `y`, `angle`, `r` and `color` carry the meanings above, so an axis or a legend on any other name MUST say where it draws through `side` and `position`.

### 4.4 Axes and tick specs

**Implemented.** An `:axis` node draws a scale on one side of the plot area; tick geometry is a `:ticks` node, the fourth level.

| Key | Type | Facet | Default | Merge |
|---|---|---|---|---|
| `scale` | `{:ref, :scale}` | `:geometry` | required | `:override` |
| `side` | `{:enum, [:top, :right, :bottom, :left]}` | `:geometry` | required | `:override` |
| `ticks` | `{:one_of, [:integer, {:list, :term}, {:node, :ticks}]}` | `:geometry` | `nil` | `:override` |
| `format` | `:string` | `:content` | `nil` | `:override` |
| `grid` | `:boolean` | `:geometry` | `false` | `:override` |
| `offset` | `:number` | `:geometry` | `0` | `:override` |
| `style` | `{:ref, :style}` | `:style` | `:axis` | `:override` |

`ticks` as an integer is the count hint, as a list the explicit values, as a `:ticks` node both with the sizes: `count` (`:integer`, `:geometry`), `values` (`{:list, :term}`, `:content`), `size_inner` and `size_outer` (`:number`, `:geometry`, `6`) and `padding` (`:number`, `:geometry`, `3`) — the setters of [05-axes-and-formatting](05-axes-and-formatting.md) §1.2 by name. Explicit values beat the count, and the count beats the scale's default of ten.

Each axis is a `Visualize.Axis` on the realised scale, oriented by `side`, with the tick spec, `offset` and the frame's theme applied, generated in the `:resolve` mode of the render (spec/05 §1.4) and placed at its side of the plot area: `:bottom` at `translate(0, height)`, `:right` at `translate(width, 0)`, `:top` and `:left` at the origin. A frame's axis is therefore byte for byte the axis a caller builds by hand from the same scale, and `test/visualize/chart/frame_test.exs` holds it to that. `format` is a `Visualize.Format` specifier applied to every tick value: `Visualize.Format.time/2` on a `:time` scale, `Visualize.Format.formatter/1` on any other, a tick value that is not a number passing through `to_string/1`.

`grid: true` draws a line at each tick position across the plot area — the height for a `:top` or `:bottom` axis, the width for a `:left` or `:right` one — in the `:grid` style, behind every axis, in one group `class="grid"` that is `aria-hidden` like the axes (D-56). The axis's line, ticks and labels draw in its `style`; tick sizes stay geometry. A `style` other than `:axis` restyles the generated axis: `stroke`, `stroke_width`, `stroke_dasharray`, `stroke_linecap`, `stroke_linejoin` and `stroke_opacity` reach the domain line and the tick lines, `fill` and the font keys reach the tick labels, `opacity` and `class` the axis group.

### 4.5 Legend

**Implemented.** A `:legend` node explains one scale, normally the colour scale.

| Key | Type | Facet | Default | Merge |
|---|---|---|---|---|
| `scale` | `{:ref, :scale}` | `:geometry` | required | `:override` |
| `position` | `{:enum, [:top_left, :top_right, :bottom_left, :bottom_right, :top, :bottom, :left, :right]}` | `:geometry` | `:top_right` | `:override` |
| `title` | `:text` | `:content` | `[]` | `:override` |
| `style` | `{:ref, :style}` | `:style` | `:label` | `:override` |

The frame builds the legend from the realised scale: one entry per value of `Visualize.Scale.ticks/2` — the domain of a discrete scale, five ticks of a continuous one — each a 12 × 12 swatch and, 16 user units to its right, the value's label as an axis would print it (spec/05 §1.5). The swatch is filled with the scale's value for the entry when that is a colour — a string, or a theme slot resolved through `Visualize.Theme.resolve/3` (§4.3) — and with the theme's `{:series, i}` for the i-th entry of a scale that yields anything else. The labels and the title take the legend's `style`.

```
group  style: %{class: "legend", font_family: <font_family>, font_size: <font_size>}, transform: translate(x, y)
├── text   style: %{fill: <fill>, font_weight: :bold}, content: title            — when the title is given
└── group  style: %{class: "legend-item"}, transform: translate(…)                — one per entry
    ├── rect  0 0 12 12, style: %{fill: <swatch>}
    └── text  x: 16 (or −4, anchored end), y: 6, dy: "0.32em", style: %{fill: <fill>}, content: label
```

Entries are 16 apart and the title, when given, is the first row. `position` places the legend inside the plot area, 8 user units from its edges: the four corner positions stack the entries downward from the corner, the right-hand ones laid out right to left — the swatch at the edge and the label anchored `end` to its left — so no text width is needed; `:left` and `:right` stack them likewise, centred on the plot's height; `:top` and `:bottom` lay them in one row centred on the plot's width, each entry's width taken as 16 plus 0.6 × the font size per character of its label — the one place the layout estimates text.

### 4.6 Kind-specific nodes

**Implemented.**

- `:cartesian` reads `scales`, `axes` and `legend` as §4.3–4.5 give them.
- `:polar` places its furniture with `translate(width / 2, height / 2)`, the plot centre, and uses `angle` and `r` as its position scales with `R = min(width, height) / 2` the outer radius (§4.3). An axis on `angle` draws a *ring*: the domain circle at `R`, at each tick a line from `R` outward by `size_inner` along the tick's spoke and its label `size_inner + padding` beyond that, anchored `middle` with `dy: "0.32em"`; `grid: true` adds a spoke from the centre to `R` per tick. An axis on `r` draws a *spoke*: the domain line from the centre to `R` in the direction its `side` names (`:top` upward, `:right`, `:bottom`, `:left`), at each tick a line of `size_inner` across the spoke with its label `padding` beyond it, and `grid: true` adds a ring at each tick's radius. An axis on any other scale draws as in a cartesian frame. Its groups are `class="axis axis-angle"` and `class="axis axis-r"`; every polar coordinate is rounded to six decimals with negative zero folded (D-6), so a right angle lands on the axis, and a grid ring of zero radius is not drawn.
- `:geo` takes a `:projection` node in place of position scales: `type` (`:name`, required, a type of `Visualize.Geo.Projection`), `scale` (`:number`), `translate`, `center`, `rotate`, `parallels` (`{:list, :number}`) and `clip_angle` (`:number`), every key `:geometry` and `:override`, defaults those of `Visualize.Geo.Projection.new/1` except `translate`, which defaults to the plot centre. The frame realises it through that module's setters and `Visualize.Chart.Frame.projection/1` returns it; an axis or a legend on a declared scale draws as in a cartesian frame. Delaunay, Voronoi and contours are transforms (§5.4).
- `:facet` repeats the frame over a grouping: a `:facet` node with `by` (`:field`, `:binding`, required) and `columns` (`:integer`, `:geometry`, `nil` for one row). The panels are the distinct values of `by`, in order of first appearance, over the bound source of every mark (a source without the column contributes nothing), so a frame with no bound source has one panel; `Visualize.Chart.Frame.new/2` records them as `panels`. The panels tile the plot area in `columns` columns and as many rows as they need, each `width / columns` by `height / rows`; the scales' `:auto` ranges run over one panel and their domains are shared, so every panel is drawn to the same axes; each panel is a group `class="panel"` translated to its cell holding the grid and the axes, with its value written at the panel's top-left in the `:label` style. The legend and the labels are drawn once, over the whole plot area.
- `viewport` makes a streaming window: `scale` (`{:ref, :scale}`, required) and `span` (`:number`, required), both `:geometry`. A compiled chart over a design with a viewport is stateful (§12, **Agreed**).

### 4.7 The frame struct and its rendering

**Implemented.** `%Visualize.Chart.Frame{}` is the realised frame: `kind`; `size` and `margin` with the schema's defaults filled; `plot`, `%{width, height}` of the plot area; `scales`, the realised structs by name (§4.3); `projection`, a `%Visualize.Geo.Projection{}` in a `:geo` frame and `nil` otherwise; `panels`, the facet values of §4.6, `[]` in any other kind, and `facet`, `%{by, columns}` with the effective column count in a `:facet` frame and `nil` otherwise; `axes`, `legend` and `labels` as the design gives them; `theme`, the `%Visualize.Theme{}` the design names — a built-in name or an inline `:theme` node — or the `theme:` option of `new/2`, which is taken for any name and required for one that is neither built-in nor inline; and `styles`, the declared styles over the built-in four (§3.3).

`Visualize.Chart.Frame.generate/2` is the static furniture as one `Visualize.IR.Element` group with the margins applied, every theme slot resolved through `Visualize.Theme.resolve/3` in its `:resolve` mode (`:css` by default), and every text a string:

```
group  style: %{class: "frame"}, transform: translate(margin.left, margin.top)
├── group  style: %{class: "grid"}, attrs: %{aria_hidden: "true"}   — when any axis has grid: true (§4.4)
├── group  style: %{class: "axis axis-<side>"}, transform            — one per axis, holding the Visualize.Axis group
├── group  style: %{class: "legend"}                                 — when a legend is given (§4.5)
└── text   style: %{class: "label", …}                               — one per label (§6.3)
```

A `:facet` frame holds one `class="panel"` group per panel in place of the grid and axes; a `:polar` frame's grid and axes sit inside a group translated to the plot centre. A `%Visualize.Chart.Var{}` reached while building — in a text, a style or a node — raises `ArgumentError` naming it: variables resolve at application (§7.3), and a frame is built from an applied design or from one that uses none. `Visualize.Chart.Frame.render/2` is `generate/2` followed by `Visualize.Render.to_string/2`, with `:resolve` defaulting to `Visualize.Theme.mode/1` of the `:backend`, as `Visualize.Axis.render/2` does.

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

`{:axis, s}` anchors the label as the title of the axis drawn for scale `s`; `s` is a scale reference and is checked as one. `{:frame, c}` anchors it at a corner of the plot area and `{:data, [x, y]}` at a point of the data (§6.3).

### 6.2 Text

**Implemented.** A text is a list, never a parsed string: `["Uptime — ", var(:unit)]`, `["deploy ", {:field, :sha}]`. Strings are literal, a variable resolves at application, a field reference reads the datum (inline labels) or is an error (frame labels, which have no datum: `{:invalid_for, :label}`). A `"{{unit}}"` string form MAY be added later as sugar that compiles to the list.

### 6.3 Placement

**Implemented.** The frame draws each label as one `text` element in its `style`, `class="label"`, at the anchor's position; `dx` and `dy` are added to it. With `w` and `h` the plot area and `m` the margin:

| Anchor | Position | `text_anchor` | Default style |
|---|---|---|---|
| `:title` | `(w / 2, −m.top / 2)`, `dy: "0.32em"`: centred in the top margin | `:middle` | `:title` |
| `:subtitle` | `(w / 2, −4)`: just above the plot area | `:middle` | `:label` |
| `:caption` | `(0, h + m.bottom − 4)`: the bottom-left of the chart | `:start` | `:label` |
| `{:axis, s}`, axis on `:bottom` | `(w / 2, h + m.bottom − 5)` | `:middle` | `:label` |
| `{:axis, s}`, axis on `:top` | `(w / 2, −m.top + 5)`, `dy: "0.71em"` | `:middle` | `:label` |
| `{:axis, s}`, axis on `:left` | `rotate(−90)`, `(−h / 2, −m.left + 15)` | `:middle` | `:label` |
| `{:axis, s}`, axis on `:right` | `rotate(90)`, `(h / 2, −(w + m.right − 15))` | `:middle` | `:label` |
| `{:frame, :top_left}` | `(4, 4)`, `dy: "0.71em"` | `:start` | `:label` |
| `{:frame, :top_right}` | `(w − 4, 4)`, `dy: "0.71em"` | `:end` | `:label` |
| `{:frame, :bottom_left}` | `(4, h − 4)` | `:start` | `:label` |
| `{:frame, :bottom_right}` | `(w − 4, h − 4)` | `:end` | `:label` |
| `{:data, [x, y]}` | the point through the frame's position scales | `:start` | `:label` |

An axis title follows the side of the first axis that names its scale; with no axis on the scale, `x` is taken as `:bottom`, `y` as `:left`, and any other name as `:bottom`. A data anchor maps `[x, y]` through the scales named `x` and `y` in a `:cartesian` or `:facet` frame (the first panel), through `angle` and `r` in a `:polar` frame — `(R sin a, −R cos a)` from the centre — and through the projection in a `:geo` frame, where the pair is `[longitude, latitude]` and a point the projection clips is not drawn. A `text_anchor` in the label's style replaces the anchor's own.

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
| `{:frame, :top_left}` | `{"$frame": "top_left"}` |
| `{:data, [x, y]}` | `{"$data": [x, y]}`, the two values as terms |
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
    %{anchor: {:axis, :y}, text: ["unit: ", var(:unit)]},
    %{anchor: {:frame, :top_right}, text: ["last 24 h"]},
    %{anchor: {:data, [~U[2026-09-08 12:00:00Z], 99.5]}, text: ["target"]}
  ]
}
```

Its application, once item 5 lands, is `Chart.apply(design, sources: %{primary: idle, deploys: deploys}, vars: %{unit: "mg/hr"})`; `Chart.compile/1` then splits it into the static frame and the dynamic marks. Its frame renders today: `Visualize.Chart.Frame.new(chart, sources: %{primary: idle, deploys: deploys})` once the variables are supplied, or without sources over the unit domains (§4.3).

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

### 14.5 `Visualize.Chart.Frame`

**Implemented.** The realised frame of §4.7.

| Function | Contract |
|---|---|
| `Visualize.Chart.Frame.new/1` | As `new/2` with `[]` options: no source bound, every `:auto` domain the unit domain. |
| `Visualize.Chart.Frame.new/2` | `new(chart, opts)`: the `%Visualize.Chart.Frame{}` of a `%Visualize.Chart{}`, every scale realised (§4.3) from `sources:` — a map from source name to anything `Visualize.Data.Table.rows/1` reads, `%{}` by default — and the theme resolved, `theme:` supplying a `%Visualize.Theme{}` that is taken for any theme name and required for one that is neither built-in nor inline (§4.7). Raises `ArgumentError` for an unresolved variable, a theme name it cannot resolve, or a bound value a scale cannot take. |
| `Visualize.Chart.Frame.scales/1` | The realised scales by name (§4.3): the escape hatch. |
| `Visualize.Chart.Frame.scale/2` | `scale(frame, name)`: one realised scale; `ArgumentError` when the frame declares no such scale. |
| `Visualize.Chart.Frame.put_scale/3` | `put_scale(frame, name, scale)`: the frame with the realised scale replaced by the given struct; the override of §4.3. |
| `Visualize.Chart.Frame.projection/1` | The `%Visualize.Geo.Projection{}` of a `:geo` frame (§4.6), `nil` for any other kind. |
| `Visualize.Chart.Frame.generate/1` | As `generate/2` with `resolve: :css`. |
| `Visualize.Chart.Frame.generate/2` | The static furniture as the `Visualize.IR.Element` group of §4.7, theme slots resolved in the `:resolve` mode. |
| `Visualize.Chart.Frame.render/1` | As `render/2` with `[]` options. |
| `Visualize.Chart.Frame.render/2` | `generate/2` rendered through `Visualize.Render.to_string/2`; `:resolve` defaults to `Visualize.Theme.mode/1` of the `:backend`. |
