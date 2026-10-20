# Rendering Backends

**Status:** Implemented

The rendering layer turns the backend-agnostic IR (`Visualize.IR.Element`, `Visualize.IR.Path`, `Visualize.IR.Transform`; see spec/02) into a delivery format. Two modules implement the `Visualize.Backend` behaviour: `Visualize.Backend.SVG` emits SVG markup as an iolist and `Visualize.Backend.Canvas` emits Canvas 2D drawing commands as JavaScript, JSON or Elixir tuples. `Visualize.Backend.CanvasBinary` packs the same drawing commands into a compact little-endian binary stream for the browser; `Visualize.Backend.CanvasIncremental` and `Visualize.Incremental` layer scroll-and-copy partial updates on top of it; `Visualize.Backend.Hybrid` splits one chart into a static SVG layer and a dynamic Canvas layer; `Visualize.Benchmark` measures them all. This document is the byte-level and command-level contract for every one of those outputs.

## 1. Scope and shared conventions

### 1.1 Modules covered

| Module | Role |
|---|---|
| `Visualize.Backend.SVG` | `Visualize.Backend` implementation producing SVG markup |
| `Visualize.Backend.Canvas` | `Visualize.Backend` implementation producing Canvas 2D commands |
| `Visualize.Backend.Canvas.Arc` | Internal: SVG arc to Canvas `ellipse` (endpoint-to-center conversion) |
| `Visualize.Backend.Canvas.Output` | Internal: the `:js` and `:json` serializers of the command list, and the hatch pattern source `hatch_js/0` the hooks share |
| `Visualize.Backend.CanvasBinary` | Binary encoder for Canvas commands (IR and `Visualize.SVG.Element` input) |
| `Visualize.Backend.CanvasBinary.Opcodes` | Internal: opcode byte constants |
| `Visualize.Backend.CanvasBinary.PathEncoder` | Internal: the `path_cubic` command stream |
| `Visualize.Backend.CanvasBinary.SVG` | Internal: `Visualize.SVG.Element` to binary |
| `Visualize.Backend.CanvasIncremental` | Scroll classification, exposed regions, incremental records |
| `Visualize.Backend.Hybrid` | Static SVG + dynamic Canvas split |
| `Visualize.Incremental` | Stateful high-level API over `CanvasIncremental` |
| `Visualize.Benchmark` | Throughput and payload comparison |
| `Visualize.Render.Raster` | Internal: the one module that runs the resvg binary, behind `Visualize.Render.to_png/2` (§9) |
| `Visualize.Render.Segments` | A drawing as keyed segments of a backend's output, written again only where an element changed (§1.4, D-203) |

### 1.2 The backend behaviour

`Visualize.Backend` (spec/02) declares `path_data/1`, `render_path/2`, `render_element/2`, `render_scene/2` and the optional `wrap_root/2`. Both built-in backends implement all five. Only the one-argument forms `render_element/1`, `render_path/1` and `render_scene/1` are public API; the two-argument callback implementations, `path_data/1` and `wrap_root/2` are `@doc false` and reachable only through `Visualize.Render` (spec/02) or the behaviour dispatch. The one-argument forms are the two-argument forms with `opts = []`.

`Visualize.Backend.resolve/1` maps `:svg` to `Visualize.Backend.SVG`, `:canvas` to `Visualize.Backend.Canvas`, `nil` to the configured default (`config :visualize, default_backend:`, itself defaulting to `Visualize.Backend.SVG`) and any other atom to itself as a module.

### 1.3 Number formatting

Wherever this document says "formatted", a number goes through `Visualize.IR.Path.format_number/1` (spec/02 §2.2; D-12, D-32): an integer as-is; a float with at most four decimals, trailing zeros and point trimmed, never in exponent notation, never `-0`. A float that rounds to a whole number is written as that integer's digits, at any magnitude (#812): `1.0e20` is `100000000000000000000`, as before, and a float past about `1.0e253`, which the four-decimal conversion could not write and raised on, is its digits too. Every number of every drawing passes through it, so it builds only the text it returns. The SVG backend uses it for path data, transform strings and points; the Canvas backend for every numeric argument.

SVG *attribute* values (as opposed to path data, transform strings and points) are NOT formatted: numbers are printed with `to_string/1`, so a float attribute keeps its full precision and may use exponent notation (`1.0e3`).

### 1.4 Segments

**A drawing is also its segments** (#813, D-203). `Visualize.Render.Segments` cuts the output of a backend into one segment per element drawn alone and one for each start and end of a group, in drawing order, each `{key, text}`, so that a page that sends a drawing as a keyed list sends only the segments a change touched (spec/10 §19.3):

- **What a segment is.** A group and the root are their start, their children's segments and their end; any other element — and a group that names its identity (`data-vis-id`) or is clipped — is one segment, its text what the backend writes for it in the style its groups give it. A segment with no text (a canvas stream's root, a group with nothing to set) is left out.
- **The texts are the output.** `svg/2`'s texts concatenated are `Visualize.Render.to_string(tree, backend: :svg)`, byte for byte. `json/2`'s texts are each segment's commands as the `:json` output writes them (§3.5) without the brackets: joined by commas and bracketed, they are `Visualize.Render.to_string(tree, backend: :canvas, format: :json)`. `binary/2`'s texts are pieces of the binary stream (§4) in base64, the stream's head — its version and paint records — the first: decoded and concatenated, they are `Visualize.Backend.CanvasBinary.encode_element!/1` of the tree. `text/2` puts them together. Each backend cuts its own output (`segment` in `Visualize.Backend.SVG`, `Visualize.Backend.Canvas` and `Visualize.Backend.CanvasBinary`), so a segment is never a second serializer of what it holds.
- **The keys.** An element that names its identity (spec/14 §3.10, D-167) is keyed `"id:" <> identity`; a group's start and end by its path from the root — each element's index among its parent's children, `"r/2/1"` — followed by `<` and `>`; any other element by its group's path, `~` and a hash of the element and the style it inherits, so an element keeps its key when an element before it comes or goes, and one drawn differently is another. A key is never repeated: a second element of one key is keyed as the first with `#2`, and so on.
- **The cache.** Each function takes the cache the previous call returned and returns the next: an element drawn alone whose key, element and inherited style are equal to the last drawing's — compared whole, never by the hash — reuses the text written then. A cache is an economy only: the segments are the same with `%{}`. It holds the last drawing's elements and nothing older; a cache of another output, or for the binary stream of another set of paints, is not read.

| Function | Contract |
|---|---|
| `Visualize.Render.Segments.svg/2` | `svg(tree, cache)`: `{segments, cache}`, the tree's SVG markup in segments. |
| `Visualize.Render.Segments.json/2` | `json(tree, cache)`: `{segments, cache}`, the tree's `:json` canvas commands in segments. |
| `Visualize.Render.Segments.binary/2` | `binary(tree, cache)`: `{segments, cache}`, the tree's binary canvas stream in base64 segments, its head first. |
| `Visualize.Render.Segments.text/2` | `text(segments, format)`: the output the segments are of, `:svg`, `:json` or `:binary` (in base64). |

## 2. Visualize.Backend.SVG

### 2.1 Functions

Every function of this module is an `@impl` callback of `Visualize.Backend` (`render_element/2`, `render_path/2`, `render_scene/2`, `path_data/1`, `wrap_root/2`) or a default-argument head of one, and is therefore internal: it is reached through `Visualize.Render` (spec/02 §3) or by a backend-agnostic caller holding the module. The contracts below describe the callbacks.

### 2.2 Options

The hidden two-argument forms accept a keyword list. `render_element/2` ignores its options entirely.

| Function | Key | Default | Meaning |
|---|---|---|---|
| `render_path/2` | `:style` | `%{}` | Style map serialized per 2.5 onto the `<path>` |
| `render_scene/2` | `:wrap` | `true` | When true, wrap the rendered elements with `wrap_root/2`; when false return the bare list of iolists |
| `wrap_root/2` | `:width` | `800` | `width` attribute of the `<svg>` root |
| `wrap_root/2` | `:height` | `600` | `height` attribute of the `<svg>` root |
| `wrap_root/2` | `:view_box` | `"0 0 #{width} #{height}"` | `viewBox` attribute of the `<svg>` root |

`wrap_root/2` MUST emit `<svg xmlns="http://www.w3.org/2000/svg" width=".." height=".." viewBox="..">…</svg>`.

### 2.3 Element rendering

Each `IR.Element` type maps to exactly one tag. "attrs" is `element.attrs`, "style" is `style_to_attrs(element.style)` (2.5), "transform" is the serialized `element.transform` (2.5) added as a `transform` attribute when the transform is non-nil and has at least one operation.

| IR type | Tag | Attributes emitted | Children / content |
|---|---|---|---|
| `:path` | `path` | attrs, then style merged over it, `d` = `path_data/1` of `element.path`, transform | none (self-closing) |
| `:group` | `g` | style, then attrs merged over it, transform | children rendered recursively |
| `:root` | `svg` | `xmlns="http://www.w3.org/2000/svg"`, then attrs (`view_box` emitted as `viewBox`, 2.4); `element.style` and `element.transform` are ignored | children |
| `:rect`, `:circle`, `:ellipse`, `:line`, `:image` | same name | attrs, then style merged over it, transform | none |
| `:polyline`, `:polygon` | same name | `points` (2.6), style, transform; every other key in attrs is dropped | none |
| `:text` | `text` | attrs, style, transform | `element.content` as escaped text, then the children — its `tspan`s when it has lines |
| `:tspan` | `tspan` | attrs | `element.content` as escaped text |
| `:title`, `:desc` | same name | attrs (the `id`) | `element.content` as escaped text |
| `:style` | `style` | none | `element.content`, a stylesheet, as escaped text (a root's automatic dark mode, spec/08 §7.3, #668) |
| `:defs` | `defs` | none | children |
| `:clip_path` | `clipPath` | attrs verbatim | children |
| `:linear_gradient` | `linearGradient` | attrs verbatim | children |
| `:radial_gradient` | `radialGradient` | attrs verbatim | children |
| `:pattern` | `pattern` | attrs verbatim (`pattern_units`, `pattern_transform` as `patternUnits`, `patternTransform`) | children: a hatch's tile (#673) |
| `:stop` | `stop` | attrs, style | none |
| `:filter` | `filter` | attrs verbatim | children |
| `:fe_drop_shadow`, `:fe_gaussian_blur` | `feDropShadow`, `feGaussianBlur` | attrs (`std_deviation` as `stdDeviation`, `flood_opacity` as `flood-opacity`, `flood_color` as `flood-color`) | none |

An element with a `clip` (spec/02 §2.1) renders as its definition followed by the element: for `:inside` a `<clipPath id="vis-clip-<h>">` holding the shape (rendered as any element, its style dropped) and `clip-path="url(#vis-clip-<h>)"` on the element; for `:outside` a `<mask id="vis-mask-<h>" maskUnits="userSpaceOnUse" x="-100000" y="-100000" width="200000" height="200000">` holding a white rectangle of that extent and the shape in black, and `mask="url(#vis-mask-<h>)"` on the element. `<h>` is the lower-case base-36 `:erlang.phash2/1` of the shape, so equal shapes share a definition and different ones never collide; the definition stands beside the element, which SVG allows anywhere, so no `defs` need be threaded up the tree. SVG resolves a clip and a mask in the user space of the element that refers to them, under its `transform`, so the shape is written without one (spec/02 §2.1): before #825 it kept the element's, and a translated clipped element — a `:symbol` with an inside or outside stroke — was clipped twice as far away and drew nothing (D-211).

A path's attrs are the data attributes of spec/10 §12.2 and §14.2 — the datum a per-series path carries and the `data-series` every element of a series carries (D-75, D-77, D-126); before those a path had no attrs to print. Any other type raises `FunctionClauseError`. Tags in `circle ellipse line path polygon polyline rect image use stop feDropShadow feGaussianBlur` are emitted self-closing (`<rect …/>`) when they have neither children nor content; all other tags are emitted as `<tag …>content children</tag>`.

### 2.4 Attribute serialization

Tags, attributes and text are rendered by the functions of `Visualize.SVG.Renderer` (spec/02 §5.4), so this backend and the HEEx bridge emit one markup for one IR (D-34):

- Attributes whose value is `nil` MUST be omitted.
- Each key's SVG name comes from `Visualize.SVG.Renderer.attribute_name/1`: underscores become hyphens (`stroke_width` → `stroke-width`) except for the camel-cased SVG attributes, which map to their spelling (`view_box` → `viewBox`, D-11).
- Attributes MUST be emitted sorted by that SVG name.
- Binary values are escaped: `&` → `&amp;`, `"` → `&quot;`, `<` → `&lt;`, `>` → `&gt;`. Numbers and atoms are printed with `to_string/1` and `Atom.to_string/1` and are not escaped.
- Text content is escaped for `&`, `<`, `>` only.

### 2.5 Style and transform serialization

A color value reaches the SVG backend already resolved for `:css` (spec/08 §1.9, §7.3). A theme name arrives as `var(--vis-…, literal)`, and a typed color's transform as the CSS that computes it, `color-mix(in oklab, …)` or a relative `oklch(from …)` (#665). The backend writes either as it writes any string. A canvas backend is given `:literal` colors, where a transform is the literal it computes.

`style_to_attrs/1` drops `nil` values and converts atoms that have SVG spellings:

| Style key | Atom value | Emitted |
|---|---|---|
| `:fill`, `:stroke` | `:none` | `"none"` |
| `:fill`, `:stroke` | `:current_color` | `"currentColor"` |
| `:fill`, `:stroke` | a `Visualize.IR.Paint` (spec/02 §2.1) | `"url(#<id>)"`, in either mode: the gradient is the `:defs` element the producer wrote under that id (#652) |
| `:text_anchor` | `:start`, `:middle`, `:end` | `"start"`, `"middle"`, `"end"` |
| `:stroke_linecap`, `:stroke_linejoin` | any atom | `Atom.to_string/1` |
| `:dominant_baseline` | any atom | `Atom.to_string/1` |
| `:vector_effect` | `:non_scaling_stroke` | `vector-effect="non-scaling-stroke"` (spec/14 §3.9, #651). The property does not inherit, so on a `:group` it is not written on the group: each child takes it, a child group passing it on the same way, unless the child sets its own |
| `:blend` | any atom | dropped for `:normal`; else `style="mix-blend-mode: <word>"`, the word the atom's name with each `_` a `-` (`:color_dodge` is `color-dodge`) — an inline `style` attribute, since `mix-blend-mode` is a CSS property and not a presentation attribute every browser honors |
| `:transition`, `:animation`, `:enter`, `:exit` | a list, maps (spec/14 §3.10–§3.12) | dropped: never an attribute. In `:css` output the frame has already written it as a class and a rule in its `<style>` (#653); any other SVG — a `:literal` render rasterized for a PNG — draws the element's end state |
| `:effect` with `:effect_radius`, `:effect_offset`, `:effect_color` | `:shadow`, `:blur` | `filter="url(#vis-effect-<effect>-<radius>)"`, the radius `3` when absent, and `url(#vis-effect-shadow-<radius>-<h>)` for a shadow with an offset or a color, `<h>` the base-36 `:erlang.phash2/1` of `{offset, color}` (spec/14 §2.7, #674); `:none` and the three keys alone are dropped |

Every other `{key, value}` pair passes through unchanged and is serialized per 2.4, so `stroke_width: 2` becomes `stroke-width="2"` and `font_size: 12` becomes `font-size="12"`.

A transform is serialized by `Visualize.IR.Transform.to_string/1` (spec/02 §2.3): its operations joined by a single space, each formatted per 1.3:

| Operation | String |
|---|---|
| `{:translate, x, y}` | `translate(x,y)` |
| `{:rotate, a}` | `rotate(a)` |
| `{:rotate, a, cx, cy}` | `rotate(a,cx,cy)` |
| `{:scale, sx, sy}` | `scale(sx,sy)`, or `scale(s)` when `sx == sy` |
| `{:skew_x, a}` | `skewX(a)` |
| `{:skew_y, a}` | `skewY(a)` |
| `{:matrix, a, b, c, d, e, f}` | `matrix(a,b,c,d,e,f)` |

### 2.6 Path and point data

`path_data/1` is `Visualize.IR.Path.to_string/1` (spec/02 §2.2; D-12): each `IR.Path` command joined with no separator, each as its SVG letter followed by its comma-separated formatted arguments — `{:M, x, y}` → `Mx,y`; `{:L, x, y}` → `Lx,y`; `{:H, x}` → `Hx`; `{:V, y}` → `Vy`; `{:C, x1, y1, x2, y2, x, y}` → `Cx1,y1,x2,y2,x,y`; `{:S, x2, y2, x, y}` → `S…`; `{:Q, x1, y1, x, y}` → `Q…`; `{:T, x, y}` → `T…`; `{:A, rx, ry, rot, large, sweep, x, y}` → `Arx,ry,rot,large,sweep,x,y` (the two flags printed verbatim); `:Z` → `Z`. The lower-case relative forms (`:m :l :h :v :c :s :q :t :a`) are emitted with the lower-case letter and the same argument layout.

`points` for `:polyline`/`:polygon` is a list of `{x, y}` tuples formatted as `x,y` pairs joined by single spaces; a binary `points` value is emitted verbatim.

### 2.7 Protocol implementations

This module defines `String.Chars` for `Visualize.IR.Element` (`to_string/1` = `render_element/1` flattened to a binary) and, only when `Phoenix.HTML.Safe` is loaded at compile time, `Phoenix.HTML.Safe` for `Visualize.IR.Element` (`to_iodata/1` = `render_element/1`). See spec/10 for how this interacts with HEEx.

## 3. Visualize.Backend.Canvas

### 3.1 Functions

Every function of this module is an `@impl` callback of `Visualize.Backend` (`render_element/2`, `render_path/2`, `render_scene/2`, `path_data/1`) or a default-argument head of one, and is therefore internal: it is reached through `Visualize.Render` (spec/02 §3) or by a backend-agnostic caller holding the module. The contracts below describe the callbacks.

### 3.2 Options and output formats

| Function | Key | Default | Accepted values |
|---|---|---|---|
| `render_element/2` | `:format` | `:js` | `:js`, `:json`, `:commands`, `:binary`, `:binary_base64` |
| `render_path/2` | `:format` | `:js` | `:js`, `:json`, `:commands` |
| `render_path/2` | `:style` | `%{}` | Style map (3.3.3) |
| `render_scene/2` | `:format` | `:js` | `:js`, `:json`, `:commands`, `:binary`, `:binary_base64` |
| `wrap_root/2` | `:width` | `800` | Canvas element width |
| `wrap_root/2` | `:height` | `600` | Canvas element height |
| `wrap_root/2` | `:canvas_id` | `"visualize-canvas"` | `id` of the emitted `<canvas>` |
| `wrap_root/2` | `:title` | `nil` | The canvas's accessible name (D-142, spec/14 §21.4) |
| `wrap_root/2` | `:description` | `nil` | The canvas's accessible description and fallback content |

Output per format:

- `:commands` — the Elixir list of `{name :: atom, args :: list}` tuples of 3.3.
- `:js` — an iolist of JavaScript statements against a variable named `ctx`, one per command, separated by `\n` (3.4). `render_scene/2` additionally wraps the statements as `// Generated by Visualize Canvas Backend\n(function(ctx) {\n…})(context);\n`.
- `:json` — an iolist forming a JSON array of `{"cmd": name, "args": [...]}` objects (3.5).
- `:binary` — `Visualize.Backend.CanvasBinary.encode_element!/1` of the element (section 4); for `render_scene/2`, the per-element binaries concatenated in order (D-37).
- `:binary_base64` — the `:binary` output passed through `CanvasBinary.to_base64/1`.

`render_element/2` and `render_scene/2` accept all five formats; `render_path/2` accepts `:js`, `:json` and `:commands`.

### 3.3 Command tuples

#### 3.3.1 Element commands

Each element produces, in order, its *setup* (transform commands per 3.3.4, then style setup per 3.3.3), its *geometry*, and its *apply* commands (3.3.3). "T" is `transform_commands(element.transform)`, "S" is `style_setup_commands(element.style)`, "A" is `style_apply_commands(element.style)`.

**A leaf's setup is its own** (#679, D-179). Every element below other than `:group` and `:root` is a *leaf*. A leaf whose setup — T and S, or T and the text style for a `:text` — is not empty is drawn inside a `{:save, []}` … `{:restore, []}` pair: `{:save, []}`, the setup, the geometry and the apply commands, `{:restore, []}`. So its transform, its colors, its alpha, its blend, its effect and its font are never the state its next sibling draws in, and the sibling draws where and how SVG draws it — in its own transform and the state of the groups above it. A leaf whose setup is empty writes neither command, so a chart's unstyled, untransformed leaves (the paths of a mark whose style is its group's) cost nothing. The rows of the table give the commands inside the pair.

| IR type | Commands |
|---|---|
| `:path` | T, S, `{:beginPath, []}`, `path_data/1` (3.3.2), A |
| any shape with a `clip` | `{:save, []}`, T (the element's own, so the clip is in its user space, as SVG's is — D-211), `{:beginPath, []}`, the shape's geometry (a `:path`'s `path_data/1`, a `:rect`'s `{:rect, …}`, a `:circle`'s `{:arc, …}`, a `:polygon`'s `moveTo`/`lineTo`/`closePath`), then `{:clip, []}` for `:inside` — or, for `:outside`, the geometry preceded by `{:rect, [-100000, -100000, 200000, 200000]}` and followed by `{:clip, ["evenodd"]}` — then the element's own commands without its transform, then `{:restore, []}` |
| `:rect` | T, S, `{:beginPath, []}`, `{:rect, [x, y, width, height]}`, A — `attrs` MUST contain `:x`, `:y`, `:width`, `:height` |
| `:circle` | T, S, `{:beginPath, []}`, `{:arc, [cx, cy, r, 0, 2π]}`, A — `attrs` MUST contain `:cx`, `:cy`, `:r` |
| `:ellipse` | T, S, `{:beginPath, []}`, `{:ellipse, [cx, cy, rx, ry, 0, 0, 2π]}`, A |
| `:line` | T, S, `{:beginPath, []}`, `{:moveTo, [x1, y1]}`, `{:lineTo, [x2, y2]}`, then the stroke's apply commands (3.3.3) where its *effective* stroke is present — its own or a group's above it, a paint stroke drawn as below — and nothing where it is absent or `:none`, as SVG draws no line without a stroke; never filled, a line having no area (#757, D-122) |
| `:polyline` | T, S, `{:beginPath, []}`, `moveTo` first point then `lineTo` each remaining point, A; no commands for an empty or missing `points` list |
| `:polygon` | as `:polyline` plus `{:closePath, []}` after the last `lineTo` |
| `:text` | T, text style (3.3.3), `{:fillText, [content or "", x, y]}` with `x`/`y` from attrs defaulting to `0` |
| `:group` | `{:save, []}`, T, S, children's commands, `{:restore, []}` — always, its setup empty or not |
| `:root` | children's commands only |
| `:image` | T, `{:drawImage, [href, x, y, width, height]}` — scoped as any leaf when T is not empty |
| `:defs`, `:clip_path`, `:linear_gradient`, `:radial_gradient`, `:pattern`, `:stop`, `:title`, `:desc`, `:style` | nothing |

A `:group`'s style setup is emitted after its transform, inside the `save`/`restore` pair, so that children without their own style inherit fill, stroke and line width through Canvas state — and the `fill`/`stroke` calls that end a child's path are decided by its *effective* style, its own over the groups' above it, since a state that is set but never applied draws nothing (#231); `Visualize.Backend.Hybrid` relies on this when it wraps a list of dynamic elements in a styled group (6.3) (D-37).

#### 3.3.2 Path commands

`path_data/1` first normalizes the path with `Visualize.IR.Path.absolute/1` (spec/02 §2.2) — relative commands resolved against the current point, `H`/`V` as `L`, `S`/`T` expanded — and then maps each absolute command to one Canvas call, tracking the current point and the subpath start (D-37):

| Normalized command | Tuple |
|---|---|
| `{:M, x, y}` | `{:moveTo, [x, y]}` |
| `{:L, x, y}` | `{:lineTo, [x, y]}` |
| `{:C, x1, y1, x2, y2, x, y}` | `{:bezierCurveTo, [x1, y1, x2, y2, x, y]}` |
| `{:Q, x1, y1, x, y}` | `{:quadraticCurveTo, [x1, y1, x, y]}` |
| `{:A, rx, ry, rot, large, sweep, x, y}` | `{:ellipse, [cx, cy, rx', ry', rot·π/180, θ₁, θ₁ + Δθ, sweep == 0]}` by the SVG endpoint-to-center conversion (`Visualize.Backend.Canvas.Arc`): radii too small for the chord scale up to fit, `large` and `sweep` choose the center and the direction, `Δθ` is adjusted by a full turn to match `sweep`; nothing when the arc's end point equals the current point; `{:lineTo, [x, y]}` when a radius is `0` |
| `:Z` | `{:closePath, []}`; the current point returns to the subpath start |

Every tuple names a Canvas 2D method, so the `:commands`, `:json` and `:js` outputs are all directly executable.

#### 3.3.3 Style commands

`style_setup_commands/1` (empty map → no commands) emits, in this order and only for keys present and non-nil:

| Style key | Command | Notes |
|---|---|---|
| `:fill` | `{:set_fillStyle, [css]}` | omitted for `:none`; `:current_color` → `"currentColor"`; any other value via `to_string/1` |
| `:stroke` | `{:set_strokeStyle, [css]}` | same rules |
| `:stroke_width` | `{:set_lineWidth, [w]}`; with `vector_effect: :non_scaling_stroke`, `{:nonScalingLineWidth, [w]}` | the second sets `lineWidth` to `w` divided by the scale of the transform current when it runs, `√|a·d − b·c|` of `getTransform()`, so the stroke keeps its width on screen (spec/14 §3.9, #651). It is the one command that names no Canvas 2D method (D-37): the width depends on the transform at draw time |
| `:stroke_linecap` | `{:set_lineCap, [to_string(v)]}` | |
| `:stroke_linejoin` | `{:set_lineJoin, [to_string(v)]}` | |
| `:stroke_dasharray` | `{:setLineDash, [lengths]}` | the lengths of SVG's `stroke-dasharray`, apart by spaces or commas, or a list of numbers; `none` is `[]`, the solid line; a value that does not read writes nothing (#675) |
| `:opacity` | `{:set_globalAlpha, [o]}` | |
| `:blend` | `{:set_globalCompositeOperation, [word]}` | omitted for `:normal`; the word as SVG writes it (2.5), each `_` of the atom's name a `-` |
| `:effect` | `:shadow`: `{:set_shadowColor, [c]}`, `{:set_shadowBlur, [r]}`, `{:set_shadowOffsetX, [dx]}`, `{:set_shadowOffsetY, [dy]}`; `:blur`: `{:set_filter, ["blur(<r>px)"]}`; `r` the `:effect_radius`, `3` when absent; `[dx, dy]` the `:effect_offset`, `[r / 2, r / 2]` when absent; `c` the `:effect_color` as `rgba()` (as a stop is, 3.3.3), `"rgba(0,0,0,0.35)"` when absent (#674) | omitted for `:none` |

`style_apply_commands/1` emits `{:fill, []}` when `:fill` is present and not `:none`, then `{:stroke, []}` when `:stroke` is present and not `:none`.

**A paint's own opacity** (#675, D-180). Where the effective style (3.3.1) has a `:fill_opacity` other than `1`, the fill's draw — `{:fill, []}`, or a paint's `save` … `restore` — is preceded by `{:set_globalAlpha, [o · f]}` and followed by `{:set_globalAlpha, [o]}`, `o` the effective `:opacity` (`1` when absent) and `f` the fill's opacity; a `:stroke_opacity` does the same around the stroke's draw, a `:line`'s included, and a `:text`'s `fillText` takes its `:fill_opacity` alike. The element's own alpha is `o` everywhere else, so a paint's opacity is its draw's alone, as SVG's `fill-opacity` and `stroke-opacity` are; inside a leaf's `save`/`restore` (3.3.1) nothing of it outlives the element. A gradient's stops carry their own alpha (below), which the context multiplies with it. `setLineDash` is a Canvas 2D method, so `:json` and `:js` need no helper for it.

**A paint is drawn, not set** (#652, D-175). A `:fill` or `:stroke` that is a `Visualize.IR.Paint` (spec/02 §2.1) emits no `set_fillStyle`/`set_strokeStyle` in the setup: a canvas gradient lives in absolute coordinates, so it is built for each element over that element's own box, SVG's `objectBoundingBox`, where the element is drawn. Where the *effective* style (own over the groups', 3.3.1) holds a paint, the `{:fill, []}` or `{:stroke, []}` of the apply commands is replaced by the paint's draw, taken over the element's tight bounding box `{x, y, w, h}` (`Visualize.IR.Paint.bounds/1`) and wrapped in `{:save, []}` … `{:restore, []}`, so the gradient never becomes the state a later sibling inherits:

| Paint | Fill | Stroke |
|---|---|---|
| `:linear` `x1 y1 x2 y2` | `{:linearGradient, ["fill", x0, y0, x1', y1', stops]}`, `{:fill, []}` | the same with `"stroke"` and `{:stroke, []}` |
| `:radial` `cx cy r` | `{:transform, [w, 0, 0, h, x, y]}`, `{:radialGradient, ["fill", cx, cy, r, stops]}`, `{:fill, []}` | `{:radialGradient, ["stroke", x + cx·w, y + cy·h, r·√(w·h), stops]}`, `{:stroke, []}` |

- **A linear gradient is mapped exactly.** In box units the gradient's value at a point `u` is `t = ((u − u₁)·d) / (d·d)` with `d = u₂ − u₁`; the box maps `u` to the user point `p = (x + uₓ·w, y + u_y·h)`, an affine map, so `t` is affine in `p` too and its isolines stay parallel — SVG's skew on a box that is not square included. Its gradient in user units is `g = (dₓ/w, d_y/h) / (d·d)`, so the canvas gradient runs from `P₀ = (x + x1·w, y + y1·h)`, where `t = 0`, to `P₁ = P₀ + g / |g|²`, where `t = 1`: `x0 y0 x1' y1'` above.
- **A radial fill is drawn in box units.** A radial gradient in `objectBoundingBox` units is an ellipse on a box that is not square, which no `createRadialGradient` is; but the fill takes its paint in the transform current when `fill()` runs, and the path was fixed in user units when it was built, so the box transform set between the two draws the ellipse exactly. **A radial stroke is the one approximation:** the same transform would scale the line's width unevenly, so a stroke is drawn with the circle of the same area, centered where the ellipse is — exact on a square box.
- **A box without area draws nothing.** SVG renders no `objectBoundingBox` paint on an element whose box has no width or no height — an axis-aligned line, a flat path — so neither does a canvas: the fill or stroke is left out.
- `stops` is a list `[[at, color], …]` in `at` order, each color the stop's resolved through `Visualize.Color.parse/1` with the stop's opacity multiplied into its alpha, written `rgba(r,g,b,a)`; a color it cannot read is opaque black, as a binary color is (4.6).
- `linearGradient` and `radialGradient` are, with `nonScalingLineWidth`, the commands that name no Canvas 2D method: each sets `<target>Style` to the gradient `createLinearGradient(x0, y0, x1, y1)` or `createRadialGradient(cx, cy, 0, cx, cy, r)` builds, its focus its center, with `addColorStop(at, color)` for each stop.
- **A hatch is drawn whatever the box** (#673): its tile is laid in user units from the origin, as SVG's `userSpaceOnUse` pattern is, so it needs no box and an element without area is still drawn. Its draw is `{:hatchPattern, [target, pattern, angle, spacing, width, color, background]}` then the `fill` or `stroke`, in the same `save`/`restore` — `pattern` the word `lines`, `crosshatch` or `dots`, `background` `nil` for none, the colors `rgba()` as stops are. The command sets `<target>Style` to a `CanvasPattern` made from an offscreen tile: a canvas `n = ⌈4·spacing⌉` pixels square — four times the period, so a period that is not a whole pixel is not rounded — scaled by `n / spacing`, holding the background and, centered, the horizontal line (and for `crosshatch` the vertical one) of `width`, or the dot of radius `width`, exactly the SVG tile; the pattern's transform is `rotate(angle)` then `scale(spacing / n)`, so one tile is one period of user units, turned as `patternTransform` turns the SVG one.
- **A text filled with a paint takes its first stop's color** (`set_fillStyle`), the one fallback left: the server cannot measure a text's box, and a canvas text is rare — a compiled chart draws its texts as SVG (spec/14 §12.3).

**An absent fill is not `:none`** (#487, D-122). An element with no `:fill` in its own style or any group's above it fills nothing here, while the SVG backend writes no `fill` attribute and the SVG initial value, black, paints it: the two backends agree on `:none` and disagree on absence. Neither backend papers over it — the IR is the caller's, and a hand-built SVG path relies on the initial value — so a producer that must draw the same on both says `:none`. The declarative layer does: a mark element whose color reading is missing carries `fill: :none` (spec/14 §3.4).


A `:text` with `:tspan` children (its lines, spec/14 §7.1) emits its style commands once, then one `fillText` per line at the text's `x` and at `y` plus the sum of the lines' `dy` so far, a `dy` in `em` read as that many times the style's `font_size` (`10` when absent).

Text style (`:text` elements only) emits `{:set_font, [font]}` when any of `:font_size` (default `10`), `:font_family` (default `"sans-serif"`), `:font_weight` or `:font_style` is set, `font` being the CSS shorthand `[style] [weight] size family` — `12px serif`, `italic 300 12px sans-serif`, `bold 12px serif` — with the style and the weight present only when set; `{:set_textAlign, ["left" | "center" | "right"]}` for `:text_anchor` `:start | :middle | :end`; and `set_fillStyle` under the fill rules above. No other style keys affect Canvas output.

#### 3.3.4 Transform commands

A `nil` transform or one with no operations emits nothing. Otherwise one command per operation, in order:

| Operation | Command |
|---|---|
| `{:translate, x, y}` | `{:translate, [x, y]}` |
| `{:rotate, deg}` | `{:rotate, [deg·π/180]}` |
| `{:rotate, deg, cx, cy}` | `{:rotate_around, [deg·π/180, cx, cy]}` |
| `{:scale, sx, sy}` | `{:scale, [sx, sy]}` |
| `{:skew_x, deg}` | `{:transform, [1, 0, tan(deg·π/180), 1, 0, 0]}` |
| `{:skew_y, deg}` | `{:transform, [1, tan(deg·π/180), 0, 1, 0, 0]}` |
| `{:matrix, a, b, c, d, e, f}` | `{:transform, [a, b, c, d, e, f]}` |

#### 3.3.5 Motion commands

**Implemented** (#653, work item #676, D-176). An element that carries a `"data-vis-id"` attribute — which only an element of a moving mark does (spec/14 §3.10) — is drawn inside a **motion span**: `{:motion, [id, box, transitions]}` before the element's commands and `{:motionEnd, []}` after them, the span holding exactly that element's own commands.

- `id` is the attribute's value, the identity the hook keys the element's shown values by.
- `box` is `[x, y, w, h]`, the element's tight box as drawn: `Visualize.IR.Paint.bounds/1` of the element mapped through its own transform — the corners' bounds — in the user units the span opens in, `null` for an element without one (#677).
- `transitions` is the resolved transition of the element's effective style — its own `:transition`, else the one a group above it carries — as a list of `[property, duration, samples]`, `property` `"fill"`, `"stroke"` or `"opacity"`, `duration` in milliseconds, and `samples` the easing's 21 values at `t = 0, 0.05, …, 1` (`Visualize.IR.Motion.samples/1`) — the curve CSS's `linear()` is written from, so both backends ease alike. It is empty for an element whose style moves nothing, and the span is still written: a mark whose data choose a moving style for some rows draws every row in a span, so the hook knows what each identity shows before a later stream moves it.

- `animation` (#677, spec/14 §3.11), a fourth argument present when the element's effective style animates: `[name, duration, samples, iterations, delay, keyframes]` — the keyframes' name (a built-in's without the `vis-` prefix), `iterations` `null` for `:infinite`, and `keyframes` a built-in's as `[[offset, opacity, x, y, rotate, scale], …]`, `null` for an absent value, or `null` for a host's.

- `enter` and `exit` (#678, spec/14 §3.12), the fifth and sixth arguments, present when the element's style has either, an absent animation then `null`: `[name, duration, samples, keyframes]`, `keyframes` a built-in's rows as an animation's, `null` for `:explode` and for a host's.

A reader that runs spans saves the context at `motion` and restores it at `motionEnd`, so the element's own transform and what its animation adds stay the element's (#677). A span does not change what is drawn: a reader that ignores it draws the element at its target, which is what the `:js` serialization does (3.4). `Visualize.IR.Motion` holds the conversions both canvas encoders share. No span is written for an element without the attribute, so a chart without motion is the commands it always was.

### 3.4 JavaScript serialization

Each command becomes one statement. `set_*` commands become property assignments (`ctx.fillStyle = 'red';`, `ctx.lineWidth = 2;`, `ctx.globalAlpha = 0.5;`, `ctx.font = '12px serif';`, `ctx.textAlign = 'center';`). `beginPath`, `closePath`, `fill`, `stroke`, `save`, `restore` become the parameterless call. `moveTo`, `lineTo`, `bezierCurveTo`, `quadraticCurveTo`, `arc`, `ellipse`, `rect`, `translate`, `rotate`, `scale`, `transform` become the same-named call with formatted (1.3) arguments separated by `, `; a boolean argument prints as `true`/`false`. `rotate_around` becomes `ctx.translate(cx, cy); ctx.rotate(a); ctx.translate(-cx, -cy);`. `nonScalingLineWidth` becomes `ctx.lineWidth = w / (function(t){return Math.sqrt(Math.abs(t.a*t.d-t.b*t.c));})(ctx.getTransform());`. `hatchPattern` becomes `ctx.fillStyle = (function(){…})();`, a function that draws the tile on a `document.createElement('canvas')` and returns `ctx.createPattern(tile, 'repeat')` with its transform set — `strokeStyle` for a `"stroke"` target (3.3.3, #673). `linearGradient` becomes `ctx.fillStyle = (function(g){g.addColorStop(at, 'color'); …; return g;})(ctx.createLinearGradient(x0, y0, x1, y1));` — `strokeStyle` for a `"stroke"` target, one `addColorStop` per stop — and `radialGradient` the same around `ctx.createRadialGradient(cx, cy, 0, cx, cy, r)` (3.3.3, #652). `{:clip, []}` becomes `ctx.clip();` and `{:clip, ["evenodd"]}` `ctx.clip('evenodd');`. `motion` and `motionEnd` write nothing: a script runs with no library beside it to move the element, so it draws the element's end state (3.3.5). `fillText` becomes `ctx.fillText('text', x, y);` with `\`, `'` and newline escaped in the text. `drawImage` becomes an immediately-invoked function that creates an `Image`, captures `ctx.getTransform()`, and in `onload` saves the context, restores that transform, calls `ctx.drawImage(img, x, y, w, h)` and restores — the load is asynchronous, the draw lands where the statement ran. No command is emitted as a comment (D-37); a command tuple the serializer does not know raises `FunctionClauseError`.

### 3.5 JSON serialization

The output is `[` + objects joined by `,` + `]`, each object exactly `{"cmd":"<name>","args":[<values>]}` with the command atom's name as the string. Values: binaries are quoted with `\`, `"`, newline, carriage return and tab escaped; numbers are formatted per 1.3; `true`/`false` are the JSON literals; a list is a JSON array of its values (a gradient's stops, 3.3.3); other atoms are quoted names; anything else is quoted `to_string/1`. No whitespace is emitted.

### 3.6 Root wrapper

`wrap_root/2` MUST emit, in order: `<canvas id="ID" width="W" height="H"></canvas>\n` — with a `:title`, `<canvas id="ID" width="W" height="H" role="img" aria-label="TITLE" aria-describedby="ID-summary"><p id="ID-summary">DESCRIPTION</p></canvas>\n`, the paragraph and `aria-describedby` only with a `:description`, every text escaped (D-142: the canvas names itself, and its fallback content is its description) — `<script>\n(function() {\n  var canvas = document.getElementById('ID');\n  var ctx = canvas.getContext('2d');\n`, the content, `})();\n</script>\n`.

## 4. Visualize.Backend.CanvasBinary

### 4.1 Functions

| Function | Contract |
|---|---|
| `Visualize.Backend.CanvasBinary.available?/0` | Returns `true` when the `Nx` module is loaded; binary encoding requires it. |
| `Visualize.Backend.CanvasBinary.encode_path/1` | `encode_path(path, [])`. |
| `Visualize.Backend.CanvasBinary.encode_path/2` | Encodes an `IR.Path` to one path record (4.5); returns `{:ok, binary}` or `{:error, :nx_not_available}`. The one option is `precision:`, `:f32` (the default) or `:f64`, which selects the f32 or the f64 path records (4.5). |
| `Visualize.Backend.CanvasBinary.encode_path!/1` | `encode_path!(path, [])`. |
| `Visualize.Backend.CanvasBinary.encode_path!/2` | As `encode_path/2` but returns the binary directly and raises `RuntimeError` when Nx is absent. |
| `Visualize.Backend.CanvasBinary.encode_element/1` | `encode_element(element, [])`. |
| `Visualize.Backend.CanvasBinary.encode_element/2` | Encodes an `IR.Element` (4.4) or a `Visualize.SVG.Element` (4.7) tree to a binary command stream; returns `{:ok, binary}` or `{:error, :nx_not_available}`. Takes `precision:` as `encode_path/2` does; it governs every path record in the stream. |
| `Visualize.Backend.CanvasBinary.encode_element!/1` | `encode_element!(element, [])`. |
| `Visualize.Backend.CanvasBinary.encode_element!/2` | As `encode_element/2` but returns the binary directly and raises `RuntimeError` when Nx is absent. |
| `Visualize.Backend.CanvasBinary.to_base64/1` | Standard Base64 (`Base.encode64/1`, padded) of a binary, for embedding in an HTML attribute or a LiveView event payload. |
| `Visualize.Backend.CanvasBinary.Decoder.decode/1` | The reference decoder (#270): the records of a stream in order — the path records with their commands, `circles`, `rects`, `style` (with `non_scaling: true` when bit 4 is set and `fill_paint:`/`stroke_paint:` with the index when bit 5 or 6 is, §4.3.5), `transform`, the version 2 records `{:version, v}`, `{:paint, index, paint}` and `{:box, {x, y, w, h}}` (§4.3.11–4.3.13), the version 4 records `{:clip, :inside | :outside}` and `{:blend, mode}` (§4.3.18, §4.3.19), `save`/`restore`/`fill`/`stroke`, and the `0x60` records of §5 as `{:incremental, mode, dx, dy, viewport, regions}` and `{:full_redraw, viewport, records}` with the viewport as `{x, y, w, h}` — written against the record layouts this section states, not against the encoder, so `decode(encode(x))` is a round trip (D-36). Raises on an unknown opcode or a truncated record. It is the executing guard a consumer runs over its own streams under test; the JavaScript executor of spec/10 §12 reads the same layouts. |
| `Visualize.Backend.CanvasBinary.Decoder.decode_path/1` | The one path record of a stream as a `Visualize.IR.Path`. |

### 4.2 Stream model and opcodes

A stream is a concatenation of records. Every record begins with a one-byte opcode; the opcode fixes the record's layout, so the stream is self-delimiting and carries no length prefix or header. All multi-byte integers are little-endian unsigned 32-bit (`u32`); all coordinates are little-endian IEEE-754 binary64 (`f64`) except where a record states `f32`, which is little-endian binary32. The two path records exist in an f64 and an f32 form under different opcodes — `path`/`path32`, `path_cubic`/`path_cubic32` — with the same layout apart from the width of every coordinate (D-73); 4.5 says which the encoder writes. Color components are single unsigned bytes.

Opcodes (`Visualize.Backend.CanvasBinary.Opcodes`, internal macros so they can appear in binary patterns):

| Name | Byte | Record |
|---|---|---|
| `path` | `0x01` | Polyline point list (4.3.1) |
| `path_cubic` | `0x02` | Full path command stream (4.3.2) |
| `circles` | `0x03` | Circle list (4.3.3) |
| `rects` | `0x04` | Rectangle list (4.3.4) |
| `path32` | `0x05` | Polyline point list, f32 coordinates (4.3.8) |
| `path_cubic32` | `0x06` | Full path command stream, f32 arguments (4.3.9) |
| `cubic_run` | `0x07` | A start point and a run of cubic curves, f32, no sub-opcodes (4.3.10) |
| `style` | `0x10` | Fill/stroke/width/opacity (4.3.5) |
| `transform` | `0x20` | Coordinate transform (4.3.6) |
| `save` | `0x30` | `ctx.save()` |
| `restore` | `0x31` | `ctx.restore()` |
| `fill` | `0x40` | `ctx.fill()` on the current path |
| `stroke` | `0x41` | `ctx.stroke()` on the current path |
| `version` | `0x00` | The stream's version, version 2 and later (4.3.11) |
| `paint` | `0x50` | A paint defined for the stream, version 2 (4.3.12) |
| `box` | `0x51` | The box the next draw's paint is built over, version 2 (4.3.13) |
| `effect` | `0x52` | The shadow or the blur the following draws are made with, version 2 (4.3.14) |
| `motion` | `0x53` | A motion span begins: an element's identity and its transition, version 2 (4.3.15) |
| `motion_end` | `0x54` | The motion span ends, version 2 (4.3.16) |
| `paint_state` | `0x55` | A paint's own alpha, the cap, the join and the dash, version 3 (4.3.17) |
| `clip` | `0x56` | The current path becomes the clip, kept inside or outside it, version 4 (4.3.18) |
| `blend` | `0x57` | The compositing operation the following draws are made with, version 4 (4.3.19) |

**Stream versions** (#652, D-175). The records above `version` are **version 1**, the stream as it was before paints. **Version 2** adds `version`, `paint`, `box`, `effect` (#674), `motion` and `motion_end` (#653), and bits 5 and 6 of the style record. A stream that uses none of them is a version 1 stream, byte for byte the same as before, and the encoder writes it so: only a stream that draws a paint, an effect or a motion span carries the version 2 records, and it begins with the record `0x00 0x02`. So a version 1 decoder — a page still running an older hook — reads every stream it could read before, and on a version 2 stream it throws at the first byte, an unknown opcode `0x00`, rather than drawing a gradient as black; a version 2 decoder reads both. A stream is still a concatenation of records with no header: two streams concatenated, as `render_scene/2` does (3.2), are one stream, each part declaring its own version and defining its own paints before it uses them. A `version` record may stand anywhere and states the version of the records after it; a decoder MUST refuse a version it does not know.

**Version 3** (#675, D-180) adds `paint_state`, under the same rule: only a stream whose styles set a paint's opacity, a cap, a join or a dash carries it and begins `0x00 0x03`, every other stream is what it was, and a version 2 decoder throws at the version record rather than drawing the paint opaque. A version 3 stream may hold every version 2 record.

**Version 4** (#788, D-208) adds `clip` and `blend`, under the same rule: only a stream whose tree clips an element or whose styles set a blend other than `:normal` carries them and begins `0x00 0x04`, every other stream is what it was, and a version 3 decoder throws at the version record rather than drawing an inside stroke at twice its width or an overlap unblended. A version 4 stream may hold every version 3 record.

No other opcode is defined by this module. `0x60` is defined by `Visualize.Backend.CanvasIncremental` (section 5) and encloses streams of these records. The module's doc comment carries the same table, and `test/visualize/backend/canvas_binary_test.exs` holds it to `Opcodes`. `test/support/canvas_binary_decoder.ex` is a decoder written from this section, not from the encoder, and the same test file proves `decode(encode(path))` over random paths (D-36).

### 4.3 Record layouts

#### 4.3.1 `path` (0x01)

```
0x01  count:u32  x0:f64 y0:f64  x1:f64 y1:f64 … x(count-1):f64 y(count-1):f64
```

`count` points, 16 bytes each (`8 + 4 + 16·count` bytes total). The decoder MUST `moveTo` the first point and `lineTo` each subsequent one; the path is left open. Coordinates are produced by `Nx.tensor(type: :f64) |> Nx.to_binary/1` and are therefore native-endian on the encoding host; on the little-endian hosts this library targets that is little-endian.

#### 4.3.2 `path_cubic` (0x02)

```
0x02  count:u32  command₀ command₁ … command(count-1)
```

`count` MUST equal the number of command records that follow. Each command record is a one-byte sub-opcode followed by its arguments (f64 unless stated):

| Sub-opcode | IR command | Arguments | Bytes |
|---|---|---|---|
| `0x01` | `{:M, x, y}` | `x y` | 17 |
| `0x02` | `{:L, x, y}` | `x y` | 17 |
| `0x03` | `{:C, x1, y1, x2, y2, x, y}` | `x1 y1 x2 y2 x y` | 49 |
| `0x04` | `{:Q, x1, y1, x, y}` | `x1 y1 x y` | 33 |
| `0x05` | `:Z` | none | 1 |
| `0x06` | `{:A, rx, ry, rot, large, sweep, x, y}` | `rx ry rot large:u32 sweep:u32 x y` | 49 |
| `0x07` | `{:a, rx, ry, rot, large, sweep, dx, dy}` | `rx ry rot large:u32 sweep:u32 dx dy` | 49 |
| `0x08` | `{:H, x}` | `x` | 9 |
| `0x09` | `{:V, y}` | `y` | 9 |
| `0x0A` | `{:h, dx}` | `dx` | 9 |
| `0x0B` | `{:v, dy}` | `dy` | 9 |
| `0x0C` | `{:m, dx, dy}` | `dx dy` | 17 |
| `0x0D` | `{:l, dx, dy}` | `dx dy` | 17 |
| `0x0E` | `{:c, dx1, dy1, dx2, dy2, dx, dy}` | six f64 | 49 |
| `0x0F` | `{:q, dx1, dy1, dx, dy}` | four f64 | 33 |

Relative commands (`0x07`, `0x0A`–`0x0F`) are stored with their relative arguments; the decoder MUST track the current point. The smooth commands `S`, `s`, `T`, `t` have no sub-opcode: the encoder rewrites them to `C`/`c`/`Q`/`q` with `Visualize.IR.Path.expand_smooth/1` (spec/02 §2.2) before encoding, so `count` always equals the records written; a command without a sub-opcode cannot reach the record writer and would fail to match rather than encode to nothing (D-36).

#### 4.3.3 `circles` (0x03)

```
0x03  count:u32  cx:f64 cy:f64 r:f64  … (count times)
```

The encoders always write `count = 1`; the decoder MUST accept any count, beginning one path that holds every circle as a full `arc(cx, cy, r, 0, 2π)` (each preceded by a `moveTo` to its rightmost point), so the `fill`/`stroke` records that follow draw them all.

#### 4.3.4 `rects` (0x04)

```
0x04  count:u32  x:f64 y:f64 w:f64 h:f64  … (count times)
```

The encoders always write `count = 1`; the decoder begins one path holding every rectangle, as for circles.

#### 4.3.5 `style` (0x10)

```
0x10  flags:u8  [fill r:u8 g:u8 b:u8 a:u8]  [stroke r g b a]  [stroke_width:f32]  [opacity:f32]
```

`flags` bits, and the optional fields that follow in exactly this order when the bit is set:

| Bit | Mask | Field | Bytes |
|---|---|---|---|
| 0 | `0x01` | fill color RGBA | 4 |
| 1 | `0x02` | stroke color RGBA | 4 |
| 2 | `0x04` | stroke width, little-endian f32 | 4 |
| 3 | `0x08` | global alpha 0–1, little-endian f32 | 4 |
| 4 | `0x10` | the stroke width does not scale: set only with bit 2 (spec/14 §3.9, #651); the reader divides the width by `√|a·d − b·c|` of the transform current when it reads the record | 0 |
| 5 | `0x20` | version 2: the fill is the paint of this index, `index:u16` (4.3.12); never set with bit 0 | 2 |
| 6 | `0x40` | version 2: the stroke is the paint of this index, `index:u16`; never set with bit 1 | 2 |

The two paint fields follow the four of version 1, so a version 1 record reads exactly as it did. A reader keeps the fill and the stroke as state that `save` and `restore` scope as they scope the context: a fill color (bit 0) replaces a fill paint and a fill paint (bit 5) a fill color, and likewise for the stroke. A `fill` or `stroke` record drawn while a paint is the fill or the stroke draws that paint over the box of the last `box` record (4.3.13), as 3.3.3 draws it.

Alpha `a` is 0–255. The IR encoder emits a style record whenever `element.style` is non-empty, even if it sets no flags; the SVG encoder (4.7) omits the record when `flags` would be `0`. The SVG encoder sets bit 3 only in a group's record, for the group's opacity (4.7, D-192).

#### 4.3.6 `transform` (0x20)

```
0x20  kind:u8  payload
```

| `kind` | Payload | Meaning |
|---|---|---|
| `0x01` | `tx:f64 ty:f64` | `translate(tx, ty)` |
| `0x03` | `tx:f64 ty:f64 sx:f64 sy:f64` | `translate(tx, ty)` then `scale(sx, sy)` |
| `0xFF` | `a b c d e f` (f64) | `transform(a, b, c, d, e, f)` |

The IR encoder chooses `0x01` for a transform whose operation list is exactly `[{:translate, x, y}]`, `0x03` for exactly `[{:translate, x, y}, {:scale, sx, sy}]`, and `0xFF` otherwise, folding the operations into one matrix with `Visualize.IR.Transform.to_matrix/1` (spec/02 §2.3): SVG composition (`M = Op₁ · Op₂ · … · Opₙ`, the last operation applying to the point first) over all seven IR operations, `rotate(a, cx, cy)` included (D-36). The decoder MUST apply `0xFF` with `ctx.transform(a, b, c, d, e, f)`, composing onto the current transform, not `setTransform`.

#### 4.3.7 `save`, `restore`, `fill`, `stroke`

Single-byte records with no payload.

#### 4.3.8 `path32` (0x05)

```
0x05  count:u32  x0:f32 y0:f32  x1:f32 y1:f32 … x(count-1):f32 y(count-1):f32
```

The `path` record of 4.3.1 with every coordinate a little-endian f32: `count` points, 8 bytes each (`1 + 4 + 8·count` bytes total). The decoder draws it exactly as 4.3.1 — `moveTo` the first point, `lineTo` each subsequent one, the path left open. Each coordinate is the nearest f32 to the encoder's value (`<<v::little-float-32>>`, round to nearest even), so the record is lossy within the bound of 4.5; there is no Nx tensor in the f32 path, the coordinates are written by the binary constructor.

#### 4.3.9 `path_cubic32` (0x06)

```
0x06  count:u32  command₀ command₁ … command(count-1)
```

The `path_cubic` record of 4.3.2 with every f64 argument a little-endian f32: the same sub-opcodes, the same commands, the same argument order, `large` and `sweep` still `u32`, and the same rules — `count` MUST equal the records that follow, the smooth commands are expanded first, relative commands carry relative arguments. Only the sizes change:

| Sub-opcode | IR command | Bytes |
|---|---|---|
| `0x01`, `0x02`, `0x0C`, `0x0D` | `M`, `L`, `m`, `l` | 9 |
| `0x03`, `0x0E` | `C`, `c` | 25 |
| `0x04`, `0x0F` | `Q`, `q` | 17 |
| `0x05` | `Z` | 1 |
| `0x06`, `0x07` | `A`, `a` (`rx ry rot` f32, `large sweep` u32, `x y` f32) | 29 |
| `0x08`–`0x0B` | `H`, `V`, `h`, `v` | 5 |

#### 4.3.10 `cubic_run` (0x07)

```
0x07  count:u32  x0:f32 y0:f32  x1:f32 y1:f32 x2:f32 y2:f32 x:f32 y:f32  … (count times)
```

The path `M x0,y0` followed by `count` absolute cubic curves `C x1,y1 x2,y2 x,y`, every coordinate a little-endian f32 and no sub-opcode per curve: `1 + 4 + 8 + 24·count` bytes, against `5 + 9 + 25·count` for the same path as `path_cubic32` and `5 + 9 + 49·count` as `path_cubic`. It is the shape the cubic curve generators of spec/04 §5 emit — `Visualize.Shape.Curve.monotone_x/1`, `monotone_y/1`, `cardinal/2`, `catmull_rom/2` and `natural/1` produce one `M` then `C`s and nothing else — so a curved line mark is one run. `basis/1` is the one cubic generator that is not: it opens with an `L` to its first control point and closes with an `L` to the last point, so a basis curve stays a command stream (4.3.9), one byte per curve larger than a run. The decoder MUST begin a path, `moveTo` the start point and `bezierCurveTo` each curve in order, leaving the path open; it MUST accept any `count`, though the encoder writes the record only for one curve or more (4.5). There is no f64 form: under `precision: :f64` the same path is a `path_cubic` record (D-74).

#### 4.3.11 `version` (0x00)

```
0x00  version:u8
```

The version of the records that follow (4.2): `4` is the one the encoder writes first in a stream that clips an element or blends one (4.3.18, 4.3.19), else `3` in one whose styles set a paint's state (4.3.17), else `2` in one that draws a paint, an effect or a motion span. A decoder MUST raise on a version it does not know; the reference decoder knows `1`, `2`, `3` and `4`.

#### 4.3.12 `paint` (0x50)

```
0x50  index:u16  kind:u8  geometry  count:u8  stop₀ … stop(count-1)
stop = at:f32 r:u8 g:u8 b:u8 a:u8
```

Defines the paint `index` for the rest of the stream, replacing any earlier paint of that index. The geometry is in box units (spec/02 §2.1), every value a little-endian f32:

| `kind` | Paint | Geometry | Bytes |
|---|---|---|---|
| `0x01` | linear gradient | `x1 y1 x2 y2` | 16 |
| `0x02` | radial gradient, focus at the center | `cx cy r` | 12 |
| `0x03` | hatch (#673) | `pattern:u8 angle spacing width`, then `color` and `background` as RGBA bytes, a background of alpha 0 being none; **no stops follow** | 21 |

A stop is its offset `at` from 0 to 1 and its color as RGBA bytes, the stop's opacity multiplied into the alpha (4.6), in `at` order: `5 + 1 + geometry + 1 + 8·count` bytes in all. A hatch's `pattern` byte is `0x01` lines, `0x02` crosshatch, `0x03` dots, and its record is `4 + 21` bytes; a reader draws it as 3.3.3 does, needing no box. The encoder writes each distinct paint of the tree once, after the `version` record and before every other record, indexed from `0` in the order the tree first uses them (D-175) — so a hundred bars of one gradient carry it once and refer to it by two bytes each — and a paint the stream draws is always defined before the record that refers to it.

#### 4.3.13 `box` (0x51)

```
0x51  x:f32  y:f32  w:f32  h:f32
```

The bounding box, in the element's user units, of the element whose draw records follow: `Visualize.IR.Paint.bounds/1` of the element, its tight box (spec/02 §2.1). A reader builds the fill's or the stroke's paint over it when a `fill` or `stroke` record draws one (3.3.3: a linear gradient mapped into user units, a radial fill under the box transform, a radial stroke as the circle of the same area, nothing on a box without area), saving and restoring the context around the draw so the gradient is never state. The encoder writes it after the geometry record and before the draw records of every element whose effective fill or stroke is a paint, and nowhere else.

#### 4.3.14 `effect` (0x52)

```
0x52  kind:u8  radius:f32  [dx:f32  dy:f32  r:u8 g:u8 b:u8 a:u8]
```

The effect of a style (#674): kind `0x01` a shadow — its blur radius, its offset and its color, the bracketed fields, 17 bytes after the opcode — or `0x02` a blur, its radius alone, 5 bytes. A reader sets the context's `shadowColor`, `shadowBlur`, `shadowOffsetX` and `shadowOffsetY`, or its `filter` to `blur(<radius>px)`, as 3.3.3 does; it is context state, so `save` and `restore` scope it. The encoder writes it after the style record of a style whose `:effect` is `:shadow` or `:blur`, the offset and the color the defaults of 3.3.3 when absent. The SVG-element encoder writes it for a `filter` that names a filter the library writes (4.7, D-211). Before #674 the binary stream had no record for an effect and dropped it, so a shadow drew on SVG and on the `:json` canvas and not on the binary one.

#### 4.3.15 `motion` (0x53)

```
0x53  length:u16  json:u8[length]
```

A motion span begins (3.3.5, #653): `json` is the UTF-8 text of the JSON array the `:json` output writes as the `motion` command's arguments, `[id, box, transitions]`, so the two formats carry one contract and a reader decodes one shape. The encoder writes it before the records of an element that carries a `"data-vis-id"`, and `motion_end` after them. A reader that moves nothing skips `length` bytes and draws on: the span changes no record inside it.

#### 4.3.16 `motion_end` (0x54)

```
0x54
```

The span the last `motion` record began ends. One byte.

#### 4.3.17 `paint_state` (0x55)

```
0x55  flags:u8  [fill_alpha:f32]  [stroke_alpha:f32]  [cap:u8]  [join:u8]  [count:u8 length:f32 × count]
```

Version 3 (#675, D-180). What a fill or a stroke paints with that the style record has no field for, each field present when its bit is set, in this order: `0x01` the fill's own opacity (`fill_opacity`), `0x02` the stroke's (`stroke_opacity`), `0x04` the cap (`0` butt, `1` round, `2` square), `0x08` the join (`0` miter, `1` round, `2` bevel), `0x10` the dash, its lengths as `setLineDash` takes them (3.3.3), at most 255. The IR encoder writes it directly after an element's or a group's style record (and its `effect` record) when the style sets any of the five. A reader sets the cap, the join and the dash on the context, and keeps the two alphas as state that `save` and `restore` scope as they scope the paints (4.3.5), each `1` at the start of a stream: a `fill` drawn while the fill's alpha is not `1` is drawn at `globalAlpha` times it, and the context's alpha is set back after the draw; likewise a `stroke`. The SVG encoder (4.7) writes it with the cap, the join and the dash alone (bits `0x04`, `0x08`, `0x10`; #693): it folds the two opacities into its colors' alpha.

#### 4.3.18 `clip` (0x56)

```
0x56  keep:u8
```

Version 4 (#788, D-208). The current path — the geometry record just before it, which began it — becomes the context's clip: `keep` `0x01` keeps what is inside it, `ctx.clip()`; `0x02` keeps what is outside it, the reader adding the rectangle `-100000, -100000, 200000, 200000` to the path and clipping with `ctx.clip('evenodd')`, so the clip is everything but the shape, as the `:json` commands' outside clip is (3.3.1). It is context state, so `save` and `restore` scope it. Two bytes. Any other `keep` is refused.

The encoder writes it for an element with a `clip` (spec/02 §2.1), in the order the `:json` commands give it (3.3.1): `save`, the element's own transform record, when it has one, the clip shape's geometry — the record that shape is drawn with (4.4, 4.5), its style and its draw records left out; it has no transform (spec/02 §2.1) — the `clip` record, then the element's own records without its transform, then `restore`. So the clip is in the element's user space, as SVG's is (D-211), it holds the element's style records and its draws, and nothing after the `restore` is clipped. The shape is a `:path`, `:rect`, `:circle`, `:ellipse` or `:polygon`, as spec/02 §2.1 allows; the last two are the path they are (4.4).

#### 4.3.19 `blend` (0x57)

```
0x57  mode:u8
```

Version 4 (#788, D-208). The `globalCompositeOperation` the following draws are made with, the CSS `mix-blend-mode` word SVG writes for the style's `:blend` (2.5) and the `:json` commands set (3.3.3): `0x01` `multiply`, `0x02` `screen`, `0x03` `overlay`, `0x04` `darken`, `0x05` `lighten`, `0x06` `color-dodge`, `0x07` `color-burn`, `0x08` `hard-light`, `0x09` `soft-light`, `0x0A` `difference`, `0x0B` `exclusion`, `0x0C` `hue`, `0x0D` `saturation`, `0x0E` `color`, `0x0F` `luminosity` — an IR blend atom spelled with an underscore, `:color_dodge`, being the word with a hyphen. It is context state, so `save` and `restore` scope it, and a reader refuses any other byte. The encoder writes it after the style record (and its `effect` and `paint_state` records) of a style whose `:blend` is one of those words; `:normal` and a word outside them write nothing, as `:normal` writes nothing on SVG and on the `:json` commands. The SVG-element encoder writes it for an element's `mix-blend-mode` (4.7, D-211). Two bytes.

### 4.4 Encoding IR elements

`encode_element/1` on an `IR.Element` writes, per type:

| IR type | Records |
|---|---|
| `:path` | transform (if non-nil with ≥1 operation), style (if the style map is non-empty), the path record (4.5), then `fill` if the *effective* style's `fill` is set and not `:none`, then `stroke` if its `stroke` is set and not `:none` — the effective style being the element's own over the styles of the groups above it, nearest last (#231); with a transform or a style record, all of it between `save` and `restore` (below) |
| `:circle` | transform, style, `circles` with one entry from `attrs.cx/cy/r`, draw records as above |
| `:rect` | transform, style, `rects` with one entry from `attrs.x/y/width/height`, draw records as above |
| `:group` | `save`, transform (if any), style (if the style map is non-empty — it sets the state the children draw in, scoped by the `save`/`restore`), each child's records, `restore` (#231) |
| `:root` | each child's records, nothing else |
| any element with a `clip` | `save`, its transform (if any), the clip shape's geometry record, `clip` (4.3.18), the element's own records as above without the transform, `restore` |
| any other type | nothing (zero bytes) |

**A leaf's records are its own** (#679, D-179), as a leaf's commands are (3.3.1), and as the SVG-element encoder's are (4.7, D-193): a `:path`, `:circle` or `:rect` — and a type encoded as the path it is — that writes a `transform` or a `style` record is written between a `save` and a `restore`, so neither the transform nor the state the style record sets (the colors, the width, the alpha, a paint, an effect) reaches the element after it; one that writes neither has no `save`. A reader needs nothing new: it scopes the fill and stroke paints with `save` and `restore` already (4.3.5).

**A paint's state** (#675, D-180). When any style in the tree sets `:fill_opacity`, `:stroke_opacity`, `:stroke_linecap`, `:stroke_linejoin` or a readable `:stroke_dasharray`, the stream begins with `version` 3 and each such style record is followed by its `paint_state` record (4.3.17), so a translucent paint draws at the element's alpha times its own on a binary canvas as on SVG.

**Paints** (#652, D-175). When any `:fill` or `:stroke` in the tree's styles is a `Visualize.IR.Paint`, or any `:effect` a shadow or a blur (#674), the stream begins with `version` 2 and one `paint` record per distinct paint (4.3.11, 4.3.12); a style that holds a paint sets bit 5 or 6 with the paint's index in place of the RGBA field; and every element whose effective fill or stroke is a paint gets a `box` record between its geometry and its draw records (4.3.13). An element drawn as the path it is — a `:line`, `:ellipse`, `:polyline`, `:polygon` — takes the box of the shape it was.

**Clips and blends** (#788, D-208). When any element in the tree has a `clip`, or any style a `:blend` that writes a `blend` record (4.3.19), the stream begins with `version` 4. A clipped element is written inside its clip (4.3.18), so an inside or an outside stroke (spec/14 §5.6) — the doubled width `Visualize.Chart.Mark.Strokes` draws clipped to the shape or away from it — draws on the binary canvas at its width, on its side of the edge, as on SVG and on the `:json` canvas; and a style's blend is the `blend` record after its style record, so a multiplied element multiplies there too. Before #788 the binary stream had a record for neither: an element was encoded unclipped, an inside or outside stroke drew at twice its width centered on the edge, and a blend was dropped. Where the element's own fill and stroke overlap, SVG blends the element as a whole and the canvas blends the fill and then the stroke, each in turn, as it composites a paint's opacity (3.3.3, D-180) — the same picture for a fill or a stroke alone, and wherever the two do not overlap. An `:effect` is the `effect` record after the style record (4.3.14, #674). The geometric types that are not paths are encoded **as the path they are** (#269): a `:line` as `M x1 y1 L x2 y2`; a `:polyline` as a move to its first point and a line to each of the rest; a `:polygon` the same, closed; an `:ellipse` as four cubic Bézier quarter-arcs about its center with the control distance κ = 0.5522847 of each radius, closed — each with the element's style and transform as a `:path` gets them, through the same record and form selection (§4.5), so a `:line` is byte for byte the two-point `Visualize.IR.Path` with the same style. Elements of type `:text`, `:title`, `:desc`, `:style`, `:image`, `:defs`, `:clip_path`, gradients, `:pattern`, filters and `:stop` are dropped from the binary stream. A basemap's tiles (spec/14 §5.2, #475) are `:image` elements and are dropped with them, and the stream has no image record (D-120): a compiled chart draws the tiles as SVG in a backdrop the page stacks beneath the canvas (spec/14 §12.3, §12.4, #476), so a canvas track sits over them with nothing in the stream to fetch, order or wait for. Text has no binary representation by design; before #269 the four geometric types above were dropped silently as well, so an axis's tick lines drew nothing on a binary canvas.

### 4.5 Path form selection

`encode_path/2` and the `:path` branch of `encode_element/2` choose the path record from the command list, with the smooth curves already expanded, and from the `precision:` option (D-36, D-73):

- One `:M` followed by zero or more `:L` commands — a single open polyline, the case the point-list records represent without loss of shape — is `path32` (0x05) under `precision: :f32`, the default, and `path` (0x01) under `:f64`.
- One `:M` followed by one or more `:C` commands — a single open cubic run, what the curve generators emit — is `cubic_run` (0x07) under `:f32` (4.3.10); under `:f64` it is `path_cubic` (0x02), the run having no f64 form (D-74).
- Every other command list, the empty list included, is `path_cubic32` (0x06) under `:f32` and `path_cubic` (0x02) under `:f64`.

The three tests are on the command list after `Visualize.IR.Path.expand_smooth/1`, so a run written with `S` after its first `C` is a run too; a `Z`, a second subpath, a relative command or a mixed run of `L` and `C` falls to the command stream, which holds it exactly.

The default is f32 because the stream carries canvas coordinates, which are pixel positions: an f32 stores a value below 2¹⁴ = 16,384 in magnitude to within 2⁻¹¹ (≈ 0.0005 px) and one below 2¹¹ = 2,048 to within 2⁻¹³ (≈ 0.0001 px) — the rounding error is at most half an ULP, and the ULP of a value in `[2ⁿ, 2ⁿ⁺¹)` is 2ⁿ⁻²³ — which is far under the half pixel a rasterizer resolves, while every f64 path record is twice the size for precision the canvas cannot show. That bound is the contract of the f32 records: `test/visualize/backend/canvas_binary_test.exs` holds it over random coordinates, and holds `decode(encode(path))` to the path with every argument rounded to its nearest f32. `precision: :f64` writes the records of 4.3.1 and 4.3.2 — byte for byte the stream before D-73 — for a consumer whose values are not pixels or exceed 2²⁴, where an f32 no longer holds every integer. The option governs the path records alone: `circles`, `rects` and `transform` keep their f64 layouts, and `Visualize.Shape.LineNx.to_binary/6,7` (spec/04 §10.2) writes the f64 `path` record as it always has.

### 4.6 Color parsing (IR encoder)

A binary style color is parsed by `Visualize.Color.parse/1` (spec/08) and written as `Visualize.Color.to_rgba/1` gives it, the opacity scaled to 0–255 and rounded: every syntax that function accepts — `#rgb`, `#rgba`, `#rrggbb`, `#rrggbbaa`, `rgb()`, `rgba()` with any decimal alpha, `hsl()`, `hsla()` and the CSS color names — resolves; a binary it cannot parse and any non-binary value (`:current_color` included) yields opaque black `{0, 0, 0, 255}` (D-36). A `Visualize.IR.Paint` is not a color: it is written as a reference to its `paint` record (4.4), and each of its stops is parsed by this rule with the stop's opacity multiplied into the alpha.

### 4.7 Encoding SVG elements (`Visualize.Backend.CanvasBinary.SVG`)

`encode_element/1` on a `Visualize.SVG.Element` reads presentation attributes from `attrs` instead of an IR style map. Tags handled:

| Tag | Records |
|---|---|
| `:svg` | as `:g` without the transform: its group state (below), when it has any, in `save` … `restore` around its children; otherwise children only |
| `:g` | when `attrs.transform` is present or it sets a presentation attribute: `save`, the parsed transform (below), its group state (below), children, `restore`; otherwise children only |
| `:rect` | its own transform (below) when `attrs.transform` reads as one, style (if any flag set), `rects` from `x y width height` (default `0`, numbers or numeric strings), draw records; with a transform, a style or a `paint_state` record, all of it between `save` and `restore` (below) |
| `:circle` | its own transform, style, `circles` from `cx cy r`, draw records; scoped as `:rect` |
| `:path` | its own transform, style, the command-stream record — `path_cubic32` under `precision: :f32`, `path_cubic` under `:f64` (4.5) — from the parsed `d` string, draw records, scoped as `:rect`; a `d` that parses to no commands produces zero bytes |
| `:line` | its own transform, style, the command-stream record of `[{:M, x1, y1}, {:L, x2, y2}]`, then a `stroke` where its effective stroke is present, and no draw record where it is not; never a `fill` (#757, D-122); scoped as `:rect` |
| `:ellipse` | its own transform, style, the command-stream record of the four cubic quarter-arcs about `cx cy` with radii `rx ry` that the IR encoder writes for an `:ellipse` (4.4), draw records; scoped as `:rect`; a radius that is not positive produces zero bytes, as SVG renders nothing |
| `:polygon`, `:polyline` | its own transform, style, the command-stream record of a move to the first point and a line to each of the rest, a polygon's closed, draw records; scoped as `:rect`; `points` a string of numbers separated by commas or whitespace, taken in pairs (an odd last number dropped, a stray character ending the list, as SVG renders up to it), or a list of `{x, y}`; a list without one whole pair produces zero bytes |
| `:text` | nothing — text is not representable |
| any other tag | nothing |

Style attributes read: `fill`, `stroke`, `stroke_width` or `"stroke-width"`, `stroke_linecap` or `"stroke-linecap"`, `stroke_linejoin` or `"stroke-linejoin"`, `stroke_dasharray` or `"stroke-dasharray"`, `fill_opacity` or `"fill-opacity"` (fill alpha, default `1.0`), `stroke_opacity` or `"stroke-opacity"` (stroke alpha, default `1.0`), and `opacity` (the element's, default `1.0`). A color is "present" unless it is `nil`, `:none` or `"none"`. Draw records: `fill` if fill is present (never on a `:line`, which has no area), `stroke` if stroke is present, and nothing if neither is — a `<line>` with no stroke, its own or inherited, draws nothing, as in SVG, where a line's fill paints nothing and its stroke's initial value is `none` (#757): a missing fill is not filled, as on every canvas (3.3.3, D-122), where SVG's initial value would paint it black — a producer that must draw the same on both says `:none` or a color. A color — a binary, or an atom taken by its name — is parsed by `Visualize.Color.parse/1` as in 4.6, so every hex, `rgb()`, `hsl()` and named form resolves and an unparseable value is black; `"none"` is transparent black. A paint's alpha byte is the product of its alphas, as SVG multiplies them (#742): `trunc(c · p · o · 255)`, `c` the color syntax's own alpha (`1` but for `rgba()`, `hsla()`, `#rgba`, `#rrggbbaa`), `p` the paint's opacity (`fill-opacity` for the fill, `stroke-opacity` for the stroke) and `o` the element's `opacity`, so an element's `opacity` reaches its fill and its stroke alike and a `fill-opacity` beside it is multiplied, not replaced. SVG composites an element at its `opacity` as a whole; the canvas draws the fill and then the stroke each at the product, so where the stroke's inner half overlaps the fill the fill shows through it here, as it does on the IR canvases (3.3.3, D-180) — exact for a fill or a stroke alone and for a stroke that does not overlap its fill.

**A stroke's dash, cap and join** (#693). An element whose attributes set a cap (`butt`, `round`, `square`), a join (`miter`, `round`, `bevel`) — an atom or its name — or a dash the canvas reads (`Visualize.Backend.Canvas.dash/1`: a list of numbers, or a string of them separated by commas or spaces) writes, after its style record, a `paint_state` record (4.3.17) carrying those of the three it sets, and its records are drawn inside `save` … `restore`, so the dash, the cap and the join are its own and outlive it on no later element. A tree any of whose elements writes one is a version 3 stream, beginning `0x00 0x03` (4.2, D-180); every other tree's stream is what it was, byte for byte. A value outside those words, and a dash that does not read, set nothing, as on the IR encoder. A group's dash, cap and join are read as its other presentation attributes are (below).

**A group's presentation attributes are its children's** (#734, D-192). SVG's children inherit `fill`, `fill-opacity`, `stroke`, `stroke-opacity`, `stroke-width`, `stroke-linecap`, `stroke-linejoin` and `stroke-dasharray` from the `:g` (or the root `:svg`) that holds them, the nearest one's value for each, unless they set their own; each is read under its underscore name or its hyphenated one. A group that sets any of them, or a transform, writes inside `save` … `restore`, after its transform, its **group state**: a style record (4.3.5) with the fill where it sets `fill` or `fill-opacity`, the stroke where it sets `stroke` or `stroke-opacity` — each color the *effective* one, the group's own over what the groups above it pass, at the effective opacity, so a `fill-opacity` set under an inherited `fill` takes it — and the width where it sets one, then the `effect` record of its own filter, the `paint_state` record of its own cap, join and dash, and the `blend` record of its own blend (below, D-211). Its children draw in that state, and it outlives the group on nothing. **A drawing element's records are its own** (#744, D-193), as the IR encoder's leaves are (4.4, D-179): one that writes a transform record, a style record, an `effect`, a `paint_state` or a `blend` record (D-211) writes all its records inside `save` … `restore`, its transform first, wherever it stands — at the root, under a group that sets nothing, or under a group's state — so its transform, its colors, its width, its dash, its cap and its join are its own (#746), and a later sibling draws in the state of the groups above it, not its predecessor's (#742 scoped only the leaves under a group's fill, stroke or width state). One that writes neither has no pair, and costs nothing. A drawing element's records are as above, with two readings of the effective attributes, its own over the groups': its **draw records** are its effective fill's and stroke's (a child that sets no fill under a group's fill fills; one that sets `fill: none` does not, and strokes in the group's stroke), and its **style record** carries, for each of the fill and the stroke its own attributes touch, the effective color at the effective opacity (a child's own fill under a group's `fill-opacity` is drawn at it). A tree with no group that sets one writes no group state.

**A group's opacity** is not inherited in SVG: it composites the group as a whole. Here it is the group's children's global alpha, bit 3 of its style record, the opacities of the groups above it multiplied in, so a nested group's is the product (`save` … `restore` scopes it as the context's). Where the group's children do not overlap the two are the same picture; where they overlap, SVG composites them once and the canvas each in turn, the overlap more opaque here — the binary format has no offscreen group to composite (D-192). A drawing element's own `opacity` is folded into its paints' alphas, as above, so under a translucent group it composes with the group's by multiplication.

**The `transform` attribute is read as SVG reads it** (#746), on a `:g` and on a drawing element alike (a root's `viewBox` places it, so the root's is not read): a list of `matrix(a b c d e f)`, `translate(tx [ty])` (`ty` `0` when missing), `scale(sx [sy])` (`sy` = `sx` when missing), `rotate(a [cx cy])`, `skewX(a)` and `skewY(a)`, angles in degrees, each number with an optional sign, decimal point and exponent, numbers separated by commas or whitespace, operations by whitespace or a comma, applied left to right as SVG composes them. It becomes the `Visualize.IR.Transform` of those operations and is written as the IR encoder writes one (4.3.6): `0x01` for exactly one `translate`, `0x03` for a `translate` then a `scale`, `0xFF` with the folded matrix otherwise. A string that does not read as a whole list — an unknown name, a wrong count of numbers, a stray character — is in error, which SVG ignores, and emits no transform record; an empty one (`""`) likewise.

The `d` string parser accepts the commands `M m L l H h V v C c Q q A a Z z`, numbers with optional sign, decimal point and exponent, comma or whitespace separators, and implicit `L` for bare coordinate pairs following a command. `S s T t` are not recognized and end the parse at that point.

**References** (#825, D-211). A `url(#id)` is resolved against every element of the tree by its `id` attribute, the first one where two share it, as SVG resolves it anywhere in the document; a definition draws nothing where it stands (`defs`, `clipPath`, `mask` and `filter` are among the "other" tags).

- **A clip** (4.3.18). A group or a drawing element whose `clip-path` names a `clipPath` of exactly one shape — a `rect`, `circle`, `ellipse`, `path`, `polygon` or `polyline` with no `transform`, `clip-path` or `mask` of its own — in user space (`clipPathUnits` absent or `userSpaceOnUse`) keeps inside it; one whose `mask` names a `mask` in user space (`maskUnits="userSpaceOnUse"`) whose content is one shape filled opaque white keeps inside that shape, and one whose content is a rectangle filled opaque white then a shape filled opaque black keeps inside the rectangle and outside the shape, the rectangle no clip when it covers the ±100000 square, as the library's own outside mask does (2.3). Its records are, as SVG resolves a clip in the referencing element's user space: `save`, its transform (below), each clip's shape's geometry record — the record the shape is drawn with — and its `clip` record, the clip-path's first, then the element's own records without its transform, then `restore`. A tree any of whose drawn elements is clipped is a version 4 stream.
- **A blend** (4.3.19). `mix-blend-mode`, as an attribute (`mix_blend_mode` or `"mix-blend-mode"`) or as a declaration of the element's inline `style` — the last one, `!important` ignored — is the `blend` record of its word, after the style, `effect` and `paint_state` records, on a group in its group state and on a drawing element among its own records; `normal` and a word outside the fifteen write nothing. A tree any of whose drawn elements blends is a version 4 stream.
- **An effect** (4.3.14). A `filter` that names a `filter` element with no attribute but its `id` holding exactly one primitive the library writes for a style's effect (spec/14 §2.7) is the `effect` record after the style record: an `feDropShadow` of `dx`, `dy`, `stdDeviation`, `flood-color` and `flood-opacity` — SVG's defaults, `2`, `2`, `2`, black and `1`, where absent — is a shadow of radius `stdDeviation`, that offset and `flood-color` at `flood-opacity` (its alpha `round(a · opacity · 255)`, as a stop's, 4.6); an `feGaussianBlur` of `stdDeviation` is a blur of that radius. The radius is the number the IR encoder writes for the effect the filter was declared from, so a filter `Visualize.SVG.Element.from_ir/1` carries is the record the IR element makes. A tree any of whose drawn elements is filtered is a version 2 stream, at least.
- **A stroke that does not scale** (4.3.5). A drawing element whose `vector-effect` (`vector_effect` or `"vector-effect"`) is `non-scaling-stroke` and which strokes writes the stroke's width with bit 4 set: its effective `stroke-width`, its own or the one the groups pass on, `1` when none sets one — after its own transform, so the reader divides it by the scale of the transform current there. `vector-effect` does not inherit and has no effect on a group, so a group's is not read.

**What this encoder does not draw** that SVG does, each a deviation from SVG (#825, D-211), the element drawn as if the attribute were absent:

- a reference to nothing, or to a definition other than those above: a `clipPath` of several shapes or of a shape with its own transform, a `clipPath` in `objectBoundingBox` units, a mask of any other content or in bounding-box units, a filter of several primitives, of another primitive, of a primitive with an attribute the record has no field for (`in`, `result`, a `stdDeviation` of two numbers), or with a region of its own;
- a mask's own region (its `x`, `y`, `width` and `height`), which clips what the mask keeps in SVG: the library's covers the ±100000 square;
- a `fill` or `stroke` that is a `url(#…)` paint: it is not resolved, and draws as an unparseable color does, black (above);
- on a group, a filter and a blend apply to each child in turn, as on the IR encoder (3.3.3), where SVG filters and blends the group as a whole;
- a stroke that does not scale is exact under a translation, a rotation and a uniform scale; under a scale of `sx` by `sy` the reader's width is `w / √(sx·sy)` in user units, so an edge along x is `w·√(sy/sx)` pixels and one along y `w·√(sx/sy)` — 0.71·w and 1.41·w under `scale(2, 1)` — where SVG draws `w` in every direction, and a dash scales with the transform where SVG's does not, as on every canvas (spec/14 §3.9).

### 4.8 Every style key on the binary stream

**The binary canvas draws every style key SVG draws, or this table says why not** (#788, D-208). Each key a style takes (spec/14 §3.1) — every leaf of `Visualize.Chart.Schema.describe(:style)`, a node's keys under its name — has a row: the records it reaches the binary stream as, or **not drawn** and the reason. A key the table marks **not drawn** is a deviation from SVG; every other key draws on the binary canvas as on the `:json` canvas. The third column is the same for the SVG-element encoder (4.7), reading the markup `Visualize.SVG.Element.from_ir/1` makes of the tree (#825, D-211).

| Style key | On the binary stream | On the SVG-element stream (4.7) |
|---|---|---|
| `fill.type`, `fill.color`, `fill.opacity` | the style record's fill (4.3.5), a paint (4.3.12) or none; the fill's alpha (4.3.17) | the style record's fill, its opacity folded into the color's alpha (4.7) |
| `fill.stops.at`, `fill.stops.color`, `fill.stops.opacity`, `fill.angle`, `fill.center`, `fill.radius`, `fill.name` | the `paint` record (4.3.12) | **not drawn**: a `url(#…)` paint is not resolved (4.7) |
| `fill.pattern`, `fill.spacing`, `fill.width`, `fill.background` | the hatch `paint` record (4.3.12) | **not drawn**: a `url(#…)` paint is not resolved (4.7) |
| `stroke.type`, `stroke.color`, `stroke.opacity` | the style record's stroke, a paint or none; the stroke's alpha (4.3.17) | the style record's stroke, its opacity folded into the color's alpha |
| `stroke.stops.at`, `stroke.stops.color`, `stroke.stops.opacity`, `stroke.angle`, `stroke.center`, `stroke.radius`, `stroke.name` | the `paint` record | **not drawn**: a `url(#…)` paint is not resolved (4.7) |
| `stroke.width`, `stroke.non_scaling` | the style record's width, bit 4 (4.3.5) | the style record's width; `vector-effect` its bit 4 (4.7) |
| `stroke.dash`, `stroke.join`, `stroke.cap` | the `paint_state` record (4.3.17) | the `paint_state` record |
| `stroke.placement` | `:inside` and `:outside` a doubled width inside a `clip` (4.3.18), `:double` a second element | the `clip-path` or `mask` each clip is written as, a `clip` record (4.7) |
| `effect.type`, `effect.radius`, `effect.offset`, `effect.color` | the `effect` record (4.3.14) | the `filter` written for the effect, an `effect` record (4.7) |
| `opacity` | the style record's alpha (4.3.5) | folded into the paints' alphas, a group's the style record's alpha (4.7) |
| `blend` | the `blend` record (4.3.19) | the `mix-blend-mode` written for it, a `blend` record (4.7) |
| `marker.shape`, `marker.size`, `curve.type`, `curve.tension`, `curve.alpha` | the geometry the mark generates (spec/14 §5.6) | the geometry the mark generates |
| `transition.*`, `animation.*`, `enter.*`, `exit.*` | the `motion` span (4.3.15) | **not drawn**: the encoder writes no motion span; an element is drawn at its end state |
| `font.family`, `font.size`, `font.weight`, `font.style`, `font.line_height` | **not drawn**: text has no record (4.4); a compiled chart draws its texts as SVG (spec/14 §12.3) | **not drawn**: text has no record |
| `text.anchor`, `text.baseline`, `text.offset`, `text.angle` | **not drawn**: text has no record (4.4) | **not drawn**: text has no record |
| `class` | **not drawn**: a class is a stylesheet's (2.5), and a canvas is given `:literal` styles, already resolved (spec/14 §3.4) | **not drawn**: as on the binary stream |

A `transition.*`, `animation.*`, `enter.*` or `exit.*` row stands for every key of that part, its per-property entries (`transition.fill.duration`, …) among them.

**The recurrence guard.** `test/visualize/backend/style_key_conformance_test.exs` walks the schema's style keys and fails on a key with no row here. For each key it draws one design — a `:rect`, a `:line`, a `:symbol` and a `:text` mark, each styled by the one style the key is set in, and a title label of one line in that style, since a label's placement reads the `text` keys from it (spec/14 §6.3) — with the key and without it. The `:text` mark's last value has two lines, so its line height shows (spec/14 §7.1, D-210). It fails on a key whose sample leaves the SVG unchanged, since such a sample tests nothing. It replays the `:json` commands on `CanvasChart` and the binary stream on `CanvasBinaryChart`, both on the recording stub (spec/12 §6), and fails where, outside the texts, the two hooks' draws are not the same draws in the same state: the transform, the alphas, the fill and the stroke, each paint, the width, the cap, the join, the dash, the shadow, the filter, the compositing operation and the clips. And it fails on a key marked **not drawn** that the binary stream does carry — the stream changes with it — so a deviation that no longer holds is found as well. It holds the SVG-element encoder to the third column the same way, its stream encoded from `from_ir/1` of the tree and replayed on `CanvasBinaryChart`: a key drawn there must change that stream and draw as the `:json` canvas draws, a paint's alpha compared as the product of the color's alpha and the global alpha, since this encoder folds the opacities into the colors (4.7); a key marked **not drawn** there must leave it as it was (#825). A style key added to the schema therefore fails the guard until either the binary canvas draws it or this table says why it does not.

## 5. Visualize.Backend.CanvasIncremental

### 5.1 Functions

| Function | Contract |
|---|---|
| `Visualize.Backend.CanvasIncremental.copy_beneficial?/2` | `copy_beneficial?({dx, dy}, {width, height})` is `true` iff `abs(dx) < 0.5·width` and `abs(dy) < 0.5·height`. |
| `Visualize.Backend.CanvasIncremental.scroll_mode/2` | Classifies a scroll offset against a canvas size as `:none`, `:scroll_x`, `:scroll_y`, `:scroll_xy` or `:full_redraw` (5.2). |
| `Visualize.Backend.CanvasIncremental.exposed_regions/2` | Returns the rectangles `{x, y, w, h}` (floats) newly exposed after shifting the canvas by the offset (5.3). |
| `Visualize.Backend.CanvasIncremental.filter_to_regions/3` | Keeps the data points whose `{x, y}` (from the accessor) lie inside any region, bounds inclusive. |
| `Visualize.Backend.CanvasIncremental.encode_incremental/4` | Encodes an `0x60` incremental update record for the offset, canvas size and `[{bounds, element}]` list (5.5), with `viewport: {x, y, w, h}` the rectangle that scrolls — the whole canvas by default (D-106); raises `ArgumentError` for more than three regions or a zero offset. |
| `Visualize.Backend.CanvasIncremental.encode_incremental/3` | `encode_incremental/4` with no options: the whole canvas is the viewport. |
| `Visualize.Backend.CanvasIncremental.encode_full_redraw/2` | Encodes an `0x60` record in full-redraw mode carrying the element's whole binary stream, with the canvas size as the record's viewport (5.6). |
| `Visualize.Backend.CanvasIncremental.encode_full_redraw/1` | `encode_full_redraw/2` with no size: a zero viewport, which a full redraw never consults. |

### 5.2 Scroll classification

`scroll_mode({dx, dy}, size)` returns, in this order of precedence: `:none` for `{0, 0}` — nothing moved and nothing is exposed (D-38); `:full_redraw` when `copy_beneficial?/2` is false; `:scroll_x` when `dy = 0`; `:scroll_y` when `dx = 0`; `:scroll_xy` when both are non-zero.

### 5.3 Exposed regions

`exposed_regions({dx, dy}, {width, height})` converts all four values to floats and returns:

- `[]` when `dx = 0` and `dy = 0`;
- one vertical strip for a horizontal scroll: `{width − dx, 0, dx, height}` when `dx > 0` (content moved left, right edge exposed) or `{0, 0, |dx|, height}` when `dx < 0`;
- one horizontal strip for a vertical scroll: `{0, height − dy, width, dy}` when `dy > 0` or `{0, 0, width, |dy|}` when `dy < 0`;
- two non-overlapping strips forming an L for a diagonal scroll: the vertical strip above, plus the horizontal strip with the corner already covered removed — `{0, height − dy, width − dx, dy}` (dx>0, dy>0), `{|dx|, height − dy, width − |dx|, dy}` (dx<0, dy>0), `{0, 0, width − dx, |dy|}` (dx>0, dy<0), `{|dx|, 0, width − |dx|, |dy|}` (dx<0, dy<0).

Regions with zero or negative width or height are removed. The function does not consult `copy_beneficial?/2`; a caller MUST classify with `scroll_mode/2` first, because an offset beyond the canvas produces nonsensical strips. The result has 0, 1 or 2 entries, never 3.

**The scroll contract** (#292). A copy-shift is exact: the hook copies the previous frame's pixels by `{dx, dy}` and draws only the exposed strips over what it copied, so it is correct only when the picture of the new frame *is* the picture of the old one translated by exactly `{dx, dy}` — every mark that stays on the canvas keeps its shape and moves by that offset, and a strip's marks are the same function of the same data as the full render's, evaluated over the strip's columns. A caller whose marks change in any other way between frames — a phase that animates, a series that slides by a fraction of a pixel — MUST NOT use the scroll modes for it: the copied pixels are then a different picture from the one the strips join, and every strip draws a fresh segment against stale neighbors. The High-Performance page sat like that (spec/14 §12.6). The same contract binds the windowed scale itself: a uniform `dx` moves every reading by the same number of pixels only when the scale is a translation of its units, so a compiled chart scrolls a viewport on a `:linear` or `:time` scale and redraws one on any other kind in full ([14-declarative-chart](14-declarative-chart.md) §12.5, #416).

**A canvas is one plot** (#432). A design of several frames draws one canvas per frame ([14-declarative-chart](14-declarative-chart.md) §12.1), and the contract above is *per canvas*: the copy-shift moves pixels within one plot, whose size is that frame's plot area and whose offset on the page is its box. Two canvases of one design scroll independently — different windows, different `dx`, one at a full redraw while its neighbor scrolls — and neither reads or writes the other's pixels. What they share is the tick that produced them: one sequence number across the canvases of a frame, so the page's flow control counts a frame and not a plot.

### 5.4 Filtering

`filter_to_regions(data, regions, accessor)` returns `data` filtered to points `{px, py} = accessor.(point)` for which some region `{rx, ry, rw, rh}` satisfies `rx ≤ px ≤ rx + rw` and `ry ≤ py ≤ ry + rh`. Coordinates are compared in the same space the regions are expressed in (canvas pixels); the caller is responsible for applying scales before comparison.

### 5.5 Incremental update record (0x60)

```
0x60  mode:u8  dx:f32  dy:f32  vx:f32  vy:f32  vw:f32  vh:f32  region_count:u8  region₀ … region(n-1)
```

- `mode`: `0x00` full redraw, `0x01` `:scroll_x`, `0x02` `:scroll_y`, `0x03` `:scroll_xy`, computed by `scroll_mode/2` from the offset and the **viewport's** size — the viewport is what is copied, so it is what the offset is classified against. `:none` has no byte: a zero offset is not an incremental update and `encode_incremental/4` raises `ArgumentError` for it (D-38).
- `dx`, `dy`: the offset as little-endian f32.
- `vx`, `vy`, `vw`, `vh`: the viewport — the rectangle of the canvas that scrolls — as little-endian f32 (D-106, #294). `encode_incremental/4` writes its `viewport:` option, `{0, 0, width, height}` when the caller gives none.
- `region_count`: `length(region_elements)`, 0–3. `encode_incremental/4` raises `ArgumentError` for more than three regions — `exposed_regions/2` never yields more than two, and the byte is never written unchecked (D-38).
- Each region: `x:f32 y:f32 w:f32 h:f32 data_length:u32 data`, where `data` is `CanvasBinary.encode_element!/1` of the element and `data_length = byte_size(data)`. Each region's `data` is a whole stream, so one that draws a paint carries its own `version` and `paint` records (4.2): a decoder replays it with no state from the regions before it.

The decoder MUST copy the viewport's pixels alone, shifted by `(−dx, −dy)` and clipped to the viewport, then clear and replay each region's stream clipped to its bounds. A pixel outside the viewport is never touched by a scroll frame (D-106): the High-Performance page's plot scrolls inside a margin that holds the axes, and a copy of the whole canvas carried the plot's leftmost columns into that margin every frame, where nothing cleared them — the y axis disappeared under the smear of everything that had scrolled off the plot (#294).

### 5.6 Full redraw record

```
0x60  0x00  0.0:f32  0.0:f32  vx:f32  vy:f32  vw:f32  vh:f32  0x00  data
```

`data` is the element's whole binary stream and runs to the end of the record; no length prefix is written. The header is the one layout of 5.5 — 27 bytes in every mode, so a decoder reads one header — and the viewport is the canvas size from `encode_full_redraw/2` or zeros from `encode_full_redraw/1`; a full redraw does not consult it. The decoder MUST clear the canvas and replay `data`.

## 6. Visualize.Backend.Hybrid

### 6.1 Functions

| Function | Contract |
|---|---|
| `Visualize.Backend.Hybrid.render/1` | Renders the static layer as SVG and the dynamic layer as Canvas commands from one option list, returning `%{svg: String.t(), canvas: String.t(), html: String.t()}`. |
| `Visualize.Backend.Hybrid.render_static/1` | Renders only the static SVG layer (initial render, resize); returns the SVG string. |
| `Visualize.Backend.Hybrid.render_dynamic/1` | Renders only the dynamic Canvas layer (data updates); returns the command string. |

### 6.2 Options

| Key | Default | Used by | Meaning |
|---|---|---|---|
| `:width` | required (`Keyword.fetch!`) | `render/1`, `render_static/1` | Chart width in pixels |
| `:height` | required | `render/1`, `render_static/1` | Chart height in pixels |
| `:margin` | `%{top: 20, right: 20, bottom: 30, left: 40}` | all | Map with `:top`, `:right`, `:bottom`, `:left`; only `:left` and `:top` are read |
| `:static` | `[]` | `render/1`, `render_static/1` | An `IR.Element` or list of them: axes, labels, grids |
| `:dynamic` | `nil` | `render/1`, `render_dynamic/1` | `nil`, an `IR.Path`, an `IR.Element`, or a list of `IR.Element` |
| `:dynamic_style` | `%{stroke: "#4e79a7", fill: :none, stroke_width: 2}` | `render/1`, `render_dynamic/1` | Style applied when `:dynamic` is a path or a list |
| `:canvas_format` | `:json` | `render/1`, `render_dynamic/1` | `:js`, `:json` or `:commands`, passed to `Canvas.render_element/2` |
| `:title`, `:description` | `nil` | `render/1` | The chart's accessible name and description, on the `html` container's `<canvas>` as `wrap_root/2` puts them (3.6, D-142) |
| `:canvas_id` | `"visualize-hybrid-canvas"` | `render/1` | The prefix of the description's id, `<canvas_id>-summary` |

The doc comment on `render/1` states a `:js` default for `:canvas_format`; the implemented and normative default is `:json`, which is what the emitted container (6.3) expects. `render_dynamic/1` passes any format of 3.2 through, `:binary` and `:binary_base64` included, for a caller that feeds the `CanvasBinaryChart` hook itself — the compiled chart of [14-declarative-chart](14-declarative-chart.md) §12.4 does; the container of `render/1` reads `:json` and `:js` only.

### 6.3 Output

Static layer: the static elements are wrapped in an `IR.Element` group with `Transform.translate(margin.left, margin.top)`, placed as the sole child of `IR.Element.root(width, height, hidden: true)` — `aria-hidden`, one layer of a picture the canvas names (D-142) — and rendered with `Visualize.Backend.SVG.render_element/1`, flattened to a string. Axes, tick labels and grid lines belong here.

Dynamic layer, by the shape of `:dynamic`:

- `nil` → `""`.
- `%IR.Path{}` → `IR.Element.path(path, dynamic_style)` with the margin translate, rendered by `Canvas.render_element/2`.
- `%IR.Element{}` → the element with its transform *replaced* by the margin translate (any transform it carried is lost), rendered; `:dynamic_style` is ignored.
- list → `IR.Element.group(list, style: dynamic_style)` with the margin translate, rendered; the group's style reaches the elements through Canvas state (3.3.1).

`html`: a `<div class="hybrid-chart" style="position: relative; width: Wpx; height: Hpx;">` containing a `<div class="hybrid-svg" style="position: absolute; top: 0; left: 0; pointer-events: none;">` with the SVG, then a `<div class="hybrid-canvas" phx-hook="CanvasChart" data-commands="…" data-width="W" data-height="H" style="position: absolute; top: 0; left: 0;">` wrapping `<canvas width="W" height="H" style="display: block;"></canvas>`. The attribute is `data-commands` for `:json` and `data-script` for any other format; its value is the canvas string with `"`, `<` and `>` HTML-escaped. The `CanvasChart` hook that reads either attribute ships in `Visualize.Hooks` (`Visualize.Hooks.Canvas`, spec/10 §7; D-40).

## 7. Visualize.Incremental

### 7.1 Functions

| Function | Contract |
|---|---|
| `Visualize.Incremental.new/1` | Builds the state struct from options (7.2); raises `KeyError` when a required option is missing. |
| `Visualize.Incremental.initial_render/1` | Returns `{"canvas_incremental", payload, state}` with a full-redraw payload for the current viewport. |
| `Visualize.Incremental.render_viewport/1` | Builds the element for the current viewport via `build_element` and returns `{binary, state}` where `binary` is `CanvasIncremental.encode_full_redraw/1` of it. |
| `Visualize.Incremental.scroll/2` | Applies a `{dx, dy}` delta to the viewport and returns `{"canvas_incremental", payload, new_state}` with an incremental, a full-redraw or a `"none"` payload (7.3). |
| `Visualize.Incremental.update_data/2` | Replaces `state.data`; the viewport and other fields are unchanged. |

### 7.2 State and `new/1`

The struct `%Visualize.Incremental{}` has fields `canvas_width`, `canvas_height`, `viewport_x`, `viewport_y`, `data`, `x_accessor`, `y_accessor`, `build_element`, `margin`.

| Option | Default | Field |
|---|---|---|
| `:canvas_size` | required | `{canvas_width, canvas_height}` in pixels |
| `:data` | required | the full dataset, a list |
| `:x_accessor` | required | `(point -> number)` giving the point's canvas x |
| `:y_accessor` | required | `(point -> number)` giving the point's canvas y |
| `:build_element` | required | `(data_subset, opts_map -> IR.Element.t())` |
| `:viewport_x` | `0` | initial horizontal viewport offset |
| `:viewport_y` | `0` | initial vertical viewport offset |
| `:margin` | `%{top: 0, right: 0, bottom: 0, left: 0}` | stored on the struct and handed to `build_element` as `margin` |

`build_element` receives an options map with keys `viewport_x`, `viewport_y`, `canvas_width`, `canvas_height`, `margin`, plus `clip_region: {x, y, w, h}` when called for one exposed region. `render_viewport/1` passes the entire `state.data` to `build_element`: what a full frame shows is the callback's decision, made from the viewport and margin it is given, since only it knows whether a mark needs its neighbors outside the viewport (a line does, a scatter does not) (D-38). Region builds receive `state.data` filtered with `CanvasIncremental.filter_to_regions/3` using the two accessors, so the accessors MUST return canvas-space coordinates.

### 7.3 Payloads

Every public entry point returns the event name `"canvas_incremental"` and a payload map with exactly these keys:

| Key | Value |
|---|---|
| `binary` | `Base.encode64/1` of the `0x60` record; `""` for `"none"` |
| `dx`, `dy` | the applied delta, or `0` for a full redraw and for `"none"` |
| `mode` | `"full"`, `"scroll_x"`, `"scroll_y"`, `"scroll_xy"` or `"none"` |

`scroll/2` first advances `viewport_x/viewport_y` by the delta, then classifies it with `scroll_mode/2`: `:none` yields the `"none"` payload with nothing encoded (D-38); `:full_redraw` yields `render_viewport/1` output as a `"full"` payload with `dx = dy = 0`; any scroll mode yields `exposed_regions/2`, one `build_element` call per region, and `encode_incremental/3` — the whole canvas is the viewport, since the state's canvas is its plot. The host application pushes the tuple with `push_event/3` (or skips the push on `"none"`); the `CanvasIncrementalChart` hook decodes the payload and ignores `"none"` (spec/10 §9).

## 8. Visualize.Benchmark

### 8.1 Functions

| Function | Contract |
|---|---|
| `Visualize.Benchmark.run/0` | `run([])`. |
| `Visualize.Benchmark.run/1` | Times SVG, Canvas (binary base64), Hybrid, Hybrid-Incremental and Canvas-Incremental rendering of a synthetic chart and returns the result map of 8.2. |
| `Visualize.Benchmark.stream_benchmark/0` | `stream_benchmark([])`. |
| `Visualize.Benchmark.stream_benchmark/1` | Renders animated frames for a fixed wall-clock duration per backend and returns the frame-rate result map of 8.3. |
| `Visualize.Benchmark.format_report/1` | Renders a `run/1` result map as a multi-line text report. |
| `Visualize.Benchmark.format_stream_report/1` | Renders a `stream_benchmark/1` result map as a multi-line text report. |

Both benchmarks encode Canvas output with `format: :binary_base64` and therefore require Nx.

### 8.2 `run/1`

| Option | Default | Meaning |
|---|---|---|
| `:data_points` | `500` | points per render |
| `:iterations` | `100` | timed renders per backend, after 10 untimed warm-up renders |
| `:chart_type` | `:line` | `:line`, `:area` or `:scatter` |
| `:width` | `800` | chart width |
| `:height` | `600` | chart height |

Result map: `config: %{data_points, iterations, chart_type, dimensions: {w, h}}`; `svg`, `canvas`, `hybrid`, `hybrid_incremental`, `canvas_incremental`, each `%{avg_render_time_us, renders_per_second, avg_payload_bytes, total_time_ms}`; `hybrid` additionally `static_svg_bytes`; the two incremental entries additionally `scroll_delta` (always `20`); `comparison: %{svg_vs_canvas_speed, svg_vs_hybrid_speed, svg_vs_hybrid_inc_speed, svg_vs_canvas_inc_speed, fastest, smallest_per_frame}` where the ratios are SVG time divided by the other backend's time rounded to 2 places and the last two are the backend keys with the lowest average time and payload.

### 8.3 `stream_benchmark/1`

| Option | Default | Meaning |
|---|---|---|
| `:duration_ms` | `5000` | wall-clock budget per backend |
| `:data_points` | `200` | points per frame |
| `:chart_type` | `:line` | `:line`, `:area` or `:scatter` |
| `:width` | `800` | chart width |
| `:height` | `600` | chart height |
| `:clock` | `fn -> System.monotonic_time(:millisecond) end` | zero-arity function returning milliseconds on a monotonic clock |

Result map: `config: %{duration_ms, data_points, chart_type}`; the same five backend keys each `%{frames, fps, data_points_per_second, total_bytes, actual_duration_ms}`, with `static_svg_bytes` added to `hybrid` and `hybrid_incremental`; `comparison: %{svg_fps, canvas_fps, hybrid_fps, hybrid_inc_fps, canvas_inc_fps, hybrid_vs_svg_fps}`. Each backend's loop reads the clock once at the start, then once per iteration, rendering a frame while the reading is below `start + duration_ms`; `actual_duration_ms` is the last reading minus the first, `frames` the number of frames rendered, and `fps` is `frames / max(actual_duration_ms / 1000, 0.001)` (D-39). Nothing but clock readings enters the elapsed time, which is what `test/visualize/benchmark_test.exs` checks on a fake clock.

### 8.4 Reports

`format_report/1` and `format_stream_report/1` return a single string of fixed-width sections, one per backend, followed by a comparison summary (fastest backend, payload sizes, 100-frame bandwidth and the Hybrid break-even frame count for `format_report/1`; FPS ranking and total bandwidth for `format_stream_report/1`). They read only the keys listed in 8.2 and 8.3, so a result map from another source MUST supply all of them.

## 9. Raster output: `Visualize.Render.Raster`

`Visualize.Render.to_png/2` and `to_png!/2` (spec/02 §4) rasterize the library's SVG through the resvg command-line tool, run as an Erlang port (spec/01 §1.7, D-121). `Visualize.Render.Raster` is the only module in `lib/` that runs it, so the backend can be replaced in one place. Its functions are `@doc false` ([11-public-api](11-public-api.md) §2.2), and the contract below is the one `to_png/2` exposes.

### 9.1 Input

- **A root `Visualize.IR.Element`** (`type: :root`) is rendered with `Visualize.Render.to_svg_string/2` first. The options `to_png/2` does not read (9.2) pass through to the SVG backend, as every `Visualize.Render` function passes them.
- **A binary** is an SVG document, as `Visualize.Chart.render/2` returns with `root: true`, and is rasterized as given. An option `to_png/2` does not read is an `ArgumentError`, since there is no backend for it to reach.

Any other input — a group, a path, a list — is a `FunctionClauseError`: a PNG is a whole document and has no size without its root.

**The SVG must carry literal colors.** The SVG backend resolves a theme slot to a custom-property reference with the literal as its fallback (`var(--vis-axis, #333)`, [08-utilities](08-utilities.md) §7.3), which a browser reads and resvg does not: resvg paints such a value black. A chart meant for a PNG is generated with `resolve: :literal` (`Visualize.Chart.generate(applied, root: true, resolve: :literal)`). An SVG containing `var(--` returns `{:error, :css_references}` rather than a picture in the wrong colors.

### 9.2 Options

Each option becomes a resvg flag (9.5):

| Option | Default | Meaning | Flag |
|---|---|---|---|
| `:scale` | `1` | Device pixel ratio, a positive number. The PNG's width and height are the root's `width` and `height` times the scale, so `scale: 2` doubles both exactly. | `--zoom`, the scale as a float (`2.0`, `1.5`) |
| `:background` | `nil` | A CSS color string painted under the document. `nil` leaves the transparent pixels transparent. A color resvg cannot parse returns `{:error, {:rasterizer, message}}`. | `--background`, omitted for `nil` |
| `:font_dirs` | `[]` | Directories whose fonts are loaded (9.6), a list of strings. Each MUST exist and be a directory; each is expanded to an absolute path (`Path.expand/1`) and passed once. | `--use-fonts-dir`, once per directory |
| `:system_fonts` | `true` | Whether the system fonts are loaded as well. The conformance suite passes `false` (D-121). | `--skip-system-fonts` when `false` |
| `:generic_families` | resvg's | The family each CSS generic keyword names, a keyword list over `:serif`, `:sans_serif`, `:monospace`, `:cursive` and `:fantasy` with string values. A key not given keeps resvg's own default: `serif` → `Times New Roman`, `sans-serif` → `Arial`, `monospace` → `Courier New`, `cursive` → `Comic Sans MS`, `fantasy` → `Impact`. | `--serif-family`, `--sans-serif-family`, `--monospace-family`, `--cursive-family`, `--fantasy-family`, for each key given |
| `:font_family` | `"sans-serif"` | The family list of text that names none, as `Visualize.Theme`'s `font_family` (whose default it is). It is written on the root `<svg>` element (9.7). | none: resvg's `--font-family` takes a single family name, not a list, so the library writes the list into the document instead |
| `:timeout` | `30_000` | Milliseconds the render may take, a positive integer. When it expires the render is stopped and `{:error, :timeout}` returned (9.5). | none |

A `:scale` that is not a positive number, a `:background` that is neither `nil` nor a string, a `:font_dirs` that is not a list of strings naming existing directories, a `:system_fonts` that is not a boolean, a `:generic_families` with a key outside the five or a value that is not a string, a `:font_family` that is not a string, or a `:timeout` that is not a positive integer, is an `ArgumentError`. Options are checked before anything else, so a bad one raises whether or not a binary is installed.

`:font_dirs`, `:system_fonts` and `:generic_families` are the **font configuration**. They are held by the host, which knows its deployment's fonts (#450's policy surface): a host on a slim image with no system fonts passes its own directory, and one whose system has no Arial maps `sans-serif` to a family it has. A wrong configuration fails loudly in the warnings (9.7). `:timeout` is the caller's intent per call; one too short fails loudly as `{:error, :timeout}`.

Every render also passes `--resources-dir` with `System.tmp_dir!/0`, the directory relative references resolve against. resvg reading from stdin has no directory of its own and warns without one; the SVG the library renders holds no relative reference, so nothing is read from it.

### 9.3 Results

`{:ok, png, warnings}` holds a PNG binary — the 8-byte signature `<<137, 80, 78, 71, 13, 10, 26, 10>>` followed by an `IHDR` chunk whose width and height are those of 9.2 — and the list of warnings of 9.7, `[]` when resvg printed none. A warning is a value the caller reads, not a log line: the picture is still returned, since an alert's chart with a label missing may be worth more than none, but it is never indistinguishable from a complete one. The errors are values (spec/11 §4):

| Result | When |
|---|---|
| `{:error, :no_rasterizer}` | no resvg binary is configured or on the `PATH`, or the configured path names no executable file (9.4) |
| `{:error, {:rasterizer_version, found, required}}` | the binary's version is below the supported minimum (9.4): `found` what `resvg --version` printed, trimmed, and `required` the minimum, `"0.45.0"` |
| `{:error, :css_references}` | the SVG holds a `var(--` reference (9.1) |
| `{:error, :timeout}` | the render did not finish within `:timeout` milliseconds; its OS processes were killed (9.5) |
| `{:error, {:rasterizer, message}}` | resvg exited non-zero, or exited 0 without a PNG; `message` is its last `Error: …` line, for example `Error: unexpected end of stream.`, or all the text it printed, trimmed, when it printed none |

`to_png!/2` returns the binary of `{:ok, png, []}`, and raises `RuntimeError` naming the reason on an error and naming the warnings when they are not empty: the bang variant returns a complete picture or none.

**Why the warnings are in the success tuple** (#474). The proposal asks for missing families "reported in the result's warnings", and the alternatives each lose something. A `warnings: :return` option would make the result's shape depend on an option, so a caller's pattern match would have to know how the call was made. A separate function (`missing_families/2`) leaves the plain call silent and makes a careful caller render twice. An error tuple would discard a picture the host may want. `to_png/2` was added in the same unreleased version (`CHANGELOG.md`, Unreleased), so neither widening `{:ok, png}` to `{:ok, png, warnings}` nor narrowing the warning to `{:missing_family, list}` (D-121) breaks a released caller.

### 9.4 The binary, its version, and the seam

**Finding the binary.** `Raster.binary/0` is the host's setting, `config :visualize, :resvg, "/path/to/resvg"`, expanded with `Path.expand/1` and accepted when it names an executable file (`System.find_executable/1` of the path). When the setting is absent it is `System.find_executable("resvg")`, the first `resvg` on the `PATH`. It is `nil` when neither gives a binary. A configured path that names nothing is `nil` too: it is **never replaced by the `PATH`'s binary**, since a host that named a binary and is silently given another has a wrong setting it cannot see. A setting that is not a string is an `ArgumentError`. The setting is read at every call, so a host may set it at run time (`config/runtime.exs`).

**The version.** The supported minimum is **resvg 0.45.0**, the version Debian bookworm and trixie package (0.45.1): the raster goldens of [12-testing-and-conformance](12-testing-and-conformance.md) §6 hold on 0.45.1 with no pixel outside the tolerance (D-121). Before its first render, a binary's version is read from `resvg --version`, whose output is the bare version (`0.48.1`), parsed as three integers and compared as a tuple. The result is cached in `:persistent_term` under `{Visualize.Render.Raster, :version, path, mtime, size}`, the binary file's path, modification time and size, so the version is read once per binary file and a binary replaced in place is read again. The value is three integers, written once per binary: the use `:persistent_term` is for. Output that is not a version refuses the binary like an old one.

**Availability and the seam.** `Raster.available?/0` is `Raster.binary() != nil`, read at the call. The test suite cannot remove a binary from the host it runs on, so the absent branch is reached through one argument: `Raster.to_png/3` and `Raster.to_png!/3` take availability as a boolean, `Visualize.Render.to_png/2` passes `Raster.available?()`, and a test passes `false`. Nothing else differs between the two branches. A host with no binary is also proved end to end, by `scripts/consumer_check.exs` calling `to_png/2` with no setting and no `resvg` on its `PATH` ([12-testing-and-conformance](12-testing-and-conformance.md) §4).

### 9.5 The port

A render is one OS process tree, started for the call and gone when it returns. The SVG goes in on stdin and the PNG comes back on stdout, so **no file is written**. An Erlang port cannot close its write end while still reading, so resvg, which reads stdin to end-of-file, would wait forever; a POSIX `sh` wrapper gives it exactly the SVG's bytes and then end-of-file:

```
/bin/sh -c 'n="$1"; b="$2"; shift 2; head -c "$n" | exec "$b" "$@" - -c 2>&1' sh <bytes> <resvg> <flags…>
```

`<bytes>` is the SVG's `byte_size/1`, `<resvg>` the binary of 9.4 and `<flags…>` those of 9.2; `-` reads the SVG from stdin and `-c` writes the PNG to stdout. The port is opened with `{:spawn_executable, "/bin/sh"}` and `[:binary, :exit_status, :stderr_to_stdout, :hide]`, the SVG is written with `Port.command/2`, and the output is collected until `{:exit_status, status}`.

- **Splitting the output.** resvg's stderr is merged into its stdout, and resvg prints its warnings while it parses, before it writes the PNG. So the output is split at the first PNG signature (`<<0x89, "PNG", 13, 10, 26, 10>>`): the text before it is warnings (9.7), and the signature and everything after it is the PNG.
- **Errors.** A nonzero exit status is `{:error, {:rasterizer, message}}`. resvg ends a failure with an `Error: …` line, and when it refuses an argument (an unparsable `--background`) it prints its usage text first, so the message is the last line that starts `Error:`, trimmed; when no line does, it is the whole text, trimmed. Exit 0 with no signature in the output is the same error.
- **The scheduler.** The calling process waits in a `receive` while resvg works in its own OS process, so no BEAM scheduler is held for the render, and a crash in resvg is an exit status, not a fault in the VM. A test holds this on a node with one normal scheduler (spec/12 §6).
- **The timeout.** A timer (`:erlang.start_timer/3`) runs for `:timeout` milliseconds. When it fires first, the render's processes are killed and `{:error, :timeout}` is returned. Closing the port would not do it: that ends `head`, but resvg already holds the SVG and runs to completion, unwatched. OTP starts every port program in a new session (`setsid`), so the port's `sh`, whose OS pid `Port.info(port, :os_pid)` gives, leads a process group that holds `head` and resvg too; `Raster` sends that group `SIGKILL` with the shell's `kill` builtin, naming the group by number and never a process by name. The killed `sh` closes the port itself, so `Raster` then waits for the `{:exit_status, _}` that follows rather than closing a port that may already be closed.
- **The kill is checked, and repeated until the port exits** (#845, D-213). The pid is reported as soon as OTP's `erl_child_setup` has forked the port's process. Until that process has called `setsid` and `exec`, it is still in `erl_child_setup`'s group, and no group with its number exists. A timer that fires in that window, which a loaded host stretches, sends a group kill that fails. If nothing checks it, the wrapper starts afterward and runs to its end. So the signal is one command, `/bin/sh -c 'kill -s KILL -- "-$1" 2>/dev/null || kill -s KILL -- "$1" 2>/dev/null' sh <os_pid>`: the group, and when no such group exists, the pid itself, which then dies before it can `exec`. It is sent again every **10 ms** until the port reports `{:exit_status, _}`, so a round that lands on nothing, for instance a group kill and a pid kill that both fall between the fork and the `setsid`, is followed by one that lands on the group. Before each round `Raster` first looks for the port's exit among its messages, so a render that ended as the timer fired is never signaled. Every wait is bounded and none is a `receive` without an `after`. If the port reports no exit within **5 s** of the timer, `Raster` closes the port, waits at most **1 s** for the close to be confirmed, and returns `{:timeout, os_pid}` anyway. **The bound:** a timed-out render returns within its `:timeout` plus 6 s, whatever the host's load. A killed render normally returns within milliseconds of its `:timeout`. Only a process that `SIGKILL` cannot end, one in uninterruptible sleep, reaches the bound, and that process outlives the call.
- **Tests.** One test checks that no process of the group survives the call. A second forces the race: it runs a stand-in program a hundred times at a 1 ms timeout, and each run must return with its group gone. Timing alone cannot make a lost kill happen on an idle runner, so `Raster.run/5` (`@doc false`) takes the signal function as a seam. A test whose first signal does nothing still sees the call return, the signal sent again and the group gone; code that did not repeat the kill fails that test every time. A test whose signal never lands sees the call return after the bound, with the port closed.
- **When the caller dies.** The port is linked to the calling process, so it closes with it; resvg then finishes its render and exits on the closed pipe. The work is bounded by the one render.

`Raster.run/4` (`@doc false`) is the port alone — a binary, its arguments, the stdin bytes and a timeout, with `run/5` also taking the signal function (above), returning `{:exit, status, output}` or `{:timeout, os_pid}` — so a test can run a stand-in program through the same wrapper and timeout.

### 9.6 Fonts

resvg builds its font database on every call from the flags of 9.2: the `--use-fonts-dir` directories, and the system's fonts unless `--skip-system-fonts`. That costs a few milliseconds for one directory and more for a system's fonts, against a chart render of tens to hundreds of milliseconds and about 4 ms to start the process. **Nothing is cached**: there is no font database in the VM, a font added to a directory is seen by the next render, and the library holds no state per font configuration.

### 9.7 Warnings and missing families

resvg never substitutes a family: a font-family list resolves to its first member the font database has, matched case-sensitively, or the text is not drawn, and resvg says so. Two rules of the library make that report complete and exact:

1. **The default family.** Text with no `font-family` of its own or on an ancestor would be drawn by resvg in its own default (`Times New Roman`), whatever the theme says, and resvg's `--font-family` takes one name, not a list. So the library writes `:font_family` (9.2), XML-escaped, as a `font-family` attribute on the root `<svg>` element, which such text inherits, unless the root already has a `font-family` attribute or style property. resvg resolves a family only for text that uses it, so a root default no text reads is never reported.
2. **The generic families** are resvg's, as the host configured them (9.2): `sans-serif` reaches for Arial unless `:generic_families` says otherwise.

The text before the PNG (9.5) is split into lines; each is trimmed, blank lines dropped, and a line repeated (resvg reports a list once per text element) is kept once, in first-seen order. Each line becomes a warning:

- **`{:missing_family, list}`** for a line `Warning (in <module>): No match for '<printed>' font-family.`, the form resvg 0.45 to 0.48 print. resvg prints the list it failed to resolve normalized: each family name in double quotes, each generic keyword bare, joined by `, ` — `font-family="Other, 'Gone', sans-serif"` is printed `"Other", "Gone", sans-serif`, and a run of whitespace inside an unquoted name is collapsed. `list` is that printed list with the double quotes around each member removed: `{:missing_family, "Other, Gone, sans-serif"}`. The members are split on commas outside double quotes, so a name holding a comma stays one member. A quoted name that equals a generic keyword (`"serif"`) reads the same as the keyword; the warning names the list, it does not re-resolve it.
- **`{:rasterizer, line}`** for any other line, so nothing resvg reports is dropped.

resvg's text is not a stable interface. Its parsing is the one function `Raster.warnings/1` (`@doc false`), and a test pins it to the output of the CI's resvg (12 §4) by rendering a missing family through the binary, not only a string.
