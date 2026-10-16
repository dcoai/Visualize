defmodule Visualize.Backend.CanvasBinarySVGGroupTest do
  @moduledoc """
  A group's presentation attributes on the binary canvas of SVG elements (spec/09 §4.7,
  #734, D-192): what a `:g` sets is its children's state inside its `save` … `restore`,
  a child's draws follow its effective attributes — its own over the groups' — and a
  group's opacity is its children's global alpha. A group that sets none of them is the
  stream it was. The binary hook's composite of an inheriting tree is then held to resvg's.
  """
  use ExUnit.Case, async: true

  import Visualize.JsHooks, only: [run: 1]

  alias Visualize.Backend.CanvasBinary
  alias Visualize.Backend.CanvasBinary.Decoder
  alias Visualize.SVG.Element

  defp group(attrs, children), do: %{Element.g(attrs) | children: children}
  defp records(tree), do: Decoder.decode(CanvasBinary.encode_element!(tree))

  describe "the stream" do
    test "a group that sets no presentation attribute is the stream its children were" do
      child = Element.rect(%{x: 1, y: 2, width: 3, height: 4, fill: "#336699"})

      assert CanvasBinary.encode_element!(group(%{}, [child])) ==
               CanvasBinary.encode_element!(child)

      # A transform alone is drawn as it was: the group's save, its transform, its children.
      assert [:save, {:transform, _, _}, {:style, _}, {:rects, _}, :fill, :restore] =
               records(group(%{transform: "translate(5, 5)"}, [child]))
    end

    test "a group's fill, stroke and width are the state a child that sets none draws in" do
      tree =
        group(%{fill: "#ff0000", stroke: "#0000ff", "stroke-width": 3}, [
          Element.rect(%{x: 0, y: 0, width: 10, height: 10})
        ])

      assert [
               :save,
               {:style, %{fill: {255, 0, 0, 255}, stroke: {0, 0, 255, 255}, stroke_width: 3.0}},
               {:rects, _},
               :fill,
               :stroke,
               :restore
             ] = records(tree)
    end

    test "a child's own attribute wins, and combines with what it inherits" do
      tree =
        group(%{fill: "#ff0000", "fill-opacity": 0.5, stroke: "#0000ff"}, [
          # Its own fill, at the group's fill-opacity, as SVG draws it.
          Element.rect(%{x: 0, y: 0, width: 10, height: 10, fill: "#00ff00"}),
          # No fill of its own to draw: the group's stroke alone.
          Element.rect(%{x: 20, y: 0, width: 10, height: 10, fill: "none"}),
          # A stroke-opacity of its own over the group's stroke color.
          Element.rect(%{x: 40, y: 0, width: 10, height: 10, "stroke-opacity": 0.5})
        ])

      # A child whose own style changes the group's state is scoped, so the third fills
      # in the group's fill, not the first child's (#742).
      assert [
               :save,
               {:style, %{fill: {255, 0, 0, 127}, stroke: {0, 0, 255, 255}}},
               :save,
               {:style, %{fill: {0, 255, 0, 127}, stroke: nil}},
               {:rects, _},
               :fill,
               :stroke,
               :restore,
               {:rects, _},
               :stroke,
               :save,
               {:style, %{fill: nil, stroke: {0, 0, 255, 127}}},
               {:rects, _},
               :fill,
               :stroke,
               :restore,
               :restore
             ] = records(tree)
    end

    test "a child's own style ends with it: a later sibling draws in the group's (#742)" do
      tree =
        group(%{fill: "#ff0000", stroke: "#0000ff"}, [
          Element.rect(%{x: 0, y: 0, width: 10, height: 10, opacity: 0.5}),
          Element.rect(%{x: 20, y: 0, width: 10, height: 10})
        ])

      assert [
               :save,
               {:style, %{fill: {255, 0, 0, 255}, stroke: {0, 0, 255, 255}}},
               :save,
               {:style, %{fill: {255, 0, 0, 127}, stroke: {0, 0, 255, 127}}},
               {:rects, _},
               :fill,
               :stroke,
               :restore,
               {:rects, _},
               :fill,
               :stroke,
               :restore
             ] = records(tree)
    end

    test "a group's opacity is its children's global alpha, a nested group's multiplied" do
      tree =
        group(%{opacity: 0.5}, [
          group(%{opacity: "0.5"}, [
            Element.rect(%{x: 0, y: 0, width: 10, height: 10, fill: "#000000"})
          ])
        ])

      assert [
               :save,
               {:style, %{opacity: outer}},
               :save,
               {:style, %{opacity: inner}},
               {:style, %{fill: {0, 0, 0, 255}, opacity: nil}},
               {:rects, _},
               :fill,
               :restore,
               :restore
             ] = records(tree)

      assert {outer, inner} == {0.5, 0.25}
    end

    test "a group's dash, cap and join are its children's, and a version 3 stream" do
      tree =
        group(%{stroke: "#000000", "stroke-dasharray": "4 2", "stroke-linecap": "round"}, [
          Element.line(%{x1: 0, y1: 0, x2: 10, y2: 0})
        ])

      assert [
               {:version, 3},
               :save,
               {:style, _},
               {:paint_state, %{dash: [4.0, 2.0], cap: :round}},
               {:path_cubic32, _},
               :stroke,
               :restore
             ] = records(tree)
    end

    test "the root's presentation attributes are inherited as a group's" do
      tree =
        %{
          Element.svg(%{width: 20, height: 20, fill: "#ff0000"})
          | children: [
              Element.rect(%{x: 0, y: 0, width: 10, height: 10})
            ]
        }

      assert [:save, {:style, %{fill: {255, 0, 0, 255}}}, {:rects, _}, :fill, :restore] =
               records(tree)
    end
  end

  describe "an inheriting group on the binary canvas is the SVG's (#734)" do
    # Both node and resvg (test_helper, #652).
    @describetag :js_resvg

    # Two bands under one translucent group: the first takes the group's fill and its
    # fill-opacity, the second its own fill at the group's fill-opacity. They do not
    # overlap, so the group's opacity composites each alone, as the global alpha does.
    defp bands do
      %{
        Element.svg(%{width: 240, height: 120})
        | children: [
            group(%{fill: "#1f77b4", "fill-opacity": 0.6, opacity: 0.5}, [
              Element.rect(%{x: 20, y: 20, width: 200, height: 30}),
              Element.rect(%{x: 20, y: 70, width: 200, height: 30, fill: "#d62728"})
            ])
          ]
      }
    end

    # Each fill the binary hook drew, as `{[r, g, b], alpha}`: its fill style's color and
    # the alpha it composites at, the context's global alpha times the style's own.
    defp drawn_fills(tree) do
      data = %{binary: CanvasBinary.to_base64(CanvasBinary.encode_element!(tree))}

      {:ok, %{"draws" => draws}} =
        run("""
        const el = Stub.element(#{Jason.encode!(Map.merge(data, %{width: "240", height: "120"}))}, 240, 120);
        Stub.mount(CanvasBinaryChart, el);
        Stub.done({});
        """)

      for %{"name" => "fill", "fillStyle" => style, "globalAlpha" => global} <- draws do
        [r, g, b, a] =
          Regex.run(~r/rgba\((\d+),(\d+),(\d+),([\d.]+)\)/, style, capture: :all_but_first)

        {alpha, ""} = Float.parse(a)
        {Enum.map([r, g, b], &String.to_integer/1), global * alpha}
      end
    end

    test "each band's composite over the page is resvg's" do
      {:ok, png, _warnings} =
        Visualize.Render.to_png(to_string(bands()), scale: 1, background: "#ffffff")

      image = Visualize.PNGPixels.decode(png)

      assert [{[31, 119, 180], first}, {[214, 39, 40], second}] = drawn_fills(bands())
      assert_in_delta first, 0.3, 0.01
      assert_in_delta second, 0.3, 0.01

      for {{color, alpha}, y} <-
            Enum.zip([{[31, 119, 180], first}, {[214, 39, 40], second}], [35, 85]),
          px <- 30..210//20 do
        expected = for c <- color, do: 255 + (c - 255) * alpha
        {r, g, b, _} = Visualize.PNGPixels.pixel(image, px, y)

        for {got, want} <- Enum.zip([r, g, b], expected) do
          assert abs(got - want) <= 3,
                 "at #{px},#{y}: #{inspect({r, g, b})} vs #{inspect(expected)}"
        end
      end
    end
  end
end
