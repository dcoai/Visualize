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

An element is `%Visualize.IR.Element{type, attrs, style, transform, children, content, path, clip}`. `clip` is `nil` or `%{shape: element, keep: :inside | :outside}`: the element is drawn only where the shape is (`:inside`) or only where it is not (`:outside`), the shape being a `:path`, `:rect`, `:circle`, `:ellipse` or `:polygon` element whose style is ignored — how a stroke is kept inside or outside an edge (spec/14 §5.6). A backend that can clip MUST honour it (spec/09 §2.3, §3.3); one that cannot draws the element unclipped and says so. `type` MUST be one of `:path`, `:rect`, `:circle`, `:ellipse`, `:line`, `:polyline`, `:polygon`, `:text`, `:group`, `:image`, `:defs`, `:clip_path`, `:linear_gradient`, `:radial_gradient`, `:pattern`, `:stop`, `:filter`, `:fe_drop_shadow`, `:fe_gaussian_blur`, `:tspan`, `:root`, `:title`, `:desc`, `:style`. `attrs` is a map of geometric attributes; `style` is a map whose recognised keys are `:fill`, `:stroke`, `:stroke_width`, `:stroke_linecap` (`:butt | :round | :square`), `:stroke_linejoin` (`:miter | :round | :bevel`), `:stroke_dasharray`, `:opacity`, `:fill_opacity`, `:stroke_opacity`, `:font_size`, `:font_family`, `:font_weight`, `:font_style`, `:text_anchor` (`:start | :middle | :end`), `:dominant_baseline`, `:class`, `:blend` (a `mix-blend-mode` word), `:effect` (`:none | :shadow | :blur`) with `:effect_radius`; `:fill` and `:stroke` accept a string, `:none`, `:current_color` or a `Visualize.IR.Paint` (below). Gradient stops additionally use `:stop_color` and `:stop_opacity`. Backends MUST pass unrecognised style keys through unchanged. Constructors with a default `style` argument default it to `%{}`.

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
| `Visualize.IR.Element.tspan/2` | `tspan(content, attrs)`: a `:tspan` — one line of a `:text`, a child of it — with the given attrs (`x`, `dy`). A `:text` with `:tspan` children and no content is a text of several lines (spec/14 §7.1). |
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
| `Visualize.IR.Element.filter/2` | `filter(id, children)`: a `:filter` with attr `id` and the given primitives. |
| `Visualize.IR.Element.drop_shadow/3` | `drop_shadow(dx, dy, radius)`: a `:fe_drop_shadow` with attrs `dx`, `dy`, `std_deviation` and `flood_opacity` 0.35. |
| `Visualize.IR.Element.gaussian_blur/1` | `gaussian_blur(radius)`: a `:fe_gaussian_blur` with attr `std_deviation`. |
| `Visualize.IR.Element.title/1` | A `:title` with the given text as content: the accessible name of the element it is the first child of. |
| `Visualize.IR.Element.desc/1` | A `:desc` with the given text as content: the accessible description. |
| `Visualize.IR.Element.stylesheet/1` | A `:style` with the given stylesheet as content, which only the SVG backend writes: a root's automatic dark mode ([08-utilities](08-utilities.md) §7.3, #668). |
| `Visualize.IR.Element.root/2` | As `root/3` with no options. |
| `Visualize.IR.Element.root/3` | A `:root` with attrs `width`, `height`, `view_box` (default `"0 0 #{width} #{height}"`) and children from `:children`, plus the responsive options of D-54: `:preserve_aspect_ratio` sets the attr of that name (rendered `preserveAspectRatio`, spec/09 §2.4), absent by default; `responsive: true` sets it to `"xMidYMid meet"` unless given and adds `style: "width:100%;height:auto"`, so the `<svg>` keeps `width` and `height` as its intrinsic size and aspect ratio but fills the width of its container. Every root carries `role: "img"` (D-56). The accessibility options: `:title` and `:description` prepend a `title/1` and a `desc/1` child, each with an `id`; `aria_labelledby` (rendered `aria-labelledby`) is the title's id and `aria_describedby` the description's (D-142, [14-declarative-chart](14-declarative-chart.md) §21.2), and a description with no title is named by `aria_labelledby` alone; `hidden: true` sets `aria_hidden: "true"`, a layer of a picture another element names (§21.4); `:id` is the prefix of the child ids (`<id>-title`, `<id>-desc`) and is also set on the root, and defaults to `vis-` followed by the lower-case base-36 `:erlang.phash2/1` of `{title, description}`, so equal charts share ids and different ones do not; with neither text no child, no `aria_labelledby` and no `id` are added. |
| `Visualize.IR.Element.put_attr/3` | The element with one attribute set: an atom key, or a string for an attribute the IR has no name for, such as `data-node` (spec/14 §4.7). |
| `Visualize.IR.Element.append/2` | Appends one element or a list of elements to `children`. |
| `Visualize.IR.Element.prepend/2` | Prepends one element or a list of elements to `children`. |
| `Visualize.IR.Element.set_transform/2` | Replaces the element's transform. |
| `Visualize.IR.Element.translate/3` | Adds a translate operation: creates the transform when `nil`, otherwise appends to it. |
| `Visualize.IR.Element.set_style/2` | Merges the given style over the existing style. |
| `Visualize.IR.Element.clip/3` | `clip(element, shape, keep)`: the element with `clip` set to the shape and `:inside` or `:outside`. |
| `Visualize.IR.Element.set_attrs/2` | Merges the given attrs over the existing attrs. |
| `Visualize.IR.Element.datum/2` | Writes the datum attributes of spec/10 §12.2 over the element's attrs, under string keys: `"data-datum"`, the field names space-separated in order, and `"data-datum-<field>"` per field with `_` as `-` and `to_string/1` of the value, a `nil` value omitted; the fields are a map (written in `Enum.sort/1` order) or a keyword list (in its order). What `TooltipHook` reads (D-75). |
| `Visualize.IR.Element.set_content/2` | Sets the text content. |
| `Visualize.IR.Element.translate_group/3` | Wraps an element or list of elements in a `:group` carrying `Transform.translate(x, y)`. |

`Visualize.IR.Element` implements `String.Chars` (renders through `Visualize.Backend.SVG`) and, when `Phoenix.HTML.Safe` is loaded, `Phoenix.HTML.Safe` (D-7).

**A paint** (#652, D-175) is `%Visualize.IR.Paint{id, type, geometry, stops, color, background}`, the value of a `:fill` or a `:stroke` that is not one colour: what a declarative chart's frame writes for a gradient ([14-declarative-chart](14-declarative-chart.md) §3.2), and what any producer may write. `id` is the id of the definition an SVG document holds for it — the backend writes `url(#id)` and the producer puts the definition in a `:defs` (`Visualize.IR.Paint.definition/1` builds it); `type` is `:linear`, `:radial` or `:hatch`; a gradient's `geometry` is in the units of the element's bounding box, `0` to `1` across it (SVG's `objectBoundingBox`): `%{x1, y1, x2, y2}` for a linear gradient, the line it runs along, and `%{cx, cy, r}` for a radial one, centred at its focus; `stops` is a list of `{at, colour, opacity}` in `at` order, `at` from `0` to `1` and each colour a string a backend reads (a literal for a canvas). A **hatch** (#673) has no stops: its `geometry` is `%{pattern, angle, spacing, width}` in the user units of the element it fills — `:lines`, `:crosshatch` or `:dots`, the lines' direction in degrees clockwise from horizontal, the period and the line width or dot radius — and `color` and `background` are its colours, `background` `nil` for none. The two colour fields are `nil` on a gradient. A canvas builds the paint over the element's tight bounding box (spec/09 §3.3.3, §4.3.12).

| Function | Contract |
|---|---|
| `Visualize.IR.Paint.url/1` | `"url(#<id>)"`, what SVG writes for the paint. |
| `Visualize.IR.Paint.definition/1` | The `:linear_gradient` or `:radial_gradient` element under the paint's id, its geometry as `x1 y1 x2 y2` or `cx cy r fx fy` with `gradientUnits="objectBoundingBox"`, and one `:stop` per stop; for a hatch, the `:pattern` element of [14-declarative-chart](14-declarative-chart.md) §2.7 — `patternUnits="userSpaceOnUse"`, the tile `spacing` square, `patternTransform="rotate(angle)"` — holding its background rectangle and its lines or dot. |
| `Visualize.IR.Paint.bounds/1` | The tight bounding box `{x, y, width, height}` of a `:path`, `:rect`, `:circle`, `:ellipse`, `:line`, `:polyline` or `:polygon` element in its own user units — a path's curves and arcs by their extremes, not their control points — or `nil` for any other type or an empty shape. |

### 2.2 `Visualize.IR.Path`

A path is `%Visualize.IR.Path{commands, metadata}`; `metadata` is a free map for producers and is not serialised. Commands are tuples tagged with the SVG command letter — absolute upper-case, relative lower-case: `{:M|:m, x, y}`, `{:L|:l, x, y}`, `{:H|:h, x}`, `{:V|:v, y}`, `{:C|:c, x1, y1, x2, y2, x, y}`, `{:S|:s, x2, y2, x, y}`, `{:Q|:q, x1, y1, x, y}`, `{:T|:t, x, y}`, `{:A|:a, rx, ry, rotation, large_arc, sweep, x, y}` and the bare atom `:Z`. `large_arc` and `sweep` MUST be `0` or `1`. Builders append in call order. **A path is built in time proportional to its commands** (#414): the appenders above put one command at the end of a list, which is the cost of the list, so a builder that draws one command per datum makes its commands in order and hands them to `from_commands/1` at the end — a path of 50,000 commands took six seconds to append one at a time and the drawing of a large chart was quadratic in its points.

| Function | Contract |
|---|---|
| `Visualize.IR.Path.new/0` | An empty path. |
| `Visualize.IR.Path.from_commands/1` | A path of the commands given, in the order given: what a builder that draws per datum ends with, so building costs the list and not a square of it (#414). |
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
| `Visualize.IR.Path.expand_smooth/1` | Rewrites `S`/`s`/`T`/`t` as `C`/`c`/`Q`/`q` (D-36): the first control point is the reflection about the current point of the previous command's last control point when that command was a cubic (for `S`/`s`) or a quadratic (for `T`/`t`), and the current point otherwise; a relative result keeps its deltas relative. Every other command is unchanged. |
| `Visualize.IR.Path.absolute/1` | Every command as an absolute `M`, `L`, `C`, `Q`, `A` or `Z`: relative commands resolved against the current point (a leading `m` is absolute), `H`/`V` as `L`, smooth curves expanded as `expand_smooth/1` does, arcs keeping radii, rotation and flags. Draws the same figure; this is what a target without relative commands replays. |
| `Visualize.IR.Path.transform/2` | Applies an affine matrix `{a, b, c, d, e, f}` (`t:Visualize.IR.Transform.matrix/0`), or a `Visualize.IR.Transform` folded with `Visualize.IR.Transform.to_matrix/1`, to the path (D-35). Absolute end and control points get the full map `{a·x + c·y + e, b·x + d·y + f}`; relative deltas get the linear part only. The current point is tracked through every command (`:Z` returns to the subpath start; a leading `m` is absolute, as SVG reads it): `H`/`h` stay single-axis when `b = 0` and `V`/`v` when `c = 0`, otherwise they become `L`/`l` to the mapped point. An arc's end point is mapped; its radii and rotation are those of the exact image of its ellipse under the linear part (the singular values and left rotation of the 2×2 product), in canonical form `rx ≥ ry`, rotation in `[0, 180)`, a circle keeping its given rotation; the sweep flag flips when the determinant is negative; `large_arc` is untouched. |
| `Visualize.IR.Path.to_string/1` | The SVG `d` string: commands concatenated with no separators, coordinates comma-separated, e.g. `"M10,20L100,200Z"`; an arc prints `Arx,ry,rot,large,sweep,x,y` with the two flags verbatim. Every number goes through `format_number/1`. |
| `Visualize.IR.Path.format_number/1` | The one number formatter of every serialiser (D-12, D-32): an integer prints as-is; a float prints with at most four decimals, trailing zeros and a trailing point removed, never in exponent notation, and never as `-0` (a zero that rounds negative prints `0`). |

`to_string/1` is the only `d` serialisation: `Visualize.Backend.SVG.path_data/1`, `Visualize.SVG.Path.to_string/1` and the `String.Chars` implementation for `Visualize.IR.Path` (defined alongside `Visualize.SVG.Path`) delegate to it (D-12, D-34).

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
| `Visualize.IR.Transform.to_matrix/1` | The operations folded into one affine matrix `{a, b, c, d, e, f}` for `[a c e; b d f; 0 0 1]`, composed as SVG composes the attribute string: `M = Op₁ · Op₂ · … · Opₙ`, so the last operation applies to a point first. `translate` is `[1 0 tx; 0 1 ty]`, `scale` `[sx 0 0; 0 sy 0]`, `rotate(a)` `[cos −sin 0; sin cos 0]`, `rotate(a, cx, cy)` is `translate(cx, cy) rotate(a) translate(−cx, −cy)`, `skew_x(a)` `[1 tan 0; 0 1 0]`, `skew_y(a)` `[1 0 0; tan 1 0]`, `matrix` as given; angles in degrees. An empty transform is the identity. |
| `Visualize.IR.Transform.multiply/2` | The product `m1 · m2` of two matrices: applying the result is applying `m2` first, then `m1`. |
| `Visualize.IR.Transform.apply_matrix/2` | `apply_matrix({a, b, c, d, e, f}, {x, y})` is `{a·x + c·y + e, b·x + d·y + f}`. |
| `Visualize.IR.Transform.to_string/1` | The SVG `transform` attribute: operations space-separated, e.g. `"translate(100,50) rotate(45) scale(2)"`. A scale with equal factors prints the single-argument form. Numbers format with `Visualize.IR.Path.format_number/1`, so `-0` never prints. This is the only transform serialisation; `Visualize.Backend.SVG` emits it (D-34). |

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
| `Visualize.Render.to_png/1` | As `to_png/2` with no options. |
| `Visualize.Render.to_png/2` | A root `Visualize.IR.Element`, or an SVG document as a binary, rasterised to a PNG by the resvg command-line tool, run as a port: `{:ok, png, warnings}`, the warnings resvg printed (`{:missing_family, list}` for each font-family list no font resolves, `{:rasterizer, line}` for any other line, `[]` when there are none), `{:error, :no_rasterizer}` with no resvg binary configured or on the `PATH`, `{:error, {:rasterizer_version, found, required}}` for a binary older than the supported minimum, `{:error, :css_references}` when the SVG holds a `var(--` reference, `{:error, :timeout}` when the render outlasts `:timeout`, `{:error, {:rasterizer, message}}` when resvg refuses the document. Options `:scale`, `:background`, `:timeout`, and the font options `:font_dirs`, `:system_fonts`, `:generic_families` and `:font_family`; [09-rendering-backends](09-rendering-backends.md) §9. |
| `Visualize.Render.to_png!/1` | As `to_png!/2` with no options. |
| `Visualize.Render.to_png!/2` | As `to_png/2`, returning the PNG binary of `{:ok, png, []}` and raising `RuntimeError` on the `{:error, _}` branch and when there is a warning: a complete picture or none. |

`to_png/2` is the one function of the module that produces no backend output: it renders an IR root with `to_svg_string/2` and hands the SVG to the rasteriser of [09-rendering-backends](09-rendering-backends.md) §9 (D-121). Its input is narrower than a renderable, because a PNG is a whole document: a `:root` element (`Visualize.IR.Element.root/3`, or `Visualize.Chart.generate/2` with `root: true`), or the SVG string such an element renders to (`Visualize.Chart.render/2` with `root: true`).

## 5. The SVG element layer

`Visualize.SVG.Element` predates the IR and remains the HEEx-facing struct: `%Visualize.SVG.Element{tag, attrs, children, content}` mirrors an SVG element one-to-one, with `tag` an SVG tag atom and `attrs` a map rendered as attributes. It implements `String.Chars` and, when Phoenix is loaded, `Phoenix.HTML.Safe` via `Visualize.SVG.Renderer.render/1`, so it interpolates into a template as an iolist without escaping. `from_ir/1` is the bridge from the IR: the scene graph is built with `Visualize.IR.Element`, converted once, and embedded.

### 5.1 `Visualize.SVG.Element`

`from_ir/1` maps element types to tags (`:group` → `:g`, `:root` → `:svg`, `:clip_path` → `:clipPath`, `:linear_gradient` → `:linearGradient`, `:radial_gradient` → `:radialGradient`, others unchanged), copies `attrs`, adds `d` from the path via `Visualize.IR.Path.to_string/1`, adds `transform` via `Visualize.IR.Transform.to_string/1`, converts every style key to its hyphenated SVG attribute name (`:stroke_width` → `:"stroke-width"` and so on) and every style atom value to its SVG keyword (`:none` → `"none"`, `:current_color` → `"currentColor"`, `:start`, `:middle`, `:end`, `:butt`, `:round`, `:square`, `:miter`, `:bevel`, `:bold`). Style attributes overwrite geometric attrs of the same name. A `:root` element gains `xmlns="http://www.w3.org/2000/svg"` and its `view_box` attr becomes the `viewBox` key (D-11, D-34); a `:polyline`/`:polygon` whose `points` is a list of `{x, y}` tuples has it formatted as `Visualize.Backend.SVG` formats points (spec/09 §2.6). Conversion is recursive over children. The result renders, through `Visualize.SVG.Renderer`, to exactly the markup `Visualize.Backend.SVG.render_element/1` emits for the same IR (D-34); `test/visualize/svg/bridge_test.exs` holds both to it.

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
| `Visualize.SVG.Path.to_string/1` | Delegates to `Visualize.IR.Path.to_string/1`, the one `d` serialisation (D-12). |

### 5.4 `Visualize.SVG.Renderer`

Serialises an `SVG.Element` tree. Attributes with a `nil` value are omitted; the rest are emitted sorted by their SVG name from `attribute_name/1`, values escaped (`&`, `"`, `<`, `>`); text content is escaped (`&`, `<`, `>`); child-less, content-less `circle`, `ellipse`, `line`, `path`, `polygon`, `polyline`, `rect`, `image`, `use`, `stop`, `feDropShadow` and `feGaussianBlur` elements are self-closing. The iolist form is what `Phoenix.HTML.Safe` returns. `Visualize.Backend.SVG` renders its tags, attributes and text through the same functions, so the two serialisers cannot drift (D-34).

| Function | Contract |
|---|---|
| `Visualize.SVG.Renderer.render/1` | The element tree as an iolist. |
| `Visualize.SVG.Renderer.render_to_string/1` | `render/1` converted to a binary. |
| `Visualize.SVG.Renderer.attribute_name/1` | The SVG attribute name for a key (D-11): a snake_case atom hyphenates (`:stroke_width` → `"stroke-width"`, `:clip_path` → `"clip-path"`) unless it is one of the camel-cased SVG attributes, which map to their spelling — `:view_box` → `"viewBox"`, `:preserve_aspect_ratio`, `:gradient_units`, `:gradient_transform`, `:pattern_units`, `:pattern_transform`, `:clip_path_units`, `:mask_units`, `:std_deviation` (`stdDeviation`), `:marker_width`, `:marker_height`, `:marker_units`, `:ref_x`, `:ref_y`, `:spread_method`, `:text_length`, `:length_adjust`; an atom already camel-cased (`:viewBox`) and a binary key pass through unchanged. |
