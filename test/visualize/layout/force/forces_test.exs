defmodule Visualize.Layout.Force.ForcesTest do
  @moduledoc """
  The collision force of spec/06 §8.2 (D-44): every overlapping pair is pushed apart
  symmetrically, so momentum is conserved and node order does not matter.
  """
  use ExUnit.Case, async: true

  alias Visualize.Layout.Force.Forces

  defp node(id, x, y), do: %{id: id, x: x, y: y, vx: 0, vy: 0, fx: nil, fy: nil}

  test "two overlapping nodes receive equal and opposite velocities" do
    [a, b] = Forces.apply_collision([node(:a, 0, 0), node(:b, 6, 0)], 1, radius: 5)
    assert a.vx < 0 and b.vx > 0
    assert_in_delta a.vx, -b.vx, 1.0e-12
    assert a.vy == 0 and b.vy == 0
    # Each moves by half of (r - d) / d * strength * alpha: (10 - 6) / 6 * 0.5 = 1/3 along 6.
    assert_in_delta b.vx, 6 * (10 - 6) / 6 * 0.5, 1.0e-12
  end

  test "momentum is conserved over a three-node cluster and does not depend on order" do
    nodes = [node(:a, 0, 0), node(:b, 4, 1), node(:c, 1, 5)]
    pushed = Forces.apply_collision(nodes, 0.7, radius: 4, strength: 0.8)
    assert_in_delta Enum.reduce(pushed, 0, &(&1.vx + &2)), 0, 1.0e-12
    assert_in_delta Enum.reduce(pushed, 0, &(&1.vy + &2)), 0, 1.0e-12
    assert Enum.all?(pushed, &(&1.vx != 0 or &1.vy != 0))

    reversed = Forces.apply_collision(Enum.reverse(nodes), 0.7, radius: 4, strength: 0.8)
    assert Enum.sort_by(reversed, & &1.id) == Enum.sort_by(pushed, & &1.id)
  end

  test "non-overlapping nodes are untouched and zero iterations apply nothing" do
    nodes = [node(:a, 0, 0), node(:b, 30, 0)]
    assert Forces.apply_collision(nodes, 1, radius: 5) == nodes

    assert Forces.apply_collision([node(:a, 0, 0), node(:b, 1, 0)], 1, radius: 5, iterations: 0) ==
             [node(:a, 0, 0), node(:b, 1, 0)]
  end
end
