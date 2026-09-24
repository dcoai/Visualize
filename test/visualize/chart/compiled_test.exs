defmodule Visualize.Chart.CompiledTest do
  @moduledoc """
  The compiled chart of spec/14 §12 (D-66): the static/dynamic split and its reasons,
  the render target per mark, the hybrid chart map and the one-string form against the
  frame, and the streaming window over the incremental path with a fake clock.
  """
  use ExUnit.Case, async: true

  alias Visualize.Backend.CanvasBinary
  alias Visualize.Backend.CanvasBinary.Decoder
  alias Visualize.Chart
  alias Visualize.Chart.{Compiled, Frame}

  doctest Compiled
  alias Visualize.Designs

  @t0 ~U[2026-09-08 00:00:00Z]

  defp rows(n, offset \\ 0) do
    for i <- 0..(n - 1), do: %{t: i + offset, v: rem(i * 7, 10)}
  end

  defp design(scales, extra \\ %{}) do
    Map.merge(
      %{
        version: 2,
        sources: %{primary: %{fields: [:t, :v]}},
        frames: %{
          main: %{
            kind: :cartesian,
            scales: scales,
            axes: [%{scale: :x, side: :bottom, grid: true}, %{scale: :y, side: :left}]
          }
        },
        marks: [%{type: :line, data: :primary, channels: %{x: :t, y: :v}}],
        labels: [%{anchor: :title, text: ["Compiled"]}]
      },
      extra
    )
  end

  @fixed %{x: %{kind: :linear, domain: [0, 100]}, y: %{kind: :linear, domain: [0, 10]}}
  @inferred %{x: %{kind: :linear}, y: %{kind: :linear, domain: [0, :auto]}}

  defp compile!(design, opts) do
    {:ok, compiled} = Chart.compile(design, Keyword.put_new(opts, :size, {300, 200}))
    compiled
  end

  describe "regions (§12.2)" do
    test "fixed domains leave only the marks dynamic" do
      compiled = compile!(design(@fixed), sources: %{primary: rows(5)})

      assert Compiled.regions(compiled) == [
               {:grid, :static},
               {{:mark, 0}, {:dynamic, :data}},
               {{:axis, 0}, :static},
               {{:axis, 1}, :static},
               {:labels, :static}
             ]

      assert Compiled.dynamic_regions(compiled) == [{{:mark, 0}, :data}]
    end

    test "an inferred domain makes its axis, and the grid drawn from it, dynamic and says why" do
      compiled = compile!(design(@inferred), sources: %{primary: rows(5)})

      assert Compiled.dynamic_regions(compiled) == [
               {:grid, {:inferred, [:x]}},
               {{:mark, 0}, :data},
               {{:axis, 0}, {:inferred, [:x]}},
               {{:axis, 1}, {:inferred, [:y]}}
             ]
    end

    test "a legend on an inferred colour scale and a data-anchored label are dynamic" do
      scales = Map.put(@fixed, :color, %{kind: :ordinal})

      extra = %{
        frames: %{
          main: %{
            kind: :cartesian,
            scales: scales,
            legend: %{scale: :color},
            axes: []
          }
        },
        marks: [%{type: :line, data: :primary, channels: %{x: :t, y: :v, series: :v}}],
        labels: [%{anchor: {:data, [1, 1]}, text: ["here"]}]
      }

      compiled = compile!(design(scales, extra), sources: %{primary: rows(3)})

      assert Compiled.dynamic_regions(compiled) == [
               {{:mark, 0}, :data},
               {:legend, {:inferred, [:color]}}
             ]

      inferred = put_in(extra, [:frames, :main, :scales, :y], %{kind: :linear})
      compiled = compile!(design(scales, inferred), sources: %{primary: rows(3)})
      assert {:labels, {:inferred, [:y]}} in Compiled.dynamic_regions(compiled)
    end

    test "a facet's panels are one dynamic region" do
      extra = %{
        sources: %{primary: %{fields: [:t, :v, :g]}},
        frames: %{
          main: %{
            kind: :facet,
            facet: %{by: :g},
            scales: @fixed,
            axes: [%{scale: :y, side: :left}]
          }
        }
      }

      rows = for {r, i} <- Enum.with_index(rows(4)), do: Map.put(r, :g, rem(i, 2))
      compiled = compile!(design(@fixed, extra), sources: %{primary: rows})
      assert Compiled.regions(compiled) == [{:panels, {:dynamic, :facet}}, {:labels, :static}]
      assert Compiled.targets(compiled) == [{:svg, 4}]
    end
  end

  describe "static bytes (§12.2, §12.4)" do
    test "the static SVG is identical across data changes and carries no mark" do
      compiled = compile!(design(@inferred), sources: %{primary: rows(5)})
      static = Compiled.static(compiled)
      assert static =~ "<svg"
      assert static =~ "Compiled"
      refute static =~ "mark-line"

      {_, compiled} = Compiled.tick(compiled, %{primary: rows(50, 10)})
      {_, compiled} = Compiled.tick(compiled, %{primary: rows(7, 99)})
      assert Compiled.static(compiled) == static

      assert Compiled.render(compiled, %{primary: rows(9)}).static ==
               Compiled.render(compiled, %{primary: rows(2)}).static
    end

    test "every static region is byte for byte the frame's over other data" do
      compiled = compile!(design(@fixed), sources: %{primary: rows(5)})
      other = %{primary: rows(30, 40)}

      applied = %Chart.Applied{
        chart: compiled.chart,
        sources: other,
        frame: Frame.new(compiled.chart, sources: other, size: {300, 200})
      }

      assert Compiled.svg(compiled, other) == Chart.render(applied)
      map = Compiled.render(compiled, other)
      assert length(map.static) == 4
      assert [%{style: %{class: "mark mark-line"}}] = map.dynamic_svg
    end
  end

  describe "targets (§12.3)" do
    test ":auto is SVG at or below the ceiling and the binary path above it" do
      assert Compiled.targets(
               compile!(design(@fixed), sources: %{primary: rows(10)}, ceiling: 10)
             ) == [{:svg, 10}]

      assert Compiled.targets(
               compile!(design(@fixed), sources: %{primary: rows(11)}, ceiling: 10)
             ) == [{:binary, 11}]

      assert Compiled.targets(compile!(design(@fixed), sources: %{primary: rows(1000)})) == [
               {:svg, 1000}
             ]

      assert Compiled.targets(compile!(design(@fixed), sources: %{primary: rows(1001)})) == [
               {:binary, 1001}
             ]
    end

    test "the override is taken as given and the ceiling must be a positive integer" do
      forced =
        design(@fixed, %{
          marks: [%{type: :line, data: :primary, channels: %{x: :t, y: :v}, render: :canvas}]
        })

      assert Compiled.targets(compile!(forced, sources: %{primary: rows(3)})) == [{:canvas, 3}]

      assert_raise ArgumentError, ~r/ceiling/, fn ->
        Chart.compile(design(@fixed), sources: %{primary: rows(3)}, ceiling: 0, size: {300, 200})
      end
    end

    test "the errors of application are the compiler's" do
      assert {:error, [{[:sources, :primary], {:unbound, :source, :primary}}]} =
               Chart.compile(design(@fixed), size: {300, 200})
    end
  end

  describe "the hybrid chart map and the payload (§12.4)" do
    test "a canvas-layer mark leaves the SVG layer, keeps its label there, and sets the format" do
      extra = %{
        marks: [
          %{type: :line, data: :primary, channels: %{x: :t, y: :v}, render: :binary},
          %{
            type: :rule,
            data: :primary,
            channels: %{x: :t},
            label: %{text: ["at ", {:field, :t}]},
            render: :canvas
          }
        ]
      }

      compiled = compile!(design(@fixed, extra), sources: %{primary: rows(3)})
      map = Compiled.render(compiled, %{primary: rows(3)})
      assert map.canvas_format == :binary_base64
      assert map.dynamic_style == %{}
      assert %{width: 300, height: 200, margin: %{left: 40}} = map

      assert [%{style: %{class: "mark mark-line"}}, %{style: %{class: "mark mark-rule"}}] =
               map.dynamic

      refute map.dynamic |> Enum.flat_map(& &1.children) |> Enum.any?(&text?/1)
      assert [%{style: %{class: "mark mark-rule"}} = labels] = map.dynamic_svg
      assert Enum.all?(leaves(labels), &text?/1)
      assert hd(map.dynamic).style.stroke == "#3b6fa8"

      {payload, _} = Compiled.tick(compiled, %{primary: rows(3)})
      assert payload.incremental == nil
      assert payload.canvas_format == :binary_base64

      assert [{:save, _} | _] =
               payload.canvas
               |> Base.decode64!()
               |> Decoder.decode()
               |> Enum.map(&{elem_or(&1), nil})

      assert payload.svg =~ "at 0"
      assert payload.bytes == byte_size(payload.svg) + byte_size(payload.canvas)
    end

    test "an SVG-only chart has no canvas layer and its dynamic SVG is a root of its own" do
      compiled = compile!(design(@fixed), sources: %{primary: rows(3)})
      map = Compiled.render(compiled, %{primary: rows(3)})
      assert map.dynamic == nil
      assert map.canvas_format == :json
      {payload, _} = Compiled.tick(compiled, %{primary: rows(3)})
      assert payload.canvas == ""
      assert payload.svg =~ "<svg"
      assert payload.svg =~ "mark-line"
      assert payload.bytes == byte_size(payload.svg)
    end

    test "a `:json` canvas layer renders its commands per tick" do
      forced =
        design(@fixed, %{
          marks: [%{type: :line, data: :primary, channels: %{x: :t, y: :v}, render: :canvas}]
        })

      compiled = compile!(forced, sources: %{primary: rows(3)})
      {payload, _} = Compiled.tick(compiled, %{primary: rows(3)})
      assert payload.canvas_format == :json
      assert payload.canvas =~ ~s("cmd")
      assert payload.svg == ""
    end
  end

  describe "the one-string form against the frame (§12.4)" do
    test "every stored design reassembles to Chart.render byte for byte" do
      for name <- Designs.names() do
        applied = Designs.apply(name)
        {:ok, compiled} = Chart.compile(applied)
        assert Enum.all?(Compiled.targets(compiled), &match?({:svg, _}, &1)), "#{name}"
        assert Compiled.svg(compiled, applied.sources) == Chart.render(applied), "#{name}"
      end
    end

    test "a polar frame with an outer axis, a geo frame and a facet frame reassemble too" do
      polar = %{
        version: 2,
        sources: %{primary: %{fields: [:bearing, :v]}},
        frames: %{
          main: %{
            kind: :polar,
            scales: %{
              angle: %{kind: :radial, domain: [0, 360]},
              r: %{kind: :linear},
              z: %{kind: :linear, domain: [0, 1]}
            },
            axes: [
              %{scale: :angle, side: :bottom, ticks: 4, grid: true},
              %{scale: :r, side: :top, ticks: 3, grid: true},
              %{scale: :z, side: :left, grid: true}
            ]
          }
        },
        marks: [%{type: :rose, data: :primary, channels: %{angle: :bearing, value: :v}}],
        labels: [%{anchor: {:data, [90, 3]}, text: ["east"]}]
      }

      geo = %{
        version: 2,
        sources: %{primary: %{fields: [:lon, :lat]}},
        frames: %{
          main: %{
            kind: :geo,
            projection: %{type: :equirectangular, scale: 30}
          }
        },
        marks: [
          %{
            type: :circle,
            data: %{source: :primary, transforms: [%{op: :projection, fields: [:lon, :lat]}]},
            channels: %{x: :x, y: :y}
          }
        ],
        labels: [%{anchor: {:data, [0, 0]}, text: ["origin"]}]
      }

      facet = %{
        version: 2,
        sources: %{primary: %{fields: [:t, :v, :g]}},
        frames: %{
          main: %{
            kind: :facet,
            facet: %{by: :g, columns: 2},
            scales: %{x: %{kind: :linear, domain: [0, 5]}, y: %{kind: :linear}},
            axes: [%{scale: :x, side: :bottom}, %{scale: :y, side: :left, grid: true}]
          }
        },
        marks: [%{type: :line, data: :primary, channels: %{x: :t, y: :v}}]
      }

      sources = %{
        primary: [
          %{bearing: 0, v: 3, lon: 0, lat: 0, t: 0, g: "a"},
          %{bearing: 90, v: 5, lon: 30, lat: 10, t: 1, g: "b"},
          %{bearing: 180, v: 2, lon: -30, lat: -10, t: 2, g: "a"}
        ]
      }

      for design <- [polar, geo, facet] do
        {:ok, applied} = Chart.apply(design, sources: sources, size: {300, 200})
        {:ok, compiled} = Chart.compile(applied)
        assert Compiled.svg(compiled, sources) == Chart.render(applied)
      end

      {:ok, compiled} = Chart.compile(polar, sources: sources, size: {300, 200})

      assert Compiled.regions(compiled) == [
               {:grid, {:dynamic, {:inferred, [:r]}}},
               {{:mark, 0}, {:dynamic, :data}},
               {{:axis, 0}, :static},
               {{:axis, 1}, {:dynamic, {:inferred, [:r]}}},
               {{:grid, :outer}, :static},
               {{:axis, 2}, :static},
               {:labels, {:dynamic, {:inferred, [:r]}}}
             ]

      map = Compiled.render(compiled, sources)

      assert [
               %{style: %{class: "polar"}},
               %{style: %{class: "grid"}},
               %{style: %{class: "axis axis-left"}}
             ] = map.static

      assert [%{style: %{class: "polar"}, children: [_grid, _rose, _r_axis]}, %{type: :text}] =
               map.dynamic_svg
    end
  end

  describe "a design's paints through the compiled chart (§12.4, #356)" do
    # An area filled by a gradient the design declares under defs, and a line beside it.
    defp painted do
      design(@fixed, %{
        defs: %{
          fade: %{
            kind: :linear,
            stops: [%{offset: 0, colour: :series_1}, %{offset: 1, colour: :background}]
          }
        },
        styles: %{soft: %{fill: {:paint, :fade}}},
        marks: [
          %{type: :area, data: :primary, channels: %{x: :t, y: :v}, style: :soft},
          %{type: :line, data: :primary, channels: %{x: :t, y: :v}}
        ]
      })
    end

    test "the static carries the defs and the SVG-layer mark refers to the gradient" do
      compiled = compile!(painted(), sources: %{primary: rows(5)}, ceiling: 100)
      assert Compiled.static(compiled) =~ ~r/<defs><linearGradient [^>]*id="vis-paint-\w+-fade"/
      {payload, _} = Compiled.tick(compiled, %{primary: rows(5)})
      assert payload.svg =~ ~r/class="mark mark-area" fill="url\(#vis-paint-\w+-fade\)"/
    end

    test "the canvas layer paints the first stop's colour, and the one-string form is the frame's" do
      sources = %{primary: rows(5)}
      compiled = compile!(painted(), sources: sources, ceiling: 1)
      {payload, _} = Compiled.tick(compiled, sources)
      records = Visualize.Backend.CanvasBinary.Decoder.decode(Base.decode64!(payload.canvas))
      [{:style, area} | _] = Enum.filter(records, &match?({:style, _}, &1))
      assert area.fill == {59, 111, 168, 255}

      applied = compile!(painted(), sources: sources, ceiling: 100)

      assert Compiled.svg(applied, sources) ==
               Chart.render(elem(Chart.apply(painted(), sources: sources, size: {300, 200}), 1))
    end
  end

  describe "an inferred domain eases (§12.5, #360)" do
    # A y scale inferred from the rows, easing over 100 ms along the linear curve.
    defp eased(transition \\ %{duration: 100, easing: :linear}) do
      design(%{
        x: %{kind: :linear, domain: [0, 100]},
        y: %{kind: :linear, domain: [0, :auto], transition: transition}
      })
    end

    defp peak(v), do: %{primary: [%{t: 0, v: 0}, %{t: 50, v: v}, %{t: 100, v: 1}]}

    # The y domain the axis was drawn at: the last tick's label.
    defp shown_max(payload) do
      Regex.scan(~r/<text[^>]*x="-9">([\d.]+)<\/text>/, payload.svg)
      |> List.last()
      |> List.last()
      |> then(&elem(Float.parse(&1), 0))
    end

    test "the shown domain leaves the old extent, is between the two mid-way, and reaches the new one" do
      compiled = compile!(eased(), sources: peak(10), ceiling: 100)
      {first, compiled} = Compiled.tick(compiled, peak(10), at: 0)
      assert first.svg =~ ">10</text>"
      assert compiled.eased.y.shown == [0.0, 10.0]

      # The extent doubles: a grow retargets at once and starts from where it was.
      {_, compiled} = Compiled.tick(compiled, peak(20), at: 0)

      assert compiled.eased.y == %{
               from: [0.0, 10.0],
               target: [0.0, 20.0],
               since: 0,
               shown: [0.0, 10.0],
               pending: nil
             }

      {mid, compiled} = Compiled.tick(compiled, peak(20), at: 50)
      assert compiled.eased.y.shown == [0.0, 15.0]
      # The axis is drawn at the shown domain: its top tick is below 20.
      assert shown_max(mid) < 20

      {done, compiled} = Compiled.tick(compiled, peak(20), at: 100)
      assert compiled.eased.y.shown == [0.0, 20.0]
      assert done.svg =~ ">20</text>"

      # A shrink eases the same way, and without shrink_after it is taken at once.
      {_, compiled} = Compiled.tick(compiled, peak(10), at: 200)
      assert compiled.eased.y.target == [0.0, 10.0] and compiled.eased.y.from == [0.0, 20.0]
      {_, compiled} = Compiled.tick(compiled, peak(10), at: 250)
      assert compiled.eased.y.shown == [0.0, 15.0]
    end

    test "the marks and the axis agree at an intermediate frame" do
      compiled = compile!(eased(), sources: peak(10), ceiling: 100)
      {_, compiled} = Compiled.tick(compiled, peak(10), at: 0)
      {_, compiled} = Compiled.tick(compiled, peak(20), at: 0)
      {mid, _} = Compiled.tick(compiled, peak(20), at: 50)

      # The plot is 150 high (200 less the 20 + 30 margins); at a shown top of 15 the peak
      # of 20 maps above the plot's top and the point at 1 maps to 150 − 10.
      [path] = Regex.run(~r/<path d="([^"]+)"/, mid.svg, capture: :all_but_first)
      assert path =~ "L120,-50"
      assert path =~ "L240,140"
    end

    test "shrink_after holds a shrink and not a grow" do
      compiled =
        compile!(eased(%{duration: 100, easing: :linear, shrink_after: 500}),
          sources: peak(10),
          ceiling: 100
        )

      {_, compiled} = Compiled.tick(compiled, peak(10), at: 0)

      # A shrink is seen and held: the target stays.
      {_, compiled} = Compiled.tick(compiled, peak(5), at: 100)
      assert compiled.eased.y.target == [0.0, 10.0] and compiled.eased.y.pending == 100
      {_, compiled} = Compiled.tick(compiled, peak(5), at: 400)
      assert compiled.eased.y.target == [0.0, 10.0]

      # A grow in the meantime is taken at once and clears the pending shrink.
      {_, compiled} = Compiled.tick(compiled, peak(30), at: 450)
      assert compiled.eased.y.target == [0.0, 30.0] and compiled.eased.y.pending == nil

      # A shrink that lasts is taken once shrink_after has passed.
      {_, compiled} = Compiled.tick(compiled, peak(5), at: 600)
      {_, compiled} = Compiled.tick(compiled, peak(5), at: 1100)
      assert compiled.eased.y.target == [0.0, 5.0]
    end

    test "a scale without a transition jumps as before, and step/3 is the one-string form eased" do
      plain =
        design(%{x: %{kind: :linear, domain: [0, 100]}, y: %{kind: :linear, domain: [0, :auto]}})

      compiled = compile!(plain, sources: peak(10), ceiling: 100)
      assert compiled.transitions == %{}
      {_, compiled} = Compiled.tick(compiled, peak(10), at: 0)
      {jumped, compiled} = Compiled.tick(compiled, peak(20), at: 1)
      assert jumped.svg =~ ">20</text>" and compiled.eased == %{}

      compiled = compile!(eased(), sources: peak(10), ceiling: 100)
      {group, compiled} = Compiled.step(compiled, peak(10), at: 0)
      assert group.type == :group and group.style.class == "frame"
      {_, compiled} = Compiled.step(compiled, peak(20), at: 0)
      {group, compiled} = Compiled.step(compiled, peak(20), at: 50)
      assert compiled.eased.y.shown == [0.0, 15.0]
      assert Visualize.Render.to_string(group, backend: :svg) =~ ~s(class="mark mark-line")
    end
  end

  describe "a mark's value eases (§12.5, #417)" do
    # A line over fixed scales whose rows ease over 100 ms along the linear curve, so a
    # shown value is a plain fraction of the travel.
    defp moving(transition \\ %{duration: 100, easing: :linear}, channels \\ %{x: :t, y: :v}) do
      design(@fixed, %{
        marks: [%{type: :line, data: :primary, channels: channels, transition: transition}]
      })
    end

    # Two rows: the first fixed at the origin, the second the one that moves.
    defp pair(v), do: %{primary: [%{t: 0, v: 0}, %{t: 100, v: v}]}

    # The plot is 240 x 150, so t = 100 draws at x = 240 and v = n at y = 150 - 15n.
    defp moved(payload) do
      [path] = Regex.run(~r/<path d="([^"]+)"/, payload.svg, capture: :all_but_first)
      path
    end

    test "a row leaves its old value, is between the two mid-way, and reaches the new one" do
      compiled = compile!(moving(), sources: pair(0), ceiling: 100)

      # A value seen for the first time is shown as it is.
      {first, compiled} = Compiled.tick(compiled, pair(0), at: 0)
      assert compiled.moving[0][{1, :v}].shown == 0.0
      assert moved(first) =~ "L240,150"

      # It changes: the easing is retargeted and starts from where it stands.
      {_, compiled} = Compiled.tick(compiled, pair(10), at: 0)
      assert compiled.moving[0][{1, :v}] == %{from: 0.0, target: 10.0, since: 0, shown: 0.0}

      {mid, compiled} = Compiled.tick(compiled, pair(10), at: 50)
      assert compiled.moving[0][{1, :v}].shown == 5.0
      assert moved(mid) =~ "L240,75"

      {done, compiled} = Compiled.tick(compiled, pair(10), at: 100)
      assert compiled.moving[0][{1, :v}].shown == 10.0
      assert moved(done) =~ "L240,0"

      # A row whose value has not changed stays where it is.
      {_, compiled} = Compiled.tick(compiled, pair(10), at: 200)
      assert compiled.moving[0][{1, :v}].shown == 10.0
    end

    test "identity is the row's position: an arrival starts at its value, a departure is forgotten" do
      compiled = compile!(moving(), sources: pair(0), ceiling: 100)
      {_, compiled} = Compiled.tick(compiled, pair(0), at: 0)

      third = %{primary: [%{t: 0, v: 0}, %{t: 100, v: 0}, %{t: 50, v: 8}]}
      {_, compiled} = Compiled.tick(compiled, third, at: 10)
      assert compiled.moving[0][{2, :v}] == %{from: 8.0, target: 8.0, since: 10, shown: 8.0}

      {_, compiled} = Compiled.tick(compiled, pair(0), at: 20)
      refute Map.has_key?(compiled.moving[0], {2, :v})
    end

    test "a series channel and a constant do not tween" do
      grouped =
        Map.merge(moving(%{duration: 100, easing: :linear}, %{x: :t, y: :v, series: :g}), %{
          sources: %{primary: %{fields: [:t, :v, :g]}}
        })

      compiled = compile!(grouped, sources: %{primary: [%{t: 0, v: 0, g: 1}]}, ceiling: 100)

      assert compiled.motions[0].fields == [:t, :v]
    end

    test "a mark without a transition jumps as before, and render/2 is unchanged" do
      plain = design(@fixed)
      compiled = compile!(plain, sources: pair(0), ceiling: 100)
      assert compiled.motions == %{}

      {_, compiled} = Compiled.tick(compiled, pair(0), at: 0)
      {jumped, compiled} = Compiled.tick(compiled, pair(10), at: 1)
      assert moved(jumped) =~ "L240,0"
      assert compiled.moving == %{}

      # One frame has nowhere to move from: an applied chart renders as it always did.
      {:ok, with_ease} = Chart.apply(moving(), sources: pair(10), size: {300, 200})
      {:ok, without} = Chart.apply(plain, sources: pair(10), size: {300, 200})
      assert Chart.render(with_ease) == Chart.render(without)
    end

    test "step/3 eases a mark as it eases a scale" do
      compiled = compile!(moving(), sources: pair(0), ceiling: 100)
      {_, compiled} = Compiled.step(compiled, pair(0), at: 0)
      {_, compiled} = Compiled.step(compiled, pair(10), at: 0)
      {group, compiled} = Compiled.step(compiled, pair(10), at: 50)

      assert compiled.moving[0][{1, :v}].shown == 5.0
      assert Visualize.Render.to_string(group, backend: :svg) =~ "L240,75"
    end
  end

  describe "the render target of a text mark (§12.3, #134)" do
    test "a :text mark is :svg whatever render says, since the binary stream carries no text" do
      design =
        Map.put(
          design(%{x: %{kind: :linear, domain: [0, 3]}, y: %{kind: :linear, domain: [0, 10]}}),
          :marks,
          [
            %{type: :text, data: :primary, channels: %{x: :t, y: :v, value: :v}, render: :binary},
            %{type: :line, data: :primary, channels: %{x: :t, y: :v}, render: :binary}
          ]
        )

      compiled = compile!(design, sources: %{primary: rows(4)})
      assert Compiled.targets(compiled) == [{:svg, 4}, {:binary, 4}]
    end
  end

  describe "the viewport (§12.5)" do
    @stream %{
      version: 2,
      sources: %{primary: %{fields: [:t, :v]}},
      frames: %{
        main: %{
          kind: :cartesian,
          margin: %{top: 0, right: 20, bottom: 0, left: 20},
          scales: %{x: %{kind: :linear}, y: %{kind: :linear, domain: [0, 10]}},
          axes: [%{scale: :x, side: :bottom}],
          viewport: %{scale: :x, span: 10}
        }
      },
      marks: [%{type: :line, data: :primary, channels: %{x: :t, y: :v}, render: :binary}]
    }

    test "the window is [hi − span, hi] with hi the newest datum or the clock, and the marks draw within it" do
      compiled = compile!(@stream, size: {140, 100}, sources: %{primary: rows(30)})

      assert Compiled.dynamic_regions(compiled) == [
               {{:mark, 0}, :data},
               {{:axis, 0}, {:inferred, [:x]}}
             ]

      assert Compiled.targets(compiled) == [{:binary, 30}]

      map = Compiled.render(compiled, %{primary: rows(30)})
      [group] = map.dynamic
      [path] = group.children
      assert length(path.path.commands) == 11
      assert {:M, +0.0, _} = hd(path.path.commands)
      assert {:L, 100.0, _} = List.last(path.path.commands)

      {payload, compiled} = Compiled.tick(compiled, %{primary: rows(30)}, now: 15)
      assert payload.svg =~ "axis-bottom"
      assert compiled.viewport.hi == 15

      assert [{:full_redraw, _viewport, records}] =
               payload.incremental.binary |> Base.decode64!() |> Decoder.decode()

      assert Enum.any?(records, &match?({:path32, points} when length(points) == 11, &1))
    end

    test "with a fake clock the canvas layer scrolls by the window's movement, then rests" do
      compiled = compile!(@stream, size: {140, 100}, sources: %{primary: rows(30)})
      sources = %{primary: rows(30)}

      {first, compiled} = Compiled.tick(compiled, sources, now: 20)
      assert %{mode: "full", dx: 0, dy: 0} = first.incremental
      assert first.canvas == ""
      assert first.bytes == byte_size(first.svg) + byte_size(first.incremental.binary)

      {second, compiled} = Compiled.tick(compiled, sources, now: 22)
      assert %{mode: "scroll_x", dx: 20, dy: 0} = second.incremental

      assert [
               {:incremental, :scroll_x, 20.0, +0.0, {+0.0, +0.0, 100.0, 100.0},
                [{{80.0, +0.0, 20.0, 100.0}, records}]}
             ] =
               second.incremental.binary |> Base.decode64!() |> Decoder.decode()

      assert Enum.any?(records, &match?({:path32, _}, &1))
      assert second.bytes == byte_size(second.svg) + byte_size(second.incremental.binary)

      # The strip draws the rows under it and three neighbours each side, not the window
      # (§12.5, D-108): the window at hi = 22 is t ∈ [12, 22], 11 rows; the 20 px strip
      # is the last 2 units, t ∈ [20, 22], 3 rows, and the three before make 6 — so the
      # path has six points and the payload is a fraction of the full redraw's.
      [{:path32, points}] = for({:path32, _} = p <- records, do: p)
      assert length(points) == 6
      # Its points are the window's last six, at the x the scrolled window gives them:
      # t = 17..22 over [12, 22] on 100 px is x = 50..100, ten pixels a unit.
      assert Enum.map(points, fn {x, _y} -> Float.round(x, 3) end) == [
               50.0,
               60.0,
               70.0,
               80.0,
               90.0,
               100.0
             ]

      {third, compiled} = Compiled.tick(compiled, sources, now: 22)
      assert %{mode: "none", binary: ""} = third.incremental
      # The strip's cost must not grow with the window the way it did (#423): the three
      # rows before it are held in slots, not rebuilt as a list per row, and on a scroll
      # the strip is at the leading edge so that was very nearly every row. A ratio of two
      # measurements in the same run, never an absolute bound — timing bounds in this
      # suite have flaked under parallel load before.
      cost = fn span, rows ->
        design = %{
          @stream
          | frames: %{main: %{@stream.frames.main | viewport: %{scale: :x, span: span}}}
        }

        compiled = compile!(design, size: {140, 100}, sources: %{primary: rows})
        {_full, compiled} = Compiled.tick(compiled, %{primary: rows}, now: span)

        Enum.min(
          for _ <- 1..3 do
            {us, _} =
              :timer.tc(fn -> Compiled.tick(compiled, %{primary: rows}, now: span + 20) end)

            us
          end
        )
      end

      small = cost.(200, rows(280))
      large = cost.(3200, rows(4480))

      # Sixteen times the window: under ten times the tick. Rebuilding the neighbours per
      # row made this nine, and it is six.
      assert large < small * 10,
             "a #{16}x window cost #{Float.round(large / small, 1)}x the tick"

      # At scale the strip is a fraction of the full redraw: a thousand-row window on
      # 100 px scrolled 20 px carries 200 rows and six neighbours against 1,001.
      big = %{
        @stream
        | frames: %{main: %{@stream.frames.main | viewport: %{scale: :x, span: 1000}}}
      }

      big_rows = rows(1400)
      compiled_big = compile!(big, size: {140, 100}, sources: %{primary: big_rows})
      {full_big, compiled_big} = Compiled.tick(compiled_big, %{primary: big_rows}, now: 1000)
      {strip_big, _} = Compiled.tick(compiled_big, %{primary: big_rows}, now: 1200)
      assert strip_big.incremental.mode == "scroll_x" and strip_big.incremental.dx == 20
      assert byte_size(strip_big.incremental.binary) < byte_size(full_big.incremental.binary) / 3

      {fourth, compiled} = Compiled.tick(compiled, sources, now: 22.04)
      assert fourth.incremental.mode == "none"
      {fifth, _compiled} = Compiled.tick(compiled, sources, now: 22.08)
      assert %{mode: "scroll_x", dx: 1} = fifth.incremental

      {jump, _} = Compiled.tick(compiled, sources, now: 40)
      assert jump.incremental.mode == "full"
    end

    test "a scroll tick builds the strip and nothing else: its cost does not follow the window (#404)" do
      # A window of 20,000 rows on 100 px: a scroll exposes 20 px, about 200 rows and six
      # neighbours. Whatever the whole window costs to build, the scroll must not pay it.
      big = %{
        @stream
        | frames: %{main: %{@stream.frames.main | viewport: %{scale: :x, span: 10_000}}}
      }

      sources = %{primary: rows(20_000)}
      compiled = compile!(big, sources: sources)

      {full, compiled} = Compiled.tick(compiled, sources, now: 10_000)
      assert full.incremental.mode == "full"

      {full_us, {_payload, compiled}} =
        :timer.tc(fn -> Compiled.tick(compiled, sources, now: 19_000) end)

      {scroll_us, {payload, _}} =
        :timer.tc(fn -> Compiled.tick(compiled, sources, now: 19_200) end)

      assert payload.incremental.mode == "scroll_x"
      # The full redraw of that window is the cost of drawing 10,001 rows; the scroll is
      # the cost of drawing about 200. A third is a generous bound — it was one to one
      # when the tick built the whole window on every scroll.
      assert scroll_us < full_us / 3,
             "a scroll cost #{scroll_us} us against a full redraw's #{full_us} us"
    end

    test "the strip's rows are selected in one pass, and an unordered source is sorted (#404)" do
      # The window is t ∈ [12, 22]; the 20 px strip at the right edge is t ∈ [20, 22].
      sources = %{primary: rows(30)}
      compiled = compile!(@stream, size: {140, 100}, sources: sources)
      {_first, compiled} = Compiled.tick(compiled, sources, now: 20)
      {ordered, _} = Compiled.tick(compiled, sources, now: 22)

      shuffled = %{primary: Enum.shuffle(sources.primary)}
      compiled2 = compile!(@stream, size: {140, 100}, sources: shuffled)
      {_first, compiled2} = Compiled.tick(compiled2, shuffled, now: 20)
      {unordered, _} = Compiled.tick(compiled2, shuffled, now: 22)

      # However the rows arrive, the strip is the same picture.
      assert ordered.incremental.binary == unordered.incremental.binary
    end

    test "the window keeps no closure between ticks, so a run's state does not grow (#406)" do
      sources = %{primary: rows(30)}
      compiled = compile!(@stream, size: {140, 100}, sources: sources)
      {_first, compiled} = Compiled.tick(compiled, sources, now: 20)

      # The state a tick stores is copied into the render task on every frame, so a
      # closure kept in it grows a chain a link a frame and each frame copies twice what
      # the last did — 13 ms a strip became 2,850 ms in eight.
      {compiled, sizes} =
        Enum.map_reduce(1..20, compiled, fn i, compiled ->
          {_payload, compiled} = Compiled.tick(compiled, sources, now: 20 + i * 0.4)
          {:erts_debug.flat_size(compiled.viewport.incremental), compiled}
        end)
        |> then(fn {sizes, compiled} -> {compiled, sizes} end)

      assert compiled.viewport.drawn != nil

      assert Enum.max(sizes) < Enum.min(sizes) * 1.1,
             "the stored state grew over twenty ticks: #{inspect(sizes)}"
    end

    test "a tick with the window's end given infers nothing, and draws what inferring drew (#409)" do
      sources = %{primary: rows(30)}
      compiled = compile!(@stream, size: {140, 100}, sources: sources)

      # The window's scale is `:auto` in the design; a tick that is told `now` gives the
      # frame `[hi − span, hi]` rather than inferring it over the rows and replacing it.
      {first, compiled} = Compiled.tick(compiled, sources, now: 20)
      {second, _} = Compiled.tick(compiled, sources, now: 22)
      assert first.incremental.mode == "full" and second.incremental.mode == "scroll_x"

      # Without `now` the window's end is the newest datum, and the picture is the same.
      by_data = compile!(@stream, size: {140, 100}, sources: sources)
      {full, by_data} = Compiled.tick(by_data, sources, now: 20)
      assert full.incremental.binary == first.incremental.binary
      {scrolled, _} = Compiled.tick(by_data, sources, now: 22)
      assert scrolled.incremental.binary == second.incremental.binary
    end

    test "the strip is found without building the window, and a 50,000-row scroll holds 60 FPS (#410)" do
      # 50,000 rows over a 740 px plot, scrolled the two pixels a run at 60 FPS and 4,500
      # samples a second gives it: the frame must cost that strip, not the window.
      big = %{
        @stream
        | frames: %{main: %{@stream.frames.main | viewport: %{scale: :x, span: 50_000}}}
      }

      sources = %{primary: rows(60_000)}
      compiled = compile!(big, sources: sources)
      {_full, compiled} = Compiled.tick(compiled, sources, now: 50_000)

      # The plot is 740 px wide over 50,000 units, so two pixels is 135 units.
      {scroll_us, {payload, _}} =
        :timer.tc(fn -> Compiled.tick(compiled, sources, now: 50_135) end)

      assert payload.incremental.mode == "scroll_x"

      # A full redraw of that window is the cost of drawing 50,000 rows; the scroll is
      # the cost of drawing about 140. Measured against each other, the ratio holds
      # whatever else the machine is doing — it was one to one when the strip was picked
      # out of a window that had been built in full.
      {full_us, _} =
        :timer.tc(fn ->
          Compiled.tick(%{compiled | viewport: %{compiled.viewport | drawn: nil}}, sources,
            now: 50_135
          )
        end)

      assert scroll_us < full_us / 4,
             "a scroll over 50,000 rows cost #{div(scroll_us, 1000)} ms against a full redraw's #{div(full_us, 1000)} ms"
    end

    test "an unordered source answers the same strip as an ordered one, sorted (#410)" do
      sources = %{primary: rows(30)}
      compiled = compile!(@stream, size: {140, 100}, sources: sources)
      {_first, compiled} = Compiled.tick(compiled, sources, now: 20)
      {ordered, _} = Compiled.tick(compiled, sources, now: 22)

      shuffled = %{primary: Enum.shuffle(sources.primary)}
      compiled2 = compile!(@stream, size: {140, 100}, sources: shuffled)
      {_first, compiled2} = Compiled.tick(compiled2, shuffled, now: 20)
      {unordered, _} = Compiled.tick(compiled2, shuffled, now: 22)

      assert ordered.incremental.binary == unordered.incremental.binary

      # A strip that falls between two rows takes three each side, ordered or not.
      sparse = %{primary: [%{t: 12, v: 1}, %{t: 13, v: 2}, %{t: 21.9, v: 3}, %{t: 22, v: 4}]}
      compiled3 = compile!(@stream, size: {140, 100}, sources: sparse)
      {_first, compiled3} = Compiled.tick(compiled3, sparse, now: 20)
      {gap, _} = Compiled.tick(compiled3, sparse, now: 22)
      assert gap.incremental.mode == "scroll_x"

      backwards = %{primary: Enum.reverse(sparse.primary)}
      compiled4 = compile!(@stream, size: {140, 100}, sources: backwards)
      {_first, compiled4} = Compiled.tick(compiled4, backwards, now: 20)
      {gap_back, _} = Compiled.tick(compiled4, backwards, now: 22)
      assert gap.incremental.binary == gap_back.incremental.binary
    end

    test "an inferred scale beside the window makes every tick a full redraw" do
      stale = put_in(@stream, [:frames, :main, :scales, :y], %{kind: :linear})
      compiled = compile!(stale, sources: %{primary: rows(30)})
      {_, compiled} = Compiled.tick(compiled, %{primary: rows(30)}, now: 20)
      {payload, _} = Compiled.tick(compiled, %{primary: rows(30)}, now: 22)
      assert payload.incremental.mode == "full"
    end

    test "a time scale windows in seconds" do
      design =
        @stream
        |> put_in([:frames, :main, :scales, :x], %{kind: :time})
        |> put_in([:marks], [%{type: :line, data: :primary, channels: %{x: :t, y: :v}}])

      rows = for i <- 0..5, do: %{t: DateTime.add(@t0, i * 60, :second), v: i}
      compiled = compile!(design, sources: %{primary: rows})

      {payload, compiled} =
        Compiled.tick(compiled, %{primary: rows}, now: DateTime.add(@t0, 300, :second))

      assert compiled.viewport.hi == DateTime.add(@t0, 300, :second)
      assert payload.incremental == nil
      assert payload.svg =~ "mark-line"
    end
  end

  describe "the hybrid map without a viewport is stateless" do
    test "tick/2 keeps nothing of the tick, not even its rows (#412)" do
      compiled = compile!(design(@fixed), sources: %{primary: rows(3)})
      {_, ticked} = Compiled.tick(compiled, %{primary: rows(4)})
      assert ticked == compiled
      refute Map.has_key?(compiled, :sources)

      # The rows a tick draws are the tick's, so a compiled chart does not grow by them —
      # what crosses to a renderer is the chart, never the window (#412).
      big = compile!(design(@fixed), sources: %{primary: rows(3)})
      {_, after_big} = Compiled.tick(big, %{primary: rows(20_000)})
      assert :erts_debug.flat_size(after_big) == :erts_debug.flat_size(big)
    end
  end

  defp text?(%{type: :text}), do: true
  defp text?(_), do: false

  defp leaves(%{children: []} = element), do: [element]
  defp leaves(%{children: children}), do: Enum.flat_map(children, &leaves/1)

  defp elem_or(atom) when is_atom(atom), do: atom
  defp elem_or(tuple) when is_tuple(tuple), do: elem(tuple, 0)

  test "binary encoding is available to these tests" do
    assert CanvasBinary.available?()
  end
end
