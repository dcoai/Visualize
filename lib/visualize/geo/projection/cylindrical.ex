defmodule Visualize.Geo.Projection.Cylindrical do
  @moduledoc """
  Cylindrical projections: Mercator, transverse Mercator, equirectangular, Lambert cylindrical equal-area, Miller and Gall-Peters.

  Raw projection maths, reached through `Visualize.Geo.Projection.project/3` and
  `invert/3`. `project/4` takes longitude and latitude in degrees, already rotated and
  centred, and returns unit-scale planar coordinates; `invert/4` is its inverse. Scale,
  translation and rotation are applied by the parent module.
  """

  @deg_to_rad :math.pi() / 180
  @rad_to_deg 180 / :math.pi()

  @doc false
  def project(:mercator, lon, lat, proj), do: mercator_project(lon, lat, proj)
  def project(:equirectangular, lon, lat, proj), do: equirectangular_project(lon, lat, proj)

  def project(:transverse_mercator, lon, lat, proj),
    do: transverse_mercator_project(lon, lat, proj)

  def project(:cylindrical_equal_area, lon, lat, proj),
    do: cylindrical_equal_area_project(lon, lat, proj)

  def project(:miller, lon, lat, proj), do: miller_project(lon, lat, proj)
  def project(:gall_peters, lon, lat, proj), do: gall_peters_project(lon, lat, proj)

  @doc false
  def invert(:mercator, x, y, proj), do: mercator_invert(x, y, proj)
  def invert(:equirectangular, x, y, proj), do: equirectangular_invert(x, y, proj)
  def invert(:transverse_mercator, x, y, proj), do: transverse_mercator_invert(x, y, proj)
  def invert(:cylindrical_equal_area, x, y, proj), do: cylindrical_equal_area_invert(x, y, proj)
  def invert(:miller, x, y, proj), do: miller_invert(x, y, proj)
  def invert(:gall_peters, x, y, proj), do: gall_peters_invert(x, y, proj)

  # Mercator
  defp mercator_project(lon, lat, _proj) do
    lat_rad = lat * @deg_to_rad
    # Clamp latitude to avoid infinity
    lat_rad = max(-1.4844, min(1.4844, lat_rad))
    x = lon * @deg_to_rad
    y = :math.log(:math.tan(:math.pi() / 4 + lat_rad / 2))
    {x, y}
  end

  defp mercator_invert(x, y, _proj) do
    lon = x * @rad_to_deg
    lat = (2 * :math.atan(:math.exp(y)) - :math.pi() / 2) * @rad_to_deg
    {lon, lat}
  end

  # Equirectangular (Plate Carrée)
  defp equirectangular_project(lon, lat, _proj) do
    {lon * @deg_to_rad, lat * @deg_to_rad}
  end

  defp equirectangular_invert(x, y, _proj) do
    {x * @rad_to_deg, y * @rad_to_deg}
  end

  # Transverse Mercator (UTM)

  defp transverse_mercator_project(lon, lat, _proj) do
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

  defp transverse_mercator_invert(x, y, _proj) do
    sinh_x = (:math.exp(x) - :math.exp(-x)) / 2
    cos_y = cos(y)
    sin_y = sin(y)

    lon = :math.atan2(sinh_x, cos_y)
    lat = :math.asin(sin_y / :math.sqrt(sinh_x * sinh_x + cos_y * cos_y))
    {lon * @rad_to_deg, lat * @rad_to_deg}
  end

  # Cylindrical Equal Area (Lambert)

  defp cylindrical_equal_area_project(lon, lat, _proj) do
    lon_rad = lon * @deg_to_rad
    lat_rad = lat * @deg_to_rad
    {lon_rad, sin(lat_rad)}
  end

  defp cylindrical_equal_area_invert(x, y, _proj) do
    lon = x * @rad_to_deg
    lat = :math.asin(max(-1, min(1, y))) * @rad_to_deg
    {lon, lat}
  end

  # Miller Cylindrical

  defp miller_project(lon, lat, _proj) do
    lon_rad = lon * @deg_to_rad
    lat_rad = lat * @deg_to_rad
    # Clamp latitude
    lat_rad = max(-1.4, min(1.4, lat_rad))

    x = lon_rad
    y = 1.25 * :math.log(:math.tan(:math.pi() / 4 + 0.4 * lat_rad))
    {x, y}
  end

  defp miller_invert(x, y, _proj) do
    lon = x * @rad_to_deg
    lat = 2.5 * (:math.atan(:math.exp(0.8 * y)) - :math.pi() / 4) * @rad_to_deg
    {lon, lat}
  end

  # Gall-Peters (Cylindrical Equal-Area at 45°)

  defp gall_peters_project(lon, lat, _proj) do
    lon_rad = lon * @deg_to_rad
    lat_rad = lat * @deg_to_rad

    # Standard parallel at 45°
    cos_phi = cos(45 * @deg_to_rad)
    x = lon_rad * cos_phi
    y = sin(lat_rad) / cos_phi
    {x, y}
  end

  defp gall_peters_invert(x, y, _proj) do
    cos_phi = cos(45 * @deg_to_rad)
    lon = x / cos_phi * @rad_to_deg
    lat = :math.asin(max(-1, min(1, y * cos_phi))) * @rad_to_deg
    {lon, lat}
  end

  defp sin(x), do: :math.sin(x)
  defp cos(x), do: :math.cos(x)
end
