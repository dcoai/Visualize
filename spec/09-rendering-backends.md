# Rendering Backends

**Status:** Implemented

The rendering layer turns the backend-agnostic IR (`Visualize.IR.Element`, `Visualize.IR.Path`, `Visualize.IR.Transform`; see spec/02) into a delivery format. Two modules implement the `Visualize.Backend` behaviour: `Visualize.Backend.SVG` emits SVG markup as an iolist and `Visualize.Backend.Canvas` emits Canvas 2D drawing commands as JavaScript, JSON or Elixir tuples. `Visualize.Backend.CanvasBinary` packs the same drawing commands into a compact little-endian binary stream for the browser; `Visualize.Backend.CanvasIncremental` and `Visualize.Incremental` layer scroll-and-copy partial updates on top of it; `Visualize.Backend.Hybrid` splits one chart into a static SVG layer and a dynamic Canvas layer; `Visualize.Benchmark` measures them all. This document is the byte-level and command-level contract for every one of those outputs.

## 1. Scope and shared conventions

### 1.1 Modules covered

| Module | Role |
|---|---|
| `Visualize.Backend.SVG` | `Visualize.Backend` implementation producing SVG markup |
| `Visualize.Backend.Canvas` | `Visualize.Backend` implementation producing Canvas 2D commands |
| `Visualize.Backend.Canvas.Arc` | Internal: SVG arc to Canvas `ellipse` (endpoint-to-centre conversion) |
| `Visualize.Backend.CanvasBinary` | Binary encoder for Canvas commands (IR and `Visualize.SVG.Element` input) |
| `Visualize.Backend.CanvasBinary.Opcodes` | Internal: opcode byte constants |
| `Visualize.Backend.CanvasBinary.PathEncoder` | Internal: the `path_cubic` command stream |
| `Visualize.Backend.CanvasBinary.SVG` | Internal: `Visualize.SVG.Element` to binary |
| `Visualize.Backend.CanvasIncremental` | Scroll classification, exposed regions, incremental records |
| `Visualize.Backend.Hybrid` | Static SVG + dynamic Canvas split |
| `Visualize.Incremental` | Stateful high-level API over `CanvasIncremental` |
| `Visualize.Benchmark` | Throughput and payload comparison |

### 1.2 The backend behaviour

`Visualize.Backend` (spec/02) declares `path_data/1`, `render_path/2`, `render_element/2`, `render_scene/2` and the optional `wrap_root/2`. Both built-in backends implement all five. Only the one-argument forms `render_element/1`, `render_path/1` and `render_scene/1` are public API; the two-argument callback implementations, `path_data/1` and `wrap_root/2` are `@doc false` and reachable only through `Visualize.Render` (spec/02) or the behaviour dispatch. The one-argument forms are the two-argument forms with `opts = []`.

`Visualize.Backend.resolve/1` maps `:svg` to `Visualize.Backend.SVG`, `:canvas` to `Visualize.Backend.Canvas`, `nil` to the configured default (`config :visualize, default_backend:`, itself defaulting to `Visualize.Backend.SVG`) and any other atom to itself as a module.

### 1.3 Number formatting

Wherever this document says "formatted", a number goes through `Visualize.IR.Path.format_number/1` (spec/02 §2.2; D-12, D-32): an integer as-is; a float with at most four decimals, trailing zeros and point trimmed, never in exponent notation, never `-0`. The SVG backend uses it for path data, transform strings and points; the Canvas backend for every numeric argument.

SVG *attribute* values (as opposed to path data, transform strings and points) are NOT formatted: numbers are printed with `to_string/1`, so a float attribute keeps its full precision and may use exponent notation (`1.0e3`).

## 2. Visualize.Backend.SVG

### 2.1 Functions

Every function of this module is an `@impl` callback of `Visualize.Backend` (`render_element/2`, `render_path/2`, `render_scene/2`, `path_data/1`, `wrap_root/2`) or a default-argument head of one, and is therefore internal: it is reached through `Visualize.Render` (spec/02 §3) or by a backend-agnostic caller holding the module. The contracts below describe the callbacks.

### 2.2 Options

The hidden two-argument forms accept a keyword list. `render_element/2` ignores its options entirely.

| Function | Key | Default | Meaning |
|---|---|---|---|
| `render_path/2` | `:style` | `%{}` | Style map serialised per 2.5 onto the `<path>` |
| `render_scene/2` | `:wrap` | `true` | When true, wrap the rendered elements with `wrap_root/2`; when false return the bare list of iolists |
| `wrap_root/2` | `:width` | `800` | `width` attribute of the `<svg>` root |
| `wrap_root/2` | `:height` | `600` | `height` attribute of the `<svg>` root |
| `wrap_root/2` | `:view_box` | `"0 0 #{width} #{height}"` | `viewBox` attribute of the `<svg>` root |

`wrap_root/2` MUST emit `<svg xmlns="http://www.w3.org/2000/svg" width=".." height=".." viewBox="..">…</svg>`.

### 2.3 Element rendering

Each `IR.Element` type maps to exactly one tag. "attrs" is `element.attrs`, "style" is `style_to_attrs(element.style)` (2.5), "transform" is the serialised `element.transform` (2.5) added as a `transform` attribute when the transform is non-nil and has at least one operation.

| IR type | Tag | Attributes emitted | Children / content |
|---|---|---|---|
| `:path` | `path` | attrs, then style merged over it, `d` = `path_data/1` of `element.path`, transform | none (self-closing) |
| `:group` | `g` | style, then attrs merged over it, transform | children rendered recursively |
| `:root` | `svg` | `xmlns="http://www.w3.org/2000/svg"`, then attrs (`view_box` emitted as `viewBox`, 2.4); `element.style` and `element.transform` are ignored | children |
| `:rect`, `:circle`, `:ellipse`, `:line`, `:image` | same name | attrs, then style merged over it, transform | none |
| `:polyline`, `:polygon` | same name | `points` (2.6), style, transform; every other key in attrs is dropped | none |
| `:text` | `text` | attrs, style, transform | `element.content` as escaped text |
| `:title`, `:desc` | same name | attrs (the `id`) | `element.content` as escaped text |
| `:defs` | `defs` | none | children |
| `:clip_path` | `clipPath` | attrs verbatim | children |
| `:linear_gradient` | `linearGradient` | attrs verbatim | children |
| `:radial_gradient` | `radialGradient` | attrs verbatim | children |
| `:stop` | `stop` | attrs, style | none |

A path's attrs are the data attributes of spec/10 §12.2 and §14.2 — the datum a per-series path carries and its `data-series` (D-75, D-77); before those a path had no attrs to print. Any other type raises `FunctionClauseError`. Tags in `circle ellipse line path polygon polyline rect image use stop` are emitted self-closing (`<rect …/>`) when they have neither children nor content; all other tags are emitted as `<tag …>content children</tag>`.

### 2.4 Attribute serialisation

Tags, attributes and text are rendered by the functions of `Visualize.SVG.Renderer` (spec/02 §5.4), so this backend and the HEEx bridge emit one markup for one IR (D-34):

- Attributes whose value is `nil` MUST be omitted.
- Each key's SVG name comes from `Visualize.SVG.Renderer.attribute_name/1`: underscores become hyphens (`stroke_width` → `stroke-width`) except for the camel-cased SVG attributes, which map to their spelling (`view_box` → `viewBox`, D-11).
- Attributes MUST be emitted sorted by that SVG name.
- Binary values are escaped: `&` → `&amp;`, `"` → `&quot;`, `<` → `&lt;`, `>` → `&gt;`. Numbers and atoms are printed with `to_string/1` and `Atom.to_string/1` and are not escaped.
- Text content is escaped for `&`, `<`, `>` only.

### 2.5 Style and transform serialisation

`style_to_attrs/1` drops `nil` values and converts atoms that have SVG spellings:

| Style key | Atom value | Emitted |
|---|---|---|
| `:fill`, `:stroke` | `:none` | `"none"` |
| `:fill`, `:stroke` | `:current_color` | `"currentColor"` |
| `:text_anchor` | `:start`, `:middle`, `:end` | `"start"`, `"middle"`, `"end"` |
| `:stroke_linecap`, `:stroke_linejoin` | any atom | `Atom.to_string/1` |
| `:dominant_baseline` | any atom | `Atom.to_string/1` |

Every other `{key, value}` pair passes through unchanged and is serialised per 2.4, so `stroke_width: 2` becomes `stroke-width="2"` and `font_size: 12` becomes `font-size="12"`.

A transform is serialised by `Visualize.IR.Transform.to_string/1` (spec/02 §2.3): its operations joined by a single space, each formatted per 1.3:

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

| IR type | Commands |
|---|---|
| `:path` | T, S, `{:beginPath, []}`, `path_data/1` (3.3.2), A |
| `:rect` | T, S, `{:beginPath, []}`, `{:rect, [x, y, width, height]}`, A — `attrs` MUST contain `:x`, `:y`, `:width`, `:height` |
| `:circle` | T, S, `{:beginPath, []}`, `{:arc, [cx, cy, r, 0, 2π]}`, A — `attrs` MUST contain `:cx`, `:cy`, `:r` |
| `:ellipse` | T, S, `{:beginPath, []}`, `{:ellipse, [cx, cy, rx, ry, 0, 0, 2π]}`, A |
| `:line` | T, S, `{:beginPath, []}`, `{:moveTo, [x1, y1]}`, `{:lineTo, [x2, y2]}`, `{:stroke, []}` — always stroked regardless of style |
| `:polyline` | T, S, `{:beginPath, []}`, `moveTo` first point then `lineTo` each remaining point, A; no commands for an empty or missing `points` list |
| `:polygon` | as `:polyline` plus `{:closePath, []}` after the last `lineTo` |
| `:text` | T, text style (3.3.3), `{:fillText, [content or "", x, y]}` with `x`/`y` from attrs defaulting to `0` |
| `:group` | `{:save, []}`, T, S, children's commands, `{:restore, []}` |
| `:root` | children's commands only |
| `:image` | T, `{:drawImage, [href, x, y, width, height]}` |
| `:defs`, `:clip_path`, `:linear_gradient`, `:radial_gradient`, `:stop`, `:title`, `:desc` | nothing |

A `:group`'s style setup is emitted after its transform, inside the `save`/`restore` pair, so that children without their own style inherit fill, stroke and line width through Canvas state; `Visualize.Backend.Hybrid` relies on this when it wraps a list of dynamic elements in a styled group (6.3) (D-37).

#### 3.3.2 Path commands

`path_data/1` first normalises the path with `Visualize.IR.Path.absolute/1` (spec/02 §2.2) — relative commands resolved against the current point, `H`/`V` as `L`, `S`/`T` expanded — and then maps each absolute command to one Canvas call, tracking the current point and the subpath start (D-37):

| Normalised command | Tuple |
|---|---|
| `{:M, x, y}` | `{:moveTo, [x, y]}` |
| `{:L, x, y}` | `{:lineTo, [x, y]}` |
| `{:C, x1, y1, x2, y2, x, y}` | `{:bezierCurveTo, [x1, y1, x2, y2, x, y]}` |
| `{:Q, x1, y1, x, y}` | `{:quadraticCurveTo, [x1, y1, x, y]}` |
| `{:A, rx, ry, rot, large, sweep, x, y}` | `{:ellipse, [cx, cy, rx', ry', rot·π/180, θ₁, θ₁ + Δθ, sweep == 0]}` by the SVG endpoint-to-centre conversion (`Visualize.Backend.Canvas.Arc`): radii too small for the chord scale up to fit, `large` and `sweep` choose the centre and the direction, `Δθ` is adjusted by a full turn to match `sweep`; nothing when the arc's end point equals the current point; `{:lineTo, [x, y]}` when a radius is `0` |
| `:Z` | `{:closePath, []}`; the current point returns to the subpath start |

Every tuple names a Canvas 2D method, so the `:commands`, `:json` and `:js` outputs are all directly executable.

#### 3.3.3 Style commands

`style_setup_commands/1` (empty map → no commands) emits, in this order and only for keys present and non-nil:

| Style key | Command | Notes |
|---|---|---|
| `:fill` | `{:set_fillStyle, [css]}` | omitted for `:none`; `:current_color` → `"currentColor"`; any other value via `to_string/1` |
| `:stroke` | `{:set_strokeStyle, [css]}` | same rules |
| `:stroke_width` | `{:set_lineWidth, [w]}` | |
| `:stroke_linecap` | `{:set_lineCap, [to_string(v)]}` | |
| `:stroke_linejoin` | `{:set_lineJoin, [to_string(v)]}` | |
| `:opacity` | `{:set_globalAlpha, [o]}` | |

`style_apply_commands/1` emits `{:fill, []}` when `:fill` is present and not `:none`, then `{:stroke, []}` when `:stroke` is present and not `:none`.

Text style (`:text` elements only) emits `{:set_font, ["#{size}px #{family}"]}` when either `:font_size` (default `10`) or `:font_family` (default `"sans-serif"`) is set; `{:set_textAlign, ["left" | "center" | "right"]}` for `:text_anchor` `:start | :middle | :end`; and `set_fillStyle` under the fill rules above. No other style keys affect Canvas output.

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

### 3.4 JavaScript serialisation

Each command becomes one statement. `set_*` commands become property assignments (`ctx.fillStyle = 'red';`, `ctx.lineWidth = 2;`, `ctx.globalAlpha = 0.5;`, `ctx.font = '12px serif';`, `ctx.textAlign = 'center';`). `beginPath`, `closePath`, `fill`, `stroke`, `save`, `restore` become the parameterless call. `moveTo`, `lineTo`, `bezierCurveTo`, `quadraticCurveTo`, `arc`, `ellipse`, `rect`, `translate`, `rotate`, `scale`, `transform` become the same-named call with formatted (1.3) arguments separated by `, `; a boolean argument prints as `true`/`false`. `rotate_around` becomes `ctx.translate(cx, cy); ctx.rotate(a); ctx.translate(-cx, -cy);`. `fillText` becomes `ctx.fillText('text', x, y);` with `\`, `'` and newline escaped in the text. `drawImage` becomes an immediately-invoked function that creates an `Image`, captures `ctx.getTransform()`, and in `onload` saves the context, restores that transform, calls `ctx.drawImage(img, x, y, w, h)` and restores — the load is asynchronous, the draw lands where the statement ran. No command is emitted as a comment (D-37); a command tuple the serialiser does not know raises `FunctionClauseError`.

### 3.5 JSON serialisation

The output is `[` + objects joined by `,` + `]`, each object exactly `{"cmd":"<name>","args":[<values>]}` with the command atom's name as the string. Values: binaries are quoted with `\`, `"`, newline, carriage return and tab escaped; numbers are formatted per 1.3; `true`/`false` are the JSON literals; other atoms are quoted names; anything else is quoted `to_string/1`. No whitespace is emitted.

### 3.6 Root wrapper

`wrap_root/2` MUST emit, in order: `<canvas id="ID" width="W" height="H"></canvas>\n`, `<script>\n(function() {\n  var canvas = document.getElementById('ID');\n  var ctx = canvas.getContext('2d');\n`, the content, `})();\n</script>\n`.

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

### 4.2 Stream model and opcodes

A stream is a concatenation of records. Every record begins with a one-byte opcode; the opcode fixes the record's layout, so the stream is self-delimiting and carries no length prefix or header. All multi-byte integers are little-endian unsigned 32-bit (`u32`); all coordinates are little-endian IEEE-754 binary64 (`f64`) except where a record states `f32`, which is little-endian binary32. The two path records exist in an f64 and an f32 form under different opcodes — `path`/`path32`, `path_cubic`/`path_cubic32` — with the same layout apart from the width of every coordinate (D-73); 4.5 says which the encoder writes. Colour components are single unsigned bytes.

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
| 0 | `0x01` | fill colour RGBA | 4 |
| 1 | `0x02` | stroke colour RGBA | 4 |
| 2 | `0x04` | stroke width, little-endian f32 | 4 |
| 3 | `0x08` | global alpha 0–1, little-endian f32 | 4 |

Alpha `a` is 0–255. The IR encoder emits a style record whenever `element.style` is non-empty, even if it sets no flags; the SVG encoder (4.7) omits the record when `flags` would be `0`. The SVG encoder never sets bit 3.

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

### 4.4 Encoding IR elements

`encode_element/1` on an `IR.Element` writes, per type:

| IR type | Records |
|---|---|
| `:path` | transform (if non-nil with ≥1 operation), style (if the style map is non-empty), the path record (4.5), then `fill` if `style.fill` is set and not `:none`, then `stroke` if `style.stroke` is set and not `:none` |
| `:circle` | transform, style, `circles` with one entry from `attrs.cx/cy/r`, draw records as above |
| `:rect` | transform, style, `rects` with one entry from `attrs.x/y/width/height`, draw records as above |
| `:group` | `save`, transform (if any), each child's records, `restore`; the group's own style is ignored |
| `:root` | each child's records, nothing else |
| any other type | nothing (zero bytes) |

Elements of type `:ellipse`, `:line`, `:polyline`, `:polygon`, `:text`, `:title`, `:desc`, `:image`, `:defs`, `:clip_path`, gradients and `:stop` are silently dropped from the binary stream. Text has no binary representation by design; the other geometric types SHOULD be encoded as `path_cubic` records.

### 4.5 Path form selection

`encode_path/2` and the `:path` branch of `encode_element/2` choose the path record from the command list, with the smooth curves already expanded, and from the `precision:` option (D-36, D-73):

- One `:M` followed by zero or more `:L` commands — a single open polyline, the case the point-list records represent without loss of shape — is `path32` (0x05) under `precision: :f32`, the default, and `path` (0x01) under `:f64`.
- One `:M` followed by one or more `:C` commands — a single open cubic run, what the curve generators emit — is `cubic_run` (0x07) under `:f32` (4.3.10); under `:f64` it is `path_cubic` (0x02), the run having no f64 form (D-74).
- Every other command list, the empty list included, is `path_cubic32` (0x06) under `:f32` and `path_cubic` (0x02) under `:f64`.

The three tests are on the command list after `Visualize.IR.Path.expand_smooth/1`, so a run written with `S` after its first `C` is a run too; a `Z`, a second subpath, a relative command or a mixed run of `L` and `C` falls to the command stream, which holds it exactly.

The default is f32 because the stream carries canvas coordinates, which are pixel positions: an f32 stores a value below 2¹⁴ = 16,384 in magnitude to within 2⁻¹¹ (≈ 0.0005 px) and one below 2¹¹ = 2,048 to within 2⁻¹³ (≈ 0.0001 px) — the rounding error is at most half an ULP, and the ULP of a value in `[2ⁿ, 2ⁿ⁺¹)` is 2ⁿ⁻²³ — which is far under the half pixel a rasteriser resolves, while every f64 path record is twice the size for precision the canvas cannot show. That bound is the contract of the f32 records: `test/visualize/backend/canvas_binary_test.exs` holds it over random coordinates, and holds `decode(encode(path))` to the path with every argument rounded to its nearest f32. `precision: :f64` writes the records of 4.3.1 and 4.3.2 — byte for byte the stream before D-73 — for a consumer whose values are not pixels or exceed 2²⁴, where an f32 no longer holds every integer. The option governs the path records alone: `circles`, `rects` and `transform` keep their f64 layouts, and `Visualize.Shape.LineNx.to_binary/6,7` (spec/04 §10.2) writes the f64 `path` record as it always has.

### 4.6 Colour parsing (IR encoder)

A binary style colour is parsed by `Visualize.Color.parse/1` (spec/08) and written as `Visualize.Color.to_rgba/1` gives it, the opacity scaled to 0–255 and rounded: every syntax that function accepts — `#rgb`, `#rgba`, `#rrggbb`, `#rrggbbaa`, `rgb()`, `rgba()` with any decimal alpha, `hsl()`, `hsla()` and the CSS colour names — resolves; a binary it cannot parse and any non-binary value (`:current_color` included) yields opaque black `{0, 0, 0, 255}` (D-36).

### 4.7 Encoding SVG elements (`Visualize.Backend.CanvasBinary.SVG`)

`encode_element/1` on a `Visualize.SVG.Element` reads presentation attributes from `attrs` instead of an IR style map. Tags handled:

| Tag | Records |
|---|---|
| `:svg` | children only |
| `:g` | if `attrs.transform` is present: `save`, the parsed transform (below), children, `restore`; otherwise children only |
| `:rect` | style (if any flag set), `rects` from `x y width height` (default `0`, numbers or numeric strings), draw records |
| `:circle` | style, `circles` from `cx cy r`, draw records |
| `:path` | style, the command-stream record — `path_cubic32` under `precision: :f32`, `path_cubic` under `:f64` (4.5) — from the parsed `d` string, draw records; a `d` that parses to no commands produces zero bytes |
| `:line` | style, the command-stream record of `[{:M, x1, y1}, {:L, x2, y2}]`, then an unconditional `stroke` |
| `:text` | nothing — text is not representable |
| any other tag | nothing |

Style attributes read: `fill`, `stroke`, `stroke_width` or `"stroke-width"`, `opacity` or `fill_opacity` or `"fill-opacity"` (fill alpha), `stroke_opacity` or `"stroke-opacity"` (stroke alpha, default `1.0`). A colour is "present" unless it is `nil`, `:none` or `"none"`. Draw records: `fill` if fill is present, `stroke` if stroke is present; if neither is present and fill is not explicitly none, a single `fill` (SVG's default black fill). A colour — a binary, or an atom taken by its name — is parsed by `Visualize.Color.parse/1` as in 4.6, so every hex, `rgb()`, `hsl()` and named form resolves and an unparseable value is black; `"none"` is transparent black. The supplied opacity becomes the alpha byte (`trunc(opacity · 255)`), except that a syntax carrying its own alpha below 1 (`rgba()`, `hsla()`, `#rgba`, `#rrggbbaa`) uses that alpha.

The `transform` attribute is parsed only when it begins with `translate(` (one or two numbers → kind `0x01`, missing `y` = `0`) or `scale(` (one or two numbers → kind `0x03` with zero translation); any other string, or a compound string, emits no transform record.

The `d` string parser accepts the commands `M m L l H h V v C c Q q A a Z z`, numbers with optional sign, decimal point and exponent, comma or whitespace separators, and implicit `L` for bare coordinate pairs following a command. `S s T t` are not recognised and end the parse at that point.

## 5. Visualize.Backend.CanvasIncremental

### 5.1 Functions

| Function | Contract |
|---|---|
| `Visualize.Backend.CanvasIncremental.copy_beneficial?/2` | `copy_beneficial?({dx, dy}, {width, height})` is `true` iff `abs(dx) < 0.5·width` and `abs(dy) < 0.5·height`. |
| `Visualize.Backend.CanvasIncremental.scroll_mode/2` | Classifies a scroll offset against a canvas size as `:none`, `:scroll_x`, `:scroll_y`, `:scroll_xy` or `:full_redraw` (5.2). |
| `Visualize.Backend.CanvasIncremental.exposed_regions/2` | Returns the rectangles `{x, y, w, h}` (floats) newly exposed after shifting the canvas by the offset (5.3). |
| `Visualize.Backend.CanvasIncremental.filter_to_regions/3` | Keeps the data points whose `{x, y}` (from the accessor) lie inside any region, bounds inclusive. |
| `Visualize.Backend.CanvasIncremental.encode_incremental/3` | Encodes an `0x60` incremental update record for the offset, canvas size and `[{bounds, element}]` list (5.5); raises `ArgumentError` for more than three regions or a zero offset. |
| `Visualize.Backend.CanvasIncremental.encode_full_redraw/1` | Encodes an `0x60` record in full-redraw mode carrying the element's whole binary stream (5.6). |

### 5.2 Scroll classification

`scroll_mode({dx, dy}, size)` returns, in this order of precedence: `:none` for `{0, 0}` — nothing moved and nothing is exposed (D-38); `:full_redraw` when `copy_beneficial?/2` is false; `:scroll_x` when `dy = 0`; `:scroll_y` when `dx = 0`; `:scroll_xy` when both are non-zero.

### 5.3 Exposed regions

`exposed_regions({dx, dy}, {width, height})` converts all four values to floats and returns:

- `[]` when `dx = 0` and `dy = 0`;
- one vertical strip for a horizontal scroll: `{width − dx, 0, dx, height}` when `dx > 0` (content moved left, right edge exposed) or `{0, 0, |dx|, height}` when `dx < 0`;
- one horizontal strip for a vertical scroll: `{0, height − dy, width, dy}` when `dy > 0` or `{0, 0, width, |dy|}` when `dy < 0`;
- two non-overlapping strips forming an L for a diagonal scroll: the vertical strip above, plus the horizontal strip with the corner already covered removed — `{0, height − dy, width − dx, dy}` (dx>0, dy>0), `{|dx|, height − dy, width − |dx|, dy}` (dx<0, dy>0), `{0, 0, width − dx, |dy|}` (dx>0, dy<0), `{|dx|, 0, width − |dx|, |dy|}` (dx<0, dy<0).

Regions with zero or negative width or height are removed. The function does not consult `copy_beneficial?/2`; a caller MUST classify with `scroll_mode/2` first, because an offset beyond the canvas produces nonsensical strips. The result has 0, 1 or 2 entries, never 3.

### 5.4 Filtering

`filter_to_regions(data, regions, accessor)` returns `data` filtered to points `{px, py} = accessor.(point)` for which some region `{rx, ry, rw, rh}` satisfies `rx ≤ px ≤ rx + rw` and `ry ≤ py ≤ ry + rh`. Coordinates are compared in the same space the regions are expressed in (canvas pixels); the caller is responsible for applying scales before comparison.

### 5.5 Incremental update record (0x60)

```
0x60  mode:u8  dx:f32  dy:f32  region_count:u8  region₀ … region(n-1)
```

- `mode`: `0x00` full redraw, `0x01` `:scroll_x`, `0x02` `:scroll_y`, `0x03` `:scroll_xy`, computed by `scroll_mode/2` from the offset and canvas size. `:none` has no byte: a zero offset is not an incremental update and `encode_incremental/3` raises `ArgumentError` for it (D-38).
- `dx`, `dy`: the offset as little-endian f32.
- `region_count`: `length(region_elements)`, 0–3. `encode_incremental/3` raises `ArgumentError` for more than three regions — `exposed_regions/2` never yields more than two, and the byte is never written unchecked (D-38).
- Each region: `x:f32 y:f32 w:f32 h:f32 data_length:u32 data`, where `data` is `CanvasBinary.encode_element!/1` of the element and `data_length = byte_size(data)`.

The decoder MUST copy the existing canvas content shifted by `(−dx, −dy)`, then clear and replay each region's stream clipped to its bounds.

### 5.6 Full redraw record

```
0x60  0x00  0.0:f32  0.0:f32  0x00  data
```

`data` is the element's whole binary stream and runs to the end of the record; no length prefix is written. The decoder MUST clear the canvas and replay `data`.

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

The doc comment on `render/1` states a `:js` default for `:canvas_format`; the implemented and normative default is `:json`, which is what the emitted container (6.3) expects. `render_dynamic/1` passes any format of 3.2 through, `:binary` and `:binary_base64` included, for a caller that feeds the `CanvasBinaryChart` hook itself — the compiled chart of [14-declarative-chart](14-declarative-chart.md) §12.4 does; the container of `render/1` reads `:json` and `:js` only.

### 6.3 Output

Static layer: the static elements are wrapped in an `IR.Element` group with `Transform.translate(margin.left, margin.top)`, placed as the sole child of `IR.Element.root(width, height)` and rendered with `Visualize.Backend.SVG.render_element/1`, flattened to a string. Axes, tick labels and grid lines belong here.

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

`build_element` receives an options map with keys `viewport_x`, `viewport_y`, `canvas_width`, `canvas_height`, `margin`, plus `clip_region: {x, y, w, h}` when called for one exposed region. `render_viewport/1` passes the entire `state.data` to `build_element`: what a full frame shows is the callback's decision, made from the viewport and margin it is given, since only it knows whether a mark needs its neighbours outside the viewport (a line does, a scatter does not) (D-38). Region builds receive `state.data` filtered with `CanvasIncremental.filter_to_regions/3` using the two accessors, so the accessors MUST return canvas-space coordinates.

### 7.3 Payloads

Every public entry point returns the event name `"canvas_incremental"` and a payload map with exactly these keys:

| Key | Value |
|---|---|
| `binary` | `Base.encode64/1` of the `0x60` record; `""` for `"none"` |
| `dx`, `dy` | the applied delta, or `0` for a full redraw and for `"none"` |
| `mode` | `"full"`, `"scroll_x"`, `"scroll_y"`, `"scroll_xy"` or `"none"` |

`scroll/2` first advances `viewport_x/viewport_y` by the delta, then classifies it with `scroll_mode/2`: `:none` yields the `"none"` payload with nothing encoded (D-38); `:full_redraw` yields `render_viewport/1` output as a `"full"` payload with `dx = dy = 0`; any scroll mode yields `exposed_regions/2`, one `build_element` call per region, and `encode_incremental/3`. The host application pushes the tuple with `push_event/3` (or skips the push on `"none"`); the `CanvasIncrementalChart` hook decodes the payload and ignores `"none"` (spec/10 §9).

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
