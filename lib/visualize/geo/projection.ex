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

  @deg_to_rad :math.pi() / 180
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

  @type projection_type ::
          # Cylindrical
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

    # Set default clip angle for azimuthal projections
    case type do
      :orthographic -> %{projection | clip_angle: 90}
      :stereographic -> %{projection | clip_angle: 142}
      :gnomonic -> %{projection | clip_angle: 60}
      :azimuthal_equal_area -> %{projection | clip_angle: 180}
      :azimuthal_equidistant -> %{projection | clip_angle: 180}
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
  Sets the rotation (lambda, phi, gamma).

  - lambda: Rotation around the vertical axis (yaw)
  - phi: Rotation around the horizontal axis (pitch)
  - gamma: Rotation around the viewing axis (roll)
  """
  @spec rotate(t(), number(), number(), number()) :: t()
  def rotate(%__MODULE__{} = proj, lambda, phi, gamma \\ 0) do
    %{proj | rotate: {lambda, phi, gamma}}
  end

  @doc "Sets the clip angle for azimuthal projections (in degrees)"
  @spec clip_angle(t(), number() | nil) :: t()
  def clip_angle(%__MODULE__{} = proj, angle), do: %{proj | clip_angle: angle}

  @doc "Sets the standard parallels for conic projections"
  @spec parallels(t(), number(), number()) :: t()
  def parallels(%__MODULE__{} = proj, phi0, phi1), do: %{proj | parallels: {phi0, phi1}}

  @doc """
  Projects a geographic point (longitude, latitude) to pixel coordinates (x, y).
  """
  @spec project(t(), number(), number()) :: {float(), float()} | nil
  def project(%__MODULE__{} = proj, lon, lat) do
    # Apply rotation
    {lon, lat} = apply_rotation(lon, lat, proj.rotate)

    # Apply centering
    {center_lon, center_lat} = proj.center
    lon = lon - center_lon
    lat = lat - center_lat

    # Check clip angle
    if clipped?(proj, lon, lat) do
      nil
    else
      # Project based on type
      case raw_project(proj.type, lon, lat, proj) do
        nil ->
          nil

        {x, y} ->
          # Apply scale and translate
          {tx, ty} = proj.translate
          {x * proj.scale + tx, -y * proj.scale + ty}
      end
    end
  end

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
    case raw_invert(proj.type, x, y, proj) do
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

  # ============================================
  # Projection Implementations
  # ============================================

  # Mercator
  defp raw_project(:mercator, lon, lat, _proj) do
    lat_rad = lat * @deg_to_rad
    # Clamp latitude to avoid infinity
    lat_rad = max(-1.4844, min(1.4844, lat_rad))
    x = lon * @deg_to_rad
    y = :math.log(:math.tan(:math.pi() / 4 + lat_rad / 2))
    {x, y}
  end

  defp raw_invert(:mercator, x, y, _proj) do
    lon = x * @rad_to_deg
    lat = (2 * :math.atan(:math.exp(y)) - :math.pi() / 2) * @rad_to_deg
    {lon, lat}
  end

  # Equirectangular (Plate Carrée)
  defp raw_project(:equirectangular, lon, lat, _proj) do
    {lon * @deg_to_rad, lat * @deg_to_rad}
  end

  defp raw_invert(:equirectangular, x, y, _proj) do
    {x * @rad_to_deg, y * @rad_to_deg}
  end

  # Orthographic (globe)
  defp raw_project(:orthographic, lon, lat, _proj) do
    lon_rad = lon * @deg_to_rad
    lat_rad = lat * @deg_to_rad

    # Only show front hemisphere
    cos_c = :math.cos(lat_rad) * :math.cos(lon_rad)

    if cos_c < 0 do
      nil
    else
      x = :math.cos(lat_rad) * :math.sin(lon_rad)
      y = :math.sin(lat_rad)
      {x, y}
    end
  end

  defp raw_invert(:orthographic, x, y, _proj) do
    rho = :math.sqrt(x * x + y * y)

    if rho > 1 do
      nil
    else
      c = :math.asin(rho)
      cos_c = :math.cos(c)
      sin_c = :math.sin(c)

      lat =
        if rho == 0 do
          0
        else
          :math.asin(y * sin_c / rho)
        end

      lon = :math.atan2(x * sin_c, rho * cos_c)
      {lon * @rad_to_deg, lat * @rad_to_deg}
    end
  end

  # Stereographic
  defp raw_project(:stereographic, lon, lat, _proj) do
    lon_rad = lon * @deg_to_rad
    lat_rad = lat * @deg_to_rad

    cos_lat = :math.cos(lat_rad)
    k = 1 + cos_lat * :math.cos(lon_rad)

    if k < 0.001 do
      nil
    else
      x = cos_lat * :math.sin(lon_rad) / k
      y = :math.sin(lat_rad) / k
      {x, y}
    end
  end

  defp raw_invert(:stereographic, x, y, _proj) do
    rho = :math.sqrt(x * x + y * y)
    c = 2 * :math.atan(rho)
    cos_c = :math.cos(c)
    sin_c = :math.sin(c)

    lat =
      if rho == 0 do
        0
      else
        :math.asin(y * sin_c / rho)
      end

    lon =
      if rho == 0 do
        0
      else
        :math.atan2(x * sin_c, rho * cos_c)
      end

    {lon * @rad_to_deg, lat * @rad_to_deg}
  end

  # Azimuthal Equal Area
  defp raw_project(:azimuthal_equal_area, lon, lat, _proj) do
    lon_rad = lon * @deg_to_rad
    lat_rad = lat * @deg_to_rad

    cos_lat = :math.cos(lat_rad)
    cos_lon = :math.cos(lon_rad)
    k_prime = 1 + cos_lat * cos_lon

    if k_prime < 0.001 do
      nil
    else
      k = :math.sqrt(2 / k_prime)
      x = k * cos_lat * :math.sin(lon_rad)
      y = k * :math.sin(lat_rad)
      {x, y}
    end
  end

  defp raw_invert(:azimuthal_equal_area, x, y, _proj) do
    rho = :math.sqrt(x * x + y * y)
    c = 2 * :math.asin(rho / 2)
    cos_c = :math.cos(c)
    sin_c = :math.sin(c)

    lat =
      if rho == 0 do
        0
      else
        :math.asin(y * sin_c / rho)
      end

    lon = :math.atan2(x * sin_c, rho * cos_c)
    {lon * @rad_to_deg, lat * @rad_to_deg}
  end

  # Azimuthal Equidistant
  defp raw_project(:azimuthal_equidistant, lon, lat, _proj) do
    lon_rad = lon * @deg_to_rad
    lat_rad = lat * @deg_to_rad

    cos_lat = :math.cos(lat_rad)
    c = :math.acos(cos_lat * :math.cos(lon_rad))

    if c == 0 do
      {0.0, 0.0}
    else
      k = c / :math.sin(c)
      x = k * cos_lat * :math.sin(lon_rad)
      y = k * :math.sin(lat_rad)
      {x, y}
    end
  end

  defp raw_invert(:azimuthal_equidistant, x, y, _proj) do
    rho = :math.sqrt(x * x + y * y)

    if rho == 0 do
      {0.0, 0.0}
    else
      c = rho
      cos_c = :math.cos(c)
      sin_c = :math.sin(c)

      lat = :math.asin(y * sin_c / rho)
      lon = :math.atan2(x * sin_c, rho * cos_c)
      {lon * @rad_to_deg, lat * @rad_to_deg}
    end
  end

  # Albers Equal-Area Conic
  defp raw_project(:albers, lon, lat, proj) do
    {phi1, phi2} = proj.parallels
    phi1_rad = phi1 * @deg_to_rad
    phi2_rad = phi2 * @deg_to_rad

    n = (sin(phi1_rad) + sin(phi2_rad)) / 2
    c = cos(phi1_rad) * cos(phi1_rad) + 2 * n * sin(phi1_rad)
    rho0 = :math.sqrt(c) / n

    lon_rad = lon * @deg_to_rad * n
    lat_rad = lat * @deg_to_rad
    rho = :math.sqrt(c - 2 * n * sin(lat_rad)) / n

    x = rho * sin(lon_rad)
    y = rho0 - rho * cos(lon_rad)
    {x, y}
  end

  defp raw_invert(:albers, x, y, proj) do
    {phi1, phi2} = proj.parallels
    phi1_rad = phi1 * @deg_to_rad
    phi2_rad = phi2 * @deg_to_rad

    n = (sin(phi1_rad) + sin(phi2_rad)) / 2
    c = cos(phi1_rad) * cos(phi1_rad) + 2 * n * sin(phi1_rad)
    rho0 = :math.sqrt(c) / n

    rho = :math.sqrt(x * x + (rho0 - y) * (rho0 - y))
    lat = :math.asin((c - rho * rho * n * n) / (2 * n))
    lon = :math.atan2(x, rho0 - y) / n

    {lon * @rad_to_deg, lat * @rad_to_deg}
  end

  # Lambert Conformal Conic
  defp raw_project(:conic_conformal, lon, lat, proj) do
    {phi1, phi2} = proj.parallels
    phi1_rad = phi1 * @deg_to_rad
    phi2_rad = phi2 * @deg_to_rad

    n =
      if abs(phi1_rad - phi2_rad) < 0.001 do
        sin(phi1_rad)
      else
        :math.log(cos(phi1_rad) / cos(phi2_rad)) /
          :math.log(:math.tan(:math.pi() / 4 + phi2_rad / 2) / :math.tan(:math.pi() / 4 + phi1_rad / 2))
      end

    f = cos(phi1_rad) * :math.pow(:math.tan(:math.pi() / 4 + phi1_rad / 2), n) / n
    rho0 = f

    lat_rad = lat * @deg_to_rad
    rho = f / :math.pow(:math.tan(:math.pi() / 4 + lat_rad / 2), n)

    lon_rad = lon * @deg_to_rad * n
    x = rho * sin(lon_rad)
    y = rho0 - rho * cos(lon_rad)
    {x, y}
  end

  defp raw_invert(:conic_conformal, x, y, proj) do
    {phi1, phi2} = proj.parallels
    phi1_rad = phi1 * @deg_to_rad
    phi2_rad = phi2 * @deg_to_rad

    n =
      if abs(phi1_rad - phi2_rad) < 0.001 do
        sin(phi1_rad)
      else
        :math.log(cos(phi1_rad) / cos(phi2_rad)) /
          :math.log(:math.tan(:math.pi() / 4 + phi2_rad / 2) / :math.tan(:math.pi() / 4 + phi1_rad / 2))
      end

    f = cos(phi1_rad) * :math.pow(:math.tan(:math.pi() / 4 + phi1_rad / 2), n) / n
    rho0 = f

    rho = :math.sqrt(x * x + (rho0 - y) * (rho0 - y))
    rho = if n < 0, do: -rho, else: rho

    lon = :math.atan2(x, rho0 - y) / n
    lat = 2 * :math.atan(:math.pow(f / rho, 1 / n)) - :math.pi() / 2

    {lon * @rad_to_deg, lat * @rad_to_deg}
  end

  # Natural Earth projection
  defp raw_project(:natural_earth, lon, lat, _proj) do
    lon_rad = lon * @deg_to_rad
    lat_rad = lat * @deg_to_rad
    lat2 = lat_rad * lat_rad
    lat4 = lat2 * lat2

    x = lon_rad * (0.8707 - 0.131979 * lat2 + lat4 * (-0.013791 + lat4 * (0.003971 * lat2 - 0.001529 * lat4)))
    y = lat_rad * (1.007226 + lat2 * (0.015085 + lat4 * (-0.044475 + 0.028874 * lat2 - 0.005916 * lat4)))

    {x, y}
  end

  defp raw_invert(:natural_earth, x, y, _proj) do
    # Newton-Raphson iteration for inverse
    lat_rad = y
    _lon_rad = x

    # Iterate to find latitude
    lat_rad = newton_raphson_natural_earth(y, lat_rad, 10)

    lat2 = lat_rad * lat_rad
    lat4 = lat2 * lat2

    # Compute longitude
    denom = 0.8707 - 0.131979 * lat2 + lat4 * (-0.013791 + lat4 * (0.003971 * lat2 - 0.001529 * lat4))
    lon_rad = if abs(denom) > 0.001, do: x / denom, else: 0

    {lon_rad * @rad_to_deg, lat_rad * @rad_to_deg}
  end

  defp newton_raphson_natural_earth(_y, lat, 0), do: lat

  defp newton_raphson_natural_earth(y, lat, iterations) do
    lat2 = lat * lat
    lat4 = lat2 * lat2

    f = lat * (1.007226 + lat2 * (0.015085 + lat4 * (-0.044475 + 0.028874 * lat2 - 0.005916 * lat4))) - y

    df = 1.007226 + lat2 * (0.045255 + lat4 * (-0.311325 + 0.259866 * lat2 - 0.053244 * lat4))

    new_lat = lat - f / df

    if abs(new_lat - lat) < 0.0001 do
      new_lat
    else
      newton_raphson_natural_earth(y, new_lat, iterations - 1)
    end
  end

  # ============================================
  # Gnomonic (great circles as straight lines)
  # ============================================

  defp raw_project(:gnomonic, lon, lat, _proj) do
    lon_rad = lon * @deg_to_rad
    lat_rad = lat * @deg_to_rad

    cos_lat = cos(lat_rad)
    cos_lon = cos(lon_rad)
    cos_c = cos_lat * cos_lon

    # Point is behind the projection plane
    if cos_c <= 0 do
      nil
    else
      x = cos_lat * sin(lon_rad) / cos_c
      y = sin(lat_rad) / cos_c
      {x, y}
    end
  end

  defp raw_invert(:gnomonic, x, y, _proj) do
    rho = :math.sqrt(x * x + y * y)
    c = :math.atan(rho)
    cos_c = cos(c)
    sin_c = sin(c)

    lat =
      if rho == 0 do
        0
      else
        :math.asin(y * sin_c / rho)
      end

    lon = :math.atan2(x * sin_c, rho * cos_c)
    {lon * @rad_to_deg, lat * @rad_to_deg}
  end

  # ============================================
  # Transverse Mercator (UTM)
  # ============================================

  defp raw_project(:transverse_mercator, lon, lat, _proj) do
    lon_rad = lon * @deg_to_rad
    lat_rad = lat * @deg_to_rad

    cos_lat = cos(lat_rad)
    sin_lat = sin(lat_rad)
    sin_lon = sin(lon_rad)
    cos_lon = cos(lon_rad)

    # B is the transverse equivalent of latitude
    b = cos_lat * sin_lon
    # Clamp to avoid infinity
    b = max(-0.9999, min(0.9999, b))

    x = 0.5 * :math.log((1 + b) / (1 - b))
    y = :math.atan2(sin_lat, cos_lat * cos_lon)
    {x, y}
  end

  defp raw_invert(:transverse_mercator, x, y, _proj) do
    sinh_x = (:math.exp(x) - :math.exp(-x)) / 2
    cos_y = cos(y)
    sin_y = sin(y)

    lon = :math.atan2(sinh_x, cos_y)
    lat = :math.asin(sin_y / :math.sqrt(sinh_x * sinh_x + cos_y * cos_y))
    {lon * @rad_to_deg, lat * @rad_to_deg}
  end

  # ============================================
  # Cylindrical Equal Area (Lambert)
  # ============================================

  defp raw_project(:cylindrical_equal_area, lon, lat, _proj) do
    lon_rad = lon * @deg_to_rad
    lat_rad = lat * @deg_to_rad
    {lon_rad, sin(lat_rad)}
  end

  defp raw_invert(:cylindrical_equal_area, x, y, _proj) do
    lon = x * @rad_to_deg
    lat = :math.asin(max(-1, min(1, y))) * @rad_to_deg
    {lon, lat}
  end

  # ============================================
  # Conic Equal Area
  # ============================================

  defp raw_project(:conic_equal_area, lon, lat, proj) do
    # Same as Albers (Albers is a conic equal-area projection)
    raw_project(:albers, lon, lat, proj)
  end

  defp raw_invert(:conic_equal_area, x, y, proj) do
    raw_invert(:albers, x, y, proj)
  end

  # ============================================
  # Conic Equidistant
  # ============================================

  defp raw_project(:conic_equidistant, lon, lat, proj) do
    {phi1, phi2} = proj.parallels
    phi1_rad = phi1 * @deg_to_rad
    phi2_rad = phi2 * @deg_to_rad

    n =
      if abs(phi1_rad - phi2_rad) < 0.001 do
        sin(phi1_rad)
      else
        (cos(phi1_rad) - cos(phi2_rad)) / (phi2_rad - phi1_rad)
      end

    g = cos(phi1_rad) / n + phi1_rad
    rho0 = g

    lat_rad = lat * @deg_to_rad
    rho = g - lat_rad

    lon_rad = lon * @deg_to_rad * n
    x = rho * sin(lon_rad)
    y = rho0 - rho * cos(lon_rad)
    {x, y}
  end

  defp raw_invert(:conic_equidistant, x, y, proj) do
    {phi1, phi2} = proj.parallels
    phi1_rad = phi1 * @deg_to_rad
    phi2_rad = phi2 * @deg_to_rad

    n =
      if abs(phi1_rad - phi2_rad) < 0.001 do
        sin(phi1_rad)
      else
        (cos(phi1_rad) - cos(phi2_rad)) / (phi2_rad - phi1_rad)
      end

    g = cos(phi1_rad) / n + phi1_rad
    rho0 = g

    rho = :math.sqrt(x * x + (rho0 - y) * (rho0 - y))
    rho = if n < 0, do: -rho, else: rho

    lon = :math.atan2(x, rho0 - y) / n
    lat = g - rho

    {lon * @rad_to_deg, lat * @rad_to_deg}
  end

  # ============================================
  # Mollweide (pseudocylindrical equal-area)
  # ============================================

  @sqrt2 :math.sqrt(2)

  defp raw_project(:mollweide, lon, lat, _proj) do
    lon_rad = lon * @deg_to_rad
    lat_rad = lat * @deg_to_rad

    # Solve for theta using Newton-Raphson
    theta = newton_raphson_mollweide(lat_rad, lat_rad, 10)

    x = 2 * @sqrt2 / :math.pi() * lon_rad * cos(theta)
    y = @sqrt2 * sin(theta)
    {x, y}
  end

  defp raw_invert(:mollweide, x, y, _proj) do
    theta = :math.asin(y / @sqrt2)
    lat = :math.asin((2 * theta + sin(2 * theta)) / :math.pi())
    lon = :math.pi() * x / (2 * @sqrt2 * cos(theta))
    {lon * @rad_to_deg, lat * @rad_to_deg}
  end

  defp newton_raphson_mollweide(_phi, theta, 0), do: theta

  defp newton_raphson_mollweide(phi, theta, iterations) do
    sin_theta = sin(theta)
    cos_theta = cos(theta)
    f = 2 * theta + sin(2 * theta) - :math.pi() * sin(phi)
    df = 2 + 2 * cos(2 * theta)

    new_theta = theta - f / df

    if abs(new_theta - theta) < 0.0001 do
      new_theta
    else
      newton_raphson_mollweide(phi, new_theta, iterations - 1)
    end
  end

  # ============================================
  # Sinusoidal (pseudocylindrical equal-area)
  # ============================================

  defp raw_project(:sinusoidal, lon, lat, _proj) do
    lon_rad = lon * @deg_to_rad
    lat_rad = lat * @deg_to_rad
    {lon_rad * cos(lat_rad), lat_rad}
  end

  defp raw_invert(:sinusoidal, x, y, _proj) do
    lat = y
    lon = if abs(cos(lat)) > 0.001, do: x / cos(lat), else: 0
    {lon * @rad_to_deg, lat * @rad_to_deg}
  end

  # ============================================
  # Eckert IV (pseudocylindrical equal-area)
  # ============================================

  @eckert4_cx 2 / :math.sqrt(:math.pi() * (4 + :math.pi()))
  @eckert4_cy 2 * :math.sqrt(:math.pi() / (4 + :math.pi()))
  @eckert4_c 2 + :math.pi() / 2

  defp raw_project(:eckert4, lon, lat, _proj) do
    lon_rad = lon * @deg_to_rad
    lat_rad = lat * @deg_to_rad

    # Solve for theta using Newton-Raphson
    theta = newton_raphson_eckert4(lat_rad, lat_rad / 2, 10)

    x = @eckert4_cx * lon_rad * (1 + cos(theta))
    y = @eckert4_cy * sin(theta)
    {x, y}
  end

  defp raw_invert(:eckert4, x, y, _proj) do
    theta = :math.asin(y / @eckert4_cy)
    lat = :math.asin((theta + sin(theta) * cos(theta) + 2 * sin(theta)) / @eckert4_c)
    lon = x / (@eckert4_cx * (1 + cos(theta)))
    {lon * @rad_to_deg, lat * @rad_to_deg}
  end

  defp newton_raphson_eckert4(_phi, theta, 0), do: theta

  defp newton_raphson_eckert4(phi, theta, iterations) do
    sin_theta = sin(theta)
    cos_theta = cos(theta)
    f = theta + sin_theta * cos_theta + 2 * sin_theta - @eckert4_c * sin(phi)
    df = 1 + cos_theta * cos_theta - sin_theta * sin_theta + 2 * cos_theta

    new_theta = theta - f / df

    if abs(new_theta - theta) < 0.0001 do
      new_theta
    else
      newton_raphson_eckert4(phi, new_theta, iterations - 1)
    end
  end

  # ============================================
  # Hammer (Hammer-Aitoff, equal-area)
  # ============================================

  defp raw_project(:hammer, lon, lat, _proj) do
    lon_rad = lon * @deg_to_rad
    lat_rad = lat * @deg_to_rad

    cos_lat = cos(lat_rad)
    d = :math.sqrt(1 + cos_lat * cos(lon_rad / 2))

    x = 2 * @sqrt2 * cos_lat * sin(lon_rad / 2) / d
    y = @sqrt2 * sin(lat_rad) / d
    {x, y}
  end

  defp raw_invert(:hammer, x, y, _proj) do
    z = :math.sqrt(1 - (x / 4) * (x / 4) - (y / 2) * (y / 2))
    lon = 2 * :math.atan2(z * x, 2 * (2 * z * z - 1))
    lat = :math.asin(z * y)
    {lon * @rad_to_deg, lat * @rad_to_deg}
  end

  # ============================================
  # Equal Earth (modern equal-area, 2018)
  # ============================================

  # Equal Earth polynomial coefficients
  @ee_a1 1.340264
  @ee_a2 -0.081106
  @ee_a3 0.000893
  @ee_a4 0.003796
  @ee_m :math.sqrt(3) / 2

  defp raw_project(:equal_earth, lon, lat, _proj) do
    lon_rad = lon * @deg_to_rad
    lat_rad = lat * @deg_to_rad

    # Parametric latitude
    theta = :math.asin(@ee_m * sin(lat_rad))
    theta2 = theta * theta
    theta6 = theta2 * theta2 * theta2

    x = lon_rad * cos(theta) / (@ee_m * (@ee_a1 + 3 * @ee_a2 * theta2 + theta6 * (7 * @ee_a3 + 9 * @ee_a4 * theta2)))
    y = theta * (@ee_a1 + @ee_a2 * theta2 + theta6 * (@ee_a3 + @ee_a4 * theta2))
    {x, y}
  end

  defp raw_invert(:equal_earth, x, y, _proj) do
    # Newton-Raphson to find theta
    theta = newton_raphson_equal_earth(y, y, 10)
    theta2 = theta * theta
    theta6 = theta2 * theta2 * theta2

    lon = @ee_m * x * (@ee_a1 + 3 * @ee_a2 * theta2 + theta6 * (7 * @ee_a3 + 9 * @ee_a4 * theta2)) / cos(theta)
    lat = :math.asin(sin(theta) / @ee_m)
    {lon * @rad_to_deg, lat * @rad_to_deg}
  end

  defp newton_raphson_equal_earth(_y, theta, 0), do: theta

  defp newton_raphson_equal_earth(y, theta, iterations) do
    theta2 = theta * theta
    theta6 = theta2 * theta2 * theta2

    f = theta * (@ee_a1 + @ee_a2 * theta2 + theta6 * (@ee_a3 + @ee_a4 * theta2)) - y
    df = @ee_a1 + 3 * @ee_a2 * theta2 + theta6 * (7 * @ee_a3 + 9 * @ee_a4 * theta2)

    new_theta = theta - f / df

    if abs(new_theta - theta) < 0.0001 do
      new_theta
    else
      newton_raphson_equal_earth(y, new_theta, iterations - 1)
    end
  end

  # ============================================
  # Robinson (compromise projection)
  # ============================================

  # Robinson projection lookup table (latitude in 5-degree intervals)
  @robinson_x [1.0000, 0.9986, 0.9954, 0.9900, 0.9822, 0.9730, 0.9600, 0.9427, 0.9216, 0.8962,
               0.8679, 0.8350, 0.7986, 0.7597, 0.7186, 0.6732, 0.6213, 0.5722, 0.5322]
  @robinson_y [0.0000, 0.0620, 0.1240, 0.1860, 0.2480, 0.3100, 0.3720, 0.4340, 0.4958, 0.5571,
               0.6176, 0.6769, 0.7346, 0.7903, 0.8435, 0.8936, 0.9394, 0.9761, 1.0000]

  defp raw_project(:robinson, lon, lat, _proj) do
    lon_rad = lon * @deg_to_rad
    lat_rad = lat * @deg_to_rad
    abs_lat = abs(lat)

    # Interpolate from lookup table
    {plen, pdfe} = robinson_interpolate(abs_lat)

    x = 0.8487 * plen * lon_rad
    y = 1.3523 * pdfe * (if lat < 0, do: -1, else: 1)
    {x, y}
  end

  defp raw_invert(:robinson, x, y, _proj) do
    # Inverse lookup
    abs_y = abs(y) / 1.3523
    {plen, lat_deg} = robinson_inverse_y(abs_y)

    lon = x / (0.8487 * plen)
    lat = lat_deg * (if y < 0, do: -1, else: 1)
    {lon * @rad_to_deg, lat}
  end

  defp robinson_interpolate(lat_deg) do
    # Find interval
    idx = min(17, trunc(lat_deg / 5))
    frac = (lat_deg - idx * 5) / 5

    x0 = Enum.at(@robinson_x, idx)
    x1 = Enum.at(@robinson_x, idx + 1)
    y0 = Enum.at(@robinson_y, idx)
    y1 = Enum.at(@robinson_y, idx + 1)

    plen = x0 + (x1 - x0) * frac
    pdfe = y0 + (y1 - y0) * frac
    {plen, pdfe}
  end

  defp robinson_inverse_y(y) do
    # Find interval by searching Y values
    {idx, _} = Enum.reduce_while(0..17, {0, 0}, fn i, _acc ->
      y0 = Enum.at(@robinson_y, i)
      y1 = Enum.at(@robinson_y, i + 1)
      if y >= y0 and y <= y1 do
        {:halt, {i, y0}}
      else
        {:cont, {i, y0}}
      end
    end)

    y0 = Enum.at(@robinson_y, idx)
    y1 = Enum.at(@robinson_y, idx + 1)
    frac = if y1 != y0, do: (y - y0) / (y1 - y0), else: 0

    lat_deg = idx * 5 + frac * 5
    plen = Enum.at(@robinson_x, idx) + (Enum.at(@robinson_x, idx + 1) - Enum.at(@robinson_x, idx)) * frac
    {plen, lat_deg}
  end

  # ============================================
  # Winkel Tripel (National Geographic)
  # ============================================

  defp raw_project(:winkel_tripel, lon, lat, _proj) do
    lon_rad = lon * @deg_to_rad
    lat_rad = lat * @deg_to_rad

    cos_lat = cos(lat_rad)
    alpha = :math.acos(cos_lat * cos(lon_rad / 2))

    sinc_alpha = if alpha == 0, do: 1, else: sin(alpha) / alpha

    # Average of equirectangular and Aitoff
    x_aitoff = 2 * cos_lat * sin(lon_rad / 2) / sinc_alpha
    y_aitoff = sin(lat_rad) / sinc_alpha

    x = (lon_rad + x_aitoff) / 2
    y = (lat_rad + y_aitoff) / 2
    {x, y}
  end

  defp raw_invert(:winkel_tripel, x, y, _proj) do
    # Newton-Raphson iteration for inverse
    {lon, lat} = newton_raphson_winkel_tripel(x, y, x, y, 10)
    {lon * @rad_to_deg, lat * @rad_to_deg}
  end

  defp newton_raphson_winkel_tripel(_x, _y, lon, lat, 0), do: {lon, lat}

  defp newton_raphson_winkel_tripel(x, y, lon, lat, iterations) do
    cos_lat = cos(lat)
    sin_lat = sin(lat)
    cos_half_lon = cos(lon / 2)
    sin_half_lon = sin(lon / 2)

    alpha = :math.acos(cos_lat * cos_half_lon)
    sinc_alpha = if alpha == 0, do: 1, else: sin(alpha) / alpha

    f1 = (lon + 2 * cos_lat * sin_half_lon / sinc_alpha) / 2 - x
    f2 = (lat + sin_lat / sinc_alpha) / 2 - y

    # Simplified Jacobian (approximate)
    d = 0.5

    new_lon = lon - f1 / d
    new_lat = lat - f2 / d

    # Clamp latitude
    new_lat = max(-:math.pi() / 2, min(:math.pi() / 2, new_lat))

    if abs(new_lon - lon) < 0.0001 and abs(new_lat - lat) < 0.0001 do
      {new_lon, new_lat}
    else
      newton_raphson_winkel_tripel(x, y, new_lon, new_lat, iterations - 1)
    end
  end

  # ============================================
  # Aitoff (pseudoazimuthal)
  # ============================================

  defp raw_project(:aitoff, lon, lat, _proj) do
    lon_rad = lon * @deg_to_rad
    lat_rad = lat * @deg_to_rad

    cos_lat = cos(lat_rad)
    alpha = :math.acos(cos_lat * cos(lon_rad / 2))
    sinc_alpha = if alpha == 0, do: 1, else: sin(alpha) / alpha

    x = 2 * cos_lat * sin(lon_rad / 2) / sinc_alpha
    y = sin(lat_rad) / sinc_alpha
    {x, y}
  end

  defp raw_invert(:aitoff, x, y, _proj) do
    # Newton-Raphson iteration
    {lon, lat} = newton_raphson_aitoff(x, y, x, y, 10)
    {lon * @rad_to_deg, lat * @rad_to_deg}
  end

  defp newton_raphson_aitoff(_x, _y, lon, lat, 0), do: {lon, lat}

  defp newton_raphson_aitoff(x, y, lon, lat, iterations) do
    cos_lat = cos(lat)
    sin_lat = sin(lat)
    half_lon = lon / 2
    cos_half_lon = cos(half_lon)
    sin_half_lon = sin(half_lon)

    alpha = :math.acos(cos_lat * cos_half_lon)
    sinc_alpha = if alpha == 0, do: 1, else: sin(alpha) / alpha

    f1 = 2 * cos_lat * sin_half_lon / sinc_alpha - x
    f2 = sin_lat / sinc_alpha - y

    new_lon = lon - f1 * 0.5
    new_lat = lat - f2 * 0.5
    new_lat = max(-:math.pi() / 2, min(:math.pi() / 2, new_lat))

    if abs(new_lon - lon) < 0.0001 and abs(new_lat - lat) < 0.0001 do
      {new_lon, new_lat}
    else
      newton_raphson_aitoff(x, y, new_lon, new_lat, iterations - 1)
    end
  end

  # ============================================
  # Miller Cylindrical
  # ============================================

  defp raw_project(:miller, lon, lat, _proj) do
    lon_rad = lon * @deg_to_rad
    lat_rad = lat * @deg_to_rad
    # Clamp latitude
    lat_rad = max(-1.4, min(1.4, lat_rad))

    x = lon_rad
    y = 1.25 * :math.log(:math.tan(:math.pi() / 4 + 0.4 * lat_rad))
    {x, y}
  end

  defp raw_invert(:miller, x, y, _proj) do
    lon = x * @rad_to_deg
    lat = 2.5 * (:math.atan(:math.exp(0.8 * y)) - :math.pi() / 4) * @rad_to_deg
    {lon, lat}
  end

  # ============================================
  # Gall-Peters (Cylindrical Equal-Area at 45°)
  # ============================================

  defp raw_project(:gall_peters, lon, lat, _proj) do
    lon_rad = lon * @deg_to_rad
    lat_rad = lat * @deg_to_rad

    # Standard parallel at 45°
    cos_phi = cos(45 * @deg_to_rad)
    x = lon_rad * cos_phi
    y = sin(lat_rad) / cos_phi
    {x, y}
  end

  defp raw_invert(:gall_peters, x, y, _proj) do
    cos_phi = cos(45 * @deg_to_rad)
    lon = x / cos_phi * @rad_to_deg
    lat = :math.asin(max(-1, min(1, y * cos_phi))) * @rad_to_deg
    {lon, lat}
  end

  # ============================================
  # Kavrayskiy VII (pseudocylindrical)
  # ============================================

  defp raw_project(:kavrayskiy7, lon, lat, _proj) do
    lon_rad = lon * @deg_to_rad
    lat_rad = lat * @deg_to_rad

    x = 3 * lon_rad / (2 * :math.pi()) * :math.sqrt(:math.pi() * :math.pi() / 3 - lat_rad * lat_rad)
    y = lat_rad
    {x, y}
  end

  defp raw_invert(:kavrayskiy7, x, y, _proj) do
    lat = y
    denom = :math.sqrt(:math.pi() * :math.pi() / 3 - lat * lat)
    lon = if denom > 0.001, do: 2 * :math.pi() * x / (3 * denom), else: 0
    {lon * @rad_to_deg, lat * @rad_to_deg}
  end

  # ============================================
  # Collignon (triangular pseudocylindrical)
  # ============================================

  @collignon_k :math.sqrt(:math.pi())

  defp raw_project(:collignon, lon, lat, _proj) do
    lon_rad = lon * @deg_to_rad
    lat_rad = lat * @deg_to_rad

    alpha = :math.sqrt(1 - sin(lat_rad))
    x = 2 / @collignon_k * lon_rad * alpha
    y = @collignon_k * (1 - alpha)
    {x, y}
  end

  defp raw_invert(:collignon, x, y, _proj) do
    alpha = 1 - y / @collignon_k
    lat = :math.asin(1 - alpha * alpha)
    lon = if alpha > 0.001, do: @collignon_k * x / (2 * alpha), else: 0
    {lon * @rad_to_deg, lat * @rad_to_deg}
  end

  # ============================================
  # Van der Grinten (polyconic, circular boundary)
  # ============================================

  defp raw_project(:van_der_grinten, lon, lat, _proj) do
    lon_rad = lon * @deg_to_rad
    lat_rad = lat * @deg_to_rad

    # Handle special cases
    cond do
      abs(lat_rad) < 0.001 ->
        {lon_rad, 0.0}

      abs(lon_rad) < 0.001 or abs(abs(lat_rad) - :math.pi() / 2) < 0.001 ->
        {0.0, :math.pi() * :math.tan(lat_rad / 2)}

      true ->
        abs_lat = abs(lat_rad)
        theta = :math.asin(2 * abs_lat / :math.pi())
        cos_theta = cos(theta)
        sin_theta = sin(theta)

        a = 0.5 * abs(:math.pi() / lon_rad - lon_rad / :math.pi())
        g = cos_theta / (sin_theta + cos_theta - 1)
        p = g * (2 / sin_theta - 1)
        q = a * a + g

        p2 = p * p
        a2 = a * a
        g2 = g * g

        x = :math.pi() * (a * (g - p2) + :math.sqrt(a2 * (g - p2) * (g - p2) - (p2 + a2) * (g2 - p2))) / (p2 + a2)
        x = if lon_rad < 0, do: -abs(x), else: abs(x)

        y = :math.pi() * abs(p * q - a * :math.sqrt((a2 + 1) * (p2 + a2) - q * q)) / (p2 + a2)
        y = if lat_rad < 0, do: -y, else: y

        {x, y}
    end
  end

  defp raw_invert(:van_der_grinten, x, y, _proj) do
    # Simplified inverse using Newton-Raphson
    {lon, lat} = newton_raphson_van_der_grinten(x, y, x, y / :math.pi(), 15)
    {lon * @rad_to_deg, lat * @rad_to_deg}
  end

  defp newton_raphson_van_der_grinten(_x, _y, lon, lat, 0), do: {lon, lat}

  defp newton_raphson_van_der_grinten(x, y, lon, lat, iterations) do
    {px, py} = raw_project(:van_der_grinten, lon * @rad_to_deg, lat * @rad_to_deg, nil)
    dx = x - px
    dy = y - py

    new_lon = lon + dx * 0.5
    new_lat = lat + dy * 0.3
    new_lat = max(-:math.pi() / 2 + 0.01, min(:math.pi() / 2 - 0.01, new_lat))

    if abs(dx) < 0.0001 and abs(dy) < 0.0001 do
      {new_lon, new_lat}
    else
      newton_raphson_van_der_grinten(x, y, new_lon, new_lat, iterations - 1)
    end
  end

  # ============================================
  # American Polyconic
  # ============================================

  defp raw_project(:polyconic, lon, lat, _proj) do
    lon_rad = lon * @deg_to_rad
    lat_rad = lat * @deg_to_rad

    if abs(lat_rad) < 0.001 do
      {lon_rad, 0.0}
    else
      cot_lat = 1 / :math.tan(lat_rad)
      e = lon_rad * sin(lat_rad)
      x = sin(e) * cot_lat
      y = lat_rad + (1 - cos(e)) * cot_lat
      {x, y}
    end
  end

  defp raw_invert(:polyconic, x, y, _proj) do
    if abs(y) < 0.001 do
      {x * @rad_to_deg, 0.0}
    else
      # Newton-Raphson iteration
      {lon, lat} = newton_raphson_polyconic(x, y, x, y, 15)
      {lon * @rad_to_deg, lat * @rad_to_deg}
    end
  end

  defp newton_raphson_polyconic(_x, _y, lon, lat, 0), do: {lon, lat}

  defp newton_raphson_polyconic(x, y, lon, lat, iterations) do
    lat = if abs(lat) < 0.001, do: 0.1, else: lat

    cot_lat = 1 / :math.tan(lat)
    e = lon * sin(lat)

    fx = sin(e) * cot_lat - x
    fy = lat + (1 - cos(e)) * cot_lat - y

    new_lon = lon - fx * 0.5
    new_lat = lat - fy * 0.5
    new_lat = max(-:math.pi() / 2 + 0.1, min(:math.pi() / 2 - 0.1, new_lat))

    if abs(fx) < 0.0001 and abs(fy) < 0.0001 do
      {new_lon, new_lat}
    else
      newton_raphson_polyconic(x, y, new_lon, new_lat, iterations - 1)
    end
  end

  # ============================================
  # Bonne (pseudoconic, heart-shaped)
  # ============================================

  defp raw_project(:bonne, lon, lat, proj) do
    {phi1, _phi2} = proj.parallels
    phi1_rad = phi1 * @deg_to_rad
    lon_rad = lon * @deg_to_rad
    lat_rad = lat * @deg_to_rad

    cot_phi1 = 1 / :math.tan(phi1_rad)
    rho = cot_phi1 + phi1_rad - lat_rad
    e = lon_rad * cos(lat_rad) / rho

    x = rho * sin(e)
    y = cot_phi1 - rho * cos(e)
    {x, y}
  end

  defp raw_invert(:bonne, x, y, proj) do
    {phi1, _phi2} = proj.parallels
    phi1_rad = phi1 * @deg_to_rad
    cot_phi1 = 1 / :math.tan(phi1_rad)

    rho = :math.sqrt(x * x + (cot_phi1 - y) * (cot_phi1 - y))
    rho = if phi1_rad < 0, do: -rho, else: rho

    lat = cot_phi1 + phi1_rad - rho
    lon = rho * :math.atan2(x, cot_phi1 - y) / cos(lat)

    {lon * @rad_to_deg, lat * @rad_to_deg}
  end

  # ============================================
  # Eckert I (rectilinear pseudocylindrical)
  # ============================================

  @eckert1_alpha :math.sqrt(8 / (3 * :math.pi()))

  defp raw_project(:eckert1, lon, lat, _proj) do
    lon_rad = lon * @deg_to_rad
    lat_rad = lat * @deg_to_rad

    x = @eckert1_alpha * lon_rad * (1 - abs(lat_rad) / :math.pi())
    y = @eckert1_alpha * lat_rad
    {x, y}
  end

  defp raw_invert(:eckert1, x, y, _proj) do
    lat = y / @eckert1_alpha
    lon = x / (@eckert1_alpha * (1 - abs(lat) / :math.pi()))
    {lon * @rad_to_deg, lat * @rad_to_deg}
  end

  # ============================================
  # Eckert II (equal-area pseudocylindrical)
  # ============================================

  @eckert2_k :math.sqrt(4 - 3 * :math.sin(1))

  defp raw_project(:eckert2, lon, lat, _proj) do
    lon_rad = lon * @deg_to_rad
    lat_rad = lat * @deg_to_rad

    s = :math.sqrt(4 - 3 * sin(abs(lat_rad)))
    x = 2 / :math.sqrt(6 * :math.pi()) * lon_rad * s
    y = :math.sqrt(2 * :math.pi() / 3) * (2 - s) * (if lat_rad < 0, do: -1, else: 1)
    {x, y}
  end

  defp raw_invert(:eckert2, x, y, _proj) do
    s = 2 - abs(y) / :math.sqrt(2 * :math.pi() / 3)
    lat = :math.asin((4 - s * s) / 3) * (if y < 0, do: -1, else: 1)
    lon = x / (2 / :math.sqrt(6 * :math.pi()) * s)
    {lon * @rad_to_deg, lat * @rad_to_deg}
  end

  # ============================================
  # Eckert III (pseudocylindrical)
  # ============================================

  @eckert3_k :math.sqrt(:math.pi() * (4 + :math.pi()))

  defp raw_project(:eckert3, lon, lat, _proj) do
    lon_rad = lon * @deg_to_rad
    lat_rad = lat * @deg_to_rad

    k = :math.sqrt(:math.pi() * (4 + :math.pi()))
    x = 2 / k * lon_rad * (1 + :math.sqrt(1 - 4 * lat_rad * lat_rad / (:math.pi() * :math.pi())))
    y = 4 / k * lat_rad
    {x, y}
  end

  defp raw_invert(:eckert3, x, y, _proj) do
    k = :math.sqrt(:math.pi() * (4 + :math.pi()))
    lat = k * y / 4
    lon = k * x / (2 * (1 + :math.sqrt(1 - 4 * lat * lat / (:math.pi() * :math.pi()))))
    {lon * @rad_to_deg, lat * @rad_to_deg}
  end

  # ============================================
  # Eckert V (pseudocylindrical)
  # ============================================

  defp raw_project(:eckert5, lon, lat, _proj) do
    lon_rad = lon * @deg_to_rad
    lat_rad = lat * @deg_to_rad

    k = :math.sqrt(2 + :math.pi())
    x = lon_rad * (1 + cos(lat_rad)) / k
    y = 2 * lat_rad / k
    {x, y}
  end

  defp raw_invert(:eckert5, x, y, _proj) do
    k = :math.sqrt(2 + :math.pi())
    lat = k * y / 2
    lon = k * x / (1 + cos(lat))
    {lon * @rad_to_deg, lat * @rad_to_deg}
  end

  # ============================================
  # Eckert VI (equal-area pseudocylindrical)
  # ============================================

  @eckert6_k :math.sqrt(2 + :math.pi())

  defp raw_project(:eckert6, lon, lat, _proj) do
    lon_rad = lon * @deg_to_rad
    lat_rad = lat * @deg_to_rad

    # Solve for theta using Newton-Raphson
    theta = newton_raphson_eckert6(lat_rad, lat_rad, 10)

    x = lon_rad * (1 + cos(theta)) / @eckert6_k
    y = 2 * theta / @eckert6_k
    {x, y}
  end

  defp raw_invert(:eckert6, x, y, _proj) do
    theta = @eckert6_k * y / 2
    lat = :math.asin((theta + sin(theta)) / (1 + :math.pi() / 2))
    lon = @eckert6_k * x / (1 + cos(theta))
    {lon * @rad_to_deg, lat * @rad_to_deg}
  end

  defp newton_raphson_eckert6(_phi, theta, 0), do: theta

  defp newton_raphson_eckert6(phi, theta, iterations) do
    f = theta + sin(theta) - (1 + :math.pi() / 2) * sin(phi)
    df = 1 + cos(theta)
    df = if abs(df) < 0.001, do: 0.001, else: df

    new_theta = theta - f / df

    if abs(new_theta - theta) < 0.0001 do
      new_theta
    else
      newton_raphson_eckert6(phi, new_theta, iterations - 1)
    end
  end

  # ============================================
  # Wagner IV (equal-area pseudocylindrical)
  # ============================================

  @wagner4_cx 0.86310
  @wagner4_cy 1.56548

  defp raw_project(:wagner4, lon, lat, _proj) do
    lon_rad = lon * @deg_to_rad
    lat_rad = lat * @deg_to_rad

    # Solve for theta
    theta = newton_raphson_wagner4(lat_rad, lat_rad, 10)

    x = @wagner4_cx * lon_rad * cos(theta)
    y = @wagner4_cy * sin(theta)
    {x, y}
  end

  defp raw_invert(:wagner4, x, y, _proj) do
    theta = :math.asin(y / @wagner4_cy)
    lat = :math.asin((2 * theta + sin(2 * theta)) / :math.pi())
    lon = x / (@wagner4_cx * cos(theta))
    {lon * @rad_to_deg, lat * @rad_to_deg}
  end

  defp newton_raphson_wagner4(_phi, theta, 0), do: theta

  defp newton_raphson_wagner4(phi, theta, iterations) do
    s = sin(phi) * :math.pi()
    f = 2 * theta + sin(2 * theta) - s
    df = 2 + 2 * cos(2 * theta)
    df = if abs(df) < 0.001, do: 0.001, else: df

    new_theta = theta - f / df

    if abs(new_theta - theta) < 0.0001 do
      new_theta
    else
      newton_raphson_wagner4(phi, new_theta, iterations - 1)
    end
  end

  # ============================================
  # Wagner VI (compromise pseudocylindrical)
  # ============================================

  @wagner6_cx :math.sqrt(8 / 3) / 2
  @wagner6_cy :math.sqrt(8 / 3)

  defp raw_project(:wagner6, lon, lat, _proj) do
    lon_rad = lon * @deg_to_rad
    lat_rad = lat * @deg_to_rad

    x = @wagner6_cx * lon_rad * :math.sqrt(1 - 3 * lat_rad * lat_rad / (:math.pi() * :math.pi()))
    y = @wagner6_cy * lat_rad
    {x, y}
  end

  defp raw_invert(:wagner6, x, y, _proj) do
    lat = y / @wagner6_cy
    denom = :math.sqrt(1 - 3 * lat * lat / (:math.pi() * :math.pi()))
    lon = if denom > 0.001, do: x / (@wagner6_cx * denom), else: 0
    {lon * @rad_to_deg, lat * @rad_to_deg}
  end

  # ============================================
  # Fahey (pseudocylindrical)
  # ============================================

  defp raw_project(:fahey, lon, lat, _proj) do
    lon_rad = lon * @deg_to_rad
    lat_rad = lat * @deg_to_rad

    t = :math.tan(lat_rad / 2)
    x = lon_rad * (1 - t * t)
    y = (1 + cos(lat_rad) / cos(lat_rad / 2)) * t
    {x, y}
  end

  defp raw_invert(:fahey, x, y, _proj) do
    # Newton-Raphson iteration
    {lon, lat} = newton_raphson_fahey(x, y, x, :math.atan(y) * 2, 10)
    {lon * @rad_to_deg, lat * @rad_to_deg}
  end

  defp newton_raphson_fahey(_x, _y, lon, lat, 0), do: {lon, lat}

  defp newton_raphson_fahey(x, y, lon, lat, iterations) do
    t = :math.tan(lat / 2)
    cos_lat = cos(lat)
    cos_half = cos(lat / 2)

    fx = lon * (1 - t * t) - x
    fy = (1 + cos_lat / cos_half) * t - y

    new_lon = lon - fx * 0.5
    new_lat = lat - fy * 0.3
    new_lat = max(-:math.pi() / 2 + 0.1, min(:math.pi() / 2 - 0.1, new_lat))

    if abs(fx) < 0.0001 and abs(fy) < 0.0001 do
      {new_lon, new_lat}
    else
      newton_raphson_fahey(x, y, new_lon, new_lat, iterations - 1)
    end
  end

  # ============================================
  # Loximuthal (rhumb lines are straight)
  # ============================================

  defp raw_project(:loximuthal, lon, lat, proj) do
    {phi0, _} = proj.parallels
    phi0_rad = phi0 * @deg_to_rad
    lon_rad = lon * @deg_to_rad
    lat_rad = lat * @deg_to_rad

    delta = lat_rad - phi0_rad

    if abs(delta) < 0.001 do
      {lon_rad * cos(phi0_rad), delta}
    else
      x = lon_rad * delta / :math.log(:math.tan(:math.pi() / 4 + lat_rad / 2) / :math.tan(:math.pi() / 4 + phi0_rad / 2))
      y = delta
      {x, y}
    end
  end

  defp raw_invert(:loximuthal, x, y, proj) do
    {phi0, _} = proj.parallels
    phi0_rad = phi0 * @deg_to_rad

    lat = y + phi0_rad

    if abs(y) < 0.001 do
      lon = x / cos(phi0_rad)
      {lon * @rad_to_deg, lat * @rad_to_deg}
    else
      lon = x * :math.log(:math.tan(:math.pi() / 4 + lat / 2) / :math.tan(:math.pi() / 4 + phi0_rad / 2)) / y
      {lon * @rad_to_deg, lat * @rad_to_deg}
    end
  end

  # ============================================
  # Rotation Helpers
  # ============================================

  defp apply_rotation(lon, lat, {0, 0, 0}), do: {lon, lat}

  defp apply_rotation(lon, lat, {lambda, phi, gamma}) do
    # Convert to radians
    lon_rad = lon * @deg_to_rad
    lat_rad = lat * @deg_to_rad
    lambda_rad = -lambda * @deg_to_rad
    phi_rad = -phi * @deg_to_rad
    gamma_rad = -gamma * @deg_to_rad

    # Apply rotation (simplified - just lambda for now for performance)
    lon_rad = lon_rad + lambda_rad

    # If phi or gamma are set, need full spherical rotation
    {lon_rad, lat_rad} =
      if phi != 0 or gamma != 0 do
        spherical_rotate(lon_rad, lat_rad, phi_rad, gamma_rad)
      else
        {lon_rad, lat_rad}
      end

    # Normalize longitude to [-180, 180]
    lon = lon_rad * @rad_to_deg
    lon = normalize_longitude(lon)

    {lon, lat_rad * @rad_to_deg}
  end

  defp apply_inverse_rotation(lon, lat, {0, 0, 0}), do: {lon, lat}

  defp apply_inverse_rotation(lon, lat, {lambda, phi, gamma}) do
    lon_rad = lon * @deg_to_rad
    lat_rad = lat * @deg_to_rad

    # Reverse the rotation
    {lon_rad, lat_rad} =
      if phi != 0 or gamma != 0 do
        spherical_rotate(lon_rad, lat_rad, phi * @deg_to_rad, gamma * @deg_to_rad)
      else
        {lon_rad, lat_rad}
      end

    lon_rad = lon_rad - (-lambda * @deg_to_rad)

    {normalize_longitude(lon_rad * @rad_to_deg), lat_rad * @rad_to_deg}
  end

  defp spherical_rotate(lon, lat, phi, gamma) do
    cos_lat = cos(lat)
    x = cos_lat * cos(lon)
    y = cos_lat * sin(lon)
    z = sin(lat)

    # Rotate around x-axis (phi)
    cos_phi = cos(phi)
    sin_phi = sin(phi)
    y1 = y * cos_phi - z * sin_phi
    z1 = y * sin_phi + z * cos_phi

    # Rotate around z-axis (gamma)
    cos_gamma = cos(gamma)
    sin_gamma = sin(gamma)
    x2 = x * cos_gamma - y1 * sin_gamma
    y2 = x * sin_gamma + y1 * cos_gamma

    new_lon = :math.atan2(y2, x2)
    new_lat = :math.asin(max(-1, min(1, z1)))

    {new_lon, new_lat}
  end

  defp normalize_longitude(lon) when lon > 180, do: normalize_longitude(lon - 360)
  defp normalize_longitude(lon) when lon < -180, do: normalize_longitude(lon + 360)
  defp normalize_longitude(lon), do: lon

  defp clipped?(_, _, _), do: false

  defp sin(x), do: :math.sin(x)
  defp cos(x), do: :math.cos(x)
end
