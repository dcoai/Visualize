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

  Nor does a test wait on the clock (D-148, #520). An `assert_receive` names no timeout of
  its own: both suites set its default to the test's timeout, so the test's timeout is the
  one bound on a message that must arrive, and a bound written at the site is a second
  clock under it (#736); a `refute_receive` does not wait at all — absence after a
  synchronizing call is `refute_received`; a `receive … after` waits nothing — `after 0`
  — for the same reason (#715); and nothing sleeps. A site that must break one of these
  is on `@allowed`, with its reason. This one is read from the parsed code, so a string or
  a comment that mentions a wait is not one.
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

  # The waits that stay, each with its reason: `{path, the code at the site, reason}`. A
  # site is matched by its file and the text of its line, so the entry survives an edit
  # above it; an entry that matches no site fails, so the list cannot outlive its sites.
  @allowed [
    {"test/visualize/layout/force/simulation_test.exs", "Process.sleep(200)",
     "a delay the test imposes, not a wait: the ticks are counted the same after it, " <>
       "which shows the count does not depend on when the caller looks (#483)"},
    {"test/visualize/render/raster_port_test.exs", "Process.sleep(10)",
     "polls an OS process group, which no message reports reaped; bounded by a count of " <>
       "tries thirty seconds long, so load lengthens the poll and never fails it (#495)"},
    {"test/visualize/feed/telemetry_test.exs", "receive after: (1 -> wait_for_message(pid))",
     "polls a suspended collector's queue until the call is in it; nothing announces a " <>
       "message's arrival, and the poll ends on the count, with no deadline of its own"},
    {"examples/test/examples_web/performance_live_test.exs",
     "assert_receive {^ref, {:all, all} = result}, @compare_wait",
     "the whole comparison runs under a test timeout raised past the suite's, and the " <>
       "wait is longer than the suite's default, inside that timeout, so a slow " <>
       "comparison fails on the receive's own message (#469, #736)"}
  ]

  # Every test file of the library and the examples, and the library's test support.
  defp files do
    files =
      Path.wildcard("test/**/*.exs") ++
        Path.wildcard("test/support/**/*.ex") ++ Path.wildcard("examples/test/**/*.exs")

    files = files -- [Path.relative_to_cwd(__ENV__.file)]
    assert length(files) > 100, "the scan found #{length(files)} test files: is the cwd the root?"
    files
  end

  test "no test outside :benchmark reads a wall clock" do
    violations = Enum.flat_map(files(), &violations(&1, File.read!(&1)))

    assert violations == [],
           "a default-suite test reads a wall clock (spec/12 §6, D-114). Assert the work " <>
             "done — `Visualize.Work.reductions/1`, or a count the code exposes — or tag " <>
             "the test `@tag :benchmark`:\n" <> Enum.join(violations, "\n")
  end

  test "no test waits on the clock, outside the allow-list" do
    sites = Enum.flat_map(files(), &waits(&1, File.read!(&1)))
    {allowed, violations} = Enum.split_with(sites, &allowed?(&1, @allowed))

    assert violations == [],
           "a test waits on the clock (spec/12 §6, D-148). Wait on a message or a count " <>
             "with an `assert_receive` that names no timeout, or a `receive` with no " <>
             "`after` but 0, which the test's own timeout bounds; assert absence after a " <>
             "synchronizing call with `refute_received`; drive time with a clock the code " <>
             "takes; or put the site on @allowed with its reason:\n" <>
             Enum.map_join(violations, "\n", &describe_site/1)

    stale = Enum.reject(@allowed, fn entry -> Enum.any?(allowed, &allowed?(&1, [entry])) end)
    assert stale == [], "@allowed names a site that is gone: #{inspect(stale)}"
  end

  describe "the wait scan" do
    test "rejects an assert_receive that names a timeout, however long, and passes one that does not" do
      source = """
      defmodule ProbeTest do
        use ExUnit.Case
        @patience 30_000
        @short 500

        test "waits" do
          assert_receive :tick, 500
          assert_receive {:frame,
                          _id}
          assert_receive :tick, @short
          assert_receive :tick, 2 * @short
          assert_receive :tick, @patience
          assert_receive :tick, 5_000
          assert_receive :tick
        end
      end
      """

      assert [
               {7, :assert_receive, "500 ms"},
               {10, :assert_receive, "500 ms"},
               {11, :assert_receive, "a timeout it cannot read"},
               {12, :assert_receive, "30000 ms"},
               {13, :assert_receive, "5000 ms"}
             ] = summary(waits("probe_test.exs", source))
    end

    # Without the setting, an `assert_receive` that names no timeout waits ExUnit's 100 ms.
    test "both suites give assert_receive the test's own timeout" do
      for helper <- ["test/test_helper.exs", "examples/test/test_helper.exs"] do
        options = start_options(File.read!(helper))
        timeout = Keyword.get(options, :timeout)
        receive_timeout = Keyword.get(options, :assert_receive_timeout)

        assert is_integer(timeout) and is_integer(receive_timeout) and
                 receive_timeout >= timeout,
               "#{helper} must pass ExUnit.start/1 a literal :timeout and an " <>
                 ":assert_receive_timeout no shorter: #{inspect(options)}"
      end

      assert ExUnit.configuration()[:assert_receive_timeout] >= ExUnit.configuration()[:timeout]
    end

    test "rejects a refute_receive that waits, and passes refute_received" do
      source = """
      defmodule ProbeTest do
        use ExUnit.Case

        test "absent" do
          refute_receive :late, 200
          refute_receive :late
          refute_receive :late, 0
          refute_received :late
        end
      end
      """

      assert [
               {5, :refute_receive, "200 ms"},
               {6, :refute_receive, "the default timeout"}
             ] = summary(waits("probe_test.exs", source))
    end

    test "rejects a sleep and a receive after of any length, in a test or a helper" do
      source = """
      defmodule ProbeTest do
        use ExUnit.Case
        @patience 30_000

        defp poll(pid) do
          receive do
            :done -> :ok
          after
            10 -> poll(pid)
          end
        end

        test "sleeps" do
          Process.sleep(100)
          :timer.sleep(5)
          receive after: (0 -> :ok)
          receive do
            :done -> :ok
          after
            30_000 -> flunk("never came")
          end
          receive do
            :done -> :ok
          after
            @patience -> flunk("never came")
          end
          receive do
            :done -> :ok
          end
        end
      end
      """

      # Every `after` but 0, however long (#715): a long one is the test's timeout made
      # shorter, and a receive with none waits on its message alone.
      assert [
               {9, :receive_after, "10 ms"},
               {14, :sleep, "a sleep"},
               {15, :sleep, "a sleep"},
               {20, :receive_after, "30000 ms"},
               {25, :receive_after, "30000 ms"}
             ] = summary(waits("probe_test.exs", source))
    end

    test "a wait in a string or a comment is not one" do
      source = ~S'''
      defmodule ProbeTest do
        use ExUnit.Case

        test "quotes" do
          # assert_receive :tick, 10
          code = "Process.sleep(10)"
          assert code =~ "sleep"
        end
      end
      '''

      assert waits("probe_test.exs", source) == []
    end

    test "an allow-list entry passes its own site only" do
      source = """
      defmodule ProbeTest do
        use ExUnit.Case

        test "a" do
          Process.sleep(200)
          Process.sleep(10)
        end
      end
      """

      sites = waits("probe_test.exs", source)
      entry = {"probe_test.exs", "Process.sleep(200)", "a stated reason"}
      assert [%{line: 6}] = Enum.reject(sites, &allowed?(&1, [entry]))
      assert Enum.reject(sites, &allowed?(&1, [{"other.exs", "Process.sleep(200)", ""}])) == sites
    end
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

  # Every wait in `source` that breaks D-148, as `%{path, line, kind, why, text}`: read from
  # the parsed code, with the module attributes bound to integers resolved.
  defp waits(path, source) do
    ast = Code.string_to_quoted!(source, file: path)
    lines = source |> String.split("\n") |> List.to_tuple()

    {_, attributes} =
      Macro.prewalk(ast, %{}, fn
        {:@, _, [{name, _, [value]}]} = node, acc when is_atom(name) and is_integer(value) ->
          {node, Map.put(acc, name, value)}

        node, acc ->
          {node, acc}
      end)

    {_, sites} =
      Macro.prewalk(ast, [], fn node, acc ->
        case wait(node, attributes) do
          nil ->
            {node, acc}

          {line, kind, why} ->
            text = lines |> elem(line - 1) |> String.trim()
            {node, [%{path: path, line: line, kind: kind, why: why, text: text} | acc]}
        end
      end)

    sites |> Enum.reverse() |> Enum.sort_by(& &1.line)
  end

  # `{line, kind, why}` for a node that waits on the clock, or nil.
  # An `assert_receive` with no timeout waits on the suite's default, the test's own
  # timeout; a timeout written at the site is a second clock, however long (#736).
  defp wait({:assert_receive, _meta, [_pattern]}, _attributes), do: nil

  defp wait({:assert_receive, meta, [_pattern, timeout | _]}, attributes) do
    case timeout(timeout, attributes) do
      ms when is_integer(ms) -> {meta[:line], :assert_receive, "#{ms} ms"}
      :unreadable -> {meta[:line], :assert_receive, "a timeout it cannot read"}
    end
  end

  defp wait({:refute_receive, meta, [_pattern]}, _attributes),
    do: {meta[:line], :refute_receive, "the default timeout"}

  defp wait({:refute_receive, meta, [_pattern, timeout | _]}, attributes) do
    case timeout(timeout, attributes) do
      0 -> nil
      ms when is_integer(ms) -> {meta[:line], :refute_receive, "#{ms} ms"}
      :unreadable -> {meta[:line], :refute_receive, "a timeout it cannot read"}
    end
  end

  defp wait({:receive, meta, [clauses]}, attributes) when is_list(clauses) do
    with [{:->, _, [[timeout], _body]} | _] <- Keyword.get(clauses, :after),
         ms when ms != 0 <- timeout(timeout, attributes) do
      line = if is_integer(ms), do: "#{ms} ms", else: "a timeout it cannot read"
      {after_line(clauses, meta), :receive_after, line}
    else
      _ -> nil
    end
  end

  defp wait({{:., meta, [{:__aliases__, _, [:Process]}, :sleep]}, _, _}, _attributes),
    do: {meta[:line], :sleep, "a sleep"}

  defp wait({{:., meta, [:timer, :sleep]}, _, _}, _attributes),
    do: {meta[:line], :sleep, "a sleep"}

  defp wait(_node, _attributes), do: nil

  # A timeout's milliseconds: an integer literal, or a module attribute bound to one.
  defp timeout(ms, _attributes) when is_integer(ms), do: ms

  defp timeout({:@, _, [{name, _, context}]}, attributes) when is_atom(context),
    do: Map.get(attributes, name, :unreadable)

  defp timeout(_expression, _attributes), do: :unreadable

  # The line of a receive's `after` clause: its arrow's, else the receive's own.
  defp after_line(clauses, meta) do
    case Keyword.get(clauses, :after) do
      [{:->, arrow, _} | _] -> arrow[:line] || meta[:line]
      _ -> meta[:line]
    end
  end

  # The keyword options of a test helper's `ExUnit.start/1` call, as written.
  defp start_options(source) do
    {_, found} =
      source
      |> Code.string_to_quoted!()
      |> Macro.prewalk(nil, fn
        {{:., _, [{:__aliases__, _, [:ExUnit]}, :start]}, _, [options]} = node, nil ->
          {node, options}

        node, acc ->
          {node, acc}
      end)

    found || []
  end

  defp allowed?(site, entries) do
    Enum.any?(entries, fn {path, code, _reason} ->
      site.path == path and String.contains?(site.text, code)
    end)
  end

  defp describe_site(site), do: "#{site.path}:#{site.line}: #{site.why}: #{site.text}"

  defp summary(sites), do: Enum.map(sites, &{&1.line, &1.kind, &1.why})

  defp attribute?(line), do: String.starts_with?(String.trim_leading(line), "@")
  defp comment?(line), do: String.starts_with?(String.trim_leading(line), "#")
end
