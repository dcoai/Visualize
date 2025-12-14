defmodule Visualize.Geo.Voronoi do
  @moduledoc """
  Voronoi diagram for spatial partitioning.

  Computes the Voronoi tessellation from a Delaunay triangulation.
  Each cell contains all points closer to its site than to any other site.

  ## Examples

      points = [{0, 0}, {100, 0}, {50, 100}, {25, 50}, {75, 50}]

      voronoi = Visualize.Geo.Voronoi.new(points)
        |> Visualize.Geo.Voronoi.bounds([0, 0, 200, 200])

      # Get cell for a specific point
      cell = Visualize.Geo.Voronoi.cell(voronoi, 0)

      # Render all cells as SVG paths
      paths = Visualize.Geo.Voronoi.render_cells(voronoi)

      # Find which cell contains a point
      i = Visualize.Geo.Voronoi.find(voronoi, {30, 30})

  """

  alias Visualize.Geo.Delaunay

  defstruct delaunay: nil,
            bounds: nil,
            circumcenters: []

  @type point :: {number(), number()}
  @type bounds :: {number(), number(), number(), number()}
  @type t :: %__MODULE__{
          delaunay: Delaunay.t(),
          bounds: bounds() | nil,
          circumcenters: [point()]
        }

  @doc "Creates a new Voronoi diagram from points"
  @spec new([point()]) :: t()
  def new(points) when is_list(points) do
    delaunay = Delaunay.new(points)
    circumcenters = compute_circumcenters(delaunay)

    %__MODULE__{
      delaunay: delaunay,
      circumcenters: circumcenters
    }
  end

  @doc "Sets the clipping bounds [x0, y0, x1, y1]"
  @spec bounds(t(), [number()] | bounds()) :: t()
  def bounds(%__MODULE__{} = voronoi, [x0, y0, x1, y1]) do
    %{voronoi | bounds: {x0, y0, x1, y1}}
  end

  def bounds(%__MODULE__{} = voronoi, {x0, y0, x1, y1}) do
    %{voronoi | bounds: {x0, y0, x1, y1}}
  end

  @doc "Returns the Voronoi cell polygon for a given point index"
  @spec cell(t(), non_neg_integer()) :: [point()]
  def cell(%__MODULE__{} = voronoi, point_index) do
    triangles = Delaunay.triangles(voronoi.delaunay)
    circumcenters = voronoi.circumcenters

    # Find all triangles containing this point
    adjacent_triangles =
      triangles
      |> Enum.with_index()
      |> Enum.filter(fn {tri, _i} -> point_index in tri end)
      |> Enum.map(fn {_tri, i} -> i end)

    if Enum.empty?(adjacent_triangles) do
      []
    else
      # Get circumcenters of adjacent triangles
      cell_vertices =
        adjacent_triangles
        |> Enum.map(&Enum.at(circumcenters, &1))
        |> Enum.filter(&(&1 != nil))

      # Sort vertices counter-clockwise around the point
      {px, py} = Enum.at(voronoi.delaunay.points, point_index)
      sorted = sort_ccw(cell_vertices, px, py)

      # Clip to bounds if specified
      case voronoi.bounds do
        nil -> sorted
        bounds -> clip_polygon(sorted, bounds)
      end
    end
  end

  @doc "Returns all Voronoi cells as lists of vertices"
  @spec cells(t()) :: [[point()]]
  def cells(%__MODULE__{} = voronoi) do
    n = length(voronoi.delaunay.points)
    Enum.map(0..(n - 1), &cell(voronoi, &1))
  end

  @doc "Finds which cell contains the given point"
  @spec find(t(), point()) :: integer()
  def find(%__MODULE__{} = voronoi, {px, py}) do
    # Find the closest site
    voronoi.delaunay.points
    |> Enum.with_index()
    |> Enum.min_by(fn {{x, y}, _i} ->
      (x - px) * (x - px) + (y - py) * (y - py)
    end)
    |> elem(1)
  end

  @doc "Generates SVG path data for a specific cell"
  @spec render_cell(t(), non_neg_integer()) :: String.t()
  def render_cell(%__MODULE__{} = voronoi, point_index) do
    vertices = cell(voronoi, point_index)
    polygon_to_path(vertices)
  end

  @doc "Generates SVG path data for all cells"
  @spec render_cells(t()) :: String.t()
  def render_cells(%__MODULE__{} = voronoi) do
    n = length(voronoi.delaunay.points)

    0..(n - 1)
    |> Enum.map(&render_cell(voronoi, &1))
    |> Enum.join()
  end

  @doc """
  Generates SVG with clipPath for rendering cells.

  Uses SVG's native clipPath instead of algorithmic clipping.
  More efficient for rendering, but doesn't compute actual clipped vertices.

  ## Options

  - `:clip_id` - ID for the clipPath element (default: "voronoi-clip")
  - `:stroke` - Stroke color for cell edges (default: "#ccc")
  - `:fill` - Fill color for cells (default: "none")

  ## Example

      voronoi = Voronoi.new(points) |> Voronoi.bounds([0, 0, 400, 400])
      svg = Voronoi.render_cells_clipped(voronoi)

  """
  @spec render_cells_clipped(t(), keyword()) :: String.t()
  def render_cells_clipped(%__MODULE__{} = voronoi, opts \\ []) do
    clip_id = Keyword.get(opts, :clip_id, "voronoi-clip")
    stroke = Keyword.get(opts, :stroke, "#ccc")
    fill = Keyword.get(opts, :fill, "none")

    {x0, y0, x1, y1} = voronoi.bounds || {0, 0, 100, 100}

    # Generate unclipped cells path
    cells_path = render_cells_unclipped(voronoi)

    # Return SVG fragment with clipPath
    """
    <defs>
      <clipPath id="#{clip_id}">
        <rect x="#{x0}" y="#{y0}" width="#{x1 - x0}" height="#{y1 - y0}"/>
      </clipPath>
    </defs>
    <g clip-path="url(##{clip_id})">
      <path d="#{cells_path}" fill="#{fill}" stroke="#{stroke}"/>
    </g>
    """
  end

  @doc """
  Returns a cell's vertices without clipping to bounds.

  Useful when you want to use SVG clipPath for rendering.
  """
  @spec cell_unclipped(t(), non_neg_integer()) :: [point()]
  def cell_unclipped(%__MODULE__{} = voronoi, point_index) do
    triangles = Delaunay.triangles(voronoi.delaunay)
    circumcenters = voronoi.circumcenters

    adjacent_triangles =
      triangles
      |> Enum.with_index()
      |> Enum.filter(fn {tri, _i} -> point_index in tri end)
      |> Enum.map(fn {_tri, i} -> i end)

    if Enum.empty?(adjacent_triangles) do
      []
    else
      cell_vertices =
        adjacent_triangles
        |> Enum.map(&Enum.at(circumcenters, &1))
        |> Enum.filter(&(&1 != nil))

      {px, py} = Enum.at(voronoi.delaunay.points, point_index)
      sort_ccw(cell_vertices, px, py)
    end
  end

  # Generates path data for all cells without clipping
  defp render_cells_unclipped(%__MODULE__{} = voronoi) do
    n = length(voronoi.delaunay.points)

    0..(n - 1)
    |> Enum.map(fn i ->
      vertices = cell_unclipped(voronoi, i)
      polygon_to_path(vertices)
    end)
    |> Enum.join()
  end

  @doc "Returns the edges of the Voronoi diagram"
  @spec edges(t()) :: [{point(), point()}]
  def edges(%__MODULE__{} = voronoi) do
    triangles = Delaunay.triangles(voronoi.delaunay)
    circumcenters = voronoi.circumcenters

    # For each pair of adjacent triangles, there's a Voronoi edge
    # between their circumcenters
    triangles
    |> Enum.with_index()
    |> Enum.flat_map(fn {[i, j, k], tri_idx} ->
      # Each edge of the triangle corresponds to an adjacent triangle
      [{i, j}, {j, k}, {k, i}]
      |> Enum.flat_map(fn {a, b} ->
        edge = if a < b, do: {a, b}, else: {b, a}

        # Find other triangle sharing this edge
        other_idx =
          triangles
          |> Enum.with_index()
          |> Enum.find(fn {tri, idx} ->
            idx != tri_idx and a in tri and b in tri
          end)

        case other_idx do
          nil -> []
          {_, idx} when idx > tri_idx ->
            c1 = Enum.at(circumcenters, tri_idx)
            c2 = Enum.at(circumcenters, idx)
            if c1 && c2, do: [{c1, c2}], else: []
          _ -> []
        end
      end)
    end)
  end

  @doc "Generates SVG path data for all Voronoi edges"
  @spec render_edges(t()) :: String.t()
  def render_edges(%__MODULE__{} = voronoi) do
    edges(voronoi)
    |> Enum.map(fn {{x0, y0}, {x1, y1}} ->
      "M#{x0},#{y0}L#{x1},#{y1}"
    end)
    |> Enum.join()
  end

  # Compute circumcenters for all triangles
  defp compute_circumcenters(%Delaunay{} = delaunay) do
    triangles = Delaunay.triangles(delaunay)
    points = delaunay.points

    Enum.map(triangles, fn [i, j, k] ->
      {x0, y0} = Enum.at(points, i)
      {x1, y1} = Enum.at(points, j)
      {x2, y2} = Enum.at(points, k)
      circumcenter(x0, y0, x1, y1, x2, y2)
    end)
  end

  # Compute circumcenter of a triangle
  defp circumcenter(x0, y0, x1, y1, x2, y2) do
    ax = x1 - x0
    ay = y1 - y0
    bx = x2 - x0
    by = y2 - y0

    d = 2 * (ax * by - ay * bx)

    if abs(d) < 1.0e-10 do
      # Degenerate triangle, return centroid
      {(x0 + x1 + x2) / 3, (y0 + y1 + y2) / 3}
    else
      al = ax * ax + ay * ay
      bl = bx * bx + by * by

      cx = x0 + (by * al - ay * bl) / d
      cy = y0 + (ax * bl - bx * al) / d

      {cx, cy}
    end
  end

  # Sort points counter-clockwise around a center
  defp sort_ccw(points, cx, cy) do
    Enum.sort_by(points, fn {x, y} ->
      :math.atan2(y - cy, x - cx)
    end)
  end

  # Convert polygon vertices to SVG path
  defp polygon_to_path([]), do: ""

  defp polygon_to_path([{x0, y0} | rest]) do
    start = "M#{x0},#{y0}"

    lines =
      rest
      |> Enum.map(fn {x, y} -> "L#{x},#{y}" end)
      |> Enum.join()

    start <> lines <> "Z"
  end

  # Clip polygon to bounding box using Sutherland-Hodgman algorithm
  defp clip_polygon([], _bounds), do: []

  defp clip_polygon(polygon, {x0, y0, x1, y1}) do
    polygon
    |> clip_edge(x0, :left)
    |> clip_edge(x1, :right)
    |> clip_edge(y0, :top)
    |> clip_edge(y1, :bottom)
  end

  defp clip_edge([], _boundary, _side), do: []

  defp clip_edge(polygon, boundary, side) do
    n = length(polygon)

    if n == 0 do
      []
    else
      0..(n - 1)
      |> Enum.flat_map(fn i ->
        current = Enum.at(polygon, i)
        next = Enum.at(polygon, rem(i + 1, n))

        current_inside = inside?(current, boundary, side)
        next_inside = inside?(next, boundary, side)

        cond do
          current_inside and next_inside ->
            [next]

          current_inside and not next_inside ->
            [intersection(current, next, boundary, side)]

          not current_inside and next_inside ->
            [intersection(current, next, boundary, side), next]

          true ->
            []
        end
      end)
    end
  end

  defp inside?({x, _y}, boundary, :left), do: x >= boundary
  defp inside?({x, _y}, boundary, :right), do: x <= boundary
  defp inside?({_x, y}, boundary, :top), do: y >= boundary
  defp inside?({_x, y}, boundary, :bottom), do: y <= boundary

  defp intersection({x0, y0}, {x1, y1}, boundary, side) do
    case side do
      :left ->
        t = (boundary - x0) / (x1 - x0)
        {boundary, y0 + t * (y1 - y0)}

      :right ->
        t = (boundary - x0) / (x1 - x0)
        {boundary, y0 + t * (y1 - y0)}

      :top ->
        t = (boundary - y0) / (y1 - y0)
        {x0 + t * (x1 - x0), boundary}

      :bottom ->
        t = (boundary - y0) / (y1 - y0)
        {x0 + t * (x1 - x0), boundary}
    end
  end
end
