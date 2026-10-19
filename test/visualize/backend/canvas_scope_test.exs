defmodule Visualize.Backend.CanvasScopeTest do
  @moduledoc """
  A leaf's own transform and style are its own (spec/09 §3.3.1, §4.4, #679, D-179): every
  canvas backend draws a leaf that sets either inside `save … restore`, so its next
  sibling draws where SVG draws it and with what SVG draws it with. The hooks replay each
  stream on the recording stub, which scopes the context's properties as a browser does
  and records the transform and the state every draw call ran in. Every encoder in
  `Visualize.CanvasEncoders` runs two siblings for every piece of state a leaf sets, the
  SVG-element encoder's root-level leaves included (spec/09 §4.7, #744, D-193).
  """
  use ExUnit.Case, async: true

  import Visualize.JsHooks, only: [run: 1]

  alias Visualize.Backend.{Canvas, CanvasBinary}
  alias Visualize.Backend.CanvasBinary.Decoder
  alias Visualize.CanvasEncoders
  alias Visualize.Chart
  alias Visualize.Chart.Frame
  alias Visualize.IR.{Element, Path, Transform}
  alias Visualize.SVG

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

  # Every piece of state a leaf can set, as the value its first sibling sets (#744): each
  # paint key, the element's opacity, and a transform.
  @state %{
    fill: "#2ca02c",
    fill_opacity: 0.4,
    stroke: "#9467bd",
    stroke_opacity: 0.3,
    stroke_width: 6,
    stroke_dasharray: "4 2",
    stroke_linecap: :round,
    stroke_linejoin: :bevel,
    opacity: 0.5,
    transform: :turned
  }

  @base %{fill: "#336699", stroke: "#cc0000"}

  # Where two siblings stand: at the root, under a group that sets nothing, and under a
  # group whose fill, stroke and width are their state.
  @places [
    root: &__MODULE__.at_root/1,
    bare_group: &Element.group/1,
    group_state: &__MODULE__.under_state/1
  ]

  @doc false
  def at_root(children), do: Element.root(240, 200, children: children)

  @doc false
  def under_state(children),
    do: Element.group(children, style: %{fill: "blue", stroke: "#00aa00", stroke_width: 2})

  defp leaf(x, style) do
    {transform, style} = Map.pop(style, :transform)
    rect = Element.rect(x, 20, 40, 30, style)

    if transform,
      do: Element.set_transform(rect, Transform.new() |> Transform.rotate(30)),
      else: rect
  end

  describe "every encoder's sibling draws as it draws alone, for every state key (#744)" do
    @describetag :js

    test "the encoders' list is the paint guard's: every canvas module is in it or named" do
      {:ok, modules} = :application.get_key(:visualize, :modules)

      canvas =
        for m <- modules, String.starts_with?(inspect(m), "Visualize.Backend.Canvas"), do: m

      assert Enum.sort(canvas) ==
               Enum.sort(Map.keys(CanvasEncoders.encoders()) ++ CanvasEncoders.not_encoders())
    end

    test "the first sets one key, the second none of it; each draws as it does alone" do
      cases =
        for {key, value} <- @state, {place, wrap} <- @places do
          first = leaf(20, Map.put(@base, key, value))
          second = leaf(140, Map.delete(@base, key))
          {{key, place}, [wrap.([first, second]), wrap.([first]), wrap.([second])]}
        end

      for encoder <- Map.keys(CanvasEncoders.encoders()) do
        drawn =
          CanvasEncoders.draws(encoder, Enum.flat_map(cases, &elem(&1, 1)))
          |> Enum.chunk_every(3)

        for {{{key, place}, _trees}, [both, first, second]} <- Enum.zip(cases, drawn) do
          assert first != [] and second != [], "#{inspect(encoder)} drew nothing"

          assert both == first ++ second,
                 "#{inspect(encoder)}: a sibling after one that sets #{inspect(key)} " <>
                   "(#{place}) draws #{inspect(both -- first)}, alone #{inspect(second)}"

          # The comparison holds as well for an encoder that drops the state as for one that
          # scopes it, so the transform the first sets is asserted drawn (#746): turned by
          # 30°, to the precision the commands write an angle in.
          if key == :transform do
            for %{"m" => m} <- first do
              assert_in_delta m["b"],
                              :math.sin(:math.pi() / 6),
                              1.0e-4,
                              "#{inspect(encoder)} (#{place}) drew the turned leaf at #{inspect(m)}"
            end
          end
        end
      end
    end
  end

  describe "a root-level SVG line after a wide one is SVG's (#744)" do
    defp lines do
      line = fn y, attrs ->
        SVG.Element.line(Map.merge(%{x1: 20, y1: y, x2: 220, y2: y, stroke: "#000000"}, attrs))
      end

      %{
        SVG.Element.svg(%{width: 240, height: 120})
        | children: [line.(40, %{"stroke-width": 6}), line.(80, %{})]
      }
    end

    test "the wide line's width is scoped to it" do
      assert [
               :save,
               {:style, %{stroke_width: 6.0}},
               {:path_cubic32, _},
               :stroke,
               :restore,
               :save,
               {:style, %{stroke_width: nil}},
               {:path_cubic32, _},
               :stroke,
               :restore
             ] = Decoder.decode(CanvasBinary.encode_element!(lines()))
    end

    # Both node and resvg (test_helper, #652).
    @tag :js_resvg
    test "the binary hook strokes the second at 1, as resvg's raster has it" do
      {:ok, png, _warnings} =
        Visualize.Render.to_png(to_string(lines()), scale: 1, background: "#ffffff")

      image = Visualize.PNGPixels.decode(png)

      # The ink in a column across each line: resvg's widths.
      ink = fn y0 ->
        Enum.count((y0 - 8)..(y0 + 8), fn y ->
          {r, _g, _b, _a} = Visualize.PNGPixels.pixel(image, 120, y)
          r < 128
        end)
      end

      assert {ink.(40), ink.(80)} == {6, 1}

      {:ok, %{"draws" => draws}} =
        run("""
        const el = Stub.element(#{js(%{binary: CanvasBinary.to_base64(CanvasBinary.encode_element!(lines())), width: "240", height: "120"})}, 240, 120);
        Stub.mount(CanvasBinaryChart, el);
        Stub.done({});
        """)

      assert [6, 1] = for(%{"name" => "stroke", "lineWidth" => w} <- draws, do: w)
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
