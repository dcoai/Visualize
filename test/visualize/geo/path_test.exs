defmodule Visualize.Geo.PathTest do
  @moduledoc """
  `Visualize.Geo.Path` as spec/07 §2 says (#349): `path/2` is the same walk as `render/2`
  as a `Visualize.IR.Path`, and `Sphere` is the projection's outline, `Projection.sphere/1`.
  """
  use ExUnit.Case, async: true

  alias Visualize.Geo.{Path, Projection}
  alias Visualize.IR

  # Wound clockwise on the map, d3's spherical winding (spec/07 §2.2.1): the square itself.
  @square %{
    "type" => "Feature",
    "geometry" => %{
      "type" => "Polygon",
      "coordinates" => [[[-10, -10], [-10, 10], [10, 10], [10, -10], [-10, -10]]]
    }
  }

  defp equirectangular,
    do:
      Projection.new(:equirectangular) |> Projection.scale(100) |> Projection.translate(200, 100)

  # `render/2` rounds to three decimals and `to_string/1` to four: the two agree to that.
  defp agree(d, string) do
    letters = fn s -> Regex.replace(~r/-?\d+(\.\d+)?/, s, "#") end

    numbers = fn s ->
      Regex.scan(~r/-?\d+(?:\.\d+)?/, s) |> List.flatten() |> Enum.map(&elem(Float.parse(&1), 0))
    end

    assert letters.(d) == letters.(string)

    Enum.zip(numbers.(d), numbers.(string))
    |> Enum.each(fn {a, b} -> assert_in_delta a, b, 1.0e-3 end)
  end

  describe "path/2 (spec/07 §2.2)" do
    test "a polygon is a closed ring of the projected vertices, agreeing with render/2" do
      geo = Path.new(equirectangular())
      path = Path.path(geo, @square)

      assert [{:M, _, _}, {:L, _, _}, {:L, _, _}, {:L, _, _}, {:L, _, _}, :Z] = path.commands
      agree(Path.render(geo, @square), IR.Path.to_string(path))
    end

    test "a ring wound the other way is the rest of the sphere, closed along the map's edge" do
      geo = Path.new(equirectangular() |> Projection.precision(0))

      reversed =
        update_in(@square, ["geometry", "coordinates"], fn [ring] -> [Enum.reverse(ring)] end)

      # The whole map's edge, then the square as a hole.
      assert [{:M, _, _} | _] = commands = Path.path(geo, reversed).commands
      assert Enum.count(commands, &(&1 == :Z)) == 2
      [x0, y0, x1, y1] = Path.bounds(geo, reversed)
      assert {x0, x1} == {200 - :math.pi() * 100, 200 + :math.pi() * 100}
      assert {y0, y1} == {100 - :math.pi() / 2 * 100, 100 + :math.pi() / 2 * 100}
    end

    test "a line string is open, a point two arcs closed, a collection concatenated" do
      geo = Path.new(equirectangular())
      line = %{"type" => "LineString", "coordinates" => [[0, 0], [10, 0], [10, 10]]}
      assert [{:M, _, _}, {:L, _, _}, {:L, _, _}] = Path.path(geo, line).commands

      point = %{"type" => "Point", "coordinates" => [0, 0]}

      assert [{:M, _, _}, {:A, _, _, _, _, _, _, _}, {:A, _, _, _, _, _, _, _}, :Z] =
               Path.path(geo, point).commands

      collection = %{"type" => "GeometryCollection", "geometries" => [line, point]}
      assert length(Path.path(geo, collection).commands) == 7
      agree(Path.render(geo, collection), IR.Path.to_string(Path.path(geo, collection)))
    end

    test "a geometry with nothing to draw is the empty path, and so is an unknown type" do
      geo = Path.new(Projection.new(:orthographic) |> Projection.translate(100, 100))
      behind = %{"type" => "Polygon", "coordinates" => [[[170, 0], [175, 0], [175, 5], [170, 0]]]}
      assert Path.path(geo, behind) == IR.Path.new()
      assert Path.path(geo, %{"type" => "Blob"}) == IR.Path.new()
      assert Path.centroid(geo, behind) == nil
    end
  end

  describe "the Sphere (spec/07 §1.6, §2.1)" do
    test "through the orthographic it is the disc of the projection's scale, under any rotation" do
      proj =
        Projection.new(:orthographic)
        |> Projection.scale(80)
        |> Projection.translate(150, 120)
        |> Projection.rotate(40, -20, 0)

      points = Projection.sphere(proj)
      assert length(points) == 361 and hd(points) == List.last(points)

      for {x, y} <- points do
        assert_in_delta :math.sqrt((x - 150) * (x - 150) + (y - 120) * (y - 120)), 80, 1.0e-6
      end

      path = Path.path(Path.new(proj), %{"type" => "Sphere"})
      assert match?([{:M, _, _} | _], path.commands) and List.last(path.commands) == :Z
      agree(Path.render(Path.new(proj), %{"type" => "Sphere"}), IR.Path.to_string(path))
    end

    test "through a pseudo-cylindrical projection it is the map's edge, wider than the corner bounds" do
      proj =
        Projection.new(:natural_earth) |> Projection.scale(100) |> Projection.translate(350, 200)

      points = Projection.sphere(proj)
      xs = Enum.map(points, &elem(&1, 0))
      ys = Enum.map(points, &elem(&1, 1))
      [bx0, by0, bx1, by1] = Projection.bounds(proj)

      assert Enum.min(xs) < bx0 and Enum.max(xs) > bx1
      assert Enum.min(ys) < by0 and Enum.max(ys) > by1
      assert_in_delta Enum.min(xs) + Enum.max(xs), 700, 1.0e-6
    end

    test "the Mercators stop at latitude 85, and no projection means no sphere" do
      proj = Projection.new(:mercator) |> Projection.scale(100) |> Projection.translate(0, 0)
      ys = Enum.map(Projection.sphere(proj), &elem(&1, 1))
      {_x, top} = Projection.project(proj, 0, 85)
      assert_in_delta Enum.min(ys), top, 1.0e-6

      assert Path.path(Path.new(nil), %{"type" => "Sphere"}) == IR.Path.new()
      assert Path.render(Path.new(nil), %{"type" => "Sphere"}) == ""
    end
  end
end
