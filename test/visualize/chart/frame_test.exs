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

  doctest Frame
  alias Visualize.IR.{Element, Transform}

  @t0 ~U[2024-01-01 00:00:00Z]
  @rows for {v, h} <- Enum.with_index([4, 9, 2, 7]),
            do: %{t: DateTime.add(@t0, h * 3600, :second), v: v, n: h, k: "c#{rem(h, 2)}"}

  defp chart(frame, extra \\ %{}) do
    Chart.from_map!(
      Map.merge(
        %{
          version: 1,
          sources: %{primary: %{fields: [:t, :v, :n, :k]}},
          frame: Map.merge(%{kind: :cartesian, size: %{width: 300, height: 200}}, frame)
        },
        extra
      )
    )
  end

  defp line(channels), do: %{type: :line, data: :primary, channels: channels}

  defp frame(scales, marks, sources \\ %{primary: @rows}) do
    Frame.new(chart(%{scales: scales}, %{marks: marks}), sources: sources)
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
          sources: %{primary: @rows}
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

      frame = Frame.new(chart, sources: %{primary: @rows})
      assert Frame.scale(frame, :angle).domain == [0, 3]
      assert Frame.scale(frame, :r).domain == [2, 9]
      assert Frame.scale(frame, :r).range == [0, 75.0]
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

      assert count.(Frame.new(chart(Map.put(base, :axes, axes.([0, 50]))))) == 2
      assert count.(Frame.new(chart(Map.put(base, :axes, axes.(3))))) == 3

      assert count.(
               Frame.new(chart(Map.put(base, :axes, axes.(%{count: 3, values: [1, 2, 3, 4]}))))
             ) == 4

      assert count.(Frame.new(chart(Map.put(base, :axes, [%{scale: :x, side: :bottom}])))) == 11
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

      frame = Frame.new(chart(%{scales: scales, axes: [%{scale: :other, side: :right}]}))
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

      frame = Frame.new(chart(%{scales: scales}))
      assert Frame.scale(frame, :c).range == Scale.Color.scheme(:category10)
      assert Frame.scale(frame, :d).range == [5, 6]
    end
  end

  describe "errors" do
    test "an unresolved variable, an unknown theme and a bad value are ArgumentErrors" do
      var = Chart.var(:unit)

      assert_raise ArgumentError, ~r/variable :unit is unresolved/, fn ->
        chart(%{}, %{vars: %{unit: %{}}, labels: [%{anchor: :title, text: [var]}]})
        |> Frame.new()
        |> Frame.generate()
      end

      assert_raise ArgumentError, ~r/theme :house is neither built-in/, fn ->
        Frame.new(chart(%{}, %{theme: :house}))
      end

      assert %Frame{theme: %Theme{name: :house}} =
               Frame.new(chart(%{}, %{theme: :house}), theme: Theme.new(name: :house))

      assert_raise ArgumentError, ~r/scale :x \(time\) cannot take "soon"/, fn ->
        frame(%{x: %{kind: :time}}, [line(%{x: :t, y: :v})], %{primary: [%{t: "soon", v: 1}]})
      end

      assert_raise ArgumentError, ~r/scale :x \(log\) cannot take 0/, fn ->
        frame(%{x: %{kind: :log}}, [line(%{x: :n, y: :v})])
      end

      assert_raise ArgumentError, ~r/declares no scale :z/, fn ->
        Frame.scale(Frame.new(chart(%{})), :z)
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
      frame = Frame.new(painted(@defs), sources: %{primary: @rows})
      %Element{children: [defs, grid | _]} = Frame.generate(frame, sources: %{primary: @rows})
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
      plain = Frame.new(painted(%{}, "#abc"))
      %Element{children: [first | _]} = Frame.generate(plain)
      assert first.type != :defs
    end

    test "a fill that is a paint is url(#id) in css and the first stop's colour in literal" do
      frame = Frame.new(painted(@defs), sources: %{primary: @rows})
      prefix = Visualize.Chart.Frame.Defs.prefix(@defs)

      css = Frame.generate(frame, sources: %{primary: @rows})
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
        version: 1,
        defs: @defs,
        styles: %{wash: %{fill: {:paint, :nope}}},
        frame: %{kind: :cartesian}
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

      tree = chart |> Frame.new() |> Frame.generate()
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
        |> Frame.new()
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
        |> Frame.new()
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
      svg = styled |> Frame.new() |> Frame.generate() |> Render.to_string()
      refute svg =~ "margin-x" or svg =~ "text-angle" or svg =~ "vertical-align"
      assert svg =~ ~s|transform="rotate(-90) rotate(-45,-75,-25)"|
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
        |> Frame.new(sources: %{primary: @rows})
        |> Frame.generate(sources: %{primary: @rows})

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

      frame = Frame.new(chart, sources: %{primary: @rows})
      tree = Frame.generate(frame, sources: %{primary: @rows})

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
        |> Frame.new(sources: %{primary: @rows})
        |> Frame.generate(sources: %{primary: @rows})
        |> Render.to_string()

      refute svg =~ "<defs>"
      refute svg =~ "mix-blend-mode"
    end
  end

  describe "byte identity with hand-built furniture" do
    test "a cartesian frame with two axes and a legend is the hand-built axes and legend" do
      design = %{
        version: 1,
        sources: %{primary: %{fields: [:t, :v, :k]}},
        frame: %{
          kind: :cartesian,
          size: %{width: 600, height: 300},
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
        },
        marks: [
          %{type: :line, data: :primary, channels: %{x: :t, y: :v}, style: :by_k}
        ],
        styles: %{by_k: %{stroke: {:field, :k}}}
      }

      frame = Frame.new(Chart.from_map!(design), sources: %{primary: @rows})
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

      frame = Frame.new(chart(%{scales: scales, axes: axes}))
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
end
