defmodule Visualize.DataTest do
  @moduledoc "`Visualize.Data.ticks/3` after #13 (spec/08 §5.2)."
  use ExUnit.Case, async: true

  alias Visualize.Data

  describe "ticks/3" do
    test "no longer raises: max/2 resolves to Kernel.max/2, not Data.max/2" do
      assert Data.ticks(0, 10, 5) == [0.0, 2.0, 4.0, 6.0, 8.0, 10.0]
    end

    test "uses the d3 thresholds" do
      assert Data.ticks(0, 1, 10) == [0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0]
      assert Data.ticks(0, 100, 3) == [0.0, 50.0, 100.0]
      assert Data.ticks(0, 100, 7) == [0.0, 20.0, 40.0, 60.0, 80.0, 100.0]
    end

    test "runs from the first multiple at or above start to the last at or below stop" do
      assert Data.ticks(0.3, 2.7, 5) == [0.5, 1.0, 1.5, 2.0, 2.5]
    end

    test "a zero span returns the value itself" do
      assert Data.ticks(4, 4, 10) == [4]
    end

    test "a span with no multiple of the step inside it yields no ticks" do
      # Found by the log-ticks property: `0..-1` descends and emitted two ticks outside.
      assert Data.ticks(500_000_000.0005, 515_625_000.01, 1) == []
    end

    test "a descending span yields the same ticks descending" do
      assert Data.ticks(10, 0, 5) == [10.0, 8.0, 6.0, 4.0, 2.0, 0.0]
    end

    test "a non-positive count is a caller error" do
      assert_raise FunctionClauseError, fn -> Data.ticks(0, 1, 0) end
    end
  end

  describe "slope/1,2 (spec/08 §5.1, #769)" do
    test "empty input and one point are nil" do
      assert Data.slope([]) == nil
      assert Data.slope([4]) == nil
      assert Data.slope([{1, 2}]) == nil
      assert Data.slope([%{v: 1}], & &1.v) == nil
    end

    test "zero x-variance is nil" do
      assert Data.slope([{3, 1}, {3, 9}, {3, 4}]) == nil
    end

    test "numbers are read over their index" do
      assert Data.slope([1, 3, 5, 7]) == 2.0
      assert Data.slope([5, 5, 5]) == 0.0
      assert Data.slope([10, 7]) == -3.0
    end

    test "is the least-squares slope of {x, y} points" do
      # Σ(x − x̄)(y − ȳ) = 9 over Σ(x − x̄)² = 5.
      assert_in_delta Data.slope([{0, 1}, {1, 4}, {2, 4}, {3, 7}]), 1.8, 1.0e-12
      assert Data.slope([{0, 0}, {10, 5}]) == 0.5
    end

    test "an accessor returns a number or a point" do
      rows = [%{t: 0, v: 2}, %{t: 5, v: 4}, %{t: 10, v: 6}]
      assert Data.slope(rows, & &1.v) == 2.0
      assert Data.slope(rows, &{&1.t, &1.v}) == 0.4
    end

    test "a mixed list reads each element by its form" do
      assert Data.slope([0, {1, 1}, 2]) == 1.0
    end
  end

  describe "delta/1,2 (spec/08 §5.1, #769)" do
    test "empty input is nil" do
      assert Data.delta([]) == nil
      assert Data.delta([], & &1.v) == nil
    end

    test "one element is zero" do
      assert Data.delta([7]) == 0
      assert Data.delta([%{v: 2.5}], & &1.v) == 0.0
    end

    test "is the last value minus the first, by accessor" do
      assert Data.delta([3, 100, -4, 8]) == 5
      assert Data.delta([%{v: 10}, %{v: 0}, %{v: 4}], & &1.v) == -6
    end
  end
end
