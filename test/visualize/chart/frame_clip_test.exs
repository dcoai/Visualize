defmodule Visualize.Chart.FrameClipTest do
  @moduledoc """
  A frame that clips its marks to its plot area (spec/14 §4.1, #828, D-212): `clip: true`
  on every backend — SVG, the `:json` canvas and the binary canvas — and on every layer of
  a compiled chart, in a cartesian, a polar and a facet frame, with the furniture left
  unclipped; and a frame without the key drawn byte for byte as before.
  """
  use ExUnit.Case, async: true

  alias Visualize.Backend.CanvasBinary.Decoder
  alias Visualize.Chart
  alias Visualize.Chart.{Compiled, Validator}

  @size {300, 200}
  @margin %{top: 10, right: 20, bottom: 30, left: 40}
  # The plot of @size less @margin.
  @plot {240, 160}

  # A line and labeled points over fixed domains, with rows past the domain's edges, so a
  # mark reaches past the plot on every side.
  @rows [
    %{t: -20, v: 5, name: "before"},
    %{t: 50, v: 15, name: "above"},
    %{t: 120, v: -4, name: "after"}
  ]

  defp design(frame \\ %{}, marks \\ nil) do
    %{
      version: 3,
      sources: %{primary: %{fields: [:t, :v, :name]}},
      frames: %{
        main:
          Map.merge(
            %{
              kind: :cartesian,
              margin: @margin,
              scales: %{
                x: %{kind: :linear, domain: [0, 100]},
                y: %{kind: :linear, domain: [0, 10]},
                color: %{kind: :ordinal, domain: ["before", "above", "after"]}
              },
              axes: [%{scale: :x, side: :bottom, grid: true}, %{scale: :y, side: :left}],
              legend: %{scale: :color, position: :top_right}
            },
            frame
          )
          |> Map.reject(fn {_key, value} -> value == nil end)
      },
      marks:
        marks ||
          [
            %{type: :line, data: :primary, channels: %{x: :t, y: :v}},
            %{
              type: :circle,
              data: :primary,
              channels: %{x: :t, y: :v},
              label: %{text: [{:field, :name}]}
            }
          ],
      labels: [%{anchor: :title, text: ["Clipped"]}]
    }
  end

  defp render(design, rows \\ @rows) do
    {:ok, applied} = Chart.apply(design, sources: %{primary: rows}, size: @size)
    Chart.render(applied)
  end

  defp compile(design, rows \\ @rows) do
    {:ok, %{"main" => compiled}} = Chart.compile(design, sources: %{primary: rows}, size: @size)
    compiled
  end

  # Each `<clipPath>`'s rectangle by its id, `{x, y, width, height}` as numbers.
  defp clip_rects(svg) do
    for [id, attrs] <-
          Regex.scan(~r{<clipPath id="([^"]+)"><rect ([^>]*)/>}, svg, capture: :all_but_first),
        into: %{} do
      number = fn name ->
        [value] = Regex.run(~r{\b#{name}="([-\d.]+)"}, attrs, capture: :all_but_first)
        value |> Float.parse() |> elem(0)
      end

      {id, {number.("x"), number.("y"), number.("width"), number.("height")}}
    end
  end

  # The clip id on each element of the class given, in document order.
  defp clipped(svg, class) do
    Regex.scan(~r{<g class="#{class}" clip-path="url\(#([^)]+)\)"}, svg, capture: :all_but_first)
    |> List.flatten()
  end

  defp plot_rect({x, y}), do: {x / 1, y / 1, elem(@plot, 0) / 1, elem(@plot, 1) / 1}

  describe "the key (spec/14 §4.1)" do
    test "is a boolean, false by default" do
      assert Validator.validate(design(%{clip: true})) == :ok
      assert Validator.validate(design(%{clip: false})) == :ok

      assert {:error, [{[:frames, "main", :clip], _}]} =
               Validator.validate(design(%{clip: 1}))

      assert Chart.Schema.default(:frame, :clip) == false
    end

    test "a frame without it, or with it false, renders byte for byte as before" do
      plain = render(design())
      assert render(design(%{clip: false})) == plain
      refute plain =~ "clip-path"
      refute plain =~ "<clipPath"
    end
  end

  describe "on SVG" do
    test "every mark's group, labels and all, is clipped to the plot; the furniture is not" do
      svg = render(design(%{clip: true}))
      rects = clip_rects(svg)

      for class <- ["mark mark-line", "mark mark-circle"] do
        assert [id] = clipped(svg, class), class
        assert Map.fetch!(rects, id) == plot_rect({0, 0})
      end

      # The labels are inside the clipped circle group; nothing else carries a clip.
      [_, circle] = String.split(svg, ~s(<g class="mark mark-circle" clip-path), parts: 2)
      assert circle =~ ~s(class="mark-labels")
      assert length(Regex.scan(~r{clip-path=}, svg)) == 2
      refute svg =~ ~r{class="(axis|legend|grid|label)[^"]*" clip-path}
    end

    test "a mark that draws nowhere past the plot draws the same, under the clip" do
      inside = [%{t: 10, v: 2, name: "before"}, %{t: 90, v: 8, name: "after"}]
      plain = render(design(), inside)
      clipped = render(design(%{clip: true}), inside)

      strip =
        &Regex.replace(
          ~r{<clipPath id="[^"]+"><rect [^>]*/></clipPath>| clip-path="[^"]+"},
          &1,
          ""
        )

      assert strip.(clipped) == plain
    end

    test "a polar frame clips in its centered group, about the plot's center" do
      polar =
        design(
          %{
            kind: :polar,
            scales: %{
              angle: %{kind: :radial, domain: [-20, 120]},
              r: %{kind: :linear, domain: [0, 10]}
            },
            axes: [],
            legend: nil,
            clip: true
          },
          [
            %{
              type: :rose,
              data: :primary,
              channels: %{angle: :t, value: :v},
              options: %{width: 1}
            }
          ]
        )

      svg = render(polar)
      [id] = clipped(svg, "mark mark-rose")
      {w, h} = @plot
      assert Map.fetch!(clip_rects(svg), id) == {-w / 2, -h / 2, w / 1, h / 1}
    end

    test "a transformed mark is wrapped in a plain group that carries the clip" do
      # An arc in a cartesian frame is translated to the plot's middle (§5.6).
      arcs =
        design(%{clip: true, legend: nil}, [
          %{
            type: :arc,
            data: :primary,
            channels: %{value: :v},
            options: %{outer_radius: 400}
          }
        ])

      rows = [%{t: 0, v: 1, name: "a"}, %{t: 0, v: 2, name: "b"}]
      {:ok, applied} = Chart.apply(arcs, sources: %{primary: rows}, size: @size)
      frame = Chart.generate(applied)
      [wrapper] = Enum.filter(frame.children, &(&1.clip != nil))

      assert wrapper.transform == nil
      assert wrapper.style == %{}
      assert [%{style: %{class: "mark mark-arc"}, transform: moved, clip: nil}] = wrapper.children
      assert moved != nil
      assert wrapper.clip.shape.attrs == %{x: 0, y: 0, width: 240, height: 160}
    end

    test "a facet frame clips each panel's marks to the panel" do
      facet =
        design(
          %{kind: :facet, facet: %{by: :name, columns: 3}, legend: nil, clip: true},
          [%{type: :circle, data: :primary, channels: %{x: :t, y: :v}}]
        )

      svg = render(facet)
      ids = clipped(svg, "mark mark-circle")
      assert length(ids) == 3
      {w, h} = @plot

      for id <- ids, do: assert(Map.fetch!(clip_rects(svg), id) == {0.0, 0.0, w / 3, h / 1})
    end

    test "a basemap's group keeps its one clip, the same rectangle" do
      geo = %{
        kind: :geo,
        margin: @margin,
        scales: %{},
        axes: [],
        legend: nil,
        clip: true,
        projection: %{type: :mercator}
      }

      tiles = %{
        type: :tiles,
        tiles: %{url: "https://tile.example/{z}/{x}/{y}.png", attribution: "© OSM"}
      }

      svg = render(design(geo, [tiles]))
      assert [id] = clipped(svg, "mark mark-tiles")
      assert Map.fetch!(clip_rects(svg), id) == plot_rect({0, 0})
      refute svg =~ ~r{clip-path="[^"]+"><g class="mark mark-tiles"}
    end
  end

  describe "in a compiled chart (spec/14 §12.3, §12.4)" do
    test "the one-string form is the frame's, clips and all" do
      clipped = design(%{clip: true})
      {:ok, applied} = Chart.apply(clipped, sources: %{primary: @rows}, size: @size)
      compiled = compile(clipped)
      svg = Compiled.svg(compiled, applied.sources)
      assert svg == Chart.render(applied)
      assert svg =~ ~s(<g class="mark mark-line" clip-path=)
    end

    test "the `:json` canvas draws each canvas mark inside the plot's clip" do
      forced =
        design(%{clip: true}, [
          %{type: :line, data: :primary, channels: %{x: :t, y: :v}, render: :canvas}
        ])

      {payload, _} = Compiled.tick(compile(forced), %{primary: @rows})
      assert payload.canvas_format == :json
      commands = payload.canvas |> Jason.decode!() |> Enum.map(&{&1["cmd"], &1["args"]})
      {w, h} = @plot
      at = Enum.find_index(commands, &(&1 == {"clip", []}))

      assert [{"save", []}, {"beginPath", []}, {"rect", [0, 0, ^w, ^h]}, {"clip", []}] =
               Enum.slice(commands, (at - 3)..at)

      assert {"restore", []} in Enum.drop(commands, at)
    end

    test "the binary canvas writes the clip record, and the labels in the SVG layer keep the clip" do
      forced =
        design(%{clip: true}, [
          %{
            type: :circle,
            data: :primary,
            channels: %{x: :t, y: :v},
            render: :binary,
            label: %{text: [{:field, :name}]}
          }
        ])

      {payload, _} = Compiled.tick(compile(forced), %{primary: @rows})
      assert payload.canvas_format == :binary_base64
      records = payload.canvas |> Base.decode64!() |> Decoder.decode()
      {w, h} = @plot
      assert [{:version, 4} | _] = records

      # Inside the margin's translation: `save`, the plot's rectangle, the clip.
      at = Enum.find_index(records, &(&1 == {:clip, :inside}))
      assert [:save, {:rects, [rect]}, {:clip, :inside}] = Enum.slice(records, (at - 2)..at)
      assert rect == {0.0, 0.0, w / 1, h / 1}
      assert {:transform, :translate, {40.0, 10.0}} in Enum.take(records, at)

      # The inline labels are the SVG layer's, in the mark's group under the same clip.
      [id] = clipped(payload.svg, "mark mark-circle")
      assert Map.fetch!(clip_rects(payload.svg), id) == plot_rect({0, 0})
      assert payload.svg =~ "before"
    end

    test "a streaming window clips its full redraw and every strip it scrolls in (§12.5)" do
      stream = %{
        version: 2,
        sources: %{primary: %{fields: [:t, :v]}},
        frames: %{
          main: %{
            kind: :cartesian,
            clip: true,
            margin: %{top: 0, right: 20, bottom: 0, left: 20},
            scales: %{x: %{kind: :linear}, y: %{kind: :linear, domain: [0, 10]}},
            axes: [%{scale: :x, side: :bottom}],
            viewport: %{scale: :x, span: 10}
          }
        },
        marks: [%{type: :line, data: :primary, channels: %{x: :t, y: :v}, render: :binary}]
      }

      # Readings up to 12 on a [0, 10] domain: the line runs past the plot's top.
      rows = for i <- 0..29, do: %{t: i, v: rem(i * 7, 13)}

      {:ok, %{"main" => compiled}} =
        Chart.compile(stream, sources: %{primary: rows}, size: {140, 100})

      {full, compiled} = Compiled.tick(compiled, %{primary: rows}, now: 20)
      {scroll, _} = Compiled.tick(compiled, %{primary: rows}, now: 22)
      plot = {:rects, [{0.0, 0.0, 100.0, 100.0}]}

      assert [{:full_redraw, _, records}] =
               full.incremental.binary |> Base.decode64!() |> Decoder.decode()

      assert [{:version, 4} | _] = records
      assert [plot, {:clip, :inside}] -- records == []

      assert [{:incremental, :scroll_x, _, _, _, [{_strip, strip}]}] =
               scroll.incremental.binary |> Base.decode64!() |> Decoder.decode()

      assert [plot, {:clip, :inside}] -- strip == []
    end

    test "without the key the binary stream is what it was: no clip, no version 4" do
      forced =
        design(%{}, [%{type: :line, data: :primary, channels: %{x: :t, y: :v}, render: :binary}])

      {payload, _} = Compiled.tick(compile(forced), %{primary: @rows})
      records = payload.canvas |> Base.decode64!() |> Decoder.decode()
      refute Enum.any?(records, &match?({:clip, _}, &1))
      refute {:version, 4} in records
    end
  end
end
