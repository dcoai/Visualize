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
    render_geojson(geo_path, geojson)
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
  # GeoJSON Rendering
  # ============================================

  defp render_geojson(geo_path, %{"type" => "FeatureCollection", "features" => features}) do
    features
    |> Enum.map(&render_geojson(geo_path, &1))
    |> Enum.join()
  end

  defp render_geojson(geo_path, %{"type" => "Feature", "geometry" => geometry}) do
    render_geometry(geo_path, geometry)
  end

  defp render_geojson(geo_path, %{"type" => type} = geometry) when type != "Feature" do
    render_geometry(geo_path, geometry)
  end

  defp render_geojson(_, _), do: ""

  defp render_geometry(_, nil), do: ""

  defp render_geometry(geo_path, %{"type" => "Point", "coordinates" => coords}) do
    render_point(geo_path, coords)
  end

  defp render_geometry(geo_path, %{"type" => "MultiPoint", "coordinates" => points}) do
    points
    |> Enum.map(&render_point(geo_path, &1))
    |> Enum.join()
  end

  defp render_geometry(geo_path, %{"type" => "LineString", "coordinates" => coords}) do
    render_line(geo_path, coords)
  end

  defp render_geometry(geo_path, %{"type" => "MultiLineString", "coordinates" => lines}) do
    lines
    |> Enum.map(&render_line(geo_path, &1))
    |> Enum.join()
  end

  defp render_geometry(geo_path, %{"type" => "Polygon", "coordinates" => rings}) do
    render_polygon(geo_path, rings)
  end

  defp render_geometry(geo_path, %{"type" => "MultiPolygon", "coordinates" => polygons}) do
    polygons
    |> Enum.map(&render_polygon(geo_path, &1))
    |> Enum.join()
  end

  defp render_geometry(geo_path, %{"type" => "GeometryCollection", "geometries" => geometries}) do
    geometries
    |> Enum.map(&render_geometry(geo_path, &1))
    |> Enum.join()
  end

  defp render_geometry(_, _), do: ""

  # Render a point as a circle
  defp render_point(%{projection: nil} = geo_path, [x, y | _]) do
    r = geo_path.point_radius
    circle_path(x, y, r)
  end

  defp render_point(%{projection: proj} = geo_path, [lon, lat | _]) do
    case Projection.project(proj, lon, lat) do
      nil ->
        ""

      {x, y} ->
        r = geo_path.point_radius
        circle_path(x, y, r)
    end
  end

  defp circle_path(cx, cy, r) do
    "M#{cx - r},#{cy}A#{r},#{r},0,1,1,#{cx + r},#{cy}A#{r},#{r},0,1,1,#{cx - r},#{cy}Z"
  end

  # Render a line string
  defp render_line(%{projection: nil}, coords) do
    render_line_coords(coords)
  end

  defp render_line(%{projection: proj}, coords) do
    projected =
      coords
      |> Enum.map(fn [lon, lat | _] -> Projection.project(proj, lon, lat) end)
      |> Enum.filter(& &1)

    render_line_coords(projected)
  end

  defp render_line_coords([]), do: ""

  defp render_line_coords([{x0, y0} | rest]) do
    start = "M#{format_num(x0)},#{format_num(y0)}"

    lines =
      rest
      |> Enum.map(fn {x, y} -> "L#{format_num(x)},#{format_num(y)}" end)
      |> Enum.join()

    start <> lines
  end

  defp render_line_coords([[x0, y0 | _] | rest]) do
    start = "M#{format_num(x0)},#{format_num(y0)}"

    lines =
      rest
      |> Enum.map(fn [x, y | _] -> "L#{format_num(x)},#{format_num(y)}" end)
      |> Enum.join()

    start <> lines
  end

  # Render a polygon (with holes)
  defp render_polygon(%{projection: nil}, rings) do
    rings
    |> Enum.map(&render_ring_coords/1)
    |> Enum.join()
  end

  defp render_polygon(%{projection: proj}, rings) do
    rings
    |> Enum.map(fn ring ->
      projected =
        ring
        |> Enum.map(fn [lon, lat | _] -> Projection.project(proj, lon, lat) end)
        |> Enum.filter(& &1)

      render_ring_coords(projected)
    end)
    |> Enum.join()
  end

  defp render_ring_coords([]), do: ""

  defp render_ring_coords([{x0, y0} | rest]) do
    start = "M#{format_num(x0)},#{format_num(y0)}"

    lines =
      rest
      |> Enum.map(fn {x, y} -> "L#{format_num(x)},#{format_num(y)}" end)
      |> Enum.join()

    start <> lines <> "Z"
  end

  defp render_ring_coords([[x0, y0 | _] | rest]) do
    start = "M#{format_num(x0)},#{format_num(y0)}"

    lines =
      rest
      |> Enum.map(fn [x, y | _] -> "L#{format_num(x)},#{format_num(y)}" end)
      |> Enum.join()

    start <> lines <> "Z"
  end

  # ============================================
  # Point Collection
  # ============================================

  defp collect_points(geo_path, %{"type" => "FeatureCollection", "features" => features}) do
    Enum.flat_map(features, &collect_points(geo_path, &1))
  end

  defp collect_points(geo_path, %{"type" => "Feature", "geometry" => geometry}) do
    collect_geometry_points(geo_path, geometry)
  end

  defp collect_points(geo_path, %{"type" => type} = geometry) when type != "Feature" do
    collect_geometry_points(geo_path, geometry)
  end

  defp collect_points(_, _), do: []

  defp collect_geometry_points(_, nil), do: []

  defp collect_geometry_points(geo_path, %{"type" => "Point", "coordinates" => coords}) do
    project_coord(geo_path, coords)
  end

  defp collect_geometry_points(geo_path, %{"type" => "MultiPoint", "coordinates" => points}) do
    Enum.flat_map(points, &project_coord(geo_path, &1))
  end

  defp collect_geometry_points(geo_path, %{"type" => "LineString", "coordinates" => coords}) do
    Enum.flat_map(coords, &project_coord(geo_path, &1))
  end

  defp collect_geometry_points(geo_path, %{"type" => "MultiLineString", "coordinates" => lines}) do
    lines |> Enum.flat_map(fn line -> Enum.flat_map(line, &project_coord(geo_path, &1)) end)
  end

  defp collect_geometry_points(geo_path, %{"type" => "Polygon", "coordinates" => rings}) do
    rings |> Enum.flat_map(fn ring -> Enum.flat_map(ring, &project_coord(geo_path, &1)) end)
  end

  defp collect_geometry_points(geo_path, %{"type" => "MultiPolygon", "coordinates" => polygons}) do
    polygons
    |> Enum.flat_map(fn polygon ->
      Enum.flat_map(polygon, fn ring -> Enum.flat_map(ring, &project_coord(geo_path, &1)) end)
    end)
  end

  defp collect_geometry_points(geo_path, %{"type" => "GeometryCollection", "geometries" => geoms}) do
    Enum.flat_map(geoms, &collect_geometry_points(geo_path, &1))
  end

  defp collect_geometry_points(_, _), do: []

  defp project_coord(%{projection: nil}, [x, y | _]), do: [{x, y}]

  defp project_coord(%{projection: proj}, [lon, lat | _]) do
    case Projection.project(proj, lon, lat) do
      nil -> []
      point -> [point]
    end
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
      0..(n - 1)
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
