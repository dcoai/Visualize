defmodule Visualize.Chart.ColorPositionsTest do
  @moduledoc """
  #710, D-185: every color position takes every color (spec/12 §6). One list holds the
  design's color positions; each is given a typed color and a transform, which validate,
  stay typed through `Visualize.Chart.Migration.canonical/1` — where a bare atom becomes
  the typed name — and draw the color the theme resolves on SVG and both canvases. The list
  is checked against the schema, so a color position the schema gains without a row here
  fails by name: the gap that typed a scale's range as a domain and refused `color(:red)`.
  """
  use ExUnit.Case, async: true

  import Visualize.Color, only: [color: 1, darken: 2]

  alias Visualize.Backend.Canvas
  alias Visualize.Backend.CanvasBinary.Decoder
  alias Visualize.Chart
  alias Visualize.Chart.{Migration, Schema, Validator}
  alias Visualize.Theme

  # One cell, `k` its category for a scale that reads one.
  defp design(style, overrides) do
    Map.merge(
      %{
        version: 3,
        sources: %{cells: %{fields: [:k]}},
        styles: %{cell: style},
        frames: %{
          main: %{
            kind: :cartesian,
            scales: %{x: %{kind: :linear, domain: [0, 1]}, y: %{kind: :linear, domain: [0, 1]}}
          }
        },
        marks: [
          %{
            type: :rect,
            data: :cells,
            channels: %{x0: 0.1, x1: 0.9, y0: 0.1, y1: 0.9},
            style: :cell
          }
        ]
      },
      overrides
    )
  end

  defp with_scale(design, scale),
    do: put_in(design, [:frames, :main, :scales, :color], scale)

  # Every color position: what the schema calls it, and a design that draws `c` there.
  defp positions do
    [
      {"a paint's color", [{:paint, :color}], &design(%{fill: %{type: :solid, color: &1}})},
      {"a hatch's background", [{:paint, :background}],
       &design(%{
         fill: %{type: :hatch, pattern: :lines, color: "#000000", background: &1}
       })},
      {"a stroke's color", [{:stroke, :color}],
       &design(%{fill: :none, stroke: %{type: :solid, color: &1, width: 2}})},
      {"an effect's color", [{:effect, :color}],
       &design(%{
         fill: "#000000",
         effect: %{type: :shadow, radius: 2, offset: [1, 1], color: &1}
       })},
      {"a gradient stop's color", [{:stop, :color}],
       &design(%{
         fill: %{type: :linear, stops: [%{at: 0, color: &1}, %{at: 1, color: "#000000"}]}
       })},
      {"a frame's background", [{:frame, :background}], &__MODULE__.frame_background/1},
      {"an ordinal scale's list range", [{:scale, :range}],
       &__MODULE__.scaled(%{kind: :ordinal, domain: ["a"], range: [&1]}, "a")},
      {"a sequential scale's list range", [{:scale, :range}],
       &__MODULE__.scaled(%{kind: :sequential, domain: [0, 1], range: [&1, "#000000"]}, 0)},
      {"a scale's map of colors", [{:scale, :range}],
       &__MODULE__.scaled(%{kind: :ordinal, range: %{"a" => &1}}, "a")},
      {"a theme's color", [{:theme, :colors}],
       &design(%{fill: color(:brand)}, %{theme: %{name: :house, colors: %{brand: &1}}})},
      {"a theme's ramp", [{:theme, :ramps}],
       &design(%{fill: {:ramp, :sequential, 0}}, %{
         theme: %{name: :house, ramps: %{sequential: [&1, "#000000"]}}
       })}
    ]
  end

  @names [
    "a paint's color",
    "a hatch's background",
    "a stroke's color",
    "an effect's color",
    "a gradient stop's color",
    "a frame's background",
    "an ordinal scale's list range",
    "a sequential scale's list range",
    "a scale's map of colors",
    "a theme's color",
    "a theme's ramp"
  ]

  @doc false
  def design(style), do: design(style, %{})

  @doc false
  def frame_background(c),
    do: put_in(design(%{fill: "#000000"}), [:frames, :main, :background], c)

  @doc false
  def scaled(scale, k), do: {with_scale(design(%{fill: {:field, :k}}), scale), [%{k: k}]}

  defp build(name), do: positions() |> List.keyfind!(name, 0) |> elem(2)

  @typed color(:red)
  @transform color(:blue) |> darken(0.4)

  # The design and its rows: a position that reads a category binds one row of it.
  defp built(build, c) do
    case build.(c) do
      {design, rows} -> {design, rows}
      design -> {design, [%{k: "a"}]}
    end
  end

  # The literal a color resolves to in the default theme, which every position draws in.
  defp literal(c), do: Visualize.Color.resolve(c, Theme.default(), :literal)

  defp rgb("#" <> <<r::binary-size(2), g::binary-size(2), b::binary-size(2), _::binary>>),
    do: Enum.map([r, g, b], &String.to_integer(&1, 16))

  # Whether a term holds the color: as a string, or as the RGB channels the binary stream
  # writes a color in.
  defp holds?(term, hex) do
    hex = String.downcase(hex)
    [r, g, b] = rgb(hex)

    walk = fn
      _walk, v when is_binary(v) ->
        String.downcase(v) =~ String.slice(hex, 0, 7) or v =~ "rgba(#{r},#{g},#{b},"

      _walk, {^r, ^g, ^b, _a} ->
        true

      walk, v when is_tuple(v) ->
        v |> Tuple.to_list() |> Enum.any?(&walk.(walk, &1))

      walk, v when is_list(v) ->
        Enum.any?(v, &walk.(walk, &1))

      walk, v when is_map(v) and not is_struct(v) ->
        Enum.any?(v, &walk.(walk, &1))

      _walk, _v ->
        false
    end

    walk.(walk, term)
  end

  # Whether a term holds `value` anywhere in it.
  defp has?(value, value), do: true
  defp has?(term, value) when is_tuple(term), do: has?(Tuple.to_list(term), value)
  defp has?(term, value) when is_list(term), do: Enum.any?(term, &has?(&1, value))

  defp has?(term, value) when is_map(term) and not is_struct(term),
    do: Enum.any?(term, &has?(&1, value))

  defp has?(_term, _value), do: false

  test "the list holds every color position of the schema" do
    color_type? = fn
      _f, t when t in [:color, :theme_color, :color_map, :range] -> true
      f, {:list, t} -> f.(f, t)
      f, {:map, t} -> f.(f, t)
      f, {:one_of, ts} -> Enum.any?(ts, &f.(f, &1))
      _f, _t -> false
    end

    in_schema =
      for kind <- Schema.kinds(),
          spec <- Schema.describe(kind),
          color_type?.(color_type?, spec.type),
          into: MapSet.new(),
          do: {kind, spec.key}

    assert Enum.map(positions(), &elem(&1, 0)) == @names

    listed = for {_name, keys, _build} <- positions(), key <- keys, into: MapSet.new(), do: key

    assert MapSet.difference(in_schema, listed) == MapSet.new(),
           "a color position of the schema has no row in @positions"

    assert MapSet.difference(listed, in_schema) == MapSet.new()
  end

  for name <- @names do
    @name name

    describe name do
      test "takes a typed color and a transform, and draws each on every backend" do
        for c <- [@typed, @transform] do
          {design, rows} = built(build(@name), c)
          assert Validator.validate(design) == :ok, inspect(c)

          {:ok, applied} = Chart.apply(Chart.from_map!(design), sources: %{cells: rows})
          hex = literal(c)

          assert holds?(Chart.render(applied, resolve: :literal), hex), "SVG lacks #{hex}"

          commands =
            applied
            |> Chart.generate(resolve: :literal)
            |> Canvas.render_element(format: :commands)

          assert holds?(commands, hex), "canvas commands lack #{hex}"

          records = Decoder.decode(Chart.render(applied, backend: :canvas, format: :binary))
          assert holds?(records, hex), "the binary stream lacks #{hex}"
        end
      end

      test "is canonicalized to the typed form, a bare name included" do
        {typed, _rows} = built(build(@name), @typed)
        {bare, _rows} = built(build(@name), :red)
        {transform, _rows} = built(build(@name), @transform)

        assert Migration.canonical(bare) == Migration.canonical(typed)
        assert has?(Migration.canonical(typed), @typed)
        assert has?(Migration.canonical(transform), @transform)
      end
    end
  end

  test "a range's name the table lacks is a fault at its index" do
    design = with_scale(design(%{fill: {:field, :k}}), %{kind: :ordinal, range: [:red, :nope]})

    assert {:error,
            [{[:frames, :main, :scales, :color, :range, 1], {:undeclared, :color, :nope}}]} =
             Validator.validate(design)
  end

  test "a range's colors round-trip through JSON as typed colors" do
    design =
      with_scale(design(%{fill: {:field, :k}}), %{
        kind: :ordinal,
        domain: ["a", "b", "c"],
        range: [@typed, @transform, "#00ff00"]
      })

    chart = Chart.from_map!(design)
    {:ok, json} = Chart.to_json(chart)
    assert json =~ ~s("$color":"red")
    assert {:ok, ^chart} = Chart.from_json(json)
  end

  test "an earlier document's atom in a range reads as the typed name" do
    json =
      ~s({"version": 3, "sources": {"cells": {"fields": ["k"]}}, "marks": [], "frames": {"main": {"kind": "cartesian", "scales": {"color": {"kind": "ordinal", "range": [{"$atom": "good"}, "#00ff00"]}}}}})

    assert {:ok, chart} = Chart.from_json(json)
    assert chart.frames.main.scales.color.range == [{:color, :good}, "#00ff00"]
  end
end
