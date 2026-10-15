defmodule Visualize.ColorShadeTest do
  @moduledoc """
  `shade(c, n)` (spec/08 §1.9, #667, D-173): one OKLCH curve for both modes, steps a theme
  pins, and the grammar, codec and contracts that carry them.
  """
  use ExUnit.Case, async: true

  import Visualize.Color, only: [color: 1, shade: 2, alpha: 2]

  alias Visualize.{Chart, Color, Theme}
  alias Visualize.Test.CssColor

  @brand Theme.new(name: :brand, colors: %{red: %{500 => "#d62728", 100 => "#fde8e8"}})

  defp oklch(hex), do: Color.to_oklch(Color.parse(hex))

  describe "the curve" do
    test "500 is the color, and the curve's numbers are the spec's" do
      assert Color.resolve(shade("#3b6fa8", 500), Theme.default(), :literal) == "#3b6fa8"
      assert {0.97, 0.8, k} = Visualize.Color.Typed.curve(100)
      assert_in_delta k, 0.36, 1.0e-9
      assert Visualize.Color.Typed.curve(1000) == {0.2, 1.0, 0.0}
    end

    test "a step toward white or black moves lightness by u and eases chroma by 1 − u²" do
      base = oklch("#3b6fa8")

      for {n, toward, u} <- [{100, 0.97, 0.8}, {300, 0.97, 0.4}, {700, 0.2, 0.4}, {900, 0.2, 0.8}] do
        got = oklch(Color.resolve(shade("#3b6fa8", n), Theme.default(), :literal))
        assert_in_delta got.l, base.l + (toward - base.l) * u, 0.005
        assert_in_delta got.c, base.c * (1 - u * u), 0.005
        if got.c > 0.02, do: assert_in_delta(got.h, base.h, 2)
      end
    end

    test "the ends are near white and near black, without chroma" do
      white = oklch(Color.resolve(shade(color(:red), 0), Theme.default(), :literal))
      black = oklch(Color.resolve(shade(color(:red), 1000), Theme.default(), :literal))
      assert_in_delta white.l, 0.97, 0.005
      assert_in_delta black.l, 0.2, 0.005
      assert white.c < 0.005 and black.c < 0.005
    end

    test "it pipes like every transform, and refuses a step outside 0..1000" do
      assert color(:red) |> shade(700) |> alpha(0.8) ==
               {:alpha, {:shade, {:color, :red}, 700}, 0.8}

      assert_raise ArgumentError, ~r/a step in 0\.\.1000/, fn -> shade(color(:red), 1200) end
      assert_raise ArgumentError, ~r/write color\(:red\)/, fn -> shade(:red, 100) end
    end
  end

  describe "the two modes agree" do
    test "an unpinned step's CSS evaluates to its literal" do
      for theme <- [Theme.default(), Theme.dark(), @brand],
          value <- [
            shade(color(:blue), 100),
            shade(color(:blue), 300),
            shade(color(:blue), 700),
            shade("#2f8f86", 900)
          ] do
        css = Color.resolve(value, theme, :css)
        {r, g, b, _a} = CssColor.eval(css)
        %Color{r: lr, g: lg, b: lb} = Color.parse(Color.resolve(value, theme, :literal))

        for {got, want} <- [{lr, r}, {lg, g}, {lb, b}],
            do: assert(abs(got - want) <= 1, "#{css}: #{inspect({r, g, b})}")
      end
    end

    test "the CSS is a relative color on the curve's numbers, or the color at 500" do
      assert Color.resolve(shade(color(:blue), 100), Theme.default(), :css) ==
               "oklch(from var(--vis-blue, #3b6fa8) calc(l + (0.97 - l) * 0.8) calc(c * 0.36) h / alpha)"

      assert Color.resolve(shade(color(:blue), 700), Theme.default(), :css) ==
               "oklch(from var(--vis-blue, #3b6fa8) calc(l - (l - 0.2) * 0.4) calc(c * 0.84) h / alpha)"

      assert Color.resolve(shade(color(:blue), 500), Theme.default(), :css) ==
               "var(--vis-blue, #3b6fa8)"
    end
  end

  describe "a theme pins steps" do
    test "its step 500 is the name's color, a pinned step its own property" do
      assert Color.resolve(color(:red), @brand, :css) == "var(--vis-red, #d62728)"
      assert Color.resolve(shade(color(:red), 100), @brand, :literal) == "#fde8e8"
      assert Color.resolve(shade(color(:red), 100), @brand, :css) == "var(--vis-red-100, #fde8e8)"
      assert Color.resolve(shade(color(:red), 500), @brand, :css) == "var(--vis-red, #d62728)"
      assert Theme.stylesheet(@brand) =~ "\n  --vis-red: #d62728;\n  --vis-red-100: #fde8e8;\n"
    end

    test "an unpinned step is computed from step 500" do
      computed = Color.resolve(shade(color(:red), 300), @brand, :literal)
      assert computed == Color.resolve(shade("#d62728", 300), @brand, :literal)
    end

    test "pinned steps hold their contract" do
      assert_raise ArgumentError,
                   ~r/color :brand breaks its contract: pinned steps must include 500/,
                   fn ->
                     Theme.new(colors: %{brand: %{100 => "#fde8e8"}})
                   end

      assert_raise ArgumentError, ~r/a pinned step is an integer in 0\.\.1000, got 1100/, fn ->
        Theme.new(colors: %{brand: %{500 => "#d62728", 1100 => "#000000"}})
      end

      assert_raise ArgumentError, ~r/a pinned step is a color string/, fn ->
        Theme.new(colors: %{brand: %{500 => "#d62728", 100 => :pale}})
      end
    end
  end

  describe "the grammar and the codec" do
    test "a design's shade validates, renders and round-trips through JSON as $shade" do
      design = %{
        version: 3,
        sources: %{s: %{fields: [:x]}},
        styles: %{pale: %{fill: shade(color(:red), 100)}},
        frames: %{main: %{kind: :cartesian}}
      }

      chart = Chart.from_map!(design)
      {:ok, json} = Chart.to_json(chart)
      assert json =~ ~s({"$shade":[{"$color":"red"},100]})
      assert {:ok, back} = Chart.from_json(json)
      assert back.styles.pale.fill.color == shade(color(:red), 100)
    end

    test "a theme document carries its pinned steps as $steps" do
      {:ok, json} = Chart.Theme.to_json(@brand)
      assert json =~ ~s("red":{"$steps":[[100,"#fde8e8"],[500,"#d62728"]]})
      assert Chart.Theme.from_json(json) == {:ok, @brand}
    end
  end
end
