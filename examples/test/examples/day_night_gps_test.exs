defmodule Examples.DayNightGpsTest do
  @moduledoc """
  *Day, night and GPS* (#526, spec/14 §12.6): the Sun, the constellation and the clock
  are right, and the night and the tracks keep their place on the land as the map turns.
  """
  use ExUnit.Case, async: true

  alias Examples.Charts.{Design, DayNightGps}
  alias Visualize.Geo.Path

  @sidereal_day 86_164

  defp angle_between({lon0, lat0}, {lon1, lat1}) do
    r = :math.pi() / 180
    {p0, p1} = {lat0 * r, lat1 * r}

    cos =
      :math.sin(p0) * :math.sin(p1) + :math.cos(p0) * :math.cos(p1) * :math.cos((lon1 - lon0) * r)

    :math.acos(max(-1.0, min(1.0, cos))) / r
  end

  describe "the Sun" do
    test "the subsolar latitude is the tropic at each solstice" do
      {_, june} = DayNightGps.subsolar(~U[2026-06-21 08:24:00Z])
      {_, december} = DayNightGps.subsolar(~U[2026-12-21 20:50:00Z])
      assert_in_delta june, 23.44, 0.01
      assert_in_delta december, -23.44, 0.01
    end

    test "the subsolar latitude is near zero at an equinox" do
      {_, march} = DayNightGps.subsolar(~U[2026-03-20 14:46:00Z])
      assert_in_delta march, 0.0, 0.02
    end

    test "near 12:00 UTC the Sun is over Greenwich, within the equation of time" do
      for date <- [~D[2026-02-11], ~D[2026-05-14], ~D[2026-07-26], ~D[2026-11-03]] do
        {lon, _} = DayNightGps.subsolar(DateTime.new!(date, ~T[12:00:00]))
        assert abs(lon) <= 4.5, "#{date}: #{lon}"
      end

      # Early November the Sun runs about 16 minutes fast: apparent noon is before 12:00
      # UTC at Greenwich, so at 12:00 the Sun is already about 4° west.
      {lon, _} = DayNightGps.subsolar(~U[2026-11-03 12:00:00Z])
      assert_in_delta lon, -4.1, 0.1
    end

    test "the subsolar point moves west 15° an hour" do
      {a, _} = DayNightGps.subsolar(~U[2026-06-21 12:00:00Z])
      {b, _} = DayNightGps.subsolar(~U[2026-06-21 13:00:00Z])
      assert_in_delta b - a, -15.0, 0.01
    end

    test "the night polygon contains the antisolar point and not the subsolar point" do
      for utc <- [~U[2026-06-21 12:00:00Z], ~U[2026-12-21 03:17:00Z], ~U[2026-09-23 22:40:00Z]] do
        night = DayNightGps.night(utc)
        {sun_lon, sun_lat} = DayNightGps.subsolar(utc)
        {anti_lon, anti_lat} = DayNightGps.antisolar(utc)

        assert %{"type" => "Polygon", "coordinates" => [ring]} = night

        # On the sphere: every vertex 90° from the antisolar point, so the cap is the
        # hemisphere about it — and d3's winding makes the path fill that cap (D-131).
        for [lon, lat] <- ring,
            do: assert_in_delta(angle_between({lon, lat}, {anti_lon, anti_lat}), 90, 1.0e-9)

        # As drawn: the antisolar point projects inside the night's rings, the subsolar
        # point outside them (even–odd over the clipped rings).
        proj =
          Visualize.Geo.Projection.new(:equirectangular) |> Visualize.Geo.Projection.scale(100)

        rings = rings(Path.path(Path.new(proj), night))
        assert inside?(rings, Visualize.Geo.Projection.project(proj, anti_lon, anti_lat))
        refute inside?(rings, Visualize.Geo.Projection.project(proj, sun_lon, sun_lat))
      end
    end
  end

  describe "the constellation" do
    test "it is 24 slots in six planes of four" do
      slots = DayNightGps.slots()
      assert length(slots) == 24

      assert slots |> Enum.map(&elem(&1, 0)) |> Enum.frequencies() |> Map.values() ==
               List.duplicate(4, 6)

      assert slots |> Enum.map(&elem(&1, 2)) |> Enum.uniq() == [
               0.0,
               60.0,
               120.0,
               180.0,
               240.0,
               300.0
             ]
    end

    test "Greenwich mean sidereal time is IAU 1982's at J2000" do
      assert_in_delta DayNightGps.gmst(~U[2000-01-01 12:00:00Z]), 280.46061837, 1.0e-6
    end

    test "no satellite's latitude exceeds the inclination" do
      utc = DayNightGps.rest_utc()

      for row <- DayNightGps.tracks(utc),
          [_lon, lat] <- row.shape["coordinates"],
          do: assert(abs(lat) <= 55.0 + 1.0e-9)

      lats = for row <- DayNightGps.tracks(utc), [_, lat] <- row.shape["coordinates"], do: lat
      # Six hours of a 12-hour orbit reach the top of it.
      assert Enum.max(lats) > 54.5
      assert Enum.min(lats) < -54.5
    end

    test "a ground track repeats after one sidereal day" do
      t = ~U[2026-06-21 12:00:00Z]

      for slot <- DayNightGps.slots(), k <- [0, 1234, 20_000] do
        a = DayNightGps.sub_satellite(slot, DateTime.add(t, k, :second))
        b = DayNightGps.sub_satellite(slot, DateTime.add(t, k + @sidereal_day, :second))
        assert angle_between(a, b) < 0.01
      end

      # Half a sidereal day later the satellite is round its orbit once, the Earth half
      # turned: the opposite meridian.
      a = DayNightGps.sub_satellite(hd(DayNightGps.slots()), t)

      {lon, lat} =
        DayNightGps.sub_satellite(hd(DayNightGps.slots()), DateTime.add(t, 43_082, :second))

      assert_in_delta lat, elem(a, 1), 1.0e-6
      assert_in_delta abs(lon - elem(a, 0)), 180, 0.01
    end

    test "the tracks are six hours every five minutes, six fading pieces per satellite" do
      tracks = DayNightGps.tracks(DayNightGps.rest_utc())
      assert length(tracks) == 24 * 6
      assert Enum.all?(tracks, &(length(&1.shape["coordinates"]) == 13))

      for {_, pieces} <- Enum.group_by(tracks, & &1.slot) do
        opacities = Enum.map(pieces, & &1.opacity)
        assert opacities == Enum.sort(opacities)
        # Consecutive pieces share their ends: one line, cut for its fade.
        for [a, b] <- Enum.chunk_every(pieces, 2, 1, :discard),
            do: assert(List.last(a.shape["coordinates"]) == hd(b.shape["coordinates"]))
      end

      # The newest piece ends at the satellite's current position.
      now = Map.new(DayNightGps.satellites(DayNightGps.rest_utc()), &{&1.slot, [&1.lon, &1.lat]})

      for %{opacity: o} = piece <- tracks,
          o == Enum.max(Enum.map(tracks, & &1.opacity)),
          do: assert(List.last(piece.shape["coordinates"]) == now[piece.slot])
    end
  end

  describe "the clock and the rotation" do
    test "a tick is 8 simulated minutes and 2° of the center meridian" do
      assert DayNightGps.utc([]) == DayNightGps.rest_utc()

      assert DayNightGps.utc(animation_tick: 3) ==
               DateTime.add(DayNightGps.rest_utc(), 1440, :second)

      start = ~U[2030-01-02 03:04:05Z]
      assert DayNightGps.utc(animation_tick: 10, utc: start) == DateTime.add(start, 4800, :second)
      # At rest the page's clock is not read: the still render is the fixed instant.
      assert DayNightGps.utc(utc: start) == DayNightGps.rest_utc()

      assert DayNightGps.lambda(nil) == 0
      assert DayNightGps.lambda(1) == -2
      assert DayNightGps.lambda(180) == 0
    end

    test "180 ticks are one mean solar day: the Sun is back over the same meridian" do
      {a, _} = DayNightGps.subsolar(DayNightGps.utc(animation_tick: 0))
      {b, _} = DayNightGps.subsolar(DayNightGps.utc(animation_tick: 180))
      # The equation of time moves about 13 s a day at the solstice: 0.05°.
      assert_in_delta a, b, 0.1
    end

    test "the night and the land move together: the night is the same on the land at any lambda" do
      # The same instant drawn at two center meridians: the night's rows are the same
      # earth-fixed polygon, and drawn, every land position is in the night at one
      # lambda exactly when it is at the other.
      utc = ~U[2026-03-01 06:00:00Z]
      night = DayNightGps.night(utc)

      for lambda <- [0, -50, -133] do
        proj = projection(lambda)
        rings = rings(Path.path(Path.new(proj), night))
        {anti_lon, anti_lat} = DayNightGps.antisolar(utc)

        for [lon, lat] <- sample_land(),
            abs(angle_between({lon, lat}, {anti_lon, anti_lat}) - 90) > 2,
            abs(seam_distance(proj, lon, lat)) > 2 do
          in_night = angle_between({lon, lat}, {anti_lon, anti_lat}) < 90

          assert inside?(rings, Visualize.Geo.Projection.project(proj, lon, lat)) == in_night,
                 "lambda #{lambda}: [#{lon}, #{lat}]"
        end
      end
    end

    test "the design's rows are earth-fixed: only the projection's rotation follows lambda" do
      # Two renders at the same simulated UTC and different ticks would differ in both;
      # at the same tick with different `utc:` they share lambda. So: same UTC, lambda
      # differs only through the tick — compare the sources directly.
      {d0, s0} = DayNightGps.design(animation_tick: 0, utc: ~U[2026-03-01 06:00:00Z])
      {d1, s1} = DayNightGps.design(animation_tick: 45, utc: ~U[2026-03-01 00:00:00Z])
      # 45 ticks × 8 minutes = 6 hours: both are 06:00 UTC.
      assert s0.night == s1.night
      assert s0.tracks == s1.tracks
      assert s0.satellites == s1.satellites
      refute d0 == d1
    end
  end

  describe "the chart" do
    test "the render at rest is deterministic" do
      assert DayNightGps.render([]) == DayNightGps.render([])
      assert DayNightGps.render(animation_tick: 12) == DayNightGps.render(animation_tick: 12)
    end

    test "it draws the night, a track per satellite hour, a dot per satellite and a legend" do
      svg = DayNightGps.render([])
      assert svg =~ "Plane A"
      assert svg =~ "Plane F"
      assert length(Regex.scan(~r/<circle/, svg)) >= 24
    end

    test "its sample code renders" do
      utc = DayNightGps.rest_utc()
      {_design, sources} = DayNightGps.design([])
      {anti_lon, anti_lat} = DayNightGps.antisolar(utc)

      binding = [
        globe: sources.globe,
        land: sources.land,
        night: [%{shape: Visualize.Geo.Circle.polygon(center: [anti_lon, anti_lat], radius: 90)}],
        tracks: DayNightGps.tracks(utc),
        satellites: DayNightGps.satellites(utc)
      ]

      {svg, _} = Code.eval_string(DayNightGps.sample_code(), binding)
      assert is_binary(svg)
      assert svg =~ "mark"
    end

    test "the still render is a light chart's" do
      assert Examples.Compare.cost(DayNightGps) == :light

      {work, _} =
        Visualize.Work.reductions(fn -> Design.render(DayNightGps, width: 700, height: 450) end)

      assert work < 4_000_000
    end
  end

  # -- helpers -----------------------------------------------------------------------

  defp projection(lambda) do
    Visualize.Geo.Projection.new(:natural_earth)
    |> Visualize.Geo.Projection.scale(127)
    |> Visualize.Geo.Projection.translate(350, 200)
    |> Visualize.Geo.Projection.rotate(lambda, 0)
  end

  defp seam_distance(proj, lon, lat) do
    {rotated, _} = Visualize.Geo.Projection.rotated(proj, lon, lat)
    180 - abs(rotated)
  end

  # Every 25th position of the land.
  defp sample_land do
    Examples.Charts.WorldGeography.land()
    |> Enum.flat_map(fn %{shape: shape} -> positions(shape) end)
    |> Enum.take_every(25)
  end

  defp positions(%{"type" => "Feature", "geometry" => g}), do: positions(g)
  defp positions(%{"type" => "Polygon", "coordinates" => rings}), do: Enum.concat(rings)

  defp positions(%{"type" => "MultiPolygon", "coordinates" => polygons}),
    do: polygons |> Enum.concat() |> Enum.concat()

  defp inside?(rings, point),
    do: rings |> Enum.count(&Visualize.Polygon.contains?(&1, point)) |> rem(2) == 1

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
