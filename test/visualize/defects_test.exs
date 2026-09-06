defmodule Visualize.DefectsTest do
  @moduledoc """
  Regression tests for the defects fixed in #6 (proposal #4).
  """
  use ExUnit.Case, async: true

  alias Visualize.Data
  alias Visualize.Geo.Projection
  alias Visualize.IR.Path
  alias Visualize.IR.Transform
  alias Visualize.Shape
  alias Visualize.Shape.Curve

  describe "Data.range/3" do
    test "integer step" do
      assert Data.range(0, 5) == [0, 1, 2, 3, 4]
    end

    test "fractional step" do
      assert Data.range(0, 1, 0.25) == [0, 0.25, 0.5, 0.75]
    end

    test "negative step" do
      assert Data.range(5, 0, -2) == [5, 3, 1]
    end

    test "empty when stop is not past start" do
      assert Data.range(3, 3) == []
      assert Data.range(5, 1) == []
    end
  end

  describe "Transform.scale" do
    test "one number creates a uniform scale" do
      assert Transform.scale(2).operations == [{:scale, 2, 2}]
    end

    test "two numbers create a scale transform" do
      assert Transform.scale(2, 3).operations == [{:scale, 2, 3}]
    end

    test "a transform and one number appends a uniform scale" do
      t = Transform.new() |> Transform.translate(1, 1) |> Transform.scale(2)
      assert t.operations == [{:translate, 1, 1}, {:scale, 2, 2}]
    end
  end

  describe "Projection clip angle" do
    test "a point beyond the clip angle is clipped" do
      proj = Projection.new(:stereographic) |> Projection.clip_angle(90)
      assert Projection.project(proj, 0, 0) != nil
      assert Projection.project(proj, 120, 0) == nil
    end

    test "no clip angle never clips" do
      proj = Projection.new(:equirectangular)
      assert Projection.project(proj, 170, 80) != nil
    end
  end

  describe "step curves" do
    @points [{0, 0}, {10, 5}, {20, 2}]

    defp step_path(curve) do
      Shape.line()
      |> Shape.x(&elem(&1, 0))
      |> Shape.y(&elem(&1, 1))
      |> Shape.curve(curve)
      |> Shape.generate(@points)
    end

    test ":step steps at the midpoint" do
      assert step_path(:step) == "M0,0H5V5H15V2H20"
    end

    test ":step_before steps at the start, with no zero-length segment" do
      assert step_path(:step_before) == "M0,0V5H10V2H20"
    end

    test ":step_after steps at the end, with no zero-length segment" do
      assert step_path(:step_after) == "M0,0H10V5H20V2"
    end
  end

  describe "spline options" do
    @spline_points [{0, 0}, {10, 8}, {20, 1}, {30, 9}]

    test "cardinal tension changes the control points" do
      tight = Curve.cardinal(@spline_points, 1) |> Path.to_string()
      loose = Curve.cardinal(@spline_points, 0) |> Path.to_string()
      assert tight != loose
    end

    test "catmull_rom alpha changes the control points" do
      uniform = Curve.catmull_rom(@spline_points, 0) |> Path.to_string()
      chordal = Curve.catmull_rom(@spline_points, 1) |> Path.to_string()
      assert uniform != chordal
    end
  end

  describe "Backend.CanvasBinary colour opacity" do
    alias Visualize.Backend.CanvasBinary

    test "atom colours honour opacity on SVG elements" do
      opaque = Visualize.SVG.Element.rect(%{x: 0, y: 0, width: 1, height: 1, fill: :red})

      faded =
        Visualize.SVG.Element.rect(%{x: 0, y: 0, width: 1, height: 1, fill: :red, opacity: 0.5})

      assert CanvasBinary.encode_element!(opaque) != CanvasBinary.encode_element!(faded)
    end
  end
end

defmodule Visualize.NegativeZeroTest do
  @moduledoc "D-32: no `d` serialiser prints `-0`."
  use ExUnit.Case, async: true

  alias Visualize.Backend.SVG
  alias Visualize.IR.Path
  alias Visualize.Shape.Arc

  test "path_data/1 and IR.Path.to_string/1 fold a zero that rounds negative" do
    path = %Path{commands: [{:M, -0.0, -0.00001}, {:L, 0.00004, -0.0}]}
    assert SVG.path_data(path) == "M0,0L0,0"
    assert Path.to_string(path) == "M0,0L0,0"
  end

  test "an arc sector straddling twelve o'clock ends at the origin without a sign" do
    d =
      Arc.new()
      |> Arc.outer_radius(100)
      |> Arc.start_angle(-:math.pi() / 4)
      |> Arc.end_angle(:math.pi() / 4)
      |> Arc.generate(%{})

    assert String.ends_with?(d, "L0,0Z")
  end
end
