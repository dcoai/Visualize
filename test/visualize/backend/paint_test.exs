defmodule Visualize.Backend.PaintTest do
  @moduledoc """
  Paints on every backend (spec/09 §3.3.3, §4.2–4.4, #652, D-175): the same gradient
  drawn by SVG, by the `:json` and `:js` canvas commands and by the version 2 binary
  stream. The canvas outputs are replayed by the hooks under node and the gradients they
  build are compared with each other; the one the binary hook builds is then evaluated at
  pixel centres and compared with resvg's raster of the SVG, which draws the
  `objectBoundingBox` gradient as a browser does.
  """
  use ExUnit.Case, async: true

  import Visualize.JsHooks, only: [run: 1]

  alias Visualize.Backend.{Canvas, CanvasBinary, CanvasIncremental}
  alias Visualize.Backend.CanvasBinary.Decoder
  alias Visualize.Chart
  alias Visualize.Chart.Frame
  alias Visualize.IR.{Element, Paint, Path}

  @stops [{0.0, "#d62728", 1}, {0.5, "#ffbf00", 1}, {1.0, "#1f77b4", 1}]

  # A linear gradient at 45° — the case SVG skews on a box that is not square — and a
  # radial one off centre.
  defp linear, do: paint("lin", :linear, angle(45))
  defp radial, do: paint("rad", :radial, %{cx: 0.3, cy: 0.4, r: 0.6})

  defp paint(id, type, geometry),
    do: %Paint{id: id, type: type, geometry: geometry, stops: @stops}

  defp angle(deg) do
    a = deg * :math.pi() / 180
    {s, c} = {:math.sin(a) / 2, :math.cos(a) / 2}
    %{x1: 0.5 - s, y1: 0.5 + c, x2: 0.5 + s, y2: 0.5 - c}
  end

  # Three shapes of different boxes: a 4:1 bar, a tall bar and a cubic area.
  defp shapes(fill) do
    style = if fill, do: %{fill: fill}, else: %{}

    area =
      Path.new()
      |> Path.move_to(10, 140)
      |> Path.curve_to(40, 90, 80, 160, 150, 110)
      |> Path.line_to(150, 190)
      |> Path.line_to(10, 190)
      |> Path.close()

    [
      Element.rect(10, 10, 160, 40, style),
      Element.rect(190, 10, 30, 120, style),
      Element.path(area, style)
    ]
  end

  defp js(value), do: Jason.encode!(value)

  # The gradients a hook built, in order: each constructor's arguments, the stops added,
  # and the style it was assigned to, with the transform current for a radial fill.
  defp gradients(log) do
    log
    |> Enum.filter(&(&1["kind"] == "set" and is_map(&1["value"]) and &1["value"]["gradient"]))
    |> Enum.map(fn %{"name" => name, "value" => g} ->
      {name, g["gradient"], g["args"], g["stops"]}
    end)
  end

  defp transforms(log),
    do: for(%{"kind" => "call", "name" => "transform", "args" => args} <- log, do: args)

  defp mount(hook, data) do
    {:ok, %{"log" => log}} =
      run("""
      const el = Stub.element(#{js(Map.merge(data, %{width: "240", height: "200"}))}, 240, 200);
      Stub.mount(#{hook}, el);
      Stub.done({});
      """)

    log
  end

  defp from_json(tree),
    do:
      mount("CanvasChart", %{
        commands: IO.iodata_to_binary(Canvas.render_element(tree, format: :json))
      })

  defp from_js(tree),
    do:
      mount("CanvasChart", %{
        script: IO.iodata_to_binary(Canvas.render_element(tree, format: :js))
      })

  defp from_binary(tree),
    do:
      mount("CanvasBinaryChart", %{
        binary: CanvasBinary.to_base64(CanvasBinary.encode_element!(tree))
      })

  defp assert_same(a, b) do
    assert length(a) == length(b)

    for {{name, kind, args, stops}, {name2, kind2, args2, stops2}} <- Enum.zip(a, b) do
      assert {name, kind} == {name2, kind2}
      # The binary stream carries its geometry and stop offsets as f32.
      for {x, y} <- Enum.zip(args, args2), do: assert_in_delta(x, y, 1.0e-3)
      assert Enum.map(stops, &List.last/1) == Enum.map(stops2, &List.last/1)
      for {[x, _], [y, _]} <- Enum.zip(stops, stops2), do: assert_in_delta(x, y, 1.0e-6)
    end
  end

  describe "the canvas commands (spec/09 §3.3.3)" do
    test "a group's gradient is built over each child's own box, inside a save/restore" do
      commands =
        Canvas.render_element(Element.group(shapes(nil), style: %{fill: linear()}),
          format: :commands
        )

      lines =
        for {:linearGradient, ["fill", x0, y0, x1, y1, _stops]} <- commands, do: {x0, y0, x1, y1}

      assert length(lines) == 3
      assert lines |> Enum.uniq() |> length() == 3

      # Never a state the next sibling inherits: each gradient is saved around.
      assert [{:save, []}, {:linearGradient, _}, {:fill, []}, {:restore, []}] =
               commands |> Enum.drop_while(&(elem(&1, 0) != :rect)) |> Enum.slice(1, 4)

      refute Enum.any?(commands, &match?({:set_fillStyle, _}, &1))
    end

    test "a radial fill is drawn under the box transform; a radial stroke is a circle of the box's area" do
      commands =
        Canvas.render_element(Element.rect(10, 20, 40, 10, %{fill: radial(), stroke: radial()}),
          format: :commands
        )

      assert [
               {:save, []},
               {:transform, [40, 0, 0, 10, 10, 20]},
               {:radialGradient, ["fill", 0.3, 0.4, 0.6, _]},
               {:fill, []},
               {:restore, []},
               {:save, []},
               {:radialGradient, ["stroke", cx, cy, r, _]},
               {:stroke, []},
               {:restore, []}
             ] = Enum.drop(commands, 2)

      assert {cx, cy} == {10 + 0.3 * 40, 20 + 0.4 * 10}
      assert_in_delta r, 0.6 * :math.sqrt(400), 1.0e-9
    end

    test "a box without area draws no paint, as SVG draws none; a text takes the first stop" do
      assert Canvas.render_element(Element.line(0, 5, 10, 5, %{stroke: linear()}),
               format: :commands
             ) ==
               [{:beginPath, []}, {:moveTo, [0, 5]}, {:lineTo, [10, 5]}]

      assert [{:save, []}, {:set_fillStyle, ["#d62728"]}, {:fillText, _}, {:restore, []}] =
               Canvas.render_element(Element.text("a", x: 0, y: 0, style: %{fill: linear()}),
                 format: :commands
               )
    end
  end

  describe "the version 2 binary stream (spec/09 §4.2–4.4)" do
    test "a stream without a paint is version 1, byte for byte" do
      tree = Element.group([Element.rect(0, 0, 10, 10, %{fill: "#336699"})])
      binary = CanvasBinary.encode_element!(tree)
      refute Enum.any?(Decoder.decode(binary), &match?({:version, _}, &1))
      assert <<0x30, 0x30, 0x10, _::binary>> = binary
    end

    test "a paint is defined once, first, and referred to by index; every draw gets its box" do
      bars = for i <- 0..99, do: Element.rect(i * 2, 0, 2, 10 + i, %{fill: linear()})
      records = bars |> Element.group() |> CanvasBinary.encode_element!() |> Decoder.decode()

      assert [{:version, 2}, {:paint, 0, %{type: :linear, geometry: geometry, stops: stops}} | _] =
               records

      assert Enum.count(records, &match?({:paint, _, _}, &1)) == 1
      assert Enum.count(records, &match?({:box, _}, &1)) == 100
      assert Enum.all?(for({:style, s} <- records, do: s.fill_paint), &(&1 == 0))

      g = linear().geometry

      for {a, b} <- Enum.zip(geometry, [g.x1, g.y1, g.x2, g.y2]),
          do: assert_in_delta(a, b, 1.0e-6)

      assert Enum.map(stops, &elem(&1, 1)) == [
               {214, 39, 40, 255},
               {255, 191, 0, 255},
               {31, 119, 180, 255}
             ]
    end

    test "two paints, a stroke paint, and each stream of a scene or a region carries its own" do
      tree = Element.rect(0, 0, 10, 10, %{fill: linear(), stroke: radial()})
      records = tree |> CanvasBinary.encode_element!() |> Decoder.decode()

      assert [{:version, 2}, {:paint, 0, %{type: :linear}}, {:paint, 1, %{type: :radial}} | _] =
               records

      assert [%{fill_paint: 0, stroke_paint: 1}] = for({:style, s} <- records, do: s)

      scene = Canvas.render_scene([tree, tree], format: :binary) |> Decoder.decode()
      assert Enum.count(scene, &match?({:version, 2}, &1)) == 2

      [region] = CanvasIncremental.exposed_regions({20, 0}, {100, 100})

      {:incremental, _, _, _, _, [{_bounds, data}]} =
        CanvasIncremental.encode_incremental({20, 0}, {100, 100}, [{region, tree}])
        |> Decoder.decode()
        |> hd()

      assert [{:version, 2}, {:paint, 0, _} | _] = data
    end

    test "a version the decoder does not know is refused" do
      assert_raise ArgumentError, ~r/version 3/, fn -> Decoder.decode(<<0x00, 3>>) end
    end
  end

  describe "the hooks build the same gradient from every stream" do
    @describetag :js

    test "CanvasChart from :json and from :js, and CanvasBinaryChart, over a group's children" do
      for fill <- [linear(), radial()] do
        tree = Element.group(shapes(nil), style: %{fill: fill})
        json = from_json(tree)
        script = from_js(tree)
        binary = from_binary(tree)

        assert [_, _, _] = gradients(json)
        assert_same(gradients(json), gradients(script))
        assert_same(gradients(json), gradients(binary))
        assert Enum.all?(gradients(json), &(elem(&1, 0) == "fillStyle"))
        assert transforms(json) == transforms(script)

        for {a, b} <- Enum.zip(List.flatten(transforms(json)), List.flatten(transforms(binary))),
            do: assert_in_delta(a, b, 1.0e-3)
      end
    end

    test "a design's gradient reaches the binary canvas as the SVG declares it" do
      design = %{
        version: 3,
        sources: %{s: %{fields: [:k, :v]}},
        defs: %{fade: %{type: :radial, color: ["#d62728", "#1f77b4"], center: [0.3, 0.4]}},
        frames: %{
          main: %{
            kind: :cartesian,
            scales: %{x: %{kind: :band, domain: [:a, :b]}, y: %{kind: :linear, domain: [0, 10]}}
          }
        },
        marks: [
          %{
            type: :rect,
            data: :s,
            channels: %{x0: :k, x1: :k, y0: 0, y1: :v},
            style: %{fill: {:paint, :fade}}
          }
        ]
      }

      rows = [%{k: :a, v: 4}, %{k: :b, v: 9}]
      {:ok, chart} = Chart.from_map(design)
      frame = Frame.new(chart, sources: %{s: rows}, size: {240, 200})
      tree = Frame.generate(frame, sources: %{s: rows}, resolve: :literal)

      svg = Visualize.Render.to_string(tree)
      assert svg =~ ~r/<radialGradient[^>]*cx="0.3"/
      assert [_, _] = gradients(from_binary(tree))
      assert_same(gradients(from_json(tree)), gradients(from_binary(tree)))
    end
  end

  describe "the canvas gradient is the SVG gradient, pixel for pixel" do
    # Both node and resvg: `--only js` must not select it where resvg is absent (test_helper).
    @describetag :js_resvg

    # One 4:1 bar of each paint on a white page: resvg rasterises the SVG, and the gradient
    # the binary hook built is evaluated at each pixel's centre inside the bar.
    test "a skewed linear gradient and an elliptical radial one" do
      for fill <- [linear(), radial()] do
        box = {20, 30, 200, 50}
        {x, y, w, h} = box
        rect = Element.rect(x, y, w, h, %{fill: fill})
        root = Element.root(240, 110, children: [Element.defs([Paint.definition(fill)]), rect])
        {:ok, png, []} = Visualize.Render.to_png(root, scale: 1, background: "#ffffff")

        [{"fillStyle", kind, args, stops}] = gradients(from_binary(rect))
        matrix = List.first(transforms(from_binary(rect)))

        for px <- (x + 3)..(x + w - 4)//7, py <- (y + 3)..(y + h - 4)//5 do
          {cx, cy} = {px + 0.5, py + 0.5}
          expected = evaluate(kind, args, stops, matrix, {cx, cy})
          {r, g, b, _a} = Visualize.PNGPixels.pixel(png, px, py)

          for {got, want} <- Enum.zip([r, g, b], expected) do
            assert abs(got - want) <= 8,
                   "#{fill.type} at #{px},#{py}: #{inspect({r, g, b})} vs #{inspect(expected)}"
          end
        end
      end
    end

    # The colour of a canvas gradient at a user point: its parameter `t` clamped to 0..1 and
    # the stops interpolated in sRGB (every stop opaque, so premultiplication is moot).
    defp evaluate("createLinearGradient", [x0, y0, x1, y1], stops, nil, {px, py}) do
      {ex, ey} = {x1 - x0, y1 - y0}
      at(stops, ((px - x0) * ex + (py - y0) * ey) / (ex * ex + ey * ey))
    end

    defp evaluate(
           "createRadialGradient",
           [cx, cy, 0, cx, cy, r],
           stops,
           [a, 0, 0, d, e, f],
           {px, py}
         ) do
      {u, v} = {(px - e) / a, (py - f) / d}
      at(stops, :math.sqrt((u - cx) * (u - cx) + (v - cy) * (v - cy)) / r)
    end

    defp at(stops, t) do
      t = t |> max(0.0) |> min(1.0)
      stops = Enum.map(stops, fn [o, c] -> {o, rgb(c)} end)
      {o0, c0} = stops |> Enum.filter(fn {o, _} -> o <= t end) |> List.last()
      {o1, c1} = Enum.find(stops, fn {o, _} -> o >= t end)
      k = if o1 == o0, do: 0.0, else: (t - o0) / (o1 - o0)
      Enum.zip_with(c0, c1, fn a, b -> a + (b - a) * k end)
    end

    defp rgb(css) do
      [r, g, b | _] =
        Regex.run(~r/rgba\(([\d.]+),([\d.]+),([\d.]+)/, css, capture: :all_but_first)

      Enum.map([r, g, b], &String.to_integer/1)
    end
  end

  # -- the hatch (#673) ------------------------------------------------------------------

  defp hatch(pattern, background \\ nil) do
    %Paint{
      id: "hatch",
      type: :hatch,
      geometry: %{pattern: pattern, angle: 30, spacing: 8, width: 3},
      color: "#1f77b4",
      background: background
    }
  end

  # The patterns a hook made: the style each was assigned to, its transform, and the size of
  # its tile canvas.
  defp patterns(log) do
    for %{"kind" => "set", "name" => name, "value" => %{"pattern" => tile} = p} <- log do
      size = for %{"on" => ^tile, "kind" => "set", "name" => "width", "value" => n} <- log, do: n
      {name, p["transform"], List.last(size)}
    end
  end

  describe "a hatch (spec/14 §3.1, spec/09 §3.3.3, #673)" do
    test "SVG declares a <pattern> once per hatch, keyed by what it draws" do
      definition = Paint.definition(hatch(:crosshatch, "#ffffff"))
      assert definition.type == :pattern

      assert %{
               pattern_units: "userSpaceOnUse",
               width: 8,
               height: 8,
               pattern_transform: "rotate(30)"
             } =
               definition.attrs

      assert [:rect, :line, :line] = Enum.map(definition.children, & &1.type)
      assert [:circle] = Enum.map(Paint.definition(hatch(:dots)).children, & &1.type)

      design = fn fills ->
        %{
          version: 3,
          sources: %{s: %{fields: [:k, :v]}},
          frames: %{
            main: %{
              kind: :cartesian,
              scales: %{x: %{kind: :band, domain: [:a, :b]}, y: %{kind: :linear, domain: [0, 10]}}
            }
          },
          marks:
            for fill <- fills do
              %{
                type: :rect,
                data: :s,
                channels: %{x0: :k, x1: :k, y0: 0, y1: :v},
                style: %{fill: fill}
              }
            end
        }
      end

      rows = [%{k: :a, v: 4}, %{k: :b, v: 9}]
      lines = %{type: :hatch, color: "#c00", spacing: 5}

      patterns = fn fills ->
        {:ok, chart} = Chart.from_map(design.(fills))
        frame = Frame.new(chart, sources: %{s: rows}, size: {240, 200})

        svg =
          frame
          |> Frame.generate(sources: %{s: rows}, resolve: :literal)
          |> Visualize.Render.to_string()

        Regex.scan(~r/<pattern /, svg) |> length()
      end

      assert patterns.([lines, lines]) == 1
      assert patterns.([lines, %{lines | spacing: 6}]) == 2
      # A hatch's spacing in a unit is resolved on the server: pt(6) is 8 user units.
      {:ok, chart} = Chart.from_map(design.([%{lines | spacing: {6, :pt}}]))
      frame = Frame.new(chart, sources: %{s: rows}, size: {240, 200})
      svg = frame |> Frame.generate(sources: %{s: rows}) |> Visualize.Render.to_string()
      assert svg =~ ~r/<pattern height="8.0"[^>]* width="8.0"/
    end

    test "the print theme's hatched roles are declared only where a chart draws one" do
      design = fn style ->
        %{
          version: 3,
          theme: :print,
          sources: %{s: %{fields: [:k, :v]}},
          frames: %{
            main: %{
              kind: :cartesian,
              scales: %{x: %{kind: :band, domain: [:a]}, y: %{kind: :linear, domain: [0, 10]}}
            }
          },
          marks: [
            %{type: :rect, data: :s, channels: %{x0: :k, x1: :k, y0: 0, y1: :v}, style: style}
          ]
        }
      end

      rows = [%{k: :a, v: 4}]

      svg = fn style ->
        {:ok, chart} = Chart.from_map(design.(style))
        frame = Frame.new(chart, sources: %{s: rows}, size: {240, 200})
        frame |> Frame.generate(sources: %{s: rows}) |> Visualize.Render.to_string()
      end

      refute svg.(:style_1) =~ "<pattern"
      assert [_] = Regex.scan(~r/<pattern /, svg.(:bad))
    end

    test "the canvas commands draw it whatever the box; the binary stream round-trips it" do
      assert [
               {:save, []},
               {:hatchPattern, ["fill", "crosshatch", 30, 8, 3, "rgba(31,119,180,1)", nil]},
               {:fill, []},
               {:restore, []}
             ] =
               Canvas.render_element(Element.rect(0, 0, 40, 0, %{fill: hatch(:crosshatch)}),
                 format: :commands
               )
               |> Enum.drop(2)

      records =
        Element.rect(0, 0, 40, 20, %{fill: hatch(:dots, "#ffffff")})
        |> CanvasBinary.encode_element!()
        |> Decoder.decode()

      assert [
               {:version, 2},
               {:paint, 0,
                %{
                  type: :hatch,
                  pattern: :dots,
                  geometry: [angle, 8.0, 3.0],
                  color: {31, 119, 180, 255},
                  background: {255, 255, 255, 255}
                }}
               | _
             ] = records

      assert_in_delta angle, 30, 1.0e-5
    end

    @tag :js
    test "the hooks make the same pattern from :json, :js and the binary stream" do
      tree = Element.group(shapes(hatch(:crosshatch, "#ffffff")))
      [first | _] = json = patterns(from_json(tree))
      assert length(json) == 3
      assert json == patterns(from_js(tree))

      for {{name, t, n}, {name2, t2, n2}} <- Enum.zip(json, patterns(from_binary(tree))) do
        assert {name, n} == {name2, n2}
        for k <- ~w(a b c d e f), do: assert_in_delta(t[k], t2[k], 1.0e-5)
      end

      # One period of user units per tile, turned by the angle: n = ⌈4·8⌉ pixels.
      {"fillStyle", t, 32} = first
      assert_in_delta :math.atan2(t["b"], t["a"]) * 180 / :math.pi(), 30, 1.0e-9
      assert_in_delta :math.sqrt(t["a"] * t["a"] + t["b"] * t["b"]) * 32, 8, 1.0e-9
    end

    # Both node and resvg (test_helper, #652).
    @tag :js_resvg
    test "the canvas pattern is the SVG pattern, pixel for pixel" do
      for pattern <- [:lines, :crosshatch] do
        fill = hatch(pattern, "#ffffff")
        rect = Element.rect(10, 10, 200, 80, %{fill: fill})
        root = Element.root(220, 100, children: [Element.defs([Paint.definition(fill)]), rect])
        {:ok, png, []} = Visualize.Render.to_png(root, scale: 1, background: "#ffffff")
        [{"fillStyle", t, n}] = patterns(from_binary(rect))
        {a, s} = {:math.atan2(t["b"], t["a"]), :math.sqrt(t["a"] ** 2 + t["b"] ** 2) * n}

        for px <- 12..207//3, py <- 12..87//3 do
          {x, y} = {px + 0.5, py + 0.5}
          # The point in the tile's frame: turned back by the angle, then within one period.
          {u, v} = {x * :math.cos(a) + y * :math.sin(a), -x * :math.sin(a) + y * :math.cos(a)}
          d = fn c -> abs(c - s * Float.floor(c / s) - s / 2) end
          distance = if pattern == :crosshatch, do: min(d.(v), d.(u)), else: d.(v)
          {r, g, b, _} = Visualize.PNGPixels.pixel(png, px, py)

          cond do
            distance < 3 / 2 - 0.9 -> assert_close({r, g, b}, {31, 119, 180}, {px, py})
            distance > 3 / 2 + 0.9 -> assert_close({r, g, b}, {255, 255, 255}, {px, py})
            true -> :edge
          end
        end
      end
    end

    defp assert_close(got, want, at) do
      for {g, w} <- Enum.zip(Tuple.to_list(got), Tuple.to_list(want)),
          do: assert(abs(g - w) <= 24, "#{inspect(at)}: #{inspect(got)} vs #{inspect(want)}")
    end
  end

  # -- the shadow's offset and colour (#674) ---------------------------------------------

  describe "a shadow's offset and color (spec/14 §3.1, §2.7, spec/09 §3.3.3, §4.3.14, #674)" do
    defp shadow_design(effect) do
      %{
        version: 3,
        sources: %{s: %{fields: [:k, :v]}},
        frames: %{
          main: %{
            kind: :cartesian,
            scales: %{x: %{kind: :band, domain: [:a]}, y: %{kind: :linear, domain: [0, 10]}}
          }
        },
        marks: [
          %{
            type: :rect,
            data: :s,
            channels: %{x0: :k, x1: :k, y0: 0, y1: :v},
            style: %{fill: "#336699", effect: effect}
          }
        ]
      }
    end

    defp shadow_tree(effect, mode) do
      rows = [%{k: :a, v: 4}]
      {:ok, chart} = Chart.from_map(shadow_design(effect))
      frame = Frame.new(chart, sources: %{s: rows}, size: {240, 200})
      Frame.generate(frame, sources: %{s: rows}, resolve: mode)
    end

    test "SVG: a plain shadow keeps its filter; an offset and a colour key a filter of their own" do
      plain = shadow_tree(%{type: :shadow}, :literal) |> Visualize.Render.to_string()
      assert plain =~ ~s(<filter id="vis-effect-shadow-3">)
      assert plain =~ ~s(<feDropShadow dx="1.5" dy="1.5" flood-opacity="0.35" stdDeviation="3"/>)

      moved =
        shadow_tree(%{type: :shadow, offset: [{3, :pt}, -2], color: "#ff000080"}, :literal)
        |> Visualize.Render.to_string()

      [_, id] = Regex.run(~r/<filter id="(vis-effect-shadow-3-[0-9a-z]+)">/, moved)
      assert moved =~ ~s|filter="url(##{id})"|

      assert moved =~
               ~s(<feDropShadow dx="4.0" dy="-2" flood-color="#ff000080" flood-opacity="1" stdDeviation="3"/>)
    end

    test "a pct offset has no box" do
      assert {:error, errors} =
               Visualize.Chart.Validator.validate(
                 shadow_design(%{type: :shadow, offset: [{5, :pct}, 0]})
               )

      assert {[:marks, 0, :style, :effect, :offset], {:no_box, :offset}} in errors
    end

    test "the canvas commands and the binary effect record carry them" do
      style = %{
        fill: "#336699",
        effect: :shadow,
        effect_radius: 4,
        effect_offset: [2, -3],
        effect_color: "#ff0000"
      }

      rect = Element.rect(0, 0, 10, 10, style)

      assert [
               {:save, []},
               {:set_fillStyle, _},
               {:set_shadowColor, ["rgba(255,0,0,1)"]},
               {:set_shadowBlur, [4]},
               {:set_shadowOffsetX, [2]},
               {:set_shadowOffsetY, [-3]} | _
             ] = Canvas.render_element(rect, format: :commands)

      records = rect |> CanvasBinary.encode_element!() |> Decoder.decode()

      assert [
               {:version, 2},
               :save,
               {:style, _},
               {:effect, :shadow, 4.0, {2.0, -3.0}, {255, 0, 0, 255}} | _
             ] = records

      plain = Element.rect(0, 0, 10, 10, %{fill: "#336699", effect: :shadow})

      assert [_, :save, _, {:effect, :shadow, 3.0, {1.5, 1.5}, {0, 0, 0, 89}} | _] =
               plain |> CanvasBinary.encode_element!() |> Decoder.decode()

      blur = Element.rect(0, 0, 10, 10, %{fill: "#336699", effect: :blur, effect_radius: 2})

      assert [_, :save, _, {:effect, :blur, 2.0} | _] =
               blur |> CanvasBinary.encode_element!() |> Decoder.decode()
    end

    @tag :js
    test "the hooks set the same shadow from :json, :js and the binary stream" do
      style = %{
        fill: "#336699",
        effect: :shadow,
        effect_radius: 4,
        effect_offset: [2, -3],
        effect_color: "#ff000080"
      }

      tree = Element.group([Element.rect(0, 0, 10, 10, style)])

      shadow = fn log ->
        # The binary hook writes the alpha byte over 255 unrounded: compare it as a number.
        for %{"kind" => "set", "name" => "shadow" <> _ = name, "value" => v} <- log do
          case Regex.run(~r/^rgba\((\d+,\d+,\d+),([\d.]+)\)$/, to_string(v)) do
            [_, rgb, a] ->
              {name,
               {rgb, Float.round(String.to_float(a <> if(a =~ ".", do: "", else: ".0")), 3)}}

            nil ->
              {name, v}
          end
        end
      end

      json = shadow.(from_json(tree))
      assert json == shadow.(from_js(tree))
      assert json == shadow.(from_binary(tree))
      assert {"shadowColor", {"255,0,0", 0.502}} in json
      assert {"shadowOffsetY", -3} in json
    end
  end
end
