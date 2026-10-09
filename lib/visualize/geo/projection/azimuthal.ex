defmodule Visualize.Geo.Projection.Azimuthal do
  @moduledoc """
  Azimuthal projections: orthographic, stereographic, gnomonic, Lambert azimuthal equal-area and azimuthal equidistant.

  Raw projection maths, reached through `Visualize.Geo.Projection.project/3` and
  `invert/3`. `project/4` takes longitude and latitude in degrees, already rotated and
  centred, and returns unit-scale planar coordinates; `invert/4` is its inverse. Scale,
  translation and rotation are applied by the parent module.
  """

  @deg_to_rad :math.pi() / 180
  @rad_to_deg 180 / :math.pi()

  @doc false
  def project(:orthographic, lon, lat, proj), do: orthographic_project(lon, lat, proj)
  def project(:stereographic, lon, lat, proj), do: stereographic_project(lon, lat, proj)

  def project(:azimuthal_equal_area, lon, lat, proj),
    do: azimuthal_equal_area_project(lon, lat, proj)

  def project(:azimuthal_equidistant, lon, lat, proj),
    do: azimuthal_equidistant_project(lon, lat, proj)

  def project(:gnomonic, lon, lat, proj), do: gnomonic_project(lon, lat, proj)

  @doc false
  def invert(:orthographic, x, y, proj), do: orthographic_invert(x, y, proj)
  def invert(:stereographic, x, y, proj), do: stereographic_invert(x, y, proj)
  def invert(:azimuthal_equal_area, x, y, proj), do: azimuthal_equal_area_invert(x, y, proj)
  def invert(:azimuthal_equidistant, x, y, proj), do: azimuthal_equidistant_invert(x, y, proj)
  def invert(:gnomonic, x, y, proj), do: gnomonic_invert(x, y, proj)

  # Orthographic (globe): d3-geo's `orthographicRaw` (orthographic.js:4–6), which places
  # the far hemisphere too, folded onto the near one. The clip angle hides it (spec/07
  # §1.5, §2.2.1): the horizon the clip closes a path along lies a hair past 90°.
  defp orthographic_project(lon, lat, _proj) do
    lon_rad = lon * @deg_to_rad
    lat_rad = lat * @deg_to_rad
    {:math.cos(lat_rad) * :math.sin(lon_rad), :math.sin(lat_rad)}
  end

  defp orthographic_invert(x, y, _proj) do
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
  defp stereographic_project(lon, lat, _proj) do
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

  defp stereographic_invert(x, y, _proj) do
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
  defp azimuthal_equal_area_project(lon, lat, _proj) do
    lon_rad = lon * @deg_to_rad
    lat_rad = lat * @deg_to_rad

    cos_lat = :math.cos(lat_rad)
    cos_lon = :math.cos(lon_rad)
    k_prime = 1 + cos_lat * cos_lon

    # Only the antipode itself has no place (d3-geo's azimuthalEqualAreaRaw carries NaN
    # there): the clip circle 10⁻³° short of it is placed on the map's rim (spec/07 §1.5).
    if k_prime <= 0 do
      nil
    else
      k = :math.sqrt(2 / k_prime)
      x = k * cos_lat * :math.sin(lon_rad)
      y = k * :math.sin(lat_rad)
      {x, y}
    end
  end

  defp azimuthal_equal_area_invert(x, y, _proj) do
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
  defp azimuthal_equidistant_project(lon, lat, _proj) do
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

  defp azimuthal_equidistant_invert(x, y, _proj) do
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

  # Gnomonic (great circles as straight lines)

  defp gnomonic_project(lon, lat, _proj) do
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

  defp gnomonic_invert(x, y, _proj) do
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

  defp sin(x), do: :math.sin(x)
  defp cos(x), do: :math.cos(x)
end
