defmodule Visualize.Feed.ConformanceLoadTest do
  @moduledoc """
  Load changes no verdict of the conformance kit (spec/08 §12.2, §12.4, #852, D-221). Each
  verdict is taken idle, then with every scheduler saturated by busy processes, and the two
  must agree. The module is not async, so the saturation shares the runner with no other
  test, and nothing here asserts a time.
  """
  use ExUnit.Case, async: false
  @moduletag :capture_log

  alias Visualize.Data.{Delivery, Schema}
  alias Visualize.Feed.{Conformance, Signals}
  alias Visualize.Saturate

  # A feed whose fetch does its work where the test says: in its own process, in an agent
  # it calls, forever, or never (blocked in `receive`).
  defmodule Worker do
    @moduledoc false
    @behaviour Visualize.Feed

    alias Visualize.Data.{Delivery, Schema}

    defstruct [:work, :agent]

    def schema, do: Schema.new!(%{n: %{type: :number}})

    @impl true
    def describe(_feed), do: {Schema.version(schema()), schema(), []}

    @impl true
    def fetch(%__MODULE__{work: :agent, agent: agent}, _window, _budget),
      do: {:ok, delivery(Agent.get(agent, fn _ -> sum(1_000_000) end))}

    def fetch(%__MODULE__{work: :forever}, _window, _budget), do: {:ok, delivery(forever(0))}

    def fetch(%__MODULE__{work: :blocked}, _window, _budget),
      do: receive(do: (:never_sent -> {:ok, delivery(0)}))

    @impl true
    def subscribe(_feed, _pid), do: {:error, :no_push}

    @impl true
    def unsubscribe(_feed, _ref), do: :ok

    defp delivery(n), do: Delivery.new([%{n: n}], schema: Schema.version(schema()))
    defp sum(n), do: Enum.reduce(1..n, 0, &(&1 + &2))
    defp forever(n), do: forever(rem(n + 1, 7))
  end

  # The verdicts of `calls`, idle and then saturated; the busy processes stopped on exit too.
  defp idle_and_saturated(calls) do
    idle = calls.()
    busy = Saturate.start()
    on_exit(fn -> Saturate.stop(busy) end)
    saturated = calls.()
    :ok = Saturate.stop(busy)
    {idle, saturated}
  end

  defp signals,
    do: Signals.new(Visualize.Signals.new(:discrete, [:t, :n], window: 3), tick: 30, limit: 10)

  test "a correct feed passes every check at the defaults, idle and saturated" do
    run = fn -> Conformance.check(signals(), windows: [nil, [4, 12], [-5, 8]]) end
    assert idle_and_saturated(run) == {[], []}
  end

  test "a budget decides by the count: one reduction fails each call, a generous one passes" do
    run = fn ->
      {Conformance.check(:describe, signals(), reductions: 1),
       Conformance.check(:deliveries, signals(), reductions: 10_000_000, budgets: [nil])}
    end

    # The count is the verdict; how far past the budget a reading caught it is not.
    {idle, saturated} = idle_and_saturated(run)

    for findings <- [idle, saturated] do
      assert {[{:describe, {:reductions, :describe, spent, 1}}], []} = findings
      assert spent > 1
    end
  end

  test "a fetch that never stops is stopped at its budget, not reported hung" do
    feed = %Worker{work: :forever}
    run = fn -> Conformance.check(:deliveries, feed, reductions: 1_000_000, budgets: [nil]) end

    {idle, saturated} = idle_and_saturated(run)

    for findings <- [idle, saturated] do
      assert [{:deliveries, {:reductions, {:fetch, nil, nil}, spent, 1_000_000}}] = findings
      assert spent > 1_000_000
    end
  end

  test "a fetch blocked in receive is hung at the liveness bound, idle and saturated" do
    feed = %Worker{work: :blocked}
    run = fn -> Conformance.check(:deliveries, feed, timeout: 50, budgets: [nil]) end
    finding = [{:deliveries, {:hung, {:fetch, nil, nil}, 50}}]
    assert idle_and_saturated(run) == {finding, finding}

    assert Conformance.format(hd(finding)) ==
             "deliveries: fetch(feed, nil, nil) did not answer within 50 ms: it is blocked (hung), not slow"
  end

  test "work done in another process counts only when the kit is given that process" do
    agent = start_supervised!({Agent, fn -> nil end})
    feed = %Worker{work: :agent, agent: agent}
    opts = [reductions: 100_000, budgets: [nil]]

    run = fn ->
      {Conformance.check(:deliveries, feed, opts),
       Conformance.check(:deliveries, feed, [processes: [agent]] ++ opts)}
    end

    {idle, saturated} = idle_and_saturated(run)

    for {alone, with_agent} <- [idle, saturated] do
      assert alone == []
      assert [{:deliveries, {:reductions, {:fetch, nil, nil}, spent, 100_000}}] = with_agent
      assert spent > 100_000
    end
  end
end
