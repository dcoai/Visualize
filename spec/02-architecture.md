# Architecture

**Status:** Implemented

Visualize is a pipeline of pure values: data is mapped by scales, turned into geometry by shapes, assembled into a backend-agnostic scene graph (the IR), and finally serialised by a backend. This document settles the pipeline, the three IR modules, the backend behaviour and its resolution, the `Visualize.Render` entry point, and the SVG element layer that faces HEEx templates.

## 1. The pipeline

```
data ──► Visualize.Scale ──► Visualize.Shape ──► Visualize.IR.Element ──► Visualize.Backend ──► Visualize.Render
          domain → range     path strings or      scene graph of          SVG | Canvas          iolist | String
                             IR.Path               elements + transforms   (+ encoders)
```

1. **Scales** (`Visualize.Scale`, [03-scales](03-scales.md)) map domain values to range values. They are structs; `apply/2` performs the mapping.
2. **Shapes** (`Visualize.Shape`, [04-shapes-and-curves](04-shapes-and-curves.md)) turn scaled data into geometry. `generate/2` returns an SVG path-data string; `generate_path/2` returns a `Visualize.IR.Path`.
3. **The IR** (`Visualize.IR.*`, §2) is the scene graph: `Element` nodes carrying attributes, style, an optional `Transform`, children, text content or a `Path`. `Visualize.Axis.generate/1` and the layouts emit IR.
4. **Backends** (`Visualize.Backend`, §3) serialise the IR. `Visualize.Backend.SVG` and `Visualize.Backend.Canvas` implement the behaviour. `Visualize.Backend.CanvasBinary`, `Visualize.Backend.Hybrid` and `Visualize.Backend.CanvasIncremental` are *encoders* with their own entry points, not behaviour implementations; they are specified in [09-rendering-backends](09-rendering-backends.md).
5. **Render** (`Visualize.Render`, §4) chooses a backend and dispatches on the IR's shape.

Every stage is a pure function of its inputs. No stage holds process state; the only process in the library is the force simulation ([06-layouts](06-layouts.md)).

## 2. The intermediate representation

### 2.1 `Visualize.IR.Element`

An element is `%Visualize.IR.Element{type, attrs, style, transform, children, content, path}`. `type` MUST be one of `:path`, `:rect`, `:circle`, `:ellipse`, `:line`, `:polyline`, `:polygon`, `:text`, `:group`, `:image`, `:defs`, `:clip_path`, `:linear_gradient`, `:radial_gradient`, `:stop`, `:root`. `attrs` is a map of geometric attributes; `style` is a map whose recognised keys are `:fill`, `:stroke`, `:stroke_width`, `:stroke_linecap` (`:butt | :round | :square`), `:stroke_linejoin` (`:miter | :round | :bevel`), `:stroke_dasharray`, `:opacity`, `:fill_opacity`, `:stroke_opacity`, `:font_size`, `:font_family`, `:font_weight`, `:text_anchor` (`:start | :middle | :end`), `:dominant_baseline`, `:class`; `:fill` and `:stroke` accept a string, `:none` or `:current_color`. Gradient stops additionally use `:stop_color` and `:stop_opacity`. Backends MUST pass unrecognised style keys through unchanged. Constructors with a default `style` argument default it to `%{}`.

| Function | Contract |
|---|---|
| `Visualize.IR.Element.new/1` | As `new/2` with no options. |
| `Visualize.IR.Element.new/2` | Builds an element of the given type from options `:attrs` (default `%{}`), `:style` (`%{}`), `:transform` (`nil`), `:children` (`[]`), `:content` (`nil`), `:path` (`nil`). |
| `Visualize.IR.Element.path/1` | As `path/2` with an empty style. |
| `Visualize.IR.Element.path/2` | Wraps a `Visualize.IR.Path` in a `:path` element with the given style. |
| `Visualize.IR.Element.group/0` | An empty `:group`. |
| `Visualize.IR.Element.group/1` | A `:group` with the given children. |
| `Visualize.IR.Element.group/2` | A `:group` with children and options `:style`, `:transform`, `:attrs`. |
| `Visualize.IR.Element.rect/4` | As `rect/5` with an empty style. |
| `Visualize.IR.Element.rect/5` | A `:rect` with attrs `x`, `y`, `width`, `height`. |
| `Visualize.IR.Element.circle/3` | As `circle/4` with an empty style. |
| `Visualize.IR.Element.circle/4` | A `:circle` with attrs `cx`, `cy`, `r`. |
| `Visualize.IR.Element.ellipse/4` | As `ellipse/5` with an empty style. |
| `Visualize.IR.Element.ellipse/5` | An `:ellipse` with attrs `cx`, `cy`, `rx`, `ry`. |
| `Visualize.IR.Element.line/4` | As `line/5` with an empty style. |
| `Visualize.IR.Element.line/5` | A `:line` with attrs `x1`, `y1`, `x2`, `y2`. |
| `Visualize.IR.Element.polyline/1` | As `polyline/2` with an empty style. |
| `Visualize.IR.Element.polyline/2` | A `:polyline` whose `points` attr is a list of `{x, y}` tuples. |
| `Visualize.IR.Element.polygon/1` | As `polygon/2` with an empty style. |
| `Visualize.IR.Element.polygon/2` | A `:polygon` whose `points` attr is a list of `{x, y}` tuples. |
| `Visualize.IR.Element.text/2` | A `:text` element from content and a keyword list; takes `:x`, `:y`, `:dx`, `:dy` into attrs and `:style` into style. |
| `Visualize.IR.Element.text/3` | As `text/4` with an empty style. |
| `Visualize.IR.Element.text/4` | A `:text` element with content and attrs `x`, `y`. |
| `Visualize.IR.Element.image/5` | As `image/6` with an empty style. |
| `Visualize.IR.Element.image/6` | An `:image` with attrs `href`, `x`, `y`, `width`, `height`. |
| `Visualize.IR.Element.defs/0` | An empty `:defs`. |
| `Visualize.IR.Element.defs/1` | A `:defs` with the given children. |
| `Visualize.IR.Element.clip_path/2` | A `:clip_path` with attr `id` and the given children. |
| `Visualize.IR.Element.linear_gradient/1` | As `linear_gradient/2` with no options. |
| `Visualize.IR.Element.linear_gradient/2` | A `:linear_gradient` with attr `id`, optional `:x1`, `:y1`, `:x2`, `:y2` attrs, and children from `:stops` (default `[]`). |
| `Visualize.IR.Element.radial_gradient/1` | As `radial_gradient/2` with no options. |
| `Visualize.IR.Element.radial_gradient/2` | A `:radial_gradient` with attr `id`, optional `:cx`, `:cy`, `:r`, `:fx`, `:fy` attrs, and children from `:stops`. |
| `Visualize.IR.Element.stop/2` | As `stop/3` with no options. |
| `Visualize.IR.Element.stop/3` | A `:stop` with attr `offset`, style `stop_color`, and `stop_opacity` when `:opacity` is given. |
| `Visualize.IR.Element.root/2` | As `root/3` with no options. |
| `Visualize.IR.Element.root/3` | A `:root` with attrs `width`, `height`, `view_box` (default `"0 0 #{width} #{height}"`) and children from `:children`. |
| `Visualize.IR.Element.append/2` | Appends one element or a list of elements to `children`. |
| `Visualize.IR.Element.prepend/2` | Prepends one element or a list of elements to `children`. |
| `Visualize.IR.Element.set_transform/2` | Replaces the element's transform. |
| `Visualize.IR.Element.translate/3` | Adds a translate operation: creates the transform when `nil`, otherwise appends to it. |
| `Visualize.IR.Element.set_style/2` | Merges the given style over the existing style. |
| `Visualize.IR.Element.set_attrs/2` | Merges the given attrs over the existing attrs. |
| `Visualize.IR.Element.set_content/2` | Sets the text content. |
| `Visualize.IR.Element.translate_group/3` | Wraps an element or list of elements in a `:group` carrying `Transform.translate(x, y)`. |

`Visualize.IR.Element` implements `String.Chars` (renders through `Visualize.Backend.SVG`) and, when `Phoenix.HTML.Safe` is loaded, `Phoenix.HTML.Safe` (D-7).

### 2.2 `Visualize.IR.Path`

A path is `%Visualize.IR.Path{commands, metadata}`; `metadata` is a free map for producers and is not serialised. Commands are tuples tagged with the SVG command letter — absolute upper-case, relative lower-case: `{:M|:m, x, y}`, `{:L|:l, x, y}`, `{:H|:h, x}`, `{:V|:v, y}`, `{:C|:c, x1, y1, x2, y2, x, y}`, `{:S|:s, x2, y2, x, y}`, `{:Q|:q, x1, y1, x, y}`, `{:T|:t, x, y}`, `{:A|:a, rx, ry, rotation, large_arc, sweep, x, y}` and the bare atom `:Z`. `large_arc` and `sweep` MUST be `0` or `1`. Builders append in call order.

| Function | Contract |
|---|---|
| `Visualize.IR.Path.new/0` | An empty path. |
| `Visualize.IR.Path.move_to/3` | Appends `{:M, x, y}`. |
| `Visualize.IR.Path.move_to_rel/3` | Appends `{:m, dx, dy}`. |
| `Visualize.IR.Path.line_to/3` | Appends `{:L, x, y}`. |
| `Visualize.IR.Path.line_to_rel/3` | Appends `{:l, dx, dy}`. |
| `Visualize.IR.Path.horizontal_to/2` | Appends `{:H, x}`. |
| `Visualize.IR.Path.horizontal_to_rel/2` | Appends `{:h, dx}`. |
| `Visualize.IR.Path.vertical_to/2` | Appends `{:V, y}`. |
| `Visualize.IR.Path.vertical_to_rel/2` | Appends `{:v, dy}`. |
| `Visualize.IR.Path.curve_to/7` | Appends a cubic Bézier `{:C, x1, y1, x2, y2, x, y}`. |
| `Visualize.IR.Path.curve_to_rel/7` | Appends `{:c, ...}` with relative coordinates. |
| `Visualize.IR.Path.smooth_curve_to/5` | Appends `{:S, x2, y2, x, y}`. |
| `Visualize.IR.Path.smooth_curve_to_rel/5` | Appends `{:s, ...}`. |
| `Visualize.IR.Path.quad_to/5` | Appends a quadratic Bézier `{:Q, x1, y1, x, y}`. |
| `Visualize.IR.Path.quad_to_rel/5` | Appends `{:q, ...}`. |
| `Visualize.IR.Path.smooth_quad_to/3` | Appends `{:T, x, y}`. |
| `Visualize.IR.Path.smooth_quad_to_rel/3` | Appends `{:t, dx, dy}`. |
| `Visualize.IR.Path.arc_to/8` | Appends `{:A, rx, ry, x_rotation, large_arc, sweep, x, y}`; rotation in degrees. |
| `Visualize.IR.Path.arc_to_rel/8` | Appends `{:a, ...}` with a relative end point. |
| `Visualize.IR.Path.close/1` | Appends `:Z`. |
| `Visualize.IR.Path.empty?/1` | `true` iff there are no commands. |
| `Visualize.IR.Path.command_count/1` | The number of commands. |
| `Visualize.IR.Path.concat/1` | One path whose commands are the concatenation of the given paths' commands, in order; metadata is dropped. |
| `Visualize.IR.Path.append/2` | The first path's commands followed by the second's; metadata is dropped. |
| `Visualize.IR.Path.transform/2` | Applies `fn {x, y} -> {x', y'} end` to every coordinate pair. Absolute end and control points are mapped directly; relative deltas are mapped as if they were points, and `H`/`V` are mapped as `{x, 0}` / `{0, y}` keeping one axis. The function MUST therefore be linear (no translation) when the path contains relative or single-axis commands; `:Z` and arc radii/flags are untouched. |
| `Visualize.IR.Path.to_string/1` | The SVG `d` string: commands concatenated with no separators, coordinates comma-separated, e.g. `"M10,20L100,200Z"`. Integers print as integers; floats print with at most four decimals, trailing zeros and a trailing point removed, never in exponent notation. |

`to_string/1` is the canonical `d` serialisation; `Visualize.Backend.SVG.path_data/1` MUST produce the same string for the same path (D-12). `Visualize.IR.Path` implements `String.Chars` (defined alongside `Visualize.SVG.Path`).

### 2.3 `Visualize.IR.Transform`

A transform is `%Visualize.IR.Transform{operations}`, an ordered list applied left to right as SVG does: `{:translate, x, y}`, `{:rotate, angle}`, `{:rotate, angle, cx, cy}`, `{:scale, sx, sy}`, `{:skew_x, angle}`, `{:skew_y, angle}`, `{:matrix, a, b, c, d, e, f}`. Angles are degrees.

| Function | Contract |
|---|---|
| `Visualize.IR.Transform.new/0` | An empty transform. |
| `Visualize.IR.Transform.translate/2` | A new transform with a single translate. |
| `Visualize.IR.Transform.translate/3` | Appends a translate to the given transform. |
| `Visualize.IR.Transform.rotate/1` | A new transform with a single rotate. |
| `Visualize.IR.Transform.rotate/2` | Appends a rotate about the origin. |
| `Visualize.IR.Transform.rotate/4` | Appends a rotate about `{cx, cy}`. |
| `Visualize.IR.Transform.scale/1` | A new transform with a single uniform scale `{:scale, s, s}`. |
| `Visualize.IR.Transform.scale/2` | Two numbers: a new transform with `{:scale, sx, sy}`. A transform and one number: appends a uniform scale to it (D-1). |
| `Visualize.IR.Transform.scale/3` | Appends `{:scale, sx, sy}`. |
| `Visualize.IR.Transform.skew_x/2` | Appends `{:skew_x, angle}`. |
| `Visualize.IR.Transform.skew_y/2` | Appends `{:skew_y, angle}`. |
| `Visualize.IR.Transform.matrix/7` | Appends `{:matrix, a, b, c, d, e, f}` for the matrix `[a c e; b d f; 0 0 1]`. |
| `Visualize.IR.Transform.empty?/1` | `true` iff there are no operations. |
| `Visualize.IR.Transform.concat/2` | The first transform's operations followed by the second's. |
| `Visualize.IR.Transform.to_string/1` | The SVG `transform` attribute: operations space-separated, e.g. `"translate(100,50) rotate(45) scale(2)"`. A scale with equal factors prints the single-argument form. Numbers format as in `Visualize.IR.Path.to_string/1`. |

## 3. The backend behaviour

### 3.1 Callbacks

`Visualize.Backend` is a behaviour. An implementation MUST define:

- `path_data(Visualize.IR.Path.t()) :: String.t() | [tuple()]` — the backend's native path data (the `d` string for SVG; a list of drawing commands for Canvas).
- `render_path(Visualize.IR.Path.t(), keyword()) :: output` — a rendered path; options MAY include `:style`.
- `render_element(Visualize.IR.Element.t(), keyword()) :: output` — a rendered element tree.
- `render_scene([Visualize.IR.Element.t()], keyword()) :: output` — a rendered list of elements; the built-in backends wrap the result with `wrap_root/2` unless `wrap: false`.

and MAY define `wrap_root(output, keyword()) :: output`, which wraps content in a root container (`<svg>` for SVG; canvas setup for Canvas) using options `:width` (default 800), `:height` (default 600) and `:view_box`. `output` is an iolist, string, map or command list as the backend chooses. The callback implementations on `Visualize.Backend.SVG` and `Visualize.Backend.Canvas` are specified in [09-rendering-backends](09-rendering-backends.md).

### 3.2 Resolution and configuration

| Function | Contract |
|---|---|
| `Visualize.Backend.default/0` | The module from `config :visualize, default_backend:` resolved through `resolve/1`; `Visualize.Backend.SVG` when unset. |
| `Visualize.Backend.resolve/1` | `nil` → `default/0`; `:svg` → `Visualize.Backend.SVG`; `:canvas` → `Visualize.Backend.Canvas`; any other atom is returned as a module unchanged. |

`config :visualize, default_backend: value` accepts the same values as `resolve/1`. There is deliberately no per-process override (D-2): the backend is either the `:backend` option at the call site or the application configuration.

## 4. `Visualize.Render`

`Visualize.Render` dispatches a renderable — a `Visualize.IR.Path`, a `Visualize.IR.Element`, or a list of elements — to `render_path/2`, `render_element/2` or `render_scene/2` respectively. Every function takes an options keyword list; `:backend` (`:svg`, `:canvas`, or a module) selects the backend and all other options pass through to it.

| Function | Contract |
|---|---|
| `Visualize.Render.render/1` | As `render/2` with the default backend. |
| `Visualize.Render.render/2` | Renders to the backend's native output (an iolist for the built-in backends). |
| `Visualize.Render.to_string/1` | As `to_string/2` with the default backend. |
| `Visualize.Render.to_string/2` | `render/2` converted with `IO.iodata_to_binary/1`. |
| `Visualize.Render.to_svg/1` | As `to_svg/2`. |
| `Visualize.Render.to_svg/2` | `render/2` with `backend: :svg` forced. |
| `Visualize.Render.to_svg_string/1` | As `to_svg_string/2`. |
| `Visualize.Render.to_svg_string/2` | `to_string/2` with `backend: :svg` forced. |
| `Visualize.Render.to_canvas/1` | As `to_canvas/2`. |
| `Visualize.Render.to_canvas/2` | `render/2` with `backend: :canvas` forced. |
| `Visualize.Render.to_canvas_string/1` | As `to_canvas_string/2`. |
| `Visualize.Render.to_canvas_string/2` | `to_string/2` with `backend: :canvas` forced. |
| `Visualize.Render.path_data/1` | As `path_data/2` with the default backend. |
| `Visualize.Render.path_data/2` | The selected backend's `path_data/1` for the path. |

## 5. The SVG element layer

`Visualize.SVG.Element` predates the IR and remains the HEEx-facing struct: `%Visualize.SVG.Element{tag, attrs, children, content}` mirrors an SVG element one-to-one, with `tag` an SVG tag atom and `attrs` a map rendered as attributes. It implements `String.Chars` and, when Phoenix is loaded, `Phoenix.HTML.Safe` via `Visualize.SVG.Renderer.render/1`, so it interpolates into a template as an iolist without escaping. `from_ir/1` is the bridge from the IR: the scene graph is built with `Visualize.IR.Element`, converted once, and embedded.

### 5.1 `Visualize.SVG.Element`

`from_ir/1` maps element types to tags (`:group` → `:g`, `:root` → `:svg`, `:clip_path` → `:clipPath`, `:linear_gradient` → `:linearGradient`, `:radial_gradient` → `:radialGradient`, others unchanged), copies `attrs`, adds `d` from the path via `Visualize.IR.Path.to_string/1`, adds `transform` via `Visualize.IR.Transform.to_string/1`, converts every style key to its hyphenated SVG attribute name (`:stroke_width` → `:"stroke-width"` and so on) and every style atom value to its SVG keyword (`:none` → `"none"`, `:current_color` → `"currentColor"`, `:start`, `:middle`, `:end`, `:butt`, `:round`, `:square`, `:miter`, `:bevel`, `:bold`). Style attributes overwrite geometric attrs of the same name. A `:root` element's `view_box` attr MUST render as `viewBox` (D-11). Conversion is recursive over children.

| Function | Contract |
|---|---|
| `Visualize.SVG.Element.new/1` | As `new/2` with empty attrs. |
| `Visualize.SVG.Element.new/2` | An element with the given tag and attrs map, no children, no content. |
| `Visualize.SVG.Element.attrs/2` | Merges a map or keyword list of attrs over the existing attrs. |
| `Visualize.SVG.Element.append/2` | Appends an `SVG.Element`, an `IR.Element` (converted with `from_ir/1`), or a list mixing both. |
| `Visualize.SVG.Element.from_ir/1` | Converts an `IR.Element` tree as described above. |
| `Visualize.SVG.Element.content/2` | Sets the text content. |
| `Visualize.SVG.Element.svg/0` | As `svg/1` with no attrs. |
| `Visualize.SVG.Element.svg/1` | An `:svg` element with `xmlns="http://www.w3.org/2000/svg"` merged under the given attrs. |
| `Visualize.SVG.Element.g/0` | As `g/1` with no attrs. |
| `Visualize.SVG.Element.g/1` | A `:g` element. |
| `Visualize.SVG.Element.rect/0` | As `rect/1` with no attrs. |
| `Visualize.SVG.Element.rect/1` | A `:rect` element. |
| `Visualize.SVG.Element.circle/0` | As `circle/1` with no attrs. |
| `Visualize.SVG.Element.circle/1` | A `:circle` element. |
| `Visualize.SVG.Element.ellipse/0` | As `ellipse/1` with no attrs. |
| `Visualize.SVG.Element.ellipse/1` | An `:ellipse` element. |
| `Visualize.SVG.Element.line/0` | As `line/1` with no attrs. |
| `Visualize.SVG.Element.line/1` | A `:line` element. |
| `Visualize.SVG.Element.polyline/0` | As `polyline/1` with no attrs. |
| `Visualize.SVG.Element.polyline/1` | A `:polyline` element. |
| `Visualize.SVG.Element.polygon/0` | As `polygon/1` with no attrs. |
| `Visualize.SVG.Element.polygon/1` | A `:polygon` element. |
| `Visualize.SVG.Element.path/0` | As `path/1` with no attrs. |
| `Visualize.SVG.Element.path/1` | A `:path` element. |
| `Visualize.SVG.Element.text/0` | As `text/1` with no attrs. |
| `Visualize.SVG.Element.text/1` | A `:text` element. |
| `Visualize.SVG.Element.tspan/0` | As `tspan/1` with no attrs. |
| `Visualize.SVG.Element.tspan/1` | A `:tspan` element. |
| `Visualize.SVG.Element.defs/0` | As `defs/1` with no attrs. |
| `Visualize.SVG.Element.defs/1` | A `:defs` element. |
| `Visualize.SVG.Element.clipPath/0` | As `clipPath/1` with no attrs. |
| `Visualize.SVG.Element.clipPath/1` | A `:clipPath` element. |
| `Visualize.SVG.Element.linearGradient/0` | As `linearGradient/1` with no attrs. |
| `Visualize.SVG.Element.linearGradient/1` | A `:linearGradient` element. |
| `Visualize.SVG.Element.radialGradient/0` | As `radialGradient/1` with no attrs. |
| `Visualize.SVG.Element.radialGradient/1` | A `:radialGradient` element. |
| `Visualize.SVG.Element.stop/0` | As `stop/1` with no attrs. |
| `Visualize.SVG.Element.stop/1` | A `:stop` element. |
| `Visualize.SVG.Element.title/0` | As `title/1` with no attrs. |
| `Visualize.SVG.Element.title/1` | A `:title` element. |

Every constructor accepts attrs as a map or keyword list. The camel-case names (`clipPath`, `linearGradient`, `radialGradient`) are deliberate: they are the SVG tag names.

### 5.2 `Visualize.SVG`

The fluent builder over `Visualize.SVG.Element`. Attrs are accepted as keyword lists or maps.

| Function | Contract |
|---|---|
| `Visualize.SVG.new/0` | As `new/1` with no attrs. |
| `Visualize.SVG.new/1` | A root `:svg` element with `xmlns` and the given attrs. |
| `Visualize.SVG.append/2` | Appends an `SVG.Element` child; or, when the second argument is a tag atom, as `append/3` with no attrs. |
| `Visualize.SVG.append/3` | Creates `Element.new(tag, attrs)` and appends it. |
| `Visualize.SVG.append_all/2` | Appends each element of the list in order. |
| `Visualize.SVG.group/0` | As `group/1` with no attrs. |
| `Visualize.SVG.group/1` | A `:g` element. |
| `Visualize.SVG.translate/3` | A `:g` with `transform="translate(x,y)"` containing the given element or elements. |
| `Visualize.SVG.render/1` | `Visualize.SVG.Renderer.render/1`: the tree as an iolist. |
| `Visualize.SVG.to_string/1` | `Visualize.SVG.Renderer.render_to_string/1`. |
| `Visualize.SVG.rect/0` | As `rect/1` with no attrs. |
| `Visualize.SVG.rect/1` | A `:rect` element. |
| `Visualize.SVG.circle/0` | As `circle/1` with no attrs. |
| `Visualize.SVG.circle/1` | A `:circle` element. |
| `Visualize.SVG.line/0` | As `line/1` with no attrs. |
| `Visualize.SVG.line/1` | A `:line` element. |
| `Visualize.SVG.path/0` | As `path/1` with no attrs. |
| `Visualize.SVG.path/1` | A `:path` element. |
| `Visualize.SVG.text/1` | As `text/2` with no attrs. |
| `Visualize.SVG.text/2` | A `:text` element with the given content and attrs. |
| `Visualize.SVG.polyline/0` | As `polyline/1` with no attrs. |
| `Visualize.SVG.polyline/1` | A `:polyline` element. |
| `Visualize.SVG.polygon/0` | As `polygon/1` with no attrs. |
| `Visualize.SVG.polygon/1` | A `:polygon` element. |

### 5.3 `Visualize.SVG.Path`

A compatibility façade: every builder delegates to `Visualize.IR.Path` and operates on `Visualize.IR.Path` structs (there is no separate `SVG.Path` struct). New code SHOULD use `Visualize.IR.Path` directly.

| Function | Contract |
|---|---|
| `Visualize.SVG.Path.new/0` | Delegates to `Visualize.IR.Path.new/0`. |
| `Visualize.SVG.Path.move_to/3` | Delegates to `Visualize.IR.Path.move_to/3`. |
| `Visualize.SVG.Path.move_to_rel/3` | Delegates to `Visualize.IR.Path.move_to_rel/3`. |
| `Visualize.SVG.Path.line_to/3` | Delegates to `Visualize.IR.Path.line_to/3`. |
| `Visualize.SVG.Path.line_to_rel/3` | Delegates to `Visualize.IR.Path.line_to_rel/3`. |
| `Visualize.SVG.Path.horizontal_to/2` | Delegates to `Visualize.IR.Path.horizontal_to/2`. |
| `Visualize.SVG.Path.horizontal_to_rel/2` | Delegates to `Visualize.IR.Path.horizontal_to_rel/2`. |
| `Visualize.SVG.Path.vertical_to/2` | Delegates to `Visualize.IR.Path.vertical_to/2`. |
| `Visualize.SVG.Path.vertical_to_rel/2` | Delegates to `Visualize.IR.Path.vertical_to_rel/2`. |
| `Visualize.SVG.Path.curve_to/7` | Delegates to `Visualize.IR.Path.curve_to/7`. |
| `Visualize.SVG.Path.curve_to_rel/7` | Delegates to `Visualize.IR.Path.curve_to_rel/7`. |
| `Visualize.SVG.Path.smooth_curve_to/5` | Delegates to `Visualize.IR.Path.smooth_curve_to/5`. |
| `Visualize.SVG.Path.smooth_curve_to_rel/5` | Delegates to `Visualize.IR.Path.smooth_curve_to_rel/5`. |
| `Visualize.SVG.Path.quad_to/5` | Delegates to `Visualize.IR.Path.quad_to/5`. |
| `Visualize.SVG.Path.quad_to_rel/5` | Delegates to `Visualize.IR.Path.quad_to_rel/5`. |
| `Visualize.SVG.Path.smooth_quad_to/3` | Delegates to `Visualize.IR.Path.smooth_quad_to/3`. |
| `Visualize.SVG.Path.smooth_quad_to_rel/3` | Delegates to `Visualize.IR.Path.smooth_quad_to_rel/3`. |
| `Visualize.SVG.Path.arc_to/8` | Delegates to `Visualize.IR.Path.arc_to/8`. |
| `Visualize.SVG.Path.arc_to_rel/8` | Delegates to `Visualize.IR.Path.arc_to_rel/8`. |
| `Visualize.SVG.Path.close/1` | Delegates to `Visualize.IR.Path.close/1`. |
| `Visualize.SVG.Path.empty?/1` | Delegates to `Visualize.IR.Path.empty?/1`. |
| `Visualize.SVG.Path.command_count/1` | Delegates to `Visualize.IR.Path.command_count/1`. |
| `Visualize.SVG.Path.concat/1` | Delegates to `Visualize.IR.Path.concat/1`. |
| `Visualize.SVG.Path.append/2` | Delegates to `Visualize.IR.Path.append/2`. |
| `Visualize.SVG.Path.transform/2` | Delegates to `Visualize.IR.Path.transform/2`. |
| `Visualize.SVG.Path.to_string/1` | The `d` string via `Visualize.Backend.SVG.path_data/1`; MUST equal `Visualize.IR.Path.to_string/1` (D-12). |

### 5.4 `Visualize.SVG.Renderer`

Serialises an `SVG.Element` tree. Attributes are emitted sorted by name, each key's underscores replaced by hyphens, values escaped (`&`, `"`, `<`, `>`); text content is escaped (`&`, `<`, `>`); child-less, content-less `circle`, `ellipse`, `line`, `path`, `polygon`, `polyline`, `rect`, `image` and `use` elements are self-closing. The iolist form is what `Phoenix.HTML.Safe` returns.

| Function | Contract |
|---|---|
| `Visualize.SVG.Renderer.render/1` | The element tree as an iolist. |
| `Visualize.SVG.Renderer.render_to_string/1` | `render/1` converted to a binary. |
