defmodule Visualize.Chart.FrameGoldenTest do
  @moduledoc """
  Rendered-SVG golden of `Visualize.Chart.Frame.render/1` for every frame kind on a fixed
  design (spec/14 §4, D-60): a cartesian frame with grid, both axes, a legend and every
  label anchor; a polar frame with a ring and a spoke; a geo frame with a projection and
  a data label; a facet frame over two panels. Regenerate only when the furniture changes
  on purpose:

      MIX_ENV=test mix run -e 'ExUnit.start(autorun: false); Code.require_file("test/visualize/chart/frame_golden_test.exs"); Visualize.Chart.FrameGoldenTest.write!()'
  """
  use ExUnit.Case, async: true

  alias Visualize.Chart
  alias Visualize.Chart.Frame

  @golden "test/support/frame_golden.txt"
  @kinds [:cartesian, :polar, :geo, :facet]

  @t0 ~U[2024-01-01 00:00:00Z]
  @rows for {v, h} <- Enum.with_index([4, 9, 2, 7]),
            do: %{
              t: DateTime.add(@t0, h * 6 * 3600, :second),
              v: v,
              bearing: h * 90,
              lon: -120 + h * 60,
              lat: 10 * h,
              region: if(h < 2, do: "west", else: "east")
            }
  @sources %{primary: @rows}

  def design(:cartesian) do
    %{
      version: 2,
      sources: %{primary: %{fields: [:t, :v, :region]}},
      styles: %{
        by_region: %{stroke: {:field, :region}},
        faint: %{stroke: "#f00", stroke_dasharray: [2, 2]}
      },
      frames: %{
        main: %{
          kind: :cartesian,
          margin: %{top: 30, right: 20, bottom: 30, left: 40},
          scales: %{
            x: %{kind: :time},
            y: %{kind: :linear, domain: [0, :auto], nice: true},
            color: %{kind: :ordinal}
          },
          axes: [
            %{scale: :x, side: :bottom, ticks: 4, format: "%H:%M", grid: true},
            %{scale: :y, side: :left, ticks: %{count: 3, size_inner: 4}, grid: true},
            %{scale: :y, side: :right, ticks: [2, 5], format: ".1f", style: :faint}
          ],
          legend: %{scale: :color, position: :top_right, title: ["region"]}
        }
      },
      marks: [%{type: :line, data: :primary, channels: %{x: :t, y: :v}, style: :by_region}],
      labels: [
        %{anchor: :title, text: ["Cartesian"]},
        %{anchor: :subtitle, text: ["four points"]},
        %{anchor: :caption, text: ["source: fixture"]},
        %{anchor: {:axis, :x}, text: ["time"]},
        %{anchor: {:axis, :y}, text: ["value"]},
        %{anchor: {:frame, :top_left}, text: ["tl"]},
        %{anchor: {:frame, :bottom_right}, text: ["br"], dx: -2, dy: -2},
        %{anchor: {:data, [@t0, 4]}, text: ["first"]}
      ]
    }
  end

  def design(:polar) do
    %{
      version: 2,
      sources: %{primary: %{fields: [:bearing, :v]}},
      frames: %{
        main: %{
          kind: :polar,
          margin: %{top: 30, right: 30, bottom: 30, left: 30},
          scales: %{
            angle: %{kind: :radial, domain: [0, 360]},
            r: %{kind: :sqrt, domain: [0, :auto]}
          },
          axes: [
            %{scale: :angle, side: :bottom, ticks: 4, grid: true},
            %{scale: :r, side: :top, ticks: 3, grid: true}
          ]
        }
      },
      marks: [%{type: :rose, data: :primary, channels: %{angle: :bearing, value: :v}}],
      labels: [%{anchor: :title, text: ["Polar"]}, %{anchor: {:data, [90, 9]}, text: ["east"]}]
    }
  end

  def design(:geo) do
    %{
      version: 2,
      sources: %{primary: %{fields: [:lon, :lat, :v]}},
      styles: %{by_v: %{fill: {:field, :v}}},
      frames: %{
        main: %{
          kind: :geo,
          margin: %{top: 20, right: 0, bottom: 0, left: 0},
          projection: %{type: :equirectangular, scale: 60},
          scales: %{color: %{kind: :sequential, domain: [0, :auto]}},
          legend: %{scale: :color, position: :bottom, title: ["v"]}
        }
      },
      marks: [%{type: :circle, data: :primary, channels: %{x: :lon, y: :lat}, style: :by_v}],
      labels: [%{anchor: :title, text: ["Geo"]}, %{anchor: {:data, [0, 0]}, text: ["origin"]}]
    }
  end

  def design(:facet) do
    %{
      version: 2,
      sources: %{primary: %{fields: [:t, :v, :region]}},
      frames: %{
        main: %{
          kind: :facet,
          margin: %{top: 20, right: 10, bottom: 30, left: 40},
          facet: %{by: :region, columns: 2},
          scales: %{x: %{kind: :linear, domain: [0, 3]}, y: %{kind: :linear, domain: [0, :auto]}},
          axes: [
            %{scale: :x, side: :bottom, ticks: 3},
            %{scale: :y, side: :left, ticks: 3, grid: true}
          ]
        }
      },
      marks: [%{type: :line, data: :primary, channels: %{x: :v, y: :v}}],
      labels: [%{anchor: {:axis, :y}, text: ["value"]}]
    }
  end

  def render(kind) do
    kind |> design() |> Chart.from_map!() |> Frame.new(sources: @sources) |> Frame.render()
  end

  def render, do: Enum.map_join(@kinds, "", &"#{&1} #{render(&1)}\n")

  def write!, do: File.write!(@golden, render())

  test "every kind renders its fixed design exactly as recorded" do
    assert File.read!(@golden) == render()
  end

  test "the golden covers every kind" do
    recorded =
      @golden
      |> File.read!()
      |> String.split("\n", trim: true)
      |> Enum.map(&(&1 |> String.split(" ", parts: 2) |> hd()))

    assert recorded == Enum.map(@kinds, &Atom.to_string/1)
  end

  test "every design validates and round-trips, and its frame is the same without sources" do
    for kind <- @kinds do
      design = design(kind)
      assert {:ok, chart} = Chart.from_map(design)
      assert {:ok, ^chart} = Chart.from_map(Chart.to_map(chart))
      unbound = Frame.new(chart)
      assert unbound.kind == kind
      assert is_binary(Frame.render(unbound))
    end
  end
end
