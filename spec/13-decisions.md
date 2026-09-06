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

**Consequences.** A scale module that omits an operation no longer compiles under `--warnings-as-errors`, so the facade is total by construction. Callers that pattern-matched the tuple form of `Power`/`Symlog`/`Quantize` domains break; none exists in this repository or in `examples/`. `Quantile.apply/2` also now reaches its last bucket (the bucket search's base case returned index `0` instead of the index it had reached), which the same test covers. The remaining scale defects of #13 — time ticks, band arithmetic, quantize/colour/ordinal/linear/log/symlog tick cases, `Data.ticks/3` — are separate work items and keep their `> Decision` markers until they land.

## 16. D-16 — Time ticks follow d3-time: boundary snapping and ratio-based interval choice

**Context.** `Visualize.Scale.Time.ticks/2` chose the first interval whose length was at least `span / count`, snapped only sub-day intervals, treated the day "ceiling" as the value's own midnight (so the first tick could precede the domain), never snapped weeks, months or years, rewrote month fields without clamping the day (31 January + 1 month was an invalid 31 February), and for any span wider than `count` years fell back to daily ticks — 8,767 of them over 24 years. Every metresis time-series panel draws a time axis, so this was the milestone's first defect (#13, #23).

**Decision.** Ticks follow `d3.timeTicks`: an interval `{unit, n}` from the table in spec/03 §7.3.1, chosen as the neighbour closer in ratio to `span / count` (not the first one at least as long — at the week→month and quarter→year seams the old rule overshot by up to 4×), and beyond one year a multi-year step from the 1-2-5 nice-step sequence. Every tick is a boundary of the interval inside `[d0, d1]`: multiples of the step below a day, midnight, Monday, the 1st of the month, 1 January of a year divisible by the step. Weeks start on Monday (ISO), where d3 defaults to Sunday. `nice/1` uses the same floor and ceiling. `Visualize.Scale.Time.interval/2` exposes the choice so callers can format ticks by the interval that produced them.

**Consequences.** Tick counts stay within about `2.2×` of the hint in either direction and a long span costs tens of ticks, not thousands. The month-stepping helper clamps the day, though ticks only ever land on the 1st. The property tests in `test/visualize/scale/time_test.exs` assert ascending, in-domain, boundary-aligned ticks over random domains from a minute to two centuries. Callers that relied on the first tick preceding the domain, or on `count` giving strictly at-least-that-long intervals, see different ticks; none exists in this repository or in `examples/`.
