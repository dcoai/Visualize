defmodule Visualize.Backend.ClipBlendTest do
  @moduledoc """
  A clip and a blend on the binary canvas (spec/09 §4.3.18, §4.3.19, #788, D-208): the
  version 4 records, written only for a tree that clips or blends; the order a clipped
  element's records take, the `:json` commands' order; the keyed segments that carry them;
  the hooks that replay them, from `:json` and from the binary stream alike; and, under
  `:js_resvg`, the binary hook's picture of a stroke inside, outside and doubled and of two
  multiplied fills held to resvg's raster of the SVG.
  """
  use ExUnit.Case, async: true

  import Visualize.JsHooks, only: [run: 1]

  alias Visualize.Backend.{Canvas, CanvasBinary}
  alias Visualize.Backend.CanvasBinary.Decoder
  alias Visualize.CanvasEncoders
  alias Visualize.Chart
  alias Visualize.Chart.Frame
  alias Visualize.IR.{Element, Path}
  alias Visualize.Render.Segments

  @style %{fill: "#336699", stroke: "#cc0000", stroke_width: 6}

  defp square(style \\ @style), do: Element.rect(10, 10, 40, 20, style)

  defp clipped(keep, shape \\ square()), do: Element.clip(square(), shape, keep)

  defp records(element), do: Decoder.decode(CanvasBinary.encode_element!(element))

  describe "the version 4 records (spec/09 §4.3.18, §4.3.19)" do
    test "a stream that neither clips nor blends is what it was, byte for byte" do
      plain = CanvasBinary.encode_element!(square())
      refute Enum.any?(Decoder.decode(plain), &match?({:version, _}, &1))
      assert CanvasBinary.encode_element!(square(Map.put(@style, :blend, :normal))) == plain
    end

    test "a clipped element is its shape's geometry made the clip, around its own records" do
      assert [
               {:version, 4},
               :save,
               {:rects, [{10.0, 10.0, 40.0, 20.0}]},
               {:clip, :inside},
               :save,
               {:style, %{stroke_width: 6.0}},
               {:rects, [{10.0, 10.0, 40.0, 20.0}]},
               :fill,
               :stroke,
               :restore,
               :restore
             ] = records(clipped(:inside))

      assert [{:version, 4}, :save, {:rects, _}, {:clip, :outside} | _] =
               records(clipped(:outside))
    end

    test "every shape spec/02 allows is its geometry, its style and transform left out" do
      styled = %{fill: "#ff0000", stroke: "#00ff00"}
      moved = Visualize.IR.Transform.translate(5, 5)

      shapes = [
        Element.path(Path.new() |> Path.move_to(0, 0) |> Path.line_to(9, 9), styled),
        %{Element.circle(20, 20, 8, styled) | transform: moved},
        Element.ellipse(20, 20, 8, 4, styled),
        Element.polygon([{0, 0}, {9, 0}, {9, 9}], styled)
      ]

      for shape <- shapes do
        assert [{:version, 4}, :save, {geometry, _}, {:clip, :inside}, :save | _] =
                 records(clipped(:inside, shape))

        assert geometry in [:path32, :path_cubic32, :circles]
      end
    end

    test "a clip is in its element's user space: the element's transform first (D-211)" do
      moved = %{square() | transform: Visualize.IR.Transform.translate(50, 40)}
      element = Element.clip(moved, moved, :inside)

      # The shape is geometry alone: clip/3 drops its transform.
      assert element.clip.shape.transform == nil

      assert [
               {:version, 4},
               :save,
               {:transform, :translate, {50.0, 40.0}},
               {:rects, [{10.0, 10.0, 40.0, 20.0}]},
               {:clip, :inside},
               :save,
               {:style, _},
               {:rects, _},
               :fill,
               :stroke,
               :restore,
               :restore
             ] = records(element)

      assert [
               {:save, []},
               {:translate, [50, 40]},
               {:beginPath, []},
               {:rect, _},
               {:clip, []} | rest
             ] =
               Canvas.render_element(element, format: :commands)

      refute Enum.any?(rest, &match?({:translate, _}, &1))

      # SVG resolves the clip under the element's transform, so the shape carries none.
      svg = Visualize.Render.to_string(element)
      assert [_, clip] = Regex.run(~r{<clipPath[^>]*>(.*?)</clipPath>}, svg)
      refute clip =~ "transform"

      assert svg =~
               ~r{<rect clip-path="url\(#vis-clip-[0-9a-z]+\)"[^>]* transform="translate\(50,40\)"}
    end

    test "a blend is a record after its style record; an underscore is the word's hyphen" do
      assert [{:version, 4}, :save, {:style, _}, {:blend, "multiply"} | _] =
               records(square(Map.put(@style, :blend, :multiply)))

      assert [{:version, 4}, :save, {:style, _}, {:blend, "color-dodge"} | _] =
               records(square(Map.put(@style, :blend, :color_dodge)))

      # A group's blend is the state its children draw in.
      group = Element.group([square(%{})], style: %{blend: :screen})
      assert [{:version, 4}, :save, {:style, _}, {:blend, "screen"} | _] = records(group)

      # SVG and the :json canvas write the same word (spec/09 §2.5, §3.3.3).
      dodge = square(Map.put(@style, :blend, :color_dodge))
      assert Visualize.Render.to_string(dodge) =~ ~s(style="mix-blend-mode: color-dodge")

      assert {:set_globalCompositeOperation, ["color-dodge"]} in Canvas.render_element(dodge,
               format: :commands
             )
    end

    test "a version 4 stream may carry the version 3 records" do
      style = Map.merge(@style, %{fill_opacity: 0.4, blend: :multiply})

      assert [{:version, 4}, :save, {:style, _}, {:paint_state, _}, {:blend, "multiply"} | _] =
               records(square(style))
    end

    test "the reference decoder refuses a version, a keep or a mode it does not know" do
      assert_raise ArgumentError, ~r/version 5/, fn -> Decoder.decode(<<0x00, 5>>) end
      assert_raise KeyError, fn -> Decoder.decode(<<0x00, 4, 0x56, 0x03>>) end

      assert_raise ArgumentError, ~r/blend mode 16/, fn ->
        Decoder.decode(<<0x00, 4, 0x57, 16>>)
      end
    end
  end

  describe "the keyed segments carry them (spec/09 §1.4)" do
    test "a clipped element and a clipped group are one segment each; the head is version 4" do
      group =
        Element.clip(Element.group([square(%{})], style: %{fill: "#00ff00"}), square(), :inside)

      tree =
        Element.root(100, 100,
          children: [Element.group([clipped(:outside), group, square(%{blend: :multiply})])]
        )

      {segments, _cache} = Segments.binary(tree, %{})
      assert [{"head", head} | _] = segments
      assert Base.decode64!(head) == <<0x00, 0x04>>

      assert Base.decode64!(Segments.text(segments, :binary)) ==
               CanvasBinary.encode_element!(tree)

      # The group, clipped, is not opened as a group: it is drawn whole, inside its clip.
      refute Enum.any?(segments, fn {key, _} -> key == "r/0/1<" end)
    end
  end

  describe "the hooks draw them from every stream" do
    @describetag :js

    test "CanvasChart from :json and CanvasBinaryChart clip and composite alike" do
      elements = [
        clipped(:inside),
        clipped(:outside),
        Element.group([clipped(:inside, Element.circle(30, 20, 9, %{}))],
          style: %{blend: :multiply}
        ),
        square(Map.put(@style, :blend, :darken))
      ]

      state = fn draws ->
        for draw <- draws, do: {draw["name"], draw["clips"], draw["globalCompositeOperation"]}
      end

      json = CanvasEncoders.draws(Canvas, elements)
      binary = CanvasEncoders.draws(CanvasBinary, elements)
      incremental = CanvasEncoders.draws(Visualize.Backend.CanvasIncremental, elements)
      # The SVG-element encoder reads the clip-path, the mask and the mix-blend-mode the
      # markup carries (spec/09 §4.7, D-211).
      svg_elements = CanvasEncoders.draws(CanvasBinary.SVG, elements)

      assert Enum.map(json, state) == Enum.map(binary, state)
      assert Enum.map(binary, state) == Enum.map(incremental, state)
      assert Enum.map(binary, state) == Enum.map(svg_elements, state)

      assert [
               [{"fill", ["nonzero"], "source-over"}, {"stroke", ["nonzero"], "source-over"}],
               [{"fill", ["evenodd"], "source-over"}, {"stroke", ["evenodd"], "source-over"}],
               [{"fill", ["nonzero"], "multiply"}, {"stroke", ["nonzero"], "multiply"}],
               [{"fill", [], "darken"}, {"stroke", [], "darken"}]
             ] = Enum.map(binary, state)
    end

    test "the clip and the blend are scoped: the next sibling draws unclipped and normal" do
      blended = square(Map.put(@style, :blend, :multiply))
      elements = [Element.group([clipped(:inside), blended, square()])]
      [draws] = CanvasEncoders.draws(CanvasBinary, elements)

      assert [
               {["nonzero"], "source-over"},
               {["nonzero"], "source-over"},
               {[], "multiply"},
               {[], "multiply"},
               {[], "source-over"},
               {[], "source-over"}
             ] = for(d <- draws, do: {d["clips"], d["globalCompositeOperation"]})
    end

    test "the hook refuses a clip keep or a blend mode it does not know" do
      for stream <- [<<0x00, 4, 0x56, 0x03>>, <<0x00, 4, 0x57, 0x20>>, <<0x00, 5>>] do
        data = %{binary: Base.encode64(stream), width: "40", height: "40"}

        {:ok, %{"report" => %{"error" => error}}} =
          run("""
          let error = null;
          try {
            const el = Stub.element(#{Jason.encode!(data)}, 40, 40);
            executeVisualizeBinary(el.querySelector('canvas').getContext('2d'), decodeBase64(#{Jason.encode!(data.binary)}));
          } catch (e) { error = e.message; }
          Stub.done({error});
          """)

        assert error =~ ~r/Unknown canvas binary (clip keep|blend mode|stream version)/
      end
    end
  end

  # -- the picture -------------------------------------------------------------------------

  # Three swatches as the Paints chart draws them (#786) — a translucent fill and a stroke
  # inside, outside and doubled — and two opaque circles multiplied where they overlap.
  defp picture do
    design = %{
      version: 3,
      sources: %{s: %{fields: [:k]}, c: %{fields: [:x, :y, :look]}},
      styles: %{
        "inside" => %{
          fill: "#1f77b440",
          stroke: %{color: "#1f77b4", width: 6, placement: :inside}
        },
        "outside" => %{
          fill: "#1f77b440",
          stroke: %{color: "#1f77b4", width: 6, placement: :outside}
        },
        "double" => %{
          fill: "#1f77b440",
          stroke: %{color: "#1f77b4", width: 9, placement: :double}
        },
        "a" => %{fill: "#ff8800", stroke: :none, blend: :multiply},
        "b" => %{fill: "#00aaff", stroke: :none, blend: :multiply}
      },
      frames: %{
        main: %{
          kind: :cartesian,
          margin: %{top: 0, left: 0, right: 0, bottom: 0},
          scales: %{
            x: %{kind: :band, domain: ~w(inside outside double), padding: 0.3},
            y: %{kind: :linear, domain: [0, 1]}
          }
        }
      },
      marks: [
        %{
          type: :rect,
          data: :s,
          channels: %{x0: :k, x1: :k, y0: 0.15, y1: 0.45},
          style: {:field, :k}
        },
        %{
          type: :circle,
          data: :c,
          channels: %{x: :x, y: :y},
          options: %{radius: 22},
          style: {:field, :look}
        }
      ]
    }

    sources = %{
      s: for(k <- ~w(inside outside double), do: %{k: k}),
      c: [%{x: "outside", y: 0.72, look: "a"}, %{x: "double", y: 0.72, look: "b"}]
    }

    {:ok, chart} = Chart.from_map(design)
    frame = Frame.new(chart, sources: sources, size: {300, 160})
    Element.root(300, 160, children: [Frame.generate(frame, sources: sources, resolve: :literal)])
  end

  describe "a translated clipped element draws (D-211)" do
    @describetag :js_resvg

    # A square at translate(50, 40) clipped to itself: SVG resolves the clip under the
    # transform, so the square draws where it stands; before D-211 the shape carried the
    # transform too, and SVG clipped it twice as far off and drew nothing.
    test "resvg inks its middle, and every canvas clips it where it is drawn" do
      moved = %{square(%{fill: "#336699"}) | transform: Visualize.IR.Transform.translate(50, 40)}
      tree = Element.root(120, 100, children: [Element.clip(moved, moved, :inside)])

      {:ok, png, []} = Visualize.Render.to_png(tree, scale: 1, background: "#ffffff")

      assert {0x33, 0x66, 0x99, _} =
               Visualize.PNGPixels.pixel(Visualize.PNGPixels.decode(png), 80, 60)

      for encoder <- [Canvas, CanvasBinary, CanvasBinary.SVG] do
        assert [[%{"name" => "fill", "m" => m, "clips" => [_]}]] =
                 CanvasEncoders.draws(encoder, [tree])

        assert {m["e"], m["f"]} == {50, 40}, "#{inspect(encoder)} draws the square elsewhere"
      end
    end
  end

  describe "the binary canvas's picture is resvg's raster of the SVG" do
    # Both node and resvg: `--only js` must not select it where resvg is absent (test_helper).
    @describetag :js_resvg

    test "a stroke inside, outside and doubled, and two fills multiplied where they overlap" do
      tree = picture()
      {:ok, png, []} = Visualize.Render.to_png(tree, scale: 1, background: "#ffffff")
      image = Visualize.PNGPixels.decode(png)

      data = %{
        binary: Base.encode64(CanvasBinary.encode_element!(tree)),
        width: "300",
        height: "160"
      }

      {:ok, %{"log" => log}} =
        run("""
        Stub.mount(CanvasBinaryChart, Stub.element(#{Jason.encode!(data)}, 300, 160));
        Stub.done({});
        """)

      paints = replay(log)
      assert Enum.any?(paints, &match?(%{composite: "multiply"}, &1))
      assert Enum.any?(paints, &match?(%{clips: [{_, "evenodd"}]}, &1))

      checked =
        for px <- 2..297//3, py <- 2..157//3, clear?(paints, {px + 0.5, py + 0.5}) do
          expected = shade(paints, {px + 0.5, py + 0.5})
          {r, g, b, _a} = Visualize.PNGPixels.pixel(image, px, py)

          for {got, want} <- Enum.zip([r, g, b], expected) do
            assert abs(got - want) <= 4,
                   "at #{px},#{py}: resvg #{inspect({r, g, b})}, the binary canvas #{inspect(expected)}"
          end
        end

      # Inside the strokes, the clips and the overlap, not only on the page.
      assert length(checked) > 1000
    end
  end

  # The binary hook's draws as the paints they lay: each a shape (a rectangle or a circle,
  # in canvas pixels) filled or stroked at a width, its color and alpha, its compositing
  # and the clips it ran in. The hook draws these charts with translations alone.
  defp replay(log) do
    init = %{m: {0, 0}, path: [], clips: [], props: %{}, stack: [], out: []}

    log
    |> Enum.reduce(init, fn entry, st -> step(entry, st) end)
    |> Map.fetch!(:out)
    |> Enum.reverse()
  end

  defp step(%{"kind" => "set", "name" => name, "value" => value}, st),
    do: %{st | props: Map.put(st.props, name, value)}

  defp step(%{"kind" => "call", "name" => name, "args" => args}, st), do: call(name, args, st)

  defp call("save", _, st), do: %{st | stack: [{st.m, st.clips, st.props} | st.stack]}

  defp call("restore", _, %{stack: [{m, clips, props} | rest]} = st),
    do: %{st | m: m, clips: clips, props: props, stack: rest}

  defp call("translate", [x, y], %{m: {mx, my}} = st), do: %{st | m: {mx + x, my + y}}
  defp call("setTransform", [1, 0, 0, 1, x, y], st), do: %{st | m: {x, y}}
  defp call("clearRect", _, st), do: st
  defp call("beginPath", _, st), do: %{st | path: []}

  defp call("rect", [x, y, w, h], %{m: {mx, my}} = st),
    do: %{st | path: st.path ++ [{:rect, x + mx, y + my, w, h}]}

  defp call("moveTo", _, st), do: st

  defp call("arc", [cx, cy, r, 0, _full], %{m: {mx, my}} = st),
    do: %{st | path: st.path ++ [{:circle, cx + mx, cy + my, r}]}

  defp call("clip", args, st),
    do: %{st | clips: st.clips ++ [{st.path, List.first(args) || "nonzero"}]}

  defp call(op, [], st) when op in ["fill", "stroke"] do
    style = Map.get(st.props, "#{op}Style", "#000000")
    {r, g, b, a} = rgba(style)
    alpha = a * Map.get(st.props, "globalAlpha", 1)

    paint = %{
      op: op,
      path: st.path,
      width: Map.get(st.props, "lineWidth", 1),
      color: [r, g, b],
      alpha: alpha,
      composite: Map.get(st.props, "globalCompositeOperation", "source-over"),
      clips: st.clips
    }

    %{st | out: [paint | st.out]}
  end

  defp rgba(css) do
    {r, g, b, a} = css |> Visualize.Color.parse() |> Visualize.Color.to_rgba()
    {r, g, b, a}
  end

  # The signed distance from a point to a shape's edge, negative inside it.
  defp distance({:rect, x, y, w, h}, {px, py}) do
    {dx, dy} = {max(x - px, px - (x + w)), max(y - py, py - (y + h))}

    if dx <= 0 and dy <= 0,
      do: max(dx, dy),
      else: :math.sqrt(:math.pow(max(dx, 0), 2) + :math.pow(max(dy, 0), 2))
  end

  defp distance({:circle, cx, cy, r}, {px, py}),
    do: :math.sqrt((px - cx) ** 2 + (py - cy) ** 2) - r

  defp inside?(path, point, "nonzero"), do: Enum.any?(path, &(distance(&1, point) < 0))

  defp inside?(path, point, "evenodd"),
    do: rem(Enum.count(path, &(distance(&1, point) < 0)), 2) == 1

  # Where a paint lays its color: inside the shape for a fill, within half the width of its
  # edge for a stroke (a rectangle's mitred corners included), and within every clip.
  defp covers?(%{op: op, path: path, width: width, clips: clips}, point) do
    laid =
      case op do
        "fill" -> inside?(path, point, "nonzero")
        "stroke" -> Enum.any?(path, &(abs(distance(&1, point)) <= width / 2))
      end

    laid and Enum.all?(clips, fn {clip, rule} -> inside?(clip, point, rule) end)
  end

  # A point at least 1.5 px from every edge a paint draws, so antialiasing is not compared.
  defp clear?(paints, point) do
    Enum.all?(paints, fn %{op: op, path: path, width: width, clips: clips} ->
      edges =
        Enum.flat_map(path, fn shape ->
          d = distance(shape, point)
          if op == "stroke", do: [abs(abs(d) - width / 2)], else: [abs(d)]
        end) ++ for({clip, _} <- clips, shape <- clip, do: abs(distance(shape, point)))

      Enum.all?(edges, &(&1 >= 1.5))
    end)
  end

  # The color the paints leave at a point on a white page: each composited in turn, `source-over`
  # or `multiply` (`B(b, s) = b·s`) at its alpha.
  defp shade(paints, point) do
    paints
    |> Enum.filter(&covers?(&1, point))
    |> Enum.reduce([255, 255, 255], fn %{color: color, alpha: a, composite: op}, under ->
      Enum.zip_with(under, color, fn b, s ->
        blended = if op == "multiply", do: b * s / 255, else: s
        (1 - a) * b + a * blended
      end)
    end)
  end
end
