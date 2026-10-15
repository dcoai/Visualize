defmodule Visualize.Chart.FrameTest do
  @moduledoc """
  The realized frame of spec/14 §4 and D-60: inference of `:auto` domains from the whole
  bound column by kind (numeric, time, categorical, collapsed, unbound), the precedence
  of an explicit domain, a half-fixed extent and `put_scale/3`, the ranges by name, the
  errors a frame raises, and the byte identity of a frame's furniture with the same
  furniture built by hand from `Visualize.Axis` and `Visualize.IR.Element`.
  """
  use ExUnit.Case, async: true

  alias Visualize.{Axis, Chart, Render, Scale, Theme}
  alias Visualize.Chart.{Compiled, Frame}
  alias Visualize.Chart.Frame.Legend

  doctest Frame
  alias Visualize.IR.{Element, Transform}
  alias Visualize.Work

  @t0 ~U[2024-01-01 00:00:00Z]
  @rows for {v, h} <- Enum.with_index([4, 9, 2, 7]),
            do: %{t: DateTime.add(@t0, h * 3600, :second), v: v, n: h, k: "c#{rem(h, 2)}"}

  # The size the suite's fixtures were written against; a design records none (§4.2).
  @size {300, 200}

  defp chart(frame, extra \\ %{}) do
    Chart.from_map!(
      Map.merge(
        %{
          version: 2,
          sources: %{primary: %{fields: [:t, :v, :n, :k]}},
          frames: %{main: Map.merge(%{kind: :cartesian}, frame)}
        },
        extra
      )
    )
  end

  defp line(channels), do: %{type: :line, data: :primary, channels: channels}

  defp frame(scales, marks, sources \\ %{primary: @rows}) do
    Frame.new(chart(%{scales: scales}, %{marks: marks}), sources: sources, size: @size)
  end

  describe "inference" do
    test "a numeric column gives its extent, whole column" do
      frame = frame(%{x: %{kind: :linear}, y: %{kind: :linear}}, [line(%{x: :n, y: :v})])
      assert Frame.scale(frame, :x).domain == [0, 3]
      assert Frame.scale(frame, :y).domain == [2, 9]
    end

    test "a time column gives its extent under time order, ISO strings parsed" do
      frame = frame(%{x: %{kind: :time}, y: %{kind: :linear}}, [line(%{x: :t, y: :v})])
      assert Frame.scale(frame, :x).domain == [@t0, DateTime.add(@t0, 3 * 3600, :second)]

      rows = [%{t: "2024-03-01T00:00:00Z", v: 1}, %{t: "2024-01-15T00:00:00Z", v: 2}]

      frame =
        frame(%{x: %{kind: :time}, y: %{kind: :linear}}, [line(%{x: :t, y: :v})], %{primary: rows})

      assert Frame.scale(frame, :x).domain == [~U[2024-01-15 00:00:00Z], ~U[2024-03-01 00:00:00Z]]
    end

    test "a categorical column gives the distinct values in first-appearance order" do
      frame = frame(%{x: %{kind: :band}, y: %{kind: :linear}}, [line(%{x: :k, y: :v})])
      assert Frame.scale(frame, :x).domain == ["c0", "c1"]
    end

    test "a collapsed extent stays collapsed and the scale maps to the midpoint (D-49)" do
      rows = [%{n: 5, v: 5}]

      frame =
        frame(%{x: %{kind: :linear}, y: %{kind: :linear}}, [line(%{x: :n, y: :v})], %{
          primary: rows
        })

      scale = Frame.scale(frame, :x)
      assert scale.domain == [5, 5]
      assert Scale.apply(scale, 5) == 120.0
      assert Scale.ticks(scale, 5) == [5]
    end

    test "nothing bound gives the unit domain, so a frame renders without a source" do
      scales = %{x: %{kind: :linear}, t: %{kind: :time}, k: %{kind: :band}, l: %{kind: :log}}
      frame = frame(scales, [line(%{x: :n, y: :v})], %{})
      assert Frame.scale(frame, :x).domain == [0, 1]
      assert Frame.scale(frame, :t).domain == [~U[1970-01-01 00:00:00Z], ~U[1970-01-02 00:00:00Z]]
      assert Frame.scale(frame, :k).domain == []
      assert Frame.scale(frame, :l).domain == [1, 10]
      assert is_binary(Frame.render(frame))
    end

    test "every channel naming the scale contributes, as does a color field in a style" do
      marks = [
        %{type: :area, data: :primary, channels: %{x: :n, y: :v, y0: 0}},
        %{type: :rule, data: :primary, channels: %{x: 10}, style: :by_k}
      ]

      styles = %{by_k: %{fill: {:field, :k}}}

      frame =
        Frame.new(
          chart(
            %{scales: %{x: %{kind: :linear}, y: %{kind: :linear}, color: %{kind: :ordinal}}},
            %{
              marks: marks,
              styles: styles
            }
          ),
          sources: %{primary: @rows},
          size: @size
        )

      assert Frame.scale(frame, :x).domain == [0, 10]
      assert Frame.scale(frame, :y).domain == [0, 9]
      assert Frame.scale(frame, :color).domain == ["c0", "c1"]
    end

    test "a mark's scales node sends a channel family to the scale it names (D-67)" do
      marks = [
        line(%{x: :t, y: :v}),
        %{
          type: :rect,
          data: :primary,
          channels: %{x0: 0, x1: :n, y0: :v, y1: :v},
          scales: %{x: :count}
        }
      ]

      scales = %{
        x: %{kind: :time},
        y: %{kind: :linear},
        count: %{kind: :linear, domain: [0, :auto], range: [0, 120]}
      }

      frame = frame(scales, marks)
      assert Frame.scale(frame, :count).domain == [0, 3]
      assert Frame.scale(frame, :count).range == [0, 120]
      assert Frame.scale(frame, :x).domain == [@t0, DateTime.add(@t0, 3 * 3600, :second)]
    end

    test "a constant channel contributes its number only when the mark has rows (#61)" do
      marks = [%{type: :rect, data: :primary, channels: %{x0: :k, x1: :k, y0: 0, y1: :v}}]
      scales = %{x: %{kind: :band}, y: %{kind: :linear, domain: [0, :auto]}}
      assert Frame.scale(frame(scales, marks), :y).domain == [0, 9]
      assert Frame.scale(frame(scales, marks, %{primary: []}), :y).domain == [0, 1]
    end

    test "a polar frame maps angle and value onto its own scales" do
      chart =
        chart(%{kind: :polar, scales: %{angle: %{kind: :radial}, r: %{kind: :sqrt}}}, %{
          marks: [%{type: :rose, data: :primary, channels: %{angle: :n, value: :v}}]
        })

      frame = Frame.new(chart, sources: %{primary: @rows}, size: @size)
      assert Frame.scale(frame, :angle).domain == [0, 3]
      assert Frame.scale(frame, :r).domain == [2, 9]
      assert Frame.scale(frame, :r).range == [0, 75.0]
    end
  end

  describe "the polar axes follow their scales' ranges (spec/14 §4.3, §4.4, §4.6, #390)" do
    defp polar(scales, axes) do
      chart(
        %{
          kind: :polar,
          margin: %{top: 0, right: 0, bottom: 0, left: 0},
          scales: scales,
          axes: axes
        },
        %{marks: [%{type: :rose, data: :primary, channels: %{angle: :n, value: :v}}]}
      )
      |> Frame.new(sources: %{primary: @rows}, size: {300, 300})
    end

    defp polar_svg(scales, axes),
      do: polar(scales, axes) |> Frame.render(sources: %{primary: @rows}, size: @size)

    test "start and sweep realize the angle range in radians; a list range wins; a full turn is the default" do
      quarter = %{
        angle: %{kind: :linear, domain: [0, 100], start: -90, sweep: 90},
        r: %{kind: :linear}
      }

      [a0, a1] = Frame.scale(polar(quarter, []), :angle).range
      assert_in_delta a0, -:math.pi() / 2, 1.0e-9
      assert_in_delta a1, 0, 1.0e-9

      back = %{angle: %{kind: :linear, domain: [0, 100], sweep: -90}, r: %{kind: :linear}}
      [b0, b1] = Frame.scale(polar(back, []), :angle).range
      assert b0 == 0
      assert_in_delta b1, -:math.pi() / 2, 1.0e-9

      listed = %{angle: %{kind: :linear, start: 45, range: [1, 2]}, r: %{kind: :linear}}
      assert Frame.scale(polar(listed, []), :angle).range == [1, 2]

      plain = %{angle: %{kind: :linear}, r: %{kind: :linear}}
      assert Frame.scale(polar(plain, []), :angle).range == [0, 2 * :math.pi()]
    end

    test "the angle axis is an arc over the sweep at its radius, a circle on a full turn; the r grid arcs too" do
      # A speedometer: 240° from -120°, the axis at 0.8 R, the r grid over the sweep.
      scales = %{
        angle: %{kind: :linear, domain: [0, 100], start: -120, sweep: 240},
        r: %{kind: :linear, domain: [0, 10], range: [30, 150]}
      }

      svg =
        polar_svg(scales, [
          %{scale: :angle, side: :bottom, ticks: 2, radius: 0.8, grid: true},
          %{scale: :r, side: :top, ticks: 2, grid: true, at: 120}
        ])

      # The domain line: from -120° to 120° at 120 (0.8 × 150), the large arc, clockwise.
      assert svg =~
               ~s|<path d="M-103.923,60A120,120,0,1,1,103.923,60" stroke="var(--vis-axis, #666666)"/>|

      refute svg =~ ~s|<circle cx="0" cy="0" r="120|
      # The angle grid's spokes run over the r band, 30 to 150.
      assert svg =~ ~s|<line x1="-25.98075" x2="-129.90375" y1="15.0" y2="75.0"/>|
      # The r grid at 10 is an arc at 150 over the sweep, not a ring.
      assert svg =~ ~s|<path d="M-129.9038,75A150,150,0,1,1,129.9038,75" fill="none"/>|
      # The r spoke stands at 120° and runs from the inner radius to the outer.
      assert svg =~
               ~s|<line stroke="var(--vis-axis, #666666)" x1="25.98075" x2="129.90375" y1="15.0" y2="75.0"/>|

      # A quarter turn is a small arc; a full turn is the circle it was.
      quarter =
        polar_svg(%{angle: %{kind: :linear, start: -90, sweep: 90}, r: %{kind: :linear}}, [
          %{scale: :angle, side: :bottom, ticks: 2}
        ])

      assert quarter =~ ~s|<path d="M-150,0A150,150,0,0,1,0,-150"|

      full =
        polar_svg(%{angle: %{kind: :linear}, r: %{kind: :linear}}, [
          %{scale: :angle, side: :bottom, ticks: 2},
          # Ten ticks, as before the count was derived (D-134), so one lands on R.
          %{scale: :r, side: :top, ticks: 10, grid: true}
        ])

      assert full =~ ~s|<circle cx="0" cy="0" r="150.0" stroke=|
      [grid | _] = String.split(full, ~s|<g class="mark|)
      refute grid =~ "<path"
      assert grid =~ ~s|<circle cx="0" cy="0" fill="none" r="150.0"/>|
    end
  end

  describe "a categorical angle (spec/14 §4.3, #393)" do
    test "a band on angle is widened by half a step: six categories 60° apart on a full turn, the ring closed; 36° apart ends-inclusive on a half turn" do
      six = ~w(a b c d e f)
      full = polar(%{angle: %{kind: :band, domain: six}, r: %{kind: :linear}}, [])
      band = Frame.scale(full, :angle)
      [a0, a1] = band.range
      assert_in_delta a0, -:math.pi() / 6, 1.0e-9
      assert_in_delta a1, 2 * :math.pi() - :math.pi() / 6, 1.0e-9
      centers = for k <- six, do: Scale.apply(band, k) + Scale.Band.bandwidth(band) / 2
      assert_in_delta hd(centers), 0, 1.0e-9
      assert_in_delta Enum.at(centers, 1), :math.pi() / 3, 1.0e-9
      assert_in_delta List.last(centers), 5 * :math.pi() / 3, 1.0e-9

      half =
        polar(
          %{angle: %{kind: :band, domain: six, start: -90, sweep: 180}, r: %{kind: :linear}},
          []
        )

      band = Frame.scale(half, :angle)
      centers = for k <- six, do: Scale.apply(band, k) + Scale.Band.bandwidth(band) / 2
      assert_in_delta hd(centers), -:math.pi() / 2, 1.0e-9
      assert_in_delta List.last(centers), :math.pi() / 2, 1.0e-9
      assert_in_delta Enum.at(centers, 1) - hd(centers), :math.pi() / 5, 1.0e-9

      # The axis ticks every category at its center: the first straight up at R.
      svg =
        chart(
          %{
            kind: :polar,
            margin: %{top: 0, right: 0, bottom: 0, left: 0},
            scales: %{angle: %{kind: :band, domain: six}, r: %{kind: :linear}},
            axes: [%{scale: :angle, side: :bottom, grid: true}]
          },
          %{marks: []}
        )
        |> Frame.new(size: {300, 300})
        |> Frame.render()

      assert svg =~
               ~s|<line stroke="var(--vis-axis, #666666)" x1="0.0" x2="0.0" y1="-150.0" y2="-156.0"/><text dy="0.32em" fill="var(--vis-text, #333333)" x="0.0" y="-159.0">a</text>|

      assert length(Regex.scan(~r/class="tick"/, svg)) == 6
    end
  end

  describe "only a scale that infers reads a column (spec/14 §4.3, #409)" do
    test "a domain given by the caller stands in for the inference" do
      scales = %{x: %{kind: :linear}, y: %{kind: :linear}}
      marks = [%{type: :line, data: :primary, channels: %{x: :n, y: :v}}]
      chart = chart(%{scales: scales}, %{marks: marks})

      inferred = Frame.new(chart, sources: %{primary: @rows}, size: @size)
      assert Frame.scale(inferred, :x).domain == [0, 3]

      given = Frame.new(chart, sources: %{primary: @rows}, domains: %{x: [10, 20]}, size: @size)
      assert Frame.scale(given, :x).domain == [10, 20]
      # Every other scale is inferred as before.
      assert Frame.scale(given, :y).domain == Frame.scale(inferred, :y).domain
    end

    test "a chart whose domains are all fixed does not walk its rows" do
      scales = %{x: %{kind: :linear, domain: [0, 1]}, y: %{kind: :linear, domain: [0, 1]}}
      marks = [%{type: :line, data: :primary, channels: %{x: :n, y: :v}}]
      chart = chart(%{scales: scales}, %{marks: marks})
      few = for t <- 1..20, do: %{n: t, v: rem(t, 97)}
      many = for t <- 1..200_000, do: %{n: t, v: rem(t, 97)}

      {few_work, _} =
        Work.reductions(fn -> Frame.new(chart, sources: %{primary: few}, size: @size) end)

      {many_work, frame} =
        Work.reductions(fn -> Frame.new(chart, sources: %{primary: many}, size: @size) end)

      assert Frame.scale(frame, :x).domain == [0, 1]

      # Gathering the columns of 200,000 rows for scales that cannot use them is millions
      # of reductions; not gathering them costs what twenty rows cost. Counted, not timed
      # (spec/12 §6, D-114).
      assert many_work < few_work * 2,
             "a fixed-domain frame over 200,000 rows cost #{many_work} reductions against #{few_work} over 20"
    end
  end

  describe "precedence" do
    test "an explicit domain beats inference and a half-fixed extent fixes one end" do
      scales = %{x: %{kind: :linear, domain: [0, 100]}, y: %{kind: :linear, domain: [0, :auto]}}
      frame = frame(scales, [line(%{x: :n, y: :v})])
      assert Frame.scale(frame, :x).domain == [0, 100]
      assert Frame.scale(frame, :y).domain == [0, 9]

      frame = frame(%{y: %{kind: :linear, domain: [:auto, 20]}}, [line(%{x: :n, y: :v})])
      assert Frame.scale(frame, :y).domain == [2, 20]
    end

    test "nice widens an inferred domain and put_scale/3 replaces it afterwards" do
      rows = [%{n: 1, v: 97}, %{n: 2, v: 3}]

      frame =
        frame(%{y: %{kind: :linear, domain: [0, :auto], nice: true}}, [line(%{x: :n, y: :v})], %{
          primary: rows
        })

      assert Frame.scale(frame, :y).domain == [0.0, 100.0]

      replaced = Scale.linear() |> Scale.domain([0, 50]) |> Scale.range([150, 0])
      frame = Frame.put_scale(frame, :y, replaced)
      assert Frame.scales(frame) == %{y: replaced}
    end

    test "an axis's explicit tick values beat its count, which beats the derived count" do
      axes = fn ticks -> [%{scale: :x, side: :bottom, ticks: ticks}] end

      count = fn frame ->
        frame |> Frame.render() |> String.split(~s(class="tick")) |> length() |> Kernel.-(1)
      end

      base = %{scales: %{x: %{kind: :linear, domain: [0, 100]}}}

      assert count.(Frame.new(chart(Map.put(base, :axes, axes.([0, 50]))), size: @size)) == 2
      assert count.(Frame.new(chart(Map.put(base, :axes, axes.(3))), size: @size)) == 3

      assert count.(
               Frame.new(chart(Map.put(base, :axes, axes.(%{count: 3, values: [1, 2, 3, 4]}))),
                 size: @size
               )
             ) == 4

      assert count.(
               Frame.new(chart(Map.put(base, :axes, [%{scale: :x, side: :bottom}])), size: @size)
             ) == 3
    end
  end

  describe "ranges by name" do
    test "position names take the plot area, a discrete color the theme's series and a sequential one its ramp" do
      scales = %{
        x: %{kind: :linear},
        y: %{kind: :linear},
        color: %{kind: :ordinal, domain: [:a, :b]},
        heat: %{kind: :sequential},
        other: %{kind: :linear}
      }

      frame =
        Frame.new(chart(%{scales: scales, axes: [%{scale: :other, side: :right}]}), size: @size)

      assert Frame.scale(frame, :x).range == [0, 240]
      assert Frame.scale(frame, :y).range == [150, 0]
      assert Frame.scale(frame, :color).range == Enum.map(1..10, &:"series_#{&1}")
      assert Frame.scale(frame, :other).range == [150, 0]
      assert Scale.apply(Frame.scale(frame, :color), :b) == :series_2
      # A sequential scale's :auto range is the theme's sequential ramp (spec/14 §4.3, D-135).
      assert Scale.apply(Frame.scale(frame, :heat), 0) == "#e9f2fc"
      assert Scale.apply(Frame.scale(frame, :heat), 1) == "#004580"
    end

    test "a scheme name is its stops and a list is used as given" do
      scales = %{
        c: %{kind: :ordinal, domain: [1, 2], range: :category10},
        d: %{kind: :linear, range: [5, 6]}
      }

      frame = Frame.new(chart(%{scales: scales}), size: @size)
      assert Frame.scale(frame, :c).range == Scale.Color.scheme(:category10)
      assert Frame.scale(frame, :d).range == [5, 6]
    end
  end

  describe "errors" do
    test "an unresolved variable, an unknown theme and a bad value are ArgumentErrors" do
      var = Chart.var(:unit)

      assert_raise ArgumentError, ~r/variable :unit is unresolved/, fn ->
        chart(%{}, %{vars: %{unit: %{}}, labels: [%{anchor: :title, text: [var]}]})
        |> Frame.new(size: @size)
        |> Frame.generate()
      end

      assert_raise ArgumentError, ~r/theme :house is neither built-in/, fn ->
        Frame.new(chart(%{}, %{theme: :house}), size: @size)
      end

      assert %Frame{theme: %Theme{name: :house}} =
               Frame.new(chart(%{}, %{theme: :house}),
                 theme: Theme.new(name: :house),
                 size: @size
               )

      assert_raise ArgumentError, ~r/scale :x \(time\) cannot take "soon"/, fn ->
        frame(%{x: %{kind: :time}}, [line(%{x: :t, y: :v})], %{primary: [%{t: "soon", v: 1}]})
      end

      assert_raise ArgumentError, ~r/scale :x \(log\) cannot take 0/, fn ->
        frame(%{x: %{kind: :log}}, [line(%{x: :n, y: :v})])
      end

      assert_raise ArgumentError, ~r/declares no scale :z/, fn ->
        Frame.scale(Frame.new(chart(%{}), size: @size), :z)
      end
    end
  end

  describe "paints (spec/14 §2.7, §3.2)" do
    @defs %{
      fade: %{
        type: :linear,
        stops: [
          %{at: 0, color: {:color, :series_1}, opacity: 0.8},
          %{at: 1, color: "#fff", opacity: 0.1}
        ]
      },
      glow: %{
        type: :radial,
        stops: [%{at: 0, color: "#ff0"}, %{at: 1, color: "#f00"}],
        center: [0.3, 0.4],
        radius: 0.6
      }
    }

    defp painted(defs, fill \\ {:paint, :fade}) do
      scales = %{x: %{kind: :linear}, y: %{kind: :linear}}
      axes = [%{scale: :x, side: :bottom, grid: true}]
      styles = %{wash: %{fill: fill}}
      mark = %{type: :area, data: :primary, channels: %{x: :n, y: :v}, style: :wash}
      chart(%{scales: scales, axes: axes}, %{defs: defs, styles: styles, marks: [mark]})
    end

    test "the defs come first, before the grid, with the gradients in the words' geometry" do
      frame = Frame.new(painted(@defs), sources: %{primary: @rows}, size: @size)

      %Element{children: [defs, grid | _]} =
        Frame.generate(frame, sources: %{primary: @rows}, size: @size)

      assert defs.type == :defs and grid.style.class == "grid"
      [fade, glow] = defs.children
      prefix = Visualize.Chart.Frame.Defs.prefix(@defs)

      # 180° runs top to bottom in the shape's box.
      assert fade.type == :linear_gradient

      assert fade.attrs == %{
               id: "vis-paint-#{prefix}-fade",
               x1: 0.5,
               y1: 0.0,
               x2: 0.5,
               y2: 1.0,
               gradient_units: "objectBoundingBox"
             }

      [s0, s1] = fade.children
      assert s0.attrs == %{offset: "0%"}
      assert s0.style == %{stop_color: "var(--vis-series-1, #3b6fa8)", stop_opacity: 0.8}
      assert s1.style == %{stop_color: "#fff", stop_opacity: 0.1}

      assert glow.type == :radial_gradient

      assert glow.attrs == %{
               id: "vis-paint-#{prefix}-glow",
               cx: 0.3,
               cy: 0.4,
               r: 0.6,
               fx: 0.3,
               fy: 0.4,
               gradient_units: "objectBoundingBox"
             }

      # A design with no paints emits no defs.
      plain = Frame.new(painted(%{}, "#abc"), size: @size)
      %Element{children: [first | _]} = Frame.generate(plain)
      assert first.type != :defs
    end

    test "a fill that is a paint is the paint in both modes: url(#id) on SVG, a gradient on a canvas" do
      frame = Frame.new(painted(@defs), sources: %{primary: @rows}, size: @size)
      prefix = Visualize.Chart.Frame.Defs.prefix(@defs)

      css = Frame.generate(frame, sources: %{primary: @rows}, size: @size)
      mark = Enum.find(css.children, &(&1.style[:class] == "mark mark-area"))
      assert %Visualize.IR.Paint{id: id, type: :linear} = mark.style.fill
      assert id == "vis-paint-#{prefix}-fade"

      # In :literal the stops are literals, which a canvas builds its gradient from (#652).
      literal = Frame.generate(frame, sources: %{primary: @rows}, resolve: :literal)
      mark = Enum.find(literal.children, &(&1.style[:class] == "mark mark-area"))
      assert %Visualize.IR.Paint{id: ^id, stops: [{+0.0, "#3b6fa8", 0.8} | _]} = mark.style.fill

      # The SVG carries the reference and the definition, in either mode; a canvas the
      # gradient itself.
      svg = Render.to_string(css)

      assert svg =~
               ~s(<linearGradient gradientUnits="objectBoundingBox" id="vis-paint-#{prefix}-fade")

      assert svg =~ ~s|fill="url(#vis-paint-#{prefix}-fade)"|
      js = literal |> Visualize.Backend.Canvas.render_element() |> IO.iodata_to_binary()
      assert js =~ "ctx.createLinearGradient("
      assert literal |> Render.to_string() =~ ~s|fill="url(#vis-paint-#{prefix}-fade)"|
    end

    test "two charts with different paints have different ids; an undeclared paint is refused" do
      a = Visualize.Chart.Frame.Defs.prefix(@defs)
      b = Visualize.Chart.Frame.Defs.prefix(Map.delete(@defs, :glow))
      assert a != b

      design = %{
        version: 3,
        defs: @defs,
        styles: %{wash: %{fill: {:paint, :nope}}},
        frames: %{main: %{kind: :cartesian}}
      }

      assert Visualize.Chart.Validator.validate(design) ==
               {:error, [{[:styles, :wash, :fill, :name], {:undeclared, :paint, :nope}}]}
    end

    test "a gradient of version 2's words reads as the paint it is (D-172)" do
      old = %{
        fade: %{
          kind: :linear,
          stops: [
            # spelling: allow — version 2's stop word.
            %{offset: 0, colour: :series_1, opacity: 0.8},
            # spelling: allow — version 2's stop word.
            %{offset: 1, colour: "#fff", opacity: 0.1}
          ]
        },
        glow: %{
          kind: :radial,
          # spelling: allow — version 2's stop word.
          stops: [%{offset: 0, colour: "#ff0"}, %{offset: 1, colour: "#f00"}],
          # spelling: allow — version 2's paint word.
          centre: [0.3, 0.4],
          radius: 0.6
        }
      }

      assert painted(old).defs == @defs
    end

    test "a gradient written inline is drawn from the frame's defs, keyed by what it draws" do
      fill = %{type: :linear, color: [:series_1, "#fff"], angle: 90, opacity: 0.5}
      frame = Frame.new(painted(%{}, fill), sources: %{primary: @rows}, size: @size)

      css = Frame.generate(frame, sources: %{primary: @rows}, size: @size)
      [defs | _] = css.children
      [gradient] = defs.children
      assert gradient.type == :linear_gradient
      assert %{x1: +0.0, y1: 0.5, x2: 1.0, y2: 0.5} = gradient.attrs

      mark = Enum.find(css.children, &(&1.style[:class] == "mark mark-area"))
      assert Visualize.IR.Paint.url(mark.style.fill) == "url(##{gradient.attrs.id})"
      assert mark.style.fill_opacity == 0.5

      # The same gradient written twice is one definition; a canvas draws it from literals.
      twice = painted(%{}, fill) |> Map.update!(:marks, &(&1 ++ &1))

      css =
        twice
        |> Frame.new(sources: %{primary: @rows}, size: @size)
        |> Frame.generate(sources: %{primary: @rows})

      assert [%{children: [_one]} | _] = css.children

      literal = Frame.generate(frame, sources: %{primary: @rows}, resolve: :literal)
      mark = Enum.find(literal.children, &(&1.style[:class] == "mark mark-area"))

      assert %Visualize.IR.Paint{stops: [{+0.0, "#3b6fa8", 1}, {1.0, "#fff", 1}]} =
               mark.style.fill
    end
  end

  describe "a text has lines (spec/14 §7.1)" do
    test "a newline breaks a label into tspans spaced by line_height; one line is left as it is" do
      styles = %{wide: %{line_height: 2, font_size: 10}}

      labels = [
        %{anchor: :title, text: "Uptime\n24 h"},
        %{anchor: :caption, text: "one line"},
        %{anchor: :subtitle, text: "a\nb\nc", style: :wide}
      ]

      chart =
        chart(%{scales: %{x: %{kind: :linear}, y: %{kind: :linear}}}, %{
          styles: styles,
          labels: labels
        })

      tree = chart |> Frame.new(size: @size) |> Frame.generate()
      # The labels are drawn in the order they are declared.
      [title, caption, subtitle] = Enum.filter(tree.children, &(&1.style[:class] == "label"))

      assert title.content == nil
      assert Enum.map(title.children, & &1.content) == ["Uptime", "24 h"]

      assert Enum.map(title.children, & &1.attrs) == [
               %{x: title.attrs.x},
               %{x: title.attrs.x, dy: "1.2em"}
             ]

      assert caption.content == "one line" and caption.children == []
      assert subtitle.children |> Enum.drop(1) |> Enum.map(& &1.attrs.dy) == ["2em", "2em"]

      svg = Render.to_string(tree)
      x = title.attrs.x

      assert svg =~
               ~s(<tspan x="#{x}">Uptime</tspan><tspan dy="1.2em" x="#{x}">24 h</tspan></text>)

      refute svg =~ "line-height"

      # A canvas draws the literal tree, one fillText per line.
      js =
        chart
        |> Frame.new(size: @size)
        |> Frame.generate(resolve: :literal)
        |> Visualize.Backend.Canvas.render_element()
        |> IO.iodata_to_binary()

      assert js =~ "ctx.fillText('Uptime', "
      assert js =~ "ctx.fillText('24 h', "
      # The wide style steps two font sizes per line: 20 px.
      ys =
        ~r/ctx\.fillText\('[abc]', [-\d.]+, ([-\d.]+)\);/
        |> Regex.scan(js)
        |> Enum.map(fn [_, y] -> y |> Float.parse() |> elem(0) end)

      [y0, y1, y2] = ys
      assert_in_delta y1 - y0, 20, 0.01
      assert_in_delta y2 - y1, 20, 0.01
    end
  end

  describe "text position (spec/14 §3.1, §6.3, §5.5)" do
    test "vertical_align sets the baseline, margins move outward, text_angle turns about the point" do
      styles = %{
        low: %{vertical_align: :bottom},
        out: %{margin_x: 6, margin_y: 4},
        tilt: %{text_angle: -45}
      }

      labels = [
        %{anchor: :title, text: "t", style: :low},
        %{anchor: :caption, text: "c", style: :out},
        %{anchor: {:frame, :top_left}, text: "tl", style: :out},
        %{anchor: {:frame, :bottom_right}, text: "br", style: :out},
        %{anchor: {:axis, :y}, text: "y", style: :tilt},
        %{anchor: {:data, [1, 5]}, text: "d", style: :out}
      ]

      scales = %{x: %{kind: :linear, domain: [0, 3]}, y: %{kind: :linear, domain: [0, 10]}}
      plain = chart(%{scales: scales}, %{labels: Enum.map(labels, &Map.delete(&1, :style))})
      styled = chart(%{scales: scales}, %{styles: styles, labels: labels})

      texts = fn c ->
        c
        |> Frame.new(size: @size)
        |> Frame.generate()
        |> Map.fetch!(:children)
        |> Enum.filter(&(&1.style[:class] == "label"))
      end

      [t0, c0, tl0, br0, y0, d0] = texts.(plain)
      [t1, c1, tl1, br1, y1, d1] = texts.(styled)

      # Only the dy changes for the title; the caption and the corners move outward.
      assert t1.attrs == %{t0.attrs | dy: "-0.25em"}
      assert c1.attrs == %{c0.attrs | y: c0.attrs.y + 4}
      assert tl1.attrs == %{tl0.attrs | x: tl0.attrs.x + 6, y: tl0.attrs.y + 4}
      assert br1.attrs == %{br0.attrs | x: br0.attrs.x - 6, y: br0.attrs.y - 4}
      # A data anchor has no outward direction.
      assert d1.attrs == d0.attrs
      # The axis title keeps its rotate(-90) and turns about its own point after it.
      assert y0.transform.operations == [{:rotate, -90}]
      assert y1.transform.operations == [{:rotate, -90}, {:rotate, -45, y1.attrs.x, y1.attrs.y}]
      # None of the four reaches the element as an attribute.
      svg = styled |> Frame.new(size: @size) |> Frame.generate() |> Render.to_string()
      refute svg =~ "margin-x" or svg =~ "text-angle" or svg =~ "vertical-align"
      assert svg =~ ~s|transform="rotate(-90) rotate(-45,-75,-25)"|
    end

    test "rotate on a frame label turns it about its own point: degrees, or :tangent/:radial about the plot's middle (#137)" do
      scales = %{x: %{kind: :linear, domain: [0, 3]}, y: %{kind: :linear, domain: [0, 10]}}

      labels = [
        %{anchor: {:data, [3, 5]}, text: "r", rotate: :radial},
        %{anchor: {:data, [0, 5]}, text: "l", rotate: :radial},
        %{anchor: {:data, [1.5, 10]}, text: "t", rotate: :tangent},
        %{anchor: {:frame, :top_left}, text: "n", rotate: 30}
      ]

      texts =
        chart(%{scales: scales}, %{labels: labels})
        |> Frame.new(size: @size)
        |> Frame.generate()
        |> Map.fetch!(:children)
        |> Enum.filter(&(&1.style[:class] == "label"))

      [right, left, top, fixed] = texts

      # The plot is 240 × 150: (3, 5) is its right edge's middle, (0, 5) its left's, (1.5, 10) its top's.
      assert right.transform.operations == [{:rotate, 0.0, 240.0, 75.0}]
      assert right.style.text_anchor == :start
      assert left.transform.operations == [{:rotate, 0.0, 0.0, 75.0}]
      assert left.style.text_anchor == :end
      assert top.transform.operations == [{:rotate, 0.0, 120.0, 0.0}]
      assert top.style.text_anchor == :middle
      assert fixed.transform.operations == [{:rotate, 30, 4, 4}]
    end

    test "a mark label moves along its anchor's side, and an axis style angles its tick labels" do
      styles = %{
        up: %{margin_y: 6, vertical_align: :top},
        slant: %{text_angle: -45, font_size: 9}
      }

      label = %{text: "v", anchor: :top, style: :up}
      mark = %{type: :circle, data: :primary, channels: %{x: :n, y: :v}, label: label}
      axes = [%{scale: :x, side: :bottom, style: :slant}, %{scale: :y, side: :left}]
      scales = %{x: %{kind: :linear, domain: [0, 3]}, y: %{kind: :linear, domain: [0, 10]}}

      tree =
        chart(%{scales: scales, axes: axes}, %{styles: styles, marks: [mark]})
        |> Frame.new(sources: %{primary: @rows}, size: @size)
        |> Frame.generate(sources: %{primary: @rows}, size: @size)

      group = Enum.find(tree.children, &(&1.style[:class] == "mark mark-circle"))
      # A labeled mark: its elements' group, then its labels' group beside it (§5.6).
      [%{children: [circle | _]}, %{children: [text | _]}] = group.children
      # 4 up for the anchor's inset, 6 more for the margin, hanging below its point.
      assert text.attrs == %{x: circle.attrs.cx, y: circle.attrs.cy - 4 - 6, dy: "0.71em"}

      [bottom, left] =
        Enum.filter(tree.children, &String.starts_with?(&1.style[:class] || "", "axis"))

      ticks = fn axis -> axis |> tick_texts() end
      assert Enum.all?(ticks.(bottom), &match?([{:rotate, -45, _, _}], &1.transform.operations))
      assert Enum.all?(ticks.(left), &(&1.transform == nil))
    end

    defp tick_texts(%Element{type: :text} = text), do: [text]
    defp tick_texts(%Element{children: children}), do: Enum.flat_map(children, &tick_texts/1)
  end

  describe "blend and effect (spec/14 §3.1, spec/09 §2.5, §3.3.3)" do
    test "a blend is an inline style and an effect a filter declared once per pair" do
      scales = %{x: %{kind: :linear}, y: %{kind: :linear}}

      styles = %{
        a: %{blend: :multiply, effect: :shadow},
        b: %{effect: :shadow, effect_radius: 3},
        c: %{effect: :blur, effect_radius: 6}
      }

      mark = fn style ->
        %{type: :area, data: :primary, channels: %{x: :n, y: :v}, style: style}
      end

      chart =
        chart(%{scales: scales}, %{styles: styles, marks: [mark.(:a), mark.(:b), mark.(:c)]})

      frame = Frame.new(chart, sources: %{primary: @rows}, size: @size)
      tree = Frame.generate(frame, sources: %{primary: @rows}, size: @size)

      [defs | _] = tree.children
      assert defs.type == :defs

      assert Enum.map(defs.children, & &1.attrs.id) == [
               "vis-effect-blur-6",
               "vis-effect-shadow-3"
             ]

      [blur, shadow] = defs.children
      assert hd(blur.children).attrs == %{std_deviation: 6}

      assert hd(shadow.children).attrs == %{
               dx: 1.5,
               dy: 1.5,
               std_deviation: 3,
               flood_opacity: 0.35
             }

      svg = Render.to_string(tree)

      assert svg =~
               ~s(<filter id="vis-effect-shadow-3"><feDropShadow dx="1.5" dy="1.5" flood-opacity="0.35" stdDeviation="3"/></filter>)

      assert svg =~ ~s(<filter id="vis-effect-blur-6"><feGaussianBlur stdDeviation="6"/></filter>)
      assert svg =~ ~s|filter="url(#vis-effect-shadow-3)" style="mix-blend-mode: multiply"|
      assert length(String.split(svg, ~s|filter="url(#vis-effect-shadow-3)"|)) == 3
      refute svg =~ "effect-radius"

      js =
        frame
        |> Frame.generate(sources: %{primary: @rows}, resolve: :literal)
        |> Visualize.Backend.Canvas.render_element()
        |> IO.iodata_to_binary()

      assert js =~ "ctx.globalCompositeOperation = 'multiply';"
      assert js =~ "ctx.shadowBlur = 3;"
      assert js =~ "ctx.shadowOffsetX = 1.5;"
      assert js =~ "ctx.filter = 'blur(6px)';"

      # Neither declares a filter, and normal and none say nothing.
      plain =
        chart(%{scales: scales}, %{
          styles: %{p: %{blend: :normal, effect: :none}},
          marks: [mark.(:p)]
        })

      svg =
        plain
        |> Frame.new(sources: %{primary: @rows}, size: @size)
        |> Frame.generate(sources: %{primary: @rows}, size: @size)
        |> Render.to_string()

      refute svg =~ "<defs>"
      refute svg =~ "mix-blend-mode"
    end
  end

  describe "derived axis defaults (§4.4, D-134)" do
    defp labels(svg) do
      ~r/<text[^>]*>([^<]*)<\/text>/ |> Regex.scan(svg) |> Enum.map(&List.last/1)
    end

    defp time_axis(rows, axis, size \\ {600, 300}) do
      %{
        version: 2,
        sources: %{primary: %{fields: [:t, :v]}},
        frames: %{
          main: %{
            kind: :cartesian,
            margin: %{top: 0, right: 0, bottom: 30, left: 0},
            scales: %{x: %{kind: :time}, y: %{kind: :linear}},
            axes: [Map.merge(%{scale: :x, side: :bottom}, axis)]
          }
        },
        marks: [line(%{x: :t, y: :v})]
      }
      |> Chart.from_map!()
      |> Frame.new(sources: %{primary: rows}, size: size)
      |> Frame.render()
      |> labels()
    end

    defp rows_over(seconds),
      do: [%{t: @t0, v: 0}, %{t: DateTime.add(@t0, seconds, :second), v: 1}]

    test "a time axis reads its span: clock, weekday, date, month" do
      assert time_axis(rows_over(2 * 3600), %{}) |> hd() == "00:00"
      assert time_axis(rows_over(3 * 86_400), %{}) |> hd() == "Mon 00:00"
      assert time_axis(rows_over(61 * 86_400), %{}) |> hd() == "Jan 01"
      assert time_axis(rows_over(730 * 86_400), %{}) |> hd() == "Jan 2024"
    end

    test "a numeric axis reads its magnitude: plain, grouped, one SI prefix" do
      numbers = fn hi ->
        %{
          version: 2,
          sources: %{primary: %{fields: [:n]}},
          frames: %{
            main: %{
              kind: :cartesian,
              scales: %{y: %{kind: :linear, domain: [0, hi]}},
              axes: [%{scale: :y, side: :left}]
            }
          }
        }
        |> Chart.from_map!()
        |> Frame.new(size: {300, 300})
        |> Frame.render()
        |> labels()
      end

      assert numbers.(900) |> List.last() == "900"
      assert numbers.(90_000) |> List.last() == "90,000"
      assert numbers.(9_000_000) == ~w(0 1M 2M 3M 4M 5M 6M 7M 8M 9M)
      assert numbers.(2_500_000) == ~w(0 0.5M 1M 1.5M 2M 2.5M)
    end

    test "the count grows with the axis's length and is capped" do
      counts =
        for width <- [200, 400, 800, 1600],
            do: length(time_axis(rows_over(86_400), %{}, {width, 300}))

      assert counts == Enum.sort(counts)
      assert hd(counts) < List.last(counts)
      assert List.last(counts) <= 13
    end

    test "an explicit format and count win" do
      rows = rows_over(2 * 3600)
      assert time_axis(rows, %{format: "%H"}) |> hd() == "00"
      assert length(time_axis(rows, %{ticks: 2})) == 3
      assert length(time_axis(rows, %{ticks: %{count: 2, size_inner: 0}})) == 3
      assert time_axis(rows, %{ticks: [@t0]}) == ["00:00"]
      # A ticks node without a count keeps the derived count.
      assert time_axis(rows, %{ticks: %{size_inner: 0}}) == time_axis(rows, %{})
    end

    test "prefix and unit wrap the derived label" do
      design = %{
        version: 2,
        sources: %{primary: %{fields: [:n]}},
        frames: %{
          main: %{
            kind: :cartesian,
            scales: %{y: %{kind: :linear, domain: [0, 3_000_000]}},
            axes: [%{scale: :y, side: :left, prefix: "$", unit: "/yr"}]
          }
        }
      }

      assert "$3M/yr" in (design
                          |> Chart.from_map!()
                          |> Frame.new(size: {300, 300})
                          |> Frame.render()
                          |> labels())
    end

    test "a derived axis is the hand-built axis given the derived count and format" do
      design = %{
        version: 2,
        sources: %{primary: %{fields: [:t, :v]}},
        frames: %{
          main: %{
            kind: :cartesian,
            margin: %{top: 0, right: 0, bottom: 0, left: 0},
            scales: %{x: %{kind: :time}},
            axes: [%{scale: :x, side: :bottom}]
          }
        },
        marks: [line(%{x: :t, y: :v})]
      }

      frame = Frame.new(Chart.from_map!(design), sources: %{primary: @rows}, size: {500, 100})
      scale = Frame.scale(frame, :x)
      count = Axis.tick_count(500, :bottom)

      hand =
        Axis.bottom(scale)
        |> Axis.theme(Theme.default())
        |> Axis.ticks(count)
        |> Axis.tick_format(Visualize.Format.Auto.formatter(scale, count: count))
        |> Axis.generate()

      assert Render.to_string(hand) =~ ">01:00<"
      assert Frame.render(frame) =~ Render.to_string(hand)
    end
  end

  describe "byte identity with hand-built furniture" do
    test "a cartesian frame with two axes and a legend is the hand-built axes and legend" do
      design = %{
        version: 2,
        sources: %{primary: %{fields: [:t, :v, :k]}},
        frames: %{
          main: %{
            kind: :cartesian,
            margin: %{top: 20, right: 20, bottom: 30, left: 40},
            scales: %{
              x: %{kind: :time, domain: :auto},
              y: %{kind: :linear, domain: [0, :auto], nice: true},
              color: %{kind: :ordinal}
            },
            axes: [
              %{scale: :x, side: :bottom, ticks: 6, format: "%H:%M"},
              %{scale: :y, side: :left, ticks: 5}
            ],
            legend: %{scale: :color, position: :top_right}
          }
        },
        marks: [
          %{type: :line, data: :primary, channels: %{x: :t, y: :v}, style: :by_k}
        ],
        styles: %{by_k: %{stroke: {:field, :k}}}
      }

      frame = Frame.new(Chart.from_map!(design), sources: %{primary: @rows}, size: {600, 300})
      theme = Theme.default()

      x_scale =
        Scale.time()
        |> Scale.domain([@t0, DateTime.add(@t0, 3 * 3600, :second)])
        |> Scale.range([0, 540])

      y_scale = Scale.linear() |> Scale.domain([0, 9]) |> Scale.range([250, 0]) |> Scale.nice()

      x_axis =
        Axis.bottom(x_scale)
        |> Axis.theme(theme)
        |> Axis.ticks(6)
        |> Axis.tick_format(&Visualize.Format.time(&1, "%H:%M"))
        |> Axis.generate()

      y_axis = Axis.left(y_scale) |> Axis.theme(theme) |> Axis.ticks(5) |> Axis.generate()
      css = &Theme.resolve(theme, &1, :css)

      item = fn label, slot, i ->
        Element.group(
          [
            Element.rect(-12, 0, 12, 12, %{fill: css.(slot)}),
            Element.text(label,
              x: -16,
              y: 6.0,
              dy: "0.32em",
              style: %{fill: css.(:text), text_anchor: :end}
            )
          ],
          style: %{class: "legend-item"},
          attrs: %{"data-series" => label},
          transform: Transform.translate(0, i * 16)
        )
      end

      legend =
        Element.group([item.("c0", :series_1, 0), item.("c1", :series_2, 1)],
          style: %{class: "legend", font_family: css.(:font_family), font_size: css.(:label_size)},
          transform: Transform.translate(532, 8)
        )

      hand_built =
        Element.group(
          [
            Element.group([x_axis],
              style: %{class: "axis axis-bottom"},
              transform: Transform.translate(0, 250)
            ),
            Element.group([y_axis],
              style: %{class: "axis axis-left"},
              transform: Transform.translate(0, 0)
            ),
            legend
          ],
          style: %{class: "frame"},
          transform: Transform.translate(40, 20)
        )

      assert Frame.generate(frame) == hand_built
      assert Frame.render(frame) == Render.to_string(hand_built)
      assert Frame.render(frame) =~ ~s(aria-hidden="true")
      assert Frame.render(frame, resolve: :literal) =~ ~s(stroke="#666666")
      refute Frame.render(frame, resolve: :literal) =~ "var(--vis"
    end

    test "the grid is drawn at the axis's tick positions, hidden, in the grid style" do
      scales = %{
        x: %{kind: :band, domain: [:a, :b], padding: 0.2},
        y: %{kind: :linear, domain: [0, 10]}
      }

      axes = [
        %{scale: :x, side: :bottom, grid: true},
        %{scale: :y, side: :left, ticks: 2, grid: true}
      ]

      frame = Frame.new(chart(%{scales: scales, axes: axes}), size: @size)
      %Element{children: [grid | _]} = Frame.generate(frame)

      assert grid.style == %{class: "grid", stroke: "var(--vis-grid, #e0e0e0)"}
      assert grid.attrs == %{aria_hidden: "true"}
      x_axis = Axis.bottom(Frame.scale(frame, :x))
      [xa, xb | horizontal] = grid.children

      assert xa.attrs == %{
               x1: Axis.tick_position(x_axis, :a),
               y1: 0,
               x2: Axis.tick_position(x_axis, :a),
               y2: 150
             }

      assert xb.attrs.x1 == Axis.tick_position(x_axis, :b)
      assert Enum.map(horizontal, & &1.attrs.y1) == [150.0, 75.0, 0.0]
    end
  end

  describe "every node carries its path when asked (spec/14 §4.7, D-105)" do
    defp addressed(sources \\ %{primary: @rows}) do
      chart(
        %{
          scales: %{
            x: %{kind: :linear},
            y: %{kind: :linear, domain: [0, :auto]},
            color: %{kind: :ordinal}
          },
          axes: [%{scale: :x, side: :bottom, grid: true}, %{scale: :y, side: :left}],
          legend: %{scale: :color, position: :top_right}
        },
        %{
          marks: [
            %{type: :line, data: :primary, channels: %{x: :n, y: :v}, style: :by_k},
            %{type: :circle, data: :primary, channels: %{x: :n, y: :v}}
          ],
          labels: [%{text: ["Mass"], anchor: :title}, %{text: ["hours"], anchor: {:axis, :x}}],
          styles: %{by_k: %{stroke: {:field, :k}}}
        }
      )
      |> Frame.new(sources: sources, size: @size)
    end

    defp nodes(svg), do: Regex.scan(~r/data-node="([^"]+)"/, svg) |> Enum.map(&Enum.at(&1, 1))

    test "the frame, each mark, each axis, the legend and each label are tagged" do
      svg = Frame.render(addressed(), sources: %{primary: @rows}, paths: true)

      assert nodes(svg) == [
               "frames.main",
               "marks[0]",
               "marks[1]",
               "frames.main.axes[0]",
               "frames.main.axes[1]",
               "frames.main.legend",
               "labels[0]",
               "labels[1]"
             ]

      # The grid is furniture, not a node: it is between the frame and the marks, untagged.
      group = Frame.generate(addressed(), sources: %{primary: @rows}, paths: true)
      [grid | _] = Enum.reject(group.children, &(&1.type == :defs))
      assert grid.style.class == "grid" and grid.attrs["data-node"] == nil

      assert svg =~ ~s(<g class="frame" data-node="frames.main" transform=)
      assert svg =~ ~s(<g class="mark mark-line" data-node="marks[0]")
      assert svg =~ ~s(<g class="axis axis-bottom" data-node="frames.main.axes[0]")
      assert svg =~ ~s(<g class="legend" data-node="frames.main.legend")
      assert svg =~ ~s(<text class="label" data-node="labels[0]")
    end

    test "without the option the markup is byte for byte what it was" do
      frame = addressed()
      before = Frame.render(frame, sources: %{primary: @rows}, size: @size)
      refute before =~ "data-node"
      assert Frame.render(frame, sources: %{primary: @rows}, paths: false) == before
      # The furniture alone, and the applied chart through Visualize.Chart.render/2, likewise.
      refute Frame.render(frame) =~ "data-node"
      refute Frame.render(frame, paths: true) =~ ~r/data-node="marks/
      assert Frame.render(frame, paths: true) =~ ~s(data-node="frames.main.axes[1]")
    end

    test "Visualize.Chart.render/2 passes the option through" do
      chart =
        chart(%{scales: %{x: %{kind: :linear}, y: %{kind: :linear}}}, %{
          marks: [%{type: :line, data: :primary, channels: %{x: :n, y: :v}}]
        })

      {:ok, applied} = Chart.apply(chart, sources: %{primary: @rows}, size: @size)
      refute Chart.render(applied) =~ "data-node"
      assert nodes(Chart.render(applied, paths: true)) == ["frames.main", "marks[0]"]
    end

    test "a facet frame's copies of one mark carry one path, and a polar frame's axes keep their positions" do
      facet =
        chart(
          %{
            kind: :facet,
            facet: %{by: :k, columns: 2},
            scales: %{x: %{kind: :linear, domain: [0, 3]}, y: %{kind: :linear, domain: [0, 10]}},
            axes: [%{scale: :x, side: :bottom}]
          },
          %{marks: [%{type: :circle, data: :primary, channels: %{x: :n, y: :v}}]}
        )
        |> Frame.new(sources: %{primary: @rows}, size: @size)

      svg = Frame.render(facet, sources: %{primary: @rows}, paths: true)

      assert nodes(svg) == [
               "frames.main",
               "marks[0]",
               "frames.main.axes[0]",
               "marks[0]",
               "frames.main.axes[0]"
             ]

      polar =
        chart(
          %{
            kind: :polar,
            scales: %{angle: %{kind: :radial}, r: %{kind: :sqrt}, y: %{kind: :linear}},
            axes: [
              %{scale: :y, side: :left},
              %{scale: :angle, side: :bottom},
              %{scale: :r, side: :left}
            ]
          },
          %{marks: [%{type: :rose, data: :primary, channels: %{angle: :n, value: :v}}]}
        )
        |> Frame.new(sources: %{primary: @rows}, size: @size)

      svg = Frame.render(polar, sources: %{primary: @rows}, paths: true)
      # The ring and the spoke are drawn inside the centered group, the cartesian axis
      # after it — and each keeps the position the design gave it.
      assert nodes(svg) == [
               "frames.main",
               "marks[0]",
               "frames.main.axes[1]",
               "frames.main.axes[2]",
               "frames.main.axes[0]"
             ]
    end

    test "a canvas render takes the option without drawing it" do
      frame = addressed()
      canvas = Frame.render(frame, sources: %{primary: @rows}, backend: :canvas, paths: true)
      assert canvas == Frame.render(frame, sources: %{primary: @rows}, backend: :canvas)
    end
  end

  describe "a tick carries a unit (spec/14 §4.4, §4.5, #135)" do
    defp unit_frame(axis, legend \\ %{}) do
      chart(
        %{
          margin: %{top: 50, right: 100, bottom: 50, left: 50},
          scales: %{
            x: %{kind: :linear, domain: [0, 100]},
            y: %{kind: :linear, domain: [0, 5]},
            color: %{kind: :sequential, domain: [0, 100]}
          },
          axes: [Map.merge(%{scale: :x, side: :bottom, ticks: 2}, axis)],
          legend: Map.merge(%{scale: :color, position: :right, inside: false}, legend)
        },
        %{marks: [%{type: :line, data: :primary, channels: %{x: :n, y: :v}}]}
      )
      |> Frame.new(sources: %{primary: @rows}, size: {400, 300})
    end

    defp tick_labels(frame) do
      Regex.scan(~r/<text[^>]*>([^<]*)<\/text>/, Frame.render(frame)) |> Enum.map(&Enum.at(&1, 1))
    end

    test "a unit follows the default label, and a prefix and a unit surround a formatted one" do
      # The domain stays under a thousand until #354 fixes the default label's exponent.
      assert tick_labels(unit_frame(%{unit: "M"})) |> Enum.take(3) == ["0M", "50M", "100M"]

      labels = tick_labels(unit_frame(%{prefix: "$", unit: "T", format: ".1f"}))
      assert Enum.take(labels, 3) == ["$0.0T", "$50.0T", "$100.0T"]
    end

    test "the legend's entries carry the legend's own prefix and unit" do
      labels = tick_labels(unit_frame(%{}, %{unit: "%"}))
      assert Enum.take(labels, -6) == ["0%", "20%", "40%", "60%", "80%", "100%"]
      refute Enum.any?(tick_labels(unit_frame(%{})), &String.ends_with?(&1, "%"))
    end
  end

  describe "a legend in a margin (spec/14 §4.5, #136)" do
    # 400 × 300 with margins of 100: a 200 × 100 plot with room on every side.
    defp legend_frame(legend, margin \\ %{top: 100, right: 100, bottom: 100, left: 100}) do
      chart(
        %{
          margin: margin,
          scales: %{x: %{kind: :linear}, y: %{kind: :linear}, color: %{kind: :ordinal}},
          legend: Map.merge(%{scale: :color}, legend)
        },
        %{
          marks: [%{type: :line, data: :primary, channels: %{x: :n, y: :v}, style: :by_k}],
          styles: %{by_k: %{stroke: {:field, :k}}}
        }
      )
      |> Frame.new(sources: %{primary: @rows}, size: {400, 300})
    end

    defp legend_at(frame) do
      [group] = Legend.generate(frame, :literal)
      {group.transform.operations, group}
    end

    test "inside: true is byte for byte what the frame draws with no key" do
      for position <- [
            :top_left,
            :top_right,
            :bottom_left,
            :bottom_right,
            :top,
            :bottom,
            :left,
            :right
          ] do
        assert Legend.generate(legend_frame(%{position: position, inside: true}), :literal) ==
                 Legend.generate(legend_frame(%{position: position}), :literal)
      end
    end

    test ":right sits 8 past the plot's right edge, centered, reading swatch then label" do
      {[{:translate, x, y}], group} = legend_at(legend_frame(%{position: :right, inside: false}))
      # Two entries (c0, c1): 32 high, centered on the 100-high plot.
      assert {x, y} == {208, 34.0}
      [item | _] = group.children
      [swatch, label] = item.children
      assert swatch.attrs.x == 0 and label.attrs.x == 16
      assert label.style.text_anchor == :start
    end

    test "each position lands in the margin it names" do
      at = fn position ->
        legend_at(legend_frame(%{position: position, inside: false})) |> elem(0)
      end

      # A stacked legend's estimated width: 16 + 0.6 × the 12 label size × 2 characters.
      width = 16 + 0.6 * 12 * 2
      assert at.(:top_right) == [{:translate, 208, 8}]
      assert at.(:bottom_right) == [{:translate, 208, 100 - 32}]
      assert at.(:right) == [{:translate, 208, 34.0}]
      assert [{:translate, x, 8}] = at.(:top_left)
      assert_in_delta x, -8 - width, 1.0e-9
      assert [{:translate, x, 68}] = at.(:bottom_left)
      assert_in_delta x, -8 - width, 1.0e-9
      assert [{:translate, x, 34.0}] = at.(:left)
      assert_in_delta x, -8 - width, 1.0e-9
      assert [{:translate, _, -20}] = at.(:top)
      assert [{:translate, _, 108}] = at.(:bottom)
    end

    test "a legend that does not fit its margin is a fault of Frame.new/2" do
      assert_raise ArgumentError, ~r/needs .* in the right margin, which is 10/, fn ->
        legend_frame(%{position: :right, inside: false}, %{
          top: 20,
          right: 10,
          bottom: 20,
          left: 20
        })
      end

      # A top or bottom margin grows to its rows instead: one row, 12 + 8 (D-169).
      grown =
        legend_frame(%{position: :top, inside: false}, %{top: 4, right: 20, bottom: 20, left: 20})

      assert grown.margin.top == 20

      # Inside, the margin is no concern.
      assert %Frame{} =
               legend_frame(%{position: :right}, %{top: 4, right: 10, bottom: 20, left: 20})
    end
  end

  describe "a design holds its frames by name (spec/14 §2.1, §4.1, §4.2, §4.7, #383)" do
    @two %{
      version: 2,
      sources: %{primary: %{fields: [:t, :v, :n, :k]}},
      frames: %{
        history: %{
          kind: :cartesian,
          box: [0, 0, 0.75, 1],
          margin: %{top: 10, right: 10, bottom: 20, left: 40},
          scales: %{x: %{kind: :time}, y: %{kind: :linear, domain: [0, 10]}},
          axes: [%{scale: :x, side: :bottom}]
        },
        now: %{
          kind: :cartesian,
          box: [0.75, 0, 0.25, 1],
          z: 1,
          background: "#eeeeee",
          margin: %{top: 10, right: 10, bottom: 20, left: 10},
          scales: %{x: %{kind: :linear, domain: [0, 1]}, y: %{kind: :linear, domain: [0, 10]}}
        }
      },
      marks: [
        %{type: :line, frame: :history, data: :primary, channels: %{x: :t, y: :v}},
        %{type: :symbol, frame: :now, data: :primary, channels: %{x: 0.5, y: :v}}
      ]
    }

    defp applied(design \\ @two) do
      {:ok, applied} = Chart.apply(design, sources: %{primary: @rows}, size: @size)
      applied
    end

    test "every frame is realized by name, its plot its own box less its own margins" do
      applied = applied()

      assert applied.frames |> Map.keys() |> Enum.sort() == [:history, :now]
      # 300 x 200: the history takes three quarters of the width, the gauge the last quarter.
      assert applied.frames.history.plot == %{width: 0.75 * 300 - 50, height: 200 - 30}
      assert applied.frames.now.plot == %{width: 0.25 * 300 - 20, height: 200 - 30}
      # `size` stays the render's: the box is a fraction of it, not a size of its own.
      assert applied.frames.now.size == %{width: 300, height: 200}
    end

    test "each frame is one group at its own box, in z order, tagged with its name" do
      svg = Chart.render(applied(), paths: true)

      assert [history, now] =
               Regex.scan(~r/data-node="frames\.(\w+)"/, svg) |> Enum.map(&List.last/1)

      # `now` has the higher z, so it is drawn last whatever the map's order.
      assert {history, now} == {"history", "now"}

      assert svg =~
               ~s|<g class="frame frame-history" data-node="frames.history" transform="translate(40,10)"|

      # 0.75 x 300 = 225, and the left margin of 10 on top of it.
      assert svg =~
               ~s|<g class="frame frame-now" data-node="frames.now" transform="translate(235,10)"|

      # The background is a rect back at the frame's own corner, under its contents.
      assert svg =~ ~s|<rect fill="#eeeeee" height="200" width="75.0" x="-10" y="-10"/>|

      # A mark carries the path the design gives it, not its position within the frame.
      assert svg =~ ~s|<g class="mark mark-symbol" data-node="marks[1]"|

      # A frame without a background paints nothing: the one rect is the gauge's.
      assert length(Regex.scan(~r/<rect /, svg)) == 1
    end

    test "z orders the frames, whatever order they are declared or enumerated in" do
      # `a` sorts first by name and is drawn last, because its z is higher.
      design = %{
        @two
        | frames: %{
            a: Map.merge(@two.frames.now, %{z: 2, background: "#111111"}),
            b: Map.merge(@two.frames.history, %{z: 1, background: "#222222"})
          },
          marks: [
            put_in(hd(@two.marks).frame, :b),
            put_in(List.last(@two.marks).frame, :a)
          ]
      }

      {:ok, applied} = Chart.apply(design, sources: %{primary: @rows}, size: @size)
      svg = Chart.render(applied, paths: true)

      assert Regex.scan(~r/data-node="frames\.(\w+)"/, svg) |> Enum.map(&List.last/1) == [
               "b",
               "a"
             ]
    end

    test "the same design at another size keeps its margins and moves its boxes" do
      {:ok, applied} = Chart.apply(@two, sources: %{primary: @rows}, size: {600, 400})

      # The margins are pixels and do not scale (§4.2); the boxes are fractions and do.
      assert applied.frames.history.margin == %{top: 10, right: 10, bottom: 20, left: 40}
      assert applied.frames.history.plot == %{width: 0.75 * 600 - 50, height: 400 - 30}

      assert Chart.render(applied, paths: true) =~
               ~s|<g class="frame frame-now" data-node="frames.now" transform="translate(460,10)"|
    end

    test "a mark draws in the frame it names, through that frame's scales" do
      applied = applied()

      assert [%{type: :line}] = applied.frames.history.marks
      assert [%{type: :symbol}] = applied.frames.now.marks
      # Both frames declare `x`; each mark reads its own frame's.
      assert applied.frames.history.scales.x.__struct__ == Visualize.Scale.Time
      assert applied.frames.now.scales.x.__struct__ == Visualize.Scale.Linear
    end

    test "a mark says its frame when the design has more than one, and says one it declares" do
      {:error, errors} =
        Chart.apply(update_in(@two.marks, &[Map.delete(hd(&1), :frame) | tl(&1)]))

      assert {[:marks, 0, :frame], :required} in errors

      {:error, errors} = Chart.apply(put_in(@two.marks, [put_in(hd(@two.marks).frame, :nope)]))
      assert {[:marks, 0, :frame], {:undeclared, :frame, :nope}} in errors

      # One frame, and the key is the frame's: a design need not repeat itself.
      one = %{@two | frames: %{history: @two.frames.history}, marks: [hd(@two.marks)]}

      assert {:ok, _} =
               Chart.apply(Map.update!(one, :marks, &[Map.delete(hd(&1), :frame)]),
                 sources: %{primary: @rows}
               )
    end

    test "a design compiles to one compiled chart per frame, each its own plot (#385)" do
      sources = %{primary: @rows}
      {:ok, frames} = Chart.compile(@two, sources: sources, size: @size)

      assert frames |> Map.keys() |> Enum.sort() == [:history, :now]

      # Each is one plot: its own box in pixels, its own plot area, its own marks.
      assert frames.history.box == %{x: 0, y: 0, width: 0.75 * 300, height: 200}
      assert frames.now.box == %{x: 0.75 * 300, y: 0, width: 0.25 * 300, height: 200}
      assert frames.history.plot == %{width: 0.75 * 300 - 50, height: 170}
      assert Enum.map(frames.history.chart.marks, & &1.type) == [:line]
      assert Enum.map(frames.now.chart.marks, & &1.type) == [:symbol]
      assert Map.keys(frames.now.chart.frames) == [:now]

      # And each draws what that frame draws alone, byte for byte.
      alone = %{@two | frames: %{history: @two.frames.history}, marks: [hd(@two.marks)]}
      {:ok, %{history: only}} = Chart.compile(alone, sources: sources, size: @size)

      assert Compiled.svg(frames.history, sources) == Compiled.svg(only, sources)
      assert Compiled.static(frames.history) == Compiled.static(only)
    end

    test "a version 1 design migrates to one frame named main, without its size" do
      old = %{
        version: 1,
        sources: %{primary: %{fields: [:t, :v]}},
        frame: %{kind: :cartesian, size: %{width: 800, height: 300}, margin: %{top: 1}},
        marks: [%{type: :line, data: :primary, channels: %{x: :t, y: :v}}]
      }

      chart = Chart.from_map!(old)
      assert chart.version == 3
      assert chart.frames == %{main: %{kind: :cartesian, margin: %{top: 1}}}
    end
  end

  describe "a frame adopts another frame's scale (spec/14 §4.3, #384)" do
    @shared %{
      version: 2,
      sources: %{low: %{fields: [:t, :v]}, high: %{fields: [:t, :v]}},
      frames: %{
        year: %{
          kind: :cartesian,
          box: [0, 0, 0.5, 1],
          margin: %{top: 10, right: 10, bottom: 20, left: 40},
          scales: %{x: %{kind: :linear}, y: %{kind: :linear}},
          axes: [%{scale: :y, side: :left}]
        },
        day: %{
          kind: :cartesian,
          box: [0.5, 0, 0.5, 1],
          margin: %{top: 10, right: 10, bottom: 20, left: 40},
          scales: %{x: %{kind: :linear}, y: {:frame, :year, :y}},
          axes: [%{scale: :y, side: :left}]
        }
      },
      marks: [
        %{type: :line, frame: :year, data: :low, channels: %{x: :t, y: :v}},
        %{type: :line, frame: :day, data: :high, channels: %{x: :t, y: :v}}
      ]
    }

    @rows_low [%{t: 0, v: 1}, %{t: 1, v: 3}]
    @rows_high [%{t: 0, v: 8}, %{t: 1, v: 20}]
    @both %{low: @rows_low, high: @rows_high}

    test "one domain over every frame taking part, each at its own range" do
      {:ok, applied} = Chart.apply(@shared, sources: @both, size: @size)

      # The union of [1, 3] and [8, 20], drawn by both.
      assert applied.frames.year.scales.y.domain == [1, 20]
      assert applied.frames.day.scales.y.domain == [1, 20]
      assert applied.frames.year.domains == %{y: [1, 20]}

      # The range is each frame's own pixels; here both halves are full height.
      assert applied.frames.day.scales.y.range == applied.frames.year.scales.y.range
      # The adopting frame's x is its own and is not shared.
      assert applied.frames.day.scales.x.domain == [0, 1]

      # Both axes draw the same domain: the same tick labels in each frame's group.
      # `day` draws first, ties in `z` being broken by name (§4.2).
      svg = Chart.render(applied, paths: true)
      [_, rest] = String.split(svg, ~s(data-node="frames.day"), parts: 2)
      [day, year] = String.split(rest, ~s(data-node="frames.year"), parts: 2)
      assert ticks(day) == ticks(year)
      assert "20" in ticks(day)
    end

    defp ticks(svg), do: Regex.scan(~r/<text[^>]*>([^<]+)<\/text>/, svg) |> Enum.map(&List.last/1)

    test "a chain resolves to the scale at its end" do
      chain =
        put_in(@shared, [:frames, :hour], %{
          kind: :cartesian,
          box: [0, 0, 1, 1],
          scales: %{x: %{kind: :linear}, y: {:frame, :day, :y}}
        })
        |> Map.update!(
          :marks,
          &(&1 ++ [%{type: :line, frame: :hour, data: :low, channels: %{x: :t, y: :v}}])
        )

      {:ok, applied} = Chart.apply(chain, sources: @both, size: @size)

      for name <- [:year, :day, :hour] do
        assert applied.frames[name].scales.y.domain == [1, 20], "#{name}"
      end
    end

    test "a cycle, an unknown frame and an unknown scale are faults" do
      cycle = put_in(@shared, [:frames, :year, :scales, :y], {:frame, :day, :y})
      assert {:error, errors} = Chart.apply(cycle, sources: @both)
      assert {[:frames, :day, :scales, :y], {:cycle, :scale, :y}} in errors

      nope = put_in(@shared, [:frames, :day, :scales, :y], {:frame, :nope, :y})
      assert {:error, errors} = Chart.apply(nope, sources: @both)
      assert {[:frames, :day, :scales, :y], {:undeclared, :frame, :nope}} in errors

      missing = put_in(@shared, [:frames, :day, :scales, :y], {:frame, :year, :z})
      assert {:error, errors} = Chart.apply(missing, sources: @both)
      assert {[:frames, :day, :scales, :y], {:undeclared, :scale, :z}} in errors
    end

    test "a compiled chart per frame holds the shared domain, and a tick does not move it" do
      {:ok, applied} = Chart.apply(@shared, sources: @both, size: @size)
      {:ok, frames} = Chart.compile(applied)

      # Each compiled chart is one frame and reaches for no other: the adoption is the
      # owner's node at the resolved domain, and the owner's own is fixed at it too.
      for name <- [:year, :day] do
        assert frames[name].chart.frames[name].scales.y == %{kind: :linear, domain: [1, 20]},
               "#{name}"

        # A given domain does not move, so the axis is static furniture.
        assert {{:axis, 0}, :static} in Compiled.regions(frames[name])
      end

      # And a tick over other rows keeps it: the shared extent is the binding's, not the
      # frame's own (spec/14 §12.1).
      other = %{low: [%{t: 0, v: 0.5}], high: [%{t: 0, v: 0.5}]}
      {_payload, ticked} = Compiled.tick(frames.day, other)
      assert Compiled.svg(ticked, other) =~ "20"
    end
  end

  describe "a layout of weights places the frames (spec/14 §2.8, §4.2, #384)" do
    defp grid(layout, frames, opts \\ []) do
      design = %{
        version: 2,
        sources: %{s: %{fields: [:t, :v]}},
        layout: layout,
        frames:
          Map.new(frames, fn {name, node} -> {name, Map.put_new(node, :kind, :cartesian)} end),
        marks: [
          %{type: :line, frame: frames |> Map.keys() |> hd(), data: :s, channels: %{x: :t, y: :v}}
        ]
      }

      case Chart.apply(design, [sources: %{s: [%{t: 0, v: 1}]}, size: @size] ++ opts) do
        {:ok, applied} -> Map.new(applied.frames, fn {name, frame} -> {name, frame.box} end)
        {:error, errors} -> errors
      end
    end

    test "a row of weights resolves to the fractions written by hand" do
      cells =
        grid(%{columns: [1, 1]}, %{
          left: %{cell: [0, 0]},
          right: %{cell: [1, 0]}
        })

      assert cells == %{left: [0.0, 0.0, 0.5, 1.0], right: [0.5, 0.0, 0.5, 1.0]}
    end

    test "a weight is not a fraction: two layouts in the same proportions are one layout" do
      frames = %{a: %{cell: [0, 0]}, b: %{cell: [1, 0]}, c: %{cell: [2, 0]}, d: %{cell: [3, 0]}}
      assert grid(%{columns: [4, 3, 2, 1]}, frames) == grid(%{columns: [8, 6, 4, 2]}, frames)
    end

    test "a span covers its cells and the gap between them" do
      # Two columns of one row each, and a frame over both: its box is the pair's.
      pair = grid(%{columns: [1, 1]}, %{both: %{cell: [0, 0], span: [2, 1]}})
      assert pair == %{both: [0.0, 0.0, 1.0, 1.0]}

      # With a gap, the spanning frame keeps the gap that falls inside it.
      gapped = grid(%{columns: [1, 1], gap: 30}, %{both: %{cell: [0, 0], span: [2, 1]}})
      assert gapped == %{both: [0.0, 0.0, 1.0, 1.0]}

      # And a frame in one cell gives up half the gap at the edge it shares (300 wide).
      halves = grid(%{columns: [1, 1], gap: 30}, %{a: %{cell: [0, 0]}, b: %{cell: [1, 0]}})
      assert halves == %{a: [0.0, 0.0, 0.45, 1.0], b: [0.55, 0.0, 0.45, 1.0]}
    end

    test "rows and columns place a frame in both directions" do
      cells =
        grid(%{columns: [1, 1], rows: [3, 1]}, %{
          top: %{cell: [0, 0], span: [2, 1]},
          low: %{cell: [1, 1]}
        })

      assert cells == %{top: [0.0, 0.0, 1.0, 0.75], low: [0.5, 0.75, 0.5, 0.25]}
    end

    test "a frame says where it goes once, inside a grid of positive weights" do
      both = grid(%{columns: [1, 1]}, %{a: %{cell: [0, 0], box: [0, 0, 1, 1]}})
      assert {[:frames, :a], :both} in both

      outside = grid(%{columns: [1, 1]}, %{a: %{cell: [2, 0]}})
      assert {[:frames, :a, :cell], :outside} in outside

      past = grid(%{columns: [1, 1]}, %{a: %{cell: [1, 0], span: [2, 1]}})
      assert {[:frames, :a, :cell], :outside} in past

      zero = grid(%{columns: [1, 0]}, %{a: %{cell: [0, 0]}})
      assert {[:layout, :columns], {:weight, :columns}} in zero
    end

    test "a design with no layout, and a frame with no cell, are what they were" do
      assert grid(%{}, %{a: %{box: [0, 0, 0.5, 1]}}) == %{a: [0, 0, 0.5, 1]}
      assert grid(%{}, %{a: %{cell: [0, 0]}}) == %{a: [0.0, 0.0, 1.0, 1.0]}
    end
  end
end
