defmodule Visualize.NoWallClockTest do
  @moduledoc """
  No default-suite test asserts on wall-clock time; a timing is a `:benchmark` test
  (spec/12 §6, D-114, #462, #271).

  A cost claim is a claim about the algorithm, and a clock reading of it is a claim about
  the machine: `Visualize.Chart.CompiledTest`'s scroll test compared two `:timer.tc`
  readings and failed under load while its algorithm was sound, as the contour test had
  before it (#271). This scans the library's and the examples' test files for a clock
  read and fails on one that is not inside a test tagged `@tag :benchmark` — in the
  attributes directly above it — nor in a module tagged `@moduletag :benchmark`. A helper
  that reads a clock outside any test fails too: a benchmark times inline. Assert work
  with `Visualize.Work.reductions/1` or a count the code exposes instead.
  """
  use ExUnit.Case, async: true

  # The counter the suite asserts work with instead.
  doctest Visualize.Work

  # A read of a clock that measures how long something took. A fake clock passed in
  # (`clock:`, `at:`, `now:`) is not one, and neither is a timeout.
  @clock ~r/:timer\.tc\b|monotonic_time|System\.(os|system)_time|:os\.(system_time|timestamp|perf_counter)|:erlang\.system_time|:erlang\.statistics\(\s*:(wall_clock|runtime)/

  @definition ~r/^\s*(test|property|describe)\s+["']|^\s*(defp?|defmacrop?)\s/
  @runnable ~r/^\s*(test|property)\s+["']/
  @benchmark_tag ~r/^\s*@tag\s+(:benchmark\b|benchmark:\s*true)/
  @benchmark_module ~r/^\s*@moduletag\s+(:benchmark\b|benchmark:\s*true)/

  test "no test outside :benchmark reads a wall clock" do
    files = Path.wildcard("test/**/*.exs") ++ Path.wildcard("examples/test/**/*.exs")
    files = files -- [Path.relative_to_cwd(__ENV__.file)]
    assert length(files) > 100, "the scan found #{length(files)} test files: is the cwd the root?"

    violations = Enum.flat_map(files, &violations(&1, File.read!(&1)))

    assert violations == [],
           "a default-suite test reads a wall clock (spec/12 §6, D-114). Assert the work " <>
             "done — `Visualize.Work.reductions/1`, or a count the code exposes — or tag " <>
             "the test `@tag :benchmark`:\n" <> Enum.join(violations, "\n")
  end

  describe "the scan" do
    test "finds a timed assertion in an untagged test" do
      source = """
      defmodule ProbeTest do
        use ExUnit.Case

        test "a scroll is cheap" do
          {us, _} = :timer.tc(fn -> :ok end)
          assert us < 1_000
        end
      end
      """

      assert ["probe_test.exs:5: " <> _] = violations("probe_test.exs", source)
    end

    test "finds a clock read in a helper outside any test, and every kind of clock" do
      source = """
      defmodule ProbeTest do
        use ExUnit.Case

        defp ms(fun), do: elem(:timer.tc(fun), 0) / 1000

        @tag :benchmark
        test "times" do
          t0 = System.monotonic_time()
        end

        test "untagged" do
          a = System.monotonic_time(:millisecond)
          b = :erlang.statistics(:wall_clock)
          c = System.os_time()
        end
      end
      """

      assert [l4, l12, l13, l14] = violations("probe_test.exs", source)
      assert l4 =~ ~r/^probe_test\.exs:4: /
      assert l12 =~ ~r/^probe_test\.exs:12: /
      assert l13 =~ ~r/^probe_test\.exs:13: /
      assert l14 =~ ~r/^probe_test\.exs:14: /
    end

    test "passes a test tagged :benchmark among its attributes, and a benchmark module" do
      tagged = """
      defmodule ProbeTest do
        use ExUnit.Case

        # Stated, not gated.
        @tag :benchmark
        @tag timeout: 60_000
        test "times" do
          {us, _} = :timer.tc(fn -> :ok end)
          IO.puts(us)
        end
      end
      """

      assert violations("probe_test.exs", tagged) == []

      module = """
      defmodule ProbeTest do
        use ExUnit.Case
        @moduletag :benchmark

        defp ms(fun), do: elem(:timer.tc(fun), 0) / 1000
      end
      """

      assert violations("probe_test.exs", module) == []
    end

    test "a tag above another test does not cover the next one, and a comment is not a read" do
      source = """
      defmodule ProbeTest do
        use ExUnit.Case

        @tag :benchmark
        test "times" do
          :timer.tc(fn -> :ok end)
        end

        test "untagged" do
          # :timer.tc would be wrong here
          :timer.tc(fn -> :ok end)
        end
      end
      """

      assert ["probe_test.exs:11: " <> _] = violations("probe_test.exs", source)
    end
  end

  # `"path:line: text"` for every clock read in `source` outside a benchmark.
  defp violations(path, source) do
    lines = String.split(source, "\n")

    if Enum.any?(lines, &Regex.match?(@benchmark_module, &1)) do
      []
    else
      numbered = Enum.with_index(lines, 1)

      for {line, number} <- numbered,
          not comment?(line),
          Regex.match?(@clock, line),
          not benchmark?(numbered, number) do
        "#{path}:#{number}: #{String.trim(line)}"
      end
    end
  end

  # The read at `number` is in a benchmark test: the nearest definition above it is a
  # test, and the attributes and comments directly above that carry the tag.
  defp benchmark?(numbered, number) do
    above = numbered |> Enum.take(number - 1) |> Enum.reverse()

    case Enum.drop_while(above, fn {line, _} -> not Regex.match?(@definition, line) end) do
      [{definition, _} | before] ->
        Regex.match?(@runnable, definition) and
          before
          |> Enum.take_while(fn {line, _} -> attribute?(line) or comment?(line) end)
          |> Enum.any?(fn {line, _} -> Regex.match?(@benchmark_tag, line) end)

      [] ->
        false
    end
  end

  defp attribute?(line), do: String.starts_with?(String.trim_leading(line), "@")
  defp comment?(line), do: String.starts_with?(String.trim_leading(line), "#")
end
