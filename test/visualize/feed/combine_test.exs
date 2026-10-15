defmodule Visualize.Feed.CombineTest do
  @moduledoc """
  `Visualize.Feed.Combine` and `Visualize.Feed.Signals` (spec/08 §11.5–§11.6, #537,
  D-140): live data and its history in one slot, routed by window and deduplicated at the
  seam; a signal as a pull feed that honors its window.
  """
  use ExUnit.Case, async: true

  alias Visualize.Data.{Delivery, Schema}
  alias Visualize.Feed
  alias Visualize.Feed.{Combine, Monitor, Signals}
  alias Visualize.Test.Feeds

  doctest Combine
  doctest Signals

  # The stores count, so `t` is a `:number` named the window field (D-154): routing works
  # over it as over instants.
  @schema Schema.new!(%{t: %{type: :number, window: true}, v: %{type: :number}})

  defp rows(range, source), do: for(t <- range, do: %{t: t, v: t, from: source})

  # A store that holds `range` and honors windows, as a history store does.
  defp store(range, source) do
    answer = fn window, _budget ->
      [from, to] = window || [nil, nil]
      held = rows(range, source) |> Feed.Window.trim(:t, [from, to])
      served = [Feed.Window.latest(from, range.first), Feed.Window.earliest(to, range.last)]
      {held, [window: served, capped: from != nil and from < range.first]}
    end

    Feeds.scripted(schema: @schema, supports: [:window], rows: answer)
  end

  describe "routing by window" do
    test "the freshest feed serves what it holds and the next the rest" do
      {live, _} = store(50..100, :live)
      {history, _} = store(0..100, :history)
      {:ok, delivery} = Feed.fetch(Combine.new([live, history]), [10, 100], nil)

      assert Enum.map(delivery.rows, & &1.t) == Enum.to_list(10..100)
      assert Enum.all?(delivery.rows, &(&1.from == if(&1.t >= 50, do: :live, else: :history)))
      assert delivery.window == [10, 100]
      refute delivery.capped
      assert delivery.schema == Schema.version(@schema)
    end

    test "a window the freshest feed covers is not asked of the history" do
      {live, _} = store(50..100, :live)
      {history, agent} = store(0..100, :history)
      {:ok, delivery} = Feed.fetch(Combine.new([live, history]), [60, 70], nil)
      assert Enum.map(delivery.rows, & &1.t) == Enum.to_list(60..70)
      assert Feeds.calls(agent, :fetch) == 0
    end

    test "the seam is deduplicated: a history that ignores the window gives only what is older" do
      {live, _} = store(50..100, :live)
      {history, _} = Feeds.scripted(schema: @schema, rows: rows(0..100, :history))
      {:ok, delivery} = Feed.fetch(Combine.new([live, history]), [40, nil], nil)
      ts = Enum.map(delivery.rows, & &1.t)
      assert ts == Enum.to_list(40..100)
      assert ts == Enum.uniq(ts)
    end

    test "a window no feed reaches is capped, and an open one takes what every feed has" do
      {live, _} = store(50..100, :live)
      {history, _} = store(20..100, :history)
      combine = Combine.new([live, history])
      {:ok, capped} = Feed.fetch(combine, [0, 100], nil)
      assert capped.capped
      assert capped.window == [20, 100]

      {:ok, all} = Feed.fetch(combine, nil, nil)
      assert Enum.map(all.rows, & &1.t) == Enum.to_list(20..100)
    end

    test "an error of any part is the combination's" do
      {live, _} = store(50..100, :live)
      {history, _} = Feeds.scripted(schema: @schema, error: :down)
      assert Feed.fetch(Combine.new([live, history]), [0, 100], nil) == {:error, :down}
    end
  end

  describe "one schema" do
    test "a part of another version but a compatible schema combines; the schema needs a window field" do
      {live, _} = store(50..100, :live)

      other =
        Schema.new!(%{t: %{type: :number, window: true}, v: %{type: :number, label: "Other"}})

      {history, _} = Feeds.scripted(schema: other, rows: rows(0..100, :history))
      version = Schema.version(@schema)
      assert {^version, @schema, [:window]} = Feed.describe(Combine.new([live, history]))

      untimed = Schema.new!(%{v: %{type: :number}})
      {a, _} = Feeds.scripted(schema: untimed)
      assert Feed.describe(Combine.new([a])) == {:error, :combine_window_field}

      # A count that does not say it is the window field is not one.
      uncounted = Schema.new!(%{t: %{type: :number}, v: %{type: :number}})
      {b, _} = Feeds.scripted(schema: uncounted)
      assert Feed.describe(Combine.new([b])) == {:error, :combine_window_field}
    end

    test "a combination honors the window, and pushes when its first feed does" do
      {pull, _} = store(0..10, :a)
      assert {_v, @schema, [:window]} = Feed.describe(Combine.new([pull]))

      {push, agent} = Feeds.scripted(schema: @schema, supports: [:window, :push])
      combine = Combine.new([push, pull])
      assert {_v, @schema, [:window, :push]} = Feed.describe(combine)
      assert {:ok, ref} = Feed.subscribe(combine, self())
      assert ref == Feeds.ref(agent)
      assert Feed.unsubscribe(combine, ref) == :ok
      assert Feeds.calls(agent, :unsubscribe) == 1
    end
  end

  describe "compatible schemas (D-159)" do
    # The proposal's pair: one metric, a panel's load time, as the in-process telemetry
    # feed describes it and as metresis's store does (#605): atoms against strings,
    # different labels, and facts only the store knows.
    @telemetry Schema.new!(%{
                 t: %{type: :time, label: "Time"},
                 value: %{
                   type: :number,
                   unit: "ms",
                   quantity: :duration,
                   label: "Panel load time"
                 },
                 panel: %{type: :category}
               })

    @metresis Schema.new!(%{
                "t" => %{type: :time},
                "value" => %{
                  type: :number,
                  unit: "ms",
                  quantity: :duration,
                  label: "metresis.panel.load.duration.max",
                  polarity: :lower_is_better,
                  bounds: [0.0, nil],
                  metric_kind: :gauge
                },
                "panel" => %{type: :category, label: "panel"}
              })

    @t0 ~U[2026-10-13 00:00:00Z]

    defp at(s), do: DateTime.add(@t0, s, :second)

    # A store holding a row per second of `seconds`, `row/1`'s, honoring `DateTime`
    # windows over `field`.
    defp timed(schema, seconds, field, row, supports \\ [:window]) do
      answer = fn window, _budget ->
        [from, to] = window || [nil, nil]
        held = seconds |> Enum.map(row) |> Feed.Window.trim(field, [from, to])
        {held, [window: [Feed.Window.latest(from, at(seconds.first)), to || at(seconds.last)]]}
      end

      Feeds.scripted(schema: schema, supports: supports, rows: answer)
    end

    defp telemetry(supports \\ [:window]),
      do: timed(@telemetry, 60..120, :t, &%{t: at(&1), value: &1 * 1.0, panel: "a"}, supports)

    defp history(schema, row), do: timed(schema, 0..120, "t", row)

    test "the telemetry and metresis pair combines, every row in the first's names" do
      {live, _} = telemetry()
      {history, _} = history(@metresis, &%{"t" => at(&1), "value" => &1 * 1.0, "panel" => "a"})
      combine = Combine.new([live, history])

      version = Schema.version(@telemetry)
      assert {^version, @telemetry, [:window]} = Feed.describe(combine)

      {:ok, delivery} = Feed.fetch(combine, [at(0), at(120)], nil)
      assert delivery.schema == version
      assert delivery.window == [at(0), at(120)]
      assert Enum.map(delivery.rows, & &1.t) == Enum.map(0..120, &at/1)

      assert Enum.map(delivery.rows, &Map.drop(&1, [:t])) ==
               Enum.map(0..120, &%{value: &1 * 1.0, panel: "a"})
    end

    test "a history in s behind live data in ms is converted exactly; the first's rows are untouched" do
      {live, _} = telemetry()

      seconds =
        Schema.new!(%{
          "t" => %{type: :time},
          "value" => %{type: :number, unit: "s"},
          "panel" => %{type: :category}
        })

      {history, _} = history(seconds, &%{"t" => at(&1), "value" => &1 / 1000, "panel" => "a"})
      {:ok, delivery} = Feed.fetch(Combine.new([live, history]), [at(0), at(120)], nil)

      assert Enum.map(delivery.rows, & &1.value) ==
               Enum.map(0..59, &Visualize.Unit.convert(&1 / 1000, "s", "ms")) ++
                 Enum.map(60..120, &(&1 * 1.0))

      assert Enum.at(delivery.rows, 59).value == 59.0
    end

    test "a later feed's extra fields are dropped; a column no schema describes is left" do
      {live, _} = telemetry()

      extra =
        Schema.new!(%{
          "t" => %{type: :time},
          "value" => %{type: :number, unit: "ms"},
          "panel" => %{type: :category},
          "host" => %{type: :category}
        })

      {history, _} =
        history(extra, fn s ->
          %{"t" => at(s), "value" => s, "panel" => "a", "host" => "h", "from" => :history}
        end)

      {:ok, delivery} = Feed.fetch(Combine.new([live, history]), [at(0), at(120)], nil)
      assert hd(delivery.rows) == %{"from" => :history, t: at(0), value: 0, panel: "a"}
      assert List.last(delivery.rows) == %{t: at(120), value: 120.0, panel: "a"}
    end

    test "every incompatibility is reported with the later feed's position" do
      {live, _} = telemetry()
      no_panel = Schema.new!(%{"t" => %{type: :time}, "value" => %{type: :number, unit: "ms"}})

      typed =
        Schema.new!(%{t: %{type: :time}, value: %{type: :category}, panel: %{type: :category}})

      bytes =
        Schema.new!(%{
          t: %{type: :time},
          value: %{type: :number, unit: "By"},
          panel: %{type: :text}
        })

      [missing, type, dimension] =
        for schema <- [no_panel, typed, bytes], do: elem(Feeds.scripted(schema: schema), 0)

      assert Feed.describe(Combine.new([live, missing, type, dimension])) ==
               {:error,
                {:combine_schema,
                 [
                   {1, :panel, :missing},
                   {2, :value, {:type, :number, :category}},
                   {3, :panel, {:type, :category, :text}},
                   {3, :value, {:unit, "ms", "By"}}
                 ]}}

      assert Feed.fetch(Combine.new([live, missing]), [at(0), nil], nil) ==
               {:error, {:combine_schema, [{1, :panel, :missing}]}}
    end

    test "a later feed counting other entities is refused: its identity differs (D-167)" do
      {live, _} = telemetry()

      by_panel =
        Schema.new!(%{
          "t" => %{type: :time},
          "value" => %{type: :number, unit: "ms"},
          "panel" => %{type: :category, identity: true}
        })

      {history, _} = Feeds.scripted(schema: by_panel)

      assert Feed.describe(Combine.new([live, history])) ==
               {:error, {:combine_schema, [{1, :panel, {:identity, false, true}}]}}
    end

    test "a later feed windowing over another field is refused, since routing asks it over its own" do
      {live, _} = store(50..100, :live)
      other = Schema.new!(%{"t" => %{type: :number}, "v" => %{type: :number, window: true}})
      {history, _} = Feeds.scripted(schema: other, rows: rows(0..100, :history))

      assert Feed.describe(Combine.new([live, history])) ==
               {:error, {:combine_schema, [{1, :t, {:window, :t, "v"}}]}}

      assert Feed.fetch(Combine.new([live, history]), [0, 100], nil) ==
               {:error, {:combine_schema, [{1, :t, {:window, :t, "v"}}]}}
    end

    test "a later feed with no window field is refused among its other incompatibilities" do
      {live, _} = store(50..100, :live)
      untimed = Schema.new!(%{"t" => %{type: :number}, "v" => %{type: :category}})
      {history, _} = Feeds.scripted(schema: untimed)

      assert Feed.describe(Combine.new([live, history])) ==
               {:error,
                {:combine_schema,
                 [{1, :t, {:window, :t, nil}}, {1, :v, {:type, :number, :category}}]}}
    end

    test "a unit facing none is refused either way round, in the first's spelling; two absent units agree" do
      unitless =
        Schema.new!(%{
          "t" => %{type: :time},
          "value" => %{type: :number},
          "panel" => %{type: :category}
        })

      {live, _} = telemetry()
      {bare, _} = Feeds.scripted(schema: unitless)

      assert Feed.describe(Combine.new([live, bare])) ==
               {:error, {:combine_schema, [{1, :value, {:unit, "ms", nil}}]}}

      assert Feed.describe(Combine.new([bare, live])) ==
               {:error, {:combine_schema, [{1, "value", {:unit, nil, "ms"}}]}}

      {also_bare, _} =
        Feeds.scripted(
          schema:
            Schema.new!(%{t: %{type: :time}, value: %{type: :number}, panel: %{type: :category}})
        )

      assert {_v, ^unitless, [:window]} = Feed.describe(Combine.new([bare, also_bare]))
    end

    test "pushes pass through unchanged, under the first's version" do
      {live, agent} = telemetry([:window, :push])
      {history, _} = history(@metresis, &%{"t" => at(&1), "value" => &1 * 1.0, "panel" => "a"})
      combine = Combine.new([live, history])

      version = Schema.version(@telemetry)
      assert {^version, @telemetry, [:window, :push]} = Feed.describe(combine)
      assert {:ok, ref} = Feed.subscribe(combine, self())
      assert ref == Feeds.ref(agent)
      assert_received {:visualize_feed, ^ref, {:schema, ^version, @telemetry}}

      assert Feed.unsubscribe(combine, ref) == :ok

      # Monitored, the history's rows and the live end's pushes are one series of one
      # version.
      monitor = Monitor.new(%{slot: combine}, window: [at(0), nil]) |> Monitor.tick(now: 0)
      monitor = Feeds.drain(monitor)
      pushed = Delivery.new([%{t: at(121), value: 121.0, panel: "a"}], schema: version)
      Feeds.push(agent, self(), pushed)
      monitor = monitor |> Feeds.drain() |> Monitor.tick(now: 1)
      delivery = Monitor.deliveries(monitor).slot

      assert delivery.schema == version
      assert Enum.map(delivery.rows, & &1.t) == Enum.map(0..121, &at/1)
      assert Monitor.status(monitor).slot == :live
      assert {:ok, @telemetry} = Schema.Cache.fetch(Monitor.cache(monitor), :slot, version)
    end

    test "a numeric window field in other units has its window converted both ways" do
      ms = Schema.new!(%{t: %{type: :number, window: true, unit: "ms"}, v: %{type: :number}})

      s =
        Schema.new!(%{"t" => %{type: :number, window: true, unit: "s"}, "v" => %{type: :number}})

      {live, _} =
        Feeds.scripted(
          schema: ms,
          supports: [:window],
          rows: fn [from, _to], _budget ->
            held = for t <- 50_000..100_000//1000, t >= from, do: %{t: t, v: :live}
            {held, [window: [max(from, 50_000), 100_000]]}
          end
        )

      {history, agent} =
        Feeds.scripted(
          schema: s,
          supports: [:window],
          rows: fn [from, to], _budget ->
            held = for t <- 0..100, t >= from, t <= to, do: %{"t" => t, "v" => :history}
            {held, [window: [max(from, 0), to]]}
          end
        )

      {:ok, delivery} = Feed.fetch(Combine.new([live, history]), [10_000, 100_000], nil)
      assert Feeds.calls(agent, :fetch) == 1

      assert Enum.map(delivery.rows, & &1.t) ==
               Enum.map(10..49, &(&1 * 1000.0)) ++ Enum.to_list(50_000..100_000//1000)

      assert delivery.window == [10_000.0, 100_000]
      refute delivery.capped
    end
  end

  test "a monitored combination reduces the union, and the live end's pushes extend it" do
    {live, agent} =
      Feeds.scripted(
        schema: @schema,
        supports: [:window, :push],
        rows: fn [from, _to], _budget ->
          {rows(max(from, 900)..1000, :live), [window: [max(from, 900), 1000]]}
        end
      )

    {history, _} = store(0..1000, :history)
    monitor = Monitor.new(%{slot: Combine.new([live, history])}, window: [0, nil], budget: 100)
    monitor = monitor |> Monitor.tick(now: 0) |> Feeds.drain()
    delivery = Monitor.deliveries(monitor).slot
    assert length(delivery.rows) == 100
    assert delivery.reduced_by == :visualize

    Feeds.push(
      agent,
      self(),
      Delivery.new(rows(1001..1010, :live), schema: Schema.version(@schema))
    )

    monitor = monitor |> Feeds.drain() |> Monitor.tick(now: 1)
    assert List.last(Monitor.deliveries(monitor).slot.rows).t == 1010
  end

  describe "a signal as a feed" do
    test "honors a window of ticks up to the present tick, capped at its limit" do
      signal = Visualize.Signals.new(:sine, [:t, :v], window: 5)
      feed = Signals.new(signal, tick: 100, limit: 10)
      assert {_v, schema, [:window]} = Feed.describe(feed)
      # The tick is a count, not an instant: a `:number` named the window field (D-154).
      assert Feed.window_field(schema) == :t
      assert Schema.fetch(schema, :t) == {:ok, %{type: :number, window: true, label: "Tick"}}

      {:ok, d} = Feed.fetch(feed, nil, nil)

      assert {Enum.map(d.rows, & &1.t), d.window, d.capped} ==
               {Enum.to_list(96..100), [96, 100], false}

      {:ok, d} = Feed.fetch(feed, [0, 1000], nil)
      assert {length(d.rows), d.window, d.capped} == {10, [91, 100], true}

      {:ok, d} = Feed.fetch(Signals.at(feed, 3), [-5, nil], nil)
      assert Enum.map(d.rows, & &1.t) == [0, 1, 2, 3]

      assert Feed.fetch(feed, [~D[2026-01-01], nil], nil) ==
               {:error, {:window, [~D[2026-01-01], nil]}}
    end

    test "two tick feeds combine by their declared window field, and a monitor windows them in ticks" do
      signal = Visualize.Signals.new(:discrete, [:t, :n])

      combine =
        Combine.new([Signals.new(signal, tick: 50, limit: 10), Signals.new(signal, tick: 50)])

      assert {_v, schema, [:window]} = Feed.describe(combine)
      assert Feed.window_field(schema) == :t

      {:ok, d} = Feed.fetch(combine, [20, 50], nil)
      assert Enum.map(d.rows, & &1.t) == Enum.to_list(20..50)
      assert {d.window, d.capped} == {[20, 50], false}

      monitor = Monitor.new(%{slot: combine}, window: [30, 45]) |> Monitor.tick(now: 0)
      assert Enum.map(Monitor.deliveries(monitor).slot.rows, & &1.t) == Enum.to_list(30..45)
    end

    test "rows match the signal's own, and a description adds to the defaults" do
      signal = Visualize.Signals.new(:random, [:t, :a, :b], seed: 3)
      feed = Signals.new(signal, tick: 30, describe: %{a: %{unit: "ms", label: "A"}})
      {:ok, d} = Feed.fetch(feed, nil, nil)
      assert d.rows == Visualize.Signals.rows(signal, 30)
      assert {:ok, %{type: :number, unit: "ms", label: "A"}} = Schema.fetch(feed.schema, :a)
      assert_raise ArgumentError, fn -> Signals.new(signal, describe: %{a: %{color: "red"}}) end
    end

    test "a clocked feed reads its tick from the clock" do
      {:ok, clock} = Agent.start_link(fn -> 1_000 end)
      read = fn -> Agent.get(clock, & &1) end
      signal = Visualize.Signals.new(:discrete, [:t, :n], window: 1)
      feed = Signals.new(signal, every: 100, clock: read)
      assert {:ok, %{rows: [%{t: 0}]}} = Feed.fetch(feed, nil, nil)
      Agent.update(clock, &(&1 + 250))
      assert {:ok, %{rows: [%{t: 2}]}} = Feed.fetch(feed, nil, nil)
    end

    test "monitored, a signal is polled at its data rate and reduced to the budget" do
      signal = Visualize.Signals.new(:sine, [:t, :v], window: 400)
      monitor = Monitor.new(%{wave: Signals.new(signal, tick: 1000)}, budget: 40, every: 50)
      monitor = Monitor.tick(monitor, now: 0)
      delivery = Monitor.deliveries(monitor).wave
      assert {length(delivery.rows), delivery.reduced_by} == {40, :visualize}

      monitor =
        Monitor.put(monitor, :wave, Signals.new(signal, tick: 1001)) |> Monitor.tick(now: 50)

      assert List.last(Monitor.deliveries(monitor).wave.rows).t == 1001
    end
  end
end
