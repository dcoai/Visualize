defmodule Visualize.Backend.CanvasBinarySVGPaintTest do
  @moduledoc """
  The gradients and hatches an SVG element's `url(#…)` fill and stroke name, on the
  SVG-element binary stream (spec/09 §4.7, #837, D-218): resolved into the IR encoder's
  `paint` records, each defined once and referred to by index, every element that draws
  one with its box; a gradient in user units or under a `gradientTransform` mapped into
  box units where the records can say it; the paint's opacities folded into it; and what
  the records cannot say painted as SVG paints an unresolvable reference, the fallback or
  nothing, never black. The hooks then build from it what they build from the IR stream,
  and what resvg rasterizes of the markup.
  """
  use ExUnit.Case, async: true

  import Visualize.JsHooks, only: [run: 1]

  alias Visualize.Backend.CanvasBinary
  alias Visualize.Backend.CanvasBinary.Decoder
  alias Visualize.IR
  alias Visualize.SVG.{Element, Renderer}

  @stops [{0.0, "#d62728", 1}, {0.5, "#ffbf00", 1}, {1.0, "#1f77b4", 1}]

  defp records(tree), do: Decoder.decode(CanvasBinary.encode_element!(tree))
  defp group(attrs, children), do: %{Element.g(attrs) | children: children}
  defp defs(children), do: %{Element.defs() | children: children}

  defp svg(children, {w, h} \\ {240, 110}),
    do: %{Element.svg(%{width: w, height: h, viewBox: "0 0 #{w} #{h}"}) | children: children}

  defp stops(stops \\ @stops) do
    for {at, color, opacity} <- stops,
        do: Element.stop(%{offset: at, "stop-color": color, "stop-opacity": opacity})
  end

  defp linear(id, attrs, stops \\ stops()),
    do: %{Element.linearGradient(Map.put(attrs, :id, id)) | children: stops}

  defp radial(id, attrs, stops \\ stops()),
    do: %{Element.radialGradient(Map.put(attrs, :id, id)) | children: stops}

  defp bar(attrs),
    do: Element.rect(Map.merge(%{x: 20, y: 30, width: 200, height: 50}, attrs))

  # The paint records of a stream, and the records of its one drawing element.
  defp paints(records), do: for({:paint, _, _} = paint <- records, do: paint)

  defp drawn(records),
    do: Enum.reject(records, &(match?({:paint, _, _}, &1) or match?({:version, _}, &1)))

  defp geometry(tree) do
    [{:paint, 0, %{geometry: geometry}}] = paints(records(tree))
    geometry
  end

  defp assert_geometry(got, want) do
    assert length(got) == length(want)
    for {g, w} <- Enum.zip(got, want), do: assert_in_delta(g, w, 1.0e-5)
  end

  # The library's own markup for an IR paint: `from_ir/1` of its definition and a bar.
  defp library(paint, style \\ nil) do
    rect = IR.Element.rect(20, 30, 200, 50, style || %{fill: paint})
    IR.Element.root(240, 110, children: [IR.Element.defs([IR.Paint.definition(paint)]), rect])
  end

  defp ir_paint(type, geometry),
    do: %IR.Paint{id: "#{type}", type: type, geometry: geometry, stops: @stops}

  defp hatch(pattern, background \\ nil) do
    %IR.Paint{
      id: "h",
      type: :hatch,
      geometry: %{pattern: pattern, angle: 30, spacing: 8, width: 3},
      color: "#1f77b4",
      background: background
    }
  end

  describe "the library's paints are the IR encoder's records" do
    test "a linear, a radial and each hatch, defined first and referred to by index" do
      paints = [
        ir_paint(:linear, %{x1: 0.2, y1: 0.9, x2: 0.8, y2: 0.1}),
        ir_paint(:radial, %{cx: 0.3, cy: 0.4, r: 0.6}),
        hatch(:lines),
        hatch(:crosshatch, "#ffffff"),
        hatch(:dots, "#ffeeaa")
      ]

      for paint <- paints do
        ir = library(paint)
        stream = records(Element.from_ir(ir))
        assert [{:version, 2}, {:paint, 0, _} | _] = stream
        assert stream == records(ir)

        assert [
                 :save,
                 {:style, %{fill: nil, fill_paint: 0}},
                 {:rects, _},
                 {:box, {20.0, 30.0, 200.0, 50.0}},
                 :fill,
                 :restore
               ] = drawn(stream)
      end
    end

    test "a fill and a stroke of one paint carry it once; a stroke paint is bit 6" do
      paint = ir_paint(:linear, %{x1: 0, y1: 0, x2: 1, y2: 0})
      ir = library(paint, %{fill: paint, stroke: paint, stroke_width: 2})
      stream = records(Element.from_ir(ir))

      assert [{:paint, 0, _}] = paints(stream)
      assert [:save, {:style, %{fill_paint: 0, stroke_paint: 0}} | _] = drawn(stream)
      assert stream == records(ir)
    end

    test "a stream that paints is version 2, at least; one that does not is as it was" do
      plain = svg([bar(%{fill: "#336699"})])
      assert [:save, {:style, _} | _] = records(plain)

      dashed = svg([defs([linear("g", %{})]), bar(%{fill: "url(#g)", stroke_dasharray: "4 2"})])
      assert [{:version, 3}, {:paint, 0, _} | _] = records(dashed)
    end
  end

  describe "a gradient is mapped into box units where the records can say it" do
    test "user units: the line and the circle in the box's units" do
      tree = fn gradient, box_attrs ->
        svg([defs([gradient]), bar(Map.put(box_attrs, :fill, "url(#g)"))])
      end

      user = %{gradient_units: "userSpaceOnUse", x1: 20, y1: 0, x2: 220, y2: 0}
      assert_geometry(geometry(tree.(linear("g", user), %{})), [0.0, -0.6, 1.0, -0.6])

      square = %{x: 20, y: 30, width: 100, height: 100}
      user_radial = %{gradientUnits: "userSpaceOnUse", cx: 70, cy: 80, r: 25}
      assert_geometry(geometry(tree.(radial("g", user_radial), square)), [0.5, 0.5, 0.25])

      # On a bar that is not square the circle is an ellipse in its units: the fallback.
      assert [] == paints(records(tree.(radial("g", user_radial), %{})))
    end

    test "a gradientTransform: any for a linear gradient, a similarity for a radial one" do
      tree = fn gradient -> svg([defs([gradient]), bar(%{fill: "url(#g)"})]) end

      # Turned a quarter: along y in box units.
      turned = linear("g", %{gradient_transform: "rotate(90)"})
      assert_geometry(geometry(tree.(turned)), [0.0, 0.0, 0.0, 1.0])

      # Skewed: still linear, its line where the parameter is the skewed gradient's.
      skewed = linear("g", %{gradient_transform: "skewX(45)"})
      assert_geometry(geometry(tree.(skewed)), [0.0, 0.0, 0.5, -0.5])

      moved = radial("g", %{gradientTransform: "translate(0.1, 0) scale(0.8)"})
      assert_geometry(geometry(tree.(moved)), [0.5, 0.4, 0.4])

      for t <- ["scale(1, 2)", "skewX(20)"] do
        stretched = radial("g", %{gradient_transform: t})
        assert paints(records(tree.(stretched))) == []
      end
    end

    test "stops: offsets as numbers or percentages, clamped and ordered; colors inline" do
      stops = [
        Element.stop(%{offset: "-10%", style: "stop-color: #ff0000; stop-opacity: 0.5"}),
        Element.stop(%{offset: "60%", stop_color: "#00ff00"}),
        Element.stop(%{offset: 0.4, "stop-color": "blue"}),
        Element.stop(%{offset: "2"})
      ]

      tree = svg([defs([linear("g", %{}, stops)]), bar(%{fill: "url(#g)"})])

      assert [{:paint, 0, %{stops: got}}] = paints(records(tree))

      assert [
               {+0.0, {255, 0, 0, 128}},
               {0.6, {0, 255, 0, 255}},
               {0.6, {0, 0, 255, 255}},
               {1.0, {0, 0, 0, 255}}
             ] = Enum.map(got, fn {at, c} -> {Float.round(at, 5), c} end)
    end
  end

  describe "a paint's opacities and a group's paint" do
    test "fill-opacity and the element's opacity are folded into the stops and the hatch" do
      tree =
        svg([defs([linear("g", %{})]), bar(%{fill: "url(#g)", fill_opacity: 0.5, opacity: 0.5})])

      [{:paint, 0, %{stops: stops}}] = paints(records(tree))
      assert Enum.map(stops, fn {_, {_, _, _, a}} -> a end) == [64, 64, 64]

      hatched = Element.from_ir(library(hatch(:lines, "#ffffff")))
      [definitions, rect] = hatched.children

      faded = %{
        hatched
        | children: [definitions, %{rect | attrs: Map.put(rect.attrs, :opacity, 0.5)}]
      }

      assert [{:paint, 0, %{color: {31, 119, 180, 128}, background: {255, 255, 255, 128}}}] =
               paints(records(faded))
    end

    test "a group's paint is each child's, over its own box; the group writes no field" do
      children = [bar(%{}), Element.rect(%{x: 0, y: 0, width: 10, height: 10})]

      for {gradient, count} <- [
            {linear("g", %{}), 1},
            {linear("g", %{gradient_units: "userSpaceOnUse", x1: 0, y1: 0, x2: 100, y2: 0}), 2}
          ] do
        stream = records(svg([defs([gradient]), group(%{fill: "url(#g)"}, children)]))
        assert length(paints(stream)) == count

        assert [
                 :save,
                 {:style, %{fill_paint: 0}},
                 {:rects, _},
                 {:box, {20.0, 30.0, 200.0, 50.0}},
                 :fill,
                 :restore,
                 :save,
                 {:style, %{fill_paint: last}},
                 {:rects, _},
                 {:box, {+0.0, +0.0, 10.0, 10.0}},
                 :fill,
                 :restore
               ] = drawn(stream)

        assert last == count - 1
      end
    end

    test "a line's fill paint is not drawn, so it is no paint of the stream" do
      line = Element.line(%{x1: 0, y1: 0, x2: 10, y2: 10, fill: "url(#g)", stroke: "#000"})

      assert [:save, {:style, %{fill: nil} = style}, _path, :stroke, :restore] =
               records(svg([defs([linear("g", %{})]), line]))

      refute Map.has_key?(style, :fill_paint)
    end
  end

  describe "what the records cannot say is painted as SVG paints an unresolvable reference" do
    test "the fallback color, or nothing, never black" do
      red = records(svg([bar(%{fill: "url(#missing) #ff0000"})]))
      assert [:save, {:style, %{fill: {255, 0, 0, 255}}}, {:rects, _}, :fill, :restore] = red

      for fill <- ["url(#missing)", "url(#missing) none"] do
        assert [{:rects, _}] = records(svg([bar(%{fill: fill})]))
      end

      # Under a group's color the child's unresolvable paint is its own: no fill.
      inherited = svg([group(%{fill: "#00ff00"}, [bar(%{fill: "url(#missing)"})])])

      assert [:save, {:style, %{fill: {0, 255, 0, 255}}}, {:rects, _}, :restore] =
               records(inherited)
    end

    test "each definition the records cannot hold paints the fallback" do
      cannot = [
        linear("g", %{spread_method: "reflect"}),
        linear("g", %{href: "#other"}),
        linear("g", %{gradient_units: "userSpaceOnUse", x1: "10%"}),
        radial("g", %{fx: 0.2}),
        radial("g", %{fr: 0.1}),
        %{Element.new(:pattern, %{id: "g", width: 8, height: 8}) | children: []},
        %{
          Element.new(:pattern, %{id: "g", pattern_units: "userSpaceOnUse", width: 8, height: 6})
          | children: [Element.circle(%{cx: 4, cy: 4, r: 2, fill: "#000"})]
        },
        Element.rect(%{id: "g"})
      ]

      for definition <- cannot do
        tree = svg([defs([definition]), bar(%{fill: "url(#g) #0000ff"})])

        assert [:save, {:style, %{fill: {0, 0, 255, 255}}}, {:rects, _}, :fill, :restore] =
                 records(tree),
               inspect(definition)
      end
    end

    test "no stop paints nothing; one stop, a line without length or a zero radius one color" do
      tree = fn gradient -> svg([defs([gradient]), bar(%{fill: "url(#g)"})]) end
      assert [{:rects, _}] = records(tree.(linear("g", %{}, [])))

      one = linear("g", %{}, stops([{0.3, "#ff0000", 0.5}]))
      assert [:save, {:style, %{fill: {255, 0, 0, 127}}} | _] = records(tree.(one))

      for gradient <- [linear("g", %{x2: 0}), radial("g", %{r: 0})] do
        assert [:save, {:style, %{fill: {31, 119, 180, 255}}}, {:rects, _}, :fill, :restore] =
                 records(tree.(gradient))
      end
    end
  end

  # -- the hooks -----------------------------------------------------------------------------

  defp mount(binary, {w, h}) do
    data = %{binary: CanvasBinary.to_base64(binary), width: "#{w}", height: "#{h}"}

    {:ok, %{"log" => log}} =
      run("""
      const el = Stub.element(#{Jason.encode!(data)}, #{w}, #{h});
      Stub.mount(CanvasBinaryChart, el);
      Stub.done({});
      """)

    log
  end

  defp built(log) do
    for %{"kind" => "set", "name" => name, "value" => %{} = value} <- log,
        value["gradient"] || value["pattern"] do
      if value["gradient"],
        do: {name, value["gradient"], value["args"], value["stops"]},
        else: {name, :pattern, value["transform"]}
    end
  end

  defp transforms(log),
    do: for(%{"kind" => "call", "name" => "transform", "args" => args} <- log, do: args)

  describe "the hooks build from it what they build from the IR stream" do
    @describetag :js

    test "a linear gradient, a radial one and a hatch, each over its own shape" do
      paints = [
        ir_paint(:linear, %{x1: 0.2, y1: 0.9, x2: 0.8, y2: 0.1}),
        ir_paint(:radial, %{cx: 0.3, cy: 0.4, r: 0.6}),
        hatch(:crosshatch, "#ffffff")
      ]

      shapes = [
        IR.Element.rect(10, 10, 160, 40, %{fill: Enum.at(paints, 0)}),
        IR.Element.circle(200, 60, 30, %{fill: Enum.at(paints, 1), stroke: Enum.at(paints, 0)}),
        IR.Element.rect(10, 60, 100, 40, %{fill: Enum.at(paints, 2)})
      ]

      ir =
        IR.Element.root(240, 110,
          children: [IR.Element.defs(Enum.map(paints, &IR.Paint.definition/1)) | shapes]
        )

      from_ir = mount(CanvasBinary.encode_element!(ir), {240, 110})
      from_svg = mount(CanvasBinary.encode_element!(Element.from_ir(ir)), {240, 110})

      assert [_, _, _, _] = built(from_ir)
      assert built(from_svg) == built(from_ir)
      assert transforms(from_svg) == transforms(from_ir)
    end
  end

  describe "the gradient the hook builds is resvg's raster of the markup" do
    # Both node and resvg (test_helper).
    @describetag :js_resvg

    # A bar of each gradient on a white page: resvg rasterizes the markup, and the
    # gradient the binary hook built from the SVG-element stream is evaluated at pixel
    # centers inside the bar — user units under a skew, a radial one moved and scaled.
    test "user units under a gradientTransform, and a radial gradient under a similarity" do
      gradients = [
        linear("g", %{
          gradient_units: "userSpaceOnUse",
          x1: 20,
          y1: 0,
          x2: 120,
          y2: 0,
          gradient_transform: "skewX(30) translate(10, 0)"
        }),
        radial("g", %{gradient_transform: "translate(0.2, 0.1) rotate(20) scale(0.7)"})
      ]

      for gradient <- gradients do
        tree = svg([defs([gradient]), bar(%{fill: "url(#g)"})])

        {:ok, png, []} =
          Visualize.Render.to_png(Renderer.render_to_string(tree),
            scale: 1,
            background: "#ffffff"
          )

        image = Visualize.PNGPixels.decode(png)
        log = mount(CanvasBinary.encode_element!(tree), {240, 110})
        [{"fillStyle", kind, args, stops}] = built(log)
        matrix = List.first(transforms(log))

        for px <- 23..216//7, py <- 33..76//5 do
          expected = evaluate(kind, args, stops, matrix, {px + 0.5, py + 0.5})
          {r, g, b, _a} = Visualize.PNGPixels.pixel(image, px, py)

          for {got, want} <- Enum.zip([r, g, b], expected) do
            assert abs(got - want) <= 8,
                   "#{gradient.tag} at #{px},#{py}: #{inspect({r, g, b})} vs #{inspect(expected)}"
          end
        end
      end
    end

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
end
