defmodule Visualize.Chart.FrameCullTest do
  @moduledoc """
  What a clipped frame cannot show is left out before it is drawn (spec/14 §4.1, #839): a
  path's runs beyond one edge cut to their ends, and elements wholly outside dropped — and
  the picture is the same, by resvg's raster of the culled drawing against the unculled
  clipped one.
  """
  use ExUnit.Case, async: true

  alias Visualize.{Chart, PNGPixels, Render}
  alias Visualize.Chart.Frame.Cull
  alias Visualize.IR.{Element, Path, Transform}

  @plot {0, 0, 100, 100}

  defp line(points, style \\ %{stroke: "#000", stroke_width: 2, fill: :none}) do
    [{x, y} | rest] = points

    path =
      Enum.reduce(rest, Path.new() |> Path.move_to(x, y), fn {x, y}, p ->
        Path.line_to(p, x, y)
      end)

    Element.group([Element.path(path)], style: style)
  end

  defp commands(%Element{children: [%Element{path: %Path{commands: commands}}]}), do: commands

  describe "a path" do
    test "a run beyond one edge keeps its first and last point" do
      culled =
        [{50, 50}, {150, 50}, {300, 60}, {400, 70}, {500, 80}, {150, 90}, {50, 90}]
        |> line()
        |> Cull.cull(@plot)

      # From {150, 50} to {150, 90} every point is beyond the right edge: the two ends stay,
      # so the segments that cross the edge are unchanged, and one segment beyond the edge
      # joins them.
      assert commands(culled) == [{:M, 50, 50}, {:L, 150, 50}, {:L, 150, 90}, {:L, 50, 90}]
    end

    test "a run that turns a corner is cut where it stops sharing an edge" do
      culled =
        [{50, 50}, {150, 50}, {200, 60}, {250, -100}, {200, -200}, {50, -200}, {50, 50}]
        |> line()
        |> Cull.cull(@plot)

      # Right of the plot from {150, 50} to {200, -200}, which is right and above; then above
      # it to {50, -200}, the last before the line comes back in.
      assert commands(culled) == [
               {:M, 50, 50},
               {:L, 150, 50},
               {:L, 200, -200},
               {:L, 50, -200},
               {:L, 50, 50}
             ]
    end

    test "points within the stroke's reach of an edge stay: twice the width and a pixel" do
      near = [{50, 50}, {108, 50}, {108, 60}, {108, 70}, {50, 70}]

      assert commands(Cull.cull(line(near, %{stroke: "#000", stroke_width: 4}), @plot)) ==
               commands(line(near))

      far = [{50, 50}, {110, 50}, {110, 60}, {110, 70}, {50, 70}]

      assert length(commands(Cull.cull(line(far, %{stroke: "#000", stroke_width: 4}), @plot))) ==
               4
    end

    test "a path wholly beyond one edge is dropped; one that only surrounds the plot is not" do
      assert Cull.cull(line([{-50, 10}, {-60, 90}, {-20, 50}]), @plot).children == []

      around = line([{-50, -50}, {150, -50}, {150, 150}, {-50, 150}, {-50, -50}])
      assert Cull.cull(around, @plot) == around
    end

    test "a path with nothing to cut is the element it was, relative commands and all" do
      path =
        Path.new() |> Path.move_to(10, 10) |> Path.line_to_rel(500, 0) |> Path.line_to_rel(0, 10)

      group = Element.group([Element.path(path)], style: %{stroke: "#000", stroke_width: 1})
      assert Cull.cull(group, @plot) == group
    end

    test "curves are never cut, only dropped whole when their box is outside" do
      curve = Path.new() |> Path.move_to(10, 10) |> Path.curve_to(500, 0, 600, 0, 700, 10)
      group = Element.group([Element.path(curve)], style: %{stroke: "#000", stroke_width: 1})
      assert Cull.cull(group, @plot) == group
    end
  end

  describe "elements" do
    test "points, shapes and labels wholly outside go; those that reach in stay" do
      far = Element.circle(150, 50, 5, %{fill: "#000", stroke: "#fff", stroke_width: 2})
      reach = Element.circle(108, 50, 5, %{fill: "#000", stroke: "#fff", stroke_width: 2})
      text = Element.text("mile 1", x: 400, y: 50, style: %{font_size: 12})

      long =
        Element.text("a label long enough to reach back in",
          x: 120,
          y: 50,
          style: %{font_size: 12, text_anchor: :end}
        )

      group = Element.group([far, reach, text, long])
      assert Cull.cull(group, @plot).children == [reach, long]
    end

    test "a translation is followed; any other transform keeps the element" do
      moved = %{
        Element.circle(0, 0, 3, %{fill: "#000"})
        | transform: Transform.translate(300, 50)
      }

      turned = %{moved | transform: Transform.rotate(Transform.translate(300, 50), 10)}
      assert Cull.cull(Element.group([moved, turned]), @plot).children == [turned]
    end

    test "a moving element, an effect, a stroke width or size not a number keep the element" do
      out = fn style -> Element.circle(300, 50, 3, Map.merge(%{fill: "#000"}, style)) end
      moving = Element.put_attr(out.(%{}), "data-vis-id", "a")
      effect = out.(%{effect: :shadow})
      slot = out.(%{stroke: "#000", stroke_width: "var(--w, 1px)"})
      unsized = Element.text("x", x: 300, y: 50, style: %{font_size: "1em"})

      kept = [moving, effect, slot, unsized]
      assert Cull.cull(Element.group(kept), @plot).children == kept
    end

    test "a text sized by a theme slot is kept wherever it is: a stylesheet may set the slot" do
      slot = %{font_size: "var(--vis-label-size, 12px)"}
      far = Element.text("mile 1", x: 10_000, y: 50, style: slot)
      assert Cull.cull(Element.group([far]), @plot).children == [far]
    end
  end

  describe "a frame" do
    defp design(clip) do
      %{
        version: 3,
        sources: %{walk: %{fields: [:t, :v, :name]}},
        frames: %{
          main: %{
            kind: :cartesian,
            clip: clip,
            margin: %{top: 20, right: 20, bottom: 30, left: 40},
            scales: %{x: %{kind: :linear, domain: [40, 60]}, y: %{kind: :linear, domain: [-3, 3]}},
            axes: [%{scale: :x, side: :bottom}, %{scale: :y, side: :left}]
          }
        },
        styles: %{thick: %{stroke: %{width: 6, join: :miter}, fill: :none}},
        marks: [
          %{type: :area, data: :walk, channels: %{x: :t, y: :v}, style: %{fill: "#9ecae1"}},
          %{type: :line, data: :walk, channels: %{x: :t, y: :v}, style: :thick},
          %{
            type: :circle,
            data: :walk,
            channels: %{x: :t, y: :v},
            label: %{text: [{:field, :name}]}
          }
        ]
      }
    end

    # A walk that leaves the window on every side and turns sharply near its edges.
    @rows for(
            i <- 0..100,
            do: %{t: i, v: :math.sin(i / 3) * 4 + rem(i * 7, 5) - 2, name: "p#{i}"}
          )

    defp applied(clip) do
      {:ok, applied} = Chart.apply(design(clip), sources: %{walk: @rows}, size: {400, 300})
      applied
    end

    test "a frame without clip is not culled: its marks carry every row" do
      svg = Chart.render(applied(false))
      assert length(Regex.scan(~r{<circle }, svg)) == 101
    end

    test "a clipped frame draws a fraction of the rows" do
      svg = Chart.render(applied(true))
      circles = length(Regex.scan(~r{<circle }, svg))
      assert circles > 5 and circles < 40
    end

    @fonts [
      font_dirs: ["test/support/fonts"],
      system_fonts: false,
      generic_families: [sans_serif: "DejaVu Sans"]
    ]

    defp pixels(element) do
      {:ok, png, []} =
        element
        |> then(&Element.root(400, 300, children: [&1]))
        |> Render.to_png([scale: 1, background: "#ffffff"] ++ @fonts)

      {_w, _h, pixels} = PNGPixels.decode(png)
      pixels
    end

    # The unculled clipped drawing: the frame drawn without the key, each mark's group then
    # given the plot's clip, as `clip: true` does before it culls.
    defp unculled(applied) do
      frame = applied.frames["main"]

      clip =
        Element.clip(
          Element.group([]),
          Element.rect(0, 0, frame.plot.width, frame.plot.height),
          :inside
        ).clip

      generated = Chart.generate(applied(false), resolve: :literal)

      clip_marks = fn
        %Element{style: %{class: "mark " <> _}} = mark -> %{mark | clip: clip}
        other -> other
      end

      update_in(generated.children, &Enum.map(&1, clip_marks))
    end

    @tag :resvg
    test "the culled drawing is pixel for pixel the unculled clipped one" do
      clipped = applied(true)
      culled = Chart.generate(clipped, resolve: :literal)
      assert culled != unculled(clipped)
      assert pixels(culled) == pixels(unculled(clipped))
    end
  end
end
