defmodule Visualize.Geo.Projection.Conic do
  @moduledoc """
  Conic and pseudoconic projections: Albers, Lambert conformal conic, conic equal-area, conic equidistant, American polyconic and Bonne.

  Raw projection maths, reached through `Visualize.Geo.Projection.project/3` and
  `invert/3`. `project/4` takes longitude and latitude in degrees, already rotated and
  centred, and returns unit-scale planar coordinates; `invert/4` is its inverse. Scale,
  translation and rotation are applied by the parent module.
  """

  @deg_to_rad :math.pi() / 180
  @rad_to_deg 180 / :math.pi()

  @doc false
  def project(:albers, lon, lat, proj), do: albers_project(lon, lat, proj)
  def project(:conic_conformal, lon, lat, proj), do: conic_conformal_project(lon, lat, proj)
  def project(:conic_equal_area, lon, lat, proj), do: conic_equal_area_project(lon, lat, proj)
  def project(:conic_equidistant, lon, lat, proj), do: conic_equidistant_project(lon, lat, proj)
  def project(:polyconic, lon, lat, proj), do: polyconic_project(lon, lat, proj)
  def project(:bonne, lon, lat, proj), do: bonne_project(lon, lat, proj)

  @doc false
  def invert(:albers, x, y, proj), do: albers_invert(x, y, proj)
  def invert(:conic_conformal, x, y, proj), do: conic_conformal_invert(x, y, proj)
  def invert(:conic_equal_area, x, y, proj), do: conic_equal_area_invert(x, y, proj)
  def invert(:conic_equidistant, x, y, proj), do: conic_equidistant_invert(x, y, proj)
  def invert(:polyconic, x, y, proj), do: polyconic_invert(x, y, proj)
  def invert(:bonne, x, y, proj), do: bonne_invert(x, y, proj)

  # Albers Equal-Area Conic
  defp albers_project(lon, lat, proj) do
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

  defp albers_invert(x, y, proj) do
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
  defp conic_conformal_project(lon, lat, proj) do
    {phi1, phi2} = proj.parallels
    phi1_rad = phi1 * @deg_to_rad
    phi2_rad = phi2 * @deg_to_rad

    n =
      if abs(phi1_rad - phi2_rad) < 0.001 do
        sin(phi1_rad)
      else
        :math.log(cos(phi1_rad) / cos(phi2_rad)) /
          :math.log(
            :math.tan(:math.pi() / 4 + phi2_rad / 2) / :math.tan(:math.pi() / 4 + phi1_rad / 2)
          )
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

  defp conic_conformal_invert(x, y, proj) do
    {phi1, phi2} = proj.parallels
    phi1_rad = phi1 * @deg_to_rad
    phi2_rad = phi2 * @deg_to_rad

    n =
      if abs(phi1_rad - phi2_rad) < 0.001 do
        sin(phi1_rad)
      else
        :math.log(cos(phi1_rad) / cos(phi2_rad)) /
          :math.log(
            :math.tan(:math.pi() / 4 + phi2_rad / 2) / :math.tan(:math.pi() / 4 + phi1_rad / 2)
          )
      end

    f = cos(phi1_rad) * :math.pow(:math.tan(:math.pi() / 4 + phi1_rad / 2), n) / n
    rho0 = f

    rho = :math.sqrt(x * x + (rho0 - y) * (rho0 - y))
    rho = if n < 0, do: -rho, else: rho

    lon = :math.atan2(x, rho0 - y) / n
    lat = 2 * :math.atan(:math.pow(f / rho, 1 / n)) - :math.pi() / 2

    {lon * @rad_to_deg, lat * @rad_to_deg}
  end

  # Conic Equal Area

  defp conic_equal_area_project(lon, lat, proj) do
    # Same as Albers (Albers is a conic equal-area projection)
    albers_project(lon, lat, proj)
  end

  defp conic_equal_area_invert(x, y, proj) do
    albers_invert(x, y, proj)
  end

  # Conic Equidistant

  defp conic_equidistant_project(lon, lat, proj) do
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

  defp conic_equidistant_invert(x, y, proj) do
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

  # American Polyconic

  defp polyconic_project(lon, lat, _proj) do
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

  defp polyconic_invert(x, y, _proj) do
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

  # Bonne (pseudoconic, heart-shaped)

  defp bonne_project(lon, lat, proj) do
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

  defp bonne_invert(x, y, proj) do
    {phi1, _phi2} = proj.parallels
    phi1_rad = phi1 * @deg_to_rad
    cot_phi1 = 1 / :math.tan(phi1_rad)

    rho = :math.sqrt(x * x + (cot_phi1 - y) * (cot_phi1 - y))
    rho = if phi1_rad < 0, do: -rho, else: rho

    lat = cot_phi1 + phi1_rad - rho
    lon = rho * :math.atan2(x, cot_phi1 - y) / cos(lat)

    {lon * @rad_to_deg, lat * @rad_to_deg}
  end

  defp sin(x), do: :math.sin(x)
  defp cos(x), do: :math.cos(x)
end
