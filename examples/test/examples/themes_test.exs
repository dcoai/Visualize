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
    for key <- @hosts do
      options = Hosts.options(String.to_existing_atom(key))
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

  defp literal(name, theme), do: Color.resolve(Color.color(name), theme, :literal)
end
