defmodule Visualize.Geo.Delaunay do
  @moduledoc """
  Delaunay triangulation for a set of points.

  Computes the Delaunay triangulation, which connects points such that
  no point is inside the circumcircle of any triangle. This is useful
  for interpolation, mesh generation, and computing Voronoi diagrams.

  ## Examples

      points = [{0, 0}, {100, 0}, {50, 100}, {25, 50}, {75, 50}]

      delaunay = Visualize.Geo.Delaunay.new(points)

      # Get triangles (each is [i, j, k] indices)
      triangles = Visualize.Geo.Delaunay.triangles(delaunay)

      # Find which triangle contains a point
      i = Visualize.Geo.Delaunay.find(delaunay, {30, 30})

      # Get neighbors of a point
      neighbors = Visualize.Geo.Delaunay.neighbors(delaunay, 0)

  """

  defstruct points: [],
            triangles: [],
            halfedges: [],
            hull: []

  @type point :: {number(), number()}
  @type t :: %__MODULE__{
          points: [point()],
          triangles: [non_neg_integer()],
          halfedges: [integer()],
          hull: [non_neg_integer()]
        }

  @doc "Creates a new Delaunay triangulation from points"
  @spec new([point()]) :: t()
  def new(points) when is_list(points) do
    n = length(points)

    if n < 3 do
      %__MODULE__{points: points, triangles: [], halfedges: [], hull: Enum.to_list(0..(n-1))}
    else
      # Use Bowyer-Watson algorithm for Delaunay triangulation
      compute_delaunay(points)
    end
  end

  @doc "Returns the triangles as lists of point indices"
  @spec triangles(t()) :: [[non_neg_integer()]]
  def triangles(%__MODULE__{triangles: tris}) do
    tris
    |> Enum.chunk_every(3)
  end

  @doc "Returns the points"
  @spec points(t()) :: [point()]
  def points(%__MODULE__{points: pts}), do: pts

  @doc "Returns the convex hull as point indices"
  @spec hull(t()) :: [non_neg_integer()]
  def hull(%__MODULE__{hull: h}), do: h

  @doc "Finds the triangle containing the given point, returns triangle index or -1"
  @spec find(t(), point()) :: integer()
  def find(%__MODULE__{} = delaunay, {px, py}) do
    tris = triangles(delaunay)
    pts = delaunay.points

    Enum.find_index(tris, fn [i, j, k] ->
      {x0, y0} = Enum.at(pts, i)
      {x1, y1} = Enum.at(pts, j)
      {x2, y2} = Enum.at(pts, k)
      point_in_triangle?(px, py, x0, y0, x1, y1, x2, y2)
    end) || -1
  end

  @doc "Returns the indices of points neighboring the given point"
  @spec neighbors(t(), non_neg_integer()) :: [non_neg_integer()]
  def neighbors(%__MODULE__{} = delaunay, point_index) do
    tris = triangles(delaunay)

    tris
    |> Enum.filter(fn tri -> point_index in tri end)
    |> Enum.flat_map(fn tri -> tri -- [point_index] end)
    |> Enum.uniq()
  end

  @doc "Generates SVG path data for all triangle edges"
  @spec render_triangles(t()) :: String.t()
  def render_triangles(%__MODULE__{} = delaunay) do
    tris = triangles(delaunay)
    pts = delaunay.points

    tris
    |> Enum.map(fn [i, j, k] ->
      {x0, y0} = Enum.at(pts, i)
      {x1, y1} = Enum.at(pts, j)
      {x2, y2} = Enum.at(pts, k)
      "M#{x0},#{y0}L#{x1},#{y1}L#{x2},#{y2}Z"
    end)
    |> Enum.join()
  end

  @doc "Generates SVG path data for the convex hull"
  @spec render_hull(t()) :: String.t()
  def render_hull(%__MODULE__{hull: hull, points: pts}) do
    case hull do
      [] -> ""
      [first | rest] ->
        {x0, y0} = Enum.at(pts, first)
        path = "M#{x0},#{y0}"

        rest_path =
          rest
          |> Enum.map(fn i ->
            {x, y} = Enum.at(pts, i)
            "L#{x},#{y}"
          end)
          |> Enum.join()

        path <> rest_path <> "Z"
    end
  end

  # Bowyer-Watson algorithm implementation
  defp compute_delaunay(points) do
    n = length(points)
    indexed_points = Enum.with_index(points)

    # Find bounding box
    {min_x, max_x} = points |> Enum.map(&elem(&1, 0)) |> Enum.min_max()
    {min_y, max_y} = points |> Enum.map(&elem(&1, 1)) |> Enum.min_max()

    dx = max_x - min_x
    dy = max_y - min_y
    delta = max(dx, dy) * 10

    # Create super-triangle that contains all points
    super_tri = [
      {min_x - delta, min_y - delta},
      {max_x + delta, min_y - delta},
      {(min_x + max_x) / 2, max_y + delta}
    ]

    # Initial triangulation is just the super-triangle
    # Triangles stored as list of {p0, p1, p2} tuples
    initial_triangles = [{0, 1, 2}]

    # Add points one by one
    all_points = super_tri ++ points

    {final_triangles, _} =
      Enum.reduce(indexed_points, {initial_triangles, all_points}, fn {{_px, _py}, orig_idx}, {tris, pts} ->
        point_idx = orig_idx + 3  # Offset for super-triangle vertices

        # Find triangles whose circumcircle contains the new point
        {bad_triangles, good_triangles} =
          Enum.split_with(tris, fn {i, j, k} ->
            {x0, y0} = Enum.at(pts, i)
            {x1, y1} = Enum.at(pts, j)
            {x2, y2} = Enum.at(pts, k)
            {px, py} = Enum.at(pts, point_idx)
            in_circumcircle?(px, py, x0, y0, x1, y1, x2, y2)
          end)

        # Find boundary of polygonal hole
        edges = bad_triangles
                |> Enum.flat_map(fn {i, j, k} -> [{i, j}, {j, k}, {k, i}] end)

        # Keep only edges that appear once (boundary edges)
        boundary_edges =
          edges
          |> Enum.reduce(%{}, fn {a, b}, acc ->
            edge = if a < b, do: {a, b}, else: {b, a}
            Map.update(acc, edge, 1, &(&1 + 1))
          end)
          |> Enum.filter(fn {_edge, count} -> count == 1 end)
          |> Enum.map(fn {edge, _} -> edge end)

        # Create new triangles from boundary edges to new point
        new_triangles =
          boundary_edges
          |> Enum.map(fn {a, b} -> {a, b, point_idx} end)

        {good_triangles ++ new_triangles, pts}
      end)

    # Remove triangles that share vertices with super-triangle
    real_triangles =
      final_triangles
      |> Enum.reject(fn {i, j, k} -> i < 3 or j < 3 or k < 3 end)
      |> Enum.map(fn {i, j, k} -> {i - 3, j - 3, k - 3} end)

    # Flatten triangles to list of indices
    flat_triangles =
      real_triangles
      |> Enum.flat_map(fn {i, j, k} -> [i, j, k] end)

    # Compute convex hull using gift wrapping
    hull = compute_hull(points)

    # Compute halfedges (simplified - just store empty for now)
    halfedges = []

    %__MODULE__{
      points: points,
      triangles: flat_triangles,
      halfedges: halfedges,
      hull: hull
    }
  end

  defp in_circumcircle?(px, py, x0, y0, x1, y1, x2, y2) do
    # Check if point (px, py) is inside circumcircle of triangle
    ax = x0 - px
    ay = y0 - py
    bx = x1 - px
    by = y1 - py
    cx = x2 - px
    cy = y2 - py

    det = (ax * ax + ay * ay) * (bx * cy - cx * by) -
          (bx * bx + by * by) * (ax * cy - cx * ay) +
          (cx * cx + cy * cy) * (ax * by - bx * ay)

    det > 0
  end

  defp point_in_triangle?(px, py, x0, y0, x1, y1, x2, y2) do
    # Barycentric coordinate method
    denom = (y1 - y2) * (x0 - x2) + (x2 - x1) * (y0 - y2)

    if abs(denom) < 1.0e-10 do
      false
    else
      a = ((y1 - y2) * (px - x2) + (x2 - x1) * (py - y2)) / denom
      b = ((y2 - y0) * (px - x2) + (x0 - x2) * (py - y2)) / denom
      c = 1 - a - b

      a >= 0 and a <= 1 and b >= 0 and b <= 1 and c >= 0 and c <= 1
    end
  end

  defp compute_hull(points) when length(points) < 3, do: Enum.to_list(0..(length(points) - 1))

  defp compute_hull(points) do
    indexed = Enum.with_index(points)

    # Find leftmost point
    {_, start_idx} = Enum.min_by(indexed, fn {{x, _y}, _i} -> x end)

    # Gift wrapping algorithm
    gift_wrap(points, start_idx, start_idx, [])
  end

  defp gift_wrap(points, current, start, hull) when length(hull) > length(points) do
    # Safety: prevent infinite loop
    Enum.reverse(hull)
  end

  defp gift_wrap(points, current, start, hull) do
    hull = [current | hull]
    n = length(points)

    # Find the most counter-clockwise point
    next =
      Enum.reduce(0..(n - 1), rem(current + 1, n), fn candidate, best ->
        if candidate == current do
          best
        else
          case ccw(points, current, best, candidate) do
            :left -> candidate
            :collinear ->
              # Pick farther point
              if distance_sq(points, current, candidate) > distance_sq(points, current, best) do
                candidate
              else
                best
              end
            :right -> best
          end
        end
      end)

    if next == start do
      Enum.reverse(hull)
    else
      gift_wrap(points, next, start, hull)
    end
  end

  defp ccw(points, a, b, c) do
    {ax, ay} = Enum.at(points, a)
    {bx, by} = Enum.at(points, b)
    {cx, cy} = Enum.at(points, c)

    cross = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)

    cond do
      cross > 1.0e-10 -> :left
      cross < -1.0e-10 -> :right
      true -> :collinear
    end
  end

  defp distance_sq(points, a, b) do
    {ax, ay} = Enum.at(points, a)
    {bx, by} = Enum.at(points, b)
    (bx - ax) * (bx - ax) + (by - ay) * (by - ay)
  end
end
