defmodule Visualize.FeedTest do
  @moduledoc """
  The feed behaviour and what visualize finishes for it (spec/08 §11.1–§11.2, #537,
  D-140): a window and a budget are requests, so a rows-only feed is trimmed and reduced
  by visualize and a feed that honours them is not touched again.
  """
  use ExUnit.Case, async: true

  alias Visualize.Data.{Delivery, Schema}
  alias Visualize.Feed
  alias Visualize.Feed.Window
  alias Visualize.Test.Feeds

  doctest Feed
  doctest Window

  @schema Schema.new!(%{
            t: %{type: :time},
            v: %{type: :number, unit: "ms"},
            route: %{type: :category}
          })

  defp rows(n, routes \\ ["/a"]) do
    for t <- 1..n, route <- routes, do: %{t: t, v: :math.sin(t / 7) * 10 + t / 50, route: route}
  end

  describe "the behaviour" do
    test "dispatches to the struct's module, and a feed that does not push says so" do
      {feed, agent} = Feeds.scripted(schema: @schema, rows: rows(3))
      assert {version, @schema, []} = Feed.describe(feed)
      assert version == Schema.version(@schema)
      assert {:ok, %Delivery{rows: [_, _, _]}} = Feed.fetch(feed, nil, nil)
      assert Feeds.calls(agent, :describe) == 1

      signals = Visualize.Feed.Signals.new(Visualize.Signals.new(:sine, [:t, :v]))
      assert Feed.subscribe(signals, self()) == {:error, :no_push}
      assert Feed.unsubscribe(signals, make_ref()) == :ok
      assert Feed.capabilities() == [:window, :budget, :push]
    end

    test "errors are values, and a describer answers by name" do
      {feed, _agent} = Feeds.scripted(schema: @schema, error: :unreachable)
      assert Feed.describe(feed) == {:error, :unreachable}
      assert Feed.fetch(feed, nil, nil) == {:error, :unreachable}

      {good, _agent} = Feeds.scripted(schema: @schema)
      describe = Feed.describer(%{good: good, bad: feed})
      assert describe.(:good) == {:ok, @schema}
      assert describe.(:bad) == {:error, :unreachable}
      assert describe.(:missing) == {:error, :no_feed}
    end

    test "the time field is the schema's one :time field" do
      assert Feed.time_field(@schema) == :t
      assert Feed.time_field(Schema.new!(%{v: %{type: :number}})) == nil
      assert Feed.time_field(Schema.new!(%{a: %{type: :time}, b: %{type: :time}})) == nil
    end
  end

  describe "finish/3: requests, not requirements" do
    test "a rows-only feed is trimmed to the window by visualize" do
      delivery = Delivery.new(rows(10))
      done = Feed.finish(delivery, @schema, supports: [], window: [3, 6])
      assert Enum.map(done.rows, & &1.t) == [3, 4, 5, 6]
      assert done.window == [3, 6]
      assert done.reduced_by == nil
    end

    test "trimming intersects the window the feed said it served, and an open bound is open" do
      delivery = Delivery.new(rows(10), window: [5, 10])
      assert Feed.finish(delivery, @schema, window: [2, 8]).window == [5, 8]
      done = Feed.finish(Delivery.new(rows(10)), @schema, window: [8, nil])
      assert Enum.map(done.rows, & &1.t) == [8, 9, 10]
    end

    test "a feed that honours the window is not trimmed again" do
      delivery = Delivery.new(rows(10), window: [1, 10])
      assert Feed.finish(delivery, @schema, supports: [:window], window: [3, 6]) == delivery
    end

    test "a rows-only feed is reduced to the budget by visualize, recording it" do
      done = Feed.finish(Delivery.new(rows(500)), @schema, budget: 50)
      assert length(done.rows) == 50
      assert done.reduced_by == :visualize
      # A subsequence of whole rows, in order, the ends kept.
      assert Enum.map(done.rows, & &1.t) == Enum.sort(Enum.map(done.rows, & &1.t))
      assert hd(done.rows).t == 1 and List.last(done.rows).t == 500
    end

    test "a budget-honouring feed is not reduced again, whatever it returned" do
      delivery = Delivery.new(rows(500), reduced_by: :feed)
      assert Feed.finish(delivery, @schema, supports: [:budget], budget: 50) == delivery
    end

    test "a delivery within the budget, or one with no window or budget asked, comes back as it is" do
      delivery = Delivery.new(rows(10))
      assert Feed.finish(delivery, @schema, budget: 50) == delivery
      assert Feed.finish(delivery, @schema, []) == delivery
    end

    test "each series keeps its shape: the budget is shared by the category's values" do
      rows = rows(400, ["/a", "/b"])
      done = Feed.finish(Delivery.new(rows), @schema, budget: 40)
      by_route = Enum.group_by(done.rows, & &1.route)
      assert map_size(by_route) == 2
      assert length(by_route["/a"]) == 20 and length(by_route["/b"]) == 20
      # Each series' own ends survive.
      for {_route, kept} <- by_route, do: assert(hd(kept).t == 1 and List.last(kept).t == 400)
    end

    test "every number field's peak survives, the rows kept whole" do
      schema = Schema.new!(%{t: %{type: :time}, a: %{type: :number}, b: %{type: :number}})

      rows =
        for t <- 1..300,
            do: %{t: t, a: if(t == 77, do: 1000, else: 0), b: if(t == 211, do: -1000, else: 0)}

      done = Feed.finish(Delivery.new(rows), schema, budget: 20)
      assert length(done.rows) <= 20
      assert Enum.any?(done.rows, &(&1.a == 1000))
      assert Enum.any?(done.rows, &(&1.b == -1000))
    end

    test "M4 is the alternative reduction, and keeps the extremes per column" do
      done = Feed.finish(Delivery.new(rows(1000)), @schema, budget: 80, reduce: :m4)
      assert done.reduced_by == :visualize
      assert length(done.rows) <= 80
      values = Enum.map(rows(1000), & &1.v)
      assert Enum.any?(done.rows, &(&1.v == Enum.max(values)))
      assert Enum.any?(done.rows, &(&1.v == Enum.min(values)))
    end

    test "a time column of DateTimes reduces by its microseconds and trims by DateTime" do
      t0 = ~U[2026-10-11 12:00:00Z]
      rows = for s <- 0..299, do: %{t: DateTime.add(t0, s), v: rem(s * 37, 101), route: "/"}
      window = [DateTime.add(t0, 100), DateTime.add(t0, 199)]
      done = Feed.finish(Delivery.new(rows), @schema, window: window, budget: 30)
      assert length(done.rows) == 30
      assert Enum.all?(done.rows, &Window.within?(&1.t, window))
    end

    test "with no time field rows are reduced against their position and not trimmed" do
      schema = Schema.new!(%{v: %{type: :number}})
      rows = for i <- 1..100, do: %{v: rem(i * 13, 17)}
      done = Feed.finish(Delivery.new(rows), schema, window: [1, 2], budget: 10)
      assert length(done.rows) == 10
      assert done.window == nil
    end

    test "a schema with no number field is not reduced" do
      schema = Schema.new!(%{t: %{type: :time}, s: %{type: :category}})
      delivery = Delivery.new(for t <- 1..100, do: %{t: t, s: "x"})
      assert Feed.finish(delivery, schema, budget: 10) == delivery
    end
  end

  describe "Window" do
    test "compares each kind by its own order" do
      assert Window.compare(~D[2026-01-02], ~D[2026-01-01]) == :gt
      assert Window.compare(~N[2026-01-01 00:00:00], ~N[2026-01-01 00:00:01]) == :lt
      assert Window.compare(2.5, 2) == :gt
    end

    test "positions, intersections and the two seams" do
      assert Window.position(~D[0000-01-02]) == 1
      assert Window.position(~N[0000-01-01 00:00:02]) == 2
      assert Window.position("x") == nil
      assert Window.intersect(nil, nil) == nil
      assert Window.intersect([nil, 4], [1, nil]) == [1, 4]
      rows = for t <- 1..5, do: %{"t" => t}
      assert Window.before(rows, :t, 2, 4) == [%{"t" => 2}, %{"t" => 3}]
      assert Window.newer(rows, :t, 4) == [%{"t" => 5}]
      refute Window.within?(nil, [1, 2])
      assert Enum.map([~U[2026-01-01 00:00:00Z], 3, :now], &Window.time?/1) == [true, true, false]
    end
  end
end
