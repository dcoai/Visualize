defmodule Visualize.Chart.PaletteAssignmentTest do
  @moduledoc """
  Assigning the theme's style palette (spec/14 §3.3, §3.6, §9.3, #637, #644, D-171): by
  name — at a site, in a stack and under `extends`, a design's entry winning — and by data,
  through a `{:field, f}` stack entry whose value per datum names the style; stored themes
  carrying their palette; and the forms #644 removed, now ordinary faults. The SVG
  (`:css`) and the canvas (`:literal`) draw the same resolved style, and a theme swap
  restyles it.
  """
  use ExUnit.Case, async: true

  alias Visualize.Chart
  alias Visualize.Chart.{Mark, Validator}
  alias Visualize.Chart.Theme, as: Document
  alias Visualize.Shape.Symbol
  alias Visualize.Theme

  @size {300, 200}
  @margin %{top: 0, right: 0, bottom: 0, left: 0}

  # `health` names a style by its text, as a feed sends it, and `load` by its atom.
  @hosts [
    %{t: 0, v: 1, health: "good", load: :bad, host: "a"},
    %{t: 1, v: 2, health: "warning", load: :warning, host: "a"},
    %{t: 2, v: 3, health: "bad", load: :good, host: "b"},
    %{t: 3, v: 4, health: "good", load: :bad, host: "b"}
  ]

  # One frame over the hosts and a mark of `type`.
  defp design(mark, extra \\ %{}) do
    Map.merge(
      %{
        version: 3,
        sources: %{hosts: %{fields: [:t, :v, :health, :load, :host]}},
        frames: %{
          main: %{
            kind: :cartesian,
            margin: @margin,
            scales: %{
              x: %{kind: :linear, domain: [0, 3]},
              y: %{kind: :linear, domain: [0, 4]}
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
      # The built-in :selected is heavier only (#638): no stroke colour of its own.
      refute Map.has_key?(group.style, :stroke)
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

        # The print theme's :bad is a crosshatch in its colour (#673).
        case group.style.fill do
          {:paint, name} ->
            assert theme.name == :print
            frame = applied(design(%{style: :bad}), theme: theme).frame
            assert %{type: :hatch, color: {:color, :bad}} = frame.defs[name]

          fill ->
            assert fill == lit(theme, :bad), inspect(theme.name)
        end
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

      assert message =~ "the role styles' colors must be distinct"
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

  describe "a field in a stack names a style" do
    test "lays each element the style its datum's value names, alone or in a list" do
      theme = Theme.default()
      fills = Enum.map([:good, :warning, :bad, :good], &lit(theme, &1))

      for style <- [{:field, :health}, [{:field, :health}]] do
        {_group, elements} = elements(design(%{style: style}))
        assert Enum.map(elements, & &1.style.fill) == fills, inspect(style)
      end

      # Each element's glyph is its own role's cue (spec/08 §7.7).
      {_group, elements} = elements(design(%{style: {:field, :health}}))

      paths =
        for row <- @hosts do
          glyph = Theme.cue(String.to_existing_atom(row.health)).glyph
          Symbol.new() |> Symbol.type(glyph) |> Symbol.size(64) |> Symbol.generate_path(row)
        end

      assert Enum.map(elements, & &1.path) == paths
    end

    test "entries lay in order, the later winning, and partial entries go over a base" do
      stack = [:base, {:field, :health}, {:field, :load}, %{stroke_width: 7}]
      design = design(%{style: stack}, %{styles: %{base: %{opacity: 0.5, stroke_width: 1}}})

      {group, elements} = elements(design)
      theme = Theme.default()

      # The load (bad, warning, good, bad) beats the health (good, warning, bad, good) on
      # the paint.
      assert Enum.map(elements, & &1.style.fill) ==
               Enum.map([:bad, :warning, :good, :bad], &lit(theme, &1))

      assert group.style.opacity == 0.5
      assert group.style.stroke_width == 7
      refute Enum.any?(elements, &Map.has_key?(&1.style, :stroke_width))
    end

    test "a value that names no style, or none, lays nothing" do
      rows =
        for {health, t} <- Enum.with_index(["lost", nil, :nope, 42, "bad"]),
            do: %{t: t, v: 1, health: health, load: nil, host: "a"}

      group = generated(design(%{style: [%{fill: "#000000"}, {:field, :health}]}), rows)

      assert group.style.fill == "#000000"
      assert [a, b, c, d, e] = group.children
      for element <- [a, b, c, d], do: refute(Map.has_key?(element.style, :fill))
      assert e.style.fill == lit(Theme.default(), :bad)
    end

    test "a design's own entry of the named style wins over the palette's" do
      design = design(%{style: {:field, :health}}, %{styles: %{bad: %{fill: "#123456"}}})
      {_group, elements} = elements(design)

      assert Enum.at(elements, 2).style.fill == "#123456"
      assert hd(elements).style.fill == lit(Theme.default(), :good)
    end

    test "a value names a style the design declares, by atom or by string" do
      rows =
        for {health, t} <- Enum.with_index([:loud, "loud"]),
            do: %{t: t, v: 1, health: health, load: nil, host: "a"}

      design = design(%{style: {:field, :health}}, %{styles: %{loud: %{stroke_width: 9}}})

      assert Enum.map(generated(design, rows).children, & &1.style.stroke_width) == [9, 9]
    end

    test "a path per series takes its first datum's style" do
      stack = [%{fill: :none}, {:field, :health}, %{fill: :none}]
      design = design(%{type: :line, channels: %{x: :t, y: :v, series: :host}, style: stack})

      {_group, [a, b]} = elements(design)
      theme = Theme.default()

      # Host a starts good, host b bad: each whole path in its first datum's role.
      assert a.style.stroke == lit(theme, :good)
      assert b.style.stroke == lit(theme, :bad)
      assert b.style.stroke_dasharray == Theme.cue(:bad).dash
      refute Map.has_key?(a.style, :stroke_dasharray)
    end

    test "a series' first datum decides its curve" do
      design =
        design(
          %{type: :line, channels: %{x: :t, y: :v, series: :host}, style: [{:field, :health}]},
          %{styles: %{good: %{curve: :step}, bad: %{curve: :linear}}}
        )

      {_group, [a, b]} = elements(design)
      # A step curve doubles the line's segments; a linear one does not.
      assert length(a.path.commands) > length(b.path.commands)
    end

    test "a mark's inline label reads its style from the datum it labels" do
      label = %{text: [{:field, :host}], style: [:label, {:field, :health}]}
      applied = applied(design(%{label: label}))

      texts =
        applied.frame
        |> Mark.generate(hd(applied.chart.marks), sources: applied.sources, resolve: :literal)
        |> texts()

      assert Enum.map(texts, & &1.style.fill) ==
               Enum.map([:good, :warning, :bad, :good], &lit(Theme.default(), &1))
    end

    test "a site without a datum lays nothing for it" do
      plain = design(%{}, %{labels: [%{anchor: :title, text: ["Hosts"], style: :title}]})

      bound =
        plain
        |> put_in([:labels, Access.at(0), :style], [:title, {:field, :health}])
        |> put_in([:frames, :main, :axes], [
          %{scale: :x, side: :bottom, style: [:axis, {:field, :health}]}
        ])

      plain =
        put_in(plain, [:frames, :main, :axes], [%{scale: :x, side: :bottom, style: [:axis]}])

      assert Validator.validate(bound) == :ok
      assert Chart.render(applied(bound)) == Chart.render(applied(plain))
    end

    test "SVG and canvas draw the same resolved style" do
      design = design(%{style: [:muted, {:field, :health}]})
      {css_group, css} = elements(design, :css)
      {lit_group, lit} = elements(design, :literal)

      assert Enum.map(css, &literal(&1.style)) == Enum.map(lit, & &1.style)
      assert literal(css_group.style) == lit_group.style
      assert hd(css).style.fill =~ "var(--vis-good"
    end

    test "round-trips through JSON at every site" do
      design =
        design(
          %{
            style: [:base, {:field, :health}, %{stroke_width: 2}],
            label: %{text: [{:field, :host}], style: {:field, :health}}
          },
          %{styles: %{base: %{opacity: 0.5}}}
        )
        |> put_in([:frames, :main, :axes], [
          %{scale: :x, side: :bottom, style: [:axis, {:field, :health}]}
        ])

      chart = Chart.from_map!(design)
      {:ok, json} = Chart.to_json(chart)
      assert json =~ ~s({"$field":"health"})
      assert Chart.from_json(json) == {:ok, chart}
    end
  end

  describe "the validator and a field in a stack" do
    test "accepts it at every site that takes a style" do
      design =
        design(%{label: %{text: [{:field, :host}], style: [:label, {:field, :health}]}}, %{
          labels: [%{anchor: :title, text: ["Hosts"], style: {:field, :health}}]
        })
        |> update_in([:marks, Access.at(0)], &Map.put(&1, :style, [:base, {:field, :health}]))
        |> put_in([:styles], %{base: %{opacity: 0.5}})
        |> put_in([:frames, :main, :axes], [%{scale: :x, side: :bottom, style: {:field, :t}}])
        |> put_in([:frames, :main, :scales, :color], %{kind: :ordinal})
        |> put_in([:frames, :main, :legend], %{scale: :color, style: [{:field, :host}]})

      assert Validator.validate(design) == :ok
    end

    test "a field the mark's source does not declare is undeclared at the entry" do
      assert {[:marks, 0, :style, 1], {:undeclared, :field, :mood}} in errors(
               design(%{style: [:base, {:field, :mood}]}, %{styles: %{base: %{}}})
             )

      assert {[:marks, 0, :style], {:undeclared, :field, :mood}} in errors(
               design(%{style: {:field, :mood}})
             )
    end

    test "a field that is not a name is a type fault" do
      assert [{[:marks, 0, :style], {:type, _}}] = errors(design(%{style: {:field, "health"}}))
    end
  end

  # -- what #644 removed ----------------------------------------------------------------

  describe "the scale-of-styles forms are ordinary faults" do
    test "a scale entry in a stack is no style" do
      for style <- [{:scale, :health, :state}, [:muted, {:scale, :health, :state}]] do
        assert [{path, {:type, _}}] = errors(design(%{style: style}))
        assert path in [[:marks, 0, :style], [:marks, 0, :style, 1]], inspect(style)
      end
    end

    test "a styles range is no range" do
      for set <- [:roles, :series] do
        design =
          put_in(design(%{}), [:frames, :main, :scales, :health], %{
            kind: :ordinal,
            range: {:styles, set}
          })

        assert [{[:frames, :main, :scales, :health, :range], {:type, _}}] = errors(design)
      end
    end

    test "a style name in a map range is an undeclared color, a role a colour" do
      node = %{kind: :ordinal, range: %{"down" => :bad, "maint" => :muted}}
      design = put_in(design(%{}), [:frames, :main, :scales, :health], node)

      assert errors(design) == [
               {[:frames, :main, :scales, :health, :range, "maint"],
                {:undeclared, :color, :muted}}
             ]
    end

    test "the JSON tags are refused" do
      design = put_in(design(%{}), [:frames, :main, :scales, :health], %{kind: :ordinal})
      {:ok, json} = Chart.to_json(Chart.from_map!(design))

      styles =
        String.replace(
          json,
          ~s("kind":"ordinal"),
          ~s("kind":"ordinal","range":{"$styles":"roles"})
        )

      # Refused as the retired tag it is, never read as data (D-182).
      assert {:error, [{["frames", "main", "scales", "health", "range"], reason}]} =
               Chart.from_json(styles)

      assert {:retired_tag, "$styles", why} = reason
      assert why =~ "#644"

      mark = put_in(design, [:marks, Access.at(0), :style], [:muted])
      {:ok, json} = Chart.to_json(Chart.from_map!(mark))
      scale = String.replace(json, ~s(["muted"]), ~s(["muted",{"$scale":["health","state"]}]))
      assert scale != json
      assert {:error, _} = Chart.from_json(scale)
    end
  end

  defp generated(design, rows) do
    {:ok, applied} = Chart.apply(design, sources: %{hosts: rows}, size: @size)

    Mark.generate(applied.frame, hd(applied.chart.marks),
      sources: applied.sources,
      resolve: :literal
    )
  end

  # Every text element under a mark group, in drawing order.
  defp texts(%{type: :text} = element), do: [element]
  defp texts(%{children: children}), do: Enum.flat_map(children, &texts/1)
  defp texts(_element), do: []

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
