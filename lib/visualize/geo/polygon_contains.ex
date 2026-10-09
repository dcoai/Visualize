defmodule Visualize.Geo.PolygonContains do
  @moduledoc false
  # d3-geo's src/polygonContains.js (v3.1.1): whether a point lies inside a spherical
  # polygon, its rings given as lists of `{lon, lat}` in degrees without the closing
  # vertex. The clip asks it whether the clip edge's start — the south pole on the
  # antimeridian — is inside the polygon (spec/07 §2.2), which is how a ring that encloses
  # a pole, and so crosses no seam, still closes along the map's edge.
  #
  # The arithmetic is d3's, in radians. Where d3 would carry a NaN (a zero cross product, an
  # arcsine of a value rounded past ±1) every comparison it feeds is false, and the
  # crossing is skipped the same way here.

  import Bitwise

  alias Visualize.Geo.{Adder, Cartesian}

  @pi :math.pi()
  @half_pi @pi / 2
  @quarter_pi @pi / 4
  @tau 2 * @pi
  @epsilon 1.0e-6
  @epsilon2 1.0e-12
  @radians @pi / 180

  @doc false
  @spec contains?([[{number(), number()}]], {number(), number()}) :: boolean()
  def contains?(polygon, {lon, lat}) do
    # polygonContains.js:10–20
    lambda = longitude(lon * @radians)
    phi = lat * @radians

    phi =
      case :math.sin(phi) do
        s when s == 1 -> @half_pi + @epsilon
        s when s == -1 -> -@half_pi - @epsilon
        _ -> phi
      end

    normal = {:math.sin(lambda), -:math.cos(lambda), 0}
    acc = %{angle: 0, winding: 0, sum: 0.0, terms: []}

    %{angle: angle, winding: winding, sum: sum, terms: terms} =
      polygon
      |> Enum.reject(&(&1 == []))
      |> Enum.reduce(acc, &ring(&1, &2, lambda, phi, normal))

    # polygonContains.js:73. d3 sums the angles with its exact `Adder`, whose result only
    # decides anything near zero. A plain sum of n terms no larger than π is within
    # n · n · π · 2⁻⁵³ (< n² · 1e-15) of the exact one, so beyond that bound — and beyond
    # 1e-6, far above d3's threshold of 1e-12 — it has the exact sum's sign, and only inside
    # it are the terms summed exactly.
    n = length(terms)

    sum =
      if abs(sum) < max(1.0e-6, n * n * 1.0e-15),
        do: terms |> Enum.reduce(Adder.new(), &Adder.add(&2, &1)) |> Adder.value(),
        else: sum

    south_inside = angle < -@epsilon or (angle < @epsilon and sum < -@epsilon2)
    south_inside != ((winding &&& 1) == 1)
  end

  # polygonContains.js:22–60: one ring, edge by edge from its last vertex round to it,
  # each vertex's longitude and the sine and cosine of its half-latitude carried to the
  # next edge, as d3 carries them.
  defp ring(points, acc, lambda, phi, normal) do
    radians = Enum.map(points, fn {lon, lat} -> {lon * @radians, lat * @radians} end)
    edges(radians, vertex(List.last(radians)), acc, {lambda, phi, normal})
  end

  defp vertex({lambda, phi} = point) do
    half = phi / 2 + @quarter_pi
    {point, longitude(lambda), :math.sin(half), :math.cos(half)}
  end

  defp edges([], _previous, acc, _ctx), do: acc

  defp edges([point1 | rest], previous, acc, ctx) do
    current = vertex(point1)
    edges(rest, current, edge(previous, current, acc, ctx), ctx)
  end

  defp edge({point0, lambda0, sin0, cos0}, {point1, lambda1, sin1, cos1}, acc, ctx) do
    {lambda, phi, normal} = ctx
    %{angle: angle, sum: sum, terms: terms} = acc
    delta = lambda1 - lambda0
    sign = if delta >= 0, do: 1, else: -1
    abs_delta = sign * delta
    antimeridian = abs_delta > @pi
    k = sin0 * sin1
    term = :math.atan2(k * sign * :math.sin(abs_delta), cos0 * cos1 + k * :math.cos(abs_delta))
    angle = angle + if(antimeridian, do: delta + sign * @tau, else: delta)
    acc = %{acc | sum: sum + term, terms: [term | terms], angle: angle}

    # polygonContains.js:47–58: are the longitudes either side of the point's meridian,
    # and is the arc's latitude there below the point's?
    if xor3(antimeridian, lambda0 >= lambda, lambda1 >= lambda) do
      crossing(point0, point1, acc, phi, normal, antimeridian != delta >= 0)
    else
      acc
    end
  end

  defp crossing(point0, point1, acc, phi, normal, flipped) do
    arc =
      Cartesian.normalize(
        Cartesian.cross(Cartesian.cartesian(point0), Cartesian.cartesian(point1))
      )

    intersection = arc && Cartesian.normalize(Cartesian.cross(normal, arc))

    case intersection do
      {_, _, z} when z >= -1 and z <= 1 ->
        phi_arc = if(flipped, do: -1, else: 1) * :math.asin(z)
        {a0, a1, _} = arc

        if phi > phi_arc or (phi == phi_arc and (a0 != 0 or a1 != 0)) do
          %{acc | winding: acc.winding + if(flipped, do: 1, else: -1)}
        else
          acc
        end

      _ ->
        acc
    end
  end

  defp xor3(a, b, c), do: a != b != c

  # polygonContains.js:5–7
  defp longitude(lambda) when abs(lambda) <= @pi, do: lambda

  defp longitude(lambda) do
    sign = if lambda > 0, do: 1, else: -1
    sign * (fmod(abs(lambda) + @pi, @tau) - @pi)
  end

  defp fmod(a, b), do: a - b * Float.floor(a / b)
end
