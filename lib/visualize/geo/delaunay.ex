defmodule Visualize.Geo.Delaunay do
  @moduledoc """
  Delaunay triangulation for a set of points.

  Computes the Delaunay triangulation, which connects points such that
  no point is inside the circumcircle of any triangle. This is useful
  for interpolation, mesh generation, and computing Voronoi diagrams.

  The triangulation is built by incremental insertion (Bowyer–Watson) over ghost
  triangles that stand for the unbounded region beyond each hull edge, so no finite
  super-triangle can distort the hull. Every triangle is counter-clockwise, which is
  what makes the in-circle determinant's sign meaningful.

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

  @doc """
  Creates a new Delaunay triangulation from points.

  `triangles` holds three point indices per triangle, counter-clockwise; `halfedges[e]`
  is the index of the half-edge opposite half-edge `e` (`3t + k` runs from
  `triangles[3t + k]` to `triangles[3t + (k + 1) rem 3]`) or `-1` on the hull; `hull`
  lists the convex hull counter-clockwise from the leftmost point. Coincident points
  after the first are left out of the triangulation.
  """
  @spec new([point()]) :: t()
  def new(points) when is_list(points) do
    n = length(points)
    coords = points |> Enum.with_index() |> Map.new(fn {p, i} -> {i, p} end)

    triangles = if n < 3, do: [], else: triangulate(coords, n)
    real = Enum.reject(triangles, &ghost?/1)

    hull =
      cond do
        n < 3 -> Enum.to_list(0..(n - 1)//1)
        real == [] -> collinear_hull(coords, n)
        true -> hull_from_ghosts(triangles, coords)
      end

    flat = Enum.flat_map(real, fn {a, b, c} -> [a, b, c] end)

    %__MODULE__{points: points, triangles: flat, halfedges: halfedges(real), hull: hull}
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
      [] ->
        ""

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

  # ------------------------------------------------------------------
  # Construction. Triangles are `{a, b, c}` tuples of point indices, counter-clockwise.
  # A ghost `{v, u, :inf}` stands for the unbounded region beyond the hull edge u -> v
  # (the real triangle lies to the left of u -> v, the ghost to its right), so the cavity
  # a new point opens is found by one rule for real and ghost triangles alike.
  # ------------------------------------------------------------------

  defp ghost?({_, _, :inf}), do: true
  defp ghost?(_), do: false

  defp triangulate(coords, n) do
    # Seed with the first three distinct, non-collinear points; distinct points that
    # were collinear with the first two are inserted afterwards like any other.
    {seed, pending, _seen, rest} = find_seed(coords, n)

    case seed do
      nil ->
        []

      {a, b, c} ->
        {a, b, c} = if orient(coords, a, b, c) > 0, do: {a, b, c}, else: {a, c, b}
        initial = [{a, b, c}, {b, a, :inf}, {c, b, :inf}, {a, c, :inf}]
        seen = MapSet.new([coords[a], coords[b], coords[c]])

        {tris, _seen} =
          Enum.reduce(pending ++ rest, {initial, seen}, fn i, {tris, seen} ->
            if MapSet.member?(seen, coords[i]) do
              {tris, seen}
            else
              {insert(tris, coords, i), MapSet.put(seen, coords[i])}
            end
          end)

        tris
    end
  end

  defp find_seed(coords, n), do: find_seed(coords, Enum.to_list(0..(n - 1)//1), [], MapSet.new())

  defp find_seed(_coords, [], pending, seen), do: {nil, Enum.reverse(pending), seen, []}

  defp find_seed(coords, [i | rest], pending, seen) do
    cond do
      MapSet.member?(seen, coords[i]) ->
        find_seed(coords, rest, pending, seen)

      length(pending) < 2 ->
        find_seed(coords, rest, [i | pending], MapSet.put(seen, coords[i]))

      true ->
        # `pending` is newest-first; the seed pair is the first two distinct points.
        [a, b | others] = Enum.reverse(pending)

        if orient(coords, a, b, i) == 0 do
          find_seed(coords, rest, [i | pending], MapSet.put(seen, coords[i]))
        else
          {{a, b, i}, others, MapSet.put(seen, coords[i]), rest}
        end
    end
  end

  defp insert(tris, coords, p) do
    {bad, good} = Enum.split_with(tris, &in_cavity?(&1, coords, p))

    edges = Enum.flat_map(bad, fn {a, b, c} -> [{a, b}, {b, c}, {c, a}] end)
    edge_set = MapSet.new(edges)

    fresh =
      edges
      |> Enum.reject(fn {u, v} -> MapSet.member?(edge_set, {v, u}) end)
      |> Enum.map(fn
        {:inf, v} -> {v, p, :inf}
        {u, :inf} -> {p, u, :inf}
        {u, v} -> {u, v, p}
      end)

    good ++ fresh
  end

  # A real triangle is opened when p is strictly inside its circumcircle; a ghost when p
  # lies beyond its hull edge, or on that edge between the endpoints.
  defp in_cavity?({v, u, :inf}, coords, p) do
    case orient(coords, v, u, p) do
      o when o > 0 -> true
      o when o < 0 -> false
      _ -> between?(coords, u, v, p)
    end
  end

  defp in_cavity?({a, b, c}, coords, p), do: in_circle(coords, a, b, c, p) > 0

  # Twice the signed area of a -> b -> c: positive when counter-clockwise.
  defp orient(coords, a, b, c) do
    {ax, ay} = coords[a]
    {bx, by} = coords[b]
    {cx, cy} = coords[c]
    (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)
  end

  # The in-circle determinant, normalized by the triangle's orientation so it is
  # positive exactly when p is strictly inside the circumcircle, whatever the vertex order.
  defp in_circle(coords, a, b, c, p) do
    {ax, ay} = coords[a]
    {bx, by} = coords[b]
    {cx, cy} = coords[c]
    {px, py} = coords[p]

    adx = ax - px
    ady = ay - py
    bdx = bx - px
    bdy = by - py
    cdx = cx - px
    cdy = cy - py

    det =
      (adx * adx + ady * ady) * (bdx * cdy - cdx * bdy) -
        (bdx * bdx + bdy * bdy) * (adx * cdy - cdx * ady) +
        (cdx * cdx + cdy * cdy) * (adx * bdy - bdx * ady)

    o = orient(coords, a, b, c)

    cond do
      o > 0 -> det
      o < 0 -> -det
      true -> 0
    end
  end

  defp between?(coords, u, v, p) do
    {ux, uy} = coords[u]
    {vx, vy} = coords[v]
    {px, py} = coords[p]
    (px - ux) * (px - vx) + (py - uy) * (py - vy) < 0
  end

  # Ghost {v, u, :inf} is the hull edge u -> v; chaining them walks the hull
  # counter-clockwise. The walk starts at the leftmost point (lowest x, then lowest y).
  defp hull_from_ghosts(tris, coords) do
    next = tris |> Enum.filter(&ghost?/1) |> Map.new(fn {v, u, :inf} -> {u, v} end)
    start = next |> Map.keys() |> Enum.min_by(&coords[&1])
    walk_hull(next, start, next[start], [start])
  end

  defp walk_hull(_next, start, start, acc), do: Enum.reverse(acc)

  defp walk_hull(next, start, current, acc),
    do: walk_hull(next, start, next[current], [current | acc])

  # Every point on one line: the hull is its two extreme distinct points.
  defp collinear_hull(coords, n) do
    distinct = Enum.uniq_by(0..(n - 1)//1, &coords[&1])
    {lo, hi} = Enum.min_max_by(distinct, &coords[&1])
    Enum.uniq([lo, hi])
  end

  defp halfedges(real) do
    index =
      real
      |> Enum.with_index()
      |> Enum.flat_map(fn {{a, b, c}, t} ->
        [{{a, b}, 3 * t}, {{b, c}, 3 * t + 1}, {{c, a}, 3 * t + 2}]
      end)
      |> Map.new()

    Enum.flat_map(real, fn {a, b, c} ->
      Enum.map([{b, a}, {c, b}, {a, c}], &Map.get(index, &1, -1))
    end)
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
end
