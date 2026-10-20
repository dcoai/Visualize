defmodule Examples.ThemesTest do
  @moduledoc """
  The chart pages' themes (spec/08 §7.2, spec/14 §12.6, #792, work item #794): one list of
  real `Visualize.Theme` values — the built-in themes with the gallery's font stack, and
  six host themes built with `Visualize.Theme.new/1` that hold every contract — looked up
  by key as a string.
  """
  use ExUnit.Case, async: true

  alias Examples.Themes
  alias Examples.Themes.Hosts
  alias Visualize.{Color, Theme}

  doctest Examples.Themes

  @hosts ~w(sunrise winter sunset fall spring summer)

  test "the list is the four built-in themes, then the six host themes" do
    assert Themes.keys() == ~w(default dark color_safe print) ++ @hosts

    for {key, builtin} <- [
          {"default", :default},
          {"dark", :dark},
          {"color_safe", :color_safe},
          {"print", :print}
        ] do
      assert Themes.theme(key) ==
               Theme.merge(Theme.builtin(builtin), font_family: Hosts.font_family())
    end
  end

  test "every host theme is built with Theme.new/1, under its name as a string, and holds every contract" do
    # The host's key is matched among `Hosts.keys/0`: `String.to_existing_atom/1` failed
    # whenever this test ran before anything had loaded `Examples.Themes.Hosts`.
    assert Enum.map(Hosts.keys(), &Atom.to_string/1) == @hosts

    for host <- Hosts.keys(), key = Atom.to_string(host) do
      options = Hosts.options(host)
      theme = Theme.new(options)

      assert Themes.theme(key) == theme
      assert theme.name == key
      assert Theme.check(theme) == :ok
      assert Theme.violations(theme) == []
    end
  end

  test "every host theme gives its own hues, its own title and grid, and its page's ramp" do
    default = Themes.default()

    for key <- @hosts, theme = Themes.theme(key) do
      for hue <- [:red, :amber, :green, :blue, :gray] do
        refute literal(hue, theme) == literal(hue, default), "#{key}: #{hue}"
      end

      assert literal(:info, theme) == literal(:blue, theme)
      assert literal(:neutral, theme) == literal(:gray, theme)
      refute Theme.style(theme, :title) == Theme.style(default, :title)
      refute Theme.style(theme, :grid) == Theme.style(default, :grid)
      assert List.last(theme.ramps.sequential) == hd(theme.series)
    end
  end

  test "every host theme's furniture holds the floors of spec/08 §7.4 on its page" do
    for key <- @hosts, theme = Themes.theme(key) do
      page = Color.parse(theme.background)

      for {slot, floor} <- [text: 4.5, axis: 3.0, grid: 1.2] do
        ratio = theme |> Map.fetch!(slot) |> Color.parse() |> Color.contrast(page)
        assert ratio >= floor, "#{key}: #{slot} is #{Float.round(ratio, 2)}:1"
      end

      refute theme.surface in [theme.grid, theme.background], key
    end
  end

  test "a key the list lacks is no theme and makes no atom; theme/1 falls to Default" do
    word = "no_theme_#{System.unique_integer([:positive])}"
    assert Themes.entry(word) == nil
    assert Themes.entry(:print) == nil
    assert Themes.theme(word) == Themes.default()
    assert Themes.theme(nil) == Themes.default()
    assert_raise ArgumentError, fn -> String.to_existing_atom(word) end
  end

  describe "Spring and Summer run apart (#797, work item #799)" do
    test "every series color of each holds 3:1 against its page (WCAG 1.4.11)" do
      for key <- ~w(spring summer), theme = Themes.theme(key) do
        page = Color.parse(theme.background)

        for hex <- theme.series do
          ratio = hex |> Color.parse() |> Color.contrast(page)
          assert ratio >= 3.0, "#{key}: #{hex} is #{Float.round(ratio, 2)}:1"
        end
      end
    end

    test "the two share no series color, and any two colors of each stay apart" do
      spring = Themes.theme("spring").series
      summer = Themes.theme("summer").series
      assert length(spring) == 8 and length(summer) == 8

      for one <- spring, other <- summer do
        assert apart(one, other) >= 0.05, "#{one} (Spring) and #{other} (Summer) read as one"
      end

      for series <- [spring, summer], one <- series, other <- series, one < other do
        assert apart(one, other) >= 0.06, "#{one} and #{other} are #{apart(one, other)} apart"
      end
    end

    test "Spring runs from a medium green to a dark yellow, Summer from a dark green to a blue" do
      # OKLCH hues: green about 145°, yellow about 86°, blue about 258°. Each series is two
      # sweeps of its run, the first four colors the whole of it, so a chart of four series
      # reads the run end to end.
      spring = Themes.theme("spring").series
      [first, _, _, last | _] = hues = Enum.map(spring, &hue/1)
      assert first in 140..155 and last in 80..92
      for sweep <- Enum.chunk_every(hues, 4), do: assert(sweep == Enum.sort(sweep, :desc))

      summer = Themes.theme("summer").series
      [first, _, _, last | _] = hues = Enum.map(summer, &hue/1)
      assert first in 140..155 and last in 250..265
      for sweep <- Enum.chunk_every(hues, 4), do: assert(sweep == Enum.sort(sweep))

      # Summer opens dark, Spring medium; Summer closes on a medium blue.
      assert lightness(hd(summer)) < 0.45 and lightness(hd(spring)) > 0.6
      assert lightness(Enum.at(summer, 3)) > 0.55
    end
  end

  defp oklab(hex), do: hex |> Color.parse() |> Color.to_oklab()

  defp apart(one, other) do
    {a, b} = {oklab(one), oklab(other)}
    :math.sqrt((a.l - b.l) ** 2 + (a.a - b.a) ** 2 + (a.b - b.b) ** 2)
  end

  defp hue(hex), do: round(Color.to_oklch(Color.parse(hex)).h)
  defp lightness(hex), do: oklab(hex).l

  defp literal(name, theme), do: Color.resolve(Color.color(name), theme, :literal)
end
