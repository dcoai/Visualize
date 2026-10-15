defmodule Visualize.Backend.PaintOpacityTest do
  @moduledoc """
  A paint's own opacity, and every other key a fill or a stroke paints with, on every
  canvas (spec/09 §3.3.3, §4.3.17, #675, D-180). The parity test is driven by the grammar's
  one table of paint keys (`Visualize.Chart.Style.Parts.paint_keys/0`): every key SVG
  writes must change what the canvas commands and the binary stream draw, so a key added
  to the table fails here until a canvas draws it. The hooks then replay a translucent
  paint on the recording stub, and the binary hook's composite is held to resvg's raster.
  """
  use ExUnit.Case, async: true

  import Visualize.JsHooks, only: [run: 1]

  alias Visualize.Backend.{Canvas, CanvasBinary}
  alias Visualize.Backend.CanvasBinary.Decoder
  alias Visualize.Chart.Style.Parts
  alias Visualize.IR.{Element, Paint}

  @base %{fill: "#336699", stroke: "#cc0000"}

  # A value of each paint key that differs from the base's.
  @samples %{
    fill: "#2ca02c",
    fill_opacity: 0.4,
    stroke: "#9467bd",
    stroke_opacity: 0.3,
    stroke_width: 5,
    stroke_dasharray: "4 2",
    stroke_linecap: :round,
    stroke_linejoin: :bevel
  }

  # A stroke's placement is the mark's (spec/14 §5.6): `Visualize.Chart.Mark.Strokes` draws
  # it as geometry and a clip, so it never reaches an element's style.
  @not_element_keys [:stroke_style]

  defp svg(style), do: Visualize.Render.to_string(Element.rect(10, 10, 40, 20, style))

  defp commands(style),
    do: Canvas.render_element(Element.rect(10, 10, 40, 20, style), format: :json)

  defp binary(style), do: CanvasBinary.encode_element!(Element.rect(10, 10, 40, 20, style))

  describe "every paint key SVG writes reaches every canvas stream" do
    test "the canvas commands and the binary stream carry it" do
      keys = Parts.paint_keys() -- @not_element_keys
      assert :fill_opacity in keys and :stroke_opacity in keys

      for key <- keys do
        sample = Map.get(@samples, key) || flunk("no sample for the paint key #{inspect(key)}")
        {with, without} = {Map.put(@base, key, sample), Map.delete(@base, key)}

        if svg(with) != svg(without) do
          assert IO.iodata_to_binary(commands(with)) != IO.iodata_to_binary(commands(without)),
                 "SVG writes #{inspect(key)}; the canvas commands do not"

          assert binary(with) != binary(without),
                 "SVG writes #{inspect(key)}; the binary stream does not"
        end
      end
    end

    test "a paint's alpha is the element's times the paint's, set around its own draw" do
      style = %{fill: "#336699", fill_opacity: 0.4, stroke: "#cc0000", opacity: 0.5}

      assert [
               {:save, []},
               {:set_fillStyle, _},
               {:set_strokeStyle, _},
               {:set_globalAlpha, [0.5]},
               {:beginPath, []},
               {:rect, _},
               {:set_globalAlpha, [0.2]},
               {:fill, []},
               {:set_globalAlpha, [0.5]},
               {:stroke, []},
               {:restore, []}
             ] = Canvas.render_element(Element.rect(0, 0, 1, 1, style), format: :commands)
    end

    test "a stream with a paint's state is version 3; one without is unchanged" do
      plain = binary(@base)
      refute Enum.any?(Decoder.decode(plain), &match?({:version, _}, &1))

      records =
        Decoder.decode(binary(Map.merge(@base, %{fill_opacity: 0.4, stroke_dasharray: "4 2"})))

      assert [{:version, 3}, :save, {:style, _}, {:paint_state, state} | _] = records
      assert_in_delta state.fill_alpha, 0.4, 1.0e-6
      assert state.stroke_alpha == nil
      assert state.dash == [4.0, 2.0]
    end
  end

  defp js(value), do: Jason.encode!(value)

  defp draws(hook, data) do
    {:ok, %{"draws" => draws}} =
      run("""
      const el = Stub.element(#{js(Map.merge(data, %{width: "240", height: "120"}))}, 240, 120);
      Stub.mount(#{hook}, el);
      Stub.done({});
      """)

    draws
  end

  defp streams(tree) do
    [
      json:
        draws("CanvasChart", %{
          commands: IO.iodata_to_binary(Canvas.render_element(tree, format: :json))
        }),
      js:
        draws("CanvasChart", %{
          script: IO.iodata_to_binary(Canvas.render_element(tree, format: :js))
        }),
      binary:
        draws("CanvasBinaryChart", %{
          binary: CanvasBinary.to_base64(CanvasBinary.encode_element!(tree))
        })
    ]
  end

  describe "the hooks draw a translucent paint alike (#675)" do
    @describetag :js

    test "a fill and a stroke at the element's alpha times the paint's, a group's included" do
      own =
        Element.rect(10, 10, 40, 20, %{
          fill: "#336699",
          fill_opacity: 0.4,
          stroke: "#cc0000",
          stroke_opacity: 0.5,
          opacity: 0.5
        })

      grouped =
        Element.group([Element.rect(10, 10, 40, 20, %{fill: "#336699", fill_opacity: 0.4})],
          style: %{opacity: 0.5}
        )

      linear = %Paint{
        id: "fade",
        type: :linear,
        geometry: %{x1: 0, y1: 0, x2: 1, y2: 0},
        stops: [{0.0, "#d62728", 1}, {1.0, "#1f77b4", 1}]
      }

      gradient = Element.rect(10, 10, 40, 20, %{fill: linear, fill_opacity: 0.5})

      for {tree, want} <- [
            {own, [{"fill", 0.2}, {"stroke", 0.25}]},
            {grouped, [{"fill", 0.2}]},
            {gradient, [{"fill", 0.5}]}
          ],
          {stream, draws} <- streams(tree) do
        got = for d <- draws, do: {d["name"], d["globalAlpha"]}
        assert length(got) == length(want), "#{stream}: #{inspect(got)}"

        for {{name, a}, {name2, b}} <- Enum.zip(got, want) do
          assert name == name2
          assert_in_delta a, b, 1.0e-6, "#{stream}: #{name} at #{a}, not #{b}"
        end
      end
    end
  end

  describe "a translucent band on the binary canvas is the SVG's (#675)" do
    # Both node and resvg (test_helper, #652).
    @describetag :js_resvg

    test "its composite over the page is resvg's" do
      band = Element.rect(20, 30, 200, 50, %{fill: "#1f77b4", fill_opacity: 0.3})
      root = Element.root(240, 120, children: [band])
      {:ok, png, _warnings} = Visualize.Render.to_png(root, scale: 1, background: "#ffffff")

      [%{"name" => "fill", "globalAlpha" => a, "fillStyle" => "rgba(31,119,180,1)"}] =
        streams(band)[:binary]

      expected = for c <- [31, 119, 180], do: 255 + (c - 255) * a

      for px <- 25..215//10, py <- 35..75//10 do
        {r, g, b, _} = Visualize.PNGPixels.pixel(png, px, py)

        for {got, want} <- Enum.zip([r, g, b], expected) do
          assert abs(got - want) <= 3,
                 "at #{px},#{py}: #{inspect({r, g, b})} vs #{inspect(expected)}"
        end
      end
    end
  end
end
