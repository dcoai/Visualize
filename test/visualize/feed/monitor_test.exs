defmodule Visualize.Feed.MonitorTest do
  @moduledoc """
  `Visualize.Feed.Monitor` (spec/08 §11.3–§11.4, #537, D-140): the loop as a value. Pull
  feeds are polled at their interval, pushes buffer and the next tick drains them, the
  schema arrives before its data and an unknown version is asked for, and errors and
  staleness are states.
  """
  use ExUnit.Case, async: true

  alias Visualize.Data.{Delivery, Schema}
  alias Visualize.Feed.Monitor
  alias Visualize.Test.Feeds

  doctest Monitor

  # The test feeds count, so `t` is a `:number` named the window field (D-154): every
  # window, seam and placement below is over numbers.
  @tick %{type: :number, window: true}
  @v1 Schema.new!(%{t: @tick, v: %{type: :number, unit: "ms", label: "Latency"}})
  @v2 Schema.new!(%{t: @tick, v: %{type: :number, unit: "s", label: "Latency"}})
  @stamped Schema.new!(%{t: %{type: :time}, v: %{type: :number}})
  @t0 ~U[2026-10-12 12:00:00Z]

  defp rows(range), do: for(t <- range, do: %{t: t, v: rem(t * 7, 11)})

  defp push_feed(rows) do
    Feeds.scripted(schema: @v1, supports: [:window, :push], rows: rows)
  end

  describe "pull feeds" do
    test "a feed is described and fetched at the first tick, and polled at its interval" do
      {feed, agent} = Feeds.scripted(schema: @v1, rows: rows(1..5))
      monitor = Monitor.new(%{a: feed}, every: 100)
      assert Monitor.status(monitor) == %{a: :loading}
      assert Monitor.deliveries(monitor) == %{}

      monitor = Monitor.tick(monitor, now: 0)
      assert Monitor.status(monitor) == %{a: :live}
      assert %{a: %Delivery{rows: [_, _, _, _, _]}} = Monitor.deliveries(monitor)
      assert {Feeds.calls(agent, :describe), Feeds.calls(agent, :fetch)} == {1, 1}

      monitor = Monitor.tick(monitor, now: 50)
      assert Feeds.calls(agent, :fetch) == 1

      Feeds.set(agent, rows: rows(1..7))
      monitor = Monitor.tick(monitor, now: 100)
      assert Feeds.calls(agent, :fetch) == 2
      assert length(Monitor.deliveries(monitor).a.rows) == 7
      # The schema was described once; the polls' version is cached.
      assert Feeds.calls(agent, :describe) == 1
    end

    test "the monitor finishes what the feed does not: a rows-only feed trimmed and reduced" do
      {feed, _agent} = Feeds.scripted(schema: @v1, rows: rows(1..1000))
      monitor = Monitor.new(%{a: feed}, window: [101, 900], budget: 50) |> Monitor.tick(now: 0)
      delivery = Monitor.deliveries(monitor).a
      assert length(delivery.rows) == 50
      assert delivery.reduced_by == :visualize
      assert Enum.all?(delivery.rows, &(&1.t in 101..900))
    end

    test "a budget-honoring feed is not reduced again" do
      answer = fn _window, budget -> {rows(1..budget), [reduced_by: :feed]} end
      {feed, _agent} = Feeds.scripted(schema: @v1, supports: [:budget], rows: answer)
      monitor = Monitor.new(%{a: feed}, budget: 40) |> Monitor.tick(now: 0)
      assert %{rows: rows, reduced_by: :feed} = Monitor.deliveries(monitor).a
      assert length(rows) == 40
    end

    test "a moved window or budget is fetched or refinished at the next tick" do
      {feed, agent} = Feeds.scripted(schema: @v1, rows: rows(1..100))
      monitor = Monitor.new(%{a: feed}) |> Monitor.tick(now: 0)
      assert Monitor.window(monitor, nil) == monitor

      monitor = monitor |> Monitor.window([10, 19]) |> Monitor.tick(now: 1)
      assert Feeds.calls(agent, :fetch) == 2
      assert length(Monitor.deliveries(monitor).a.rows) == 10

      monitor = monitor |> Monitor.budget(5) |> Monitor.tick(now: 2)
      assert length(Monitor.deliveries(monitor).a.rows) == 5
      assert Feeds.calls(agent, :fetch) == 2
    end
  end

  describe "errors and staleness are states" do
    test "a feed that cannot describe is down, retried when due, and recovers" do
      {feed, agent} = Feeds.scripted(schema: @v1, rows: rows(1..3), error: :unreachable)
      monitor = Monitor.new(%{a: feed}, every: 100) |> Monitor.tick(now: 0)
      assert Monitor.status(monitor) == %{a: {:down, :unreachable}}
      assert Monitor.deliveries(monitor) == %{}

      monitor = Monitor.tick(monitor, now: 10)
      assert Feeds.calls(agent, :describe) == 1

      Feeds.set(agent, error: nil)
      monitor = Monitor.tick(monitor, now: 100)
      assert Monitor.status(monitor) == %{a: :live}
    end

    test "a failed poll is down, and the last delivery is still handed out" do
      {feed, agent} = Feeds.scripted(schema: @v1, rows: rows(1..3))
      monitor = Monitor.new(%{a: feed}, every: 100) |> Monitor.tick(now: 0)
      Feeds.set(agent, error: :timeout)
      monitor = Monitor.tick(monitor, now: 100)
      assert Monitor.status(monitor) == %{a: {:down, :timeout}}
      assert length(Monitor.deliveries(monitor).a.rows) == 3
    end

    test "a feed with no answer within stale_after is stale, and live again on the next" do
      {feed, _agent} = push_feed(rows(1..3))
      monitor = Monitor.new(%{a: feed}, stale_after: 100) |> Monitor.tick(now: 0)
      monitor = Feeds.drain(monitor) |> Monitor.tick(now: 100)
      assert Monitor.status(monitor) == %{a: :live}
      monitor = Monitor.tick(monitor, now: 101)
      assert Monitor.status(monitor) == %{a: :stale}
    end
  end

  describe "push feeds" do
    test "a push feed is subscribed by the owner, and the handshake's schema is first" do
      {feed, agent} = push_feed(rows(1..3))
      monitor = Monitor.new(%{a: feed}) |> Monitor.tick(now: 0)
      assert Feeds.calls(agent, :subscribe) == 1
      ref = Feeds.ref(agent)
      assert_received {:visualize_feed, ^ref, {:schema, _version, @v1}}
      assert Monitor.handle_message(monitor, :unrelated) == :ignore
    end

    test "pushes buffer and the next tick drains them in one merge, without a fetch" do
      {feed, agent} = push_feed(rows(1..3))
      monitor = Monitor.new(%{a: feed}) |> Monitor.tick(now: 0) |> Feeds.drain()

      for chunk <- [4..5, 6..6, 7..9] do
        Feeds.push(
          agent,
          self(),
          Delivery.new(rows(chunk),
            window: [chunk.first, chunk.last],
            schema: Schema.version(@v1)
          )
        )
      end

      monitor = Feeds.drain(monitor)
      # Buffered, not yet merged: the handed-out delivery is the tick's.
      assert length(Monitor.deliveries(monitor).a.rows) == 3

      monitor = Monitor.tick(monitor, now: 10_000)
      assert Enum.map(Monitor.deliveries(monitor).a.rows, & &1.t) == Enum.to_list(1..9)
      assert Feeds.calls(agent, :fetch) == 1
      assert Monitor.deliveries(monitor).a.window == [nil, 9]
    end

    test "a push overlapping what the feed holds adds nothing twice at the seam" do
      {feed, agent} = push_feed(rows(1..5))
      fetched = fn _window, _budget -> {rows(1..5), [window: [1, 5]]} end
      Feeds.set(agent, rows: fetched)
      monitor = Monitor.new(%{a: feed}) |> Monitor.tick(now: 0) |> Feeds.drain()
      Feeds.push(agent, self(), Delivery.new(rows(4..7), schema: Schema.version(@v1)))
      monitor = monitor |> Feeds.drain() |> Monitor.tick(now: 1)
      assert Enum.map(Monitor.deliveries(monitor).a.rows, & &1.t) == Enum.to_list(1..7)
    end

    test "a schema pushed before its data is used without asking the feed" do
      {feed, agent} = push_feed(rows(1..3))
      monitor = Monitor.new(%{a: feed}) |> Monitor.tick(now: 0) |> Feeds.drain()
      Feeds.push_schema(agent, self(), @v2)
      Feeds.push(agent, self(), Delivery.new(rows(4..4), schema: Schema.version(@v2)))
      monitor = monitor |> Feeds.drain() |> Monitor.tick(now: 1)
      assert Feeds.calls(agent, :describe) == 1
      assert Monitor.deliveries(monitor).a.schema == Schema.version(@v2)
      assert {:ok, @v2} = Schema.Cache.fetch(Monitor.cache(monitor), :a, Schema.version(@v2))
    end

    test "a delivery with an unknown version is resolved by asking the feed once" do
      {feed, agent} = push_feed(rows(1..3))
      monitor = Monitor.new(%{a: feed}) |> Monitor.tick(now: 0) |> Feeds.drain()
      # The schema message was lost: the feed now describes v2, and pushes under it.
      Feeds.set(agent, schema: @v2)

      for t <- [4, 5] do
        Feeds.push(agent, self(), Delivery.new(rows(t..t), schema: Schema.version(@v2)))
      end

      monitor = monitor |> Feeds.drain() |> Monitor.tick(now: 1)
      assert Feeds.calls(agent, :describe) == 2
      assert Monitor.status(monitor) == %{a: :live}
      assert Monitor.errors(monitor) == %{}
      assert Enum.map(Monitor.deliveries(monitor).a.rows, & &1.t) == [1, 2, 3, 4, 5]
    end

    test "a delivery whose version the feed no longer describes is not used, and says why" do
      {feed, agent} = push_feed(rows(1..3))
      monitor = Monitor.new(%{a: feed}) |> Monitor.tick(now: 0) |> Feeds.drain()
      Feeds.push(agent, self(), Delivery.new(rows(4..4), schema: "0000"))
      monitor = monitor |> Feeds.drain() |> Monitor.tick(now: 1)
      v1 = Schema.version(@v1)
      assert %{a: {:schema_version, :a, "0000", ^v1}} = Monitor.errors(monitor)
      assert length(Monitor.deliveries(monitor).a.rows) == 3
    end

    test "a window within what a push feed holds trims; one before it fetches" do
      fetched = fn [from, _to], _budget -> {rows(from..10), [window: [from, 10]]} end
      {feed, agent} = push_feed(fetched)
      monitor = Monitor.new(%{a: feed}, window: [3, nil]) |> Monitor.tick(now: 0)
      assert Feeds.calls(agent, :fetch) == 1

      monitor = monitor |> Monitor.window([6, nil]) |> Monitor.tick(now: 1)
      assert Feeds.calls(agent, :fetch) == 1
      assert Enum.map(Monitor.deliveries(monitor).a.rows, & &1.t) == Enum.to_list(6..10)

      monitor = monitor |> Monitor.window([1, nil]) |> Monitor.tick(now: 2)
      assert Feeds.calls(agent, :fetch) == 2
      assert hd(Monitor.deliveries(monitor).a.rows).t == 1
    end

    test "a push of a subscription no longer held is dropped; put and remove unsubscribe" do
      {feed, agent} = push_feed(rows(1..3))
      monitor = Monitor.new(%{a: feed}) |> Monitor.tick(now: 0) |> Feeds.drain()
      stale = {:visualize_feed, make_ref(), {:delivery, Delivery.new([])}}
      assert {:ok, ^monitor} = Monitor.handle_message(monitor, stale)

      {other, _agent} = Feeds.scripted(schema: @v1, rows: rows(1..2))
      monitor = Monitor.put(monitor, :a, other)
      assert Feeds.calls(agent, :unsubscribe) == 1
      assert Monitor.status(monitor) == %{a: :loading}
      assert Monitor.remove(monitor, :a).entries == %{}
      assert Monitor.remove(monitor, :missing) == monitor
    end

    test "stop unsubscribes every push feed" do
      {feed, agent} = push_feed(rows(1..3))
      monitor = Monitor.new(%{a: feed}) |> Monitor.tick(now: 0)
      assert Monitor.stop(monitor) == :ok
      assert Feeds.calls(agent, :unsubscribe) == 1
    end
  end

  describe "time order (spec/15 §8.5, #574, D-146)" do
    test "a late pushed row is placed by its timestamp, and one already held is not added twice" do
      {feed, agent} = push_feed([])
      held = rows([1, 2, 4, 5])
      Feeds.set(agent, rows: fn _window, _budget -> {held, [window: [1, 5]]} end)
      monitor = Monitor.new(%{a: feed}) |> Monitor.tick(now: 0) |> Feeds.drain()

      # Out of order within the push, one reading late (3), one a repeat of a held row (4).
      pushed = rows([7, 3, 6, 4])
      Feeds.push(agent, self(), Delivery.new(pushed, schema: Schema.version(@v1)))
      monitor = monitor |> Feeds.drain() |> Monitor.tick(now: 1)

      assert Enum.map(Monitor.deliveries(monitor).a.rows, & &1.t) == [1, 2, 3, 4, 5, 6, 7]
      assert Monitor.deliveries(monitor).a.window == [1, 7]
    end

    test "a late row stamped with an instant is placed by its timestamp as well" do
      at = fn s -> DateTime.add(@t0, s) end
      stamped = fn seconds -> for s <- seconds, do: %{t: at.(s), v: s} end
      {feed, agent} = Feeds.scripted(schema: @stamped, supports: [:window, :push], rows: [])
      held = stamped.([1, 2, 4])
      Feeds.set(agent, rows: fn _window, _budget -> {held, [window: [at.(1), at.(4)]]} end)
      monitor = Monitor.new(%{a: feed}) |> Monitor.tick(now: 0) |> Feeds.drain()

      pushed = stamped.([5, 3])
      Feeds.push(agent, self(), Delivery.new(pushed, schema: Schema.version(@stamped)))
      monitor = monitor |> Feeds.drain() |> Monitor.tick(now: 1)

      assert Enum.map(Monitor.deliveries(monitor).a.rows, & &1.v) == [1, 2, 3, 4, 5]
    end

    test "a fetched delivery out of order is put in order before it is reduced" do
      {feed, _agent} = Feeds.scripted(schema: @v1, rows: Enum.shuffle(rows(1..40)))
      monitor = Monitor.new(%{a: feed}, budget: 12) |> Monitor.tick(now: 0)
      times = Enum.map(Monitor.deliveries(monitor).a.rows, & &1.t)

      assert times == Enum.sort(times)
      assert hd(times) == 1 and List.last(times) == 40
    end

    test "refetch asks every feed again, push feeds whose holding covers the window included" do
      {pull, pull_agent} = Feeds.scripted(schema: @v1, rows: rows(1..5))
      {push, push_agent} = push_feed(rows(1..5))
      monitor = Monitor.new(%{a: pull, b: push}) |> Monitor.tick(now: 0) |> Feeds.drain()
      monitor = Monitor.tick(monitor, now: 1)
      assert {Feeds.calls(pull_agent, :fetch), Feeds.calls(push_agent, :fetch)} == {1, 1}

      monitor |> Monitor.refetch() |> Monitor.tick(now: 2)
      assert {Feeds.calls(pull_agent, :fetch), Feeds.calls(push_agent, :fetch)} == {2, 2}
    end
  end

  describe "a window applies to a window field of its kind (spec/08 §11.2, D-154)" do
    test "a window of instants leaves a feed over ticks its own span, and moving it fetches nothing" do
      {ticks, tick_agent} = Feeds.scripted(schema: @v1, supports: [:window], rows: rows(1..10))
      t0 = @t0
      asked = fn window, _budget -> {[%{t: t0, v: 1}], [window: window]} end

      {stamped, stamped_agent} =
        Feeds.scripted(schema: @stamped, supports: [:window], rows: asked)

      window = [DateTime.add(@t0, -60), @t0]

      monitor =
        Monitor.new(%{ticks: ticks, stamped: stamped}, window: window, every: 1000)
        |> Monitor.tick(now: 0)

      assert Monitor.status(monitor) == %{ticks: :live, stamped: :live}
      # The feed over ticks was asked for its own span and is not trimmed by instants.
      assert Enum.map(Monitor.deliveries(monitor).ticks.rows, & &1.t) == Enum.to_list(1..10)
      assert Monitor.deliveries(monitor).stamped.window == window

      moved = [DateTime.add(@t0, -30), DateTime.add(@t0, 30)]
      Monitor.window(monitor, moved) |> Monitor.tick(now: 1)
      assert Feeds.calls(tick_agent, :fetch) == 1
      assert Feeds.calls(stamped_agent, :fetch) == 2
    end

    test "a numeric window trims a feed over ticks, and a feed of instants keeps its span" do
      {ticks, _} = Feeds.scripted(schema: @v1, rows: rows(1..10))
      {stamped, _} = Feeds.scripted(schema: @stamped, rows: [%{t: @t0, v: 1}])

      monitor =
        Monitor.new(%{ticks: ticks, stamped: stamped}, window: [3, 5]) |> Monitor.tick(now: 0)

      assert Enum.map(Monitor.deliveries(monitor).ticks.rows, & &1.t) == [3, 4, 5]
      assert Monitor.deliveries(monitor).stamped.rows == [%{t: @t0, v: 1}]
    end
  end

  test "a host passes the deliveries and the cache to apply/2, which asks no feed" do
    {feed, agent} = Feeds.scripted(schema: @v1, rows: rows(1..4))
    monitor = Monitor.new(%{primary: feed}) |> Monitor.tick(now: 0)

    design = %{
      version: 2,
      sources: %{primary: %{fields: [:t, :v], requires: %{v: [:unit]}}},
      frames: %{main: %{kind: :cartesian, scales: %{x: %{kind: :linear}, y: %{kind: :linear}}}},
      marks: [%{type: :line, data: :primary, channels: %{x: :t, y: :v}}],
      labels: [
        %{
          anchor: {:axis, :y},
          text: "\#{fact(:primary, :v, :label)} (\#{fact(:primary, :v, :unit)})"
        }
      ]
    }

    assert {:ok, applied} =
             Visualize.Chart.apply(design,
               sources: Monitor.deliveries(monitor),
               schemas: Monitor.cache(monitor)
             )

    assert [%{text: "Latency (ms)"}] = applied.chart.labels
    assert Feeds.calls(agent, :describe) == 1
  end
end
