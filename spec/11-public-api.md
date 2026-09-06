# Public API

**Status:** Implemented

The public API is every function the library documents; the `Visualize` module is a small facade over the most-used constructors. This document settles what "public" means, how the facade delegates, the naming conventions every builder follows, and the rule that expected failures are values rather than exceptions.

## 1. The `Visualize` facade

`Visualize` re-exports the constructors a typical chart starts from. Every delegate MUST behave exactly as its target; the facade adds no logic.

| Function | Contract |
|---|---|
| `Visualize.linear/0` | Delegates to `Visualize.Scale.linear/0`. |
| `Visualize.time/0` | Delegates to `Visualize.Scale.time/0`. |
| `Visualize.band/0` | Delegates to `Visualize.Scale.band/0`. |
| `Visualize.ordinal/0` | Delegates to `Visualize.Scale.ordinal/0`. |
| `Visualize.line/0` | Delegates to `Visualize.Shape.line/0`. |
| `Visualize.area/0` | Delegates to `Visualize.Shape.area/0`. |
| `Visualize.arc/0` | Delegates to `Visualize.Shape.arc/0`. |
| `Visualize.pie/0` | Delegates to `Visualize.Shape.pie/0`. |
| `Visualize.symbol/0` | Delegates to `Visualize.Shape.symbol/0`. |
| `Visualize.svg/0` | As `svg/1` with no attrs. |
| `Visualize.svg/1` | Delegates to `Visualize.SVG.new/1`: a root `<svg>` element with the given attrs. |
| `Visualize.render/1` | Delegates to `Visualize.SVG.render/1`: an `SVG.Element` tree as an iolist. |
| `Visualize.version/0` | The library version string; MUST equal the `version` in `mix.exs`. |

## 2. What is public

### 2.1 The rule

Every function that is `def` and not `@doc false` in a module under `lib/` is public. It MUST appear in a function table in this specification and is covered by the `API_SURFACE.md` gate ([12-testing-and-conformance](12-testing-and-conformance.md) §2). `Visualize.MixProject` is excluded. Default arguments produce one public arity per omitted argument, and each arity is a separate row.

### 2.2 `@doc false`

A function marked `@doc false` is internal: it is reachable, but its name, arguments and behaviour MAY change in any release without notice, and it MUST NOT appear in a function table. The current internals are of three kinds:

- **Family and encoder modules reached through a parent** (D-9): `project/4` and `invert/4` on each `Visualize.Geo.Projection.{Azimuthal, Compromise, Conic, Cylindrical, Pseudocylindrical}`, `Visualize.Geo.Projection.family/1`, `Visualize.Backend.CanvasBinary.SVG.encode_element/1`, and `Visualize.Backend.CanvasBinary.PathEncoder.encode_cubic_path/1` and `to_float/1`.
- **Behaviour callbacks**: on `Visualize.Backend.SVG` and `Visualize.Backend.Canvas` the `@impl` callback arities (`path_data/1`, `render_path/2`, `render_element/2`, `render_scene/2`, `wrap_root/2`) are hidden and reached through `Visualize.Render`, while the default-argument heads `render_path/1`, `render_element/1` and `render_scene/1` remain public and are specified in [09-rendering-backends](09-rendering-backends.md); likewise the GenServer callbacks of `Visualize.Layout.Force.Simulation` (`init/1`, `handle_call/3`, `handle_cast/2`, `handle_info/2`, `terminate/2`, `code_change/3`).
- **Anything else a module hides** to keep a helper out of the contract.

Hidden functions MAY be mentioned in prose where they explain a design.

## 3. Naming conventions

### 3.1 Builders

A generator, scale, layout or projection is a struct. Its module exposes:

- `new/0` (or `new/1` when a type or seed is required, e.g. `Visualize.Geo.Projection.new/1`, `Visualize.Scale.Log.new/1`) returning the struct with documented defaults;
- one setter per field, named after the field, taking the struct first and returning the struct (`domain/2`, `range/2`, `x/2`, `curve/2`, `padding/2`);
- one application function taking the struct first: `generate/2` for shapes and layouts that produce geometry or positioned nodes, `compute/2` or `compute/3` where the result is data (contours, sankey), `apply/2` or `scale/2` for scales, `project/3` for projections, `render/2` where the result is a path string built from data.

Setters MUST be pure and MUST NOT validate against other fields; validation, if any, happens at application. This is what makes `Visualize.Scale.linear() |> domain(...) |> range(...) |> nice()` order-independent.

### 3.2 Accessors

Where D3 takes an accessor, Visualize accepts either a one-argument function or an atom field name (`Visualize.Shape.Line.x/2`); a constant is accepted where D3 accepts one. Comparators are two-argument functions returning a boolean, as `Enum.sort/2` expects.

### 3.3 Angles and units

Angles in shapes and layouts (arc, pie, chord) are radians, as in D3. Angles in `Visualize.IR.Transform`, in path arc rotation, and in `Visualize.Geo.Projection` (rotate, center, clip angle, parallels) are degrees, as in SVG and GeoJSON. Sizes are pixels; symbol size is area in square pixels.

### 3.4 Module naming

Grouped functionality lives under a namespace module that both re-exports the group's constructors and dispatches setters over every struct in the group: `Visualize.Scale` over `Visualize.Scale.*`, `Visualize.Shape` over `Visualize.Shape.*`. Concrete modules keep the D3 name in `CamelCase`; the only camel-cased *functions* are `Visualize.SVG.Element`'s tag constructors, which spell SVG tags.

## 4. Failures are values

Functions MUST NOT raise for expected conditions. An expected failure returns `nil` (a projection point outside the visible domain, an unknown scale domain value without `unknown/2`, `Visualize.Geo.Delaunay.find/2` returning `-1`) or `{:error, reason}` (`Visualize.Backend.CanvasBinary.encode_element/1` without Nx). Where a raising variant is useful it is a separate function ending in `!` (`encode_element!/1`, `encode_path!/1`, `Visualize.Hooks.install!/0`) whose only difference is raising on the `{:error, _}` branch.

Exceptions are reserved for programmer error — a bad argument type, a missing required field — and surface as `FunctionClauseError` or `ArgumentError` from pattern matching and guards. The library MUST NOT use `try`/`rescue`/`catch` for control flow, and MUST NOT swallow an error to return a default. Where the code currently raises on a value it should return `nil` for, that is a recorded defect (D-5).
