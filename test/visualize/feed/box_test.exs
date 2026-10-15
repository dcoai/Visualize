defmodule Visualize.Feed.BoxTest do
  @moduledoc """
  The box window (spec/08 §11.1–§11.2, §11.4–§11.6, §12.3, #626, D-168): ranges over any
  `:time` or `:number` field, each identity's latest row, the shorthand kept, a box checked
  against its schema, and a feed that honors a box answering the same rows as one
  `Visualize.Feed.finish/3` finishes.
  """
  use ExUnit.Case, async: true

  alias Visualize.Data.{Delivery, Schema}
  alias Visualize.Feed
  alias Visualize.Feed.{Combine, Conformance, Monitor, Signals, Window}
  alias Visualize.Test.Feeds
  alias Visualize.Test.Feeds.{Broken, Fleet}

  @boxes [
    %{ranges: %{x: [2, 7]}},
    %{ranges: %{t: [3, 8], x: [0, 5], y: [2, 9]}},
    %{ranges: %{t: [nil, 9]}, latest: true},
    %{ranges: %{"t" => [4, 9], "x" => [1, 8]}, latest: true},
    %{latest: true},
    %{ranges: %{}, latest: false}
  ]

  defp fetch!(feed, window) do
    {:ok, delivery} = Feed.fetch(feed, window, nil)
    delivery
  end

  # What a monitor does with a delivery: finished for what the feed does not honor.
  defp finished(feed, window, budget \\ nil) do
    {_version, schema, supports} = Feed.describe(feed)

    feed
    |> fetch!(window)
    |> Feed.finish(schema, supports: supports, window: window, budget: budget)
  end

  describe "the box" do
    test "box/2 gives every window as the box it asks, the shorthand only where it applies" do
      schema = Fleet.schema()
      assert Window.box(nil, schema) == nil
      assert Window.box([1, 5], schema) == %{ranges: %{t: [1, 5]}, latest: false}
      assert Window.box([~U[2026-10-14 00:00:00Z], nil], schema) == nil
      assert Window.box(%{latest: true}, schema) == %{ranges: %{}, latest: true}

      no_clock = Schema.new!(%{v: %{type: :number}})
      assert Window.box([1, 5], no_clock) == nil
    end

    test "range/2 reads a field's range by either spelling, and the shorthand as it is" do
      assert Window.range(%{ranges: %{"x" => [0, 1]}}, :x) == [0, 1]
      assert Window.range(%{ranges: %{x: [0, 1]}}, "x") == [0, 1]
      assert Window.range(%{ranges: %{x: [0, 1]}}, :t) == nil
      assert Window.range(nil, :t) == nil
      assert Window.range([:not, :a_time], :t) == [:not, :a_time]
      assert Window.range(%{ranges: :nope}, :t) == nil
    end

    test "check/2 holds a box to the schema, every fault at its path" do
      schema =
        Schema.new!(%{
          at: %{type: :time},
          n: %{type: :number, window: true},
          s: %{type: :category},
          id: %{type: :text, identity: true}
        })

      assert Window.check(nil, schema) == :ok
      assert Window.check([9, 1], schema) == :ok
      assert Window.check([:not, :a_time], schema) == :ok
      assert Window.check(%{}, schema) == :ok

      assert Window.check(
               %{ranges: %{n: [1, 1], at: [nil, ~D[2026-10-14]]}, latest: true},
               schema
             ) == :ok

      assert Window.check(:soon, schema) == {:error, [{[], {:type, :window}}]}
      assert Window.check(%{ranges: [1, 2]}, schema) == {:error, [{[:ranges], {:type, :ranges}}]}

      assert {:error, faults} =
               Window.check(
                 %{
                   ranges: %{
                     "id" => [0, 1],
                     n: [5, 1],
                     at: [~D[2026-10-14], ~U[2026-10-14 00:00:00Z]],
                     s: ["a", "b"],
                     nope: [0, 1]
                   },
                   latest: :yes,
                   extra: 1
                 },
                 schema
               )

      assert faults == [
               {[:extra], :unknown_key},
               {[:latest], {:type, :boolean}},
               {[:ranges, :at], {:window, :mixed}},
               {[:ranges, :n], {:window, :inverted}},
               {[:ranges, :nope], {:window, :unknown_field}},
               {[:ranges, :s], {:invalid_for, :category}},
               {[:ranges, "id"], {:invalid_for, :text}}
             ]

      assert Window.check(%{ranges: %{n: [0, "1"], at: [5, nil], m: 1}}, schema) ==
               {:error,
                [
                  {[:ranges, :at, 0], {:type, :time}},
                  {[:ranges, :m], {:window, :unknown_field}},
                  {[:ranges, :n, 1], {:type, :number}}
                ]}

      bare = Schema.new!(%{v: %{type: :number}, s: %{type: :category}})

      assert Window.check(%{latest: true}, bare) ==
               {:error,
                [{[:latest], {:window, :no_window_field}}, {[:latest], {:window, :no_identity}}]}
    end

    test "a range over a field the schema does not describe is unknown, whatever its name" do
      assert Window.check(%{ranges: %{{:t} => [0, 1]}}, Fleet.schema()) ==
               {:error, [{[:ranges, {:t}], {:window, :unknown_field}}]}
    end

    test "latest_rows/3 keeps each identity's last row, ties to the later, in order" do
      rows = [
        %{id: "a", t: 1, n: 1},
        %{id: "b", t: 5, n: 2},
        %{id: "a", t: 5, n: 3},
        %{id: "a", t: 5, n: 4},
        %{id: "b", t: 2, n: 5},
        %{id: "c", t: nil, n: 6},
        %{id: nil, t: 9, n: 7}
      ]

      kept = Window.latest_rows(rows, & &1.t, & &1.id)
      assert Enum.map(kept, & &1.n) == [2, 4]
    end
  end

  describe "finish/3" do
    test "the shorthand and nil finish exactly as before" do
      rows = Fleet.rows()
      delivery = Delivery.new(rows, window: [0, 11])
      schema = Fleet.schema()

      assert Feed.finish(delivery, schema, window: nil) == delivery
      trimmed = Feed.finish(delivery, schema, window: [3, 4])
      assert Enum.map(trimmed.rows, & &1.t) |> Enum.uniq() == [3, 4]
      assert trimmed.window == [3, 4]

      # A shorthand of instants over a feed of ticks asks for its own span (D-154).
      assert Feed.finish(delivery, schema, window: [~U[2026-10-14 00:00:00Z], nil]) == delivery
      assert Feed.finish(delivery, schema, supports: [:window], window: [3, 4]) == delivery
    end

    test "a box trims its window field's range, its region, then keeps the latest rows" do
      delivery = Delivery.new(Fleet.rows(), window: [0, 11])
      schema = Fleet.schema()
      box = %{ranges: %{t: [nil, 9], x: [0, 6]}, latest: true}
      finished = Feed.finish(delivery, schema, window: box)

      within = for r <- Fleet.rows(), r.t <= 9, r.x <= 6, do: r

      expected =
        for car <- ["a", "b", "c"], do: Enum.max_by(Enum.filter(within, &(&1.car == car)), & &1.t)

      assert Enum.sort_by(finished.rows, & &1.car) == expected
      assert finished.window == [0, 9]
      assert finished.reduced_by == nil
    end

    test "each part is skipped where supports names it" do
      delivery = Delivery.new(Fleet.rows(), window: [0, 11])
      box = %{ranges: %{t: [2, 4], x: [0, 8]}, latest: true}

      assert Feed.finish(delivery, Fleet.schema(),
               supports: [:window, :region, :latest],
               window: box
             ) == delivery

      only_latest =
        Feed.finish(delivery, Fleet.schema(), supports: [:window, :region], window: box)

      assert length(only_latest.rows) == 3

      no_latest = Feed.finish(delivery, Fleet.schema(), supports: [:latest], window: box)
      assert Enum.all?(no_latest.rows, &(&1.t in 2..4 and &1.x <= 8))
      assert length(no_latest.rows) > 3
    end

    test "the budget follows the latest rows" do
      delivery = Delivery.new(Fleet.rows())
      finished = Feed.finish(delivery, Fleet.schema(), window: %{latest: true}, budget: 5)
      assert length(finished.rows) == 3
      assert finished.reduced_by == nil
    end

    test "a box the schema cannot answer raises, naming its faults" do
      delivery = Delivery.new(Fleet.rows())

      assert_raise ArgumentError, ~r/:inverted/, fn ->
        Feed.finish(delivery, Fleet.schema(), window: %{ranges: %{x: [9, 1]}})
      end

      assert_raise ArgumentError, ~r/:no_identity/, fn ->
        Feed.finish(delivery, Schema.new!(%{t: %{type: :number, window: true}}),
          window: %{latest: true}
        )
      end
    end

    test "rows with no identity or no time name nothing under latest" do
      schema = Fleet.schema()

      rows = [
        %{t: 1, car: nil, x: 0, y: 0},
        %{t: nil, car: "a", x: 0, y: 0},
        %{t: 2, car: "a", x: 0, y: 0}
      ]

      assert Feed.finish(Delivery.new(rows), schema, window: %{latest: true}).rows == [
               List.last(rows)
             ]
    end
  end

  describe "a feed that honors a box and one that does not" do
    test "finish the same rows, box by box" do
      for window <- @boxes ++ [nil, [2, 6]] do
        assert finished(Fleet.new(), window).rows ==
                 finished(Fleet.new(honors: false), window).rows,
               "window #{inspect(window)}"
      end
    end

    test "latest gives at most one row per identity, the last within the box" do
      for %{latest: true} = box <- @boxes, feed <- [Fleet.new(), Fleet.new(honors: false)] do
        rows = finished(feed, box).rows
        assert rows |> Enum.map(& &1.car) |> Enum.uniq() |> length() == length(rows)
        whole = finished(feed, %{box | latest: false}).rows

        for row <- rows do
          assert row.t ==
                   whole |> Enum.filter(&(&1.car == row.car)) |> Enum.map(& &1.t) |> Enum.max()
        end
      end
    end

    test "a monitor hands out the same rows of either" do
      for window <- @boxes do
        handed =
          for honors <- [true, false] do
            monitor =
              Monitor.new(%{f: Fleet.new(honors: honors)}, window: window)
              |> Monitor.tick(now: 0)

            Monitor.deliveries(monitor).f.rows
          end

        assert [same, same] = handed
      end
    end
  end

  describe "the monitor" do
    test "a box the feed's schema refuses is not asked, and the feed is down with the faults" do
      {feed, agent} = Feeds.scripted(schema: Fleet.schema(), rows: Fleet.rows())
      monitor = Monitor.new(%{f: feed}, window: %{ranges: %{x: [9, 1]}}) |> Monitor.tick(now: 0)

      assert Monitor.status(monitor) == %{
               f: {:down, {:window, [{[:ranges, :x], {:window, :inverted}}]}}
             }

      assert Feeds.calls(agent, :fetch) == 0
      assert Monitor.deliveries(monitor) == %{}

      monitor = monitor |> Monitor.window(%{ranges: %{x: [1, 9]}}) |> Monitor.tick(now: 1)
      assert Monitor.status(monitor) == %{f: :live}
      assert Enum.all?(Monitor.deliveries(monitor).f.rows, &(&1.x in 1..9))
    end

    test "a live feed asked for the latest rows holds one row per entity however much it pushes" do
      schema = Fleet.schema()

      {feed, agent} =
        Feeds.scripted(
          schema: schema,
          supports: [:window, :push],
          rows: Enum.take(Fleet.rows(), 6)
        )

      monitor =
        Monitor.new(%{f: feed}, window: %{latest: true}) |> Monitor.tick(now: 0) |> Feeds.drain()

      assert length(Monitor.deliveries(monitor).f.rows) == 3

      for t <- 20..25 do
        row = %{t: t, car: Enum.at(["a", "b", "c"], rem(t, 3)), x: t, y: t}

        Feeds.push(
          agent,
          self(),
          Delivery.new([row], window: [t, t], schema: Schema.version(schema))
        )
      end

      monitor = monitor |> Feeds.drain() |> Monitor.tick(now: 1)
      rows = Monitor.deliveries(monitor).f.rows
      assert Enum.sort(Enum.map(rows, &{&1.car, &1.t})) == [{"a", 24}, {"b", 25}, {"c", 23}]
      assert length(monitor.entries.f.held.rows) == 3
      assert Feeds.calls(agent, :fetch) == 1
    end

    test "a box moves as the shorthand does, until its region, latest or an earlier to asks more" do
      schema = Fleet.schema()

      fetched = fn window, _budget ->
        {Fleet.rows(), [window: Window.range(window, :t) || [0, 11]]}
      end

      {feed, agent} = Feeds.scripted(schema: schema, supports: [:window, :push], rows: fetched)

      monitor = Monitor.new(%{f: feed}, window: %{ranges: %{t: [2, nil]}}) |> Monitor.tick(now: 0)
      assert Feeds.calls(agent, :fetch) == 1

      # Within what it holds, the region and latest unchanged: trimmed, not fetched.
      monitor = monitor |> Monitor.window(%{ranges: %{t: [4, nil]}}) |> Monitor.tick(now: 1)
      assert Feeds.calls(agent, :fetch) == 1

      # A region changed: fetched.
      monitor =
        monitor |> Monitor.window(%{ranges: %{t: [4, nil], x: [0, 3]}}) |> Monitor.tick(now: 2)

      assert Feeds.calls(agent, :fetch) == 2

      # latest asked: fetched; a later to under latest: trimmed; an earlier one: fetched.
      monitor =
        monitor |> Monitor.window(%{ranges: %{t: [4, 8]}, latest: true}) |> Monitor.tick(now: 3)

      assert Feeds.calls(agent, :fetch) == 3

      monitor =
        monitor |> Monitor.window(%{ranges: %{t: [4, 9]}, latest: true}) |> Monitor.tick(now: 4)

      assert Feeds.calls(agent, :fetch) == 3

      monitor =
        monitor |> Monitor.window(%{ranges: %{t: [4, 6]}, latest: true}) |> Monitor.tick(now: 5)

      assert Feeds.calls(agent, :fetch) == 4
      assert Enum.map(Monitor.deliveries(monitor).f.rows, & &1.t) == [6, 6, 6]
    end
  end

  describe "the providers" do
    test "Signals serves a box by its tick's range, the rest finished by visualize" do
      signal = Visualize.Signals.new(:discrete, [:t, :n], window: 3)
      feed = Signals.new(signal, tick: 30)
      assert {_v, _s, [:window]} = Feed.describe(feed)
      assert fetch!(feed, %{ranges: %{t: [4, 12]}}).window == [4, 12]

      assert fetch!(feed, %{ranges: %{t: [4, 12]}, latest: false}).rows ==
               fetch!(feed, [4, 12]).rows

      assert {:error, {:window, _}} =
               Feed.fetch(feed, %{ranges: %{t: [~U[2026-10-14 00:00:00Z], nil]}}, nil)
    end

    test "Combine routes a box by its window field's range, and the union is finished" do
      # Each part is asked `[from, to]`, never the box: a part answering a map would fail
      # to match here.
      part = fn keep, start ->
        Feeds.scripted(
          schema: Fleet.schema(),
          supports: [:window],
          rows: fn [from, to], _budget ->
            rows = Enum.filter(Fleet.rows(), &(keep.(&1.t) and Window.within?(&1.t, [from, to])))
            {rows, [window: [max(from || start, start), to]]}
          end
        )
      end

      {fresh, fresh_agent} = part.(&(&1 >= 6), 6)
      {older, older_agent} = part.(&(&1 < 6), 0)
      combined = Combine.new([fresh, older])
      box = %{ranges: %{t: [0, 11], x: [0, 4]}, latest: true}

      assert {_version, _schema, [:window]} = Feed.describe(combined)
      assert finished(combined, box).rows == finished(Fleet.new(honors: false), box).rows
      assert Feeds.calls(fresh_agent, :fetch) == 1
      assert Feeds.calls(older_agent, :fetch) == 1
    end
  end

  describe "the conformance kit" do
    test "a feed that honors a box, and one that does not, pass every check" do
      windows = [nil, [2, 6]] ++ @boxes
      assert Conformance.check(Fleet.new(), windows: windows) == []
      assert Conformance.check(Fleet.new(honors: false), windows: windows) == []
    end

    test "a region or latest feed with no box to probe it says so" do
      findings = Conformance.check(:supports, Fleet.new(), windows: [nil, [2, 6]])
      assert {:supports, {:no_probe, :region}} in findings
      assert {:supports, {:no_probe, :latest}} in findings
    end

    test "each flaw of a box fails the supports check with the finding that names it" do
      box = %{ranges: %{t: [2, 8], x: [0, 4]}, latest: true}
      region = %{ranges: %{x: [0, 4]}}
      opts = [windows: [[2, 8], box, region], budgets: [nil]]

      overrun = Conformance.check(:supports, Fleet.new(flaw: :region_overrun), opts)
      assert Enum.any?(overrun, &match?({:supports, {:region_row, {^region, nil}, :x, _}}, &1))

      assert {:supports, {:latest_twice, {box, nil}, "a"}} in Conformance.check(
               :supports,
               Fleet.new(flaw: :latest_twice),
               opts
             )

      assert {:supports, {:not_latest, {box, nil}, "a"}} in Conformance.check(
               :supports,
               Fleet.new(flaw: :stale_latest),
               opts
             )
    end

    test "a probe box the schema refuses is the run's fault, and every finding has words" do
      box = %{latest: true}

      assert Conformance.check(:deliveries, Broken.new(), windows: [box]) ==
               List.duplicate(
                 {:deliveries, {:probe, box, [{[:latest], {:window, :no_identity}}]}},
                 2
               )

      for finding <- [
            {:deliveries, {:probe, box, []}},
            {:supports, {:no_probe, :region}},
            {:supports, {:no_probe, :latest}},
            {:supports, {:region_row, {box, nil}, :x, 9}},
            {:supports, {:latest_twice, {box, nil}, "a"}},
            {:supports, {:not_latest, {box, nil}, "a"}}
          ] do
        refute Conformance.format(finding) =~ "{:"
      end
    end
  end
end
