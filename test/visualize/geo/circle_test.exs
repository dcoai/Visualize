defmodule Visualize.Geo.CircleTest do
  @moduledoc """
  `Visualize.Geo.Circle` (spec/07 §2.5, #525, D-131): d3-geo's `geoCircle`.

  The conformance cases are d3-geo 3.1.1's own rings, recorded in
  `test/support/geo/circle_golden.jsonl` by the one-off oracle beside it
  (`circle_golden.mjs`, whose header names the command), and every point of every ring is
  held to d3's within `1e-9` degrees. The rest of the module holds what the port is for: a
  circle drawn through `Visualize.Geo.Path`, which clips on the sphere as d3 does
  (spec/07 §2.2.1, D-127), fills the cap about its centre and nothing else.
  """
  use ExUnit.Case, async: true

  alias Visualize.Geo.{Circle, Path, Projection}

  doctest Visualize.Geo.Circle

  @golden "test/support/geo/circle_golden.jsonl"
  @tolerance 1.0e-9
  @radians :math.pi() / 180

  @cases @golden
         |> File.stream!()
         |> Enum.reject(&String.starts_with?(&1, "#"))
         |> Enum.map(&Jason.decode!/1)

  describe "conformance with d3-geo's geoCircle" do
    test "the golden covers every centre, radius and precision it was written for" do
      assert length(@cases) == 10 * 8 * 4 + 3 * 3 * 2
    end

    for %{"center" => center, "radius" => radius, "precision" => precision} = golden <- @cases do
      @golden_case golden
      test "center #{inspect(center)}, radius #{radius}, precision #{precision}" do
        %{"center" => center, "radius" => radius, "precision" => precision, "ring" => ring} =
          @golden_case

        assert %{"type" => "Polygon", "coordinates" => [ours]} =
                 Circle.polygon(center: center, radius: radius, precision: precision)

        assert Enum.count(ours) == Enum.count(ring)

        for {{[a, b], [c, d]}, i} <- Enum.with_index(Enum.zip(ours, ring)) do
          assert abs(a - c) <= @tolerance and abs(b - d) <= @tolerance,
                 "point #{i}: #{inspect([a, b])}, d3 #{inspect([c, d])}"
        end
      end
    end
  end

  describe "polygon/1" do
    test "the defaults are a 90° circle about [0, 0] every 6°, closed by its first point" do
      assert Circle.polygon() == Circle.polygon(center: [0, 0], radius: 90, precision: 6)
      %{"coordinates" => [ring]} = Circle.polygon()
      assert length(ring) == 61
      # The ring starts at the angle `radius`, here the south pole, whose longitude is
      # whatever the arithmetic leaves: the same point, not the same numbers.
      assert distance(hd(ring), List.last(ring)) < 1.0e-6
    end

    test "every point is the radius away from the centre" do
      center = [-75.5, -23.44]
      %{"coordinates" => [ring]} = Circle.polygon(center: center, radius: 37, precision: 5)

      for point <- ring, do: assert_in_delta(distance(center, point), 37, 1.0e-9)
    end

    test "a precision of 0 is an empty ring, as d3's" do
      assert Circle.polygon(precision: 0) == %{"type" => "Polygon", "coordinates" => [[]]}
    end
  end

  describe "drawn through Visualize.Geo.Path" do
    # A projection across the antimeridian of its rotated frame, so the clip must cut the
    # circle at the seam and close it along the map's edge.
    defp natural_earth(lambda) do
      Projection.new(:natural_earth)
      |> Projection.scale(150)
      |> Projection.translate(480, 250)
      |> Projection.rotate(lambda, 0)
    end

    test "a 90° circle under a rotated Natural Earth fills its hemisphere and nothing else" do
      # The cap crosses the rotated frame's seam (at lon 37 − 180 = −143).
      center = [-150, 23]
      proj = natural_earth(37)
      rings = rings(Path.path(Path.new(proj), Circle.polygon(center: center)))
      assert rings != []

      # Every point of a 5° grid well clear of the circle and of the seam: inside the
      # drawn rings (even–odd) exactly when it is within 90° of the centre. A chord drawn
      # the long way round would put the far side's points inside.
      for lon <- -175..175//5,
          lat <- -85..85//5,
          abs(distance(center, [lon, lat]) - 90) > 3,
          abs(seam_distance(proj, lon, lat)) > 3 do
        {x, y} = Projection.project(proj, lon, lat)
        inside = rings |> Enum.count(&Visualize.Polygon.contains?(&1, {x, y})) |> rem(2) == 1

        assert inside == distance(center, [lon, lat]) < 90,
               "[#{lon}, #{lat}]: drawn #{if inside, do: "inside", else: "outside"}"
      end
    end

    test "under an equal-area projection the circle's drawn area is the hemisphere's" do
      proj =
        Projection.new(:equal_earth)
        |> Projection.scale(150)
        |> Projection.translate(480, 250)
        |> Projection.rotate(-61, 0)

      rings = rings(Path.path(Path.new(proj), Circle.polygon(center: [100, -40])))
      drawn = rings |> Enum.map(&abs(Visualize.Polygon.area(&1))) |> Enum.sum()
      sphere = abs(Visualize.Polygon.area(Projection.sphere(proj)))
      assert_in_delta drawn / sphere, 0.5, 0.005
    end

    test "a small circle is the small cap and a large one the rest of the sphere" do
      proj = natural_earth(0)
      small = rings(Path.path(Path.new(proj), Circle.polygon(center: [20, 10], radius: 20)))
      large = rings(Path.path(Path.new(proj), Circle.polygon(center: [20, 10], radius: 160)))
      {x, y} = Projection.project(proj, 20, 10)
      {ax, ay} = Projection.project(proj, -160, -10)

      assert Enum.any?(small, &Visualize.Polygon.contains?(&1, {x, y}))
      refute Enum.any?(small, &Visualize.Polygon.contains?(&1, {ax, ay}))
      assert large |> Enum.count(&Visualize.Polygon.contains?(&1, {x, y})) |> rem(2) == 1
    end
  end

  # The great-circle distance between two `[lon, lat]` positions, in degrees.
  defp distance([lon0, lat0], [lon1, lat1]) do
    {p0, p1} = {lat0 * @radians, lat1 * @radians}
    dl = (lon1 - lon0) * @radians
    cos = :math.sin(p0) * :math.sin(p1) + :math.cos(p0) * :math.cos(p1) * :math.cos(dl)
    :math.acos(max(-1.0, min(1.0, cos))) / @radians
  end

  # How far a point's longitude in the rotated frame is from ±180°, in degrees.
  defp seam_distance(proj, lon, lat) do
    {rotated, _} = Projection.rotated(proj, lon, lat)
    180 - abs(rotated)
  end

  # The path's closed rings, each a list of `{x, y}`.
  defp rings(%Visualize.IR.Path{commands: commands}) do
    commands
    |> Enum.reduce([], fn
      {:M, x, y}, acc -> [[{x, y}] | acc]
      {:L, x, y}, [points | acc] -> [[{x, y} | points] | acc]
      :Z, acc -> acc
    end)
    |> Enum.map(&Enum.reverse/1)
    |> Enum.reverse()
  end
end
