defmodule Visualize.Backend.CanvasBinarySVGRefsTest do
  @moduledoc """
  What the SVG-element encoder draws that it once dropped (spec/09 §4.7, #825, D-211): the
  `ellipse`, `polygon` and `polyline` tags as the paths they are; a `clip-path` and a
  `mask` resolved against the tree's ids into `clip` records in the element's user space;
  `mix-blend-mode` into the `blend` record; a `filter` the library writes into the `effect`
  record; `vector-effect="non-scaling-stroke"` into the style record's bit 4; each stream
  at the least version it needs, and every definition the records cannot hold drawn as if
  absent.
  """
  use ExUnit.Case, async: true

  alias Visualize.Backend.CanvasBinary
  alias Visualize.Backend.CanvasBinary.Decoder
  alias Visualize.IR
  alias Visualize.SVG.Element

  defp group(attrs, children), do: %{Element.g(attrs) | children: children}
  defp records(tree), do: Decoder.decode(CanvasBinary.encode_element!(tree))
  defp bytes(tree), do: CanvasBinary.encode_element!(tree)

  defp square(attrs \\ %{}),
    do: Element.rect(Map.merge(%{x: 10, y: 10, width: 40, height: 20, fill: "#336699"}, attrs))

  defp clip_path(id, children), do: %{Element.clipPath(%{id: id}) | children: children}

  defp mask(id, children, attrs \\ %{mask_units: "userSpaceOnUse"}),
    do: %{Element.new(:mask, Map.put(attrs, :id, id)) | children: children}

  defp filter(id, children), do: %{Element.new(:filter, %{id: id}) | children: children}

  describe "the three tags are the paths they are" do
    test "an ellipse is the IR encoder's four quarter-arcs; a polygon closes, a polyline does not" do
      ellipse = Element.ellipse(%{cx: 30, cy: 20, rx: 10, ry: 5, fill: "#336699"})
      ir = IR.Element.ellipse(30, 20, 10, 5, %{fill: "#336699"})

      assert [
               :save,
               {:style, _},
               {:path_cubic32, [{:M, _, _}, {:C, _, _, _, _, _, _} | _]},
               :fill,
               :restore
             ] =
               records(ellipse)

      assert records(ellipse) == records(ir)

      assert [
               :save,
               _,
               {:path_cubic32, [{:M, +0.0, +0.0}, {:L, 10.0, +0.0}, {:L, 5.0, 8.0}, :Z]},
               :fill,
               :restore
             ] =
               records(Element.polygon(%{points: "0,0 10,0 5,8", fill: "red"}))

      assert [
               :save,
               _,
               {:path_cubic32, [{:M, +0.0, +0.0}, {:L, 10.0, +0.0}, {:L, 5.0, 8.0}]},
               :stroke,
               :restore
             ] =
               records(Element.polyline(%{points: "0 0, 10 0 5 8 7", stroke: "red"}))

      # A list of points reads as the string does.
      assert records(Element.polygon(%{points: [{0, 0}, {10, 0}, {5, 8}], fill: "red"})) ==
               records(Element.polygon(%{points: "0,0 10,0 5,8", fill: "red"}))
    end

    test "a shape SVG renders nothing of draws nothing" do
      for shape <- [
            Element.ellipse(%{cx: 1, cy: 1, rx: 0, ry: 5, fill: "red"}),
            Element.polygon(%{points: "4", fill: "red"}),
            Element.polyline(%{fill: "red"})
          ] do
        assert bytes(shape) == <<>>
      end
    end

    test "each takes its transform and style as a path does" do
      assert [:save, {:transform, _, _}, {:style, _}, {:path_cubic32, _}, :fill, :restore] =
               records(
                 Element.ellipse(%{
                   cx: 0,
                   cy: 0,
                   rx: 4,
                   ry: 2,
                   fill: "red",
                   opacity: 0.5,
                   transform: "translate(5,5)"
                 })
               )
    end
  end

  describe "a clip-path and a mask are clip records" do
    test "a clipPath of one shape keeps inside it, in the element's user space; version 4" do
      tree =
        group(%{}, [
          group(%{}, [clip_path("c", [Element.circle(%{cx: 30, cy: 20, r: 9})])]),
          square(%{clip_path: "url(#c)", transform: "translate(5,5)"})
        ])

      assert [
               {:version, 4},
               :save,
               {:transform, :translate, {5.0, 5.0}},
               {:circles, [{30.0, 20.0, 9.0}]},
               {:clip, :inside},
               :save,
               {:style, _},
               {:rects, [{10.0, 10.0, 40.0, 20.0}]},
               :fill,
               :restore,
               :restore
             ] = records(tree)

      # A hyphenated name and a quoted reference read alike.
      assert bytes(
               group(%{}, [
                 clip_path("c", [Element.circle(%{cx: 30, cy: 20, r: 9})]),
                 square(%{"clip-path": "url('#c')"})
               ])
             ) ==
               bytes(
                 group(%{}, [
                   clip_path("c", [Element.circle(%{cx: 30, cy: 20, r: 9})]),
                   square(%{clip_path: "url(#c)"})
                 ])
               )
    end

    test "the library's outside mask is one outside clip; a white rectangle and a black shape two" do
      shape = Element.circle(%{cx: 30, cy: 20, r: 9, fill: "black"})

      everything =
        Element.rect(%{x: -100_000, y: -100_000, width: 200_000, height: 200_000, fill: "white"})

      small = Element.rect(%{x: 0, y: 0, width: 60, height: 40, fill: "#ffffff"})

      outside = group(%{}, [mask("m", [everything, shape]), square(%{mask: "url(#m)"})])

      assert [
               {:version, 4},
               :save,
               {:circles, _},
               {:clip, :outside},
               :save,
               {:style, _},
               {:rects, _},
               :fill,
               :restore,
               :restore
             ] =
               records(outside)

      both = group(%{}, [mask("m", [small, shape]), square(%{mask: "url(#m)"})])

      assert [
               {:version, 4},
               :save,
               {:rects, [{+0.0, +0.0, 60.0, 40.0}]},
               {:clip, :inside},
               {:circles, _},
               {:clip, :outside} | _
             ] = records(both)

      white =
        group(%{}, [
          mask("m", [%{shape | attrs: %{shape.attrs | fill: "white"}}]),
          square(%{mask: "url(#m)"})
        ])

      assert [{:version, 4}, :save, {:circles, _}, {:clip, :inside} | _] = records(white)
    end

    test "a clip-path and a mask on one element are both clips, the clip-path's first" do
      tree =
        group(%{}, [
          clip_path("c", [Element.circle(%{cx: 30, cy: 20, r: 9})]),
          mask("m", [Element.rect(%{x: 0, y: 0, width: 5, height: 5, fill: "white"})]),
          square(%{clip_path: "url(#c)", mask: "url(#m)"})
        ])

      assert [
               {:version, 4},
               :save,
               {:circles, _},
               {:clip, :inside},
               {:rects, _},
               {:clip, :inside} | _
             ] =
               records(tree)
    end

    test "a definition the records cannot hold is drawn as if absent, and the stream as it was" do
      plain = bytes(square())
      circle = Element.circle(%{cx: 30, cy: 20, r: 9})

      for definition <- [
            clip_path("x", [circle, circle]),
            clip_path("x", [%{circle | attrs: Map.put(circle.attrs, :transform, "scale(2)")}]),
            %{clip_path("x", [circle]) | attrs: %{id: "x", clip_path_units: "objectBoundingBox"}},
            mask("x", [%{circle | attrs: Map.put(circle.attrs, :fill, "#808080")}]),
            mask("x", [%{circle | attrs: Map.put(circle.attrs, :fill, "white")}], %{}),
            Element.rect(%{id: "x", x: 0, y: 0, width: 1, height: 1})
          ] do
        for ref <- [:clip_path, :mask] do
          tree =
            group(%{}, [%{Element.defs() | children: [definition]}, square(%{ref => "url(#x)"})])

          assert bytes(tree) == plain, "#{inspect(definition.tag)} as a #{ref}"
        end
      end

      # A reference to nothing.
      assert bytes(square(%{clip_path: "url(#nothing)"})) == plain
    end
  end

  describe "a mix-blend-mode is the blend record" do
    test "as an attribute or in the inline style, on a leaf and on a group" do
      assert [
               {:version, 4},
               :save,
               {:style, _},
               {:blend, "multiply"},
               {:rects, _},
               :fill,
               :restore
             ] =
               records(square(%{mix_blend_mode: "multiply"}))

      assert records(square(%{style: "opacity: 1; mix-blend-mode: color-dodge !important"})) ==
               records(square(%{"mix-blend-mode": "color-dodge"}))

      assert [
               {:version, 4},
               :save,
               {:blend, "screen"},
               :save,
               {:style, _},
               {:rects, _},
               :fill,
               :restore,
               :restore
             ] =
               records(group(%{style: "mix-blend-mode:screen"}, [square()]))

      # Normal and a word outside the fifteen write nothing, as on the IR encoder.
      for word <- ["normal", "plus-lighter"] do
        assert bytes(square(%{mix_blend_mode: word})) == bytes(square())
      end

      # A CSS keyword is read as CSS reads it, whatever its case.
      assert records(square(%{mix_blend_mode: " MULTIPLY "})) ==
               records(square(%{mix_blend_mode: "multiply"}))
    end
  end

  describe "a filter the library writes is the effect record" do
    test "a drop shadow and a blur, as the IR encoder writes the effect they were declared from" do
      shadow = %IR.Element{
        type: :rect,
        attrs: %{x: 10, y: 10, width: 40, height: 20},
        style: %{fill: "#336699", effect: :shadow, effect_radius: 4}
      }

      blur = %{shadow | style: %{fill: "#336699", effect: :blur, effect_radius: 2}}

      colored = %{
        shadow
        | style: Map.merge(shadow.style, %{effect_offset: [1, 2], effect_color: "#ff000080"})
      }

      for ir <- [shadow, blur, colored] do
        filter =
          case ir.style.effect do
            :shadow ->
              [dx, dy] =
                ir.style[:effect_offset] ||
                  [ir.style.effect_radius / 2, ir.style.effect_radius / 2]

              IR.Element.drop_shadow(dx, dy, ir.style.effect_radius, ir.style[:effect_color])

            :blur ->
              IR.Element.gaussian_blur(ir.style.effect_radius)
          end

        id =
          Visualize.Backend.SVG.effect_id(
            ir.style.effect,
            ir.style.effect_radius,
            ir.style[:effect_offset],
            ir.style[:effect_color]
          )

        tree = IR.Element.group([IR.Element.defs([IR.Element.filter(id, [filter])]), ir])

        [effect] = for e <- records(tree), is_tuple(e) and elem(e, 0) == :effect, do: e

        assert [^effect] =
                 for(
                   e <- records(Element.from_ir(tree)),
                   is_tuple(e) and elem(e, 0) == :effect,
                   do: e
                 )

        assert [{:version, 2} | _] = records(Element.from_ir(tree))
      end
    end

    test "a filter the record cannot hold is drawn as if absent" do
      plain = bytes(square())
      shadow = Element.new(:feDropShadow, %{dx: 1, dy: 1, std_deviation: 2})

      for definition <- [
            filter("f", [shadow, shadow]),
            filter("f", [Element.new(:feOffset, %{dx: 1})]),
            filter("f", [Element.new(:feGaussianBlur, %{std_deviation: "2 4"})]),
            filter("f", [Element.new(:feGaussianBlur, %{std_deviation: 2, in: "SourceAlpha"})]),
            %{filter("f", [shadow]) | attrs: %{id: "f", x: "-50%"}}
          ] do
        assert bytes(group(%{}, [definition, square(%{filter: "url(#f)"})])) == plain
      end
    end
  end

  describe "a stroke that does not scale" do
    test "writes its effective width with bit 4 after its own transform; a group's is not read" do
      leaf =
        Element.rect(%{
          x: 0,
          y: 0,
          width: 4,
          height: 4,
          stroke: "red",
          vector_effect: "non-scaling-stroke",
          transform: "scale(3)"
        })

      assert [
               :save,
               {:transform, _, _},
               {:style, %{stroke_width: 1.0, non_scaling: true}},
               {:rects, _},
               :stroke,
               :restore
             ] =
               records(leaf)

      inherited = group(%{"stroke-width": 2}, [leaf])

      assert [
               :save,
               {:style, %{stroke_width: 2.0}},
               :save,
               _,
               {:style, %{stroke_width: 2.0, non_scaling: true}} | _
             ] = records(inherited)

      # A group's vector-effect does nothing in SVG.
      assert bytes(
               group(%{stroke: "red", vector_effect: "non-scaling-stroke"}, [
                 Element.rect(%{width: 4, height: 4})
               ])
             ) ==
               bytes(group(%{stroke: "red"}, [Element.rect(%{width: 4, height: 4})]))

      # An element that does not stroke writes no width.
      assert bytes(square(%{vector_effect: "non-scaling-stroke"})) == bytes(square())
    end

    test "is the IR encoder's record for the same element" do
      ir =
        IR.Element.rect(0, 0, 4, 4, %{
          stroke: "#ff0000",
          stroke_width: 2,
          vector_effect: :non_scaling_stroke
        })

      assert records(ir) == records(Element.from_ir(ir))
    end
  end
end
