# Shapes and Curves

**Status:** Implemented

Shape generators turn data into geometry. `Visualize.Shape` is a facade over `Shape.Line`, `Shape.Area`, `Shape.Arc`, `Shape.Pie`, `Shape.Stack`, and `Shape.Symbol`; `Shape.Curve` supplies the point interpolators used by lines and areas; `Shape.LineNx` is an optional Nx-accelerated line path builder. Path-producing generators offer `generate_path/2`, returning a backend-neutral `Visualize.IR.Path`, and `generate/2`, returning that path serialised as an SVG `d` string. Layout generators (`Pie`, `Stack`) return data, not paths. All coordinates are in user units with the SVG convention (x right, y down); all angles are radians.

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

Atom accessors read a map key and return `nil` when absent (except `Pie`, which defaults to `0`); a `nil` coordinate fails arithmetic downstream. Callers SHOULD supply functions when data are not maps. A numeric constant is the accessor `fn _ -> n end`; `Line` accepts one since D-20.

### 1.2 `defined/2`

`Line.defined/2` and `Area.defined/2` take a 1-arity predicate. A datum for which it returns a falsy value **breaks** the path (d3-shape's `defined` semantics, D-18): the data are split into runs of consecutive defined data, each run is generated through the curve as its own subpath — for `Area`, its own closed ring — and the subpaths are concatenated in data order, so a gap is visible between them. A run of fewer than two points has no segment to draw and contributes nothing; data whose defined runs are all single points therefore produce an empty path. With no predicate the whole data list is one run.

### 1.3 `generate/2` versus `generate_path/2`

`generate_path/2` returns `%Visualize.IR.Path{commands: [...]}` with commands from `{:M, x, y}`, `{:L, x, y}`, `{:H, x}`, `{:V, y}`, `{:C, x1, y1, x2, y2, x, y}`, `{:A, rx, ry, rot, large_arc, sweep, x, y}`, `:Z`. `generate/2` is `generate_path/2` piped through `Visualize.Backend.SVG.path_data/1`; the result is the SVG path-data string. Code targeting a non-SVG backend MUST use `generate_path/2` and render through `Visualize.Render`.

Both `Line.generate_path/2` and `Area.generate_path/2` return an empty path (`Visualize.IR.Path.new/0`) when no defined run (1.2) has two or more points; a lone point yields no `M` command.

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
| `Visualize.Shape.x/2` | `Line.x/2` or `Area.x/2`. |
| `Visualize.Shape.y/2` | `Line.y/2` or `Area.y/2`. |
| `Visualize.Shape.x0/2` | `Area.x0/2`. |
| `Visualize.Shape.x1/2` | `Area.x1/2`. |
| `Visualize.Shape.y0/2` | `Area.y0/2`. |
| `Visualize.Shape.y1/2` | `Area.y1/2`. |
| `Visualize.Shape.curve/2` | As `curve/3` with `[]` options. |
| `Visualize.Shape.curve/3` | `Line.curve/3` or `Area.curve/3`. |
| `Visualize.Shape.defined/2` | `Line.defined/2` or `Area.defined/2`. |
| `Visualize.Shape.value/2` | `Pie.value/2` or `Stack.value/2`. |
| `Visualize.Shape.keys/2` | `Stack.keys/2`. |
| `Visualize.Shape.order/2` | `Stack.order/2`. |
| `Visualize.Shape.offset/2` | `Stack.offset/2`. |
| `Visualize.Shape.inner_radius/2` | `Arc.inner_radius/2`. |
| `Visualize.Shape.outer_radius/2` | `Arc.outer_radius/2`. |
| `Visualize.Shape.start_angle/2` | `Arc.start_angle/2` or `Pie.start_angle/2`. |
| `Visualize.Shape.end_angle/2` | `Arc.end_angle/2` or `Pie.end_angle/2`. |
| `Visualize.Shape.pad_angle/2` | `Arc.pad_angle/2` or `Pie.pad_angle/2`. |
| `Visualize.Shape.type/2` | `Symbol.type/2`. |
| `Visualize.Shape.size/2` | `Symbol.size/2`. |
| `Visualize.Shape.generate/1` | As `generate/2` with `nil` data (meaningful for `Symbol` only). |
| `Visualize.Shape.generate/2` | Dispatches to the module's `generate/2`: SVG path string for `Line`, `Area`, `Arc`, `Symbol`; arc-datum list for `Pie`; series list for `Stack`. |
| `Visualize.Shape.generate_path/1` | As `generate_path/2` with `nil` data. |
| `Visualize.Shape.generate_path/2` | Dispatches to `generate_path/2` of `Line`, `Area`, `Arc`, or `Symbol`; `Pie` and `Stack` are not accepted. |

`Shape.corner_radius/2` is absent from the facade; use `Shape.Arc.corner_radius/2` directly. `Pie.sort/2` and `Pie.sort_values/2` likewise.

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

`%Visualize.Shape.Arc{inner_radius: 0, outer_radius: nil, corner_radius: 0, start_angle: nil, end_angle: nil, pad_angle: 0, pad_radius: nil}`. `new/0` sets `outer_radius` to `100`, `start_angle` to `Map.get(d, :start_angle, 0)`, and `end_angle` to `Map.get(d, :end_angle, 2π)`, so a `Pie` arc datum (section 7) is consumed directly. `pad_radius` has no setter.

### 6.2 Geometry

All parameters are accessors (1.1) evaluated against the datum. Radii are in user units; angles are **radians measured clockwise from 12 o'clock** (the generator subtracts `π/2` before taking `cos`/`sin`). The path is centred on the origin; callers translate it.

With `r0` inner, `r1` outer, `a0`/`a1` the shifted angles, `da = |a1 − a0|`, `cw = a1 > a0`, `ε = 1e−12`:

- `da > 2π − ε` (full ring): `M` on the outer circle at `a0`, two `A` half-circles (`large_arc = 1`, `sweep = cw`) around the outer radius; then if `r0 > ε` an `M` and two reversed half-circles on the inner radius (no `Z`), else `Z`.
- `ε < da ≤ 2π − ε` (sector): `M` outer start, `A r1 r1 0 large sweep` to outer end (`large = 1` when `da > π`); then if `r0 > ε`: `L` inner end, `A r0 r0 0 large (1 − sweep)` back to inner start, `Z`; else `L 0,0`, `Z`.
- `da ≤ ε`: empty path.

`centroid/2` returns `{r·cos a, r·sin a}` with `r = (r0 + r1) / 2` and `a` the mean of the shifted angles.

`corner_radius` and `pad_angle` are stored and accessible but **not applied** by `generate_path/2`; the emitted geometry ignores them. Intended behaviour is D3's: `pad_angle` narrows the sector by half the pad on each side (at `pad_radius`, default `√(r0² + r1²)`), and `corner_radius` rounds the four corners with tangent arcs, limited to half the ring thickness.

> Decision: see spec/13 — `Arc.generate_path/2` MUST honour `pad_angle` and `corner_radius`.

### 6.3 Functions

| Function | Contract |
|---|---|
| `Visualize.Shape.Arc.new/0` | Returns an arc generator with `outer_radius` 100 reading `:start_angle`/`:end_angle` from the datum. |
| `Visualize.Shape.Arc.inner_radius/2` | Sets the inner radius accessor (default `0`). |
| `Visualize.Shape.Arc.outer_radius/2` | Sets the outer radius accessor. |
| `Visualize.Shape.Arc.corner_radius/2` | Sets the corner radius accessor (stored; see 6.2). |
| `Visualize.Shape.Arc.start_angle/2` | Sets the start angle accessor, radians. |
| `Visualize.Shape.Arc.end_angle/2` | Sets the end angle accessor, radians. |
| `Visualize.Shape.Arc.pad_angle/2` | Sets the pad angle accessor, radians (stored; see 6.2). |
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
%{key: k, points: [%{key: k, index: i, data: d, value: v, y0: lo, y1: hi}, …]}
```

one series per key **in stacking order** (after `order` is applied; the output is not restored to key order), each with one point per datum in data order.

### 8.4 Order

| Order | Series sequence |
|---|---|
| `:none` | key order |
| `:reverse` | reversed key order |
| `:ascending` | ascending by series sum |
| `:descending` | descending by series sum |
| `:insideout` | descending by sum, then alternated so the largest series is in the middle and successively smaller ones are placed outward on alternating sides |

### 8.5 Offset

Stacking first computes, per column, `y0 = baseline`, `y1 = baseline + v`, `baseline ← y1` across the ordered series (negatives lower the baseline). Offsets then adjust:

| Offset | Adjustment |
|---|---|
| `:none` | none |
| `:expand` | `y0`, `y1` divided by the column's total `Σ v`; both `0` when the total is `0` |
| `:diverging` | points with `v < 0` become `y0 = v`, `y1 = 0`; positive points unchanged |
| `:silhouette` | `y0`, `y1` shifted by `−total / 2` per column |
| `:wiggle` | identical to `:silhouette` when there are at least two data; otherwise none |

Intended D3 semantics differ for two offsets. `:diverging` MUST stack positives cumulatively upward from zero and negatives cumulatively downward from zero, independent of one another; the code neither accumulates negatives nor isolates positives from preceding negative series. `:wiggle` MUST minimise weighted change in slope (the streamgraph algorithm); the code substitutes `:silhouette`.

> Decision: see spec/13 — `Stack` `:diverging` and `:wiggle` are to be implemented per D3.

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
