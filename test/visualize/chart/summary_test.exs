defmodule Visualize.Chart.SummaryTest do
  @moduledoc """
  A chart's text alternative (spec/14 §21, #557, D-142): the summary generated from the
  design and its data — name, kind, series, axes and extremes — the data-table fallback
  beside the chart, and the canvas and hybrid layers that carry the summary.
  """
  use ExUnit.Case, async: true

  doctest Visualize.Chart.Summary

  alias Visualize.Backend.{Canvas, Hybrid}
  alias Visualize.Chart
  alias Visualize.Chart.Summary

  defp applied(design, sources, opts \\ []) do
    design = Map.merge(%{version: 2}, design)
    {:ok, applied} = Chart.apply(design, [sources: sources, size: {400, 300}] ++ opts)
    applied
  end

  defp cartesian(scales, axes, marks, extra \\ %{}) do
    Map.merge(
      %{
        sources: %{s: %{fields: [:name, :x, :y]}},
        frames: %{main: %{kind: :cartesian, scales: scales, axes: axes}},
        marks: marks
      },
      extra
    )
  end

  defp kind(design, sources), do: hd(Summary.new(applied(design, sources)).frames).kind

  @rows [%{name: "a", x: 1, y: 4}, %{name: "b", x: 2, y: 9}, %{name: "c", x: 3, y: 2}]

  describe "the name and the kind (§21.1)" do
    test "the design's name, else the kind, capitalized" do
      line =
        cartesian(%{x: %{kind: :linear}, y: %{kind: :linear}}, [], [
          %{type: :line, data: :s, channels: %{x: :x, y: :y}}
        ])

      assert Summary.new(applied(line, %{s: @rows})).name == "Line chart"

      named = Map.put(line, :meta, %{name: "Rain", description: ""})
      assert Summary.new(applied(named, %{s: @rows})).name == "Rain"
    end

    test "a bar has a band edge and a baseline; a heatmap's cells read a field at both ends" do
      scales = %{x: %{kind: :band}, y: %{kind: :linear}}

      bar = %{type: :rect, data: :s, channels: %{x0: :name, x1: :name, y0: 0, y1: :y}}
      assert kind(cartesian(scales, [], [bar]), %{s: @rows}) == "bar chart"

      cells = %{
        type: :rect,
        data: :s,
        channels: %{x0: :name, x1: :name, y0: :x, y1: :y, value: :y}
      }

      assert kind(cartesian(scales, [], [cells]), %{s: @rows}) == "heatmap"

      linear = %{x: %{kind: :linear}, y: %{kind: :linear}}
      boxes = %{type: :rect, data: :s, channels: %{x0: :x, x1: :x, y0: :y, y1: :y}}
      assert kind(cartesian(linear, [], [boxes]), %{s: @rows}) == "rectangle chart"
    end

    test "points are a scatter plot, sized points a bubble chart, a needle a gauge" do
      linear = %{x: %{kind: :linear}, y: %{kind: :linear}}
      dots = %{type: :circle, data: :s, channels: %{x: :x, y: :y}}
      assert kind(cartesian(linear, [], [dots]), %{s: @rows}) == "scatter plot"

      sized = put_in(dots, [:channels, :value], :y)
      assert kind(cartesian(linear, [], [sized]), %{s: @rows}) == "bubble chart"

      gauge = %{
        sources: %{s: %{fields: [:v]}},
        frames: %{main: %{kind: :polar, scales: %{angle: %{kind: :linear, domain: [0, 10]}}}},
        marks: [%{type: :needle, data: :s, channels: %{x: :v}}]
      }

      assert kind(gauge, %{s: [%{v: 4}]}) == "gauge"
    end

    test "an arc is a pie, with an inner radius a donut" do
      pie = %{
        sources: %{s: %{fields: [:name, :v]}},
        frames: %{main: %{kind: :polar}},
        marks: [%{type: :arc, data: :s, channels: %{value: :v}}]
      }

      rows = [%{name: "a", v: 3}, %{name: "b", v: 1}]
      assert kind(pie, %{s: rows}) == "pie chart"

      donut = %{pie | marks: [Map.put(hd(pie.marks), :options, %{inner_radius: 40})]}

      assert kind(donut, %{s: rows}) == "donut chart"
    end
  end

  describe "axes, series and extremes (§21.1)" do
    test "an axis says its range, a band axis its categories, and a label anchored at it titles it" do
      design =
        cartesian(
          %{x: %{kind: :band}, y: %{kind: :linear, domain: [0, 10]}},
          [%{scale: :x, side: :bottom}, %{scale: :y, side: :left}],
          [%{type: :rect, data: :s, channels: %{x0: :name, x1: :name, y0: 0, y1: :y}}],
          %{labels: [%{anchor: {:axis, :y}, text: "Rainfall"}]}
        )

      text = Summary.text(applied(design, %{s: @rows}))

      assert text ==
               "Bar chart, 1 series (y) of 3 bars. Bottom axis name, 3 categories: a, b and c. " <>
                 "Left axis Rainfall, from 0 to 10. Highest y 9 at name b; lowest y 2 at name c."
    end

    test "a value is written in its axis's measure, to four significant digits, not at the ticks' step" do
      design =
        cartesian(
          %{x: %{kind: :linear}, y: %{kind: :linear}},
          [%{scale: :x, side: :bottom}, %{scale: :y, side: :left, measure: %{unit: "ms"}}],
          [%{type: :line, data: :s, channels: %{x: :x, y: :y}}]
        )

      rows = [
        %{name: "a", x: 0, y: 1234.6},
        %{name: "b", x: 1, y: 2500},
        %{name: "c", x: 2, y: 1500}
      ]

      text = Summary.text(applied(design, %{s: rows}))

      assert text =~ "Left axis ms, from 1.235 s to 2.5 s."
      assert text =~ "Highest y 2.5 s at x 1; lowest y 1.235 s at x 0."
    end

    test "a series channel lists its values, and the extremes say which series" do
      design =
        cartesian(%{x: %{kind: :linear}, y: %{kind: :linear}}, [], [
          %{type: :line, data: :s, channels: %{x: :x, y: :y, series: :name}}
        ])

      rows = [
        %{x: 0, y: 1, name: "north"},
        %{x: 1, y: 5, name: "south"},
        %{x: 1, y: 3, name: "north"}
      ]

      text = Summary.text(applied(design, %{s: rows}))

      assert text =~ "Line chart, 2 series: north and south."
      assert text =~ "Highest y 5 at x 1 in south; lowest y 1 at x 0 in north."
    end

    test "marks that draw one value on one scale say one highest and one lowest" do
      mark = &%{type: :line, data: &1, channels: %{x: :x, y: :y}}

      design = %{
        sources: %{a: %{fields: [:x, :y]}, b: %{fields: [:x, :y]}},
        frames: %{main: %{kind: :cartesian, scales: %{x: %{kind: :linear}, y: %{kind: :linear}}}},
        marks: [mark.(:a), mark.(:b)]
      }

      sources = %{a: [%{x: 0, y: 3}, %{x: 1, y: 4}], b: [%{x: 0, y: 9}, %{x: 1, y: 1}]}
      [frame] = Summary.new(applied(design, sources)).frames

      assert [%{field: "y", rows: 4, high: {"9", "x 0"}, low: {"1", "x 1"}}] = frame.extremes
    end

    test "a value of one row says that row; an empty chart says it has none" do
      design =
        cartesian(%{x: %{kind: :linear}, y: %{kind: :linear}}, [], [
          %{type: :symbol, data: :s, channels: %{x: :x, y: :y}}
        ])

      assert Summary.text(applied(design, %{s: [%{name: "a", x: 1, y: 7}]})) =~ "Y 7 at x 1."
      assert Summary.text(applied(design, %{s: []})) == "Scatter plot, 0 points."
    end

    test "a design of several frames says each frame's name first, in drawing order" do
      line = fn frame -> %{type: :line, data: :s, frame: frame, channels: %{x: :x, y: :y}} end
      scales = %{x: %{kind: :linear}, y: %{kind: :linear}}

      design = %{
        sources: %{s: %{fields: [:x, :y]}},
        frames: %{
          now: %{kind: :cartesian, box: [0.5, 0, 0.5, 1], scales: scales},
          history: %{kind: :cartesian, box: [0, 0, 0.5, 1], scales: scales}
        },
        marks: [line.(:now), line.(:history)]
      }

      text = Summary.text(applied(design, %{s: @rows}))
      assert text =~ ~r/^History: Line chart, .* Now: Line chart, /
    end
  end

  describe "the data table (§21.3)" do
    defp bars do
      cartesian(
        %{x: %{kind: :band}, y: %{kind: :linear}},
        [%{scale: :y, side: :left, unit: "%"}],
        [%{type: :rect, data: :s, channels: %{x0: :name, x1: :name, y0: 0, y1: :y}}],
        %{meta: %{name: "Votes & seats"}}
      )
    end

    test "one table per data mark: a caption, scoped headers by field, values as the axis writes them" do
      html =
        Summary.table(
          applied(bars(), %{s: [%{name: "<b>", x: 0, y: 12.345}, %{name: "c", x: 1, y: 3}]})
        )

      assert html =~ ~s(<div class="vis-data-table" style="position:absolute;width:1px;)
      assert html =~ "<caption>Votes &amp; seats</caption>"
      assert html =~ ~s(<th scope="col">name</th><th scope="col">y</th>)
      assert html =~ "<tr><td>&lt;b&gt;</td><td>12.35%</td></tr><tr><td>c</td><td>3%</td></tr>"
    end

    test "the options: shown, an id, a class, a caption, and a limit that says what it left out" do
      rows = for i <- 1..5, do: %{name: "n#{i}", x: i, y: i}

      html =
        Summary.table(applied(bars(), %{s: rows}),
          hidden: false,
          id: "t",
          class: "data",
          caption: "Votes",
          limit: 2
        )

      assert html =~ ~s(<div class="data" id="t">)
      refute html =~ "position:absolute"
      assert html =~ "<caption>Votes (the first 2 of 5 rows)</caption>"
      assert length(Regex.scan(~r/<tr><td>/, html)) == 2
    end

    test "a mark repeating another's table is left out, and a layout's pixels are not a column" do
      twice = Map.update!(bars(), :marks, &(&1 ++ &1))
      html = Summary.table(applied(twice, %{s: @rows}))
      assert length(Regex.scan(~r/<table>/, html)) == 1

      pixels = cartesian(%{}, [], [%{type: :circle, data: :s, channels: %{x: :x, y: :y}}])
      assert Summary.table(applied(pixels, %{s: @rows})) =~ ~r/<div [^>]*><\/div>$/
    end
  end

  describe "an element that stands for the chart (§21.4)" do
    test "attrs/2 and description/2 name and describe it, escaped" do
      summary = %Summary{name: "A & B", frames: []}

      assert Summary.attrs(summary, "c") ==
               [role: "img", "aria-label": "A & B", "aria-describedby": "c-summary"]

      design =
        cartesian(%{x: %{kind: :linear}, y: %{kind: :linear}}, [], [
          %{type: :line, data: :s, channels: %{x: :x, y: :y}}
        ])

      summary = Summary.new(applied(design, %{s: @rows}))
      assert Summary.description(summary, "c") =~ ~r/^<p id="c-summary" hidden>Line chart, /
    end

    test "a canvas root is named by the title and described by its fallback content" do
      html =
        IO.iodata_to_binary(
          Canvas.wrap_root("", canvas_id: "k", title: "A < B", description: "x & y")
        )

      assert html =~
               ~s(<canvas id="k" width="800" height="600" role="img" aria-label="A &lt; B" aria-describedby="k-summary"><p id="k-summary">x &amp; y</p></canvas>)

      assert IO.iodata_to_binary(Canvas.wrap_root("", [])) =~
               ~s(<canvas id="visualize-canvas" width="800" height="600"></canvas>)
    end

    test "a hybrid chart names its canvas and hides its SVG layer" do
      out =
        Hybrid.render(width: 100, height: 50, title: "Load", description: "Low", canvas_id: "h")

      assert out.svg =~ ~s(<svg aria-hidden="true")

      assert out.html =~
               ~s(role="img" aria-label="Load" aria-describedby="h-summary"><p id="h-summary">Low</p></canvas>)

      assert Hybrid.render_static(width: 100, height: 50) =~ ~s(aria-hidden="true")
    end
  end
end
