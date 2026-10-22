defmodule Visualize.Backend.TextHaloTest do
  @moduledoc """
  A stroked text paints its stroke under its fill, on every backend (spec/09 §2.5, §3.3,
  spec/14 §3.1, #775, #927, D-235): a halo frames its glyphs and never eats them. SVG writes
  `paint-order="stroke"` on a `<text>` whose effective stroke — its own, else its groups' —
  is present, and on nothing else; the `:json` and `:js` canvas commands stroke the text
  before they fill it; the binary stream carries no text (spec/09 §4.4). Under `:resvg`, the
  raster of a dark text with a thick light halo keeps its fill inside its glyph; under
  `:js`, the canvas hook strokes the text before it fills it, in the halo's color and width.
  """
  use ExUnit.Case, async: true

  import Visualize.JsHooks, only: [run: 1]

  alias Visualize.Backend.{Canvas, CanvasBinary}
  alias Visualize.Chart
  alias Visualize.IR.Element
  alias Visualize.PNGPixels
  alias Visualize.Render
  alias Visualize.Render.Segments

  @ink "#1a1a1a"
  @halo %{stroke: "#ffffff", stroke_width: 24}
  @font %{font_size: 96, font_weight: "bold", font_family: "DejaVu Sans", text_anchor: :middle}

  # The bundled font and no system fonts (spec/12 §6).
  @fonts [
    font_dirs: ["test/support/fonts"],
    system_fonts: false,
    generic_families: [sans_serif: "DejaVu Sans"]
  ]

  # A bold "I" whose stem is narrower than the halo: a stroke painted over the fill covers
  # the whole glyph, and one painted under it leaves the stem in the fill.
  defp own, do: Element.text("I", 60, 130, Map.merge(@font, Map.put(@halo, :fill, @ink)))

  # The same text inheriting its fill and halo from its group, as a mark's text does.
  defp inherited do
    Element.group([Element.text("I", 180, 130, @font)], style: Map.put(@halo, :fill, @ink))
  end

  defp svg(element), do: Render.to_string(element, backend: :svg)

  describe "the decision (spec/02 §2.1)" do
    test "a text paints its stroke first where its effective stroke is present" do
      assert Element.stroke_first?(own(), %{})
      assert Element.stroke_first?(Element.text("I", 0, 0), %{stroke: "#ffffff"})
      refute Element.stroke_first?(Element.text("I", 0, 0), %{})
      refute Element.stroke_first?(Element.text("I", 0, 0, %{stroke: :none}), %{stroke: "#fff"})
      refute Element.stroke_first?(Element.text("I", 0, 0), %{stroke: :none})
      refute Element.stroke_first?(Element.rect(0, 0, 4, 4, @halo), %{})
    end
  end

  describe "SVG (spec/09 §2.5)" do
    test "a stroked text writes paint-order=\"stroke\", its own stroke or its group's" do
      assert svg(own()) =~ ~r/<text [^>]*paint-order="stroke"/
      assert svg(inherited()) =~ ~r/<text [^>]*paint-order="stroke"/
      # The group's other children and the group itself paint in SVG's order.
      group = Element.group([Element.rect(0, 0, 4, 4), Element.text("I", 0, 0)], style: @halo)
      assert [_] = Regex.scan(~r/paint-order/, svg(group))
      assert svg(group) =~ ~r/<g [^>]*>(?:(?!paint-order).)*<rect/
    end

    test "nested groups carry the stroke down, and a text's or a group's :none ends it" do
      nested = Element.group([Element.group([Element.text("I", 0, 0)])], style: @halo)
      assert svg(nested) =~ ~r/<text [^>]*paint-order="stroke"/

      for unstroked <- [
            Element.text("I", 0, 0, %{fill: @ink}),
            Element.group([Element.text("I", 0, 0, %{stroke: :none})], style: @halo),
            Element.group([Element.group([Element.text("I", 0, 0)], style: %{stroke: :none})],
              style: @halo
            ),
            Element.rect(0, 0, 4, 4, @halo)
          ] do
        refute svg(unstroked) =~ "paint-order"
      end
    end

    test "the segments and the HEEx bridge write the markup the backend writes" do
      tree = Element.root(240, 160, children: [own(), inherited()])
      {segments, _cache} = Segments.svg(tree, %{})
      assert Segments.text(segments, :svg) == svg(tree)

      bridged = tree |> Visualize.SVG.Element.from_ir() |> Visualize.SVG.Renderer.render()
      assert [_, _] = Regex.scan(~r/paint-order="stroke"/, IO.iodata_to_binary(bridged))
    end

    test "a chart's text mark and label with a stroke in their style write it" do
      design = %{
        version: 3,
        sources: %{s: %{fields: [:x, :y, :t]}},
        styles: %{"halo" => %{fill: @ink, stroke: %{color: "#ffffff", width: 3}}},
        frames: %{
          main: %{
            kind: :cartesian,
            scales: %{x: %{kind: :linear, domain: [0, 10]}, y: %{kind: :linear, domain: [0, 10]}}
          }
        },
        marks: [%{type: :text, data: :s, channels: %{x: :x, y: :y, value: :t}, style: "halo"}],
        labels: [%{anchor: :title, text: ["Title"], style: "halo", frame: :main}]
      }

      rows = [%{x: 2, y: 3, t: "a"}, %{x: 5, y: 6, t: "b"}]
      {:ok, chart} = Chart.from_map(design)
      frame = Chart.Frame.new(chart, sources: %{s: rows}, size: {300, 200})
      out = svg(Chart.Frame.generate(frame, sources: %{s: rows}, resolve: :literal))

      texts = Regex.scan(~r/<text [^>]*>[^<]*/, out) |> List.flatten()
      haloed = Enum.filter(texts, &(&1 =~ ~r/>(a|b|Title)$/))
      assert length(haloed) == 3
      for text <- haloed, do: assert(text =~ ~s(paint-order="stroke"), text)
      for text <- texts -- haloed, do: refute(text =~ "paint-order", text)
    end
  end

  describe "the canvas commands (spec/09 §3.3)" do
    test "a stroked text is stroked, in its halo, before it is filled" do
      assert [
               {:save, []},
               {:set_font, ["bold 96px DejaVu Sans"]},
               {:set_textAlign, ["center"]},
               {:set_fillStyle, [@ink]},
               {:set_strokeStyle, ["#ffffff"]},
               {:set_lineWidth, [24]},
               {:strokeText, ["I", 60, 130]},
               {:fillText, ["I", 60, 130]},
               {:restore, []}
             ] == Canvas.render_element(own(), format: :commands)

      assert [_save, {:set_fillStyle, _}, {:set_strokeStyle, _}, {:set_lineWidth, _} | rest] =
               Canvas.render_element(inherited(), format: :commands)

      assert [{:strokeText, ["I", 180, 130]}, {:fillText, ["I", 180, 130]}] =
               Enum.filter(rest, &match?({name, _} when name in [:strokeText, :fillText], &1))
    end

    test "a text of several lines strokes each line before filling it" do
      text = %{
        own()
        | content: nil,
          children: [Element.tspan("I", %{x: 60, dy: 0}), Element.tspan("I", %{x: 60, dy: 2})]
      }

      draws =
        text
        |> Canvas.render_element(format: :commands)
        |> Enum.filter(&match?({name, _} when name in [:strokeText, :fillText], &1))

      assert [
               {:strokeText, ["I", 60, 130]},
               {:fillText, ["I", 60, 130]},
               {:strokeText, ["I", 60, 132]},
               {:fillText, ["I", 60, 132]}
             ] == draws
    end

    test "an unstroked text is filled alone, and :js writes strokeText" do
      plain = Element.group([Element.text("I", 0, 0, %{stroke: :none})], style: @halo)

      refute Enum.any?(
               Canvas.render_element(plain, format: :commands),
               &match?({:strokeText, _}, &1)
             )

      js = IO.iodata_to_binary(Canvas.render_element(own(), format: :js))
      assert js =~ "ctx.strokeText('I', 60, 130);\nctx.fillText('I', 60, 130);"
    end

    test "the binary stream carries no text (spec/09 §4.4)" do
      assert CanvasBinary.encode_element!(Element.group([own()])) ==
               CanvasBinary.encode_element!(Element.group([]))
    end
  end

  describe "the canvas hook (spec/12 §6)" do
    @describetag :js

    test "strokes the text in the halo's color and width, then fills it in its own" do
      data = %{
        commands:
          IO.iodata_to_binary(
            Canvas.render_element(Element.group([own(), inherited()]), format: :json)
          ),
        width: "240",
        height: "160"
      }

      {:ok, %{"draws" => draws}} =
        run("""
        Stub.mount(CanvasChart, Stub.element(#{Jason.encode!(data)}, 240, 160));
        Stub.done({});
        """)

      texts = Enum.filter(draws, &(&1["name"] in ["strokeText", "fillText"]))

      assert [
               {"strokeText", "#ffffff", 24},
               {"fillText", @ink, _},
               {"strokeText", "#ffffff", 24},
               {"fillText", @ink, _}
             ] = Enum.map(texts, &{&1["name"], style(&1), &1["lineWidth"]})
    end
  end

  describe "the raster (spec/09 §9)" do
    @describetag :resvg

    # The middle of each "I"'s stem is the text's fill on resvg's raster of the SVG, the
    # halo beside it, and the page beyond.
    test "a dark text under a thick light halo keeps its fill inside its glyph" do
      tree = Element.root(240, 160, children: [own(), inherited()])
      {:ok, png, []} = Render.to_png(tree, [scale: 1, background: "#808080"] ++ @fonts)
      image = PNGPixels.decode(png)

      for x <- [60, 180] do
        for y <- 80..120//10 do
          assert {0x1A, 0x1A, 0x1A, _} = PNGPixels.pixel(image, x, y), "#{x},#{y}: the glyph"
        end

        assert {255, 255, 255, _} = PNGPixels.pixel(image, x + 10, 100), "#{x}: the halo"
        assert {0x80, 0x80, 0x80, _} = PNGPixels.pixel(image, x + 30, 100), "#{x}: the page"
      end
    end
  end

  defp style(%{"name" => "strokeText", "strokeStyle" => s}), do: s
  defp style(%{"name" => "fillText", "fillStyle" => s}), do: s
end
