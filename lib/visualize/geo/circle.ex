defmodule Visualize.Geo.Circle do
  @moduledoc """
  A circle on the sphere as a GeoJSON `Polygon`: d3-geo's `geoCircle` (spec/07 §2.5, D-131).

  `polygon/1` returns the small circle of angular `radius` degrees about `center`, as
  `%{"type" => "Polygon", "coordinates" => [ring]}`, one ring of `[lon, lat]` positions in
  degrees. The ring is d3-geo 3.1.1's, point for point and in d3's order and winding, so
  `Visualize.Geo.Path`, which clips on the sphere as d3 does (spec/07 §2.2.1, D-127), fills
  the cap of `radius` about `center` under every projection — a hemisphere at 90°.

      iex> %{"type" => "Polygon", "coordinates" => [ring]} =
      ...>   Visualize.Geo.Circle.polygon(center: [0, 0], radius: 10, precision: 90)
      iex> length(ring)
      5

  The ring starts at the circle's angle `radius` about its axis, not at its southernmost
  point, and runs every `precision` degrees back round to it, as d3's does.

  Options:

    * `:center` — `[lon, lat]` in degrees (default `[0, 0]`)
    * `:radius` — the angular radius in degrees (default `90`)
    * `:precision` — the step between the ring's points, in degrees of the circle's own
      angle (default `6`); `0` gives an empty ring, as in d3
  """

  import Visualize.Geo.Math, only: [asin: 1]

  @pi :math.pi()
  @tau 2 * @pi
  @radians @pi / 180
  @degrees 180 / @pi

  @type position :: [float()]
  @type t :: %{required(String.t()) => String.t() | [[position()]]}

  @doc """
  The circle of `radius` degrees about `center`, every `precision` degrees, as a GeoJSON
  `Polygon` (spec/07 §2.5).
  """
  @spec polygon(keyword()) :: t()
  def polygon(opts \\ []) do
    [center_lon, center_lat] = Keyword.get(opts, :center, [0, 0])
    radius = Keyword.get(opts, :radius, 90)
    precision = Keyword.get(opts, :precision, 6)

    # src/circle.js:47–51: the rotation that takes the frame centred on `center` back.
    rotation = rotation(-center_lon * @radians, -center_lat * @radians)

    ring =
      for {lambda, phi} <- circle_stream(radius * @radians, precision * @radians) do
        {lambda, phi} = invert(rotation, lambda, phi)
        [lambda * @degrees, phi * @degrees]
      end

    %{"type" => "Polygon", "coordinates" => [ring]}
  end

  # src/circle.js:7–24, `circleStream(stream, radius, delta, 1)` with no `t0`: the whole
  # circle about the frame's origin, from angle `radius + τ` down by `delta`. A delta of 0
  # draws nothing (src/circle.js:8); a negative one would never end, as in d3.
  defp circle_stream(_radius, delta) when delta == 0, do: []

  defp circle_stream(radius, delta) when delta > 0 do
    cos_radius = :math.cos(radius)
    sin_radius = :math.sin(radius)
    walk(radius + @tau, radius - delta / 2, delta, cos_radius, sin_radius, [])
  end

  defp walk(t, t1, step, cos_radius, sin_radius, acc) when t > t1 do
    point = spherical({cos_radius, -sin_radius * :math.cos(t), -sin_radius * :math.sin(t)})
    walk(t - step, t1, step, cos_radius, sin_radius, [point | acc])
  end

  defp walk(_t, _t1, _step, _cos_radius, _sin_radius, acc), do: Enum.reverse(acc)

  # -- src/rotation.js:11–16, `rotateRadians(deltaLambda, deltaPhi, 0)`, its inverse --

  # `deltaLambda %= tau` as JavaScript's `%` takes it (the sign of the dividend), and the
  # rotation chosen as d3 chooses it: λ alone, φ alone, both composed, or the identity.
  defp rotation(delta_lambda, delta_phi) do
    delta_lambda = :math.fmod(delta_lambda, @tau)

    case {delta_lambda == 0, delta_phi == 0} do
      {false, false} -> {:compose, delta_lambda, phi_trig(delta_phi)}
      {false, true} -> {:lambda, delta_lambda}
      {true, false} -> {:phi, phi_trig(delta_phi)}
      {true, true} -> :identity
    end
  end

  defp phi_trig(delta_phi), do: {:math.cos(delta_phi), :math.sin(delta_phi)}

  # src/compose.js:8–10: a composed rotation's inverse undoes `rotationPhiGamma` first.
  defp invert({:compose, delta_lambda, trig}, lambda, phi) do
    {lambda, phi} = invert_phi(trig, lambda, phi)
    shift(lambda + -delta_lambda, phi)
  end

  # rotation.js:30–31: `rotationLambda(δλ).invert` is `forwardRotationLambda(-δλ)`.
  defp invert({:lambda, delta_lambda}, lambda, phi), do: shift(lambda + -delta_lambda, phi)
  defp invert({:phi, trig}, lambda, phi), do: invert_phi(trig, lambda, phi)
  # rotation.js:4–9: the identity normalises the longitude, and is its own inverse.
  defp invert(:identity, lambda, phi), do: shift(lambda, phi)

  # rotation.js:18–24: beyond ±π, less the nearest whole turn, rounded as `Math.round`.
  defp shift(lambda, phi) when abs(lambda) > @pi,
    do: {lambda - Float.floor(lambda / @tau + 0.5) * @tau, phi}

  defp shift(lambda, phi), do: {lambda, phi}

  # rotation.js:50–60, `rotationPhiGamma(δφ, 0).invert`, with cos δγ = 1 and sin δγ = 0 kept
  # in the arithmetic as d3 keeps them, so a signed zero comes out as it does in d3.
  defp invert_phi({cos_delta_phi, sin_delta_phi}, lambda, phi) do
    cos_phi = :math.cos(phi)
    x = :math.cos(lambda) * cos_phi
    y = :math.sin(lambda) * cos_phi
    z = :math.sin(phi)
    k = z * 1.0 - y * 0.0

    {:math.atan2(y * 1.0 + z * 0.0, x * cos_delta_phi + k * sin_delta_phi),
     asin(k * cos_delta_phi - x * sin_delta_phi)}
  end

  # cartesian.js:3–5.
  defp spherical({x, y, z}), do: {:math.atan2(y, x), asin(z)}
end
