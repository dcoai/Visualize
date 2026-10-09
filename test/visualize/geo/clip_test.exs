defmodule Visualize.Geo.ClipTest do
  @moduledoc """
  The antimeridian clip of spec/07 §2.2 (#509, D-127): `Visualize.Geo.Path` cuts lines and
  rings where they cross ±180° in the rotated frame and closes polygons along the seam, as
  d3-geo's `clipAntimeridian` does.

  The conformance cases are d3-geo's own output, recorded in
  `test/support/geo/clip_golden.jsonl` by the one-off oracle beside it
  (`clip_golden.mjs`, whose header names the command). Each case is projected here at
  precision 0 — d3's `precision(0)`, no resampling and no seam samples — and every subpath
  is compared with d3's point by point within a tolerance. d3 drops a ring's closing vertex
  where the clip leaves the ring whole and the library keeps it (`Z` closes the ring
  either way), so a ring is compared without a closing vertex that repeats its first.
  """
  use ExUnit.Case, async: true

  alias Visualize.Geo.{Path, Projection}

  @golden "test/support/geo/clip_golden.jsonl"
  @tolerance 1.0e-6

  @cases @golden
         |> File.stream!()
         |> Enum.reject(&String.starts_with?(&1, "#"))
         |> Enum.map(&Jason.decode!/1)

  defp projection(%{
         "type" => type,
         "scale" => scale,
         "translate" => [tx, ty],
         "rotate" => [l, p, g]
       }) do
    String.to_existing_atom(type)
    |> Projection.new()
    |> Projection.scale(scale)
    |> Projection.translate(tx, ty)
    |> Projection.rotate(l, p, g)
    |> Projection.precision(0)
  end

  # The path's subpaths as `{kind, points}`: a `Z` makes the subpath a ring.
  defp subpaths(%Visualize.IR.Path{commands: commands}) do
    commands
    |> Enum.reduce([], fn
      {:M, x, y}, acc -> [{"line", [{x, y}]} | acc]
      {:L, x, y}, [{kind, points} | acc] -> [{kind, [{x, y} | points]} | acc]
      :Z, [{_, points} | acc] -> [{"ring", points} | acc]
    end)
    |> Enum.map(fn {kind, points} -> {kind, Enum.reverse(points)} end)
    |> Enum.reverse()
  end

  defp d3_subpaths(output) do
    for %{"kind" => kind, "points" => points} <- output,
        do: {kind, Enum.map(points, fn [x, y] -> {x, y} end)}
  end

  defp unclosed({"ring", [first | _] = points}) do
    if close?(first, List.last(points)) and length(points) > 1,
      do: {"ring", Enum.drop(points, -1)},
      else: {"ring", points}
  end

  defp unclosed(line), do: line

  defp close?({x0, y0}, {x1, y1}), do: abs(x0 - x1) < @tolerance and abs(y0 - y1) < @tolerance

  describe "conformance with d3-geo's clipAntimeridian" do
    for %{"name" => name} = golden <- @cases do
      @golden_case golden
      test name do
        %{"projection" => proj, "geometry" => geometry, "output" => output} = @golden_case
        ours = Path.new(projection(proj)) |> Path.path(geometry) |> subpaths()
        theirs = d3_subpaths(output)

        assert Enum.map(ours, &elem(&1, 0)) == Enum.map(theirs, &elem(&1, 0)),
               "subpath kinds: #{inspect(Enum.map(ours, &elem(&1, 0)))}"

        for {{ours, theirs}, i} <- Enum.with_index(Enum.zip(ours, theirs)) do
          {_, a} = unclosed(ours)
          {_, b} = unclosed(theirs)
          assert length(a) == length(b), "subpath #{i}: #{length(a)} points, d3 #{length(b)}"

          for {{p, q}, j} <- Enum.with_index(Enum.zip(a, b)) do
            assert close?(p, q), "subpath #{i}, point #{j}: #{inspect(p)}, d3 #{inspect(q)}"
          end
        end
      end
    end
  end

  defp equirectangular(lambda) do
    Projection.new(:equirectangular)
    |> Projection.scale(100)
    |> Projection.translate(480, 250)
    |> Projection.rotate(lambda, 0, 0)
  end

  defp ring(lat, lons), do: Enum.map(lons ++ [hd(lons)], &[&1, lat])

  describe "lines" do
    test "a line across the seam is two subpaths, each ending on the map's edge" do
      line = %{"type" => "LineString", "coordinates" => [[170, 10], [-170, 20]]}

      assert [{"line", [_, {x0, _}]}, {"line", [{x1, _}, _]}] =
               subpaths(Path.path(Path.new(equirectangular(0)), line))

      assert_in_delta x0, 480 + :math.pi() * 100, 1.0e-9
      assert_in_delta x1, 480 - :math.pi() * 100, 1.0e-9
      assert Path.render(Path.new(equirectangular(0)), line) =~ ~r/^M[^M]+M[^M]+$/
    end

    test "a rotation moves the seam: the same line is whole once the seam is elsewhere" do
      line = %{"type" => "LineString", "coordinates" => [[170, 10], [-170, 20]]}
      assert [{"line", [_, _]}] = subpaths(Path.path(Path.new(equirectangular(180)), line))
    end
  end

  describe "polygons" do
    test "a ring around a pole is closed along the seam and the pole, filling the cap" do
      cap = %{"type" => "Polygon", "coordinates" => [ring(-70, [-135, -45, 45, 135])]}
      proj = equirectangular(0) |> Projection.precision(0)
      assert [{"ring", points}] = subpaths(Path.path(Path.new(proj), cap))
      {xs, ys} = Enum.unzip(points)
      # The whole width of the map, down to the south pole's line.
      assert_in_delta Enum.min(xs), 480 - :math.pi() * 100, 1.0e-6
      assert_in_delta Enum.max(xs), 480 + :math.pi() * 100, 1.0e-6
      assert_in_delta Enum.max(ys), 250 + :math.pi() / 2 * 100, 1.0e-6
    end

    test "the same ring wound the other way is everything but the cap" do
      rest = %{"type" => "Polygon", "coordinates" => [ring(-70, [135, 45, -45, -135])]}
      proj = equirectangular(0) |> Projection.precision(0)
      subpaths = subpaths(Path.path(Path.new(proj), rest))
      ys = for {_, points} <- subpaths, {_, y} <- points, do: y
      # It reaches the north pole's line: the map's top.
      assert_in_delta Enum.min(ys), 250 - :math.pi() / 2 * 100, 1.0e-6
    end

    test "a polygon clear of the seam is drawn from its own vertices, the closing one kept" do
      square = %{
        "type" => "Polygon",
        "coordinates" => [[[0, 0], [0, 10], [10, 10], [10, 0], [0, 0]]]
      }

      geo = Path.new(equirectangular(0))
      assert [{"ring", points}] = subpaths(Path.path(geo, square))
      assert length(points) == 5
      assert hd(points) == List.last(points)
    end

    test "every projection without a clip angle places the clip's poles and seam" do
      cap = %{"type" => "Polygon", "coordinates" => [ring(-70, [-135, -45, 45, 135])]}
      across = %{"type" => "Polygon", "coordinates" => [ring(60, [170, -170, -160, 160])]}

      for type <- Visualize.Geo.ProjectionGoldenTest.types(),
          Projection.new(type).clip_angle == nil,
          rotate <- [0, 90, -135] do
        geo = Path.new(Projection.new(type) |> Projection.rotate(rotate, 0, 0))

        for shape <- [cap, across, %{"type" => "Sphere"}] do
          assert [{_, [_, _, _ | _]} | _] = subpaths(Path.path(geo, shape)),
                 "#{type} at #{rotate}: #{shape["type"]}"
        end
      end
    end

    test "the seam is sampled every degree unless the precision is 0" do
      cross = %{
        "type" => "Polygon",
        "coordinates" => [[[170, 10], [170, 40], [-170, 40], [-170, 10], [170, 10]]]
      }

      proj =
        Projection.new(:natural_earth) |> Projection.scale(100) |> Projection.translate(480, 250)

      count = fn proj ->
        proj |> Path.new() |> Path.path(cross) |> subpaths() |> Enum.map(&length(elem(&1, 1)))
      end

      # Two pieces, each closed along its side of the seam from about 10.15° to 40.43° (the
      # great circles' crossings): 30.28°, sampled at 31 equal steps, 30 points inside.
      assert [a, b] = count.(proj)
      assert [a0, b0] = count.(Projection.precision(proj, 0))
      assert {a - a0, b - b0} == {30, 30}
    end
  end
end
