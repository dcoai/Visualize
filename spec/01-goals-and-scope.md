# Goals and Scope

**Status:** Implemented

Visualize exists to let a Phoenix LiveView application compute a visualization on the server and embed the result in a template, using an API shaped like D3's. This document states the goals the library is held to, the things it will not attempt, and the compatibility commitments it makes.

## 1. Goals

### 1.1 Server-side SVG for Phoenix LiveView

The primary output is SVG produced on the server. `Visualize.SVG.Element` and `Visualize.IR.Element` implement `Phoenix.HTML.Safe` when Phoenix is present, so a chart is a value that a HEEx template interpolates directly; LiveView's diffing then ships only what changed. A rendered chart MUST be embeddable without any client-side library.

### 1.2 A D3-shaped, composable API

The library MUST expose the primitives, not just finished charts: scales map data to visual coordinates, shapes turn scaled data into path geometry, and elements assemble geometry into a scene. Each layer is usable alone. A generator is a struct created by `new/0`, configured by setter functions that return the struct, and applied by `generate/2`, `compute/2` or `apply/2` (see [11-public-api](11-public-api.md)). Names follow D3's where D3 has a name.

### 1.3 Phoenix is optional

Phoenix MUST NOT be a dependency. `Visualize.Components` and `Visualize.Components.Tree` compile only when `Phoenix.Component` is loaded, and the `Phoenix.HTML.Safe` implementations only when `Phoenix.HTML.Safe` is (D-7). Without Phoenix every other module works unchanged and renders to strings or iolists.

### 1.4 Nx is optional

Nx MUST NOT be a required dependency; it is declared `optional: true`. The binary canvas encoding (`Visualize.Backend.CanvasBinary`) and the batch line generator (`Visualize.Shape.LineNx`) need it. `CanvasBinary.available?/0` reports whether it is loaded; `encode_*` functions return `{:error, _}` without it and the `!` variants raise.

### 1.5 Zero required runtime dependencies

The library's `deps` MUST contain no required entries. Everything from projections to the force simulation is implemented in Elixir over the standard library and OTP.

## 2. Non-goals

- **A client-side charting runtime.** The library ships JavaScript only as hook text (`Visualize.Hooks`) that a host installs; it does not draw in the browser, manage a scene graph there, or depend on any JS charting library.
- **Animation scheduling.** `Visualize.Ease` and `Visualize.Interpolate` supply the maths; running a frame loop, timing transitions and interpolating live DOM state are the client's job.
- **SVG beyond roughly a thousand points.** The SVG path is bounded by the DOM ([00-prior-art](00-prior-art.md) §3.2). Higher cardinality MUST use the Canvas backends, the binary encoding, or the hybrid and incremental paths described in [09-rendering-backends](09-rendering-backends.md).
- **Loading geodata.** `Visualize.Geo.Path` consumes GeoJSON that is already a map; fetching, parsing TopoJSON or shapefiles, and simplification are out of scope.
- **Interaction handling.** Pointer events are handled in the hooks; the server receives finished selections and transforms.

## 3. Compatibility policy

### 3.1 Elixir

The library requires Elixir `~> 1.19` as declared in `mix.exs`. It uses no compiler-version-specific behaviour beyond what that constraint implies.

### 3.2 Versioning

`Visualize.version/0` returns the library version as a string and MUST equal the `version` in `mix.exs`. The current value is `"0.1.0"`. Releases follow semantic versioning: within `0.x`, a minor bump MAY change the public API when a decision in [13-decisions](13-decisions.md) records it; a patch bump MUST NOT.

### 3.3 The public surface

Every function that is not `@doc false` is public and is governed by this specification and the `API_SURFACE.md` gate. Anything marked `@doc false` is internal and MAY change without notice ([11-public-api](11-public-api.md) §2).
