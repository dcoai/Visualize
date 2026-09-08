defmodule Visualize.Chart.MarkTest do
  @moduledoc """
  The marks of spec/14 §5 and D-61: every type is byte for byte the generator it names
  called with the same numbers, channels map through the frame's scales with the band
  edge rule, the paint follows the theme's series and a `series` channel, a `{:field, f}`
  binds per element, the inline label sits at the anchor point, and the frame places the
  marks between the grid and the axes — on SVG and, with literal paints, on a canvas.
  """
  use ExUnit.Case, async: true

  alias Visualize.Backend.SVG
  alias Visualize.{Chart, Render, Scale}
  alias Visualize.Chart.{Frame, Mark}
  alias Visualize.IR.{Element, Path}
  alias Visualize.Shape.{Arc, Area, Band, Line, PercentileBand, Pie, Rose, Rule, Symbol, XBand}

  doctest Mark

  @rows for {v, i} <- Enum.with_index([4, 9, 2, 7]),
            do: %{t: i, v: v, lo: v - 1, hi: v + 1, lo2: v - 2, hi2: v + 2, k: "k#{rem(i, 2)}"}
  @sources %{primary: @rows}

  @frame %{
    kind: :cartesian,
    size: %{width: 300, height: 200},
    margin: %{top: 0, right: 0, bottom: 0, left: 0},
    scales: %{
      x: %{kind: :linear, domain: [0, 3]},
      y: %{kind: :linear, domain: [0, 10]},
      color: %{kind: :ordinal}
    }
  }

  defp chart(mark, extra \\ %{}) do
    Chart.from_map!(
      Map.merge(
        %{
          version: 1,
          sources: %{primary: %{fields: [:t, :v, :lo, :hi, :lo2, :hi2, :k]}},
          frame: @frame,
          marks: [Map.merge(%{data: :primary}, mark)]
        },
        extra
      )
    )
  end

  defp generate(mark, extra \\ %{}, opts \\ []) do
    chart = chart(mark, extra)
    frame = Frame.new(chart, sources: @sources)
    Mark.generate(frame, hd(chart.marks), Keyword.put_new(opts, :sources, @sources))
  end

  defp x, do: Scale.linear() |> Scale.domain([0, 3]) |> Scale.range([0, 300])
  defp y, do: Scale.linear() |> Scale.domain([0, 10]) |> Scale.range([200, 0])
  defp px(field), do: fn d -> Scale.apply(x(), d[field]) end
  defp py(field), do: fn d -> Scale.apply(y(), d[field]) end
  defp d(%Element{path: path}), do: SVG.path_data(path)

  describe "byte identity with the generators" do
    test ":line is Shape.Line through the scales, in the style's curve" do
      group =
        generate(%{type: :line, channels: %{x: :t, y: :v}, style: :s}, %{
          styles: %{s: %{curve: :step_after}}
        })

      [path] = group.children

      assert d(path) ==
               Line.new()
               |> Line.x(px(:t))
               |> Line.y(py(:v))
               |> Line.curve(:step_after)
               |> Line.generate(@rows)

      assert group.style.class == "mark mark-line"
    end

    test ":area is Shape.Area with the baseline at the y scale's zero" do
      [path] = generate(%{type: :area, channels: %{x: :t, y: :v}}).children

      assert d(path) ==
               Area.new()
               |> Area.x(px(:t))
               |> Area.y0(200)
               |> Area.y1(py(:v))
               |> Area.generate(@rows)

      [path] = generate(%{type: :area, channels: %{x: :t, y: :v, y0: :lo}}).children

      assert d(path) ==
               Area.new()
               |> Area.x(px(:t))
               |> Area.y0(py(:lo))
               |> Area.y1(py(:v))
               |> Area.generate(@rows)
    end

    test ":band is Shape.Band with the height option" do
      rects =
        generate(%{type: :band, channels: %{x0: :t, x1: :hi, y: :v}, options: %{height: 12}}).children

      expected =
        Band.new()
        |> Band.x0(px(:t))
        |> Band.x1(px(:hi))
        |> Band.y(py(:v))
        |> Band.height(12)
        |> Band.generate(@rows)

      assert Enum.map(rects, & &1.attrs) == Enum.map(expected, & &1.attrs)
    end

    test ":rule is Shape.Rule over the plot height with the generator's own label" do
      group = generate(%{type: :rule, channels: %{x: :t}, label: %{text: ["at ", {:field, :t}]}})

      expected =
        Rule.new()
        |> Rule.x(:t)
        |> Rule.scale(x())
        |> Rule.y0(0)
        |> Rule.y1(200)
        |> Rule.label(fn d -> "at #{d.t}" end)
        |> Rule.generate(@rows)

      assert length(group.children) == 4

      for {got, want} <- Enum.zip(group.children, expected) do
        [line, text] = got.children
        [want_line, want_text] = want.children
        assert line.attrs == want_line.attrs
        assert {text.attrs, text.content} == {want_text.attrs, want_text.content}
        assert line.style.stroke == "var(--vis-series-1, #3b6fa8)"
        assert text.style.fill == "var(--vis-text, #333333)"
      end
    end

    test ":x_band is Shape.XBand filled in the mark's paint" do
      [group | _] = generate(%{type: :x_band, channels: %{x0: :t, x1: :hi}}).children

      [want | _] =
        XBand.new()
        |> XBand.x0(:t)
        |> XBand.x1(:hi)
        |> XBand.scale(x())
        |> XBand.y1(200)
        |> XBand.generate(@rows)

      [rect] = group.children
      [want_rect] = want.children
      assert rect.attrs == want_rect.attrs
      assert rect.style.fill == "var(--vis-series-1, #3b6fa8)"
    end

    test ":percentile_band is Shape.PercentileBand: outer, inner, median" do
      channels = %{
        x: :t,
        median: :v,
        inner_lo: :lo,
        inner_hi: :hi,
        outer_lo: :lo2,
        outer_hi: :hi2
      }

      [outer, inner, median] = generate(%{type: :percentile_band, channels: channels}).children

      expected =
        PercentileBand.new()
        |> PercentileBand.x(px(:t))
        |> PercentileBand.median(py(:v))
        |> PercentileBand.inner({py(:lo), py(:hi)})
        |> PercentileBand.outer({py(:lo2), py(:hi2)})
        |> PercentileBand.generate(@rows)

      assert {d(outer), d(inner), d(median)} == {expected.outer, expected.inner, expected.median}

      assert outer.style == %{
               class: "outer",
               fill: "var(--vis-series-1, #3b6fa8)",
               fill_opacity: 0.2,
               stroke: :none
             }

      assert median.style == %{
               class: "median",
               fill: :none,
               stroke: "var(--vis-series-1, #3b6fa8)"
             }

      [median] = generate(%{type: :percentile_band, channels: %{x: :t, median: :v}}).children
      assert median.style.class == "median"
    end

    test ":rose is Shape.Rose over the polar frame's angle scale, about the centre" do
      polar = %{
        kind: :polar,
        size: %{width: 200, height: 200},
        margin: %{top: 0, right: 0, bottom: 0, left: 0},
        scales: %{angle: %{kind: :radial, domain: [0, 4]}, r: %{kind: :linear, domain: [0, 10]}}
      }

      mark = %{
        type: :rose,
        channels: %{angle: :t, value: :v},
        options: %{width: 1, pad_angle: 0.05}
      }

      group = generate(mark, %{frame: polar})
      angle = Scale.radial() |> Scale.domain([0, 4]) |> Scale.range([0, 2 * :math.pi()])
      r = Scale.linear() |> Scale.domain([0, 10]) |> Scale.range([0, 100])

      expected =
        Rose.new()
        |> Rose.scale(angle)
        |> Rose.angle(:t)
        |> Rose.width(1)
        |> Rose.outer_radius(fn d -> Scale.apply(r, d.v) end)
        |> Rose.pad_angle(0.05)
        |> Rose.generate(@rows)

      assert Enum.map(group.children, &d/1) == expected
      assert group.transform == nil
    end

    test ":symbol is Shape.Symbol in the style's symbol and size, translated to the datum" do
      style = %{symbol: :star, symbol_size: 30}

      paths =
        generate(%{type: :symbol, channels: %{x: :t, y: :v}, style: :s}, %{styles: %{s: style}}).children

      star = Symbol.new() |> Symbol.type(:star) |> Symbol.size(30) |> Symbol.generate()
      assert Enum.map(paths, &d/1) == List.duplicate(star, 4)
      assert hd(paths).transform == Visualize.IR.Transform.translate(0.0, 120.0)

      [path | _] = generate(%{type: :symbol, channels: %{x: :t, y: :v, value: :v}}).children
      assert d(path) == Symbol.new() |> Symbol.size(4) |> Symbol.generate()
    end

    test ":arc is Shape.Pie over the values then Shape.Arc, about the plot centre" do
      mark = %{type: :arc, channels: %{value: :v}, options: %{inner_radius: 20, pad_angle: 0.1}}
      group = generate(mark)
      arcs = Pie.new() |> Pie.value(& &1.v) |> Pie.pad_angle(0.1) |> Pie.generate(@rows)
      generator = Arc.new() |> Arc.inner_radius(20) |> Arc.outer_radius(100)
      assert Enum.map(group.children, &d/1) == Enum.map(arcs, &Arc.generate(generator, &1))
      assert group.transform == Visualize.IR.Transform.translate(150.0, 100.0)
    end

    test ":path draws each row's IR.Path as it is and refuses anything else" do
      path = Path.new() |> Path.move_to(1, 2) |> Path.line_to(3, 4)
      sources = %{primary: [%{p: path}]}

      chart =
        chart(%{type: :path, channels: %{path: :p}}, %{sources: %{primary: %{fields: [:p]}}})

      frame = Frame.new(chart, sources: sources)
      [element] = Mark.generate(frame, hd(chart.marks), sources: sources).children
      assert element.path == path

      assert_raise ArgumentError, ~r/draws a Visualize.IR.Path per row/, fn ->
        Mark.generate(frame, hd(chart.marks), sources: %{primary: [%{p: "M0,0"}]})
      end
    end

    test ":arc with start and end is Shape.Arc over each datum's own angles, no pie (D-69)" do
      pi = :math.pi()

      rows =
        for {a0, a1, r} <- [{0, pi / 2, 40}, {pi / 2, pi, 60}, {pi, 2 * pi, 100}],
            do: %{a0: a0, a1: a1, r: r}

      sources = %{primary: rows}

      mark = %{
        type: :arc,
        channels: %{start: :a0, end: :a1, outer: :r},
        options: %{inner_radius: 20, pad_angle: 0.1, corner_radius: 3, start_angle: 1},
        label: %{text: ["r=", {:field, :r}], anchor: :middle}
      }

      chart = chart(mark, %{sources: %{primary: %{fields: [:a0, :a1, :r]}}})
      frame = Frame.new(chart, sources: sources)
      group = Mark.generate(frame, hd(chart.marks), sources: sources)
      {paths, texts} = Enum.split_with(group.children, &(&1.type == :path))

      expected =
        for row <- rows do
          Arc.new()
          |> Arc.inner_radius(20)
          |> Arc.outer_radius(row.r)
          |> Arc.start_angle(row.a0)
          |> Arc.end_angle(row.a1)
          |> Arc.pad_angle(0.1)
          |> Arc.corner_radius(3)
        end

      assert Enum.map(paths, &d/1) == Enum.map(expected, &Arc.generate(&1, %{}))

      assert Enum.map(texts, &{&1.attrs.x, &1.attrs.y}) ==
               Enum.map(expected, &Arc.centroid(&1, %{}))

      assert Enum.map(texts, & &1.content) == ["r=40", "r=60", "r=100"]
      assert group.transform == Visualize.IR.Transform.translate(150.0, 100.0)

      # A datum without both angles is dropped; the pie's angle options are not read.
      more = %{primary: rows ++ [%{a0: 0, a1: nil, r: 10}]}
      assert length(Mark.generate(frame, hd(chart.marks), sources: more).children) == 6
    end

    test ":rect and :circle are one element per datum in pixels" do
      [rect | _] =
        generate(%{
          type: :rect,
          channels: %{x0: :t, x1: :hi, y0: 0, y1: :v},
          options: %{corner_radius: 2}
        }).children

      assert rect.attrs == %{x: 0.0, y: 120.0, width: 500.0, height: 80.0, rx: 2, ry: 2}

      [circle | _] = generate(%{type: :circle, channels: %{x: :t, y: :v, value: :v}}).children
      assert circle.attrs == %{cx: 0.0, cy: 120.0, r: 4}

      [circle | _] =
        generate(%{type: :circle, channels: %{x: :t, y: :v}, options: %{radius: 7}}).children

      assert circle.attrs.r == 7
    end
  end

  describe "channels" do
    test "a band scale gives edges its start and end and a position its centre" do
      band = %{x: %{kind: :band, domain: ["k0", "k1"]}, y: %{kind: :linear, domain: [0, 10]}}
      frame = Map.put(@frame, :scales, band)

      [rect | _] =
        generate(%{type: :rect, channels: %{x0: :k, x1: :k, y0: 0, y1: :v}}, %{frame: frame}).children

      assert rect.attrs.x == 0 and rect.attrs.width == 150.0

      [point | _] =
        generate(%{type: :symbol, channels: %{x: :k, y: :v}}, %{frame: frame}).children

      assert point.transform == Visualize.IR.Transform.translate(75.0, 120.0)
    end

    test "a datum a scale cannot place is dropped from a per-datum mark and breaks a path" do
      band = %{x: %{kind: :band, domain: ["k0"]}, y: %{kind: :linear, domain: [0, 10]}}
      frame = Map.put(@frame, :scales, band)

      assert length(
               generate(%{type: :symbol, channels: %{x: :k, y: :v}}, %{frame: frame}).children
             ) == 2

      rows = [%{t: 0, v: 1}, %{t: 1, v: nil}, %{t: 2, v: 3}, %{t: 3, v: 4}]
      sources = %{primary: rows}
      chart = chart(%{type: :line, channels: %{x: :t, y: :v}})
      frame = Frame.new(chart, sources: sources)
      [path] = Mark.generate(frame, hd(chart.marks), sources: sources).children
      assert d(path) == "M200,140L300,120"
    end

    test "a channel naming no declared scale is read as pixels, a constant as itself" do
      chart =
        chart(%{type: :circle, channels: %{x: :t, y: 50}}, %{frame: Map.put(@frame, :scales, %{})})

      frame = Frame.new(chart, sources: @sources)
      [circle | _] = Mark.generate(frame, hd(chart.marks), sources: @sources).children
      assert circle.attrs == %{cx: 0, cy: 50, r: 3}
    end

    test "a mark's scales node places a channel family through the scale it names (D-67)" do
      scales = Map.put(@frame.scales, :count, %{kind: :linear, domain: [0, 10], range: [0, 100]})

      chart =
        chart(
          %{type: :rect, channels: %{x0: 0, x1: :v, y0: :t, y1: :t}, scales: %{x: :count}},
          %{frame: Map.put(@frame, :scales, scales)}
        )

      frame = Frame.new(chart, sources: @sources)
      [rect | _] = Mark.generate(frame, hd(chart.marks), sources: @sources).children
      assert rect.attrs == %{x: 0, y: 200.0, width: 40.0, height: 0.0}
    end

    test "rows/3 runs the mark's pipeline and is [] for an unbound source" do
      chart =
        chart(%{
          type: :rect,
          data: %{source: :primary, transforms: [%{op: :bin, field: :v, thresholds: 2}]},
          channels: %{x0: :x0, x1: :x1, y0: :y0, y1: :count}
        })

      frame = Frame.new(chart, sources: @sources)
      assert [%{x0: 2, count: _} | _] = Mark.rows(frame, hd(chart.marks), @sources)
      assert Mark.rows(frame, hd(chart.marks), %{}) == []
      assert Mark.generate(frame, hd(chart.marks)).children == []
      assert Frame.scale(frame, :y).domain == [0, 10]
    end

    test "inference reads the transformed columns" do
      frame =
        Map.put(@frame, :scales, %{x: %{kind: :linear}, y: %{kind: :linear, domain: [0, :auto]}})

      data = %{source: :primary, transforms: [%{op: :bin, field: :v, thresholds: [5]}]}

      chart =
        chart(%{type: :rect, data: data, channels: %{x0: :x0, x1: :x1, y0: :y0, y1: :count}}, %{
          frame: frame
        })

      frame = Frame.new(chart, sources: @sources)
      assert Frame.scale(frame, :x).domain == [2, 9]
      assert Frame.scale(frame, :y).domain == [0, 2]
    end
  end

  describe "paint and style" do
    test "the paint is the theme's series colour for the mark's position" do
      assert generate(%{type: :line, channels: %{x: :t, y: :v}}).style ==
               %{class: "mark mark-line", fill: :none, stroke: "var(--vis-series-1, #3b6fa8)"}

      group = generate(%{type: :area, channels: %{x: :t, y: :v}}, %{}, index: 3)
      assert group.style == %{class: "mark mark-area", fill: "var(--vis-series-3, #c8373b)"}

      group = generate(%{type: :area, channels: %{x: :t, y: :v}}, %{}, resolve: :literal)
      assert group.style.fill == "#3b6fa8"
    end

    test "the style's own value wins and its class is appended" do
      style = %{stroke: "#f00", stroke_width: 2, class: "hot"}

      group =
        generate(%{type: :line, channels: %{x: :t, y: :v}, style: :s}, %{styles: %{s: style}})

      assert group.style == %{
               class: "mark mark-line hot",
               fill: :none,
               stroke: "#f00",
               stroke_width: 2
             }
    end

    test "a series channel gives one path per series, coloured by the colour scale" do
      group = generate(%{type: :line, channels: %{x: :t, y: :v, series: :k}})
      [k0, k1] = group.children
      assert k0.style == %{stroke: "var(--vis-series-1, #3b6fa8)"}
      assert k1.style == %{stroke: "var(--vis-series-2, #d9730d)"}

      assert d(k0) ==
               Line.new()
               |> Line.x(px(:t))
               |> Line.y(py(:v))
               |> Line.generate(Enum.filter(@rows, &(&1.k == "k0")))

      frame = Map.put(@frame, :scales, Map.delete(@frame.scales, :color))
      group = generate(%{type: :area, channels: %{x: :t, y: :v, series: :k}}, %{frame: frame})

      assert Enum.map(group.children, & &1.style.fill) == [
               "var(--vis-series-1, #3b6fa8)",
               "var(--vis-series-2, #d9730d)"
             ]
    end

    test "a field binding is bound per element through the colour scale" do
      styles = %{s: %{fill: {:field, :k}, stroke_width: {:field, :v}}}
      group = generate(%{type: :circle, channels: %{x: :t, y: :v}, style: :s}, %{styles: styles})
      refute Map.has_key?(group.style, :fill)
      assert hd(group.children).style == %{fill: "var(--vis-series-1, #3b6fa8)", stroke_width: 4}
      assert Enum.at(group.children, 1).style.fill == "var(--vis-series-2, #d9730d)"

      group = generate(%{type: :band, channels: %{x0: :t, x1: :hi}, style: :s}, %{styles: styles})

      assert hd(group.children).style == %{
               class: "band",
               fill: "var(--vis-series-1, #3b6fa8)",
               stroke_width: 4
             }
    end

    test "a rect's value reaches the colour scale as its fill" do
      [rect | _] =
        generate(%{type: :rect, channels: %{x0: :t, x1: :hi, y0: 0, y1: :v, value: :k}}).children

      assert rect.style == %{fill: "var(--vis-series-1, #3b6fa8)"}
    end
  end

  describe "inline label" do
    test "one text per element at the anchor point, the field read from the datum" do
      label = %{text: ["v=", {:field, :v}], anchor: :right, dx: 1, dy: 2}
      group = generate(%{type: :symbol, channels: %{x: :t, y: :v}, label: label})
      texts = Enum.filter(group.children, &(&1.type == :text))
      assert length(texts) == 4
      [first | _] = texts
      assert first.attrs == %{x: 5.0, y: 122.0, dy: "0.32em"}
      assert first.content == "v=4"
      assert first.style.text_anchor == :start
      assert first.style.class == "mark-label"
      assert first.style.fill == "var(--vis-text, #333333)"
    end

    test "a path mark labels each series at its last point, above it by default" do
      group =
        generate(%{
          type: :line,
          channels: %{x: :t, y: :v, series: :k},
          label: %{text: [{:field, :k}]}
        })

      [_, _, t0, t1] = group.children
      assert {t0.content, t0.attrs} == {"k0", %{x: 200.0, y: 156.0}}
      assert {t1.content, t1.attrs} == {"k1", %{x: 300.0, y: 56.0}}
      assert t0.style.text_anchor == :middle
    end
  end

  describe "the frame" do
    test "places every mark between the grid and the axes, and none without sources" do
      axes = [%{scale: :x, side: :bottom, grid: true}, %{scale: :y, side: :left}]

      chart =
        chart(%{type: :line, channels: %{x: :t, y: :v}}, %{frame: Map.put(@frame, :axes, axes)})

      frame = Frame.new(chart, sources: @sources)

      classes = fn opts ->
        frame |> Frame.generate(opts) |> Map.fetch!(:children) |> Enum.map(& &1.style.class)
      end

      assert classes.([]) == ["grid", "axis axis-bottom", "axis axis-left"]

      assert classes.(sources: @sources) == [
               "grid",
               "mark mark-line",
               "axis axis-bottom",
               "axis axis-left"
             ]
    end

    test "draws a facet's marks per panel from the panel's rows" do
      facet = %{
        kind: :facet,
        size: %{width: 300, height: 200},
        margin: %{top: 0, right: 0, bottom: 0, left: 0},
        facet: %{by: :k, columns: 2},
        scales: %{x: %{kind: :linear, domain: [0, 3]}, y: %{kind: :linear, domain: [0, 10]}}
      }

      chart = chart(%{type: :circle, channels: %{x: :t, y: :v}}, %{frame: facet})
      frame = Frame.new(chart, sources: @sources)
      [panel0, panel1] = Frame.generate(frame, sources: @sources).children
      [mark0, _title] = panel0.children
      [mark1, _] = panel1.children
      assert Enum.map(mark0.children, & &1.attrs.cx) == [0.0, 100.0]
      assert Enum.map(mark1.children, & &1.attrs.cx) == [50.0, 150.0]
    end

    test "renders the marks on a canvas with literal paints" do
      chart = chart(%{type: :line, channels: %{x: :t, y: :v}, label: %{text: ["end"]}})
      frame = Frame.new(chart, sources: @sources)
      svg = Frame.render(frame, sources: @sources)
      assert svg =~ ~s(class="mark mark-line") and svg =~ "var(--vis-series-1"

      canvas = Frame.render(frame, sources: @sources, backend: :canvas)
      refute canvas =~ "var("
      assert canvas =~ "#3b6fa8"

      assert Render.to_string(Frame.generate(frame, sources: @sources, resolve: :literal),
               backend: :canvas
             ) == canvas
    end

    test "a variable reached while drawing raises" do
      label = %{text: ["at ", Chart.var(:unit)]}

      chart =
        chart(%{type: :line, channels: %{x: :t, y: :v}, label: label}, %{vars: %{unit: %{}}})

      frame = Frame.new(chart)

      assert_raise ArgumentError, ~r/variable :unit is unresolved/, fn ->
        Mark.generate(frame, hd(chart.marks), sources: @sources)
      end
    end
  end
end
