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
        version: 1,
        sources: %{primary: %{fields: [:t, :v]}},
        frame: %{
          kind: :cartesian,
          size: %{width: 300, height: 200},
          scales: scales,
          axes: [%{scale: :x, side: :bottom, grid: true}, %{scale: :y, side: :left}]
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
    {:ok, compiled} = Chart.compile(design, opts)
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
        frame: %{
          kind: :cartesian,
          scales: scales,
          legend: %{scale: :color},
          axes: []
        },
        marks: [%{type: :line, data: :primary, channels: %{x: :t, y: :v, series: :v}}],
        labels: [%{anchor: {:data, [1, 1]}, text: ["here"]}]
      }

      compiled = compile!(design(scales, extra), sources: %{primary: rows(3)})

      assert Compiled.dynamic_regions(compiled) == [
               {{:mark, 0}, :data},
               {:legend, {:inferred, [:color]}}
             ]

      inferred = put_in(extra, [:frame, :scales, :y], %{kind: :linear})
      compiled = compile!(design(scales, inferred), sources: %{primary: rows(3)})
      assert {:labels, {:inferred, [:y]}} in Compiled.dynamic_regions(compiled)
    end

    test "a facet's panels are one dynamic region" do
      extra = %{
        sources: %{primary: %{fields: [:t, :v, :g]}},
        frame: %{
          kind: :facet,
          facet: %{by: :g},
          scales: @fixed,
          axes: [%{scale: :y, side: :left}]
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
        frame: Frame.new(compiled.chart, sources: other)
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
        Chart.compile(design(@fixed), sources: %{primary: rows(3)}, ceiling: 0)
      end
    end

    test "the errors of application are the compiler's" do
      assert {:error, [{[:sources, :primary], {:unbound, :source, :primary}}]} =
               Chart.compile(design(@fixed))
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
        version: 1,
        sources: %{primary: %{fields: [:bearing, :v]}},
        frame: %{
          kind: :polar,
          size: %{width: 200, height: 200},
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
        },
        marks: [%{type: :rose, data: :primary, channels: %{angle: :bearing, value: :v}}],
        labels: [%{anchor: {:data, [90, 3]}, text: ["east"]}]
      }

      geo = %{
        version: 1,
        sources: %{primary: %{fields: [:lon, :lat]}},
        frame: %{
          kind: :geo,
          size: %{width: 200, height: 100},
          projection: %{type: :equirectangular, scale: 30}
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
        version: 1,
        sources: %{primary: %{fields: [:t, :v, :g]}},
        frame: %{
          kind: :facet,
          size: %{width: 300, height: 200},
          facet: %{by: :g, columns: 2},
          scales: %{x: %{kind: :linear, domain: [0, 5]}, y: %{kind: :linear}},
          axes: [%{scale: :x, side: :bottom}, %{scale: :y, side: :left, grid: true}]
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
        {:ok, applied} = Chart.apply(design, sources: sources)
        {:ok, compiled} = Chart.compile(applied)
        assert Compiled.svg(compiled, sources) == Chart.render(applied)
      end

      {:ok, compiled} = Chart.compile(polar, sources: sources)

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

  describe "the viewport (§12.5)" do
    @stream %{
      version: 1,
      sources: %{primary: %{fields: [:t, :v]}},
      frame: %{
        kind: :cartesian,
        size: %{width: 140, height: 100},
        margin: %{top: 0, right: 20, bottom: 0, left: 20},
        scales: %{x: %{kind: :linear}, y: %{kind: :linear, domain: [0, 10]}},
        axes: [%{scale: :x, side: :bottom}],
        viewport: %{scale: :x, span: 10}
      },
      marks: [%{type: :line, data: :primary, channels: %{x: :t, y: :v}, render: :binary}]
    }

    test "the window is [hi − span, hi] with hi the newest datum or the clock, and the marks draw within it" do
      compiled = compile!(@stream, sources: %{primary: rows(30)})

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
      compiled = compile!(@stream, sources: %{primary: rows(30)})
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

      {third, compiled} = Compiled.tick(compiled, sources, now: 22)
      assert %{mode: "none", binary: ""} = third.incremental

      {fourth, compiled} = Compiled.tick(compiled, sources, now: 22.04)
      assert fourth.incremental.mode == "none"
      {fifth, _compiled} = Compiled.tick(compiled, sources, now: 22.08)
      assert %{mode: "scroll_x", dx: 1} = fifth.incremental

      {jump, _} = Compiled.tick(compiled, sources, now: 40)
      assert jump.incremental.mode == "full"
    end

    test "an inferred scale beside the window makes every tick a full redraw" do
      stale = put_in(@stream, [:frame, :scales, :y], %{kind: :linear})
      compiled = compile!(stale, sources: %{primary: rows(30)})
      {_, compiled} = Compiled.tick(compiled, %{primary: rows(30)}, now: 20)
      {payload, _} = Compiled.tick(compiled, %{primary: rows(30)}, now: 22)
      assert payload.incremental.mode == "full"
    end

    test "a time scale windows in seconds" do
      design =
        @stream
        |> put_in([:frame, :scales, :x], %{kind: :time})
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
    test "tick/2 keeps the sources and nothing else" do
      compiled = compile!(design(@fixed), sources: %{primary: rows(3)})
      {_, ticked} = Compiled.tick(compiled, %{primary: rows(4)})
      assert ticked.sources == %{primary: rows(4)}
      assert %{ticked | sources: compiled.sources} == compiled
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
