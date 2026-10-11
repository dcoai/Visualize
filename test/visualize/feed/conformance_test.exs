defmodule Visualize.Feed.ConformanceTest do
  @moduledoc """
  The feed conformance kit (spec/08 §12, #538, D-145): run on this library's two
  providers through `use`, and held to its negatives by a fake feed whose every flaw must
  fail the check it targets.
  """
  # A raising feed's process logs its crash; the kit reports it as a finding.
  use ExUnit.Case, async: true
  @moduletag :capture_log

  import Telemetry.Metrics

  alias Visualize.Feed.{Conformance, Signals, Telemetry}
  alias Visualize.Test.Feeds.Broken

  doctest Conformance

  # -- the providers ---------------------------------------------------------------------

  # Windows before the signal's start, past its present tick (30) and beyond its limit (10),
  # so one is capped.
  use Conformance,
    name: "Signals",
    feed: Signals.new(Visualize.Signals.new(:discrete, [:t, :n], window: 3), tick: 30, limit: 10),
    windows: [nil, [4, 12], [-5, 8], [nil, 6], [25, nil], [0, 100]]

  # The collector's clock is fixed, so its stamps are `@t0 + 1`, `@t0 + 2`, …: a window
  # before `@t0` is before its start and capped, one after it is within its rows.
  @t0 1_760_000_000_000_000
  @event [:vis_conformance, :sample]

  use Conformance,
    name: "Telemetry",
    feed: telemetry_feed(),
    windows: [nil, [at(-10), at(3)], [at(2), at(4)], [at(3), nil], [nil, at(2)]],
    push: fn feed ->
      :telemetry.execute(@event, %{value: 7}, %{host: "b"})
      Telemetry.flush(feed.server)
    end,
    down: Telemetry.feed(:vis_conformance_no_collector, "vis_conformance.sample.value")

  defp telemetry_feed do
    server =
      start_supervised!(
        {Telemetry,
         metrics: [last_value("vis_conformance.sample.value", tags: [:host])],
         every: nil,
         clock: fn -> @t0 end}
      )

    for v <- 1..6, do: :telemetry.execute(@event, %{value: v}, %{host: "a"})
    # A call after the events, from the process that emitted them, so they are collected.
    :ok = Telemetry.flush(server)
    Telemetry.feed(server, "vis_conformance.sample.value")
  end

  defp at(micro), do: DateTime.from_unix!(@t0 + micro, :microsecond)

  # -- the negatives -----------------------------------------------------------------------

  @opts [
    windows: [nil, [2, 10], [nil, 6], [12, nil], [-3, 8]],
    budgets: [nil, 5],
    push: &Broken.emit/1,
    quiet: 30
  ]

  # Each flaw, the check it targets and the finding that names it.
  @expected [
    unstable_version: {:describe, :unstable},
    wrong_version: {:describe, :version},
    stale_version: {:deliveries, :version},
    served_window_lie: {:deliveries, :outside_served},
    missing_row: {:deliveries, :missing},
    capped_lie: {:deliveries, :capped},
    uncapped_lie: {:deliveries, :uncapped},
    reduction_unrecorded: {:deliveries, :unrecorded_reduction},
    resolution_lie: {:deliveries, :resolution},
    window_overrun: {:supports, :window_served},
    budget_overrun: {:supports, :over_budget},
    push_undeclared: {:supports, :push_undeclared},
    no_handshake: {:push, :handshake},
    data_before_schema: {:push, :before_schema},
    raises: {:errors, :raised},
    keeps_pushing: {:unsubscribe, :pushed_after_unsubscribe}
  ]

  describe "the kit's negatives" do
    test "an honest feed passes every check" do
      assert Conformance.check(Broken.new(), [{:down, Broken.new(:down)} | @opts]) == []
    end

    test "every flaw is expected to fail a check, and every check is failed by a flaw" do
      assert Enum.sort(Keyword.keys(@expected)) == Enum.sort(Broken.flaws() -- [:down])

      assert @expected |> Keyword.values() |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> Enum.sort() ==
               Enum.sort(Conformance.checks())
    end

    for {flaw, {check, reason}} <- @expected do
      test "#{flaw} fails #{check} with #{reason}" do
        findings = Conformance.check(unquote(check), Broken.new(unquote(flaw)), @opts)

        assert Enum.any?(findings, &(elem(elem(&1, 1), 0) == unquote(reason))),
               "#{unquote(flaw)}: expected a #{unquote(reason)} finding, got #{inspect(findings)}"

        for finding <- findings, do: assert(is_binary(Conformance.format(finding)))
      end
    end

    test "a down feed that answers is a finding; a raising one is a finding, not a crash" do
      findings = Conformance.check(:errors, Broken.new(), down: Broken.new())

      assert Enum.any?(findings, &match?({:errors, {:answered_down, :describe, {_, _, _}}}, &1))
      assert Enum.any?(findings, &match?({:errors, {:answered_down, {:fetch, nil, nil}, _}}, &1))
      assert Enum.any?(findings, &match?({:errors, {:answered_down, :subscribe, _}}, &1))

      assert [
               {:errors, {:raised, {:fetch, [:not, :a_time], nil}, {%ArgumentError{}, _stack}}}
               | _
             ] =
               Conformance.check(:errors, Broken.new(:raises), [])
    end

    test "a capability the options cannot probe is a finding" do
      findings = Conformance.check(:supports, Broken.new(), windows: [nil], budgets: [nil])

      assert {:supports, {:no_probe, :window}} in findings
      assert {:supports, {:no_probe, :budget}} in findings
      assert {:supports, {:no_probe, :push}} in findings
      assert Conformance.check(:push, Broken.new(), []) == [push: {:no_probe, :push}]
    end

    test "a feed that cannot describe stops each check with the reason" do
      for check <- [:describe, :deliveries, :supports, :push, :unsubscribe] do
        assert Conformance.check(check, Broken.new(:down), @opts) == [
                 {check, {:describe_error, :down}}
               ]
      end
    end

    test "a callback that hangs is a finding once the timeout passes" do
      hang = %Signals{
        Signals.new(Visualize.Signals.new(:discrete, [:t, :n]), every: 1)
        | clock: fn -> receive(do: (:never_sent -> nil)) end
      }

      assert [{:deliveries, {:timeout, {:fetch, nil, nil}}} | _] =
               Conformance.check(:deliveries, hang, timeout: 20, budgets: [nil])
    end

    test "each finding reads as a line naming its check" do
      assert Conformance.format({:deliveries, {:capped, {[2, 10], nil}, [2, 10]}}) ==
               "deliveries: fetch(feed, [2, 10], nil): capped is true, but the served window [2, 10] reaches the asked from"
    end
  end

  describe "the macro" do
    test "writes one test per check into the describe block" do
      names = for {name, 1} <- __MODULE__.__info__(:functions), do: Atom.to_string(name)

      for block <- ["Signals", "Telemetry"], check <- Conformance.checks() do
        assert Enum.any?(names, &String.starts_with?(&1, "test #{block} #{check}: ")),
               "no #{check} test in #{block}"
      end
    end

    test "refuses a missing feed and an unknown option at compile time" do
      assert_raise ArgumentError, ~r/needs feed:/, fn ->
        Code.compile_quoted(
          quote do
            defmodule Visualize.Feed.ConformanceTest.NoFeed do
              use ExUnit.Case
              use Visualize.Feed.Conformance, windows: [nil]
            end
          end
        )
      end

      assert_raise ArgumentError, ~r/unknown keys \[:window\]/, fn ->
        Code.compile_quoted(
          quote do
            defmodule Visualize.Feed.ConformanceTest.Unknown do
              use ExUnit.Case
              use Visualize.Feed.Conformance, feed: nil, window: [0, 1]
            end
          end
        )
      end
    end

    test "an unknown check is refused" do
      assert_raise ArgumentError, ~r/not a conformance check/, fn ->
        Conformance.check(:everything, Broken.new(), [])
      end
    end
  end
end
