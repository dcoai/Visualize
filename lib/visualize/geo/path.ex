defmodule Visualize.Geo.Path do
  @moduledoc """
  Renders GeoJSON geometries as SVG path strings.

  Takes GeoJSON data and a projection to produce SVG paths
  suitable for rendering maps.

  ## Examples

      projection = Visualize.Geo.Projection.new(:mercator)
        |> Visualize.Geo.Projection.scale(100)
        |> Visualize.Geo.Projection.translate(200, 150)

      geo_path = Visualize.Geo.Path.new(projection)

      # Render a GeoJSON feature
      feature = %{
        "type" => "Feature",
        "geometry" => %{
          "type" => "Polygon",
          "coordinates" => [[[-122, 37], [-122, 38], [-121, 38], [-121, 37], [-122, 37]]]
        }
      }

      path_data = Visualize.Geo.Path.render(geo_path, feature)

  ## Clipping on the sphere

  With a projection, lines and polygons are clipped on the sphere before they are
  projected, as d3-geo clips them (spec/07 §2.2.1, D-127): under a projection with a
  `clip_angle` they are cut where they cross the small circle of that radius about the
  centre — the orthographic's horizon — a line into several subpaths and a polygon closed
  along the circle, so a globe never closes its land by a chord across the disc; under a
  projection without one they are cut where they cross ±180° of the rotated frame and a
  polygon is closed along the seam and the poles, so a rotated map never joins a ring the
  long way round. Winding is d3's: a polygon's exterior ring runs clockwise on a north-up
  map, and a ring wound the other way is the rest of the sphere.

  """

  alias Visualize.Geo.Clip
  alias Visualize.Geo.Clip.{Antimeridian, Circle}
  alias Visualize.Geo.Projection
  alias Visualize.IR

  defstruct projection: nil,
            point_radius: 4.5,
            context: nil

  @type t :: %__MODULE__{
          projection: Projection.t() | nil,
          point_radius: number(),
          context: any()
        }

  @doc "Creates a new GeoPath with the given projection"
  @spec new(Projection.t() | nil) :: t()
  def new(projection \\ nil) do
    %__MODULE__{projection: projection}
  end

  @doc "Sets the projection"
  @spec projection(t(), Projection.t()) :: t()
  def projection(%__MODULE__{} = geo_path, proj) do
    %{geo_path | projection: proj}
  end

  @doc "Sets the radius for Point geometries"
  @spec point_radius(t(), number()) :: t()
  def point_radius(%__MODULE__{} = geo_path, radius) do
    %{geo_path | point_radius: radius}
  end

  @doc """
  Renders GeoJSON to an SVG path string.

  Accepts GeoJSON Feature, FeatureCollection, or raw Geometry objects.
  """
  @spec render(t(), map()) :: String.t()
  def render(%__MODULE__{} = geo_path, geojson) do
    geo_path |> parts(geojson) |> Enum.map_join(&render_part/1)
  end

  @doc """
  The GeoJSON object as a `Visualize.IR.Path` (spec/07 §2.2): the same walk as `render/2`,
  its numbers the projected coordinates unrounded, and an empty path for a geometry with
  nothing to draw.
  """
  @spec path(t(), map()) :: IR.Path.t()
  def path(%__MODULE__{} = geo_path, geojson) do
    geo_path |> parts(geojson) |> Enum.reduce(IR.Path.new(), &path_part/2)
  end

  @doc """
  Computes the centroid of a GeoJSON geometry.

  Returns {x, y} in projected coordinates.
  """
  @spec centroid(t(), map()) :: {float(), float()} | nil
  def centroid(%__MODULE__{} = geo_path, geojson) do
    geo_path |> parts(geojson) |> parts_centroid()
  end

  @doc false
  # `path/2` and `centroid/2` from one walk, so the clip runs once: the `:projection` step
  # reads both for every row (spec/14 §5.4.4).
  @spec path_and_centroid(t(), map()) :: {IR.Path.t(), {float(), float()} | nil}
  def path_and_centroid(%__MODULE__{} = geo_path, geojson) do
    parts = parts(geo_path, geojson)
    {Enum.reduce(parts, IR.Path.new(), &path_part/2), parts_centroid(parts)}
  end

  defp parts_centroid(parts) do
    case parts_points(parts) do
      [] ->
        nil

      points ->
        n = length(points)
        {sum_x, sum_y} = Enum.reduce(points, {0, 0}, fn {x, y}, {sx, sy} -> {sx + x, sy + y} end)
        {sum_x / n, sum_y / n}
    end
  end

  @doc """
  Computes the bounding box of a GeoJSON geometry.

  Returns [x0, y0, x1, y1] in projected coordinates.
  """
  @spec bounds(t(), map()) :: [float()] | nil
  def bounds(%__MODULE__{} = geo_path, geojson) do
    points = collect_points(geo_path, geojson)

    if Enum.empty?(points) do
      nil
    else
      xs = Enum.map(points, fn {x, _} -> x end)
      ys = Enum.map(points, fn {_, y} -> y end)
      [Enum.min(xs), Enum.min(ys), Enum.max(xs), Enum.max(ys)]
    end
  end

  @doc """
  Computes the projected planar area of a GeoJSON geometry.
  """
  @spec area(t(), map()) :: float()
  def area(%__MODULE__{} = geo_path, geojson) do
    compute_area(geo_path, geojson)
  end

  # ============================================
  # The walk (spec/07 §2.2)
  # ============================================

  # A GeoJSON object as the parts a path is drawn from, every vertex projected: a point
  # (its centre and radius), a line and a ring (their vertices, in order). Lines and
  # polygons are clipped on the sphere first (`clip_parts/3`), so a line may become several
  # and a polygon's rings are the clipped rings. `render/2` and `path/2` serialise the same
  # parts, and the measures read their vertices.
  defp parts(geo_path, %{"type" => "FeatureCollection", "features" => features}) do
    Enum.flat_map(features, &parts(geo_path, &1))
  end

  defp parts(geo_path, %{"type" => "Feature", "geometry" => geometry}) do
    geometry_parts(geo_path, geometry)
  end

  defp parts(geo_path, %{"type" => type} = geometry) when type != "Feature" do
    geometry_parts(geo_path, geometry)
  end

  defp parts(_, _), do: []

  defp geometry_parts(_, nil), do: []

  defp geometry_parts(geo_path, %{"type" => "Point", "coordinates" => coords}) do
    Enum.map(project_coord(geo_path, coords), fn {x, y} ->
      {:point, x, y, geo_path.point_radius}
    end)
  end

  defp geometry_parts(geo_path, %{"type" => "MultiPoint", "coordinates" => points}) do
    Enum.flat_map(points, &geometry_parts(geo_path, %{"type" => "Point", "coordinates" => &1}))
  end

  defp geometry_parts(geo_path, %{"type" => "LineString", "coordinates" => coords}) do
    clip_parts(geo_path, :line, coords)
  end

  defp geometry_parts(geo_path, %{"type" => "MultiLineString", "coordinates" => lines}) do
    Enum.flat_map(lines, &clip_parts(geo_path, :line, &1))
  end

  defp geometry_parts(geo_path, %{"type" => "Polygon", "coordinates" => rings}) do
    clip_parts(geo_path, :polygon, rings)
  end

  defp geometry_parts(geo_path, %{"type" => "MultiPolygon", "coordinates" => polygons}) do
    Enum.flat_map(polygons, &clip_parts(geo_path, :polygon, &1))
  end

  defp geometry_parts(geo_path, %{"type" => "GeometryCollection", "geometries" => geometries}) do
    Enum.flat_map(geometries, &geometry_parts(geo_path, &1))
  end

  # The whole globe: the projection's outline (spec/07 §1.6), nothing without one.
  defp geometry_parts(%{projection: nil}, %{"type" => "Sphere"}), do: []

  defp geometry_parts(%{projection: proj}, %{"type" => "Sphere"}),
    do: [{:ring, Projection.sphere(proj)}]

  defp geometry_parts(_, _), do: []

  # -- the clip on the sphere (spec/07 §2.2, D-127) --

  # A line or a polygon's rings as parts. With a projection the vertices are taken into
  # the clip's frame, clipped there, and the clip's output projected; without one they are
  # planar and drawn as they are.
  defp clip_parts(%{projection: nil}, :line, coords),
    do: [{:line, Enum.map(coords, fn [x, y | _] -> {x, y} end)}]

  defp clip_parts(%{projection: nil}, :polygon, rings),
    do: Enum.map(rings, &{:ring, Enum.map(&1, fn [x, y | _] -> {x, y} end)})

  defp clip_parts(%{projection: proj}, :line, coords) do
    clipper = clipper(proj)

    clipper
    |> Clip.line(frame(proj, clipper, coords))
    |> Enum.map(&{:line, project_frame(proj, clipper, &1)})
  end

  defp clip_parts(%{projection: proj}, :polygon, rings) do
    clipper = clipper(proj)

    clipper
    |> Clip.polygon(Enum.map(rings, &frame(proj, clipper, &1)))
    |> Enum.map(&{:ring, project_frame(proj, clipper, &1)})
  end

  # The clip a projection's paths are cut by (d3-geo's preclip, projection/index.js:101–
  # 103): the small circle of its `clip_angle`, or the antimeridian without one, its seam
  # sampled every degree but at precision 0.
  defp clipper(%Projection{clip_angle: nil, precision: precision}),
    do: %Antimeridian{step: if(precision == 0, do: nil, else: 1)}

  defp clipper(%Projection{clip_angle: angle}), do: Circle.new(angle)

  # The antimeridian is the rotated frame's, before `center`; the circle is about the
  # projection's centre, the clip test's frame (spec/07 §1.5), and what it keeps is not
  # tested again.
  defp frame(proj, %Circle{}, coords),
    do: Enum.map(coords, fn [lon, lat | _] -> Projection.centred(proj, lon, lat) end)

  defp frame(proj, _clipper, coords),
    do: Enum.map(coords, fn [lon, lat | _] -> Projection.rotated(proj, lon, lat) end)

  defp project_frame(proj, %Circle{}, points) do
    for {lon, lat} <- points, xy = Projection.project_centred(proj, lon, lat), xy != nil, do: xy
  end

  defp project_frame(proj, _clipper, points) do
    for {lon, lat} <- points, xy = Projection.project_rotated(proj, lon, lat), xy != nil, do: xy
  end

  defp project_coord(%{projection: nil}, [x, y | _]), do: [{x, y}]

  defp project_coord(%{projection: proj}, [lon, lat | _]) do
    case Projection.project(proj, lon, lat) do
      nil -> []
      point -> [point]
    end
  end

  # -- as a string: numbers rounded to 3 decimals (spec/07 §2.2) --

  defp render_part({:point, cx, cy, r}) do
    "M#{cx - r},#{cy}A#{r},#{r},0,1,1,#{cx + r},#{cy}A#{r},#{r},0,1,1,#{cx - r},#{cy}Z"
  end

  defp render_part({:line, points}), do: render_points(points)
  defp render_part({:ring, []}), do: ""
  defp render_part({:ring, points}), do: render_points(points) <> "Z"

  defp render_points([]), do: ""

  defp render_points([{x0, y0} | rest]) do
    "M#{format_num(x0)},#{format_num(y0)}" <>
      Enum.map_join(rest, fn {x, y} -> "L#{format_num(x)},#{format_num(y)}" end)
  end

  # -- as an IR path: the coordinates as they are --

  defp path_part({:point, cx, cy, r}, path) do
    path
    |> IR.Path.move_to(cx - r, cy)
    |> IR.Path.arc_to(r, r, 0, 1, 1, cx + r, cy)
    |> IR.Path.arc_to(r, r, 0, 1, 1, cx - r, cy)
    |> IR.Path.close()
  end

  defp path_part({:line, points}, path), do: path_points(path, points)
  defp path_part({:ring, []}, path), do: path
  defp path_part({:ring, points}, path), do: path |> path_points(points) |> IR.Path.close()

  defp path_points(path, []), do: path

  defp path_points(path, [{x0, y0} | rest]) do
    Enum.reduce(rest, IR.Path.move_to(path, x0, y0), fn {x, y}, acc ->
      IR.Path.line_to(acc, x, y)
    end)
  end

  # ============================================
  # Point Collection
  # ============================================

  # Every projected vertex of the object, a point's centre for a point part.
  defp collect_points(geo_path, geojson), do: geo_path |> parts(geojson) |> parts_points()

  defp parts_points(parts) do
    Enum.flat_map(parts, fn
      {:point, x, y, _r} -> [{x, y}]
      {_line_or_ring, points} -> points
    end)
  end

  # ============================================
  # Area Computation
  # ============================================

  defp compute_area(geo_path, %{"type" => "FeatureCollection", "features" => features}) do
    Enum.reduce(features, 0, fn f, acc -> acc + compute_area(geo_path, f) end)
  end

  defp compute_area(geo_path, %{"type" => "Feature", "geometry" => geometry}) do
    compute_geometry_area(geo_path, geometry)
  end

  defp compute_area(geo_path, %{"type" => type} = geometry) when type != "Feature" do
    compute_geometry_area(geo_path, geometry)
  end

  defp compute_area(_, _), do: 0.0

  defp compute_geometry_area(_, nil), do: 0.0

  defp compute_geometry_area(geo_path, %{"type" => "Polygon", "coordinates" => rings}) do
    [exterior | holes] = rings
    exterior_area = ring_area(geo_path, exterior)
    holes_area = Enum.reduce(holes, 0, fn hole, acc -> acc + ring_area(geo_path, hole) end)
    abs(exterior_area) - abs(holes_area)
  end

  defp compute_geometry_area(geo_path, %{"type" => "MultiPolygon", "coordinates" => polygons}) do
    Enum.reduce(polygons, 0, fn rings, acc ->
      [exterior | holes] = rings
      exterior_area = ring_area(geo_path, exterior)
      holes_area = Enum.reduce(holes, 0, fn hole, hacc -> hacc + ring_area(geo_path, hole) end)
      acc + abs(exterior_area) - abs(holes_area)
    end)
  end

  defp compute_geometry_area(geo_path, %{"type" => "GeometryCollection", "geometries" => geoms}) do
    Enum.reduce(geoms, 0, fn g, acc -> acc + compute_geometry_area(geo_path, g) end)
  end

  defp compute_geometry_area(_, _), do: 0.0

  defp ring_area(%{projection: nil}, coords) do
    shoelace_area(coords)
  end

  defp ring_area(%{projection: proj}, coords) do
    projected =
      coords
      |> Enum.map(fn [lon, lat | _] -> Projection.project(proj, lon, lat) end)
      |> Enum.filter(& &1)

    shoelace_area(projected)
  end

  defp shoelace_area([]), do: 0.0
  defp shoelace_area([_]), do: 0.0

  defp shoelace_area(points) do
    n = length(points)

    sum =
      0..(n - 1)//1
      |> Enum.reduce(0, fn i, acc ->
        {x0, y0} = get_point(points, i)
        {x1, y1} = get_point(points, rem(i + 1, n))
        acc + x0 * y1 - x1 * y0
      end)

    sum / 2
  end

  defp get_point(points, i) do
    case Enum.at(points, i) do
      {x, y} -> {x, y}
      [x, y | _] -> {x, y}
      _ -> {0, 0}
    end
  end

  defp format_num(n) when is_float(n), do: Float.round(n, 3) |> to_string()
  defp format_num(n), do: to_string(n)
end
