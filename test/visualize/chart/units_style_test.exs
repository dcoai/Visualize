defmodule Visualize.Chart.UnitsStyleTest do
  @moduledoc """
  Sizes in units and strokes that do not scale (spec/14 §3.9, #651, #671, D-174): absolute
  units converted, `em` measured at compile time against the inherited font size, `pct` only
  where a size has a box, and `stroke.non_scaling` drawn by SVG and every canvas backend.
  """
  use ExUnit.Case, async: true

  import Visualize.Units

  alias Visualize.Backend.{Canvas, CanvasBinary}
  alias Visualize.Backend.CanvasBinary.Decoder
  alias Visualize.Chart
  alias Visualize.Chart.Validator
  alias Visualize.IR.Element

  @rows [%{x: 0, y: 1, k: "a"}, %{x: 1, y: 2, k: "b"}]

  defp design(marks, extra \\ %{}) do
    Map.merge(
      %{
        version: 3,
        sources: %{s: %{fields: [:x, :y, :k]}},
        frames: %{
          main: %{
            kind: :cartesian,
            scales: %{x: %{kind: :linear, domain: [0, 2]}, y: %{kind: :linear}}
          }
        },
        marks: marks
      },
      extra
    )
  end

  defp applied(design) do
    {:ok, applied} = Chart.apply(design, sources: %{s: @rows})
    applied
  end

  defp all(%Element{children: children} = element),
    do: [element | Enum.flat_map(children, &all/1)]

  defp drawn(design), do: design |> applied() |> Chart.generate(resolve: :literal) |> all()

  # The style the first element of a type draws with: its own over its groups'.
  defp style_of(design, type) do
    design |> drawn() |> hd() |> way_to(type) |> Enum.reduce(%{}, &Map.merge(&2, &1.style))
  end

  defp way_to(%Element{type: type} = element, type), do: [element]

  defp way_to(%Element{children: children} = element, type) do
    Enum.find_value(children, fn child ->
      case way_to(child, type) do
        nil -> nil
        way -> [element | way]
      end
    end)
  end

  @line %{type: :line, data: :s, channels: %{x: :x, y: :y}}
  # A text mark draws in its label's style, here one that names no font of its own.
  @text %{type: :text, data: :s, channels: %{x: :x, y: :y}, label: %{text: "t", style: %{}}}

  defp text_style(style), do: put_in(@text, [:label, :style], style)

  describe "absolute units" do
    test "convert when the style resolves, so both backends get the same number" do
      d = design([Map.put(@line, :style, %{stroke: %{width: pt(1.5), dash: [mm(2), 4]}})])
      style = style_of(d, :path)
      assert style.stroke_width == 2.0
      assert style.stroke_dasharray =~ ~r/^7\.55\d* 4$/

      svg = d |> applied() |> Chart.render()
      assert svg =~ ~s(stroke-width="2.0")
    end
  end

  describe "em" do
    test "a font size in em is measured against the inherited font size" do
      d = design([text_style(%{font: %{size: em(1.5)}})], %{defaults: %{font: %{size: pt(9)}}})
      assert style_of(d, :text).font_size == 18.0
    end

    test "containers' relative sizes nest, measured from the theme's root" do
      d =
        design([@text], %{defaults: %{font: %{size: em(1.2)}}})
        |> put_in([:frames, :main, :defaults], %{font: %{size: em(1.5)}})

      # The default theme's root font size is 10: 10 × 1.2 × 1.5.
      assert_in_delta style_of(d, :text).font_size, 18.0, 1.0e-9
    end

    test "an em anywhere else is the element's own font size, the inherited one for a line" do
      d =
        design([Map.put(@line, :style, %{stroke: %{width: em(0.2)}})], %{
          defaults: %{font: %{size: 15}}
        })

      assert_in_delta style_of(d, :path).stroke_width, 3.0, 1.0e-9

      # With no container's size, the theme's root.
      d = design([Map.put(@line, :style, %{stroke: %{width: em(0.2)}})])
      assert_in_delta style_of(d, :path).stroke_width, 2.0, 1.0e-9
    end

    test "a pct font size is of the inherited font size" do
      d = design([text_style(%{font: %{size: pct(150)}})], %{defaults: %{font: %{size: 12}}})
      assert style_of(d, :text).font_size == 18.0
    end
  end

  describe "pct where a size has a box" do
    test "a text offset in pct is of the labelled element's box" do
      rect = %{
        type: :rect,
        data: :s,
        channels: %{x0: 0, x1: :x, y0: 0, y1: :y},
        label: %{text: "#{"\#{field(:k)}"}", anchor: :right}
      }

      at = fn offset ->
        [rect |> put_in([:label, :style], %{text: %{offset: offset}})]
        |> design()
        |> drawn()
        |> Enum.filter(&(&1.type == :text))
        |> Enum.map(& &1.attrs.x)
      end

      # The second rect runs from 0 to 1 on a [0, 2] domain over 540: 270 wide.
      [_first, second] = at.([pct(50), 0])
      [_first, numeric] = at.([135, 0])
      assert second == numeric
    end

    test "a marker size in pct is the side, a percentage of the band" do
      symbol = fn size ->
        design([
          %{type: :symbol, data: :s, channels: %{x: :k, y: :y}, style: %{marker: %{size: size}}}
        ])
        |> put_in([:frames, :main, :scales, :x], %{kind: :band, domain: ["a", "b"]})
        |> drawn()
        |> Enum.filter(&(&1.type == :path))
        |> Enum.map(& &1.path)
      end

      # Two bands over 540: 270 each, so 10% is a side of 27, an area of 729.
      assert symbol.(pct(10)) == symbol.(729.0)
      # A unit-valued size is the side: 6 pt is 8 user units, an area of 64.
      assert symbol.(pt(6)) == symbol.(64.0)
    end
  end

  describe "validation and storage" do
    defp faults(style), do: elem(Validator.validate(design([Map.put(@line, :style, style)])), 1)

    test "pct has no box at a stroke's width, a dash or an effect's radius" do
      assert {[:marks, 0, :style, :stroke, :width], {:no_box, :width}} in faults(%{
               stroke: %{width: pct(10)}
             })

      assert {[:marks, 0, :style, :stroke, :dash], {:no_box, :dash}} in faults(%{
               stroke: %{dash: [pct(5), 2]}
             })

      assert {[:marks, 0, :style, :effect, :radius], {:no_box, :radius}} in faults(%{
               effect: %{type: :shadow, radius: pct(5)}
             })
    end

    test "an opacity takes no unit, and a unit must be one of the library's" do
      assert {[:marks, 0, :style, :opacity], {:no_unit, :opacity}} in faults(%{opacity: pt(1)})

      assert {[:marks, 0, :style, :stroke, :width], {:type, :size}} in faults(%{
               stroke: %{width: {3, :furlong}}
             })

      assert {[:marks, 0, :style, :stroke, :dash, 0], {:type, :length}} in faults(%{
               stroke: %{dash: [{3, :furlong}]}
             })

      assert Validator.format({[:marks, 0], {:no_box, :width}}) =~ "a pct needs a box"
    end

    test "units round-trip through the map and JSON, in styles and in defaults" do
      d =
        design(
          [
            Map.put(@line, :style, %{
              stroke: %{width: pt(1.5), dash: [mm(2), em(0.5)], non_scaling: true}
            })
          ],
          %{defaults: %{font: %{size: em(1.2)}, text: %{offset: [pct(10), 2]}}}
        )

      chart = Chart.from_map!(d)
      {:ok, json} = Chart.to_json(chart)
      assert json =~ ~s("$unit":[1.5,"pt"])
      assert Chart.from_json(json) == {:ok, chart}
    end
  end

  describe "a stroke that does not scale" do
    defp scaled_group do
      path =
        Visualize.IR.Path.new()
        |> Visualize.IR.Path.move_to(0, 0)
        |> Visualize.IR.Path.line_to(5, 5)

      Element.group([Element.path(path), Element.path(path, %{vector_effect: nil})],
        style: %{stroke: "#123456", stroke_width: 2, vector_effect: :non_scaling_stroke}
      )
    end

    test "SVG writes vector-effect on each shape that does not set its own, never on the group" do
      svg = scaled_group() |> Visualize.Render.to_string()
      refute svg =~ ~r/<g[^>]*vector-effect/
      # The second path says it has none, and keeps none.
      assert length(Regex.scan(~r/<path[^>]*vector-effect="non-scaling-stroke"/, svg)) == 1
      assert length(Regex.scan(~r/<path/, svg)) == 2
    end

    test "a design's non-scaling stroke reaches its element" do
      d = design([Map.put(@line, :style, %{stroke: %{width: 2, non_scaling: true}})])
      assert style_of(d, :path).vector_effect == :non_scaling_stroke
      assert d |> applied() |> Chart.render() =~ ~s(vector-effect="non-scaling-stroke")
    end

    test "the canvas commands divide the width by the transform's scale; the binary flags it" do
      element =
        Element.group([],
          style: %{stroke: "#123456", stroke_width: 2, vector_effect: :non_scaling_stroke}
        )

      assert Canvas.render_element(element, format: :json) |> IO.iodata_to_binary() =~
               ~s({"cmd":"nonScalingLineWidth","args":[2]})

      assert Canvas.render_element(element, format: :js) |> IO.iodata_to_binary() =~
               "ctx.lineWidth = 2 / (function(t){return Math.sqrt(Math.abs(t.a*t.d-t.b*t.c));})(ctx.getTransform());"

      assert [:save, {:style, %{stroke_width: 2.0, non_scaling: true}} | _] =
               element |> CanvasBinary.encode_element!() |> Decoder.decode()
    end
  end
end
