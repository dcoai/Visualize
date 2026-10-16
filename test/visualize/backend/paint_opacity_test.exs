defmodule Visualize.Backend.PaintOpacityTest do
  @moduledoc """
  A paint's own opacity, and every other key a fill or a stroke paints with, on every
  canvas (spec/09 §3.3.3, §4.3.17, #675, D-180). The parity test is driven by the grammar's
  one table of paint keys (`Visualize.Chart.Style.Parts.paint_keys/0`): every key SVG
  writes must change what every canvas encoder draws, so a key added to the table fails
  here until each canvas draws it. The encoders are one list, `@encoders`, and every module
  under `Visualize.Backend.Canvas*` is either in it or named as no encoder, so a new encoder
  cannot escape the guard (#693). The hooks then replay a translucent paint on the
  recording stub, and the binary hook's composite is held to resvg's raster; so is an SVG
  element's dashed, capped and joined stroke (#693).
  """
  use ExUnit.Case, async: true

  import Visualize.JsHooks, only: [run: 1]

  alias Visualize.Backend.{Canvas, CanvasBinary, CanvasIncremental}
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

  # Every canvas encoder, by its module, as the bytes it writes for an IR element: the
  # SVG-element encoder is given the element as `Visualize.SVG.Element.from_ir/1` makes it.
  @encoders %{
    Canvas => &__MODULE__.commands/1,
    CanvasBinary => &CanvasBinary.encode_element!/1,
    CanvasBinary.SVG => &__MODULE__.svg_elements/1,
    CanvasIncremental => &CanvasIncremental.encode_full_redraw/1
  }

  # The modules under `Visualize.Backend.Canvas*` that encode no element: a geometry
  # helper, the commands' serializer (the canvas commands' `:json` is it), the decoder,
  # the opcode table and the path record writer.
  @not_encoders [
    Canvas.Arc,
    Canvas.Output,
    CanvasBinary.Decoder,
    CanvasBinary.Opcodes,
    CanvasBinary.PathEncoder
  ]

  defp rect(style), do: Element.rect(10, 10, 40, 20, style)

  defp svg(style), do: Visualize.Render.to_string(rect(style))

  @doc false
  def commands(element), do: IO.iodata_to_binary(Canvas.render_element(element, format: :json))

  @doc false
  def svg_elements(element),
    do: CanvasBinary.encode_element!(Visualize.SVG.Element.from_ir(element))

  defp binary(style), do: CanvasBinary.encode_element!(rect(style))

  describe "every paint key SVG writes reaches every canvas stream" do
    test "the encoders' list holds every canvas module that encodes an element" do
      {:ok, modules} = :application.get_key(:visualize, :modules)

      canvas =
        for m <- modules, String.starts_with?(inspect(m), "Visualize.Backend.Canvas"), do: m

      assert Enum.sort(canvas) == Enum.sort(Map.keys(@encoders) ++ @not_encoders),
             "a canvas module is neither an encoder in @encoders nor in @not_encoders"
    end

    test "every canvas encoder carries it" do
      keys = Parts.paint_keys() -- @not_element_keys
      assert :fill_opacity in keys and :stroke_opacity in keys

      for key <- keys, {encoder, encode} <- @encoders do
        sample = Map.get(@samples, key) || flunk("no sample for the paint key #{inspect(key)}")
        {with, without} = {Map.put(@base, key, sample), Map.delete(@base, key)}

        if svg(with) != svg(without) do
          assert encode.(rect(with)) != encode.(rect(without)),
                 "SVG writes #{inspect(key)}; #{inspect(encoder)} does not"
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
      image = Visualize.PNGPixels.decode(png)

      [%{"name" => "fill", "globalAlpha" => a, "fillStyle" => "rgba(31,119,180,1)"}] =
        streams(band)[:binary]

      expected = for c <- [31, 119, 180], do: 255 + (c - 255) * a

      for px <- 25..215//10, py <- 35..75//10 do
        {r, g, b, _} = Visualize.PNGPixels.pixel(image, px, py)

        for {got, want} <- Enum.zip([r, g, b], expected) do
          assert abs(got - want) <= 3,
                 "at #{px},#{py}: #{inspect({r, g, b})} vs #{inspect(expected)}"
        end
      end
    end
  end

  # -- an SVG element's stroke on the binary canvas (#693) ---------------------------------

  defp svg_stream(tree), do: CanvasBinary.encode_element!(Visualize.SVG.Element.from_ir(tree))

  defp stroke_path(points, style) do
    [{x0, y0} | rest] = points

    path =
      Enum.reduce(rest, Visualize.IR.Path.move_to(Visualize.IR.Path.new(), x0, y0), fn {x, y},
                                                                                       p ->
        Visualize.IR.Path.line_to(p, x, y)
      end)

    Element.path(path, Map.merge(%{fill: :none, stroke: "#1f77b4", stroke_width: 8}, style))
  end

  describe "an SVG element's dash, cap and join reach the binary stream (#693)" do
    test "a version 3 stream, the record after the style, the element in save and restore" do
      dashed =
        stroke_path([{0, 0}, {10, 0}], %{
          stroke_dasharray: "4 2",
          stroke_linecap: :square,
          stroke_linejoin: :bevel
        })

      assert [
               {:version, 3},
               :save,
               {:style, _},
               {:paint_state, %{cap: :square, join: :bevel, dash: [4.0, 2.0]} = state},
               {:path_cubic32, _},
               :stroke,
               :restore
             ] = Decoder.decode(svg_stream(dashed))

      # The opacities are folded into the colors' alpha, never kept as state.
      assert state.fill_alpha == nil and state.stroke_alpha == nil
    end

    test "a hyphenated attribute and a name read as the atom does" do
      svg =
        Visualize.SVG.Element.line(%{
          x1: 0,
          y1: 0,
          x2: 9,
          y2: 0,
          stroke: "red",
          "stroke-dasharray": [3, 1],
          "stroke-linecap": "round",
          "stroke-linejoin": "miter"
        })

      records = Decoder.decode(CanvasBinary.encode_element!(svg))

      assert {:paint_state, %{cap: :round, join: :miter, dash: [3.0, 1.0]}} =
               Enum.find(records, &match?({:paint_state, _}, &1))
    end

    test "a tree that sets none of them is the stream it was; a value that does not read sets nothing" do
      plain = stroke_path([{0, 0}, {10, 0}], %{})
      assert [{:style, _}, {:path_cubic32, _}, :stroke] = Decoder.decode(svg_stream(plain))

      unread = stroke_path([{0, 0}, {10, 0}], %{stroke_dasharray: "four", stroke_linecap: :wide})
      assert svg_stream(unread) == svg_stream(plain)

      # A group's attributes are not read here, so they make no version 3 stream.
      group =
        Visualize.SVG.Element.g(%{"stroke-dasharray": "4 2"})
        |> Map.put(:children, [Visualize.SVG.Element.from_ir(plain)])

      refute Enum.any?(
               Decoder.decode(CanvasBinary.encode_element!(group)),
               &match?({:version, _}, &1)
             )
    end

    test "the dash ends with its element" do
      root =
        Element.root(20, 20,
          children: [
            stroke_path([{0, 0}, {10, 0}], %{stroke_dasharray: "4 2"}),
            stroke_path([{0, 5}, {10, 5}], %{})
          ]
        )

      records = Decoder.decode(svg_stream(root))
      assert [{:version, 3}, :save | _] = records

      assert [:stroke, :restore, {:style, _}, {:path_cubic32, _}, :stroke] =
               Enum.take(records, -5)
    end
  end

  # The context's cap, join and dash at each stroke the stub drew, read from its log: every
  # assignment and `setLineDash` kept, `save` and `restore` scoping them as a browser does.
  defp strokes(tree) do
    {:ok, %{"log" => log}} =
      run("""
      const el = Stub.element(#{js(%{binary: CanvasBinary.to_base64(svg_stream(tree)), width: "240", height: "120"})}, 240, 120);
      Stub.mount(CanvasBinaryChart, el);
      Stub.done({});
      """)

    initial = %{cap: "butt", join: "miter", dash: []}

    {_state, _stack, strokes} =
      Enum.reduce(log, {initial, [], []}, fn
        %{"kind" => "set", "name" => "lineCap", "value" => v}, {st, stack, out} ->
          {%{st | cap: v}, stack, out}

        %{"kind" => "set", "name" => "lineJoin", "value" => v}, {st, stack, out} ->
          {%{st | join: v}, stack, out}

        %{"kind" => "call", "name" => "setLineDash", "args" => [d]}, {st, stack, out} ->
          {%{st | dash: d}, stack, out}

        %{"kind" => "call", "name" => "save"}, {st, stack, out} ->
          {st, [st | stack], out}

        %{"kind" => "call", "name" => "restore"}, {_st, [back | stack], out} ->
          {back, stack, out}

        %{"kind" => "call", "name" => "stroke"}, {st, stack, out} ->
          {st, stack, out ++ [st]}

        _other, acc ->
          acc
      end)

    strokes
  end

  describe "an SVG element's dashed, capped and joined stroke on the binary canvas is the SVG's (#693)" do
    # Both node and resvg (test_helper, #652).
    @describetag :js_resvg

    defp png(tree) do
      {:ok, png, _warnings} =
        Visualize.Render.to_png(Element.root(240, 120, children: [tree]),
          scale: 1,
          background: "#ffffff"
        )

      Visualize.PNGPixels.decode(png)
    end

    defp inked?(image, px, py) do
      {r, g, b, _a} = Visualize.PNGPixels.pixel(image, px, py)

      cond do
        abs(r - 31) <= 40 and abs(g - 119) <= 40 and abs(b - 180) <= 40 -> true
        r >= 235 and g >= 235 and b >= 235 -> false
        true -> flunk("at #{px},#{py}: #{inspect({r, g, b})} is neither ink nor page")
      end
    end

    test "a dash and its caps ink the pixels the binary hook's dash and cap say" do
      # A line from x 20 to 220 at y 60, 8 wide, dashed 20 on and 10 off.
      for cap <- [:butt, :square] do
        line =
          stroke_path([{20, 60}, {220, 60}], %{stroke_dasharray: "20 10", stroke_linecap: cap})

        [%{cap: drawn_cap, dash: [on, off]}] = strokes(line)
        assert drawn_cap == Atom.to_string(cap)
        ext = if drawn_cap == "square", do: 4, else: 0
        png = png(line)

        # The dashes' spans along the line, each widened by the cap.
        spans =
          for k <- 0..7, a = 20 + k * (on + off), a < 220, do: {a - ext, min(a + on, 220) + ext}

        for px <- 18..222, py <- [58, 61] do
          x = px + 0.5
          distance = spans |> Enum.map(fn {a, b} -> max(max(a - x, x - b), 0) end) |> Enum.min()
          expected = distance == 0

          # A pixel within a pixel and a half of a span's end is the anti-aliased edge.
          edge? = Enum.any?(spans, fn {a, b} -> abs(x - a) < 1.5 or abs(x - b) < 1.5 end)
          unless edge?, do: assert(inked?(png, px, py) == expected, "#{cap} at #{px},#{py}")
        end
      end
    end

    test "a join inks the corner the binary hook's join says" do
      # A right angle at (200, 30), 16 wide: the pixel at (206, 24) is inside the miter's
      # square corner, beyond the bevel's cut and outside the round join.
      for join <- [:miter, :bevel, :round] do
        corner =
          stroke_path([{40, 30}, {200, 30}, {200, 100}], %{
            stroke_width: 16,
            stroke_linejoin: join
          })

        [%{join: drawn_join}] = strokes(corner)
        assert drawn_join == Atom.to_string(join)
        assert inked?(png(corner), 206, 24) == (drawn_join == "miter"), "#{join}"
      end
    end
  end
end
