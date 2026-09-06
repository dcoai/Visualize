# Shapes and Curves

**Status:** Implemented

Shape generators turn data into geometry. `Visualize.Shape` is a facade over `Shape.Line`, `Shape.Area`, `Shape.Arc`, `Shape.Pie`, `Shape.Stack`, `Shape.Symbol`, the element-producing marks `Shape.Band`, `Shape.Rule`, and `Shape.XBand` (sections 11–13), and the composed mark `Shape.PercentileBand` (section 14); `Shape.Curve` supplies the point interpolators used by lines and areas; `Shape.LineNx` is an optional Nx-accelerated line path builder. Path-producing generators offer `generate_path/2`, returning a backend-neutral `Visualize.IR.Path`, and `generate/2`, returning that path serialised as an SVG `d` string. Layout generators (`Pie`, `Stack`) return data, not paths. All coordinates are in user units with the SVG convention (x right, y down); all angles are radians.

## 1. Common Model

### 1.1 Accessors

An accessor extracts a value from a datum. The accepted forms differ by module:

| Module | 1-arity function | atom (field, `Map.get(d, field)`) | number (constant) |
|---|---|---|---|
| `Line` (`x`, `y`) | yes | yes | yes |
| `Area` (`x`, `x0`, `x1`, `y`, `y0`, `y1`) | yes | yes | yes |
| `Arc` (radii, angles) | yes | yes | yes |
| `Pie` (`value`) | yes | yes (`Map.get(d, field, 0)`) | yes |
| `Stack` (`value`) | 2-arity only | no | no |
| `Symbol` (`type`, `size`) | yes | atom is the literal type | literal size |
| `Band` (`x0`, `x1`, `y`, `height`; `fill`) | yes | yes | yes (`fill`: a string constant) |
| `Rule` (`x`, `y0`, `y1`; `label`), `XBand` (`x0`, `x1`, `y0`, `y1`; `fill`, `label`) | yes | yes | yes (`fill`, `label`: a string constant) |
| `PercentileBand` (`x`, `median`; `inner`, `outer` as `{lo, hi}` pairs) | yes | yes | yes |

Atom accessors read a map key and return `nil` when absent (except `Pie`, which defaults to `0`); a `nil` coordinate fails arithmetic downstream. Callers SHOULD supply functions when data are not maps. A numeric constant is the accessor `fn _ -> n end`; `Line` accepts one since D-20.

### 1.2 `defined/2`

`Line.defined/2` and `Area.defined/2` take a 1-arity predicate. A datum for which it returns a falsy value **breaks** the path (d3-shape's `defined` semantics, D-18): the data are split into runs of consecutive defined data, each run is generated through the curve as its own subpath — for `Area`, its own closed ring — and the subpaths are concatenated in data order, so a gap is visible between them. A run of fewer than two points has no segment to draw and contributes nothing; data whose defined runs are all single points therefore produce an empty path. With no predicate the whole data list is one run.

### 1.3 `generate/2` versus `generate_path/2`

`generate_path/2` returns `%Visualize.IR.Path{commands: [...]}` with commands from `{:M, x, y}`, `{:L, x, y}`, `{:H, x}`, `{:V, y}`, `{:C, x1, y1, x2, y2, x, y}`, `{:A, rx, ry, rot, large_arc, sweep, x, y}`, `:Z`. `generate/2` is `generate_path/2` piped through `Visualize.Backend.SVG.path_data/1`; the result is the SVG path-data string. Code targeting a non-SVG backend MUST use `generate_path/2` and render through `Visualize.Render`.

Both `Line.generate_path/2` and `Area.generate_path/2` return an empty path (`Visualize.IR.Path.new/0`) when no defined run (1.2) has two or more points; a lone point yields no `M` command.

`Band.generate/2`, `Rule.generate/2`, and `XBand.generate/2` return a list of `Visualize.IR.Element`, one per datum, rather than a string: these marks carry per-datum style (a fill, a label) that a path cannot (D-26). The elements render through `Visualize.Render` like any other. `Band.generate_path/2` is the one path form among them, folding every rectangle into a single `IR.Path`.

`PercentileBand.generate/2` and `PercentileBand.generate_path/2` return a map of three paths (`outer`, `inner`, `median`), each in the form the corresponding `Line` or `Area` call would return, or `nil` for a band that is not set (D-28).

## 2. `Visualize.Shape` Facade

Facade setters dispatch on the struct type and fail to match (`FunctionClauseError`) for a generator that lacks the setting.

| Function | Contract |
|---|---|
| `Visualize.Shape.line/0` | `Shape.Line.new/0`. |
| `Visualize.Shape.area/0` | `Shape.Area.new/0`. |
| `Visualize.Shape.arc/0` | `Shape.Arc.new/0`. |
| `Visualize.Shape.pie/0` | `Shape.Pie.new/0`. |
| `Visualize.Shape.symbol/0` | `Shape.Symbol.new/0`. |
| `Visualize.Shape.stack/0` | `Shape.Stack.new/0`. |
| `Visualize.Shape.band/0` | `Shape.Band.new/0`. |
| `Visualize.Shape.rule/0` | `Shape.Rule.new/0`. |
| `Visualize.Shape.x_band/0` | `Shape.XBand.new/0`. |
| `Visualize.Shape.percentile_band/0` | `Shape.PercentileBand.new/0`. |
| `Visualize.Shape.x/2` | `Line.x/2`, `Area.x/2`, `Rule.x/2`, or `PercentileBand.x/2`. |
| `Visualize.Shape.y/2` | `Line.y/2`, `Area.y/2`, or `Band.y/2`. |
| `Visualize.Shape.x0/2` | `Area.x0/2`, `Band.x0/2`, or `XBand.x0/2`. |
| `Visualize.Shape.x1/2` | `Area.x1/2`, `Band.x1/2`, or `XBand.x1/2`. |
| `Visualize.Shape.y0/2` | `Area.y0/2`, `Rule.y0/2`, or `XBand.y0/2`. |
| `Visualize.Shape.y1/2` | `Area.y1/2`, `Rule.y1/2`, or `XBand.y1/2`. |
| `Visualize.Shape.height/2` | `Band.height/2`. |
| `Visualize.Shape.fill/2` | `Band.fill/2` or `XBand.fill/2`. |
| `Visualize.Shape.scale/2` | `Rule.scale/2` or `XBand.scale/2`. |
| `Visualize.Shape.label/2` | `Rule.label/2` or `XBand.label/2`. |
| `Visualize.Shape.median/2` | `PercentileBand.median/2`. |
| `Visualize.Shape.inner/2` | `PercentileBand.inner/2`. |
| `Visualize.Shape.outer/2` | `PercentileBand.outer/2`. |
| `Visualize.Shape.curve/2` | As `curve/3` with `[]` options. |
| `Visualize.Shape.curve/3` | `Line.curve/3`, `Area.curve/3`, or `PercentileBand.curve/3`. |
| `Visualize.Shape.defined/2` | `Line.defined/2`, `Area.defined/2`, or `PercentileBand.defined/2`. |
| `Visualize.Shape.value/2` | `Pie.value/2` or `Stack.value/2`. |
| `Visualize.Shape.keys/2` | `Stack.keys/2`. |
| `Visualize.Shape.order/2` | `Stack.order/2`. |
| `Visualize.Shape.offset/2` | `Stack.offset/2`. |
| `Visualize.Shape.inner_radius/2` | `Arc.inner_radius/2`. |
| `Visualize.Shape.outer_radius/2` | `Arc.outer_radius/2`. |
| `Visualize.Shape.corner_radius/2` | `Arc.corner_radius/2`. |
| `Visualize.Shape.pad_radius/2` | `Arc.pad_radius/2`. |
| `Visualize.Shape.start_angle/2` | `Arc.start_angle/2` or `Pie.start_angle/2`. |
| `Visualize.Shape.end_angle/2` | `Arc.end_angle/2` or `Pie.end_angle/2`. |
| `Visualize.Shape.pad_angle/2` | `Arc.pad_angle/2` or `Pie.pad_angle/2`. |
| `Visualize.Shape.sort/2` | `Pie.sort/2`. |
| `Visualize.Shape.sort_values/2` | `Pie.sort_values/2`. |
| `Visualize.Shape.type/2` | `Symbol.type/2`. |
| `Visualize.Shape.size/2` | `Symbol.size/2`. |
| `Visualize.Shape.generate/1` | As `generate/2` with `nil` data (meaningful for `Symbol` only). |
| `Visualize.Shape.generate/2` | Dispatches to the module's `generate/2`: SVG path string for `Line`, `Area`, `Arc`, `Symbol`; arc-datum list for `Pie`; series list for `Stack`; element list for `Band`, `Rule`, `XBand`; path map for `PercentileBand`. |
| `Visualize.Shape.generate_path/1` | As `generate_path/2` with `nil` data. |
| `Visualize.Shape.generate_path/2` | Dispatches to `generate_path/2` of `Line`, `Area`, `Arc`, `Symbol`, `Band`, or `PercentileBand`; `Pie`, `Stack`, `Rule`, and `XBand` are not accepted. |

Every setter of `Arc` and `Pie` is reachable through the facade; `Symbol.types/0` and `Arc.centroid/2` are not (D-21).

## 3. `Visualize.Shape.Line`

### 3.1 Struct

`%Visualize.Shape.Line{x: nil, y: nil, defined: nil, curve: :linear, curve_opts: []}`. `new/0` sets `x` to `elem(d, 0)` and `y` to `elem(d, 1)`, so tuple data `{x, y}` work without configuration.

### 3.2 Semantics

`generate_path/2` splits the data into defined runs (1.2), maps each run's data to `{x.(d), y.(d)}`, calls `Curve.generate(curve, points, curve_opts)` per run, and concatenates the commands; each run therefore starts with its own `M`.

### 3.3 Functions

| Function | Contract |
|---|---|
| `Visualize.Shape.Line.new/0` | Returns a line generator reading tuple elements 0 and 1. |
| `Visualize.Shape.Line.x/2` | Sets the x accessor: 1-arity function, atom field, or numeric constant. |
| `Visualize.Shape.Line.y/2` | Sets the y accessor: 1-arity function, atom field, or numeric constant. |
| `Visualize.Shape.Line.defined/2` | Sets the 1-arity defined predicate (1.2). |
| `Visualize.Shape.Line.curve/2` | As `curve/3` with `[]` options. |
| `Visualize.Shape.Line.curve/3` | Sets the curve type (section 5) and its option keyword list. |
| `Visualize.Shape.Line.generate/2` | Returns the SVG path-data string. |
| `Visualize.Shape.Line.generate_path/2` | Returns an `IR.Path`, one subpath per defined run; empty when no run has two points. |

## 4. `Visualize.Shape.Area`

### 4.1 Struct

`%Visualize.Shape.Area{x: nil, x0: nil, x1: nil, y: nil, y0: nil, y1: nil, defined: nil, curve: :linear, curve_opts: []}`. `new/0` sets `x` to `elem(d, 0)`, `y0` to the constant `0`, and `y1` to `elem(d, 1)`.

### 4.2 Semantics

Effective accessors are `x0 || x`, `x1 || x`, `y0 || y`, `y1 || y`. `x/2` sets `x`, `x0`, and `x1` together; `y/2` sets `y`, `y0`, and `y1` together. Setting `y/2` after `new/0` therefore makes the area zero-height; callers wanting a baseline MUST set `y0`/`y1` individually.

`generate_path/2`:

1. Splits the data into defined runs (1.2); each run of two or more points produces one closed ring by steps 2–4, and the rings are concatenated in data order. A run of one point produces nothing.
2. Per run, builds the top line `(x1, y1)` per datum, forward, and the bottom line `(x0, y0)` per datum, reversed.
3. Generates each line through `Curve.generate/3` with the same curve and options.
4. Concatenates: top commands, `{:L, bx, by}` to the bottom line's first point, the bottom commands without their leading `:M`, then `:Z`.

### 4.3 Functions

| Function | Contract |
|---|---|
| `Visualize.Shape.Area.new/0` | Returns an area generator with baseline `y0 = 0`. |
| `Visualize.Shape.Area.x/2` | Sets `x`, `x0`, and `x1` to the accessor (function, atom, or number). |
| `Visualize.Shape.Area.x0/2` | Sets the baseline-side x accessor. |
| `Visualize.Shape.Area.x1/2` | Sets the top-side x accessor. |
| `Visualize.Shape.Area.y/2` | Sets `y`, `y0`, and `y1` to the accessor. |
| `Visualize.Shape.Area.y0/2` | Sets the baseline y accessor. |
| `Visualize.Shape.Area.y1/2` | Sets the top y accessor. |
| `Visualize.Shape.Area.defined/2` | Sets the 1-arity defined predicate (1.2). |
| `Visualize.Shape.Area.curve/2` | As `curve/3` with `[]` options. |
| `Visualize.Shape.Area.curve/3` | Sets the curve type and options, applied to both edges. |
| `Visualize.Shape.Area.generate/2` | Returns the SVG path-data string of the closed area. |
| `Visualize.Shape.Area.generate_path/2` | Returns the closed `IR.Path` as in 4.2. |

## 5. `Visualize.Shape.Curve`

### 5.1 Curve Types and Options

`Curve.generate(type, points, opts)` accepts these atoms; `opts` is a keyword list read only by the curves shown.

| Type | Option keys | Default | Notes |
|---|---|---|---|
| `:linear` | — | — | `M` then `L` per point |
| `:step` | — | — | step at the midpoint (`t = 0.5`) |
| `:step_before` | — | — | step at the start (`t = 0`) |
| `:step_after` | — | — | step at the end (`t = 1`) |
| `:basis` | — | — | uniform B-spline approximation |
| `:cardinal` | `:tension` | `0` | cardinal spline; `tension = 1` collapses to linear |
| `:catmull_rom` | `:alpha` | `0.5` | parameterised Catmull-Rom (`0` uniform, `0.5` centripetal, `1` chordal) |
| `:monotone_x` | — | — | Fritsch-Carlson monotone cubic in x |
| `:monotone_y` | — | — | as `:monotone_x` with axes swapped |
| `:natural` | — | — | natural cubic spline (see 5.6) |

An unknown type fails to match. For every type, `[]` or a single point returns an empty path. `:basis`, `:cardinal`, `:catmull_rom`, `:monotone_x`, `:monotone_y`, and `:natural` fall back to `:linear` for two points.

### 5.2 Step Curves

`step(points, t)` emits `M x0,y0` and then, for each subsequent point `(x1, y1)`, with `x_prev` the previous datum's x and `x_pen` the pen's current x: `x_mid = x_prev + (x1 − x_prev) · t`; `H x_mid` **only when `x_mid ≠ x_pen`**; `V y1`. After the last point, `H x_last` unless the pen is already there. Consecutive horizontals therefore merge and the path never contains a zero-length horizontal segment; a vertical is emitted per point even when `y` is unchanged.

### 5.3 Basis

`M p0`; for each sliding window `[p0, p1, p2, p3]` (windows of four, stride one, partial windows discarded), `C ((2x0+x1)/3, (2y0+y1)/3), ((x0+2x1)/3, (y0+2y1)/3), ((x0+4x1+x2)/6, (y0+4y1+y2)/6)`; then a closing `C` from the penultimate point to the last point using the thirds of that segment. The curve starts and ends on the data endpoints.

### 5.4 Cardinal and Catmull-Rom

Both prepend a copy of the first point and append a copy of the last (phantom points), then slide windows of four `[p0, p1, p2, p3]` emitting one `C … p2` per window.

Cardinal with `k = (1 − tension) / 6`: control points `p1 + k·(p2 − p0)` and `p2 + k·(p1 − p3)`.

Catmull-Rom: segment lengths `d1 = |p1 − p0|`, `d2 = |p2 − p1|`, `d3 = |p3 − p2|`, each floored at `0.0001`; `t_i = d_i^alpha`; control points per the standard parameterised formula (`cp1 = (t1²·p2 − t2²·p0 + (2t1² + 3t1·t2 + t2²)·p1) / (3·t1·(t1 + t2))`, symmetrically for `cp2`).

### 5.5 Monotone

Secant slopes `m_i` between consecutive points (`0` when `dx = 0`). Interior tangents are the harmonic mean `2·m_{i−1}·m_i / (m_{i−1} + m_i)`, or `0` when the slopes differ in sign or either is zero; end tangents take the adjacent secant slope. Each tangent is then limited to `min(3, τ/m)·m` (zero when `τ/m < 0`). Segment `i` is `C (x0 + dx/3, y0 + τ0·dx/3), (x1 − dx/3, y1 − τ1·dx/3), (x1, y1)`. `:monotone_y` swaps the coordinates before tangent computation and swaps them back in the emitted commands. The final tangent is paired with a padding slope of `0` and is therefore always `0`.

### 5.6 Natural

The natural cubic spline — the C² interpolating cubic with zero second derivative at both ends — as d3-shape's `curveNatural` (D-19). For points `p0 … pn` and per axis, with `v_i` the coordinate of `p_i`, the first Bézier control coordinate `a_i` of each segment `i` (`0 ≤ i < n`) solves the tridiagonal system

```
2·a0 + a1                    = v0 + 2·v1
a_{i−1} + 4·a_i + a_{i+1}    = 4·v_i + 2·v_{i+1}      0 < i < n − 1
2·a_{n−2} + 7·a_{n−1}        = 8·v_{n−1} + v_n
```

by the Thomas algorithm (forward elimination, back substitution). The second control coordinate is `b_i = 2·v_{i+1} − a_{i+1}` for `i < n − 1` and `b_{n−1} = (v_n + a_{n−1}) / 2`. Segment `i` is `C a_i b_i p_{i+1}`, the x and y systems solved independently. Control points mirror across every interior knot, so the curve is C¹ there as well. The reference `d` string for the golden point set is in `test/support/curve_golden.txt`; the three-point case `(0,0) (1,1) (2,0)` gives `M0,0 C1/3,1/2 2/3,1 1,1 C4/3,1 5/3,1/2 2,0`.

### 5.7 Functions

| Function | Contract |
|---|---|
| `Visualize.Shape.Curve.generate/2` | As `generate/3` with `[]` options. |
| `Visualize.Shape.Curve.generate/3` | Dispatches by curve type as in 5.1; returns an `IR.Path`. |
| `Visualize.Shape.Curve.linear/1` | `M` first point, `L` each subsequent point. |
| `Visualize.Shape.Curve.step/2` | Step path with position `t ∈ [0, 1]` as in 5.2. |
| `Visualize.Shape.Curve.basis/1` | B-spline path as in 5.3. |
| `Visualize.Shape.Curve.cardinal/2` | Cardinal spline with the given tension. |
| `Visualize.Shape.Curve.catmull_rom/2` | Catmull-Rom spline with the given alpha. |
| `Visualize.Shape.Curve.monotone_x/1` | Monotone cubic in x. |
| `Visualize.Shape.Curve.monotone_y/1` | Monotone cubic in y. |
| `Visualize.Shape.Curve.natural/1` | Natural cubic spline as in 5.6. |

## 6. `Visualize.Shape.Arc`

### 6.1 Struct

`%Visualize.Shape.Arc{inner_radius: 0, outer_radius: nil, corner_radius: 0, start_angle: nil, end_angle: nil, pad_angle: 0, pad_radius: nil}`. `new/0` sets `outer_radius` to `100`, `start_angle` to `Map.get(d, :start_angle, 0)`, and `end_angle` to `Map.get(d, :end_angle, 2π)`, so a `Pie` arc datum (section 7) is consumed directly. `pad_radius/2` sets `pad_radius`; `nil` (the default) means `√(r0² + r1²)` at generation time.

### 6.2 Geometry

All parameters are accessors (1.1) evaluated against the datum. Radii are in user units; angles are **radians measured clockwise from 12 o'clock** (the generator subtracts `π/2` before taking `cos`/`sin`). The path is centred on the origin; callers translate it. The construction is d3-shape's `arc` (D-21).

With `r0` inner and `r1` outer (swapped when `r1 < r0`, so the outer radius is always the larger), `a0`/`a1` the shifted angles, `da = |a1 − a0|`, `cw = a1 > a0`, `ε = 1e−12`:

- `r1 ≤ ε` or `da ≤ ε`: empty path — there is nothing to draw (d3 emits a degenerate `M … Z`).
- `da > 2π − ε` (full ring): `M` on the outer circle at `a0`, two `A` half-circles (`large_arc = 1`, `sweep = cw`) around the outer radius; then if `r0 > ε` an `M` on the inner circle at `a1` and two reversed half-circles on the inner radius; then `Z`.
- otherwise (sector), in this order:
  1. **Padding.** With `ap = pad_angle / 2` and, when `ap > ε`, `rp = pad_radius` (default `√(r0² + r1²)`): each ring's two ends move inward by `asin(rp / r · sin ap)` for that ring's radius `r`, so the *linear* gap `rp · pad_angle` is the same on both rings and the angular shift is larger on the inner one. A ring whose extent the pad exceeds — or whose radius is `0`, or for which `rp / r · sin ap > 1` — collapses to the sector's mid-angle with zero extent.
  2. **Corner radius.** `rc = min(corner_radius, |r1 − r0| / 2)`. When `da < π` the corners are further limited by the sector's own geometry: with `oc` the intersection of the two straight edges, `lc = |oc|`, and `kc = 1 / sin(θ/2)` for `θ` the angle between the edges at `oc`, the inner corner radius is `min(rc, (r0 − lc) / (kc − 1))` and the outer `min(rc, (r1 − lc) / (kc + 1))`; parallel edges give `0`.
  3. **Outer edge.** If the outer ring's padded extent is `≤ ε`: `M` at its start. Else if its corner radius is `> ε`: `M` at the first corner's tangent point on the start edge, a corner `A` (radius the corner radius) to the ring, `A r1` along the ring, and a corner `A` down to the end edge — or, when the corner radius was limited below `rc`, one corner `A` from edge to edge (the two corners have merged). Else `M` at the outer start and `A r1` (`large_arc = 1` when the padded extent is `≥ π`, `sweep = cw`) to the outer end.
  4. **Inner edge.** If `r0 ≤ ε` or the inner ring's padded extent is `≤ ε`: `L` to the inner end (the origin for a circular sector). Else if its corner radius is `> ε`: `L` to the first inner corner's tangent point on the end edge, then the mirror of step 3 with `A r0` in the reverse sweep. Else `L` to the inner end and `A r0` (`sweep = 1 − cw`) back to the inner start.
  5. `Z`.

Every `A` is emitted as d3-path emits it: an implicit `L` to the arc's start when the pen is not already there (within `1e−6`), `large_arc = 1` when the arc spans at least `π`, `sweep = 0` for a counter-clockwise arc. The corner construction is d3-shape's `cornerTangents`: the centre of the circle of the corner radius tangent to both the ring and the straight edge (the nearer of the two candidates), with the tangent points on the edge and on the ring. Reference strings are in `test/visualize/shape/arc_stack_test.exs`.

`centroid/2` returns `{r·cos a, r·sin a}` with `r = (r0 + r1) / 2` and `a` the mean of the shifted angles; padding and corners do not move it.

### 6.3 Functions

| Function | Contract |
|---|---|
| `Visualize.Shape.Arc.new/0` | Returns an arc generator with `outer_radius` 100 reading `:start_angle`/`:end_angle` from the datum. |
| `Visualize.Shape.Arc.inner_radius/2` | Sets the inner radius accessor (default `0`). |
| `Visualize.Shape.Arc.outer_radius/2` | Sets the outer radius accessor. |
| `Visualize.Shape.Arc.corner_radius/2` | Sets the corner radius accessor, applied as in 6.2. |
| `Visualize.Shape.Arc.start_angle/2` | Sets the start angle accessor, radians. |
| `Visualize.Shape.Arc.end_angle/2` | Sets the end angle accessor, radians. |
| `Visualize.Shape.Arc.pad_angle/2` | Sets the pad angle accessor, radians, applied as in 6.2. |
| `Visualize.Shape.Arc.pad_radius/2` | Sets the pad radius accessor; `nil` restores the default `√(r0² + r1²)`. |
| `Visualize.Shape.Arc.generate/2` | Returns the SVG path-data string for the datum. |
| `Visualize.Shape.Arc.generate_path/2` | Returns the `IR.Path` as in 6.2. |
| `Visualize.Shape.Arc.centroid/2` | Returns `{x, y}` at mid-radius and mid-angle. |

## 7. `Visualize.Shape.Pie`

### 7.1 Struct

`%Visualize.Shape.Pie{value: nil, sort: nil, sort_values: nil, start_angle: 0, end_angle: 2π, pad_angle: 0}`. `new/0` sets `value` to: the datum itself when a number; `Map.get(d, :value, 0)` when a map; otherwise `0`.

Angles are radians. `start_angle`, `end_angle`, and `pad_angle` are numbers, or 1-arity functions of the **whole data list** (evaluated once per `generate/2`).

### 7.2 Sorting

`sort/2` sets a comparator on data and clears `sort_values`; `sort_values/2` sets a comparator on computed values and clears `sort`. A comparator is a 2-arity function returning `true` when its first argument SHOULD precede the second (`Enum.sort/2` semantics); `nil` clears. Sorting affects angle assignment only; the returned list is always in original data order.

### 7.3 Arc Datum

`generate/2` returns `[]` for empty data; otherwise one map per datum, ordered by original index:

```
%{data: d, value: v, index: i, start_angle: a, end_angle: b, pad_angle: p}
```

with `v = max(0, value.(d))`, `total = Σ v`, `da = clamp(end − start, −2π, 2π)`, `k = (da − n·pad) / total` (`0` when `total ≤ 0`), each arc spanning `v·k` from the running angle, `p = pad` when `v > 0` else `0`, and the running angle advancing by `v·k + p`. Negative values are treated as zero. No limit is imposed on `pad`; `n·pad > da` makes `k` negative.

### 7.4 Functions

| Function | Contract |
|---|---|
| `Visualize.Shape.Pie.new/0` | Returns a pie generator with the default value accessor. |
| `Visualize.Shape.Pie.value/2` | Sets the value accessor: function, atom field (default `0`), or constant. |
| `Visualize.Shape.Pie.sort/2` | Sets the data comparator (clears `sort_values`); `nil` to unset. |
| `Visualize.Shape.Pie.sort_values/2` | Sets the value comparator (clears `sort`); `nil` to unset. |
| `Visualize.Shape.Pie.start_angle/2` | Sets the start angle in radians (default `0`). |
| `Visualize.Shape.Pie.end_angle/2` | Sets the end angle in radians (default `2π`). |
| `Visualize.Shape.Pie.pad_angle/2` | Sets the pad angle between arcs in radians (default `0`). |
| `Visualize.Shape.Pie.generate/2` | Returns the arc-datum list as in 7.3. |

## 8. `Visualize.Shape.Stack`

### 8.1 Struct

`%Visualize.Shape.Stack{keys: [], value: nil, order: :none, offset: :none}`. `new/0` sets `value` to `fn d, key -> Map.get(d, key, 0) end`.

### 8.2 Enumerations

`order/2` MUST be one of `:none`, `:ascending`, `:descending`, `:reverse`, `:insideout`; `offset/2` MUST be one of `:none`, `:expand`, `:diverging`, `:silhouette`, `:wiggle`. Any other atom fails to match.

### 8.3 Series Shape

`generate/2` returns `[]` when data or keys are empty; otherwise a list of

```
%{key: k, index: i, points: [%{key: k, index: j, data: d, value: v, y0: lo, y1: hi}, …]}
```

one series per key **in key order**, with the series' `index` its position in the stacking order (`0` at the bottom, as d3 records `series.index`), each with one point per datum in data order; a point's `index` is its datum's index (D-22).

### 8.4 Order

| Order | Series sequence |
|---|---|
| `:none` | key order |
| `:reverse` | reversed key order |
| `:ascending` | ascending by series sum |
| `:descending` | descending by series sum |
| `:insideout` | descending by sum, then alternated so the largest series is in the middle and successively smaller ones are placed outward on alternating sides |

### 8.5 Offset

The offsets are d3-shape's (D-22), applied in stacking order (8.4). Every series starts with `y0 = 0`, `y1 = v` per point. "Stacking" below means: the bottom series keeps its `y0`; each following series takes `y0` from the previous series' `y1` and `y1 = y0 + v`, so negatives lower the running top.

| Offset | Adjustment |
|---|---|
| `:none` | stack |
| `:expand` | `v` divided by the column's total `Σ v` (`0` when the total is `0`), then stack |
| `:diverging` | per column, positives accumulate upward from `0` (`y0 = yp`, `y1 = yp + v`) and negatives downward from `0` (`y1 = yn`, `y0 = yn + v`), independently of each other; a zero value is `y0 = y1 = 0` |
| `:silhouette` | the bottom series' `y0` is `−total / 2` per column, then stack |
| `:wiggle` | the bottom series' `y0` per column is the streamgraph baseline (Byron and Wattenberg): `0` for the first column, and for each following column `j` the previous baseline minus `Σ_i (Δ_i / 2 + Σ_{k<i} Δ_k) · v_ij / Σ_i v_ij`, with `Δ_i = v_ij − v_i(j−1)` and `i`, `k` over series in stacking order (the baseline is unchanged when `Σ_i v_ij = 0`); then stack |

### 8.6 Functions

| Function | Contract |
|---|---|
| `Visualize.Shape.Stack.new/0` | Returns a stack generator reading `Map.get(d, key, 0)`. |
| `Visualize.Shape.Stack.keys/2` | Sets the list of series keys. |
| `Visualize.Shape.Stack.value/2` | Sets the 2-arity `(datum, key) -> number` accessor. |
| `Visualize.Shape.Stack.order/2` | Sets the series order (8.4). |
| `Visualize.Shape.Stack.offset/2` | Sets the baseline offset (8.5). |
| `Visualize.Shape.Stack.generate/2` | Returns the series list as in 8.3. |

## 9. `Visualize.Shape.Symbol`

### 9.1 Struct

`%Visualize.Shape.Symbol{type: :circle, size: 64}`. `type` is a symbol atom or a 1-arity function of the datum returning one; `size` is a number in **square user units (area)** or a 1-arity function returning one. `generate/1` passes `nil` as the datum.

### 9.2 Types and Geometry

Every path is centred on the origin. With `s` the size:

| Type | Construction |
|---|---|
| `:circle` | `r = √(s/π)`; `M r,0`, two `A r r 0 1 1` half-circles, `Z` |
| `:cross` | `r = √(s/5)/2`; 12-vertex plus sign with arm width `2r` and extent `±3r` |
| `:diamond` | `r = √(s/(2√3))`, `h = r√3`; vertices `(0,−h) (r,0) (0,h) (−r,0)` |
| `:square` | `r = √s/2`; axis-aligned square `±r` |
| `:star` | `r_o = √(0.6·s)`, `r_i = 0.4·r_o`; 10 vertices alternating radii from `−π/2` |
| `:triangle` | `h = √(s/√3)`, `w = h√3/2`; vertices `(0,−2h/3) (w,h/3) (−w,h/3)` |
| `:wye` | `r = √(s/4)`, `c = r·cos(π/6)`, `t = r·sin(π/6)`; 12-vertex three-armed Y |

`types/0` returns `[:circle, :cross, :diamond, :square, :star, :triangle, :wye]`. An unknown type raises `CaseClauseError`. Only `:circle` and `:square` have area exactly `s`; other shapes are sized so their bounding area is approximately `s`.

### 9.3 Functions

| Function | Contract |
|---|---|
| `Visualize.Shape.Symbol.new/0` | Returns a `:circle` of size 64. |
| `Visualize.Shape.Symbol.type/2` | Sets the type atom or a 1-arity function returning one. |
| `Visualize.Shape.Symbol.size/2` | Sets the area in square user units, or a 1-arity function returning one. |
| `Visualize.Shape.Symbol.types/0` | Returns the seven type atoms. |
| `Visualize.Shape.Symbol.generate/1` | As `generate/2` with `nil` datum. |
| `Visualize.Shape.Symbol.generate/2` | Returns the SVG path-data string. |
| `Visualize.Shape.Symbol.generate_path/2` | Returns the `IR.Path` as in 9.2. |

## 10. `Visualize.Shape.LineNx`

### 10.1 Requirements

`Nx` is an optional dependency (`{:nx, "~> 0.9", optional: true}`). The module compiles without it; calling any transforming function without `Nx` loaded raises `UndefinedFunctionError`. Applications MUST add `:nx` to their own dependencies to use this module. Tensors are `:f64`.

### 10.2 Semantics

- `generate_path/2,3`: options `:x_domain`, `:x_range`, `:y_domain`, `:y_range`, each a `{min, max}` tuple defaulting to `{0, 1}`; `:curve` (a type from section 5, default `:linear`) and `:curve_opts` (its keyword list, default `[]`). Coordinates are scaled by `(v − d0) / (d1 − d0) · (r1 − r0) + r0` in one vectorised operation. With `:linear` they are emitted directly as `{:M, x, y}` followed by `{:L, x, y}` per point; any other curve passes the scaled points through `Visualize.Shape.Curve.generate/3` (D-20).
- `generate_path_raw/2`: the same `M`/`L` path from already-scaled lists.
- `batch_transform/6`: returns `{scaled_xs, scaled_ys}` as lists of floats.
- `to_binary/6,7`: scales, adds `:translate_x`/`:translate_y` (default `0`), and encodes the `Visualize.Backend.CanvasBinary` opcode stream: an optional style block `<<0x10, flags>>` followed by fill RGBA (`flag 0x01`), stroke RGBA (`flag 0x02`), stroke width as little-endian `f32` (`flag 0x04`), present only when any of `:fill`, `:stroke`, `:stroke_width` is given; then `<<0x01, count::little-32>>` and `2·count` native-endian `f64` coordinates interleaved x, y; then `0x40` (fill) and/or `0x41` (stroke) draw ops. Colours MUST be `"#rrggbb"`; any other value encodes as opaque black; `:none` suppresses that operation.
- `to_base64/6,7`: `Base.encode64/1` of `to_binary`.

### 10.3 Functions

| Function | Contract |
|---|---|
| `Visualize.Shape.LineNx.generate_path/2` | As `generate_path/3` with `[]` options (identity domains and ranges). |
| `Visualize.Shape.LineNx.generate_path/3` | Batch-scales `xs`, `ys` by the domain/range options and returns an `IR.Path` through the `:curve` option. |
| `Visualize.Shape.LineNx.generate_path_raw/2` | Returns a linear `IR.Path` from pre-scaled coordinate lists. |
| `Visualize.Shape.LineNx.batch_transform/6` | Vectorised linear scaling; returns `{xs, ys}` float lists. |
| `Visualize.Shape.LineNx.to_binary/6` | As `to_binary/7` with `[]` options. |
| `Visualize.Shape.LineNx.to_binary/7` | Scales and encodes directly to the CanvasBinary byte format (10.2). |
| `Visualize.Shape.LineNx.to_base64/6` | As `to_base64/7` with `[]` options. |
| `Visualize.Shape.LineNx.to_base64/7` | Base64 of `to_binary/7`. |

## 11. `Visualize.Shape.Band`

### 11.1 Struct

`%Visualize.Shape.Band{x0: nil, x1: nil, y: 0, height: 10, fill: nil}`. `new/0` sets `x0` to `elem(d, 0)` and `x1` to `elem(d, 1)`, so tuple data `{start, stop}` work without configuration; `y` and `height` are the constants `0` and `10`; `fill` is unset.

### 11.2 Semantics

A band is a state timeline: one rectangle per datum spanning `x0` to `x1` at `y`, `height` tall, filled per datum — *which state, for how long*. All four coordinates are pixel accessors (1.1): the caller applies the x scale inside `x0`/`x1`, as with `Line` and `Area`. `fill/2` takes a 1-arity function, an atom field, or a string constant.

`generate/2` returns one `Visualize.IR.Element` of type `:rect` per datum, in data order, so the list is index-aligned with the data. Its `attrs` are `x = min(x0, x1)`, `y`, `width = |x1 − x0|`, `height`; its `style` is `%{class: "band"}` plus `fill: fill` when the fill accessor yields a value other than `nil`. A datum whose edges coincide is a zero-width rectangle and is still emitted. An empty data list yields `[]`.

`generate_path/2` returns one `IR.Path` of closed rectangles in the same order — per datum `{:M, x, y}`, `{:H, x + width}`, `{:V, y + height}`, `{:H, x}`, `:Z` — for a timeline filled alike; `fill` plays no part in it. `generate/2` and `generate_path/2` never raise for an empty list.

### 11.3 Functions

| Function | Contract |
|---|---|
| `Visualize.Shape.Band.new/0` | Returns a band generator reading tuple elements 0 and 1 as `x0`/`x1`, with `y = 0` and `height = 10`. |
| `Visualize.Shape.Band.x0/2` | Sets the start-edge accessor (function, atom, or number), in pixels. |
| `Visualize.Shape.Band.x1/2` | Sets the end-edge accessor, in pixels. |
| `Visualize.Shape.Band.y/2` | Sets the top accessor, in pixels. |
| `Visualize.Shape.Band.height/2` | Sets the height accessor, in pixels. |
| `Visualize.Shape.Band.fill/2` | Sets the fill accessor: function, atom field, or string constant. |
| `Visualize.Shape.Band.generate/2` | Returns the list of `:rect` elements as in 11.2. |
| `Visualize.Shape.Band.generate_path/2` | Returns one `IR.Path` of closed rectangles as in 11.2. |

## 12. `Visualize.Shape.Rule`

### 12.1 Struct

`%Visualize.Shape.Rule{x: nil, scale: nil, y0: 0, y1: 100, label: nil}`. `new/0` sets `x` to the identity `fn d -> d end`, so a list of bare domain values is valid data; `y0` and `y1` are constants; `scale` and `label` are unset.

### 12.2 Semantics

A rule marks an instant — a deploy, an incident — as a vertical line at a domain x value, drawn inside the same scale and margin system as the data marks (D-27). `x/2` is an accessor (1.1) yielding a *domain* value; `scale/2` is the scale that maps it, any struct `Visualize.Scale.apply/2` accepts; with no scale the value is taken as a pixel coordinate. `y0`/`y1` are pixel accessors giving the vertical extent. `label/2` is an accessor yielding the label text — a function, an atom field, or a string constant; `nil` (the default) draws no label.

`generate/2` returns one `:group` element per datum, in data order, with `style: %{class: "rule"}`. With `px = Visualize.Scale.apply(scale, x)` (or `x` itself without a scale), the group's children are:

1. a `:line` from `(px, y0)` to `(px, y1)` with `style: %{stroke: :current_color, stroke_width: 1}`;
2. when the label is not `nil`, a `:text` with `attrs: %{x: px, y: min(y0, y1), dx: 3, dy: 10}` and `style: %{font_size: 10, font_family: "sans-serif", text_anchor: :start, fill: :current_color}` — the label sits to the right of the rule's upper end, inside the plot.

An empty data list yields `[]`. The group is a plain `Visualize.IR.Element`: callers restyle it with `Visualize.IR.Element.set_style/2` and place it with `Visualize.IR.Element.translate/3` like any other element.

### 12.3 Functions

| Function | Contract |
|---|---|
| `Visualize.Shape.Rule.new/0` | Returns a rule generator reading each datum as its x value, with extent `0` to `100`. |
| `Visualize.Shape.Rule.x/2` | Sets the domain-value accessor (function, atom, or number). |
| `Visualize.Shape.Rule.scale/2` | Sets the x scale the values map through; `nil` means the values are pixels. |
| `Visualize.Shape.Rule.y0/2` | Sets the first vertical-extent accessor, in pixels. |
| `Visualize.Shape.Rule.y1/2` | Sets the second vertical-extent accessor, in pixels. |
| `Visualize.Shape.Rule.label/2` | Sets the label accessor: function, atom field, or string constant; `nil` clears it. |
| `Visualize.Shape.Rule.generate/2` | Returns the list of `:group` elements as in 12.2. |

## 13. `Visualize.Shape.XBand`

### 13.1 Struct

`%Visualize.Shape.XBand{x0: nil, x1: nil, scale: nil, y0: 0, y1: 100, fill: nil, label: nil}`. `new/0` sets `x0` to `elem(d, 0)`, `x1` to `elem(d, 1)`, and `fill` to the constant `"rgba(119, 119, 119, 0.2)"`, so `{start, stop}` tuples of domain values are valid data and the region shades like a brush selection (spec/10 §6.2).

### 13.2 Semantics

An x-band shades the interval between two domain x values — an incident, a maintenance window — under the rule's model (12.2, D-27): `x0`/`x1` are domain-value accessors, `scale/2` maps them (no scale: pixels), `y0`/`y1` are the pixel extent, and `fill/2` and `label/2` are accessors that also take a string constant.

`generate/2` returns one `:group` element per datum, in data order, with `style: %{class: "x-band"}`. With `p0`, `p1` the mapped edges, `left = min(p0, p1)`, `top = min(y0, y1)`, the group's children are:

1. a `:rect` at `(left, top)` with `width = |p1 − p0|` and `height = |y1 − y0|`, `style: %{fill: fill}` (the key omitted when the fill is `nil`);
2. when the label is not `nil`, a `:text` at `attrs: %{x: left, y: top, dx: 3, dy: 10}` with the rule's label style.

An empty data list yields `[]`.

### 13.3 Functions

| Function | Contract |
|---|---|
| `Visualize.Shape.XBand.new/0` | Returns an x-band generator reading tuple elements 0 and 1 as its edges, with extent `0` to `100` and the brush's fill. |
| `Visualize.Shape.XBand.x0/2` | Sets the first-edge domain-value accessor. |
| `Visualize.Shape.XBand.x1/2` | Sets the second-edge domain-value accessor. |
| `Visualize.Shape.XBand.scale/2` | Sets the x scale the edges map through; `nil` means the values are pixels. |
| `Visualize.Shape.XBand.y0/2` | Sets the first vertical-extent accessor, in pixels. |
| `Visualize.Shape.XBand.y1/2` | Sets the second vertical-extent accessor, in pixels. |
| `Visualize.Shape.XBand.fill/2` | Sets the fill accessor: function, atom field, or string constant. |
| `Visualize.Shape.XBand.label/2` | Sets the label accessor: function, atom field, or string constant; `nil` clears it. |
| `Visualize.Shape.XBand.generate/2` | Returns the list of `:group` elements as in 13.2. |

## 14. `Visualize.Shape.PercentileBand`

### 14.1 Struct

`%Visualize.Shape.PercentileBand{x: nil, median: nil, inner: nil, outer: nil, defined: nil, curve: :linear, curve_opts: []}`. `new/0` sets `x` to `elem(d, 0)`; `median`, `inner`, and `outer` are unset.

### 14.2 Semantics

A percentile band is the standard reading of a distribution over time: a median line with a shaded inner band (say p25–p75) and a wider outer band (say p5–p95) around it. It is a composition of `Visualize.Shape.Area` and `Visualize.Shape.Line` with a fixed output shape (D-28), so every consumer draws it the same way.

`x/2` and `median/2` are pixel accessors (1.1). `inner/2` and `outer/2` each take a `{lo, hi}` pair of pixel accessors, the lower and upper percentile; `nil` clears the band. `curve/2,3` and `defined/2` apply to all three paths alike.

`generate_path/2` returns `%{outer: outer, inner: inner, median: median}` where:

- `outer` is `Area.generate_path/2` for the area with `x`, `y0 = lo`, `y1 = hi` of the outer pair, the same `defined`, `curve`, and `curve_opts` — or `nil` when `outer` is unset; `inner` likewise for the inner pair;
- `median` is `Line.generate_path/2` for the line with `x`, `y = median`, the same `defined`, `curve`, and `curve_opts` — or `nil` when `median` is unset.

`generate/2` returns the same map with each path serialised by `Visualize.Backend.SVG.path_data/1`; `nil` stays `nil`. The three paths are drawn outer, inner, median — the caller fills the bands and strokes the median; a generator with no band and no median returns a map of three `nil`.

### 14.3 Functions

| Function | Contract |
|---|---|
| `Visualize.Shape.PercentileBand.new/0` | Returns a generator reading tuple element 0 as `x`, with no median and no bands. |
| `Visualize.Shape.PercentileBand.x/2` | Sets the x accessor (function, atom, or number). |
| `Visualize.Shape.PercentileBand.median/2` | Sets the median accessor; `nil` clears it. |
| `Visualize.Shape.PercentileBand.inner/2` | Sets the inner band as a `{lo, hi}` pair of accessors; `nil` clears it. |
| `Visualize.Shape.PercentileBand.outer/2` | Sets the outer band as a `{lo, hi}` pair of accessors; `nil` clears it. |
| `Visualize.Shape.PercentileBand.defined/2` | Sets the 1-arity defined predicate (1.2), applied to every path. |
| `Visualize.Shape.PercentileBand.curve/2` | As `curve/3` with `[]` options. |
| `Visualize.Shape.PercentileBand.curve/3` | Sets the curve type and options, applied to every path. |
| `Visualize.Shape.PercentileBand.generate/2` | Returns `%{outer:, inner:, median:}` of SVG path-data strings or `nil`, as in 14.2. |
| `Visualize.Shape.PercentileBand.generate_path/2` | Returns `%{outer:, inner:, median:}` of `IR.Path` or `nil`, as in 14.2. |
