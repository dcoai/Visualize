defmodule Visualize.ThemeContrastTest do
  @moduledoc """
  The contrast a theme guarantees (spec/08 §7.4, D-56): both built-in themes hold their
  floors against their own background, and every colour scheme keeps a usable colour on
  either theme.
  """
  use ExUnit.Case, async: true

  alias Visualize.{Color, Theme}
  alias Visualize.Scale.Color, as: Schemes

  @themes [Theme.default(), Theme.dark()]

  defp contrast(hex, %Theme{background: background}) do
    colour = Color.parse(hex)
    assert colour, "#{hex} does not parse"
    Color.contrast(colour, Color.parse(background))
  end

  for theme <- @themes do
    @theme theme

    test "the #{theme.name} theme: text 4.5:1, axis 3:1, every series 3:1, grid 1.2:1" do
      assert contrast(@theme.text, @theme) >= 4.5
      assert contrast(@theme.axis, @theme) >= 3.0
      assert contrast(@theme.grid, @theme) >= 1.2

      for colour <- @theme.series do
        ratio = contrast(colour, @theme)
        assert ratio >= 3.0, "#{colour} is #{Float.round(ratio, 2)}:1 on #{@theme.name}"
      end
    end

    # 3:1 on the dark theme; 2.5:1 on the light, where set2 (a pastel scheme) tops out at
    # 2.6:1 on white.
    @floor if(theme.name == :dark, do: 3.0, else: 2.5)

    test "on the #{theme.name} theme every scheme parses and keeps a colour at #{@floor}:1" do
      for scheme <- Schemes.schemes() do
        ratios = Enum.map(Schemes.scheme(scheme), &contrast(&1, @theme))
        assert Enum.max(ratios) >= @floor, "#{scheme} has no #{@floor}:1 colour on #{@theme.name}"
      end
    end
  end

  test "a scheme's lightest colour vanishes on the light theme and its darkest on the dark" do
    # The reason each theme carries its own palette (spec/08 §7.2).
    [light, dark] = @themes
    blues = Schemes.scheme(:blues)
    assert contrast(hd(blues), light) < 1.2
    assert contrast(List.last(blues), dark) < 2.0
  end
end
