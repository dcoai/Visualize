# Changelog

All notable changes to Visualize are recorded here, following
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

> **Note.** This file is written for a consumer of the library, so it says what changed in
> the surface and in behaviour, not what changed in the repository. What the library *is*,
> module by module, lives in [`spec/`](spec/README.md), which is the source of truth for
> that and is not restated here.

## [Unreleased]

`mix.exs` reads `0.1.1-dev`: the `-dev` suffix is what keeps a commit from claiming to be the
release it merely follows.

### Added

- **A theme's `:surface` slot** (#422): the plane a chart's data is laid on, between the
  background and the grid — `#eef2f6` on `Visualize.Theme.default/0`, `#23272f` on
  `dark/0`. It is a colour slot like any other: `slots/1` and `colour_slots/1` list it,
  `resolve/3` gives `var(--vis-surface, …)` on SVG and the literal on canvas, and an inline
  `:theme` node takes a `surface` key. A theme from `new/1` that names none takes the light
  value, as it does for every field it leaves out.

## [0.1.0] — 2026-09-09

`0.1.0` is the first tag. Until it, the only way to depend on this library was
`branch: "main"`, so everything below has already reached anyone tracking that branch — the
sections are therefore written as they will read from the tag onwards: **Added** is the
surface a new consumer gets, and **Changed** and **Fixed** are what moved under a consumer
who was following `main` and now has a point to pin.

Pre-1.0. The surface can still move; a breaking change opens `0.2.0` rather than bending
the meaning of a patch.

### Added

- **The declarative chart layer — `Visualize.Chart`.** A chart is a **design**: a plain map
  of atoms, numbers, strings and `Visualize.Chart.Var` placeholders, with no functions and
  no structs in it, so a design can be stored, diffed, sent over the wire, versioned and
  edited by something other than code (D-57). The imperative pipeline —
  `Scale` → `Shape` → `IR.Element` → `Render` — is unchanged and remains the layer this one
  is written on; nothing about the chart layer is mandatory.

  - `Visualize.Chart.Schema` is the design's grammar **as data**. Every key carries a facet
    (`:data`, `:geometry`, `:channel`, `:binding`, `:style`, `:meta`) and a merge rule, so a
    validator, an editor and a composition operator all read the same description instead of
    each carrying their own copy of it (D-58). `Schema.describe/1` is what the builder's UI
    is generated from.
  - `Visualize.Chart.Validator` checks a design against the schema and reports **by path** —
    `[:marks, 2, :channels, :y]` — rather than by message, so an editor can put an error
    next to the field that caused it.
  - **Frames** own the scales. A frame declares named scales whose domains may be `:auto`,
    realises them **once** from the whole bound column, never widens them afterwards, and
    renders its own furniture — axes, grid, legend, labels — with or without data (D-60).
  - **Marks** are the generators, named: `:line`, `:area`, `:band`, `:rule`, `:x_band`,
    `:percentile_band`, `:rose`, `:symbol`, `:arc`, `:path`, `:rect`, `:circle`. A mark
    names the scale each channel family reads through (D-61, D-67), and takes its paint from
    the theme's series.
  - **Transforms** are pure steps over rows, run by the frame *before* its scales are
    realised, so a transform can change what the domains infer from (D-62):
    `:filter`, `:bin`, `:stack`, `:sum`, `:sort`, `:tree`, `:cluster`, `:pack`,
    `:partition`, `:treemap`, `:chord`, `:sankey`, `:force`, `:contour`, `:density`,
    `:delaunay`, `:voronoi`, `:projection`.
  - **Styles and themes.** A style node resolves to two outputs — literal attributes for
    SVG, and CSS custom-property references for a themed page — and binds its field
    references per element (D-63). `Visualize.Theme` carries the slots; a slot renders as
    `var(--vis-…, <literal>)`, its literal always present as the fallback, so a page that
    ships no stylesheet still draws in colour (D-55).
  - **Templates**: typed source slots and `Visualize.Chart.Var` variables, bound by
    `Chart.apply/2`. A variable's default lives in its declaration, and a stored design
    keeps what its author wrote rather than being rewritten with defaults (D-59).
  - `Chart.compile/2` splits a chart into the regions that are static and drawn once and
    those that are dynamic and carry a closure, fixes each mark's render target at
    compilation, and gives the streaming window its own plot-area canvas (D-66).
  - `Chart.to_map/1`, `from_map/1`, `to_json/1`, `from_json/1` — JSON carries what JSON
    cannot hold (dates, tuples, atoms) as tagged terms, and the round trip is the identity
    (D-57). JSON needs the optional `:jason` dependency; without it the two JSON functions
    return an error value rather than failing to compile.

- **The fragment algebra — `Visualize.Chart.Build` and the operators on it.** A **fragment**
  is a partial design, and the algebra is what makes designs composable rather than merely
  storable.

  - `Visualize.Chart.Build` builds fragments through one function per schema node — a
    function per mark type, transform op and scale kind, **generated from the schema** so
    the builder cannot drift from the grammar it builds (D-79). Every option is a key of the
    node the function builds (D-78).
  - `Chart.compose/1,2` merges fragments key by key under the schema's merge rules.
    `Chart.stack/1,2` is a **second** closed operation over the same values: a cascade, where
    a higher layer overrides a lower one and the result is itself a fragment, so a stack of
    stacks is a stack (D-81). Composition unions; a cascade overrides. They are different
    questions and now have different operators.
  - **Element identity.** A mark's or label's identity is its `id`, an axis's is
    `{scale, side}`, and a matched element is replaced whole rather than deep-merged
    (D-82) — which is what lets a layer say "this one, replaced" without saying it by list
    position.
  - `Chart.explain/1` reports **provenance**: which layer each key in the result came from,
    computed from the layers rather than carried in the fragment (D-83).
  - `Chart.free_vars/1` reports the variables a design still needs, walking exactly where
    application walks; a variable bound to another variable is an error reported by path
    (D-84).
  - `extends:` on a style derives it from a parent, flattened at the lookup rather than at
    write time, so a change to the parent reaches its children (D-80).

- **`Visualize.Chart.Builder` — an embeddable LiveComponent for building designs.** Optional
  in every sense: it needs LiveView, which is an optional dependency, and it is a component
  the host mounts rather than a route the library owns. Its only output is one message to
  the host, which owns the route, the storage (`Builder.Store`) and the meaning of saving
  (D-85). The editor's nodes, controls and widgets are generated from the schema's types,
  and a composite value is read as a literal and **never evaluated** (D-86). The stack panel
  shows the layers — disabling a layer is not deleting it — the inspector is `explain/1`
  rendered, and the parameters form is `free_vars/1` rendered, editing the builder's own copy
  of the bindings (D-87, D-88). Import and export move a design as JSON.

- **New marks:** `Visualize.Shape.Band` (a state timeline: one `:rect` per datum,
  index-aligned — D-26), `Visualize.Shape.Rule` and `Visualize.Shape.XBand` (annotations
  that take domain values and a scale, not pixels — D-27),
  `Visualize.Shape.PercentileBand` (a composition with a fixed output shape — D-28), and
  `Visualize.Shape.Rose` (`Arc` over a radial scale — D-31).

- **New scale:** `Visualize.Scale.Radial`, an angle scale whose ticks divide the turn and
  whose `nice/1` is the identity, because there is no nicer boundary on a circle than the
  one you asked for (D-30).

- **Interaction hooks — `Visualize.Hooks`.** `Zoom` and `Brush` (with one-axis selection
  helpers that work on the axes they are given — D-29), `Resize`, and the three canvas hooks
  `CanvasChart`, `CanvasBinaryChart` and `CanvasIncrementalChart` (D-40). New in this
  release: `Tooltip`, which reads the datum's own fields from data attributes the **server**
  wrote on the element (D-75); `Crosshair`, which snaps to an array the server wrote once and
  draws in an overlay it owns rather than in the patched subtree (D-76); and `Legend`, where
  an entry and its series path carry the same `data-series` and toggling hides with
  `display` (D-77). The pattern throughout: **data attributes are the contract**, and a hook
  draws outside the subtree LiveView patches.

- **Tabular ingestion — `Visualize.Data.Table.rows/1`.** One door for tabular data: row
  lists, column maps, Nx tensors, Explorer data frames and anything else implementing
  `Table.Reader` (D-52). Every generator, compute and component reads its data through it
  (D-53), so a data frame is accepted wherever a list of maps is. The `:table` package is
  optional, like Nx; without it lists, column maps and tensors still work and a struct
  source raises at the call.

- **Themes and accessibility.** `Visualize.Theme` with a light and a dark palette and a
  generated stylesheet; responsive sizing as two halves — `ResizeHook` for the round trip
  and `viewBox` scaling for everything between (D-54); and a chart that names itself, with
  `<title>`, `<desc>` and `role="img"` on the root and `aria-hidden` axes (D-56).

- **Ten preset chart components** (`Visualize.Chart.Presets`): line, bar, horizontal bar,
  pie, scatter, area, stacked bar, tree, treemap and sunburst — each a preset design plus an
  assign mapping, drawn by the chart layer into the same markup the hand-written components
  always produced (D-64), and byte-identical to their goldens.

- The specification ships with the package (`spec/`), together with `API_SURFACE.md`, a
  generated golden that lists every public function the specification declares against every
  public function `lib/` defines. A function in `lib/` with no row is `unspecified`; a row
  with no function is `unimplemented`; either fails CI. It is the contract a consumer holds
  the library to, so it ships.

- `LICENSE` — MIT — and `package/0` now declares `licenses: ["MIT"]`. Before this the
  licence was unstated to anyone who received the package.

### Changed

- **`Visualize.Render.with_backend/2` is removed** (D-2). It set a backend in the process
  dictionary for the duration of a function, so any render inside that function silently
  used a backend chosen somewhere else, and restoring the previous value needed `try/after`.
  A backend is now selected only by the `:backend` option at the call site or by
  `config :visualize, default_backend:`. **Code that rendered inside `with_backend/2` must
  thread `backend:` through instead.**

- **`Shape.Stack` returns its series in key order**, not in stacking order, and each series
  carries `index`, its position in the stack (D-22). A caller that indexed the returned list
  by stacking position must read `index` instead. `:diverging` and `:wiggle` are now ports
  of d3's `stackOffsetDiverging` and `stackOffsetWiggle`; previously `:diverging` did not
  accumulate negatives and `:wiggle` was `:silhouette` under another name.

- **A collapsed domain maps to the range midpoint** in every continuous scale, and nothing
  raises (D-49). `Linear` and `Time` previously raised `ArithmeticError` on a single-datum
  extent or an all-zero `[0, 0]` domain; `Power` and `Symlog` returned the range **start**.
  All five now return the midpoint, as d3 does — a single-datum chart draws its point in the
  middle of the axis. Callers that widened collapsed domains by hand no longer need to.

- **`:top` axis labels moved off the plot, and band ticks moved to the centre of the band**
  (D-23). A `:top` axis's labels shift by `2·(tick_size_inner + tick_padding)`; every band
  axis's ticks shift by half a band. A caller who had added `bandwidth / 2` through
  `offset/2` to centre ticks by hand is not double-shifted, but should drop the workaround.

- **Negative zero is folded** in the `d` serialisers, so a coordinate that rounds to zero
  prints `0` and never `-0` (D-32), and in the projection golden, where the sign of zero is
  not a property of the maths (D-6). Path strings that differed only in a minus sign before a
  zero are now stable across refactors.

- **One `d` serialisation.** There were two path serialisers producing different strings for
  the same path; there is now one, behind both the SVG bridge and the IR (D-12, D-34, D-71).
  The tree components' link paths therefore print in the comma-separated form (D-71, #79);
  goldens that recorded the old form were regenerated.

- **Time ticks follow d3-time**: boundary snapping on every interval, ratio-based interval
  choice, clamped month stepping and multi-year intervals (D-16). A time axis that previously
  produced unsnapped or wrongly-spaced ticks produces d3's.

- **`Format.number/2` groups the magnitude**, `Format.formatter/1` is a parser for d3-format
  specifiers, and `Format.time/2` is a one-pass strftime tokenizer (D-24, D-25) — where
  before each was an approximation.

- **The scale protocol is a behaviour**, and every scale stores lists (D-15).
  `Power`, `Symlog`, `Quantile`, `Quantize` and `Threshold` implement it, so
  `Scale.apply/2`, `ticks`, `nice`, `invert` and `bandwidth` work uniformly across every
  scale type — which is what lets `Axis` stop special-casing scale kinds.

- **`Layout.Force`'s many-body force has no `:theta`** (D-4). The option was accepted and
  ignored — there is no quadtree behind it — so it is removed rather than left inert. The
  force is exact, O(n²) per tick. Passing `:theta` is now a programmer error.

- **`Geo.Projection.clip_angle/2` clips.** The value was stored and never read, so
  orthographic globes drew the back of the world over the front (D-3). `project/3` now
  returns `nil` beyond the clip angle, and azimuthal projections take d3's per-type defaults.
  **Callers that project points beyond the horizon now receive `nil` and must handle it**;
  `Geo.Path` drops them.

- **Phoenix is optional and stays optional** (D-7, D-45). `Visualize.Components`,
  `Visualize.Components.Tree`, `Visualize.Chart.Builder` and the `Phoenix.HTML.Safe`
  implementations compile only when `Phoenix.Component` is loaded; a host without LiveView
  never fetches Phoenix. The same holds for Nx, `:jason` and `:table`, and a consumer check
  runs on every pipeline to prove it.

- `Geo.Projection` and `Backend.CanvasBinary` were split into family modules, which are
  `@doc false` internals rather than public API (D-9).

- The canvas binary format gained **f32 path records** (`path32`, `path_cubic32`), which are
  the encoder's default because canvas coordinates are pixels (D-73), and a **compact
  cubic-run record** with no sub-opcodes, because that is what every curve generator emits
  (D-74). The decoder round-trips both.

### Fixed

- **`Visualize.Components` never rendered.** The component layer called a `Scale` API that
  did not exist; every component raised. It was rewritten against the real API and is now
  held by render goldens (#43). `Visualize.Components.Tree` — tree, treemap and sunburst —
  was rewritten the same way and now honours `colors` and `label` (#44, D-46).

- **`Geo.Delaunay` was not a Delaunay triangulation.** It is now Bowyer–Watson with an
  orientation-normalised in-circle test and half-edges (D-43), which also makes
  `Geo.Voronoi` correct.

- **The hierarchy, sankey and pack layouts are now ports of d3's.** `Layout.Hierarchy` gained
  `path/2` and `stratify/2`; the tidy tree is Buchheim; `Partition` and `Treemap` keep
  zero-valued children (D-41); `Sankey` has d3's alignments and one link scale; `Pack` is
  d3's `packSiblings`/`packEnclose` with a deterministic fallback (D-42).

- **Projection rotation now inverts in reverse order**, the collision force pushes **both**
  nodes rather than one, and every computed range has a step — the `0..-1` empty-range class
  was swept out of the tree (D-44).

- **Transverse Mercator `invert/3` no longer raises.** It raised `ArithmeticError` away from
  the central meridian; it is now d3's spherical inverse, returns `nil` outside the
  hemisphere, and the forward projection clips (D-5, D-51). The projection golden records the
  inverse instead of excluding it.

- **`Line` and `Area` break into subpaths at undefined data** instead of drawing through the
  gap (D-18); `Curve.natural/1` is the natural cubic spline, solved rather than approximated
  (D-19); `Curve.basis/1` is d3's `curveBasis`, which previously skipped a B-spline segment
  and started and ended in the wrong place (D-33); the step curves emit d3-identical paths
  (D-8); `Line.x/1` and `Line.y/1` accept constants, and `LineNx` honours `:curve` (D-20).

- **`Shape.Arc` applies `corner_radius` and `pad_angle`** (D-21). Both were accepted and
  ignored.

- **Band, quantize, colour, ordinal, linear, log and symlog tick defects**, and a crash in
  `Data.ticks/3` (D-17, #24).

- **`IR.Transform.scale/2`'s pipeline form** raised `FunctionClauseError` because a guard
  ordering made its second clause unreachable (D-1). `IR.Path.transform/2` now takes a full
  affine matrix (D-35).

- **`SVG.Element.from_ir/1` renders `view_box` as `viewBox`** — attribute names go through
  one map, so casing cannot differ between the two bridges (D-11, D-34).

- **`Backend.Canvas` emits executable commands** and group styles; the `CanvasIncremental`
  and `Incremental` contracts were made to match the code; `Benchmark` measures elapsed time
  with its own clock (D-37, D-38, D-39).

- **`Hooks.js_code/0` emitted every hook twice**, as duplicate named exports, which is a
  syntax error in a JavaScript module (D-48); and `BrushHook` leaked its listeners, because
  it removed handlers it had never bound — it now stores the bound handlers and removes
  those (D-47).

- **`Contour.Density.compute/2` took minutes on its default grid.** The grid is now an
  indexed structure and the ring tracing takes each segment once; a list read by index was
  the whole cost (D-72).

- **`Shape.LineNx` warned at compile time in a consumer without Nx** — nine warnings, not
  the one first reported. Both Nx-calling modules declare `@compile {:no_warn_undefined, Nx}`
  and a consumer check fails on any `warning:` line from the library's compile (D-50).

- `Data.range/3` and a set of dead clauses across the tree; the force simulation's timer
  discipline — tagged ticks, restart keeps the state, alpha is clamped — under an ExTLA
  model that is checked in CI (D-14).

[Unreleased]: https://gitlab.conet.yarina.org/dco-tek/visualize/-/compare/v0.1.0...main
[0.1.0]: https://gitlab.conet.yarina.org/dco-tek/visualize/-/tags/v0.1.0
