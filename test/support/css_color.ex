defmodule Visualize.Test.CssColor do
  @moduledoc """
  An evaluator of the CSS the library writes for a typed color in `:css` mode (spec/09,
  spec/08 §1.9, #665), written from CSS Color 4 and 5 alone and sharing nothing with
  `Visualize.Color`: `var()` with its fallback, `color-mix(in oklab, …)`, relative
  `oklch(from …)` with `calc()` over `l`, `c`, `h` and `alpha`, hex and `transparent`.

  `eval/1` answers `{r, g, b, alpha}`, channels in `0..255`, unclipped; the OKLab it works
  in is CSS Color 4's sample code, through XYZ.
  """

  @rgb_xyz [
    [0.41239079926595934, 0.357584339383878, 0.1804807884018343],
    [0.21263900587151027, 0.715168678767756, 0.07219231536073371],
    [0.01933081871559182, 0.11919477979462598, 0.9505321522496607]
  ]
  @xyz_lms [
    [0.8190224379967030, 0.3619062600528904, -0.1288737815209879],
    [0.0329836539323885, 0.9292868615863434, 0.0361446663506424],
    [0.0481771893596242, 0.2642395317527308, 0.6335478284694309]
  ]
  @lms_oklab [
    [0.2104542683093140, 0.7936177747023054, -0.0040720430116193],
    [1.9779985324311684, -2.4285922420485799, 0.4505937096174110],
    [0.0259040424655478, 0.7827717124575296, -0.8086757549230774]
  ]
  @oklab_lms [
    [1.0, 0.3963377773761749, 0.2158037573099136],
    [1.0, -0.1055613458156586, -0.0638541728258133],
    [1.0, -0.0894841775298119, -1.2914855480194092]
  ]
  @lms_xyz [
    [1.2268798758459243, -0.5578149944602171, 0.2813910456659647],
    [-0.0405757452148008, 1.1122868032803170, -0.0717110580655164],
    [-0.0763729366746601, -0.4214933324022432, 1.5869240198367816]
  ]
  @xyz_rgb [
    [3.2409699419045226, -1.537383177570094, -0.4986107602930034],
    [-0.9692436362808796, 1.8759675015077202, 0.04155505740717559],
    [0.05563007969699366, -0.20397695888897652, 1.0569715142428786]
  ]

  @doc "The color a CSS color string evaluates to, `{r, g, b, alpha}` in sRGB 0..255."
  def eval(css) do
    {color, ""} = color(String.trim(css))
    to_rgb(color)
  end

  # A colour while evaluating is `{[l, a, b], alpha}` in OKLab.

  defp color("var(" <> rest) do
    [_name, rest] = String.split(rest, ",", parts: 2)
    {c, rest} = color(String.trim_leading(rest))
    {c, close(rest)}
  end

  defp color("color-mix(in oklab," <> rest) do
    {c1, rest} = color(String.trim_leading(rest))
    {p1, rest} = percent(rest)
    "," <> rest = String.trim_leading(rest)
    {c2, rest} = color(String.trim_leading(rest))
    {p2, rest} = percent(rest)
    {mix(c1, p1, c2, p2), close(rest)}
  end

  defp color("oklch(from " <> rest) do
    {origin, rest} = color(rest)
    {[l, a, b], alpha} = origin
    [l, c, h] = lch([l, a, b])
    env = %{"l" => l, "c" => c, "h" => h, "alpha" => alpha}
    {l2, rest} = channel(String.trim_leading(rest), env)
    {c2, rest} = channel(String.trim_leading(rest), env)
    {h2, rest} = channel(String.trim_leading(rest), env)
    "/" <> rest = String.trim_leading(rest)
    {a2, rest} = channel(String.trim_leading(rest), env)
    {{from_lch([l2, c2, h2]), a2}, close(rest)}
  end

  defp color("transparent" <> rest), do: {{[0.0, 0.0, 0.0], 0.0}, rest}

  defp color("#" <> rest) do
    [hex | _] = Regex.run(~r/^[0-9a-fA-F]+/, rest)
    rest = String.replace_prefix(rest, hex, "")
    {hex_color(hex), rest}
  end

  defp hex_color(hex) do
    bytes =
      case String.length(hex) do
        6 -> hex
        8 -> hex
        3 -> hex |> String.graphemes() |> Enum.map_join(&(&1 <> &1))
      end

    [r, g, b | alpha] =
      for <<pair::binary-size(2) <- bytes>>, do: String.to_integer(pair, 16)

    alpha = if alpha == [], do: 1.0, else: hd(alpha) / 255
    {oklab(Enum.map([r, g, b], &(&1 / 255))), alpha}
  end

  defp close(rest) do
    ")" <> rest = String.trim_leading(rest)
    rest
  end

  defp percent(rest) do
    rest = String.trim_leading(rest)

    case Float.parse(rest) do
      {n, "%" <> rest} -> {n, rest}
      _none -> {nil, rest}
    end
  end

  # CSS Color 5 §2.1: a missing percentage is the rest of 100; the pair normalized; a sum
  # below 100 multiplies the alpha; premultiplied OKLab.
  defp mix(c1, p1, c2, p2) do
    {p1, p2} =
      case {p1, p2} do
        {nil, nil} -> {50.0, 50.0}
        {nil, p} -> {100 - p, p}
        {p, nil} -> {p, 100 - p}
        pair -> pair
      end

    sum = p1 + p2
    mult = if sum < 100, do: sum / 100, else: 1.0
    {w1, w2} = {p1 / sum, p2 / sum}
    {lab1, a1} = c1
    {lab2, a2} = c2
    alpha = w1 * a1 + w2 * a2

    lab =
      if alpha == 0,
        do: [0.0, 0.0, 0.0],
        else: Enum.zip_with(lab1, lab2, fn x, y -> (w1 * a1 * x + w2 * a2 * y) / alpha end)

    {lab, alpha * mult}
  end

  # A channel of a relative color: a keyword, a number or a `calc()`.
  defp channel("calc(" <> rest, env) do
    {value, rest} = expr(rest, env)
    {value, close(rest)}
  end

  defp channel(rest, env), do: factor(rest, env)

  defp expr(rest, env) do
    {left, rest} = term(String.trim_leading(rest), env)
    expr_more(left, String.trim_leading(rest), env)
  end

  defp expr_more(left, "+" <> rest, env) do
    {right, rest} = term(String.trim_leading(rest), env)
    expr_more(left + right, String.trim_leading(rest), env)
  end

  defp expr_more(left, "- " <> rest, env) do
    {right, rest} = term(String.trim_leading(rest), env)
    expr_more(left - right, String.trim_leading(rest), env)
  end

  defp expr_more(left, rest, _env), do: {left, rest}

  defp term(rest, env) do
    {left, rest} = factor(rest, env)
    term_more(left, String.trim_leading(rest), env)
  end

  defp term_more(left, "*" <> rest, env) do
    {right, rest} = factor(String.trim_leading(rest), env)
    term_more(left * right, String.trim_leading(rest), env)
  end

  defp term_more(left, rest, _env), do: {left, rest}

  defp factor("(" <> rest, env) do
    {value, rest} = expr(rest, env)
    {value, close(rest)}
  end

  defp factor(rest, env) do
    case Regex.run(~r/^(alpha|l|c|h)\b/, rest) do
      [word, _] ->
        {Map.fetch!(env, word), String.replace_prefix(rest, word, "")}

      nil ->
        {n, rest} = Float.parse(rest)
        {n, rest}
    end
  end

  # -- CSS Color 4's sample code ----------------------------------------------------------

  defp mul(m, v),
    do:
      Enum.map(m, fn row ->
        row |> Enum.zip(v) |> Enum.map(fn {a, b} -> a * b end) |> Enum.sum()
      end)

  defp lin(c) when c <= 0.04045, do: c / 12.92
  defp lin(c), do: :math.pow((c + 0.055) / 1.055, 2.4)
  defp enc(c) when c < 0, do: -enc(-c)
  defp enc(c) when c <= 0.0031308, do: 12.92 * c
  defp enc(c), do: 1.055 * :math.pow(c, 1 / 2.4) - 0.055

  defp cbrt(x) when x < 0, do: -:math.pow(-x, 1 / 3)
  defp cbrt(x), do: :math.pow(x, 1 / 3)

  defp oklab(rgb) do
    rgb
    |> Enum.map(&lin/1)
    |> then(&mul(@rgb_xyz, &1))
    |> then(&mul(@xyz_lms, &1))
    |> Enum.map(&cbrt/1)
    |> then(&mul(@lms_oklab, &1))
  end

  defp to_rgb({lab, alpha}) do
    [r, g, b] =
      @oklab_lms
      |> mul(lab)
      |> Enum.map(&(&1 * &1 * &1))
      |> then(&mul(@lms_xyz, &1))
      |> then(&mul(@xyz_rgb, &1))
      |> Enum.map(&(enc(&1) * 255))

    {r, g, b, alpha}
  end

  defp lch([l, a, b]) do
    c = :math.sqrt(a * a + b * b)
    h = if c < 1.0e-9, do: 0.0, else: :math.atan2(b, a) * 180 / :math.pi()
    [l, c, if(h < 0, do: h + 360, else: h)]
  end

  defp from_lch([l, c, h]) do
    rad = h * :math.pi() / 180
    [l, c * :math.cos(rad), c * :math.sin(rad)]
  end
end
