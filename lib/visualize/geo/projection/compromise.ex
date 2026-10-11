defmodule Visualize.Geo.Projection.Compromise do
  @moduledoc """
  Compromise and polyconic world projections: Natural Earth, Equal Earth, Robinson, Winkel tripel, Aitoff and Van der Grinten.

  Raw projection maths, reached through `Visualize.Geo.Projection.project/3` and
  `invert/3`. `project/4` takes longitude and latitude in degrees, already rotated and
  centred, and returns unit-scale planar coordinates; `invert/4` is its inverse. Scale,
  translation and rotation are applied by the parent module.
  """

  import Visualize.Geo.Math, only: [asin: 1, acos: 1]

  @deg_to_rad :math.pi() / 180
  @rad_to_deg 180 / :math.pi()

  @doc false
  def project(:natural_earth, lon, lat, proj), do: natural_earth_project(lon, lat, proj)
  def project(:equal_earth, lon, lat, proj), do: equal_earth_project(lon, lat, proj)
  def project(:robinson, lon, lat, proj), do: robinson_project(lon, lat, proj)
  def project(:winkel_tripel, lon, lat, proj), do: winkel_tripel_project(lon, lat, proj)
  def project(:aitoff, lon, lat, proj), do: aitoff_project(lon, lat, proj)
  def project(:van_der_grinten, lon, lat, proj), do: van_der_grinten_project(lon, lat, proj)

  @doc false
  def invert(:natural_earth, x, y, proj), do: natural_earth_invert(x, y, proj)
  def invert(:equal_earth, x, y, proj), do: equal_earth_invert(x, y, proj)
  def invert(:robinson, x, y, proj), do: robinson_invert(x, y, proj)
  def invert(:winkel_tripel, x, y, proj), do: winkel_tripel_invert(x, y, proj)
  def invert(:aitoff, x, y, proj), do: aitoff_invert(x, y, proj)
  def invert(:van_der_grinten, x, y, proj), do: van_der_grinten_invert(x, y, proj)

  # Natural Earth projection
  defp natural_earth_project(lon, lat, _proj) do
    lon_rad = lon * @deg_to_rad
    lat_rad = lat * @deg_to_rad
    lat2 = lat_rad * lat_rad
    lat4 = lat2 * lat2

    x =
      lon_rad *
        (0.8707 - 0.131979 * lat2 +
           lat4 * (-0.013791 + lat4 * (0.003971 * lat2 - 0.001529 * lat4)))

    y =
      lat_rad *
        (1.007226 + lat2 * (0.015085 + lat4 * (-0.044475 + 0.028874 * lat2 - 0.005916 * lat4)))

    {x, y}
  end

  defp natural_earth_invert(x, y, _proj) do
    # Newton-Raphson iteration for inverse
    lat_rad = y
    _lon_rad = x

    # Iterate to find latitude
    lat_rad = newton_raphson_natural_earth(y, lat_rad, 10)

    lat2 = lat_rad * lat_rad
    lat4 = lat2 * lat2

    # Compute longitude
    denom =
      0.8707 - 0.131979 * lat2 + lat4 * (-0.013791 + lat4 * (0.003971 * lat2 - 0.001529 * lat4))

    lon_rad = if abs(denom) > 0.001, do: x / denom, else: 0

    {lon_rad * @rad_to_deg, lat_rad * @rad_to_deg}
  end

  defp newton_raphson_natural_earth(_y, lat, 0), do: lat

  defp newton_raphson_natural_earth(y, lat, iterations) do
    lat2 = lat * lat
    lat4 = lat2 * lat2

    f =
      lat *
        (1.007226 + lat2 * (0.015085 + lat4 * (-0.044475 + 0.028874 * lat2 - 0.005916 * lat4))) -
        y

    df = 1.007226 + lat2 * (0.045255 + lat4 * (-0.311325 + 0.259866 * lat2 - 0.053244 * lat4))

    new_lat = lat - f / df

    if abs(new_lat - lat) < 0.0001 do
      new_lat
    else
      newton_raphson_natural_earth(y, new_lat, iterations - 1)
    end
  end

  # Equal Earth (modern equal-area, 2018)

  # Equal Earth polynomial coefficients
  @ee_a1 1.340264
  @ee_a2 -0.081106
  @ee_a3 0.000893
  @ee_a4 0.003796
  @ee_m :math.sqrt(3) / 2

  defp equal_earth_project(lon, lat, _proj) do
    lon_rad = lon * @deg_to_rad
    lat_rad = lat * @deg_to_rad

    # Parametric latitude
    theta = asin(@ee_m * sin(lat_rad))
    theta2 = theta * theta
    theta6 = theta2 * theta2 * theta2

    x =
      lon_rad * cos(theta) /
        (@ee_m * (@ee_a1 + 3 * @ee_a2 * theta2 + theta6 * (7 * @ee_a3 + 9 * @ee_a4 * theta2)))

    y = theta * (@ee_a1 + @ee_a2 * theta2 + theta6 * (@ee_a3 + @ee_a4 * theta2))
    {x, y}
  end

  defp equal_earth_invert(x, y, _proj) do
    # Newton-Raphson to find theta
    theta = newton_raphson_equal_earth(y, y, 10)
    theta2 = theta * theta
    theta6 = theta2 * theta2 * theta2

    lon =
      @ee_m * x * (@ee_a1 + 3 * @ee_a2 * theta2 + theta6 * (7 * @ee_a3 + 9 * @ee_a4 * theta2)) /
        cos(theta)

    lat = asin(sin(theta) / @ee_m)
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

  # Robinson (compromise projection)

  # Robinson projection lookup table (latitude in 5-degree intervals)
  @robinson_x [
    1.0000,
    0.9986,
    0.9954,
    0.9900,
    0.9822,
    0.9730,
    0.9600,
    0.9427,
    0.9216,
    0.8962,
    0.8679,
    0.8350,
    0.7986,
    0.7597,
    0.7186,
    0.6732,
    0.6213,
    0.5722,
    0.5322
  ]
  @robinson_y [
    0.0000,
    0.0620,
    0.1240,
    0.1860,
    0.2480,
    0.3100,
    0.3720,
    0.4340,
    0.4958,
    0.5571,
    0.6176,
    0.6769,
    0.7346,
    0.7903,
    0.8435,
    0.8936,
    0.9394,
    0.9761,
    1.0000
  ]

  defp robinson_project(lon, lat, _proj) do
    lon_rad = lon * @deg_to_rad
    abs_lat = abs(lat)

    # Interpolate from lookup table
    {plen, pdfe} = robinson_interpolate(abs_lat)

    x = 0.8487 * plen * lon_rad
    y = 1.3523 * pdfe * if lat < 0, do: -1, else: 1
    {x, y}
  end

  defp robinson_invert(x, y, _proj) do
    # Inverse lookup
    abs_y = abs(y) / 1.3523
    {plen, lat_deg} = robinson_inverse_y(abs_y)

    lon = x / (0.8487 * plen)
    lat = lat_deg * if y < 0, do: -1, else: 1
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
    {idx, _} =
      Enum.reduce_while(0..17, {0, 0}, fn i, _acc ->
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

    plen =
      Enum.at(@robinson_x, idx) +
        (Enum.at(@robinson_x, idx + 1) - Enum.at(@robinson_x, idx)) * frac

    {plen, lat_deg}
  end

  # Winkel Tripel (National Geographic)

  defp winkel_tripel_project(lon, lat, _proj) do
    lon_rad = lon * @deg_to_rad
    lat_rad = lat * @deg_to_rad

    cos_lat = cos(lat_rad)
    alpha = acos(cos_lat * cos(lon_rad / 2))

    sinc_alpha = if alpha == 0, do: 1, else: sin(alpha) / alpha

    # Average of equirectangular and Aitoff
    x_aitoff = 2 * cos_lat * sin(lon_rad / 2) / sinc_alpha
    y_aitoff = sin(lat_rad) / sinc_alpha

    x = (lon_rad + x_aitoff) / 2
    y = (lat_rad + y_aitoff) / 2
    {x, y}
  end

  defp winkel_tripel_invert(x, y, _proj) do
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

    alpha = acos(cos_lat * cos_half_lon)
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

  # Aitoff (pseudoazimuthal)

  defp aitoff_project(lon, lat, _proj) do
    lon_rad = lon * @deg_to_rad
    lat_rad = lat * @deg_to_rad

    cos_lat = cos(lat_rad)
    alpha = acos(cos_lat * cos(lon_rad / 2))
    sinc_alpha = if alpha == 0, do: 1, else: sin(alpha) / alpha

    x = 2 * cos_lat * sin(lon_rad / 2) / sinc_alpha
    y = sin(lat_rad) / sinc_alpha
    {x, y}
  end

  defp aitoff_invert(x, y, _proj) do
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

    alpha = acos(cos_lat * cos_half_lon)
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

  # Van der Grinten (polyconic, circular boundary)

  defp van_der_grinten_project(lon, lat, _proj) do
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
        theta = asin(2 * abs_lat / :math.pi())
        cos_theta = cos(theta)
        sin_theta = sin(theta)

        a = 0.5 * abs(:math.pi() / lon_rad - lon_rad / :math.pi())
        g = cos_theta / (sin_theta + cos_theta - 1)
        p = g * (2 / sin_theta - 1)
        q = a * a + g

        p2 = p * p
        a2 = a * a
        g2 = g * g

        x =
          :math.pi() *
            (a * (g - p2) + :math.sqrt(a2 * (g - p2) * (g - p2) - (p2 + a2) * (g2 - p2))) /
            (p2 + a2)

        x = if lon_rad < 0, do: -abs(x), else: abs(x)

        y = :math.pi() * abs(p * q - a * :math.sqrt((a2 + 1) * (p2 + a2) - q * q)) / (p2 + a2)
        y = if lat_rad < 0, do: -y, else: y

        {x, y}
    end
  end

  defp van_der_grinten_invert(x, y, _proj) do
    # Simplified inverse using Newton-Raphson
    {lon, lat} = newton_raphson_van_der_grinten(x, y, x, y / :math.pi(), 15)
    {lon * @rad_to_deg, lat * @rad_to_deg}
  end

  defp newton_raphson_van_der_grinten(_x, _y, lon, lat, 0), do: {lon, lat}

  defp newton_raphson_van_der_grinten(x, y, lon, lat, iterations) do
    {px, py} = van_der_grinten_project(lon * @rad_to_deg, lat * @rad_to_deg, nil)
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

  defp sin(x), do: :math.sin(x)
  defp cos(x), do: :math.cos(x)
end
