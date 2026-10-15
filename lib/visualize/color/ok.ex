defmodule Visualize.Color.OK do
  @moduledoc false
  # OKLab and OKLCH (Björn Ottosson, 2020; CSS Color 4 §9), and CSS Color 4's gamut mapping
  # (§13.2), for the typed colors of spec/08 §1.9 (D-173). A colour here is `{r, g, b}` in
  # linear-light or gamma-encoded sRGB as each function says, channels in `0..1`; the
  # public face is `Visualize.Color`'s `to_oklab/1`, `oklab/4`, `to_oklch/1` and `oklch/4`.

  # The just-noticeable difference and the search's precision of §13.2.
  @jnd 0.02
  @epsilon 0.0001

  @doc false
  # Gamma-encoded sRGB channels in `0..1` to OKLab `{l, a, b}`.
  @spec from_srgb({number(), number(), number()}) :: {float(), float(), float()}
  def from_srgb({r, g, b}), do: from_linear({linear(r), linear(g), linear(b)})

  @doc false
  # OKLab `{l, a, b}` to gamma-encoded sRGB, unclipped: a channel outside `0..1` is a colour
  # outside the gamut.
  @spec to_srgb({number(), number(), number()}) :: {float(), float(), float()}
  def to_srgb(lab) do
    {r, g, b} = to_linear(lab)
    {gamma(r), gamma(g), gamma(b)}
  end

  @doc false
  # OKLab to OKLCH `{l, c, h}`, `h` in degrees `[0, 360)`; a grey's hue is 0.
  @spec to_lch({number(), number(), number()}) :: {float(), float(), float()}
  def to_lch({l, a, b}) do
    c = :math.sqrt(a * a + b * b)
    h = if c < 1.0e-9, do: 0.0, else: :math.atan2(b, a) * 180 / :math.pi()
    {l * 1.0, c, if(h < 0, do: h + 360, else: h)}
  end

  @doc false
  @spec from_lch({number(), number(), number()}) :: {float(), float(), float()}
  def from_lch({l, c, h}) do
    rad = h * :math.pi() / 180
    {l * 1.0, c * :math.cos(rad), c * :math.sin(rad)}
  end

  @doc false
  # An OKLab colour brought into sRGB by CSS Color 4's gamut mapping (§13.2): a colour in
  # the gamut as it is; lightness at or past either end white or black; otherwise chroma
  # reduced in OKLCH by binary search until the clipped colour is within a just-noticeable
  # difference of the reduced one. Answers gamma-encoded sRGB channels in `0..1`.
  @spec map_to_srgb({number(), number(), number()}) :: {float(), float(), float()}
  def map_to_srgb({l, _a, _b}) when l >= 1, do: {1.0, 1.0, 1.0}
  def map_to_srgb({l, _a, _b}) when l <= 0, do: {0.0, 0.0, 0.0}

  def map_to_srgb(lab) do
    rgb = to_srgb(lab)

    if in_gamut?(rgb) do
      rgb
    else
      {l, c, h} = to_lch(lab)
      clipped = clip(rgb)

      if delta(from_srgb(clipped), lab) < @jnd,
        do: clipped,
        else: search({l, h}, 0.0, c, true, clipped)
    end
  end

  defp search({l, h}, min, max, min_in_gamut?, clipped) when max - min > @epsilon do
    chroma = (min + max) / 2
    current = from_lch({l, chroma, h})
    rgb = to_srgb(current)

    if min_in_gamut? and in_gamut?(rgb) do
      search({l, h}, chroma, max, true, clipped)
    else
      clipped = clip(rgb)
      e = delta(from_srgb(clipped), current)

      cond do
        e < @jnd and @jnd - e < @epsilon -> clipped
        e < @jnd -> search({l, h}, chroma, max, false, clipped)
        true -> search({l, h}, min, chroma, min_in_gamut?, clipped)
      end
    end
  end

  defp search(_lh, _min, _max, _min_in_gamut?, clipped), do: clipped

  defp in_gamut?({r, g, b}), do: Enum.all?([r, g, b], &(&1 >= -1.0e-7 and &1 <= 1 + 1.0e-7))

  defp clip({r, g, b}), do: {clamp(r), clamp(g), clamp(b)}

  defp clamp(x), do: x |> max(0.0) |> min(1.0)

  # ΔEOK: the distance in OKLab.
  defp delta({l1, a1, b1}, {l2, a2, b2}) do
    :math.sqrt((l1 - l2) * (l1 - l2) + (a1 - a2) * (a1 - a2) + (b1 - b2) * (b1 - b2))
  end

  # Ottosson's matrices, linear sRGB straight to LMS and back.
  defp from_linear({r, g, b}) do
    l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
    m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
    s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)

    {0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
     1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
     0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s}
  end

  defp to_linear({l, a, b}) do
    l_ = l + 0.3963377774 * a + 0.2158037573 * b
    m_ = l - 0.1055613458 * a - 0.0638541728 * b
    s_ = l - 0.0894841775 * a - 1.2914855480 * b

    {l3, m3, s3} = {l_ * l_ * l_, m_ * m_ * m_, s_ * s_ * s_}

    {4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3,
     -1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3,
     -0.0041960863 * l3 - 0.7034186147 * m3 + 1.7076147010 * s3}
  end

  defp cbrt(x) when x < 0, do: -:math.pow(-x, 1 / 3)
  defp cbrt(x), do: :math.pow(x, 1 / 3)

  # The sRGB transfer function (IEC 61966-2-1), extended to negative values by symmetry as
  # CSS Color 4 does, so an out-of-gamut channel round-trips.
  defp linear(c) when c < 0, do: -linear(-c)
  defp linear(c) when c <= 0.04045, do: c / 12.92
  defp linear(c), do: :math.pow((c + 0.055) / 1.055, 2.4)

  defp gamma(c) when c < 0, do: -gamma(-c)
  defp gamma(c) when c <= 0.0031308, do: 12.92 * c
  defp gamma(c), do: 1.055 * :math.pow(c, 1 / 2.4) - 0.055
end
