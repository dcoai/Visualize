defmodule Visualize.Feed.CombineTest do
  @moduledoc """
  `Visualize.Feed.Combine` and `Visualize.Feed.Signals` (spec/08 §11.5–§11.6, #537,
  D-140): live data and its history in one slot, routed by window and deduplicated at the
  seam; a signal as a pull feed that honours its window.
  """
  use ExUnit.Case, async: true

  alias Visualize.Data.{Delivery, Schema}
  alias Visualize.Feed
  alias Visualize.Feed.{Combine, Monitor, Signals}
  alias Visualize.Test.Feeds

  doctest Combine
  doctest Signals

  @schema Schema.new!(%{t: %{type: :time}, v: %{type: :number}})

  defp rows(range, source), do: for(t <- range, do: %{t: t, v: t, from: source})

  # A store that holds `range` and honours windows, as a history store does.
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
    test "every part must describe the same version, and the schema needs a time field" do
      {live, _} = store(50..100, :live)
      other = Schema.new!(%{t: %{type: :time}, v: %{type: :number, label: "Other"}})
      {history, _} = Feeds.scripted(schema: other)
      assert {:error, {:combine_schema, [_, _]}} = Feed.describe(Combine.new([live, history]))

      untimed = Schema.new!(%{v: %{type: :number}})
      {a, _} = Feeds.scripted(schema: untimed)
      assert Feed.describe(Combine.new([a])) == {:error, :combine_time_field}
    end

    test "a combination honours the window, and pushes when its first feed does" do
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
    test "honours a window of ticks up to the present tick, capped at its limit" do
      signal = Visualize.Signals.new(:sine, [:t, :v], window: 5)
      feed = Signals.new(signal, tick: 100, limit: 10)
      assert {_v, schema, [:window]} = Feed.describe(feed)
      assert Feed.time_field(schema) == :t

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

    test "rows match the signal's own, and a description adds to the defaults" do
      signal = Visualize.Signals.new(:random, [:t, :a, :b], seed: 3)
      feed = Signals.new(signal, tick: 30, describe: %{a: %{unit: "ms", label: "A"}})
      {:ok, d} = Feed.fetch(feed, nil, nil)
      assert d.rows == Visualize.Signals.rows(signal, 30)
      assert {:ok, %{type: :number, unit: "ms", label: "A"}} = Schema.fetch(feed.schema, :a)
      assert_raise ArgumentError, fn -> Signals.new(signal, describe: %{a: %{colour: "red"}}) end
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
