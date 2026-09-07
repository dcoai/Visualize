# Decisions

**Status:** Implemented

This is the architecture decision record. Each entry states the context that forced a choice, the decision, and its consequences. Entries are never edited after acceptance; a reversal is a new entry that references the old one. Other documents cite entries as `D-N`.

## 1. D-1 — `IR.Transform.scale/2` is two constructors, not one

**Context.** `Visualize.IR.Transform.scale/2` had two clauses: `scale(sx, sy)` building a new transform, and `scale(%Transform{}, s)` appending a uniform scale. A guard ordering made the second clause unreachable, so `Transform.new() |> scale(2)` raised `FunctionClauseError` and the documented pipeline form did not work.

**Decision.** `scale/2` with two numbers constructs a new transform with `{:scale, sx, sy}`; with a transform and one number it appends `{:scale, s, s}`. `scale/1` constructs a uniform scale; `scale/3` appends a non-uniform one. Both `scale/2` clauses are guarded so each is reachable.

**Consequences.** The pipeline form works and is tested in `test/visualize/defects_test.exs`. The overloading remains: a reader must know that the first argument's type selects the meaning. This mirrors `translate/2` vs `translate/3` and `rotate/1` vs `rotate/2`, so it is consistent rather than surprising.

## 2. D-2 — No per-process backend override

**Context.** `Visualize.Render.with_backend/2` set a backend in the process dictionary for the duration of a function, restoring it afterwards. Any render inside the function silently used a backend chosen elsewhere, and restoring the previous value required `try/after`, which this project forbids because it hides the failure it wraps.

**Decision.** `with_backend/2` is removed. A backend is selected only by the `:backend` option at the call site or by `config :visualize, default_backend:`. `Visualize.Backend.default/0` reads the configuration; nothing reads the process dictionary.

**Consequences.** Every render call names its backend or inherits the application-wide default, so the choice is visible where it matters. Code that rendered inside `with_backend/2` threads `backend:` through instead. No `try/after` remains in `lib/`.

## 3. D-3 — Clip angle clips by angular distance from the centre

**Context.** `Visualize.Geo.Projection.clip_angle/2` stored a value that nothing read: a projection with a clip angle still projected the far hemisphere, so orthographic globes drew the back of the world over the front.

**Decision.** `project/3` returns `nil` when the angular distance from the point to the projection centre (after rotation) exceeds `clip_angle`, with a `1.0e-9` tolerance on the boundary. `new/1` sets a default clip angle per azimuthal type: orthographic 90°, stereographic 142°, gnomonic 60°, azimuthal equal-area 180°, azimuthal equidistant 180°. `clip_angle(proj, nil)` disables clipping.

**Consequences.** Azimuthal projections behave as in `d3-geo`. Callers that projected points beyond the horizon now receive `nil` and MUST handle it, which `Visualize.Geo.Path` does by dropping the point. The projection golden was regenerated for the affected cells.

## 4. D-4 — The many-body force is exact and has no `:theta`

**Context.** `Visualize.Layout.Force.Forces.apply_many_body/3` accepted a `:theta` option in the manner of `d3-force`'s Barnes–Hut approximation, but there is no quadtree in the library and the option was ignored. An accepted, ignored option is a lie in the API.

**Decision.** The many-body force evaluates every pair directly, O(n²) per tick, and the `:theta` option is removed rather than left inert. Passing it is a programmer error.

**Consequences.** The force is exact and simple, and documented as such. Graphs beyond a few thousand nodes are slow per tick; a Barnes–Hut implementation, if ever wanted, arrives as a new decision with a quadtree, at which point `:theta` returns with meaning.

## 5. D-5 — Transverse Mercator inverse: contract is `nil`, code raises

**Context.** `Visualize.Geo.Projection.invert/3` for `:transverse_mercator` raises `ArithmeticError` for points away from the central meridian, where the inverse series leaves its domain. This predates the projection split and is tracked as issue #9.

**Decision.** The contract is that `invert/3` returns `nil` outside the valid domain, as every other projection does ([11-public-api](11-public-api.md) §4). The fix is not yet implemented. Until it is, the projection golden records the transverse Mercator inverse as `excluded` so the golden neither crashes nor freezes the wrong behaviour.

**Consequences.** Callers inverting transverse Mercator points MUST expect the exception until #9 closes. When it does, the golden is regenerated to record the inverse and the `@no_inverse` exclusion is removed; this entry then stands as the record of the gap.

## 6. D-6 — The projection golden folds negative zero

**Context.** Moving projection maths verbatim into family modules (D-9) changed the sign of zero on 259 golden cells with no numeric change: whether `0.0` or `-0.0` emerges from an expression depends on whether the compiler could see the operand's type, which changed when the functions moved across a module boundary.

**Decision.** The golden's formatter adds `0.0` to every value before printing, which folds `-0.0` into `0.0`. The sign of zero is not a property of the maths and is not part of the contract.

**Consequences.** Refactors that move maths without changing it leave the golden untouched. Residuals that round to zero at nine decimals but are genuinely negative still print with a sign; that is real and stable. Nothing in the library treats `-0.0` as distinct from `0.0`.

## 7. D-7 — Components compile only when `Phoenix.Component` is loaded

**Context.** Chart components and the `Phoenix.HTML.Safe` implementations need Phoenix, but the library is useful without it and must not force the dependency on a script, a report generator or a test.

**Decision.** `Visualize.Components` and `Visualize.Components.Tree` are wrapped in `if Code.ensure_loaded?(Phoenix.Component)`; the `Phoenix.HTML.Safe` implementations for `Visualize.IR.Element` and `Visualize.SVG.Element` in `if Code.ensure_loaded?(Phoenix.HTML.Safe)`. Phoenix is not listed in `deps`.

**Consequences.** A consumer with Phoenix gets the components with no configuration; one without gets everything else. The guard is a compile-time check of the consumer's build, so a consumer that adds Phoenix later MUST recompile `visualize` (`mix deps.compile visualize --force`). CI proves the no-Phoenix build with a consumer compile ([12-testing-and-conformance](12-testing-and-conformance.md) §4).

## 8. D-8 — Step curves emit D3-identical paths

**Context.** `:step_before` and `:step_after` emitted a zero-length segment at the first point and consecutive horizontal commands, so the path was longer than D3's and differed textually while drawing the same picture — which made comparison against D3 output impossible.

**Decision.** For points `p0 … pn`, `:step` emits `M x0,y0` then for each following point `H mid V y H x`; `:step_before` emits `V y H x` per point; `:step_after` emits `H x V y` per point. No zero-length command and no two consecutive `H` commands are emitted. The reference strings are in `test/visualize/defects_test.exs`.

**Consequences.** Paths match `d3-shape`'s `curveStep*` byte for byte for the same input, so D3 fixtures can serve as goldens. Existing rendered output changes textually but not visually.

## 9. D-9 — Family modules are `@doc false` internals

**Context.** `Visualize.Geo.Projection` and `Visualize.Backend.CanvasBinary` each exceeded the project's 1,000-line file limit. Splitting them was necessary, but exposing the pieces would have widened the public API with modules that only make sense through their parent.

**Decision.** `Visualize.Geo.Projection.{Cylindrical, Azimuthal, Conic, Pseudocylindrical, Compromise}` and `Visualize.Backend.CanvasBinary.{Opcodes, PathEncoder, SVG}` hold the maths and encoders, reached only via the parent's public functions. Their functions are `@doc false`. The maths was moved verbatim, which is what made the projection golden (§1 of [12-testing-and-conformance](12-testing-and-conformance.md)) a valid proof of output identity.

**Consequences.** The public surface did not grow. The family modules MAY be reorganised freely. `Opcodes` is public because the JavaScript decoder is written against the same byte values, and a reader of the hook needs the table.

## 10. D-10 — The specification is generated from the code as found

**Context.** The specification was written after most of the code. Writing it as the code *should* be would have produced a document that disagrees with `lib/` on day one; writing it as the code *is* would have enshrined defects.

**Decision.** Each document describes the behaviour the code actually has, except where code and intent differ: there the document states the intent and a decision in this log records the gap (D-5, D-11, D-12). `API_SURFACE.md` measures the surface; the decision log measures the behaviour gaps.

**Consequences.** Every `Implemented` document is falsifiable against `lib/`, and every known divergence is enumerated. Closing a gap is a code change plus a note on the decision; opening one is a new decision, never a silent edit.

## 11. D-11 — `SVG.Element.from_ir/1` renders `view_box` as `viewBox`

**Context.** `Visualize.IR.Element.root/3` stores the view box under the attr key `view_box`. `Visualize.Backend.SVG` maps it to `viewBox` when rendering a `:root`, but `Visualize.SVG.Element.from_ir/1` copies attrs verbatim and `Visualize.SVG.Renderer` converts every underscore to a hyphen, emitting `view-box="…"`, which is not an SVG attribute. The same IR root therefore renders correctly through one path and incorrectly through the other.

**Decision.** `from_ir/1` MUST map a `:root` element's `view_box` attr to the `viewBox` key. Attribute names that are camel-cased in SVG (`viewBox`, `preserveAspectRatio`, `gradientUnits`, `patternUnits`, `clipPathUnits`, `markerWidth`, `markerHeight`, `refX`, `refY`) MUST NOT be hyphenated by the renderer; the underscore-to-hyphen rule applies to presentation attributes only.

**Consequences.** Both rendering paths agree. This is not yet implemented; a `:root` converted with `from_ir/1` currently emits `view-box`, and browsers fall back to the `width`/`height` attrs so the defect is visible only when the view box differs from the size.

## 12. D-12 — One `d` serialisation

**Context.** `Visualize.IR.Path.to_string/1` formats floats with `:erlang.float_to_binary/2` at four decimals; `Visualize.Backend.SVG.path_data/1` uses `Float.round/2` then `Float.to_string/1`, which emits exponent notation for magnitudes below `1.0e-4` or at or above `1.0e16`, after which trailing-zero trimming can corrupt the mantissa (`1.0e20` → `"1.0e2"`). `Visualize.SVG.Path.to_string/1` and the `String.Chars` implementation go through the backend, so the same path can serialise two ways.

**Decision.** The `d` string for a path is defined by `Visualize.IR.Path.to_string/1`: integers verbatim, floats with at most four decimals, trailing zeros and point trimmed, never exponent notation. `Visualize.Backend.SVG.path_data/1` MUST produce the identical string, by delegating to it or by using the same formatter.

**Consequences.** One formatter to test; goldens compare across backends. Not yet implemented: today the two agree for coordinates in the ordinary pixel range and differ only at extreme magnitudes.

## 13. D-13 — Defects found while writing the specification are tracked as proposals, not normalised into it

**Context.** Generating this specification from the code surfaced roughly sixty behaviours where the code does not do what its own documentation, D3's reference behaviour, or basic correctness requires: a scale protocol five modules do not implement (`Scale.apply/2` raises on power, symlog, quantile and quantize scales), a component layer that has never rendered, a Delaunay triangulation that is not Delaunay, a tidy tree that overlaps cousins, and a binary path encoder that silently drops commands. Each document marks such a spot with `> Decision: see spec/13` and states the intended behaviour.

**Decision.** The specification states intent. Every marker is owned by one of these proposals, which carry the reproduction, the root cause and the recurrence guard: #13 (scales and `Data.ticks/3`), #14 (shapes, axes, formatting), #15 (`Components` and the brush hook), #16 (layouts, geo, random), #17 (SVG bridge, binary and canvas backends, benchmark), plus #9 (transverse Mercator inverse) and #5 (force-simulation timers, verified by the ExTLA model). A document's status stays `Implemented` when the divergence is a defect against a settled contract; it would become `Agreed` only if the contract itself were still open.

**Consequences.** Closing a proposal above MUST replace the corresponding markers with the implemented contract and, where the resolution changed the intended behaviour, add a D-entry here. Until then `API_SURFACE.md` reports the functions as `specified`: the surface gate checks that the declared functions exist, not that they are correct — correctness is what the tests those proposals add are for.

## 14. D-14 — Force-simulation timer discipline: tagged ticks, restart keeps the state, alpha is clamped

**Context.** Review found two timer defects in `Visualize.Layout.Force.Simulation` (an unguarded deferred start; a `:restart` that started a stopped simulation) and the ExTLA model (spec/12 §5) found a third: a tick from a timer cancelled after its message had reached the mailbox was indistinguishable from a live tick, so `stop/1` then `start/1` could leave two tick chains running for ever. `set_alpha/2` and `set_alpha_target/2` accepted any number.

**Decision.** Tick messages carry the reference generated when the timer was armed, the server keeps the current one, and a tick with any other tag is ignored. `:start_simulation` and `:start` share one idempotent `arm`. `restart/1` resets `alpha` to 1.0 and does nothing else: a running simulation keeps its chain, a stopped one stays stopped (a client that wants both calls `restart/1` then `start/1`). `set_alpha/2` and `set_alpha_target/2` clamp into `[0, 1]` rather than raise, because a value slightly outside the range from an interpolation is a rounding artefact, not a caller error.

**Consequences.** The three model invariants hold on the code, and the conformance test drives the callbacks through the scripts the model's counterexamples produced. `restart/1` no longer starts anything, which is a behaviour change for any caller that relied on the defect; none exists in this repository or in `examples/`.

## 15. D-15 — The scale protocol is a behaviour, and every scale stores lists

**Context.** `Visualize.Scale` dispatches nine operations to `scale.__struct__`, but nothing declared what a scale module had to define. Five modules (`Power`, `Symlog`, `Quantile`, `Quantize`, `Threshold`) were written against a different interface — `scale/2` for the mapping, no `nice/1`, `padding/2`, `bandwidth/1`, and for the three discretising scales no `invert/2`, `ticks/2`, `clamp/2` — so `Scale.apply/2` raised `UndefinedFunctionError` on any of them and `Axis` could not draw a power, sqrt or symlog axis. Three of them stored domain and range as tuples, which `Axis` read as "no range" and replaced with `[0, 1]`. `Power` applied `|x|^e` to the bounds and only negated the value, collapsing any domain with a negative bound. No test exercised the facade polymorphically, which is why none of this was seen (#13).

**Decision.** The protocol is the behaviour `Visualize.Scale.Behaviour` with the nine callbacks of spec/03 §1.3; every scale module declares it and implements every callback with explicit clauses (no `__using__` defaults, so each module's surface stays readable and scannable). Operations without meaning for a kind are identity, `nil`, or `0`; discretising scales tick at their thresholds. `scale/2` remains on the five modules as a documented alias of `apply/2` for one release. Domains and ranges are two-element lists in every struct; tuples are still accepted on input. `Power` uses D3's signed transform on bounds and value alike. The facade gains `threshold/0`. `test/visualize/scale/protocol_test.exs` constructs every kind through the facade and calls all nine operations, and renders an axis on every continuous scale.

**Consequences.** A scale module that omits an operation no longer compiles under `--warnings-as-errors`, so the facade is total by construction. Callers that pattern-matched the tuple form of `Power`/`Symlog`/`Quantize` domains break; none exists in this repository or in `examples/`. `Quantile.apply/2` also now reaches its last bucket (the bucket search's base case returned index `0` instead of the index it had reached), which the same test covers. The remaining scale defects of #13 landed as D-16 (time ticks) and D-17 (band, tick and colour defects).

## 16. D-16 — Time ticks follow d3-time: boundary snapping and ratio-based interval choice

**Context.** `Visualize.Scale.Time.ticks/2` chose the first interval whose length was at least `span / count`, snapped only sub-day intervals, treated the day "ceiling" as the value's own midnight (so the first tick could precede the domain), never snapped weeks, months or years, rewrote month fields without clamping the day (31 January + 1 month was an invalid 31 February), and for any span wider than `count` years fell back to daily ticks — 8,767 of them over 24 years. Every metresis time-series panel draws a time axis, so this was the milestone's first defect (#13, #23).

**Decision.** Ticks follow `d3.timeTicks`: an interval `{unit, n}` from the table in spec/03 §7.3.1, chosen as the neighbour closer in ratio to `span / count` (not the first one at least as long — at the week→month and quarter→year seams the old rule overshot by up to 4×), and beyond one year a multi-year step from the 1-2-5 nice-step sequence. Every tick is a boundary of the interval inside `[d0, d1]`: multiples of the step below a day, midnight, Monday, the 1st of the month, 1 January of a year divisible by the step. Weeks start on Monday (ISO), where d3 defaults to Sunday. `nice/1` uses the same floor and ceiling. `Visualize.Scale.Time.interval/2` exposes the choice so callers can format ticks by the interval that produced them.

**Consequences.** Tick counts stay within about `2.2×` of the hint in either direction and a long span costs tens of ticks, not thousands. The month-stepping helper clamps the day, though ticks only ever land on the 1st. The property tests in `test/visualize/scale/time_test.exs` assert ascending, in-domain, boundary-aligned ticks over random domains from a minute to two centuries. Callers that relied on the first tick preceding the domain, or on `count` giving strictly at-least-that-long intervals, see different ticks; none exists in this repository or in `examples/`.

## 17. D-17 — Band, tick and colour defects resolve to d3-scale's behaviour

**Context.** The last group of #13: `Band` gave negative `bandwidth` and `step` on a descending range and left `step/1` unrounded; `Quantize.thresholds/1` returned two values for a one-element range (`1..0` descends); `Color` silently substituted `:blues` for an unknown scheme and, unclamped, extrapolated channels past `0…255` into malformed hex; `Ordinal.apply/2` raised on an empty range; `Linear.ticks/2` and `nice/1` raised on a degenerate domain; `Log.ticks/2` ignored its count; `Symlog.ticks/2` ignored its constant; and `Data.ticks/3` raised on every call because `max/2` resolved to `Visualize.Data.max/2` under the module's `import Kernel, except:`. Writing the property tests for the fixes surfaced three more of the same `0..-1` class: `Linear.ticks/2` and `Data.ticks/3` emitted two ticks *outside* a domain that contained no multiple of the step, and `Symlog.ticks/2` emitted decades below a positive lower bound.

**Decision.** Each resolves to the d3-scale reference. `Band` is d3's `rescale`: a descending range is laid out in reverse with positive step and bandwidth; `round/2` floors the step and rounds the start and bandwidth from it. `Log.ticks/2` is d3's log ticks — every `k · base^e` inside the domain when the decades fit the count, thinned powers when they do not, linear ticks when the multiples are too few — with exact logarithms for bases 10 and 2 so `1e12` is decade 12, not 11.999…. `Symlog` decades are `±c · 10^k`, since the log region begins at the constant. An unknown colour scheme raises `ArgumentError` naming `schemes/0`; RGB channels clamp to a byte. `Ordinal` on an empty range returns `unknown`; `Linear` on a degenerate domain returns `[d0]` and leaves `nice/1` alone. Every tick loop steps `0..(n − 1)//1`, so an empty tick set is `[]`. `Data.ticks/3` calls `Kernel.max/2` explicitly and handles zero and descending spans.

**Consequences.** `test/visualize/scale/{band,color,ticks}_test.exs` and `test/visualize/data_test.exs` carry one regression per defect and properties (StreamData) for band arithmetic under either range direction and for tick lists being ascending, distinct and inside the domain — which is what found the three extra defects. `Log.ticks/2` returns different (and more) values than before for every domain, and `Symlog.ticks/2` differs whenever the constant is not 1; nothing in this repository or `examples/` depended on the old lists. The `import Kernel, except: [min: 2, max: 2]` in `Visualize.Data` remains a hazard for any future arithmetic in that module; every `min`/`max` there now names `Kernel` explicitly, and the regression test fails the moment one does not.

## 18. D-18 — `defined/2` breaks the path into subpaths

**Context.** `Line.defined/2` and `Area.defined/2` filtered undefined data out and joined what remained into one continuous path, so a gap in a time series drew as a line across it — the opposite of what the moduledoc promised and of what a dashboard panel needs to show missing data (#14). Nothing tested the path.

**Decision.** d3-shape's semantics: the data are split into runs of consecutive defined data, each run is generated through the configured curve as its own subpath (each with its own `M`; for `Area`, its own closed ring), and the subpaths are concatenated in data order. A run of fewer than two points contributes nothing — it has no segment — so a lone defined point between gaps is invisible and a data list with no run of two points yields an empty path. This keeps the existing "fewer than two points is empty" contract of spec/04 §1.3 rather than adopting d3's `M x,y Z` for a lone point, which fills nothing and strokes nothing but is not empty. The run splitting is one `@doc false` helper on `Shape.Line` that `Area` shares.

**Consequences.** A gap is visible. Rendered output changes for any caller that used `defined` to filter and relied on the points either side being joined; none exists in this repository or in `examples/`. The reference strings are in `test/visualize/shape/line_area_test.exs`.

## 19. D-19 — `Curve.natural/1` is the natural cubic spline

**Context.** The natural spline placed both control points of every segment one third of the way along the chord, which is a straight line written as a cubic Bézier: `:natural` rendered identically to `:linear` (#14). The tridiagonal solve the moduledoc and the spec announced had never been written.

**Decision.** A port of d3-shape's `controlPoints`: per axis, the first control coordinates solve the open natural-spline tridiagonal system (spec/04 §5.6) by the Thomas algorithm and the second control coordinates follow from them; x and y are solved independently, as in d3. The two-point fallback to `:linear` stays.

**Consequences.** `:natural` paths change for every input of three or more points. The three-point example in `test/visualize/shape/line_area_test.exs` is hand-derived from the system and matches d3; `test/support/curve_golden.txt` records every curve type over one fixed point set (the projection-golden pattern), so any later change to curve maths is a visible diff rather than a silent drift.

## 20. D-20 — `Line` accepts constant accessors; `LineNx` honours `:curve`

**Context.** `Line.x/2` and `Line.y/2` matched only a function or an atom while `Area` and `Arc` also took a number, so the same constant baseline needed a lambda on one generator and not another. `LineNx.generate_path/3` documented a `:curve` option it never read (#14).

**Decision.** `Line` normalises a number to `fn _ -> n end`, exactly as `Area` does. `LineNx.generate_path/3` reads `:curve` (default `:linear`) and `:curve_opts` (default `[]`); `:linear` keeps the direct `M`/`L` build and every other curve passes the scaled points through `Visualize.Shape.Curve.generate/3`. Implementing the option was chosen over deleting the documentation because the point of `LineNx` is the vectorised scaling, which a curve does not disturb.

**Consequences.** Default output of both is unchanged. A `LineNx` call with a curve pays the curve's per-point cost after the batch scale, which is the same cost `Line` pays.

## 21. D-21 — `Arc` is a port of d3-shape's arc: padding and corner radius are applied

**Context.** `Arc` stored `corner_radius` and `pad_angle` and rendered as if both were zero; `pad_radius` had no setter; the facade lacked `corner_radius/2`, `sort/2` and `sort_values/2` (#14). A pie with padded, rounded slices — the standard donut on a dashboard — could not be drawn.

**Decision.** `generate_path/2` is d3-shape's `arc` sector branch, ported line for line: the per-ring padding shift `asin(rp / r · sin(ap))` with collapse to the mid-angle, the corner radius limited to half the ring thickness and (for sectors under a half-turn) by the sector's own edge geometry, `cornerTangents` for the corner circles, and a small port of d3-path's `arc` so the emitted `A` commands — including the implicit `L` to an arc's start — are byte-faithful to d3. Two departures: an arc with no outer radius or no angular extent is an empty path rather than d3's degenerate `M … Z` (there is nothing to draw, and spec/04 §6.2 already said so), and d3's NaN-driven collapse of a ring whose pad shift has no arcsine is written as an explicit branch. With the port come two behaviours the old generator lacked: the radii swap when `r1 < r0`, and the full ring closes with `Z`. `pad_radius/2` sets the pad radius (`nil` restores the default). The facade gains `corner_radius/2`, `pad_radius/2`, `sort/2` and `sort_values/2`.

**Consequences.** Every arc with a non-zero `corner_radius` or `pad_angle` renders differently — the shape callers asked for. Plain sectors are byte-identical to before. The reference strings and the tangent-geometry checks are in `test/visualize/shape/arc_stack_test.exs`; the corner path was checked against the geometry by hand (the corner centre lies `r1 − rc` from the origin, its tangent points on the edge and the ring), not against a d3 run, since no JavaScript runtime is available here.

## 22. D-22 — `Stack` series are in key order; `:diverging` and `:wiggle` are d3's

**Context.** `Stack.generate/2` returned series in stacking order, so a caller colouring by key had to search for each key after any `order` but `:none`; `:diverging` neither accumulated negatives nor separated them from positives; `:wiggle` was `:silhouette` under another name (#14).

**Decision.** As d3-stack: series are returned in key order and each carries `index`, its position in the stacking order. The offsets take that order as a permutation. `:diverging` and `:wiggle` are direct ports of `stackOffsetDiverging` and `stackOffsetWiggle`; `:none`, `:expand` and `:silhouette` keep their values, expressed in the same shape (a baseline on the bottom series, then stacking). `:expand` keeps the existing "all zero when the column total is zero" rule where d3 would leave a mixed-sign column that sums to zero unnormalised. `:insideout` keeps its sum-descending interleave; d3 orders by peak position (`orderAppearance`), which is out of #14's scope and unchanged.

**Consequences.** The series list is a different permutation than before for any `order` other than `:none`; a caller that indexed the list by stacking position must use `index` instead — none exists in this repository or in `examples/`. Every point map gains nothing; every series map gains `index`. The d3 algorithms were hand-run for the reference layouts in `test/visualize/shape/arc_stack_test.exs`.

## 23. D-23 — Axis labels sit away from the plot; band ticks are centred

**Context.** `Axis` computed the `:top` label's `y` as `−k·i − p`, which with `k = −1` is `i − p = +3`: the label sat below the axis line, inside the plot, overlapping the marks. On a `Band` scale every tick sat at the band's start edge, so a bar chart's labels hung off the left of each bar (#14). Every metresis panel with a top axis or a categorical axis showed both.

**Decision.** d3-axis's behaviour: the label offset is `k·(tick_size_inner + tick_padding)` for `:top` (the other three orientations were already right), and the tick position is `apply + offset + max(0, bandwidth − 2·offset) / 2`, rounded when the band scale rounds — d3's `center`, which keeps `offset` meaning "pixel offset" while still landing the tick in the middle of the band. The bandwidth comes from the scale protocol, so no orientation or scale type is special-cased.

**Consequences.** Every `:top` axis moves its labels by `2·(i + p)`; every band axis moves its ticks by half a band. Callers that had added `bandwidth / 2` through `offset/2` to centre ticks by hand now get `offset + max(0, bandwidth − 2·offset) / 2` — for the usual `offset = bandwidth / 2` that is `bandwidth / 2` again, so they are not double-shifted, but they should drop the workaround. `test/support/axis_golden.txt` records the rendered SVG of every orientation over a linear, a band and a rounded band scale.

## 24. D-24 — `Format.number/2` groups the magnitude; `formatter/1` is d3-format's parser

**Context.** `number/2` grouped the signed digit string, so `−123456` came out as `"-,123,456"` and `−0.5` lost its sign entirely. `formatter/1` classified a specifier by substring in the order `s, %, e, f, d`, so `"e"` anywhere selected exponential and no fill, alignment, sign, width, zero padding, `~` or the `g`/`r`/`b`/`o`/`x`/`X`/`c` types existed (#14).

**Decision.** `number/2` formats `abs(value)` and prepends `-` afterwards, hiding it when the magnitude rounds to all zeros. `formatter/1` is a port of d3-format: the specifier regular expression, the `n` and no-type aliases, precision clamping, the type formatters (`toFixed`, `toExponential` and `toPrecision` reproduced over Erlang's `float_to_binary/2`, d3's `formatRounded` and `formatPrefixAuto` for `r`/`p`/`s`), `formatTrim`, the sign conventions, the `$`/`#` affixes, grouping before or after zero padding with d3's width limit, and the four alignments. One locale departure: the minus is ASCII `-` rather than d3's U+2212, because every other formatter in the module and every axis label already uses `-`. `exponential/2` keeps Erlang's exponent form (`1.23e3`) since spec/05 §2.4 documents it; the parser's `e` type produces JavaScript's (`1.23e+3`).

**Consequences.** Outputs of `formatter/1` change wherever the old classifier was wrong (`"e"` in a specifier that meant fixed, `".2e"` now `1.23e+3`, `"d"` on a float now rounds like d3). The table in `test/visualize/axis_format_test.exs` carries d3-format's documented examples and edge cases (`~`, `(`, `^`, `0` with `,`, `#x`, sub-yocto `s`); an invalid specifier raises `ArgumentError` instead of silently formatting with `to_string/1`.

## 25. D-25 — `Format.time/2` is a one-pass strftime tokenizer

**Context.** `time/2` applied eight `String.replace/3` calls in sequence, so a directive's output was re-scanned by the next replacement, there was no `%%`, and `%y`, `%j`, `%a`, `%I`, `%p`, `%Z` and the rest of strftime were unsupported (#14).

**Decision.** The format is tokenised once — `%` plus one character is a directive, everything else literal — and each directive is looked up against a fixed table: the original eight plus `%y %e %j %I %L %p %a %A %U %w %Z %z` and `%%`. A trailing lone `%` and an unknown directive pass through verbatim, as d3-time-format leaves an unknown directive in place. `%Z` and `%z` read a `DateTime`'s zone fields and are empty for `Date` and `NaiveDateTime`; no zone conversion is performed. Weeks under `%U` start on Sunday, as in C and d3, which differs from the Monday-based time ticks of D-16 because `%U` is a display convention, not a tick interval.

**Consequences.** Existing formats produce the same output unless they contained `%%` or a directive whose output contained `%`-sequences. Consumers can format any label d3-time-format's common subset can; `%f`, `%q`, `%V`, `%G` and the locale-dependent `%c`/`%x`/`%X` are not provided and pass through, which is visible rather than silent.

## 26. D-26 — `Band` is an element mark: one `:rect` per datum, index-aligned

**Context.** A state timeline — *which state was this in, and for how long* — colours every block by its datum. The path generators return one `d` string, which carries no per-datum style, and `Visualize.Shape.Area` with a step curve cannot change fill mid-path; metresis (#1) had no primitive to build from.

**Decision.** `Visualize.Shape.Band` returns a list of `Visualize.IR.Element` rectangles from `generate/2`, one per datum in data order, with the fill accessor's value in each element's style. It reuses the `Area` accessor vocabulary (`x0`, `x1`, `y`) and adds `height` and `fill`, all in pixels: the caller applies the x scale in the accessors exactly as for `Line` and `Area`, so a band and the line above it share one scale pipeline. `generate_path/2` is kept for the uniformly filled case and folds every rectangle into one path.

**Consequences.** `Visualize.Shape.generate/2` is no longer path-or-data: for `Band` it returns elements, which render through `Visualize.Render` like any scene-graph node. A zero-width datum is still emitted, so the element list can be zipped with the data. The rectangles are separate DOM nodes; a timeline of thousands of states meets the SVG ceiling (spec/00) as any other mark does.

## 27. D-27 — Annotations take domain values and a scale

**Context.** Vertical rules and shaded x-bands were hand-rolled per chart as raw SVG, outside the scale and margin system, and misaligned the moment a margin changed (#1).

**Decision.** `Visualize.Shape.Rule` and `Visualize.Shape.XBand` are generators over a list of annotations whose x accessors yield *domain* values, mapped through the scale given to `scale/2`; with no scale the values are pixels, so they compose with a caller's own mapping. `Rule.new/0` reads each datum as its own value, so a list of instants is valid data. Each annotation renders as a `:group` element (a line or rect, plus a `:text` label when set) styled with `:current_color` and a `class`, so CSS can restyle it. `XBand`'s default fill is the brush selection's, so a live selection and a recorded window read alike. Neither has `generate_path/2`: a label is not a path.

**Consequences.** A rule follows the axis it annotates whatever the margins, because both read the same scale. The label position is fixed (right of the upper end, 10 px in); a caller wanting another placement moves or replaces the text child.

## 28. D-28 — `PercentileBand` is a composition with a fixed output shape

**Context.** A median line with p25–p75 and p5–p95 bands around it is composable from `Visualize.Shape.Area` and `Visualize.Shape.Line` today, and was verified to be; but the composition is fiddly enough that every consumer would do it slightly differently — different band order, different handling of gaps, curves applied to the line and not the bands (#1).

**Decision.** `Visualize.Shape.PercentileBand` holds one `x`, one `median`, and two `{lo, hi}` pairs, and `generate_path/2` returns exactly `%{outer:, inner:, median:}` built by delegating to `Area` and `Line` with the same `defined`, `curve`, and `curve_opts`. It adds no geometry of its own: each path is byte-identical to the standalone generator's, which is the whole guarantee. An unset band or median is `nil` in the map rather than an empty path, so a caller can tell "not asked for" from "no defined run".

**Consequences.** `Visualize.Shape.generate/2` returns a map for this generator. Consumers get one place to change the band convention. Styling stays with the caller, as for every path generator.

## 29. D-29 — Brush helpers work on the axes they are given

**Context.** `Visualize.Hooks.Brush.selection_to_domain/2` and `filter_selection/3` fetched both scales with `Keyword.fetch!/2`, so an `"x"` time brush — the common dashboard gesture — could not be converted without inventing a y scale (`KeyError :y_scale`), and the filter tested a `y0 = y1` band the hook had not meant (#1, acceptance note).

**Decision.** Each helper reads the scales it is given. With one scale, `selection_to_domain/2` returns a `{start, stop}` pair in domain units, in pixel order as d3's `selection.map(scale.invert)` would give; with both, the four-key map as before. `filter_selection/3` tests only the axes whose scale is present. Neither scale is an `ArgumentError`: a brush with no axis is a programming error, not an expected condition (spec/11 §5).

**Consequences.** Existing two-scale callers are unchanged. One-axis callers get a tuple, not a map, so the return type follows the arguments; the spec states both shapes. The y-only pair is in pixel order, which under a flipped range is descending in the domain — documented rather than sorted, since sorting domain values of arbitrary type would need a comparator the helper does not have.

## 30. D-30 — `Scale.Radial` ticks divide the turn; `nice/1` is identity

**Context.** `Visualize.Scale` was entirely cartesian; a cyclic quantity — bearing, hour of day, day of year — needs a scale whose range is an angle (#1). Reusing `Linear` with a range of `[0, 2π]` gets the mapping but the wrong ticks: the nice-step sequence gives `0, 100, 200, 300` for a bearing domain, and `nice/1` would extend `[0, 360]` to `[0, 400]`, breaking the cycle.

**Decision.** `Visualize.Scale.Radial` interpolates exactly as `Linear` (the same struct shape, range in radians, default one full turn) but `ticks/2` returns `count` equal divisions of the domain — the count exact, the last division dropped when the range is a full turn since it coincides with the first — and `nice/1` is identity. It implements `Visualize.Scale.Behaviour` in full, so the facade and the protocol test cover it; angles follow `Arc`'s clockwise-from-12 convention so a bearing domain needs no offset.

**Consequences.** `ticks/2` is the one protocol operation whose count is a guarantee rather than a hint; the spec says so. A caller who wants nice-step ticks on an angular axis uses `Linear` with the same range. Values outside the domain extrapolate past a full turn unless clamped; wrapping a cyclic value modulo its period is the caller's job, as with any scale.

## 31. D-31 — `Rose` is `Arc` over a radial scale

**Context.** With `Scale.Radial` in place the missing piece for a wind rose was small: a mark that centres one `Arc` sector on each datum's angle and lengthens it by a value (#1). `Shape.Arc` already does the angular geometry, padding included.

**Decision.** `Visualize.Shape.Rose` holds an `angle` and a `width` accessor in the scale's domain units, maps `angle ± width / 2` through `scale/2`, and delegates each datum to `Arc.generate_path/2` with the radius and pad-angle accessors. It adds no geometry of its own — every sector is byte-identical to the `Arc` call with the same numbers — and returns a list of paths, one per datum, so a stacked rose is several roses with rising inner radii, drawn by the caller. No fill accessor: as with `Arc`, styling is the caller's.

**Consequences.** A sector straddling the domain's origin (bearing 0, width 45) spans negative radians, which `Arc` draws correctly since it never reduces its angles modulo a turn. A datum with a zero outer radius is an empty path, kept in the list so it stays index-aligned with the data.

## 32. D-32 — The `d` serialisers fold negative zero

**Context.** `Visualize.Backend.SVG.path_data/1`, `Visualize.Backend.Canvas` and `Visualize.IR.Path.to_string/1` printed a float that is `-0.0`, or rounds to it at four decimals, as `-0`: an `Arc` sector whose inner edge is the origin ended `L0,-0Z`. Valid SVG, but a byte difference in every path golden for a value whose sign is not a property of the maths; D-6 had already settled the same question for the projection golden, and the rose goldens were folding `-0` in the test instead.

**Decision.** Every `d` serialiser adds `0.0` after rounding, so `-0.0` and anything that rounds to it print as `0`. The contract in [02-architecture](02-architecture.md) §3 gains the clause; the goldens assert raw strings.

**Consequences.** No `-0` coordinate is emitted by any backend. A caller that read the sign of a zero coordinate out of a path string never had a contract to rely on.

## 33. D-33 — `Curve.basis/1` is d3's `curveBasis`

**Context.** The original `basis/1` emitted one `C` per sliding window of four points and a closing `C` from the penultimate data point, so an `n`-point spline had `n − 3 + 1` segments instead of `n − 1`, skipped its last two knots, and kinked into the endpoint. The per-curve golden written for #25 made it visible (#28).

**Decision.** `basis/1` is the d3-shape `curveBasis` algorithm exactly, as written in [04-shapes-and-curves](04-shapes-and-curves.md) §5.3: leading `L` to `(5p0 + p1)/6`, a `C` per point from the third on, a closing `C` and a trailing `L` to the last point. Fewer than three points remain `:linear`.

**Consequences.** Every basis path changes shape (the old one was wrong, not merely different); only the `basis` line of `test/support/curve_golden.txt` moved. A property test holds the segment count and continuity for any point set.

## 34. D-34 — One SVG serialiser behind both bridges

**Context.** The same IR root rendered correctly through `Visualize.Backend.SVG` and incorrectly through `Visualize.SVG.Element.from_ir/1`: the backend wrote `viewBox` while the bridge copied `view_box` and `Visualize.SVG.Renderer` hyphenated it to `view-box`, and the bridge's root carried no `xmlns` (D-11). Path data and transforms each had two serialisers (`Backend.SVG.path_data/1` with `Float.to_string/1`'s exponent forms, D-12; a private transform printer that never used the single-argument `scale`), and a `points` list reached the bridge unformatted (#17).

**Decision.** `Visualize.SVG.Renderer.attribute_name/1` is the one attribute-name map: hyphenate, except the camel-cased SVG names (`viewBox`, `preserveAspectRatio`, `gradientUnits`, `clipPathUnits`, …), which is what keeps `clip_path` a presentation attribute and `clip_path_units` a camel-cased one. `Visualize.Backend.SVG` renders tags, attributes (nil-dropped, sorted by SVG name) and text through the renderer's functions; a root passes its attrs through, so `view_box` reaches the map; `from_ir/1` adds `xmlns` to a root, renames `view_box` to `viewBox` and formats a points list. `Backend.SVG.path_data/1`, `Visualize.SVG.Path.to_string/1` and `String.Chars` delegate to `Visualize.IR.Path.to_string/1`; `Backend.SVG` serialises transforms with `Visualize.IR.Transform.to_string/1`; `Visualize.IR.Path.format_number/1` is the shared number formatter, which also gives transforms the negative-zero fold of D-32. `stop` self-closes in both.

**Consequences.** `test/visualize/svg/bridge_test.exs` renders one scene of every element type through both paths and asserts byte equality, so a divergence is a red test rather than a browser-only symptom. A `:rotate` or `:scale` transform on an IR element now prints as `Visualize.IR.Transform.to_string/1` prints it (`scale(2)` for equal factors), and an arc's rotation prints formatted (`0` rather than `0.0`); nothing in this repository or in `examples/` compared those strings.

## 35. D-35 — `IR.Path.transform/2` takes an affine matrix

**Context.** `transform/2` applied an arbitrary function to every coordinate pair, including relative deltas and the `{x, 0}` / `{0, y}` stand-ins for `H`/`V`, so any function with a translation moved relative segments and single-axis lines by the wrong amount, and the contract's "MUST be linear" clause could not be checked (#17).

**Decision.** The argument is an affine matrix `{a, b, c, d, e, f}` or a `Visualize.IR.Transform`, folded by the new `Visualize.IR.Transform.to_matrix/1` in SVG composition order. Absolute points get the full map, deltas the linear part; the current point is tracked so `H`/`V` are exact — they stay single-axis when the transform preserves that axis and become `L` otherwise — and an arc's ellipse is mapped exactly through the closed-form SVD of the 2×2 product, in canonical form (`rx ≥ ry`, rotation in `[0, 180)`), the sweep flipping under a reflection. A function argument no longer matches: it was never sound for paths with relative commands, and no caller in this repository or in `examples/` passed one.

**Consequences.** The same matrix serves the binary encoder's transform fold (spec/09 §4.3.6). Integer inputs stay integers under an integer matrix; a `Transform` yields floats. `test/visualize/ir/path_transform_test.exs` checks translation invariance of deltas, `H`/`V` under rotation and scale, the arc image, and holds the identity and translate-and-back properties over random paths.

## 36. D-36 — The binary path stream is lossless and round-trip tested

**Context.** `Visualize.Backend.CanvasBinary` chose the compact `path` record whenever a path had no `C`, `Q` or `A`, collecting only `M`/`L` end points — so `Z`, `H`/`V`, every relative command and every second subpath vanished from the stream, which is exactly what a step curve or a multi-segment `defined` line produces. In the full stream, `S`/`s`/`T`/`t` encoded to zero bytes while still being counted, desynchronising the decoder. The transform fold pre-multiplied some operations and post-multiplied others and ignored four of the seven; `rgba(0,0,0,1)` raised in `String.to_float/1`; named colours were black; and the moduledoc's opcode table was stale (#17). No decoder existed, so none of this could be seen from Elixir.

**Decision.** The compact record is used only for one `M` followed by `L` commands, the one shape it holds without loss; everything else is a `path_cubic` stream. `Visualize.IR.Path.expand_smooth/1` rewrites the smooth curves to `C`/`Q` by SVG's reflection rule before encoding, and `absolute/1` (the same walker, for targets without relative commands) joins it on `IR.Path`; the encoder's silent fallback clause is gone, so an unknown command fails to match instead of encoding to nothing. Transforms fold through `Visualize.IR.Transform.to_matrix/1` (D-35). Both the IR and the `SVG.Element` encoder parse colours with `Visualize.Color.parse/1`. `test/support/canvas_binary_decoder.ex` decodes every record of spec/09 §4–5 from the specification's layouts, and `test/visualize/backend/canvas_binary_test.exs` holds `decode(encode_path!(path)) == expand_smooth(path)` over random paths, the compact-form choice, the matrix fold for every operation and for order, the colour cases and the moduledoc table.

**Consequences.** Streams for closed, stepped or multi-subpath paths grow (17 bytes per command against 16 per point) and draw correctly; a polyline is byte-identical to before. A `0xFF` transform is now right for every operation list, which the hooks must apply with `ctx.transform`, not `setTransform` (spec/09 §4.3.6). `Visualize.Color.parse/1` downcases its input, so `"SteelBlue"` resolves too.

## 37. D-37 — Every Canvas output is executable

**Context.** `Visualize.Backend.Canvas` emitted `moveTo_rel`, `bezierCurveTo_smooth`, `lineTo_h`, `arcSvg` and the like as command tuples; the `:js` serialiser printed them as comments and `drawImage` as a commented call, and the JSON hook skipped them as unknown methods — so a step curve, a relative path or an arc drew nothing on Canvas. A group's style never reached its children, which lost `Visualize.Backend.Hybrid` its `:dynamic_style` for lists, and `render_scene/2` lacked the two binary formats `render_element/2` had (#17).

**Decision.** `path_data/1` normalises the path with `Visualize.IR.Path.absolute/1` and maps the result to Canvas methods only; an arc becomes an `ellipse` call by the SVG endpoint-to-centre conversion in `Visualize.Backend.Canvas.Arc`, done on the server rather than in each hook. So the `:commands`, `:json` and `:js` outputs are all directly executable, not just `:js`. A group emits its style setup after its transform inside `save`/`restore`. `drawImage` loads the image and draws in `onload` under the transform that was current. `render_scene/2` concatenates per-element binaries for `:binary` and `:binary_base64`. Booleans serialise as literals. The comment fallback is gone: an unknown tuple raises.

**Consequences.** The 3.3.2 table is shorter and the `*_rel`/`*_smooth`/`lineTo_h*`/`arcSvg*` tuple names no longer exist; a consumer that matched on them (none in this repository or in `examples/`) sees `lineTo`/`ellipse` instead. The `CanvasChart` hook needs no arc helper. `test/visualize/backend/canvas_test.exs` renders a path of every command kind and asserts no `//` in the JavaScript, checks the arc conversion against hand-computed centres, and holds the group style and scene binary contracts.

## 38. D-38 — Incremental scrolling: a zero delta is `:none`, regions are bounded, the callback sees the margin

**Context.** `scroll_mode({0, 0}, _)` fell through to `:full_redraw`, so a no-op scroll event re-sent the whole viewport; `region_count` was documented 1–3, written unchecked from a list length, and `exposed_regions/2` produced at most two; `Visualize.Incremental` promised a `"canvas_full"` event it never emitted and stored a `:margin` nothing read (#17).

**Decision.** `scroll_mode/2` returns `:none` for a zero offset, and `Visualize.Incremental.scroll/2` answers it with a `"none"` payload — same event name, empty binary, nothing encoded — so the caller's pipeline is unchanged and the hook ignores it. `encode_incremental/3` raises `ArgumentError` above three regions or for a zero offset; the docs say 0–2 from `exposed_regions/2` and 0–3 in the record. `build_element` receives `margin` in its options map for every build; `render_viewport/1` keeps passing the whole dataset, and the docs now say so and why: whether a full frame needs points outside the viewport depends on the mark, which only the callback knows. The `"canvas_full"` promise is deleted.

**Consequences.** A zero-delta scroll costs nothing. Callers that relied on `:full_redraw` for `{0, 0}` (none in this repository; `examples/` never sends one) would now see `"none"`. `test/visualize/incremental_test.exs` covers the classification, the bounds, the `"none"` payload and the options map.

## 39. D-39 — The stream benchmark measures time with its clock only

**Context.** `Visualize.Benchmark.stream_benchmark/1` computed elapsed time as `now − (end_time − frames)`, subtracting a frame count from a timestamp, so `fps` was `frames / (frames − overrun)` — about one thousand for any backend, whatever the machine did (#17).

**Decision.** The two loops are one `stream_loop/5` over a frame-rendering function; it reads a clock at the start and once per iteration and reports `last − first` as the elapsed time. The clock is the `:clock` option (default `System.monotonic_time(:millisecond)`), so `test/visualize/benchmark_test.exs` runs the whole benchmark on a clock that advances ten milliseconds per reading and asserts the frame count, the elapsed time and the frame rate exactly.

**Consequences.** Reported frame rates are true rates; the historical `format_stream_report/1` numbers were meaningless and are not comparable. The option is public API, which is the honest price of a testable benchmark.

## 40. D-40 — The canvas hooks ship in `Visualize.Hooks`

**Context.** `Visualize.Backend.Hybrid`, `Visualize.Backend.CanvasBinary` and `Visualize.Incremental` all named a client hook — `CanvasChart`, `CanvasBinaryChart`, `CanvasIncrementalChart` — that only `examples/` carried, inline in a layout, with two diverging copies of the binary decoder (one applied a full matrix with `setTransform`, one double-drew circles, neither handled the relative arc sub-opcode). `Hybrid`'s doc also promised a `:js` default the code did not have (#17). metresis's dense panels will run on these hooks.

**Decision.** Three modules — `Visualize.Hooks.Canvas`, `Visualize.Hooks.CanvasBinary`, `Visualize.Hooks.CanvasIncremental` — carry the examples' JavaScript with the debug logging removed and one decoder, `executeVisualizeBinary`, written against `Visualize.Backend.CanvasBinary.Opcodes`: every opcode, sub-opcode and transform kind has a case, `0xFF` composes with `ctx.transform`, circles and rectangles fill one path for the draw records that follow, and an unknown byte throws. `Visualize.Hooks.js_code/0` bundles all five hooks in one ES module with the decoder exported. `CanvasChart` replays `data-commands` (JSON) or `data-script` (JavaScript), the two attributes `Hybrid` emits; `CanvasIncrementalChart` ignores mode `"none"` (D-38). The `Hybrid` doc states the `:json` default.

**Consequences.** A host installs one file and has every hook the library's own output needs; `examples/` can drop its inline copies. The test holds the bundle's exports and the decoder's byte coverage, so an opcode added to `Opcodes` without a `case` fails in Elixir before it desynchronises a browser.

## 41. D-41 — Hierarchy, tidy tree, partition and treemap follow d3-hierarchy

**Context.** Four layout defects verified under #16: `Visualize.Layout.Hierarchy.stratify/2` attached a snapshot of each child at the moment it was appended, so a grandchild listed after its parent was lost (the moduledoc's own example produced three nodes); `Visualize.Layout.Hierarchy.path/2` prefixed the answer with every ancestor of the lowest common ancestor; `Visualize.Layout.Tree.generate/2` was not Reingold–Tilford — its second walk handed every child the same modifier, so cousin subtrees overlapped (`A1 = B1`, `A2 = B2` for the two-by-two tree); and `Visualize.Layout.Partition` and `Visualize.Layout.Treemap` filtered zero- and `nil`-valued children out of the returned hierarchy.

**Decision.** Port d3-hierarchy. `stratify/2` resolves every parent link over the whole input and builds the tree from the root down, so the result depends only on the links; the root rule, list-order children and the silent drop of unknown parents are unchanged. `path/2` is d3's `node.path`: source-side chain up to the lowest common ancestor, then target-side chain down, nodes matched by the `data` of their ancestor chain (a node equals its own snapshot in a descendant's `parent`). `Tree.generate/2` is d3's `tree` — Buchheim's linear-time algorithm with threads, apportioned shifts and accumulated modifiers — run on an id-keyed store of plain maps in place of d3's mutable wrappers; raw coordinates put the root at `x = 0`, and the `size` normalisation (leftmost 0, rightmost `width`) and `node_size` multiplication of spec/06 §2.1 are kept as they were, so `size` mode does not carry d3's half-separation margins. `Partition` and `Treemap` weigh a `nil` or non-positive value as 0, tile every child, give a weightless child a zero-extent rectangle at the slot it would occupy, and lay its subtree out below it; an inner rectangle or tile that a padding inverts collapses to its midpoint as d3's `positionNode` does, in place of the negative extent or the unpositioned subtree the old code left. The `:binary` tiler's half-split is guarded so the prefix is never empty — with zero-weight children the old split could recurse on the same list forever.

**Consequences.** Every descendant of a partitioned or treemapped root carries a rectangle, so a consumer no longer has to guard against vanished nodes; one that relied on zero-valued children being absent must now skip zero-area rectangles itself. Raw tidy-tree coordinates are centred on the root rather than starting at 0; only the raw mode moves, `size` and `node_size` output for a single-parent tree is unchanged. `test/support/tree_golden.txt` (two trees, three scaling modes) and `test/support/treemap_golden.txt` (five tilers and the partition over a hierarchy with a zero-valued child) are the recurrence guards, with `test/visualize/layout/hierarchy_test.exs` holding the stratify order-independence and path cases.

## 42. D-42 — Sankey and circle packing are ports of d3-sankey and d3-hierarchy pack

**Context.** `Visualize.Layout.Sankey` placed every node in one column under `:center`, made `:justify` identical to `:left`, mirrored the diagram under `:right` so links flowed backwards, stored `link_sort` without consulting it, sized node heights on a per-layer scale and link widths on a global one (so the ribbons of a node did not add up to its height), and assigned layers in an order that depended on `MapSet` iteration. `Visualize.Layout.Pack` separated siblings by twice the padding, enclosed them in a bounding-box circle rather than the minimal one, and fell back to `:rand` when its tangent search found no candidate, so a layout could differ between runs (#16).

**Decision.** Both modules are ports of their d3 references. Sankey: `depth` and `height` are longest paths (a cycle stops after `n` rounds instead of raising as d3 does); the four alignment functions are `sankeyLeft`, `sankeyRight`, `sankeyCenter` and `sankeyJustify`; one scale `ky`, the least over the columns, sizes nodes and links, so no minimum link width remains; the vertical pass is d3's — centred columns, `alpha`/`beta` relaxation towards the ideal link positions in both directions, two-sided collision resolution, links re-ordered by their neighbour's position unless `link_sort` is given, in which case it is applied once. This library's own conventions stay: link `y0`/`y1` are top offsets (d3 stores centres), the ribbon path of §7.4 is unchanged, and `node_align/2` now rejects an unknown atom. Pack: `packSiblings` (the front chain) and `packEnclose` (Welzl over a shuffle drawn from d3's constant-seeded LCG) replace the tangent search, the bounding-box circle and the random fallback; children are packed in input order, not by radius; padding follows d3's two-pass scheme, so the sibling gap is `padding * r0 / r1` output units, where `r0` and `r1` are the unpadded and padded root radii.

**Consequences.** Sankey output changes for every input: columns spread across the width under every alignment, sinks share the last column under `:right` and `:justify`, and links tile their nodes exactly. A caller that relied on the 1-pixel minimum link width must draw thin ribbons itself. Pack layouts are reproducible and tighter; a consumer that depended on the descending-radius order of the old packing sees the input order instead. `test/support/sankey_golden.txt` (five nodes, four alignments) and `test/support/pack_golden.txt` (five leaves, with and without padding) are the recurrence guards, and the pack property test checks non-overlap, containment and determinism over random sibling sets.

## 43. D-43 — `Geo.Delaunay` is a Delaunay triangulation with half-edges

**Context.** `Visualize.Geo.Delaunay.new/1` inserted points into a super-triangle with an in-circle test whose sign depends on vertex order, while it built new triangles from boundary edges whose orientation it had discarded; the result was neither Delaunay nor a triangulation (40 random points gave 147 triangles, 138 with a point inside their circumcircle). `new([])` returned `hull: [0, -1]`, `halfedges` was always `[]`, and the hull came from a separate gift wrap with an "infinite loop" guard (#16).

**Decision.** Incremental insertion with ghost triangles (Shewchuk's formulation) rather than a finite super-triangle, which can lose thin hull triangles however large it is made: every hull edge carries a ghost for the region beyond it, the cavity rule is one predicate over real and ghost triangles, and the hull is read off the surviving ghosts, so triangles and hull cannot disagree. Every triangle is kept counter-clockwise and the in-circle determinant is normalised by orientation, so `det > 0` is "inside" for any vertex order. `halfedges` is filled with d3-delaunay's semantics — the field was already public, and filling it is what lets `Visualize.Geo.Voronoi.edges/1` stop searching the triangle list, a change left for later; the quadratic `edges/1` keeps its contract. Coincident points after the first are dropped; all-collinear input gives no triangles and a two-point hull; fewer than three points list every index. Predicates are plain floating point, adequate for general position and for exactly representable degenerate coordinates; adaptive-precision arithmetic (d3's `robust-predicates`) is out of scope. `Visualize.Geo.Voronoi` is untouched and still does not extend hull cells to infinity (spec/07 §4.1).

**Consequences.** Triangulations are correct, so Voronoi cells and `neighbors/2` are now meaningful; the triangle list changes for every input, and triangle vertices are now counter-clockwise where before their order was arbitrary. Construction remains quadratic — `d3-delaunay`'s sweep would be `O(n log n)` — which is acceptable at the sizes this library draws. `test/visualize/geo/delaunay_test.exs` holds the StreamData property (empty circumcircles, `2n - 2 - h`, counter-clockwise triangles, convex hull, paired half-edges, every point present) and the degenerate fixed cases.

## 44. D-44 — Rotation inverts in reverse order, collision pushes both nodes, every computed range has a step

**Context.** Three defects verified under #16. `Visualize.Geo.Projection.invert/3` undid the spherical rotation by `phi` then `gamma` — the forward order — so it was exact only when at most one of the two was non-zero. `Visualize.Layout.Force.Forces.apply_collision/3` pushed only node `i` of each overlapping pair. `Visualize.Random.binomial/2` and `samples/2` iterated `1..n`, which for `n = 0` is the descending range `[1, 0]`, so `binomial(0, p)` ran two trials and `samples(fun, 0)` returned two samples — the third instance of the class after `Data.range/3` and `Quantize.thresholds/1` (#13).

**Decision.** The inverse rotation is composed in reverse: gamma about z, then phi about x, then lambda added back; the rotation axes and the `lon - lambda` sign convention of spec/07 §1.4 are kept as documented, so the projection golden (rotation `{0, 0, 0}`) is unchanged and no consumer's map moves. Flipping to d3's sign would have been a silent contract change for every caller of `rotate/3,4` with nothing gained but conformity; it can be its own proposal if ever wanted. The collision force accumulates, over every pair `i < j`, an equal and opposite half of the overlap correction on both nodes before touching any velocity, so it is symmetric and order-independent; the equal split of spec/06 §8.2 is kept rather than d3's radius-squared weighting, since the specification states the equal split and nothing in the library depends on the difference. Every range in `lib/` whose upper bound is computed — 44 sites across 20 modules, from `Random` and `Forces` to `Voronoi.cells/1`, `Chord`, `Stack` and the benchmark loops — now carries `//1`, so an upper bound below the lower one yields an empty range instead of a descending one; the sweep was mechanical and intentionally total, so that the class cannot recur by omission.

**Consequences.** `invert/3` is an inverse for any rotation; the property in `test/visualize/geo/projection_rotation_test.exs` runs every type but transverse Mercator (#9) at per-type tolerances. Collision layouts change wherever nodes overlapped: clusters now spread symmetrically and momentum is conserved (`test/visualize/layout/force/forces_test.exs`). `Random.binomial(0, p)` is 0 and `samples(fun, 0)` is `[]` (`test/visualize/random_test.exs`); `Voronoi.cells/1` on an empty diagram is `[]` rather than a crash; a force run or collision with `iterations: 0` does nothing instead of two passes. Ranges that were always non-empty behave as before.

## 45. D-45 — Phoenix is an optional dependency; the components render through the real scale API and are held by render goldens

**Context.** Every function component in `Visualize.Components` raised on first render: they called `Visualize.Scale.scale/2` (the facade is `apply/2`), `Visualize.Scale.color/0` and `Visualize.Scale.scheme/2` (never existed), passed `Visualize.Data.extent/1`'s tuple where `Visualize.Scale.domain/2` takes a list, and raised in `Enum.max/1` or `hd/1` on empty data (#15). Nothing had ever executed them, and the reason was deeper than the missing Phoenix in this library's own build: `examples/`, which depends on `phoenix_live_view` 1.2, compiles visualize without the component modules at all. Mix prunes the code path to a dependency's *declared* deps while compiling it, so `if Code.ensure_loaded?(Phoenix.Component)` over an undeclared Phoenix is false in every host — and the source, which called the `raw/1` that LiveView 1.x no longer imports, would not have compiled had the guard ever been true. A test-only dependency would have made the goldens green while leaving every consumer exactly where it was.

**Decision.** `phoenix_live_view` is declared `optional: true`, as `nx` already is: a host that has LiveView gets the ordering and code-path guarantee and compiles the components; a host without it never fetches Phoenix. The library's own builds therefore carry Phoenix, so the components compile in every environment, are documented, and are rendered under test. The proof that a consumer stays Phoenix-free moves out of this checkout's `MIX_ENV=prod` build into `scripts/consumer_check.exs`, the throwaway consumer [12-testing-and-conformance](12-testing-and-conformance.md) §4 always described. The seven chart components are rewritten against spec/03–05: every coordinate is `Visualize.Scale.apply/2`; a `colors` atom is `Visualize.Scale.Color.scheme/1` as the range of a `Visualize.Scale.Ordinal` over the mark indexes, a list is used the same way, and an unknown scheme or empty list is an `ArgumentError`; extents become `[min, max]`, ordered by the value's module for time values; a collapsed domain spans one unit so a single datum renders; empty data renders the frame over `[0, 1]` domains with no mark. Coordinates print through `Visualize.IR.Path.format_number/1`, and a `nil` `class` or a false `animate` emits no attribute. A private support module (`lib/visualize/components/support.ex`, hidden from the documented surface) holds what the two component modules share. `test/visualize/components_test.exs` renders each component through `Phoenix.LiveViewTest.render_component/2` on a fixed dataset and on `[]` against `test/support/components/*.svg`.

**Consequences.** `mix deps.get` in this repository fetches Phoenix, Plug and their dependencies for every environment; a consumer's dependency tree is unchanged unless it already had LiveView, in which case it now also compiles `Visualize.Components` and `Visualize.Components.Tree`. A single-datum chart puts its datum at the start of the range rather than raising; the linear and time scales themselves still divide by zero on a collapsed domain, which is a scale-level question for a proposal of its own. The `consumer-compile` job takes the time of a cold compile of `lib/`. The tree components compile again (their calls into the removed scale functions are mechanically replaced) but keep their remaining defects until the next work item of #15.

## 46. D-46 — The hierarchy components lay out with `Layout.Partition`, colour by branch and draw their labels

**Context.** The three components of `Visualize.Components.Tree` shared the scale-API defects of D-45 and had three of their own (#15): `treemap_chart/1` and `sunburst_chart/1` replaced a `colors` list with `:category10`; `sunburst_chart/1` accepted `label`, computed it and never drew it; and the sunburst carried a private angular layout — a level-by-level walk that matched nodes back to their originals by `data` and `depth`, gave equal shares to children summing to 0, and duplicated what `Visualize.Layout.Partition` already computes. The treemap coloured leaves by immediate parent while its own function-table row said top-level parent.

**Decision.** The sunburst is `Visualize.Layout.Partition` sized `{2π, radius}`, which gives the same ring radii the private layout did, and each node is drawn by `Visualize.Shape.Arc` over its `x0`/`x1` angles and `y0`/`y1` radii — the arc's clockwise-from-12 convention is the one the private path builder implemented by hand. A node whose value is not positive is a zero-width slot that draws nothing, as D-41 already settled for the layout, in place of the equal-share rule. Colour is assigned once, walking down from the root: the i-th child of the root takes the i-th colour and every descendant inherits it, in both the treemap and the sunburst, so the two agree and a colour list is honoured through the palette of D-45. Sunburst labels are drawn at `Visualize.Shape.Arc.centroid/2` under the treemap's fit test transposed to polar terms (ring thicker than 15, mid-radius arc longer than 30, truncated to the arc). A root-only hierarchy is the empty case and renders without raising. `test/visualize/components/tree_test.exs` holds render goldens for the three components on a fixed hierarchy and on a root-only one, next to the chart goldens of D-45.

**Consequences.** A treemap deeper than two levels changes colour: leaves under the same top-level branch now share its colour instead of splitting by immediate parent. A sunburst whose siblings all sum to 0 draws no arc for them where it drew equal sectors before; a sunburst now carries labels where it drew none. The tree components no longer hold any layout code of their own.

## 47. D-47 — `BrushHook` stores its bound handlers and removes those

**Context.** `BrushHook.destroyed()` called `document.removeEventListener` with `this.handleMouseMove.bind(this)` and three siblings — a fresh function each time, which `removeEventListener` matches against nothing — so every unmount of a brushed SVG leaked four `document` listeners that kept the dead hook, its element and its LiveView closure reachable (#15). The `Visualize.Hooks.Brush` module doc also stated a default brush colour of `rgba(0,0,0,0.1)` where the script applies `rgba(119, 119, 119, 0.2)`.

**Decision.** `mounted()` binds each handler once, stores it on the hook (`onMouseMove` and the rest) and adds those references; `destroyed()` removes the four `document` listeners by the same references. The capture rect's listeners are left to go with the element. The module doc states the colour the script applies. The test holds the source to the shape rather than exercising a DOM: it asserts that every `.bind(this)` in `mounted()` is a stored one, that `destroyed()` binds nothing and removes the four stored document references, and that the documented default is the applied one.

**Consequences.** Unmounting a brushed chart releases it. `ZoomHook` binds inline too but only on `this.el`, whose listeners die with the element, so it needs no clean-up and its `destroyed()` stays empty.

## 48. D-48 — `Hooks.js_code/0` exports each hook once

**Context.** The generated module declared every hook with `export const` and then appended `export { ZoomHook, … }`, a second export of each name. esbuild refuses a module that exports a name twice, so a consumer that bundles the file (metresis's `mix assets.deploy`) could not use it as written and stripped the closing list itself.

**Decision.** `Visualize.Hooks.js_code/0` emits per-hook `export const` declarations and one `export default { … }` object, nothing else. A test asserts each export name appears exactly once and that the default object lists every hook.

**Consequences.** Named imports and the default import both work; the file bundles unchanged.

## 49. D-49 — A collapsed domain maps to the range midpoint

**Context.** `Visualize.Scale.Linear.apply/2` and `Visualize.Scale.Time.apply/2` computed `(v − d0) / (d1 − d0)` and raised `ArithmeticError` when the domain's ends coincided — the extent of a single datum, or `[0, 0]` for an all-zero bar chart. `Visualize.Scale.Power` and `Visualize.Scale.Symlog` guarded the same case with `t = 0`, so the five continuous scales disagreed with each other and with d3, whose `normalize` returns a constant `0.5` for a degenerate interval. `Visualize.Components` had started widening collapsed domains itself (spec/10 §1.3), a chart-level workaround for a scale-level gap (#47).

**Decision.** `Visualize.Scale.Behaviour.normalize/3` is the one place the fraction is computed: `0.5` when the interval is collapsed, `(v − a) / (b − a)` otherwise. Every continuous scale's `apply/2` and `invert/2` use it, so a collapsed domain maps every value to the range midpoint and a collapsed range inverts to the domain midpoint. Nothing raises.

**Consequences.** A single-datum chart draws its point in the middle of the axis, as it does in d3. `Power` and `Symlog` moved from `0` to `0.5` on the collapsed case. The components' own widening stays as a chart-level policy for readable axes; it is no longer load-bearing.

## 50. D-50 — Optional-dependency modules compile warning-free without the dependency

**Context.** `Visualize.Shape.LineNx` and `Visualize.Backend.CanvasBinary` call `Nx` directly. In this repository Nx is always fetched, so the build never showed it; in a consumer that does not depend on Nx every call printed `Nx.… is undefined` while visualize compiled — nine warnings, not the one #46 first reported, once the consumer check kept the whole output.

**Decision.** Both modules declare `@compile {:no_warn_undefined, Nx}`, Elixir's mechanism for exactly this case. The calls stay direct, so a missing Nx still raises `UndefinedFunctionError` at the call as spec/04 §10.1 promises. `scripts/consumer_check.exs` compiles visualize inside the throwaway consumer with its output captured and fails on any `warning:` line, which is the recurrence guard; the consumer's own `--warnings-as-errors` never covered a dependency's compile.

**Consequences.** An Nx-less consumer builds silently. Any future optional dependency gets the same declaration or the gate goes red.
