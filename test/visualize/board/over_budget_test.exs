defmodule Visualize.Board.OverBudgetTest do
  @moduledoc """
  A slot over the board's ceiling (spec/15 §8.2, §8.4, #865, D-227): a feed that names
  `:budget` and ships more rows than the ceiling is handed to its cell without them, and
  the cell is `{:over_budget, rows, ceiling}`, its panel in the chart's place. Within the
  ceiling, or with none, the cell draws; a feed that is down says so first; a snapshot
  keeps the state through its map and JSON forms.
  """
  use ExUnit.Case, async: true

  @moduletag :capture_log

  alias Visualize.Board
  alias Visualize.Board.{Binding, Export, Server, Snapshot, View}
  alias Visualize.Data.Schema
  alias Visualize.Test.Feeds

  # The fake feeds' ticks are a `:number` window field.
  @design %{
    version: 2,
    sources: %{primary: %{fields: [:t, :v]}},
    frames: %{
      main: %{
        kind: :cartesian,
        scales: %{x: %{kind: :linear}, y: %{kind: :linear}},
        axes: [%{scale: :x, side: :bottom}, %{scale: :y, side: :left}]
      }
    },
    marks: [%{type: :line, data: :primary, channels: %{x: :t, y: :v}}]
  }

  @schema Schema.new!(%{t: %{type: :number, window: true}, v: %{type: :number}})

  defp rows(n), do: for(t <- 0..(n - 1), do: %{t: t, v: rem(t * 7, 11)})

  defp start(feed, opts) do
    sup = start_supervised!(Supervisor.child_spec(Visualize.Board.Supervisor, id: make_ref()))

    board =
      Board.from_map!(%{cells: %{a: %{x: 0, y: 0, w: 12, h: 3, ref: {:composite, 1}}}})

    defaults = [
      board: board,
      store: %{{:composite, 1} => @design},
      feeds: %{f: feed},
      binding: Binding.new(%{{:a, :primary} => :f}),
      tick: nil,
      clock: fn -> ~U[2026-10-21 12:00:00Z] end
    ]

    {:ok, server} = Server.start(sup, Keyword.merge(defaults, opts))
    {:ok, _info} = Server.subscribe(server)
    server
  end

  defp scripted(opts) do
    {feed, agent} = Feeds.scripted(Keyword.put(opts, :schema, @schema))
    Process.unlink(agent)
    on_exit(fn -> if Process.alive?(agent), do: Agent.stop(agent) end)
    {feed, agent}
  end

  # The fake feed of the conformance kit (spec/08 §12), its agent outliving the test until
  # the board has unsubscribed.
  defp broken(flaw \\ nil) do
    %Feeds.Broken{agent: agent} = feed = Feeds.Broken.new(flaw)
    Process.unlink(agent)
    on_exit(fn -> if Process.alive?(agent), do: Agent.stop(agent) end)
    feed
  end

  defp view_until(test) do
    receive do
      {:visualize_board, _board, {:cell, "a", %View{} = view}} ->
        if test.(view), do: view, else: view_until(test)
    end
  end

  defp settled, do: view_until(&(&1.state != :loading))

  defp held(server), do: :sys.get_state(Server.info(server).cells["a"].pid).slots["primary"]

  describe "a :budget feed that over-delivers (spec/08 §11.2, D-227)" do
    test "under a ceiling it is the over-budget panel, and its rows never reach the cell" do
      server = start(broken(:budget_overrun), budget: 10)
      view = settled()

      # Twenty ticks, every one shipped though the feed was asked ten.
      assert view.state == {:over_budget, 20, 10}
      assert view.svg == nil and view.frames == 0
      assert view.note =~ ~s(data-vis-state="over_budget")
      assert view.note =~ "Over budget: 20 rows, ceiling 10"
      refute view.note =~ "mark-line"

      assert held(server) == %{
               delivery: nil,
               schema: held(server).schema,
               status: {:over_budget, 20, 10}
             }

      assert Server.info(server).cells["a"].state == {:over_budget, 20, 10}
    end

    test "an honest :budget feed under the same ceiling draws" do
      server = start(broken(), budget: 10)
      view = view_until(&(&1.state == :live))
      assert view.svg =~ ~s(class="mark mark-line") and view.note == nil
      assert length(held(server).delivery.rows) <= 10
    end

    test "with no ceiling there is no over-budget state: the delivery is drawn whole" do
      server = start(broken(:budget_overrun), budget: nil)
      view = view_until(&(&1.state == :live))
      assert view.svg =~ ~s(class="mark mark-line")
      assert length(held(server).delivery.rows) == 20
    end

    test "the ceiling is the only bound: a delivery over its derived budget but within it draws" do
      # A twelve-column plot's derived budget is in the thousands; the feed ships more.
      {feed, _agent} = scripted(supports: [:budget], rows: rows(6_000))
      server = start(feed, budget: 10_000)
      view = view_until(&(&1.state == :live))
      assert view.svg =~ "6000 points" and view.note == nil
      assert length(held(server).delivery.rows) == 6_000
    end

    test "a feed without the claim is reduced to the slot's budget, never over the ceiling" do
      {feed, _agent} = scripted(rows: rows(500))
      server = start(feed, budget: 50)
      assert view_until(&(&1.state == :live)).svg =~ "mark-line"
      assert length(held(server).delivery.rows) <= 50
    end

    test "a feed that is down says down, and its rows are not handed either" do
      {feed, agent} = scripted(supports: [:budget], rows: rows(50))
      server = start(feed, budget: 10)
      assert settled().state == {:over_budget, 50, 10}

      Feeds.set(agent, error: :timeout)
      :ok = Server.tick(server)
      assert view_until(&match?({:down, _}, &1.state)).state == {:down, :timeout}
      assert %{delivery: nil, status: {:down, :timeout}} = held(server)

      # Within the ceiling again, the cell draws.
      Feeds.set(agent, error: nil, rows: rows(8))
      :ok = Server.tick(server)
      assert view_until(&(&1.state == :live)).svg =~ "mark-line"
    end
  end

  describe "the snapshot (spec/15 §12.2–§12.3)" do
    test "an over-budget slot is kept with no delivery, through the map and JSON forms" do
      server = start(broken(:budget_overrun), budget: 10)
      live = settled()

      snapshot = Server.snapshot(server)
      slot = snapshot.cells["a"].slots["primary"]
      assert slot.delivery == nil and slot.status == {:over_budget, 20, 10}

      view = Snapshot.views(snapshot)["a"]
      assert view.state == {:over_budget, 20, 10} and view.note == live.note
      assert Export.svg(snapshot) =~ ~s(data-vis-cell="a" data-vis-state="over_budget")

      assert Snapshot.from_map(Snapshot.to_map(snapshot)) == {:ok, snapshot}
      {:ok, json} = Snapshot.to_json(snapshot)
      assert json =~ ~s("over_budget":[20,10])
      assert {:ok, reopened} = Snapshot.from_json(json)
      assert reopened.cells["a"].slots["primary"].status == {:over_budget, 20, 10}
      assert Snapshot.views(reopened)["a"].note == live.note
    end

    test "an over-budget status that is not two positive integers is refused" do
      server = start(broken(:budget_overrun), budget: 10)
      settled()
      map = Snapshot.to_map(Server.snapshot(server))

      for bad <- [{:over_budget, 0, 10}, {:over_budget, 20, "ten"}] do
        map = put_in(map, [:cells, "a", :slots, "primary", :status], bad)

        assert {:error, [{[:cells, "a", :slots, "primary", :status], {:type, :status}}]} =
                 Snapshot.from_map(map)
      end
    end
  end
end
