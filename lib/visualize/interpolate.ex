defmodule Visualize.Interpolate do
  @moduledoc """
  Interpolation functions for smooth transitions between values.

  Provides various interpolation methods for numbers, colors, strings,
  arrays, and other data types.

  ## Examples

      # Number interpolation
      interp = Visualize.Interpolate.number(0, 100)
      interp.(0.5)  # => 50.0

      # Color interpolation (RGB)
      interp = Visualize.Interpolate.rgb("#ff0000", "#0000ff")
      interp.(0.5)  # => "#800080" (purple)

      # String interpolation with embedded numbers
      interp = Visualize.Interpolate.string("10px solid red", "20px solid blue")
      interp.(0.5)  # => "15px solid ..."

  """

  # ============================================
  # Number Interpolation
  # ============================================

  @doc """
  Creates a linear interpolator between two numbers.

  ## Examples

      interp = Visualize.Interpolate.number(0, 100)
      interp.(0.0)  # => 0.0
      interp.(0.5)  # => 50.0
      interp.(1.0)  # => 100.0

  """
  @spec number(number(), number()) :: (number() -> float())
  def number(a, b) do
    delta = b - a
    fn t -> a + delta * t end
  end

  @doc """
  Interpolates between two numbers, rounding to the nearest integer.
  """
  @spec round(number(), number()) :: (number() -> integer())
  def round(a, b) do
    delta = b - a
    fn t -> Kernel.round(a + delta * t) end
  end

  @doc """
  Creates a discrete interpolator that returns one of n values.

  Useful for stepped animations or categorical transitions.

  ## Examples

      interp = Visualize.Interpolate.discrete(["a", "b", "c", "d"])
      interp.(0.0)   # => "a"
      interp.(0.25)  # => "b"
      interp.(0.99)  # => "d"

  """
  @spec discrete([any()]) :: (number() -> any())
  def discrete(values) when is_list(values) and length(values) > 0 do
    n = length(values)

    fn t ->
      i = trunc(max(0, min(n - 1, floor(t * n))))
      Enum.at(values, i)
    end
  end

  # ============================================
  # Color Interpolation
  # ============================================

  @doc """
  Creates an RGB color interpolator.

  Accepts hex strings, RGB tuples, or Color structs.

  ## Examples

      interp = Visualize.Interpolate.rgb("#ff0000", "#0000ff")
      interp.(0.5)  # => "#800080"

  """
  @spec rgb(any(), any()) :: (number() -> String.t())
  def rgb(a, b) do
    {r0, g0, b0} = parse_color(a)
    {r1, g1, b1} = parse_color(b)

    fn t ->
      r = Kernel.round(r0 + (r1 - r0) * t)
      g = Kernel.round(g0 + (g1 - g0) * t)
      b = Kernel.round(b0 + (b1 - b0) * t)

      r = max(0, min(255, r))
      g = max(0, min(255, g))
      b = max(0, min(255, b))

      "#" <>
        String.pad_leading(Integer.to_string(r, 16), 2, "0") <>
        String.pad_leading(Integer.to_string(g, 16), 2, "0") <>
        String.pad_leading(Integer.to_string(b, 16), 2, "0")
    end
  end

  @doc """
  Creates an HSL color interpolator.

  Interpolating in HSL space often produces more pleasing transitions
  than RGB, especially for colors that are far apart on the color wheel.

  ## Examples

      interp = Visualize.Interpolate.hsl("#ff0000", "#00ff00")
      interp.(0.5)  # Interpolates through yellow

  """
  @spec hsl(any(), any()) :: (number() -> String.t())
  def hsl(a, b) do
    {r0, g0, b0} = parse_color(a)
    {r1, g1, b1} = parse_color(b)

    {h0, s0, l0} = rgb_to_hsl(r0, g0, b0)
    {h1, s1, l1} = rgb_to_hsl(r1, g1, b1)

    # Handle hue interpolation (shortest path around the circle)
    dh = h1 - h0

    dh =
      cond do
        dh > 180 -> dh - 360
        dh < -180 -> dh + 360
        true -> dh
      end

    fn t ->
      h = h0 + dh * t
      h = if h < 0, do: h + 360, else: if(h >= 360, do: h - 360, else: h)
      s = s0 + (s1 - s0) * t
      l = l0 + (l1 - l0) * t

      {r, g, b} = hsl_to_rgb(h, s, l)

      "#" <>
        String.pad_leading(Integer.to_string(r, 16), 2, "0") <>
        String.pad_leading(Integer.to_string(g, 16), 2, "0") <>
        String.pad_leading(Integer.to_string(b, 16), 2, "0")
    end
  end

  @doc """
  Creates an HSL interpolator that takes the long path around the hue circle.
  """
  @spec hsl_long(any(), any()) :: (number() -> String.t())
  def hsl_long(a, b) do
    {r0, g0, b0} = parse_color(a)
    {r1, g1, b1} = parse_color(b)

    {h0, s0, l0} = rgb_to_hsl(r0, g0, b0)
    {h1, s1, l1} = rgb_to_hsl(r1, g1, b1)

    # Long path: take the long way around
    dh = h1 - h0

    dh =
      cond do
        dh > 0 and dh < 180 -> dh - 360
        dh < 0 and dh > -180 -> dh + 360
        true -> dh
      end

    fn t ->
      h = h0 + dh * t
      h = cond do
        h < 0 -> h + 360
        h >= 360 -> h - 360
        true -> h
      end

      s = s0 + (s1 - s0) * t
      l = l0 + (l1 - l0) * t

      {r, g, b} = hsl_to_rgb(h, s, l)

      "#" <>
        String.pad_leading(Integer.to_string(r, 16), 2, "0") <>
        String.pad_leading(Integer.to_string(g, 16), 2, "0") <>
        String.pad_leading(Integer.to_string(b, 16), 2, "0")
    end
  end

  # ============================================
  # Array/List Interpolation
  # ============================================

  @doc """
  Creates an interpolator between two lists of numbers.

  Lists must be the same length.

  ## Examples

      interp = Visualize.Interpolate.array([0, 0], [100, 200])
      interp.(0.5)  # => [50.0, 100.0]

  """
  @spec array([number()], [number()]) :: (number() -> [float()])
  def array(a, b) when is_list(a) and is_list(b) and length(a) == length(b) do
    interpolators = Enum.zip(a, b) |> Enum.map(fn {v0, v1} -> number(v0, v1) end)

    fn t ->
      Enum.map(interpolators, fn interp -> interp.(t) end)
    end
  end

  # ============================================
  # Date/Time Interpolation
  # ============================================

  @doc """
  Creates an interpolator between two DateTime values.

  ## Examples

      start = ~U[2024-01-01 00:00:00Z]
      finish = ~U[2024-12-31 00:00:00Z]
      interp = Visualize.Interpolate.datetime(start, finish)
      interp.(0.5)  # => ~U[2024-07-01 ...]

  """
  @spec datetime(DateTime.t(), DateTime.t()) :: (number() -> DateTime.t())
  def datetime(%DateTime{} = a, %DateTime{} = b) do
    a_unix = DateTime.to_unix(a, :millisecond)
    b_unix = DateTime.to_unix(b, :millisecond)
    delta = b_unix - a_unix

    fn t ->
      ms = Kernel.round(a_unix + delta * t)
      DateTime.from_unix!(ms, :millisecond)
    end
  end

  @doc """
  Creates an interpolator between two Date values.
  """
  @spec date(Date.t(), Date.t()) :: (number() -> Date.t())
  def date(%Date{} = a, %Date{} = b) do
    a_days = Date.diff(a, ~D[1970-01-01])
    b_days = Date.diff(b, ~D[1970-01-01])
    delta = b_days - a_days

    fn t ->
      days = Kernel.round(a_days + delta * t)
      Date.add(~D[1970-01-01], days)
    end
  end

  # ============================================
  # String Interpolation
  # ============================================

  @doc """
  Creates an interpolator for strings containing numbers.

  Numbers in the string are interpolated while other characters
  are preserved from the ending string.

  ## Examples

      interp = Visualize.Interpolate.string("10px", "20px")
      interp.(0.5)  # => "15px"

      interp = Visualize.Interpolate.string("rotate(0)", "rotate(180)")
      interp.(0.5)  # => "rotate(90)"

  """
  @spec string(String.t(), String.t()) :: (number() -> String.t())
  def string(a, b) when is_binary(a) and is_binary(b) do
    # Extract numbers from both strings
    number_pattern = ~r/-?\d+\.?\d*/

    a_numbers = Regex.scan(number_pattern, a) |> List.flatten() |> Enum.map(&parse_number/1)
    b_numbers = Regex.scan(number_pattern, b) |> List.flatten() |> Enum.map(&parse_number/1)

    # Get the template from b (non-number parts)
    parts = Regex.split(number_pattern, b, include_captures: true)

    # Create interpolators for each pair of numbers
    interpolators =
      Enum.zip(a_numbers ++ List.duplicate(0, max(0, length(b_numbers) - length(a_numbers))), b_numbers)
      |> Enum.map(fn {v0, v1} -> number(v0, v1) end)

    fn t ->
      {result, _} =
        Enum.reduce(parts, {"", interpolators}, fn part, {acc, interps} ->
          if Regex.match?(number_pattern, part) do
            case interps do
              [interp | rest] ->
                value = interp.(t)
                # Format: use integer if result is whole number
                formatted =
                  if value == trunc(value) do
                    Integer.to_string(trunc(value))
                  else
                    Float.to_string(Float.round(value, 4))
                  end

                {acc <> formatted, rest}

              [] ->
                {acc <> part, []}
            end
          else
            {acc <> part, interps}
          end
        end)

      result
    end
  end

  # ============================================
  # Transform Interpolation
  # ============================================

  @doc """
  Creates an interpolator for SVG transform strings.

  Handles translate, scale, and rotate transformations.

  ## Examples

      interp = Visualize.Interpolate.transform(
        "translate(0, 0) rotate(0)",
        "translate(100, 50) rotate(90)"
      )
      interp.(0.5)  # => "translate(50, 25) rotate(45)"

  """
  @spec transform(String.t(), String.t()) :: (number() -> String.t())
  def transform(a, b) do
    a_transforms = parse_transform(a)
    b_transforms = parse_transform(b)

    # Create interpolators for each transform type
    translate_interp = transform_interpolator(a_transforms[:translate], b_transforms[:translate], [0, 0])
    scale_interp = transform_interpolator(a_transforms[:scale], b_transforms[:scale], [1, 1])
    rotate_interp = transform_interpolator(a_transforms[:rotate], b_transforms[:rotate], [0])

    fn t ->
      parts = []

      [tx, ty] = translate_interp.(t)
      parts = if tx != 0 or ty != 0, do: parts ++ ["translate(#{format_num(tx)}, #{format_num(ty)})"], else: parts

      [sx, sy] = scale_interp.(t)
      parts = if sx != 1 or sy != 1, do: parts ++ ["scale(#{format_num(sx)}, #{format_num(sy)})"], else: parts

      [r | _] = rotate_interp.(t)
      parts = if r != 0, do: parts ++ ["rotate(#{format_num(r)})"], else: parts

      if Enum.empty?(parts), do: "", else: Enum.join(parts, " ")
    end
  end

  # ============================================
  # Basis Spline Interpolation
  # ============================================

  @doc """
  Creates a basis spline interpolator through a series of values.

  Returns smooth values that pass near (but not through) control points.

  ## Examples

      interp = Visualize.Interpolate.basis([0, 10, 5, 20, 15])
      interp.(0.5)  # Smooth value around middle

  """
  @spec basis([number()]) :: (number() -> float())
  def basis(values) when is_list(values) and length(values) >= 2 do
    n = length(values)

    fn t ->
      t = max(0, min(1, t))

      if t == 0 do
        hd(values) + 0.0
      else
        if t == 1 do
          List.last(values) + 0.0
        else
          # Map t to segment index
          i = t * (n - 1)
          segment = trunc(i)
          local_t = i - segment

          # Get control points (clamp to valid indices)
          p0 = Enum.at(values, max(0, segment - 1))
          p1 = Enum.at(values, segment)
          p2 = Enum.at(values, min(n - 1, segment + 1))
          p3 = Enum.at(values, min(n - 1, segment + 2))

          basis_value(local_t, p0, p1, p2, p3)
        end
      end
    end
  end

  defp basis_value(t, p0, p1, p2, p3) do
    t2 = t * t
    t3 = t2 * t

    ((-t3 + 3 * t2 - 3 * t + 1) * p0 +
       (3 * t3 - 6 * t2 + 4) * p1 +
       (-3 * t3 + 3 * t2 + 3 * t + 1) * p2 +
       t3 * p3) / 6
  end

  # ============================================
  # Zoom Interpolation
  # ============================================

  @doc """
  Creates a smooth zoom interpolator between two views.

  Views are specified as [cx, cy, width] representing the center
  point and visible width. Uses van Wijk and Nuij's algorithm.

  ## Examples

      interp = Visualize.Interpolate.zoom(
        [0, 0, 100],      # Start: centered at origin, width 100
        [500, 300, 50]    # End: centered at (500,300), width 50
      )
      [cx, cy, w] = interp.(0.5)

  """
  @spec zoom([number()], [number()]) :: (number() -> [float()])
  def zoom([cx0, cy0, w0], [cx1, cy1, w1]) do
    # van Wijk and Nuij's smooth zoom algorithm
    rho = 1.4  # Aesthetic parameter

    dx = cx1 - cx0
    dy = cy1 - cy0
    d = :math.sqrt(dx * dx + dy * dy)

    if d < 1.0e-6 do
      # Just zooming, no panning
      s = :math.log(w1 / w0) / rho

      fn t ->
        w = w0 * :math.exp(rho * t * s)
        [cx0, cy0, w]
      end
    else
      b0 = (w1 * w1 - w0 * w0 + rho * rho * rho * rho * d * d) / (2 * w0 * rho * rho * d)
      b1 = (w1 * w1 - w0 * w0 - rho * rho * rho * rho * d * d) / (2 * w1 * rho * rho * d)

      r0 = :math.log(:math.sqrt(b0 * b0 + 1) - b0)
      r1 = :math.log(:math.sqrt(b1 * b1 + 1) - b1)

      s = (r1 - r0) / rho

      fn t ->
        t_scaled = t * s
        u = w0 / (rho * rho * d) * (cosh(r0) * tanh(rho * t_scaled + r0) - sinh(r0))
        w = w0 * cosh(r0) / cosh(rho * t_scaled + r0)

        [cx0 + u * dx, cy0 + u * dy, w]
      end
    end
  end

  defp cosh(x), do: (:math.exp(x) + :math.exp(-x)) / 2
  defp sinh(x), do: (:math.exp(x) - :math.exp(-x)) / 2
  defp tanh(x), do: sinh(x) / cosh(x)

  # ============================================
  # Helper Functions
  # ============================================

  defp parse_color(color) when is_binary(color) do
    # Parse hex color
    color = String.trim_leading(color, "#")

    case String.length(color) do
      3 ->
        <<r::binary-size(1), g::binary-size(1), b::binary-size(1)>> = color
        {String.to_integer(r <> r, 16), String.to_integer(g <> g, 16), String.to_integer(b <> b, 16)}

      6 ->
        <<r::binary-size(2), g::binary-size(2), b::binary-size(2)>> = color
        {String.to_integer(r, 16), String.to_integer(g, 16), String.to_integer(b, 16)}

      _ ->
        # Try named colors
        case named_color(color) do
          nil -> {0, 0, 0}
          hex -> parse_color(hex)
        end
    end
  end

  defp parse_color({r, g, b}), do: {r, g, b}

  # Basic named colors
  defp named_color("red"), do: "#ff0000"
  defp named_color("green"), do: "#00ff00"
  defp named_color("blue"), do: "#0000ff"
  defp named_color("white"), do: "#ffffff"
  defp named_color("black"), do: "#000000"
  defp named_color("yellow"), do: "#ffff00"
  defp named_color("cyan"), do: "#00ffff"
  defp named_color("magenta"), do: "#ff00ff"
  defp named_color("orange"), do: "#ffa500"
  defp named_color("purple"), do: "#800080"
  defp named_color("pink"), do: "#ffc0cb"
  defp named_color("gray"), do: "#808080"
  defp named_color("grey"), do: "#808080"
  defp named_color(_), do: nil

  defp rgb_to_hsl(r, g, b) do
    r = r / 255
    g = g / 255
    b = b / 255

    max_c = max(max(r, g), b)
    min_c = min(min(r, g), b)
    l = (max_c + min_c) / 2

    if max_c == min_c do
      {0.0, 0.0, l * 100}
    else
      d = max_c - min_c

      s =
        if l > 0.5 do
          d / (2 - max_c - min_c)
        else
          d / (max_c + min_c)
        end

      h =
        cond do
          max_c == r -> (g - b) / d + if(g < b, do: 6, else: 0)
          max_c == g -> (b - r) / d + 2
          true -> (r - g) / d + 4
        end

      {h * 60, s * 100, l * 100}
    end
  end

  defp hsl_to_rgb(h, s, l) do
    h = h / 360
    s = s / 100
    l = l / 100

    if s == 0 do
      v = Kernel.round(l * 255)
      {v, v, v}
    else
      q = if l < 0.5, do: l * (1 + s), else: l + s - l * s
      p = 2 * l - q

      r = hue_to_rgb(p, q, h + 1 / 3)
      g = hue_to_rgb(p, q, h)
      b = hue_to_rgb(p, q, h - 1 / 3)

      {Kernel.round(r * 255), Kernel.round(g * 255), Kernel.round(b * 255)}
    end
  end

  defp hue_to_rgb(p, q, t) do
    t = if t < 0, do: t + 1, else: if(t > 1, do: t - 1, else: t)

    cond do
      t < 1 / 6 -> p + (q - p) * 6 * t
      t < 1 / 2 -> q
      t < 2 / 3 -> p + (q - p) * (2 / 3 - t) * 6
      true -> p
    end
  end

  defp parse_number(str) do
    case Float.parse(str) do
      {num, ""} -> num
      _ ->
        case Integer.parse(str) do
          {num, ""} -> num
          _ -> 0
        end
    end
  end

  defp parse_transform(str) do
    translate = case Regex.run(~r/translate\s*\(\s*([^,\)]+)(?:\s*,\s*([^\)]+))?\s*\)/, str) do
      [_, x] -> [parse_number(x), 0]
      [_, x, y] -> [parse_number(x), parse_number(y)]
      _ -> nil
    end

    scale = case Regex.run(~r/scale\s*\(\s*([^,\)]+)(?:\s*,\s*([^\)]+))?\s*\)/, str) do
      [_, s] -> [parse_number(s), parse_number(s)]
      [_, sx, sy] -> [parse_number(sx), parse_number(sy)]
      _ -> nil
    end

    rotate = case Regex.run(~r/rotate\s*\(\s*([^\)]+)\s*\)/, str) do
      [_, r] -> [parse_number(r)]
      _ -> nil
    end

    %{translate: translate, scale: scale, rotate: rotate}
  end

  defp transform_interpolator(nil, nil, default), do: fn _t -> default end
  defp transform_interpolator(nil, b, _default), do: array(b, b)
  defp transform_interpolator(a, nil, _default), do: array(a, a)
  defp transform_interpolator(a, b, _default), do: array(a, b)

  defp format_num(n) when is_float(n) do
    if n == trunc(n), do: Integer.to_string(trunc(n)), else: Float.to_string(Float.round(n, 4))
  end

  defp format_num(n), do: Integer.to_string(n)
end
