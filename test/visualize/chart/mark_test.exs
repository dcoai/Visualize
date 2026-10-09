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
  doctest Visualize.Chart.Mark.Bend

  @rows for {v, i} <- Enum.with_index([4, 9, 2, 7]),
            do: %{t: i, v: v, lo: v - 1, hi: v + 1, lo2: v - 2, hi2: v + 2, k: "k#{rem(i, 2)}"}
  @sources %{primary: @rows}

  @frame %{
    kind: :cartesian,
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
          version: 2,
          sources: %{primary: %{fields: [:t, :v, :lo, :hi, :lo2, :hi2, :k, :s]}},
          frames: %{main: @frame},
          marks: [Map.merge(%{data: :primary}, mark)]
        },
        extra
      )
    )
  end

  defp generate(mark, extra \\ %{}, opts \\ []) do
    chart = chart(mark, extra)
    frame = Frame.new(chart, sources: @sources, size: {300, 200})
    Mark.generate(frame, hd(chart.marks), Keyword.put_new(opts, :sources, @sources))
  end

  # A labelled mark's two parts (spec/14 §5.6, #485): its elements' group, which carries
  # the mark's style, and the texts of its labels' group beside it.
  defp parts(%Element{
         children: [
           %Element{style: %{class: "mark-elements"}} = elements,
           %Element{style: %{class: "mark-labels"} = style, children: labels}
         ]
       }) do
    assert style == %{class: "mark-labels"}
    {elements, labels}
  end

  defp labels(group), do: group |> parts() |> elem(1)

  # A labelled mark read as one group: its elements' group with the labels after them.
  defp flat(group) do
    {elements, labels} = parts(group)
    %{elements | children: elements.children ++ labels}
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

      # The generator's text is lifted out of its rule's group into the labels' group (#485).
      {elements, texts} = parts(group)
      assert length(elements.children) == 4

      for {{got, text}, want} <- Enum.zip(Enum.zip(elements.children, texts), expected) do
        [line] = got.children
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
        margin: %{top: 0, right: 0, bottom: 0, left: 0},
        scales: %{angle: %{kind: :radial, domain: [0, 4]}, r: %{kind: :linear, domain: [0, 10]}}
      }

      mark = %{
        type: :rose,
        channels: %{angle: :t, value: :v},
        options: %{width: 1, pad_angle: 0.05}
      }

      group = generate(mark, %{frames: %{main: polar}})
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

      frame = Frame.new(chart, sources: sources, size: {300, 200})
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
      frame = Frame.new(chart, sources: sources, size: {300, 200})
      group = Mark.generate(frame, hd(chart.marks), sources: sources)
      {paths, texts} = Enum.split_with(flat(group).children, &(&1.type == :path))

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
      assert length(flat(Mark.generate(frame, hd(chart.marks), sources: more)).children) == 6
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
        generate(%{type: :rect, channels: %{x0: :k, x1: :k, y0: 0, y1: :v}}, %{
          frames: %{main: frame}
        }).children

      assert rect.attrs.x == 0 and rect.attrs.width == 150.0

      [point | _] =
        generate(%{type: :symbol, channels: %{x: :k, y: :v}}, %{frames: %{main: frame}}).children

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
          %{frames: %{main: Map.put(@frame, :scales, scales)}}
        )

      frame = Frame.new(chart, sources: %{primary: rows}, size: {300, 200})
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
          frames: %{main: Map.put(@frame, :scales, lacking)}
        })

      frame2 = Frame.new(chart2, sources: %{primary: rows}, size: {300, 200})

      assert length(Mark.generate(frame2, hd(chart2.marks), sources: %{primary: rows}).children) ==
               2
    end

    test "a datum a scale cannot place is dropped from a per-datum mark and breaks a path" do
      band = %{x: %{kind: :band, domain: ["k0"]}, y: %{kind: :linear, domain: [0, 10]}}
      frame = Map.put(@frame, :scales, band)

      assert length(
               generate(%{type: :symbol, channels: %{x: :k, y: :v}}, %{frames: %{main: frame}}).children
             ) == 2

      rows = [%{t: 0, v: 1}, %{t: 1, v: nil}, %{t: 2, v: 3}, %{t: 3, v: 4}]
      sources = %{primary: rows}
      chart = chart(%{type: :line, channels: %{x: :t, y: :v}})
      frame = Frame.new(chart, sources: sources, size: {300, 200})
      [path] = Mark.generate(frame, hd(chart.marks), sources: sources).children
      assert d(path) == "M200,140L300,120"
    end

    test "a channel naming no declared scale is read as pixels, a constant as itself" do
      chart =
        chart(%{type: :circle, channels: %{x: :t, y: 50}}, %{
          frames: %{main: Map.put(@frame, :scales, %{})}
        })

      frame = Frame.new(chart, sources: @sources, size: {300, 200})
      [circle | _] = Mark.generate(frame, hd(chart.marks), sources: @sources).children
      assert circle.attrs == %{cx: 0, cy: 50, r: 3}
    end

    test "a mark's scales node places a channel family through the scale it names (D-67)" do
      scales = Map.put(@frame.scales, :count, %{kind: :linear, domain: [0, 10], range: [0, 100]})

      chart =
        chart(
          %{type: :rect, channels: %{x0: 0, x1: :v, y0: :t, y1: :t}, scales: %{x: :count}},
          %{frames: %{main: Map.put(@frame, :scales, scales)}}
        )

      frame = Frame.new(chart, sources: @sources, size: {300, 200})
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

      frame = Frame.new(chart, sources: @sources, size: {300, 200})
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
          frames: %{main: frame}
        })

      frame = Frame.new(chart, sources: @sources, size: {300, 200})
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

      group =
        generate(%{type: :area, channels: %{x: :t, y: :v, series: :k}}, %{frames: %{main: frame}})

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

  describe "a channel names its scale's own end (spec/14 §5.2, #420)" do
    # A y scale whose domain excludes zero: the plot is 200 high, so `y(50)` is 200 and
    # `y(150)` is 0 — and data zero maps to 300, a hundred pixels below the plot.
    defp offset_frame(scales) do
      %{@frame | scales: Map.merge(%{x: %{kind: :linear, domain: [0, 3]}}, scales)}
    end

    defp offset_rows, do: for(r <- @rows, do: %{r | v: r.v * 10 + 60})

    defp area_of(mark, frame, rows) do
      chart =
        Chart.from_map!(%{
          version: 2,
          sources: %{primary: %{fields: [:t, :v]}},
          frames: %{main: frame},
          marks: [Map.merge(%{data: :primary}, mark)]
        })

      sources = %{primary: rows}

      group =
        Mark.generate(Frame.new(chart, sources: sources, size: {300, 200}), hd(chart.marks),
          sources: sources
        )

      [child] = group.children
      d(child)
    end

    test "y0 reads the low end of the y domain, so the fill reaches the axis" do
      frame = offset_frame(%{y: %{kind: :linear, domain: [50, 150]}})
      rows = offset_rows()

      drawn =
        area_of(%{type: :area, channels: %{x: :t, y: :v, y0: {:scale, :min}}}, frame, rows)

      scale = Scale.linear() |> Scale.domain([50, 150]) |> Scale.range([200, 0])

      assert drawn ==
               Area.new()
               |> Area.x(fn d -> Scale.apply(x(), d[:t]) end)
               |> Area.y0(200.0)
               |> Area.y1(fn d -> Scale.apply(scale, d[:v]) end)
               |> Area.generate(rows)

      # :max is the other end — the top of the plot.
      assert area_of(%{type: :area, channels: %{x: :t, y: :v, y0: {:scale, :max}}}, frame, rows) =~
               "L0,0"
    end

    test "it follows an inferred domain, where a number could only name a fixed one" do
      rows = offset_rows()
      frame = offset_frame(%{y: %{kind: :linear, domain: :auto}})

      drawn = area_of(%{type: :area, channels: %{x: :t, y: :v, y0: {:scale, :min}}}, frame, rows)

      # The inferred domain is [80, 150]: its low end is the bottom of the plot, whatever
      # the rows turn out to be.
      assert drawn =~ "L0,200"
      refute drawn =~ "L0,300"
    end

    test "on a band scale it is the first or the last category's band" do
      frame = %{
        @frame
        | scales: %{
            x: %{kind: :band, domain: :auto},
            y: %{kind: :linear, domain: [0, 10]}
          }
      }

      rows = [%{t: "a", v: 4}, %{t: "b", v: 9}, %{t: "c", v: 2}]

      # Three bands over 300 pixels: the first starts at 0 and the last at 200, and an
      # edge channel reads a band's start (§5.2).
      assert area_of(%{type: :area, channels: %{x: :t, y: :v, x0: {:scale, :min}}}, frame, rows) =~
               "L0,200"

      assert area_of(%{type: :area, channels: %{x: :t, y: :v, x0: {:scale, :max}}}, frame, rows) =~
               "L200,200"
    end

    test "it contributes nothing to the domain it reads, which would be circular" do
      rows = offset_rows()
      frame = offset_frame(%{y: %{kind: :linear, domain: :auto}})

      chart =
        Chart.from_map!(%{
          version: 2,
          sources: %{primary: %{fields: [:t, :v]}},
          frames: %{main: frame},
          marks: [
            %{data: :primary, type: :area, channels: %{x: :t, y: :v, y0: {:scale, :min}}}
          ]
        })

      # The domain is the rows' extent alone: the y0 channel is read from it, never into
      # it, so it neither widens it nor raises on a value it has no column for.
      assert Frame.new(chart, sources: %{primary: rows}, size: {300, 200}).scales.y.domain ==
               Enum.min_max(Enum.map(rows, & &1.v)) |> Tuple.to_list()
    end
  end

  describe "an area's default baseline stays in the plot (spec/14 §5.2, #420)" do
    test "a domain that excludes zero fills to the nearer edge, not off the plot" do
      frame = %{@frame | scales: %{@frame.scales | y: %{kind: :linear, domain: [50, 150]}}}
      rows = for r <- @rows, do: %{r | v: r.v * 10 + 60}

      chart =
        Chart.from_map!(%{
          version: 2,
          sources: %{primary: %{fields: [:t, :v]}},
          frames: %{main: frame},
          marks: [%{data: :primary, type: :area, channels: %{x: :t, y: :v}}]
        })

      sources = %{primary: rows}

      group =
        Mark.generate(Frame.new(chart, sources: sources, size: {300, 200}), hd(chart.marks),
          sources: sources
        )

      [child] = group.children

      # Data zero is 300 — a hundred pixels below a 200-high plot. Clamped, it is 200.
      assert d(child) =~ "L0,200"
      refute d(child) =~ ",300"
    end

    test "a domain that holds zero is the zero line, exactly as before" do
      group = generate(%{type: :area, channels: %{x: :t, y: :v}})
      [child] = group.children

      assert d(child) ==
               Area.new()
               |> Area.x(px(:t))
               |> Area.y0(Scale.apply(y(), 0))
               |> Area.y1(py(:v))
               |> Area.generate(@rows)
    end

    test "a baseline the design gives is placed as given: the ridgeline's partial fill" do
      rows = [
        %{t: 0, base: 2, top: 5},
        %{t: 1, base: 2, top: 8},
        %{t: 2, base: 2, top: 4}
      ]

      chart =
        Chart.from_map!(%{
          version: 2,
          sources: %{primary: %{fields: [:t, :base, :top]}},
          frames: %{
            main: %{@frame | scales: %{@frame.scales | x: %{kind: :linear, domain: [0, 2]}}}
          },
          marks: [%{data: :primary, type: :area, channels: %{x: :t, y: :top, y0: :base}}]
        })

      sources = %{primary: rows}

      group =
        Mark.generate(Frame.new(chart, sources: sources, size: {300, 200}), hd(chart.marks),
          sources: sources
        )

      [child] = group.children

      # The fill stops at the ridge's own base — 2 of a [0, 10] domain, y = 160 — and
      # never reaches the plot's floor at 200.
      assert d(child) =~ "L0,160"
      refute d(child) =~ ",200"
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
        version: 2,
        sources: %{primary: %{fields: [:t, :v]}},
        frames: %{main: @frame},
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
      texts = labels(group)
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

      # Each label names its series, so a legend toggle hides it with its line (D-126).
      [_, _, t0, t1] = flat(group).children

      assert {t0.content, t0.attrs} ==
               {"k0", %{:x => 200.0, :y => 156.0, "data-series" => "k0"}}

      assert {t1.content, t1.attrs} ==
               {"k1", %{:x => 300.0, :y => 56.0, "data-series" => "k1"}}

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
        margin: %{top: 0, right: 0, bottom: 0, left: 0},
        scales: %{angle: %{kind: :radial, domain: [0, 4]}, r: %{kind: :linear, domain: [0, 10]}}
      }

      labels = fn label ->
        generate(
          %{type: :rose, channels: %{angle: :t, value: :v}, options: %{width: 1}, label: label},
          %{frames: %{main: polar}}
        )
        |> labels()
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
          generate(%{type: type, channels: channels, label: %{text: ["!"], anchor: anchor}})
          |> labels()

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
        generate(mark) |> labels() |> Enum.map(& &1.content)
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

    test "fit holds a rect's height to the label's font size, but not at an edge anchor (#497)" do
      texts = fn channels, label ->
        generate(%{type: :rect, channels: channels, label: label})
        |> labels()
        |> Enum.map(& &1.content)
      end

      # 20 px tall (one unit of y over 200 px for 0..10), and a zero-area cell.
      tall = %{x0: :t, x1: :hi, y0: :lo, y1: :v}
      flat = %{x0: :t, x1: :hi, y0: :v, y1: :v}
      label = fn fit, anchor -> %{text: ["ab"], anchor: anchor, fit: fit} end

      assert texts.(tall, label.(:truncate, :middle)) == ["ab", "ab", "ab", "ab"]
      # A label that would sit on a cell with no room for a line is drawn by no fit.
      assert texts.(flat, label.(:truncate, :middle)) == []
      assert texts.(flat, label.(:hide, :top)) == []
      # `:none` draws it as it is, and an edge anchor sits outside the cell.
      assert length(texts.(flat, label.(:none, :middle))) == 4
      assert length(texts.(flat, label.(:truncate, :x1))) == 4
    end
  end

  describe "a label is not drawn in its mark's style (spec/14 §5.5, §5.6, #485)" do
    @outlined %{outline: %{stroke: "#ffffff", stroke_width: 2, fill_opacity: 0.5}}

    @label_polar %{
      kind: :polar,
      margin: %{top: 0, right: 0, bottom: 0, left: 0},
      scales: %{angle: %{kind: :radial, domain: [0, 4]}, r: %{kind: :linear, domain: [0, 10]}}
    }

    # Every type that draws an inline label, in the frame it draws in, stroked by its style.
    @labelled [
      {:line, %{x: :t, y: :v}, :cartesian},
      {:area, %{x: :t, y: :v}, :cartesian},
      {:band, %{x0: :t, x1: :hi, y: :v}, :cartesian},
      {:rule, %{x: :t}, :cartesian},
      {:x_band, %{x0: :t, x1: :hi}, :cartesian},
      {:symbol, %{x: :t, y: :v}, :cartesian},
      {:rect, %{x0: :t, x1: :hi, y0: 0, y1: :v}, :cartesian},
      {:circle, %{x: :t, y: :v}, :cartesian},
      {:arc, %{value: :v}, :cartesian},
      {:rose, %{angle: :t, value: :v}, :polar},
      {:needle, %{x: :t, y: :v}, :polar},
      {:rect, %{x0: :t, x1: :hi, y0: :lo, y1: :v}, :polar}
    ]

    # Every text of a tree with the elements above it, nearest first: a frame with no axes,
    # legend or labels, so every text is a mark's label.
    defp label_paths(%Element{} = element, ancestors \\ []) do
      case element do
        %Element{type: :text} ->
          [{element, ancestors}]

        %Element{children: children} ->
          Enum.flat_map(children, &label_paths(&1, [element | ancestors]))
      end
    end

    defp drawn(type, channels, kind, label_style) do
      label = Map.merge(%{text: [{:field, :k}], anchor: :middle}, label_style)
      mark = %{type: type, channels: channels, style: :outline, label: label}
      frames = if kind == :polar, do: %{frames: %{main: @label_polar}}, else: %{}
      chart = chart(mark, Map.merge(%{styles: @outlined}, frames))
      frame = Frame.new(chart, sources: @sources, size: {300, 200})
      Frame.generate(frame, sources: @sources, paths: true)
    end

    test "no mark's label inherits the mark's stroke, while its elements keep it" do
      for {type, channels, kind} <- @labelled do
        tree = drawn(type, channels, kind, %{})
        paths = label_paths(tree)
        assert paths != [], "#{type} in #{kind}: no labels"

        for {text, ancestors} <- paths do
          refute Map.has_key?(text.style, :stroke), "#{type}: the label has a stroke"

          for ancestor <- ancestors do
            refute Map.has_key?(ancestor.style, :stroke),
                   "#{type}: a label sits under #{inspect(ancestor.style)}"

            refute Map.has_key?(ancestor.style, :fill_opacity), "#{type}: a faded label"
          end

          # The mark is still the wrapper the hooks read: its class and data-node (D-75).
          mark = Enum.find(ancestors, &match?(%{style: %{class: "mark " <> _}}, &1))
          assert mark.attrs["data-node"] == "marks[0]", "#{type}"
          assert mark.style == %{class: "mark mark-#{type}"}

          assert [%{style: %{class: "mark-elements", stroke: "#ffffff", stroke_width: 2}}, _] =
                   mark.children
        end
      end
    end

    test "a label style that sets a stroke keeps it: a deliberate halo" do
      halo = %{halo: %{stroke: "#000000", stroke_width: 3}}

      for {type, channels, kind} <- @labelled do
        label = %{text: [{:field, :k}], anchor: :middle, style: :halo}
        mark = %{type: type, channels: channels, style: :outline, label: label}
        frames = if kind == :polar, do: %{frames: %{main: @label_polar}}, else: %{}
        chart = chart(mark, Map.merge(%{styles: Map.merge(@outlined, halo)}, frames))
        frame = Frame.new(chart, sources: @sources, size: {300, 200})
        tree = Frame.generate(frame, sources: @sources)

        for {text, _ancestors} <- label_paths(tree) do
          assert {text.style.stroke, text.style.stroke_width} == {"#000000", 3}, "#{type}"
        end
      end
    end

    test "the SVG says it: no stroke on the labels' group or above it" do
      tree = drawn(:arc, %{value: :v}, :cartesian, %{})
      svg = Render.to_string(tree, backend: :svg)

      assert svg =~
               ~r{<g class="mark mark-arc" data-node="marks\[0\]"[^>]*><g class="mark-elements"[^>]*stroke="#ffffff"[^>]*>.*</g><g class="mark-labels"><text class="mark-label"}s

      refute svg =~ ~r{<g class="mark-labels"[^>]*stroke}
    end

    test "an unlabelled mark is the one styled group as before, and a labelled one with no rows is still the wrapper" do
      plain =
        generate(%{type: :circle, channels: %{x: :t, y: :v}, style: :outline}, %{
          styles: @outlined
        })

      assert plain.style.class == "mark mark-circle" and plain.style.stroke == "#ffffff"
      assert Enum.all?(plain.children, &(&1.type == :circle))

      empty =
        generate(
          %{type: :circle, channels: %{x: :t, y: :v}, label: %{text: ["!"]}},
          %{},
          sources: %{}
        )

      assert {%{children: []}, []} = parts(empty)
    end
  end

  describe "a label's ink follows its element (spec/14 §3.2, §5.5, #486, D-123)" do
    @pale "#fff2b0"
    @deep "#1a2a5a"

    @inked_frame %{
      kind: :cartesian,
      margin: %{top: 0, right: 0, bottom: 0, left: 0},
      scales: %{
        x: %{kind: :linear, domain: [0, 4]},
        y: %{kind: :linear, domain: [0, 10]},
        color: %{kind: :ordinal, domain: ["k0", "k1"], range: [@pale, @deep]}
      }
    }

    defp inked(style, label_style, opts \\ []) do
      mark = %{
        type: :rect,
        channels: %{x0: :t, x1: :hi, y0: 0, y1: :v},
        style: :cell,
        label: %{text: [{:field, :k}], anchor: :middle, style: :ink}
      }

      extra = %{
        frames: %{main: @inked_frame},
        styles: %{cell: style, ink: label_style},
        defs: Keyword.get(opts, :defs, %{})
      }

      mark
      |> generate(extra, Keyword.take(opts, [:resolve]))
      |> labels()
      |> Enum.map(&{&1.content, &1.style.fill})
    end

    test "dark ink on a light fill and light ink on a dark fill, the same literal in both modes" do
      for mode <- [:css, :literal] do
        assert inked(%{fill: {:field, :k}}, %{fill: :contrast}, resolve: mode) == [
                 {"k0", "#333333"},
                 {"k1", "#ffffff"},
                 {"k0", "#333333"},
                 {"k1", "#ffffff"}
               ]
      end
    end

    test "the mark's own paint is the fill when the element carries none" do
      assert [{_, "#ffffff"} | _] = inked(%{fill: @deep}, %{fill: :contrast})
      assert [{_, "#333333"} | _] = inked(%{fill: @pale}, %{fill: :contrast})
      # No fill in the style: the series paint, the default theme's #3b6fa8.
      assert [{_, "#ffffff"} | _] = inked(%{}, %{fill: :contrast})
      # A slot reaches the CSS output as a reference, read here by its fallback.
      assert [{_, "#ffffff"} | _] = inked(%{fill: :series_1}, %{fill: :contrast}, resolve: :css)
    end

    test "a translucent fill is read over the background, and no fill is the background" do
      # Deep navy at a tenth is a pale wash over white.
      assert [{_, "#333333"} | _] = inked(%{fill: @deep, fill_opacity: 0.1}, %{fill: :contrast})
      assert [{_, "#333333"} | _] = inked(%{fill: @deep, opacity: 0.1}, %{fill: :contrast})
      assert [{_, "#333333"} | _] = inked(%{fill: :none, stroke: @deep}, %{fill: :contrast})
    end

    test "a paint is read by its first stop" do
      defs = %{
        wash: %{kind: :linear, stops: [%{offset: 0, colour: @deep}, %{offset: 1, colour: @pale}]}
      }

      for mode <- [:css, :literal] do
        assert [{_, "#ffffff"} | _] =
                 inked(%{fill: {:paint, :wash}}, %{fill: :contrast}, defs: defs, resolve: mode)
      end
    end

    test "a halo's :contrast stroke is inked the same way, and other keys are untouched" do
      mark = %{
        type: :rect,
        channels: %{x0: :t, x1: :hi, y0: 0, y1: :v},
        style: :cell,
        label: %{text: [{:field, :k}], anchor: :middle, style: :ink}
      }

      extra = %{
        frames: %{main: @inked_frame},
        styles: %{cell: %{fill: {:field, :k}}, ink: %{fill: "#ff0000", stroke: :contrast}}
      }

      [first, second | _] = mark |> generate(extra) |> labels()
      assert {first.style.fill, first.style.stroke} == {"#ff0000", "#333333"}
      assert {second.style.fill, second.style.stroke} == {"#ff0000", "#ffffff"}
    end

    test "a text with no element under it is inked against the background" do
      chart =
        chart(%{type: :text, channels: %{x: :t, y: :v}, label: %{text: ["!"], style: :ink}}, %{
          styles: %{ink: %{fill: :contrast}},
          theme: :dark
        })

      frame = Frame.new(chart, sources: @sources, size: {300, 200})
      group = Mark.generate(frame, hd(chart.marks), sources: @sources)
      texts = for %Element{type: :text} = t <- group.children, do: t.style.fill
      assert texts != [] and Enum.all?(texts, &(&1 == "#e6e6e6"))
    end

    test "it validates on every theme and reads back from JSON" do
      chart =
        chart(
          %{
            type: :rect,
            channels: %{x0: :t, x1: :hi, y0: 0, y1: :v},
            label: %{text: ["!"], style: :ink}
          },
          %{styles: %{ink: %{fill: :contrast}}}
        )

      {:ok, json} = Chart.to_json(chart)
      assert json =~ ~s("fill":"contrast")
      assert {:ok, back} = Chart.from_json(json)
      assert back.styles.ink.fill == :contrast

      # A built-in theme, whose slots the validator checks, accepts it: it is not a slot.
      on_dark = fn fill ->
        Chart.from_map(%{
          version: 2,
          theme: :dark,
          sources: %{p: %{fields: [:t]}},
          frames: %{main: @frame},
          styles: %{ink: %{fill: fill}},
          marks: [%{type: :rect, data: :p, channels: %{x0: :t, x1: :t, y0: 0, y1: :t}}]
        })
      end

      assert {:ok, _} = on_dark.(:contrast)
      assert {:error, _} = on_dark.(:no_such_slot)
      Chart.from_json(String.replace(json, ~s("version"), ~s("theme":"dark","version")))
    end
  end

  describe "the frame" do
    test "places every mark between the grid and the axes, and none without sources" do
      axes = [%{scale: :x, side: :bottom, grid: true}, %{scale: :y, side: :left}]

      chart =
        chart(%{type: :line, channels: %{x: :t, y: :v}}, %{
          frames: %{main: Map.put(@frame, :axes, axes)}
        })

      frame = Frame.new(chart, sources: @sources, size: {300, 200})

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
        margin: %{top: 0, right: 0, bottom: 0, left: 0},
        facet: %{by: :k, columns: 2},
        scales: %{x: %{kind: :linear, domain: [0, 3]}, y: %{kind: :linear, domain: [0, 10]}}
      }

      chart = chart(%{type: :circle, channels: %{x: :t, y: :v}}, %{frames: %{main: facet}})
      frame = Frame.new(chart, sources: @sources, size: {300, 200})
      [panel0, panel1] = Frame.generate(frame, sources: @sources).children
      [mark0, _title] = panel0.children
      [mark1, _] = panel1.children
      assert Enum.map(mark0.children, & &1.attrs.cx) == [0.0, 100.0]
      assert Enum.map(mark1.children, & &1.attrs.cx) == [50.0, 150.0]
    end

    test "renders the marks on a canvas with literal paints" do
      chart = chart(%{type: :line, channels: %{x: :t, y: :v}, label: %{text: ["end"]}})
      frame = Frame.new(chart, sources: @sources, size: {300, 200})
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

  describe "polar is a coordinate transform (spec/14 §4.3, §5.2, #391)" do
    alias Visualize.Chart.Mark.Bend

    # A polar frame of a 240° sweep from −120°, r over 30..150; x names angle, y names r.
    @polar %{
      kind: :polar,
      margin: %{top: 0, right: 0, bottom: 0, left: 0},
      scales: %{
        angle: %{kind: :linear, domain: [0, 3], start: -120, sweep: 240},
        r: %{kind: :linear, domain: [0, 10], range: [30, 150]},
        color: %{kind: :ordinal}
      }
    }

    defp polar(mark, extra \\ %{}) do
      chart = chart(mark, Map.merge(%{frames: %{main: @polar}}, extra))
      frame = Frame.new(chart, sources: @sources, size: {300, 200})
      {frame, Mark.generate(frame, hd(chart.marks), sources: @sources)}
    end

    defp angle_of(frame, t), do: Scale.apply(Frame.scale(frame, :angle), t)
    defp radius_of(frame, v), do: Scale.apply(Frame.scale(frame, :r), v)

    # Every point of a path's `M`/`L` commands.
    defp points(%Element{path: %Path{commands: commands}}) do
      for {c, x, y} <- commands, c in [:M, :L], do: {x, y}
    end

    test "a line over (t, v) wraps around the arc: every point at r(v)'s radius, within the sweep" do
      {frame, group} = polar(%{type: :line, channels: %{x: :t, y: :v}})
      [path] = group.children
      points = points(path)
      # Sampled at ≤ 2°: three segments over 240° give at least 120 points.
      assert length(points) >= 120

      # The first point is (t = 0, v = 4) bent; the last (t = 3, v = 7); everything lies
      # between the inner and outer radii and inside the sweep.
      {a0, r0} = {angle_of(frame, 0), radius_of(frame, 4)}
      assert hd(points) == Bend.point({a0, r0})
      assert List.last(points) == Bend.point({angle_of(frame, 3), radius_of(frame, 7)})

      for {x, y} <- points do
        r = :math.sqrt(x * x + y * y)
        assert r >= 30 - 1.0e-6 and r <= 150 + 1.0e-6
        angle = :math.atan2(x, -y)
        assert angle >= -2 * :math.pi() / 3 - 1.0e-6 and angle <= 2 * :math.pi() / 3 + 1.0e-6
      end

      # A curve is interpolated in (angle, r) before it bends: still within the band.
      {_frame, curved} =
        polar(%{type: :line, channels: %{x: :t, y: :v}, style: :bent}, %{
          styles: %{bent: %{curve: :monotone_x}}
        })

      [curve] = curved.children

      for {x, y} <- points(curve) do
        assert :math.sqrt(x * x + y * y) <= 150 + 1.0e-6
      end
    end

    test "a rule at x is a spoke over the r band, at y an arc at that radius; an x-band a wedge" do
      {frame, group} = polar(%{type: :rule, channels: %{x: :t}})
      assert length(group.children) == 4
      [first | _] = group.children
      [line | _] = first.children
      [{x0, y0} = inner, {x1, y1} = outer | _] = points(line)
      a = angle_of(frame, 0)
      assert inner == Bend.point({a, 30})
      assert outer == Bend.point({a, 150})
      assert_in_delta :math.sqrt(x0 * x0 + y0 * y0), 30, 1.0e-6
      assert_in_delta :math.sqrt(x1 * x1 + y1 * y1), 150, 1.0e-6

      {frame, arcs} = polar(%{type: :rule, channels: %{y: :v}})
      [ring | _] = arcs.children
      r = radius_of(frame, 4)

      for {x, y} <- points(ring), do: assert_in_delta(:math.sqrt(x * x + y * y), r, 1.0e-6)
      assert length(points(ring)) >= 120
      assert hd(points(ring)) == Bend.point({angle_of(frame, 0), r})

      {_frame, wedges} = polar(%{type: :x_band, channels: %{x0: :t, x1: :hi}})
      [wedge | _] = wedges.children
      [sector | _] = wedge.children
      assert %Element{type: :path, path: %Path{commands: commands}} = sector
      assert Enum.count(commands, &match?({:A, _, _, _, _, _, _, _}, &1)) == 2
      assert List.last(commands) == :Z
    end

    test "a rect with a band on y is an arced bar, with a band on x a sector; a circle stays a dot" do
      bars =
        polar(%{type: :rect, channels: %{x0: :t, x1: :hi, y0: :lo, y1: :lo}}, %{
          frames: %{
            main:
              put_in(@polar, [:scales, :r], %{kind: :band, domain: [3, 8, 1, 6], range: [30, 150]})
          }
        })

      {frame, group} = bars
      [bar | _] = group.children

      %Element{
        type: :path,
        path: %Path{
          commands: [
            {:M, _, _},
            {:A, ro, ro, 0, _, 1, _, _},
            {:L, _, _},
            {:A, ri, ri, 0, _, 0, _, _},
            :Z
          ]
        }
      } = bar

      band = Frame.scale(frame, :r)
      assert ri < ro
      assert_in_delta ro - ri, Scale.Band.bandwidth(band), 1.0e-6

      {frame, dots} = polar(%{type: :circle, channels: %{x: :t, y: :v}})
      [dot | _] = dots.children
      assert dot.type == :circle
      assert dot.attrs.r == 3
      assert {dot.attrs.cx, dot.attrs.cy} == Bend.point({angle_of(frame, 0), radius_of(frame, 4)})

      {_frame, symbols} = polar(%{type: :symbol, channels: %{x: :t, y: :v}})
      [symbol | _] = symbols.children
      assert %Visualize.IR.Transform{operations: [{:translate, tx, ty}]} = symbol.transform
      assert {tx, ty} == Bend.point({angle_of(frame, 0), radius_of(frame, 4)})
    end

    test "an arc's start and end read through the angle scale when the frame declares one, raw radians otherwise" do
      {frame, scaled} = polar(%{type: :arc, channels: %{start: :t, end: :hi}})
      [first | _] = scaled.children
      assert first.style == %{}
      {a0, _} = {angle_of(frame, 0), nil}
      # The centroid's angle is between start (t = 0) and end (hi = 5) as the scale maps them.
      %Element{path: %Path{commands: [{:M, mx, my} | _]}} = first
      assert_in_delta :math.atan2(mx, -my), a0, 1.0e-6

      raw_frame = %{
        kind: :polar,
        margin: %{top: 0, right: 0, bottom: 0, left: 0}
      }

      chart =
        chart(%{type: :arc, channels: %{start: :t, end: :hi}}, %{frames: %{main: raw_frame}})

      frame = Frame.new(chart, sources: @sources, size: {300, 200})
      raw = Mark.generate(frame, hd(chart.marks), sources: @sources)
      [first_raw | _] = raw.children
      %Element{path: %Path{commands: [{:M, rx, ry} | _]}} = first_raw
      # t = 0 radians: straight up.
      assert_in_delta :math.atan2(rx, -ry), 0, 1.0e-6
    end

    test "a mark's inline label anchors at the bent point, outward from the sector's radii" do
      {frame, group} =
        polar(%{
          type: :rect,
          channels: %{x0: :t, x1: :hi, y0: :lo, y1: :v},
          label: %{text: [{:field, :k}], anchor: :outward}
        })

      texts = labels(group)
      assert length(texts) == 4
      [text | _] = texts
      # Beyond the outer radius (v = 4 → r(4)), along the sector's centre ray.
      r = :math.sqrt(text.attrs.x * text.attrs.x + text.attrs.y * text.attrs.y)
      assert r > radius_of(frame, 4)
    end

    test "a needle points from the hub to the value's angle, its label beyond the tip; three rows three needles (#392)" do
      {frame, group} =
        polar(%{
          type: :needle,
          channels: %{x: :t, y: :v},
          options: %{width: 8, tail: 10, hub: 5, cap: :round},
          label: %{text: [{:field, :k}]}
        })

      needles = Enum.filter(flat(group).children, &(&1.type == :group))
      assert length(needles) == 4
      [first | _] = needles
      assert first.style == %{class: "needle"}
      [pointer, hub] = first.children
      # The pointer's tip is at (angle(0), r(4)); the hub is a circle of 5 about the origin.
      %Element{path: %Path{commands: commands}} = pointer
      a = angle_of(frame, 0)
      r = radius_of(frame, 4)
      assert Enum.count(commands, &match?({:A, h, h, _, _, _, _, _} when h == 4, &1)) == 1
      # The round cap's corner: at the length, half the width across the ray.
      assert {:L, lx, ly} = Enum.at(commands, 2)
      assert_in_delta :math.sqrt(lx * lx + ly * ly), :math.sqrt(r * r + 16), 1.0e-3
      assert_in_delta :math.atan2(lx, -ly), a, 0.1
      assert %Element{path: %Path{commands: [{:M, -5.0, +0.0} | _]}} = hub

      # The label sits outward of the tip by default.
      [text | _] = labels(group)
      assert :math.sqrt(text.attrs.x * text.attrs.x + text.attrs.y * text.attrs.y) > r

      # Without y the needle reaches the outer radius; the group is not bent again.
      {_frame, long} = polar(%{type: :needle, channels: %{x: :t}})
      [%{children: [pointer | _]} | _] = long.children
      %Element{path: %Path{commands: [_, _, {:L, tx, ty} | _]}} = pointer
      assert_in_delta :math.sqrt(tx * tx + ty * ty), 150, 1.0e-3
    end

    test "the radar: chords over a categorical angle, closed on a full turn, series layered in order; step_after as arcs (#393)" do
      six = ~w(a b c d e f)

      radar = fn mark, extra ->
        frame =
          @polar
          |> put_in([:scales, :angle], %{kind: :band, domain: six})
          |> put_in([:scales, :r], %{kind: :linear, domain: [0, 10]})

        chart = chart(mark, Map.merge(%{frames: %{main: frame}}, extra))
        rows = for {k, i} <- Enum.with_index(six), s <- ["p", "q"], do: %{k: k, v: 2 + i, s: s}
        frame = Frame.new(chart, sources: %{primary: rows}, size: {300, 200})
        {frame, Mark.generate(frame, hd(chart.marks), sources: %{primary: rows})}
      end

      {frame, lines} =
        radar.(%{type: :line, channels: %{x: :k, y: :v, series: :s}, style: :faint}, %{
          styles: %{faint: %{stroke_width: 1}}
        })

      [p, q] = lines.children
      assert p.attrs == %{"data-series": "p"} or p.attrs["data-series"] == "p"
      %Element{path: %Path{commands: commands}} = p
      # Six chords and the closing one back to the first point: seven L after the M.
      assert Enum.map(commands, &elem(&1, 0)) == [:M | List.duplicate(:L, 6)]
      {:M, mx, my} = hd(commands)
      assert {:L, ^mx, ^my} = List.last(commands)
      band = Frame.scale(frame, :angle)

      first =
        Bend.point({Scale.apply(band, "a") + Scale.Band.bandwidth(band) / 2, radius_of(frame, 2)})

      assert {mx, my} == first
      assert q.attrs["data-series"] == "q"

      # Not closed when asked: the twelve rows (two per category), no return.
      {_frame, open} =
        radar.(%{type: :line, channels: %{x: :k, y: :v}, options: %{closed: false}}, %{})

      [path] = open.children
      assert length(path.path.commands) == 12

      # The area's volumes, one per series in series order, each closed.
      {_frame, areas} = radar.(%{type: :area, channels: %{x: :k, y: :v, series: :s}}, %{})
      [pa, qa] = areas.children
      assert pa.attrs["data-series"] == "p" and qa.attrs["data-series"] == "q"
      assert List.last(pa.path.commands) == :Z
      assert Enum.count(pa.path.commands, &match?({:L, _, _}, &1)) >= 7

      # A closed curve closes itself: no row appended, n curves and a Z.
      {_frame, smooth} =
        radar.(%{type: :line, channels: %{x: :k, y: :v}, style: :loop}, %{
          styles: %{loop: %{curve: :cardinal_closed}}
        })

      [loop] = smooth.children
      # Twelve curves sampled at eight points or more, then the close; no chord.
      assert Enum.count(loop.path.commands, &match?({:L, _, _}, &1)) >= 96
      assert List.last(loop.path.commands) == :Z

      # step_after steps along an arc: many sampled points at each radius.
      {_frame, stepped} =
        radar.(%{type: :line, channels: %{x: :k, y: :v}, style: :arcs}, %{
          styles: %{arcs: %{curve: :step_after}}
        })

      [arcs] = stepped.children
      assert length(arcs.path.commands) > 6 * 10
    end

    test "the bend is a pure function of the elements: relative commands, curves and rects" do
      bent =
        Bend.bend(%Element{
          type: :path,
          path: %Path{
            commands: [{:M, 0, 10}, {:l, :math.pi() / 2, 0}, {:c, 0, 5, 0.5, 5, 0.5, 5}, :Z]
          }
        })

      assert [{:M, +0.0, -10.0} | rest] = bent.path.commands
      assert List.last(rest) == :Z
      # 45 samples over the quarter turn, then at least 8 for the curve.
      assert length(rest) >= 45 + 8 + 1
      rect = Bend.bend(Element.rect(0, 10, :math.pi() / 2, 5))
      assert rect.type == :path
      assert rect.attrs == %{}

      assert rect.path.commands == [
               {:M, 0.0, -15.0},
               {:A, 15, 15, 0, 0, 1, 15.0, 0.0},
               {:L, 10.0, 0.0},
               {:A, 10, 10, 0, 0, 0, 0.0, -10.0},
               :Z
             ]

      wedge = Bend.bend(Element.rect(0, 0, :math.pi(), 5))

      assert wedge.path.commands == [
               {:M, 0.0, -5.0},
               {:A, 5, 5, 0, 0, 1, 0.0, 5.0},
               {:L, 0, 0},
               :Z
             ]

      assert Bend.bend(Element.text("t", x: :math.pi() / 2, y: 4)).attrs == %{x: 4.0, y: 0.0}
    end
  end
end
