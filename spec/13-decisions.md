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
