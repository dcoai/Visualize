defmodule Visualize.Chart.StyleListsTest do
  @moduledoc """
  A list of styles anywhere a style goes (spec/14 §2.6, §3.5, §3.6, #658, D-172): a
  `styles` entry, `extends`, a theme palette entry and a site each stack a list left to
  right by the merge rule; a cycle through names, lists or `extends` is `:cycle`; and the
  precedence order of §3.7 holds where the library lays a layer itself.
  """
  use ExUnit.Case, async: true

  alias Visualize.{Chart, Theme}
  alias Visualize.Chart.{Style, Validator}

  @design %{version: 3, frames: %{main: %{kind: :cartesian}}}

  describe "a list in every style position" do
    test "a styles entry names a composition, or another style" do
      styles = Style.all(%{bad_bold: [:bad, :bold], alert: :bad})

      assert Style.node(styles, :bad_bold) ==
               Style.node(styles, [:bad, :bold])

      assert Style.node(styles, :bad_bold).font_weight == :bold
      assert Style.node(styles, :bad_bold).stroke == {:color, :bad}
      assert Style.node(styles, :alert) == Style.node(styles, :bad)
    end

    test "extends takes a list, stacked before the style's own parts" do
      styles = Style.all(%{quiet_bad: %{extends: [:bad, :bold], fill: :none}})
      node = Style.node(styles, :quiet_bad)

      assert node.fill == :none
      assert node.font_weight == :bold
      assert node.stroke == {:color, :bad} and node.stroke_dasharray == Theme.cue(:bad).dash
    end

    test "a list nests: a named composition inside a site's list" do
      styles = Style.all(%{bad_bold: [:bad, :bold]})
      node = Style.node(styles, [:bad_bold, :outline, %{stroke: %{width: 4}}])
      assert node.fill == :none and node.font_weight == :bold and node.stroke_width == 4
    end

    test "the validator accepts lists and names where a named style goes, and they round-trip" do
      design =
        Map.put(@design, :styles, %{
          bad_bold: [:bad, :bold],
          alert: :bad,
          quiet: %{extends: [:muted, :thin], opacity: 0.5},
          local: [:bad, %{stroke: %{width: 3}}]
        })

      assert Validator.validate(design) == :ok
      chart = Chart.from_map!(design)
      assert chart.styles.local == [:bad, %{stroke: %{width: 3}}]
      {:ok, json} = Chart.to_json(chart)
      assert Chart.from_json(json) == {:ok, chart}
    end

    test "a name in a list is a reference like any other" do
      design = Map.put(@design, :styles, %{s: [:bad, :nope], t: %{extends: [:bold, :none_such]}})

      assert {:error, errors} = Validator.validate(design)
      assert {[:styles, :s, 1], {:undeclared, :style, :nope}} in errors
      assert {[:styles, :t, :extends, 1], {:undeclared, :style, :none_such}} in errors
    end
  end

  describe "a cycle through names, lists or extends" do
    test "is :cycle at the path of every style on it" do
      design =
        Map.put(@design, :styles, %{
          a: [:b],
          b: %{extends: :a},
          c: :c,
          d: %{extends: [:bold, :e]},
          e: [:d],
          fine: [:a]
        })

      assert {:error, errors} = Validator.validate(design)

      assert Enum.sort(for {path, :cycle} <- errors, do: path) ==
               [[:styles, :a], [:styles, :b], [:styles, :c], [:styles, :d], [:styles, :e]]
    end

    test "and raises at resolution" do
      styles = Style.all(%{a: [:b], b: %{extends: :a}})

      assert_raise ArgumentError, ~r/style :a reaches itself/, fn -> Style.node(styles, :a) end
    end
  end

  describe "a theme's palette entry may be a list" do
    test "of palette names and nodes, held to its contract by what it stacks into" do
      theme = Theme.new(name: :house, styles: %{emphasis: [:bold, :thick]})

      assert Theme.style(theme, :emphasis) == %{font: %{weight: :bold}, stroke: %{width: 3}}

      rule =
        Theme.new(
          name: :rule,
          styles: %{
            bad: [
              %{fill: :bad, stroke: %{color: :bad, dash: :cue}},
              %{marker: %{shape: :cue, size: 90}}
            ]
          }
        )

      assert Theme.style(rule, :bad).marker == %{shape: Theme.cue(:bad).glyph, size: 90}
    end

    test "a name the palette lacks, a list that reaches itself, or a state with no non-hue change is refused" do
      assert_raise ArgumentError, ~r/:sparkle in a list is not a name of the palette/, fn ->
        Theme.new(name: :house, styles: %{emphasis: [:bold, :sparkle]})
      end

      assert_raise ArgumentError, ~r/a list that reaches itself through :emphasis/, fn ->
        Theme.new(name: :house, styles: %{emphasis: [:bold, :emphasis]})
      end

      assert_raise ArgumentError, ~r/style :hover breaks its contract: a state style/, fn ->
        Theme.new(name: :house, styles: %{hover: [:bold, %{stroke: :text}]})
      end
    end

    test "an inline theme's list entry validates" do
      design = Map.put(@design, :theme, %{styles: %{emphasis: [:bold, :thick]}})
      assert Validator.validate(design) == :ok

      design = Map.put(@design, :theme, %{styles: %{emphasis: [:bold, 7]}})

      assert {:error, [{[:theme, :styles, :emphasis, 1], {:type, _}} | _]} =
               Validator.validate(design)
    end
  end

  describe "precedence (spec/14 §3.7)" do
    # The board's selection is a view state laid through a field (spec/15 §13.2).
    defp pick(state),
      do: fn
        {:field, :state} -> state
        {:field, :kind} -> :bad
      end

    test "a view state is laid at its layer: over the data's choice, under the local edit" do
      styles = Style.all(%{selected: %{stroke: %{width: 6}, opacity: 0.9}})

      stack =
        Style.with_state([:style_1, {:field, :kind}, %{stroke: %{width: 2}}], {:field, :state})

      assert stack == [:style_1, {:field, :kind}, {:field, :state}, %{stroke: %{width: 2}}]

      node = Style.node(styles, stack, pick(:selected))
      # The field-chosen style (5) over the named one (4): the bad color.
      assert node.stroke == {:color, :bad}
      # The view state (7) over the data: its opacity.
      assert node.opacity == 0.9
      # The local edit (8) over the state: its width.
      assert node.stroke_width == 2
    end

    test "the design's entry of a palette name over the theme's, and a named style under a field-chosen one" do
      styles = Style.all(%{bad: %{stroke: %{color: "#900"}}})
      node = Style.node(styles, [:style_2, {:field, :kind}], pick(nil))
      assert node.stroke == "#900"
      # What the field-chosen style leaves alone is the named style's.
      assert node.symbol == :square
    end

    test "with_state keeps a stack with no local edit's order, the state last" do
      assert Style.with_state([:a, {:field, :k}], {:field, :s}) == [
               :a,
               {:field, :k},
               {:field, :s}
             ]
    end
  end
end
