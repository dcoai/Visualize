defmodule Visualize.ThemeTest do
  @moduledoc "`Visualize.Theme` (spec/08 §7, D-55): slots, both modes, both themes' contrast."
  use ExUnit.Case, async: true

  alias Visualize.{Backend, Color, Theme}

  doctest Theme

  @fixed ~w(axis grid text background font_family font_size label_size title_size)a

  describe "slots" do
    test "series first, then the fixed slots, for both themes" do
      series = Enum.map(1..10, &:"series_#{&1}")
      assert Theme.slots(Theme.default()) == series ++ @fixed
      assert Theme.slots(Theme.dark()) == series ++ @fixed
      assert Theme.slots(Theme.new(series: ["#000"])) == [:series_1 | @fixed]
    end

    test "{:series, i} cycles over the palette" do
      theme = Theme.new(series: ~w(#111 #222 #333))
      assert Theme.series_slot(theme, 1) == :series_1
      assert Theme.series_slot(theme, 3) == :series_3
      assert Theme.series_slot(theme, 4) == :series_1
      assert Theme.resolve(theme, {:series, 5}, :literal) == "#222"
      assert Theme.resolve(theme, {:series, 5}, :css) == "var(--vis-series-2, #222)"
      assert_raise ArgumentError, fn -> Theme.series_slot(theme, 0) end
    end

    test "an unknown slot, or a series slot beyond the palette, is an ArgumentError" do
      theme = Theme.new(series: ~w(#111 #222))
      assert_raise ArgumentError, fn -> Theme.resolve(theme, :series_3, :literal) end
      assert_raise ArgumentError, fn -> Theme.resolve(theme, :series_0, :css) end
      assert_raise ArgumentError, fn -> Theme.resolve(theme, :accent, :css) end
      assert_raise ArgumentError, fn -> Theme.css_name(:accent) end
    end
  end

  describe "resolve/3" do
    test ":literal is the stored value, a number for a size" do
      theme = Theme.default()
      assert Theme.resolve(theme, :series_1, :literal) == "#3b6fa8"
      assert Theme.resolve(theme, :axis, :literal) == "#666666"
      assert Theme.resolve(theme, :font_family, :literal) == "sans-serif"
      assert Theme.resolve(theme, :font_size, :literal) == 10
      assert Theme.resolve(theme, :label_size, :literal) == 12
      assert Theme.resolve(theme, :title_size, :literal) == 16
    end

    test ":css is a var() reference carrying the literal, sizes in px" do
      theme = Theme.dark()
      assert Theme.resolve(theme, :series_10, :css) == "var(--vis-series-10, #b7bcc6)"
      assert Theme.resolve(theme, :background, :css) == "var(--vis-background, #1b1e24)"
      assert Theme.resolve(theme, :font_family, :css) == "var(--vis-font-family, sans-serif)"
      assert Theme.resolve(theme, :font_size, :css) == "var(--vis-font-size, 10px)"
    end

    test "css_name hyphenates the slot" do
      assert Theme.css_name(:series_1) == "--vis-series-1"
      assert Theme.css_name(:font_family) == "--vis-font-family"
    end

    test "mode/1 is :css for the SVG backend only" do
      assert Theme.mode(nil) == :css
      assert Theme.mode(:svg) == :css
      assert Theme.mode(Backend.SVG) == :css
      assert Theme.mode(:canvas) == :literal
      assert Theme.mode(Backend.Canvas) == :literal
    end
  end

  describe "new/1 and merge/2" do
    test "replace fields over the default or any theme" do
      theme = Theme.new(font_family: "Inter, sans-serif", axis: "#123456")
      assert theme.name == :default
      assert theme.font_family == "Inter, sans-serif"
      assert theme.series == Theme.default().series
      assert Theme.merge(Theme.dark(), name: :night).name == :night
      assert Theme.merge(Theme.dark(), name: :night).background == "#1b1e24"
    end

    test "an unknown field is a KeyError and an empty series an ArgumentError" do
      assert_raise KeyError, fn -> Theme.new(accent: "#fff") end
      assert_raise ArgumentError, fn -> Theme.new(series: []) end
    end
  end

  describe "stylesheet/1" do
    test "declares every slot under the theme's class, sizes in px" do
      css = Theme.stylesheet(Theme.dark())
      assert String.starts_with?(css, ".vis-theme-dark {\n  --vis-series-1: #7fb3e6;\n")
      assert css =~ "\n  --vis-background: #1b1e24;\n"
      assert css =~ "\n  --vis-font-family: sans-serif;\n"
      assert String.ends_with?(css, "  --vis-title-size: 16px;\n}\n")
      assert length(String.split(css, "\n  --vis-")) == 1 + length(Theme.slots(Theme.dark()))
    end
  end

  describe "contrast (spec/08 §7.2)" do
    for name <- [:default, :dark] do
      test "the #{name} theme holds its floors against its background" do
        theme = apply(Theme, unquote(name), [])
        bg = Color.parse(theme.background)
        against = fn hex -> Color.contrast(Color.parse(hex), bg) end

        assert against.(theme.text) >= 4.5
        assert against.(theme.axis) >= 3.0
        assert against.(theme.grid) >= 1.2

        for colour <- theme.series do
          assert against.(colour) >= 3.0, "#{colour} is #{against.(colour)} on #{theme.name}"
        end
      end
    end
  end
end
