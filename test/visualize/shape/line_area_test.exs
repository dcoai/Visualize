defmodule Visualize.Shape.LineAreaTest do
  @moduledoc "Regressions for the `Line`, `Area`, `Curve` and `LineNx` defects of #14 (#25)."
  use ExUnit.Case, async: true

  alias Visualize.Backend.SVG
  alias Visualize.IR.Path
  alias Visualize.Shape
  alias Visualize.Shape.{Area, Curve, Line, LineNx}

  @data [{0, 0}, {10, 5}, {20, 2}, {30, 8}, {40, 3}, {50, 6}]
  # Data 2 and 4 are undefined: runs are [0, 1], [3], [5] → only the first run draws.
  defp gap?({x, _y}), do: x not in [20, 40]

  describe "Line.defined/2 (spec/04 §1.2, D-18)" do
    test "an undefined datum breaks the line into subpaths" do
      d =
        Line.new()
        |> Line.defined(fn {x, _} -> x != 20 end)
        |> Line.generate(@data)

      assert d == "M0,0L10,5M30,8L40,3L50,6"
    end

    test "a run of one point draws nothing" do
      d = Line.new() |> Line.defined(&gap?/1) |> Line.generate(@data)
      assert d == "M0,0L10,5"
    end

    test "no run of two points is an empty path" do
      path = Line.new() |> Line.defined(fn {x, _} -> rem(x, 20) == 0 end)
      assert Line.generate_path(path, @data) == Path.new()
    end

    test "each subpath is generated through the curve" do
      d =
        Line.new()
        |> Line.defined(fn {x, _} -> x != 20 end)
        |> Line.curve(:step_after)
        |> Line.generate(@data)

      assert d == "M0,0H10V5M30,8H40V3H50V6"
    end

    test "a nil predicate keeps every datum" do
      assert Line.new() |> Line.generate(@data) =~ ~r/^M0,0(L\d+,\d+){5}$/
    end
  end

  describe "Area.defined/2 (spec/04 §1.2, D-18)" do
    test "an undefined datum breaks the area into separate closed rings" do
      d =
        Area.new()
        |> Area.defined(fn {x, _} -> x != 20 end)
        |> Area.generate(@data)

      assert d == "M0,0L10,5L10,0L0,0ZM30,8L40,3L50,6L50,0L40,0L30,0Z"
    end

    test "a run of one point draws nothing" do
      d = Area.new() |> Area.defined(&gap?/1) |> Area.generate(@data)
      assert d == "M0,0L10,5L10,0L0,0Z"
    end
  end

  describe "Line.x/2 and Line.y/2 accept a constant (spec/04 §1.1, D-20)" do
    test "a number is a constant accessor" do
      d = Line.new() |> Line.x(5) |> Line.y(fn {_, y} -> y end) |> Line.generate(@data)
      assert String.starts_with?(d, "M5,0L5,5")
    end

    test "through the facade" do
      d = Shape.line() |> Shape.y(7) |> Shape.generate([{0, 1}, {10, 2}])
      assert d == "M0,7L10,7"
    end
  end

  describe "Curve.natural/1 (spec/04 §5.6, D-19)" do
    test "matches d3-shape's control points for a three-point spline" do
      # x = [0, 1, 2]: p = [1/3, 4/3], q = [2/3, 5/3]; y = [0, 1, 0]: p = [1/2, 1], q = [1, 1/2].
      d = Curve.natural([{0, 0}, {1, 1}, {2, 0}]) |> SVG.path_data()
      assert d == "M0,0C0.3333,0.5,0.6667,1,1,1C1.3333,1,1.6667,0.5,2,0"
    end

    test "is C1-continuous: control points mirror across every interior knot" do
      points = [{0, 0}, {1, 1}, {2, 0}, {3, 3}, {4, 1}]
      %Path{commands: [{:M, _, _} | curves]} = Curve.natural(points)

      curves
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.each(fn [{:C, _, _, x2, y2, x, y}, {:C, x1, y1, _, _, _, _}] ->
        assert_in_delta x - x2, x1 - x, 1.0e-9
        assert_in_delta y - y2, y1 - y, 1.0e-9
      end)
    end

    test "is not a straight line expressed as a cubic" do
      %Path{commands: [{:M, _, _}, {:C, x1, y1, _, _, _, _} | _]} =
        Curve.natural([{0, 0}, {1, 1}, {2, 0}])

      # The old implementation put every control point on the chord: (1/3, 1/3) here.
      refute_in_delta y1 / x1, 1.0, 1.0e-6
    end

    test "two points fall back to a straight line" do
      assert Curve.natural([{0, 0}, {5, 5}]) == Curve.linear([{0, 0}, {5, 5}])
    end
  end

  describe "LineNx.generate_path/3 :curve (spec/04 §10.2, D-20)" do
    test "the default is linear" do
      assert LineNx.generate_path([0, 1, 2], [0, 1, 0]) |> SVG.path_data() == "M0,0L1,1L2,0"
    end

    test "a step curve is honored on the scaled points" do
      d =
        LineNx.generate_path([0, 1, 2], [0, 1, 0],
          x_range: {0, 20},
          x_domain: {0, 2},
          curve: :step_after
        )
        |> SVG.path_data()

      assert d == "M0,0H10V1H20V0"
    end

    test "curve options pass through" do
      opts = [curve: :cardinal, curve_opts: [tension: 1]]
      tight = LineNx.generate_path([0, 1, 2, 3], [0, 1, 0, 1], opts) |> SVG.path_data()

      loose =
        LineNx.generate_path([0, 1, 2, 3], [0, 1, 0, 1], curve: :cardinal) |> SVG.path_data()

      assert tight != loose
    end
  end
end
