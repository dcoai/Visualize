defmodule Visualize.Chart.Builder.PlaceTest do
  @moduledoc """
  Where a drop on the graph lands and what a component means there (spec/14 §18.16):
  the region of a point against the frame, every row of the component table, an axis
  bringing its scale, a legend needing an ordinal scale, and a library entry's placement.
  """
  use ExUnit.Case, async: true

  alias Visualize.Chart.Builder.Place

  doctest Place

  # A *geometry*, not a design frame: the preview's box and the design's margin.
  @frame %{size: %{width: 400, height: 200}, margin: %{top: 20, right: 20, bottom: 30, left: 40}}
  @design %{
    frames: %{
      main: Map.merge(@frame, %{scales: %{x: %{kind: :linear}, colour: %{kind: :ordinal}}})
    }
  }

  describe "region/2" do
    test "the plot, the four bands, and the corners going to the top or the bottom" do
      assert Place.region({200, 100}, @frame) == :plot
      assert Place.region({40, 20}, @frame) == :plot
      assert Place.region({380, 170}, @frame) == :plot
      assert Place.region({200, 10}, @frame) == :top
      assert Place.region({200, 185}, @frame) == :bottom
      assert Place.region({20, 100}, @frame) == :left
      assert Place.region({390, 100}, @frame) == :right
      # Corners: the top and the bottom win.
      assert Place.region({5, 5}, @frame) == :top
      assert Place.region({395, 5}, @frame) == :top
      assert Place.region({5, 195}, @frame) == :bottom
      assert Place.region({395, 195}, @frame) == :bottom
    end
  end

  describe "node/4" do
    test "an axis takes the side of its band and the scale that side reads, bringing it when missing" do
      assert {:sites, [%{kind: :axis, body: %{scale: :x, side: :top}}]} =
               Place.node(:axis, :top, @design, {0, 0})

      assert {:sites, [%{kind: :axis, body: %{scale: :x, side: :bottom}}]} =
               Place.node(:axis, :plot, @design, {0, 0})

      assert {:sites,
              [
                %{kind: :scale, body: %{kind: :linear, domain: :auto}, key: :y},
                %{kind: :axis, body: %{scale: :y, side: :right}, key: nil}
              ]} = Place.node(:axis, :right, @design, {0, 0})
    end

    test "a title is a title everywhere but the bottom, where it is a caption" do
      for region <- [:top, :left, :right, :plot] do
        assert {:sites, [%{kind: :label, body: %{anchor: :title, text: ["Title"]}}]} =
                 Place.node(:title, region, @design, {0, 0})
      end

      assert {:sites, [%{kind: :label, body: %{anchor: :caption}}]} =
               Place.node(:title, :bottom, @design, {0, 0})
    end

    test "a label takes the anchor its region implies, a plot drop the nearest corner" do
      anchors =
        for region <- [:top, :bottom, :left, :right] do
          {:sites, [%{body: %{anchor: anchor}}]} = Place.node(:label, region, @design, {0, 0})
          anchor
        end

      assert anchors == [:subtitle, {:axis, :x}, {:axis, :y}, {:frame, :top_right}]

      assert {:sites, [%{body: %{anchor: {:frame, :top_left}}}]} =
               Place.node(:label, :plot, @design, {56, 43})

      assert {:sites, [%{body: %{anchor: {:frame, :bottom_right}}}]} =
               Place.node(:label, :plot, @design, {564, 347})
    end

    test "a legend takes the first ordinal scale and the nearest of the eight positions" do
      assert Place.node(:legend, :top, @design, {0, 0}) ==
               {:legend, %{scale: :colour, position: :top}}

      assert Place.node(:legend, :left, @design, {0, 0}) ==
               {:legend, %{scale: :colour, position: :left}}

      assert Place.node(:legend, :plot, @design, {56, 43}) ==
               {:legend, %{scale: :colour, position: :top_left}}

      assert Place.node(:legend, :plot, @design, {310, 43}) ==
               {:legend, %{scale: :colour, position: :top}}

      assert Place.node(:legend, :plot, @design, {564, 195}) ==
               {:legend, %{scale: :colour, position: :right}}

      assert Place.node(:legend, :plot, @design, {564, 358}) ==
               {:legend, %{scale: :colour, position: :bottom_right}}

      assert Place.node(
               :legend,
               :plot,
               %{frames: %{main: %{scales: %{x: %{kind: :linear}}}}},
               {0, 0}
             ) ==
               {:error, :no_scale}
    end

    test "a mark is a mark of its type wherever it lands" do
      for region <- [:top, :bottom, :left, :right, :plot] do
        assert Place.node({:mark, :circle}, region, @design, {0, 0}) ==
                 {:sites, [%{kind: :mark, body: %{type: :circle}, key: nil}]}
      end
    end
  end

  describe "guess/2" do
    test "the last mark's source first, else the first by name; fields over required channels" do
      design = %{
        sources: %{b: %{fields: [:p, :q]}, a: %{fields: [:hour, :value, :extra]}},
        marks: [%{type: :line, data: :b, channels: %{}}]
      }

      assert Place.guess(design, :line) == %{data: :b, channels: %{x: :p, y: :q}}

      assert Place.guess(Map.delete(design, :marks), :line) == %{
               data: :a,
               channels: %{x: :hour, y: :value}
             }

      assert Place.guess(Map.delete(design, :marks), :rect) == %{
               data: :a,
               channels: %{x0: :hour, x1: :value, y0: :extra}
             }

      assert Place.guess(%{sources: %{s: %{fields: [:only]}}}, :line) == %{
               data: :s,
               channels: %{x: :only}
             }

      assert Place.guess(%{sources: %{}}, :line) == %{}
      # A mark placed carries the guess in its body.
      assert {:sites, [%{body: %{type: :circle, data: :a, channels: %{x: :hour, y: :value}}}]} =
               Place.node({:mark, :circle}, :plot, Map.delete(design, :marks), {0, 0})
    end
  end

  test "home/1 is where the keyboard and the + menu place a component" do
    assert Enum.map([:axis, :title, :label, :legend, {:mark, :line}], &Place.home/1) ==
             [:bottom, :top, :bottom, :plot, :plot]
  end

  test "geometry/1 is the design's size and margin over the schema's defaults" do
    assert Place.geometry(@design) == %{@frame | size: %{width: 600, height: 400}}

    assert Place.geometry(%{frames: %{main: %{margin: %{top: 900}}}}).size == %{
             width: 600,
             height: 400
           }

    assert Place.geometry(%{frames: %{main: %{margin: %{top: 5}}}}).margin.top == 5
  end

  describe "the graph is the box (spec/14 §18.4, §18.16, #613)" do
    @two %{
      frames: %{
        history: %{kind: :cartesian, box: [0, 0, 0.5, 1]},
        now: %{kind: :cartesian, box: [0.5, 0, 0.5, 1], margin: %{left: 10}},
        inset: %{kind: :polar, box: [0.6, 0.1, 0.3, 0.3], z: 1}
      }
    }

    test "frames/2 is every frame's pixel box at the measured size, in drawing order" do
      frames = Place.frames(@two, {1000, 500})
      assert Enum.map(frames, & &1.name) == [:history, :now, :inset]

      assert %{x: 500.0, y: +0.0, size: %{width: 500.0, height: 500.0}, margin: %{left: 10}} =
               Enum.at(frames, 1)

      # The same fractions at another size: a resize keeps the proportions.
      assert %{x: 400.0, size: %{width: 400.0}} = Enum.at(Place.frames(@two, {800, 300}), 1)
    end

    test "a frame placed by a cell is read through the layout; one that does not read is the whole box" do
      design = %{
        layout: %{columns: [3, 1]},
        frames: %{a: %{cell: [0, 0]}, b: %{cell: [1, 0]}, c: %{box: [:x, 0, 1, 1]}}
      }

      assert [a, b, c] = Place.frames(design, {800, 400})
      assert {a.x, a.size.width} == {0.0, 600.0}
      assert {b.x, b.size.width} == {600.0, 200.0}
      assert {c.x, c.size.width} == {0.0, 800.0}
    end

    test "spot/3 reads a point in the topmost frame under it, else the nearest" do
      # Over the inset, which is drawn last, though `now` is under it too.
      assert %{frame: :inset, point: {50.0, 20.0}} = Place.spot(@two, {1000, 500}, {650, 70})
      assert %{frame: :history} = Place.spot(@two, {1000, 500}, {100, 100})

      # The second frame's own margin: its left band, at its own 10 px.
      spot = Place.spot(@two, {1000, 500}, {505, 250})
      assert spot.frame == :now
      assert Place.region(spot.point, spot.geometry) == :left
      assert Place.region({spot.point |> elem(0) |> Kernel.+(10), 250}, spot.geometry) == :plot

      # Outside every box, the nearest frame.
      assert %{frame: :now} = Place.spot(@two, {1000, 500}, {1100, 250})
    end

    test "a label dropped in a frame's plot takes the corner nearest in that frame" do
      # x 700 is left of the middle of `now`'s plot (500 + 10 + 235), though right of the
      # middle of the whole box: the corner is the frame's.
      spot = Place.spot(@two, {1000, 500}, {700, 450})

      assert {:sites, [%{body: %{anchor: {:frame, :bottom_left}}}]} =
               Place.node(:label, :plot, @two, spot)

      # The bare point of a single-frame design reads as it did, at the default size.
      assert {:sites, [%{body: %{anchor: {:frame, :top_left}}}]} =
               Place.node(:label, :plot, @design, {56, 43})
    end
  end

  test "the palette's rows name every component and every mark type" do
    words = Place.components() |> Enum.map(&elem(&1, 0)) |> Enum.map(&Atom.to_string/1)
    assert Enum.take(words, 4) == ~w(axis legend title label)
    assert "mark:rose" in words and "mark:rect" in words
    for word <- words, do: assert({:ok, _} = Place.component(word))
  end
end
