defmodule Visualize.BenchmarkTest do
  @moduledoc "The stream benchmark measures elapsed time from its clock alone (spec/09 §8.3, D-39)."
  use ExUnit.Case, async: true

  alias Visualize.Benchmark

  # A clock that advances ten milliseconds on every reading.
  defp fake_clock do
    {:ok, agent} = Agent.start_link(fn -> 0 end)
    fn -> Agent.get_and_update(agent, &{&1, &1 + 10}) end
  end

  test "frames, elapsed time and fps come from clock readings only" do
    results = Benchmark.stream_benchmark(duration_ms: 100, data_points: 8, clock: fake_clock())

    for key <- [:svg, :canvas, :hybrid, :hybrid_incremental, :canvas_incremental] do
      r = results[key]
      # Readings at 0 (start), then 10, 20, …, 100: nine frames render before the budget ends.
      assert r.frames == 9
      assert r.actual_duration_ms == 100
      assert_in_delta r.fps, 90.0, 1.0e-9
      assert r.data_points_per_second == 720
      assert r.total_bytes > 0
    end

    assert results.hybrid.static_svg_bytes > 0
    assert results.comparison.svg_fps == 90.0
    assert is_binary(Benchmark.format_stream_report(results))
  end
end
