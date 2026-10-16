defmodule Visualize.Feed.TelemetryTest do
  @moduledoc """
  `Visualize.Feed.Telemetry` (spec/08 §11.6, #537, D-140) under real `:telemetry.execute/3`
  calls and real `Telemetry.Metrics` definitions: a schema from the definitions, one feed
  per metric, a window honored, pushes with the schema first, and calls that answer
  values when the collector is gone.
  """
  use ExUnit.Case, async: true

  import Telemetry.Metrics

  alias Visualize.Data.Schema
  alias Visualize.Feed
  alias Visualize.Feed.{Monitor, Telemetry}
  alias Visualize.Test.Feeds

  doctest Telemetry

  # Each test emits under its own prefix, so tests running together never see each
  # other's events.
  defp prefix(context), do: :"vis_feed_#{:erlang.phash2(context.test)}"

  # A clock that moves a millisecond each time it is read: deterministic, no wall clock.
  defp clock do
    counter = :counters.new(1, [])
    :counters.put(counter, 1, 1_760_000_000_000_000)

    fn ->
      :counters.add(counter, 1, 1_000)
      :counters.get(counter, 1)
    end
  end

  defp start(metrics, opts \\ []) do
    opts = Keyword.merge([metrics: metrics, every: nil, clock: clock()], opts)
    start_supervised!({Telemetry, opts})
  end

  defp request(p, ms, route),
    do: :telemetry.execute([p, :request, :stop], %{duration: ms * 1_000_000}, %{route: route})

  describe "the schema from the definitions" do
    test "labels, UCUM units, the quantity, a counter's count and a tag's category", context do
      p = prefix(context)

      server =
        start([
          summary("#{p}.request.stop.duration",
            unit: {:native, :millisecond},
            tags: [:route],
            description: "Request time"
          ),
          counter("#{p}.request.stop.duration", tags: [:route]),
          last_value("#{p}.vm.memory.total", unit: {:byte, :kilobyte}),
          last_value("#{p}.queue.length", unit: :native)
        ])

      feeds = Telemetry.feeds(server)
      # A summary and a counter of one name are each keyed by their kind as well.
      name = "#{p}.request.stop.duration"

      assert Map.keys(feeds) |> Enum.sort() ==
               Enum.sort([
                 name <> ":summary",
                 name <> ":counter",
                 "#{p}.vm.memory.total",
                 "#{p}.queue.length"
               ])

      {version, schema, supports} = Feed.describe(Telemetry.feed(server, name <> ":summary"))
      assert supports == [:window, :push]
      assert version == Schema.version(schema)
      # `t` holds `DateTime`s: the one `:time` field, so the window field with nothing said.
      assert Feed.window_field(schema) == :t
      assert {:ok, %{type: :time}} = Schema.fetch(schema, :t)
      refute Map.has_key?(elem(Schema.fetch(schema, :t), 1), :window)
      assert {:ok, %{type: :category}} = Schema.fetch(schema, :route)

      assert {:ok, %{type: :number, label: "Request time", unit: "ms", quantity: :duration}} =
               Schema.fetch(schema, :value)

      {_v, count, _} = Feed.describe(feeds[name <> ":counter"])
      assert {:ok, %{unit: "1", quantity: :count, label: ^name}} = Schema.fetch(count, :value)

      {_v, memory, _} = Feed.describe(feeds["#{p}.vm.memory.total"])
      assert {:ok, %{unit: "kBy", quantity: :information}} = Schema.fetch(memory, :value)

      # `:native` has no size until converted: no unit rather than a guess.
      {_v, queue, _} = Feed.describe(feeds["#{p}.queue.length"])
      assert {:ok, value} = Schema.fetch(queue, :value)
      refute Map.has_key?(value, :unit)
    end
  end

  describe "a definition's facts (D-160)" do
    defp value(server, name) do
      {_v, schema, _} = Feed.describe(Telemetry.feed(server, name))
      {:ok, value} = Schema.fetch(schema, :value)
      value
    end

    test "each metric type gives its metric_kind", context do
      p = prefix(context)

      server =
        start([
          counter("#{p}.a.count"),
          sum("#{p}.a.sum"),
          last_value("#{p}.a.last"),
          summary("#{p}.a.summary"),
          distribution("#{p}.a.distribution")
        ])

      kinds =
        for k <- ~w(count sum last summary distribution), into: %{} do
          {k, value(server, "#{p}.a.#{k}").metric_kind}
        end

      assert kinds == %{
               "count" => :counter,
               "sum" => :counter,
               "last" => :gauge,
               "summary" => :gauge,
               "distribution" => :gauge
             }
    end

    test "reporter_options[:visualize] lands in the schema; an explicit metric_kind wins",
         context do
      p = prefix(context)

      server =
        start([
          summary("#{p}.panel.load",
            unit: {:native, :millisecond},
            reporter_options: [
              visualize: [polarity: :lower_is_better, bounds: [0, nil], target: 250]
            ]
          ),
          last_value("#{p}.queue.total", reporter_options: [visualize: [metric_kind: :counter]]),
          # Options for another reporter are that reporter's, never read here.
          last_value("#{p}.queue.depth", reporter_options: [other: [anything: true]])
        ])

      assert %{
               type: :number,
               unit: "ms",
               quantity: :duration,
               metric_kind: :gauge,
               polarity: :lower_is_better,
               bounds: [0, nil],
               target: 250
             } = value(server, "#{p}.panel.load")

      assert value(server, "#{p}.queue.total").metric_kind == :counter
      assert %{type: :number, metric_kind: :gauge} = depth = value(server, "#{p}.queue.depth")
      refute Map.has_key?(depth, :polarity)
    end

    test "an unknown key or an invalid fact stops start_link, naming the metric", context do
      p = prefix(context)
      # Two definitions of one name: the metric is named as `feeds/1` keys it.
      ok = counter("#{p}.request.duration")

      label = summary("#{p}.request.duration", reporter_options: [visualize: [label: "Nope"]])
      up = summary("#{p}.request.duration", reporter_options: [visualize: [polarity: :up]])
      bad = last_value("#{p}.gauge", reporter_options: [visualize: :lower_is_better])

      # As any `GenServer` stopping in `init/1`, the collector exits with the reason, so a
      # linked caller traps exits to read `start_link/1`'s answer (a supervisor does).
      Process.flag(:trap_exit, true)

      assert Telemetry.start_link(metrics: [ok, label], every: nil) ==
               {:error,
                {:telemetry_facts, "#{p}.request.duration:summary",
                 [{[:value, :label], :unknown_key}]}}

      assert Telemetry.start_link(metrics: [ok, up], every: nil) ==
               {:error,
                {:telemetry_facts, "#{p}.request.duration:summary",
                 [{[:value, :polarity], {:enum, Schema.polarities()}}]}}

      assert Telemetry.start_link(metrics: [bad], every: nil) ==
               {:error, {:telemetry_facts, "#{p}.gauge", [{[:value], {:type, :description}}]}}

      # Nothing was attached for a collector that never started.
      assert :telemetry.list_handlers([p, :request, :duration]) == []
      assert :telemetry.list_handlers([p, :gauge]) == []
    end

    test "a combination keeps the facts of the Telemetry feed in front of a history", context do
      p = prefix(context)

      server =
        start([
          summary("#{p}.panel.load",
            unit: {:native, :millisecond},
            reporter_options: [
              visualize: [polarity: :lower_is_better, bounds: [0, nil], target: 250]
            ]
          )
        ])

      live = Telemetry.feed(server, "#{p}.panel.load")
      :telemetry.execute([p, :panel], %{load: 7_000_000}, %{})

      # The store's history, in its own words: string fields, seconds, no facts.
      history_schema =
        Schema.new!(%{"t" => %{type: :time}, "value" => %{type: :number, unit: "s"}})

      # Before the collector's clock starts, so the history serves it.
      t0 = ~U[2025-10-01 00:00:00Z]

      {history, _} =
        Feeds.scripted(
          schema: history_schema,
          supports: [:window],
          rows: fn [from, to], _budget ->
            {[%{"t" => t0, "value" => 0.25}], [window: [from, to]]}
          end
        )

      {version, schema, _} = Feed.describe(live)
      combine = Feed.Combine.new([live, history])
      assert {^version, ^schema, [:window, :push]} = Feed.describe(combine)

      assert {:ok, %{polarity: :lower_is_better, bounds: [0, nil], target: 250}} =
               Schema.fetch(schema, :value)

      {:ok, delivery} = Feed.fetch(combine, [t0, nil], nil)
      assert delivery.schema == version
      assert [%{t: ^t0, value: 250.0}, %{value: 7.0}] = delivery.rows
    end
  end

  describe "the rows" do
    test "a summary row is the measurement, converted; a counter's the count per tag", context do
      p = prefix(context)

      server =
        start([
          summary("#{p}.request.stop.duration", unit: {:native, :millisecond}, tags: [:route]),
          counter("#{p}.request.count", event_name: [p, :request, :stop], tags: [:route]),
          sum("#{p}.request.total",
            event_name: [p, :request, :stop],
            measurement: :duration,
            unit: {:native, :millisecond}
          )
        ])

      for {ms, route} <- [{5, "/a"}, {7, "/b"}, {11, "/a"}], do: request(p, ms, route)

      {:ok, d} = Feed.fetch(Telemetry.feed(server, "#{p}.request.stop.duration"), nil, nil)
      assert Enum.map(d.rows, &{&1.value, &1.route}) == [{5, "/a"}, {7, "/b"}, {11, "/a"}]
      assert Enum.all?(d.rows, &match?(%DateTime{}, &1.t))

      assert d.rows
             |> Enum.map(& &1.t)
             |> Enum.chunk_every(2, 1, :discard)
             |> Enum.all?(fn [a, b] -> DateTime.before?(a, b) end)

      {:ok, count} = Feed.fetch(Telemetry.feed(server, "#{p}.request.count"), nil, nil)
      assert Enum.map(count.rows, &{&1.value, &1.route}) == [{1, "/a"}, {1, "/b"}, {2, "/a"}]

      {:ok, total} = Feed.fetch(Telemetry.feed(server, "#{p}.request.total"), nil, nil)
      assert Enum.map(total.rows, & &1.value) == [5, 12, 23]
    end

    test "keep, a measurement function and a missing measurement", context do
      p = prefix(context)

      server =
        start([
          last_value("#{p}.job.stop.duration",
            drop: &(&1.kind == :noise),
            measurement: fn m -> m.duration * 2 end
          ),
          last_value("#{p}.job.stop.size", measurement: :size)
        ])

      :telemetry.execute([p, :job, :stop], %{duration: 1}, %{kind: :real})
      :telemetry.execute([p, :job, :stop], %{duration: 2}, %{kind: :noise})
      :telemetry.execute([p, :job, :stop], %{duration: 3}, %{kind: :real})

      {:ok, d} = Feed.fetch(Telemetry.feed(server, "#{p}.job.stop.duration"), nil, nil)
      assert Enum.map(d.rows, & &1.value) == [2, 6]
      {:ok, none} = Feed.fetch(Telemetry.feed(server, "#{p}.job.stop.size"), nil, nil)
      assert none.rows == []
    end
  end

  describe "the window and retention" do
    test "a window of DateTimes is honored; a fetch before the kept rows is capped", context do
      p = prefix(context)
      server = start([last_value("#{p}.gauge.value")], keep: 3)
      feed = Telemetry.feed(server, "#{p}.gauge.value")
      for v <- 1..5, do: :telemetry.execute([p, :gauge], %{value: v}, %{})

      {:ok, all} = Feed.fetch(feed, nil, nil)
      assert Enum.map(all.rows, & &1.value) == [3, 4, 5]
      [oldest, middle, newest] = Enum.map(all.rows, & &1.t)
      assert all.window == [oldest, newest]

      {:ok, part} = Feed.fetch(feed, [middle, newest], nil)
      assert Enum.map(part.rows, & &1.value) == [4, 5]
      refute part.capped

      {:ok, early} = Feed.fetch(feed, [DateTime.add(oldest, -1, :hour), nil], nil)
      assert early.capped
      assert early.window == [oldest, newest]

      assert Feed.fetch(feed, [1, 2], nil) == {:error, {:window, [1, 2]}}
      assert Feed.fetch(feed, :all, nil) == {:error, {:window, :all}}

      assert Feed.fetch(Telemetry.feed(server, "nope"), nil, nil) ==
               {:error, {:unknown_metric, "nope"}}
    end
  end

  describe "push" do
    test "the schema arrives first, then the rows new since the last flush", context do
      p = prefix(context)
      server = start([last_value("#{p}.gauge.value")])
      feed = Telemetry.feed(server, "#{p}.gauge.value")
      :telemetry.execute([p, :gauge], %{value: 0}, %{})

      {:ok, ref} = Feed.subscribe(feed, self())
      {version, schema, _} = Feed.describe(feed)
      assert_received {:visualize_feed, ^ref, {:schema, ^version, ^schema}}

      for v <- 1..3, do: :telemetry.execute([p, :gauge], %{value: v}, %{})
      :ok = Telemetry.flush(server)
      assert_received {:visualize_feed, ^ref, {:delivery, d}}
      assert Enum.map(d.rows, & &1.value) == [1, 2, 3]
      assert d.schema == version
      assert d.window == [hd(d.rows).t, List.last(d.rows).t]

      # Nothing new, nothing sent; unsubscribed, nothing sent either.
      :ok = Telemetry.flush(server)
      refute_received {:visualize_feed, ^ref, _}
      :ok = Feed.unsubscribe(feed, ref)
      :telemetry.execute([p, :gauge], %{value: 4}, %{})
      :ok = Telemetry.flush(server)
      refute_received {:visualize_feed, ^ref, _}
    end

    test "monitored: history fetched once, pushes appended, nothing twice at the seam", context do
      p = prefix(context)
      server = start([last_value("#{p}.gauge.value")])
      for v <- 1..3, do: :telemetry.execute([p, :gauge], %{value: v}, %{})

      monitor = Monitor.new(%{gauge: Telemetry.feed(server, "#{p}.gauge.value")})
      # Subscribed and fetched in one tick; anything flushed meanwhile overlaps the fetch.
      monitor = Monitor.tick(monitor, now: 0)
      for v <- 4..6, do: :telemetry.execute([p, :gauge], %{value: v}, %{})
      :ok = Telemetry.flush(server)
      monitor = monitor |> Feeds.drain() |> Monitor.tick(now: 1)

      assert Enum.map(Monitor.deliveries(monitor).gauge.rows, & &1.value) == [1, 2, 3, 4, 5, 6]
      assert Monitor.status(monitor) == %{gauge: :live}
      assert :ok = Monitor.stop(monitor)
    end

    test "a subscriber that exits is dropped", context do
      p = prefix(context)
      server = start([last_value("#{p}.gauge.value")])
      feed = Telemetry.feed(server, "#{p}.gauge.value")
      subscriber = spawn(fn -> receive do: (:never -> :ok) end)
      {:ok, _ref} = Feed.subscribe(feed, subscriber)
      ref = Process.monitor(subscriber)
      Process.exit(subscriber, :kill)
      assert_receive {:DOWN, ^ref, :process, _, :killed}
      :telemetry.execute([p, :gauge], %{value: 1}, %{})
      assert :ok = Telemetry.flush(server)
      assert %{subscribers: subscribers} = :sys.get_state(server)
      assert subscribers == %{}
    end
  end

  describe "the collector's life" do
    test "calls answer values when the collector is gone, and its handler is detached", context do
      p = prefix(context)
      server = start([last_value("#{p}.gauge.value")])
      feed = Telemetry.feed(server, "#{p}.gauge.value")
      assert [_handler] = :telemetry.list_handlers([p, :gauge])

      :ok = stop_supervised(Telemetry)
      assert :telemetry.list_handlers([p, :gauge]) == []
      assert Feed.describe(feed) == {:error, :noproc}
      assert Feed.fetch(feed, nil, nil) == {:error, :noproc}
      assert Feed.subscribe(feed, self()) == {:error, :noproc}
      assert Feed.unsubscribe(feed, make_ref()) == :ok
      refute_received _anything
    end

    test "a collector that stops during a call is a value, not an exit", context do
      p = prefix(context)
      server = start([last_value("#{p}.gauge.value")])
      :sys.suspend(server)
      feed = Telemetry.feed(server, "#{p}.gauge.value")
      caller = Task.async(fn -> Feed.describe(feed) end)
      # Wait until the call has reached the suspended collector's mailbox.
      wait_for_message(server)
      Process.exit(server, :kill)
      assert {:error, {:down, :killed}} = Task.await(caller)
    end
  end

  defp wait_for_message(pid) do
    case Process.info(pid, :message_queue_len) do
      {:message_queue_len, 0} ->
        receive after: (1 -> wait_for_message(pid))

      _queued ->
        :ok
    end
  end
end
