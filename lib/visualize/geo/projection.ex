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
      case family(proj.type).project(proj.type, lon, lat, proj) do
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

    lon_rad = lon_rad - -lambda * @deg_to_rad

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
