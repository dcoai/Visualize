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
          sources: %{primary: %{fields: [:t, :v, :lo, :hi, :lo2, :hi2, :k, :s]}},
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

    test "an offset places a datum within its band: the two-band grouped bar, byte for byte the hand-built one (#132, D-109)" do
      # Rows: k0 and k1 twice each (t = 0..3), s = the series within the category.
      rows =
        for {v, i} <- Enum.with_index([4, 9, 2, 7]),
            do: %{k: "k#{rem(i, 2)}", s: "s#{div(i, 2)}", v: v}

      scales = %{
        x: %{kind: :band, domain: ["k0", "k1"], padding: 0.2},
        x_offset: %{kind: :band, padding: 0.1},
        y: %{kind: :linear, domain: [0, 10]}
      }

      chart =
        chart(
          %{type: :rect, channels: %{x0: :k, x1: :k, y0: 0, y1: :v}, offset: %{x: :s}},
          %{frame: Map.put(@frame, :scales, scales)}
        )

      frame = Frame.new(chart, sources: %{primary: rows})
      # The offset scale's domain is the offset field's values, its range the outer bandwidth.
      assert frame.scales.x_offset.domain == ["s0", "s1"]

      assert frame.scales.x_offset.range == [
               0,
               Visualize.Scale.Band.bandwidth(frame.scales.x)
             ]

      rects = Mark.generate(frame, hd(chart.marks), sources: %{primary: rows}).children

      # By hand: the outer band over the categories, the inner over the series inside it.
      outer =
        Scale.band()
        |> Scale.domain(["k0", "k1"])
        |> Scale.range([0, 300])
        |> Scale.Band.padding(0.2)

      inner =
        Scale.band()
        |> Scale.domain(["s0", "s1"])
        |> Scale.range([0, Scale.Band.bandwidth(outer)])
        |> Scale.Band.padding(0.1)

      expected =
        for %{k: k, s: s, v: v} <- rows do
          x = Scale.apply(outer, k) + Scale.apply(inner, s)
          {x, Scale.apply(y(), v), Scale.Band.bandwidth(inner), 200 - Scale.apply(y(), v)}
        end

      round4 = fn tuple -> tuple |> Tuple.to_list() |> Enum.map(&Float.round(&1 * 1.0, 4)) end

      assert Enum.map(rects, &round4.({&1.attrs.x, &1.attrs.y, &1.attrs.width, &1.attrs.height})) ==
               Enum.map(expected, round4)

      # A series the inner scale lacks places nothing; a family whose outer is not a band too.
      lacking = Map.put(scales, :x_offset, %{kind: :band, domain: ["s0"]})

      chart2 =
        chart(%{type: :rect, channels: %{x0: :k, x1: :k, y0: 0, y1: :v}, offset: %{x: :s}}, %{
          frame: Map.put(@frame, :scales, lacking)
        })

      frame2 = Frame.new(chart2, sources: %{primary: rows})

      assert length(Mark.generate(frame2, hd(chart2.marks), sources: %{primary: rows}).children) ==
               2
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

  describe "a filled line is the area under it (spec/14 §5.6)" do
    test "a fill on a line draws the area to the baseline beneath an unfilled line" do
      styles = %{s: %{fill: "#abc", curve: :step_after}}
      group = generate(%{type: :line, channels: %{x: :t, y: :v}, style: :s}, %{styles: styles})
      [area, line] = group.children

      assert area.style == %{class: "line-fill", stroke: :none}
      assert line.style == %{fill: :none}
      assert group.style.fill == "#abc"

      assert d(area) ==
               Area.new()
               |> Area.x(px(:t))
               |> Area.y0(Scale.apply(y(), 0))
               |> Area.y1(py(:v))
               |> Area.curve(:step_after)
               |> Area.generate(@rows)

      assert d(line) ==
               Line.new()
               |> Line.x(px(:t))
               |> Line.y(py(:v))
               |> Line.curve(:step_after)
               |> Line.generate(@rows)

      # A line with no fill, or fill none, is one path as before.
      [only] = generate(%{type: :line, channels: %{x: :t, y: :v}}).children
      refute Map.has_key?(only.style, :fill)

      [only] =
        generate(%{type: :line, channels: %{x: :t, y: :v}, style: :n}, %{
          styles: %{n: %{fill: :none}}
        }).children

      assert only.style == %{}

      # Per series, the area comes before each series' line and carries its series.
      group =
        generate(%{type: :line, channels: %{x: :t, y: :v, series: :k}, style: :s}, %{
          styles: styles
        })

      assert Enum.map(group.children, &{&1.style[:class], &1.attrs["data-series"]}) == [
               {"line-fill", "k0"},
               {nil, "k0"},
               {"line-fill", "k1"},
               {nil, "k1"}
             ]
    end
  end

  describe "stroke style (spec/14 §5.6)" do
    @styles %{s: %{stroke: "#000", stroke_width: 2, stroke_style: :inside}}

    test "inside doubles the width and clips the element to its own shape" do
      group =
        generate(%{type: :circle, channels: %{x: :t, y: :v}, style: :s}, %{styles: @styles})

      [first | _] = group.children
      assert first.style.stroke_width == 4
      assert first.clip.keep == :inside
      assert first.clip.shape.type == :circle and first.clip.shape.attrs == first.attrs
      assert first.clip.shape.style == %{}

      svg = group |> SVG.render_element() |> IO.iodata_to_binary()

      assert svg =~
               ~r|<clipPath id="vis-clip-[a-z0-9]+"><circle [^>]*/></clipPath><circle [^>]*clip-path="url\(#vis-clip-[a-z0-9]+\)"|

      assert length(group.children) == 4
    end

    test "outside is the fill alone then the outline clipped to everything but the shape" do
      styles = %{s: %{@styles.s | stroke_style: :outside}}

      group =
        generate(%{type: :rect, channels: %{x0: :t, x1: :hi, y0: 0, y1: :v}, style: :s}, %{
          styles: styles
        })

      [fill, outline | _] = group.children
      assert fill.style.stroke == :none and fill.clip == nil
      assert outline.style == %{fill: :none, stroke_width: 4}
      assert outline.clip.keep == :outside
      assert length(group.children) == 8

      svg = group |> SVG.render_element() |> IO.iodata_to_binary()
      assert svg =~ ~s(<mask height="200000" id="vis-mask-)
      assert svg =~ ~s(maskUnits="userSpaceOnUse")
      assert svg =~ ~r|<rect [^>]*fill="white"[^>]*/><rect [^>]*fill="black"|
      assert svg =~ ~r|<rect [^>]*mask="url\(#vis-mask-[a-z0-9]+\)"|

      # The canvas clips with the even-odd rule under a rectangle of everything.
      js = group |> Visualize.Backend.Canvas.render_element() |> IO.iodata_to_binary()
      assert js =~ "ctx.rect(-100000, -100000, 200000, 200000);"
      assert js =~ "ctx.clip('evenodd');"
    end

    test "inside on a canvas clips to the shape; on the binary stream it draws single" do
      group =
        generate(%{type: :circle, channels: %{x: :t, y: :v}, style: :s}, %{styles: @styles})

      js = group |> Visualize.Backend.Canvas.render_element() |> IO.iodata_to_binary()
      assert js =~ ~r/ctx\.save\(\);\nctx\.beginPath\(\);\nctx\.arc\([^)]*\);\nctx\.clip\(\);/
      assert is_binary(Visualize.Backend.Canvas.render_element(group, format: :binary))
    end

    test "double lays a third-width stroke in the fill colour over the first; on a line, the background" do
      styles = %{s: %{fill: "#abc", stroke: "#000", stroke_width: 3, stroke_style: :double}}

      group =
        generate(%{type: :rect, channels: %{x0: :t, x1: :hi, y0: 0, y1: :v}, style: :s}, %{
          styles: styles
        })

      [first, second | _] = group.children
      assert first.clip == nil and second.clip == nil
      assert second.style == %{fill: :none, stroke: "#abc", stroke_width: 1.0}
      assert length(group.children) == 8

      styles = %{s: %{stroke: "#000", stroke_width: 3, stroke_style: :double}}
      group = generate(%{type: :line, channels: %{x: :t, y: :v}, style: :s}, %{styles: styles})
      [_line, gap] = group.children
      assert gap.style.stroke == "var(--vis-background, #ffffff)"
    end

    test "inside and outside on an open mark draw single" do
      group = generate(%{type: :line, channels: %{x: :t, y: :v}, style: :s}, %{styles: @styles})
      [line] = group.children
      assert line.clip == nil and Map.get(line.style, :stroke_width) == nil
    end
  end

  describe "tooltip" do
    test "without a tooltip node no element carries a datum attribute" do
      group = generate(%{type: :circle, channels: %{x: :t, y: :v}})
      assert group.attrs == %{}
      refute Enum.any?(group.children, &Map.has_key?(&1.attrs, "data-datum"))
    end

    test "the named fields go on every element in order, the template and event on the group" do
      group =
        generate(%{
          type: :circle,
          channels: %{x: :t, y: :v},
          tooltip: %{fields: [:v, :k], template: "{k}: {v}", event: :point_click}
        })

      assert group.attrs == %{
               "data-tooltip-template" => "{k}: {v}",
               "data-tooltip-event" => "point_click"
             }

      assert Enum.map(group.children, & &1.attrs["data-datum"]) == List.duplicate("v k", 4)
      assert Enum.map(group.children, & &1.attrs["data-datum-v"]) == ~w(4 9 2 7)
      assert Enum.map(group.children, & &1.attrs["data-datum-k"]) == ~w(k0 k1 k0 k1)
      assert Render.to_string(group) =~ ~s|data-datum="v k" data-datum-k="k0" data-datum-v="4"|
    end

    test "no fields writes every column of the datum in sorted order, and nothing on the group" do
      [first | _] = generate(%{type: :circle, channels: %{x: :t, y: :v}, tooltip: %{}}).children
      assert first.attrs["data-datum"] == "hi hi2 k lo lo2 t v"
      assert first.attrs["data-datum-hi2"] == "6"
    end

    test "a transformed row's own columns are fields, and a per-series path carries its first row" do
      group =
        generate(%{
          type: :line,
          data: %{source: :primary, transforms: [%{op: :sort, field: :v}]},
          channels: %{x: :t, y: :v, series: :k},
          tooltip: %{fields: [:k, :v]}
        })

      assert Enum.map(group.children, & &1.attrs["data-datum-k"]) == ~w(k0 k1)
      assert Enum.map(group.children, & &1.attrs["data-datum-v"]) == ~w(2 7)
    end

    test "a nil field value writes no attribute and a rule's group carries the datum" do
      [rule | _] =
        generate(
          %{type: :rule, channels: %{x: :t}, tooltip: %{fields: [:t, :gone]}},
          %{sources: %{primary: %{fields: [:t, :gone]}}}
        ).children

      assert rule.type == :group
      assert rule.attrs["data-datum"] == "t gone"
      refute Map.has_key?(rule.attrs, "data-datum-gone")
    end

    test "the node validates: an undeclared field is reported, and it round-trips the map" do
      design = %{
        version: 1,
        sources: %{primary: %{fields: [:t, :v]}},
        frame: @frame,
        marks: [
          %{
            type: :circle,
            data: :primary,
            channels: %{x: :t, y: :v},
            tooltip: %{fields: [:t, :w]}
          }
        ]
      }

      assert {:error, [{[:marks, 0, :tooltip, :fields, 1], {:undeclared, :field, :w}}]} =
               Chart.from_map(design)

      ok = put_in(design, [:marks, Access.at(0), :tooltip], %{fields: [:t], event: :pick})
      assert hd(Chart.to_map(Chart.from_map!(ok)).marks).tooltip == %{fields: [:t], event: :pick}
    end
  end

  describe "legend toggling" do
    test "each series path names its series; a mark without the channel names none" do
      group = generate(%{type: :line, channels: %{x: :t, y: :v, series: :k}})
      assert Enum.map(group.children, & &1.attrs["data-series"]) == ["k0", "k1"]

      area = generate(%{type: :area, channels: %{x: :t, y: :v, series: :k}})
      assert Enum.map(area.children, & &1.attrs["data-series"]) == ["k0", "k1"]

      plain = generate(%{type: :line, channels: %{x: :t, y: :v}})
      assert hd(plain.children).attrs == %{}
      assert Render.to_string(group) =~ ~s|<path d="M0,120L200,160" data-series="k0"|
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

    test "a :text mark is one text per datum at its position, its label's text in its label's style, and nothing else (#134)" do
      group =
        generate(%{
          type: :text,
          channels: %{x: :t, y: :v},
          label: %{text: [{:field, :k}, ":", {:field, :v}], anchor: :bottom, dx: 3}
        })

      assert length(group.children) == 4
      assert Enum.all?(group.children, &(&1.type == :text))
      [first | _] = group.children
      assert first.content == "k0:4"
      # Row 0: t = 0 → x 0, v = 4 → y 120; anchored below, 4 down, dx 3.
      assert first.attrs == %{x: 3.0, y: 124.0, dy: "0.71em"}
      assert first.style.class == "mark-text"
      assert first.style.text_anchor == :middle
      assert first.style.fill == "var(--vis-text, #333333)"

      # Without a label node, the value channel is the text and the anchor the default.
      plain = generate(%{type: :text, channels: %{x: :t, y: :v, value: :v}})
      assert Enum.map(plain.children, & &1.content) == ["4", "9", "2", "7"]
      assert hd(plain.children).attrs == %{x: 0.0, y: 116.0}
    end

    test ":outward on a rose lands on the sector's own ray at R + 4 + dr, anchored to its side; rotate follows the ray (#137)" do
      polar = %{
        kind: :polar,
        size: %{width: 200, height: 200},
        margin: %{top: 0, right: 0, bottom: 0, left: 0},
        scales: %{angle: %{kind: :radial, domain: [0, 4]}, r: %{kind: :linear, domain: [0, 10]}}
      }

      labels = fn label ->
        generate(
          %{type: :rose, channels: %{angle: :t, value: :v}, options: %{width: 1}, label: label},
          %{frame: polar}
        ).children
        |> Enum.filter(&(&1.type == :text))
      end

      # Sector i is centred on its angle, a quarter turn each from 12 o'clock: up, right,
      # down, left. Its label leaves from its rim (v × 10) along the ray, 4 + 15 beyond it;
      # the side gives the anchor.
      texts = labels.(%{text: [{:field, :k}], anchor: :outward, dr: 15})
      assert length(texts) == 4

      for {text, {v, i}} <- Enum.zip(texts, Enum.with_index([4, 9, 2, 7])) do
        a = i * :math.pi() / 2
        radius = v * 10 + 19
        assert_in_delta text.attrs.x, radius * :math.sin(a), 1.0e-6
        assert_in_delta text.attrs.y, -radius * :math.cos(a), 1.0e-6
        assert text.style.text_anchor == Enum.at([:middle, :start, :middle, :end], i)
      end

      # :radial rotation is the ray's angle; on the left half it flips a half turn and the
      # text anchors :end so it runs toward the centre. A number is plain degrees.
      # Sector 1 is at 3 o'clock (ray 0°), sector 3 at 9 o'clock (ray 180°): a radial
      # label reads along the ray on the right and flips a half turn on the left, where it
      # anchors :end so it runs toward the centre.
      [_, right, _, left] = labels.(%{text: ["!"], anchor: :outward, rotate: :radial})
      assert right.style.text_anchor == :start and left.style.text_anchor == :end
      [{:rotate, deg_r, _, _}] = right.transform.operations
      [{:rotate, deg_l, _, _}] = left.transform.operations
      assert_in_delta deg_r, 0.0, 1.0e-6
      assert_in_delta deg_l, 0.0, 1.0e-6
      [fixed | _] = labels.(%{text: ["!"], anchor: :outward, rotate: 30})
      assert [{:rotate, 30, _, _}] = fixed.transform.operations

      # :tangent is a quarter turn from the ray, flipped on the lower half: sector 0 (up,
      # ray −90°) and sector 2 (down, ray 90°) both read level.
      [top, _, bottom, _] = labels.(%{text: ["!"], anchor: :outward, rotate: :tangent})
      [{:rotate, t_deg, _, _}] = top.transform.operations
      [{:rotate, b_deg, _, _}] = bottom.transform.operations
      assert_in_delta t_deg, 0.0, 1.0e-6
      assert_in_delta b_deg, 0.0, 1.0e-6
    end

    test "the edge anchors of a rect land 4 outside the midpoint of that edge; on a circle they fall back to the side (#134)" do
      at = fn anchor, type, channels ->
        [first | _] =
          generate(%{type: type, channels: channels, label: %{text: ["!"], anchor: anchor}}).children
          |> Enum.filter(&(&1.type == :text))

        {first.attrs, first.style.text_anchor}
      end

      rect = %{x0: :t, x1: :hi, y0: 0, y1: :v}
      # Row 0's rect: x 0..500, y 120..200 (v = 4 → 120, 0 → 200).
      assert at.(:x1, :rect, rect) == {%{x: 504.0, y: 160.0, dy: "0.32em"}, :start}
      assert at.(:x0, :rect, rect) == {%{x: -4.0, y: 160.0, dy: "0.32em"}, :end}
      assert at.(:y1, :rect, rect) == {%{x: 250.0, y: 116.0}, :middle}
      assert at.(:y0, :rect, rect) == {%{x: 250.0, y: 204.0, dy: "0.71em"}, :middle}
      # A circle has no edges: the same side, from its point.
      assert at.(:x1, :circle, %{x: :t, y: :v}) == {%{x: 4.0, y: 120.0, dy: "0.32em"}, :start}
    end

    test "fit cuts a label to its element's width or hides it; a type with no extent fits everything (#138)" do
      texts = fn mark ->
        generate(mark).children |> Enum.filter(&(&1.type == :text)) |> Enum.map(& &1.content)
      end

      # The rects span 500, 900, 100 and 500 px (t to hi through x); at the default 12px
      # font, 0.6 × 12 = 7.2 per character, that is 69, 125, 13 and 69 characters of room.
      wide = %{type: :rect, channels: %{x0: :t, x1: :hi, y0: 0, y1: :v}}
      label = fn fit, text -> %{text: [text], anchor: :middle, fit: fit} end
      long = String.duplicate("abcdefghij", 8)

      assert texts.(Map.put(wide, :label, label.(:truncate, "short"))) |> hd() == "short"

      assert texts.(Map.put(wide, :label, label.(:truncate, long))) == [
               String.slice(long, 0, 68) <> "…",
               long,
               String.slice(long, 0, 12) <> "…",
               String.slice(long, 0, 68) <> "…"
             ]

      assert texts.(Map.put(wide, :label, label.(:none, long))) |> hd() == long
      assert texts.(Map.put(wide, :label, label.(:hide, long))) == [long]
      assert texts.(Map.put(wide, :label, label.(:hide, "short"))) |> length() == 4

      # A circle's extent is its diameter: r 3 by default, no room for even one character.
      circle = %{type: :circle, channels: %{x: :t, y: :v}, label: label.(:truncate, "ab")}
      assert texts.(circle) == []
      big = Map.put(circle, :options, %{radius: 20})
      assert texts.(Map.put(big, :label, label.(:truncate, "abcdefgh"))) |> hd() == "abcd…"

      # A symbol has no extent, so nothing is cut.
      symbol = %{type: :symbol, channels: %{x: :t, y: :v}, label: label.(:truncate, long)}
      assert texts.(symbol) |> hd() == long
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
