defmodule Visualize.Shape.BandTest do
  @moduledoc "The `Band` state-timeline mark (spec/04 §11, D-26)."
  use ExUnit.Case, async: true

  alias Visualize.Backend.SVG
  alias Visualize.IR.Element
  alias Visualize.Shape
  alias Visualize.Shape.Band

  # A day in three states, in pixels already; the third block is zero-width.
  @states [
    %{from: 0, to: 40, state: :ok},
    %{from: 40, to: 70, state: :down},
    %{from: 70, to: 70, state: :ok},
    %{from: 70, to: 100, state: :degraded}
  ]

  @colours %{ok: "#2a9d8f", down: "#e76f51", degraded: "#e9c46a"}

  defp band do
    Band.new()
    |> Band.x0(:from)
    |> Band.x1(:to)
    |> Band.y(20)
    |> Band.height(12)
    |> Band.fill(fn d -> @colours[d.state] end)
  end

  describe "generate/2" do
    test "one rect per datum, index-aligned, filled per datum" do
      rects = Band.generate(band(), @states)
      assert length(rects) == 4

      assert Enum.map(rects, & &1.attrs) == [
               %{x: 0, y: 20, width: 40, height: 12},
               %{x: 40, y: 20, width: 30, height: 12},
               %{x: 70, y: 20, width: 0, height: 12},
               %{x: 70, y: 20, width: 30, height: 12}
             ]

      assert Enum.map(rects, & &1.style) == [
               %{class: "band", fill: "#2a9d8f"},
               %{class: "band", fill: "#e76f51"},
               %{class: "band", fill: "#2a9d8f"},
               %{class: "band", fill: "#e9c46a"}
             ]

      assert Enum.all?(rects, &(&1.type == :rect))
    end

    test "renders as rect elements" do
      [first | _] = Band.generate(band(), @states)
      svg = first |> SVG.render_element() |> IO.iodata_to_binary()
      assert svg =~ ~r/<rect /
      assert svg =~ ~s(fill="#2a9d8f")
      assert svg =~ ~s(width="40")
    end

    test "edges are ordered whichever way they are given" do
      [rect] = Band.new() |> Band.generate([{50, 10}])
      assert rect.attrs == %{x: 10, y: 0, width: 40, height: 10}
    end

    test "the fill key is omitted when unset or nil" do
      [plain] = Band.new() |> Band.generate([{0, 10}])
      assert plain.style == %{class: "band"}

      [absent] =
        Band.new()
        |> Band.x0(:a)
        |> Band.x1(:b)
        |> Band.fill(:colour)
        |> Band.generate([%{a: 0, b: 10}])

      assert absent.style == %{class: "band"}
    end

    test "a string fill is a constant" do
      [rect] = Band.new() |> Band.fill("steelblue") |> Band.generate([{0, 10}])
      assert rect.style.fill == "steelblue"
    end

    test "an empty list yields []" do
      assert Band.generate(band(), []) == []
    end
  end

  describe "generate_path/2" do
    test "one closed rectangle per datum" do
      d = band() |> Band.generate_path(@states) |> SVG.path_data()
      assert d == "M0,20H40V32H0ZM40,20H70V32H40ZM70,20H70V32H70ZM70,20H100V32H70Z"
    end

    test "an empty list is an empty path" do
      assert Band.generate_path(band(), []) == Visualize.IR.Path.new()
    end
  end

  describe "through the facade" do
    test "every setter and both generators dispatch" do
      shape =
        Shape.band()
        |> Shape.x0(:from)
        |> Shape.x1(:to)
        |> Shape.y(5)
        |> Shape.height(3)
        |> Shape.fill(:state)

      assert [%Element{type: :rect, attrs: %{y: 5, height: 3}}] =
               Shape.generate(shape, [%{from: 1, to: 2, state: "red"}])

      assert Shape.generate_path(shape, [%{from: 1, to: 2}]) |> SVG.path_data() ==
               "M1,5H2V8H1Z"
    end
  end
end
