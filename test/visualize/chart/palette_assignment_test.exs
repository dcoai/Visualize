defmodule Visualize.Chart.PaletteAssignmentTest do
  @moduledoc """
  Assigning the theme's style palette (spec/14 §3.3, §3.6, §4.3, §9.3, #637, D-171): by
  name — at a site, in a stack and under `extends`, a design's entry winning — and by data,
  through an ordinal or threshold scale whose range is styles, laid per datum by a
  `{:scale, name, field}` entry of a mark's stack; stored themes carrying their palette;
  and every fault the validator names for a misuse. The SVG (`:css`) and the canvas
  (`:literal`) draw the same resolved style, and a theme swap restyles it.
  """
  use ExUnit.Case, async: true

  import Visualize.Chart, only: [fact: 3]

  alias Visualize.Chart
  alias Visualize.Chart.{Frame, Mark, Validator}
  alias Visualize.Chart.Theme, as: Document
  alias Visualize.Data.{Delivery, Schema}
  alias Visualize.Shape.Symbol
  alias Visualize.Theme

  @size {300, 200}
  @margin %{top: 0, right: 0, bottom: 0, left: 0}

  @hosts [
    %{t: 0, v: 1, state: "up", cpu: 10, host: "a"},
    %{t: 1, v: 2, state: "degraded", cpu: 50, host: "a"},
    %{t: 2, v: 3, state: "down", cpu: 90, host: "b"},
    %{t: 3, v: 4, state: "up", cpu: 20, host: "b"}
  ]

  # One frame over the hosts, with the scales a stack may name and a mark of `type`.
  defp design(mark, extra \\ %{}) do
    Map.merge(
      %{
        version: 2,
        sources: %{hosts: %{fields: [:t, :v, :state, :cpu, :host]}},
        frames: %{
          main: %{
            kind: :cartesian,
            margin: @margin,
            scales: %{
              x: %{kind: :linear, domain: [0, 3]},
              y: %{kind: :linear, domain: [0, 4]},
              health: %{
                kind: :ordinal,
                domain: ["up", "degraded", "down"],
                range: {:styles, :roles}
              },
              load: %{kind: :threshold, domain: [40, 80], range: {:styles, :roles}}
            }
          }
        },
        marks: [Map.merge(%{type: :symbol, data: :hosts, channels: %{x: :t, y: :v}}, mark)]
      },
      extra
    )
  end

  defp applied(design, opts \\ []) do
    {:ok, applied} =
      Chart.apply(design, Keyword.merge([sources: %{hosts: @hosts}, size: @size], opts))

    applied
  end

  # The first mark's bound elements, in `mode`.
  defp elements(design, mode \\ :literal, opts \\ []) do
    applied = applied(design, opts)

    group =
      Mark.generate(applied.frame, hd(applied.chart.marks),
        sources: applied.sources,
        resolve: mode
      )

    {group, group.children}
  end

  defp lit(theme, slot), do: Theme.resolve(theme, slot, :literal)

  defp errors(design) do
    {:error, errors} = Validator.validate(design)
    errors
  end

  # -- by name -------------------------------------------------------------------------

  describe "a palette name is a style reference" do
    test "a site names a whole role style, drawn in the theme's colours with its cue" do
      {group, [element | _]} = elements(design(%{style: :warning}))
      theme = Theme.default()

      assert group.style.fill == lit(theme, :warning)
      assert group.style.stroke == lit(theme, :warning)
      assert group.style.stroke_dasharray == Theme.cue(:warning).dash
      # The role's glyph reaches the symbol generator.
      expected = Symbol.new() |> Symbol.type(:triangle) |> Symbol.size(64)
      assert element.path == Symbol.generate_path(expected, hd(@hosts))
    end

    test "a design entry of a palette name wins for that design" do
      {group, _} = elements(design(%{style: :warning}, %{styles: %{warning: %{fill: "#123456"}}}))
      assert group.style.fill == "#123456"
      refute Map.has_key?(group.style, :stroke_dasharray)
    end

    test "a stack lays a state style over a base, the later winning" do
      design =
        design(%{style: [:base, :selected]}, %{
          styles: %{base: %{fill: "#111111", stroke_width: 1}}
        })

      {group, _} = elements(design)

      assert group.style.fill == "#111111"
      assert group.style.stroke_width == 2
      assert group.style.stroke == lit(Theme.default(), :text)
    end

    test "a design style extends a palette entry" do
      design = design(%{style: :heavy}, %{styles: %{heavy: %{extends: :bad, stroke_width: 4}}})
      {group, _} = elements(design)

      assert group.style.fill == lit(Theme.default(), :bad)
      assert group.style.stroke_width == 4
    end

    test "a theme swap restyles a palette-styled mark" do
      for theme <- [Theme.default(), Theme.dark(), Theme.colour_safe(), Theme.print()] do
        {group, _} = elements(design(%{style: :bad}), :literal, theme: theme)
        assert group.style.fill == lit(theme, :bad), inspect(theme.name)
      end

      house = Theme.new(name: :house, styles: %{bad: %{fill: :bad, stroke_width: 5}})
      {group, _} = elements(design(%{style: :bad}), :literal, theme: house)
      assert group.style.stroke_width == 5
      refute Map.has_key?(group.style, :stroke_dasharray)
    end

    test "an unknown name is undeclared, checked against the theme's palette" do
      assert Validator.validate(design(%{style: [:style_10, :muted, :annotation]})) == :ok

      assert {[:marks, 0, :style], {:undeclared, :style, :nope}} in errors(
               design(%{style: :nope})
             )

      # The default theme has ten style series, and an inline theme its own palette's.
      assert {[:marks, 0, :style], {:undeclared, :style, :style_11}} in errors(
               design(%{style: :style_11})
             )

      eleven = %{style_11: %{fill: {:series, 1}, symbol: :star, stroke_dasharray: "2 2"}}
      inline = design(%{style: :style_11}, %{theme: %{name: :eleven, styles: eleven}})
      assert Validator.validate(inline) == :ok
    end

    test "under a theme only the host knows, every style series is accepted, no other name" do
      assert Validator.validate(design(%{style: :style_14}, %{theme: :house})) == :ok
      errors = errors(design(%{style: :nope}, %{theme: :house}))
      assert {[:marks, 0, :style], {:undeclared, :style, :nope}} in errors
    end
  end

  # -- stored themes ---------------------------------------------------------------------

  describe "a stored theme carries its palette" do
    test "an inline theme's styles are its palette" do
      theme = %{name: :house, styles: %{warning: %{fill: :warning, stroke_width: 6}}}
      {group, _} = elements(design(%{style: :warning}, %{theme: theme}))
      assert group.style.stroke_width == 6
    end

    test "an inline theme's entry breaking its contract is a contract fault at its name" do
      theme = %{name: :house, styles: %{bad: %{fill: :good}}}
      errors = errors(design(%{style: :bad}, %{theme: theme}))

      assert [{[:theme, :styles, :bad], {:contract, message}}] =
               Enum.filter(errors, &match?({[:theme | _], _}, &1))

      assert message =~ "a role style paints with its own role"
    end

    test "an inline theme cannot add a name, and an entry is a style node" do
      added =
        errors(design(%{}, %{theme: %{name: :house, styles: %{sparkle: %{stroke_width: 2}}}}))

      assert [{[:theme, :styles, :sparkle], {:contract, _}}] = added

      typed = errors(design(%{}, %{theme: %{name: :house, styles: %{muted: 0.4}}}))
      assert {[:theme, :styles, :muted], {:type, {:node, :style}}} in typed

      keyed = errors(design(%{}, %{theme: %{name: :house, styles: %{muted: %{glow: 1}}}}))
      assert {[:theme, :styles, :muted, :glow], :unknown_key} in keyed
    end

    test "a role's cue is accepted where it means something, and the built-in palette validates" do
      cued = %{good: %{fill: :good, stroke_dasharray: :cue, symbol: :cue}}
      assert Validator.validate(design(%{}, %{theme: %{name: :house, styles: cued}})) == :ok

      assert Validator.validate(design(%{}, %{theme: Map.from_struct(Theme.dark())})) == :ok
    end

    test "a theme document round-trips its palette, as a map and as JSON" do
      house =
        Theme.new(
          name: :house,
          styles: %{
            muted: %{opacity: 0.4},
            warning: %{fill: :warning, stroke_width: 3, stroke_dasharray: :cue}
          }
        )

      assert Document.from_map(Document.to_map(house)) == {:ok, house}
      {:ok, json} = Document.to_json(house)
      assert Document.from_json(json) == {:ok, house}
      assert Document.from_json(elem(Document.to_json(Theme.print()), 1)) == {:ok, Theme.print()}
    end

    test "a theme document with a broken palette entry is refused at the entry" do
      document = %{theme: %{name: :house, styles: %{hover: %{stroke: :text}}}}

      assert {:error, [{[:theme, :styles, :hover], {:contract, message}}]} =
               Document.from_map(document)

      assert message =~ "a state style must read without hue"
    end
  end

  # -- by data -------------------------------------------------------------------------

  defp range(scale_node, opts \\ []) do
    design =
      design(%{}, %{
        frames: %{
          main: %{
            kind: :cartesian,
            margin: @margin,
            scales: %{s: scale_node, x: %{kind: :linear}}
          }
        },
        marks: []
      })

    Frame.scales(frame(design, opts)).s.range
  end

  defp frame(design, opts) do
    Frame.new(Chart.from_map!(design), Keyword.merge([size: @size], opts))
  end

  describe "a range of styles" do
    test "{:styles, :roles} spreads an ordinal domain over the roles by position" do
      roles = fn domain -> range(%{kind: :ordinal, domain: domain, range: {:styles, :roles}}) end

      assert roles.(["a"]) == [:good]
      assert roles.(["a", "b"]) == [:good, :bad]
      assert roles.(["a", "b", "c"]) == [:good, :warning, :bad]
      assert roles.(["a", "b", "c", "d"]) == [:good, :warning, :warning, :bad]
      assert roles.(["a", "b", "c", "d", "e"]) == [:good, :warning, :warning, :warning, :bad]
    end

    test "a threshold's bands take the roles in order, and polarity flips or folds them" do
      node = %{kind: :threshold, domain: [10, 20], range: {:styles, :roles}}

      assert range(node) == [:good, :warning, :bad]
      assert range(Map.put(node, :polarity, :higher_is_better)) == [:bad, :warning, :good]
      assert range(Map.put(node, :polarity, :neutral)) == [:bad, :good, :bad]
      assert range(%{node | domain: [7]}) == [:good, :bad]
    end

    test "{:styles, :series} gives the style series in domain order, cycling over the theme's" do
      node = %{kind: :ordinal, domain: ["a", "b", "c"], range: {:styles, :series}}
      assert range(node) == [:style_1, :style_2, :style_3]

      two =
        Theme.new(
          name: :two,
          styles: %{
            style_1: %{fill: {:series, 1}, symbol: :circle},
            style_2: %{fill: {:series, 2}, symbol: :square}
          }
        )

      # `new/1` merges over the default's ten; a theme of exactly two cycles over its two.
      only_two = %{two | styles: Map.drop(two.styles, Enum.map(3..10, &:"style_#{&1}"))}
      assert range(node, theme: only_two) == [:style_1, :style_2, :style_1]
    end

    test "a styles range on another kind is a fault at the range, and raises at realisation" do
      node = %{kind: :linear, range: {:styles, :roles}}

      assert {[:frames, :main, :scales, :health, :range], {:style_range, :linear}} in errors(
               put_in(design(%{}), [:frames, :main, :scales, :health], node)
             )

      # Realised from a chart the validator never saw.
      chart = Chart.from_map!(design(%{}, %{marks: []}))
      chart = %{chart | frames: put_in(chart.frames, [:main, :scales, :health], node)}

      assert_raise ArgumentError, ~r/cannot range over \{:styles, :roles\}/, fn ->
        Frame.new(chart, size: @size)
      end
    end

    test "polarity orders the roles but not the style series" do
      roles = %{
        kind: :threshold,
        domain: [5],
        range: {:styles, :roles},
        polarity: :higher_is_better
      }

      assert Validator.validate(put_in(design(%{}), [:frames, :main, :scales, :load], roles)) ==
               :ok

      series = %{kind: :ordinal, range: {:styles, :series}, polarity: :higher_is_better}

      assert {[:frames, :main, :scales, :health, :polarity], {:polarity, :range}} in errors(
               put_in(design(%{}), [:frames, :main, :scales, :health], series)
             )
    end

    test "an unknown set is a type fault" do
      node = %{kind: :ordinal, range: {:styles, :moods}}

      assert {[:frames, :main, :scales, :health, :range], {:type, :styles}} in errors(
               put_in(design(%{}), [:frames, :main, :scales, :health], node)
             )
    end
  end

  # -- the stack ---------------------------------------------------------------------------

  describe "a scale in a mark's stack" do
    test "lays each element the style its datum's reading picks" do
      {_group, elements} = elements(design(%{style: [{:scale, :health, :state}]}))
      theme = Theme.default()

      assert Enum.map(elements, & &1.style.fill) ==
               Enum.map([:good, :warning, :bad, :good], &lit(theme, &1))

      # Each element's glyph is its own role's cue (spec/08 §7.7).
      glyphs = for row <- @hosts, do: Theme.cue(role(row.state)).glyph

      paths =
        for {row, glyph} <- Enum.zip(@hosts, glyphs),
            do: Symbol.new() |> Symbol.type(glyph) |> Symbol.size(64) |> Symbol.generate_path(row)

      assert Enum.map(elements, & &1.path) == paths
    end

    test "entries lay in order, the later winning, and partial entries go over a base" do
      stack = [:base, {:scale, :health, :state}, {:scale, :load, :cpu}, %{stroke_width: 7}]

      design =
        design(%{style: stack}, %{styles: %{base: %{opacity: 0.5, stroke_width: 1}}})
        |> put_in([:frames, :main, :scales, :load, :polarity], :higher_is_better)

      {group, elements} = elements(design)
      theme = Theme.default()

      # The load (10, 50, 90, 20; higher is better) beats the health (up, degraded, down,
      # up) on the paint.
      assert Enum.map(elements, & &1.style.fill) ==
               Enum.map([:bad, :warning, :good, :bad], &lit(theme, &1))

      assert group.style.opacity == 0.5
      assert group.style.stroke_width == 7
      refute Enum.any?(elements, &Map.has_key?(&1.style, :stroke_width))
    end

    test "a reading outside the domain, or none, lays nothing" do
      rows = [
        %{t: 0, v: 1, state: "lost", cpu: 0, host: "a"},
        %{t: 1, v: 1, state: nil, cpu: 0, host: "a"},
        %{t: 2, v: 1, state: "down", cpu: 0, host: "a"}
      ]

      design = design(%{style: [%{fill: "#000000"}, {:scale, :health, :state}]})
      {:ok, applied} = Chart.apply(design, sources: %{hosts: rows}, size: @size)

      group =
        Mark.generate(applied.frame, hd(applied.chart.marks),
          sources: applied.sources,
          resolve: :literal
        )

      assert group.style.fill == "#000000"
      assert [first, second, third] = group.children
      refute Map.has_key?(first.style, :fill)
      refute Map.has_key?(second.style, :fill)
      assert third.style.fill == lit(Theme.default(), :bad)
    end

    test "a path per series takes its first datum's style, its curve and its fill" do
      stack = [%{fill: :none}, {:scale, :health, :state}, %{fill: :none}]

      design =
        design(%{type: :line, channels: %{x: :t, y: :v, series: :host}, style: stack}, %{
          styles: %{}
        })

      {_group, [a, b]} = elements(design)
      theme = Theme.default()

      # Host a starts "up", host b "down": each whole path in its first datum's role.
      assert a.style.stroke == lit(theme, :good)
      assert b.style.stroke == lit(theme, :bad)
      assert b.style.stroke_dasharray == Theme.cue(:bad).dash
      refute Map.has_key?(a.style, :stroke_dasharray)
    end

    test "a series' first datum decides its curve" do
      design =
        design(
          %{
            type: :line,
            channels: %{x: :t, y: :v, series: :host},
            style: [{:scale, :health, :state}]
          },
          %{styles: %{good: %{curve: :step}, bad: %{curve: :linear}}}
        )

      {_group, [a, b]} = elements(design)
      # A step curve doubles the line's segments; a linear one does not.
      assert length(a.path.commands) > length(b.path.commands)
    end

    test "the field infers an auto ordinal domain, in order of first appearance" do
      design =
        put_in(
          design(%{style: [{:scale, :health, :state}]}),
          [:frames, :main, :scales, :health],
          %{
            kind: :ordinal,
            range: {:styles, :series}
          }
        )

      applied = applied(design)
      scale = Frame.scales(applied.frame).health
      assert scale.domain == ["up", "degraded", "down"]
      assert scale.range == [:style_1, :style_2, :style_3]
    end

    test "list, map and status ranges lay explicit styles" do
      list = %{
        kind: :ordinal,
        domain: ["up", "degraded", "down"],
        range: [:neutral, :muted, :bad]
      }

      design =
        put_in(
          design(%{style: [{:scale, :health, :state}]}),
          [:frames, :main, :scales, :health],
          list
        )

      {_group, elements} = elements(design)

      assert Enum.map(elements, &Map.get(&1.style, :opacity)) == [nil, 0.25, nil, nil]
      assert Enum.at(elements, 2).style.fill == lit(Theme.default(), :bad)

      map = %{kind: :ordinal, range: %{"down" => :bad, "degraded" => :muted}}

      design =
        put_in(
          design(%{style: [{:scale, :health, :state}]}),
          [:frames, :main, :scales, :health],
          map
        )

      {_group, elements} = elements(design)
      assert Enum.map(elements, &Map.get(&1.style, :opacity)) == [nil, 0.25, nil, nil]
      assert Enum.at(elements, 2).style.fill == lit(Theme.default(), :bad)
    end

    test "a feed's status gives each state its role's whole style" do
      schema =
        Schema.new!(%{
          t: %{type: :number},
          v: %{type: :number},
          cpu: %{type: :number},
          host: %{type: :category},
          state: %{
            type: :category,
            status: %{"up" => :good, "degraded" => :warning, "down" => :bad}
          }
        })

      design =
        design(%{style: [{:scale, :health, :state}]})
        |> put_in([:frames, :main, :scales, :health], %{
          kind: :ordinal,
          range: fact(:hosts, :state, :status)
        })

      assert Validator.validate(design) == :ok

      {:ok, applied} =
        Chart.apply(design,
          sources: %{hosts: Delivery.new(@hosts, schema: Schema.version(schema))},
          describe: fn _feed -> {:ok, schema} end,
          size: @size
        )

      group =
        Mark.generate(applied.frame, hd(applied.chart.marks),
          sources: applied.sources,
          resolve: :literal
        )

      assert Enum.map(group.children, & &1.style.fill) ==
               Enum.map([:good, :warning, :bad, :good], &lit(Theme.default(), &1))
    end

    test "SVG and canvas draw the same resolved style" do
      design = design(%{style: [:muted, {:scale, :health, :state}]})
      {css_group, css} = elements(design, :css)
      {lit_group, lit} = elements(design, :literal)

      assert Enum.map(css, &literal(&1.style)) == Enum.map(lit, & &1.style)
      assert literal(css_group.style) == lit_group.style
      assert hd(css).style.fill =~ "var(--vis-good"
    end

    test "round-trips through JSON" do
      design =
        design(%{style: [:base, {:scale, :health, :state}, %{stroke_width: 2}]}, %{
          styles: %{base: %{opacity: 0.5}}
        })
        |> put_in([:frames, :main, :scales, :load, :range], {:styles, :series})
        |> put_in([:frames, :main, :scales, :spare], %{
          kind: :ordinal,
          range: %{"a" => :muted, "b" => :bad, "c" => :style_2}
        })

      chart = Chart.from_map!(design)
      {:ok, json} = Chart.to_json(chart)
      assert Chart.from_json(json) == {:ok, chart}
    end
  end

  describe "the faults of a scale in a stack" do
    test "a scale that does not range over styles" do
      x = design(%{style: [{:scale, :x, :t}]})
      assert {[:marks, 0, :style, 0], {:style_scale, :x}} in errors(x)

      colours =
        put_in(
          design(%{style: {:scale, :health, :state}}),
          [:frames, :main, :scales, :health, :range],
          ["#ff0000", "#00ff00"]
        )

      assert {[:marks, 0, :style], {:style_scale, :health}} in errors(colours)

      typo =
        put_in(
          design(%{style: {:scale, :health, :state}}),
          [:frames, :main, :scales, :health, :range],
          [:good, :nope]
        )

      assert {[:marks, 0, :style], {:style_scale, :health}} in errors(typo)
    end

    test "an undeclared scale or field" do
      assert {[:marks, 0, :style, 0], {:undeclared, :scale, :nope}} in errors(
               design(%{style: [{:scale, :nope, :state}]})
             )

      assert {[:marks, 0, :style, 0], {:undeclared, :field, :mood}} in errors(
               design(%{style: [{:scale, :health, :mood}]})
             )
    end

    test "a site that is not a mark's style" do
      axis = %{scale: :x, side: :bottom, style: [:axis, {:scale, :health, :state}]}
      design = put_in(design(%{}), [:frames, :main, :axes], [axis])
      assert {[:frames, :main, :axes, 0, :style, 1], {:invalid_for, :axis}} in errors(design)
    end

    test "every fault is worded" do
      for reason <- [
            {:style_scale, :x},
            {:style_range, :linear},
            {:type, :styles},
            {:type, :style_scale}
          ] do
        assert Validator.format({[:marks, 0, :style], reason}) =~ "marks[0].style: "
      end
    end
  end

  describe "a scale of styles read as colour" do
    defp scale(design, name, node), do: put_in(design, [:frames, :main, :scales, name], node)

    test "the color scale ranging over styles is a fault at its range" do
      for range <- [{:styles, :roles}, {:styles, :series}, [:good, :muted], %{"a" => :style_2}] do
        design = scale(design(%{}), :color, %{kind: :ordinal, range: range})

        assert {[:frames, :main, :scales, :color, :range], {:style_colour, :color}} in errors(
                 design
               ),
               inspect(range)
      end
    end

    test "an adopted color scale is a fault at the adoption" do
      design =
        design(%{}, %{
          frames: %{
            main: %{
              kind: :cartesian,
              margin: @margin,
              scales: %{
                x: %{kind: :linear},
                y: %{kind: :linear},
                color: {:frame, :other, :health}
              }
            },
            other: %{
              kind: :cartesian,
              scales: %{health: %{kind: :ordinal, range: {:styles, :roles}}}
            }
          },
          marks: []
        })

      assert {[:frames, :main, :scales, :color], {:style_colour, :color}} in errors(design)
    end

    test "a legend on a scale of styles is a fault at the legend's scale" do
      design = put_in(design(%{}), [:frames, :main, :legend], %{scale: :health})
      assert {[:frames, :main, :legend, :scale], {:style_colour, :health}} in errors(design)
    end

    test "a mark renaming color to a scale of styles is a fault at its scales.color" do
      design = design(%{scales: %{color: :health}})
      assert {[:marks, 0, :scales, :color], {:style_colour, :health}} in errors(design)
    end

    test "a colour binding through a scale of styles is a fault at the mark's style" do
      binding = design(%{scales: %{color: :health}, style: %{fill: {:field, :state}}})
      assert {[:marks, 0, :style], {:style_colour, :health}} in errors(binding)

      named =
        design(%{style: [:tinted]}, %{styles: %{tinted: %{stroke: {:field, :state}}}})
        |> scale(:color, %{kind: :ordinal, range: [:muted, :bad]})

      assert {[:marks, 0, :style], {:style_colour, :color}} in errors(named)
    end

    test "a list or a map of style names that are slots reads as colours" do
      for range <- [[:good, :warning, :bad], %{"a" => :info, "b" => :axis}] do
        design =
          design(%{style: %{fill: {:field, :state}}})
          |> scale(:color, %{kind: :ordinal, range: range})
          |> put_in([:frames, :main, :legend], %{scale: :color})

        assert Validator.validate(design) == :ok, inspect(range)
      end

      # A scale of styles nothing reads as colour is not a fault.
      assert Validator.validate(design(%{style: [{:scale, :health, :state}]})) == :ok
    end

    test "is worded" do
      assert Validator.format({[:marks, 0, :style], {:style_colour, :health}}) =~
               "reads scale :health as colour"
    end
  end

  defp role("up"), do: :good
  defp role("degraded"), do: :warning
  defp role("down"), do: :bad

  # A `:css` style read as the canvas reads it: each `var(--x, literal)` its literal.
  defp literal(style) do
    Map.new(style, fn
      {key, "var(" <> _ = value} ->
        {key, value |> String.split(", ") |> List.last() |> String.trim_trailing(")")}

      pair ->
        pair
    end)
  end
end
