defmodule Visualize.ThemePaletteTest do
  @moduledoc """
  A theme's style palette (spec/08 §7.7, D-171): every built-in theme defines it and holds
  its contracts, each contract refuses a breaking entry naming the theme, the entry and the
  term, a missing name falls back to the default theme's entry whole, `style/2` and
  `style_names/1` read it, and the four built-in styles of spec/14 §3.3 are the theme's
  furniture styles — unchanged under every built-in theme.
  """
  use ExUnit.Case, async: true

  alias Visualize.{Chart, Theme}
  alias Visualize.Chart.{Frame, Schema, Style}

  @themes [Theme.default(), Theme.dark(), Theme.colour_safe(), Theme.print()]
  @roles [:good, :warning, :bad, :info, :neutral]
  @states [:hover, :focused, :selected, :active, :disabled, :muted, :emphasis, :breakpoint]
  @furniture [:axis, :grid, :label, :title, :caption, :value, :annotation]

  defp refusal(fields) do
    assert_raise(ArgumentError, fn -> Theme.new([name: :house] ++ fields) end).message
  end

  describe "the built-in themes" do
    test "every one defines every name of the palette and holds every contract" do
      for theme <- @themes do
        assert Theme.check(theme) == :ok, inspect(theme.name)
        assert Theme.violations(theme) == [], inspect(theme.name)
        assert theme.styles |> Map.keys() |> Enum.sort() == Enum.sort(Theme.style_names(theme))
      end
    end

    test "the names are ten style series, then the roles, the states and the furniture" do
      for theme <- @themes do
        series = Enum.map(1..10, &:"style_#{&1}")
        assert Theme.style_names(theme) == series ++ @roles ++ @states ++ @furniture
      end
    end

    test "the four built-in styles are exactly the nodes of spec/14 §3.3, on every theme" do
      label = %{fill: :text, font_family: :font_family, font_size: :label_size}

      for theme <- @themes do
        assert Theme.style(theme, :axis) ==
                 %{stroke: :axis, fill: :text, font_family: :font_family, font_size: :font_size}

        assert Theme.style(theme, :grid) == %{stroke: :grid}
        assert Theme.style(theme, :label) == label

        assert Theme.style(theme, :title) ==
                 Map.merge(label, %{font_size: :title_size, font_weight: :bold})
      end
    end

    test "the default :muted is the board's dim and :selected is heavier only (#638)" do
      for theme <- [Theme.default(), Theme.dark(), Theme.colour_safe(), Theme.print()] do
        assert Theme.style(theme, :muted) == %{opacity: 0.25}
        # No colour and no outline of its own, so a stroked mark keeps its paint.
        assert Theme.style(theme, :selected) == %{stroke_width: 2}
      end
    end

    test "no two of the ten style series share both symbol and dash" do
      theme = Theme.default()

      looks =
        for k <- 1..10, s = Theme.style(theme, {:style, k}), do: {s.symbol, s[:stroke_dasharray]}

      assert length(Enum.uniq(looks)) == 10
    end
  end

  describe "style/2" do
    test "a role's :cue is its dash and glyph, and a solid dash is no key" do
      for theme <- @themes, role <- @roles do
        entry = Theme.style(theme, role)
        cue = Theme.cue(role)
        assert entry.fill == role and entry.stroke == role
        assert entry.symbol == cue.glyph
        assert Map.get(entry, :stroke_dasharray) == cue.dash
      end

      refute Map.has_key?(Theme.style(Theme.default(), :good), :stroke_dasharray)
    end

    test "{:style, i} cycles over the style series as {:series, i} cycles over the colours" do
      theme = Theme.default()
      assert Theme.style(theme, {:style, 1}) == Theme.style(theme, :style_1)
      assert Theme.style(theme, {:style, 11}) == Theme.style(theme, :style_1)
      assert Theme.style(theme, {:style, 23}) == Theme.style(theme, :style_3)
    end

    test "a theme's own style series is its length, and {:style, i} cycles over it" do
      a = %{fill: {:series, 1}, symbol: :circle}
      b = %{fill: {:series, 2}, symbol: :square}
      theme = %{Theme.default() | styles: %{style_1: a, style_2: b}}

      assert Enum.take(Theme.style_names(theme), 3) == [:style_1, :style_2, :good]
      assert Theme.style(theme, {:style, 3}) == a
      assert Theme.check(theme) == :ok

      assert_raise ArgumentError, ~r/unknown palette style :style_3/, fn ->
        Theme.style(theme, :style_3)
      end
    end

    test "an unknown name, or a style index that is not a positive integer, raises" do
      assert_raise ArgumentError, ~r/unknown palette style :sparkle of theme :default/, fn ->
        Theme.style(Theme.default(), :sparkle)
      end

      assert_raise ArgumentError, ~r/got \{:style, 0\}/, fn ->
        Theme.style(Theme.default(), {:style, 0})
      end
    end
  end

  describe "fallback" do
    test "a theme lacking a name takes the default theme's entry, whole" do
      theme = %{Theme.dark() | styles: %{muted: %{opacity: 0.5}}}

      assert Theme.style(theme, :muted) == %{opacity: 0.5}
      assert Theme.style(theme, :selected) == Theme.style(Theme.default(), :selected)
      assert Theme.style(theme, :style_4) == Theme.style(Theme.default(), :style_4)
      assert Theme.style_names(theme) == Theme.style_names(Theme.default())
    end

    test "a theme with no styles at all falls back for every name" do
      theme = %{Theme.default() | styles: nil}

      for name <- Theme.style_names(Theme.default()) do
        assert Theme.style(theme, name) == Theme.style(Theme.default(), name)
      end
    end

    test "new/1 and merge/2 merge styles key by key, as ramps and roles" do
      theme = Theme.merge(Theme.dark(), styles: %{selected: %{stroke_width: 4}})
      assert Theme.style(theme, :selected) == %{stroke_width: 4}
      assert Theme.style(theme, :hover) == Theme.style(Theme.dark(), :hover)
      assert Theme.style(Theme.new(styles: [muted: %{opacity: 0.1}]), :muted) == %{opacity: 0.1}
    end
  end

  describe "contracts refuse a breaking entry, naming the theme, the entry and the term" do
    test "a role paints with its own role, or a status role's ramp position" do
      assert refusal(styles: %{bad: %{fill: :good}}) ==
               "theme :house: style :bad breaks its contract: a role style paints with its own " <>
                 "role, so fill must be :bad or absent; got :good"

      assert refusal(styles: %{info: %{stroke: "#3b6fa8"}}) =~
               ~r/style :info .*stroke must be :info or absent; got "#3b6fa8"/

      assert Theme.new(styles: %{warning: %{fill: {:ramp, :status, 0.5}}}).styles.warning ==
               %{fill: {:ramp, :status, 0.5}}

      assert refusal(styles: %{warning: %{fill: {:ramp, :status, 1}}}) =~
               ~r/fill must be :warning or absent; got \{:ramp, :status, 1\}/

      assert Theme.new(styles: %{neutral: %{stroke_width: 2}}).styles.neutral == %{
               stroke_width: 2
             }
    end

    test "a state style changes a non-hue key, never only a colour" do
      message = refusal(styles: %{hover: %{stroke: :bad}})
      assert message =~ "theme :house: style :hover breaks its contract"
      assert message =~ "a state style must read without hue"
      assert message =~ "got %{stroke: :bad}"

      # A value that leaves the object as it is changes nothing.
      for neutral <- [
            %{opacity: 1},
            %{stroke_style: :single},
            %{effect: :none},
            %{stroke_dasharray: ""}
          ] do
        assert refusal(styles: %{selected: neutral}) =~ "style :selected breaks its contract"
      end

      for change <- [
            %{stroke_width: 2},
            %{stroke_style: :outside},
            %{opacity: 0.5},
            %{fill_opacity: 0.2},
            %{stroke_dasharray: "2 2"},
            %{effect: :shadow}
          ] do
        assert Theme.new(styles: %{active: change}).styles.active == change
      end
    end

    test "neighbouring style series differ in a non-hue key, the wrap included" do
      a = %{fill: {:series, 1}, stroke: {:series, 1}, symbol: :circle}
      b = %{fill: {:series, 2}, stroke: {:series, 2}, symbol: :square}
      same_as_a = %{fill: {:series, 3}, stroke: {:series, 3}, symbol: :circle}

      assert refusal(styles: %{style_1: a, style_2: %{b | symbol: :circle}}) =~
               "style :style_2 breaks its contract: neighbouring style series must differ in a " <>
                 "key besides fill and stroke (a dash, a symbol, a weight), but :style_1 and " <>
                 ":style_2 differ only in hue"

      # A theme of exactly three entries is a struct, so the wrap is :style_3 beside :style_1.
      theme = %{Theme.default() | styles: %{style_1: a, style_2: b, style_3: same_as_a}}

      assert {:error, {:style, :style_1}, message} = Theme.check(theme)
      assert message =~ ":style_3 and :style_1 differ only in hue"
    end

    test "a style series of one entry is its own neighbour" do
      theme = %{Theme.default() | styles: %{style_1: %{fill: {:series, 1}, symbol: :circle}}}
      assert {:error, {:style, :style_1}, message} = Theme.check(theme)
      assert message =~ "has itself for a neighbour"
    end

    test "a text furniture entry resolves a font family and a size" do
      assert refusal(styles: %{caption: %{fill: :text, font_size: :font_size}}) ==
               "theme :house: style :caption breaks its contract: a text style must resolve a " <>
                 "font family, a string or :font_family; got font_family: nil"

      assert refusal(styles: %{value: %{font_family: "Inter", font_size: 0}}) =~
               ~r/style :value .*must resolve a size, .*got font_size: 0/

      assert refusal(styles: %{axis: %{font_family: :font_family, font_size: :grid}}) =~
               ~r/style :axis .*got font_size: :grid/

      assert Theme.new(styles: %{title: %{font_family: "Inter", font_size: 20}}).styles.title ==
               %{font_family: "Inter", font_size: 20}
    end

    test ":grid resolves a stroke" do
      assert refusal(styles: %{grid: %{stroke_width: 1}}) ==
               "theme :house: style :grid breaks its contract: the grid must resolve a stroke, " <>
                 "a colour other than :none; got nil"

      assert refusal(styles: %{grid: %{stroke: :none}}) =~ "got :none"

      assert Theme.new(styles: %{grid: %{stroke: :axis, stroke_width: 0.5}}).styles.grid.stroke ==
               :axis
    end

    test "an entry is flat: no extends" do
      assert refusal(styles: %{emphasis: %{extends: :selected, stroke_width: 3}}) ==
               "theme :house: style :emphasis breaks its contract: a palette entry is flat and " <>
                 "may not use extends, got extends: :selected"
    end

    test "an entry is a style node" do
      assert refusal(styles: %{muted: 0.25}) =~
               "style :muted breaks its contract: an entry is a style node, a map of style keys, got 0.25"
    end

    test ":cue only on a role's dash or symbol" do
      assert refusal(styles: %{hover: %{stroke_width: 2, stroke_dasharray: :cue}}) =~
               ~r/style :hover .*:hover is not a role; got stroke_dasharray: :cue/

      assert refusal(styles: %{bad: %{fill: :bad, stroke: :cue}}) =~
               ~r/style :bad .*only on stroke_dasharray or symbol; got stroke: :cue/
    end

    test "no unknown names, and no gap in the style series" do
      assert refusal(styles: %{sparkle: %{opacity: 0.5}}) =~
               ~r/^theme :house: style :sparkle breaks its contract: is not a name of the palette; a theme cannot add one/

      assert refusal(styles: %{style_12: %{symbol: :star}}) =~
               "style :style_12 breaks its contract: the style series runs :style_1 to :style_n " <>
                 "with no gap, and :style_11 is missing below :style_12"
    end

    test "violations/1 names every breaking entry, after the ramps and roles" do
      theme = %{
        Theme.default()
        | roles: %{neutral: "#ff0000"},
          styles: %{bad: %{fill: :good}, hover: %{stroke: :bad}, sparkle: %{}}
      }

      assert theme |> Theme.violations() |> Enum.map(&elem(&1, 0)) ==
               [{:role, :neutral}, {:style, :bad}, {:style, :hover}, {:style, :sparkle}]

      assert {:error, {:role, :neutral}, _} = Theme.check(theme)
    end
  end

  describe "the built-in styles of spec/14 §3.3 are the theme's furniture" do
    @size {300, 200}

    defp design(extra \\ %{}) do
      Chart.from_map!(
        Map.merge(
          %{
            version: 2,
            frames: %{main: %{kind: :cartesian, scales: %{}}},
            labels: [%{anchor: :title, text: "Uptime"}]
          },
          extra
        )
      )
    end

    defp title_weight(chart, theme) do
      {:ok, applied} = Chart.apply(chart, sources: %{}, theme: theme, size: @size)

      [_, weight] =
        Regex.run(~r/<text[^>]*font-weight="([^"]+)"[^>]*>Uptime/, Chart.render(applied))

      weight
    end

    test "Schema.builtin_styles/0 still answers the four, among the palette a design reaches" do
      assert Schema.builtin_styles() == [:axis, :grid, :label, :title]
      # Every palette name is a style reference (spec/14 §3.3, #637).
      names = Style.all(%{}) |> Map.keys() |> Enum.sort()
      assert names == Enum.sort(Visualize.Theme.style_names(Visualize.Theme.default()))
      assert Enum.all?(Schema.builtin_styles(), &(&1 in names))
    end

    test "the frame reads them from its theme, and every built-in theme's are today's" do
      for theme <- @themes do
        frame = Frame.new(design(), size: @size, theme: theme)

        for name <- Schema.builtin_styles() do
          assert frame.styles[name] == Style.builtin(name), "#{theme.name} #{name}"
        end
      end
    end

    test "a host theme's :title restyles every title drawn under it" do
      house =
        Theme.new(
          name: :house,
          styles: %{
            title: %{fill: :text, font_family: :font_family, font_size: 20, font_weight: 300}
          }
        )

      assert title_weight(design(), Theme.default()) == "bold"
      assert title_weight(design(), house) == "300"
    end

    test "a design's own :title still replaces the theme's whole" do
      house =
        Theme.new(
          name: :house,
          styles: %{
            title: %{fill: :text, font_family: :font_family, font_size: 20, font_weight: 300}
          }
        )

      own = %{styles: %{title: %{fill: :text, font_size: 14, font_weight: :medium}}}
      assert title_weight(design(own), house) == "500"
    end
  end
end
