defmodule Visualize.Geo.ProjectionRotationTest do
  @moduledoc """
  The rotation round trip of spec/07 §1.4 (D-44): under any `{lambda, phi, gamma}`,
  `invert(project(p))` is as close to `p` as the type's own raw inverse allows.

  A rotation is an isometry of the sphere, so a correct inverse rotation adds nothing
  to the round-trip error: the rotated round trip's angular error is bounded by the
  unrotated round trip's error at the rotated point. That bound holds every type to the
  same standard whether its raw inverse is closed-form or iterative (spec/07 §1.2).
  Transverse Mercator's inverse is #9's and is excluded as in the projection golden.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Visualize.Geo.Projection
  alias Visualize.Geo.ProjectionTypes

  @types ProjectionTypes.all()
  @deg :math.pi() / 180

  defp gen_point, do: {float(min: -179.0, max: 179.0), float(min: -85.0, max: 85.0)}

  defp gen_angles,
    do:
      {float(min: -180.0, max: 180.0), float(min: -90.0, max: 90.0),
       float(min: -180.0, max: 180.0)}

  defp base(type), do: Projection.new(type) |> Projection.scale(100) |> Projection.translate(0, 0)

  # Great-circle angular distance in degrees.
  defp distance({lon1, lat1}, {lon2, lat2}) do
    {l1, p1, l2, p2} = {lon1 * @deg, lat1 * @deg, lon2 * @deg, lat2 * @deg}
    sin_dlat = :math.sin((p2 - p1) / 2)
    sin_dlon = :math.sin((l2 - l1) / 2)
    a = sin_dlat * sin_dlat + :math.cos(p1) * :math.cos(p2) * sin_dlon * sin_dlon
    2 * :math.asin(min(1, :math.sqrt(a))) / @deg
  end

  # The point in the rotated frame, read off an equirectangular projection at unit scale.
  defp rotated({lambda, phi, gamma}, {lon, lat}) do
    proj = Projection.new(:equirectangular) |> Projection.scale(1) |> Projection.translate(0, 0)
    {x, y} = Projection.project(Projection.rotate(proj, lambda, phi, gamma), lon, lat)
    {x / @deg, -y / @deg}
  end

  defp round_trip(proj, {lon, lat}) do
    case Projection.project(proj, lon, lat) do
      nil -> nil
      {x, y} -> Projection.invert(proj, x, y)
    end
  end

  defp assert_round_trip(type, {lambda, phi, gamma} = angles, point) do
    rotated_proj = Projection.rotate(base(type), lambda, phi, gamma)
    inner = rotated(angles, point)

    with {:ok, back} <- wrap(round_trip(rotated_proj, point)),
         {:ok, raw_back} <- wrap(round_trip(base(type), inner)) do
      raw_error = distance(raw_back, inner)

      assert distance(back, point) <= raw_error + 1.0e-6,
             "#{type} rotate #{inspect(angles)}: #{inspect(point)} -> #{inspect(back)} " <>
               "(raw inverse error at the rotated point #{raw_error})"

      :ok
    end
  end

  defp wrap(nil), do: :skipped
  defp wrap(value), do: {:ok, value}

  property "every projection type inverts its own projection under any rotation" do
    check all(
            type <- member_of(@types),
            angles <- gen_angles(),
            point <- gen_point(),
            max_runs: 400
          ) do
      assert_round_trip(type, angles, point)
    end
  end

  # The property's failure of #566: a rotation that carries its point onto a pole, where
  # collignon's inverse took asin(-1.0000000000000004). Random angles land within 10⁻⁸° of
  # a pole only on some seeds, so the cases are fixed here.
  test "a point the rotation carries onto a pole round-trips on every type" do
    for type <- @types,
        {angles, point} <- [
          {{0, 90, 0}, {0, 0}},
          {{0, -90, 0}, {0, 0}},
          {{30, 90, 45}, {-30, 0}},
          {{180, -90, 0}, {0, 0}}
        ] do
      assert_round_trip(type, angles, point)
    end
  end

  test "all three angles non-zero round-trip to floating-point noise on closed forms" do
    for type <- [
          :equirectangular,
          :mercator,
          :orthographic,
          :azimuthal_equal_area,
          :albers,
          :sinusoidal
        ],
        {angles, point} <- [{{30, 40, 25}, {10, 20}}, {{-100, -35, 80}, {-45, -10}}] do
      proj = Projection.rotate(base(type), elem(angles, 0), elem(angles, 1), elem(angles, 2))
      back = round_trip(proj, point)
      assert distance(back, point) < 1.0e-9, "#{type} #{inspect(angles)} -> #{inspect(back)}"
    end
  end

  test "the lambda convention is unchanged: rotate(lambda) makes meridian lambda central" do
    proj =
      Projection.rotate(
        Projection.new(:equirectangular) |> Projection.scale(1) |> Projection.translate(0, 0),
        30,
        0,
        0
      )

    assert {x, _} = Projection.project(proj, 30, 0)
    assert_in_delta x, 0, 1.0e-12
  end
end
