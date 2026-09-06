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
end
