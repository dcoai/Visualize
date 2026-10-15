# Prior Art

**Status:** Implemented

Visualize is a port of the computational half of D3.js to Elixir, shaped by the mechanics of Phoenix LiveView. This document records where each part of the library comes from, what was deliberately left behind, the constraints of the LiveView model that decided the architecture, and the Elixir libraries that occupy neighboring ground.

## 1. The D3.js lineage

D3 is not one library but a family of modules, and its lasting contribution is the separation of *computing* a visualization (scales, shapes, layouts, projections) from *drawing* it (selections, transitions). Visualize ports the first half module-for-module and replaces the second with server-side SVG generation.

| d3 module | Visualize module(s) | Notes |
|---|---|---|
| `d3-scale` | `Visualize.Scale`, `Visualize.Scale.*` | Linear, log, power, sqrt, symlog, time, band, ordinal, quantize, quantile, threshold, sequential and diverging color |
| `d3-scale-chromatic` | `Visualize.Scale.Color` | Named schemes reached through `scheme/1` and `schemes/0` |
| `d3-shape` | `Visualize.Shape`, `Visualize.Shape.*` | Line, area, arc, pie, stack, symbol, and every curve in `Visualize.Shape.Curve` |
| `d3-axis` | `Visualize.Axis` | Emits an IR element tree rather than mutating a selection |
| `d3-format`, `d3-time-format` | `Visualize.Format` | Number, SI, currency, percent, exponential and time formatting |
| `d3-array` | `Visualize.Data` | Extent, statistics, grouping, binning, ticks |
| `d3-hierarchy` | `Visualize.Layout.Hierarchy`, `Tree`, `Cluster`, `Pack`, `Partition`, `Treemap` | Node struct plus one generator per layout |
| `d3-chord`, `d3-sankey` | `Visualize.Layout.Chord`, `Visualize.Layout.Sankey` | |
| `d3-force` | `Visualize.Layout.Force`, `Force.Simulation`, `Force.Forces` | The simulation is a GenServer driven by a timer; see D-4 for the many-body force |
| `d3-geo`, `d3-geo-projection` | `Visualize.Geo.Projection`, `Geo.Projection.*`, `Geo.Path` | Thirty-eight projection types; the family modules are internal (D-9) |
| `d3-delaunay` | `Visualize.Geo.Delaunay`, `Visualize.Geo.Voronoi` | |
| `d3-contour` | `Visualize.Contour`, `Visualize.Contour.Density` | Marching squares and kernel density |
| `d3-polygon` | `Visualize.Polygon` | |
| `d3-interpolate` | `Visualize.Interpolate` | Number, round, string, array, date, color, transform, zoom, basis, discrete |
| `d3-ease` | `Visualize.Ease` | Every named easing, `by_name/1`, `frames/2` |
| `d3-random` | `Visualize.Random` | Every distribution plus seeding, sampling and shuffling |
| `d3-color` | `Visualize.Color` | RGB, HSL, Lab, HCL and the derived operations |
| `d3-path` | `Visualize.IR.Path` | The path builder became the backend-agnostic IR |

The API shape is D3's too: a generator is a struct built with `new/0`, configured with setter functions that return the struct, and applied with `generate`/`compute`/`apply`. Where D3 uses a single overloaded getter/setter, Visualize uses a pure setter and reads the struct field directly.

## 2. What was deliberately not ported

- **`d3-selection` and the DOM.** There is no DOM on the server. Output is a value — an `IR.Element` tree, an `SVG.Element`, a path string, or a binary — that a template embeds or a hook consumes. Nothing in the library selects, joins or mutates.
- **`d3-transition` and `d3-timer`.** Animation scheduling belongs to the client. The library ships the maths (`Visualize.Ease`, `Visualize.Interpolate`) so a server can compute keyframes or a CSS transition target, but it never runs an animation loop. The one timer in the library drives the force simulation's ticks, not rendering.
- **The client runtime of `d3-zoom` and `d3-brush`.** `Visualize.Hooks.Zoom` and `Visualize.Hooks.Brush` provide the JavaScript hook text and the server-side helpers for transforms and selections; the event handling itself runs in the browser.
- **`d3-fetch`, `d3-dsv`, `d3-drag`, `d3-dispatch`, `d3-quadtree`.** Loading data, parsing files and dispatching events are the host application's concern. There is no quadtree, which is why the many-body force is exact O(n²) (D-4).

## 3. Constraints drawn from the LiveView model

`dev_docs/liveview_plotting_strategies.md` analyses plotting under LiveView. Four of its conclusions are load-bearing for this design.

### 3.1 Round-trip latency and the 100 ms threshold

Every interaction lifted into LiveView costs a full round trip: browser event, socket, server process, re-render, diff, patch. Below roughly 100 ms a response reads as instantaneous; above it the chart feels sluggish, and a 60 Hz animation (16.6 ms per frame) is out of reach entirely. The design therefore separates *data delivery* (server-driven, may lag) from *interaction* (must be local). Server-rendered SVG is the right tool for the first and the wrong tool for the second.

### 3.2 The ~1,000 DOM-node ceiling

Browser layout engines are built for documents, not for tens of thousands of vector nodes; each SVG element carries style, layout and diffing cost. Pure SVG through LiveView is architecturally limited to roughly a thousand data points or to update rates under about 1 Hz. This is a stated non-goal of the SVG path ([01-goals-and-scope](01-goals-and-scope.md)) and the reason the Canvas backends exist.

### 3.3 Instant interaction lives in a JS hook

Hover, brushing, zoom and pan must complete inside the browser's frame budget, so they are implemented as `phx-hook` JavaScript that owns its element (`phx-update="ignore"`) and reports results to the server with `pushEvent`. The server side keeps only the pure helpers — converting a pixel selection to a domain extent, composing transforms — so the round trip carries a decision, not a frame.

### 3.4 Canvas and binary transfer for high cardinality

Above the SVG ceiling the library emits Canvas 2D command streams instead of elements. JSON expands a float to two or three times its binary size and must be parsed on the browser's main thread; `Visualize.Backend.CanvasBinary` (and `Shape.LineNx`) therefore encode coordinates as raw `f64` binaries — with Nx, when it is loaded — that the hook wraps in a typed array with no parsing at all. `Backend.Hybrid` keeps static axes as SVG and moves only the data to canvas; `Backend.CanvasIncremental` and `Visualize.Incremental` avoid full redraws on scroll by copying the existing bitmap and rendering only the exposed regions.

## 4. Elixir neighbors

- **Contex** renders charts to SVG on the server with a fixed set of chart types. It occupies the same low-cardinality, server-rendered niche; Visualize differs in exposing the D3 primitives (scales, shapes, layouts, projections) so any chart can be composed rather than choosing from a catalog.
- **Tucan** is a grammar-of-graphics wrapper over Vega-Lite: the server emits a JSON specification and the browser's Vega runtime renders it. It is client-rendered and declarative, which suits exploratory work; Visualize keeps rendering on the server and ships no client runtime beyond the hooks.
- **Matplotex** targets static scientific plots through SVG or images with Nx. Visualize shares the optional Nx dependency but is oriented to live templates rather than exported figures.
