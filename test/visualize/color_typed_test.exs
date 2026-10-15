defmodule Visualize.ColorTypedTest do
  @moduledoc """
  The typed colors of spec/08 §1.9 (D-173): the values the helpers build, OKLab and OKLCH
  against published references, and every transform against values this test computes on
  its own — through CSS Color 4's XYZ route, not the library's direct LMS matrices — so a
  shared mistake cannot hide in both.
  """
  use ExUnit.Case, async: true

  import Visualize.Color,
    only: [
      color: 1,
      ramp: 2,
      intensity: 2,
      blend: 1,
      alpha: 2,
      lighten: 2,
      darken: 2,
      saturate: 2,
      contrast: 1
    ]

  alias Visualize.{Color, Theme}

  doctest Visualize.Color

  # -- an independent OKLab, by CSS Color 4's sample code -------------------------------

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

  defp mul(m, v),
    do:
      Enum.map(m, fn row ->
        row |> Enum.zip(v) |> Enum.map(fn {a, b} -> a * b end) |> Enum.sum()
      end)

  defp lin(c) when c <= 0.04045, do: c / 12.92
  defp lin(c), do: :math.pow((c + 0.055) / 1.055, 2.4)
  defp enc(c) when c <= 0.0031308, do: 12.92 * c
  defp enc(c), do: 1.055 * :math.pow(c, 1 / 2.4) - 0.055

  defp ref_oklab(hex) do
    %Color{r: r, g: g, b: b} = Color.parse(hex)

    [r, g, b]
    |> Enum.map(&lin(&1 / 255))
    |> then(&mul(@rgb_xyz, &1))
    |> then(&mul(@xyz_lms, &1))
    |> Enum.map(&:math.pow(&1, 1 / 3))
    |> then(&mul(@lms_oklab, &1))
  end

  # OKLab to sRGB channels in 0..255, asserting the color is in the gamut: a reference
  # value is only compared where no gamut mapping stands between the two.
  defp ref_rgb(lab) do
    rgb =
      @oklab_lms
      |> mul(lab)
      |> Enum.map(&(&1 * &1 * &1))
      |> then(&mul(@lms_xyz, &1))
      |> then(&mul(@xyz_rgb, &1))

    assert Enum.all?(rgb, &(&1 >= -1.0e-4 and &1 <= 1.0001)),
           "the reference color #{inspect(rgb)} is outside sRGB; choose another"

    Enum.map(rgb, &(enc(max(&1, 0.0)) * 255))
  end

  defp to_lch([l, a, b]) do
    h = :math.atan2(b, a) * 180 / :math.pi()
    [l, :math.sqrt(a * a + b * b), if(h < 0, do: h + 360, else: h)]
  end

  defp from_lch([l, c, h]) do
    rad = h * :math.pi() / 180
    [l, c * :math.cos(rad), c * :math.sin(rad)]
  end

  # A literal as `{r, g, b, alpha}`, each channel 0..255.
  defp channels(hex) do
    %Color{r: r, g: g, b: b, opacity: a} = Color.parse(hex)
    {r, g, b, a}
  end

  defp assert_rgb(hex, expected, alpha \\ 1.0) do
    {r, g, b, a} = channels(hex)

    for {got, want} <- Enum.zip([r, g, b], expected) do
      assert abs(got - want) <= 1,
             "#{hex}: channel #{got}, expected #{Float.round(want * 1.0, 2)}"
    end

    assert abs(a - alpha) <= 1 / 255 + 1.0e-9, "#{hex}: alpha #{a}, expected #{alpha}"
  end

  defp literal(value), do: Color.resolve(value, Theme.default(), :literal)

  # -- the values ------------------------------------------------------------------------

  describe "the helpers build data" do
    test "every helper takes the color first and pipes" do
      assert color(:blue) |> intensity(0.65) == {:intensity, {:color, :blue}, 0.65}
      assert ramp(:status, 1) == {:ramp, :status, 1}

      assert [color(:blue) |> intensity(0.65), color(:red)] |> blend() |> alpha(0.5) ==
               {:alpha, {:blend, [{:intensity, {:color, :blue}, 0.65}, {:color, :red}]}, 0.5}

      assert "#ff0000" |> lighten(0.1) |> darken(0.2) |> saturate(0.3) |> contrast() ==
               {:contrast, {:saturate, {:darken, {:lighten, "#ff0000", 0.1}, 0.2}, 0.3}}
    end

    test "a bare atom is refused as an operand, with the spelling to use" do
      assert_raise ArgumentError,
                   ~r/a bare atom is a style, not a color; write color\(:red\)/,
                   fn ->
                     intensity(:red, 0.5)
                   end

      assert_raise ArgumentError, ~r/write color\(:bad\)/, fn -> blend([color(:red), :bad]) end
      assert_raise ArgumentError, ~r/write color\(:text\)/, fn -> contrast(:text) end
    end

    test "every number is in 0..1, and a name is an atom" do
      for bad <- [-0.1, 1.5, :half, nil] do
        assert_raise ArgumentError, ~r/a number in 0\.\.1/, fn -> alpha(color(:red), bad) end
      end

      assert_raise ArgumentError, ~r/a color name is an atom/, fn -> color(nil) end
      assert_raise ArgumentError, ~r/a color name is an atom/, fn -> color("red") end
      assert_raise ArgumentError, ~r/a number in 0\.\.1/, fn -> ramp(:thermal, 2) end
      assert_raise ArgumentError, ~r/non-empty list/, fn -> blend([]) end
    end

    test "saturate/2 keeps its released meaning on a %Visualize.Color{}" do
      c = Color.rgb(200, 100, 100)
      %{h: h, s: s, l: l} = Color.to_hsl(c)
      assert Color.saturate(c, 1.2) == Color.hsl(h, s * 1.2, l)
      assert Color.saturate(c) == Color.hsl(h, s * 1.2, l)
      assert Color.desaturate(c) == Color.hsl(h, s * 0.8, l)
    end

    test "value?/1 reads every operand" do
      assert Color.value?(blend([intensity("#000", 0.2), ramp(:thermal, 0.5)]))
      assert Color.value?({:series, 3})
      refute Color.value?({:alpha, :red, 0.5})
      refute Color.value?({:blend, []})
      refute Color.value?({:lighten, color(:red), 2})
      refute Color.value?(:none)
    end
  end

  # -- OKLab and OKLCH --------------------------------------------------------------------

  describe "OKLab and OKLCH" do
    # Published values for the sRGB primaries (CSS Color 4, Ottosson 2020).
    @primaries [
      {"#ff0000", {0.62796, 0.22486, 0.12585}, {0.25768, 29.2339}},
      {"#00ff00", {0.86644, -0.23389, 0.1795}, {0.29483, 142.4953}},
      {"#0000ff", {0.45201, -0.03246, -0.31153}, {0.31321, 264.052}}
    ]

    test "the primaries convert to their published values" do
      for {hex, {l, a, b}, {c, h}} <- @primaries do
        lab = Color.to_oklab(Color.parse(hex))
        lch = Color.to_oklch(Color.parse(hex))
        assert_in_delta lab.l, l, 1.0e-4
        assert_in_delta lab.a, a, 1.0e-4
        assert_in_delta lab.b, b, 1.0e-4
        assert_in_delta lch.c, c, 1.0e-4
        assert_in_delta lch.h, h, 1.0e-2
      end
    end

    test "white is L 1 and a gray has no chroma" do
      assert_in_delta Color.to_oklab(Color.parse("#ffffff")).l, 1.0, 1.0e-6
      assert_in_delta Color.to_oklch(Color.parse("#808080")).c, 0.0, 1.0e-6
    end

    test "the library's matrices agree with CSS Color 4's XYZ route" do
      for hex <- ~w(#3b6fa8 #d9730d #c8373b #2f8f86 #e9f2fc #1b1e24 #bd7407) do
        %{l: l, a: a, b: b} = Color.to_oklab(Color.parse(hex))
        [rl, ra, rb] = ref_oklab(hex)
        assert_in_delta l, rl, 1.0e-6
        assert_in_delta a, ra, 1.0e-6
        assert_in_delta b, rb, 1.0e-6
      end
    end

    test "oklab/4 and oklch/4 are the inverses, within a channel's rounding" do
      for hex <- ~w(#3b6fa8 #d9730d #c8373b #000000 #ffffff) do
        %{l: l, a: a, b: b} = Color.to_oklab(Color.parse(hex))
        assert Color.to_hex(Color.oklab(l, a, b)) == hex
        %{l: l, c: c, h: h} = Color.to_oklch(Color.parse(hex))
        assert Color.to_hex(Color.oklch(l, c, h)) == hex
      end
    end
  end

  # -- the transforms ---------------------------------------------------------------------

  describe "intensity and blend, by CSS color-mix's rules" do
    test "intensity on its own is the color at that fraction of its alpha" do
      assert literal(intensity("#ff0000", 0.5)) == "#ff000080"
      assert literal(intensity(alpha("#3b6fa8", 0.5), 0.5)) == "#3b6fa840"
      assert literal(intensity("#3b6fa8", 1)) == "#3b6fa8"
    end

    test "two colors at full weight mix evenly in OKLab" do
      expected = ref_mix([{"#3b6fa8", 0.5}, {"#d9730d", 0.5}])
      assert_rgb(literal(blend(["#3b6fa8", "#d9730d"])), expected)
    end

    test "intensities are the weights, and a sum below 1 leaves the rest transparent" do
      value = blend([intensity("#3b6fa8", 0.3), intensity("#d9730d", 0.2)])
      expected = ref_mix([{"#3b6fa8", 0.6}, {"#d9730d", 0.4}])
      assert_rgb(literal(value), expected, 0.5)
    end

    test "weights summing above 1 are scaled to sum to 1, and stay opaque" do
      value = blend([intensity("#3b6fa8", 0.9), intensity("#d9730d", 0.6)])
      expected = ref_mix([{"#3b6fa8", 0.6}, {"#d9730d", 0.4}])
      assert_rgb(literal(value), expected)
    end

    test "a color without intensity counts as 1" do
      value = blend(["#3b6fa8", intensity("#d9730d", 0.5), intensity("#2f8f86", 0.5)])
      expected = ref_mix([{"#3b6fa8", 0.5}, {"#d9730d", 0.25}, {"#2f8f86", 0.25}])
      assert_rgb(literal(value), expected)
    end

    test "alpha is premultiplied: a transparent color adds weight but no hue" do
      assert_rgb(literal(blend([alpha("#ff0000", 0), "#0000ff"])), [0, 0, 255], 0.5)
    end

    test "a blend of nothing is transparent, and of one color is that color" do
      assert channels(literal(blend([intensity("#ff0000", 0)]))) |> elem(3) == 0.0
      assert literal(blend(["#3b6fa8"])) == "#3b6fa8"
    end

    test "names resolve through the theme before they mix" do
      theme = Theme.dark()
      by_name = Color.resolve(blend([color(:text), color(:background)]), theme, :literal)
      by_literal = Color.resolve(blend([theme.text, theme.background]), theme, :literal)
      assert by_name == by_literal
    end
  end

  describe "alpha, lighten, darken and saturate in OKLCH" do
    test "alpha sets the opacity, whatever it was" do
      assert literal(alpha("#3b6fa8", 0.25)) == "#3b6fa840"
      assert literal(alpha(intensity("#3b6fa8", 0.5), 0.8)) == "#3b6fa8cc"
      assert literal(alpha(alpha("#3b6fa8", 0.1), 1)) == "#3b6fa8"
    end

    test "lighten moves L toward 1 and darken toward 0, hue and chroma kept" do
      [l, c, h] = to_lch(ref_oklab("#3b6fa8"))
      assert_rgb(literal(lighten("#3b6fa8", 0.2)), ref_rgb(from_lch([l + (1 - l) * 0.2, c, h])))
      assert_rgb(literal(darken("#3b6fa8", 0.3)), ref_rgb(from_lch([l * 0.7, c, h])))
    end

    test "saturate moves chroma toward 0.4, CSS's 100%" do
      [l, c, h] = to_lch(ref_oklab("#8a6a4f"))

      assert_rgb(
        literal(saturate("#8a6a4f", 0.1)),
        ref_rgb(from_lch([l, c + (0.4 - c) * 0.1, h]))
      )
    end

    test "the ends: lighten and darken by 1 are white and black" do
      assert literal(lighten("#3b6fa8", 1)) == "#ffffff"
      assert literal(darken("#3b6fa8", 1)) == "#000000"
    end

    test "a result outside sRGB is gamut-mapped by chroma, keeping lightness and hue" do
      mapped = literal(saturate("#3b6fa8", 1))
      before = Color.to_oklch(Color.parse("#3b6fa8"))
      after_ = Color.to_oklch(Color.parse(mapped))
      assert_in_delta after_.l, before.l, 0.02
      # Clipping the last step moves hue a little; within a few degrees it is the same hue.
      assert_in_delta after_.h, before.h, 6
      assert after_.c > before.c
    end
  end

  describe "contrast" do
    test "the theme's ink over the color, as Visualize.Theme.ink/2 chooses it" do
      theme = Theme.default()
      assert literal(contrast("#3b6fa8")) == Theme.ink(theme, "#3b6fa8")
      assert literal(contrast(color(:axis))) == Theme.ink(theme, "#666666")
      assert literal(contrast("#ffd098")) == "#333333"
    end

    test "a translucent color is read over the background" do
      assert literal(contrast("#000000")) == "#ffffff"
      assert literal(contrast(intensity("#000000", 0.05))) == "#333333"
    end

    test "it is a literal in both modes" do
      assert Color.resolve(contrast("#000000"), Theme.default(), :css) == "#ffffff"
    end
  end

  describe "resolution of names" do
    test "a name resolves exactly as the theme's slot does, in both modes" do
      for theme <- [Theme.default(), Theme.dark()],
          slot <- Theme.color_slots(theme),
          mode <- [:css, :literal] do
        assert Color.resolve(color(slot), theme, mode) == Theme.resolve(theme, slot, mode)
      end
    end

    test "a series and a ramp position resolve as the theme's, a literal as written" do
      theme = Theme.default()

      assert Color.resolve({:series, 12}, theme, :css) ==
               Theme.resolve(theme, {:series, 12}, :css)

      assert Color.resolve(ramp(:status, 1), theme, :css) == "var(--vis-bad, #c23238)"
      assert Color.resolve("currentColor", theme, :css) == "currentColor"
    end

    test "an operand that is no color a transform can compute raises" do
      assert_raise ArgumentError, ~r/must resolve to a color/, fn ->
        literal(alpha("currentColor", 0.5))
      end
    end
  end

  # The mix of CSS color-mix for opaque colors at normalized weights, in sRGB 0..255.
  defp ref_mix(weighted) do
    weighted
    |> Enum.map(fn {hex, w} -> Enum.map(ref_oklab(hex), &(&1 * w)) end)
    |> Enum.zip_with(&Enum.sum/1)
    |> ref_rgb()
  end
end
