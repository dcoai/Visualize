defmodule Examples.Charts.DayNightGps do
  @moduledoc """
  Day, night and GPS (#526): the rotating World Map with the night side over the land and
  the ground tracks of the GPS constellation over the last six hours.

  **The map** is World Map's (#129, #499): a `:geo` frame on the Natural Earth projection,
  the ocean as the theme's `:surface`, the graticule every 30° and Natural Earth's 1:110m
  land (`Examples.Charts.WorldGeography`) — here one neutral fill, the theme's `:axis`
  thinly, so the planes' colours are the only colours on the map.

  **The clock.** One animation tick is **8 simulated minutes**, and the simulated UTC is
  `t0 + tick × 480 s`. At rest — no `animation_tick`, as the gallery's card, the tests and
  the charts golden draw it — `t0` is the fixed instant `2026-06-21 12:00:00Z`, the June
  solstice at noon at Greenwich, so the render is deterministic. A run on the chart page
  starts at the real current UTC: the page passes `utc:`, the wall-clock instant the run
  started at, with every tick's options (spec/14 §12.6), and a run without one (the
  performance pages, the tests) starts at the fixed instant.

  **The rotation and what it represents.** `rotate`'s `lambda` is the centre meridian
  (spec/07 §1.4, D-44) and turns `−2°` a tick — `lambda = −(2 × tick mod 360)` — so the
  land drifts east, as the Earth turns, at 360° per 180 ticks: per 24 simulated hours, the
  **mean solar day**. The rotation is the Earth's turn relative to the mean Sun, and the
  view is held facing it: the day side stays nearly where it is on the map while the land
  turns under it, the terminator moving only by the equation of time and the season. It is
  *not* the sidereal turn (about 2.005° per 8 minutes), and nothing depends on it being so:
  the night side and the satellites are computed for the simulated UTC in **earth-fixed**
  longitude and latitude, the land's own coordinates, and all three are drawn through the
  one projection. Their relation to the land is therefore right whatever `lambda` is; the
  rotation only chooses where on the page the Earth is seen from.

  **Night** is `Visualize.Geo.Circle` (spec/07 §2.5, D-131): the 90° circle about the
  antisolar point, the hemisphere the Sun does not light, drawn over the land in the
  theme's `:text` — the page's ink, dark on every light palette — at a low opacity, so the
  gallery names no absolute colour (#421). The subsolar point is the NOAA solar
  calculator's (Meeus's low-precision formulas): the Sun's apparent longitude and the
  obliquity give the declination, which is the subsolar latitude; the equation of time
  gives the longitude where it is apparent noon, which is the subsolar longitude. The
  terminator is the geometric one: no refraction, no twilight.

  **GPS** is the nominal 24-slot constellation, **modelled, not live ephemerides**: the
  gallery fetches nothing. Six planes, A to F, inclined 55°, their ascending nodes 60°
  apart in right ascension (A at 0°, B at 60°, … F at 300°, measured from the vernal
  equinox at J2000, 2000-01-01 12:00 TT taken as UTC); circular orbits of semi-major axis
  26,559.7 km and a period of half a sidereal day, 43,082 s, so a ground track repeats
  every sidereal day. **The phasing is a documented uniform one, not the almanac's
  table**: the nominal 24-slot almanac's arguments of latitude could not be sourced here,
  so the four slots of a plane are 90° apart and each plane is 15° ahead of the one before
  it — a Walker 24/6/1 pattern, `u₀ = 90° · (slot − 1) + 15° · plane`, plane A = 0, at
  J2000. The real constellation's slots are spaced unevenly within a plane. A satellite's
  position is its inertial position on the circle, turned into the earth-fixed frame by
  the Greenwich mean sidereal time (IAU 1982, from the UTC, UT1 taken as UTC); the
  sub-satellite point is that direction's geocentric longitude and latitude on a sphere.
  Each satellite draws its ground track over the trailing 6 simulated hours as
  `LineString`s sampled every 5 simulated minutes, in six one-hour pieces fading toward
  the old end, coloured by plane through a `color` scale with the explicit domain
  `["A" … "F"]` so a plane's colour never moves, and a dot at its current position. A track
  that crosses the rotated frame's antimeridian is cut there by the path's clip (D-127).
  """

  import Visualize.Chart.Build

  alias Examples.Charts.{Design, WorldGeography}

  @zero_margin %{top: 0, right: 0, bottom: 28, left: 0}

  @rest_utc ~U[2026-06-21 12:00:00Z]
  @tick_seconds 480
  @trail_seconds 6 * 3600
  @sample_seconds 300
  @piece_seconds 3600

  @planes ~w(A B C D E F)
  @inclination 55.0
  @semi_major_axis_km 26_559.7
  @period_seconds 43_082
  # J2000.0 as a Unix time: 2000-01-01 12:00:00, taken as UTC.
  @j2000_unix 946_728_000

  @doc "The size this chart is drawn at when the caller names none (spec/14 §4.2)."
  def size, do: {700, 430}

  def title, do: "Day, Night and GPS"

  def description,
    do:
      "Night side and 6 h GPS ground tracks on the rotating World Map; orbits modelled from " <>
        "the nominal 24-slot constellation, not live ephemerides; one tick is 8 simulated minutes"

  @doc "The planes, in the colour scale's order."
  def planes, do: @planes

  @doc "The constellation's semi-major axis in km (it sets the period; the track is a direction)."
  def semi_major_axis_km, do: @semi_major_axis_km

  @doc "The design and the rows it binds (spec/14 §16.1)."
  def design(opts \\ []) do
    {width, _height} = Design.size(__MODULE__, opts)
    lambda = lambda(opts[:animation_tick])
    utc = utc(opts)

    design =
      Design.fold([
        chart(meta: %{name: title(), description: [description()]}),
        source(:globe, [:shape]),
        source(:graticule, [:kind, :degree, :shape, :weight, :opacity]),
        source(:land, [:name, :shape]),
        source(:night, [:shape]),
        source(:tracks, [:plane, :slot, :shape, :opacity]),
        source(:satellites, [:plane, :slot, :lon, :lat]),
        style(:ocean, fill: :surface, stroke: :none),
        style(:rim, fill: :none, stroke: :axis, stroke_width: 1.5),
        style(:graticule,
          fill: :none,
          stroke: :grid,
          stroke_width: {:field, :weight},
          stroke_opacity: {:field, :opacity}
        ),
        style(:land, fill: :axis, fill_opacity: 0.35, stroke: :background, stroke_width: 0.5),
        style(:night, fill: :text, fill_opacity: 0.3, stroke: :none),
        style(:track,
          fill: :none,
          stroke: {:field, :plane},
          stroke_width: 1.5,
          stroke_opacity: {:field, :opacity}
        ),
        style(:satellite, fill: {:field, :plane}, stroke: :background, stroke_width: 1),
        geo(
          margin: @zero_margin,
          projection: %{type: :natural_earth, scale: width / 5.5, rotate: [lambda, 0, 0]}
        ),
        ordinal_scale(:color, domain: @planes),
        legend(:color, position: :bottom, inside: false, prefix: "Plane "),
        # The sphere under everything, the lines, the land, the night over the land, the
        # tracks and the satellites over the night, and the sphere's rim over all.
        path(projection(from(:globe), nil, field: :shape), %{path: :path}, style: :ocean),
        path(projection(from(:graticule), nil, field: :shape), %{path: :path}, style: :graticule),
        path(projection(from(:land), nil, field: :shape), %{path: :path}, style: :land),
        path(projection(from(:night), nil, field: :shape), %{path: :path}, style: :night),
        path(projection(from(:tracks), nil, field: :shape), %{path: :path}, style: :track),
        circle(projection(from(:satellites), [:lon, :lat]), %{x: :x, y: :y},
          style: :satellite,
          options: %{radius: 3.5}
        ),
        path(projection(from(:globe), nil, field: :shape), %{path: :path}, style: :rim)
      ])

    {design,
     %{
       globe: [%{shape: %{"type" => "Sphere"}}],
       graticule: graticule(),
       land: WorldGeography.land(),
       night: [%{shape: night(utc)}],
       tracks: tracks(utc),
       satellites: satellites(utc)
     }}
  end

  def render(opts \\ []), do: Design.render(__MODULE__, opts)

  @doc """
  The centre meridian of the view at a tick: `−(2 × tick mod 360)`, 0 at rest — 2° per
  8 simulated minutes, the mean solar day's rate (see the moduledoc).
  """
  def lambda(nil), do: 0
  def lambda(tick), do: -rem(tick * 2, 360)

  @doc """
  The simulated UTC of a render: `t0 + tick × 480 s`, `t0` the `utc:` option when the
  chart animates and one is given, else the fixed `2026-06-21 12:00:00Z`.
  """
  def utc(opts) do
    case opts[:animation_tick] do
      nil -> @rest_utc
      tick -> DateTime.add(opts[:utc] || @rest_utc, tick * @tick_seconds, :second)
    end
  end

  @doc "The fixed instant a render at rest is drawn for."
  def rest_utc, do: @rest_utc

  # -- the Sun -----------------------------------------------------------------------

  @doc """
  The subsolar point at `utc` as `{lon, lat}` in degrees, from the NOAA solar calculator's
  formulas: the declination is the latitude, and the longitude is where the true solar
  time is noon — `(720 − minutes of the UTC day − equation of time) / 4`, in `[−180, 180)`.
  """
  def subsolar(%DateTime{} = utc) do
    {declination, equation_of_time} = sun(utc)
    minutes = seconds_of_day(utc) / 60
    {(wrap(720 - minutes - equation_of_time) / 4) |> wrap_longitude(), declination}
  end

  @doc "The antisolar point at `utc`, `{lon, lat}`: the subsolar point's antipode."
  def antisolar(%DateTime{} = utc) do
    {lon, lat} = subsolar(utc)
    {wrap_longitude(lon + 180), -lat}
  end

  @doc "The night side at `utc`: the 90° circle about the antisolar point (D-131)."
  def night(%DateTime{} = utc) do
    {lon, lat} = antisolar(utc)
    Visualize.Geo.Circle.polygon(center: [lon, lat], radius: 90)
  end

  # NOAA's solar position (after Meeus, Astronomical Algorithms, ch. 25): the declination
  # in degrees and the equation of time in minutes.
  defp sun(utc) do
    t = (julian_day(utc) - 2_451_545.0) / 36_525
    mean_longitude = fmod(280.46646 + t * (36_000.76983 + t * 0.0003032), 360)
    mean_anomaly = 357.52911 + t * (35_999.05029 - 0.0001537 * t)
    eccentricity = 0.016708634 - t * (0.000042037 + 0.0000001267 * t)

    centre =
      sin(mean_anomaly) * (1.914602 - t * (0.004817 + 0.000014 * t)) +
        sin(2 * mean_anomaly) * (0.019993 - 0.000101 * t) + sin(3 * mean_anomaly) * 0.000289

    omega = 125.04 - 1934.136 * t
    apparent_longitude = mean_longitude + centre - 0.00569 - 0.00478 * sin(omega)

    mean_obliquity =
      23 + (26 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60) / 60

    obliquity = mean_obliquity + 0.00256 * cos(omega)
    declination = asin(sin(obliquity) * sin(apparent_longitude))

    y = :math.pow(:math.tan(obliquity / 2 * :math.pi() / 180), 2)

    equation_of_time =
      4 *
        degrees(
          y * sin(2 * mean_longitude) - 2 * eccentricity * sin(mean_anomaly) +
            4 * eccentricity * y * sin(mean_anomaly) * cos(2 * mean_longitude) -
            0.5 * y * y * sin(4 * mean_longitude) -
            1.25 * eccentricity * eccentricity * sin(2 * mean_anomaly)
        )

    {declination, equation_of_time}
  end

  # -- the constellation -------------------------------------------------------------

  @doc """
  Greenwich mean sidereal time at `utc` in degrees, `[0, 360)`: IAU 1982 (Aoki et al.),
  UT1 taken as UTC.
  """
  def gmst(%DateTime{} = utc) do
    tu = (julian_day(utc) - 2_451_545.0) / 36_525

    seconds =
      67_310.54841 + (876_600 * 3600 + 8_640_184.812866) * tu + 0.093104 * tu * tu -
        6.2e-6 * tu * tu * tu

    fmod(seconds, 86_400) / 240
  end

  @doc "The 24 slots as `{plane, slot, raan, u0}`: plane A–F, slot 1–4, in degrees at J2000."
  def slots do
    for {plane, p} <- Enum.with_index(@planes), slot <- 1..4 do
      {plane, slot, 60.0 * p, 90.0 * (slot - 1) + 15.0 * p}
    end
  end

  @doc """
  The sub-satellite point of a slot at `utc`, `{lon, lat}` in degrees: the circular orbit's
  inertial direction at the argument of latitude `u₀ + 360° · (t − J2000) / 43,082 s`,
  turned by the GMST into the earth-fixed frame.
  """
  def sub_satellite({_plane, _slot, raan, u0}, %DateTime{} = utc) do
    elapsed = DateTime.to_unix(utc) - @j2000_unix
    u = u0 + 360 * Integer.mod(elapsed, @period_seconds) / @period_seconds
    {x, y, z} = inertial(raan, u)
    {wrap_longitude(degrees(:math.atan2(y, x)) - gmst(utc)), degrees(:math.asin(z))}
  end

  # The unit vector of a circular orbit's position: the argument of latitude `u` along the
  # orbit from its ascending node at right ascension `raan`, inclined `@inclination`.
  defp inertial(raan, u) do
    {cos_o, sin_o, cos_u, sin_u} = {cos(raan), sin(raan), cos(u), sin(u)}
    {cos_i, sin_i} = {cos(@inclination), sin(@inclination)}
    {cos_o * cos_u - sin_o * sin_u * cos_i, sin_o * cos_u + cos_o * sin_u * cos_i, sin_u * sin_i}
  end

  @doc "Every satellite's current position: one row per slot, `plane`, `slot`, `lon`, `lat`."
  def satellites(%DateTime{} = utc) do
    for {plane, slot, _, _} = s <- slots() do
      {lon, lat} = sub_satellite(s, utc)
      %{plane: plane, slot: "#{plane}#{slot}", lon: lon, lat: lat}
    end
  end

  @doc """
  The ground tracks over the trailing 6 hours, sampled every 5 minutes: per slot, six
  one-hour `LineString`s sharing their ends, the oldest the faintest.
  """
  def tracks(%DateTime{} = utc) do
    pieces = div(@trail_seconds, @piece_seconds)
    per_piece = div(@piece_seconds, @sample_seconds)

    for {plane, slot, _, _} = s <- slots(), piece <- 1..pieces do
      # Piece 1 is the oldest hour, piece 6 the one ending now.
      start = -@trail_seconds + (piece - 1) * @piece_seconds

      coordinates =
        for k <- 0..per_piece do
          {lon, lat} = sub_satellite(s, DateTime.add(utc, start + k * @sample_seconds, :second))
          [lon, lat]
        end

      %{
        plane: plane,
        slot: "#{plane}#{slot}",
        shape: %{"type" => "LineString", "coordinates" => coordinates},
        opacity: Float.round(0.15 + 0.75 * piece / pieces, 3)
      }
    end
  end

  # -- time and angles ---------------------------------------------------------------

  defp julian_day(utc), do: DateTime.to_unix(utc, :microsecond) / 86_400_000_000 + 2_440_587.5

  defp seconds_of_day(utc) do
    {seconds, _} = utc |> DateTime.to_time() |> Time.to_seconds_after_midnight()
    seconds
  end

  defp fmod(x, m), do: x - Float.floor(x / m) * m
  defp wrap(minutes), do: fmod(minutes + 720, 1440) - 720
  defp wrap_longitude(lon), do: fmod(lon + 180, 360) - 180

  defp degrees(radians), do: radians * 180 / :math.pi()
  defp sin(deg), do: :math.sin(deg * :math.pi() / 180)
  defp cos(deg), do: :math.cos(deg * :math.pi() / 180)
  defp asin(x), do: degrees(:math.asin(x))

  # Every thirty degrees; the equator and the prime meridian heavier.
  defp graticule do
    for line <- WorldGeography.graticule(30) do
      Map.merge(
        line,
        if(line.degree == 0, do: %{weight: 1, opacity: 0.8}, else: %{weight: 0.5, opacity: 0.5})
      )
    end
  end

  def sample_code do
    ~S"""
    import Visualize.Chart.Build

    {:ok, design} =
      Visualize.Chart.compose([
        chart(meta: %{name: "Day, Night and GPS"}),
        source(:globe, [:shape]),
        source(:land, [:name, :shape]),
        source(:night, [:shape]),
        source(:tracks, [:plane, :slot, :shape, :opacity]),
        source(:satellites, [:plane, :slot, :lon, :lat]),
        style(:ocean, fill: :surface, stroke: :none),
        style(:rim, fill: :none, stroke: :axis, stroke_width: 1.5),
        style(:land, fill: :axis, fill_opacity: 0.35, stroke: :background, stroke_width: 0.5),
        style(:night, fill: :text, fill_opacity: 0.3, stroke: :none),
        style(:track, fill: :none, stroke: {:field, :plane}, stroke_width: 1.5,
          stroke_opacity: {:field, :opacity}),
        style(:satellite, fill: {:field, :plane}, stroke: :background, stroke_width: 1),
        # rotate's lambda is the centre meridian (spec/07 §1.4): -2° a tick turns the
        # land east under the Sun.
        geo(margin: %{top: 0, right: 0, bottom: 28, left: 0},
          projection: %{type: :natural_earth, scale: 700 / 5.5, rotate: [0, 0, 0]}),
        # An explicit domain, so a plane's colour never moves.
        ordinal_scale(:color, domain: ~w(A B C D E F)),
        legend(:color, position: :bottom, inside: false, prefix: "Plane "),
        path(projection(from(:globe), nil, field: :shape), %{path: :path}, style: :ocean),
        path(projection(from(:land), nil, field: :shape), %{path: :path}, style: :land),
        # Everything below is earth-fixed lon/lat through the same projection, so the
        # night and the tracks keep their place on the land whatever the rotation.
        path(projection(from(:night), nil, field: :shape), %{path: :path}, style: :night),
        path(projection(from(:tracks), nil, field: :shape), %{path: :path}, style: :track),
        circle(projection(from(:satellites), [:lon, :lat]), %{x: :x, y: :y},
          style: :satellite, options: %{radius: 3.5}),
        path(projection(from(:globe), nil, field: :shape), %{path: :path}, style: :rim)
      ])

    # The night is a 90° circle about the antisolar point (spec/07 §2.5):
    #   night = [%{shape: Visualize.Geo.Circle.polygon(center: [lon, lat], radius: 90)}]
    # The tracks are rows with a GeoJSON LineString under :shape, the satellites rows of
    # lon/lat (Examples.Charts.DayNightGps.tracks/1 and satellites/1, for a UTC instant).
    {:ok, applied} =
      Visualize.Chart.apply(design,
        sources: %{globe: globe, land: land, night: night, tracks: tracks, satellites: satellites}
      )

    Visualize.Chart.render(applied)
    """
  end
end
