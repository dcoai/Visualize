# Geography and Geometry

**Status:** Implemented

This document specifies the geographic and computational-geometry modules: `Visualize.Geo.Projection` (38 map projections behind one struct), `Visualize.Geo.Path` (GeoJSON to SVG path data), `Visualize.Geo.Delaunay` and `Visualize.Geo.Voronoi` (planar triangulation and tessellation), `Visualize.Polygon` (polygon measures), and `Visualize.Contour` with `Visualize.Contour.Density` (marching squares over a grid, and kernel density estimation feeding it). Geographic input is in degrees; projected output is in pixels with y pointing down. Planar geometry uses `{x, y}` tuples.

## 1. Projections

`Visualize.Geo.Projection` maps `{longitude, latitude}` in degrees to `{x, y}` in pixels and back. The raw mathematics of each projection lives in five `@doc false` family modules — `Projection.Cylindrical`, `Projection.Azimuthal`, `Projection.Conic`, `Projection.Pseudocylindrical` and `Projection.Compromise` — each exposing `project/4` and `invert/4` on unit-scale, radian-based planar coordinates. They are internal; only `Visualize.Geo.Projection` is public API. The hidden `family/1` returns the family module for a type atom and raises `KeyError` for any other atom.

### 1.1 Struct

| Field | Default | Meaning |
|---|---|---|
| `type` | `:mercator` | Projection type atom (1.2). |
| `scale` | `150` | Pixels per unit of the raw projection (one radian of longitude on a cylindrical projection). |
| `translate` | `{480, 250}` | Pixel position of the raw origin. |
| `center` | `{0, 0}` | `{lon, lat}` in degrees subtracted after rotation and before projecting (1.4). |
| `rotate` | `{0, 0, 0}` | `{lambda, phi, gamma}` in degrees (1.4). |
| `clip_angle` | `nil` | Angular radius of the visible disc in degrees, or `nil` for no clipping; `new/1` sets a per-type default (1.5). |
| `precision` | `0.5` | Stored but not consulted by any function. |
| `parallels` | `{29.5, 45.5}` | Standard parallels `{phi1, phi2}` in degrees for conic types; `phi1` alone for `:bonne` and `:loximuthal`. |

`new/0` is `new(:mercator)`. `new/1` accepts any atom; an unsupported atom is only detected when `project/3` or `invert/3` dispatches. Setters return an updated struct: `scale/2`, `translate/3`, `center/3`, `rotate/3` (gamma 0), `rotate/4`, `clip_angle/2` (a number or `nil`), `parallels/3`.

### 1.2 Projection types

The 38 type atoms, grouped as the dispatch table in `lib/visualize/geo/projection.ex` groups them:

- Cylindrical (`Projection.Cylindrical`): `:mercator`, `:equirectangular`, `:transverse_mercator`, `:cylindrical_equal_area`, `:miller`, `:gall_peters`.
- Azimuthal (`Projection.Azimuthal`): `:orthographic`, `:stereographic`, `:azimuthal_equal_area`, `:azimuthal_equidistant`, `:gnomonic`.
- Conic (`Projection.Conic`): `:albers`, `:conic_conformal`, `:conic_equal_area`, `:conic_equidistant`, `:polyconic`, `:bonne`.
- Pseudocylindrical (`Projection.Pseudocylindrical`): `:mollweide`, `:sinusoidal`, `:eckert1`, `:eckert2`, `:eckert3`, `:eckert4`, `:eckert5`, `:eckert6`, `:hammer`, `:kavrayskiy7`, `:wagner4`, `:wagner6`, `:fahey`, `:collignon`, `:loximuthal`.
- Compromise (`Projection.Compromise`): `:natural_earth`, `:equal_earth`, `:robinson`, `:winkel_tripel`, `:aitoff`, `:van_der_grinten`.

Type-specific behaviour:

- `:mercator` clamps latitude to ±1.4844 rad (about ±85.05°); `:miller` clamps to ±1.4 rad; `:transverse_mercator` clamps `cos(lat) * sin(lon)` to ±0.9999. None of the cylindrical types returns `nil`.
- `:orthographic` returns `nil` for the far hemisphere; `:gnomonic` returns `nil` when the point is on or beyond the horizon; `:stereographic` and `:azimuthal_equal_area` return `nil` within 0.001 of the antipode. `orthographic` `invert/3` returns `nil` outside the unit disc.
- `:albers` and `:conic_equal_area` are the same projection; the conic types read both parallels, `:bonne` and `:loximuthal` read only `phi1`. `:polyconic`, `:mollweide`, `:fahey`, `:natural_earth`, `:equal_earth`, `:winkel_tripel`, `:aitoff` and `:van_der_grinten` invert iteratively with a bounded number of steps, so their `invert/3` is approximate.
- `:transverse_mercator` `invert/3` MUST satisfy `lat = asin(sin(y) / cosh(x))` and `lon = atan2(sinh(x), cos(y))` so that `invert(project(p)) == p` for every projectable `p`.

> Decision: see spec/13. The current transverse Mercator inverse computes `lat = asin(sin(y) / sqrt(sinh(x)^2 + cos(y)^2))`, which agrees with the forward projection only on the central meridian (issue #9, D-5).

### 1.3 Projection pipeline

`project(proj, lon, lat)` performs, in order: rotation (1.4); subtraction of `center` in degrees; the clip test (1.5), returning `nil` when the point is clipped; the raw family projection, which may itself return `nil`; and finally `{x * scale + tx, -y * scale + ty}` with `{tx, ty} = translate`. The y axis is flipped so that north is up on screen. Output is `{float, float}` or `nil`.

`invert(proj, x, y)` computes `{(x - tx) / scale, -(y - ty) / scale}`, applies the raw inverse (which may return `nil`), adds `center`, and applies the inverse rotation. Output is `{lon, lat}` in degrees or `nil`. The clip test is not applied on inversion.

### 1.4 Rotation and centre

`rotate/3,4` stores `{lambda, phi, gamma}` in degrees. On projection, longitude becomes `lon - lambda`, normalised into `[-180, 180]`, so the meridian `lambda` becomes the central meridian (the opposite sign convention from d3's `rotate`, kept on purpose: D-44). When `phi` or `gamma` is non-zero the point is then rotated on the sphere about the x axis by `-phi` (tilt) and about the z axis by `-gamma` (roll). `invert/3` undoes the three in reverse order — about the z axis by `+gamma`, then about the x axis by `+phi`, then `lambda` is added back — so `invert(project(p))` recovers `p` for any `{lambda, phi, gamma}` to the precision of the raw inverse (floating-point noise for the closed forms, the iteration tolerance for the approximate inverses of 1.2). `test/visualize/geo/projection_rotation_test.exs` holds this as a property over every type but transverse Mercator (#9).

`center/3` stores `{lon, lat}`; both are subtracted from the rotated coordinates in degrees before the raw projection. For cylindrical types this shifts the map; for other families it re-centres the sphere rather than translating the projected plane.

### 1.5 Clipping

A point is clipped when its angular distance `c` from the projection centre — computed after rotation and centring as `cos(c) = cos(lat) * cos(lon)` — exceeds `clip_angle`: the test is `cos(c) < cos(clip_angle) - 1.0e-9`, in which case `project/3` returns `nil`. `clip_angle` of `nil` disables the test; 180 clips nothing. `new/1` sets defaults for azimuthal types: `:orthographic` 90, `:stereographic` 142, `:gnomonic` 60, `:azimuthal_equal_area` 180, `:azimuthal_equidistant` 180; every other type starts with `nil`.

### 1.6 Bounds and fitting

`bounds/1` projects the four corners `{-180, -85}`, `{180, -85}`, `{180, 85}`, `{-180, 85}`, drops `nil` results, and returns `[min_x, min_y, max_x, max_y]`; if every corner is clipped it returns `[tx - scale, ty - scale, tx + scale, ty + scale]`. This is a corner-based estimate, not the outline of a curved graticule.

`fit_extent(proj, [[x0, y0], [x1, y1]], [[lon0, lat0], [lon1, lat1]])` sets `scale` to `min(width / Δlon, height / Δlat) * 0.95` with the deltas in radians, `center` to the geographic midpoint and `translate` to the extent's midpoint; `rotate` is untouched. The fit is projection-independent and approximate.

### 1.7 Functions

| Function | Contract |
|---|---|
| `Visualize.Geo.Projection.new/0` | `new(:mercator)`. |
| `Visualize.Geo.Projection.new/1` | Creates a projection of the given type with the defaults of 1.1 and the type's default clip angle (1.5). |
| `Visualize.Geo.Projection.scale/2` | Sets `scale`. |
| `Visualize.Geo.Projection.translate/3` | Sets `translate` to `{x, y}`. |
| `Visualize.Geo.Projection.center/3` | Sets `center` to `{lon, lat}` degrees. |
| `Visualize.Geo.Projection.rotate/3` | `rotate(proj, lambda, phi, 0)`. |
| `Visualize.Geo.Projection.rotate/4` | Sets `rotate` to `{lambda, phi, gamma}` degrees. |
| `Visualize.Geo.Projection.clip_angle/2` | Sets `clip_angle` in degrees, or `nil` to disable clipping. |
| `Visualize.Geo.Projection.parallels/3` | Sets `parallels` to `{phi1, phi2}` degrees. |
| `Visualize.Geo.Projection.project/3` | `{x, y}` pixels for `lon, lat` degrees, or `nil` when clipped or unprojectable (1.3). |
| `Visualize.Geo.Projection.invert/3` | `{lon, lat}` degrees for `x, y` pixels, or `nil` (1.3). |
| `Visualize.Geo.Projection.bounds/1` | `[x0, y0, x1, y1]` corner-based pixel bounds (1.6). |
| `Visualize.Geo.Projection.fit_extent/3` | Sets scale, centre and translate to fit a geographic box into a pixel box (1.6). |

## 2. GeoJSON paths

`Visualize.Geo.Path` renders GeoJSON into SVG path data and measures geometries in projected space.

### 2.1 Struct and input

| Field | Default | Meaning |
|---|---|---|
| `projection` | `nil` | A `Projection` struct; when `nil`, positions are used as planar `x, y`. |
| `point_radius` | `4.5` | Radius of the circle drawn for each `Point`. |
| `context` | `nil` | Reserved; unused. |

`new/0` is `new(nil)`. Input is a GeoJSON map with string keys (`"type"`, `"coordinates"`, `"geometry"`, `"features"`, `"geometries"`). `Feature` and `FeatureCollection` are unwrapped; a feature with `"geometry" => nil` contributes nothing. Supported geometry types: `Point`, `MultiPoint`, `LineString`, `MultiLineString`, `Polygon`, `MultiPolygon`, `GeometryCollection`. A position is a list `[lon, lat | _]`; extra elements are ignored. Any other `"type"` renders as `""`, measures as `0.0` and contributes no points.

### 2.2 Rendering

`render/2` returns one string, concatenating the parts of multi-geometries and collections:

- `Point` — a circle of radius `point_radius` at the projected position as two arcs: `M{cx - r},{cy}A{r},{r},0,1,1,{cx + r},{cy}A{r},{r},0,1,1,{cx - r},{cy}Z`, with numbers interpolated as-is.
- `LineString` — `M{x},{y}` followed by `L{x},{y}` per further vertex.
- `Polygon` — each ring rendered as a line string followed by `Z`.

Vertices whose projection is `nil` are dropped from lines and rings; lines are not split at clipped vertices. Line and ring numbers are floats rounded to 3 decimals (integers unchanged). A point whose projection is `nil` renders as `""`.

### 2.3 Measures

- `area/2` — for `Polygon`, `|shoelace(exterior)| - |sum of shoelace(holes)|`; for `MultiPolygon`, the sum over polygons; for `GeometryCollection`, the sum of members; `0.0` for points and lines. Units are projected pixels squared (or input units squared with no projection).
- `bounds/2` — `[x0, y0, x1, y1]` over every projected vertex of the geometry, or `nil` when there are none.
- `centroid/2` — the arithmetic mean of every projected vertex (not area-weighted), as `{x, y}`, or `nil` when there are none.

### 2.4 Functions

| Function | Contract |
|---|---|
| `Visualize.Geo.Path.new/0` | `new(nil)`. |
| `Visualize.Geo.Path.new/1` | Creates a path generator with the given projection or `nil`. |
| `Visualize.Geo.Path.projection/2` | Sets the projection. |
| `Visualize.Geo.Path.point_radius/2` | Sets the point circle radius. |
| `Visualize.Geo.Path.render/2` | SVG path data for a GeoJSON object (2.2). |
| `Visualize.Geo.Path.area/2` | Projected planar area (2.3). |
| `Visualize.Geo.Path.bounds/2` | `[x0, y0, x1, y1]` of projected vertices or `nil`. |
| `Visualize.Geo.Path.centroid/2` | Mean of projected vertices as `{x, y}` or `nil`. |

## 3. Delaunay triangulation

`Visualize.Geo.Delaunay.new/1` takes a list of `{x, y}` points and returns a struct with `points` (the input), `triangles` (a flat list of point indices, three per triangle, each triangle counter-clockwise), `halfedges` (one entry per triangle vertex, in d3-delaunay's form: half-edge `e = 3t + k` runs from `triangles[e]` to `triangles[3t + (k + 1) rem 3]`, and `halfedges[e]` is the index of the opposite half-edge or `-1` on the hull) and `hull` (point indices of the convex hull, counter-clockwise from the leftmost point — lowest `x`, then lowest `y`).

### 3.1 Algorithm and guarantees

The triangulation is Delaunay (D-43): no input point lies strictly inside the circumcircle of any triangle, the triangles cover the convex hull of the points without overlap, and there are exactly `2n - 2 - h` triangles, where `h` counts the points on the hull boundary (collinear boundary points included), whenever the points are not all collinear. Every triangle is counter-clockwise, so `halfedges[halfedges[e]] == e` and the unpaired half-edges are exactly the hull edges. Fewer than three points yields no triangles and a hull listing every index; the empty input yields an empty hull; points all on one line yield no triangles and a hull of the two extreme distinct points. A point coincident with an earlier one is left out of the triangulation, the hull and the half-edges. Four or more cocircular points admit more than one Delaunay triangulation; which one results depends on input order.

The implementation is incremental insertion (Bowyer–Watson) with ghost triangles in place of a finite super-triangle: each hull edge `u -> v` carries a ghost `{v, u, inf}` standing for the unbounded region beyond it, so the cavity a new point opens is the set of real triangles whose circumcircle strictly contains it together with the ghosts whose hull edge it lies beyond (or on, between the endpoints); the cavity's boundary is the set of directed edges of those triangles whose reverse is not also one, and the new triangles join each boundary edge to the point in that direction, which keeps them counter-clockwise. The in-circle determinant is multiplied by the sign of the triangle's orientation, so it is positive exactly for a point strictly inside the circumcircle whatever the vertex order. The seed is the first three distinct non-collinear points in input order; distinct points collinear with the first two are inserted afterwards. Predicates are evaluated in floating point without adaptive precision, so the guarantees hold for points in general position and for exactly representable collinear or cocircular configurations (integer or grid coordinates). Each insertion scans every triangle, so construction is quadratic in the number of points.

### 3.2 Queries and rendering

- `triangles/1` — `[[i, j, k]]` in construction order, each counter-clockwise.
- `hull/1` — hull indices counter-clockwise from the leftmost point.
- `neighbors/2` — indices of every point sharing a triangle with the given index, unique, in triangle order.
- `find/2` — index (into `triangles/1`) of the first triangle containing `{x, y}` by an inclusive barycentric test, or `-1`.
- `points/1` — the input points.
- `render_triangles/1` — `M{x0},{y0}L{x1},{y1}L{x2},{y2}Z` per triangle, concatenated; numbers unformatted.
- `render_hull/1` — `M..L..Z` around the hull, or `""` for an empty hull.

### 3.3 Functions

| Function | Contract |
|---|---|
| `Visualize.Geo.Delaunay.new/1` | Triangulates a list of `{x, y}` points; fills `triangles`, `halfedges` and `hull` (3.1). |
| `Visualize.Geo.Delaunay.triangles/1` | Triangles as counter-clockwise `[i, j, k]` index lists. |
| `Visualize.Geo.Delaunay.points/1` | The input points. |
| `Visualize.Geo.Delaunay.hull/1` | Convex hull as point indices. |
| `Visualize.Geo.Delaunay.find/2` | Index of the triangle containing a point, or `-1`. |
| `Visualize.Geo.Delaunay.neighbors/2` | Indices adjacent to a point index. |
| `Visualize.Geo.Delaunay.render_triangles/1` | Path data outlining every triangle. |
| `Visualize.Geo.Delaunay.render_hull/1` | Path data outlining the hull. |

## 4. Voronoi diagram

`Visualize.Geo.Voronoi.new/1` takes a list of `{x, y}` points (not a `Delaunay` struct), triangulates them, and stores the circumcentre of every triangle (the centroid for a degenerate triangle) in `circumcenters`. `bounds/2` accepts `[x0, y0, x1, y1]` or a 4-tuple and stores a tuple; `bounds` is `nil` until set.

### 4.1 Cells and edges

- `cell/2` — the circumcentres of the triangles incident to the site, sorted by `atan2` angle around the site, then clipped to `bounds` by Sutherland–Hodgman when bounds are set; `[]` for a site with no incident triangle. Cells of hull sites consist only of finite circumcentres; they are not extended to infinity, so their unbounded region is absent even after clipping.
- `cell_unclipped/2` — the same without clipping.
- `cells/1` — `cell/2` for every site index in order.
- `edges/1` — one `{c1, c2}` segment between the circumcentres of every pair of triangles sharing an edge; unbounded edges are omitted. Quadratic in the number of triangles (it searches the triangle list rather than reading `halfedges`).
- `find/2` — the index of the site nearest to `{x, y}` (Euclidean), independent of cells.

### 4.2 Rendering

- `render_cell/2` and `render_cells/1` — `M..L..Z` per cell (an empty cell renders `""`), the latter concatenated over all sites; numbers unformatted.
- `render_edges/1` — `M..L..` per edge, concatenated.
- `render_cells_clipped/1,2` — an SVG fragment: `<defs><clipPath id="…"><rect …/></clipPath></defs><g clip-path="url(#…)"><path d="…" fill="…" stroke="…"/></g>`, where the path holds every unclipped cell and the rect is `bounds` (defaulting to `{0, 0, 100, 100}`). Options: `:clip_id` (default `"voronoi-clip"`), `:stroke` (`"#ccc"`), `:fill` (`"none"`).

### 4.3 Functions

| Function | Contract |
|---|---|
| `Visualize.Geo.Voronoi.new/1` | Builds the diagram from a list of `{x, y}` points. |
| `Visualize.Geo.Voronoi.bounds/2` | Sets the clipping rectangle from a list or tuple. |
| `Visualize.Geo.Voronoi.cell/2` | Clipped cell polygon of a site index (4.1). |
| `Visualize.Geo.Voronoi.cell_unclipped/2` | Cell polygon without clipping. |
| `Visualize.Geo.Voronoi.cells/1` | Clipped cells for every site. |
| `Visualize.Geo.Voronoi.edges/1` | Finite Voronoi edges as `{point, point}`. |
| `Visualize.Geo.Voronoi.find/2` | Index of the nearest site. |
| `Visualize.Geo.Voronoi.render_cell/2` | Path data for one cell. |
| `Visualize.Geo.Voronoi.render_cells/1` | Path data for all cells. |
| `Visualize.Geo.Voronoi.render_cells_clipped/1` | `render_cells_clipped(voronoi, [])`. |
| `Visualize.Geo.Voronoi.render_cells_clipped/2` | SVG fragment using a `clipPath` (4.2). |
| `Visualize.Geo.Voronoi.render_edges/1` | Path data for all edges. |

## 5. Polygons

`Visualize.Polygon` operates on lists of `{x, y}` tuples; a polygon is implicitly closed.

- `area/1` — signed shoelace area; positive when the vertices wind counter-clockwise in a y-up frame (which appears clockwise on screen, where y points down); `0.0` for fewer than three points.
- `centroid/1` — area-weighted centroid; `{0.0, 0.0}` for `[]`, the point itself for one, the midpoint for two, and the vertex mean when `|area| < 1.0e-10`.
- `perimeter/1` — sum of edge lengths including the closing edge; `0.0` for fewer than two points.
- `contains?/2` — even–odd ray casting; `false` for fewer than three points; behaviour for points exactly on an edge is unspecified.
- `hull/1` — Andrew's monotone chain; vertices in counter-clockwise order (y-up), collinear points removed, duplicates removed; inputs of two or fewer points are returned unchanged.
- `bounds/1` — `{min_x, min_y, max_x, max_y}`, or `nil` for `[]`.
- `path_length/1` — length of the open polyline (no closing edge).

| Function | Contract |
|---|---|
| `Visualize.Polygon.area/1` | Signed shoelace area. |
| `Visualize.Polygon.centroid/1` | Area-weighted centroid with degenerate fallbacks. |
| `Visualize.Polygon.perimeter/1` | Closed edge-length sum. |
| `Visualize.Polygon.contains?/2` | Even–odd point-in-polygon test. |
| `Visualize.Polygon.hull/1` | Convex hull in counter-clockwise order. |
| `Visualize.Polygon.bounds/1` | `{min_x, min_y, max_x, max_y}` or `nil`. |
| `Visualize.Polygon.path_length/1` | Open polyline length. |

## 6. Contours

`Visualize.Contour` traces iso-lines through a scalar grid with marching squares.

### 6.1 Configuration

| Field | Default | Meaning |
|---|---|---|
| `width`, `height` | `1`, `1` | Grid dimensions, used only when the grid is given as a flat list. |
| `thresholds` | `[]` | A list of iso-values, or a positive integer count. |
| `smooth?` | `true` | Linear interpolation of crossing positions; when false, crossings sit at edge midpoints. |

`size/3` sets width and height; `thresholds/2` stores a list or integer; `smooth/2` sets the flag.

### 6.2 Input and thresholds

`compute/2` accepts the grid either as a list of rows (row-major; the number of rows is the height and the length of the first row the width, overriding the struct) or as a flat list indexed `y * width + x` using the struct's dimensions. A threshold list is used verbatim. A count `n > 0` produces `n` values strictly inside the data range: `min + i * (max - min) / (n + 1)` for `i` in `1..n`. Any other value yields no contours.

### 6.3 Output

`compute/2` returns one map per threshold: `%{value: threshold, type: "MultiPolygon", coordinates: polygons}` where `polygons` is a list of polygons, each polygon a list containing a single ring, and each ring a list of `[x, y]` two-element lists. Coordinates are grid units — `x` the column, `y` the row — and are clamped to `[0, width - 1]` by `[0, height - 1]`. A grid corner is inside when its value is `>= threshold`. The grid is padded with a border of `min - 1000` before tracing so that regions touching the edge close along it. Rings are traced by following segments end to start; saddle cells (cases 5 and 10) always emit two separate segments. Holes are not distinguished from outer rings — each ring is its own single-ring polygon — and a ring that cannot be closed is emitted as an open polyline.

`render/2` returns `[%{value, path}]`, where `path` is `M..L..` per ring with numbers rounded to 3 decimals, followed by `Z` only when the ring's last point coincides with its first (within 0.001).

### 6.4 Functions

| Function | Contract |
|---|---|
| `Visualize.Contour.new/0` | Creates a generator with a 1×1 grid, no thresholds and smoothing on. |
| `Visualize.Contour.size/3` | Sets grid width and height. |
| `Visualize.Contour.thresholds/2` | Sets a threshold list or count. |
| `Visualize.Contour.smooth/2` | Enables or disables crossing interpolation. |
| `Visualize.Contour.compute/2` | Contour polygons per threshold (6.3). |
| `Visualize.Contour.render/2` | Path data per threshold. |

## 7. Density contours

`Visualize.Contour.Density` estimates a density surface from points by Gaussian kernel density estimation and contours it with `Visualize.Contour`.

### 7.1 Configuration

| Field | Default | Meaning |
|---|---|---|
| `x`, `y` | `nil` | Accessors `fn datum -> number end`. When `nil`, a map datum is read at `:x`/`:y` (0 when absent) and a tuple datum at elements 0/1. |
| `weight` | `nil` | Accessor; when `nil` every datum weighs 1. |
| `width`, `height` | `960`, `500` | Output extent in pixels. |
| `cell_size` | `4` | Grid cell size in pixels. |
| `bandwidth` | `20` | Kernel standard deviation in pixels. |
| `thresholds` | `20` | List or count, as in 6.2, applied to density values. |

`x/2`, `y/2` and `weight/2` require arity-1 functions.

### 7.2 Algorithm

The grid has `div(width, cell_size) + 1` columns and `div(height, cell_size) + 1` rows. Each point `{px, py, w}` adds `w * exp(-d² / (2σ²)) / (2πσ²)` to every cell within a square of half-side `ceil(3 * bandwidth / cell_size)` cells around it (clamped to the grid), where `d` is the distance from the point to the cell in cell units and `σ = bandwidth / cell_size`. Densities are therefore expressed per cell². Contours are computed with smoothing on, and every coordinate is multiplied by `cell_size` so the result is in pixels. `compute/2` returns the same shape as 6.3; `render/2` returns `[%{value, path}]` with every ring closed by `Z`.

### 7.3 Functions

| Function | Contract |
|---|---|
| `Visualize.Contour.Density.new/0` | Creates an estimator with the defaults of 7.1. |
| `Visualize.Contour.Density.x/2` | Sets the x accessor. |
| `Visualize.Contour.Density.y/2` | Sets the y accessor. |
| `Visualize.Contour.Density.weight/2` | Sets the weight accessor. |
| `Visualize.Contour.Density.size/3` | Sets output width and height in pixels. |
| `Visualize.Contour.Density.cell_size/2` | Sets the grid cell size. |
| `Visualize.Contour.Density.bandwidth/2` | Sets the kernel bandwidth in pixels. |
| `Visualize.Contour.Density.thresholds/2` | Sets a density threshold list or count. |
| `Visualize.Contour.Density.compute/2` | Density contours in pixel coordinates (7.2). |
| `Visualize.Contour.Density.render/2` | Closed path data per threshold. |
