defmodule Visualize.ThemeColorsTest do
  @moduledoc """
  The theme's color table (spec/08 §7.1, #663, D-173): the CSS named colors under the
  default theme's names under a theme's own, the furniture and series as names, and the
  role colors folded into it as names by use (D-135, amended).
  """
  use ExUnit.Case, async: true

  import Visualize.Color, only: [color: 1]

  alias Visualize.{Color, Theme}

  test "a hue resolves through the theme's table, as a slot does" do
    assert Color.resolve(color(:red), Theme.default(), :css) == "var(--vis-red, #c23238)"
    assert Color.resolve(color(:red), Theme.dark(), :css) == "var(--vis-red, #ff8f8a)"
    assert Color.resolve(color(:red), Theme.dark(), :literal) == "#ff8f8a"
  end

  test "a name the theme does not hold is the CSS named color's" do
    assert Color.resolve(color(:steelblue), Theme.default(), :css) ==
             "var(--vis-steelblue, #4682b4)"

    assert Theme.css_name(:steelblue) == "--vis-steelblue"
  end

  test "a theme changes a value and adds names; a name in no part of the table raises" do
    theme = Theme.new(name: :house, colors: %{red: "#e00000", brand: "#123456"})
    assert Color.resolve(color(:red), theme, :literal) == "#e00000"
    assert Color.resolve(color(:brand), theme, :css) == "var(--vis-brand, #123456)"
    assert Theme.stylesheet(theme) =~ "\n  --vis-brand: #123456;\n"
    assert "brand" in Theme.color_names(theme)

    assert_raise ArgumentError, ~r/unknown theme slot :brand/, fn ->
      Color.resolve(color(:brand), Theme.default(), :css)
    end
  end

  # The membership test builds no list, and so may not drift from the list it stands for
  # (#704, D-184): every name of every built-in theme's table, a theme's own name, and the
  # words beside the table — a series past the theme's count, a palette name, a string.
  test "color_name?/2 answers exactly color_names/1's membership" do
    house = Theme.new(name: :house, colors: %{brand: "#123456"})

    for theme <- [house | Enum.map([:default, :dark, :color_safe, :print], &Theme.builtin/1)] do
      names = Theme.color_names(theme)
      assert Enum.all?(names, &Theme.color_name?(theme, &1))

      beside = [:"series_#{length(theme.series) + 1}", :series_0, :series_01, :thick, :nope]
      refute Enum.any?(beside, &Theme.color_name?(theme, &1))
      refute Theme.color_name?(theme, "red")
    end

    assert Theme.color_name?(house, :brand)
    refute Theme.color_name?(Theme.default(), :brand)
  end

  test "an entry may be a color value that resolves through the same table" do
    theme = Theme.new(colors: %{accent: color(:red), wash: {:intensity, color(:red), 0.5}})
    assert Color.resolve(color(:accent), theme, :css) == "var(--vis-accent, #c23238)"
    assert Color.resolve(color(:wash), theme, :literal) == "#c2323880"
  end

  test "the furniture and the series are names of the table" do
    theme = Theme.default()
    assert Color.resolve(color(:text), theme, :css) == Theme.resolve(theme, :text, :css)
    assert Color.resolve(color(:series_3), theme, :css) == "var(--vis-series-3, #c8373b)"
  end

  describe "the role colors are names by use (D-135, amended)" do
    test "every built-in theme resolves each role exactly as before" do
      expected = %{
        default: ~w(#4ca34b #bd7407 #c23238 #3b6fa8 #6f7480),
        dark: ~w(#4f924c #db8e1c #ff8f8a #7fb3e6 #b7bcc6),
        color_safe: ~w(#5996d6 #cd6012 #b92931 #3b6fa8 #6f7480),
        print: ~w(#5996d6 #cd6012 #b92931 #3b6fa8 #6f7480)
      }

      for {name, literals} <- expected,
          {role, literal} <- Enum.zip(Theme.role_names(), literals) do
        theme = Theme.builtin(name)
        assert Theme.resolve(theme, role, :literal) == literal
        assert Theme.resolve(theme, role, :css) == "var(--vis-#{role}, #{literal})"
      end
    end

    test "the status roles are their ramp positions, and follow the ramp" do
      theme = Theme.new(ramps: %{status: ~w(#5996d6 #cd6012 #b92931)})
      assert Theme.resolve(theme, :bad, :literal) == "#b92931"
      assert Theme.resolve(theme, {:ramp, :status, 1}, :css) == "var(--vis-bad, #b92931)"
    end

    test "a theme may set a role's color, which then stands apart from the ramp" do
      theme = Theme.new(colors: %{bad: "#d55e00"})
      assert Theme.resolve(theme, :bad, :css) == "var(--vis-bad, #d55e00)"
      assert Theme.resolve(theme, {:ramp, :status, 1}, :css) == "#c23238"
    end

    test "roles: is read as colors" do
      assert Theme.new(roles: %{info: "#2255aa"}).colors.info == "#2255aa"

      assert Theme.new(roles: %{info: "#2255aa"}, colors: %{info: "#2266bb"}).colors.info ==
               "#2266bb"
    end
  end
end
