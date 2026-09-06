defmodule Visualize.Shape.CurveBasisTest do
  @moduledoc "D-33: `Curve.basis/1` is d3-shape's curveBasis."
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Visualize.IR.Path
  alias Visualize.Shape.Curve

  defp d(points), do: points |> Curve.basis() |> Path.to_string()

  test "three points, hand-derived from the d3 formula" do
    assert d([{0, 0}, {6, 6}, {12, 0}]) == "M0,0L1,1C2,2,4,4,6,4C8,4,10,2,11,1L12,0"
  end

  test "four points" do
    assert d([{0, 0}, {6, 6}, {12, 0}, {18, 6}]) ==
             "M0,0L1,1C2,2,4,4,6,4C8,4,10,2,12,2C14,2,16,4,17,5L18,6"
  end

  test "two points fall back to a straight line" do
    assert d([{0, 0}, {10, 5}]) == "M0,0L10,5"
  end

  property "n points give n − 1 curves between two lines, each continuing the last" do
    check all(
            points <-
              uniq_list_of(
                tuple({integer(0..1000), integer(0..1000)}),
                min_length: 3,
                max_length: 12
              )
          ) do
      %Path{commands: commands} = Curve.basis(points)
      kinds = Enum.map(commands, &elem(&1, 0))
      assert kinds == [:M, :L] ++ List.duplicate(:C, length(points) - 1) ++ [:L]
      assert List.first(commands) == {:M, elem(hd(points), 0), elem(hd(points), 1)}
      {lx, ly} = List.last(points)
      assert List.last(commands) == {:L, lx, ly}
    end
  end
end
