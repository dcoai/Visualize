defmodule Visualize.Backend.CanvasScopeTest do
  @moduledoc """
  A leaf's own transform and style are its own (spec/09 §3.3.1, §4.4, #679, D-179): every
  canvas backend draws a leaf that sets either inside `save … restore`, so its next
  sibling draws where SVG draws it and with what SVG draws it with. The hooks replay each
  stream on the recording stub, which scopes the context's properties as a browser does
  and records the transform and the state every draw call ran in.
  """
  use ExUnit.Case, async: true

  import Visualize.JsHooks, only: [run: 1]

  alias Visualize.Backend.{Canvas, CanvasBinary}
  alias Visualize.Backend.CanvasBinary.Decoder
  alias Visualize.Chart
  alias Visualize.Chart.Frame
  alias Visualize.IR.{Element, Path, Transform}

  @identity %{"a" => 1, "b" => 0, "c" => 0, "d" => 1, "e" => 0, "f" => 0}

  # Two siblings under a blue group: the first turned, moved and translucent with a fill
  # of its own, the second with nothing of its own, so it draws in the group's state.
  defp siblings do
    triangle = Path.new() |> Path.move_to(0, -5) |> Path.line_to(5, 5) |> Path.line_to(-5, 5)

    first =
      Element.path(triangle, %{fill: "red", opacity: 0.5})
      |> Element.set_transform(
        Transform.new()
        |> Transform.translate(50, 40)
        |> Transform.rotate(30)
      )

    Element.group([first, Element.rect(10, 10, 20, 20)], style: %{fill: "blue"})
  end

  defp js(value), do: Jason.encode!(value)

  defp draws(hook, data) do
    {:ok, %{"draws" => draws}} =
      run("""
      const el = Stub.element(#{js(Map.merge(data, %{width: "240", height: "200"}))}, 240, 200);
      Stub.mount(#{hook}, el);
      Stub.done({});
      """)

    draws
  end

  defp from_json(tree),
    do:
      draws("CanvasChart", %{
        commands: IO.iodata_to_binary(Canvas.render_element(tree, format: :json))
      })

  defp from_js(tree),
    do:
      draws("CanvasChart", %{
        script: IO.iodata_to_binary(Canvas.render_element(tree, format: :js))
      })

  defp from_binary(tree),
    do:
      draws("CanvasBinaryChart", %{
        binary: CanvasBinary.to_base64(CanvasBinary.encode_element!(tree))
      })

  describe "the encoders scope a leaf's setup" do
    test "a leaf that sets a transform or a style is drawn inside save … restore" do
      commands = Canvas.render_element(siblings(), format: :commands)

      assert [
               {:save, []},
               {:set_fillStyle, ["blue"]},
               {:save, []},
               {:translate, [50, 40]},
               {:rotate, [_]},
               {:set_fillStyle, ["red"]},
               {:set_globalAlpha, [0.5]},
               {:beginPath, []} | _
             ] = commands

      # The second leaf sets nothing, so it pays nothing: its path follows the restore.
      assert Enum.take(commands, -6) == [
               {:fill, []},
               {:restore, []},
               {:beginPath, []},
               {:rect, [10, 10, 20, 20]},
               {:fill, []},
               {:restore, []}
             ]
    end

    test "a bare leaf writes no save; a styled text and an image are scoped too" do
      assert Canvas.render_element(Element.rect(0, 0, 1, 1), format: :commands) ==
               [{:beginPath, []}, {:rect, [0, 0, 1, 1]}]

      text = %{Element.text("t", 1, 2, %{fill: "red"}) | transform: Transform.rotate(-90)}
      assert [{:save, []} | _] = text_commands = Canvas.render_element(text, format: :commands)
      assert List.last(text_commands) == {:restore, []}

      image =
        Element.image("a.png", 1, 2, 3, 4) |> Element.set_transform(Transform.translate(1, 1))

      assert [{:save, []}, {:translate, [1, 1]}, {:drawImage, _}, {:restore, []}] =
               Canvas.render_element(image, format: :commands)
    end

    test "the binary stream wraps the same leaves, and only them" do
      assert [
               :save,
               {:style, _},
               :save,
               {:transform, :matrix, _},
               {:style, %{opacity: 0.5}},
               {:path32, _},
               :fill,
               :restore,
               {:rects, _},
               :fill,
               :restore
             ] = Decoder.decode(CanvasBinary.encode_element!(siblings()))

      assert [{:rects, _}] =
               Decoder.decode(CanvasBinary.encode_element!(Element.rect(0, 0, 1, 1)))
    end
  end

  describe "a sibling draws in its own transform and state (#679)" do
    @describetag :js

    test "on the JSON canvas, the script canvas and the binary canvas" do
      for {stream, draws} <- [
            json: from_json(siblings()),
            js: from_js(siblings()),
            binary: from_binary(siblings())
          ] do
        assert [first, second] = draws, "#{stream}: #{inspect(draws)}"
        assert first["globalAlpha"] == 0.5
        assert_in_delta first["m"]["e"], 50, 1.0e-6

        assert second["m"] == @identity,
               "#{stream}: the second leaf drew at #{inspect(second["m"])}"

        assert second["globalAlpha"] == 1,
               "#{stream}: the second leaf drew at alpha #{second["globalAlpha"]}"

        assert second["fillStyle"] in ["blue", "rgba(0,0,255,1)"],
               "#{stream}: #{second["fillStyle"]}"
      end
    end
  end

  describe "a symbol scatter on the binary canvas is the SVG's (#679)" do
    # Both node and resvg (test_helper, #652).
    @describetag :js_resvg

    test "every symbol is drawn where resvg's raster of the SVG has it" do
      design = %{
        version: 3,
        sources: %{s: %{fields: [:x, :y]}},
        frames: %{
          main: %{
            kind: :cartesian,
            scales: %{
              x: %{kind: :linear, domain: [0, 10]},
              y: %{kind: :linear, domain: [0, 10]}
            }
          }
        },
        marks: [
          %{
            type: :symbol,
            data: :s,
            channels: %{x: :x, y: :y},
            style: %{fill: %{color: "#1f77b4"}, symbol: :square, symbol_size: 100}
          }
        ]
      }

      rows = for i <- 1..9, do: %{x: i, y: rem(i * 7, 9) + 0.5}
      {:ok, chart} = Chart.from_map(design)
      frame = Frame.new(chart, sources: %{s: rows}, size: {240, 200})
      tree = Frame.generate(frame, sources: %{s: rows}, resolve: :literal)
      root = Element.root(240, 200, children: [tree])
      {:ok, png, _warnings} = Visualize.Render.to_png(root, scale: 1, background: "#ffffff")
      image = Visualize.PNGPixels.decode(png)

      symbols =
        for %{"name" => "fill", "fillStyle" => "rgba(31,119,180,1)"} = d <- from_binary(tree),
            do: d

      assert length(symbols) == length(rows)

      for %{"m" => %{"e" => x, "f" => y}} <- symbols do
        {px, py} = {trunc(x), trunc(y)}
        assert px in 0..239 and py in 0..199, "a symbol drawn off the canvas at #{x},#{y}"
        {r, g, b, _a} = Visualize.PNGPixels.pixel(image, px, py)

        assert abs(r - 31) + abs(g - 119) + abs(b - 180) <= 24,
               "no symbol at #{x},#{y}: #{inspect({r, g, b})}"
      end
    end
  end
end
