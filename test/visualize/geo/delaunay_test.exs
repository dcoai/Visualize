defmodule Visualize.Geo.DelaunayTest do
  @moduledoc """
  The Delaunay guarantees of spec/07 §3.1 (D-43): empty circumcircles, the triangle
  count `2n - 2 - h`, counter-clockwise triangles, a convex hull consistent with the
  triangulation and half-edges that pair up.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Visualize.Geo.{Delaunay, Voronoi}

  defp coords(d), do: List.to_tuple(d.points)

  defp orient({ax, ay}, {bx, by}, {cx, cy}), do: (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)

  defp circumcircle({ax, ay}, {bx, by}, {cx, cy}) do
    d = 2 * ((bx - ax) * (cy - ay) - (by - ay) * (cx - ax))
    b2 = (bx - ax) * (bx - ax) + (by - ay) * (by - ay)
    c2 = (cx - ax) * (cx - ax) + (cy - ay) * (cy - ay)
    ux = ax + ((cy - ay) * b2 - (by - ay) * c2) / d
    uy = ay + ((bx - ax) * c2 - (cx - ax) * b2) / d
    {ux, uy, :math.sqrt((ux - ax) * (ux - ax) + (uy - ay) * (uy - ay))}
  end

  defp assert_delaunay(d) do
    pts = coords(d)
    tris = Delaunay.triangles(d)

    for [i, j, k] <- tris do
      assert orient(elem(pts, i), elem(pts, j), elem(pts, k)) > 0,
             "triangle #{inspect([i, j, k])} is not CCW"

      {ux, uy, r} = circumcircle(elem(pts, i), elem(pts, j), elem(pts, k))

      for {{x, y}, p} <- Enum.with_index(d.points), p not in [i, j, k] do
        dist = :math.sqrt((x - ux) * (x - ux) + (y - uy) * (y - uy))

        assert dist >= r * (1 - 1.0e-9),
               "point #{p} lies inside the circumcircle of #{inspect([i, j, k])}"
      end
    end
  end

  defp assert_hull_convex(d) do
    pts = coords(d)
    hull = d.hull
    n = length(hull)

    for i <- 0..(n - 1)//1 do
      a = elem(pts, Enum.at(hull, i))
      b = elem(pts, Enum.at(hull, rem(i + 1, n)))
      c = elem(pts, Enum.at(hull, rem(i + 2, n)))
      assert orient(a, b, c) >= 0, "hull turns right at #{Enum.at(hull, rem(i + 1, n))}"
    end
  end

  defp assert_halfedges(d) do
    tris = d.triangles
    he = d.halfedges
    assert length(he) == length(tris)

    for {opposite, e} <- Enum.with_index(he), opposite != -1 do
      assert Enum.at(he, opposite) == e
      t = div(e, 3)
      from = Enum.at(tris, e)
      to = Enum.at(tris, 3 * t + rem(rem(e, 3) + 1, 3))
      ot = div(opposite, 3)
      assert Enum.at(tris, opposite) == to
      assert Enum.at(tris, 3 * ot + rem(rem(opposite, 3) + 1, 3)) == from
    end

    # Unpaired half-edges are exactly the hull edges.
    boundary =
      for {-1, e} <- Enum.with_index(he) do
        t = div(e, 3)
        {Enum.at(tris, e), Enum.at(tris, 3 * t + rem(rem(e, 3) + 1, 3))}
      end

    hull_edges = d.hull |> Enum.chunk_every(2, 1, [hd(d.hull)]) |> Enum.map(&List.to_tuple/1)
    assert Enum.sort(boundary) == Enum.sort(hull_edges)
  end

  property "random point sets are Delaunay with 2n - 2 - h triangles and a convex CCW hull" do
    check all(
            points <-
              uniq_list_of({float(min: 0.0, max: 100.0), float(min: 0.0, max: 100.0)},
                min_length: 3,
                max_length: 60
              )
          ) do
      d = Delaunay.new(points)
      n = length(points)
      [p0, p1 | rest] = points

      if Enum.all?(rest, &(orient(p0, p1, &1) == 0)) do
        assert d.triangles == []
        assert length(d.hull) == 2
      else
        # Euler: 2n - 2 - h holds with h counting collinear points on the hull boundary.
        assert length(d.triangles) == 3 * (2 * n - 2 - length(d.hull))
        assert_delaunay(d)
        assert_hull_convex(d)
        assert_halfedges(d)
        assert d.triangles |> Enum.uniq() |> Enum.sort() == Enum.to_list(0..(n - 1))
      end
    end
  end

  test "the spec's forty random points give 2n - 2 - h triangles, all Delaunay" do
    :rand.seed(:exsss, 16)
    points = for _ <- 1..40, do: {:rand.uniform() * 100, :rand.uniform() * 100}
    d = Delaunay.new(points)
    assert length(Delaunay.triangles(d)) == 2 * 40 - 2 - length(d.hull)
    assert_delaunay(d)
  end

  test "a square gives two triangles and a four-point hull from the leftmost point" do
    d = Delaunay.new([{0, 0}, {10, 0}, {10, 10}, {0, 10}])
    assert length(Delaunay.triangles(d)) == 2
    assert d.hull == [0, 1, 2, 3]
    assert Enum.count(d.halfedges, &(&1 == -1)) == 4
    assert_delaunay(d)
  end

  test "the moduledoc points: both inner points sit on hull edges, so the hull has five" do
    d = Delaunay.new([{0, 0}, {100, 0}, {50, 100}, {25, 50}, {75, 50}])
    assert d.hull == [0, 1, 4, 2, 3]
    assert length(Delaunay.triangles(d)) == 2 * 5 - 2 - 5
    assert [0, 2, 4] -- Delaunay.neighbors(d, 3) == []
    assert Delaunay.find(d, {30, 30}) >= 0
    assert Delaunay.find(d, {90, 90}) == -1
    assert_delaunay(d)
    assert_halfedges(d)
  end

  test "fewer than three points: no triangles, every index on the hull, empty gives empty" do
    assert %{triangles: [], halfedges: [], hull: []} = Delaunay.new([])
    assert %{triangles: [], hull: [0]} = Delaunay.new([{1, 1}])
    assert %{triangles: [], hull: [0, 1]} = Delaunay.new([{1, 1}, {2, 2}])
    assert Delaunay.render_hull(Delaunay.new([])) == ""
  end

  test "collinear points give no triangles and a two-point hull" do
    d = Delaunay.new([{0, 0}, {5, 5}, {10, 10}, {2, 2}])
    assert d.triangles == []
    assert d.hull == [0, 2]
  end

  test "points collinear with the first two are still inserted once a triangle exists" do
    d = Delaunay.new([{0, 0}, {10, 0}, {20, 0}, {5, 0}, {10, 10}, {-5, 0}, {30, 0}])
    assert d.triangles |> Enum.uniq() |> Enum.sort() == Enum.to_list(0..6)
    assert length(Delaunay.triangles(d)) == 2 * 7 - 2 - length(d.hull)
    assert_delaunay(d)
    assert_hull_convex(d)
    assert_halfedges(d)
  end

  test "coincident points are left out after the first" do
    d = Delaunay.new([{0, 0}, {0, 0}, {10, 0}, {0, 10}, {10, 0}])
    assert length(Delaunay.triangles(d)) == 1
    assert d.triangles |> Enum.uniq() |> Enum.sort() == [0, 2, 3]
    assert d.hull == [0, 2, 3]
  end

  test "a point on an existing edge splits both triangles without a degenerate one" do
    d = Delaunay.new([{0, 0}, {10, 0}, {10, 10}, {0, 10}, {5, 5}])
    assert length(Delaunay.triangles(d)) == 4
    assert_delaunay(d)
  end

  test "the Voronoi diagram follows: one circumcentre per triangle, cells for every site" do
    :rand.seed(:exsss, 7)
    points = for _ <- 1..25, do: {:rand.uniform() * 100, :rand.uniform() * 100}
    v = Voronoi.new(points) |> Voronoi.bounds([0, 0, 100, 100])
    assert length(v.circumcenters) == length(Delaunay.triangles(v.delaunay))
    assert Enum.all?(Voronoi.cells(v), &(&1 != []))
    assert length(Voronoi.edges(v)) == Enum.count(v.delaunay.halfedges, &(&1 != -1)) |> div(2)
  end
end
