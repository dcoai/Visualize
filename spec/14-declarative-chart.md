# Declarative chart layer

**Status:** Agreed

A chart is a nested map — a *design* — that names its data, its coordinate frame, its marks and its labels without a function anywhere in it, so that a design can be stored, diffed, shared, built by a tool and rendered against different data. This document is the contract for the whole layer: the map at every level with every key's type, facet, default and merge rule; the style grammar; sources as typed slots and variables as terms; version and migration; the validator and its error shape; the JSON form; and, as agreed prose, application, composition and compilation. Vega-Lite is the precedent for a stored design and its flat several-hundred-key specification is the warning: the map keeps the three-noun nesting of theme, style and frame (D-57).

Each section states what is implemented. The schema, the validator, the `Visualize.Chart` struct with its map and JSON round-trips, variables and version handling, the frame — its scales, inference, axes, grid, legend and labels, rendered as the static furniture — and the marks — every mark type drawn from the frame's scales by the existing generators, the transforms as steps of a mark's data pipeline, and the style grammar resolved to an SVG and a canvas output — and the presets — the ten LiveView components of [10-liveview-integration](10-liveview-integration.md) as stored designs plus an assign mapping (§15) — and application and composition — variables resolved and slots bound by `Visualize.Chart.apply/2` into an applied chart, fragments merged by `Visualize.Chart.compose/2` under the schema's merge rules (§7.3, §8) — and compilation — the static/dynamic split computed from the design, a render target per mark from the bound data, the hybrid chart map per tick, the streaming window over the incremental path, and the payload measured (§12) — are **Implemented**.

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
| 3 | size, margin, scales, axes, legend, projection, facet, viewport; a mark's data, channels, scales, options and inline label; a style's curve options | `:size`, `:margin`, `:scale`, `:axis`, `:legend`, `:projection`, `:facet`, `:viewport`, `:data`, `:channels`, `:mark_scales`, `:options`, `:mark_label`, `:curve_opts` |
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

**Implemented** as data, applied by `Visualize.Chart.compose/2` (§8). Every key declares how two fragments combine under it:

| Rule | Keys | Effect |
|---|---|---|
| `:concat` | every list of nodes: `marks`, `labels`, `axes`, `transforms` | the later fragment's elements follow the earlier's; the elements are never merged with each other |
| `:union` | every name-keyed declaration: `sources`, `vars`, `styles`, `scales` | the union of the two maps; a name declared with equal values in both is taken once, and declared differently in both is `:conflict` at the name's path |
| `:override` | every scalar and every other node: `version`, `theme`, `size`, `kind`, `type`, `text`, … | the later fragment's value replaces the earlier's. A node given as a map by both fragments composes key by key under its own kind's rules, so a frame fragment adds its scales and axes to another's (§8); given as anything else by either — a name, a variable — it is replaced whole |

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

**Implemented.** A `:source` is a typed slot (§7.2): the fields the design reads from it, and the name of the pool entry that fills it when application supplies none under the slot's own name (§7.3).

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
- a **channel binding** `{:field, f}` for any key, which is how `Visualize.Shape.Band`'s per-datum fill is expressed: the value is read from the datum at render — per element for a mark that draws one element per datum, from the series' first datum for a mark that draws one path per series (§5.6) — and, for a `:colour` key, passed through the scale named `color` when the frame declares one (§3.4).

Fourteen keys reach the element the mark draws; the other four — `curve`, `curve_opts`, `symbol` and `symbol_size` — reach the mark's generator (§5.6) and never an element.

For an enumerated key an atom is the literal; for a `:colour`, `:size` or `:font` key an atom is a slot, and `:none` is the literal "no paint". The validator checks a slot against the theme's `Visualize.Theme.slots/1` when the theme is built-in or inline (§2.5) and reports `{:undeclared, :slot, name}` otherwise.

### 3.3 Built-in styles

**Implemented.** Four style names are always declared, derived from the theme's slots, and a `styles` entry of the same name replaces one whole: `:axis` (`stroke: :axis`, `fill: :text`, `font_family: :font_family`, `font_size: :font_size`), `:grid` (`stroke: :grid`), `:label` (`fill: :text`, `font_family: :font_family`, `font_size: :label_size`) and `:title` (as `:label` with `font_size: :title_size`, `font_weight: :bold`). `Visualize.Chart.Schema.builtin_styles/0` lists them, a `{:ref, :style}` resolves against the union of the built-in and the declared names, and the frame resolves a style to an element's style map by `Visualize.Theme.resolve/3` for every slot in it (§4.7). A mark whose style gives no value for its paint key — `stroke` for a stroked type, `fill` for a filled one — takes the theme's `{:series, i}` for its one-based position among the marks as its paint (§5.6).

### 3.4 Resolution: one node, two outputs

**Implemented.** A style node resolves to the style map of a `Visualize.IR.Element` through `Visualize.Chart.Style.resolve/3` in the mode of the render target, and the mode is what makes one node serve two backends (D-63): in `:css` the SVG output carries classes and CSS custom-property references — `class="mark mark-line series"`, `stroke="var(--vis-series-1, #3b6fa8)"` — that a stylesheet overrides; in `:literal` a canvas gets the plain colour, width and font it needs, which `Visualize.Backend.Canvas` reads as they are (spec/09 §3). `resolve/3` keeps the fourteen element keys, resolves every slot through `Visualize.Theme.resolve/3`, joins a dash-array list with spaces and passes a literal through; a `{:field, f}` survives it unchanged, and `Visualize.Chart.Style.bind/4` then reads it from a datum through `Visualize.Data.Table.get/2` — a `:colour` key's reading through the frame's `color` scale when the frame declares one, the scale's output resolved as a slot when it is one — and drops the key when the reading is `nil`. A variable in either raises `ArgumentError` naming it: variables resolve at application (§7.3).

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

- A channel names a scale by the frame's kind. In a `:cartesian` (and a `:facet`) frame `x`, `x0` and `x1` name `x`; `y`, `y0`, `y1`, `median`, `inner_lo`, `inner_hi`, `outer_lo` and `outer_hi` name `y`; `series` names `color`, and so does `value` on a `:rect`. In a `:polar` frame `angle` names `angle`; `value` on a `:rose`, `inner` and `outer` name `r`. In a `:geo` frame `series` names `color`. The `value` of a `:symbol`, a `:circle` and an `:arc` is a size or a share (§5.2) and names nothing. A mark's `scales` node (§5.1) renames what its channels name: `scales: %{x: :count}` sends that mark's `x`, `x0` and `x1` through the frame's `count` scale instead of `x`, so a scale of any other name — a marginal histogram's counts, a second `y` — is inferred from, and drawn by, the marks that name it (D-67). A `{:field, f}` on a `:colour` key of a mark's style names `color` in every kind (§3.2), whatever the mark's `scales` say.
- The values are the channel's column of the mark's source through `Visualize.Data.Table.get/2` — the field itself, or the `f` of a `{:field, f}` — with `nil`s dropped; a number channel contributes the number. A mark whose source is not among the bound sources contributes nothing; a mark that reads its source through transforms contributes the column of the *transformed* rows — the pipeline of §5.4 runs at construction over the bound source, so a `:bin`'s `count` or a `:stack`'s `y1` infers the domain it is drawn on (D-62).
- The domain follows the kind. Continuous scales (`:linear`, `:log`, `:power`, `:sqrt`, `:symlog`, `:radial`, `:quantize`, `:threshold`, `:sequential`) take the extent `[lo, hi]` of `Visualize.Data.extent/2`; `:diverging` takes `[lo, (lo + hi) / 2, hi]`. `:time` takes the extent under the values' own ordering (`DateTime`, `Date` or `NaiveDateTime` compare by their module, never by term order), an ISO 8601 string read as `Visualize.Data.Table.temporal?/1` reads it, and a value that is not temporal raises `ArgumentError` naming the scale. `:quantile` takes every value as its samples. `:ordinal` and `:band` take the distinct values in order of first appearance.
- `[0, :auto]` fixes the lower end and infers the upper; `[:auto, hi]` the reverse.
- A collapsed extent — one distinct value — stays `[v, v]`: every continuous scale maps it to the range midpoint and its axis draws one tick (D-49). The frame never widens a domain; an author who wants a readable axis fixes an end.
- Nothing bound gives the unit domain: `[0, 1]` for a continuous scale (`[1, 10]` for `:log`, whose domain excludes zero), `[0, 0.5, 1]` diverging, one day from the Unix epoch for `:time`, `[]` for the discrete and quantile scales. A frame therefore renders without any source, over its unit domains, which is what the static split needs (§12).

**Range.** `range: :auto` follows the scale's name. `x` is `[0, width]` of the plot area and `y` is `[height, 0]`; `angle` is `[0, 2π]`, radians clockwise from 12 o'clock ([04-shapes-and-curves](04-shapes-and-curves.md) §6.2); `r` is `[0, min(width, height) / 2]`; `color` on a discrete scale is the theme's series as slot atoms, `[:series_1, …, :series_n]`, which the legend and the marks resolve through `Visualize.Theme.resolve/3` in the mode of their render target, so a theme swap recolours the scale's output. A `:sequential` scale, whatever its name, runs from the theme's `background` to its first series colour and a `:diverging` one from the second series colour through the background to the first: a colour scale's output is a colour, and the plot area has nothing to offer it. Any other name follows the first axis that names it — `:top` or `:bottom` as `x`, `:left` or `:right` as `y` — and is `[0, 1]` when no axis does. A range given as a list is used as it is, and an empty list raises `ArgumentError` naming the scale — a scale with no value to map to is an authoring error, not a scale; a scheme name is `Visualize.Scale.Color.scheme/1`'s stops, the colours of a discrete scale or the interpolator of a colour scale. A scale name is any atom; the names `x`, `y`, `angle`, `r` and `color` carry the meanings above, so an axis or a legend on any other name MUST say where it draws through `side` and `position`.

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
- `:facet` repeats the frame over a grouping: a `:facet` node with `by` (`:field`, `:binding`, required) and `columns` (`:integer`, `:geometry`, `nil` for one row). The panels are the distinct values of `by`, in order of first appearance, over the bound source of every mark (a source without the column contributes nothing), so a frame with no bound source has one panel; `Visualize.Chart.Frame.new/2` records them as `panels`. The panels tile the plot area in `columns` columns and as many rows as they need, each `width / columns` by `height / rows`; the scales' `:auto` ranges run over one panel and their domains are shared, so every panel is drawn to the same axes; each panel is a group `class="panel"` translated to its cell holding the grid, the marks drawn from the rows whose `by` is the panel's value (§5.6), and the axes, with its value written at the panel's top-left in the `:label` style. The legend and the labels are drawn once, over the whole plot area.
- `viewport` makes a streaming window: `scale` (`{:ref, :scale}`, required) and `span` (`:number`, required), both `:geometry`. The frame itself draws the scale over its inferred or given domain; a compiled chart over a design with a viewport windows the scale to `[hi − span, hi]` on every tick and is stateful (§12.5).

### 4.7 The frame struct and its rendering

**Implemented.** `%Visualize.Chart.Frame{}` is the realised frame: `kind`; `size` and `margin` with the schema's defaults filled; `plot`, `%{width, height}` of the plot area; `scales`, the realised structs by name (§4.3); `projection`, a `%Visualize.Geo.Projection{}` in a `:geo` frame and `nil` otherwise; `panels`, the facet values of §4.6, `[]` in any other kind, and `facet`, `%{by, columns}` with the effective column count in a `:facet` frame and `nil` otherwise; `axes`, `legend`, `labels` and `marks` as the design gives them; `theme`, the `%Visualize.Theme{}` the design names — a built-in name or an inline `:theme` node — or the `theme:` option of `new/2`, which is taken for any name and required for one that is neither built-in nor inline; and `styles`, the declared styles over the built-in four (§3.3).

`Visualize.Chart.Frame.generate/2` is the static furniture as one `Visualize.IR.Element` group with the margins applied, every theme slot resolved through `Visualize.Theme.resolve/3` in its `:resolve` mode (`:css` by default), and every text a string:

```
group  style: %{class: "frame"}, transform: translate(margin.left, margin.top)
├── group  style: %{class: "grid"}, attrs: %{aria_hidden: "true"}   — when any axis has grid: true (§4.4)
├── group  style: %{class: "mark mark-<type>"}                        — one per mark, when sources are given (§5.6)
├── group  style: %{class: "axis axis-<side>"}, transform            — one per axis, holding the Visualize.Axis group
├── group  style: %{class: "legend"}                                 — when a legend is given (§4.5)
└── text   style: %{class: "label", …}                               — one per label (§6.3)
```

A `:facet` frame holds one `class="panel"` group per panel in place of the grid, marks and axes; a `:polar` frame's grid, marks and axes sit inside a group translated to the plot centre. `generate/2` draws the marks only when given `sources:` — a map from source name to anything `Visualize.Data.Table.rows/1` reads, as `new/2` takes — each through `Visualize.Chart.Mark.generate/3` at its one-based position; without sources it is the furniture alone, which is what the static split needs (§12). A `%Visualize.Chart.Var{}` reached while building — in a text, a style or a node — raises `ArgumentError` naming it: variables resolve at application (§7.3), and a frame is built from an applied design or from one that uses none. `Visualize.Chart.Frame.render/2` is `generate/2` followed by `Visualize.Render.to_string/2`, with `:resolve` defaulting to `Visualize.Theme.mode/1` of the `:backend`, as `Visualize.Axis.render/2` does.

## 5. Marks

### 5.1 Keys

**Implemented.** A mark binds fields of its data to the frame's scales and draws them with one of the existing generators. `Visualize.Chart.Mark.generate/3` draws one mark of a frame (§5.6); `Visualize.Chart.Frame.generate/2` draws every mark of the design when it is given the sources (§4.7). `render` is the compiler's override (§12.3) and changes nothing `generate/3` draws.

| Key | Type | Facet | Default | Merge |
|---|---|---|---|---|
| `type` | `{:enum, mark types}` | `:channel` | required | `:override` |
| `data` | `{:one_of, [{:ref, :source}, {:node, :data}]}` | `:binding` | required | `:override` |
| `channels` | `{:node, :channels}` | `:channel` | `%{}` | `:override` |
| `scales` | `{:node, :mark_scales}` | `:channel` | `%{}` | `:override` |
| `options` | `{:node, :options}` | `:geometry` | `%{}` | `:override` |
| `style` | `{:ref, :style}` | `:style` | `nil` (§3.3) | `:override` |
| `label` | `{:node, :mark_label}` | `:content` | `nil` | `:override` |
| `render` | `{:enum, [:auto, :svg, :canvas, :binary]}` | `:geometry` | `:auto` | `:override` |

`scales` is the mark's word on which scale a channel family reads through (§4.3). A `:mark_scales` node's keys are the scale names of the frame kinds' tables — `x`, `y`, `angle`, `r` and `color` — each `{:ref, :scale}`, `:channel`, `nil` by default, `:override`; a key the frame's kind does not use names nothing. `scales: %{x: :count}` sends the mark's `x`, `x0` and `x1` through the declared scale `count`, and every channel not renamed reads the scale of the kind's table as before. The name must be one the frame declares (`{:undeclared, :scale, name}` otherwise), so a mark still references scales by name and never by nesting (§1.2).

### 5.2 Types and channels

**Implemented.** The mark types are the data-shaped generators of [04-shapes-and-curves](04-shapes-and-curves.md) and four generic marks. A `:channels` node's keys are the channels; every key is `:channel`, `:override`, of type `:channel`. Which channels a mark takes is a function of its type, and the validator reports a channel the type does not read as `{:invalid_for, type}`:

| Type | Required | Optional | Draws |
|---|---|---|---|
| `:line` | `x`, `y` | `series` | `Visualize.Shape.Line`, one path per series |
| `:area` | `x`, `y` | `x0`, `x1`, `y0`, `y1`, `series` | `Visualize.Shape.Area`, one path per series |
| `:band` | `x0`, `x1` | `y` | `Visualize.Shape.Band`, one rectangle per datum |
| `:rule` | `x` | | `Visualize.Shape.Rule`, spanning the plot height |
| `:x_band` | `x0`, `x1` | | `Visualize.Shape.XBand`, spanning the plot height |
| `:percentile_band` | `x`, `median` | `inner_lo`, `inner_hi`, `outer_lo`, `outer_hi` | `Visualize.Shape.PercentileBand`: outer, inner, median |
| `:rose` | `angle` | `value` | `Visualize.Shape.Rose`; `value` is the petal's outer radius |
| `:symbol` | `x`, `y` | `value` | `Visualize.Shape.Symbol` at each datum; `value` is its area |
| `:arc` | `value` | `start`, `end`, `inner`, `outer` | `Visualize.Shape.Arc` over `Visualize.Shape.Pie`; `value` is the share — or, with both `start` and `end`, `Visualize.Shape.Arc` over each datum's own angles, and `value` is not required (D-69) |
| `:path` | `path` | | one path element per datum: the row's `Visualize.IR.Path`, in plot pixels |
| `:rect` | `x0`, `x1`, `y0`, `y1` | `value` | a rectangle per datum; `value` reaches the colour scale |
| `:circle` | `x`, `y` | `value` | a circle per datum; `value` is the radius |

`Visualize.Chart.Schema.channels/1` returns the two lists for a type. A channel reads its field from each row through `Visualize.Data.Table.get/2` — a number is a constant, a `{:field, f}` reads `f` — and the frame maps the reading through the scale the channel names (§4.3) when the frame declares that scale. A datum the scale cannot place (a `nil` reading, or a category a `:band` or an `:ordinal` scale does not hold) is dropped from a per-datum mark and breaks a path mark's path there, as `defined/2` of spec/04 §1.2 would. Through a `:band` scale `x0` (and `y0`) is the band's start, `x1` (`y1`) its end — the start plus `Visualize.Scale.bandwidth/1` — and `x` (`y`) its centre, so a bar over categories is `x0: :cat, x1: :cat` and a point over them sits mid-band. A channel that names no scale, or names one the frame does not declare, is read as pixels: `path`, the `value` of a `:symbol` and of a `:circle`, the `value`, `start` and `end` of an `:arc` (a share and two angles in radians, never scaled in any kind), and the position channels of a `:geo` frame, whose pixels come from the `:projection` transform (§5.4.4). An `:arc`'s `value` is required unless both `start` and `end` are given, and either of those two requires the other: the validator reports the missing one as `:required` (D-69). `series` splits a `:line` or an `:area` into one path per distinct value, in order of first appearance, and colours each as §5.6 says.

### 5.3 Options

**Implemented.** An `:options` node holds a mark's geometry scalars, every key `:number`, `:geometry`, `:override`; the validator reports a key the type does not read as `{:invalid_for, type}`. `Visualize.Chart.Schema.options/1` returns a type's keys; the defaults are the generators' own, with `R` the outer radius `min(width, height) / 2` of the plot area.

| Type | Keys and defaults |
|---|---|
| `:band` | `height` (`10`) |
| `:rose` | `width` (`1`, in the angle scale's domain units), `inner_radius` (`0`), `outer_radius` (the `value` reading, else `R`), `pad_angle` (`0`) |
| `:arc` | `inner_radius` (`0`), `outer_radius` (`R`), `corner_radius` (`0`), `pad_angle` (`0`), `start_angle` (`0`), `end_angle` (`2π`) |
| `:rect` | `corner_radius` (`0`) |
| `:circle` | `radius` (`3`, when `value` is absent) |
| every other type | none |

An `:arc`'s `inner` and `outer` channels replace `inner_radius` and `outer_radius` per datum; its `start` and `end` channels, given together, replace the pie — `start_angle` and `end_angle` are not read then, and `pad_angle` is the arc's own (`Visualize.Shape.Arc.pad_angle/2`) rather than the pie's. Angles are radians and sizes user units, as in [11-public-api](11-public-api.md) §3.3.

### 5.4 Data and transforms

**Implemented.** `data` is a source name, or a `:data` node with `source` (`{:ref, :source}`, `:binding`, required) and `transforms` (`{:list, {:node, :transform}}`, `:binding`, `[]`, `:concat`). Layouts, binning, stacking, aggregation and the geo algorithms are transforms — steps in a mark's data pipeline that yield rows — never marks: a treemap is a `:treemap` transform producing rows with `x0 y0 x1 y1` that a `:rect` draws, and a chord diagram is a `:chord` transform whose rows carry a `path` that a `:path` mark draws.

`Visualize.Chart.Transform.apply/3` runs the steps in order over the source's rows (`Visualize.Data.Table.rows/1`), each step a pure function of the rows before it and its node, yielding the rows the next step or the mark reads. Its only context is the plot area, as `size:`, and in a `:geo` frame the projection, as `projection:` — never a scale, so the frame runs the pipeline before its scales exist and infers their domains from the transformed columns (§4.3, D-62). A step that reads a column the rows lack reads `nil` and treats it as the op says; a step that lacks a key its op requires raises `ArgumentError` naming both.

A `:transform` node has `op` (`{:enum, ops}`, `:binding`, required) and the keys its op reads; every key is `:override`. `Visualize.Chart.Schema.transform_keys/1` returns the required and optional keys of an op, and the validator reports a missing required key as `:required` and a key the op does not read as `{:invalid_for, op}`:

| Key | Type | Facet | Read by |
|---|---|---|---|
| `field` | `:field` | `:binding` | `:bin`, `:sum`, `:sort`, `:contour` (the value); the hierarchies (the value summed); `:chord`, `:sankey` (the flow's value); `:density` (the weight) |
| `fields` | `{:list, :field}` | `:binding` | `:stack` (the series); `:chord`, `:sankey`, `:force` (`[source, target]`); `:delaunay`, `:voronoi`, `:density` (`[x, y]`); `:projection` (`[longitude, latitude]`) |
| `by` | `:field` | `:binding` | `:sum` (the group), the hierarchies (the parent) |
| `id` | `:field` | `:binding` | the hierarchies (the node identifier) |
| `as` | `:name` | `:binding` | `:bin`, `:sum` (the output column) |
| `thresholds` | `{:one_of, [:integer, {:list, :number}]}` | `:geometry` | `:bin`, `:contour`, `:density` |
| `order` | `{:enum, [:none, :ascending, :descending, :inside_out, :reverse, :appearance]}` | `:geometry` | `:stack`, `:sort` |
| `offset` | `{:enum, [:none, :expand, :silhouette, :wiggle, :diverging]}` | `:geometry` | `:stack` |
| `size` | `{:list, :number}` | `:geometry` | the layouts and the geo algorithms (`[width, height]`, default the plot area); `:contour` (the grid's `[columns, rows]`) |
| `padding` | `:number` | `:geometry` | the hierarchies, `:sankey` (the node gap), `:chord` (the pad angle) |
| `tile` | `{:enum, [:squarify, :binary, :slice, :dice, :slice_dice]}` | `:geometry` | `:treemap` |
| `bandwidth` | `:number` | `:geometry` | `:density` |
| `output` | `{:enum, [:nodes, :links, :groups, :chords, :triangles, :hull, :cells, :edges]}` | `:binding` | the layouts and the geo algorithms: which rows they yield |
| `test` | `{:enum, [:eq, :ne, :lt, :lte, :gt, :gte, :present, :absent]}` | `:binding` | `:filter` (how the reading is tested, `:present` by default) |
| `value` | `:term` | `:binding` | `:filter` (what the reading is tested against, `nil` by default) |

The ops are `:filter`, `:bin`, `:stack`, `:sum`, `:sort`, `:tree`, `:cluster`, `:pack`, `:partition`, `:treemap`, `:chord`, `:sankey`, `:force`, `:contour`, `:density`, `:delaunay` and `:voronoi` (`Visualize.Chart.Schema.transform_ops/0`) and `:projection`. Every row a step yields is a map; a row the step derives from a datum keeps the datum's columns and adds its own, so a `:treemap` node still carries its `name`. A field named in a mark's `channels`, in its inline label's text or in its transforms is checked against the source's declared `fields` when the mark reads the source directly. After a transform the columns are the transform's, and a `{:field, f}` in a style is shared by every mark that references the style; those references are read at render, when the rows exist.

#### 5.4.1 Data steps

- `:filter` — `field` required; `test` (`:present`) and `value` (`nil`). The rows, in order, whose reading of `field` through `Visualize.Data.Table.get/2` passes the test: `:present` keeps a reading that is not `nil` and `:absent` one that is; `:eq` keeps a reading equal to `value` (`==`) and `:ne` one that is not; `:lt`, `:lte`, `:gt` and `:gte` keep a reading that is not `nil` and stands so to `value` under Elixir's term ordering, as `:sort` orders — a `nil` reading never passes an ordering. The step reads a column the rows lack as `nil`, so `%{op: :filter, field: :height, test: :eq, value: 0}` after a hierarchy keeps its leaves and `%{op: :filter, field: :depth, test: :gt, value: 0}` drops its root (D-68). The transform node's `op` names the step, which is why the test is not under `op`.
- `:bin` — `field` required; `thresholds` (`10`) and `as` (`:count`). `Visualize.Data.bin/2` over the column with `nil`s dropped, one row per bin: `x0`, `x1`, `y0` (`0`, so a histogram's channels read the rows alone), `as` (the bin's count) and `values`.
- `:stack` — `fields` required (the series keys); `order` (`:none`), `offset` (`:none`). `Visualize.Shape.Stack` with the keys, the order and the offset (`:inside_out` is its `:insideout`; `:appearance` orders the keys by the index of each series' greatest value, d3's `stackOrderAppearance`, before a `:none` stack). One row per series in key order, per datum in data order: the datum's columns plus `key`, `series` (the series' stacking position), `value`, `y0` and `y1`.
- `:sum` — `field` required; `by` and `as` (`:sum`). One row per distinct `by` value in order of first appearance, `%{by => value, as => sum}` with `nil`s ignored; without `by`, one row `%{as => sum}`.
- `:sort` — `field` required; `order` (`:ascending`, or `:descending`). The rows stably sorted by the column under `Enum.sort_by/3`'s ordering.

#### 5.4.2 Hierarchies

`:tree`, `:cluster`, `:pack`, `:partition` and `:treemap` read the rows as a flat node list: `id` (`:id`) names each node and `by` (`:parent`) its parent, `nil` or `""` for the root, through `Visualize.Layout.Hierarchy.stratify/2`; `field` names the value `Visualize.Layout.Hierarchy.sum/2` adds up (`nil` as `0`), and without it `Visualize.Layout.Hierarchy.count/1` counts leaves. `size` (`[width, height]`, default the plot area) and `padding` (`0`) reach the layout's own setters, `tile` (`:squarify`) the treemap's. The hierarchies of [06-layouts](06-layouts.md) §2–5 lay out the tree exactly as a direct call would.

- `output: :nodes` (the default) — one row per node in pre-order (`Visualize.Layout.Hierarchy.descendants/1`): the datum's columns plus `depth`, `height`, `value` and the layout's own fields — `x`, `y` for `:tree` and `:cluster`; `x`, `y`, `r` for `:pack`; `x0`, `y0`, `x1`, `y1` for `:partition` and `:treemap`.
- `output: :links` (`:tree`, `:cluster` and `:pack`) — one row per parent–child pair in the order of `Visualize.Layout.Hierarchy.links/1`: `source` and `target` (the ids), `x0`, `y0` (the parent's position), `x1`, `y1` (the child's) and `path`, a `Visualize.IR.Path` — for `:tree` and `:cluster` the vertical link `M x0,y0 C x0,ym x1,ym x1,y1` with `ym` the mid-height, for `:pack` the straight line between the centres.

#### 5.4.3 Graphs

`:chord`, `:sankey` and `:force` read the rows as flows: `fields: [source, target]` required, `field` the flow's value (`1` when absent for `:force`, required by the other two). The nodes are the distinct ids over every source and then every target, in order of first appearance. `size` (`[width, height]`) defaults to the plot area; every position and path is in its pixels.

- `:chord` — `padding` (`0`) is the pad angle in radians. The flows fill the square matrix of `Visualize.Layout.Chord.generate/2` (a repeated pair adds up); with `R = min(width, height) / 2` and the centre at `(width / 2, height / 2)`, `output: :groups` (the default) yields one row per group in index order — `index`, `id`, `start_angle`, `end_angle`, `value` and `path`, the annulus sector between `0.9 R` and `R` as `Visualize.Shape.Arc` draws it, translated to the centre — and `output: :chords` one row per chord in row-major order: `source`, `target` (the ids), `source_value`, `target_value` and `path`, the ribbon at `0.9 R` of `Visualize.Layout.Chord.ribbon_path/2` as a `Visualize.IR.Path` (the source arc, a quadratic curve through the centre to the target arc's start, the target arc, a quadratic curve back, `Z`), translated to the centre.
- `:sankey` — `padding` (`8`) is the node gap; the node width is `24`. `Visualize.Layout.Sankey.compute/3` over the nodes and the flows; `output: :nodes` (the default) yields one row per node in input order with `id`, `index`, `depth`, `height`, `layer`, `value`, `x0`, `x1`, `y0`, `y1`; `output: :links` one row per flow in input order with `source`, `target`, `value`, `width`, `x0` (the source node's right edge), `y0`, `x1` (the target node's left edge), `y1` and `path`, the ribbon of `Visualize.Layout.Sankey.generate_link_path/1` as a `Visualize.IR.Path`.
- `:force` — `Visualize.Layout.Force.run/1` over the nodes and the flows with the forces `[{:center, x: width / 2, y: height / 2}, {:many_body, strength: -30}, {:link, distance: 30}]` and its default 300 iterations: a pure function of the input, so a design renders the same graph twice. `output: :nodes` (the default) yields one row per node with `id`, `x`, `y`; `output: :links` one row per flow with `source`, `target`, `x0`, `y0`, `x1`, `y1` and `path`, the straight line.

#### 5.4.4 Geo algorithms

`:delaunay`, `:voronoi` and `:density` read pixel coordinates from `fields: [x, y]` (required); a `nil` coordinate drops the datum. They run after a `:projection` step, or a `:force`, or over columns already in pixels, and never through a scale.

- `:projection` — `fields: [longitude, latitude]` required; the projection is the frame's (`projection:` of `Visualize.Chart.Transform.apply/3`), and a pipeline without one raises `ArgumentError`. Each row gains `x` and `y` from `Visualize.Geo.Projection.project/3`; a point the projection clips is dropped.
- `:delaunay` — `Visualize.Geo.Delaunay.new/1` over the points. `output: :triangles` (the default) yields one row per triangle in construction order: `index`, `vertices` (the three point indices, counter-clockwise) and `path`, the closed triangle; `output: :hull` one row, `path`, the closed hull (an empty path for fewer than three points).
- `:voronoi` — `Visualize.Geo.Voronoi.new/1` over the points, bounded by `[0, 0, width, height]`. `output: :cells` (the default) yields one row per point in input order: the datum's columns plus `index` and `path`, the closed clipped cell (`Visualize.Geo.Voronoi.cell/2`; an empty path for a site without a cell); `output: :edges` one row per finite edge: `x0`, `y0`, `x1`, `y1` and `path`.
- `:contour` — `field` required, read from every row in row-major order over the grid `size: [columns, rows]` (required); `thresholds` (`10`). `Visualize.Contour.compute/2` with smoothing on; one row per ring — a polygon of a threshold's `MultiPolygon` — in threshold order: `value` and `path`, the ring closed with `Z`, its grid coordinates scaled so that the grid's `columns − 1` by `rows − 1` cells span the plot area.
- `:density` — `field` (the weight, `1` when absent), `size` (default the plot area), `bandwidth` (`20`), `thresholds` (`20`); the cell size is `4`. `Visualize.Contour.Density.compute/2`; one row per ring in threshold order, `value` and `path`, the ring closed, in pixels.

### 5.5 Inline label

**Implemented.** A `:mark_label` node labels the mark from its own data: `text` (`:text`, `:content`, required), `anchor` (`{:enum, [:top, :bottom, :left, :right, :start, :middle, :end]}`, `:geometry`, `:top`), `style` (`{:ref, :style}`, `:style`, `:label`), `dx` and `dy` (`:number`, `:geometry`, `0`); every key `:override`. A `{:field, f}` in its text reads the datum through `Visualize.Data.Table.get/2` — `to_string/1` of the value, nothing for `nil` — which is how a rule labels itself with the deploy's `sha`.

`Visualize.Chart.Mark.generate/3` draws the label as one `text` element per datum — per series for a `:line` or an `:area`, at its last point — in the label's `style` with `class="mark-label"`, `dx` and `dy` added. Each mark type has an *anchor point* `(px, py)`: the datum's position for a `:symbol`, a `:circle` and the end of a `:line` or an `:area`; the centre of the rectangle for a `:rect` and a `:band`; `Visualize.Shape.Arc.centroid/2` about the plot centre for an `:arc` — over the pie's angles, or the datum's own `start` and `end` — and a `:rose`; the first point of the path for a `:path`. The anchor names where the text sits:

| Anchor | Position | `text_anchor` |
|---|---|---|
| `:top` | `(px, py − 4)` | `:middle` |
| `:bottom` | `(px, py + 4)`, `dy: "0.71em"` | `:middle` |
| `:left` | `(px − 4, py)`, `dy: "0.32em"` | `:end` |
| `:right` | `(px + 4, py)`, `dy: "0.32em"` | `:start` |
| `:start`, `:middle`, `:end` | `(px, py)`, `dy: "0.32em"` | as named |

A `:rule` and an `:x_band` label themselves through their generator's own `label/2` — to the right of the upper end, spec/04 §12.2 — so the annotation is byte for byte the one the generator draws; `anchor`, `dx` and `dy` are not read by those two types, and the label's `style` reaches the generator's text. A `text_anchor` in the label's style replaces the anchor's own.

### 5.6 Rendering

**Implemented.** `Visualize.Chart.Mark.generate/3` is one mark as one `Visualize.IR.Element` group in the plot area's coordinates, its rows those of `Visualize.Chart.Mark.rows/3` (the bound source through the pipeline of §5.4; `[]` when the source is not bound, so a mark renders empty rather than raising), its channels mapped as §5.2 says through `Visualize.Chart.Frame.scales/1`, its style resolved as §3.4 says in the `:resolve` mode:

```
group  style: %{class: "mark mark-<type>[ <class>]", …the resolved style}
├── <element>   one per datum, or one per series for a :line and an :area (§5.2)
└── text  style: %{class: "mark-label", …}                                — the inline label (§5.5)
```

The elements are the generators' own, so a mark is byte for byte the direct call with the same numbers (D-61):

| Type | Elements |
|---|---|
| `:line` | one `path` per series: `Visualize.Shape.Line.generate_path/2` in the style's `curve` and `curve_opts` |
| `:area` | one `path` per series: `Visualize.Shape.Area.generate_path/2`, `x0`/`x1` and `y0`/`y1` when given, else `x` and `y` with the baseline `y0` at the `y` scale's zero |
| `:band` | `Visualize.Shape.Band.generate/2`: one `rect` per datum at `y` (`0` when absent), `height` tall |
| `:rule` | `Visualize.Shape.Rule.generate/2`: one `group` per datum from `0` to the plot height |
| `:x_band` | `Visualize.Shape.XBand.generate/2`: one `group` per datum from `0` to the plot height |
| `:percentile_band` | `Visualize.Shape.PercentileBand.generate_path/2`: the `outer` and `inner` paths (`class="outer"`, `"inner"`, filled in the mark's paint at `fill_opacity` `0.2` and `0.4`, no stroke) then the `median` (`class="median"`, stroked in the paint, no fill); a band whose channels are absent is not drawn |
| `:rose` | `Visualize.Shape.Rose.generate_path/2`: one `path` per datum about the plot centre, the angle scale as its `scale/2` |
| `:symbol` | one `path` per datum, `Visualize.Shape.Symbol.generate_path/2` in the style's `symbol` (`:circle`) and `symbol_size` (`64`), or `value`, translated to the datum |
| `:arc` | `Visualize.Shape.Pie.generate/2` over the values with the angle options, then one `path` per datum, `Visualize.Shape.Arc.generate_path/2` with the radii, about the plot centre; with `start` and `end`, no pie — one `path` per datum placed on both, `Visualize.Shape.Arc.generate_path/2` with the datum's angles and radii and the `pad_angle` and `corner_radius` options, byte for byte the direct call (D-69) |
| `:path` | one `path` per datum: the row's `Visualize.IR.Path` as it is |
| `:rect` | one `rect` per datum: `x = min(x0, x1)`, `width = |x1 − x0|`, likewise `y` and `height`; `rx` and `ry` when `corner_radius` is positive |
| `:circle` | one `circle` per datum at `(x, y)` with `r` the `value` or `radius` |

A mark's *paint* is the colour its elements are drawn in: the style's `fill` for a filled type (`area`, `band`, `x_band`, `rose`, `symbol`, `arc`, `path`, `rect`, `circle`, the bands of a `percentile_band`) and its `stroke` for a stroked one (`line`, `rule`, the median of a `percentile_band`). When the style gives no value for that key, the paint is the theme's `{:series, i}` for the mark's one-based position among the design's marks (§3.3), set on the group as that key, and a `:line` also takes `fill: :none`. The generators of a `:rule` and an `:x_band` draw in `current_color` and the brush's fill, which a group's style does not reach, so the stroke keys of the resolved style and the paint are set on the rule's line and the fill keys and the paint on the x-band's rectangle. With a `series` channel each series' element takes the frame's `color` scale's value for its series value when the frame declares one — a slot atom resolved through `Visualize.Theme.resolve/3`, exactly as the legend does — and `{:series, j}` for its position among the series otherwise. A `:rect`'s `value` reaches the colour scale the same way, as the element's `fill`. A `{:field, f}` on any style key is bound per element (§3.4). Every slot resolves in the `:resolve` mode, so the SVG carries `var(--vis-series-1, #3b6fa8)` and a canvas the literal; on a canvas the same tree renders through `Visualize.Backend.Canvas` with literal paints, an inline label as `fillText`, and nothing for a text on the binary stream (spec/09 §4).

The group is returned untranslated. `Visualize.Chart.Frame.generate/2` places every mark of the design after the grid, inside the group the margins translate — inside the centred group of a `:polar` frame, inside each panel of a `:facet` frame from the rows whose `by` is the panel's value — when it is given `sources:`, and draws the furniture alone without them (§4.7). A `:rose` and an `:arc` mark are about the plot centre in every kind, so `generate/3` translates their group there in a frame that is not polar. A `%Visualize.Chart.Var{}` reached while drawing raises `ArgumentError` naming it, as the frame does.

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

**Implemented.** `Visualize.Chart.var/1` builds `%Visualize.Chart.Var{name: name}`, a term allowed wherever a value can appear — a style value, a text part, a channel, a whole node (`style: var(:style)`, `margin: var(:margin)`). The term carries only the name; the default is declared once under `vars` (§2.4), so two fragments cannot disagree about it (D-59). The validator requires every variable used to be declared (`{:undeclared, :var, name}`) and does not type the value, which is unknown until application: the value is typed by the validator at the path where the variable stood, once `Visualize.Chart.apply/2` has put it there (§7.3).

### 7.2 Sources as slots

**Implemented.** A source declaration is a slot: the fields the design reads are the contract, and binding maps slot to source at application — "made for `{a, b, c}` but showing `{d, e, f}`" is one rebinding, `Visualize.Chart.apply/2` with another `sources:` map. Application takes a *pool* of named sources; a slot binds to the pool's entry under its own name, else under its `default`, and a slot with neither is unbound (§7.3). A dashboard picker validates a candidate source against `fields` before offering it, by the rule application applies: every declared field is a key of some row of the source, in either spelling (D-52).

### 7.3 Application

**Implemented** (work item 5 of #53, D-65). `Visualize.Chart.apply/2` takes a design — a `%Visualize.Chart{}`, or a design map that goes through `Visualize.Chart.from_map/1` first, so an invalid map is its errors — and the options `sources:` (the pool, a map from name to source, `%{}`), `vars:` (a map from variable name to value, `%{}`) and `theme:` (a `%Visualize.Theme{}`, as `Visualize.Chart.Frame.new/2` takes it), and returns `{:ok, applied}` or `{:error, errors}` — the errors of §10.1 by path, ordered by path — in three steps. Each step reports every fault it finds and a step with faults stops before the next, so resolution faults are never mixed with binding faults, nor either with the validator's.

1. **Variables resolve.** Every `%Visualize.Chart.Var{}` in the design — a value, a text part, a whole node — is replaced by the value `vars:` gives its name, else by the declared `default` (§2.4); a variable with neither is `{:unresolved, :var, name}` at the path of its use, and every use is reported. A name in `vars:` that no declaration carries is `{:undeclared, :var, name}` at `[:vars, name]`. In a text a resolved part that is a number or an atom is written with `to_string/1`, so `["n = ", var(:n)]` with `n: 3` reads `["n = ", "3"]`; every other value stands as it is, where the validator types it. The `vars` declarations are dropped: the concrete chart has none and no variable anywhere in it, which is what `Visualize.Chart.Frame.new/2` requires (§4.7).
2. **Slots bind.** Each slot of `sources` (§2.3) binds to the pool's entry under its own name, else under its `default`; a slot with neither is `{:unbound, :source, name}` at `[:sources, name]`. Pool entries that no slot names are ignored, so one pool serves many designs. A bound source is anything `Visualize.Data.Table.rows/1` reads and is kept as given — the frame reads it through `rows/1` as it does any source, and a rank-1 `Nx` tensor stays a tensor for the dense path (D-52). Every field the slot declares MUST be a key of some row of the bound source, in either spelling; a field no row carries is `{:missing_field, field}` at `[:sources, name]`, one error per field, which is the "made for `{a, b, c}`" contract failing loudly (§7.2). A source with no rows binds without a check. A field a channel, a text or a transform reads is checked against the slot's declaration by the validator (§5.4), so a field the design reads and the source lacks is caught at one or the other.
3. **The result validates and its frame is realised.** `Visualize.Chart.Validator.validate/1` runs over the resolved, bound design — the value a variable took is typed here, at the path where it stood — and `Visualize.Chart.Frame.new/2` builds the frame over the bound sources, inferring every `:auto` domain from the bound columns (§4.3). A value a scale cannot take, or a theme name `theme:` does not resolve, raises `ArgumentError` from the frame as it does for any chart: those are faults of the data or the consumer, not of the binding.

The result is a `%Visualize.Chart.Applied{}` (§14.10): `chart`, the concrete `%Visualize.Chart{}` — no variable anywhere in it, `vars` empty, the slot declarations kept as the data contract, everything else as the design wrote it; `sources`, the bound sources by slot name; and `frame`, the realised frame, whose `Visualize.Chart.Frame.scales/1` is the escape hatch. `Visualize.Chart.render/2` draws it: `Visualize.Chart.Frame.render/2` of the frame over the bound sources, with the same options. The design, its fragments and a binding are storable; the applied chart holds data and is not — it has no map form and no JSON form.

## 8. Composition

**Implemented** (work item 5 of #53, D-65). `Visualize.Chart.compose/2` merges two fragments — design maps, or `%Visualize.Chart{}`s taken as their maps — into one map by the merge rule of every key (§1.5), the second over the first, and returns `{:ok, map}` or `{:error, errors}`; `Visualize.Chart.compose/1` folds a list left to right, so `compose([a, b, c])` is `compose(b, c)` over `compose(a, b)`, and `compose([])` is `{:ok, %{}}`. A fragment is any map with the design's keys: it need not carry `version` or `frame`, and nothing is validated or defaulted — the result is a fragment too, and becomes a chart through `Visualize.Chart.from_map/1` or `Visualize.Chart.apply/2`, which is where it MUST validate.

For each key present in either fragment, by the key's spec in the node kind being merged:

- `:concat` — the later fragment's elements after the earlier's: `marks`, `labels`, `axes`, `transforms`. Elements are never merged with each other.
- `:union` — the union of the two name-keyed maps: `sources`, `vars`, `styles`, `scales`. A name in both with equal values is taken once; with different values it is `:conflict` at the name's path (`[:styles, :series]`, `[:frame, :scales, :x]`), every conflict reported. A house style sheet composes with a chart's own styles and disagrees loudly, never silently.
- `:override` — the later fragment's value, except that a key whose type is a node — `{:node, kind}`, or a `{:one_of, …}` that admits one, such as `theme` — given as a map by both fragments composes key by key under that kind's rules: `frame` merges, its `scales` union, its `axes` concatenate, its `size` is the later's; `meta` merges likewise. A key the schema does not know is `:override`.

A key present in one fragment alone is taken as it is. Over a list, `:concat` and `:union` keys compose associatively and `:override` keys last-wins, so the order of the fragments is the order of their marks and labels and the precedence of their scalars: a standard label set, a house style sheet and a chart-specific fragment compose in that order into one design.

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
| `{:unresolved, :var, name}` | a variable used here with no value at application and no default (§7.3) |
| `{:unbound, :source, name}` | a slot with no source in the pool under its name or its default (§7.3) |
| `{:missing_field, field}` | the bound source has no row carrying a field the slot declares (§7.3) |
| `:conflict` | a `:union` key declared with different values by two fragments (§8) |

The last four are reported by `Visualize.Chart.apply/2` and `Visualize.Chart.compose/2` in the same shape, so one reader serves every error of the layer. `Visualize.Chart.Validator.format/1` renders one error as a line a person reads, `marks[1].channels.y: field :temp is not declared by the mark's source`, `sources.primary: has no field :v`.

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

### 12.1 The compiled chart

**Implemented** (work item 6 of #53, D-66). `Visualize.Chart.compile/2` compiles a design the way HEEx compiles a template: the design is validated once, the theme and the styles are resolved, everything data-independent is drawn once, and the result is a `%Visualize.Chart.Compiled{}` with one closure per dynamic region taking the realised frame and the bound sources. Rendering a compiled chart per tick pays no validation and no static drawing.

`compile/2` takes a `%Visualize.Chart.Applied{}` (§7.3), or a `%Visualize.Chart{}` or a design map, which go through `Visualize.Chart.apply/2` first with the same `sources:`, `vars:` and `theme:` options — so a compiled chart is always compiled *over a binding*, the one the render targets are chosen from (§12.3) — and returns `{:ok, compiled}` or the `{:error, errors}` of application. Its one option of its own is `ceiling:`, the point-count ceiling of §12.3, a positive integer, `1000` by default. The struct holds `chart`, the concrete `%Visualize.Chart{}`; `theme`, its `%Visualize.Theme{}`; `sources`, the sources it was last drawn over, by slot name; `regions`, every region of §12.2 in the frame's drawing order, each static with its element drawn once or dynamic with its closure and its reason; `targets`, the target and the bound point count of every mark in design order (§12.3); `ceiling`; `static`, the static SVG string of §12.4, rendered once; `plot`, `margin` and `size` as the frame gives them; and `viewport`, `nil` or the window state of §12.5. A compiled chart is a value: recompile on a design change, not on a data change; one compiled chart serves every tick of one binding, and a slot rebound to another source is another compilation. It holds closures and data, so it has no map or JSON form, as the applied chart has none (§14.10); a macro or sigil that runs the compiler on a literal design at compile time is not built here and would need a data form of the regions.

### 12.2 Regions: the static/dynamic split

**Implemented.** The split is computed from the design, never assumed. The frame's drawing order (§4.7) is a list of *regions*, and each region is static — drawn once at compilation, byte for byte the same on every tick — or dynamic, drawn per tick by its closure:

| Region | What it holds | Static when |
|---|---|---|
| `:grid` | the grid group of every axis with `grid: true` (§4.4; the polar grid in a `:polar` frame) | every axis that draws grid lines names a fixed scale |
| `{:grid, :outer}` | in a `:polar` frame, the cartesian grid of an axis on a scale other than `angle` and `r` (§4.6) | as `:grid` |
| `{:mark, i}` | the i-th mark, zero-based | never: a mark is the data |
| `{:axis, i}` | the i-th axis, zero-based | its scale is fixed |
| `:legend` | the legend (§4.5) | its scale is fixed |
| `:labels` | every frame label (§6) | no `{:data, [x, y]}` anchor reads a moving position scale |
| `:panels` | the panels of a `:facet` frame, grid, marks, axes and titles (§4.6) | never: the panel set is the distinct values of the data |

A scale is *fixed* when its `domain` is an extent with no `:auto` in it and it is not the frame's viewport scale (§12.5); it *moves* when its domain is inferred (`:auto`, or `:auto` at one end, §4.3) or windowed. The order of the regions is the order the frame draws in: `:grid`, the marks, the axes, `:legend`, `:labels` in a `:cartesian` or a `:geo` frame; in a `:polar` frame the grid, the marks and the axes on `angle` and `r` sit in the centred group and the outer grid and an axis on another scale follow it (§4.6); a `:facet` frame is `:panels`, `:legend`, `:labels`. A region that would hold nothing — a grid no axis asks for, a legend or labels the design has none of — is not listed. `Visualize.Chart.Compiled.regions/1` reports every region as `{region, :static}` or `{region, {:dynamic, reason}}`, and `Visualize.Chart.Compiled.dynamic_regions/1` the dynamic ones alone as `{region, reason}`. The reason is `:data` for a mark, `:facet` for the panels, and `{:inferred, names}` for a region that reads moving scales — the names of those scales, sorted — so an author reading `{:grid, {:inferred, [:y]}}` and `{{:axis, 1}, {:inferred, [:y]}}` sees exactly which domain to fix to make the diff smaller.

A static region is drawn at compilation in the `:css` mode from the frame the chart was compiled over; since it reads no moving scale, the frame of any tick draws it the same. A dynamic region's closure takes the frame realised over the tick's sources — `Visualize.Chart.Frame.new/2` runs per tick, which is where the moving domains are inferred — and draws the region as §4 and §5 do: a mark through `Visualize.Chart.Mark.generate/3` at its position, an axis and the grid through the frame's furniture, the legend and the labels likewise. The static elements are cached on the struct as `Visualize.IR.Element`s, and `test/visualize/chart/compiled_test.exs` holds the static bytes identical across data changes and the assembled output of §12.4 equal to `Visualize.Chart.Frame.render/2` for every design under `test/support/designs/`.

### 12.3 The render target

**Implemented.** The render target is a compiler decision per mark, never a design property beyond the `render` override (§5.1). For each mark, in design order: `render: :svg`, `:canvas` or `:binary` is taken as given; `:auto` (the default) counts the rows the mark draws over the bound sources — `Visualize.Chart.Mark.rows/3`, the points of a path mark, the elements of a per-datum one — and picks `:svg` when the count is at most the ceiling, else `:binary` when `Visualize.Backend.CanvasBinary.available?/0` (Nx is loaded) and `:canvas` otherwise. The ceiling is the `ceiling:` option of `compile/2`, `1000` by default: the ~1,000 DOM-node ceiling of [00-prior-art](00-prior-art.md) §3.2. Rebinding a slot to a denser source and recompiling moves a mark from SVG to canvas without touching the design. `Visualize.Chart.Compiled.targets/1` reports `{target, points}` per mark, the target chosen and the count it was chosen from, so `[{:svg, 120}, {:binary, 5000}]` is a chart whose second mark went to the binary path.

Static furniture is always SVG. Layering is fixed — the canvas layer under the SVG layer, and mark order within each layer — and text stays in the SVG layer: a canvas-layer mark's inline label (§5.5) is drawn as SVG text in the mark's group, since the canvas has no text a stylesheet or a DOM hit can reach (spec/09 §4.4). The marks of a `:facet` frame are drawn per panel inside the `:panels` region and stay in the SVG layer whatever their count: their target is reported as `:svg`. One node of style resolves for both layers (§3.4): the SVG layer in `:css`, the canvas layer in `:literal`.

### 12.4 Rendering per tick: the hybrid chart map

**Implemented.** `Visualize.Chart.Compiled.render/2` takes the compiled chart and the sources by slot name — the map `Visualize.Chart.Applied` holds, anything `Visualize.Data.Table.rows/1` reads under each name; a slot the map omits draws nothing, and nothing is re-validated — realises the frame over them, runs every dynamic closure, and returns the chart map of `Visualize.Backend.Hybrid` (spec/09 §6) with one key added for the SVG layer's moving part:

| Key | Value |
|---|---|
| `width`, `height`, `margin` | the frame's size and margin |
| `static` | the static regions' elements, in region order — the same list on every tick; `Visualize.Backend.Hybrid.render_static/1` draws it once |
| `dynamic` | the canvas layer: one group per mark whose target is `:canvas` or `:binary`, in mark order, in `:literal` style with its text children removed, in the centred group of a `:polar` frame; `nil` when no mark targets the canvas |
| `dynamic_style` | `%{}`: every element carries its own resolved style |
| `canvas_format` | `:binary_base64` when any canvas-layer mark targets `:binary`, else `:json` — one canvas layer, one format |
| `dynamic_svg` | the SVG layer's dynamic regions, in region order: the `:svg` marks, the moving axes, grid, legend and labels, the facet's panels, and the inline labels of the canvas-layer marks |

`Visualize.Chart.Compiled.static/1` is the static SVG string, `Visualize.Backend.Hybrid.render_static/1` of the `static` list, rendered once at compilation and cached. `Visualize.Chart.Compiled.tick/3` is the per-tick payload: `{payload, compiled}` where `payload` is a map with `svg`, the `dynamic_svg` list rendered as one SVG root of the same shape as `static/1` — the consumer stacks the three layers, the canvas under the static SVG under the dynamic SVG, each positioned at the container's origin; `canvas`, `Visualize.Backend.Hybrid.render_dynamic/1` of the map, `""` when there is no canvas layer; `canvas_format`; `incremental`, the payload of §12.5 or `nil`; and `bytes`, the byte size of what a tick transmits — `svg` plus `canvas`, or `svg` plus the incremental payload's `binary` — which is what the measurement of §12.6 reads. The returned compiled chart holds the tick's sources and the window state; a design without a viewport returns it otherwise unchanged.

`Visualize.Chart.Compiled.svg/2` is the one-string form: the frame's group of §4.7 assembled from the cached static elements and the tick's dynamic ones in the frame's own order — the grid, the marks, the axes, the legend, the labels — rendered through `Visualize.Render.to_string/2` as SVG. When every mark targets `:svg` it is byte for byte `Visualize.Chart.Frame.render/2` over the same sources, which is how the split is held to the frame; a canvas-layer mark is absent from it, since it is the SVG layer.

### 12.5 The viewport: a streaming window

**Implemented.** A frame `viewport` (§4.6) — `scale`, a `{:ref, :scale}`, and `span`, a number in the scale's domain units, seconds for a `:time` scale — makes the compiled chart *stateful*: the named scale is windowed to `[hi − span, hi]` on every tick, where `hi` is the newest value the marks bind to it over the tick's sources — the greatest value of every channel naming the scale, as inference reads them (§4.3) — or the `now:` option of `tick/3`, which is how a clock, or a test's fake clock, drives the window. The windowed scale moves (§12.2): its axis and grid are dynamic regions. A mark that reads the windowed scale draws the rows whose reading lies within the window, so nothing is drawn beyond the plot area; the reading is the channel's field before the mark's transforms, and a mark whose channel is a transform's output draws every row its pipeline yields.

When the chart has a binary canvas layer (`canvas_format` `:binary_base64`, §12.4 — the incremental record of spec/09 §5.5 carries binary streams and nothing else; a `:json` layer is sent whole per tick), the window slides it through `Visualize.Incremental` (spec/09 §7), whose state the compiled chart holds between ticks: the first tick is the full-redraw payload of `Visualize.Incremental.initial_render/1`; each later tick scrolls by `dx = (hi − hi₀) × width / span` pixels, with `width` the plot's, through `Visualize.Incremental.scroll/2`, so the payload is the `canvas_incremental` event of spec/09 §7.3 — `"scroll_x"` with the exposed strip filled, `"full"` when the window jumped by half the plot or more, `"none"` when it did not move. The incremental canvas is the *plot area*: its size is `plot`, it sits at `(margin.left, margin.top)` of the container, and the marks are drawn in plot coordinates — the exposed strip is at the canvas's edge (spec/09 §5.3), and only a canvas whose right edge is the plot's right edge exposes the newest points there. The compiled chart draws the whole window into each exposed region, since a path mark needs its neighbour outside the region and the client clips to the region's bounds (spec/10 §9.2); the state's `data` is therefore empty and its accessors are never consulted. A scroll payload is consequently no smaller in bytes than a full redraw of one path mark — what it saves is the client's redraw of the pixels that only moved, and the whole-window draw is what keeps a path continuous across the strip's edge. The copy-and-shift holds only while every other scale the canvas marks read is fixed: with an inferred one the old pixels are wrong once the domain moves, so every tick is a full-redraw payload, and `dynamic_regions/1` names the scale to fix. The SVG layer of a viewport design is per-tick SVG as §12.4 says, its `:svg` marks windowed alike.

### 12.6 Measurement

**Implemented.** The claim of the split is a smaller payload per update, and it is measured, not asserted. The gallery's performance page (`examples/lib/examples_web/live/performance_live.ex`, `/performance`) has a *Compiled* mode over the line design of `ExamplesWeb.PerformanceLive.compiled_design/1` — a `:cartesian` frame with fixed `x` and `y` domains, both axes with a grid, a title, and one `:line` mark of the page's point count — streaming through `tick/3` with `render: :svg` and `render: :binary`. `ExamplesWeb.PerformanceLive.measure_compiled/1` runs the same updates headless: the old path is `Visualize.Chart.render/2` of the design applied to each update, one SVG string, and the compiled path is `static/1` once and the tick payload's `bytes` per update; both are summed over N updates and reported as bytes per update, with the static bytes beside them. The numbers for this item are recorded on issue #63.

## 13. Worked example

**Implemented** as a valid design that renders (`test/visualize/chart/example_test.exs` reads it from this section, round-trips it, applies it and draws it). Every construct of the layer appears once:

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
      count: %{kind: :linear, domain: [0, :auto], range: [0, 120]},
      color: %{kind: :ordinal, range: :category10}
    },
    axes: [
      %{scale: :x, side: :bottom, ticks: 6, format: "%H:%M"},
      %{scale: :y, side: :left, ticks: 5, grid: true},
      %{scale: :count, side: :top, ticks: 3}
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
      channels: %{x0: 0, x1: :count, y0: :x0, y1: :x1},
      scales: %{x: :count},
      style: :muted
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

Its application is `Visualize.Chart.apply(design, sources: %{primary: idle, deploys: deploys}, vars: %{unit: "mg/hr"})` (§7.3): the variables resolve, both slots bind and are checked, the design validates; bound to `%{gitlab_uptime: uptime, deploys: deploys}` instead, `primary` fills from its default. The third mark is the marginal histogram of `v`: its `:bin` yields one row per bin with the edges `x0`, `x1` and the `count`, and the mark draws the edges along the frame's own `y` — the scale `v` is drawn on, so the bins line up with the line — and the counts from `0` through `count`, the second linear scale its `scales` node names for `x` (§5.1), whose axis on `:top` spans the first 120 pixels of the plot (§4.3). Bins of a number cannot be placed on the `:time` scale `x`, which is why the mark names its own (D-67). It renders: `Visualize.Chart.render/2` draws the applied chart on SVG, with one group per mark, or on a canvas with `backend: :canvas`; `Visualize.Chart.compile/2` splits it into the static frame and the dynamic marks (§12), and `Visualize.Chart.Compiled.svg/2` is the same SVG. The frame alone renders without any application: `Visualize.Chart.Frame.new/1` of a design that uses no variable, then `Visualize.Chart.Frame.render/1` for the furniture over the unit domains.

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
| `Visualize.Chart.apply/1` | As `apply/2` with `[]` options: every variable takes its default and the pool is empty, so a slot with a default is unbound too — it applies a design that declares no source. |
| `Visualize.Chart.apply/2` | `apply(design, opts)`: `{:ok, %Visualize.Chart.Applied{}}` for a chart or a design map with the variables of `vars:` resolved, the slots bound from the pool of `sources:` and the frame realised with `theme:` (§7.3), else `{:error, errors}` by path — the map's own errors, the unresolved variables, the unbound slots and missing fields, or the validator's, whichever step fails first. Raises `ArgumentError` as `Visualize.Chart.Frame.new/2` does. |
| `Visualize.Chart.compose/1` | `compose(fragments)`: the fragments folded left to right through `compose/2`; `{:ok, %{}}` for `[]`. |
| `Visualize.Chart.compose/2` | `compose(a, b)`: `{:ok, map}`, the second fragment merged over the first by the merge rule of every key (§8), else `{:error, errors}` with `:conflict` at the path of every `:union` name the two declare differently. |
| `Visualize.Chart.compile/1` | As `compile/2` with `[]` options: an applied chart compiled as it is, or a design applied with no options first. |
| `Visualize.Chart.compile/2` | `compile(design, opts)`: `{:ok, %Visualize.Chart.Compiled{}}` for an applied chart, or for a chart or a design map applied first with `sources:`, `vars:` and `theme:` as `apply/2` takes them (§12.1), with `ceiling:` the point-count ceiling of §12.3 (`1000`); else the `{:error, errors}` of application. Raises `ArgumentError` as `apply/2` does, and for a `ceiling:` that is not a positive integer. |
| `Visualize.Chart.render/1` | As `render/2` with `[]` options. |
| `Visualize.Chart.render/2` | `render(applied, opts)`: `Visualize.Chart.Frame.render/2` of the applied chart's frame over its bound sources — `backend:` and `resolve:` as that function takes them, `sources:` supplied by the applied chart. |

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
| `Visualize.Chart.Schema.transform_keys/1` | `%{required: [...], optional: [...]}` for a transform op (§5.4). |
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
| `Visualize.Chart.Frame.generate/2` | The `Visualize.IR.Element` group of §4.7: the static furniture, and every mark of the design between the grid and the axes when `sources:` is given, theme slots resolved in the `:resolve` mode. |
| `Visualize.Chart.Frame.render/1` | As `render/2` with `[]` options. |
| `Visualize.Chart.Frame.render/2` | `generate/2` rendered through `Visualize.Render.to_string/2`; `sources:` as `generate/2` takes it, `:resolve` defaulting to `Visualize.Theme.mode/1` of the `:backend`. |

### 14.6 `Visualize.Chart.Mark`

**Implemented.** The marks of §5.

| Function | Contract |
|---|---|
| `Visualize.Chart.Mark.generate/2` | As `generate/3` with `[]` options: no source bound, an empty mark group. |
| `Visualize.Chart.Mark.generate/3` | `generate(frame, mark, opts)`: the `Visualize.IR.Element` group of §5.6 for one mark node, its rows from `sources:` (as `Visualize.Chart.Frame.new/2` takes them) through the mark's pipeline, its channels through the frame's scales, its style in the `resolve:` mode (`:css`); `index:` is the mark's one-based position for its paint, defaulting to its position among the frame's marks (`1` when it is not one of them), and `panel:` restricts the rows to the facet value. Raises `ArgumentError` for an unresolved variable, a `:path` row without a `Visualize.IR.Path`, or a pipeline step it cannot run (§5.4). |
| `Visualize.Chart.Mark.rows/3` | `rows(frame, mark, sources)`: the rows the mark draws — its source's rows through its transforms with the frame's plot area and projection — or `[]` when the source is not bound. |

### 14.7 `Visualize.Chart.Transform`

**Implemented.** The data pipeline of §5.4.

| Function | Contract |
|---|---|
| `Visualize.Chart.Transform.apply/2` | As `apply/3` with `[]` options: `size: [1, 1]`, no projection. |
| `Visualize.Chart.Transform.apply/3` | `apply(transforms, rows, opts)`: the rows after every `:transform` node in order; `size:` is the `[width, height]` the layouts and the geo algorithms default to, `projection:` the `%Visualize.Geo.Projection{}` a `:projection` step maps through. Raises `ArgumentError` for an op that is not one of §5.4, a key an op requires and the node lacks, or a `:projection` step without a projection. |
| `Visualize.Chart.Transform.step/3` | `step(transform, rows, opts)`: one step of `apply/3`. |

### 14.8 `Visualize.Chart.Style`

**Implemented.** The style resolution of §3.4.

| Function | Contract |
|---|---|
| `Visualize.Chart.Style.resolve/3` | `resolve(node, theme, mode)`: the element style map of a style node — the fourteen element keys, every slot resolved through `Visualize.Theme.resolve/3` in `mode`, a dash-array list joined, a `{:field, f}` kept for `bind/4`. Raises `ArgumentError` for a variable. |
| `Visualize.Chart.Style.bind/4` | `bind(style, datum, frame, mode)`: the map of `resolve/3` with every `{:field, f}` read from the datum; a colour key's reading passes through the frame's `color` scale when it declares one and resolves as a slot when it is one; a `nil` reading drops the key. |

### 14.9 `Visualize.Chart.Presets`

**Implemented.** The ten components of [10-liveview-integration](10-liveview-integration.md) as designs (§15). Every preset function takes the component's assigns — a map with the keys of the component's table in spec/10, an absent key taking the default that table gives — and returns a design map that validates and round-trips (§14.1); no function reaches the map.

| Function | Contract |
|---|---|
| `Visualize.Chart.Presets.names/0` | The ten preset names in the order of spec/10 §2.1 and §3.1: `[:line_chart, :bar_chart, :horizontal_bar_chart, :pie_chart, :scatter_plot, :area_chart, :stacked_bar_chart, :tree_diagram, :treemap_chart, :sunburst_chart]`. |
| `Visualize.Chart.Presets.defaults/1` | `defaults(name)`: the assigns the component's table defaults, as a map — the one place the numbers live; the component's `attr/3` declarations read them. |
| `Visualize.Chart.Presets.design/2` | `design(name, assigns)`: the design of the named preset — the function below of that name. `ArgumentError` for a name not in `names/0`. |
| `Visualize.Chart.Presets.sources/2` | `sources(name, assigns)`: the assign mapping of §15.2 — `%{data: rows}`, the rows the design's one source binds to, the accessor assigns applied to each row of `data` (§15.2), or the nested map flattened to node rows for a hierarchy (§15.4). |
| `Visualize.Chart.Presets.line_chart/1` | The design of §15.3 for spec/10 §2.2. |
| `Visualize.Chart.Presets.bar_chart/1` | The design of §15.3 for spec/10 §2.3. |
| `Visualize.Chart.Presets.horizontal_bar_chart/1` | The design of §15.3 for spec/10 §2.4. |
| `Visualize.Chart.Presets.pie_chart/1` | The design of §15.3 for spec/10 §2.5. |
| `Visualize.Chart.Presets.scatter_plot/1` | The design of §15.3 for spec/10 §2.6. |
| `Visualize.Chart.Presets.area_chart/1` | The design of §15.3 for spec/10 §2.7. |
| `Visualize.Chart.Presets.stacked_bar_chart/1` | The design of §15.3 for spec/10 §2.8. |
| `Visualize.Chart.Presets.tree_diagram/1` | The design of §15.4 for spec/10 §3.2. |
| `Visualize.Chart.Presets.treemap_chart/1` | The design of §15.4 for spec/10 §3.3. |
| `Visualize.Chart.Presets.sunburst_chart/1` | The design of §15.4 for spec/10 §3.4. |

### 14.10 `Visualize.Chart.Applied`

**Implemented.** The applied chart of §7.3, a struct with no functions of its own: `chart`, the concrete `%Visualize.Chart{}`; `sources`, the bound sources by slot name, each as the pool gave it; `frame`, its `%Visualize.Chart.Frame{}` realised over them. `Visualize.Chart.apply/2` is its only constructor and `Visualize.Chart.render/2` its renderer; it has no map or JSON form, because it holds the data the design was applied to.

### 14.11 `Visualize.Chart.Compiled`

**Implemented.** The compiled chart of §12, a struct whose fields §12.1 lists; `Visualize.Chart.compile/2` is its only constructor.

| Function | Contract |
|---|---|
| `Visualize.Chart.Compiled.regions/1` | Every region of §12.2 in the frame's drawing order, each `{region, :static}` or `{region, {:dynamic, reason}}`. |
| `Visualize.Chart.Compiled.dynamic_regions/1` | The dynamic regions alone, `{region, reason}` with the reason `:data`, `:facet` or `{:inferred, names}` (§12.2). |
| `Visualize.Chart.Compiled.targets/1` | `{target, points}` per mark in design order: the target of §12.3 and the bound row count it was chosen from. |
| `Visualize.Chart.Compiled.static/1` | The static SVG string: `Visualize.Backend.Hybrid.render_static/1` of the static regions, rendered once at compilation (§12.4). |
| `Visualize.Chart.Compiled.render/2` | `render(compiled, sources)`: the hybrid chart map of §12.4 over the sources by slot name — `static`, `dynamic`, `dynamic_style`, `canvas_format`, `dynamic_svg`, `width`, `height`, `margin`. Raises `ArgumentError` as `Visualize.Chart.Frame.new/2` does for a value a scale cannot take. |
| `Visualize.Chart.Compiled.svg/2` | `svg(compiled, sources)`: the one-string form of §12.4, the frame's group with the static and the dynamic regions in the frame's order; equal to `Visualize.Chart.Frame.render/2` when every mark targets `:svg`. |
| `Visualize.Chart.Compiled.tick/2` | As `tick/3` with `[]` options: the window's `hi` is the newest bound value. |
| `Visualize.Chart.Compiled.tick/3` | `tick(compiled, sources, opts)`: `{payload, compiled}` — the per-tick payload of §12.4 (`svg`, `canvas`, `canvas_format`, `incremental`, `bytes`) and the compiled chart holding the tick's sources and, for a viewport design, the window state of §12.5; `now:` fixes the window's upper end. |

## 15. Presets

### 15.1 A component is a preset design plus an assign mapping

**Implemented** (work item 4 of #53, D-64). Each of the ten function components of [10-liveview-integration](10-liveview-integration.md) §2–3 is a *preset*: a function in `Visualize.Chart.Presets` from the component's assigns to a design map of this document, and an *assign mapping* that turns the component's `data` and accessor assigns into the rows the design's one source binds to. The component itself is what is left: it calls the preset, builds the frame with `Visualize.Chart.Frame.new/2` over the mapped source, draws it with `Visualize.Chart.Frame.generate/2`, and lays the elements the layer returns into the markup spec/10 declares. Three things follow:

- **The markup contract of spec/10 is unchanged.** The `<svg>` and its attributes, the `<title>` and `<desc>`, the `<g transform="translate(left, top)">`, the `<g class="x-axis">` and `<g class="y-axis">` wrappers, the attribute order of every mark element, `class` on the `<svg>` and the `animate` transition on every mark are the component's shell, drawn by its HEEx template as before; the ten render goldens of `test/support/components/` hold every component byte for byte to what it drew before it was a preset. A design rendered through `Visualize.Chart.Frame.render/2` carries the layer's own groups instead — `class="frame"`, `class="mark mark-<type>"`, `class="axis axis-<side>"`, marks under the axes (§4.7) — which is the one difference between a preset drawn by its component and the same design drawn by the layer.
- **Every number and every paint is the layer's.** The axes are the frame's (§4.4); a path's `d`, a rectangle's `x y width height`, a circle's `cx cy r`, an arc's `d` and its label's centroid, an axis title's position are read from the `Visualize.IR.Element`s of `generate/2`; a colour is the resolved style of the mark's group or, for a per-datum colour, the element's own (§3.4). The component keeps no scale, no generator call and no extent of its own.
- **A design is not a template.** The preset takes the assigns because two of the design's choices depend on them — the kind of the `x` scale of a line or an area chart is decided by the first datum, as spec/10 §2.2 says, and a hierarchy's colour domain is the count of the root's children — and because sizes, margins, colours and options are assigns. Everything else in the design is constant, and `Visualize.Chart.Presets.design/2` of the same assigns without `data` is the same design over the unit domains (§4.3).

The assign mapping puts the accessor assigns out of the design: a design carries no function (§1.1), so `x`, `y`, `value`, `label` and `size` are applied once, by `Visualize.Chart.Presets.sources/2`, and the design's channels name the resulting columns.

### 15.2 The assign mapping

**Implemented.** `Visualize.Chart.Presets.sources/2` returns `%{data: rows}` — the design's one source is named `data` — with `data` read through `Visualize.Data.Table.rows/1` first (D-53):

| Preset | Row |
|---|---|
| `line_chart`, `area_chart`, `bar_chart`, `horizontal_bar_chart` | `%{x: x.(d), y: y.(d)}` |
| `scatter_plot` | `%{x: x.(d), y: y.(d), r: size}` with `r` the `size` assign, or `size.(d)` when it is a function |
| `stacked_bar_chart` | `%{x: x.(d)}` plus every key of `keys` read from `d` through `Visualize.Data.Table.get/2` |
| `pie_chart` | `%{value: value.(d), index: i}` with `i` the datum's zero-based position, plus `label: label.(d)` when a `label` accessor is given |
| `tree_diagram`, `treemap_chart`, `sunburst_chart` | one row per node of the nested map in pre-order (§15.4): `id`, the node's dotted position (`"0"` the root, `"0.2.1"` the second child of the root's third child); `parent`, the parent's `id`, `nil` for the root; `label`, the `label` assign applied to the node's data (`:name` or `"name"` by default); `value`, the `value` assign applied to it (`:value` or `"value"` by default, missing → `0`) — every node, so an accessor that gives an internal node a value is honoured as `Visualize.Layout.Hierarchy.sum/2` honours it; and `branch`, the zero-based index of the root's child the node descends from, `nil` for the root |

The row map is the design's whole contract with the data, so a preset design binds to any source with those columns: a `line_chart` design rendered through `Visualize.Chart.Frame.render/2` over a `%{x: [...], y: [...]}` column map draws the same line the component draws.

### 15.3 The chart presets

**Implemented.** The seven presets of spec/10 §2 are drawn entirely by the layer: the frame's axes and labels, and one or two marks whose elements the component prints. Every one has `sources: %{data: %{fields: [...]}}` with the row's columns, `meta: %{name: title, description: [description]}` from the two accessibility assigns when given, `theme: :default` (the `theme` assign, a `%Visualize.Theme{}`, reaches `Visualize.Chart.Frame.new/2` as its `theme:` option, so the design names no theme of its own), a `:cartesian` frame of the component's `width` × `height` with its `margin` merged over the component's default, and `axes: [%{scale: :x, side: :bottom}, %{scale: :y, side: :left}]`. A colour assign left `nil` is the slot spec/10 names; given, it is the literal.

| Preset | Scales | Styles | Marks | Labels |
|---|---|---|---|---|
| `line_chart` | `x` by the first datum — `%{kind: :time}` for a `DateTime`, `NaiveDateTime` or `Date`, `%{kind: :linear}` for a number, `%{kind: :band, padding: 0.1}` otherwise and with no datum `:linear`; `y: %{kind: :linear}` | `line: %{stroke, stroke_width, curve}`; `point: %{fill: stroke}` | `%{type: :line, channels: %{x: :x, y: :y}, style: :line}`; with `show_points`, `%{type: :circle, channels: %{x: :x, y: :y}, options: %{radius: 4}, style: :point}` | `x_label` at `{:axis, :x}`, `y_label` at `{:axis, :y}`, when given |
| `bar_chart` | `x: %{kind: :band, padding: padding}`; `y: %{kind: :linear, domain: [0, :auto]}` | `bar: %{fill}` | `%{type: :rect, channels: %{x0: :x, x1: :x, y0: 0, y1: :y}, style: :bar}` | |
| `horizontal_bar_chart` | `x: %{kind: :linear, domain: [0, :auto]}`; `y: %{kind: :band, padding: padding, range: [0, plot height]}` — the range is fixed because `:auto` on `y` runs upward (§4.3) and the categories read downward | `bar: %{fill}` | `%{type: :rect, channels: %{x0: 0, x1: :x, y0: :y, y1: :y}, style: :bar}` | |
| `scatter_plot` | `x: %{kind: :linear}`; `y: %{kind: :linear}` | `point: %{fill, opacity: 0.7}` | `%{type: :circle, channels: %{x: :x, y: :y, value: :r}, style: :point}` | |
| `area_chart` | `x` as `line_chart`; `y: %{kind: :linear, domain: [0, :auto]}` | `area: %{fill, fill_opacity, curve}`; `line: %{stroke, stroke_width, curve}` | `%{type: :area, channels: %{x: :x, y: :y}, style: :area}`, then `%{type: :line, channels: %{x: :x, y: :y}, style: :line}` | |
| `stacked_bar_chart` | `x: %{kind: :band, padding: padding}`; `y: %{kind: :linear, domain: [0, :auto]}`; `color: %{kind: :ordinal, domain: keys, range: colors}` | `segment: %{fill: {:field, :key}}` | `%{type: :rect, data: %{source: :data, transforms: [%{op: :stack, fields: keys}]}, channels: %{x0: :x, x1: :x, y0: :y0, y1: :y1}, style: :segment}` | |
| `pie_chart` | `color: %{kind: :ordinal, range: colors}` over `index` | `slice: %{fill: {:field, :index}, stroke: :background, stroke_width: 2}`; `slice_label: %{fill: :background, font_size: :label_size}` | `%{type: :arc, channels: %{value: :value}, options: %{inner_radius, outer_radius, pad_angle}, style: :slice}` in a `:polar` frame with no margin; with `show_labels` and a `label` accessor, `label: %{text: [{:field, :label}], anchor: :middle, style: :slice_label}` | |

`colors` reaches the colour scale's `range` as it is — a scheme name or a colour list (§4.3) — and `Visualize.Scale.Ordinal.apply/2` cycles a short list as spec/10 §1.3 says; an unknown scheme or an empty list is the `ArgumentError` of spec/10 §1.3, raised by the frame. `outer_radius` of the pie is `min(width, height) / 2 − 10` when the assign is `nil`.

Where the layer's rule and the component's old arithmetic differed, the layer's rule now holds, and spec/10 §1.3 says so: a collapsed domain stays `[v, v]` and maps to the range midpoint (D-49, D-60) where the component widened it by one unit; a line or an area over a `:band` x scale sits at the band centres (§5.2) where the component drew it at the band starts; a `:band` domain is the distinct categories in order of first appearance (§4.3), so a repeated category is one band; a `[0, :auto]` domain over values whose maximum is not positive is `[0, max]`, not `[0, 1]`.

### 15.4 The hierarchy presets

**Implemented.** The three presets of spec/10 §3 are laid out by the layer and drawn by the component: their transforms yield the rows (`Visualize.Chart.Mark.rows/3`) and the component prints the markup spec/10 §3 declares from them, because that markup is not a mark of §5 — a tree node is a group of a circle and a text whose anchor and offset depend on the node, a treemap draws the leaves alone, a sunburst draws the nodes below the root with a positive extent and takes each arc's angles from its own row. Every one has the row of §15.2 as its source and `meta` and `theme` as §15.3; the treemap and the sunburst, which take `colors`, declare a `color` scale `%{kind: :ordinal, domain: [0, …, n − 1], range: colors}` with `n` the count of the root's children, which is what `branch` maps through (§3.4): the i-th child of the root takes the i-th colour and every descendant inherits it (D-46); the root, whose `branch` is `nil`, is the theme's `:grid`. The tree, whose nodes are one colour, declares no scale.

| Preset | Frame | Transform | Marks |
|---|---|---|---|
| `tree_diagram` | `:cartesian`, the component's margin | `%{op: :tree, id: :id, by: :parent, size: s}` with `s` the plot's `[height, width]` for `:horizontal` and `[width, height]` for `:vertical` (spec/10 §3.2) | `%{type: :path, channels: %{path: :path}, style: :link}` over the transform with `output: :links`, with `link: %{stroke: link_stroke, stroke_width: 1.5}`; `%{type: :circle, channels: %{x: :y, y: :x}` for `:horizontal`, `%{x: :x, y: :y}` for `:vertical`, `options: %{radius: node_radius}, style: :node}` over the transform with `output: :nodes`, with `node: %{fill: node_fill, stroke: node_stroke, stroke_width: 2}` — an internal node is filled `node_stroke` by the component (spec/10 §3.2) |
| `treemap_chart` | `:cartesian`, no margin | `%{op: :treemap, id: :id, by: :parent, field: :value, padding: padding, tile: tile}` | `%{type: :rect, channels: %{x0: :x0, x1: :x1, y0: :y0, y1: :y1}, style: :cell}` with `cell: %{fill: {:field, :branch}, stroke: :background, stroke_width: 1}` |
| `sunburst_chart` | `:polar`, no margin | `%{op: :partition, id: :id, by: :parent, field: :value, size: [2π, R]}` with `R = min(width, height) / 2` | `%{type: :arc, channels: %{value: :value, inner: :y0, outer: :y1}, style: :arc}` with `arc: %{fill: {:field, :branch}, stroke: :background, stroke_width: 1}` |

The component reads the rows of each mark, and draws: the tree's links from the `:links` rows' `x0 y0 x1 y1` as the cubic of spec/10 §3.2 — swapped for `:horizontal`, which is why the row's own `path`, the vertical link of §5.4.2, is not what it prints — and its nodes from the `:nodes` rows, a node whose `height` is `0` a leaf; the treemap's leaves; the sunburst's nodes of `depth ≥ 1` and positive `x1 − x0` through `Visualize.Shape.Arc` over `x0 x1 y0 y1`. A fill is `Visualize.Chart.Style.bind/4` of the mark's style over the row, so it is the colour scale's output resolved as §3.4 says. Rendered through `Visualize.Chart.Frame.render/2` instead, these three designs draw what their marks say — every node the transform yields, the tree's links vertical, the sunburst's angles from the pie over `value` — which is the layer's vocabulary as it stands; the three gaps it names (a row filter, per-datum angles on an `:arc`, an oriented link) are recorded as proposal #71, not closed here.
