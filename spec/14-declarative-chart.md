# Declarative chart layer

**Status:** Agreed

A chart is a nested map — a *design* — that names its data, its coordinate frame, its marks and its labels without a function anywhere in it, so that a design can be stored, diffed, shared, built by a tool and rendered against different data. This document is the contract for the whole layer: the map at every level with every key's type, facet, default and merge rule; the style grammar; sources as typed slots and variables as terms; version and migration; the validator and its error shape; the JSON form; and, as agreed prose, application, composition and compilation. Vega-Lite is the precedent for a stored design and its flat several-hundred-key specification is the warning: the map keeps the three-noun nesting of theme, style and frame (D-57).

Each section states what is implemented. The schema, the validator, the `Visualize.Chart` struct with its map and JSON round-trips, variables and version handling, the frame — its scales, inference, axes, grid, legend and labels, rendered as the static furniture — and the marks — every mark type drawn from the frame's scales by the existing generators, the transforms as steps of a mark's data pipeline, and the style grammar resolved to an SVG and a canvas output — and the presets — the ten LiveView components of [10-liveview-integration](10-liveview-integration.md) as stored designs plus an assign mapping (§15) — and application and composition — variables resolved and slots bound by `Visualize.Chart.apply/2` into an applied chart, fragments merged by `Visualize.Chart.compose/2` and layered by `Visualize.Chart.stack/1` under the schema's merge rules (§7.3, §8) — and compilation — the static/dynamic split computed from the design, a render target per mark from the bound data, the hybrid chart map per tick, the streaming window over the incremental path, and the payload measured (§12) — are **Implemented**. The builder — `Visualize.Chart.Build`, whose every function returns a fragment the composition of §8 folds into a design (§16) — is **Implemented**. The inspectors of a stack — `Visualize.Chart.explain/1`, the provenance of every leaf over the layers, and `Visualize.Chart.free_vars/1`, the variables a stack still demands (§17) — are **Implemented**.

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
| 2 | meta, sources, vars, theme, styles, defs, frame, marks, labels | `:meta`, `:source`, `:var`, `:theme`, `:style`, `:gradient`, `:frame`, `:mark`, `:label` |
| 3 | size, margin, scales, axes, legend, projection, facet, viewport; a mark's data, channels, scales, offset, options, inline label and tooltip; a style's curve options; a gradient's stops | `:size`, `:margin`, `:scale`, `:axis`, `:legend`, `:projection`, `:facet`, `:viewport`, `:data`, `:channels`, `:mark_scales`, `:mark_offset`, `:options`, `:mark_label`, `:tooltip`, `:curve_opts`, `:stop` |
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
| `:text` | a string with interpolation: `#{var(:name)}` stands for a variable and `#{field(:name)}` for a datum's field, a literal `#{` is `\#{` (§7.1); a list of parts — strings, variables and `:field_ref`s, the form an earlier draft wrote — is read and written back as the string (§9) |
| `:anchor` | `:title`, `:subtitle`, `:caption`; `{:axis, s}` with `s` a `{:ref, :scale}`; `{:frame, c}` with `c` one of `:top_left`, `:top_right`, `:bottom_left`, `:bottom_right`; or `{:data, [x, y]}` with `x` and `y` values in the domains of the frame's position scales (§6.3) |
| `:colour` | a colour string, `:none`, or a theme slot |
| `:size` | a number or a theme slot |
| `:font` | a string or a theme slot |
| `:slot` | a slot of the design's theme: `:series_k`, `{:series, i}`, `:axis`, `:grid`, `:text`, `:background`, `:font_family`, `:font_size`, `:label_size`, `:title_size` ([08-utilities](08-utilities.md) §7.1) |
| `:term` | any JSON-representable term: a number, string, boolean, `nil`, atom or `DateTime`, or a list or name-keyed map of those |

A `%Visualize.Chart.Var{}` (§7.1) is accepted wherever a value of any type is expected, including in place of a whole node; its value is typed at application.

**A struct is a leaf of every walk** (D-92). A variable stands *for* a value rather than being one, so no walk over the design map — composition and the cascade (§8), resolution (§7.3), validation (§10), the JSON codec (§11), the provenance and free-variable walks (§17) and the builder's node list (§18.5) — descends into a struct or merges one as a map, whatever type the schema gives the key it sits at. That a struct is also a map in Elixir is an implementation fact and never a licence to treat it as one: a walk MUST exclude it explicitly. Exactly two structs may appear in a design map — a `%Visualize.Chart.Var{}` and a `DateTime` — and both are values.

A field name is an atom in the map form even for a source whose columns are strings: `Visualize.Data.Table.get/2` reads either spelling (D-52), so `:v` reaches a column named `"v"` and the map never carries a string where a name belongs (D-57).

### 1.5 Merge rules

**Implemented** as data, applied by `Visualize.Chart.compose/2` and `Visualize.Chart.stack/2` (§8). Every key declares how two fragments combine under it; the Effect column is the union's, and the cascade's difference where two fragments collide is §8.2:

| Rule | Keys | Effect |
|---|---|---|
| `:concat` | every list of nodes: `marks`, `labels`, `axes`, `transforms` | the later fragment's elements follow the earlier's; the elements are never merged with each other |
| `:union` | every name-keyed declaration: `sources`, `vars`, `styles`, `scales` | the union of the two maps; a name declared with equal values in both is taken once, and declared differently in both is `:conflict` at the name's path. A key either fragment gives as a struct — a whole-node variable — is not a map of names and is not united: equal in both it is taken once, different it is `:conflict` at the *key's* path (§8.1) |
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
| `defs` | `{:map, {:node, :gradient}}` | `:style` | `%{}` | `:union` |
| `frame` | `{:node, :frame}` | `:geometry` | required | `:override` |
| `marks` | `{:list, {:node, :mark}}` | `:channel` | `[]` | `:concat` |
| `labels` | `{:list, {:node, :label}}` | `:content` | `[]` | `:concat` |

### 2.2 Meta

**Implemented.** `:meta` identifies the design; nothing renders from it except through a label that quotes it.

| Key | Type | Facet | Default | Merge |
|---|---|---|---|---|
| `name` | `:text` | `:content` | `nil` | `:override` |
| `description` | `:text` | `:content` | `""` | `:override` |

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

### 2.7 Defs

**Implemented** (#133). `defs` declares the design's **paints**: named `:gradient` nodes a `:colour` key refers to as `{:paint, name}` (§3.2). A gradient is written once in the words a person uses — a kind, its stops, an angle or a centre — and the SVG geometry is derived; `:union` merge, like `styles`, so a house sheet of gradients composes.

| Key | Type | Facet | Default | Notes |
|---|---|---|---|---|
| `kind` | `{:enum, [:linear, :radial]}` | `:style` | required | |
| `stops` | `{:list, {:node, :stop}}` | `:style` | required | at least two, in offset order |
| `angle` | `:number` | `:geometry` | `180` | linear: degrees clockwise from *up*, as CSS has it — `0` runs bottom to top, `90` left to right, `180` top to bottom; range `{0, 360, 15}` |
| `centre` | `{:list, :number}` | `:geometry` | `[0.5, 0.5]` | radial: `[cx, cy]` as fractions of the shape's box |
| `radius` | `:number` | `:geometry` | `0.5` | radial: as a fraction of the box; range `{0, 1, 0.05}` |

A `:stop` node is `offset` (`:number`, required, `0` to `1`), `colour` (`:colour`, required — a literal, a slot or a variable, resolved as any colour is), and `opacity` (`:size`, default `1`, range `{0, 1, 0.05}`); every key `:style` and `:override`.

A gradient's units are the shape's bounding box (`objectBoundingBox`), so one gradient fits any mark. From the angle θ a linear gradient's line runs from `(½ − ½ sin θ, ½ + ½ cos θ)` to `(½ + ½ sin θ, ½ − ½ cos θ)`; a radial one is centred at `centre` with `radius`, its focus at the centre. `Visualize.Chart.Frame.generate/2` emits one `defs` element **first** in the frame's group, before the grid, holding every gradient of the design as a `Visualize.IR.Element.linear_gradient/2` or `radial_gradient/2` with its stops, each under the id `vis-paint-<h>-<name>` where `<h>` is the lower-case base-36 `:erlang.phash2/1` of the design's `defs`, so two charts on one page collide only when their paints are the same; a design with no paints emits no `defs`. The same `defs` holds one **filter** per `{effect, radius}` pair any style in the tree uses (§3.1): `<filter id="vis-effect-shadow-3">` with a `feDropShadow` of `dx`, `dy` and `stdDeviation` the radius (`flood-opacity` 0.35), or `<filter id="vis-effect-blur-3">` with a `feGaussianBlur` of `stdDeviation` the radius; a design whose styles use no effect declares none. The defs are static furniture (§12.2): they never change with the data.

## 3. The style grammar

### 3.1 Keys

**Implemented.** A `:style` node has twenty-nine keys, every one `:style` and `:override`, every one optional with no default: an absent key is decided by the theme and the mark at compilation (§12), never by the schema. The keys are read as a drawing tool shows a style — in **groups**: what a style derives from first, then its *fill*, its *stroke*, its *font*, the *position* of its text, its *effects*, and last the keys that belong to no group. A key's group is data on its spec (`group`, §14.2), and the table below is in group order, which is the order the form shows them in (§18.7).

| Key | Type | Group | Notes |
|---|---|---|---|
| `extends` | `{:ref, :style}` | — | the style this one derives from (§3.5) |
| `fill` | `:colour` | `:fill` | |
| `fill_opacity` | `:size` | `:fill` | |
| `stroke_style` | `{:enum, [:single, :double, :inside, :outside]}` | `:stroke` | how the stroke sits on the edge (§5.6); `:single` when absent |
| `stroke_width` | `:size` | `:stroke` | user units |
| `stroke` | `:colour` | `:stroke` | |
| `stroke_opacity` | `:size` | `:stroke` | |
| `stroke_dasharray` | `{:one_of, [:string, {:list, :number}]}` | `:stroke` | |
| `stroke_linejoin` | `{:enum, [:miter, :round, :bevel]}` | `:stroke` | |
| `stroke_linecap` | `{:enum, [:butt, :round, :square]}` | `:stroke` | |
| `font_family` | `:font` | `:font` | |
| `font_size` | `:size` | `:font` | |
| `font_weight` | `{:one_of, [:integer, {:enum, [:light, :normal, :medium, :bold]}]}` | `:font` | a word is 300, 400, 500 or 700 |
| `font_style` | `{:enum, [:normal, :italic]}` | `:font` | |
| `line_height` | `:number` | `:font` | the space between a text's lines as a factor of the font size (§7.1), `1.2` when absent; range `{0.8, 3, 0.1}` |
| `text_anchor` | `{:enum, [:start, :middle, :end]}` | `:position` | the horizontal alignment |
| `vertical_align` | `{:enum, [:top, :middle, :baseline, :bottom]}` | `:position` | where a text sits on its point (§6.3, §5.5); each placement's own when absent |
| `margin_x` | `:number` | `:position` | a gap from the anchor point, along the anchor's outward direction (§6.3, §5.5); `0` when absent; range `{0, 40, 1}` |
| `margin_y` | `:number` | `:position` | likewise, vertically |
| `text_angle` | `:number` | `:position` | a rotation in degrees about the anchor point, clockwise; `0` when absent; range `{-180, 180, 5}` |
| `opacity` | `:size` | `:effects` | `0` to `1` |
| `blend` | `{:enum, [:normal, :multiply, :screen, :overlay, :darken, :lighten]}` | `:effects` | how the mark composites with what is under it; `:normal` when absent |
| `effect` | `{:enum, [:none, :shadow, :blur]}` | `:effects` | `:none` when absent |
| `effect_radius` | `:size` | `:effects` | the shadow's or the blur's radius, `3` when absent; range `{0, 20, 0.5}` |
| `class` | `:string` | — | a CSS class added to the mark's element |
| `curve` | `{:enum, curve types}` | — | the types of [04-shapes-and-curves](04-shapes-and-curves.md) §5.1 |
| `curve_opts` | `{:node, :curve_opts}` | — | `tension` and `alpha`, both `:number`, `:style`, `:override` |
| `symbol` | `{:enum, symbol types}` | — | the types of [04-shapes-and-curves](04-shapes-and-curves.md) §9.2 |
| `symbol_size` | `:size` | — | area in square user units |

### 3.2 Values

**Implemented.** A style value is one of five things, and which of them a key accepts follows from its type:

- a **literal** of the key's type — `"#3b6fa8"`, `2`, `:step_after`;
- a **theme slot** (`:slot`) for the `:colour`, `:size` and `:font` keys — `:series_1`, `{:series, 3}`, `:axis`, `:font_size` — resolved through `Visualize.Theme.resolve/3` in the mode of the render target, so the SVG output carries `var(--vis-axis, #666666)` and a canvas the literal (D-55);
- a **variable** (§7.1) for any key;
- a **paint** `{:paint, name}` for a `:colour` key: a gradient the design declares under `defs` (§2.7). `Visualize.Chart.Style.resolve/3` passes it through untouched, as it does a binding, and the **frame** resolves it once its elements are drawn — `Visualize.Chart.Frame.generate/2` replaces every `{:paint, name}` in the tree's styles with `url(#vis-paint-<h>-<name>)` in `:css` and with the gradient's **first stop's colour**, resolved as a colour, in `:literal`, since a canvas gradient is a different object and the first stop keeps a canvas chart drawable and honest. The validator reports `{:undeclared, :paint, name}` for a name `defs` lacks.
- a **channel binding** `{:field, f}` for any key, which is how `Visualize.Shape.Band`'s per-datum fill is expressed: the value is read from the datum at render — per element for a mark that draws one element per datum, from the series' first datum for a mark that draws one path per series (§5.6) — and, for a `:colour` key, passed through the scale named `color` when the frame declares one (§3.4).

Eighteen keys reach the element the mark draws — the fifteen of §3.4, `line_height`, and, as one, `effect` with `effect_radius`, and `blend`; four more — `curve`, `curve_opts`, `symbol` and `symbol_size` — reach the mark's generator (§5.6) and never an element; five — `stroke_style` (§5.6), `vertical_align`, `margin_x`, `margin_y` and `text_angle` (§6.3) — are read by the placements from the style node and never reach an element as themselves; and `extends` reaches neither, being consumed by the lookup that flattens it (§3.5).

For an enumerated key an atom is the literal; for a `:colour`, `:size` or `:font` key an atom is a slot, and `:none` is the literal "no paint". The validator checks a slot against the theme's `Visualize.Theme.slots/1` when the theme is built-in or inline (§2.5) and reports `{:undeclared, :slot, name}` otherwise.

### 3.3 Built-in styles

**Implemented.** Four style names are always declared, derived from the theme's slots, and a `styles` entry of the same name replaces one whole: `:axis` (`stroke: :axis`, `fill: :text`, `font_family: :font_family`, `font_size: :font_size`), `:grid` (`stroke: :grid`), `:label` (`fill: :text`, `font_family: :font_family`, `font_size: :label_size`) and `:title` (as `:label` with `font_size: :title_size`, `font_weight: :bold`). `Visualize.Chart.Schema.builtin_styles/0` lists them, a `{:ref, :style}` resolves against the union of the built-in and the declared names, and the frame resolves a style to an element's style map by `Visualize.Theme.resolve/3` for every slot in it (§4.7). A mark whose style gives no value for its paint key — `stroke` for a stroked type, `fill` for a filled one — takes the theme's `{:series, i}` for its one-based position among the marks as its paint (§5.6).

### 3.4 Resolution: one node, two outputs

**Implemented.** A style node resolves to the style map of a `Visualize.IR.Element` through `Visualize.Chart.Style.resolve/3` in the mode of the render target, and the mode is what makes one node serve two backends (D-63): in `:css` the SVG output carries classes and CSS custom-property references — `class="mark mark-line series"`, `stroke="var(--vis-series-1, #3b6fa8)"` — that a stylesheet overrides; in `:literal` a canvas gets the plain colour, width and font it needs, which `Visualize.Backend.Canvas` reads as they are (spec/09 §3). `resolve/3` keeps the eighteen element keys — `line_height`, `blend`, `effect` and `effect_radius` among them, which the backends read as spec/09 §2.5 and §3.3.3 say: `blend` is `mix-blend-mode` in an inline `style` attribute (it is a CSS property, not a presentation attribute every browser honours) and `globalCompositeOperation` on a canvas; `effect` with its radius is `filter="url(#vis-effect-<effect>-<radius>)"`, the filter itself declared once per chart per pair in the frame's `defs` (§2.7) as a `feDropShadow` or a `feGaussianBlur`, and on a canvas the context's shadow properties or its `filter` — resolves every slot through `Visualize.Theme.resolve/3`, joins a dash-array list with spaces, writes a `font_weight` of `:light` as `300` and `:medium` as `500` (`:normal` and `:bold` are CSS's own words and pass as they are) and passes a literal through; a canvas reads `font_style` and `font_weight` into its font shorthand — `italic 300 12px sans-serif` — beside the size and the family (spec/09 §3); a `{:field, f}` survives it unchanged, and `Visualize.Chart.Style.bind/4` then reads it from a datum through `Visualize.Data.Table.get/2` — a `:colour` key's reading through the frame's `color` scale when the frame declares one, the scale's output resolved as a slot when it is one — and drops the key when the reading is `nil`. A variable in either raises `ArgumentError` naming it: variables resolve at application (§7.3).

### 3.5 Derivation: `extends`

**Implemented** (work item 3 of #91, D-80). A style MAY name a parent under `extends`, a `{:ref, :style}` like any other style reference: the lookup flattens the parent's keys first and the child's over them, key by key, so `%{extends: :axis, stroke_width: 2}` is the axis style drawn heavier and the four keys of §3.3 are not copied. A chain of any length resolves, each link flattened over the one above it; the parent is looked up among the declared styles and the built-in four, so a design derives from `:axis`, `:grid`, `:label` or `:title` without declaring them.

Derivation is *within* a style; composition (§8) is *between* fragments, and the two never meet. `Visualize.Chart.compose/2` unions two `styles` maps and reports `:conflict` where they declare one name differently, and `extends` is a value of a style node like any other key while it does so. What derivation buys is that a dashboard wanting "the series style, but heavier" writes one key instead of copying four that then drift.

A cycle — a style that reaches itself through `extends`, directly or through a chain — is `:cycle` at the style's path (`[:styles, :series]`), reported by the validator for every style that reaches itself, and a design with one does not validate. `extends` reaches neither the element nor the mark's generator: the lookup consumes it, so a flattened style node never carries it and `Visualize.Chart.Style.resolve/3` never sees it.

### 3.6 Composition at a site: the style stack

Derivation (§3.5) is a chain *within* a style. A **stack** is composition *at the site that uses one*. Five keys refer to a style — `mark.style`, `label.style`, `mark_label.style`, `axis.style` and `legend.style` — and each takes either a reference, a style node written inline, or a **list** of those:

```elixir
[
  style: :series,
  # one reference, as it always was
  style: [:series, :emphasis],
  # two, the later winning
  style: [:series, %{stroke_width: 5}]
  # a shared style and a local one
]
```

A list cascades **left to right, the later winning**, which is `Visualize.Chart.stack/1`'s rule (§8.2) applied at a point rather than across a document. Each entry is resolved through its own `extends` chain *first*, and the resolved nodes then merge key by key. The two mechanisms are orthogonal and both remain: `extends` is a statement about a style, a stack is a statement about this mark.

A bare reference is a stack of one. That is not a compatibility shim but the definition — `:series` and `[:series]` resolve to the same node by the same path — so every design written before this section means exactly what it meant.

The private `node/2` of `Visualize.Chart.Style` is where this happens, and it is the only place a reference becomes a node; its eight callers are unchanged.

**The local style.** The last entry of a stack MAY be an inline style node, and that is where an edit made at the site lands. Editing the stroke width of a mark that references `:series` must not restyle every other mark that references the same name, so an edit writes to the site's own node and never to the shared one. A local style is **created on first edit** — a site with no local edit carries references and nothing else, because a document should not carry structure nobody asked for.

It is **anonymous in the document**: an inline node is not a key of `design.styles`, so nothing can refer to it. `Visualize.Chart.explain/1` needs a name for attribution and synthesises one from where it sits — `marks[0].style.local`, `axes[1].style.local` — which is unique by construction, one local per site and one site per position. That name is a **display name and not a reference**: writing `style: :"marks[0].style.local"` names a style nothing declares, exactly as any other undeclared name does. Sharing a local style means promoting it to a declared one.

**What does not change.** A reference to a style nothing declares is the error it already is, at the entry's own path. A cycle through `extends` is `:cycle` as before, and a stack cannot introduce one, because a stack is not a chain: an entry may not name the stack it sits in.

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
| `transition` | `{:node, :transition}` | `nil` | continuous: how a moving domain reaches its new extent in a compiled chart (§12.5, #360) |

A `:transition` node has `duration` (`:number`, `:geometry`, `300`, milliseconds), `easing` (`{:enum, …}`, `:geometry`, `:cubic_in_out` — a curve of `Visualize.Ease` by name) and `shrink_after` (`:number`, `:geometry`, `0`, milliseconds), every key `:override`. It says nothing to `Visualize.Chart.Frame.new/2`, which draws the inferred domain as it always has: a transition is a property of a *run*, and lives in the thing that runs (§12.5).

**Realisation.** `Visualize.Chart.Frame.new/2` builds one scale struct per entry through the constructors of `Visualize.Scale` — `:linear` by `Visualize.Scale.linear/0`; `:log` by `Visualize.Scale.log/1` with `base`; `:power` by `Visualize.Scale.power/0` with `exponent`; `:sqrt`; `:symlog` with `constant`; `:time`; `:radial`; `:ordinal` with `unknown`; `:band` with `padding` or, when either is given, `padding_inner` and `padding_outer`, then `align` and `round`; `:quantize`, `:quantile` and `:threshold`; `:sequential` and `:diverging` by `Visualize.Scale.Color` over the range — then the domain, the range, and `Visualize.Scale.nice/1` and `Visualize.Scale.clamp/2` when the flags are true. The realised scales are cached on the frame and read through `Visualize.Chart.Frame.scales/1`, the escape hatch for annotations, brush conversion and custom marks; `Visualize.Chart.Frame.put_scale/3` replaces one after construction, which is the code-level override of §1.1 — an axis drawn for that name follows the replacement (D-60).

**Inference.** `domain: :auto`, or an extent with `:auto` at one end, is inferred at construction from every mark channel that names the scale, over the sources given to `new/2`, whole column (Tucan's first-row rule is the documented limit, D-52):

- A channel names a scale by the frame's kind. In a `:cartesian` (and a `:facet`) frame `x`, `x0` and `x1` name `x`; `y`, `y0`, `y1`, `median`, `inner_lo`, `inner_hi`, `outer_lo` and `outer_hi` name `y`; `series` names `color`, and so does `value` on a `:rect`. In a `:polar` frame `angle` names `angle`; `value` on a `:rose`, `inner` and `outer` name `r`. In a `:geo` frame `series` names `color`. The `value` of a `:symbol`, a `:circle` and an `:arc` is a size or a share (§5.2) and names nothing. A mark's `scales` node (§5.1) renames what its channels name: `scales: %{x: :count}` sends that mark's `x`, `x0` and `x1` through the frame's `count` scale instead of `x`, so a scale of any other name — a marginal histogram's counts, a second `y` — is inferred from, and drawn by, the marks that name it (D-67). A `{:field, f}` on a `:colour` key of a mark's style names `color` in every kind (§3.2), whatever the mark's `scales` say.
- The values are the channel's column of the mark's source through `Visualize.Data.Table.get/2` — the field itself, or the `f` of a `{:field, f}` — with `nil`s dropped; a number channel contributes the number. A mark whose source is not among the bound sources contributes nothing; a mark that reads its source through transforms contributes the column of the *transformed* rows — the pipeline of §5.4 runs at construction over the bound source, so a `:bin`'s `count` or a `:stack`'s `y1` infers the domain it is drawn on (D-62).
- The domain follows the kind. Continuous scales (`:linear`, `:log`, `:power`, `:sqrt`, `:symlog`, `:radial`, `:quantize`, `:threshold`, `:sequential`) take the extent `[lo, hi]` of `Visualize.Data.extent/2`; `:diverging` takes `[lo, (lo + hi) / 2, hi]`. `:time` takes the extent under the values' own ordering (`DateTime`, `Date` or `NaiveDateTime` compare by their module, never by term order), an ISO 8601 string read as `Visualize.Data.Table.temporal?/1` reads it, and a value that is not temporal raises `ArgumentError` naming the scale. `:quantile` takes every value as its samples. `:ordinal` and `:band` take the distinct values in order of first appearance.
- `[0, :auto]` fixes the lower end and infers the upper; `[:auto, hi]` the reverse.
- A collapsed extent — one distinct value — stays `[v, v]`: every continuous scale maps it to the range midpoint and its axis draws one tick (D-49). The frame never widens a domain; an author who wants a readable axis fixes an end.
- Nothing bound gives the unit domain: `[0, 1]` for a continuous scale (`[1, 10]` for `:log`, whose domain excludes zero), `[0, 0.5, 1]` diverging, one day from the Unix epoch for `:time`, `[]` for the discrete and quantile scales. A frame therefore renders without any source, over its unit domains, which is what the static split needs (§12).

**Range.** `range: :auto` follows the scale's name. `x` is `[0, width]` of the plot area and `y` is `[height, 0]`; `angle` is `[0, 2π]`, radians clockwise from 12 o'clock ([04-shapes-and-curves](04-shapes-and-curves.md) §6.2); `r` is `[0, min(width, height) / 2]`; `color` on a discrete scale is the theme's series as slot atoms, `[:series_1, …, :series_n]`, which the legend and the marks resolve through `Visualize.Theme.resolve/3` in the mode of their render target, so a theme swap recolours the scale's output. A `:sequential` scale, whatever its name, runs from the theme's `background` to its first series colour and a `:diverging` one from the second series colour through the background to the first: a colour scale's output is a colour, and the plot area has nothing to offer it. Any other name follows the first axis that names it — `:top` or `:bottom` as `x`, `:left` or `:right` as `y` — and is `[0, 1]` when no axis does. A range given as a list is used as it is, and an empty list raises `ArgumentError` naming the scale — a scale with no value to map to is an authoring error, not a scale; a scheme name is `Visualize.Scale.Color.scheme/1`'s stops, the colours of a discrete scale or the interpolator of a colour scale. A scale name is any atom; the names `x`, `y`, `angle`, `r` and `color` carry the meanings above, so an axis or a legend on any other name MUST say where it draws through `side` and `position`. **An offset scale** (#132): the names `x_offset` and `y_offset` are a band within a band — a `:band` scale whose `:auto` range is `[0, bandwidth]` of the scale its family maps to (`x` or `y`, or whatever the mark's `scales` node renames it to), realised after that scale; its domain is inferred from the fields the marks' `offset` nodes read (§5.1). A range given as a list is used as it is.

### 4.4 Axes and tick specs

**Implemented.** An `:axis` node draws a scale on one side of the plot area; tick geometry is a `:ticks` node, the fourth level.

| Key | Type | Facet | Default | Merge |
|---|---|---|---|---|
| `scale` | `{:ref, :scale}` | `:geometry` | required | `:override` |
| `side` | `{:enum, [:top, :right, :bottom, :left]}` | `:geometry` | required | `:override` |
| `ticks` | `{:one_of, [:integer, {:list, :term}, {:node, :ticks}]}` | `:geometry` | `nil` | `:override` |
| `format` | `{:one_of, [:string, {:enum, [:duration]}]}` | `:content` | `nil` | `:override` |
| `prefix` | `:string` | `:content` | `nil` | `:override` |
| `unit` | `:string` | `:content` | `nil` | `:override` |
| `grid` | `:boolean` | `:geometry` | `false` | `:override` |
| `offset` | `:number` | `:geometry` | `0` | `:override` |
| `style` | `{:ref, :style}` | `:style` | `:axis` | `:override` |

`ticks` as an integer is the count hint, as a list the explicit values, as a `:ticks` node both with the sizes: `count` (`:integer`, `:geometry`), `values` (`{:list, :term}`, `:content`), `size_inner` and `size_outer` (`:number`, `:geometry`, `6`) and `padding` (`:number`, `:geometry`, `3`) — the setters of [05-axes-and-formatting](05-axes-and-formatting.md) §1.2 by name. Explicit values beat the count, and the count beats the scale's default of ten.

Each axis is a `Visualize.Axis` on the realised scale, oriented by `side`, with the tick spec, `offset` and the frame's theme applied, generated in the `:resolve` mode of the render (spec/05 §1.4) and placed at its side of the plot area: `:bottom` at `translate(0, height)`, `:right` at `translate(width, 0)`, `:top` and `:left` at the origin. A frame's axis is therefore byte for byte the axis a caller builds by hand from the same scale, and `test/visualize/chart/frame_test.exs` holds it to that. `format` is a `Visualize.Format` specifier applied to every tick value: `Visualize.Format.time/2` on a `:time` scale, `Visualize.Format.formatter/1` on any other, a tick value that is not a number passing through `to_string/1` — or the name of a format no specifier can express: `:duration`, `Visualize.Format.duration/1` over a value in seconds, the unit chosen by magnitude (`45s`, `2m30s`, `1.5h`; spec/05 §2.9, #191). Bytes by magnitude are the specifier's own `s` type with a unit (`format: ".1~s", unit: "B"` prints `2.3GB`). **A tick carries a unit** (#135): `prefix` and `unit` are literals put before and after every tick's label — the formatted value, or the default label when there is no `format` — so `unit: "M"` prints `1412M`, `prefix: "$", unit: "T"` prints `$5T`, and `unit: "%"` prints `45%` of a value already in percent, where the specifier's own `%` would multiply by a hundred. The specifier stays d3's; a unit is what every caller was concatenating by hand, and the two keys live on the axis beside `format`, the key they complete, rather than on the `:ticks` node, which holds geometry.

`grid: true` draws a line at each tick position across the plot area — the height for a `:top` or `:bottom` axis, the width for a `:left` or `:right` one — in the `:grid` style, behind every axis, in one group `class="grid"` that is `aria-hidden` like the axes (D-56). The axis's line, ticks and labels draw in its `style`; tick sizes stay geometry. A `style` other than `:axis` restyles the generated axis: `stroke`, `stroke_width`, `stroke_dasharray`, `stroke_linecap`, `stroke_linejoin` and `stroke_opacity` reach the domain line and the tick lines, `fill` and the font keys reach the tick labels, `opacity` and `class` the axis group.

An axis has no `id`: its identity in a stack is `{scale, side}` (§8.2), so a layer that wants the shared frame's bottom x-axis with six ticks writes an axis for that scale and side and replaces it, and two axes drawing one scale on one side can never both be drawn. Nothing in the axis node is required to make that identity — `scale` and `side` are both required keys already.

### 4.5 Legend

**Implemented.** A `:legend` node explains one scale, normally the colour scale.

| Key | Type | Facet | Default | Merge |
|---|---|---|---|---|
| `scale` | `{:ref, :scale}` | `:geometry` | required | `:override` |
| `position` | `{:enum, [:top_left, :top_right, :bottom_left, :bottom_right, :top, :bottom, :left, :right]}` | `:geometry` | `:top_right` | `:override` |
| `inside` | `:boolean` | `:geometry` | `true` | `:override` |
| `title` | `:text` | `:content` | `""` | `:override` |
| `prefix` | `:string` | `:content` | `nil` | `:override` |
| `unit` | `:string` | `:content` | `nil` | `:override` |
| `style` | `{:ref, :style}` | `:style` | `:label` | `:override` |

The frame builds the legend from the realised scale: one entry per value of `Visualize.Scale.ticks/2` — the domain of a discrete scale, five ticks of a continuous one — each a 12 × 12 swatch and, 16 user units to its right, the value's label as an axis would print it (spec/05 §1.5), with the legend's own `prefix` and `unit` before and after it (#135), so a legend explaining a scale with units agrees with the axis drawing it. The swatch is filled with the scale's value for the entry when that is a colour — a string, or a theme slot resolved through `Visualize.Theme.resolve/3` (§4.3) — and with the theme's `{:series, i}` for the i-th entry of a scale that yields anything else. The labels and the title take the legend's `style`.

```
group  style: %{class: "legend", font_family: <font_family>, font_size: <font_size>}, transform: translate(x, y)
├── text   style: %{fill: <fill>, font_weight: :bold}, content: title            — when the title is given
└── group  style: %{class: "legend-item"}, attrs: %{"data-series" => value}, transform: translate(…)  — one per entry
    ├── rect  0 0 12 12, style: %{fill: <swatch>}
    └── text  x: 16 (or −4, anchored end), y: 6, dy: "0.32em", style: %{fill: <fill>}, content: label
```

Entries are 16 apart and the title, when given, is the first row. `position` places the legend inside the plot area, 8 user units from its edges: the four corner positions stack the entries downward from the corner, the right-hand ones laid out right to left — the swatch at the edge and the label anchored `end` to its left — so no text width is needed; `:left` and `:right` stack them likewise, centred on the plot's height; `:top` and `:bottom` lay them in one row centred on the plot's width, each entry's width taken as 16 plus 0.6 × the font size per character of its label — the one place the layout estimates text.

**A legend in a margin** (#136). With `inside: false` the legend sits in the margin its position names, 8 user units out from the plot's edge, laid out in the same direction as inside: `:right`, `:top_right` and `:bottom_right` stack in the right margin, at the plot's top, centred on its height, or at its bottom; `:left`, `:top_left` and `:bottom_left` likewise in the left margin; `:top` and `:bottom` run in one row in the top and bottom margins, centred on the plot's width, the row's swatches 8 above the plot's top edge or 8 below its bottom one. Outside there is room, so every position reads swatch-then-label — the right-to-left order is the inside layout's alone — and a left-margin legend is placed by its estimated width so its labels end 8 from the plot: the swatch, the gap and 0.6 × the font size per character of the longest label (the title counted as a label). A legend that does not fit its margin is not clipped silently: `Visualize.Chart.Frame.new/2` raises `ArgumentError` naming the margin and the size the legend needs — its estimated width for a side margin, its rows × 16 (the swatch's 12 for a row) plus the 8 for a top or bottom one — as it raises for an empty range, since a legend the author cannot see is worse than a fault. The converted gallery charts that reserved a margin for their legend draw it there.

Every entry's group carries `data-series`, `to_string/1` of the entry's value — the string a series path carries (§5.6) — so `LegendHook` (spec/10 §14) can hide what the entry explains; it is written whatever the scale and is inert without the hook (D-77).

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

With `paths: true` the frame's group, each mark's and axis's group, the legend's group and each label's text carry `data-node` with the node's path (below).

A `:facet` frame holds one `class="panel"` group per panel in place of the grid, marks and axes; a `:polar` frame's grid, marks and axes sit inside a group translated to the plot centre. `generate/2` draws the marks only when given `sources:` — a map from source name to anything `Visualize.Data.Table.rows/1` reads, as `new/2` takes — each through `Visualize.Chart.Mark.generate/3` at its one-based position; without sources it is the furniture alone, which is what the static split needs (§12). A `%Visualize.Chart.Var{}` reached while building — in a text, a style or a node — raises `ArgumentError` naming it: variables resolve at application (§7.3), and a frame is built from an applied design or from one that uses none. `Visualize.Chart.Frame.render/2` is `generate/2` followed by `Visualize.Render.to_string/2`, with `:resolve` defaulting to `Visualize.Theme.mode/1` of the `:backend`, as `Visualize.Axis.render/2` does.

**Every node the frame draws carries its path when asked** (#259, D-105). `generate/2` and `render/2` take `paths:`, `false` by default; with `paths: true` the element each design node renders carries `data-node` spelling the node's path as `Visualize.Chart.Validator.format_path/1` spells one — `frame` on the frame's own group, `marks[i]` on a mark's group (its zero-based position among `marks`), `frame.axes[i]` on an axis's group, `frame.legend` on the legend's, `labels[i]` on a label's text. The frame stamps what it places: a mark's group is `Visualize.Chart.Mark.generate/3`'s as it is, tagged by the frame at the position it drew it, so a facet frame's copies of one mark carry one path and a polar frame's ring and spoke axes keep their positions among `axes`. A mark's inline label (§5.5) sits inside its mark's group and has no path of its own; the grid is furniture, not a node. Without the option the markup is byte for byte what it was, so a chart drawn for a page is unchanged, and the builder — which draws with it so a click on the graph can name what it hit (§18.4, §18.16) — is the caller that asks. `Visualize.Chart.render/2` passes it through.

**A design renders as a document when asked** (#131). `Visualize.Chart.generate/2` is the applied chart as a `Visualize.IR.Element` — the frame's group, as `generate/2` above builds it over the bound sources — and `Visualize.Chart.render/2` is that element serialised. Both take `root:`, `false` by default: with `root: true` the group is the one child of `Visualize.IR.Element.root/3` at the frame's own `size`, the accessible root of spec/02 §2.1 — `role="img"`, the `viewBox`, a `<title>` and a `<desc>` first with `aria-labelledby` naming them — its title and description the design's `meta.name` and `meta.description` (§2.1), each a text with no hole left in it after application, an absent or empty one leaving its element out; `title:` and `description:` override them and `responsive:` reaches the root as its own option. A design carries everything the root needs, so nothing new is written to say it: a caller that put a chart in a page built this `<svg>` by hand, and three of them did it three ways. The default stays the bare group, so nothing that renders a chart today changes. The components of spec/10 keep their own `<svg>`: their markup is what spec/10 §1.2 specifies, class and font included, not a shell around a rendered design.

## 5. Marks

### 5.1 Keys

**Implemented.** A mark binds fields of its data to the frame's scales and draws them with one of the existing generators. `Visualize.Chart.Mark.generate/3` draws one mark of a frame (§5.6); `Visualize.Chart.Frame.generate/2` draws every mark of the design when it is given the sources (§4.7). `render` is the compiler's override (§12.3) and changes nothing `generate/3` draws.

| Key | Type | Facet | Default | Merge |
|---|---|---|---|---|
| `type` | `{:enum, mark types}` | `:channel` | required | `:override` |
| `data` | `{:one_of, [{:ref, :source}, {:node, :data}]}` | `:binding` | required | `:override` |
| `channels` | `{:node, :channels}` | `:channel` | `%{}` | `:override` |
| `scales` | `{:node, :mark_scales}` | `:channel` | `%{}` | `:override` |
| `offset` | `{:node, :mark_offset}` | `:channel` | `%{}` | `:override` |
| `options` | `{:node, :options}` | `:geometry` | `%{}` | `:override` |
| `style` | `{:ref, :style}` | `:style` | `nil` (§3.3) | `:override` |
| `label` | `{:node, :mark_label}` | `:content` | `nil` | `:override` |
| `render` | `{:enum, [:auto, :svg, :canvas, :binary]}` | `:geometry` | `:auto` | `:override` |
| `tooltip` | `{:node, :tooltip}` | `:content` | `nil` | `:override` |
| `id` | `:name` | `:content` | `nil` | `:override` |

`scales` is the mark's word on which scale a channel family reads through (§4.3). A `:mark_scales` node's keys are the scale names of the frame kinds' tables — `x`, `y`, `angle`, `r` and `color` — each `{:ref, :scale}`, `:channel`, `nil` by default, `:override`; a key the frame's kind does not use names nothing. `scales: %{x: :count}` sends the mark's `x`, `x0` and `x1` through the declared scale `count`, and every channel not renamed reads the scale of the kind's table as before. The name must be one the frame declares (`{:undeclared, :scale, name}` otherwise), so a mark still references scales by name and never by nesting (§1.2).

`offset` is a band within a band (#132, D-109): a `:mark_offset` node's keys are `x` and `y`, each a `:field`, `:channel`, `nil` by default, `:override` — the field whose value places the datum *within* its band on that family. With `offset: %{x: :series}` a `:rect`'s `x0` and `x1` read the category's band from `x` as before, then the series' band from the `x_offset` scale (§4.3) inside it: `x0` at the outer band's start plus the inner band's start, `x1` a bandwidth of the inner further, a position channel at the inner band's centre; the reading adds, which is d3's own model and the one the layer's grain allows, since the frame owns both scales and an offset scale is a scale. A grouped bar chart is therefore one `:rect` mark over one row per bar, its `x_offset` a `:band` over the series; an offset on `y` is a grouped horizontal bar; an offset scale with one member is the ungrouped chart. A family whose outer scale is not a `:band`, or a datum the inner scale cannot place, places nothing (§5.2's per-datum drop). The mark's `scales` renames apply to both: `scales: %{x: :cat, x_offset: :inner}`.

`id` is the mark's identity in a stack (§8.2): a higher layer's mark with the same `id` replaces this one in place rather than drawing a second mark beside it. It is optional, is not required to be unique, and nothing renders from it — a mark without one appends, as every mark did before identity existed.

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
| `:text` | `x`, `y` | `value` | a text per datum at the scaled position (#134): its content the mark's inline `label` text (§5.5) read from the datum, else `value` as a string; drawn in the label's style, `class="mark mark-text"`, and anchored as the label's `anchor` says about the position — the mark a grammar of graphics has, so a text at a data position needs no invisible carrier. It draws text alone, so its render target is `:svg` whatever `render` says (§12.3) |

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
| `:text` | — |
| every other type | none |

An `:arc`'s `inner` and `outer` channels replace `inner_radius` and `outer_radius` per datum; its `start` and `end` channels, given together, replace the pie — `start_angle` and `end_angle` are not read then, and `pad_angle` is the arc's own (`Visualize.Shape.Arc.pad_angle/2`) rather than the pie's. Angles are radians and sizes user units, as in [11-public-api](11-public-api.md) §3.3.

### 5.4 Data and transforms

**Implemented.** `data` is a source name, or a `:data` node with `source` (`{:ref, :source}`, `:binding`, required) and `transforms` (`{:list, {:node, :transform}}`, `:binding`, `[]`, `:concat`). Layouts, binning, stacking, aggregation and the geo algorithms are transforms — steps in a mark's data pipeline that yield rows — never marks: a treemap is a `:treemap` transform producing rows with `x0 y0 x1 y1` that a `:rect` draws, and a chord diagram is a `:chord` transform whose rows carry a `path` that a `:path` mark draws.

`Visualize.Chart.Transform.apply/3` runs the steps in order over the source's rows (`Visualize.Data.Table.rows/1`), each step a pure function of the rows before it and its node, yielding the rows the next step or the mark reads. Its only context is the plot area, as `size:`, in a `:geo` frame the projection, as `projection:`, and the bound sources, as `sources:`, for the one step that reads a second table (a graph's `nodes`, §5.4.3) — never a scale, so the frame runs the pipeline before its scales exist and infers their domains from the transformed columns (§4.3, D-62). A step that reads a column the rows lack reads `nil` and treats it as the op says; a step that lacks a key its op requires raises `ArgumentError` naming both.

A `:transform` node has `op` (`{:enum, ops}`, `:binding`, required) and the keys its op reads; every key is `:override`. `Visualize.Chart.Schema.transform_keys/1` returns the required and optional keys of an op, and the validator reports a missing required key as `:required` and a key the op does not read as `{:invalid_for, op}`:

| Key | Type | Facet | Read by |
|---|---|---|---|
| `field` | `:field` | `:binding` | `:bin`, `:sum`, `:sort`, `:contour` (the value); the hierarchies (the value summed); `:chord`, `:sankey` (the flow's value); `:density` (the weight); `:projection` (the geometry, in place of `fields`) |
| `fields` | `{:list, :field}` | `:binding` | `:stack` (the series); `:fold` (the columns to fold, those the rows have); `:chord`, `:sankey`, `:force` (`[source, target]`); `:delaunay`, `:voronoi`, `:density` (`[x, y]`); `:projection` (`[longitude, latitude]`) |
| `by` | `:field` | `:binding` | `:sum` (the group), the hierarchies (the parent) |
| `id` | `:field` | `:binding` | the hierarchies (the node identifier) |
| `as` | `{:one_of, [:name, {:list, :name}]}` | `:binding` | `:bin`, `:sum` (the output column, a name); `:fold` (the two output columns, a pair of names) — the validator holds each op to its shape |
| `thresholds` | `{:one_of, [:integer, {:list, :number}]}` | `:geometry` | `:bin`, `:contour`, `:density` |
| `order` | `{:enum, [:none, :ascending, :descending, :inside_out, :reverse, :appearance]}` | `:geometry` | `:stack`, `:sort` |
| `offset` | `{:enum, [:none, :expand, :silhouette, :wiggle, :diverging]}` | `:geometry` | `:stack` |
| `size` | `{:list, :number}` | `:geometry` | the layouts and the geo algorithms (`[width, height]`, default the plot area); `:contour` (the grid's `[columns, rows]`) |
| `padding` | `:number` | `:geometry` | the hierarchies, `:sankey` (the node gap), `:chord` (the pad angle) |
| `tile` | `{:enum, [:squarify, :binary, :slice, :dice, :slice_dice]}` | `:geometry` | `:treemap` |
| `nodes` | `{:ref, :source}` | `:binding` | `:chord`, `:sankey`, `:force` (the node source, §5.4.3) |
| `strength` | `:number` | `:geometry` | `:force` (the many-body strength, `-30`) |
| `distance` | `:number` | `:geometry` | `:force` (the link distance, `30`) |
| `orientation` | `{:enum, [:vertical, :horizontal]}` | `:geometry` | `:tree`, `:cluster` (the orientation of the `:links` rows' `path`, `:vertical` by default) |
| `link` | `{:enum, [:curve, :elbow, :line]}` | `:geometry` | `:tree`, `:cluster` (the shape of the `:links` rows' `path`, `:curve` by default) |
| `bandwidth` | `:number` | `:geometry` | `:density` |
| `radius` | `:number` | `:geometry` | `:hexbin` (the hexagon's circumradius in pixels, `20`) |
| `output` | `{:enum, [:nodes, :links, :groups, :chords, :triangles, :hull, :cells, :edges, :points]}` | `:binding` | the layouts and the geo algorithms: which rows they yield |
| `test` | `{:enum, [:eq, :ne, :lt, :lte, :gt, :gte, :present, :absent]}` | `:binding` | `:filter` (how the reading is tested, `:present` by default) |
| `value` | `:term` | `:binding` | `:filter` (what the reading is tested against, `nil` by default) |

The ops are `:filter`, `:bin`, `:stack`, `:fold`, `:sum`, `:sort`, `:tree`, `:cluster`, `:pack`, `:partition`, `:treemap`, `:chord`, `:sankey`, `:force`, `:contour`, `:density`, `:delaunay`, `:voronoi` and `:hexbin` (`Visualize.Chart.Schema.transform_ops/0`) and `:projection`. Every row a step yields is a map; a row the step derives from a datum keeps the datum's columns and adds its own, so a `:treemap` node still carries its `name`. A field named in a mark's `channels`, in its inline label's text or in its transforms is checked against the source's declared `fields` when the mark reads the source directly. After a transform the columns are the transform's, and a `{:field, f}` in a style is shared by every mark that references the style; those references are read at render, when the rows exist.

#### 5.4.1 Data steps

- `:filter` — `field` required; `test` (`:present`) and `value` (`nil`). The rows, in order, whose reading of `field` through `Visualize.Data.Table.get/2` passes the test: `:present` keeps a reading that is not `nil` and `:absent` one that is; `:eq` keeps a reading equal to `value` (`==`) and `:ne` one that is not; `:lt`, `:lte`, `:gt` and `:gte` keep a reading that is not `nil` and stands so to `value` under Elixir's term ordering, as `:sort` orders — a `nil` reading never passes an ordering. The step reads a column the rows lack as `nil`, so `%{op: :filter, field: :height, test: :eq, value: 0}` after a hierarchy keeps its leaves and `%{op: :filter, field: :depth, test: :gt, value: 0}` drops its root (D-68). The transform node's `op` names the step, which is why the test is not under `op`.
- `:bin` — `field` required; `thresholds` (`10`) and `as` (`:count`). `Visualize.Data.bin/2` over the column with `nil`s dropped, one row per bin: `x0`, `x1`, `y0` (`0`, so a histogram's channels read the rows alone), `as` (the bin's count) and `values`.
- `:stack` — `fields` required (the series keys); `order` (`:none`), `offset` (`:none`). `Visualize.Shape.Stack` with the keys, the order and the offset (`:inside_out` is its `:insideout`; `:appearance` orders the keys by the index of each series' greatest value, d3's `stackOrderAppearance`, before a `:none` stack). One row per series in key order, per datum in data order: the datum's columns plus `key`, `series` (the series' stacking position), `value`, `y0` and `y1`.
- `:fold` — `fields` required; `as` (`[:key, :value]`). Wide columns to long rows (#237): one output row per input row per listed column the row *has* — a listed column the rows lack is skipped, never a fault, which is how a design says "these, if they exist", and a row's `nil` in a folded column yields no row for it — the row's other columns carried unchanged, the folded column's name under the first name of `as` and its value under the second. Input rows in order, and within a row the columns in the order `fields` lists them, so the series order is the author's. A `fields` that is a variable resolves at application like any list (§7.1), so a host or the variables panel chooses the set. The validator holds `fields` to names alone — not to the source's fields, since a missing one is not a fault; the source declares the columns every row has (`[:hour]`, checked at binding, §7.3) and the fold lists the ones a row may — and, as after any step, does not check a channel against the folded rows (a step's columns are known at run time); a channel that reads a folded column after the fold reads `nil`, as §5.4 says of any column the rows lack.
- `:sum` — `field` required; `by` and `as` (`:sum`). One row per distinct `by` value in order of first appearance, `%{by => value, as => sum}` with `nil`s ignored; without `by`, one row `%{as => sum}`.
- `:sort` — `field` required; `order` (`:ascending`, or `:descending`). The rows stably sorted by the column under `Enum.sort_by/3`'s ordering.

#### 5.4.2 Hierarchies

`:tree`, `:cluster`, `:pack`, `:partition` and `:treemap` read the rows as a flat node list: `id` (`:id`) names each node and `by` (`:parent`) its parent, `nil` or `""` for the root, through `Visualize.Layout.Hierarchy.stratify/2`; `field` names the value `Visualize.Layout.Hierarchy.sum/2` adds up (`nil` as `0`), and without it `Visualize.Layout.Hierarchy.count/1` counts leaves. `size` (`[width, height]`, default the plot area) and `padding` (`0`) reach the layout's own setters, `tile` (`:squarify`) the treemap's. The hierarchies of [06-layouts](06-layouts.md) §2–5 lay out the tree exactly as a direct call would.

- `output: :nodes` (the default) — one row per node in pre-order (`Visualize.Layout.Hierarchy.descendants/1`): the datum's columns plus `depth`, `height`, `value` and the layout's own fields — `x`, `y` for `:tree` and `:cluster`; `x`, `y`, `r` for `:pack`; `x0`, `y0`, `x1`, `y1` for `:partition` and `:treemap`.
- `output: :links` (`:tree`, `:cluster` and `:pack`) — one row per parent–child pair in the order of `Visualize.Layout.Hierarchy.links/1`: `source` and `target` (the ids), `x0`, `y0` (the parent's position), `x1`, `y1` (the child's) and `path`, a `Visualize.IR.Path` — for `:tree` and `:cluster` the link of `orientation` (`:vertical`): vertical is `M x0,y0 C x0,ym x1,ym x1,y1` with `ym` the mid-height, horizontal the same curve with the axes swapped, `M y0,x0 C ym,x0 ym,x1 y1,x1`, so `size: [height, width]` with `orientation: :horizontal` is the tree spec/10 §3.2 draws; the rows' `x`, `y`, `x0`, `y0`, `x1` and `y1` stay the layout's own in either orientation (D-70). `link` (`:curve`) is the path's shape (#127): `:curve` the cubic above; `:elbow` the dendrogram's step, across at the parent's depth and then down to the child — vertical `M x0,y0 H x1 V y1`, horizontal `M y0,x0 V x1 H y1` — so the branches of one parent leave it as one line; `:line` the straight segment. For `:pack` the path is the straight line between the centres.

#### 5.4.3 Graphs

`:chord`, `:sankey` and `:force` read the rows as flows: `fields: [source, target]` required, `field` the flow's value (`1` when absent for `:force`, required by the other two). The nodes are the distinct ids over every source and then every target, in order of first appearance — or, with `nodes` (#346, D-110), the rows of the source it names: a graph is two tables, and the second is the nodes. The node source's `id` column (the step's `id` key, `:id` by default) keys them; a node row the layout yields is that row's columns with the layout's own — `id`, its position, `index`, `depth` — over them, so a mark's style reads `fill: {:field, :group}` and its label `{:field, :name}` from the node table; the node order is the source's; a flow whose source or target the table lacks raises `ArgumentError` naming the id; a node the flows never mention is laid out as an isolated node. The validator holds `nodes` to a declared source as it holds a mark's `data`, and `Visualize.Chart.Frame.new/2` reads the source from the same binding a mark's `data` is bound from (§7.3), so an unbound node source is the unbound-source fault. `size` (`[width, height]`) defaults to the plot area; every position and path is in its pixels.

- `:chord` — `padding` (`0`) is the pad angle in radians. The flows fill the square matrix of `Visualize.Layout.Chord.generate/2` (a repeated pair adds up); with `R = min(width, height) / 2` and the centre at `(width / 2, height / 2)`, `output: :groups` (the default) yields one row per group in index order — `index`, `id`, `start_angle`, `end_angle`, `value` and `path`, the annulus sector between `0.9 R` and `R` as `Visualize.Shape.Arc` draws it, translated to the centre — and `output: :chords` one row per chord in row-major order: `source`, `target` (the ids), `source_value`, `target_value` and `path`, the ribbon at `0.9 R` of `Visualize.Layout.Chord.ribbon_path/2` as a `Visualize.IR.Path` (the source arc, a quadratic curve through the centre to the target arc's start, the target arc, a quadratic curve back, `Z`), translated to the centre.
- `:sankey` — `padding` (`8`) is the node gap; the node width is `24`. `Visualize.Layout.Sankey.compute/3` over the nodes and the flows; `output: :nodes` (the default) yields one row per node in input order with `id`, `index`, `depth`, `height`, `layer`, `value`, `x0`, `x1`, `y0`, `y1`; `output: :links` one row per flow in input order with `source`, `target`, `value`, `width`, `x0` (the source node's right edge), `y0`, `x1` (the target node's left edge), `y1` and `path`, the ribbon of `Visualize.Layout.Sankey.generate_link_path/1` as a `Visualize.IR.Path`.
- `:force` — `Visualize.Layout.Force.run/1` over the nodes and the flows with the forces `[{:center, x: width / 2, y: height / 2}, {:many_body, strength: strength}, {:link, distance: distance}]` — `strength` (`-30`) and `distance` (`30`) the step's own keys (#346) — and its default 300 iterations: a pure function of the input, so a design renders the same graph twice. `output: :nodes` (the default) yields one row per node with `id`, `x`, `y`; `output: :links` one row per flow with `source`, `target`, `x0`, `y0`, `x1`, `y1` and `path`, the straight line.

#### 5.4.4 Geo algorithms

`:delaunay`, `:voronoi`, `:density` and `:hexbin` read pixel coordinates from `fields: [x, y]` (required); a `nil` coordinate drops the datum. They run after a `:projection` step, or a `:force`, or over columns already in pixels, and never through a scale.

- `:projection` — the projection is the frame's (`projection:` of `Visualize.Chart.Transform.apply/3`), and a pipeline without one raises `ArgumentError`. With `fields: [longitude, latitude]` each row is a point: it gains `x` and `y` from `Visualize.Geo.Projection.project/3`, and a point the projection clips is dropped. With `field` (#349) each row holds a GeoJSON geometry or feature under that column — a map as `Visualize.Geo.Path` reads it (spec/07 §2.1), `%{"type" => "Sphere"}` included — and gains `path`, the projected outline as a `Visualize.IR.Path` from `Visualize.Geo.Path.path/2`, and `x`, `y`, its centroid from `Visualize.Geo.Path.centroid/2`; a row whose geometry projects to nothing is dropped. One of the two keys is required and the validator reports a step with neither as `fields` `:required`; a step with both is reported as `field` `{:invalid_for, :projection}`. Clipping is the projection's own (spec/07 §1.5): the orthographic drops the far hemisphere and a pseudo-cylindrical map ends at the antimeridian, so a design draws no `clipPath`.
- `:delaunay` — `Visualize.Geo.Delaunay.new/1` over the points. `output: :triangles` (the default) yields one row per triangle in construction order: `index`, `vertices` (the three point indices, counter-clockwise) and `path`, the closed triangle; `output: :hull` one row, `path`, the closed hull (an empty path for fewer than three points).
- `:voronoi` — `Visualize.Geo.Voronoi.new/1` over the points, bounded by `[0, 0, width, height]`. `output: :cells` (the default) yields one row per point in input order: the datum's columns plus `index` and `path`, the closed clipped cell (`Visualize.Geo.Voronoi.cell/2`; an empty path for a site without a cell); `output: :edges` one row per finite edge: `x0`, `y0`, `x1`, `y1` and `path`.
- `:contour` — `field` required, read from every row in row-major order over the grid `size: [columns, rows]` (required); `thresholds` (`10`). `Visualize.Contour.compute/2` with smoothing on; one row per ring — a polygon of a threshold's `MultiPolygon` — in threshold order: `value` and `path`, the ring closed with `Z`, its grid coordinates scaled so that the grid's `columns − 1` by `rows − 1` cells span the plot area.
- `:density` — `field` (the weight, `1` when absent), `size` (default the plot area), `bandwidth` (`20`), `thresholds` (`20`); the cell size is `4`. `Visualize.Contour.Density.compute/2`; one row per ring in threshold order, `value` and `path`, the ring closed, in pixels.
- `:hexbin` (#348) — `radius` (`20`), the hexagon's circumradius in pixels. `Visualize.Layout.Hexbin.bin/2` over the points (spec/06 §9); `output: :cells` (the default) yields one row per non-empty cell in lattice order — `x`, `y` (the centre), `count` and `path`, the closed hexagon of `Visualize.Layout.Hexbin.hexagon/3` — so a `:path` mark with `fill: {:field, :count}` through a `:sequential` `color` scale is the density; `output: :points` yields the input rows in order, each with its cell's `x`, `y` and `count` under `cx`, `cy` and `count`.

### 5.5 Inline label

**Implemented.** A `:mark_label` node labels the mark from its own data: `text` (`:text`, `:content`, required), `anchor` (`{:enum, [:top, :bottom, :left, :right, :start, :middle, :end, :x0, :x1, :y0, :y1, :outward, :inward]}`, `:geometry`, `:top`), `style` (`{:ref, :style}`, `:style`, `:label`), `dx`, `dy` and `dr` (`:number`, `:geometry`, `0`), `rotate` (`{:one_of, [:number, {:enum, [:tangent, :radial]}]}`, `:geometry`, `nil`), `fit` (`{:enum, [:none, :truncate, :hide]}`, `:geometry`, `:none`); every key `:override`. A `{:field, f}` in its text reads the datum through `Visualize.Data.Table.get/2` — `to_string/1` of the value, nothing for `nil` — which is how a rule labels itself with the deploy's `sha`.

`Visualize.Chart.Mark.generate/3` draws the label as one `text` element per datum — per series for a `:line` or an `:area`, at its last point — in the label's `style` with `class="mark-label"`, `dx` and `dy` added. Each mark type has an *anchor point* `(px, py)`: the datum's position for a `:symbol`, a `:circle` and the end of a `:line` or an `:area`; the centre of the rectangle for a `:rect` and a `:band`; `Visualize.Shape.Arc.centroid/2` about the plot centre for an `:arc` — over the pie's angles, or the datum's own `start` and `end` — and a `:rose`; the first point of the path for a `:path`. The anchor names where the text sits:

| Anchor | Position | `text_anchor` |
|---|---|---|
| `:top` | `(px, py − 4)` | `:middle` |
| `:bottom` | `(px, py + 4)`, `dy: "0.71em"` | `:middle` |
| `:left` | `(px − 4, py)`, `dy: "0.32em"` | `:end` |
| `:right` | `(px + 4, py)`, `dy: "0.32em"` | `:start` |
| `:start`, `:middle`, `:end` | `(px, py)`, `dy: "0.32em"` | as named |
| `:x0`, `:x1` | the midpoint of the rectangle's left or right edge, 4 outside it, `dy: "0.32em"` (#134) | `:end`, `:start` |
| `:y1`, `:y0` | the midpoint of its top or bottom edge, 4 outside it — `:y0` with `dy: "0.71em"` | `:middle` |

The two **polar anchors** (#137) place the label along the ray from the plot's centre through the anchor point — a sector's from its rim, the outer radius outward or the inner inward, any other mark's from its own point — 4 plus `dr` beyond it, rather than along an axis, so a label leaves the sector it belongs to on the sector's own spoke: `:outward` on a `:rose` at `dr: 15` sits at `R + 19` on the sector's ray, `R` its outer radius. The centre is the group's origin for a centred mark (a `:rose`, an `:arc`, §5.6) or in a `:polar` frame, and the plot's middle otherwise. The `text_anchor` follows the side: `:start` right of the centre, `:end` left of it, `:middle` on the vertical. **`rotate`** turns the text about its own position: a number is degrees, `rotate(deg, x, y)`; `:tangent` and `:radial` are computed per datum from the anchor point's angle about the centre — `:radial` along the ray, `:tangent` across it — with the half-turn flip that keeps the text upright on the left (radial) or the lower (tangent) half, the flip every hand-written ring label does and the reason it is written once here; a radial label anchors `:start` on the right and, flipped, `:end` on the left, so it runs toward the centre and ends at the point; a tangent label anchors `:middle`. A `text_anchor` in the label's style replaces both. The same `rotate` on a frame `:label` (§6.1) turns it about its own position, `:tangent` and `:radial` about the plot's middle.

The four **edge anchors** are for the rectangular types, a `:rect` and a `:band`, whose elements carry their bounds: a bar labels itself past its own end, whatever its length, with no second mark. On any other type they fall back to the cartesian anchor of the same side — `:x0` to `:left`, `:x1` to `:right`, `:y1` to `:top`, `:y0` to `:bottom` — so the anchor list stays total.

**A label fitted to its element** (#138). `fit` is what happens when the text is wider than the element it labels: `:none` (the default) draws it as it is; `:truncate` cuts it to the characters that fit and ends a cut label with `…`, drawing nothing when not even one character fits; `:hide` draws nothing for an element the whole text does not fit and the text as it is otherwise. The width is the element's own, per type — the width of a `:rect`'s or a `:band`'s bounds, a `:circle`'s diameter, and for an `:arc` or a `:rose` the arc's length at the label's own radius, the sector's angle times the distance from the label's point to the centre — and a type with no extent (a `:symbol`, a `:line`'s end, a `:text`) fits everything. The text's width is estimated as the legend's is (§4.5): 0.6 × the label's font size per character, the font size the label's style resolves to. It is an estimate — a design cannot measure a glyph — and is stated as one; a label the estimate keeps may still overrun a narrow glyph's neighbour by a pixel. The components of spec/10 §3.3 and §3.4 keep their own rule, seven pixels a character with their own thresholds, which is what their goldens hold.

A `:rule` and an `:x_band` label themselves through their generator's own `label/2` — to the right of the upper end, spec/04 §12.2 — so the annotation is byte for byte the one the generator draws; `anchor`, `dx` and `dy` are not read by those two types, and the label's `style` reaches the generator's text. A `text_anchor` in the label's style replaces the anchor's own.

### 5.6 Rendering

**Implemented.** `Visualize.Chart.Mark.generate/3` is one mark as one `Visualize.IR.Element` group in the plot area's coordinates, its rows those of `Visualize.Chart.Mark.rows/3` (the bound source through the pipeline of §5.4; `[]` when the source is not bound, so a mark renders empty rather than raising), its channels mapped as §5.2 says through `Visualize.Chart.Frame.scales/1`, its style resolved as §3.4 says in the `:resolve` mode:

```
group  style: %{class: "mark mark-<type>[ <class>]", …the resolved style}   — attrs: %{"data-node" => "marks[i]"} when the frame draws with paths: true (§4.7)
├── <element>   one per datum, or one per series for a :line and an :area (§5.2)
└── text  style: %{class: "mark-label", …}                                — the inline label (§5.5)
```

With a `tooltip` node (§5.7) the group also carries `data-tooltip-template` and `data-tooltip-event` when the node gives them, and every element the mark draws carries the datum attributes of spec/10 §12.2 through `Visualize.IR.Element.datum/2` — a per-datum element its own datum's fields, a per-series path (`:line`, `:area`) and the paths of a `:percentile_band` the first row's of their series, so `{series}` names the line under the pointer. A per-series path of a `:line` or an `:area` carries `data-series`, `to_string/1` of its series value, the string the legend's entries carry (§4.5); a mark without the channel carries none (D-77).

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

A mark's *paint* is the colour its elements are drawn in: the style's `fill` for a filled type (`area`, `band`, `x_band`, `rose`, `symbol`, `arc`, `path`, `rect`, `circle`, the bands of a `percentile_band`) and its `stroke` for a stroked one (`line`, `rule`, the median of a `percentile_band`). When the style gives no value for that key, the paint is the theme's `{:series, i}` for the mark's one-based position among the design's marks (§3.3), set on the group as that key, and a `:line` also takes `fill: :none`. **A filled line is the area under it**: a `:line` whose style gives a fill other than `:none` draws, beneath each series' path, one more path — the area from the line down to the baseline, the `y` scale's zero exactly as an `:area`'s `y0` defaults, in the same curve, `class="line-fill"`, `stroke: :none`, its fill the group's — and the line's own path takes `fill: :none`, so the fill is the volume under the plot and never the polygon SVG would close between the curve's ends. A `fill_opacity` reaches the area as it reaches any fill. The generators of a `:rule` and an `:x_band` draw in `current_color` and the brush's fill, which a group's style does not reach, so the stroke keys of the resolved style and the paint are set on the rule's line and the fill keys and the paint on the x-band's rectangle. With a `series` channel each series' element takes the frame's `color` scale's value for its series value when the frame declares one — a slot atom resolved through `Visualize.Theme.resolve/3`, exactly as the legend does — and `{:series, j}` for its position among the series otherwise. A `:rect`'s `value` reaches the colour scale the same way, as the element's `fill`. A `{:field, f}` on any style key is bound per element (§3.4). Every slot resolves in the `:resolve` mode, so the SVG carries `var(--vis-series-1, #3b6fa8)` and a canvas the literal; on a canvas the same tree renders through `Visualize.Backend.Canvas` with literal paints, an inline label as `fillText`, and nothing for a text on the binary stream (spec/09 §4).

**The stroke style** (`stroke_style`, §3.1) says how a mark's stroke sits on its edge, and the mark draws it — it is not an element key, so `Visualize.Chart.Style.resolve/3` drops it and `Visualize.Chart.Mark.generate/3` reads it from the style node once its elements are bound:

| `stroke_style` | Drawn as |
|---|---|
| `:single` (the default) | the element as it is: the stroke centred on the edge, half in and half out, as SVG draws every stroke |
| `:inside` | the element at **twice** its `stroke_width`, clipped to its own shape (`Visualize.IR.Element.clip/3` with `:inside`), so exactly one width lies inside the edge and none outside; the fill is unchanged |
| `:outside` | two elements: the fill alone (`stroke: :none`), then the outline alone (`fill: :none`) at twice the width, clipped to everything *but* its shape (`:outside`), so one width lies outside the edge and none inside |
| `:double` | two elements: the element as it is, then its outline alone at a **third** of the width in the mark's fill colour — the paint when the paint is the fill, else the theme's `background` — which reads as two lines with a gap between |

Inside and outside belong to a **closed** mark — `area`, `band`, `x_band`, `rose`, `symbol`, `arc`, `path`, `rect`, `circle` — where "in" and "out" of the edge mean something; on an open mark (`line`, `rule`, `percentile_band`) they draw as `:single`, and the validator says nothing, since a style stacks onto marks of any type through a name. `:double` draws on every type. The width is the style's `stroke_width`, `1` when it gives none; the second element of an outside or a double stroke carries the same datum attributes as the first, so a tooltip reads either. How a clip reaches each backend is spec/02 §2.1 and spec/09 §2.3, §3.3.

The group is returned untranslated. `Visualize.Chart.Frame.generate/2` places every mark of the design after the grid, inside the group the margins translate — inside the centred group of a `:polar` frame, inside each panel of a `:facet` frame from the rows whose `by` is the panel's value — when it is given `sources:`, and draws the furniture alone without them (§4.7). A `:rose` and an `:arc` mark are about the plot centre in every kind, so `generate/3` translates their group there in a frame that is not polar. A `%Visualize.Chart.Var{}` reached while drawing raises `ArgumentError` naming it, as the frame does.

### 5.7 Tooltip

**Implemented.** A `:tooltip` node asks the mark to carry each datum's fields on its elements, for `TooltipHook` of spec/10 §12 to show under the pointer with no round trip (D-75):

| Key | Type | Facet | Default | Merge |
|---|---|---|---|---|
| `fields` | `{:list, :field}` | `:binding` | `[]` | `:override` |
| `template` | `:string` | `:content` | `nil` | `:override` |
| `event` | `:name` | `:binding` | `nil` | `:override` |

`fields` names the columns written, in that order, each read from the datum through `Visualize.Data.Table.get/2`; `[]` writes every column of the datum in `Enum.sort/1` order of its keys. The datum is the row the element was drawn from — after the mark's transforms, so a `:stack` row's `key`, `y0` and `y1` are fields a tooltip can name (§5.4). A field named in `fields` is checked against the source's declared `fields` when the mark reads the source directly, as a channel is (§5.4). `template` is the `data-tooltip-template` of the group — `{field}` placeholders, spec/10 §12.2 — and `event` its `data-tooltip-event`, the name a click pushes. The node changes nothing the mark draws: only attributes are added (§5.6), so a design without one renders byte for byte as before.

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
| `rotate` | `{:one_of, [:number, {:enum, [:tangent, :radial]}]}` | `:geometry` | `nil` | `:override` |
| `id` | `:name` | `:content` | `nil` | `:override` |

`rotate` turns the text about its own position — degrees, or `:tangent`/`:radial` about the plot's middle with the upright flip — as a mark label's does (§5.5, #137); it composes with an axis title's own rotation.

`{:axis, s}` anchors the label as the title of the axis drawn for scale `s`; `s` is a scale reference and is checked as one. `{:frame, c}` anchors it at a corner of the plot area and `{:data, [x, y]}` at a point of the data (§6.3).

`id` is the label's identity in a stack (§8.2), read exactly as a mark's is: a higher layer's label with the same `id` replaces this one in place. A label without one appends. Nothing renders from it.

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

**Position** (§3.1). Each placement above has a *baseline* — the `dy` in its row, or none — and an *outward direction*: away from the plot for a title, a subtitle (up), a caption and a bottom axis title (down), a top axis title (up), a left or a right axis title (further from the plot, which in the rotated frame is `−y`); into the plot for a corner, so `{:frame, :top_left}` runs `(+x, +y)` and `{:frame, :bottom_right}` `(−x, −y)`; none for a data anchor. The label's style says how the text sits on that point: `vertical_align` replaces the baseline — `:baseline` no `dy`, `:middle` `"0.32em"`, `:top` `"0.71em"` (the text hangs below its point), `:bottom` `"-0.25em"` — and leaves the placement's own when absent; `margin_x` and `margin_y` move the point along the outward direction, each by its sign, so a caption with `margin_y: 6` sits 6 further down and a corner label 6 further in; `text_angle` rotates the text about the point it sits on, a `rotate(angle, x, y)` added after any transform the placement has, so a left axis title turns about its own point in its rotated frame. A label's `dx` and `dy` are added as before, the signed one-off nudge; the margins are what a named style sets for every label it reaches. The same four keys reach a mark's inline label (§5.5) — outward is the label's `anchor`: `:top` up, `:bottom` down, `:left` left, `:right` right, `:start` right, `:end` left, `:middle` nowhere — and `text_angle` alone reaches an axis's tick labels through the axis's style (§4.4), each turned about its own anchor, which is how a category axis with long names angles them; a legend's entries take none of the four.

An axis title follows the side of the first axis that names its scale; with no axis on the scale, `x` is taken as `:bottom`, `y` as `:left`, and any other name as `:bottom`. A data anchor maps `[x, y]` through the scales named `x` and `y` in a `:cartesian` or `:facet` frame (the first panel), through `angle` and `r` in a `:polar` frame — `(R sin a, −R cos a)` from the centre — and through the projection in a `:geo` frame, where the pair is `[longitude, latitude]` and a point the projection clips is not drawn. A `text_anchor` in the label's style replaces the anchor's own.

## 7. Variables and slots

### 7.1 Variables

**Implemented.** `Visualize.Chart.var/1` builds `%Visualize.Chart.Var{name: name}`, a term allowed wherever a value can appear — a style value, a channel, a whole node (`style: var(:style)`, `margin: var(:margin)`) — and, inside a text, as `#{var(:name)}`. The term carries only the name; the default is declared once under `vars` (§2.4), so two fragments cannot disagree about it (D-59). The validator requires every variable used to be declared (`{:undeclared, :var, name}`) and does not type the value, which is unknown until application: the value is typed by the validator at the path where the variable stood, once `Visualize.Chart.apply/2` has put it there (§7.3). Resolution is **single level**: the value a variable takes at application MUST NOT itself be a variable, and one that is is `{:var_binding, name}` at every path where the variable stood (§7.3, §10.1). A variable *nested inside* a value another variable is bound to is not resolved either, and needs no rule of its own — the `vars` declarations are dropped before validation, so the validator finds it as `{:undeclared, :var, name}` at its path; only the direct case was silent.

**A text interpolates.** A `:text` is one string — `"Uptime for #{var(:host)} over 24h"` — in which `#{var(:name)}` stands for a variable and `#{field(:name)}` for the datum's field a mark's label reads (§5.5); `\#{` is a literal `#{`. `Visualize.Chart.Text.parse/1` reads it into parts and `Visualize.Chart.Text.unparse/1` writes parts back, the two inverse, so a text is one value whichever form holds it: its variables stand *at the key* (`labels[0].text`, never `labels[0].text[1]`), each named once however many holes name it, and application writes the bound value into the string as `to_string/1` gives it. A hole that names neither `var` nor `field`, or a `#{` never closed, is `{:template, reason}` at the key. The list-of-parts form an earlier draft wrote is read wherever a text is read and is written back as the string (§9), so no document goes stale and no second form survives a round trip.

| Function | Contract |
|---|---|
| `Visualize.Chart.Text.parse/1` | a text as its parts — strings, variables, fields; a list is already parts; `{:error, :unterminated}` or `{:error, {:hole, text}}` for a string that does not read |
| `Visualize.Chart.Text.parse!/1` | the same, raising — for a text already validated |
| `Visualize.Chart.Text.unparse/1` | parts as the string: `#{var(:name)}`, `#{field(:name)}`, a literal `#{` escaped; a string as it is |
| `Visualize.Chart.Text.template?/1` | whether a string carries a hole |
| `Visualize.Chart.Text.lines/1` | parts as lines: the parts split at every newline in a string part, `[[]]` for an empty text |

**A text has lines.** A newline in a text breaks it: `"Uptime\n24 h"` is two lines, and so is a text whose variable resolves to a string with a newline in it, since the split is of the resolved parts. Every text the frame draws — a frame label (§6.3), a mark's inline label (§5.5), an axis title, a legend title — draws its lines as one `text` element holding one `tspan` per line, each at the text's `x` and the first at its `y`, the rest each `line_height` em below the last (§3.1); a text of one line is drawn as it was, a `text` with its content and no `tspan`, so nothing changes for a text that has no newline. `Visualize.Chart.Frame.generate/2` does it in one pass over its tree once the labels are placed, so no placement has to know about lines; a canvas draws one `fillText` per line, stepping by `line_height × font_size` (spec/09 §3.3). The lines are left-, centre- or right-aligned together by the text's `text_anchor`, since each `tspan` restarts at `x`.

### 7.2 Sources as slots

**Implemented.** A source declaration is a slot: the fields the design reads are the contract, and binding maps slot to source at application — "made for `{a, b, c}` but showing `{d, e, f}`" is one rebinding, `Visualize.Chart.apply/2` with another `sources:` map. Application takes a *pool* of named sources; a slot binds to the pool's entry under its own name, else under its `default`, and a slot with neither is unbound (§7.3). A dashboard picker validates a candidate source against `fields` before offering it, by the rule application applies: every declared field is a key of some row of the source, in either spelling (D-52).

### 7.3 Application

**Implemented** (work item 5 of #53, D-65). `Visualize.Chart.apply/2` takes a design — a `%Visualize.Chart{}`, or a design map that goes through `Visualize.Chart.from_map/1` first, so an invalid map is its errors — and the options `sources:` (the pool, a map from name to source, `%{}`), `vars:` (a map from variable name to value, `%{}`) and `theme:` (a `%Visualize.Theme{}`, as `Visualize.Chart.Frame.new/2` takes it), and returns `{:ok, applied}` or `{:error, errors}` — the errors of §10.1 by path, ordered by path — in three steps. Each step reports every fault it finds and a step with faults stops before the next, so resolution faults are never mixed with binding faults, nor either with the validator's.

1. **Variables resolve.** Every `%Visualize.Chart.Var{}` in the design — a value, a text part, a whole node — is replaced by the value `vars:` gives its name, else by the declared `default` (§2.4); a variable with neither is `{:unresolved, :var, name}` at the path of its use, and every use is reported; a variable whose value — from `vars:` or from its own declared default — is itself a `%Visualize.Chart.Var{}` is `{:var_binding, name}` at every path where it stood, since resolution is single level (§7.1) and a second pass would let a stored design bind a variable to a variable and never settle. A name in `vars:` that no declaration carries is `{:undeclared, :var, name}` at `[:vars, name]`. In a text a resolved part that is a number or an atom is written with `to_string/1`, so `["n = ", var(:n)]` with `n: 3` reads `["n = ", "3"]`; every other value stands as it is, where the validator types it. The `vars` declarations are dropped: the concrete chart has none and no variable anywhere in it, which is what `Visualize.Chart.Frame.new/2` requires (§4.7).
2. **Slots bind.** Each slot of `sources` (§2.3) binds to the pool's entry under its own name, else under its `default`; a slot with neither is `{:unbound, :source, name}` at `[:sources, name]`. Pool entries that no slot names are ignored, so one pool serves many designs. A bound source is anything `Visualize.Data.Table.rows/1` reads and is kept as given — the frame reads it through `rows/1` as it does any source, and a rank-1 `Nx` tensor stays a tensor for the dense path (D-52). Every field the slot declares MUST be a key of some row of the bound source, in either spelling; a field no row carries is `{:missing_field, field}` at `[:sources, name]`, one error per field, which is the "made for `{a, b, c}`" contract failing loudly (§7.2). A source with no rows binds without a check. A field a channel, a text or a transform reads is checked against the slot's declaration by the validator (§5.4), so a field the design reads and the source lacks is caught at one or the other.
3. **The result validates and its frame is realised.** `Visualize.Chart.Validator.validate/1` runs over the resolved, bound design — the value a variable took is typed here, at the path where it stood — and `Visualize.Chart.Frame.new/2` builds the frame over the bound sources, inferring every `:auto` domain from the bound columns (§4.3). A value a scale cannot take, or a theme name `theme:` does not resolve, raises `ArgumentError` from the frame as it does for any chart: those are faults of the data or the consumer, not of the binding.

The result is a `%Visualize.Chart.Applied{}` (§14.10): `chart`, the concrete `%Visualize.Chart{}` — no variable anywhere in it, `vars` empty, the slot declarations kept as the data contract, everything else as the design wrote it; `sources`, the bound sources by slot name; and `frame`, the realised frame, whose `Visualize.Chart.Frame.scales/1` is the escape hatch. `Visualize.Chart.render/2` draws it: `Visualize.Chart.Frame.render/2` of the frame over the bound sources, with the same options. The design, its fragments and a binding are storable; the applied chart holds data and is not — it has no map form and no JSON form.

## 8. Composition and the stack

**Implemented.** Two operations close over fragments, and both are total in the sense that matters: their result is a fragment, so a stored composition is a part of another composition and a stored stack is a layer of another stack. `Visualize.Chart.compose/2` is the *union* — it assembles one design from disjoint parts and reports a name two fragments declare differently as a fault. `Visualize.Chart.stack/2` is the *cascade* — it layers a house theme, a shared frame and a panel's own overrides, and a name two layers declare differently is the higher layer's word. Neither validates nor defaults: the result becomes a chart through `Visualize.Chart.from_map/1` or `Visualize.Chart.apply/2`, which is where it MUST validate.

### 8.1 `compose/2`: the union

**Implemented** (work item 5 of #53, D-65). `Visualize.Chart.compose/2` merges two fragments — design maps, or `%Visualize.Chart{}`s taken as their maps — into one map by the merge rule of every key (§1.5), the second over the first, and returns `{:ok, map}` or `{:error, errors}`; `Visualize.Chart.compose/1` folds a list left to right, so `compose([a, b, c])` is `compose(b, c)` over `compose(a, b)`, and `compose([])` is `{:ok, %{}}`. A fragment is any map with the design's keys: it need not carry `version` or `frame`, and nothing is validated or defaulted — the result is a fragment too, and becomes a chart through `Visualize.Chart.from_map/1` or `Visualize.Chart.apply/2`, which is where it MUST validate.

For each key present in either fragment, by the key's spec in the node kind being merged:

- `:concat` — the later fragment's elements after the earlier's: `marks`, `labels`, `axes`, `transforms`. Elements are never merged with each other. A key either fragment gives as a struct is not a list, so there is nothing to append and the later fragment's value is taken whole (§1.4); a variable at a `:concat` key is not a disagreement, because a collection has no names for two fragments to claim.
- `:union` — the union of the two name-keyed maps: `sources`, `vars`, `styles`, `scales`. A name in both with equal values is taken once; with different values it is `:conflict` at the name's path (`[:styles, :series]`, `[:frame, :scales, :x]`), every conflict reported. A house style sheet composes with a chart's own styles and disagrees loudly, never silently. A key either fragment gives as a **struct** — `styles: var(:sheet)`, the documented way to leave a whole node to application (§1.4, §7.1) — carries no names to unite, so it is read as one value: equal in both fragments it is taken once, and different it is `:conflict` at the key's own path (`[:styles]`, `[:frame, :scales]`) with the later fragment's value in the result. A variable at a `:union` key says *this whole declaration is somebody else's*, and a fragment that also declares part of it is the disagreement `compose/2` exists to report (D-92).
- `:override` — the later fragment's value, except that a key whose type is a node — `{:node, kind}`, or a `{:one_of, …}` that admits one, such as `theme` — given as a map by both fragments composes key by key under that kind's rules: `frame` merges, its `scales` union, its `axes` concatenate, its `size` is the later's; `meta` merges likewise. A key the schema does not know is `:override`.

A key present in one fragment alone is taken as it is. Over a list, `:concat` and `:union` keys compose associatively and `:override` keys last-wins, so the order of the fragments is the order of their marks and labels and the precedence of their scalars: a standard label set, a house style sheet and a chart-specific fragment compose in that order into one design.

### 8.2 `stack/1`: the cascade

**Implemented** (#97, D-81). `Visualize.Chart.stack/2` merges two fragments as a cascade: for every key the higher layer wins. `Visualize.Chart.stack/1` folds a list left to right, the later layer the higher, so `stack([a, b, c])` is `stack(stack(a, b), c)`; `stack([])` is `%{}` and `stack([a])` is `a` itself. A layer is a design map or a `%Visualize.Chart{}` taken as its map, exactly as a fragment of `compose/2` is, or a `{name, layer}` pair whose name `stack/1` ignores and `Visualize.Chart.explain/1` reports (§17.1), so the two functions take the same list.

The cascade cannot fail — there is no disagreement for it to report, since a disagreement is what it exists to resolve — so `stack/1` and `stack/2` return the fragment itself and not an `{:ok, fragment}` tuple. That is the second difference from `compose/2` (§8.3) and it is what makes `stack([a]) == a` an equality rather than a comparison of wrappers.

For each key present in either layer, by the key's spec in the node kind being merged:

- `:concat` — a higher element whose *identity* equals a lower element's replaces it in place, keeping the lower's position; every other higher element follows the lower's, as `compose/2` appends them. Identity is what lets a layer restyle the shared frame's x-axis rather than draw a second one, and it is defined below.
- `:union` — the union of the two name-keyed maps; a name both layers declare is the **higher layer's entry**, where `compose/2` reports `:conflict`. The entry is taken *whole*: a style the higher layer redeclares replaces the lower's rather than merging into it, so the result is a style some layer actually wrote. Derivation within a style is `extends` (§3.5), which is the key-by-key operation on styles and is unrelated to the cascade. A key either layer gives as a **struct** carries no names to unite (§1.4), so it is the higher layer's value whole, exactly as the `:override` rule below reads it — the cascade resolves the disagreement `compose/2` reports (D-92).
- `:override` — the higher layer's value, except that a key whose type is a node — `{:node, kind}`, or a `{:one_of, …}` that admits one — given as a map by **both** layers cascades key by key under that kind's rules, exactly as `compose/2` recurses: a panel fragment's frame adds its own scales and axes to the shared frame's and takes precedence on the frame's scalars. A node either layer gives as anything else — a name, a variable — is the higher layer's value whole. A key the schema does not know is `:override`.

**Element identity** (#98, D-82) is what a `:concat` key's elements are matched by:

| Element | Identity |
|---|---|
| a mark (§5.1) | its `id`, when it declares one |
| a label (§6.1) | its `id`, when it declares one |
| an axis (§4.4) | `{scale, side}`, always: two axes drawing one scale on one side *are* one axis |
| a transform (§5.4) | none: a data pipeline is a sequence, and a step of it is not a thing a layer names |

An element with no identity appends, so a stack of layers that name nothing behaves exactly as the append of §8.1 and the identity rule costs a design that does not use it nothing. Identity matches only *within one key* — a mark and a label with the same `id` are different elements — and nothing renders from an `id` or from an axis's identity: they are the algebra's names for elements, and the SVG carries neither (D-77 is what names a series in the document).

The schema does not require an `id` to be unique — a fragment is not a whole design, and uniqueness is only meaningful once the layers are known — so where the cascade merges two lists it reads the lower's elements and the higher's as one sequence and collapses duplicates in both: each identity keeps its first position and its last value. A key only one layer carries is passed through untouched, as every rule of the cascade passes such a key through, so a fragment that is never stacked is never rewritten.

A matched element is replaced **whole**, not merged key by key, for the reason the `:union` rule is: a mark's meaning is its whole node, and a higher `%{id: :series, type: :area}` merged over a lower `:line` would keep the line's channels under the area's type and draw something no layer wrote. A layer that wants to change one key of a mark writes the mark.

The result of that is that the stacked list is ordered by each identity's *first* appearance across the layers and carries its *last* value, whichever way the layers are grouped, which is why the cascade stays associative over `:concat` keys.

A key present in one layer alone is taken as it is. `:concat`, `:union` and `:override` keys all cascade associatively **where every layer gives a mergeable key as a map** — a `:union` key as a name map, a node key as a node — which is every layer that declares anything at them. So a stack is a list of layers in precedence order and the fold over it may be built in parts: a house sheet stacked with a frame is a layer of the panel's stack.

The exception is a layer that gives a mergeable key as a **struct** — a whole-node variable (§1.4). That layer is *replacing* the declaration rather than merging into it, and a replacement in the middle of a stack is not recoverable by regrouping: `stack([a, b, c])` is the left fold, which is what `Visualize.Chart.stack/1` computes and what `Visualize.Chart.explain/1` reports, while `stack(a, stack(b, c))` may differ where `b` replaces a key `a` declares and `c` declares it again. Carrying the erasure through the regrouping would mean an intermediate result that is not a fragment, which §8.2 exists to rule out. This is the price of admitting a whole-node value at a key whose rule is to merge, and it is the second reason `compose/2` reports the same pair as a `:conflict` (§8.1) instead of resolving it (D-92).

### 8.3 Why there are two operations

**Implemented.** The two are not one operation with a flag, and neither is the other's default.

`compose/2` assembles one design from parts that are *meant to be disjoint* — a standard label set, a source list, the fragments a builder function returns (§16) — and a name declared twice there is a mistake: two authors believing they own `:series` produce a design neither of them wrote, silently, and the `:conflict` is the whole value of the operation. `stack/1` layers designs that are *meant to overlap* — a house theme, a shared frame, a panel's overrides, a dashboard's per-panel edits — and a name declared twice there is the point: the higher layer is saying what it is for.

They agree exactly where the fragments are disjoint. Over two fragments that declare no `:union` name and no `:override` key in common, `stack(a, b)` is the map of `compose(a, b)`, which is the property that holds the two definitions together as the schema's merge rules grow.

## 9. Version and migration

**Implemented.** `version` is required and is the integer `Visualize.Chart.Migration.current/0`, which is `1`. `Visualize.Chart.from_map/1` calls `Visualize.Chart.Migration.migrate/1` before validation: a design at the current version passes through unchanged; one at an older version is stepped forward one version at a time through the migration registered for each step, so a stored design never goes stale; a version above the current one, or that is not an integer, is `{:error, [{[:version], reason}]}` with `{:unsupported_version, v}` or `:required`. No migration is registered yet — the hook exists so that the first schema change ships with its step, not with a breaking change. Within a version, `migrate/1` also returns the design in the shape this library *writes* (`Visualize.Chart.Migration.canonical/1`): a `:text` given as a list of parts becomes its string form (§7.1), which is a canonicalisation and not a version step, since the two forms are one value and both read. Every migration MUST be pure and MUST produce a map that validates at its target version.

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
| `{:var_binding, name}` | the value the variable took at application is itself a variable (§7.1, §7.3) |
| `{:unbound, :source, name}` | a slot with no source in the pool under its name or its default (§7.3) |
| `{:missing_field, field}` | the bound source has no row carrying a field the slot declares (§7.3) |
| `:conflict` | a `:union` key declared with different values by two fragments (§8) |
| `:cycle` | a style that reaches itself through `extends` (§3.5) |

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
| `{:paint, :area}` (a colour, §3.2) | `{"$paint": "area"}` |
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

**Implemented.** The render target is a compiler decision per mark, never a design property beyond the `render` override (§5.1). For each mark, in design order: `render: :svg`, `:canvas` or `:binary` is taken as given; `:auto` (the default) counts the rows the mark draws over the bound sources — a `:text` mark is `:svg` whatever `render` says, since it draws text alone and the binary stream carries none (spec/09 §4.4, #134) — — `Visualize.Chart.Mark.rows/3`, the points of a path mark, the elements of a per-datum one — and picks `:svg` when the count is at most the ceiling, else `:binary` when `Visualize.Backend.CanvasBinary.available?/0` (Nx is loaded) and `:canvas` otherwise. The ceiling is the `ceiling:` option of `compile/2`, `1000` by default: the ~1,000 DOM-node ceiling of [00-prior-art](00-prior-art.md) §3.2. Rebinding a slot to a denser source and recompiling moves a mark from SVG to canvas without touching the design. `Visualize.Chart.Compiled.targets/1` reports `{target, points}` per mark, the target chosen and the count it was chosen from, so `[{:svg, 120}, {:binary, 5000}]` is a chart whose second mark went to the binary path.

Static furniture is always SVG. Layering is fixed — the canvas layer under the SVG layer, and mark order within each layer — and text stays in the SVG layer: a canvas-layer mark's inline label (§5.5) is drawn as SVG text in the mark's group, since the canvas has no text a stylesheet or a DOM hit can reach (spec/09 §4.4). The marks of a `:facet` frame are drawn per panel inside the `:panels` region and stay in the SVG layer whatever their count: their target is reported as `:svg`. One node of style resolves for both layers (§3.4): the SVG layer in `:css`, the canvas layer in `:literal`.

### 12.4 Rendering per tick: the hybrid chart map

**Implemented.** `Visualize.Chart.Compiled.render/2` takes the compiled chart and the sources by slot name — the map `Visualize.Chart.Applied` holds, anything `Visualize.Data.Table.rows/1` reads under each name; a slot the map omits draws nothing, and nothing is re-validated — realises the frame over them, runs every dynamic closure, and returns the chart map of `Visualize.Backend.Hybrid` (spec/09 §6) with one key added for the SVG layer's moving part:

| Key | Value |
|---|---|
| `width`, `height`, `margin` | the frame's size and margin |
| `static` | the design's `<defs>` (§2.7) first — the gradients it declares and the filters its marks' effects need, computed once at compilation over every mark rendered in `:css`, so a `url(#id)` on either SVG layer resolves against the static `<svg>` on the page (#356) — then the static regions' elements, in region order; the same list on every tick; `Visualize.Backend.Hybrid.render_static/1` draws it once |
| `dynamic` | the canvas layer: one group per mark whose target is `:canvas` or `:binary`, in mark order, in `:literal` style — every `{:paint, name}` the first stop's colour, as §3.4 says of a literal render (#356) — with its text children removed, in the centred group of a `:polar` frame; `nil` when no mark targets the canvas |
| `dynamic_style` | `%{}`: every element carries its own resolved style |
| `canvas_format` | `:binary_base64` when any canvas-layer mark targets `:binary`, else `:json` — one canvas layer, one format |
| `dynamic_svg` | the SVG layer's dynamic regions, in region order: the `:svg` marks, the moving axes, grid, legend and labels, the facet's panels, and the inline labels of the canvas-layer marks |

`Visualize.Chart.Compiled.static/1` is the static SVG string, `Visualize.Backend.Hybrid.render_static/1` of the `static` list, rendered once at compilation and cached. `Visualize.Chart.Compiled.tick/3` is the per-tick payload: `{payload, compiled}` where `payload` is a map with `svg`, the `dynamic_svg` list rendered as one SVG root of the same shape as `static/1` — the consumer stacks the three layers, the canvas under the static SVG under the dynamic SVG, each positioned at the container's origin; `canvas`, `Visualize.Backend.Hybrid.render_dynamic/1` of the map, `""` when there is no canvas layer; `canvas_format`; `incremental`, the payload of §12.5 or `nil`; and `bytes`, the byte size of what a tick transmits — `svg` plus `canvas`, or `svg` plus the incremental payload's `binary` — which is what the measurement of §12.6 reads. The returned compiled chart holds the tick's sources and the window state; a design without a viewport returns it otherwise unchanged.

`Visualize.Chart.Compiled.svg/2` is the one-string form: the frame's group of §4.7 assembled from the cached static elements — the defs first — and the tick's dynamic ones in the frame's own order — the grid, the marks, the axes, the legend, the labels — rendered through `Visualize.Render.to_string/2` as SVG. A region's elements are built as the frame builds them: a mark's group through `Visualize.Chart.Mark.generate/3` with its paints resolved for the mode and its texts' lines split (§4.7), so a compiled mark is the frame's mark (#356). When every mark targets `:svg` it is byte for byte `Visualize.Chart.Frame.render/2` over the same sources, which is how the split is held to the frame; a canvas-layer mark is absent from it, since it is the SVG layer.

### 12.5 The viewport: a streaming window

**Implemented.** A frame `viewport` (§4.6) — `scale`, a `{:ref, :scale}`, and `span`, a number in the scale's domain units, seconds for a `:time` scale — makes the compiled chart *stateful*: the named scale is windowed to `[hi − span, hi]` on every tick, where `hi` is the newest value the marks bind to it over the tick's sources — the greatest value of every channel naming the scale, as inference reads them (§4.3) — or the `now:` option of `tick/3`, which is how a clock, or a test's fake clock, drives the window. The windowed scale moves (§12.2): its axis and grid are dynamic regions. A mark that reads the windowed scale draws the rows whose reading lies within the window, so nothing is drawn beyond the plot area; the reading is the channel's field before the mark's transforms, and a mark whose channel is a transform's output draws every row its pipeline yields.

When the chart has a binary canvas layer (`canvas_format` `:binary_base64`, §12.4 — the incremental record of spec/09 §5.5 carries binary streams and nothing else; a `:json` layer is sent whole per tick), the window slides it through `Visualize.Incremental` (spec/09 §7), whose state the compiled chart holds between ticks: the first tick is the full-redraw payload of `Visualize.Incremental.initial_render/1`; each later tick scrolls by `dx = (hi − hi₀) × width / span` pixels, with `width` the plot's, through `Visualize.Incremental.scroll/2`, so the payload is the `canvas_incremental` event of spec/09 §7.3 — `"scroll_x"` with the exposed strip filled, `"full"` when the window jumped by half the plot or more, `"none"` when it did not move. The incremental canvas is the *plot area*: its size is `plot`, it sits at `(margin.left, margin.top)` of the container, and the marks are drawn in plot coordinates — the exposed strip is at the canvas's edge (spec/09 §5.3), and only a canvas whose right edge is the plot's right edge exposes the newest points there. Into each exposed region the compiled chart draws **the rows under the strip and three neighbours each side** (#332, D-108): the region's `x` and `x + width` in plot pixels are mapped back through the windowed scale to a range of the scale's units, each canvas mark's source is restricted to the rows whose reading lies within it, widened by the three rows before and the three after (the compiled chart's window module, `strip/6`, a private helper), and the mark is built over those — a path enters and leaves the strip on its own line, since a `:monotone_x` curve reads one neighbour each side and a `:basis` curve two, and the client's clip to the region's bounds (spec/10 §9.2) removes the overhang. The full redraw draws the whole window. A scroll payload is therefore the strip's — a few kilobytes against a full redraw's hundred — which is the saving the incremental path exists for; the compiled chart once drew the whole window into every strip, so a scroll cost what a full redraw cost and saved the client's redraw alone. The state's `data` is empty and its accessors are never consulted: the builder receives the region as `clip_region` and reads the rows itself. The copy-and-shift holds only while every other scale the canvas marks read is fixed: with an inferred one the old pixels are wrong once the domain moves, so every tick is a full-redraw payload, and `dynamic_regions/1` names the scale to fix. The SVG layer of a viewport design is per-tick SVG as §12.4 says, its `:svg` marks windowed alike.

**An inferred domain eases** (#360). A scale with a `transition` (§4.3) and a domain that moves — `:auto`, or `:auto` at one end — keeps a *shown* domain in the compiled chart between ticks, beside the viewport's state: on the first tick the shown domain is the inferred one; on a later tick whose inferred extent differs, the shown domain is retargeted — it eases from where it is toward the new extent over `duration` milliseconds along `easing`, each tick's frame drawn at the shown domain through the escape hatch (§4.3), so the marks, the axis and its grid agree at every intermediate frame; a domain that has not changed costs nothing and a scale with no transition jumps as before, byte for byte. The clock is `tick/3`'s `at:` option, milliseconds, `System.monotonic_time(:millisecond)` when absent, so a test drives the easing as it drives the window. `shrink_after` is hysteresis: an inferred extent that lies *inside* the shown target is a shrink, and a shrink is taken only once every inferred extent for `shrink_after` milliseconds has stayed inside — a passing spike does not pump the axis — while a grow is taken at once and clears a pending shrink. Only a numeric domain eases (`:linear`, `:log`, `:power`, `:sqrt`, `:symlog`, `:radial`); a `:time` scale, or a fixed domain, draws its target as it is. `Visualize.Chart.render/2` of an applied chart — one frame, no state — is unchanged.

### 12.6 Measurement

**Implemented.** The claim of the split is a smaller payload per update, and it is measured, not asserted. The measurement is `Examples.Compare.run/3` (#322, #328): a gallery chart run headless through each backend for a fixed count of ticks — *SVG*, the old path, `Visualize.Chart.render/2` of the design applied to each tick, one SVG string; *Canvas*, the compiled path, `static/1` once and the tick payload's `bytes` per tick; *Incremental* for a streaming design — each tick timed, reported as the mean render time and bytes per frame with the static bytes beside them. It runs from every chart page's drawer (below) and from `/performance` (`ExamplesWeb.PerformanceLive`), the comparison view over the gallery: a chart picked from the gallery and compared, or every design compared in one table, each in a task off the view's process. The page once held six hand-built chart types of its own with their renderers and a *Compiled* mode over a line design of its own (`compiled_design/1`, `measure_compiled/1`); the gallery's designs are the charts now, and those went with #328. The numbers for the first measurement are recorded on issue #63; the same measurement after the binary stream shrank (spec/09 §4.3.8–4.3.10, D-73 and D-74) is recorded on issue #73, where the acceptance was `render: :binary` below `render: :svg` at 200 points, which #63 had found the other way round. **A frame is rendered off the view's process** (#323): the page never renders a frame in its LiveView — on a tick it snapshots the frame's inputs and renders under `Examples.TaskSupervisor` (`Task.Supervisor.async_nolink/2`), pushing the result when it arrives; one frame is in flight at a time, a tick that finds one is counted *Skipped* and the next tick is scheduled on completion, so the FPS is the lesser of the target and what the render allows and the mailbox is never more than a tick deep; *Stop test* terminates the task and a late result is ignored. The page had rendered in its own process, so at 50,000 points on SVG every click waited behind ten-second frames.

**The gallery's Canvas mode is the split** (#268). The chart page (`examples/lib/examples_web/live/chart_live.ex`) offered *Canvas* as the whole chart — furniture included — through the binary stream, which drops `:line` and `:text` by design (spec/09 §4.4), so the axes lost their ticks and labels and a newcomer read the canvas backend as broken. For a chart that is a design, Canvas mode is now the split of §12: `Examples.Charts.Design.hybrid/2` compiles the applied design with a ceiling of one — every mark of more than a point to the binary canvas — and returns the compiled chart's static SVG (`Visualize.Chart.Compiled.static/1`) and the tick's canvas stream (`Visualize.Chart.Compiled.tick/2`), which the page layers as the performance page does: the canvas under, the static SVG over with no pointer events, both the frame's size. Every chart of the gallery is a design (#335, #130), so the whole-element binary the page once kept for a chart that was not yet one is gone with the charts that needed it. The code sample under the button is the compile-and-render call the page makes — opening with the module's `sample_code/0`, the `Visualize.Chart.Build` calls that fold to the `design` the split then takes, so the sample never starts from a value the page has not shown (#318). Beneath the code, a design chart shows **its design as data**: the folded map of `design/1`, pretty-printed as the Elixir term, with a note that `Visualize.Chart.to_json/1` is the same map as JSON — the stored form the builder and a host exchange (§1, §9), so a reader sees what the calls fold to and what a deployed design carries. The page says above the sample that the design is the thing to copy: the Build calls fold to a map and the map is the chart, applied to rows and rendered by the library on any backend (§16).

**The High-Performance page keeps the scroll contract** (#292, spec/09 §5.3). `ExamplesWeb.HighPerformanceLive` (`/high-performance`) streams incremental frames through `Visualize.Backend.CanvasIncremental`, and with *Incremental ON* each of its series drew as short discontinuous segments following its profile: the strips were the sine series at a phase animated per frame and the random line slid one sample — a fraction of a pixel — per frame, so nothing the hook copied was the picture the strips joined. The page's animation is now the scroll alone. Every series is a function of an absolute sample index at a whole number of samples per pixel — `points_per_series` is `samples_per_px × inner_width + 1` for the density nearest the requested total, so the x scale maps a sample to exactly `1 / samples_per_px` pixels — and the frame keeps an `origin` in samples that advances by `scroll_delta × samples_per_px` per frame: a series' value at column `i` is `f(origin + i)` with no phase term, and the random line drops and appends that many samples. The full render and a region render share the one series function, so a strip's y values equal the full render's at the same columns, which `examples/test/examples/scrolling_series_test.exs` holds since #327 (the page's own stream test went with the page).

**Every chart page measures itself** (#322, #326). Under the chart on `/chart/:slug` a **performance drawer** — one line, *Performance ▸*, collapsed by default so the gallery stays a gallery — opens to the controls and the metrics of the High-Performance page applied to the chart in front of the person: a **backend** — *SVG*, the chart rendered whole per tick (`Examples.Charts.Design.render/2`), and *Canvas*, for a design the split, `Visualize.Chart.compile/2` once and `Visualize.Chart.Compiled.tick/2` per tick with `render: :binary` pushed to the `CanvasBinaryChart` hook as `canvas_update` (the furniture the compiled chart's static SVG, any SVG-layer marks the tick's `svg`), with no other path, every chart being a design — a **Target FPS** slider, **Flow control** where the backend acks (the binary canvas does, spec/10 §8.2; an SVG frame travels in the LiveView diff and no ack exists for it, so its run holds nothing and shows no ack metrics), *Start* and *Stop*, and the metrics rows. **Every run has a data rate** (#361), and the frame rate never drives the data: for a chart that animates by tick the rate is **ticks per second** — the rate its rows change at, 20 by default, the page's own cadence — and the run keeps a tick counter advanced by the whole arrivals `Examples.Run` accounts at that rate (its `tick/3` at density one), so a run's frame is the chart at the run's tick — the rows its `design/1` binds for `animation_tick: n`, every chart module having one — however often frames are drawn; a frame with no new tick redraws the same rows (with a scale transition, §12.5, the eased scale still moving). The frame is rendered in a task by `Examples.Run`. **The page has one frame loop** (#362): its *Animate* button starts and stops that run on the page's backend — the backend buttons above the chart and the drawer's are one choice, `Frames.backends/1` of the chart — so no frame is ever rendered in the LiveView process, one frame is in flight at a time and the view answers a click while a frame renders; the tick counter beside the button is the run's. A **still** chart — before a run, after one stops, on a palette, backend or hex-size change — is rendered the same way, once, in a task (`{:still, frame, state, design}`), and the page shows the last frame it has, the run's while a run is going and the still one otherwise; the design-as-data panel is computed with it. On a disconnected mount, the first HTML, the still frame is rendered in place, since there is no interaction to block. The *Data rate* slider is there for every chart, in the chart's unit — `ticks/s` (1–100) or, for a streaming design, `samples/s per series` (10–5000, below) — and the point metrics with it: *Pts/frame* (the rows the frame drew), *Total points* (the rows the chart holds, a streaming design's window), *Pts/s* (the measured rate times the points a tick moves) and *Mode*. **Compare** runs the chart headless through each backend for a fixed count of ticks in a task (`Examples.Compare.run/3`) and tables the mean render time and the bytes per frame beside the static bytes, per chart — the measurement of the paragraph above, for any chart of the gallery. **A streaming design streams in the drawer** (#327). A chart module whose `stream?/0` is true — *Scrolling series*, `Examples.Charts.ScrollingSeries`, the High-Performance chart as a design: an area and four lines over a cartesian frame with a `viewport` on `x` (§12.5), every series a function of its absolute sample index at a whole number of samples per pixel column (`Examples.Scroll`), the random line a hash of its sample — offers a third backend, **Incremental**: the compiled chart ticked with `now:` the window's upper end, its `incremental` payload pushed to a `CanvasIncrementalChart` hook sized to the plot at the margin's offset under the compiled chart's static SVG, the tick's SVG-layer regions (the windowed axis and grid) over it; and a **Data rate** slider, samples per second per series — there from the moment the drawer opens, at 600 by default as the High-Performance page mounted (#359) — whose density follows the rate as that page's did (about five seconds across the plot) and whose samples the run accounts as whole columns per tick: the window advances by them on **every** backend, the design's `origin` option, so the rate moves the chart and the FPS only decides how often it is drawn — the compiled chart scrolls by exactly the pixels they fill on *Incremental* and the copy-shift contract of spec/09 §5.3 holds through the library's own path, and *SVG* and *Canvas* render the full frame of the advanced window. Beside *Samples/s* a streaming chart's metrics carry what the High-Performance page's did: *Pts/s* (the rate times the series), *Total points* (the window's count times the series), *Pts/frame* (the rows the last frame drew) and *Mode* (the last frame's `full` or `scroll`). `/high-performance` redirects to the chart's page; `ExamplesWeb.HighPerformanceLive` is gone, its behaviour the drawer's.

**The run is one module** (#322): `Examples.Run` (`examples/lib/examples/run.ex`) is the frame loop every page that streams frames drives, a struct of the run's state and pure functions over it, time passed in — `start/2`, `stop/1`, `schedule/2` (the next tick's deadline and the milliseconds to wait, below), `tick/3` (the samples due since the last tick accounted as whole columns of the page's density, or the tick counted *Skipped* while a render is in flight), `mode/3` (what the frame goes as: strips, the empty update, a full render, or held back), `hold/2` and `window/1` (the lag budget), `sending/1` (the next sequence), `rendering/2` and `rendered/4` (a frame rendered in a task under `Examples.TaskSupervisor`, one in flight, its result measured — #323), `acked/4` (the hook's ack), `cancel/1` (Stop, the task terminated). The High-Performance page is the first page on it and changes nothing a person sees; the chart page's drawer is the second (#326). The paragraphs below state the model the module keeps.

**The frame rate and the data rate are separate** (#300). *Target FPS* says how often the page draws; *Data rate* says how many samples per second arrive per series. Samples arrive by the clock — each tick, `data_rate × elapsed / 1000` samples are due, kept as a whole `pending` count and a fractional `carry` — and a frame scrolls by the whole columns the pending samples fill, `div(pending, samples_per_px)`, keeping the remainder: the contract holds because a frame moves by whole pixels and the columns' samples are its fresh data. Every tick sends a frame (#302): with *Incremental OFF* a full render, the whole picture again when nothing moved; with *Incremental ON* the strips the tick's columns expose, or, when no column filled, the `"none"` payload of spec/09 §7.3 (D-38) — an incremental frame whose update is empty, zero bytes, which the hook leaves the canvas alone on — so the FPS counter reports ticks and the two rates are independent. A tick whose scroll `scroll_mode/2` classifies `:full_redraw` is sent as a full render. Ticks follow a deadline: the next frame's due time advances by `1_000_000 / target_fps` microseconds and the timer is set for the whole milliseconds left, rounded to the nearest and never negative, so a target between whole-millisecond rates averages to it — the page had set `div(1000, fps)` milliseconds, which quantised every target from 334 to 500 to 500 fps and 501 to 999 to 1,000. The metrics bar shows the target and the measured data rate beside the FPS. **The point count follows the data rate** (#308): the plot spans about five seconds of data at the rate, so `samples_per_px = max(1, round(data_rate × 5 / inner_width))` — four per pixel at 600 samples/s, 3,241 per series, 16,205 points, the plot crossed in 5.4 s; one per pixel at 10 samples/s, 81 s across — and changing the rate re-sizes the window; there is no separate point-count control, and the *Total points* metric states the count with the density and span it implies. The metrics sit in two rows of eight — the frames' and the data's — and *Lag* is an exponential moving average (α = 2/31) of `in flight × period` over the ticks, since in flight swings between acks. **Frames in flight are visible and bounded** (#304): every frame carries its `seq`, the hook element carries `data-ack="frame_drawn"` (spec/10 §9.2), and the page shows *Client FPS* (frames the browser drew per second, from the acks), *In flight* (sent − acked) and *Lag* (in flight × the tick period). With *Flow control* on, the default, the page sends no frame while the window is in flight — the window is a lag budget, `@max_lag_ms` (250) of frames at the target rate, fifteen at 60 fps, since the hook's ack interval (50 ms on this page) bounds how stale the count is and a count of eight filled before the first ack of a run's opening full render, every drop then breeding the full frame that caused the next (#310): the data still advances by the clock, the tick is a frame, the frame is counted as *Dropped*, and the next frame sent after a dropped scroll frame is a full render, since a strip drawn against a canvas that missed a scroll is the wrong picture (spec/09 §5.3, D-107). With it off the page sends every frame and the metrics show the backlog grow. A hold times out (#306): a frame is held only while the hold is younger than two seconds; past that, if no ack has arrived in the run the client does not acknowledge — an older hook, an element without `data-ack` — and flow control turns itself off for the run with the button reading *no acks*, and if acks had arrived the client is stalled, so the window is released, the frame goes as a full render, *Stalls* counts it and *Last ack* shows the age. A producer that bounds frames by acks must not depend on their arriving; the page as first delivered held every frame forever when they did not. `ExamplesWeb.HooksController` serves the hooks module with `cache-control: no-cache`, so a reload revalidates and a restarted server's hooks reach the browser. The page had tied the two — every frame scrolled a fixed five pixels, so the data rate was `5 × samples_per_px × fps` and could not be set on its own.

**The model is shared** (#296; the performance page's own scrolling chart, `ExamplesWeb.PerformanceLive.MultiLine`, was on it until #328 folded the page's chart types into the gallery, where *Scrolling series* is the model's chart). The model is `Examples.Scroll` (`examples/lib/examples/scroll.ex`): a density in whole samples per pixel column (`density/2`, the nearest to a requested count, at least one), a window of `samples_per_px × inner_width + 1` samples (`count/1`) whose x scale maps a sample to exactly `1 / samples_per_px` pixels (`x_scale/1`), an `origin` in samples that a scroll of `px` pixels advances by `px × samples_per_px` (`samples/2`, `advance/2`), a sampled line shifted by dropping that many and appending fresh samples by absolute index (`shift/4`), and the sample range under a strip of the plot with a buffer each side (`columns/3`, `nil` when the strip lies outside the plot or holds fewer than two samples). `ExamplesWeb.HighPerformanceLive` is on it. The performance page's Multi-Line chart (`ExamplesWeb.PerformanceLive.MultiLine`) broke the contract three ways — it shifted its data by whole samples that were not whole pixels and rounded the copy, its full render and its strips were different builders at different margins, and its other chart types, phase-animated, were scrolled at all — and is now one ridgeline builder over a column range (`ridges/3`) in one geometry — the page's plot, the rectangle inside its margin that the hybrid backends' static axes frame, given to `init/2` and the same for every backend (#298) — `advance/1` scrolls by exactly one pixel's samples; `incremental/1` is the strips through the same builder with the plot as the viewport (D-106), so the margin and its axes are never copied or drawn over; the page's other data elements, the ridgeline's included, are laid into that plot too; and the Line, Area and Scatter charts under an incremental backend send a full redraw every frame, which is what §5.2's `:full_redraw` is for. `examples/test/examples/scroll_test.exs` and `examples/test/examples_web/performance_multi_line_test.exs` hold both.

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

The same design as a `Visualize.Chart.Build` pipeline (§16), which folds to the identical map (`test/visualize/chart/example_test.exs` reads both blocks from this section and holds them equal):

```elixir
import Visualize.Chart.Build
import Visualize.Chart, only: [var: 1]

Visualize.Chart.compose([
  chart(meta: %{name: "Uptime", description: ["Uptime in ", var(:unit)]}),
  source(:primary, [:t, :v], default: :gitlab_uptime),
  source(:deploys, [:at, :sha]),
  var(:unit, "%"),
  var(:accent, :series_1),
  theme(:default),
  style(:series, stroke: var(:accent), stroke_width: 2, curve: :step_after),
  style(:muted, stroke: :axis, stroke_width: 1, opacity: 0.6),
  cartesian(600, 300, margin: %{top: 20, right: 20, bottom: 30, left: 40}),
  time_scale(:x, domain: :auto),
  linear_scale(:y, domain: [0, :auto], nice: true),
  linear_scale(:count, domain: [0, :auto], range: [0, 120]),
  ordinal_scale(:color, range: :category10),
  axis(:x, :bottom, ticks: 6, format: "%H:%M"),
  axis(:y, :left, ticks: 5, grid: true),
  axis(:count, :top, ticks: 3),
  legend(:color, position: :top_right),
  line(:primary, %{x: :t, y: :v}, style: :series),
  rule(:deploys, %{x: :at},
    label: %{text: ["deploy ", {:field, :sha}], anchor: :top},
    style: :muted
  ),
  rect(from(:primary) |> bin(:v, thresholds: 20), %{x0: 0, x1: :count, y0: :x0, y1: :x1},
    scales: %{x: :count},
    style: :muted
  ),
  title(["Uptime — ", var(:unit)]),
  label({:axis, :y}, ["unit: ", var(:unit)]),
  label({:frame, :top_right}, ["last 24 h"]),
  label({:data, [~U[2026-09-08 12:00:00Z], 99.5]}, ["target"])
])
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
| `Visualize.Chart.compose/2` | `compose(a, b)`: `{:ok, map}`, the second fragment merged over the first by the merge rule of every key (§8.1), else `{:error, errors}` with `:conflict` at the path of every `:union` name the two declare differently. |
| `Visualize.Chart.stack/1` | `stack(layers)`: the layers cascaded left to right, the later the higher (§8.2); `%{}` for `[]` and the layer itself for one. The cascade cannot fail, so the result is the fragment, not an ok tuple. |
| `Visualize.Chart.stack/2` | `stack(lower, higher)`: the higher fragment cascaded over the lower by the rule of every key (§8.2) — a `:union` name both declare taken from the higher, a node both give as a map cascading key by key. |
| `Visualize.Chart.explain/1` | `explain(layers)`: one `t:Visualize.Chart.provenance/0` per leaf path of `stack/1` of the layers — the value, the layer that set it and the layers it overrode — ordered by path (§17.1). |
| `Visualize.Chart.free_vars/1` | `free_vars(design)`: one `t:Visualize.Chart.free_var/0` per variable still in a fragment, a chart or a stack of layers — its default, whether it is required, and every path it stands at with the schema's expectation there and the layer it came from — ordered by name (§17.2). |
| `Visualize.Chart.compile/1` | As `compile/2` with `[]` options: an applied chart compiled as it is, or a design applied with no options first. |
| `Visualize.Chart.compile/2` | `compile(design, opts)`: `{:ok, %Visualize.Chart.Compiled{}}` for an applied chart, or for a chart or a design map applied first with `sources:`, `vars:` and `theme:` as `apply/2` takes them (§12.1), with `ceiling:` the point-count ceiling of §12.3 (`1000`); else the `{:error, errors}` of application. Raises `ArgumentError` as `apply/2` does, and for a `ceiling:` that is not a positive integer. |
| `Visualize.Chart.generate/1` | As `generate/2` with `[]` options. |
| `Visualize.Chart.generate/2` | `generate(applied, opts)`: the applied chart as a `Visualize.IR.Element` — `Visualize.Chart.Frame.generate/2` of its frame over its bound sources with `resolve:` and `paths:` as that function takes them — or, with `root: true`, that group inside `Visualize.IR.Element.root/3` at the frame's size, titled from the design's `meta` unless `title:` and `description:` say otherwise, `responsive:` passed through (§4.7). |
| `Visualize.Chart.render/1` | As `render/2` with `[]` options. |
| `Visualize.Chart.render/2` | `render(applied, opts)`: `generate/2` serialised through `Visualize.Render.to_string/2` — `backend:` and `resolve:` (default `Visualize.Theme.mode/1` of the backend), `paths:`, `root:`, `title:`, `description:` and `responsive:` as `generate/2` takes them. |

### 14.2 `Visualize.Chart.Schema`

**Implemented.** The schema as data. A key spec (`t:Visualize.Chart.Schema.key_spec/0`) is `%{key, type, facet, default, required, merge, range, group}`; `nil` as a default means "none". `range` is `{min, max, step}` for a numeric key that has a sensible span — an opacity is 0 to 1, a stroke width 0 to 20, a font size 6 to 72, a margin 0 to 200, a size 100 to 2000 — and `nil` for every other key. It is data about the key for a control to read (§18.6), never a bound the validator enforces: a value outside it is unusual, not wrong. `group` is one of `:fill`, `:stroke`, `:font`, `:position`, `:effects` for a style key that belongs with others under one heading (§3.1), and `nil` for every other key; like `range` it is data for the form (§18.7) and means nothing to the cascade or the validator.

| Function | Contract |
|---|---|
| `Visualize.Chart.Schema.kinds/0` | Every node kind of §1.2, the design first. |
| `Visualize.Chart.Schema.describe/1` | The key specs of a node kind in the order of its table, for introspection and the builder's forms. |
| `Visualize.Chart.Schema.key/2` | `key(kind, key)`: the key spec, or `nil` when the node has no such key. |
| `Visualize.Chart.Schema.keys/1` | Every `{kind, key}` pair carrying the facet, over every node kind (§1.3). |
| `Visualize.Chart.Schema.keys/2` | `keys(kind, facet)`: the keys of one node kind carrying the facet, in table order. |
| `Visualize.Chart.Schema.group/2` | `group(kind, key)`: the group the key's spec carries, or `nil`. |
| `Visualize.Chart.Schema.groups/1` | `groups(kind)`: the groups a node kind's keys carry, once each, in table order — `[:fill, :stroke, :font, :position, :effects]` for a style, `[]` for every other kind. |
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
| `Visualize.Chart.Validator.format_path/1` | A path in that `a[1].b` form, `design` for the root — the one spelling an error, a node label (§18.5) and a rendered `data-node` (§4.7) share. |

### 14.4 `Visualize.Chart.Migration`

**Implemented.**

| Function | Contract |
|---|---|
| `Visualize.Chart.Migration.current/0` | The schema version this library writes: `1`. |
| `Visualize.Chart.Migration.migrate/1` | `{:ok, map}` at the current version after stepping an older design forward, in the shape this library writes (`canonical/1`), else `{:error, [{[:version], reason}]}` (§9). |
| `Visualize.Chart.Migration.canonical/1` | the design in the shape this library writes within the current version: a `:text` given as parts becomes its string (§7.1); everything else passes through. |

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
| `Visualize.Chart.Frame.generate/2` | The `Visualize.IR.Element` group of §4.7: the static furniture, and every mark of the design between the grid and the axes when `sources:` is given, theme slots resolved in the `:resolve` mode; with `paths: true` every node's element carries `data-node` with its path. |
| `Visualize.Chart.Frame.render/1` | As `render/2` with `[]` options. |
| `Visualize.Chart.Frame.render/2` | `generate/2` rendered through `Visualize.Render.to_string/2`; `sources:` and `paths:` as `generate/2` takes them, `:resolve` defaulting to `Visualize.Theme.mode/1` of the `:backend`. |

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
| `Visualize.Chart.Style.resolve/3` | `resolve(node, theme, mode)`: the element style map of a style node — the eighteen element keys, every slot resolved through `Visualize.Theme.resolve/3` in `mode`, a dash-array list joined, a `{:field, f}` kept for `bind/4` and a `{:paint, name}` kept for the frame (§3.2). Raises `ArgumentError` for a variable. |
| `Visualize.Chart.Style.bind/4` | `bind(style, datum, frame, mode)`: the map of `resolve/3` with every `{:field, f}` read from the datum; a colour key's reading passes through the frame's `color` scale when it declares one and resolves as a slot when it is one; a `nil` reading drops the key. |

A style is looked up by name among the declared styles and the built-in four (§3.3) with its `extends` chain flattened first (§3.5), so neither function ever sees that key; a cycle reached at resolution raises `ArgumentError`, the validator having reported it by path (§10.1).

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
| `Visualize.Chart.Compiled.step/2` | As `step/3` with `[]` options. |
| `Visualize.Chart.Compiled.step/3` | `step(compiled, sources, opts)`: one frame of the one-string form as a `Visualize.IR.Element` — the frame's group at the eased scales' shown domains — and the compiled chart after it; `now:` and `at:` as `tick/3` takes them (§12.5, #360). |

### 14.12 `Visualize.Chart.Build`

**Implemented** (work item 1 of #91, D-78). The builder of §16. Every function returns a *fragment* — a design map carrying the keys that one function sets and no others (§8) — except `from/1` and the transform appenders, which return a mark's `:data` node (§5.4). Every function's trailing `opts` are the remaining keys of the node it builds, checked against `Visualize.Chart.Schema.describe/1`: an option that is not a key of that node kind raises `ArgumentError` naming the key and the kind. Nothing here validates, defaults or realises anything — a fragment becomes a chart through `Visualize.Chart.from_map/1` or `Visualize.Chart.apply/2`.

| Function | Contract |
|---|---|
| `Visualize.Chart.Build.chart/0` | As `chart/1` with `[]`. |
| `Visualize.Chart.Build.chart/1` | `chart(opts)`: the seed a design is folded onto — `%{version: v}` with `v` the integer `Visualize.Chart.Migration.current/0`; `opts` are the remaining keys of the `:design` node (§2.1). |
| `Visualize.Chart.Build.source/2` | As `source/3` with `[]`. |
| `Visualize.Chart.Build.source/3` | `source(name, fields, opts)`: `%{sources: %{name => %{fields: fields}}}`, one typed slot (§2.3); `opts` are the slot's remaining keys, `default:` among them. |
| `Visualize.Chart.Build.var/2` | As `var/3` with `[]`. |
| `Visualize.Chart.Build.var/3` | `var(name, default, opts)`: `%{vars: %{name => %{default: default}}}`, the *declaration* of a variable (§2.4). `Visualize.Chart.var/1` builds the term that *uses* one; the two are different functions of different modules and different arities (§16.2). |
| `Visualize.Chart.Build.style/2` | As `style/3` with `[]`. |
| `Visualize.Chart.Build.style/3` | `style(name, keys, opts)`: `%{styles: %{name => node}}` with the node the style keys of §3.1 — `keys` as a map or a keyword list, `opts` merged over it, every key checked. |
| `Visualize.Chart.Build.gradient/2` | As `gradient/3` with `[]`. |
| `Visualize.Chart.Build.gradient/3` | `gradient(name, kind, opts)`: `%{defs: %{name => node}}`, a `:gradient` node of §2.7 — `kind` `:linear` or `:radial`, `opts` its remaining keys (`stops:` as a list of `%{offset, colour, opacity}` maps or `{offset, colour}` / `{offset, colour, opacity}` tuples, `angle:`, `centre:`, `radius:`), every key checked. |
| `Visualize.Chart.Build.paint/1` | `paint(name)`: `{:paint, name}`, the value a `:colour` key takes to refer to a gradient (§3.2). |
| `Visualize.Chart.Build.theme/1` | `theme(theme)`: `%{theme: theme}`, a theme name or an inline `:theme` node (§2.5). |
| `Visualize.Chart.Build.cartesian/2` | As `cartesian/3` with `[]`. |
| `Visualize.Chart.Build.cartesian/3` | `cartesian(width, height, opts)`: `%{frame: %{kind: :cartesian, size: %{width: width, height: height}}}`; `opts` are the frame's remaining keys (§4.1). |
| `Visualize.Chart.Build.polar/2` | As `polar/3` with `[]`. |
| `Visualize.Chart.Build.polar/3` | `polar(width, height, opts)`: as `cartesian/3` with `kind: :polar` (§4.6). |
| `Visualize.Chart.Build.geo/2` | As `geo/3` with `[]`. |
| `Visualize.Chart.Build.geo/3` | `geo(width, height, opts)`: as `cartesian/3` with `kind: :geo`; the projection is the frame's `projection:` key, a `:projection` node (§4.6). |
| `Visualize.Chart.Build.facet/2` | As `facet/3` with `[]`. |
| `Visualize.Chart.Build.facet/3` | `facet(width, height, opts)`: as `cartesian/3` with `kind: :facet`; `by:` and `columns:`, the keys of the `:facet` node, are lifted into the frame's `facet` key (§4.6). |
| `Visualize.Chart.Build.scale/2` | As `scale/3` with `[]`. |
| `Visualize.Chart.Build.scale/3` | `scale(name, kind, opts)`: `%{frame: %{scales: %{name => %{kind: kind}}}}`, one declared scale (§4.3); `opts` are the scale's remaining keys. |
| `Visualize.Chart.Build.axis/2` | As `axis/3` with `[]`. |
| `Visualize.Chart.Build.axis/3` | `axis(scale, side, opts)`: `%{frame: %{axes: [%{scale: scale, side: side}]}}`, one axis (§4.4); `opts` are its remaining keys. |
| `Visualize.Chart.Build.legend/1` | As `legend/2` with `[]`. |
| `Visualize.Chart.Build.legend/2` | `legend(scale, opts)`: `%{frame: %{legend: %{scale: scale}}}` (§4.5) — `opts` are `position`, `inside`, `title`, `prefix`, `unit`, `style`. |
| `Visualize.Chart.Build.label/2` | As `label/3` with `[]`. |
| `Visualize.Chart.Build.label/3` | `label(anchor, text, opts)`: `%{labels: [%{anchor: anchor, text: text}]}`, one frame label (§6.1). |
| `Visualize.Chart.Build.title/1` | As `title/2` with `[]`. |
| `Visualize.Chart.Build.title/2` | `title(text, opts)`: `label(:title, text, opts)`. |
| `Visualize.Chart.Build.mark/3` | As `mark/4` with `[]`. |
| `Visualize.Chart.Build.mark/4` | `mark(type, data, channels, opts)`: `%{marks: [%{type: type, data: data, channels: channels}]}` (§5.1). `data` is a source name or a `:data` node; `channels` is a map or a keyword list whose keys MUST be channels of the type (`Visualize.Chart.Schema.channels/1`); an `options:` option's keys MUST be options of the type (`Visualize.Chart.Schema.options/1`); either raises `ArgumentError`. A `%Visualize.Chart.Var{}` given as the whole channels or options node is passed through unchecked. |
| `Visualize.Chart.Build.from/1` | `from(source)`: `%{source: source}`, the `:data` node of a mark (§5.4) — not a fragment; the transform appenders below extend it. |

The mark, transform and scale functions are generated from the schema (§16.6), so the three tables below are the schema's own and change with it. `mark/4` and `scale/3` remain the generic forms, taking a type and a kind as values.

| Function | Contract |
|---|---|
| `Visualize.Chart.Build.line/2` | As `line/3` with no options. |
| `Visualize.Chart.Build.line/3` | `line(data, channels, opts)`: `mark/4` of the `:line` type (§5.2) — required channels `x`, `y`; optional `series`. |
| `Visualize.Chart.Build.area/2` | As `area/3` with no options. |
| `Visualize.Chart.Build.area/3` | `area(data, channels, opts)`: `mark/4` of the `:area` type (§5.2) — required channels `x`, `y`; optional `x0`, `x1`, `y0`, `y1`, `series`. |
| `Visualize.Chart.Build.band/2` | As `band/3` with no options. |
| `Visualize.Chart.Build.band/3` | `band(data, channels, opts)`: `mark/4` of the `:band` type (§5.2) — required channels `x0`, `x1`; optional `y`; options `height`. |
| `Visualize.Chart.Build.rule/2` | As `rule/3` with no options. |
| `Visualize.Chart.Build.rule/3` | `rule(data, channels, opts)`: `mark/4` of the `:rule` type (§5.2) — required channels `x`. |
| `Visualize.Chart.Build.x_band/2` | As `x_band/3` with no options. |
| `Visualize.Chart.Build.x_band/3` | `x_band(data, channels, opts)`: `mark/4` of the `:x_band` type (§5.2) — required channels `x0`, `x1`. |
| `Visualize.Chart.Build.percentile_band/2` | As `percentile_band/3` with no options. |
| `Visualize.Chart.Build.percentile_band/3` | `percentile_band(data, channels, opts)`: `mark/4` of the `:percentile_band` type (§5.2) — required channels `x`, `median`; optional `inner_lo`, `inner_hi`, `outer_lo`, `outer_hi`. |
| `Visualize.Chart.Build.rose/2` | As `rose/3` with no options. |
| `Visualize.Chart.Build.rose/3` | `rose(data, channels, opts)`: `mark/4` of the `:rose` type (§5.2) — required channels `angle`; optional `value`; options `width`, `inner_radius`, `outer_radius`, `pad_angle`. |
| `Visualize.Chart.Build.symbol/2` | As `symbol/3` with no options. |
| `Visualize.Chart.Build.symbol/3` | `symbol(data, channels, opts)`: `mark/4` of the `:symbol` type (§5.2) — required channels `x`, `y`; optional `value`. |
| `Visualize.Chart.Build.arc/2` | As `arc/3` with no options. |
| `Visualize.Chart.Build.arc/3` | `arc(data, channels, opts)`: `mark/4` of the `:arc` type (§5.2) — required channels `value`; optional `start`, `end`, `inner`, `outer`; options `inner_radius`, `outer_radius`, `corner_radius`, `pad_angle`, `start_angle`, `end_angle`. |
| `Visualize.Chart.Build.path/2` | As `path/3` with no options. |
| `Visualize.Chart.Build.path/3` | `path(data, channels, opts)`: `mark/4` of the `:path` type (§5.2) — required channels `path`. |
| `Visualize.Chart.Build.rect/2` | As `rect/3` with no options. |
| `Visualize.Chart.Build.rect/3` | `rect(data, channels, opts)`: `mark/4` of the `:rect` type (§5.2) — required channels `x0`, `x1`, `y0`, `y1`; optional `value`; options `corner_radius`. |
| `Visualize.Chart.Build.circle/2` | As `circle/3` with no options. |
| `Visualize.Chart.Build.circle/3` | `circle(data, channels, opts)`: `mark/4` of the `:circle` type (§5.2) — required channels `x`, `y`; optional `value`; options `radius`. |
| `Visualize.Chart.Build.text/2` | As `text/3` with no options. |
| `Visualize.Chart.Build.text/3` | `text(data, channels, opts)`: `mark/4` of the `:text` type (§5.2, #134) — required channels `x`, `y`; optional `value`; no options; the text is the mark's `label`, else `value`. |

The transform appenders, one per op of §5.4 (`Visualize.Chart.Schema.transform_ops/0`, the `:projection` step among them), each taking the data node — a `:data` node or a source name, read as `from/1` of it — and returning it with the step appended. The positional arguments after the node are the op's required keys, in the schema's order.

| Function | Contract |
|---|---|
| `Visualize.Chart.Build.filter/2` | As `filter/3` with no options. |
| `Visualize.Chart.Build.filter/3` | `filter(data, field, opts)`: a `:filter` step appended to the data node (§5.4) — `opts` are `test`, `value`. |
| `Visualize.Chart.Build.bin/2` | As `bin/3` with no options. |
| `Visualize.Chart.Build.bin/3` | `bin(data, field, opts)`: a `:bin` step appended to the data node (§5.4) — `opts` are `thresholds`, `as`. |
| `Visualize.Chart.Build.stack/2` | As `stack/3` with no options. |
| `Visualize.Chart.Build.stack/3` | `stack(data, fields, opts)`: a `:stack` step appended to the data node (§5.4) — `opts` are `order`, `offset`. |
| `Visualize.Chart.Build.fold/2` | As `fold/3` with no options. |
| `Visualize.Chart.Build.fold/3` | `fold(data, fields, opts)`: a `:fold` step appended to the data node (§5.4) — `opts` are `as`. |
| `Visualize.Chart.Build.sum/2` | As `sum/3` with no options. |
| `Visualize.Chart.Build.sum/3` | `sum(data, field, opts)`: a `:sum` step appended to the data node (§5.4) — `opts` are `by`, `as`. |
| `Visualize.Chart.Build.sort/2` | As `sort/3` with no options. |
| `Visualize.Chart.Build.sort/3` | `sort(data, field, opts)`: a `:sort` step appended to the data node (§5.4) — `opts` are `order`. |
| `Visualize.Chart.Build.tree/1` | As `tree/2` with no options. |
| `Visualize.Chart.Build.tree/2` | `tree(data, opts)`: a `:tree` step appended to the data node (§5.4) — `opts` are `id`, `by`, `field`, `size`, `output`, `orientation`, `link`. |
| `Visualize.Chart.Build.cluster/1` | As `cluster/2` with no options. |
| `Visualize.Chart.Build.cluster/2` | `cluster(data, opts)`: a `:cluster` step appended to the data node (§5.4) — `opts` are `id`, `by`, `field`, `size`, `output`, `orientation`, `link`. |
| `Visualize.Chart.Build.pack/1` | As `pack/2` with no options. |
| `Visualize.Chart.Build.pack/2` | `pack(data, opts)`: a `:pack` step appended to the data node (§5.4) — `opts` are `id`, `by`, `field`, `size`, `output`, `padding`. |
| `Visualize.Chart.Build.partition/1` | As `partition/2` with no options. |
| `Visualize.Chart.Build.partition/2` | `partition(data, opts)`: a `:partition` step appended to the data node (§5.4) — `opts` are `id`, `by`, `field`, `size`, `output`, `padding`. |
| `Visualize.Chart.Build.treemap/1` | As `treemap/2` with no options. |
| `Visualize.Chart.Build.treemap/2` | `treemap(data, opts)`: a `:treemap` step appended to the data node (§5.4) — `opts` are `id`, `by`, `field`, `size`, `output`, `padding`, `tile`. |
| `Visualize.Chart.Build.chord/3` | As `chord/4` with no options. |
| `Visualize.Chart.Build.chord/4` | `chord(data, fields, field, opts)`: a `:chord` step appended to the data node (§5.4) — `opts` are `size`, `padding`, `output`, `nodes`, `id`. |
| `Visualize.Chart.Build.sankey/3` | As `sankey/4` with no options. |
| `Visualize.Chart.Build.sankey/4` | `sankey(data, fields, field, opts)`: a `:sankey` step appended to the data node (§5.4) — `opts` are `size`, `padding`, `output`, `nodes`, `id`. |
| `Visualize.Chart.Build.force/2` | As `force/3` with no options. |
| `Visualize.Chart.Build.force/3` | `force(data, fields, opts)`: a `:force` step appended to the data node (§5.4) — `opts` are `field`, `size`, `output`, `nodes`, `id`, `strength`, `distance`. |
| `Visualize.Chart.Build.contour/3` | As `contour/4` with no options. |
| `Visualize.Chart.Build.contour/4` | `contour(data, field, size, opts)`: a `:contour` step appended to the data node (§5.4) — `opts` are `thresholds`. |
| `Visualize.Chart.Build.density/2` | As `density/3` with no options. |
| `Visualize.Chart.Build.density/3` | `density(data, fields, opts)`: a `:density` step appended to the data node (§5.4) — `opts` are `field`, `size`, `bandwidth`, `thresholds`. |
| `Visualize.Chart.Build.delaunay/2` | As `delaunay/3` with no options. |
| `Visualize.Chart.Build.delaunay/3` | `delaunay(data, fields, opts)`: a `:delaunay` step appended to the data node (§5.4) — `opts` are `output`. |
| `Visualize.Chart.Build.voronoi/2` | As `voronoi/3` with no options. |
| `Visualize.Chart.Build.voronoi/3` | `voronoi(data, fields, opts)`: a `:voronoi` step appended to the data node (§5.4) — `opts` are `size`, `output`. |
| `Visualize.Chart.Build.hexbin/2` | As `hexbin/3` with no options. |
| `Visualize.Chart.Build.hexbin/3` | `hexbin(data, fields, opts)`: a `:hexbin` step appended to the data node (§5.4) — `opts` are `radius`, `size`, `output`. |
| `Visualize.Chart.Build.projection/2` | As `projection/3` with no options. |
| `Visualize.Chart.Build.projection/3` | `projection(data, fields, opts)`: a `:projection` step appended to the data node (§5.4) — `fields` the point columns, or `nil` with `field:` in `opts` for a geometry column (§5.4.4). |

The scale functions, one per kind of §4.3. The name carries the `_scale` suffix because a kind and a mark type may spell the same word: `band` is both.

| Function | Contract |
|---|---|
| `Visualize.Chart.Build.linear_scale/1` | As `linear_scale/2` with no options. |
| `Visualize.Chart.Build.linear_scale/2` | `linear_scale(name, opts)`: `scale/3` of the `:linear` kind (§4.3). |
| `Visualize.Chart.Build.log_scale/1` | As `log_scale/2` with no options. |
| `Visualize.Chart.Build.log_scale/2` | `log_scale(name, opts)`: `scale/3` of the `:log` kind (§4.3). |
| `Visualize.Chart.Build.power_scale/1` | As `power_scale/2` with no options. |
| `Visualize.Chart.Build.power_scale/2` | `power_scale(name, opts)`: `scale/3` of the `:power` kind (§4.3). |
| `Visualize.Chart.Build.sqrt_scale/1` | As `sqrt_scale/2` with no options. |
| `Visualize.Chart.Build.sqrt_scale/2` | `sqrt_scale(name, opts)`: `scale/3` of the `:sqrt` kind (§4.3). |
| `Visualize.Chart.Build.symlog_scale/1` | As `symlog_scale/2` with no options. |
| `Visualize.Chart.Build.symlog_scale/2` | `symlog_scale(name, opts)`: `scale/3` of the `:symlog` kind (§4.3). |
| `Visualize.Chart.Build.time_scale/1` | As `time_scale/2` with no options. |
| `Visualize.Chart.Build.time_scale/2` | `time_scale(name, opts)`: `scale/3` of the `:time` kind (§4.3). |
| `Visualize.Chart.Build.ordinal_scale/1` | As `ordinal_scale/2` with no options. |
| `Visualize.Chart.Build.ordinal_scale/2` | `ordinal_scale(name, opts)`: `scale/3` of the `:ordinal` kind (§4.3). |
| `Visualize.Chart.Build.band_scale/1` | As `band_scale/2` with no options. |
| `Visualize.Chart.Build.band_scale/2` | `band_scale(name, opts)`: `scale/3` of the `:band` kind (§4.3). |
| `Visualize.Chart.Build.quantize_scale/1` | As `quantize_scale/2` with no options. |
| `Visualize.Chart.Build.quantize_scale/2` | `quantize_scale(name, opts)`: `scale/3` of the `:quantize` kind (§4.3). |
| `Visualize.Chart.Build.quantile_scale/1` | As `quantile_scale/2` with no options. |
| `Visualize.Chart.Build.quantile_scale/2` | `quantile_scale(name, opts)`: `scale/3` of the `:quantile` kind (§4.3). |
| `Visualize.Chart.Build.threshold_scale/1` | As `threshold_scale/2` with no options. |
| `Visualize.Chart.Build.threshold_scale/2` | `threshold_scale(name, opts)`: `scale/3` of the `:threshold` kind (§4.3). |
| `Visualize.Chart.Build.sequential_scale/1` | As `sequential_scale/2` with no options. |
| `Visualize.Chart.Build.sequential_scale/2` | `sequential_scale(name, opts)`: `scale/3` of the `:sequential` kind (§4.3). |
| `Visualize.Chart.Build.diverging_scale/1` | As `diverging_scale/2` with no options. |
| `Visualize.Chart.Build.diverging_scale/2` | `diverging_scale(name, opts)`: `scale/3` of the `:diverging` kind (§4.3). |
| `Visualize.Chart.Build.radial_scale/1` | As `radial_scale/2` with no options. |
| `Visualize.Chart.Build.radial_scale/2` | `radial_scale(name, opts)`: `scale/3` of the `:radial` kind (§4.3). |

## 15. Presets

### 15.1 A component is a preset design plus an assign mapping

**Implemented** (work item 4 of #53, D-64). Each of the ten function components of [10-liveview-integration](10-liveview-integration.md) §2–3 is a *preset*: a function in `Visualize.Chart.Presets` from the component's assigns to a design map of this document, and an *assign mapping* that turns the component's `data` and accessor assigns into the rows the design's one source binds to. The component itself is what is left: it calls the preset, builds the frame with `Visualize.Chart.Frame.new/2` over the mapped source, draws it with `Visualize.Chart.Frame.generate/2`, and lays the elements the layer returns into the markup spec/10 declares. Three things follow:

- **The markup contract of spec/10 is unchanged.** The `<svg>` and its attributes, the `<title>` and `<desc>`, the `<g transform="translate(left, top)">`, the `<g class="x-axis">` and `<g class="y-axis">` wrappers, the attribute order of every mark element, `class` on the `<svg>` and the `animate` transition on every mark are the component's shell, drawn by its HEEx template as before; the ten render goldens of `test/support/components/` hold every component byte for byte to what it drew before it was a preset. A design rendered through `Visualize.Chart.Frame.render/2` carries the layer's own groups instead — `class="frame"`, `class="mark mark-<type>"`, `class="axis axis-<side>"`, marks under the axes (§4.7) — which is the one difference between a preset drawn by its component and the same design drawn by the layer.
- **Every number and every paint is the layer's.** The axes are the frame's (§4.4); a path's `d`, a rectangle's `x y width height`, a circle's `cx cy r`, an arc's `d` and its label's centroid, an axis title's position are read from the `Visualize.IR.Element`s of `generate/2`; a colour is the resolved style of the mark's group or, for a per-datum colour, the element's own (§3.4). The component keeps no scale, no generator call and no extent of its own.
- **A design is not a template.** The preset takes the assigns because two of the design's choices depend on them — the kind of the `x` scale of a line or an area chart is decided by the first datum, as spec/10 §2.2 says, and a hierarchy's colour domain is the count of the root's children — and because sizes, margins, colours and options are assigns. Everything else in the design is constant, and `Visualize.Chart.Presets.design/2` of the same assigns without `data` is the same design over the unit domains (§4.3).

Each preset is a list of fragments folded by `Visualize.Chart.compose/1` (§16.7): the helpers ten designs written in Elixir needed are the builder's, not one module's private section. The assign mapping puts the accessor assigns out of the design: a design carries no function (§1.1), so `x`, `y`, `value`, `label` and `size` are applied once, by `Visualize.Chart.Presets.sources/2`, and the design's channels name the resulting columns.

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

**Implemented** (D-64; the gaps closed by #71, D-68–D-70). The three presets of spec/10 §3 are laid out and drawn by the layer, as the seven of §15.3 are: their marks say what the component prints — a `:filter` step keeps the rows spec/10 §3 draws, the sunburst's `:arc` takes its angles from its own row, the tree's link is the link of its orientation — so `Visualize.Chart.Frame.render/2` of each design carries the mark elements the component prints, and the component lays them into its markup (§15.1). Every one has the row of §15.2 as its source and `meta` and `theme` as §15.3; the treemap and the sunburst, which take `colors`, declare a `color` scale `%{kind: :ordinal, domain: [0, …, n − 1], range: colors}` with `n` the count of the root's children, which is what `branch` maps through (§3.4): the i-th child of the root takes the i-th colour and every descendant inherits it (D-46); the root, whose `branch` is `nil`, is the theme's `:grid`. The tree, whose nodes are one colour, declares no scale.

| Preset | Frame | Transform | Marks |
|---|---|---|---|
| `tree_diagram` | `:cartesian`, the component's margin | `%{op: :tree, id: :id, by: :parent, size: s, orientation: orientation}` with `s` the plot's `[height, width]` for `:horizontal` and `[width, height]` for `:vertical` (spec/10 §3.2) | `%{type: :path, channels: %{path: :path}, style: :link}` over the transform with `output: :links`, with `link: %{fill: :none, stroke: link_stroke, stroke_width: 1.5}` — `fill: :none` said, since a `:path` is a filled type (§5.3) and an open link cubic would otherwise be filled and closed by its chord (#345); `%{type: :circle, channels: %{x: :y, y: :x}` for `:horizontal`, `%{x: :x, y: :y}` for `:vertical`, `options: %{radius: node_radius}, style: :node, label: %{text: [{:field, :label}], anchor: :middle}}` over the transform with `output: :nodes`, with `node: %{fill: node_fill, stroke: node_stroke, stroke_width: 2}` — an internal node is filled `node_stroke` by the component (spec/10 §3.2) |
| `treemap_chart` | `:cartesian`, no margin | `%{op: :treemap, id: :id, by: :parent, field: :value, padding: padding, tile: tile}`, then `%{op: :filter, field: :height, test: :eq, value: 0}` (the leaves) | `%{type: :rect, channels: %{x0: :x0, x1: :x1, y0: :y0, y1: :y1}, style: :cell}` with `cell: %{fill: {:field, :branch}, stroke: :background, stroke_width: 1}` |
| `sunburst_chart` | `:polar`, no margin | `%{op: :partition, id: :id, by: :parent, field: :value, size: [2π, R]}` with `R = min(width, height) / 2`, then `%{op: :filter, field: :depth, test: :gt, value: 0}` (below the root) and `%{op: :filter, field: :value, test: :gt, value: 0}` (a positive extent) | `%{type: :arc, channels: %{start: :x0, end: :x1, inner: :y0, outer: :y1}, style: :arc, label: %{text: [{:field, :label}], anchor: :middle, style: :arc_label}}` with `arc: %{fill: {:field, :branch}, stroke: :background, stroke_width: 1}` and `arc_label: %{fill: :background, font_size: :label_size}` |

The component prints the elements of `Visualize.Chart.Frame.generate/2` as the chart components do (§15.1), and reads the rows of `Visualize.Chart.Mark.rows/3` beside them where its markup depends on the node: the tree's links are the `:path` mark's elements — the row's `path`, the link of the design's orientation (§5.4.2) — and its nodes are the circle-and-text groups of spec/10 §3.2, one per `:circle` element at its `cx cy`, filled `node_stroke` when the row's `height` is not `0` and its text placed as spec/10 §3.2 says, since a group whose text's anchor and offset depend on the node is the one shape the layer has no mark for and the `:circle` with a `label` is the nearest it has; the treemap's cells are the `:rect` elements — `x y width height` and the element's fill — with the component's label rule (spec/10 §3.3) over the row; the sunburst's arcs are the `:arc` elements — `d` and the element's fill — and its labels the mark's `text` elements at the centroid, kept when the row's ring is thick and long enough and truncated as spec/10 §3.4 says. An element's fill is `Visualize.Chart.Style.bind/4` of the mark's style over its row, the colour scale's output resolved as §3.4 says. Rendered through `Visualize.Chart.Frame.render/2`, each design therefore carries the elements the component prints, in count and geometry — the tree's paths, circles and texts, the treemap's leaf rectangles, the sunburst's arcs and labels — and `test/visualize/chart/presets_test.exs` holds it; what differs is the shell of §15.1 and where the tree's text sits.

## 16. The builder

### 16.1 Fragments and the pipe

**Implemented** (work item 1 of #91, D-78). `Visualize.Chart.Build` is a module to `import` whose every function returns a *fragment* — a design map carrying the keys that one function sets and no others — and whose pipe is `Visualize.Chart.compose/2`: a design is the fold of its fragments, `Visualize.Chart.compose/1` over the list (§8). A design written this way is the same map as the literal, key for key; the literal remains the contract and the builder is sugar in the strict sense, so anything the builder cannot express is written as a map and composed with the rest.

Nothing in the builder validates, defaults or realises anything. A fragment need not carry `version` or `frame`, its references need not resolve, and no default of §2 is filled: the fold is a fragment too and becomes a chart through `Visualize.Chart.from_map/1`, or an applied chart through `Visualize.Chart.apply/2`, which is where it MUST validate (§8). Order therefore matters exactly where §8 says it does and nowhere else — marks and labels appear in the order their fragments do, axes in the order theirs do, a scalar takes the last fragment's word, and two fragments that declare one name differently are `:conflict` at that name's path rather than a silent overwrite.

What the builder adds over the literal is the schema, twice.

- **Every option is a key of the node the function builds.** Each function sets the node's required keys from its positional arguments and takes the rest as `opts`, checked against `Visualize.Chart.Schema.describe/1` of that kind: a misspelt `stoke_width` on a style, or `ticks:` on a legend, raises `ArgumentError` naming the key and the kind at the call, rather than reaching the validator as an `:unknown_key` at a path in a design fifty lines long. A mark's channels and options are checked the same way against the mark's type (§16.4).
- **A mark declares only what its type reads.** The channels and the options a mark takes are read from the schema at the call (§16.4), so the builder accepts exactly what §5.2 and §5.3 declare of that type. The mark, transform and scale functions carry it the whole way: each is generated from the schema (§16.6), so a schema addition grows the builder with no edit to it.

A `%Visualize.Chart.Var{}` is a value like any other and may stand anywhere the map admits one (§7.1), including as a whole node: `mark(:band, :states, %{x0: :t0, x1: :t1}, options: var(:band))` is the design of `test/support/designs/state_timeline.exs`.

### 16.2 The design and its declarations

**Implemented.** `chart/1` is the seed: the current version (§9) and whatever design-level keys it is given. The four declaration functions each add one named entry under the design's `:union` keys (§1.5), so a house style sheet, a source list and a chart's own fragments compose in any order and disagree loudly:

```elixir
import Visualize.Chart.Build
import Visualize.Chart, only: [var: 1]

{:ok, design} =
  Visualize.Chart.compose([
    chart(meta: %{name: "Uptime"}),
    source(:primary, [:t, :v], default: :gitlab_uptime),
    var(:unit, "%"),
    theme(:default),
    style(:series, stroke: var(:accent), stroke_width: 2, curve: :step_after)
  ])
```

`Visualize.Chart.Build.var/2` and `Visualize.Chart.var/1` are different functions and are not confusable: the first *declares* a variable and its default under `vars` (§2.4) and belongs to the builder; the second *builds* the `%Visualize.Chart.Var{}` term that uses one (§7.1) and belongs to the chart. They differ in module and in arity, so a module that imports both reads `var(:unit, "%")` for the declaration and `var(:unit)` for the use, and neither import shadows the other.

### 16.3 The frame

**Implemented.** A frame is assembled from fragments, never from one call: the kind and the size come from the kind's own function, and each scale, axis and legend is its own fragment, which is what lets a standard axis pair or a house frame size compose with a chart's own scales.

```elixir
cartesian(600, 300, margin: %{top: 20, right: 20, bottom: 30, left: 40})
time_scale(:x)
linear_scale(:y, domain: [0, :auto], nice: true)
axis(:x, :bottom, ticks: 6, format: "%H:%M")
axis(:y, :left, ticks: 5, grid: true)
legend(:color, position: :top_right)
```

The four kinds are `cartesian/3`, `polar/3`, `geo/3` and `facet/3`, each taking the width and the height because a frame always has both (§4.2) and the frame's remaining keys as options. `geo/3` takes its projection as the frame's `projection:` key. `facet/3` is the one place an option is not a key of the node the function builds: `by:` and `columns:` are the keys of the `:facet` node (§4.6) and are lifted into the frame's `facet` key, because a `:facet` frame and its `facet` node name the same thing and `facet(600, 400, facet: %{by: :region})` would say it twice. Scales union, axes concatenate and every other frame key is the last fragment's (§1.5), so `scale/3` and `axis/3` may precede or follow the kind.

### 16.4 Marks and labels

**Implemented.** `mark/4` is the generic mark: a type, its data, its channels, and the mark's remaining keys as options. `label/3` and `title/2` are the frame's labels (§6). Marks and labels are `:concat` keys, so the order of their fragments is the order they draw in.

```elixir
line(:primary, %{x: :t, y: :v}, style: :series)
rule(:deploys, %{x: :at}, style: :muted, label: %{text: ["deploy ", {:field, :sha}]})
title(["Uptime — ", var(:unit)])
label({:axis, :y}, ["unit: ", var(:unit)])
```

A channel the type does not read, and an option key the type does not read, raise `ArgumentError` at the call — the two lists are `Visualize.Chart.Schema.channels/1` and `Visualize.Chart.Schema.options/1`, so the builder accepts exactly what §5.2 and §5.3 declare. What it does *not* check is that the required channels are present: an `:arc` is required to carry `value` only when it carries neither `start` nor `end` (D-69), and a rule with that much context belongs to the validator, which sees the whole node (§10.2). The builder rejects what can never be right; the validator decides what is right here.

`id:` is an option of `mark/4`, of every generated mark function and of `label/3` and `title/2`, because it is a key of those nodes (§16.1) — `line(:primary, %{x: :t, y: :v}, id: :series, style: :series)` is the mark a higher layer replaces by declaring `id: :series` again (§8.2).

### 16.5 Data nodes and transforms

**Implemented.** A mark's `data` is a source name or a `:data` node (§5.4), and the node is built by `from/1` and extended by one appender per transform op, each taking the node and returning it with its step appended:

```elixir
rect(from(:primary) |> bin(:v, thresholds: 20), %{x0: :x0, x1: :x1, y0: :y0, y1: :count})
area(from(:series) |> stack([:a, :b, :c]), %{x: :t, y: :y1, y0: :y0, series: :key})
```

`from/1` returns `%{source: source}` and no `transforms` key, so a mark that reads its source directly and one built by `from/1` alone are the same map. An appender given a source name in place of a node reads it as `from/1` of that name, so `bin(:samples, :w)` is `from(:samples) |> bin(:w)`. `transforms` is a `:concat` key, so a pipeline built in two fragments runs in the order it was written (§8).

There is one appender per op of §5.4, generated from the schema (§16.6).

### 16.6 Generated from the schema

**Implemented** (work item 2 of #91, D-79). The builder's mark, transform and scale functions are not written. `Visualize.Chart.Build` uses a hidden macro module that reads `Visualize.Chart.Schema.mark_types/0`, `channels/1`, `options/1`, `transform_ops/0`, `transform_keys/1` and `scale_kinds/0` at compile time and emits one documented function per type, per op and per kind, each delegating to the generic `mark/4`, the data-node appender or `scale/3`. A type added to the schema — as #71 added three transform ops — grows the builder with no edit to it, and the builder cannot fall behind the schema, which is the acceptance of this work item.

| Generated | Name and shape | Read from |
|---|---|---|
| one per mark type | `<type>(data, channels, opts \\ [])`, `mark/4` of the type | `Visualize.Chart.Schema.mark_types/0` |
| one per transform op | `<op>(data, …the op's required keys…, opts \\ [])` | `Visualize.Chart.Schema.transform_ops/0` and `Visualize.Chart.Schema.transform_keys/1` |
| one per scale kind | `<kind>_scale(name, opts \\ [])`, `scale/3` of the kind | `Visualize.Chart.Schema.scale_kinds/0` |

Three things follow from generating them rather than writing them.

- **A name takes a suffix where two vocabularies collide.** A scale kind and a mark type may spell the same word — `band` is both (§4.3, §5.2) — so a scale's function is `<kind>_scale`, and *every* kind takes the suffix rather than only the one that collides: a rule that holds for one name and not another is a rule a reader has to look up.
- **A transform's positional arguments are the op's required keys, in the schema's order.** `chord/4` is `chord(data, fields, field, opts)` because `Visualize.Chart.Schema.transform_keys/1` requires `fields` then `field` for that op; an op with no required key, `:treemap` among them, is `treemap/2`. The op's optional keys go in `opts` and are checked as every option is (§16.1).
- **The documentation is the schema's.** Each generated function's documentation lists the channels, the options or the keys the schema gives it, so the answer to "what channels does a rose take" comes from the same table the validator reads.

The generic forms remain: `mark/4` takes a type that is a value rather than a name in the source, and `scale/3` a kind, which is what a consumer building a design from stored data needs.

A generated function is not in the source of `lib/`, so the surface scanner cannot find it by reading the file (spec/12 §2). A module that injects functions through `use` therefore declares what it injects, and the scanner asks it, so every generated function is a row of `API_SURFACE.md` like any other and a type dropped from the schema drops its rows.

### 16.7 The presets are written with it

**Implemented** (work item 3 of #91, D-80). `Visualize.Chart.Presets` (§15) is the builder's first consumer and the reason it exists: ten designs written in Elixir had grown a private construction section — a mark, a design, a cartesian frame and an axis label — which is the shape of a library function in the wrong place. Each preset is now a list of fragments folded by `Visualize.Chart.compose/1`, and the private construction helpers are gone.

What is left in `Visualize.Chart.Presets` is what the builder cannot supply: the assign mapping of §15.2, and the two choices the assigns force on the design — the kind of a series chart's `x` scale, decided by the first datum (§15.3), and a hierarchy's colour domain, the count of the root's children (§15.4). Those are decisions, not construction, and each is one call to a builder function.

The ten render goldens of `test/support/components/` are unchanged by the rewrite, byte for byte, which is what says the fold and the literal are the same map.

## 17. Inspecting a stack
Two functions read a stack rather than build one: `Visualize.Chart.explain/1` says where every value in the result came from, and `Visualize.Chart.free_vars/1` says what is still open. Neither renders anything and neither validates; they are the inspector and the parameters panel a builder UI is made of (#54), and the two questions a human asks of a four-layer template.
`Visualize.Chart.explain/1` reads a stack rather than building one: it says where every value in the result came from. It renders nothing and validates nothing — it is the inspector a builder UI is made of (#54) and the first question a human asks of a four-layer template.

### 17.1 `explain/1`: provenance

**Implemented** (#99, D-83). `Visualize.Chart.explain/1` takes the *layers* of a stack — the same list `Visualize.Chart.stack/1` takes, each a fragment, a `%Visualize.Chart{}` or a `{name, layer}` pair (§8.2) — and returns one entry per leaf path of `Visualize.Chart.stack/1` of those layers, ordered by path as the validator's errors are (§10.1):

| Key | What |
|---|---|
| `path` | the keys and list indexes from the design to the value: `[:frame, :size, :width]`, `[:marks, 0, :channels, :y]`, `[:styles, :series, :stroke]` |
| `value` | the value at that path in `Visualize.Chart.stack/1` of the same layers |
| `layer` | the layer that set it: its name, or its zero-based position in the list when it was given without one |
| `overrode` | the layers that set a value at the same path and were overridden, lowest first; `[]` where none did |

A *leaf* is a value the cascade does not descend into. The walk descends through every node (`{:node, kind}`), every name-keyed declaration (`{:map, t}`) and every element of a collection (`{:list, {:node, kind}}`), and stops everywhere else: a scalar, a name, a reference, an extent, a text, a variable, a `{:field, f}` and a whole node given as one of those are each one entry. Every leaf of the result has exactly one entry, and every entry's `layer` is a layer of the list.

**Why the layers and not the result.** A stack's result is a fragment (§8.2), and a fragment carrying provenance tags would not be one: the tags are keys no node kind declares, so the tagged map would not validate, would not survive `Visualize.Chart.to_map/1` or the JSON form, and could not be a layer of another stack — which is the property §8 exists to keep. `explain/1` therefore recomputes the stack from the layers, sharing the merge of §8.2 exactly: the same recursion into nodes, the same whole-entry rule for a `:union` name, the same identity rule for a `:concat` element. What it reports and what `Visualize.Chart.stack/1` produces cannot drift, because they are one walk.

Two limits follow from the cascade's own shape and are not defects. A value a higher layer discarded by replacing a whole `:union` entry or a whole identified element has no path in the result, so it has no entry; the layer that discarded it is named on the sibling leaves it did write, which is where a reader looking for it will be. And `overrode` names the layers that set a value **at the same path**: a higher element that adds a key the lower element did not carry overrode nothing at that key, whatever it did to the element as a whole.

### 17.2 `free_vars/1`: the variables still open

**Implemented** (#100, D-84). `Visualize.Chart.free_vars/1` takes a fragment, a `%Visualize.Chart{}` or the layers of a stack — the list of §8.2, stacked first — and returns one entry per variable still in the result, ordered by name. A fragment is a one-layer stack, so its uses are reported as layer `0`.

| Key | What |
|---|---|
| `name` | the variable's name |
| `default` | its default from the *stacked* `vars` node (§2.4), `nil` where no layer declares one |
| `required` | `true` when `default` is `nil`: the variable MUST be supplied to `Visualize.Chart.apply/2` |
| `uses` | one entry per path the variable stands at, ordered by path: `path`, `expects` and `layer` |

A use's `expects` is the schema's type at that path (§1.4) — `:colour` for a style's `stroke`, `{:ref, :style}` for a mark's `style`, `{:node, :options}` for a whole options node, `:text` for a part of a text — which is what a parameters panel needs to choose a widget, and it is the same term `Visualize.Chart.Schema.describe/1` returns. A use's `layer` is the layer that set the leaf the variable stands in, named as `explain/1` names it (§17.1).

The walk is `Visualize.Chart.apply/2`'s own (§7.3), which is the point of the function: it descends into nodes, name-keyed declarations, lists and text parts and stops where resolution stops, so `free_vars/1` lists exactly the variables `apply/2` will demand and no others. A variable the schema's walk does not reach — inside an `:extent`, inside a value another variable is bound to — is not listed, because resolution does not reach it either; the validator is what reports those (§7.1).

A variable is *free* whether or not it has a default: `required` is what separates the two, since a default is a value the caller may still override. A stack in which a higher layer writes a literal over a lower layer's variable has one use fewer, and a higher layer that writes a variable over a lower layer's literal has one more — a variable and a literal override each other in a stack like any other value (§8.2), and that is the whole of the interaction between variables and the cascade.

## 18. The builder component

A design is data, and §16 makes one writable in Elixir; nothing above it lets a person build one without writing Elixir. `Visualize.Chart.Builder` is that: an embeddable editor for a *stack* of fragments, whose panels are views of the functions the layer already has — the schema (§14.2) generates its forms, `Visualize.Chart.stack/1` (§8.2) is what it edits, `Visualize.Chart.explain/1` (§17.1) is its inspector and `Visualize.Chart.free_vars/1` (§17.2) is its parameters form. Nothing in it keeps a list of node kinds, keys or widgets of its own.

### 18.1 What it is, and what the host owns

**Implemented** (work item 1 of #54, D-85). `Visualize.Chart.Builder` is a `Phoenix.LiveComponent`, not a `Phoenix.LiveView`: a LiveView owns a route and a session, and a component embeds in whatever page the host already has.

```heex
<.live_component module={Visualize.Chart.Builder} id="builder"
                 layers={@layers} sources={@sources} on_save={:design_saved} />
```

The division is the whole of the contract. The **host** owns the route, the layers it starts the builder with, the pool of sample sources, and what happens when a design is saved — storing it, applying it, sending it somewhere. The **builder** owns the editing state: which layer is selected, which layers are disabled, which panel is open, what the parameters are set to. It reads its host's assigns on every parent render and never writes to them, and the one thing that leaves it is the message of §18.2.

One assign is not like the others. `layers` is the thing the builder *edits* — reordering, disabling, adding from the library, writing a value into a node and importing a document all rewrite it — so a component that adopted the host's list on every parent render would discard the edit that render was caused by. `layers` is therefore **seeded, not controlled**: the builder keeps the list the host last gave it, and on each render adopts the incoming one only when the host's list has actually changed. A host that deliberately replaces the stack still replaces it; a host that re-renders for its own reasons no longer erases the editing session (D-95). `sources`, `vars`, `theme`, `store` and `on_save` are controlled in the ordinary way, because the builder never writes to them.

It is optional exactly as `Visualize.Components` is (spec/10 §1.1, D-45): every module of the builder is wrapped in `if Code.ensure_loaded?(Phoenix.Component)`, `phoenix_live_view` stays an optional dependency of this library, and `scripts/consumer_check.exs` asserts that `Visualize.Chart.Builder` is absent from a consumer that does not have LiveView, beside the assertions it already makes for the components. An application that renders predefined charts never compiles a line of it.

### 18.2 Assigns and the message

**Implemented.** Every assign the host gives is declared with `attr/3`, so a misspelt one is a compile-time warning in the caller (spec/10 §1.2). The `layers` assign is the list `Visualize.Chart.stack/1` takes, in precedence order with the higher layer later, so a layer may be a design map, a `%Visualize.Chart{}` or a `{name, layer}` pair whose name the builder shows and `Visualize.Chart.explain/1` reports.

| Assign | Type | Default | Meaning |
|---|---|---|---|
| `id` | `:string` | required | the component id, as every LiveComponent takes |
| `layers` | `:list` | `[]` | the fragments in precedence order, the higher later (§8.2) — each a fragment map, a `%Visualize.Chart{}`, an id `{kind, n}` of the host's library, or a `{name, one of those}` pair; a `nil` where a fragment was expected is refused by `Visualize.Chart.Builder.Stack.seed/1` with an `ArgumentError` naming the layer, since a host that resolved a name to nothing has a bug to read, not a blank layer to edit (#272); **seeded, not controlled** — the builder owns the stack once given it, and adopts a new one only when the host's list changes (§18.1, D-95) |
| `sources` | `:map` | `%{}` | the pool of sample sources the preview binds the design's slots to, as `Visualize.Chart.apply/2` takes it (§7.3) |
| `styles` | `:boolean` | `true` | render the stylesheet in a `<style>` element (§18.13); `false` when the host ships it |
| `vars` | `:map` | `%{}` | the variable values the preview applies with; the parameters form edits a copy of this |
| `theme` | `:any` | `nil` | the `Visualize.Theme` the preview draws with, `nil` for the default |
| `store` | `:atom` | `nil` | a module implementing `Visualize.Chart.Builder.Store` (§18.3), or `nil` for no library |
| `on_save` | `:any` | `:visualize_chart_saved` | the tag of the message of the next paragraph |
| `on_deploy` | `:any` | `:visualize_chart_deployed` | the tag of the deploy message (§19.6): the flat design, where save's carries structure |
| `source_defaults` | `:boolean` | `true` | whether a source's `default` (§2.3) is offered in the form; a host that binds every source by its own name sets `false` and the field is not shown (§19.10) |
| `tick_ms` | `:integer` | `500` | the period of the signals' tick while playing (§19.10) |

**The tick is the host's to forward.** A component receives no messages of its own, so the builder schedules its tick to the host's process — `{:visualize_chart_tick, id}` after `tick_ms` while playing — and the host forwards it with one line, `Visualize.Chart.Builder.tick(id, socket)`, which sends the component an update; a host that does not forward it sees signals that do not move and nothing else amiss. The demo host forwards it.
| `class` | `:string` | `nil` | placed on the builder's root element |

Saving sends `{on_save, id, design}` to the host LiveView process — `send(self(), …)` from the component's own callback, which runs in that process — where `design` is `Visualize.Chart.stack/1` of the enabled layers, the same map the preview drew. The `id` is the component's, so a page with two builders tells them apart. That message is the entire output of the component: it pushes no event, patches no URL and touches no store the host did not give it. The host handles it in `handle_info/2` and decides what a saved design means.

The editing state is initialised once, in the component's `mount/1`, and is not reset by a parent re-render: a host that re-renders with the same `layers` finds the same layer selected and the same layers disabled. A host that gives a *different* `layers` list replaces the layers and keeps the panel it was on, since the panel is the person's place in the tool and the layers are the document.

### 18.3 The store

**Implemented.** A host that wants to offer a library of saved fragments gives `store`, a module implementing the `Visualize.Chart.Builder.Store` behaviour. The library is the host's — the builder neither knows where a fragment is kept nor when it is written — and the behaviour is three callbacks:

| Callback | Contract |
|---|---|
| `list/0` | Every stored fragment's name, in the order the picker offers them. A name is any term the host chooses; the builder prints it with `to_string/1` and hands it back unchanged. |
| `get/1` | `get(name)`: `{:ok, fragment}` for a stored fragment — a design map, as a layer is — or `:error` when the name is not stored. |
| `put/2` | `put(name, fragment)`: `:ok` when the fragment is stored under the name, replacing what was there, or `{:error, reason}`, whose reason the builder shows and does not interpret. |

Nothing in the behaviour validates: a fragment is a fragment (§8), and a store that hands back a map the design cannot use fails where every other bad fragment fails — in the preview, by path (§18.4). `store` left `nil` is a builder with no library, which is the default and the whole of what changes.

### 18.4 The preview

**Implemented.** `Visualize.Chart.Builder.Preview.panel/1` is the pane that draws what the stack currently says, and it is the only place the builder renders a chart. It takes the stacked design, the pool and the variables, and shows one of two things:

- `Visualize.Chart.render/2` of `Visualize.Chart.apply/2` of the design over `sources:`, `vars:` and `theme:` — the chart, as any consumer would draw it; or
- the faults, when application returns them: one line per error, `Visualize.Chart.Validator.format/1` of it, ordered by path as the validator orders them (§10.1). An incomplete design — a fragment with no `frame`, a mark naming a scale no layer declares — is the normal state of a design being built, so the error list is a panel of the tool and not an error page.

A fault the *frame* raises rather than reports — a value a scale cannot take, a theme name nothing resolves — raises here as it does anywhere else (§7.3): those are faults of the data or of the host's pool, not of the design being edited, and hiding them in a panel would be hiding a bug in the host.

**The pane draws with paths, and says which node is open** (#259, #261). The chart is rendered with `paths: true` (§4.7), so every node it draws carries `data-node`, and the `<svg>` shell carries `data-builder-selected` with the open node's label (`selected`, `nil` for none) — the two attributes the graph's hook reads to select by click and to outline the open node (§18.16). The pane draws nothing else differently: a host rendering the same design through `Visualize.Chart.render/2` gets the markup without the paths, which is why the option exists.

The preview draws the **enabled** layers stacked, so disabling a layer is how a person asks what the design looks like without it, and it draws through the ordinary path — `Visualize.Chart.apply/2` then `Visualize.Chart.render/2` — so what the preview shows and what the host gets from the saved design cannot differ.

### 18.5 The nodes of a fragment

**Implemented** (work item 2 of #54, D-86). A fragment is a tree of nodes (§1.2), and the editor edits one node at a time. `Visualize.Chart.Builder.Editor.nodes/1` is that list: one entry per node the *schema's own walk* reaches in a fragment, so no kind, key or path is written by hand and a node kind added to the schema becomes editable with no edit to the builder.

| Key | What |
|---|---|
| `path` | the keys and list indexes from the fragment to the node: `[]` for the fragment itself, `[:frame]`, `[:frame, :scales, :x]`, `[:marks, 0, :channels]` |
| `kind` | the node kind at that path (§1.2), which is what `Visualize.Chart.Schema.describe/1` is asked for |
| `label` | the path as a person reads it: `design` for the root, else `frame.scales.x`, `marks[0].channels` — the spelling `Visualize.Chart.Validator.format/1` uses for an error's path (§10.1) |

The walk starts at the `:design` kind and descends by the type of every key the node actually carries: a `{:node, kind}` is one node at that key, a `{:map, {:node, kind}}` is one node per declared name in name order, a `{:list, {:node, kind}}` is one node per element at its index, and a `{:one_of, …}` that admits a node kind is that node when the value is a map — which is what makes an inline `theme` (§2.5) editable and a named one a value. Nothing else is descended into: a text, an extent, a channel and a reference are *values* of the node that carries them, and are edited there (§18.6). Entries are in the order the walk reaches them, the root first, so the list reads as the fragment does.

A key a fragment does not carry has no node, because a fragment is not a whole design (§8): the editor offers what is there. Adding a node is adding the key, which is the same edit as any other.

### 18.6 Widgets and values

**Implemented.** Which control a key gets is a function of its type (§1.4) and of nothing else: `Visualize.Chart.Builder.Editor.widget/1` takes a `t:Visualize.Chart.Schema.type/0` and returns the control, and `Visualize.Chart.Builder.Editor.parse/2` reads a submitted string back as a value of that type. The two are the whole of the editor's knowledge of values, and both are total over the schema's types, which is the property that says the editor cannot fall behind it.

| Type | Widget |
|---|---|
| `:boolean` | `:checkbox` |
| `:integer`, `:number` | `:number` |
| `{:enum, allowed}` | `{:select, allowed}` |
| `:string`, `:name`, `:field`, `:size`, `:font`, `:slot`, `:text`, `{:ref, _}` | `:text` |
| `:colour` | `:colour` — a well showing the colour (§19.10) |
| `{:list, scalar}` — a list of fields, names, strings or numbers | `{:items, scalar}` — a list of items (below) |
| every other type — `:channel`, `:field_ref`, `:extent`, `:anchor`, `:term`, `{:list, :term}`, `{:map, _}`, `{:node, _}` | `:textarea` |
| `{:one_of, [first | _rest]}` | the widget of `first` |

`Visualize.Chart.Builder.Editor.parse/2` reads a `{:one_of, …}` as its first alternative too, the one whose widget the control is, so what a person can type and what the reader accepts are the same thing.

**A drawn enum is chosen by its picture.** Some enums name a *look* — the join of a stroke, the shape of a curve, a symbol, a side — and choosing a look by reading its name is the opposite of what a drawing tool does. Where `Visualize.Chart.Builder.Glyphs.drawn?/1` says a key's values have a picture, the form draws the `{:select, allowed}` as a **radio group of glyphs**: one `<label class="vis-builder-glyph">` per allowed value holding the SVG `Visualize.Chart.Builder.Glyphs.glyph/2` draws for it, the word as the option's title and accessible name, the chosen one checked. The widget and the reader are unchanged — a radio submits the word the select would, and `parse/2` reads it the same — so this is a face of the control, not a new type; it is decided by the *key* and not the type because one enum type (`top`, `bottom`, `left`, `right`) is a side on an axis and an anchor on a label, and the pictures differ.

| Key | Drawn as |
|---|---|
| `stroke_style` | a square's edge stroked single, double, inside or outside |
| `effect` | a square plain, with a shadow, or blurred |
| `vertical_align` | a block of text above, across, on or below the point's line |
| `stroke_linejoin` | a corner joined miter, round or bevel |
| `stroke_linecap` | a stroke's end butt, round or square |
| `curve` | the interpolation of one short polyline, by `Visualize.Shape.Line` itself |
| `symbol` | the symbol, by `Visualize.Shape.Symbol` itself |
| `side` | a plot with that edge marked |
| `anchor`, `position`, `text_anchor` | a box with the place marked |
| `orientation` | bars standing, or lying |
| `kind` of a frame | cartesian axes, a polar ring, a globe, a facet grid |

Every other enum stays a select of its words; `Glyphs.glyph/2` is total over the drawn keys' values, which a test walks.

**A text field is a text field.** A `:text` (§7.1) is a box holding the string with its holes — `Uptime for #{var(:host)}` — whichever form the layer holds it in, and `parse/2` keeps what was typed: a hole that does not read is the validator's fault under the field, not a refusal at the box. A variable reaches a text as text among text: a chip dropped on the box is inserted at the caret as `#{var(:name)}` by `Visualize.Hooks.Builder` — the browser is the only party that knows the caret — and the box's own change writes the string; `bind_field` on a text key does nothing, since a text is never bound whole. `meta.name` is a `:text`, so a title can carry a variable in its middle.

**A source's `fields` is the columns to choose from** (#251). In a source's form the `fields` key — a `{:list, :field}` — renders not as typed items but as the `ls`-style list of §19.10 over the **columns the source's rows have**: the first row's keys under the source's name in the pool the chart binds (the host's sample rows, or the chart's signal), sorted, each a checkbox (`fields.pick`), the declared ones **highlighted**; ticking adds the column, unticking removes it, and the write is the whole list in the list's order. A column the source declares but the rows lack is shown highlighted and marked *not in the rows*, so a declaration never vanishes; a variable item stays a chip in a row of its own beneath, with its ×, since a variable is not a column; the **+** box stays beneath for a column the rows do not have yet — a design may promise one a future host supplies — and a chip drop still adds a variable. A source whose name the pool lacks has no columns to offer and shows the items list below. The columns reach the form as `columns` (name to columns) and, for a source site keyed in the layer's context, `source_name`.

**A list of scalars is a list of items.** A `{:list, scalar}` key — a source's `fields`, a theme's `series` colours — renders as rows, one per item with its text and an **×** that removes it (`list_remove`, by index), and a **+** box whose Enter adds one item read by the element's type through `parse/2` (`list_add`); a blank adds nothing. Both write the whole list, as the schema says a list is one value; removing the last item removes the key. A variable in the list renders as its chip, and a chip dropped on the list adds the variable as an item — `fields: [:t, var(:ycol)]` — which is how a source declares the column a variable chooses, matching the mark whose channel is the same variable (§19.9). Lists of nodes — `marks`, `axes` — are not this: they are nodes, each with a form, and the strip walks them.

**A fill is a fill style.** A style's `fill` (§3.1) is written by a person as *none*, *solid*, a *linear gradient* or a *radial gradient*, and the form shows the fill block as **two columns and two rows**: the *style* — four glyphs named `fill_style` — at the top left with the **opacity** (`fill_opacity`, titled *opacity*) beside it at the top right; below them the fill's **colour** (the `fill` field, titled *colour*) at the left and its remaining **number** at the right. A field's title is the word a person uses — *colour*, *opacity* — where the key's name would only repeat the block's:

| `fill_style` | Writes | Colour (bottom left) | Number (bottom right) |
|---|---|---|---|
| `none` | `fill: :none` | the hatched well | — |
| `solid` | `fill:` the well's colour — the paint's first stop when the fill was a gradient, else the theme's `:series_1` when it was none or unset | the `fill` well | — |
| `linear` | a gradient declared under `defs` (§2.7) as `kind: :linear` and `fill: {:paint, name}` | the first stop's well (`fill.stop.0`) where the fill's well stood, the last stop's (`fill.stop.1`) below it | the **angle** as a box with a scrubber (`fill.angle`, `fill.angle.range`) |
| `radial` | the same with `kind: :radial` | the two stop wells | the **centre** as two boxes (`fill.centre.x`, `fill.centre.y`) |

For a gradient the fill's well *is* the first stop — there is no third swatch showing the paint — so selecting a well or dropping a patch on it writes that stop; the stops keep the opacities they were declared with (`0.8` fading to `0.1` for a fresh gradient, the area chart's convention) and `fill_opacity` is the opacity a person sets. The gradient is **named for the style** it fills — `<style name>_fill`, `marks[0].style` becoming `marks_0_style_fill` — and is declared in the same layer, under `defs`, when the style is picked; picking it again keeps the declaration and its colours. Picking *solid* or *none* leaves the declaration where it is — a `defs` entry no fill refers to is harmless and a person may come back to it. `fill_style` and the `fill.…` controls are read by the builder, not `Visualize.Chart.Builder.Editor.changes/2`, since they write a second node: `fill_style` declares and writes the fill, `fill.stop.<i>` and `fill.stop.<i>.slot` write a stop's colour as a well's would (a chooser on a selected stop well writes the same names, §19.10, and a patch drops onto a stop well as onto any well), `fill.angle` and `fill.angle.range` the angle, `fill.centre.x` and `fill.centre.y` the centre. A `fill` that is a variable or a binding shows its chip as any field does and no fill style. A well whose value is a paint, anywhere else a well shows one, shows the paint's first stop's colour with the paint's name as its title.

**Line height shows its points.** The `line_height` slider (§14.2) writes the factor; beside its box the form prints the points between lines it means — `font_size × (line_height − 1)`, from the node's `font_size` or the theme's — so a person who thinks in points reads the number they know.

**A face is one control over two keys.** A style's `font_weight` and `font_style` (§3.1) are two CSS axes, and a person names their product — *Regular, Italic, Light, Light Italic, Medium, Medium Italic, Bold, Bold Italic*. The form shows the two keys as one **face dropdown** in the `font_weight` field's place — a `<select name="font_face">` of the eight, each option drawn in its own weight and slant, the node's face selected — and `font_style` has no row of its own; the font panel (§19.10), which has room, shows the same eight as a list of radios under the same name. `Visualize.Chart.Builder.Editor.changes/2` reads a `font_face` as two writes, the weight word and the style word (`light_italic` is `font_weight: :light, font_style: :italic`; `regular` is `:normal, :normal`), where `change/2` reads every other control as one; the builder applies each write as it would the control's own. The face a node shows is `Visualize.Chart.Builder.Editor.face/2` of its two values — an integer weight is shown as the nearest of 300, 400, 500 and 700 and is left as written until a face is picked, and a missing key reads as `:normal`. The font panel (§19.10) shows the same list under the same name.

**A ranged number is a slider over its box.** A key whose spec carries a `range` (§14.2) renders its box and `<input type="range" name="key.range">` together in one `<span class="vis-builder-ranged">` the size of the box — the box first, the slider after it — and the stylesheet lays the slider over the box: the slider fills the box's whole height, is about 70% transparent (`opacity: 0.3`) so the number under it stays readable, draws its track as a **bar from the left edge to the dot** in the accent colour at low opacity and nothing after it — so the box reads how far along its range the value stands — and draws its thumb as a small round dot centred on the current value, half either side of it. The bar's extent is the value's fraction of the range, `--vis-builder-scrub`, set by the render and kept under the dot by `Visualize.Hooks.Builder` while it is dragged. The slider passes pointer events through (`pointer-events: none`) and only its thumb takes them, so a click on the number selects it to type and a drag of the dot moves the value while the preview redraws; the box stays for typing, and for a `:size` key it still takes a slot word. The tab order reaches the box first and the dot after it. The chooser's large slider (§19.10) stays a bar of its own, since the context has room for one. `Visualize.Chart.Builder.Editor.change/2` reads `key.range` as the key itself, with the key's type, so a slider's write is the box's write. A value typed outside the range is kept, since the range is a control's span and not a rule. `stroke_dasharray` draws its pattern beside the box — a short line with the value as its `stroke-dasharray` — so a pattern is seen, not decoded.

A `:textarea` holds the value as `inspect/1` writes it and `parse/2` reads it back as a **literal**: the string is parsed with `Code.string_to_quoted/1` — parsed, never evaluated — and the quoted form is accepted only where it is a number, a string, an atom, `true`, `false`, `nil`, a list, a tuple, a map, a `%Visualize.Chart.Var{}` or a `~U` sigil, which is the whole vocabulary a design may contain (§1.4). Anything else — a call, an operator, a variable, any other struct — is `:error`, so a design map cannot acquire a function or a term the codec has no form for (§11). That the reader is one walk over the literal grammar rather than a rule per type is what keeps it total: a type added to the schema needs no case here.

The other widgets read what their control can produce: a checkbox is `true` or `false`, a number is an integer for `:integer` and an integer or a float for `:number`, a select is the listed atom the string names, a `:text` control is the string itself for `:string`, the atom of the string for a name, a field, a slot or a reference, and otherwise the loose reading a person expects — a leading `:` is an atom, a numeral is a number, and everything else is the string, which is how `#3b6fa8` reaches a `:colour` and `:series_1` reaches the same key as a theme slot. A blank string is `:error` for every type, and blanking a control is how a key is removed rather than set to nothing.

Reading an atom from a submitted string creates it, as `Visualize.Chart.from_json/1` does for the same reason (§11.1): a design is authored, and its names are the author's vocabulary. A host that exposes the builder to an untrusted author bounds that itself, as it does for the JSON form.

### 18.7 The form and its errors

**Implemented.** `Visualize.Chart.Builder.Editor.panel/1` renders one form for one node: the *facets* of the node's keys as tabs, in the order of §1.3, and the keys of the open tab in the order of the node's table in this document — which is the order `Visualize.Chart.Schema.describe/1` returns them in, so the form reads as the specification does. A facet no key of the *node kind* carries has no tab — the tabs are the kind's, not the node's, so every key the kind declares is reachable and adding one is the same edit as changing one — and a kind whose keys are all one facet has one tab.

**Keys that carry a group are shown under its heading.** Where the open tab's keys carry a `group` (§14.2) — a style's — the form is blocks: each run of keys with one group is a `<fieldset class="vis-builder-block">` with the group's word as its `<legend>`, in table order, and a key with no group stands on its own between or after them. A style form therefore reads *extends*, then **fill**, **stroke**, **font**, **position**, **effects**, then *class*, *curve* and the rest — five blocks a person can find a stroke's cap in without scanning past the font, rather than nineteen keys in one list. The blocks are a view of the table and change nothing about what a key writes; a kind whose keys carry no group renders as it did.

Each key is a `<label>` holding its name, the control `Visualize.Chart.Builder.Editor.widget/1` chose, the value the node carries, and — where the node does not carry the key — the schema's default as the control's placeholder, so what a key would be if left alone is visible without being written into the design. The key's own errors are listed under its control: an error of the validator whose path is exactly this node's path followed by this key (§10.1), rendered by `Visualize.Chart.Validator.format/1`. An error at a path no key of the open tab owns is not shown twice — it belongs to the node that owns that path, and the tab that holds it.

The errors are the *stacked* design's, the ones the preview lists (§18.4), and a layer's node sits at the same path in the stack as in the layer unless a higher layer replaced it — which is the one case where a fault shown against a key belongs to another layer's value at that path. Recomputing them per layer would mean validating a fragment, and a fragment is not a design: it is the stack that is validated, which is exactly what §8 says.

Editing a control writes the parsed value into the layer that owns the node (§18.15; the selected layer, before #255) at the node's path, and a control blanked removes the key. Nothing else happens: the layer is a fragment, the stack is recomputed, the preview redraws, and no validation runs until application does it (§8).

### 18.8 The stack panel

**Implemented** (work item 3 of #54, D-87). `Visualize.Chart.Builder.Layers.panel/1` is the list of layers, in the order `Visualize.Chart.stack/1` reads them — the higher layer last — because that is the order the cascade is defined in and a panel that reversed it would be teaching a person the opposite of the specification. A layer's name is the one the `{name, layer}` pair carries, and its zero-based position where it has none, exactly as `Visualize.Chart.explain/1` names it (§17.1).

Each layer offers three things and no more: **select** it, so the editor edits it; **disable** it; and **drag** it to a position, which is what changes precedence (§18.10, §18.17). Moving is dragging and nothing else — the panel carried up and down buttons beside every layer, which is two more controls per row to say what one gesture already says, and a stack of any depth is not reordered a step at a time. The `reorder` event is unchanged; only the second way of raising it is gone. Disabling is not deleting: a disabled layer stays in the list and is dropped from the stack, so "what does this look like without the house theme" is one click and one click back. The builder's design — what the preview draws and what saving sends (§18.2) — is `Visualize.Chart.stack/1` of the enabled layers, which is where disabling has its whole effect.

**The toggle is an eye, and a library layer wears a lock** (#263). The enable/disable control is an eye glyph — open for an enabled layer, struck through for a disabled one — drawn inline by `Visualize.Chart.Builder.Glyphs.icon/1` in `currentColor`, as the context's icons are, so the control says what it does; its accessible name stays *Disable name* / *Enable name* and its event `toggle_layer`. A layer whose site **references** a library entry (`Use.ref` set — a linked drop, or a site of a stored composite, §18.17) carries `vis-builder-layer-locked` and a **lock** glyph before the eye: the layer is the library's word, and in the chart it is **read-only** (§18.15). The lock is a button — `open_layer` with the layer's position — that opens the entry at the chart level as the library click does (§19.9), which is how a library entry is changed: edit it there, save it, and every chart that references it takes the change. The row's keys gain `o`, which opens it too, and its title ends *from the library: o to open*. An inline site — a copy, a `+` site, a decomposed template — has no lock and is edited as it always was.

**A row opens to show what the layer declares** (#281). The six-dot drag affordance is gone — the row is the drag source and says so in its title — and in its place each row carries a **›** disclosure (`toggle_layer_detail`; `expanded_layers`, a set of use ids kept while a person works, as `library_open` is; `Right` and `Left` on a focused row open and close it). Open, the row lists beneath it the **kinds the layer's own contribution declares** and nothing more (#285) — in the schema's order, `meta`, `theme`, `sources`, `vars`, `styles`, `defs`, `frame`, `scales`, `axes`, `marks`, `labels` — a kind the layer does not declare not shown, since an empty row would be the `+` menu's job; the details are the inspector's. `Visualize.Chart.Builder.Layers.declared/1` is the reading, over the layer's contribution placed where the design keeps its kind (`Visualize.Chart.Builder.Stack.contribution/2`, §19.3), so a `style` site lists `styles` and an `axis` site `axes`. Each kind is a button — `open_declared` with the layer's position and the kind — that selects the layer and opens the kind's page in the inspector, through `opened/1` over the kind's root path: `frame`, `scales`, `axes` and `meta` open the frame's page, whose sections hold them (§18.15); `styles`, `sources`, `marks` and `labels` their own root; `vars` the variables panel (§19.10); `theme` and `defs` whatever node the chart has there, else the layer's first. A disabled layer's list is muted with the row; a locked layer's is listed the same, its pages opening read-only (#263). **The open row's first line is a › Mask item, the kinds beneath it** (#316, #319; `toggle_layer_mask`, positions kept in `mask_layers` as `expanded_layers` are): opened, it lists the layer's mask checkboxes — one per maskable path of the layer's contribution (`Visualize.Chart.Builder.Masks.rows/2` over `Stack.unmasked/2`), checked where the path is masked, each writing `mask` with the layer's position — with the notes that go with them, *disabled — every key is masked, so the layers below show through* and *this layer sets nothing yet*. The mask is the site's own and never the entry's (§18.15), so a **locked library layer's mask is editable** there: that is how a library item is used in part, the chart choosing which of its keys show through. The checkboxes have no other home; the context panel's layer context is the site's key and its free variables (§19.10).

| Function | Contract |
|---|---|
| `Visualize.Chart.Builder.Layers.declared/1` | a placed fragment as the kinds it declares, in the schema's order |

Nothing here validates or copies a fragment: reordering a stack is reordering a list, and the design is recomputed from it.

**The Charts panel** (#243). The stack panel sits one level down: the sidebar is the **Charts** panel, a row per chart of the workspace (§19.9) — its name, a disclosure that expands or collapses it (`toggle_chart`), a close (`close_chart`) — the selected chart marked (`select_chart`), and beneath an expanded chart its layers as the stack panel above, with every gesture of it. The **+** on the Charts title adds a chart (`add_chart`): a new chart is one frame layer, since a chart minimally is a frame, named *chart n*. The **+** on a chart's row is the site menu of the next paragraph, for that chart. A layer of a chart that is not selected is selected by clicking it, which selects its chart first.

**A + on a chart's row adds an empty site.** At the right of the selected chart's row is a **+**; it opens a menu of the single kinds a site can be — theme, style, frame, scale, axis, source, var, mark, label; never composite, which comes from the library, and never design, which is Deploy's — and choosing one (`add_site`) inserts an empty inline site of that kind (`Visualize.Chart.Builder.Stack.empty/1`, `ref: nil`) directly below the selected layer, or at the end with nothing selected, selects it and opens its form. Its label reads *new style*, *new mark*, and so on until it is keyed or saved under a name. A name-keyed kind arrives keyless, so its row reads *not placed* until a name is given in the layer's context (§19.3): the honest state, since it has nowhere to be declared under yet.

### 18.9 The inspector

**Implemented.** `Visualize.Chart.Builder.Inspector.panel/1` is `Visualize.Chart.explain/1` rendered: one row per leaf path of the stack, ordered by path, with the value, the layer that set it and the layers it overrode (§17.1). It is the answer to the question a four-layer template makes unanswerable by eye — *which layer said this, and what did it replace* — and it is a view of one function, so what it shows and what `Visualize.Chart.stack/1` produces cannot drift.

A row carries its path and the position of the layer that set it, so clicking one selects that layer and opens the node that owns the path: the inspector is how a person gets from a value they can see to the layer they must edit. The node opened is the deepest node of that layer whose path is a prefix of the value's, which is the node whose form carries the key; a path no node of the layer owns opens the layer's root.

The two limits are `Visualize.Chart.explain/1`'s own and are shown rather than worked around: a value a higher layer discarded whole — a redeclared `:union` name, a replaced identified element — has no path in the result and so no row, and `overrode` names only the layers that wrote a value at the *same* path (§17.1).

### 18.10 The hook

**Implemented.** Two gestures need the browser, and they ship as one hook, `Visualize.Hooks.Builder`, which joins `Visualize.Hooks.js_code/0` under the export-uniqueness rule like every other hook (spec/10 §16, D-48). Dragging a layer onto another reorders the list and pushes the move; clicking an inspector row pushes the path and the layer it names. Everything else the panels do is a `phx-click`, because everything else is a server decision: a hook exists where the browser knows something the server does not — a drop position, a click on a row — and nowhere else.

### 18.11 The parameters form

**Implemented** (work item 4 of #54, D-88). `Visualize.Chart.Builder.Params.panel/1` is `Visualize.Chart.free_vars/1` rendered: one control per variable the stack still demands, ordered by name, with its default, whether it is required, and the paths it stands at (§17.2). It is the second inspector — `Visualize.Chart.explain/1` says where a value came from and `free_vars/1` says what is still open — and, like the first, it is a view of one function, so what it offers and what `Visualize.Chart.apply/2` will demand are the same set by construction.

The control is `Visualize.Chart.Builder.Editor.widget/1` of the **first use's `expects`** — the schema's type at the path the variable stands at (§17.2) — read back by `Visualize.Chart.Builder.Editor.parse/2` of that same type, so the parameters form and the fragment editor choose their controls from one table and a schema addition reaches both with no edit. A variable used at two paths of different types takes the first use's, in path order, and every path is listed beside the control so a person can see what they are setting.

What the form edits is the builder's own copy of the `vars` assign, not the assign: the host gives the values the builder *starts* with, and the parameters form is a person exploring a template, not the host changing its mind. The preview applies with that copy (§18.4), so the chart on the screen is the parameterised chart; the design saving sends is the design, which carries the variables and not the values, because a template's parameters are supplied at application and are not part of what is stored (§7.3).

A blank control removes the binding rather than setting it to nothing, so a variable falls back to its declared default, and a variable with no default is `required` and is what `Visualize.Chart.apply/2` will report as `{:unresolved, :var, name}` until something supplies it.

### 18.12 Import and export

**Implemented.** `Visualize.Chart.Builder.Document.panel/1` is the design's JSON form (§11), in and out.

**Export** is `Visualize.Chart.to_json/1` of the stacked design, and it therefore demands a *design*: the stack goes through `Visualize.Chart.from_map/1` first, and a fragment that does not validate is its errors, listed by path exactly as the preview lists them (§18.4). That is the honest failure — a half-built fragment has no JSON form because it has no version, no frame, or a reference to something nothing declares — and it is the same message a person is already reading in the preview.

**Import** is `Visualize.Chart.from_json/1` of a pasted document, and a document that reads **replaces the stack with its sites**: `Visualize.Chart.Composite.decompose/1` turns the flat document into one site per root — its theme, its meta, its frame without the scales and axes, then one keyed site per style, scale, source and var, one site per mark, per label, per axis — in the order the document is read, so every row is one kind and `flatten/2` of what the import made is the document again (`version` aside, which Deploy writes). A document is a whole design, not a layer of somebody else's stack, so what was in the stack is replaced, not joined. A document that does not parse is `{:json, message}` at the design's path and a document that parses but does not validate is the validator's errors, both shown in the panel.

Both are behind the optional `Jason` dependency (§11.1): without it each returns `{:missing_dependency, :jason}`, which the panel shows as its one error rather than as a crash, because a consumer without Jason has a builder that edits and previews and cannot import or export — which is exactly what the optional dependency means.

### 18.13 The shell and its stylesheet

Every section above describes a panel by what it *is a view of*, and none of them says where it sits or what it looks like. That silence was itself a decision, and the wrong one: a component whose panels are eight full-width blocks in source order is a component nobody reads, however honest each block is. The builder therefore has a shell, and it ships the stylesheet that draws it (D-94).

**The builder ships its CSS the way it ships its JavaScript.** `Visualize.Chart.Builder.css/0` returns the stylesheet as a binary, exactly as `Visualize.Hooks.js_code/0` returns the hook source (spec/10 §14), and `Visualize.Chart.Builder.styles/1` is the function component that renders it in a `<style>` element. The builder renders it at its own root, so a host with no asset pipeline at all — the examples application, a Livebook, a page assembled by hand — has a legible builder from the `<.live_component>` call and nothing else. A host that *has* a pipeline writes `css/0` to disk and drops the `<style>` by passing `styles={false}`, which is the same choice the hooks offer.

Two properties bound what the stylesheet may do, and both are testable:

- **Every rule is scoped under `.vis-builder`.** No bare element selector, no class of the host's, nothing at `:root`. The builder is a guest on somebody else's page and a stylesheet that restyled their headings would be a defect, not a theme.
- **Every colour and metric is a custom property declared on `.vis-builder`** — `--vis-builder-bg`, `--vis-builder-line`, `--vis-builder-accent`, `--vis-builder-radius`, and the rest. A host restyles by setting properties on the root element, not by out-specifying rules it did not write. A dark page is a short block of overrides, and no rule in `css/0` needs to know that dark pages exist.

| Function | Contract |
|---|---|
| `Visualize.Chart.Builder.css/0` | the stylesheet as a binary |
| `Visualize.Chart.Builder.styles/1` | the `<style>` element carrying it |
| `Visualize.Chart.Builder.Styles.css/0` | the stylesheet itself, as `Visualize.Hooks.js_code/0` is the hooks |
| `Visualize.Chart.Builder.Styles.styles/1` | the `<style>` element, which the builder renders unless `styles={false}` |
| `Visualize.Chart.Builder.Styles.default_path/0` | where a host with a pipeline installs it, beside the hooks |
| `Visualize.Chart.Builder.Styles.install!/0` | writes it there, as `Visualize.Hooks.install!/0` writes the hooks |

**The three regions.** The shell is a grid:

```
┌──────────────────────────────────────────────────────────┐
│ toolbar                                        [ Save ]  │
├────────────┬─────────────────────────────────────────────┤
│  LAYERS    │  design │ frame │ frame.scales.x │ marks[0] │
│            ├─────────────────────────────────────────────┤
│  ⠿ house   │  binding · channel · geometry · style       │
│  ⠿ shared  │                                             │
│  ⠿ panel   │  the form for the open node                 │
│            ├─────────────────────────────────────────────┤
│            │  preview                                    │
└────────────┴─────────────────────────────────────────────┘
```

The **sidebar** is the stack panel of §18.8, unchanged in order, contents and events: the layers in the order `Visualize.Chart.stack/1` reads them, the higher last. What the shell adds is that it *looks* like what it is — a fixed-width column of rows, each with a drag handle, a selected state and a dimmed disabled state. Dragging a layer already reordered the stack (§18.10); a bulleted list simply never said so.

The **main column** was the selected layer, and is now the chart (#255, §18.15); the tab strip across its top is how any of it is reached. A fragment is a tree and the labels say so — `frame`, `frame.size`, `frame.margin` — so the strip is two rows rather than one long line of dotted paths.

The **top row is every root the *stacked design* declares** — the frame first, since a chart minimally is a frame and its page opens with the chart's name (§18.8, §18.15, #257), then the rest in the schema's order — and not only the selected layer's. A design has seven node-bearing keys and no more — `meta`, `sources`, `vars`, `styles`, `frame`, `marks`, `labels` — so the whole vocabulary of a chart is seven short words, which fits in one row and answers the question a person actually asks. **The row is icons** (#314): each root is drawn by `Visualize.Chart.Builder.Glyphs.icon/1` — `frame` the plot's corner with an axis each way, `sources` the sine wave, `styles` a brush, `marks` two bars and a line, `labels` a tag, `theme` a swatch grid, `defs` a gradient disc, and any other root its first letter in a ring, so a root the schema gains later is never blank — with the root's name as the button's `title` and `aria-label`, shown on hover and read aloud, and the *needs* count as the badge it was (§18.13). The design's own root is not a tab: its keys are Deploy's (`version`) or sites of their own (`theme`, §19.8), so there is nothing at it to edit, and a layer opens on its first real node. Nor is `vars`: a declaration is made, defaulted and bound in the variable panel (§19.10), and a `var` site selected in the stack still opens its own form, since a site's form is its kind's.

**What the design still needs is marked where it is.** The faults the preview lists (§18.4) are counted under every node on their paths — `marks[0].data` is owed by `marks`, `marks[0]` and `marks[0].data` — and a tab or a chip with any fault under it carries `vis-builder-node-needs` or `vis-builder-chip-needs` in orange, with the count in its title (*marks of this layer — 2 things still needed*); an *elsewhere* tab included, since the need is the design's and not the layer's. In the form, a field with a fault at its path carries `vis-builder-field-needs` and the fault's words under its control (§18.7); a required key with no value is the commonest case. A `:required` fault is what "must have a value" means, and every other fault marks the same way, because the chart draws no better with a wrong value than with a missing one. The marks are a view of the faults and nothing else — one appears, one clears — and the colour is one token, `--vis-builder-needs`, apart from the warn colour a notice uses. The strip showing one layer's nodes answered *what is in this fragment*; a person asks *where are the marks in this chart*, and a builder that opens on a layer declaring no marks put the answer nowhere.

A root opens as the chart declares it, whatever layer is selected (#255): the page under a root is the composed design's, every section tagged with the layer that supplies it (§18.15), so *elsewhere* is no longer a state a tab can be in — a root the selected layer does not declare is drawn and opened as any other, and its sections say which layer owns them. A root nothing declares is not shown, because offering it would be an add-node control and §18.5 has no gesture for adding a key. The rule the *elsewhere* tab applied — *get me to the layer that owns this*, the inspector's row (§18.9) and the palette's style (§18.14) — now applies to every write instead: an edit goes to the layer that owns the node (§18.15).

The **second row** is the nodes under whichever root the open node sits in, each labelled by what it adds to the root rather than by its whole path, so `frame.size` reads as `size` under `frame`. A root that is not itself a node — `styles`, which exists only as the map its members live in — opens its first member, because a tab that opened nothing would be a tab for a node the fragment does not have. The root stays marked while a child is open, so the strip says where you are. Both rows scroll horizontally rather than wrapping, because a wrapped strip changes height as a person clicks through it. The facets of the open node (§18.7) are a row of chips beneath the strip, and the form fills the rest. The preview sits below the form in the same column, so an edit and its effect are on screen together.

The tab strip is a view of `Visualize.Chart.Builder.Editor.nodes/1` and of nothing else, which is the same discipline every other panel is held to: a node kind added to the schema becomes a tab with no edit here.

**Nothing in the shell is a capability.** No event, assign, message or panel signature changes because a shell exists; every panel remains independently renderable, which is what keeps the tests that assert on one panel's markup meaningful. The shell is where the panels are placed, and `css/0` is how they are drawn.

### 18.14 The style palette, and a reference as a choice

**A design's `styles` is a map of name to style node (§3), and a mark refers to one by name** — and until this section there was no way to *add* a name. §18.5 says "adding a node is adding the key, which is the same edit as any other", but no control added one, so a style could be edited only where some layer had already declared it. A mark's `style` fared no better: its type is `{:ref, :style}`, whose widget is `:text` (§18.6), so a person spelled a name into a box and learned from the error list whether it was one that existed.

`Visualize.Chart.Builder.Palette.panel/1` is the answer to both.

| Function | Contract |
|---|---|
| `Visualize.Chart.Builder.Palette.panel/1` | the palette: the declared styles, and the form that adds one |
| `Visualize.Chart.Builder.Palette.names/1` | the style names a design declares, in name order |

The palette is a view of the **stacked** design, because the stack is what a mark's reference resolves against: a style the house layer declares is available to a mark in the panel layer, and a palette that showed only the selected layer's styles would be lying about what a mark may name. Each row is the name, what the style declares, and a swatch — shown only where the style names a colour outright, since a stroke given as a theme slot such as `:series_1` has no colour until the theme resolves it, and a guessed swatch is worse than none.

**Creating** a style writes `styles.<name>` into the **selected** layer, because that is where every other edit goes, and the editor opens on the new node: creating a style and not being taken to it is half a gesture. The name is read with `Visualize.Chart.Builder.Editor.parse/2` at `{:ref, :style}`, so a name becomes an atom exactly as a typed reference already did (§18.6) and no second spelling of that rule exists. A blank name is a notice, not a style called `:""`.

**Selecting** one opens the node that owns it, in the layer that declares it — the highest such layer, which is the one whose value the stack takes, the same rule the inspector follows (§18.9). This is why the palette can be a view of the stack and still get a person to an editable node.

**A reference becomes a choice.** `Visualize.Chart.Builder.Editor.panel/1` takes a `refs` assign — the names a `{:ref, kind}` may take, by kind — and renders a select over them instead of a text box wherever it has them. `Visualize.Chart.Builder.Editor.widget/1` is unchanged and stays a function of the type alone, which is the property that makes it total over the schema (§18.6); the panel is what narrows a reference when it happens to know the names. A kind the caller knows no names for is still a text box, so the editor remains renderable over any node with no palette at all.

### 18.15 A root tab is one page of sections

The nodes of §18.13 are the top row — the root tabs. Beneath them the first drafts put chips for the open node's children and tabs for its facets, so a frame was *geometry / binding* beside *size, margin, scales.hour, axes[0]*, the geometry facet listing `size` and `margin` as textareas beside the chips that opened them, and a mark was five subtabs. **A root tab is now one page of sections** (#249): `Visualize.Chart.Builder.Page.page/1` renders the node under the open root — or, for a root that is a map or a list (styles, marks, labels…), a section per member — as collapsible sections (`<details>` with a `<summary>`, folded and kept through `toggle_section` in `collapsed`):

- the node's own keys grouped by **facet**, one section per facet in the order of §1.3, titled by the facet's word, the style groups of §18.7 inside the style section;
- a key that holds a **node** — `{:node, _}`, a map or a list of nodes, or a `one_of` whose value is a node — is not a textarea in its facet's section but a **sub-section inside it**, titled by the node's label, itself a page; so the whole subtree of a root is one page and nothing is listed twice;
- a section with a fault under it is marked (`vis-builder-section-needs`), as a chip was, so a folded fault still shows.

**The frame's page reads as a frame**: its `kind` first, bare, then the design's **name and description** — the `meta` node's fields, written to the layer's `meta` (created when the layer lacks it), so `meta` is no tab of its own — then **size**, one section holding the `size` node's width and height and the `margin` node's four together, then **binding** (the frame's `facet`), then its parts — scales, axes, legend, projection, viewport — each a section with its members as sub-sections. The frame's geometry facet, which held only `kind` beside its parts, is not a section of its own.

**The page is the chart's, and every section says which layer it comes from** (#255). The first page of sections was the selected layer's slice of the design: with the demo's `primary` declared in `shared` and `house` selected, the sources tab listed nothing, and after a signal was added it listed `signal_1` alone — the vocabulary of §19.9 makes the *chart* the thing described, and a tab that showed one layer's part of it without saying so read as the chart having lost a source. The page under a root is now the **composed design's** — `Visualize.Chart.Builder.Stack.design/3`, what the preview draws — and the nodes of §18.5 are walked over it, so every root tab lists what the chart has whatever layer is selected. Each top section, and each sub-section whose owner differs from its parent's, carries a **tag** naming the layer that supplies the node (`vis-builder-section-layer`); a node two layers declare shows once, tagged with the highest of them, since that is the layer whose word the cascade keeps (§17.1). **The selected layer scopes the drawing, not the content**: a section whose layer is not the selected one is drawn muted (`vis-builder-section-other`) — readable and editable, but visibly someone else's — so selecting a layer in the Charts panel brings its sections forward and pushes the rest back, and the strip's *elsewhere* state (§18.13) has nothing left to say.

**An edit goes to the layer that owns the node.** The owner of a node is the highest enabled layer that gives any value under its path — `Visualize.Chart.explain/1` over the placed layers (§17.1, `Visualize.Chart.Composite.place/2`), the provenance the inspector already shows (§18.9) — and every write a form raises for a node goes there: a field, a list add or remove, a tick in a picks list, a colour or a chip dropped, a style stacked. The write reaches the layer at its *own* path — a site of one kind holds its body under the kind's key (§19.3), so the composed `sources.primary` of a `source` site keyed `primary` is written at that site's `[:source]`. A node no layer owns yet — a new declaration under a root, the frame's `meta`, a signal's source (§19.10), a **+** site — goes to the **selected layer**, as before: what exists is edited where it is, and what is new is made where the person is standing.

**A locked owner refuses the write** (#263). Where the layer a write would go to is a referenced site (§18.8), nothing is written and the notice says *name is from the library — open it to edit*: a field, a list add or remove, a tick, a drop, a style stacked — every write of the paragraph above. The page draws it so: a section whose owner is locked, and the page of a locked selected layer, render their fields disabled (`vis-builder-form-locked`, the fields inside a disabled `<fieldset>`) under the note *from the library — open it to edit*. The site's own parts are not the entry's and stay editable at the site: its `vars` bindings (§19.4, the sanctioned adaptation of a linked layer), its `key`, its `mask` and its enabled state. `Visualize.Chart.Builder.Editor.form_body/1` takes `locked` for the rendering; the refusal is the builder's, in `update_layer/4` and every write that resolves an owner.

| Function | Contract |
|---|---|
| `Visualize.Chart.Builder.Stack.placed/2` | the enabled uses as the design's layers, `{id, fragment}` in stack order, each resolved and placed where the design keeps its kind; a keyless name-keyed site is left out |
| `Visualize.Chart.Builder.Stack.local_path/3` | the path a design path has inside a use: `[:source | rest]` for a `source` site's `[:sources, key | rest]`, and so for every placed kind; a design-level site's path as it is |
| `Visualize.Chart.Builder.Stack.contribution/2` | one use's contribution placed where the design keeps its kind, resolved through the flattening fetch as `placed/2` resolves it, its mask ignored — what a layer's row lists (§18.8, #283) |
| `Visualize.Chart.Builder.Stack.locked?/1` | whether a use references a library entry and so is locked in the chart — read-only, opened to edit (§18.8, §18.15) |
| `Visualize.Chart.Builder.Stack.copies/3` | an entry as the inline sites a copy of it is (§18.17): a composite's sites each holding what its use contributed, labelled by the referenced entry's name or the composite's own, with the composite's vars and signals; any other body as one site named for the entry; ids left for the caller to issue |

**Every form intercepts its submit** (#274). A browser submits a form on Enter in a text box whatever the page meant, and a `<form>` LiveView is not told about — one with no `phx-submit` — is submitted as a plain GET to the page, which reloads it and loses the editing session. Every `<form>` the builder renders therefore carries `phx-submit`: the ones whose Enter means something have their own event, and every other carries `submitted`, which the builder answers with nothing, since `phx-change` already wrote every field and the *+ add* box's `phx-keydown` already pushed its item. A test renders the builder in every state and holds it: a form without `phx-submit` fails the suite rather than reloading a page.

**A guessed field says so** (#267): a channel a placed mark bound by guessing carries `vis-builder-field-guess` and the title *guessed from the source's fields — check it* until it is edited; `Visualize.Chart.Builder.Editor.form_body/1` takes `guessed`, the labels so marked.

**Every form knows its node.** Every form on a page carries its node's label — `data-builder-node`, and a hidden `_node` input — so an edit, a field selection, a chip drop, a colour drop, a list add or remove in any section aims at that node: the builder selects it first (`aimed`), and the context — the colour chooser, the style stack — follows the node last touched. `Visualize.Chart.Builder.Editor.form_body/1` is that form alone, of one facet's keys or of the listed ones; `Visualize.Chart.Builder.Editor.panel/1` still renders a node as facet tabs over one form, for the style panel and for a host that wants the smaller thing.

| Function | Contract |
|---|---|
| `Visualize.Chart.Builder.Editor.facets/1` | the facets a node kind has, in the order of §1.3 |

**A group with nothing to choose is not rendered.** One facet is not a choice, so a lone facet chip never appears; a node whose root has no other children and whose kind has one facet has no strip at all. This is the same rule the top row already follows in spirit — a control that cannot change anything is not a control — and it is what makes the strip mean "here is what you may pick".

### 18.16 The workspace, and the library as a tree

The shell of §18.13 put the stack beside one editing column. The workspace is four regions across (#243 — the drawing-tool shell):

```
┌───────────┬───────────┬──────────────────────────────┬──────────────────┐
│ LIBRARY   │ CHARTS    │                              │ CONTEXT          │
│ a tree of │ the       │ the graph: the selected      │ node icons, chips│
│ the store,│ charts,   │ chart drawn, alone           │ inspect · colour │
│ folding   │ each with │                              │ variables        │
│ to a rail │ its layers│                              │ form / signals / │
│           │           │                              │ fonts / pickers  │
│           │           │                              │ 400px, adjustable│
└───────────┴───────────┴──────────────────────────────┴──────────────────┘
```

The **library** is the left-most column, at the height of the viewport and scrolling on its own, so browsing a large library never moves the chart; it **folds to a rail** (`library_open`, a person's choice kept while they work) with one button to unfold it, so the graph may have the room; and **every top-level header in it folds** (#355) — a category's in the group view, a kind's in the kind view — the header a button carrying `aria-expanded`, its items hidden when folded and the header staying with the count of what it hides, so a folded library still says what it holds. The folded headers are the builder's `library_folded`, a set of header names toggled by `library_toggle` with `phx-value-name`, kept across a view switch and a store change, empty by default so nothing moves until a person folds it; a host passes a starting set as the assign. A sub-group's `<h4>` does not fold. A fold hides and does not disable: a folded section's items are not on the page, so they are neither drop sources nor in the focus order until it unfolds. The **charts** sit beside it (§18.8), because a fragment travels from one to the other and a gesture across two adjacent columns is a gesture. The **middle is the graph** — the selected chart's preview and nothing else; a chart that is not a composite (a style opened from the library) has no chart to look at and the middle says so. The **context** is the right-most column, the inspector (§18.18): **400px wide by default and adjustable** — a handle on its left edge is dragged, `Visualize.Hooks.Builder` in scope `resize` reporting the width (`context_width`, kept between 300 and 800) — with the selected chart's node icons and chips always at its top and a row of three panels beneath: **inspect** — the selected node's form (what the first draft's middle column held) and, under it, the layer's context of §19.10 (its key, its free variables, its style stack — its mask is under its row, §18.8), with the signals under the `sources` root and the font panel under `styles` (#314); **colour** and **variables**, the pickers of §19.10. Selecting a node, a root or a layer opens *inspect*; a colour field its picker. The toolbar — New, Save as, Save, Deploy — stays above the columns.

**The graph selects** (#259, #261; proposal B of #242). The graph is drawn with paths (§18.4) and carries `Visualize.Hooks.Builder` in scope `graph` (spec/10 §16): a click anywhere in the chart finds the nearest element carrying `data-node` and pushes `pick` with the node's label; the builder opens that node — `opened/1`, as the inspector's row does — **in the layer that owns it**: the highest enabled layer supplying a value under its path, the provenance of §18.15 that every write already follows, selected before the node is opened. A masked node is not drawn, so it cannot be clicked; a node two layers declare opens in the one whose word the cascade keeps; a label the composed design has no node for is a no-op, and a click outside the frame's group — the svg's own margin — hits nothing. A click on the plot area opens `frame`, since the frame's group is the element under it. **Hover and selection are drawn**: an element under the pointer that carries `data-node`, and none of whose descendants does, is outlined from the stylesheet alone (`:hover`, `--vis-builder-accent`); the hook marks the drawn node whose path is the longest prefix of `data-builder-selected` — `marks[0]` while `marks[0].style` is the open form, since the graph draws the mark and not its facets — `vis-builder-graph-selected` on mount and on every update, so the outline survives the re-render an edit causes and is steadier than hover. Nothing else moves: the strip, the sections and the pickers are unchanged, and the graph is one more way to reach `opened/1`.

**The components palette, and a drop that snaps to the frame** (#262, proposal C of #242; #266). Above the library's tree sits a fixed **Components** section — *axis*, *legend*, *title*, *label*, and one row per mark type of `Visualize.Chart.Schema.mark_types/0` — each row carrying `data-builder-component` (`axis`, `legend`, `title`, `label`, `mark:line`, …), draggable, and operable with `Insert`/`i`, which places it in its home region. The graph accepts a component or a library entry dropped on it and the hook pushes `place` with what was dropped and the pointer in **chart coordinates** — the drop's client position scaled through the `<svg>`'s `viewBox` (spec/10 §16.3) — and the builder classifies the point against the frame the preview drew: `Visualize.Chart.Builder.Place.region/2`, a pure function of the point and the frame's `size` and `margin` (the schema's defaults when the design does not apply), which is `:plot` inside the plot area, else `:top` or `:bottom` when the point is in those bands, else `:left` or `:right` — so a corner belongs to the top or bottom band, where the title and the x axis live. `Visualize.Chart.Builder.Place.node/4` says what a component means in a region:

| Component | `:top` | `:bottom` | `:left` | `:right` | `:plot` |
|---|---|---|---|---|---|
| axis | `side: :top`, scale `x` | `side: :bottom`, scale `x` | `side: :left`, scale `y` | `side: :right`, scale `y` | as `:bottom` |
| title | `anchor: :title` | `anchor: :caption` | `anchor: :title` | `anchor: :title` | `anchor: :title` |
| label | `anchor: :subtitle` | `anchor: {:axis, :x}` | `anchor: {:axis, :y}` | `anchor: {:frame, :top_right}` | `anchor: {:frame, <nearest corner>}` |
| legend | `position: :top` | `position: :bottom` | `position: :left` | `position: :right` | `position: <nearest of the eight>` |
| mark *type* | a mark of the type, wherever it lands | ″ | ″ | ″ | ″ |

An axis, a label and a mark are **sites** of their kind — inline, as a `+` site is — inserted above the selected layer and selected, the placed node opened; a legend is a node of the frame, written through the ownership rule of §18.15 (the layer that owns `frame.legend`, else the frame's owner, else the selected one). **An axis declares the scale it needs**: when the composed design has no scale of that name, a `scale` site keyed `x` or `y` — `%{kind: :linear, domain: :auto}` — is inserted beneath the axis; scales are not visual and are never dropped. An axis dropped where the design has one on the same scale and side replaces it, since that pair is an axis's identity in the cascade (§8.2) — and to replace it the new site is inserted above the layer that owns the old one, when that is higher than the selected layer, so the drop is what draws. A legend takes the first scale of kind `:ordinal` the design declares, and is the notice *a legend needs a colour scale* when there is none. **A placed mark guesses its channels** (#267): it takes the chart's **first source** — the one the last mark binds, else the first declared by name — and binds its **required** channels (`Visualize.Chart.Schema.channels/1`) to that source's fields in the fields' order, `[hour, value]` on a `:line` being `x: hour, y: value`; fewer fields than channels leave the rest unbound, which the needs marks say, and a chart with no source places `%{type: type}` alone. `Visualize.Chart.Builder.Place.guess/2` is the reading. The guessed fields are kept in `guessed` — the labels `marks[i].channels.x` — and each is drawn `vis-builder-field-guess`, titled *guessed from the source's fields — check it*, until it is edited or the mark's `data` changes, which clears the mark's guesses; a guess is not a fault and is not orange, so the chart draws at once and says what it assumed. A **library entry** dropped on the graph is the copy of §18.17, its placement key — an axis's `side`, a label's `anchor` — set from the region where the region names one and as the entry wrote it in the plot. **Every drop has a keyboard twin**: the `+` menu's `add_site` seeds the same node as a drop in the component's home region — an axis at the `:bottom`, a title at the `:top`, a label at the `:bottom`, a legend and a mark (a `:line`) in the `:plot` — so `+ axis` draws an axis and no longer an empty site; the other kinds of the menu are the empty sites they were.

| Function | Contract |
|---|---|
| `Visualize.Chart.Builder.Place.region/2` | a chart-coordinate point against a frame's `size` and `margin`: `:plot`, `:top`, `:bottom`, `:left` or `:right` |
| `Visualize.Chart.Builder.Place.node/4` | a component in a region, over the composed design at a point: `{:sites, [site]}` — each `%{kind, body, key}` lowest first, an axis's scale before it — or `{:legend, node}`, or `{:error, :no_scale}` |
| `Visualize.Chart.Builder.Place.component/1` | a palette row's word as the component, or `:error` |
| `Visualize.Chart.Builder.Place.guess/2` | a mark type's `data` and `channels` over the composed design: the first source and its fields in order over the required channels; `%{}` with no source |
| `Visualize.Chart.Builder.Place.moved/5` | a node kind and its body moved to a region at a point over the composed design: `{:ok, body}` with its placement key rewritten — `{:ok, body, sites}` when an axis's new orientation needs a scale the design lacks, the scale site to bring — `:same` when the region names what it already is, `:unmovable` for a kind with no placement |
| `Visualize.Chart.Builder.Place.moved/4` | as `moved/5` over an empty design |
| `Visualize.Chart.Builder.Place.movable?/1` | whether a drawn node's label names a movable node: an axis, the legend, a label |

**What is placed is moved** (#275, proposal D of #242; #276). A drawn node with a placement is dragged on the graph to another region, snapped as a drop is. The hook in scope `graph` starts a **move** on `dragstart` from an element carrying `data-node` whose label `Visualize.Chart.Builder.Place.movable?/1` admits — `frame.axes[i]`, `frame.legend`, `labels[i]`; a mark's position is its data and the frame does not move — the label travelling as `application/x-visualize-node`; while it moves the region the drop would snap to is drawn, `vis-builder-region-<name>` on the graph element, the four bands and the plot as translucent overlays; the drop pushes `move` with the label and the point in chart coordinates. The builder classifies the point (`region/2`) and rewrites the node's **placement key** through the ownership rule of §18.15 — the layer that owns the node takes the write, a locked owner refuses with its notice (§18.8) — as `moved/4` says:

| Node | Moved to | Writes |
|---|---|---|
| axis | any margin | `side`; and, when the move changes the axis's orientation, `scale` — the scale another axis on that orientation reads, else `x` for a horizontal side and `y` for a vertical one, brought as a drop brings it when the design lacks it (#279). An axis cannot keep its scale across orientations: a scale's `:auto` range is set by its name (§4.3), so an `x`-scale axis on a vertical side draws the plot's width down its height and runs off the view |
| legend | a margin, or the plot | `position`: the margin's edge, or the nearest of the eight in the plot, as a drop does |
| title, label | a margin, or the plot | `anchor`: the region's anchor of the table above, a plot drop the nearest corner |
| mark, frame | — | not movable |

A move into the region the node already occupies is nothing. The moved node opens, as a placed one does. **The keyboard twin:** the graph is focusable (`tabindex="0"`), and with a movable node open `Shift+Arrow` pushes `move` with a region — up `:top`, down `:bottom`, left `:left`, right `:right`, and `Shift+Enter` the `:plot` — so a legend goes to a corner and back without a pointer.
| `Visualize.Chart.Builder.Place.placed/2` | a library entry's body with its placement key set from the region where the region names one |
| `Visualize.Chart.Builder.Place.home/1` | the region a component is placed in from the keyboard or the `+` menu |
| `Visualize.Chart.Builder.Place.components/0` | the palette's rows: `{component, word}` in the order shown |
| `Visualize.Chart.Builder.Place.geometry/1` | a design's frame `size` and `margin` as the preview drew them, the schema's defaults where the design does not say |

**A library item's name carries its place in the tree.**

    <category>:<sub-category>:<fragment name>

`Frame:axes:dense ticks` is the fragment `dense ticks`, under `axes`, under `Frame`. The tree is that name parsed and nothing else: no classification is stored, computed from a fragment's keys, or kept in a list here. A category exists because some item names it, which is what lets a person invent one.

**A chart type is a template in the library** (#233). The builder has no chooser of chart types, because a chart type is a composition — a frame, its scales, its marks — and a composition is what a library entry holds. The demo's library therefore seeds, under `Charts::<title>`, one composite per chart the gallery draws as a design (`Examples.Charts.Templates`, every module with `design/1`) and per preset of `Visualize.Chart.Presets` that has no gallery design, each decomposed through `Visualize.Chart.Composite.decompose/1` so it opens as sites of one kind; a template's sources are renamed with the chart's slug (`bar_chart_bars`) and its marks' `data` rewritten to match, so every template's sample rows sit together in the host's pool, and its `meta` names it. A chart converted to a design later is a template by construction; nothing lists them by hand. Picking a bar chart is dragging `Charts::Bar Chart` into the stack, or opening it as the stack, and restyling it.

| Function | Contract |
|---|---|
| `Visualize.Chart.Builder.Library.parse/1` | a stored name as `{category, sub_category, name}` |
| `Visualize.Chart.Builder.Library.tree/1` | stored names as categories, each with its sub-categories and their items |
| `Visualize.Chart.Builder.Library.name/3` | a category, sub-category and name as the stored name |
| `Visualize.Chart.Builder.Library.categories/1` | the categories a set of stored names names, in name order |
| `Visualize.Chart.Builder.Library.sub_categories/2` | the sub-categories one category has, without the unnamed group |
| `Visualize.Chart.Builder.Library.panel/1` | the tree, rendered |

The parse is total and forgiving, because a store the host populated before this section existed must keep working:

| Stored name | Category | Sub-category | Name |
|---|---|---|---|
| `Frame:axes:dense ticks` | `Frame` | `axes` | `dense ticks` |
| `Styles::thick line` | `Styles` | none | `thick line` |
| `Theme:none:dark` | `Theme` | none | `dark` |
| `Frame:dense ticks` | `Frame` | none | `dense ticks` |
| `dark` | `Uncategorised` | none | `dark` |

An empty sub-category and the literal `none` are the same thing, so a person who types nothing and a form that submits `none` agree. A name with more than three parts keeps the remainder in the leaf — `a:b:c:d` is `d` under `c` under… no: the split is on the **first two** separators, so the leaf may contain a colon and a fragment can be called `2:1 aspect`. That asymmetry is deliberate: the category and sub-category are chosen from a short list, and the name is free text.

Sub-categories sort by name with the unnamed group first, because a fragment sitting directly under its category is the general case and the sub-categories are refinements of it.

### 18.17 Dropping a fragment into the stack

A fragment is **dragged out of the library and dropped into the layer pane at a position**, so precedence is chosen in the gesture rather than fixed and corrected afterwards. `Visualize.Hooks.Builder` carries both drags and tells them apart by what was picked up: an element with `data-builder-layer` is a **move** within the stack, and one with `data-builder-fragment` is an **insert** from the library. The stack marks itself `data-builder-stack`, and only an element so marked accepts a drop — the library is a source and not a destination.

The dragged name travels in `dataTransfer` under `application/x-visualize-fragment`, which is what lets the library's hook instance and the stack's hear about each other without either knowing the other exists.

| Event | Payload | Meaning |
|---|---|---|
| `reorder` | `%{"from" => integer, "to" => integer}` | a layer moved within the stack (§18.10) |
| `insert` | `%{"name" => string, "at" => integer, "as" => "copy" \| "link"}` | a library fragment dropped at a position, as a copy (the default, `as` absent) or a reference; `at` absent is the gap above the selected layer |
| `place` | `%{"component" => string}` or `%{"name" => string, "as" => …}`, with `"x"` and `"y"` in chart coordinates, or `"region"` in place of the point | a component or a library entry dropped on the graph, snapped to the frame's region (§18.16); `region` is what the keyboard twin sends |

**Where it lands** is one rule for both drags, and the rule is a **gap**, not a row. The pointer's position is compared with each row's midpoint: the result is the first row whose midpoint is below the pointer, and the end of the stack when none is. A gap is therefore always named — including the gap above the first row and the gap below the last — and the pointer never has to be inside a row at all.

That last part is the substance. An earlier rule required the drop to land on a row and computed a side from it, which left both ends of the stack unreachable: the space above the first layer and below the last belongs to the container, not to any row, so a drop there was simply discarded. The stack accepts a drop anywhere within itself, and reserves some empty space below the last row for exactly this.

A **move** is the same gap, adjusted: `at` is a gap in the list as it stands, and once the dragged layer is lifted out every gap after it shifts down by one, so the position sent is `at - 1` where `at` is beyond the layer's own position. The position is clamped server-side regardless, because a hook is a client and a client's number is not to be trusted.

**A drag must be able to start, and a click must still land.** Both panels learned the same lesson the same way: **the row is the control.** A `<button>` spanning a draggable row defeats both gestures at once — a browser treats a form control as a special drag source and often will not start a drag from one, and a mousedown on a control inside a draggable row becomes a drag on the first pixel of movement, so its own click never fires. A layer row and a library row therefore carry `phx-click` and `draggable` themselves, with plain text inside; the one control that remains beside a layer's name, its toggle, says `draggable="false"` to stop the browser's search for a drag source at itself.

**A drop needs an operation, not just permission.** `preventDefault` on `dragover` says the drop is allowed; a `dropEffect` says what it *is*. Without one the browser has no operation to perform and refuses the drop anyway. The stack sets `copy` for a fragment arriving from the library and `move` for a layer changing places, matching the `effectAllowed` each drag declared.

**A drag that leaves takes its marks with it.** `dragend` fires on the drag's *source*, which for a library drag is in another element entirely, so the stack clears its own indicator on `dragleave` rather than waiting for an event that will never reach it.



**What follows the insert.** The selected layer and the disabled set are *positions*, so both shift by one where they sit at or below the insertion — the same rule a move already follows (§18.8). A name the store does not hold is a notice and changes no layer, exactly as adding one is.

Inserting does not consult the fragment: the stack is a list and a fragment is an element of it, so an insert is `List.insert_at/3` and the design is recomputed from the result. There is nothing to validate at insertion time that applying the design does not already say better (§18.4).

**A drop is a copy; a link is asked for** (#262, proposal C of #242). What a drop inserts is an **inline site** — `ref: nil`, `local` the entry's body, labelled with the entry's name — so the chart holds its own values and editing them never reaches the library; the library is a palette, and a palette is copied from. A **composite** entry — a `Charts::` template — is copied as its sites: each of the entry's uses becomes an inline site holding what the use contributed, its referenced fragment (flattened, when that is itself a composite) stacked under its `local`, with the use's `mask`, `vars` and `key` kept, labelled with the referenced entry's name; the composite's own `vars` and `signals` join the chart's where the chart does not already declare them. `Visualize.Chart.Builder.Stack.copies/3` is that reading of an entry. A **link** — `as: "link"` — is the reference site of §19.3 as before, for the house look: a layer that is to follow the library. A link is made by holding **Alt** while dropping, or with `I` on a library row (`i` copies); a linked layer is locked in the chart and edited by opening the entry (#263). The graph is also a drop target for a library entry: the hook in scope `graph` accepts the drag and the copy lands above the selected layer.

**The keyboard has every gesture the pointer has.** Making the row the control took the `<button>` away, and with it Enter and Space; a row is reachable — `role="button"`, `tabindex="0"` — only if it is also operable. Every row therefore carries `phx-keydown`, and the builder reads the key:

| Row | Key | Does |
|---|---|---|
| a layer | Enter, Space | selects it, as clicking does |
| a layer | ArrowUp, ArrowDown | moves it one position — the same `reorder` a drop raises — and focus follows the row to where it went |
| a library item | Enter, Space | opens it, as clicking does (§19.8) |
| a library item | Insert, `i` | inserts a copy directly above the selected layer — the same `insert` a drop raises — with no drag to make |
| a library item | `I` | inserts it as a link, as an Alt-drop does |

Focus follows a moved layer because the rows are re-rendered by position: the builder pushes `vis:focus` with the id of the row at the layer's new position, and `Visualize.Hooks.Builder` focuses it after the patch. A row's accessible name says what it is and what activating it does — *house, layer 1 of 3, selected: Enter to edit, arrows to move* — so what is announced is what the keys do, and the `title` that pointer users hover is the same sentence.

### 18.18 The style stack at a site

§3.6 gives every style site a stack; this is the control over it. `Visualize.Chart.Builder.StyleStack.panel/1` renders the stack of the open node's `style` key: one row per entry, in resolution order — the first applied first, the last winning — because that is the order the cascade is defined in and a panel that reversed it would teach the opposite of §3.6.

| Function | Contract |
|---|---|
| `Visualize.Chart.Builder.StyleStack.panel/1` | the stack at a site: its entries, and the controls that change them |
| `Visualize.Chart.Builder.StyleStack.entries/2` | a `style` value as the rows to draw, whatever shape it takes |
| `Visualize.Chart.Schema.style_stack/0` | the type a style site takes, written once |
| `Visualize.Chart.Builder.StyleStack.choices/1` | the names an entry may take: what the design declares, and the built-in four |

**A row per entry, whatever the value's shape.** `entries/2` is total over §3.6's three shapes: a bare reference is one row, an inline node is one row, a list is a row each. A site with no `style` key at all is the empty stack, and the schema's default for that site — `:axis` for an axis, `:label` for a label and a legend — is shown as the row it will resolve as, marked as a default rather than as something the design says.

Each row offers what a layer row offers and for the same reasons: **select** it, which opens it in the context panel; **remove** it; and **drag** it to a position, which is what changes precedence. A row is the control, carrying the click and the drag itself, because a control inside a draggable row defeats both (§18.17).

**The local row.** An inline entry is drawn as `local` and is the row an edit lands in. There is at most one, it is the last entry, and it is **created on first edit** (D-98) — so a site that has never been edited directly shows references only, and the local row appears when it is needed rather than sitting empty in every document.

**Adding.** A control offers the style names the stacked design declares (§18.14) and the four built-in names, and appends the chosen one. Appending rather than inserting is the useful default — a style added to a site is nearly always meant to win — and dragging moves it if it was not.

**One hook, many stacks.** `Visualize.Hooks.Builder` already reorders a list by dragging (§18.10, §18.17), and a style stack is a list. The hook's queries are scoped to its own element, so a second stack on the page is a second instance with no knowledge of the first; what the component needs is to know *which* stack a `reorder` came from. The hook therefore reads `data-builder-scope` from its element and returns it in the payload, absent for the layer stack and `"style"` for a style stack. This is why the layer stack needed no change: an absent scope means what it always meant.

### 18.19 The context panel over a style

Beneath the stack of §18.18 sits the style the site actually renders as: the entries cascaded, every key of the `:style` kind, with the control §18.6 chooses from its type. It is `Visualize.Chart.Builder.Editor.panel/1` at kind `:style` over the resolved node, which is why it needs no list of style keys of its own — a key added to the schema appears here with no edit.

**Every edit lands in the local style.** A field changed here writes into the site's inline entry, creating it when there is none (D-98). It never writes into a named entry: editing a mark that references `:series` must not restyle every other mark that references the same name, and a panel that wrote to the resolved node would do exactly that. This is the whole reason the local style exists, and it is why the panel edits through its own event rather than the editor's.

**Every field says where its value came from.** A resolved style is a cascade, so a value is one entry's and the entries below it are overridden. Each field carries the name of the entry that supplied its current value — `series`, `axis`, `local`, or the site's default — which is `Visualize.Chart.explain/1`'s question asked at a site: *which style said this, and what did it replace*. A key no entry sets shows the schema's default as a placeholder and names nothing, because nothing said it.

| Function | Contract |
|---|---|
| `Visualize.Chart.Builder.StyleStack.resolved/2` | the site's stack cascaded, as the panel shows it |
| `Visualize.Chart.Builder.StyleStack.origins/2` | which entry supplied each key of the resolved style |

The panel is shown when an entry of the stack is selected, and hidden otherwise: a site's resolved style is a question about the site, and asking it costs a click so that the column is not a wall of nineteen controls for every node that happens to have a style.

### 18.20 Dropping a style fragment onto a site

A library fragment whose kind is `:style` (§18.16) may be dropped **onto the stack of a site**, and that is the answer to the question §18.14 could not ask: *which style did you mean*. The fragment does not have to know the name its target uses, because the drop said where it goes.

**One gesture, two writes.** Dropping `Styles::thick line` — `%{styles: %{"thick line" => %{stroke_width: 5}}}` — onto a mark's stack:

1. **merges the fragment into the design** as a layer, exactly as dropping it into the layer pane does (§18.17), so the style stays declared once and reusable; and
2. **inserts a reference to it** into the site's stack at the position it was dropped at.

The name stays shared, the placement is explicit, and nothing is copied: a second site referring to the same name gets the same style, which is the whole point of naming one.

**Only a style fragment.** A fragment of any other kind dropped on a stack is refused with a notice naming its kind, rather than merged into the design and left with nothing referring to it — a silent half-effect is worse than a refusal. A fragment that declares more than one style is refused for the same reason: which of them the site meant is exactly the question the gesture is supposed to answer.

**The stack is the drop target.** `data-builder-stack` already marks what accepts a drop and `data-builder-scope` says which stack it is (§18.18), so the hook needs nothing new: the `insert` event of §18.17 carries the scope, and a scoped insert is this.

## 19. Typed fragments: identity, use sites, and one composer at every level

§18 built a component that edits one stack of fragments, and doing so found the model underneath it. A fragment there is a map with the author's names inside it; a layer is its position in a list; saving a stack collapses it; and a library entry is a name that composites point at by spelling it. Every one of those was a source of friction the moment two fragments had to agree on something, and this section replaces them with one rule: **identity lives in the library, a reference is an id, and a declaration in place is only values.** The rest of the section is what follows from that rule. Where it conflicts with §18, this section governs and the earlier text is marked.

### 19.1 Three tiers of identity

A thing sits in the lowest tier that serves it, and moves up only when sharing widens.

| Tier | Declared | Referenced by | What a rename costs | Example |
|---|---|---|---|---|
| **inline** | at the site, as values | nothing — it *is* the value | — | the local style of a stack (§3.6, D-98) |
| **local key** | once in a document | a key, within that document | one walk of one document | `frame.scales.hour`; `styles.series` in a hand-written design |
| **library entry** | once in the store | an id, from any fragment in the store | nothing — a name is an attribute | `{:style, 11}` |

**Promotion is a gesture, one tier at a time.** A style at one site is inline. A second site in the same document needs it: it becomes a local key. A second document needs it: it becomes a library entry. Each step is reversible by copying the value back in. The tool never forces anything upward, and nothing has to begin in the library.

The hand-authored design of §13 lives entirely in the middle tier, and that stays exactly as legal as it is: within one document a key is local, renaming it is one walk of one term, and there is no second fragment to disagree. The builder writes ids; a person writing a design by hand may still write words. These are two rungs of one ladder, not two systems.

### 19.2 Ids

An id is **tagged with its kind** — `{:style, 11}`, `{:theme, 32}`, `{:scale, 4}`, `{:composite, 5}` — and is **issued by the store** from a per-kind sequence that never repeats.

| Property | Consequence |
|---|---|
| tagged | readable in the raw data and in a JSON export (`{"style": 11}`); the validator refuses `{:scale, 4}` where `{:ref, :style}` was expected *before* resolution, so a wrong-kind reference is an error at the cheapest moment |
| store-issued, never reused | a stale id can never resolve to something new; a small integer stays readable; ids sort by creation |
| unique within a store | one store per builder; a collection crossing into another store is relocated (§19.7) |
| **transparent when missing** | a deleted entry leaves every site that referenced it as a mask of everything — lower entries show through, or the site's default applies. Rendering never fails. The builder shows the site as *no longer exists — showing through*, so degradation is visible and never silent |

The `{:ref, kind}` type (§1.4) admits three forms: a local key (an atom naming a declaration in this document), an id `{kind, n}`, or — where the site takes a stack — an inline node. A name that this document does not declare, and an id the store does not hold, are both faults at the site's path; the first is the error it already was (§10.1), the second renders as a mask and is reported by the builder.

**A name is never an identity.** A library entry's name and group are attributes of the entry, free to change; nothing references them. Inside a fragment's body there is no name at all: a style fragment is `%{style: %{stroke_width: 5, …}}` — a singular wrapper naming the kind, and values. The wrapper is what keeps a body's kind derivable (§19.8) without the store having to say it.

### 19.3 The use site

A layer in a composite and an entry in a style stack are the same thing: a fragment **used at a position**. The site is a struct, so it is a leaf of every walk (D-92) and `Visualize.Chart.stack/1` never descends into it.

```elixir
%Visualize.Chart.Use{
  id:    {:use, 7},             # this site's own identity, so it is the same site wherever it sits
  ref:   {:style, 11},          # which fragment; or a local key; or nil for an inline-only site
  mask:  [:stroke],             # keys removed here, so a lower layer shows through
  vars:  %{color: var(:color_1)}, # what the fragment's variables mean here
  local: %{opacity: 0.8},       # what is added or overridden here
  key:   :series                # the name a name-keyed kind is declared under, here
}
```

| Part | Means | Written by |
|---|---|---|
| `ref` | which fragment | a linked drop or `I` on a library row (§18.17); a plain drop makes a copy with no `ref` |
| `mask` | keys removed at this site | checkboxes under the layer's row, its › Mask item (§18.8) |
| `vars` | what the fragment's variables mean at this site | the Variables tab (§19.10) |
| `local` | what is added or overridden at this site | the field forms — at an **inline** site only: a referenced site is locked (§18.8, §18.15) and its forms write nothing; a `local` an older workspace carries at a referenced site still applies and is shown, but is not added to |
| `key` | the name this site's body is declared under, for a kind the document keys by name | the key control in the context panel (§19.10) |

Each part is edited from exactly one surface, so there is never a question of where an edit went.

**`key` is the composite's word, never the fragment's.** Four kinds live under a name in a document — `styles.<k>`, `frame.scales.<k>`, `sources.<k>`, `vars.<k>` — and a body has no name (§19.2), so the *site* says where it goes: the same `Styles::thick` is `series` in one composite and `line` in another, and no fragment ever hard-codes the name a reference will use. Every other kind has one place it can land, and `key` is `nil`. A name-keyed site with no key is a fault the builder shows at the row and Deploy refuses; it is not a silent nothing.

**Order of operations, stated once:** `ref → local → mask → bind → stack`. The referenced fragment is fetched; the local node is merged over it; masked keys are removed; variables are substituted (§19.4); and the result cascades with the sites around it by §8.2. Mask and bind run after local, so both speak for everything the site contributes, whichever part said it — a site the host seeded is nothing but its local, and its keys are masked and its variables bound at the site like any other's. (Mask-before-local, so a masked key could be re-set locally, was considered and dropped: the local cascades over the reference anyway, so re-setting never needed the mask, and a mask that could not reach a seeded layer's own keys would have left the checkbox of §19.10 doing nothing on the layers a host starts with.)

**A site has its own id** because a site was its position, and position is the wrong identity: the selection and the disabled set had to be remapped on every insert and move, a local style was named by an index that a reorder changed, and a drop target was a number a client could not be trusted with. With `Use.id` a site is the same site wherever it sits, and `Visualize.Chart.explain/1` attributes to it by id with a display name.

**Disabling a layer is a mask of everything** (D-87 restated), and a mask of everything removes the *whole* site — its local node included, since a site the host seeded is nothing but its local — so the design is what it would be without that layer. A ref whose id no longer exists masks what the ref would have given (§19.2); the site's local still stands, which is what *showing through* means.

### 19.4 Bindings are substitution before the cascade

A fragment that carries `var(:color)` may be placed at several sites, and each site may want something different of it:

| Case | `Use.vars` at the site | `free_vars/1` of the composite reports |
|---|---|---|
| **shared** — one `:color` for every site | nothing | `:color` |
| **set** — a literal at this site | `%{color: "blue"}` | nothing from this site |
| **renamed** — this site's colour is the composite's own | `%{color: var(:color_1)}` | `:color_1` |

`bind/2` on `Visualize.Chart` is a pure substitution: every `%Var{name: k}` in the fragment becomes the map's value for `k`, a literal or another `var/1`, and the result is a fragment with fewer, or differently named, variables in it. It runs at the site, before the cascade. The renamed case is legal here and refused at `apply/2` — the var-to-var error of §7 stays — because by the time application binds anything, substitution has already rewritten one name into the other. A composite placed inside a larger composite is rebound again, so bindings nest like function application.

Nothing in `stack/1`, `apply/2`, `free_vars/1` or the validator changes: each sees a fragment those rules already accept.

### 19.5 Masks

`Use.mask` is a list of paths dropped from the referenced fragment at this site, before it is stacked. It is the dual of `local`, which adds; without it the only way to let a lower layer's key through is to copy the lower value into `local`, which is the drift `extends` exists to prevent (D-80), or to fork the fragment, which bloats the library.

Because the key is genuinely absent by the time the cascade runs, `explain/1` attributes the value to the layer it now comes from — which is simply true — and names the mask at the site it was applied. Keys of nodes first; a path may later name an identified list element.

### 19.6 Composites: stored as structure, flattened at deployment

A composite is a fragment whose content is a list of use sites and its own `vars`:

```elixir
%{composite: %{
  uses: [
    %Use{id: {:use, 1}, ref: {:theme, 32}},
    %Use{id: {:use, 2}, ref: {:frame, 2},  mask: [:margin]},
    %Use{id: {:use, 3}, ref: {:style, 11}, vars: %{color: var(:color_1)}, local: %{opacity: 0.8}}
  ],
  vars: %{color_1: %{default: :series_1}}
}}
```

**Save writes structure.** The store holds the uses, never `stack/1`'s result, so a composite reopens as what was built — references intact, masks and bindings where they were left — and references keep their point: edit `{:style, 11}` and every composite using it follows. The save message of §18.2 carries structure.

**Flatten is a deployment verb.** `flatten/2` on `Visualize.Chart` resolves every use recursively — `ref → local → mask → bind` — through a store, and stacks the result: a flat design in §13's shape, with no ids and no uses, which `apply/2` and `render/2` consume as they always have. A host calls it in its own pipeline. The builder's preview resolves the structure to draw it, and the builder offers flatten as its own, separately-labelled action, **Deploy**: on the workspace or an open composite it flattens the structure through the store and sends the host `{on_deploy, id, design}` — the flat design, where *Save* sends structure — with a notice naming any reference that showed through; a stack that reaches itself is refused and nothing is sent. The two verbs are different, and offering the second never loses the first. Deploy is not offered while a non-composite kind is open, since there is no chart to deploy.

**A design is the deployed tier, not a starting one.** *New fragment of a kind* (§19.8) does not offer `design`: a composite does everything a design does and deploys to one, so an empty design typed into forms would be the one path with no library behind it. The kind still exists — the library may hold one, and an imported document is one (§18.12) — and asking for it by name is refused with a notice that says to start a composite.

**Flatten places every site by its kind.** A site's contribution — its body after `ref → local → mask → bind` — is placed in the design by the kind it derives to (§19.8):

| The site's kind | Lands at | Identity |
|---|---|---|
| `theme`, `meta` | the design key of that name | the position |
| `frame` | cascades into `frame` (§8.2) | the position |
| `mark`, `label`, `axis` | appended under `marks`, `labels`, `frame.axes` | its own — `id`, `id`, `{scale, side}` — as the cascade already merges them |
| `style`, `scale`, `source`, `var` | `styles[key]`, `frame.scales[key]`, `sources[key]`, `vars[key]` | the site's `key` (§19.3) |
| `composite` | flattened first, then each of *its* sites as above | — |
| more than one root (a host-seeded layer, an imported document) | cascades as a layer of the stack, as §18 always did | — |

A name-keyed site with no key is reported — `keyless: [use id]` beside `missing` — and its body is not placed. The report is what the builder shows and what Deploy refuses on.

**Resolution is one rule.** Once the sites are placed, every id at a reference *inside* the design is resolved through the same store, by `Visualize.Chart.Refs.resolve/2`, so what leaves `flatten/2` carries no ids and nothing below it needs a store: a `{:style, n}` at a style site — alone or in a stack (§3.6) — becomes the entry's body inline; a `{:scale, n}` or `{:source, n}` at a single-valued site — an axis's `scale`, a mark's `data`, a mark's `scales.x` — is declared in the design's namespace for the kind under a **synthesised key**, `:"scale:4"`, the word the DOM already uses for the id, and the site is rewritten to that key. A body that is itself a composite flattens first. An id the store no longer holds is a mask at the site (§19.2, D-100): a style entry becomes nothing, a single-valued site is removed so the kind's default or the validator's fault applies, and the id is reported in `missing` by the path of the site that named it. The builder's preview (`Stack.design/3`) and Deploy both go through `flatten/2`, so what the preview draws and what the host receives cannot differ — the invariant of §18.4, which the preview alone inlining style ids had broken.

**Composites nest**, because a composite is a fragment and a use may reference one. Resolution is recursive. A composite that reaches itself through any chain of uses is refused, as an `extends` cycle is (§3.5), at the site that closed the loop.

**Within a kind, the same operation.** A composer opened on a style accepts only style fragments and its result is a style; opened on a composite it accepts anything and its result is a design. Both are `stack/1`; only what the stack may take differs, and the kind derivation (§19.8) says which was made. The style stack at a site (§3.6) is the same operation by reference at the point of use.

### 19.7 The store, revised: ids, a context, and import as relocation

`Visualize.Chart.Builder.Store` (§18.3) gains three things in one revision, so a consumer migrates once.

| Callback | Was | Is |
|---|---|---|
| `list/1` | `list/0` → names | `list(context)` → `[%{id, name, group, kind}]` |
| `get/2` | `get(name)` | `get(id, context)` → `{:ok, fragment}` or `:error` |
| `put/3` | `put(name, fragment)` | `put(entry, context)` → `{:ok, id}`; an entry without an id is new and is issued one, with one is replaced |
| `delete/2` | — | `delete(id, context)`; a later reference to the id is a mask (§19.2) |
| `import/2` | — | `import(bundle, context)` → `{:ok, %{old_id => new_id}}`, committed whole or not at all |

The **context** is whatever the host passes as the second element of a `{module, context}` store assign — who is saving, from where — and a bare module is `{module, nil}`. It answers the need metresis raised (#148): a library entry nobody can trace is an entry nobody trusts, and the process dictionary is not a signature.

**Import is a relocation**, and it has every property that ruled out renaming by name: it is bounded to a known set, it happens once at the boundary between stores rather than during editing, and it is one call with one outcome. The importer allocates a new id for each arriving fragment, builds one table `old → new`, rewrites the references inside the collection through it, and commits.

**Export takes the closure.** Exporting a composite exports every fragment it references, transitively, with their ids, so an import cannot dangle by construction. A **bundle** is that set plus provenance — the source store's identity and each fragment's original id — so re-importing the same collection is detectable as a duplicate rather than minting a second copy. A reference to an id outside a bundle is only possible in a hand-edited file; it imports as a mask and is **reported** — *n references point outside this collection* — never a failure, never silent.

| Function | Contract |
|---|---|
| `Visualize.Chart.Builder.Store.split/1` | a store assign as `{module, context}`; a bare module has a `nil` context |
| `Visualize.Chart.Builder.Store.encode_id/1` | an id as the one string the DOM and the wire carry |
| `Visualize.Chart.Builder.Store.decode_id/1` | that string back to an id, refusing a kind that is not one so no atom is made from a client's string |
| `Visualize.Chart.Builder.Store.relocate/3` | the reference `import/2`: issue, then rewrite through the table, through a store's own `put/2` |
| `Visualize.Chart.Builder.Bundle.export/3` | the closure of an id through a store, dependencies first, with provenance |
| `Visualize.Chart.Fragment.kinds/0` | every kind a fragment can be, and so every kind an id can carry |
| `Visualize.Chart.Fragment.kind/1` | the kind of a fragment, derived (§19.8); `nil` for a map that is many things, which is no kind of fragment |
| `Visualize.Chart.Fragment.singular/1` | the kind a singular wrapper key names — `:style` for `style:` — or `nil`; `composite` is not one |
| `Visualize.Chart.Fragment.wrapped/1` | a singular-wrapper fragment as `{kind, body}`, or `nil` |
| `Visualize.Chart.Validator.validate/2` | per-kind validity (§19.8): a fragment read as a kind — a design whole, a composite as sites, any other kind as the body under its key with that kind's schema, no key required and no reference looked up, since a fragment is a piece |
| `Visualize.Chart.Fragment.refs/1` | every id a fragment refers to, once each, sorted — the order a map is walked is the runtime's, not a promise |
| `Visualize.Chart.Fragment.relocate/2` | a fragment with its ids rewritten through a table, and the ids the table did not carry |

| Function | Contract |
|---|---|
| `Visualize.Chart.Use.new/1` | a use of a fragment with id `{:use, 1}` and the three empty parts |
| `Visualize.Chart.Use.new/2` | a use of a fragment with a fresh id — one more than the highest it sits beside — and the three empty parts |
| `Visualize.Chart.Use.bind/2` | a fragment with its variables substituted: a literal sets, another `var/1` renames (§19.4) |
| `Visualize.Chart.Use.mask/2` | a fragment with paths removed; `:all` removes everything (§19.5) |
| `Visualize.Chart.Use.resolve/2` | one use through a fetch: `ref → local → mask → bind`; a ref the fetch cannot find is `{:missing, id, local}` |
| `Visualize.Chart.Use.over/2` | a use over a body already in hand — everything `resolve/2` does after the fetch |
| `Visualize.Chart.Composite.composite?/1` | whether a fragment is one key, `composite`, holding uses |
| `Visualize.Chart.Composite.flatten/2` | a composite through a fetch, recursively, every site placed by its kind (§19.6): `{:ok, design, %{missing: …, keyless: …}}` or `{:error, {:cycle, chain}}` |
| `Visualize.Chart.Composite.place/2` | one site's contribution as the layer that declares it where the design keeps its kind — a name-keyed one under the site's `key` — or `:keyless` |
| `Visualize.Chart.Refs.resolve/2` | a flat design with every id at a reference site resolved through a fetch — styles inline, scales and sources declared under synthesised keys — and the ids that were missing, by path (§19.6) |
| `Visualize.Chart.Composite.decompose/1` | a flat document as sites, one kind each, keyed where the document keyed them, with a label for each (§18.12); `flatten/2` of the result is the document again |
| `Visualize.Chart.bind/2` | `Use.bind/2` on the design's own module |
| `Visualize.Chart.mask/2` | `Use.mask/2` likewise |
| `Visualize.Chart.resolve/2` | `Use.resolve/2` likewise |
| `Visualize.Chart.flatten/2` | `Composite.flatten/2` likewise; a design that is not a composite flattens to itself |

**The JSON form** (§11.2) gains two tagged terms: an id is `{"$id": ["style", 11]}` and a use is `{"$use": {"id": 7, "ref": …, "mask": [...], "vars": {...}, "local": {...}}}`, with `"mask": "all"` for everything. An id whose kind is not one a fragment can have is left as it was read, never made into an atom.

**The validator** (§10.1) accepts an id at a `{:ref, kind}` site by its tag alone — whether the store holds it is resolution's question — and refuses a tag of the wrong kind as `{:ref_kind, wanted, given}` before anything tries to resolve it.

### 19.8 The library: kind derived, group stored, two views

A library item has two independent axes, and the library is browsed by either.

**Kind is derived, never stored.** Walk down while the fragment sets exactly one key, and the kind is the last thing reached: `%{style: %{…}}` is `:style`, `%{theme: %{…}}` is `:theme`, `%{frame: %{size: …, margin: …}}` is `:frame`, `%{composite: %{uses: …}}` is `:composite`. The singular wrapper of §19.2 is what makes a bare body's kind readable without the store holding it.

**A fragment about more than one thing is not a kind of fragment.** A map that branches at the top — `theme` and `styles` and `frame` — derives to no kind: `Visualize.Chart.Fragment.kind/1` gives `nil`, `Visualize.Chart.Validator.validate/2` refuses it as a fragment, and the library refuses to store it. The thing that is many kinds is a *composite*, whose sites are each one kind (§19.6), and a person who has such a map — a hand-written document of §13, an import — has it decomposed into sites (§18.12). **Design is therefore not a kind**: it is the deployed tier and nothing else — Deploy's output (§19.6), complete, validated by `validate/1`, never a heading in the library and never an id. A composite need not be complete: a theme-and-frame composite is a "house look", a library entry, and a layer for another composite; flattening it gives a partial map that is not a design, which is what makes it a fragment.

**Group and sub-group are stored, subjective, and orthogonal** — the person's own filing, free to gather dissimilar kinds under one heading. They remain in the entry's name as `<group>:<sub-group>:<name>` (§18.16, D-97), which is now an attribute of the entry and not a key anything references.

Two views over one store: by kind, or by group. **Empty kinds are shown** — a `Scale` heading with nothing under it says the library holds no scale yet, which is information, where an absent heading is indistinguishable from a bug. The kinds a library item is usually one of — composite, design, theme, style, frame, scale, axis, source, var, mark, label — are always shown, empty or not; any other kind appears when an entry has it. **Group is the default view**, kind a click away.

| Function | Contract |
|---|---|
| `Visualize.Chart.Builder.Library.by_kind/1` | entries as the kind tree: every usual kind, empty or not, then any other present; items by name, each with its group as a second line |

**Click opens; drag composes.** Clicking an item opens it in the editor. Dragging is the only gesture that puts a fragment into something else — a composer's stack, or a style site. **New fragment of a kind** starts from an empty, valid one of that kind, so a style cannot be half a frame by accident; **per-kind validity** is the validator restricted to a kind and refuses a fragment that drifted. **Save** writes back under the entry's kind and group, and names the entry — never the body.

This supersedes §18.3's flat store and the dropdown of §18.2, and it completes §18.16.

### 19.9 The editor: two faces, one composer

Every fragment has two faces, and the editor is one component whose shape is the open fragment's kind.

**Edit** is a form shaped by the kind: the nineteen keys of a style, the keys of a theme, the schema's own walk for the rest (§18.5). A composite's edit face is empty — its content is its layers.

**Compose** is the stack, constrained to the kind (§19.6). Opened on a composite the constraint is none, and the node tabs (§18.13) and the preview (§18.4) appear beneath the stack, because now there is a chart to look at. The layer stack is therefore not a region of the workspace but the composite's compose face; §18.16's four regions are three.

**The stack is a list of sites.** The builder's state is its uses — `%Visualize.Chart.Use{}` in stack order — and everything a panel reads is derived from them, by one pure module:

| Function | Contract |
|---|---|
| `Visualize.Chart.Builder.Stack.seed/1` | a host's layers as uses with their labels: a fragment as an inline-only use (`ref: nil`, the fragment as `local`), so §18.2's contract is unchanged; an id `{kind, n}` as a use referring to it, so a host may start the builder over its own library |
| `Visualize.Chart.Builder.Stack.label/2` | the name a person sees for a use: its label, or its id |
| `Visualize.Chart.Builder.Stack.enabled?/1` | whether a use contributes: anything but a mask of everything |
| `Visualize.Chart.Builder.Stack.toggle/1` | a use disabled or re-enabled: `mask: :all`, or not (§19.3) |
| `Visualize.Chart.Builder.Stack.fetch/1` | a store as the function resolution takes: an id to `{:ok, fragment}` or `:error` |
| `Visualize.Chart.Builder.Stack.resolve/3` | every use as the `{label, fragment}` the panels read, and the refs no store holds; a disabled use resolves as it would enabled, since the panels edit it either way |
| `Visualize.Chart.Builder.Stack.design/3` | the enabled uses as a composite over the stack's own vars, flattened through the store (§19.6), with every `{:style, n}` at a site inlined so the frame needs no store |
| `Visualize.Chart.Builder.Stack.index_of/2` | a use's position, or `nil` |
| `Visualize.Chart.Builder.Stack.get/2` | the use with an id, or `nil` |
| `Visualize.Chart.Builder.Stack.update/3` | one use replaced by a function of it |
| `Visualize.Chart.Builder.Stack.write/4` | a write into a use's `local` at a path: `{:ok, value}` sets, `:error` removes (§18.5) |
| `Visualize.Chart.Builder.Stack.write_at/4` | the same write into any fragment — an opened entry's body |
| `Visualize.Chart.Builder.Stack.move/3` | a move: list surgery, nothing to remap |
| `Visualize.Chart.Builder.Stack.kinds/0` | the kinds *new fragment of a kind* offers, the composite first and never a design (§19.6, §19.8) |
| `Visualize.Chart.Builder.Stack.empty/1` | the empty, valid fragment of a kind |

| `Visualize.Chart.Builder.Stack.open/2` | an entry as the stack: a composite's sites labelled by the store's names, with its vars; any other body as one inline site named for the entry |
| `Visualize.Chart.Builder.Stack.structure/2` | the stack as a composite over its vars: what saving sends, and what a composite stores |
| `Visualize.Chart.Builder.Stack.body/2` | the lowest tier that holds the stack (D-99): one bare inline site is its body, anything more is structure |
| `Visualize.Chart.Builder.Stack.sites/3` | each site that carries variables — its fragment's free variables *before* the site's bindings, and what the site binds them to — for the per-site rows (§19.10) |

Selection is a use's id, and a host that seeds one (`selected`) is honoured when the stack has it; disabling is the mask of everything, and its whole effect is in `design/3`. Saving sends the structure — `%{composite: %{uses, vars}}` — and never a flattened design; a host that wants the design asks `Visualize.Chart.flatten/2` with the store's fetch.

**Opening is a chart** (#243; this replaces the one-open-thing model of the first draft, in which the workspace was stashed while an entry was open). The workspace holds several **charts** at once, one **selected**; each chart is a stack — the compose face of one thing — and the panel of §18.8 lists them. The chart the host seeded is the first; its layers take anything. Clicking a library entry opens it *as a new chart* — a composite's sites, labelled by the store's names, or any other body as one inline site named for the entry — selected, with the entry recorded on it so that *Save as* writes the entry; the field forms write to the selected site's local, which for an opened style is the style's own body. Closing a chart removes it from the workspace and selects its neighbour; the last chart is not closed. Opening another entry adds another chart, as opening a second file does. Dragging an entry into the selected chart composes it, as a use referring to its id whose label is the entry's name, and the composer **admits only the chart's kind**: a chart opened on a style refuses a frame by name — *a style composer takes a style; Frame::wide is a frame* — while a chart that is a composite takes anything. The chart's row says which: its name, and its kind when it is not a composite.

**What an open kind shows.** A composite or a design has the node tabs, the preview and the design's faults from `apply/2`; any other kind has its own form as the one root — a wrapper body's nodes are its kind's, so `%{style: %{…}}` opens on a `style` tab — no preview, since there is no chart to look at, and the faults of per-kind validity in their place. The document panel exports the fragment itself in the JSON form, valid as its kind.

**Save writes the lowest tier.** The workspace and a composite are saved as structure. Any other kind is saved as `body/2` gives it — one bare inline site is its body, values and nothing else, so a style stays a style; a stack of sites is structure under the kind's id — and is refused when what it flattens to is no longer that kind (*opened as a style and is now a frame*) or is not valid as one. A singular wrapper cascades as a node of its kind, so two style fragments stack key by key as two styles would (§8.2), and a stored structure of kind `style` flattens to a style wherever it is used.

A field in any form shows a **variable as a variable** — as a **chip**, `var(:color)`, in the place of its control, never as a struct's text in a textarea. A variable reaches a field one way only: its chip, dragged from the variable panel (§19.10) and **dropped on the field**, which writes `var(:name)` at that key (`bind_field`); dropped on a **strip tab**, it binds the first key of that root the variable fits (`bind_root`). The chip carries an **×** that unbinds — the key is removed, and the typed control returns empty and waiting (`unbind_field`). A field's own value can go the other way: every literal field has a handle, and dropping it on the panel's create area **promotes** the value into a new variable named for the key, with the value as its default, and binds the field (`promote`); a second promotion of the same key takes the next free name. The form therefore has no literal/variable switch and no name box — the `key.mode` and `key.var` controls an earlier draft carried are gone — and a field is a control or a chip, nothing else.

**A variable has the type of its first use** (§17.2). Dropping a chip on a field of another type is refused by name — *`unit` is a `:text`; `opacity` takes a `:size`* — and a variable used nowhere yet takes the type of the first control it lands on, by landing there. A **field is a channel** for this rule — a channel is a field or a constant — so a variable typed by a mark's channel fits a source's field list and one typed by a field list fits a channel; and a list of scalars takes a chip as an item of its element's type. One function says what a change to the form means:

| Function | Contract |
|---|---|
| `Visualize.Chart.Builder.Editor.change/2` | what a change to a form means: the key, and `{:ok, value}` or `:error` for a removal; `nil` for a key the kind lacks |
| `Visualize.Chart.Builder.Editor.submitted/2` | a control's value read as a type, with the checkbox rule `parse/2` cannot know |

The names on offer are those the stack declares under `vars` and those any layer already uses, listed by the variable panel.

### 19.10 Variables, and the context panel

**The variable panel** is `Visualize.Chart.Builder.Variables.panel/1`, in the context panel: the composition's variables — what the stack declares under `vars` and what any layer still uses, `Visualize.Chart.Builder.Variables.list/2` — **alphabetically**, each a chip (§19.9) beside the word for its type. A chip **expands** to its details: every use as *layer → path*, each a link that opens that node (§18.9); the **default** of its declaration — written where the stack declares the name, the highest site that does (a `var` site by its key, or a layer under its `vars`), else declared by a new `var` site on top so it is what wins (`set_default`); the **value** the preview binds it to (§18.11's control, one per variable, writing `set_var`) with the default as its placeholder; and the **per-site rows** below — one `<form class="vis-builder-site">` per site whose fragment carries the variable (from `Visualize.Chart.Builder.Stack.sites/3`), reading as one of three — *flows up as `:color`*, `= "blue"`, `= var(:color_1)` — with a value box and a variable box; whichever changed last is what the site says, a blank in either is a removal, and `bind_site` writes `Use.vars` and nothing else, which is §19.4's rename. A **find** box filters the list, and a name typed whole highlights the chip and every field bound to it. A **create** form declares a new variable as a `var` site at the bottom of the stack, keyed by its name, with its default (`create_variable`); the same area is where a field's handle is dropped to promote (§19.9). The tab the strip once ended with is gone — variables are not a root of the design, they are what the context panel is for.

| Function | Contract |
|---|---|
| `Visualize.Chart.Builder.Editor.variable/1` | a typed variable name as the variable it names; a blank is `:error`, a removal |
| `Visualize.Chart.Builder.Variables.panel/1` | the variable panel: chips alphabetically, find, create, and each expanded chip's uses, value and per-site rows |
| `Visualize.Chart.Builder.Variables.list/2` | every variable the composition declares or uses, alphabetically, typed by its first use |
| `Visualize.Chart.Builder.Variables.type_of/1` | the type a variable took from its first use, or `nil` for none |
| `Visualize.Chart.Builder.Editor.label/1` | a path as a person reads it — the spelling the validator uses for an error's path |

**The context panel opens with an icon row of three panels** — *inspect*, *colour*, *variables* — one open at a time (`context`), *inspect* holding the form and the layer's context, under the node icons and chips that stand above the row (§18.16), each staying put while a person works, the way a drawing tool keeps its pickers beside the canvas. Two panels of the first row of five are now under the tab they doubled (#314): the chart's signals are sources, so they stand under the **sources** root — *inspect* over it shows the sources page and, beneath, the signals panel (below) — and the font keys are a style's, so the font panel stands under the **styles** root, beneath its page, over the node being edited:

| Panel | Shows | Writes |
|---|---|---|
| **inspect** (the default) | the selected node's form (§18.7), then the selected site's key for a name-keyed kind and its free variables (§19.5, §19.3) — its mask is under its row (§18.8); at a style site, the site's stack and the chosen entry's resolved style (§18.18, §18.19) | `key`, the style stack |
| **colour** | `Visualize.Chart.Builder.Picker.panel/1`, the chooser, **patches above the picker**: the theme's colour slots as swatches in their colours and the colour literals the chart already uses first, then a grid of hues at three lightnesses and a picker for any colour; with a colour field selected they write it, with none they show only — and every patch is a colour a person can **drag onto any well** (below) | the selected colour field, through `edit`; any well, through `drop_colour` |
| **inspect** over `styles` | beneath the page, `Visualize.Chart.Builder.Fonts.panel/1`: the families rendered in themselves, size as a slider, the face list of §18.6, text anchor — the font keys of the node being edited, together; a node with none says which to open | `font_family`, `font_size`, `font_weight` and `font_style` (as `font_face`), `text_anchor`, through `edit` |
| **inspect** over `sources` | beneath the page, the signals panel: the chart's signals as rows, +, ×, play and pause, the tick's period (below) | `edit_signal`, `add_signal`, `remove_signal`, `play`, `pause` |
| **variables** | the variable panel, above | `Use.vars`, bindings, declarations |

**Selecting a field opens its panel.** Clicking into a field marks it (`select_field`): the form's `Visualize.Hooks.Builder` is the one listener for clicks — a click on a colour well selects the well's own field, which for a gradient's stop is `fill.stop.<i>` and not the `fill` row it sits in (§18.6), and any other click in a row selects the row's key — and a key pressed in a row selects it too (`phx-keyup`); a row carries no click binding of its own, so one click is never two selections. A colour field opens the colour panel; a font key, and any other field, leaves the panel where it is — a font key is a style's, and the font panel is under the styles root the style's form is in. Selecting a node, a facet or a layer clears the field, and **selecting a layer, a node or a root opens *inspect*** — the tab a site's key lives in, so a source's list is in sight whenever its site is selected, whichever picker was open before. Every control in a picker writes the same `edit` the form does under the same names (`key`, `key.slot`, `key.range`), so a picker is a bigger view of the form's fields and never a second form; the per-field faces of an earlier draft — glyphs, words, references and sliders in the context — live in the form itself (§18.6) and have no second home.

A bare `<input type="color">` would drop the theme slot, and the theme slot is how the built-in styles work; the well shows whichever face the value has, and the chooser offers every face.

**A colour field is a well.** Every `:colour` key in a form — `fill`, `stroke`, a theme's `axis` — renders as one square showing the colour the value resolves to: a slot through the theme the design names (`Visualize.Theme.resolve/3` in `:literal`), a literal as itself, a paint as its gradient's first stop (§18.6), `:none` as a hatched square, an unset key as an empty one; the slot's or literal's word is the well's `title`, and a bound variable shows as its chip in the well's place (§19.9). There is no select of slot names and no picker in the form: a name where the only thing wanted is the colour, and a picker under every colour key, were clutter, and both wrote the key the chooser writes. Clicking the well selects the field and opens the chooser in the context (`select_field`, above). A well is also a **drop target** (`data-builder-well`): every patch in the chooser — a slot, a hue, a colour the chart uses — is draggable (`data-builder-colour`, carried as `application/x-visualize-colour`), and a patch dropped on a well writes that well's key whether or not the field is selected, so one colour is carried to several fields without selecting each. `drop_colour` carries the field and the colour: a word writes the slot as the atom, a `#rrggbb` writes the literal, both through the same `edit` the chooser uses (`key.slot`, `key`), and a key that is not a colour refuses by name. A well in the style panel of the layer context (§18.19) takes a drop the same way, through `edit_style`.

| Function | Contract |
|---|---|
| `Visualize.Chart.Builder.Picker.panel/1` | the chooser: patches — slots and the chart's colours — above the hues and the picker, each patch draggable, writing the selected colour field through `edit` or showing with nothing to write |
| `Visualize.Chart.Builder.Editor.well/2` | what a colour well shows for a value and a theme: the resolved colour, `:none`, or nothing |
| `Visualize.Chart.Builder.Picker.face/1` | which picker a field would get from its key and type: colour, font, glyphs, enum, reference, range or plain |
| `Visualize.Chart.Builder.Fonts.panel/1` | the font panel over the node being edited: families, size, the face list, anchor, through `edit` |
| `Visualize.Chart.Builder.Fills.control?/1` | whether a control of the form belongs to the fill group — `fill_style`, `fill.stop.<i>[.slot\|.opacity]`, `fill.angle`, `fill.centre.x\|y` — rather than to a key |
| `Visualize.Chart.Builder.Fills.name/1` | the gradient named for a style at a path: `:series_fill` for `styles.series`, the path with underscores and `_fill` otherwise |
| `Visualize.Chart.Builder.Fills.style_of/2` | the fill style a fill value shows as, given the design's `defs`: none, solid, linear or radial |
| `Visualize.Chart.Builder.Fills.styles/0` | the four fill styles in order |
| `Visualize.Chart.Builder.Fills.writes/6` | what a fill-group control writes: `{:fill, parsed}`, `{:declare, name, gradient}`, `{:gradient, name, fun}` |
| `Visualize.Chart.Builder.Fills.view/3` | what the form shows for a fill: its style, its paint's name, and for a gradient its stops, angle and centre |
| `Visualize.Chart.Builder.Editor.changes/2` | every write a change to the form means — one for most controls, two for a `font_face` — as `{key, {:ok, value} \| :error}` pairs |
| `Visualize.Chart.Builder.Editor.face/2` | the face a weight and a style show as: one of the eight words, an integer weight rounded to the nearest of the four |
| `Visualize.Chart.Builder.Editor.faces/0` | the eight faces in order, each with the weight and style it writes |
| `Visualize.Chart.Builder.Fonts.keys/1` | the font keys a node kind carries |

**Signals are the chart's sources while it is designed** (#244, spec/08 §8). Each chart of the workspace carries `signals` — a map of name to `Visualize.Signals` signal — part of its structure on Save (`%{composite: %{uses, vars, signals}}`) and read back on open, since a chart without its stand-in sources draws nothing. The signals panel, under the **sources** root, is `Visualize.Chart.Builder.Sources.panel/1`: one row per signal — its name, a kind select, its fields as a comma-separated box, its window, period, min and max — edited in place (`edit_signal`); a **+** declares one (`add_signal`: `signal_n`, a sine over `[t, value]`) **and, with it, a source of the same name in the selected layer** — `sources: %{signal_n: %{fields: [:t, :value]}}` — unless the chart already declares one, so the signal is readable the moment it is added: it stands under the *sources* tab with its columns ticked (#253), and a mark's `data` offers it. Editing the signal's fields afterwards does not rewrite the declaration — the `fields` list shows what the signal now has and marks what it lacks, and a person ticks — and removing the signal leaves the declaration with no rows, which the preview reports; an **×** removes one (`remove_signal`); **play** and **pause** (`play`, `pause`) with the tick's period. While playing the tick advances (`tick`), the pool is regenerated and the graph redraws. The pool the preview binds, and the pool list of a source site (above), is the host's `sources` **under** the chart's signals at the tick — `Visualize.Signals.pool/2` merged over the host's, so where a name is both the signal wins while designing; picking a signal fills a source's fields as picking a pool name does. A deployed design binds to the host's pool alone.

**The layer's context** is `Visualize.Chart.Builder.Masks.panel/1`, shown under the form in the *inspect* tab for the selected site whenever no style entry is chosen: the site's name; one checkbox per path its contribution carries — every top-level key, and the keys of each node under one, which are the paths `Use.mask/2` takes (§19.5) — checked where the mask holds it; and the variables the site still needs, pointing at the Variables tab. The contribution is what the site would say before its mask, `Visualize.Chart.Builder.Stack.unmasked/2`, so a key the mask has removed is still offered to un-mask. A site masked as a whole is disabled (§19.3) and is said so rather than drawn as every box checked. The `mask` event carries the checkbox that changed; an unchecked box submits nothing, which is the path leaving.

| Function | Contract |
|---|---|
| `Visualize.Chart.Builder.Masks.panel/1` | the selected layer's context: its key control, its not-placed fault, and its free variables — the mask checkboxes are the layer row's (§18.8) |
| `Visualize.Chart.Builder.Masks.rows/2` | `rows(fragment, use)`: one row per maskable path of a contribution — its name, whether the use masks it, its class and title — for the row's › Mask item |
| `Visualize.Chart.Builder.Masks.paths/1` | the paths a contribution can mask: top-level keys and each node's keys, sorted |
| `Visualize.Chart.Builder.Masks.toggle/3` | a use with a path added to or removed from its mask, as its checkbox says; a site masked as a whole is left alone |
| `Visualize.Chart.Builder.Glyphs.drawn?/1` | whether a key's enum is chosen by its picture (§18.6) |
| `Visualize.Chart.Builder.Glyphs.icon/1` | the inline SVG of a control's icon — `:eye`, `:eye_off`, `:lock` for the layer row (§18.8); `:inspect`, `:colour`, `:variables` for the panel row; a root's name for the node row (§18.13), any other root as its first letter in a ring |
| `Visualize.Chart.Builder.Glyphs.glyph/2` | the inline SVG for one value of a drawn key, or `nil` |
| `Visualize.Chart.Builder.Masks.keyed?/1` | whether a contribution is of a kind the document keys by name, so the panel offers the key control |
| `Visualize.Chart.Builder.Page.page/1` | a root tab's node as a page of sections (§18.15): facet sections with the node keys' sub-sections inside, the frame's page as a frame, every form aimed at its node |
| `Visualize.Chart.Builder.Page.sections/1` | the sections of a node's page — per facet the value keys and the child nodes; a frame's kind, size, binding and parts |
| `Visualize.Chart.Builder.Editor.form_body/1` | one node's form alone: the fields of one facet, or of the listed keys, carrying the node's label (`_node`, `data-builder-node`) |
| `Visualize.Chart.Builder.Sources.panel/1` | the signals panel, under the sources root: the chart's signals as rows, +, ×, play and pause, the tick's period |
| `Visualize.Chart.Builder.Sources.rows/1` | the signals as the tab's rows, sorted by name — the fields as one comma-separated string, the numbers as pairs |
| `Visualize.Chart.Builder.Sources.edit/3` | `edit(signal, key, value)`: a signal edited by one control of the tab — kind, fields, or a number — left as it is when the value does not read |
| `Visualize.Chart.Builder.Stack.structure/3` | as `structure/2`, with the chart's signals under `signals` when it has any |
| `Visualize.Chart.Builder.tick/2` | `tick(id, socket)`: the host's forwarding of the tick message as an update to the builder (§18.2) |
| `Visualize.Chart.Builder.Masks.pooled?/1` | whether a contribution is a source, whose key control lists the host's pool rather than taking a name |

**A source is chosen from the pool** (#235, #238). The key control of a *source* site is the **pool list**: `<div class="vis-builder-pool" role="radiogroup">`, one `<label class="vis-builder-pool-name">` per name of the pool — the sample sources the host hands the builder (`sources`), sorted — each holding a radio (`name="key"`) and the name, laid out as `ls` lays out a directory: the names flow **down each column, then across** (CSS `columns`, the column width fitted to the names, so the count of columns follows the width the list has), the list bounded in height and **scrolling on its own** when the pool does not fit, the chosen entry marked (`vis-builder-pool-name-on`) and scrolled into view by the hook; a *none* entry first removes the key. **Beneath the list a box takes a name the pool lacks** (`key.other`) — a design may name the source a *future* host supplies, and the site's current name is kept marked in the list while the pool lacks it, so nothing is lost. A source is bound by its name, so the list spares a person guessing at what exists, and the box says what is expected. Choosing a name whose source the pool holds also **fills the source's `fields`** when it declares none — the pool's first row's keys, sorted — so a source is one pick and previews at once; fields already declared are left alone. Every other name-keyed kind — a style, a scale, a gradient, a var — keeps the box alone, since those are named by the person. In the form, a source's `default` (§2.3) is the same list under `name="default"` with its own box (`default.other`), read by `Visualize.Chart.Builder.Editor.change/2` as the key like `key.range` is. A host with an empty pool sees the box alone, there being nothing to list.
| `Visualize.Chart.Builder.Stack.unmasked/2` | what a site contributes before its mask and bindings |

**The typed controls in place.** A field's control is chosen from its type (§18.6), and three types now carry more than a box:

- **a colour** (`Visualize.Chart.Builder.Editor.widget/1` gives `:colour`) is a well in the form, above: the colour itself, selected to open the chooser, dropped on to be written. The chooser's controls are the three faces — the slots as `key.slot`, a hue or the picker as `key` — and a slot chosen writes the atom, a hue or the picker the string.
- **a reference** offers what the document declares locally and what the library holds by id, in one select — for styles, scales and sources alike: an id is spelt as the DOM carries one — `style:11` — and read back through `Visualize.Chart.Builder.Store.decode_id/1`, so `Editor.parse/2` of `{:ref, :style}` gives `{:style, 11}` for the id and an atom for anything else, and no client string of the wrong kind becomes an id. The field is also a **drop target**: the editor's form carries `Visualize.Hooks.Builder` in scope `ref`, each reference field names its key in `data-builder-ref`, and a library entry dropped on it raises `insert` with the field — the same write the select makes, refused by name when the entry is of another kind (*a scale field takes a scale; Styles::thick is a style*); a style dropped on a style field goes onto the site's stack (§18.20).
- **an enum** is the allowed values, as it was.

### 19.11 What §18 said that this section replaces

| §18 | Now |
|---|---|
| §18.2 — the toolbar's library dropdown; the save message carries `stack/1` of the layers | the library is a region (§19.8); the message carries structure (§19.6) |
| §18.3 — `list/0`, `get/1`, `put/2` over names | §19.7 |
| §18.8 — a layer is its position; four things per row | a layer is a `Use` with its own id (§19.3); select, disable-as-mask, drag |
| §18.11 — the parameters form in the tray | the variable panel in the context, chips dropped on fields (§19.9, §19.10); `Params.panel/1` stays a component a host may render on its own |
| §18.14 — a style palette that creates named styles in the selected layer | a declaration in place is values; a name is the library's (§19.1, §19.2) |
| §18.16 — four regions, a store of names | three regions (§19.9); a store of ids (§19.7) |
| §18.20 — a dropped style fragment merges its `styles` declaration into the design | a dropped fragment is a `Use` with its id as `ref`; nothing is merged, and nothing is copied |
| §18.12 — an imported document is the builder's single layer | it is decomposed into sites, one kind each (§18.12) |
| §19.8 — a multi-root fragment is of kind `design` | it is no kind of fragment; the thing that is many kinds is a composite, and design is only what Deploy makes |

The rule underneath all of it: **the thing a person renames is never the thing a reference uses.** A name is an attribute of a library entry; a reference is an id; a declaration in place has neither. Nothing in the model ever has to hunt for a word.
