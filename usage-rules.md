# Visualize Usage Rules

Rules for working on, or building against, this library. The specification under `spec/`
is the source of truth; these rules are the short form.

## Key modules

| Module | Purpose |
|---|---|
| `Visualize` | Facade: constructors for the common scales and shapes, `svg/1`, `render/1` |
| `Visualize.Scale` | Data domain → visual range: linear, log, power, symlog, time, band, ordinal, quantile, quantize, threshold, colour |
| `Visualize.Shape` | Path generators: line, area, arc, pie, stack, symbol; ten curve types |
| `Visualize.Axis`, `Visualize.Format` | Axes with ticks and labels; number and time formatting |
| `Visualize.Layout.*` | Hierarchy, tree, cluster, pack, partition, treemap, chord, sankey, force |
| `Visualize.Geo.*`, `Visualize.Contour`, `Visualize.Polygon` | Projections, GeoJSON paths, Delaunay, Voronoi, contours |
| `Visualize.IR.*` | Backend-agnostic scene graph: `Element`, `Path`, `Transform` |
| `Visualize.Backend.*`, `Visualize.Render` | SVG and canvas backends; binary, hybrid and incremental encoders |
| `Visualize.SVG.*` | The HEEx-facing element struct (`Phoenix.HTML.Safe`) and its renderer |
| `Visualize.Components`, `Visualize.Hooks` | LiveView function components (Phoenix optional) and the zoom/brush/canvas/resize JS hooks |
| `Visualize.Theme` | Colours, font and sizes as named slots; `resolve/3` gives CSS `var()` references for SVG or literals for canvas |
| `Visualize.Chart` | A chart as a design map (spec/14): `from_map/1`, `to_map/1`, the JSON round trip (Jason optional), `var/1`; `Chart.Schema` is the schema as data, `Chart.Validator` reports faults by path |

## Start at the gallery

Every chart in `examples/lib/examples/charts/` is a design (spec/14): a `design/1` that
returns the map and the rows it binds, a `sample_code/0` with the `Visualize.Chart.Build`
calls that make it, and nothing drawn by hand. To make a chart, find the nearest one there
and copy its sample; the grammar of scales, shapes and elements below is what the layer is
built from, not the way to write a chart.

## The pipeline

Data (a row list, or any `Visualize.Data.Table.rows/1` source: a column map, a keyword list
of columns, an Explorer frame, an Nx tensor) → `Scale` (domain to pixels) → `Shape` (pixels to a path) → `IR.Element` (a scene
graph) → a `Backend` (SVG string, canvas commands, or binary) → `Render`. Every stage is
a pure function over immutable structs; builders are `new/0` plus setter pipelines plus a
`generate`/`compute` call.

## Rules

1. **The spec comes first.** Before changing behaviour, change the document under `spec/`
   that governs it and, if intent changes, add an entry to `spec/13-decisions.md`. Code
   that disagrees with the spec is a bug in the code.
2. **Every public function has a spec row.** `mix vis.surface --check` fails the build
   when `lib/` defines a public function no document declares, or a document declares one
   `lib/` does not define. After editing either side: `mix vis.surface --write`, and
   commit `API_SURFACE.md` with the change. Internal functions are `@doc false`.
3. **Headings are numbered.** `mix vis.headings` fails on a gap, duplicate, orphan or
   unnumbered heading in `spec/`.
4. **No `try`/`rescue`/`catch`.** Expected failures return `nil` or `{:error, _}`; `!`
   variants raise. Surface bugs, do not hide them.
5. **Backends are explicit.** Pass `backend:` to `Visualize.Render` functions or set
   `config :visualize, default_backend:`. There is no per-process override.
6. **Phoenix and Nx are optional.** Both are `optional: true` dependencies — declared, so
   a host that has them gets them on the code path; never fetched by a host that does not.
   `Visualize.Components` compiles only when `Phoenix.Component` is loaded;
   `Backend.CanvasBinary` and `Shape.LineNx` need Nx. Never make either required, and
   never guard on a module of an undeclared dependency: Mix prunes the code path to the
   declared ones, so such a guard is always false in a host (D-45).
7. **About 1,000 points is the SVG ceiling.** Beyond that use the canvas backends, or
   reduce resolution before rendering; see `spec/00-prior-art.md`.
8. **Files stay under 1,000 lines**; split by family (`Geo.Projection.*` is the pattern).
9. **Format at 98 columns** (`mix format`), compile with `--warnings-as-errors`, and keep
   `mix test` green before submitting.

## Known gaps

The spec marks behaviour the code does not yet deliver with `> Decision: see spec/13`.
Each marker is owned by a proposal in the tracker; see `spec/13-decisions.md` D-13.
