defmodule Visualize.Geo.ProjectionEdgeTest do
  @moduledoc """
  No point at the edge of a projection's domain raises (spec/07 §1.2, D-149, #566).

  Rounding carries a quantity that is exactly ±1 at a pole or the antimeridian a few ulps
  past it: `:collignon`'s inverse of its own south pole took `asin(-1.0000000000000004)`.
  Every type is driven forward and back at both poles and the antimeridian, at the
  latitudes and longitudes one ulp to either side, and at each projected point moved one
  ulp in `x` and in `y` before it is inverted.
  """
  use ExUnit.Case, async: true

  alias Visualize.Geo.Projection
  alias Visualize.Geo.ProjectionGoldenTest, as: Golden

  Code.require_file("test/visualize/geo/projection_golden_test.exs")

  @types Golden.types()

  # The next float toward +∞ (`dir > 0`) or −∞, from the float's bits: Erlang has no
  # `nextafter`. A positive float's successor is its bit pattern plus one, a negative
  # float's minus one.
  defp ulp(x, dir) when x == 0, do: if(dir > 0, do: 5.0e-324, else: -5.0e-324)

  defp ulp(x, dir) do
    <<bits::64>> = <<x * 1.0::float>>
    step = if x > 0 == dir > 0, do: 1, else: -1
    <<next::float>> = <<bits + step::64>>
    next
  end

  defp nudged(v), do: [v * 1.0, ulp(v, 1), ulp(v, -1)]

  defp unit(type), do: Projection.new(type) |> Projection.scale(1) |> Projection.translate(0, 0)

  test "the ulp step is one float either side" do
    assert ulp(1.0, 1) == 1.0000000000000002
    assert ulp(1.0, -1) == 0.9999999999999999
    assert ulp(-90.0, -1) == -90.00000000000001
    assert ulp(-90.0, 1) == -89.99999999999999
    assert ulp(0.0, 1) > 0
  end

  for type <- @types do
    test "#{type} projects and inverts the poles and the antimeridian, ±1 ulp" do
      proj = unit(unquote(type))
      lats = Enum.flat_map([-90, 90, 0], &nudged/1)
      lons = Enum.flat_map([-180, 180, 0], &nudged/1)

      for lon <- lons, lat <- lats, {x, y} <- [Projection.project(proj, lon, lat)] do
        assert is_float(x) and is_float(y), "#{unquote(type)} #{lon} #{lat} -> #{inspect({x, y})}"

        for xx <- nudged(x), yy <- nudged(y) do
          case Projection.invert(proj, xx, yy) do
            nil -> :ok
            {ilon, ilat} -> assert is_number(ilon) and is_number(ilat)
          end
        end
      end
    end
  end

  test "collignon inverts its own south pole (#566)" do
    proj = unit(:collignon)
    {x, y} = Projection.project(proj, 0, -90)
    # α = 1.4142135623730951 and α² = 2.0000000000000004 here, so asin(1 − α²) was
    # asin(-1.0000000000000004).
    assert {x, y} == {0.0, 0.7341744237254846}
    assert {lon, lat} = Projection.invert(proj, x, y)
    assert lon == 0
    assert lat == -90.0
  end

  test "mollweide places a latitude a ulp inside a pole, where its Newton step's derivative is zero" do
    assert {x, y} = Projection.project(unit(:mollweide), 180, -89.99999999999999)
    assert_in_delta x, 0, 1.0e-9
    assert_in_delta y, :math.sqrt(2), 1.0e-9
  end

  test "loximuthal inverts its own poles to the meridian x = 0 puts them on" do
    proj = unit(:loximuthal)

    for lat <- [-90, 90] do
      {x, y} = Projection.project(proj, 120, lat)
      assert {lon, ^lat} = round_lat(Projection.invert(proj, x, y))
      assert lon == 0
    end
  end

  defp round_lat({lon, lat}), do: {lon, round(lat)}

  test "a point outside the domain is clamped as d3 clamps it, not raised" do
    assert {_, lat} = Projection.invert(unit(:mollweide), 0, -2)
    assert_in_delta lat, 90, 1.0e-9
    assert {_, _} = Projection.invert(unit(:azimuthal_equal_area), 3, 0)
  end

  test "no Geo module takes :math.asin or :math.acos outside Visualize.Geo.Math (D-149)" do
    offenders =
      for path <- Path.wildcard("lib/visualize/geo/**/*.ex") ++ ["lib/visualize/geo.ex"],
          File.exists?(path),
          path != "lib/visualize/geo/math.ex",
          {line, n} <- Enum.with_index(File.stream!(path), 1),
          line =~ ~r/:math\.a(sin|cos)\(/,
          do: "#{path}:#{n}"

    assert offenders == []
  end
end
