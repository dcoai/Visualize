defmodule Visualize.Shape.CurveClosedTest do
  @moduledoc "The closed loops of spec/04 §5.3 (#393): d3-shape's curveBasisClosed and curveCardinalClosed."
  use ExUnit.Case, async: true

  alias Visualize.IR.Path
  alias Visualize.Shape.Curve

  # A square, clockwise from the top-left.
  @square [{0, 0}, {12, 0}, {12, 12}, {0, 12}]

  test "basis_closed: n curves round the loop from the knot before the first point, no lead-in, closed" do
    d = @square |> Curve.basis_closed() |> Path.to_string()
    # The first knot is (p2 + 4p3 + p0)/6 = (12 + 0 + 0, 12 + 48 + 0)/6 = (2, 10).
    assert d == "M2,10C0,8,0,4,2,2C4,0,8,0,10,2C12,4,12,8,10,10C8,12,4,12,2,10Z"
    %Path{commands: commands} = Curve.basis_closed(@square)
    assert Enum.count(commands, &match?({:C, _, _, _, _, _, _}, &1)) == 4
    assert List.last(commands) == :Z
  end

  test "cardinal_closed: from the first point, one curve per point cyclically, closed; tension 1 is the polygon" do
    %Path{commands: commands} = Curve.cardinal_closed(@square, 0)
    assert hd(commands) == {:M, 0, 0}
    assert Enum.count(commands, &match?({:C, _, _, _, _, _, _}, &1)) == 4
    assert List.last(commands) == :Z
    # The last curve returns to the first point.
    assert {:C, _, _, _, _, 0, 0} = Enum.at(commands, 4)
    # Tension 1 makes k = 0: the control points sit on the points, the polygon.
    tight = @square |> Curve.cardinal_closed(1) |> Path.to_string()
    assert tight == "M0,0C0,0,12,0,12,0C12,0,12,12,12,12C12,12,0,12,0,12C0,12,0,0,0,0Z"
  end

  test "fewer than three points close a straight line; generate/3 dispatches both" do
    assert Curve.basis_closed([{0, 0}, {4, 4}]) |> Path.to_string() == "M0,0L4,4Z"
    assert Curve.cardinal_closed([{0, 0}, {4, 4}], 0) |> Path.to_string() == "M0,0L4,4Z"
    assert Curve.generate(:basis_closed, @square) == Curve.basis_closed(@square)

    assert Curve.generate(:cardinal_closed, @square, tension: 0.5) ==
             Curve.cardinal_closed(@square, 0.5)
  end
end
