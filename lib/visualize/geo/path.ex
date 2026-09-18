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
          "coordinates" => [[[-122, 37], [-121, 37], [-121, 38], [-122, 38], [-122, 37]]]
        }
      }

      path_data = Visualize.Geo.Path.render(geo_path, feature)

  """

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
    points = collect_points(geo_path, geojson)

    if Enum.empty?(points) do
      nil
    else
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
  # (its centre and radius), a line and a ring (their vertices, in order, the clipped ones
  # dropped). `render/2` and `path/2` serialise the same parts, and the measures read
  # their vertices.
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
    [{:line, vertices(geo_path, coords)}]
  end

  defp geometry_parts(geo_path, %{"type" => "MultiLineString", "coordinates" => lines}) do
    Enum.map(lines, &{:line, vertices(geo_path, &1)})
  end

  defp geometry_parts(geo_path, %{"type" => "Polygon", "coordinates" => rings}) do
    Enum.map(rings, &{:ring, vertices(geo_path, &1)})
  end

  defp geometry_parts(geo_path, %{"type" => "MultiPolygon", "coordinates" => polygons}) do
    Enum.flat_map(polygons, fn rings -> Enum.map(rings, &{:ring, vertices(geo_path, &1)}) end)
  end

  defp geometry_parts(geo_path, %{"type" => "GeometryCollection", "geometries" => geometries}) do
    Enum.flat_map(geometries, &geometry_parts(geo_path, &1))
  end

  # The whole globe: the projection's outline (spec/07 §1.6), nothing without one.
  defp geometry_parts(%{projection: nil}, %{"type" => "Sphere"}), do: []

  defp geometry_parts(%{projection: proj}, %{"type" => "Sphere"}),
    do: [{:ring, Projection.sphere(proj)}]

  defp geometry_parts(_, _), do: []

  defp vertices(geo_path, coords), do: Enum.flat_map(coords, &project_coord(geo_path, &1))

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
  defp collect_points(geo_path, geojson) do
    geo_path
    |> parts(geojson)
    |> Enum.flat_map(fn
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
