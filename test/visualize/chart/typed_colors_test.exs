defmodule Visualize.Chart.TypedColorsTest do
  @moduledoc """
  Typed colors through the grammar (spec/14 §3.2, §9, §11.2, #664, D-173): a color position
  of a stored design is typed, canonicalized at every version; the validator checks names
  against the theme's color table; the JSON codec writes a tag per typed color and refuses
  one it does not know; the status ramp is defined from the theme's green, amber and red.
  """
  use ExUnit.Case, async: true

  import Visualize.Color,
    only: [color: 1, intensity: 2, alpha: 2, blend: 1, lighten: 2, contrast: 0, contrast: 1]

  alias Visualize.Chart
  alias Visualize.Chart.{Mark, Migration, Validator}
  alias Visualize.{Designs, Theme}

  @hosts [%{t: 0, v: 1}, %{t: 1, v: 3}, %{t: 2, v: 2}]
  @size %{width: 200, height: 100}

  defp design(style, extra \\ %{}) do
    Map.merge(
      %{
        version: 3,
        sources: %{hosts: %{fields: [:t, :v]}},
        styles: %{s: style},
        frames: %{
          main: %{
            kind: :cartesian,
            margin: %{top: 0, right: 0, bottom: 0, left: 0},
            scales: %{
              x: %{kind: :linear, domain: [0, 2]},
              y: %{kind: :linear, domain: [0, 4]}
            }
          }
        },
        marks: [
          %{type: :rect, data: :hosts, style: :s, channels: %{x0: :t, x1: 1, y0: 0, y1: :v}}
        ]
      },
      extra
    )
  end

  defp fill(design, mode) do
    {:ok, applied} = Chart.apply(design, sources: %{hosts: @hosts}, size: @size)

    group =
      Mark.generate(applied.frame, hd(applied.chart.marks),
        sources: applied.sources,
        resolve: mode
      )

    hd(group.children).style[:fill] || group.style[:fill]
  end

  describe "the canonical form, at every version" do
    test "a bare atom in a color position is the color it names; :none stays" do
      canonical = Migration.canonical(%{fill: :bad, stroke: %{color: :axis}}, :style)
      assert canonical.fill.color == {:color, :bad}
      assert canonical.stroke.color == {:color, :axis}
      assert Migration.canonical(%{fill: :none}, :style) == %{fill: %{type: :none}}
    end

    test ":contrast is the ink over what is under, and operands are canonical too" do
      assert Migration.canonical(%{fill: :contrast}, :style).fill.color == {:contrast, :under}

      raw = %{fill: {:alpha, {:blend, [:red, {:intensity, :blue, 0.5}]}, 0.5}}

      assert Migration.canonical(raw, :style).fill.color ==
               alpha(blend([color(:red), intensity(color(:blue), 0.5)]), 0.5)
    end

    test "a map of colors, a gradient's stops and a stored version 2 design are typed" do
      v2 = %{
        version: 2,
        frames: %{
          main: %{kind: :cartesian, scales: %{c: %{kind: :ordinal, range: %{"down" => :bad}}}}
        },
        # spelling: allow — version 2's stop word.
        defs: %{fade: %{kind: :linear, stops: [%{offset: 0, colour: :series_1}]}},
        styles: %{s: %{stroke: :good}}
      }

      assert {:ok, v3} = Migration.migrate(v2)
      assert v3.frames.main.scales.c.range == %{"down" => {:color, :bad}}
      assert hd(v3.defs.fade.stops).color == {:color, :series_1}
      assert v3.styles.s.stroke.color == {:color, :good}
    end

    test "every stored design is typed: no bare atom but :none in a color position" do
      for name <- Designs.names() do
        {:ok, chart} = Chart.from_map(Designs.design(name))

        assert untyped(Chart.to_map(chart)) == [],
               "#{name}: #{inspect(untyped(Chart.to_map(chart)))}"
      end
    end

    test "a bare name and its typed form draw the same, in both modes" do
      for mode <- [:css, :literal] do
        assert fill(design(%{fill: :bad}), mode) == fill(design(%{fill: color(:bad)}), mode)
      end

      assert fill(design(%{fill: :bad}), :css) == "var(--vis-bad, #c23238)"
    end
  end

  # Every value under a `color` key that is an atom other than `:none`.
  defp untyped(map) when is_map(map) and not is_struct(map) do
    Enum.flat_map(map, fn
      {:color, v} when is_atom(v) and v != :none -> [v]
      {_k, v} -> untyped(v)
    end)
  end

  defp untyped(list) when is_list(list), do: Enum.flat_map(list, &untyped/1)
  defp untyped(_leaf), do: []

  describe "a transform draws" do
    test "as its literal in :literal mode, a name inside it through the theme" do
      d = design(%{fill: color(:red) |> lighten(0.5)})
      literal = fill(d, :literal)

      assert literal ==
               Visualize.Color.resolve(lighten(color(:red), 0.5), Theme.default(), :literal)

      assert String.starts_with?(literal, "#")
    end

    test "the theme's ink over a chosen color" do
      assert fill(design(%{fill: contrast(color(:text))}), :css) == "#ffffff"
      assert fill(design(%{fill: contrast()}), :literal) == "#333333"
    end
  end

  describe "the validator" do
    test "a name the theme's table lacks is undeclared, at every depth" do
      assert {:error, [{[:styles, :s, :fill, :color], {:undeclared, :color, :brand}}]} =
               Validator.validate(design(%{fill: alpha(color(:brand), 0.5)}))

      assert :ok = Validator.validate(design(%{fill: color(:steelblue)}))
    end

    test "an inline theme's own names are its table's" do
      theme = %{colors: %{brand: "#123456"}}

      assert :ok =
               Validator.validate(design(%{fill: color(:brand)}, %{theme: theme}))
    end

    test "a transform of the wrong shape or an unreadable literal operand is no color" do
      for bad <- [{:alpha, color(:red), 2}, {:blend, []}, alpha("currentColor", 0.5)] do
        assert {:error, [{[:styles, :s, :fill, :color], {:type, :color}}]} =
                 Validator.validate(design(%{fill: bad}))
      end

      # A literal that is the whole color is CSS's, as written, and is never computed.
      assert :ok = Validator.validate(design(%{fill: "currentColor"}))
    end
  end

  describe "the JSON codec" do
    test "every typed color round-trips under its tag" do
      values = [
        color(:red),
        intensity(color(:blue), 0.65),
        alpha(color(:red), 0.5),
        lighten("#3b6fa8", 0.2),
        {:darken, color(:red), 0.1},
        {:saturate, color(:red), 0.3},
        blend([intensity(color(:blue), 0.65), color(:red)]),
        contrast(color(:bad)),
        contrast(),
        {:ramp, :thermal, 0.7},
        {:series, 3}
      ]

      for value <- values do
        {:ok, json} = Chart.to_json(Chart.from_map!(design(%{fill: value})))
        assert {:ok, back} = Chart.from_json(json)
        assert back.styles.s.fill.color == value, inspect(value)
      end

      {:ok, json} = Chart.to_json(Chart.from_map!(design(%{fill: intensity(color(:blue), 0.65)})))
      assert json =~ ~s("color":{"$intensity":[{"$color":"blue"},0.65]})
    end

    test "a slot name as a string, and \"contrast\", are read as they were and typed" do
      {:ok, json} = Chart.to_json(Chart.from_map!(design(%{fill: "#000"})))

      for {old, typed} <- [{~s("bad"), color(:bad)}, {~s("contrast"), contrast()}] do
        legacy = String.replace(json, ~s("color":"#000"), ~s("color":) <> old)
        assert {:ok, back} = Chart.from_json(legacy)
        assert back.styles.s.fill.color == typed
      end

      # Any other string is a literal: "red" stays CSS's red, never the theme's.
      legacy = String.replace(json, ~s("color":"#000"), ~s("color":"red"))
      assert {:ok, back} = Chart.from_json(legacy)
      assert back.styles.s.fill.color == "red"
    end

    test "an unknown tag in a color position is refused, and a name that is not plain words is no atom" do
      {:ok, json} = Chart.to_json(Chart.from_map!(design(%{fill: "#000"})))

      # An unknown tag is the reader's to refuse, at its path in the document (D-182).
      at = ["styles", "s", "fill", "color"]

      for {tag, error} <- [
            {~s({"$colr":"red"}), {at, {:unknown_tag, "$colr"}}},
            {~s({"$alpha":[{"$bogus":1},0.5]}), {at ++ ["$alpha", 0], {:unknown_tag, "$bogus"}}}
          ] do
        bad = String.replace(json, ~s("color":"#000"), ~s("color":) <> tag)
        assert Chart.from_json(bad) == {:error, [error]}
      end

      # A known tag whose name is not plain words is no atom, and no color.
      bad = String.replace(json, ~s("color":"#000"), ~s("color":{"$color":"a b"}))

      assert {:error, [{[:styles, :s, :fill, :color], {:type, :color}}]} =
               Chart.from_json(bad)
    end
  end

  describe "the status ramp is defined from the theme's green, amber and red" do
    test "the built-ins name their hues, and draw as before" do
      for theme <- [Theme.default(), Theme.dark()] do
        assert theme.ramps.status == [color(:green), color(:amber), color(:red)]
      end

      assert Theme.ramp(Theme.default(), :status, 1) == "#c23238"
      assert Theme.ramp(Theme.dark(), :status, 0) == "#4f924c"
    end

    test "a theme that changes its red changes the status ramp's bad end" do
      theme = Theme.new(colors: %{red: "#b92931"})
      assert Theme.ramp(theme, :status, 1) == "#b92931"
      assert Theme.resolve(theme, :bad, :css) == "var(--vis-bad, #b92931)"
    end

    test "an anchor that names no color string breaks the ramp's contract" do
      assert_raise ArgumentError, ~r/ramp :status breaks its contract: anchor 3/, fn ->
        Theme.new(colors: %{red: {:ramp, :status, 1}})
      end
    end
  end
end
