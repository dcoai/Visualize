# Geography and Geometry

**Status:** Implemented

This document specifies the geographic and computational-geometry modules: `Visualize.Geo.Projection` (38 map projections behind one struct), `Visualize.Geo.Path` (GeoJSON to SVG path data), `Visualize.Geo.Delaunay` and `Visualize.Geo.Voronoi` (planar triangulation and tessellation), `Visualize.Polygon` (polygon measures), `Visualize.Contour` with `Visualize.Contour.Density` (marching squares over a grid, and kernel density estimation feeding it), and `Visualize.Geo.Tiles` (the Web-Mercator tile arithmetic under a basemap, §8). Geographic input is in degrees; projected output is in pixels with y pointing down. Planar geometry uses `{x, y}` tuples.

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
| `precision` | `0.5` | How a path draws the edge it is clipped along (2.2): `0` as d3-geo draws it at `precision(0)`, straight between the clip's own points; any other value sampled every degree. `project/3` does not read it. |
| `parallels` | `{29.5, 45.5}` | Standard parallels `{phi1, phi2}` in degrees for conic types; `phi1` alone for `:bonne` and `:loximuthal`. |

`new/0` is `new(:mercator)`. `new/1` accepts any atom; an unsupported atom is only detected when `project/3` or `invert/3` dispatches. Setters return an updated struct: `scale/2`, `translate/3`, `center/3`, `rotate/3` (gamma 0), `rotate/4`, `clip_angle/2` (a number or `nil`), `precision/2`, `parallels/3`.

### 1.2 Projection types

The 38 type atoms, grouped as the dispatch table in `lib/visualize/geo/projection.ex` groups them:

- Cylindrical (`Projection.Cylindrical`): `:mercator`, `:equirectangular`, `:transverse_mercator`, `:cylindrical_equal_area`, `:miller`, `:gall_peters`.
- Azimuthal (`Projection.Azimuthal`): `:orthographic`, `:stereographic`, `:azimuthal_equal_area`, `:azimuthal_equidistant`, `:gnomonic`.
- Conic (`Projection.Conic`): `:albers`, `:conic_conformal`, `:conic_equal_area`, `:conic_equidistant`, `:polyconic`, `:bonne`.
- Pseudocylindrical (`Projection.Pseudocylindrical`): `:mollweide`, `:sinusoidal`, `:eckert1`, `:eckert2`, `:eckert3`, `:eckert4`, `:eckert5`, `:eckert6`, `:hammer`, `:kavrayskiy7`, `:wagner4`, `:wagner6`, `:fahey`, `:collignon`, `:loximuthal`.
- Compromise (`Projection.Compromise`): `:natural_earth`, `:equal_earth`, `:robinson`, `:winkel_tripel`, `:aitoff`, `:van_der_grinten`.

Type-specific behaviour:

- `:mercator` clamps latitude to ±1.4844 rad (about ±85.05°); `:miller` clamps to ±1.4 rad; `:transverse_mercator` clamps `cos(lat) * sin(lon)` to ±0.9999. None of the cylindrical types returns `nil`.
- `:orthographic` places every point, the far hemisphere folded onto the near one, as d3-geo's `orthographicRaw` does: its clip angle (1.5) hides the far side, and the path's clip closes along a horizon a hair past 90°, which the raw projection must place (#510). `:gnomonic` returns `nil` when the point is on or beyond the horizon; `:stereographic` returns `nil` within 0.001 of the antipode, and `:azimuthal_equal_area` only at the antipode itself, where d3-geo's `azimuthalEqualAreaRaw` carries NaN — its clip circle, 10⁻³° short of it, lies on the map's rim (#510). `orthographic` `invert/3` returns `nil` outside the unit disc.
- `:albers` and `:conic_equal_area` are the same projection; the conic types read both parallels, `:bonne` and `:loximuthal` read only `phi1`. `:polyconic`, `:mollweide`, `:fahey`, `:natural_earth`, `:equal_earth`, `:winkel_tripel`, `:aitoff` and `:van_der_grinten` invert iteratively with a bounded number of steps, so their `invert/3` is approximate.
- Every type places both poles, which the clipped paths of 2.2.1 run along (#509): `:conic_conformal` holds the latitude 10⁻⁶ radians short of the pole behind its apex, as d3-geo's `conicConformalRaw` does, so that pole lies far off the map but finite; `:loximuthal` puts a pole at `x = 0`, as d3-geo-projection's `loximuthalRaw` does; `:mollweide` takes `θ = ±π/2` at a pole without iterating, its Newton step dividing by zero there. Before #509 the three raised `ArithmeticError` at a pole, and so did their `sphere/1`.
- `:transverse_mercator` `invert/3` is Snyder's spherical inverse, `lat = asin(sin(y) / cosh(x))` and `lon = atan2(sinh(x), cos(y))`: `|sin(y) / cosh(x)| ≤ 1` for every point of the plane, so it never raises, and `cos(y) < 0` returns the back hemisphere, so `invert(project(p)) == p` on the whole sphere except the two singular points `(0°, ±90°)` where the forward clamp applies (D-51).


### 1.3 Projection pipeline

`project(proj, lon, lat)` performs, in order: rotation (1.4); subtraction of `center` in degrees; the clip test (1.5), returning `nil` when the point is clipped; the raw family projection, which may itself return `nil`; and finally `{x * scale + tx, -y * scale + ty}` with `{tx, ty} = translate`. The y axis is flipped so that north is up on screen. Output is `{float, float}` or `nil`.

A path does not project its vertices one by one: it takes them through the rotation, clips the lines and polygons there, on the sphere, and projects what the clip leaves through the remaining stages (2.2.1) — centre, clip test, raw projection, scale and translate without a `clip_angle`; with one, the centre is subtracted before the clip, which is the clip test, and what it leaves goes through the raw projection, scale and translate.

`invert(proj, x, y)` computes `{(x - tx) / scale, -(y - ty) / scale}`, applies the raw inverse (which may return `nil`), adds `center`, and applies the inverse rotation. Output is `{lon, lat}` in degrees or `nil`. The clip test is not applied on inversion.

### 1.4 Rotation and centre

`rotate/3,4` stores `{lambda, phi, gamma}` in degrees. On projection, longitude becomes `lon - lambda`, normalised into `[-180, 180]`, so the meridian `lambda` becomes the central meridian (the opposite sign convention from d3's `rotate`, kept on purpose: D-44). When `phi` or `gamma` is non-zero the point is then rotated on the sphere about the x axis by `-phi` (tilt) and about the z axis by `-gamma` (roll). `invert/3` undoes the three in reverse order — about the z axis by `+gamma`, then about the x axis by `+phi`, then `lambda` is added back — so `invert(project(p))` recovers `p` for any `{lambda, phi, gamma}` to the precision of the raw inverse (floating-point noise for the closed forms, the iteration tolerance for the approximate inverses of 1.2). `test/visualize/geo/projection_rotation_test.exs` holds this as a property over every type but transverse Mercator (#9).

`center/3` stores `{lon, lat}`; both are subtracted from the rotated coordinates in degrees before the raw projection. For cylindrical types this shifts the map; for other families it re-centres the sphere rather than translating the projected plane.

### 1.5 Clipping

A point is clipped when its angular distance `c` from the projection centre — computed after rotation and centring as `cos(c) = cos(lat) * cos(lon)` — exceeds `clip_angle`: the test is `cos(c) < cos(clip_angle) - 1.0e-9`, in which case `project/3` returns `nil`. `clip_angle` of `nil` disables the test; 180 clips nothing. `new/1` sets defaults for azimuthal types, d3-geo's own (#510): `:orthographic` `90 + 10⁻⁶`, `:stereographic` 142, `:gnomonic` 60, `:azimuthal_equal_area` and `:azimuthal_equidistant` `180 − 10⁻³`; every other type starts with `nil`. The orthographic's horizon lies a hair past 90° and the whole-sphere azimuthals' a hair short of the antipode, as in d3, so the circle a path is clipped by (2.2.1) is never degenerate: at exactly 90° d3's clip would take its other branch, and at 180° the circle is a point. A point is placed by this test; a line or a polygon is clipped by the circle on the sphere (2.2.1).

### 1.6 Bounds and fitting

`bounds/1` projects the four corners `{-180, -85}`, `{180, -85}`, `{180, 85}`, `{-180, 85}`, drops `nil` results, and returns `[min_x, min_y, max_x, max_y]`; if every corner is clipped it returns `[tx - scale, ty - scale, tx + scale, ty + scale]`. This is a corner-based estimate, not the outline of a curved graticule.

`sphere/1` is that outline (#349): the projection's edge as a closed list of `{x, y}` pixel points, the sphere of d3-geo's `{type: "Sphere"}`. With a `clip_angle` it is the small circle at that angular distance from the projection's centre — for the orthographic the visible disc, radius `scale` — taken in the rotated and centred frame (1.3) so that `rotate` and `center` turn the globe under it, sampled at 360 bearings and projected without the clip test. Without one it is the map's edge: the antimeridian on either side and the two poles, sampled every degree, at latitude ±85 for `:mercator` and `:transverse_mercator` (which have no finite pole, as `bounds/1` assumes) and ±90 for every other type. A point the raw projection cannot place is dropped.

`fit_extent(proj, [[x0, y0], [x1, y1]], [[lon0, lat0], [lon1, lat1]])` sets `scale` to `min(width / Δlon, height / Δlat) * 0.95` with the deltas in radians, `center` to the geographic midpoint and `translate` to the extent's midpoint; `rotate` is untouched. The fit is projection-independent and approximate.

`fit(proj, [[x0, y0], [x1, y1]], points)` is the projection-aware fit (#475), d3-geo's `fitExtent` over a list of `{lon, lat}` points: the projection is taken with `scale` 150 and `translate` `{0, 0}`, every point is projected (a clipped point is skipped), and with `[bx0, by0, bx1, by1]` the bounds of the projected points, `k = min((x1 − x0) / (bx1 − bx0), (y1 − y0) / (by1 − by0))` gives `scale` `150 · k` and `translate` `{x0 + ((x1 − x0) − k · (bx1 + bx0)) / 2, y0 + ((y1 − y0) − k · (by1 + by0)) / 2}`. `center`, `rotate`, `clip_angle` and `parallels` are untouched, so the points' projected bounds are centred in the box and fill it on the tighter axis exactly, whatever the type. An axis along which the points have no extent does not bound `k`; when neither axis does (one point, or every point the same) `scale` is unchanged and `translate` puts the point at the box's centre; with no projectable point the projection is returned unchanged. Because it leaves `center` alone, `fit/3` keeps a Mercator projection Web-Mercator (§8.1), which `fit_extent/3`, centring on the latitude midpoint, does not.

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
| `Visualize.Geo.Projection.precision/2` | Sets `precision` (1.1, 2.2). |
| `Visualize.Geo.Projection.parallels/3` | Sets `parallels` to `{phi1, phi2}` degrees. |
| `Visualize.Geo.Projection.project/3` | `{x, y}` pixels for `lon, lat` degrees, or `nil` when clipped or unprojectable (1.3). |
| `Visualize.Geo.Projection.invert/3` | `{lon, lat}` degrees for `x, y` pixels, or `nil` (1.3). |
| `Visualize.Geo.Projection.bounds/1` | `[x0, y0, x1, y1]` corner-based pixel bounds (1.6). |
| `Visualize.Geo.Projection.sphere/1` | The projection's outline as a closed list of `{x, y}` pixel points (1.6). |
| `Visualize.Geo.Projection.fit_extent/3` | Sets scale, centre and translate to fit a geographic box into a pixel box (1.6). |
| `Visualize.Geo.Projection.fit/3` | Sets scale and translate so a list of `{lon, lat}` points, projected, fills a pixel box on its tighter axis and is centred in it; `center` and `rotate` untouched (1.6). |

## 2. GeoJSON paths

`Visualize.Geo.Path` renders GeoJSON into SVG path data and measures geometries in projected space.

### 2.1 Struct and input

| Field | Default | Meaning |
|---|---|---|
| `projection` | `nil` | A `Projection` struct; when `nil`, positions are used as planar `x, y`. |
| `point_radius` | `4.5` | Radius of the circle drawn for each `Point`. |
| `context` | `nil` | Reserved; unused. |

`new/0` is `new(nil)`. Input is a GeoJSON map with string keys (`"type"`, `"coordinates"`, `"geometry"`, `"features"`, `"geometries"`). `Feature` and `FeatureCollection` are unwrapped; a feature with `"geometry" => nil` contributes nothing. Supported geometry types: `Point`, `MultiPoint`, `LineString`, `MultiLineString`, `Polygon`, `MultiPolygon`, `GeometryCollection`, and `Sphere` (#349) — `%{"type" => "Sphere"}`, d3-geo's whole globe, whose outline is `Visualize.Geo.Projection.sphere/1` (1.6) and which is empty without a projection. A position is a list `[lon, lat | _]`; extra elements are ignored. Any other `"type"` renders as `""`, measures as `0.0` and contributes no points.

### 2.2 Rendering

`render/2` returns one string, concatenating the parts of multi-geometries and collections:

- `Point` — a circle of radius `point_radius` at the projected position as two arcs: `M{cx - r},{cy}A{r},{r},0,1,1,{cx + r},{cy}A{r},{r},0,1,1,{cx - r},{cy}Z`, with numbers interpolated as-is.
- `LineString` — each piece the clip leaves (2.2.1) as `M{x},{y}` followed by `L{x},{y}` per further vertex.
- `Polygon` — each ring of the clipped polygon (2.2.1) rendered as a line string followed by `Z`.
- `Sphere` — the outline of 1.6 as one ring.

Line and ring numbers are floats rounded to 3 decimals (integers unchanged). A point is not clipped on the sphere: it is placed by `project/3`, and a point whose projection is `nil` renders as `""`.

#### 2.2.1 Clipping on the sphere

With a projection, lines and polygons are clipped **on the sphere, before they are projected**, as d3-geo's projection stream clips them (#504, D-127). The internal module Visualize.Geo.Clip is a port of d3-geo 3.1.1's `src/clip/` — `index.js`, `antimeridian.js`, `circle.js`, `rejoin.js` and `buffer.js` — with `src/circle.js`'s `circleStream`, `src/polygonContains.js`, its `src/cartesian.js` helpers and d3-array's exact `Adder`; it and its modules are internal (`@moduledoc false`). The clip is the projection's **preclip**, as d3 chooses it (`src/projection/index.js:101–103`): the small circle of its `clip_angle`, or the antimeridian without one. Without a `clip_angle` every vertex is taken into the **rotated frame** — `rotate` applied (1.4), the longitude in `[-180, 180]` as d3's rotation leaves it — and clipped there; the clip's output then goes through the rest of the pipeline of 1.3 (centre, clip test, raw projection, scale, translate), and an output point the raw projection cannot place is dropped. `center` is applied after the antimeridian clip, so it does not move the seam, as d3's `center` does not. With a `clip_angle` every vertex is taken into the **rotated and centred frame** of the clip test (1.5) — `center` subtracted in degrees after the rotation, the longitude normalised into `[-180, 180]` — so the circle a path is clipped by is the circle the clip test and `sphere/1` (1.6) use, about that frame's origin; with `center` `{0, 0}`, every gallery projection's, it is d3's frame exactly. The circle's output goes through the raw projection, scale and translate, and is not tested again. The clip works in degrees where d3 works in radians, so a vertex the clip passes through is the float the projection would have been given; every tolerance d3 states in radians is restated in degrees, `ε` being d3's `1e-6` radians.

**A projection without `clip_angle` is cut at the antimeridian** (d3's `clipAntimeridian`, the default preclip of every d3 projection):

- **Lines.** An edge whose ends lie on opposite sides of the seam (a longitude above 0 is the eastern side, any other the western) with longitudes at least 180° apart crosses ±180°: it is cut at the latitude where the great circle through its ends meets the antimeridian (`atan((sin φ0 cos φ1 sin λ1 − sin φ1 cos φ0 sin λ0) / (cos φ0 cos φ1 sin(λ0 − λ1)))`, or the mean latitude when `|sin(λ0 − λ1)| ≤ 10⁻⁶`), after an end within `ε` of the seam is moved `180 · 10⁻⁶` degrees off it. The piece before the cut ends at that latitude on its side of the seam and the piece after starts at it on the other. An edge whose ends are 180° apart in longitude (within `ε`) passes over a pole — the north when the mean of its latitudes is positive, the south otherwise — and is cut there, each piece running along the pole to the seam. **Each piece is its own subpath** (`M` … `L`), so a line is never joined across the map.
- **Polygons.** Every ring of a polygon is cut the same way, each ring closed by its first vertex (GeoJSON's closing vertex is dropped and the first appended, as d3's stream does). A ring cut nowhere is drawn as it was given, its closing vertex kept (d3 drops it; `Z` closes the ring either way). The cut rings' pieces are **rejoined along the clip edge** (rejoin.js): when a ring is cut, its last piece runs on into its first; each piece's two ends are intersections, ordered along the edge — up the western side from the south pole, then down the eastern side from the north — and the rejoin walks pieces and edge alternately until it is back where it began, each walk one ring. The edge between two intersections on the same side is the seam between them; between the two sides it runs along a pole: from `from` to the seam's corner at the pole, across to the other side's corner and on to `to`. Whether the first stretch of edge is inside the polygon is whether the polygon contains the south pole on the antimeridian (d3's `polygonContains`, with the spherical winding below); a polygon cut nowhere that contains that point — a ring around a pole, such as Antarctica — is **closed by the whole edge**: across the north pole from the western seam, down the eastern seam, back across the south pole and up the western seam.
- **Winding is spherical, as d3's.** A ring bounds the region on its right as it is walked — on a map with north up, a polygon's exterior ring runs clockwise, its holes anticlockwise — and a ring wound the other way is the **rest of the sphere**: everything outside it, closed along the map's edge. RFC 7946's anticlockwise exterior rings are not this convention; the Natural Earth data of the gallery (`examples/priv/geo/`) is wound for d3.
- **The edge as drawn.** d3 resamples every projected line adaptively, which curves the seam under a pseudo-cylindrical projection; the library resamples nothing. At `precision` 0 the edge is drawn straight between the clip's own points, as d3 draws it at `precision(0)`; at any other `precision` (the default `0.5`) every stretch of edge the clip walks — along one side of the seam or along one pole — is sampled at equal steps of no more than 1°, so a clipped polygon meets the outline of 1.6, which is sampled every degree.

**A projection with `clip_angle` is clipped by the small circle of that radius about the frame's origin** (d3's `clipCircle`, #510) — the orthographic's horizon. A vertex is visible when `cos λ · cos φ > cos r`, `r` the clip angle; the vertices a path is clipped at are never dropped one by one and joined by a chord:

- **Lines.** Where an edge's ends are on either side of the circle it is cut where the great circle through them meets the circle (circle.js:99–133: the intersection of the plane `x = cos r` with the edge's great-circle plane, taken on the unit sphere), and the visible piece ends or starts there. Where both ends are on the far side of a circle smaller than a hemisphere (or both inside one larger than a hemisphere, the clip being the cap about the antipode), the edge can still pass through it — unless the circle is within `ε` of a hemisphere, as the orthographic's is, where it cannot (d3's `notHemisphere`) — and when the codes of its ends against the circle's bounding box share no side, the edge's two meetings with the circle are found, and when the first lies on the edge, the piece between them is drawn (circle.js:63–81, 137–161). A visible vertex repeating the one before it within `ε` is drawn once. **Each piece is its own subpath.**
- **Polygons.** Each ring is cut the same way, closed by its first vertex as at the seam, and a ring cut nowhere is drawn as it was given; the cut rings' pieces are **rejoined along the circle** by the same rejoin (rejoin.js) with the same ordering of intersections (index.js:220–223). The circle between two intersections is walked as d3's `circleStream` walks it, **every 2°** from the angle of the one about the circle's axis to the other's, in the rejoin's direction (src/circle.js:7–32), and those points are drawn at every `precision`: they are the clip's own, which d3 emits at `precision(0)` too, and 2° of a horizon is under a tenth of a pixel from its chord at the gallery's sizes. Whether the first stretch of circle is inside the polygon is whether the polygon contains the clip's start — the circle's southernmost point `(0, −r)` when the circle is smaller than a hemisphere, else `(−180°, r − 180°)` on the antimeridian, the southernmost point of the cap about the antipode (circle.js:176) — by `polygonContains` with the spherical winding above. A polygon that crosses nothing but contains that point — one whose interior holds the whole circle, such as the rest of the sphere about a small ring wound anticlockwise — is **closed by the whole circle**.
- **Winding** is spherical, as at the seam: a ring wound anticlockwise on a north-up map is the rest of the sphere, so a small anticlockwise ring under the orthographic fills the visible disc but for itself.

`test/visualize/geo/clip_test.exs` holds the clip to d3-geo itself: `test/support/geo/clip_golden.jsonl` is d3-geo 3.1.1's output for lines and polygons across the seam, over a pole and around one, a hole, and Natural Earth land under rotated equirectangular and Natural Earth projections; and, for the circle, lines and polygons across circles of 60°, 120° and the orthographic's `90 + 10⁻⁶`, through one from outside, around the centre and around the antipode, wound the other way, with a hole, and Natural Earth land under rotated orthographic, stereographic and azimuthal-equidistant projections at their default clip angles, written by the one-off oracle `test/support/geo/clip_golden.mjs` (spec/12 §1).

#### 2.2.2 As an IR path

`path/2` is the same walk as a `Visualize.IR.Path` (#349): a `Point` as `M` and two `A`s closed with `Z`, a line as `M` and `L`s, a ring the same closed with `Z`, the parts of multi-geometries, collections and feature collections concatenated into one path, an empty path for a geometry with nothing to draw. Its numbers are the projected coordinates unrounded — `Visualize.IR.Path.to_string/1` formats them (spec/02) — so `render/2` and `path/2` agree to the rounding.

### 2.3 Measures

- `area/2` — for `Polygon`, `|shoelace(exterior)| - |sum of shoelace(holes)|`; for `MultiPolygon`, the sum over polygons; for `GeometryCollection`, the sum of members; `0.0` for points and lines. Units are projected pixels squared (or input units squared with no projection). The rings are the geometry's own, each vertex projected by `project/3` and the clipped ones dropped: the area is not taken over the clipped rings of 2.2.1.
- `bounds/2` — `[x0, y0, x1, y1]` over every vertex of the drawn path — the clipped lines and rings of 2.2.1, the seam samples included — or `nil` when there are none.
- `centroid/2` — the arithmetic mean of every vertex of the drawn path (not area-weighted), as `{x, y}`, or `nil` when there are none.

### 2.4 Functions

| Function | Contract |
|---|---|
| `Visualize.Geo.Path.new/0` | `new(nil)`. |
| `Visualize.Geo.Path.new/1` | Creates a path generator with the given projection or `nil`. |
| `Visualize.Geo.Path.projection/2` | Sets the projection. |
| `Visualize.Geo.Path.point_radius/2` | Sets the point circle radius. |
| `Visualize.Geo.Path.render/2` | SVG path data for a GeoJSON object (2.2). |
| `Visualize.Geo.Path.path/2` | The GeoJSON object as a `Visualize.IR.Path` (2.2). |
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

`compute/2` returns one map per threshold: `%{value: threshold, type: "MultiPolygon", coordinates: polygons}` where `polygons` is a list of polygons, each polygon a list containing a single ring, and each ring a list of `[x, y]` two-element lists. Coordinates are grid units — `x` the column, `y` the row — and are clamped to `[0, width - 1]` by `[0, height - 1]`. A grid corner is inside when its value is `>= threshold`. The grid is padded with a border of `min - 1000` before tracing so that regions touching the edge close along it. Rings are traced by following segments end to start; saddle cells (cases 5 and 10) always emit two separate segments. Holes are not distinguished from outer rings — each ring is its own single-ring polygon — and a ring that cannot be closed is emitted as an open polyline. **A crossing never sits on a corner** (#81, D-112): with smoothing on, the interpolation parameter `t` along an edge is kept within `[10⁻⁶, 1 − 10⁻⁶]`, so a corner whose value equals the threshold puts the crossing a hair along each of the edges that meet there rather than on the corner itself, and the two rings that pass a shared corner each continue along their own edges — the segments of one cell join the neighbouring cell's on the shared edge, whose crossing both compute from the same two corners and so to the same point. **A ring closes on its exact start point**: the tracing continues until the current point *is* the start (`==`), never a point within a tolerance, so no ring closes early on a near neighbour along the padded border and no two-point polyline is emitted.

The grid is an indexed structure: `compute/2` turns the list into a tuple and pads it once, before any threshold, so a corner read is constant-time and one threshold costs time linear in the number of cells (D-72). The segments of a threshold are collected in cell order, and the tracing walks them through a map from each segment's start point to its end, taking a segment out of the map as it is followed, so tracing a threshold's rings is linear in its segment count and always terminates. Rings begin at the first untraced segment in cell order, and a ring's points are removed from the map when the ring closes. A start point carries one segment, since no crossing sits on a corner (above), and every closed ring has at least four points — three crossings and the start again.

`render/2` returns `[%{value, path}]`, where `path` is `M..L..` per ring with numbers rounded to 3 decimals, followed by `Z` only when the ring's last point is its first.

### 6.4 Functions

| Function | Contract |
|---|---|
| `Visualize.Contour.new/0` | Creates a generator with a 1×1 grid, no thresholds and smoothing on. |
| `Visualize.Contour.size/3` | Sets grid width and height. |
| `Visualize.Contour.thresholds/2` | Sets a threshold list or count. |
| `Visualize.Contour.smooth/2` | Enables or disables crossing interpolation. |
| `Visualize.Contour.compute/2` | Contour polygons per threshold (6.3). |
| `Visualize.Contour.render/2` | Path data per threshold. |
| `Visualize.Contour.cost/2` | The work one `compute/2` does, as counts: `%{reads, segments, hops}` — the padded cells read per threshold, the segments built, the hops the tracing takes — summed over the thresholds; what holds D-72 (#271). |

## 7. Density contours

`Visualize.Contour.Density` estimates a density surface from points by Gaussian kernel density estimation and contours it with `Visualize.Contour`.

### 7.1 Configuration

| Field | Default | Meaning |
|---|---|---|
| `x`, `y` | `nil` | Accessors `fn datum -> number end`. When `nil`, a map datum is read at `:x`/`:y` through `Visualize.Data.Table.get/2` (`0` when absent or `nil`) and a tuple datum at elements 0/1. |
| `weight` | `nil` | Accessor; when `nil` every datum weighs 1. |
| `width`, `height` | `960`, `500` | Output extent in pixels. |
| `cell_size` | `4` | Grid cell size in pixels. |
| `bandwidth` | `20` | Kernel standard deviation in pixels. |
| `thresholds` | `20` | List or count, as in 6.2, applied to density values. |

`x/2`, `y/2` and `weight/2` require arity-1 functions. `compute/2` passes its points through `Visualize.Data.Table.rows/1` ([08-utilities](08-utilities.md) §6) first, so a column map, an `Nx.Tensor` of rank 2 or a `Table.Reader` struct is accepted wherever a point list is; a list is read as given.

### 7.2 Algorithm

The grid has `div(width, cell_size) + 1` columns and `div(height, cell_size) + 1` rows. Each point `{px, py, w}` adds `w * exp(-d² / (2σ²)) / (2πσ²)` to every cell within a square of half-side `ceil(3 * bandwidth / cell_size)` cells around it (clamped to the grid), where `d` is the distance from the point to the cell in cell units and `σ = bandwidth / cell_size`. Densities are therefore expressed per cell². Contours are computed with smoothing on, and every coordinate is multiplied by `cell_size` so the result is in pixels. `compute/2` returns the same shape as 6.3; `render/2` returns `[%{value, path}]` with every ring closed by `Z`.

A point touches only the cells of its footprint, and its contributions accumulate in a map keyed by cell index that is materialised into the grid once, so the estimate costs time proportional to the points times the footprint plus the cells, never the points times the grid; a cell's contributions are summed in point order, so the surface is the same whatever the order of accumulation (D-72). With the defaults of 7.1 — a 241 × 126 grid and 20 thresholds — `compute/2` over a handful of points completes well inside a second, and `test/visualize/contour_test.exs` holds it to that by count — its reductions within a budget per padded cell and threshold, and ten times the points under one and a half times the work, since the cost is the grid's and not the points times the grid (#462) — and holds the cost of `Visualize.Contour.compute/2` linear by count — `Visualize.Contour.cost/2`, the reads, segments and hops of one compute ([12-testing-and-conformance](12-testing-and-conformance.md), #271).

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

## 8. Web-Mercator tiles

`Visualize.Geo.Tiles` is the arithmetic of a slippy-map basemap (#475): which zoom level's tiles match a Mercator projection, which tiles cover a plot, where each one goes in plot pixels and what its URL is. It is the maths under the `:tiles` mark of [14-declarative-chart](14-declarative-chart.md) §5.2. **It never fetches anything**: it computes URLs and rectangles, and the browser loads each tile as it loads any `<image href>`. Choosing a tile provider, and keeping its usage policy and its attribution, is the host's decision; public servers such as OpenStreetMap's have policies that a dashboard polling them must respect.

A tile is a square of 256 pixels at its own zoom level: at zoom `z` the world is `2^z` tiles wide and `2^z` tiles high, column `x` counted east from the antimeridian and row `y` south from latitude 85.0511° (the latitude whose Mercator ordinate is π), the slippy-map convention every tile server shares.

### 8.1 The aligned projection

Tiles exist in one plane only, Web-Mercator's. A `Visualize.Geo.Projection` is *tile-aligned* when its `type` is `:mercator`, its `center` latitude is `0` and its `rotate` tilt `phi` and roll `gamma` are both `0`. Such a projection with scale `k` and translate `{tx, ty}` places a point at

- `x = tx + k · rad(lon − m)`, where `m = lambda + center_lon` is the central meridian (the rotation's `lambda` and the centre's longitude both shift the map sideways, §1.4);
- `y = ty − k · ln(tan(π/4 + rad(lat) / 2))`,

which is the Web-Mercator plane scaled and shifted. A non-zero centre latitude is subtracted from every latitude *before* the projection (§1.3), which is a different map from that plane, not a vertical shift of it, and a tilt or a roll turns the sphere under it; neither has tiles. `aligned/1` is `:ok` or `{:error, reason}`, the reason `{:type, type}` for another projection type, `:center` for a centre latitude other than zero, `:rotate` for a non-zero tilt or roll, checked in that order.

### 8.2 The zoom

One radian of longitude is `k` pixels (§1.1), so the world is `W = 2πk` pixels wide on the plot. The zoom is the level whose 256-pixel tiles are nearest that size:

`z = round(log2(W / 256))`, clamped to `[0, max_zoom]`,

rounding half away from zero, `max_zoom` `19` unless given (the deepest level OpenStreetMap serves). Each tile is then drawn `t = W / 2^z` pixels square. When `W` is 256 times a power of two, `t` is exactly 256; otherwise the zoom is *fractional* and the tiles are scaled to the projection, `t` between `256 / √2` and `256 · √2` — the nearest level is taken rather than the one below because it keeps the scaling factor nearest 1, so a tile's text is neither blurred by more than √2 nor shrunk by more than it. A projection smaller than one tile, or deeper than `max_zoom`, scales the clamped level's tiles further, as it must: the basemap then stays under the data, blurred or reduced, rather than leaving it.

### 8.3 The covering set

The world's top-left corner — longitude −180°, latitude 85.0511° — lies at the plot pixel

`x0 = tx − W · (m + 180) / 360`, `y0 = ty − W / 2`,

and tile `(i, j)` of the zoom's grid at `(x0 + i · t, y0 + j · t)`, `t` square. The tiles covering a plot `width × height` are the columns `i` from `floor(−x0 / t)` to `ceil((width − x0) / t) − 1` and the rows `j` from `max(0, floor(−y0 / t))` to `min(2^z − 1, ceil((height − y0) / t) − 1)`: a tile that only touches the plot's edge is not in the set, and the rows stop at the poles of the Mercator square, so the plot is empty north and south of it. A column is **wrapped** for its address: its tile is `x = i mod 2^z` (the floored modulo, never negative), so a plot across the antimeridian, or one wide enough to show the world more than once, draws the world's copies side by side as a slippy map does. `cover/3` returns one map per tile, `%{z, x, y, left, top, size}` — `x` wrapped, `left` and `top` the tile's plot pixel, `size` `t` — ordered by row and then by column.

**A point lands where its tile says.** For a point `(lon, lat)` the standard slippy-map formulas give its tile `X = floor((lon + 180) / 360 · 2^z)`, `Y = floor((1 − ln(tan φ + sec φ) / π) / 2 · 2^z)` and its fractions `fx`, `fy` within it; the tile's `left + fx · t`, `top + fy · t` is the point's `Visualize.Geo.Projection.project/3`, up to floating point, because §8.1's plane and the tile grid are one plane at two scales. That is what makes data drawn through the projection sit on the roads of the basemap.

### 8.4 The URL

A tile's URL is its template with `{z}`, `{x}` and `{y}` replaced by the tile's zoom, wrapped column and row as decimal integers, and `{s}` by a subdomain: `subdomains[rem(x + y, n)]` for the `n` subdomains given (Leaflet's rule, so neighbouring tiles go to different hosts and a browser's per-host connection limit is shared among them). Every other character of the template is kept as it is, and nothing is escaped: a template is the provider's own string. A template with `{s}` and no subdomains raises `ArgumentError`.

### 8.5 Functions

| Function | Contract |
|---|---|
| `Visualize.Geo.Tiles.aligned/1` | `:ok` when the projection is tile-aligned, else `{:error, {:type, type} \| :center \| :rotate}` (8.1). |
| `Visualize.Geo.Tiles.zoom/1` | `zoom(proj, [])`. |
| `Visualize.Geo.Tiles.zoom/2` | The zoom level of 8.2 for the projection's scale; option `max_zoom` (`19`). |
| `Visualize.Geo.Tiles.cover/2` | `cover(proj, size, [])`. |
| `Visualize.Geo.Tiles.cover/3` | The tiles covering a plot of `{width, height}` pixels (8.3), as `%{z, x, y, left, top, size}` maps in row-then-column order; option `max_zoom`. Raises `ArgumentError` for a projection that is not tile-aligned. |
| `Visualize.Geo.Tiles.url/3` | The tile's URL from a template and a list of subdomains (8.4). |
