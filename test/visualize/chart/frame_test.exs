defmodule Visualize.Chart.FrameTest do
  @moduledoc """
  The realised frame of spec/14 §4 and D-60: inference of `:auto` domains from the whole
  bound column by kind (numeric, time, categorical, collapsed, unbound), the precedence
  of an explicit domain, a half-fixed extent and `put_scale/3`, the ranges by name, the
  errors a frame raises, and the byte identity of a frame's furniture with the same
  furniture built by hand from `Visualize.Axis` and `Visualize.IR.Element`.
  """
  use ExUnit.Case, async: true

  alias Visualize.{Axis, Chart, Render, Scale, Theme}
  alias Visualize.Chart.Frame
  alias Visualize.Chart.Frame.Legend

  doctest Frame
  alias Visualize.IR.{Element, Transform}

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

    test "every channel naming the scale contributes, as does a colour field in a style" do
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

    test "start and sweep realise the angle range in radians; a list range wins; a full turn is the default" do
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
          %{scale: :r, side: :top, grid: true}
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
      centres = for k <- six, do: Scale.apply(band, k) + Scale.Band.bandwidth(band) / 2
      assert_in_delta hd(centres), 0, 1.0e-9
      assert_in_delta Enum.at(centres, 1), :math.pi() / 3, 1.0e-9
      assert_in_delta List.last(centres), 5 * :math.pi() / 3, 1.0e-9

      half =
        polar(
          %{angle: %{kind: :band, domain: six, start: -90, sweep: 180}, r: %{kind: :linear}},
          []
        )

      band = Frame.scale(half, :angle)
      centres = for k <- six, do: Scale.apply(band, k) + Scale.Band.bandwidth(band) / 2
      assert_in_delta hd(centres), -:math.pi() / 2, 1.0e-9
      assert_in_delta List.last(centres), :math.pi() / 2, 1.0e-9
      assert_in_delta Enum.at(centres, 1) - hd(centres), :math.pi() / 5, 1.0e-9

      # The axis ticks every category at its centre: the first straight up at R.
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
      many = for t <- 1..200_000, do: %{n: t, v: rem(t, 97)}

      {us, frame} = :timer.tc(fn -> Frame.new(chart, sources: %{primary: many}, size: @size) end)
      assert Frame.scale(frame, :x).domain == [0, 1]

      # Gathering the columns of 200,000 rows for scales that cannot use them took tens of
      # milliseconds; not gathering them takes about none.
      assert us < 50_000, "realising a fixed-domain frame over 200,000 rows took #{us} us"
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

    test "an axis's explicit tick values beat its count, which beats the default" do
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
             ) == 11
    end
  end

  describe "ranges by name" do
    test "position names take the plot area and a colour name the theme's series" do
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
      assert Scale.apply(Frame.scale(frame, :heat), 0) == "#ffffff"
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
        kind: :linear,
        stops: [
          %{offset: 0, colour: :series_1, opacity: 0.8},
          %{offset: 1, colour: "#fff", opacity: 0.1}
        ]
      },
      glow: %{
        kind: :radial,
        stops: [%{offset: 0, colour: "#ff0"}, %{offset: 1, colour: "#f00"}],
        centre: [0.3, 0.4],
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

    test "a fill that is a paint is url(#id) in css and the first stop's colour in literal" do
      frame = Frame.new(painted(@defs), sources: %{primary: @rows}, size: @size)
      prefix = Visualize.Chart.Frame.Defs.prefix(@defs)

      css = Frame.generate(frame, sources: %{primary: @rows}, size: @size)
      mark = Enum.find(css.children, &(&1.style[:class] == "mark mark-area"))
      assert mark.style.fill == "url(#vis-paint-#{prefix}-fade)"

      literal = Frame.generate(frame, sources: %{primary: @rows}, resolve: :literal)
      mark = Enum.find(literal.children, &(&1.style[:class] == "mark mark-area"))
      assert mark.style.fill == "#3b6fa8"

      # The SVG carries the reference and the definition; a canvas the plain colour.
      svg = Render.to_string(css)

      assert svg =~
               ~s(<linearGradient gradientUnits="objectBoundingBox" id="vis-paint-#{prefix}-fade")

      assert svg =~ ~s|fill="url(#vis-paint-#{prefix}-fade)"|
      js = literal |> Visualize.Backend.Canvas.render_element() |> IO.iodata_to_binary()
      assert js =~ "ctx.fillStyle = '#3b6fa8';"
    end

    test "two charts with different paints have different ids; an undeclared paint is refused" do
      a = Visualize.Chart.Frame.Defs.prefix(@defs)
      b = Visualize.Chart.Frame.Defs.prefix(Map.delete(@defs, :glow))
      assert a != b

      design = %{
        version: 2,
        defs: @defs,
        styles: %{wash: %{fill: {:paint, :nope}}},
        frames: %{main: %{kind: :cartesian}}
      }

      assert Visualize.Chart.Validator.validate(design) ==
               {:error, [{[:styles, :wash, :fill], {:undeclared, :paint, :nope}}]}
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
      [circle | _] = group.children
      text = Enum.find(group.children, &(&1.type == :text))
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

  describe "byte identity with hand-built furniture" do
    test "a cartesian frame with two axes and a legend is the hand-built axes and legend" do
      design = %{
        version: 2,
        sources: %{primary: %{fields: [:t, :v, :k]}},
        frames: %{main: %{
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
        }},
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
               "frame",
               "marks[0]",
               "marks[1]",
               "frame.axes[0]",
               "frame.axes[1]",
               "frame.legend",
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
      assert svg =~ ~s(<g class="legend" data-node="frame.legend")
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
      assert nodes(Chart.render(applied, paths: true)) == ["frame", "marks[0]"]
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
      assert nodes(svg) == ["frame", "marks[0]", "frame.axes[0]", "marks[0]", "frame.axes[0]"]

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
      # The ring and the spoke are drawn inside the centred group, the cartesian axis
      # after it — and each keeps the position the design gave it.
      assert nodes(svg) == [
               "frame",
               "marks[0]",
               "frame.axes[1]",
               "frame.axes[2]",
               "frame.axes[0]"
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

    test ":right sits 8 past the plot's right edge, centred, reading swatch then label" do
      {[{:translate, x, y}], group} = legend_at(legend_frame(%{position: :right, inside: false}))
      # Two entries (c0, c1): 32 high, centred on the 100-high plot.
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

      assert_raise ArgumentError, ~r/in the top margin, which is 4/, fn ->
        legend_frame(%{position: :top, inside: false}, %{top: 4, right: 20, bottom: 20, left: 20})
      end

      # Inside, the margin is no concern.
      assert %Frame{} =
               legend_frame(%{position: :right}, %{top: 4, right: 10, bottom: 20, left: 20})
    end
  end
end
