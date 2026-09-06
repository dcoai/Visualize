defmodule Visualize.Geo.Projection.Pseudocylindrical do
  @moduledoc """
  Pseudocylindrical projections: Mollweide, sinusoidal, Eckert I-VI, Hammer, Kavrayskiy VII, Wagner IV and VI, Fahey, Collignon and loximuthal.

  Raw projection maths, reached through `Visualize.Geo.Projection.project/3` and
  `invert/3`. `project/4` takes longitude and latitude in degrees, already rotated and
  centred, and returns unit-scale planar coordinates; `invert/4` is its inverse. Scale,
  translation and rotation are applied by the parent module.
  """

  @deg_to_rad :math.pi() / 180
  @rad_to_deg 180 / :math.pi()
  @sqrt2 :math.sqrt(2)

  @doc false
  def project(:mollweide, lon, lat, proj), do: mollweide_project(lon, lat, proj)
  def project(:sinusoidal, lon, lat, proj), do: sinusoidal_project(lon, lat, proj)
  def project(:eckert4, lon, lat, proj), do: eckert4_project(lon, lat, proj)
  def project(:hammer, lon, lat, proj), do: hammer_project(lon, lat, proj)
  def project(:kavrayskiy7, lon, lat, proj), do: kavrayskiy7_project(lon, lat, proj)
  def project(:collignon, lon, lat, proj), do: collignon_project(lon, lat, proj)
  def project(:eckert1, lon, lat, proj), do: eckert1_project(lon, lat, proj)
  def project(:eckert2, lon, lat, proj), do: eckert2_project(lon, lat, proj)
  def project(:eckert3, lon, lat, proj), do: eckert3_project(lon, lat, proj)
  def project(:eckert5, lon, lat, proj), do: eckert5_project(lon, lat, proj)
  def project(:eckert6, lon, lat, proj), do: eckert6_project(lon, lat, proj)
  def project(:wagner4, lon, lat, proj), do: wagner4_project(lon, lat, proj)
  def project(:wagner6, lon, lat, proj), do: wagner6_project(lon, lat, proj)
  def project(:fahey, lon, lat, proj), do: fahey_project(lon, lat, proj)
  def project(:loximuthal, lon, lat, proj), do: loximuthal_project(lon, lat, proj)

  @doc false
  def invert(:mollweide, x, y, proj), do: mollweide_invert(x, y, proj)
  def invert(:sinusoidal, x, y, proj), do: sinusoidal_invert(x, y, proj)
  def invert(:eckert4, x, y, proj), do: eckert4_invert(x, y, proj)
  def invert(:hammer, x, y, proj), do: hammer_invert(x, y, proj)
  def invert(:kavrayskiy7, x, y, proj), do: kavrayskiy7_invert(x, y, proj)
  def invert(:collignon, x, y, proj), do: collignon_invert(x, y, proj)
  def invert(:eckert1, x, y, proj), do: eckert1_invert(x, y, proj)
  def invert(:eckert2, x, y, proj), do: eckert2_invert(x, y, proj)
  def invert(:eckert3, x, y, proj), do: eckert3_invert(x, y, proj)
  def invert(:eckert5, x, y, proj), do: eckert5_invert(x, y, proj)
  def invert(:eckert6, x, y, proj), do: eckert6_invert(x, y, proj)
  def invert(:wagner4, x, y, proj), do: wagner4_invert(x, y, proj)
  def invert(:wagner6, x, y, proj), do: wagner6_invert(x, y, proj)
  def invert(:fahey, x, y, proj), do: fahey_invert(x, y, proj)
  def invert(:loximuthal, x, y, proj), do: loximuthal_invert(x, y, proj)

  # Mollweide (pseudocylindrical equal-area)

  @sqrt2 :math.sqrt(2)

  defp mollweide_project(lon, lat, _proj) do
    lon_rad = lon * @deg_to_rad
    lat_rad = lat * @deg_to_rad

    # Solve for theta using Newton-Raphson
    theta = newton_raphson_mollweide(lat_rad, lat_rad, 10)

    x = 2 * @sqrt2 / :math.pi() * lon_rad * cos(theta)
    y = @sqrt2 * sin(theta)
    {x, y}
  end

  defp mollweide_invert(x, y, _proj) do
    theta = :math.asin(y / @sqrt2)
    lat = :math.asin((2 * theta + sin(2 * theta)) / :math.pi())
    lon = :math.pi() * x / (2 * @sqrt2 * cos(theta))
    {lon * @rad_to_deg, lat * @rad_to_deg}
  end

  defp newton_raphson_mollweide(_phi, theta, 0), do: theta

  defp newton_raphson_mollweide(phi, theta, iterations) do
    f = 2 * theta + sin(2 * theta) - :math.pi() * sin(phi)
    df = 2 + 2 * cos(2 * theta)

    new_theta = theta - f / df

    if abs(new_theta - theta) < 0.0001 do
      new_theta
    else
      newton_raphson_mollweide(phi, new_theta, iterations - 1)
    end
  end

  # Sinusoidal (pseudocylindrical equal-area)

  defp sinusoidal_project(lon, lat, _proj) do
    lon_rad = lon * @deg_to_rad
    lat_rad = lat * @deg_to_rad
    {lon_rad * cos(lat_rad), lat_rad}
  end

  defp sinusoidal_invert(x, y, _proj) do
    lat = y
    lon = if abs(cos(lat)) > 0.001, do: x / cos(lat), else: 0
    {lon * @rad_to_deg, lat * @rad_to_deg}
  end

  # Eckert IV (pseudocylindrical equal-area)

  @eckert4_cx 2 / :math.sqrt(:math.pi() * (4 + :math.pi()))
  @eckert4_cy 2 * :math.sqrt(:math.pi() / (4 + :math.pi()))
  @eckert4_c 2 + :math.pi() / 2

  defp eckert4_project(lon, lat, _proj) do
    lon_rad = lon * @deg_to_rad
    lat_rad = lat * @deg_to_rad

    # Solve for theta using Newton-Raphson
    theta = newton_raphson_eckert4(lat_rad, lat_rad / 2, 10)

    x = @eckert4_cx * lon_rad * (1 + cos(theta))
    y = @eckert4_cy * sin(theta)
    {x, y}
  end

  defp eckert4_invert(x, y, _proj) do
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

  # Hammer (Hammer-Aitoff, equal-area)

  defp hammer_project(lon, lat, _proj) do
    lon_rad = lon * @deg_to_rad
    lat_rad = lat * @deg_to_rad

    cos_lat = cos(lat_rad)
    d = :math.sqrt(1 + cos_lat * cos(lon_rad / 2))

    x = 2 * @sqrt2 * cos_lat * sin(lon_rad / 2) / d
    y = @sqrt2 * sin(lat_rad) / d
    {x, y}
  end

  defp hammer_invert(x, y, _proj) do
    z = :math.sqrt(1 - x / 4 * (x / 4) - y / 2 * (y / 2))
    lon = 2 * :math.atan2(z * x, 2 * (2 * z * z - 1))
    lat = :math.asin(z * y)
    {lon * @rad_to_deg, lat * @rad_to_deg}
  end

  # Kavrayskiy VII (pseudocylindrical)

  defp kavrayskiy7_project(lon, lat, _proj) do
    lon_rad = lon * @deg_to_rad
    lat_rad = lat * @deg_to_rad

    x =
      3 * lon_rad / (2 * :math.pi()) * :math.sqrt(:math.pi() * :math.pi() / 3 - lat_rad * lat_rad)

    y = lat_rad
    {x, y}
  end

  defp kavrayskiy7_invert(x, y, _proj) do
    lat = y
    denom = :math.sqrt(:math.pi() * :math.pi() / 3 - lat * lat)
    lon = if denom > 0.001, do: 2 * :math.pi() * x / (3 * denom), else: 0
    {lon * @rad_to_deg, lat * @rad_to_deg}
  end

  # Collignon (triangular pseudocylindrical)

  @collignon_k :math.sqrt(:math.pi())

  defp collignon_project(lon, lat, _proj) do
    lon_rad = lon * @deg_to_rad
    lat_rad = lat * @deg_to_rad

    alpha = :math.sqrt(1 - sin(lat_rad))
    x = 2 / @collignon_k * lon_rad * alpha
    y = @collignon_k * (1 - alpha)
    {x, y}
  end

  defp collignon_invert(x, y, _proj) do
    alpha = 1 - y / @collignon_k
    lat = :math.asin(1 - alpha * alpha)
    lon = if alpha > 0.001, do: @collignon_k * x / (2 * alpha), else: 0
    {lon * @rad_to_deg, lat * @rad_to_deg}
  end

  # Eckert I (rectilinear pseudocylindrical)

  @eckert1_alpha :math.sqrt(8 / (3 * :math.pi()))

  defp eckert1_project(lon, lat, _proj) do
    lon_rad = lon * @deg_to_rad
    lat_rad = lat * @deg_to_rad

    x = @eckert1_alpha * lon_rad * (1 - abs(lat_rad) / :math.pi())
    y = @eckert1_alpha * lat_rad
    {x, y}
  end

  defp eckert1_invert(x, y, _proj) do
    lat = y / @eckert1_alpha
    lon = x / (@eckert1_alpha * (1 - abs(lat) / :math.pi()))
    {lon * @rad_to_deg, lat * @rad_to_deg}
  end

  # Eckert II (equal-area pseudocylindrical)

  defp eckert2_project(lon, lat, _proj) do
    lon_rad = lon * @deg_to_rad
    lat_rad = lat * @deg_to_rad

    s = :math.sqrt(4 - 3 * sin(abs(lat_rad)))
    x = 2 / :math.sqrt(6 * :math.pi()) * lon_rad * s
    y = :math.sqrt(2 * :math.pi() / 3) * (2 - s) * if lat_rad < 0, do: -1, else: 1
    {x, y}
  end

  defp eckert2_invert(x, y, _proj) do
    s = 2 - abs(y) / :math.sqrt(2 * :math.pi() / 3)
    lat = :math.asin((4 - s * s) / 3) * if y < 0, do: -1, else: 1
    lon = x / (2 / :math.sqrt(6 * :math.pi()) * s)
    {lon * @rad_to_deg, lat * @rad_to_deg}
  end

  # Eckert III (pseudocylindrical)

  defp eckert3_project(lon, lat, _proj) do
    lon_rad = lon * @deg_to_rad
    lat_rad = lat * @deg_to_rad

    k = :math.sqrt(:math.pi() * (4 + :math.pi()))
    x = 2 / k * lon_rad * (1 + :math.sqrt(1 - 4 * lat_rad * lat_rad / (:math.pi() * :math.pi())))
    y = 4 / k * lat_rad
    {x, y}
  end

  defp eckert3_invert(x, y, _proj) do
    k = :math.sqrt(:math.pi() * (4 + :math.pi()))
    lat = k * y / 4
    lon = k * x / (2 * (1 + :math.sqrt(1 - 4 * lat * lat / (:math.pi() * :math.pi()))))
    {lon * @rad_to_deg, lat * @rad_to_deg}
  end

  # Eckert V (pseudocylindrical)

  defp eckert5_project(lon, lat, _proj) do
    lon_rad = lon * @deg_to_rad
    lat_rad = lat * @deg_to_rad

    k = :math.sqrt(2 + :math.pi())
    x = lon_rad * (1 + cos(lat_rad)) / k
    y = 2 * lat_rad / k
    {x, y}
  end

  defp eckert5_invert(x, y, _proj) do
    k = :math.sqrt(2 + :math.pi())
    lat = k * y / 2
    lon = k * x / (1 + cos(lat))
    {lon * @rad_to_deg, lat * @rad_to_deg}
  end

  # Eckert VI (equal-area pseudocylindrical)

  @eckert6_k :math.sqrt(2 + :math.pi())

  defp eckert6_project(lon, lat, _proj) do
    lon_rad = lon * @deg_to_rad
    lat_rad = lat * @deg_to_rad

    # Solve for theta using Newton-Raphson
    theta = newton_raphson_eckert6(lat_rad, lat_rad, 10)

    x = lon_rad * (1 + cos(theta)) / @eckert6_k
    y = 2 * theta / @eckert6_k
    {x, y}
  end

  defp eckert6_invert(x, y, _proj) do
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

  # Wagner IV (equal-area pseudocylindrical)

  @wagner4_cx 0.86310
  @wagner4_cy 1.56548

  defp wagner4_project(lon, lat, _proj) do
    lon_rad = lon * @deg_to_rad
    lat_rad = lat * @deg_to_rad

    # Solve for theta
    theta = newton_raphson_wagner4(lat_rad, lat_rad, 10)

    x = @wagner4_cx * lon_rad * cos(theta)
    y = @wagner4_cy * sin(theta)
    {x, y}
  end

  defp wagner4_invert(x, y, _proj) do
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

  # Wagner VI (compromise pseudocylindrical)

  @wagner6_cx :math.sqrt(8 / 3) / 2
  @wagner6_cy :math.sqrt(8 / 3)

  defp wagner6_project(lon, lat, _proj) do
    lon_rad = lon * @deg_to_rad
    lat_rad = lat * @deg_to_rad

    x = @wagner6_cx * lon_rad * :math.sqrt(1 - 3 * lat_rad * lat_rad / (:math.pi() * :math.pi()))
    y = @wagner6_cy * lat_rad
    {x, y}
  end

  defp wagner6_invert(x, y, _proj) do
    lat = y / @wagner6_cy
    denom = :math.sqrt(1 - 3 * lat * lat / (:math.pi() * :math.pi()))
    lon = if denom > 0.001, do: x / (@wagner6_cx * denom), else: 0
    {lon * @rad_to_deg, lat * @rad_to_deg}
  end

  # Fahey (pseudocylindrical)

  defp fahey_project(lon, lat, _proj) do
    lon_rad = lon * @deg_to_rad
    lat_rad = lat * @deg_to_rad

    t = :math.tan(lat_rad / 2)
    x = lon_rad * (1 - t * t)
    y = (1 + cos(lat_rad) / cos(lat_rad / 2)) * t
    {x, y}
  end

  defp fahey_invert(x, y, _proj) do
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

  # Loximuthal (rhumb lines are straight)

  defp loximuthal_project(lon, lat, proj) do
    {phi0, _} = proj.parallels
    phi0_rad = phi0 * @deg_to_rad
    lon_rad = lon * @deg_to_rad
    lat_rad = lat * @deg_to_rad

    delta = lat_rad - phi0_rad

    if abs(delta) < 0.001 do
      {lon_rad * cos(phi0_rad), delta}
    else
      x =
        lon_rad * delta /
          :math.log(
            :math.tan(:math.pi() / 4 + lat_rad / 2) / :math.tan(:math.pi() / 4 + phi0_rad / 2)
          )

      y = delta
      {x, y}
    end
  end

  defp loximuthal_invert(x, y, proj) do
    {phi0, _} = proj.parallels
    phi0_rad = phi0 * @deg_to_rad

    lat = y + phi0_rad

    if abs(y) < 0.001 do
      lon = x / cos(phi0_rad)
      {lon * @rad_to_deg, lat * @rad_to_deg}
    else
      lon =
        x *
          :math.log(
            :math.tan(:math.pi() / 4 + lat / 2) / :math.tan(:math.pi() / 4 + phi0_rad / 2)
          ) / y

      {lon * @rad_to_deg, lat * @rad_to_deg}
    end
  end

  defp sin(x), do: :math.sin(x)
  defp cos(x), do: :math.cos(x)
end
