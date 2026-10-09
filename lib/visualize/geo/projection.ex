defmodule Visualize.Geo.Projection do
  @moduledoc """
  Geographic projections for mapping spherical coordinates to a plane.

  Transforms longitude/latitude coordinates to x/y pixel coordinates
  for rendering maps.

  ## Supported Projections

  ### Cylindrical
  - `:mercator` - Conformal cylindrical (web maps)
  - `:transverse_mercator` - Transverse Mercator (UTM zones)
  - `:equirectangular` - Simple plate carrée
  - `:cylindrical_equal_area` - Lambert cylindrical equal-area

  ### Azimuthal
  - `:orthographic` - Globe/hemisphere view
  - `:stereographic` - Conformal azimuthal
  - `:gnomonic` - Gnomonic (great circles as straight lines)
  - `:azimuthal_equal_area` - Lambert azimuthal equal-area
  - `:azimuthal_equidistant` - Equidistant azimuthal

  ### Conic
  - `:albers` - Albers equal-area conic
  - `:conic_conformal` - Lambert conformal conic
  - `:conic_equal_area` - Conic equal-area
  - `:conic_equidistant` - Conic equidistant

  ### Pseudocylindrical
  - `:mollweide` - Mollweide equal-area
  - `:sinusoidal` - Sinusoidal equal-area
  - `:eckert1` - Eckert I (rectilinear)
  - `:eckert2` - Eckert II (equal-area)
  - `:eckert3` - Eckert III
  - `:eckert4` - Eckert IV equal-area
  - `:eckert5` - Eckert V
  - `:eckert6` - Eckert VI equal-area
  - `:hammer` - Hammer (Hammer-Aitoff) equal-area
  - `:kavrayskiy7` - Kavrayskiy VII compromise
  - `:wagner4` - Wagner IV equal-area
  - `:wagner6` - Wagner VI compromise
  - `:fahey` - Fahey pseudocylindrical
  - `:collignon` - Collignon (triangular)
  - `:loximuthal` - Loximuthal (rhumb lines straight)

  ### Compromise/Polyconic
  - `:natural_earth` - Natural Earth projection
  - `:equal_earth` - Equal Earth (modern equal-area, 2018)
  - `:robinson` - Robinson compromise
  - `:winkel_tripel` - Winkel tripel (National Geographic)
  - `:aitoff` - Aitoff pseudoazimuthal
  - `:van_der_grinten` - Van der Grinten (circular)
  - `:miller` - Miller cylindrical
  - `:gall_peters` - Gall-Peters equal-area cylindrical
  - `:bonne` - Bonne pseudoconic (heart-shaped)
  - `:polyconic` - American Polyconic

  ## Examples

      projection = Visualize.Geo.Projection.new(:mercator)
        |> Visualize.Geo.Projection.scale(100)
        |> Visualize.Geo.Projection.translate(200, 150)
        |> Visualize.Geo.Projection.center(-95, 40)

      # Project a point
      {x, y} = Visualize.Geo.Projection.project(projection, -122.4, 37.8)

      # Inverse projection
      {lon, lat} = Visualize.Geo.Projection.invert(projection, x, y)

  """

  alias Visualize.Geo.Projection.{Azimuthal, Compromise, Conic, Cylindrical, Pseudocylindrical}

  @deg_to_rad :math.pi() / 180
  @pi_rad :math.pi()
  @rad_to_deg 180 / :math.pi()

  defstruct type: :mercator,
            scale: 150,
            translate: {480, 250},
            center: {0, 0},
            rotate: {0, 0, 0},
            clip_angle: nil,
            precision: 0.5,
            # Conic projection parameters
            parallels: {29.5, 45.5}

  # Cylindrical
  @type projection_type ::
          :mercator
          | :transverse_mercator
          | :equirectangular
          | :cylindrical_equal_area
          | :miller
          | :gall_peters
          # Azimuthal
          | :orthographic
          | :stereographic
          | :gnomonic
          | :azimuthal_equal_area
          | :azimuthal_equidistant
          # Conic
          | :albers
          | :conic_conformal
          | :conic_equal_area
          | :conic_equidistant
          # Pseudoconic
          | :bonne
          | :polyconic
          # Pseudocylindrical
          | :mollweide
          | :sinusoidal
          | :eckert1
          | :eckert2
          | :eckert3
          | :eckert4
          | :eckert5
          | :eckert6
          | :hammer
          | :kavrayskiy7
          | :wagner4
          | :wagner6
          | :fahey
          | :collignon
          | :loximuthal
          # Compromise/Polyconic
          | :natural_earth
          | :equal_earth
          | :robinson
          | :winkel_tripel
          | :aitoff
          | :van_der_grinten

  @type t :: %__MODULE__{
          type: projection_type(),
          scale: number(),
          translate: {number(), number()},
          center: {number(), number()},
          rotate: {number(), number(), number()},
          clip_angle: number() | nil,
          precision: number(),
          parallels: {number(), number()}
        }

  @doc "Creates a new projection of the specified type"
  @spec new(projection_type()) :: t()
  def new(type \\ :mercator) do
    projection = %__MODULE__{type: type}

    # The azimuthal types' clip angles are d3-geo's (spec/07 §1.5): the orthographic's
    # horizon a hair past 90° and the whole-sphere azimuthals' a hair short of 180°, so
    # the circle the paths are clipped by is never degenerate (src/projection/
    # orthographic.js:14, azimuthalEqualArea.js:16, azimuthalEquidistant.js:16).
    case type do
      :orthographic -> %{projection | clip_angle: 90 + 1.0e-6}
      :stereographic -> %{projection | clip_angle: 142}
      :gnomonic -> %{projection | clip_angle: 60}
      :azimuthal_equal_area -> %{projection | clip_angle: 180 - 1.0e-3}
      :azimuthal_equidistant -> %{projection | clip_angle: 180 - 1.0e-3}
      _ -> projection
    end
  end

  @doc "Sets the scale factor"
  @spec scale(t(), number()) :: t()
  def scale(%__MODULE__{} = proj, s), do: %{proj | scale: s}

  @doc "Sets the translation offset"
  @spec translate(t(), number(), number()) :: t()
  def translate(%__MODULE__{} = proj, x, y), do: %{proj | translate: {x, y}}

  @doc "Sets the center point (longitude, latitude)"
  @spec center(t(), number(), number()) :: t()
  def center(%__MODULE__{} = proj, lon, lat), do: %{proj | center: {lon, lat}}

  @doc """
  Sets the rotation (lambda, phi, gamma), in degrees: d3-geo's `projection.rotate` at
  `[-lambda, phi, gamma]` (spec/07 §1.4).

  - lambda: the central meridian — the longitude turned to the centre (d3's `λ` with the
    opposite sign)
  - phi: d3's `φ`, a tilt toward or away from the viewer — `-20` brings 20° N to the
    centre of an azimuthal view
  - gamma: d3's `γ`, a roll about the viewing axis
  """
  @spec rotate(t(), number(), number(), number()) :: t()
  def rotate(%__MODULE__{} = proj, lambda, phi, gamma \\ 0) do
    %{proj | rotate: {lambda, phi, gamma}}
  end

  @doc "Sets the clip angle for azimuthal projections (in degrees)"
  @spec clip_angle(t(), number() | nil) :: t()
  def clip_angle(%__MODULE__{} = proj, angle), do: %{proj | clip_angle: angle}

  @doc """
  Sets the precision (spec/07 §1.1): `0` draws the edge a path is clipped along as d3-geo
  does at `precision(0)`, its interpolation points joined by straight segments; any
  other value samples that edge every degree (§2.2).
  """
  @spec precision(t(), number()) :: t()
  def precision(%__MODULE__{} = proj, precision), do: %{proj | precision: precision}

  @doc "Sets the standard parallels for conic projections"
  @spec parallels(t(), number(), number()) :: t()
  def parallels(%__MODULE__{} = proj, phi0, phi1), do: %{proj | parallels: {phi0, phi1}}

  @doc """
  Projects a geographic point (longitude, latitude) to pixel coordinates (x, y).
  """
  @spec project(t(), number(), number()) :: {float(), float()} | nil
  def project(%__MODULE__{} = proj, lon, lat) do
    {lon, lat} = apply_rotation(lon, lat, proj.rotate)
    project_rotated(proj, lon, lat)
  end

  @doc false
  # The point in the rotated frame, `{lon, lat}` degrees: the first stage of `project/3`
  # (spec/07 §1.3), where `Visualize.Geo.Path` clips on the sphere (§2.2). The longitude
  # is in [-180, 180], as d3's rotation leaves it (rotation.js:79, 95).
  @spec rotated(t(), number(), number()) :: {number(), number()}
  def rotated(%__MODULE__{} = proj, lon, lat) do
    {lon, lat} = apply_rotation(lon, lat, proj.rotate)
    {normalize_longitude(lon), lat}
  end

  @doc false
  # The rest of `project/3` for a point already in the rotated frame: the centre
  # subtracted, the clip test, the raw projection, scale and translate.
  @spec project_rotated(t(), number(), number()) :: {float(), float()} | nil
  def project_rotated(%__MODULE__{} = proj, lon, lat) do
    {center_lon, center_lat} = proj.center
    lon = lon - center_lon
    lat = lat - center_lat

    if clipped?(proj, lon, lat) do
      nil
    else
      case family(proj.type).project(proj.type, lon, lat, proj) do
        nil ->
          nil

        {x, y} ->
          {tx, ty} = proj.translate
          {x * proj.scale + tx, -y * proj.scale + ty}
      end
    end
  end

  @doc false
  # The point in the rotated and centred frame, `{lon, lat}` degrees: the frame of the
  # clip test (spec/07 §1.5), where `Visualize.Geo.Path` clips a projection with a
  # `clip_angle` by its small circle (§2.2.1). With `center` `{0, 0}` it is `rotated/3`.
  @spec centred(t(), number(), number()) :: {number(), number()}
  def centred(%__MODULE__{center: {0, 0}} = proj, lon, lat), do: rotated(proj, lon, lat)

  def centred(%__MODULE__{center: {center_lon, center_lat}} = proj, lon, lat) do
    {lon, lat} = rotated(proj, lon, lat)
    {normalize_longitude(lon - center_lon), lat - center_lat}
  end

  @doc false
  # A point of the centred frame the clip has kept, through the raw projection, scale and
  # translate: the clip was the clip test, so it is not tested again.
  @spec project_centred(t(), number(), number()) :: {float(), float()} | nil
  def project_centred(%__MODULE__{} = proj, lon, lat), do: raw(proj, lon, lat)

  @doc """
  Inverse projection: converts pixel coordinates (x, y) to geographic (lon, lat).
  """
  @spec invert(t(), number(), number()) :: {float(), float()} | nil
  def invert(%__MODULE__{} = proj, x, y) do
    {tx, ty} = proj.translate

    # Remove scale and translate
    x = (x - tx) / proj.scale
    y = -(y - ty) / proj.scale

    # Inverse project
    case family(proj.type).invert(proj.type, x, y, proj) do
      nil ->
        nil

      {lon, lat} ->
        # Apply centering
        {center_lon, center_lat} = proj.center
        lon = lon + center_lon
        lat = lat + center_lat

        # Apply inverse rotation
        apply_inverse_rotation(lon, lat, proj.rotate)
    end
  end

  @doc "Returns the projection's visible bounds as [x0, y0, x1, y1]"
  @spec bounds(t()) :: [number()]
  def bounds(%__MODULE__{} = proj) do
    # Project corner points to find bounds
    corners = [
      {-180, -85},
      {180, -85},
      {180, 85},
      {-180, 85}
    ]

    projected =
      corners
      |> Enum.map(fn {lon, lat} -> project(proj, lon, lat) end)
      |> Enum.filter(& &1)

    if Enum.empty?(projected) do
      {tx, ty} = proj.translate
      [tx - proj.scale, ty - proj.scale, tx + proj.scale, ty + proj.scale]
    else
      xs = Enum.map(projected, fn {x, _} -> x end)
      ys = Enum.map(projected, fn {_, y} -> y end)
      [Enum.min(xs), Enum.min(ys), Enum.max(xs), Enum.max(ys)]
    end
  end

  @doc """
  The projection's outline as a closed list of `{x, y}` pixel points (spec/07 §1.6): the
  sphere of d3-geo's `{type: "Sphere"}`.

  With a `clip_angle` it is the small circle at that angular distance from the centre,
  taken in the rotated and centred frame so `rotate` and `center` turn the globe under it,
  at 360 bearings and projected without the clip test; without one it is the map's edge —
  the antimeridian on either side and the two poles, sampled every degree, at latitude ±85
  for the Mercators and ±90 otherwise. A point the raw projection cannot place is dropped.
  """
  @spec sphere(t()) :: [{float(), float()}]
  def sphere(%__MODULE__{} = proj) do
    proj
    |> outline()
    |> Enum.map(fn {lon, lat} -> raw(proj, lon, lat) end)
    |> Enum.reject(&is_nil/1)
    |> close()
  end

  # The small circle of radius `clip_angle` about the centre, by bearing.
  defp outline(%{clip_angle: c} = _proj) when is_number(c) and c < 180 do
    c = c * @deg_to_rad

    for bearing <- 0..359 do
      b = bearing * @deg_to_rad
      lat = :math.asin(sin(c) * cos(b))
      lon = :math.atan2(sin(b) * sin(c), cos(c))
      {lon / @deg_to_rad, lat / @deg_to_rad}
    end
  end

  # The map's edge: up the western antimeridian, across the north pole, down the eastern
  # antimeridian and back across the south pole.
  defp outline(proj) do
    top = if proj.type in [:mercator, :transverse_mercator], do: 85, else: 90

    Enum.map(-top..top//1, &{-180, &1}) ++
      Enum.map(-179..179//1, &{&1, top}) ++
      Enum.map(top..-top//-1, &{180, &1}) ++
      Enum.map(179..-179//-1, &{&1, -top})
  end

  # The raw projection of a point already rotated and centred, scaled and translated.
  defp raw(proj, lon, lat) do
    case family(proj.type).project(proj.type, lon, lat, proj) do
      nil ->
        nil

      {x, y} ->
        {tx, ty} = proj.translate
        {x * proj.scale + tx, -y * proj.scale + ty}
    end
  end

  defp close([]), do: []
  defp close([first | _] = points), do: points ++ [first]

  @doc """
  Fits the projection to the specified extent for the given GeoJSON bounds.

  extent is [[x0, y0], [x1, y1]] in pixels
  bounds is [[lon0, lat0], [lon1, lat1]] in degrees
  """
  @spec fit_extent(t(), [[number()]], [[number()]]) :: t()
  def fit_extent(%__MODULE__{} = proj, [[x0, y0], [x1, y1]], [[lon0, lat0], [lon1, lat1]]) do
    # Project the geographic bounds
    width = x1 - x0
    height = y1 - y0

    # Calculate scale to fit
    geo_width = abs(lon1 - lon0)
    geo_height = abs(lat1 - lat0)

    # Rough scale estimate (varies by projection)
    scale_x = width / (geo_width * @deg_to_rad)
    scale_y = height / (geo_height * @deg_to_rad)
    new_scale = min(scale_x, scale_y) * 0.95

    # Center point
    center_lon = (lon0 + lon1) / 2
    center_lat = (lat0 + lat1) / 2

    # Translate to center of extent
    translate_x = (x0 + x1) / 2
    translate_y = (y0 + y1) / 2

    proj
    |> scale(new_scale)
    |> center(center_lon, center_lat)
    |> translate(translate_x, translate_y)
  end

  @doc """
  Fits the projection to a list of `{lon, lat}` points (spec/07 §1.6, #475): d3-geo's
  `fitExtent` over points.

  The points are projected at scale 150 and translate `{0, 0}`, and `scale` and
  `translate` are set so their projected bounds fill the pixel box
  `[[x0, y0], [x1, y1]]` on the tighter axis and are centred in it. `center`, `rotate`,
  `clip_angle` and `parallels` are untouched, so a Mercator projection stays
  Web-Mercator. An axis along which the points have no extent does not bound the
  scale; with no extent on either the scale is kept and the point is centred; with no
  projectable point the projection is returned unchanged.

  ## Examples

      iex> proj =
      ...>   Visualize.Geo.Projection.new(:mercator)
      ...>   |> Visualize.Geo.Projection.fit([[0, 0], [100, 100]], [{-10, 0}, {10, 0}])
      iex> {x0, _} = Visualize.Geo.Projection.project(proj, -10, 0)
      iex> {x1, _} = Visualize.Geo.Projection.project(proj, 10, 0)
      iex> {Float.round(x0, 6), Float.round(x1, 6), proj.center}
      {0.0, 100.0, {0, 0}}

  """
  @spec fit(t(), [[number()]], [{number(), number()}]) :: t()
  def fit(%__MODULE__{} = proj, [[x0, y0], [x1, y1]], points) do
    probe = %{proj | scale: 150, translate: {0, 0}}

    projected =
      for {lon, lat} <- points, xy = project(probe, lon, lat), xy != nil, do: xy

    case projected do
      [] ->
        proj

      _some ->
        {xs, ys} = Enum.unzip(projected)
        {bx0, bx1} = Enum.min_max(xs)
        {by0, by1} = Enum.min_max(ys)
        w = x1 - x0
        h = y1 - y0

        k =
          [{w, bx1 - bx0}, {h, by1 - by0}]
          |> Enum.filter(fn {_box, extent} -> extent > 0 end)
          |> Enum.map(fn {box, extent} -> box / extent end)
          |> Enum.min(fn -> proj.scale / 150 end)

        proj
        |> scale(150 * k)
        |> translate(x0 + (w - k * (bx1 + bx0)) / 2, y0 + (h - k * (by1 + by0)) / 2)
    end
  end

  # ============================================

  # ============================================
  # Family dispatch
  # ============================================

  @families %{
    mercator: Cylindrical,
    equirectangular: Cylindrical,
    transverse_mercator: Cylindrical,
    cylindrical_equal_area: Cylindrical,
    miller: Cylindrical,
    gall_peters: Cylindrical,
    orthographic: Azimuthal,
    stereographic: Azimuthal,
    azimuthal_equal_area: Azimuthal,
    azimuthal_equidistant: Azimuthal,
    gnomonic: Azimuthal,
    albers: Conic,
    conic_conformal: Conic,
    conic_equal_area: Conic,
    conic_equidistant: Conic,
    polyconic: Conic,
    bonne: Conic,
    mollweide: Pseudocylindrical,
    sinusoidal: Pseudocylindrical,
    eckert4: Pseudocylindrical,
    hammer: Pseudocylindrical,
    kavrayskiy7: Pseudocylindrical,
    collignon: Pseudocylindrical,
    eckert1: Pseudocylindrical,
    eckert2: Pseudocylindrical,
    eckert3: Pseudocylindrical,
    eckert5: Pseudocylindrical,
    eckert6: Pseudocylindrical,
    wagner4: Pseudocylindrical,
    wagner6: Pseudocylindrical,
    fahey: Pseudocylindrical,
    loximuthal: Pseudocylindrical,
    natural_earth: Compromise,
    equal_earth: Compromise,
    robinson: Compromise,
    winkel_tripel: Compromise,
    aitoff: Compromise,
    van_der_grinten: Compromise
  }

  @doc false
  @spec family(projection_type()) :: module()
  def family(type), do: Map.fetch!(@families, type)

  # ============================================

  # Rotation Helpers

  # The rotation is d3-geo 3.1.1's `rotateRadians` (src/rotation.js:11–16) at
  # `[-lambda, phi, gamma]` (spec/07 §1.4, D-44, D-129): the longitude shift of
  # `rotationLambda`, then, when either is non-zero, `rotationPhiGamma` — `phi` tilting
  # the globe about the y axis, `gamma` rolling it about the viewing (x) axis.
  defp apply_rotation(lon, lat, {0, 0, 0}), do: {lon, lat}

  defp apply_rotation(lon, lat, {lambda, phi, gamma}) when phi == 0 and gamma == 0,
    do: {normalize_longitude((lon * @deg_to_rad - lambda * @deg_to_rad) * @rad_to_deg), lat}

  defp apply_rotation(lon, lat, {lambda, phi, gamma}) do
    lon_rad = normalize_radians(lon * @deg_to_rad - lambda * @deg_to_rad)
    {lon_rad, lat_rad} = rotate_phi_gamma(lon_rad, lat * @deg_to_rad, phi, gamma)
    {lon_rad * @rad_to_deg, lat_rad * @rad_to_deg}
  end

  defp apply_inverse_rotation(lon, lat, {0, 0, 0}), do: {lon, lat}

  # d3's inverse of a composed rotation undoes it in reverse (src/compose.js:8–10, D-44):
  # `rotationPhiGamma.invert`, then `lambda` added back and normalised.
  defp apply_inverse_rotation(lon, lat, {lambda, phi, gamma}) do
    {lon_rad, lat_rad} =
      if phi != 0 or gamma != 0 do
        unrotate_phi_gamma(lon * @deg_to_rad, lat * @deg_to_rad, phi, gamma)
      else
        {lon * @deg_to_rad, lat * @deg_to_rad}
      end

    lon_rad = lon_rad + lambda * @deg_to_rad

    {normalize_longitude(lon_rad * @rad_to_deg), lat_rad * @rad_to_deg}
  end

  # `rotationPhiGamma`'s `rotation` (src/rotation.js:39–48), angles in degrees, the point
  # in radians.
  defp rotate_phi_gamma(lon, lat, phi, gamma) do
    {cos_p, sin_p, cos_g, sin_g} = trig(phi, gamma)
    {x, y, z} = to_cartesian(lon, lat)
    k = z * cos_p + x * sin_p
    {:math.atan2(y * cos_g - k * sin_g, x * cos_p - z * sin_p), asin(k * cos_g + y * sin_g)}
  end

  # `rotationPhiGamma`'s `rotation.invert` (src/rotation.js:50–60).
  defp unrotate_phi_gamma(lon, lat, phi, gamma) do
    {cos_p, sin_p, cos_g, sin_g} = trig(phi, gamma)
    {x, y, z} = to_cartesian(lon, lat)
    k = z * cos_g - y * sin_g
    {:math.atan2(y * cos_g + z * sin_g, x * cos_p + k * sin_p), asin(k * cos_p - x * sin_p)}
  end

  defp trig(phi, gamma) do
    {p, g} = {phi * @deg_to_rad, gamma * @deg_to_rad}
    {cos(p), sin(p), cos(g), sin(g)}
  end

  # d3's `asin` (src/math.js), which clamps its argument to [-1, 1].
  defp asin(v), do: :math.asin(max(-1.0, min(1.0, v)))

  # `rotationLambda`'s normalisation (src/rotation.js:21): beyond ±π, less the nearest
  # whole turn, rounded as JavaScript's `Math.round` rounds a half (up).
  defp normalize_radians(lambda) when abs(lambda) > @pi_rad,
    do: lambda - Float.floor(lambda / (2 * @pi_rad) + 0.5) * 2 * @pi_rad

  defp normalize_radians(lambda), do: lambda

  defp to_cartesian(lon, lat) do
    cos_lat = cos(lat)
    {cos_lat * cos(lon), cos_lat * sin(lon), sin(lat)}
  end

  defp normalize_longitude(lon) when lon > 180, do: normalize_longitude(lon - 360)
  defp normalize_longitude(lon) when lon < -180, do: normalize_longitude(lon + 360)
  defp normalize_longitude(lon), do: lon

  # A point is clipped when its angular distance from the projection centre
  # exceeds the clip angle. `lon` and `lat` are already rotated and centred, in degrees.
  defp clipped?(%{clip_angle: nil}, _lon, _lat), do: false

  defp clipped?(%{clip_angle: clip_angle}, lon, lat) do
    cos_c = cos(lat * @deg_to_rad) * cos(lon * @deg_to_rad)
    cos_c < cos(clip_angle * @deg_to_rad) - 1.0e-9
  end

  defp sin(x), do: :math.sin(x)
  defp cos(x), do: :math.cos(x)
end
