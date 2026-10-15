defmodule Visualize.Chart.BuilderBoardTest do
  @moduledoc """
  The board mode (spec/14 §22, D-152): a board is a library entry of its own kind, placed
  and resized on the grid with the server the authority on placement, previewed cell by
  cell through `Visualize.Board.realize/4`, and a cell's component opened in the chart
  builder and returned from.
  """
  use ExUnit.Case, async: true

  alias Visualize.{Board, BuilderFixture}
  alias Visualize.Chart.Builder
  alias Visualize.Chart.Builder.{Boards, Bundle, Store}
  alias Visualize.Chart.{Fragment, Validator}

  doctest Visualize.Chart.Builder.Boards

  # A store over an Agent, as a host's would be: ids issued per kind, entries kept whole.
  # The context is the agent.
  defmodule Memory do
    @moduledoc false
    @behaviour Store

    def start(entries) do
      {:ok, agent} = Agent.start_link(fn -> %{entries: %{}, counters: %{}} end)

      Enum.each(entries, fn {name, fragment} ->
        {:ok, _id} = put(%{id: nil, name: name, kind: nil, fragment: fragment}, agent)
      end)

      agent
    end

    @impl true
    def list(agent),
      do:
        Agent.get(agent, fn s ->
          for {id, e} <- s.entries, do: %{id: id, name: e.name, kind: e.kind}
        end)

    @impl true
    def get(id, agent) do
      Agent.get(agent, fn s ->
        case Map.fetch(s.entries, id) do
          {:ok, entry} -> {:ok, Map.put(entry, :id, id)}
          :error -> :error
        end
      end)
    end

    @impl true
    def put(%{id: nil} = entry, agent) do
      kind = Fragment.kind(entry.fragment)

      id =
        Agent.get_and_update(agent, fn s ->
          n = Map.get(s.counters, kind, 0) + 1
          {{kind, n}, %{s | counters: Map.put(s.counters, kind, n)}}
        end)

      put(%{entry | id: id}, agent)
    end

    def put(%{id: id} = entry, agent) do
      stored = %{name: entry.name, kind: Fragment.kind(entry.fragment), fragment: entry.fragment}
      Agent.update(agent, fn s -> %{s | entries: Map.put(s.entries, id, stored)} end)
      {:ok, id}
    end

    @impl true
    def delete(id, agent),
      do: Agent.update(agent, fn s -> %{s | entries: Map.delete(s.entries, id)} end)

    @impl true
    def import(bundle, agent), do: Store.relocate(bundle, agent, &put/2)
  end

  # The fixture's uptime chart as a composite: one slot, `primary`, and one variable, `unit`.
  defp uptime do
    {uses, _labels} =
      Visualize.Chart.Composite.decompose(Visualize.Chart.stack(BuilderFixture.layers()))

    %{composite: %{uses: uses, vars: %{}}}
  end

  defp board_map do
    %{
      meta: %{name: "Ops"},
      cells: %{
        latency: %{x: 0, y: 0, w: 6, h: 3, ref: {:composite, 1}, title: "Latency"},
        errors: %{x: 6, y: 0, w: 6, h: 3, ref: {:composite, 1}, vars: %{unit: "ms"}}
      },
      window: %{last: 600}
    }
  end

  # A library holding the uptime component and the board over it.
  defp store do
    agent =
      Memory.start([
        {"Charts::uptime", uptime()},
        {"Boards::ops", %{board: board_map() |> Board.from_map!() |> Board.to_map()}}
      ])

    {Memory, agent}
  end

  # The builder with the board entry opened, as a click on it in the library opens it.
  defp opened(store \\ store()) do
    s = BuilderFixture.socket(BuilderFixture.layers(), store: store)
    {:noreply, s} = Builder.handle_event("add_layer", %{"name" => "board:1"}, s)
    s
  end

  defp event(s, name, params) do
    {:noreply, s} = Builder.handle_event(name, params, s)
    s
  end

  defp rect(s, cell), do: Map.take(s.assigns.board.cells[cell], [:x, :y, :w, :h])

  describe "a board is a library entry (§22.1)" do
    test "a board fragment is the kind :board, and per-kind validity is its reader" do
      fragment = %{board: board_map() |> Board.from_map!() |> Board.to_map()}

      assert Fragment.kind(fragment) == :board
      assert :board in Fragment.kinds()
      assert Store.decode_id("board:3") == {:ok, {:board, 3}}
      assert Validator.validate(fragment, :board) == :ok

      overlapping = put_in(fragment, [:board, :cells, :errors, :x], 4)

      assert Validator.validate(overlapping, :board) ==
               {:error, [{[:board, :cells, :latency], {:overlap, :errors}}]}

      assert Validator.validate(%{board: %{version: 9}}, :board) ==
               {:error, [{[:board, :version], {:newer_schema, 9, 3}}]}
    end

    test "a board fragment round-trips through the fragment's JSON, its own stamp inside" do
      board =
        Board.from_map!(%{
          board_map()
          | window: %{from: ~U[2026-10-01 00:00:00Z], to: ~U[2026-10-01 06:00:00Z]}
        })

      fragment = %{board: Board.to_map(board)}

      assert {:ok, json} = Fragment.to_json(fragment)
      assert %{"$version" => 3, "board" => %{"$version" => 3}} = Jason.decode!(json)
      assert Fragment.from_json(json) == {:ok, fragment}

      newer = String.replace(json, ~s("board":{"$version":3), ~s("board":{"$version":7))
      assert Fragment.from_json(newer) == {:error, {:newer_schema, 7, 3}}
    end

    test "the board value round-trips through the store" do
      {Memory, agent} = s_store = store()
      s = opened(s_store)

      s =
        event(s, "board_place", %{
          "cell" => "errors",
          "x" => "6",
          "y" => "3",
          "w" => "6",
          "h" => "2"
        })

      s = event(s, "put_design", %{"name" => "Boards::ops"})
      assert s.assigns.notice == nil

      {:ok, entry} = Memory.get({:board, 1}, agent)
      assert entry.kind == :board
      assert {:ok, stored} = Board.from_map(entry.fragment.board)
      assert stored == s.assigns.board
      assert rect(s, :errors) == %{x: 6, y: 3, w: 6, h: 2}

      # Opened again, it is the board that was saved.
      again = opened(s_store)
      assert again.assigns.board == stored
    end

    test "a bundle of a board entry carries its components, and an import re-keys the cells" do
      {Memory, source} = store()
      bundle = Bundle.export({Memory, source}, {:board, 1}, "here")
      assert bundle.entries |> Enum.map(& &1.id) |> Enum.sort() == [{:board, 1}, {:composite, 1}]

      target = Memory.start([{"Other::first", uptime()}, {"Other::second", uptime()}])
      assert {:ok, %{ids: ids}} = Memory.import(bundle, target)
      {:ok, imported} = Memory.get(Map.fetch!(ids, {:board, 1}), target)
      new = Map.fetch!(ids, {:composite, 1})
      assert new == {:composite, 3}
      assert imported.fragment.board.cells.latency.ref == new
    end

    test "New offers a board, which opens empty in the mode" do
      s = BuilderFixture.socket(BuilderFixture.layers(), store: store())
      assert :board in Visualize.Chart.Builder.Stack.kinds()
      s = event(s, "new_fragment", %{"kind" => "board"})

      assert s.assigns.open.kind == :board
      assert s.assigns.board == %Board{}
      html = BuilderFixture.render(s)
      assert html =~ "this board has no cells yet"
      assert html =~ ~s(class="vis-builder-board-panel")
    end

    test "a board entry is never composed into a chart" do
      s = BuilderFixture.socket(BuilderFixture.layers(), store: store())
      before = s.assigns.uses
      s = event(s, "insert", %{"name" => "board:1"})

      assert s.assigns.uses == before
      assert s.assigns.notice =~ "a board is opened, never composed"
    end

    test "an entry that does not read is not opened, and the notice names its faults" do
      agent = Memory.start([{"Charts::uptime", uptime()}])
      broken = %{board: %{cells: %{a: %{x: 10, y: 0, w: 4, h: 1, ref: {:composite, 1}}}}}

      {:ok, {:board, 1}} =
        Memory.put(
          %{id: {:board, 1}, name: "Boards::broken", kind: :board, fragment: broken},
          agent
        )

      s = BuilderFixture.socket(BuilderFixture.layers(), store: {Memory, agent})
      charts = length(s.assigns.charts)
      s = event(s, "add_layer", %{"name" => "board:1"})

      assert length(s.assigns.charts) == charts
      assert s.assigns.notice =~ "does not open"
      assert s.assigns.notice =~ "cells.a: runs past"
    end
  end

  describe "placing cells (§22.3)" do
    test "a drag's rectangle is placed by the server" do
      s =
        event(opened(), "board_place", %{
          "cell" => "latency",
          "x" => "0",
          "y" => "3",
          "w" => "4",
          "h" => "2"
        })

      assert rect(s, :latency) == %{x: 0, y: 3, w: 4, h: 2}
      assert s.assigns.board_cell == :latency
      assert s.assigns.notice == nil
    end

    test "an overlap is refused and the cell stays where it was" do
      s = opened()

      s =
        event(s, "board_place", %{
          "cell" => "latency",
          "x" => "3",
          "y" => "0",
          "w" => "6",
          "h" => "3"
        })

      assert rect(s, :latency) == %{x: 0, y: 0, w: 6, h: 3}
      assert s.assigns.notice =~ "overlaps cell :errors"
    end

    test "a cell off the grid, or a rectangle that is not integers, is refused" do
      s = opened()

      s =
        event(s, "board_place", %{
          "cell" => "errors",
          "x" => "8",
          "y" => "0",
          "w" => "6",
          "h" => "3"
        })

      assert rect(s, :errors) == %{x: 6, y: 0, w: 6, h: 3}
      assert s.assigns.notice =~ "cells.errors"

      s =
        event(s, "board_place", %{
          "cell" => "errors",
          "x" => "-1",
          "y" => "0",
          "w" => "2",
          "h" => "3"
        })

      assert rect(s, :errors) == %{x: 6, y: 0, w: 6, h: 3}

      s =
        event(s, "board_place", %{
          "cell" => "errors",
          "x" => "a",
          "y" => "0",
          "w" => "2",
          "h" => "3"
        })

      assert rect(s, :errors) == %{x: 6, y: 0, w: 6, h: 3}
    end

    test "a cell the board does not have is ignored, and no atom is made of it" do
      s = opened()
      before = s.assigns.board

      s =
        event(s, "board_place", %{
          "cell" => "no_such_cell_#{System.unique_integer([:positive])}",
          "x" => "0",
          "y" => "9",
          "w" => "1",
          "h" => "1"
        })

      assert s.assigns.board == before
    end

    test "a new cell takes the first free place, named cell_<n>" do
      s = event(opened(), "board_add", %{"ref" => "composite:1"})
      assert s.assigns.board_cell == :cell_1
      assert rect(s, :cell_1) == %{x: 0, y: 3, w: 4, h: 2}

      s = event(s, "board_add", %{"ref" => "composite:1"})
      assert rect(s, :cell_2) == %{x: 4, y: 3, w: 4, h: 2}

      s = event(s, "board_remove", %{"cell" => "cell_1"})
      refute Map.has_key?(s.assigns.board.cells, :cell_1)
      s = event(s, "board_add", %{"ref" => "composite:1"})
      assert rect(s, :cell_1) == %{x: 0, y: 3, w: 4, h: 2}
    end

    test "the grid draws every cell at its place, with its handles" do
      html = BuilderFixture.render(opened())

      assert html =~ ~s(data-builder-scope="board")
      assert html =~ ~s(data-board-cell="latency")
      assert html =~ "grid-column: 1 / span 6; grid-row: 1 / span 3"
      assert html =~ "grid-column: 7 / span 6; grid-row: 1 / span 3"
      assert length(Regex.scan(~r/data-board-handle="se"/, html)) == 2
      refute html =~ ~s(id="b-graph")
    end

    test "the narrow view shows the reflow below the breakpoint, without handles" do
      s = event(opened(), "board_view", %{"view" => "narrow"})
      html = BuilderFixture.render(s)

      assert html =~ "below 768 px the cells stack in reading order"
      # errors (6, 0) and latency (0, 0) read latency first: by y, then x.
      assert html =~ "grid-column: 1 / span 12; grid-row: 1 / span 3"
      assert html =~ "grid-column: 1 / span 12; grid-row: 4 / span 3"
      refute html =~ "data-board-handle"
      refute html =~ ~s(data-builder-scope="board")
    end
  end

  describe "the cell and the board (§22.4)" do
    test "a cell's title, component and sync are written from its form" do
      s = opened()
      s = event(s, "board_select", %{"cell" => "errors"})
      s = event(s, "board_cell", %{"_target" => ["title"], "title" => "Errors"})
      s = event(s, "board_cell", %{"_target" => ["sync"], "sync" => "false"})

      assert s.assigns.board.cells.errors.title == "Errors"
      assert s.assigns.board.cells.errors.sync == false

      s = event(s, "board_cell", %{"_target" => ["ref"], "ref" => "style:3"})
      assert s.assigns.board.cells.errors.ref == {:composite, 1}
      assert s.assigns.notice =~ "composite"
    end

    test "a cell's variables are the ones its component declares; empty removes one" do
      s = event(opened(), "board_select", %{"cell" => "latency"})
      s = event(s, "board_cell_var", %{"_target" => ["var.unit"], "var.unit" => "%"})
      assert s.assigns.board.cells.latency.vars == %{unit: "%"}

      s = event(s, "board_cell_var", %{"_target" => ["var.unit"], "var.unit" => ""})
      refute Map.has_key?(s.assigns.board.cells.latency, :vars)

      before = s.assigns.board
      s = event(s, "board_cell_var", %{"_target" => ["var.nothing"], "var.nothing" => "1"})
      assert s.assigns.board == before
    end

    test "the board's window, zone, group, staleness, layout and variables are written" do
      s = opened()
      s = event(s, "board_edit", %{"_target" => ["name"], "name" => "Ops floor"})
      s = event(s, "board_edit", %{"_target" => ["last"], "last" => "900"})
      s = event(s, "board_edit", %{"_target" => ["sync"], "sync" => "ops"})
      s = event(s, "board_edit", %{"_target" => ["stale_after"], "stale_after" => "30"})
      s = event(s, "board_edit", %{"_target" => ["gap"], "gap" => "4"})
      s = event(s, "board_var", %{"_target" => ["var.unit"], "var.unit" => "12.5"})
      board = s.assigns.board

      assert board.meta.name == "Ops floor"
      assert board.window == %{last: 900}
      assert board.sync == "ops"
      assert board.stale_after == 30
      assert board.layout == %{gap: 4}
      assert board.vars == %{unit: 12.5}

      s = event(s, "board_edit", %{"_target" => ["window"], "window" => "fixed"})
      %{from: from, to: to} = s.assigns.board.window
      assert DateTime.diff(to, from) == 3600
      assert to.minute == 0 and to.second == 0

      s = event(s, "board_edit", %{"_target" => ["from"], "from" => "2026-10-01T00:00"})
      assert s.assigns.board.window.from == ~U[2026-10-01 00:00:00Z]

      s = event(s, "board_edit", %{"_target" => ["window"], "window" => "none"})
      assert s.assigns.board.window == nil
    end

    test "a write the board refuses is not kept, and says why" do
      s = opened()
      s = event(s, "board_edit", %{"_target" => ["zone"], "zone" => "Mars/Olympus"})
      assert s.assigns.board.zone == "Etc/UTC"
      assert s.assigns.notice =~ "zone"

      s = event(s, "board_edit", %{"_target" => ["stale_after"], "stale_after" => "-3"})
      assert s.assigns.board.stale_after == nil
    end

    test "the validity section lists the board's faults given the store" do
      s = event(opened(), "board_add", %{"ref" => "composite:9"})
      html = BuilderFixture.render(s)

      assert html =~ "cells.cell_1.ref"
      assert html =~ "vis-builder-board-cell-faulty"
    end
  end

  describe "the preview (§22.6)" do
    test "each cell is realized alone over the pool, its slot bound by its own name" do
      html = BuilderFixture.render(opened())

      [_, latency] =
        Regex.run(
          ~r/data-board-cell="latency".*?<div class="vis-builder-board-cell-body">(.*?)<\/div>/s,
          html
        )

      assert latency =~ "<svg"
      assert latency =~ "Uptime — %"

      [_, errors] =
        Regex.run(
          ~r/data-board-cell="errors".*?<div class="vis-builder-board-cell-body">(.*?)<\/div>/s,
          html
        )

      assert errors =~ "Uptime — ms"
    end

    test "a cell that cannot be applied shows its faults and the others still draw" do
      s = event(opened(), "board_add", %{"ref" => "composite:9"})

      fetch = Visualize.Chart.Builder.Stack.fetch(s.assigns.store)
      pools = Map.new(s.assigns.board.cells, fn {name, _} -> {name, BuilderFixture.sources()} end)
      previews = Boards.preview(s.assigns.board, fetch, pools: pools)

      assert {:error, [line]} = previews.cell_1
      assert line =~ "composite:9" or line =~ "{:composite, 9}"
      assert {:ok, "<svg" <> _} = previews.latency
    end
  end

  describe "Edit component (§22.7)" do
    test "opens the cell's composite and Back to board returns, closing the unchanged chart" do
      s = opened()
      board_chart = s.assigns.chart
      charts = length(s.assigns.charts)

      s = event(s, "board_edit_component", %{"cell" => "latency"})
      assert s.assigns.open.id == {:composite, 1}
      assert s.assigns.open.kind == :composite
      assert s.assigns.return_to.chart == board_chart
      assert BuilderFixture.render(s) =~ "Back to board"

      s = event(s, "board_return", %{})
      assert s.assigns.chart == board_chart
      assert s.assigns.open.kind == :board
      assert length(s.assigns.charts) == charts
      assert s.assigns.board_cell == :latency
    end

    test "a component saved before returning shows in the board, and its chart closes" do
      s = event(opened(), "board_edit_component", %{"cell" => "latency"})
      s = event(s, "new_layer", %{})
      s = event(s, "put_design", %{"name" => "Charts::uptime"})
      assert s.assigns.notice == nil

      s = event(s, "board_return", %{})
      assert s.assigns.open.kind == :board
      refute Enum.any?(s.assigns.charts, &(&1.open && &1.open.id == {:composite, 1}))
    end

    test "unsaved changes keep the component's chart open, with a notice" do
      s = event(opened(), "board_edit_component", %{"cell" => "latency"})
      component_chart = s.assigns.chart
      s = event(s, "new_layer", %{})

      s = event(s, "board_return", %{})
      assert s.assigns.open.kind == :board
      assert Enum.any?(s.assigns.charts, &(&1.id == component_chart))
      assert s.assigns.notice =~ "changes not saved"
    end

    test "a component the store no longer holds is not opened" do
      s = event(opened(), "board_add", %{"ref" => "composite:9"})
      charts = length(s.assigns.charts)
      s = event(s, "board_edit_component", %{"cell" => "cell_1"})

      assert length(s.assigns.charts) == charts
      assert s.assigns.notice =~ "no longer holds composite:9"
    end
  end

  describe "binding the slots (§22.8)" do
    alias Visualize.Board.Binding
    alias Visualize.Data.Schema

    # The uptime chart whose one slot states a contract: `v` must say its unit, and `t` is a
    # number.
    defp strict do
      [{:house, house}, {:shared, shared}, panel] = BuilderFixture.layers()

      shared =
        put_in(shared, [:sources, :primary], %{
          fields: [:t, :v],
          types: %{t: :number},
          requires: %{v: [:unit]}
        })

      {uses, _labels} =
        Visualize.Chart.Composite.decompose(
          Visualize.Chart.stack([{:house, house}, {:shared, shared}, panel])
        )

      %{composite: %{uses: uses, vars: %{}}}
    end

    defp catalog do
      %{
        :api => Schema.new!(%{t: %{type: :number}, v: %{type: :number, unit: "ms"}}),
        :bare => Schema.new!(%{t: %{type: :time}, v: %{type: :number}}),
        "vm.memory" => Schema.new!(%{t: %{type: :number}, v: %{type: :number, unit: "MB"}})
      }
    end

    defp strict_board(opts) do
      agent =
        Memory.start([
          {"Charts::strict", strict()},
          {"Boards::ops", %{board: board_map() |> Board.from_map!() |> Board.to_map()}}
        ])

      s = BuilderFixture.socket(BuilderFixture.layers(), [store: {Memory, agent}] ++ opts)
      s = event(s, "add_layer", %{"name" => "board:1"})
      event(s, "board_select", %{"cell" => "latency"})
    end

    test "with no catalog the sample pool is bound by name, and every change is sent" do
      s = event(opened(), "board_select", %{"cell" => "latency"})

      assert s.assigns.binding.slots == %{
               {:latency, :primary} => :primary,
               {:errors, :primary} => :primary
             }

      html = BuilderFixture.render(s)
      assert html =~ "sources — the sample pool"
      assert html =~ ~s(<select name="slot.primary">)

      s = event(s, "board_bind", %{"_target" => ["slot.primary"], "slot.primary" => ""})
      assert s.assigns.binding.slots == %{{:errors, :primary} => :primary}
      binding = s.assigns.binding
      assert_received {:visualize_board_bound, "b", {:board, 1}, ^binding}

      html = BuilderFixture.render(s)
      assert html =~ "cells.latency.sources.primary"
      assert html =~ "vis-builder-board-slot-faulty"
    end

    test "with a catalog its feeds are offered, and unbound slots and unmet contracts are shown" do
      s = strict_board(catalog: catalog())
      # No feed is called `primary`, so nothing binds by name.
      assert s.assigns.binding == Binding.new()

      html = BuilderFixture.render(s)
      assert html =~ "sources — the host&#39;s feeds"
      assert html =~ ~s(<option value="vm.memory">vm.memory</option>)
      assert html =~ "cells.latency.sources.primary: "

      s = event(s, "board_bind", %{"_target" => ["slot.primary"], "slot.primary" => "bare"})
      assert Binding.fetch(s.assigns.binding, :latency, :primary) == {:ok, :bare}
      mode = Visualize.Chart.Builder.Editing.editing(s.assigns).board_mode
      faults = Enum.join(mode.selected.slots |> hd() |> Map.fetch!(:faults), "\n")
      assert faults =~ "unit"
      assert faults =~ "cells.latency.sources.primary.types.t"

      s = event(s, "board_bind", %{"_target" => ["slot.primary"], "slot.primary" => "api"})
      mode = Visualize.Chart.Builder.Editing.editing(s.assigns).board_mode
      assert hd(mode.selected.slots).faults == []

      # A catalog feed previews over rows made from its schema.
      html = BuilderFixture.render(s)

      [_, latency] =
        Regex.run(
          ~r/data-board-cell="latency".*?<div class="vis-builder-board-cell-body">(.*?)<\/div>/s,
          html
        )

      assert latency =~ "<svg"
    end

    test "a feed the page names that the catalog lacks binds nothing" do
      s = strict_board(catalog: catalog())
      s = event(s, "board_bind", %{"_target" => ["slot.primary"], "slot.primary" => "nope"})
      assert s.assigns.binding == Binding.new()
    end

    test "the host's binding for a board is taken when it opens, and the board never holds it" do
      held = Binding.new(%{{:latency, :primary} => :api, {:errors, :primary} => "vm.memory"})
      s = strict_board(catalog: catalog(), board_bindings: %{{:board, 1} => held})
      assert s.assigns.binding == held

      {Memory, agent} = s.assigns.store
      s = event(s, "put_design", %{"name" => "Boards::ops"})
      {:ok, entry} = Memory.get({:board, 1}, agent)
      refute inspect(entry.fragment) =~ "vm.memory"
      assert Map.keys(entry.fragment) == [:board]
      assert s.assigns.binding == held
    end

    test "removing a cell removes its bindings, and adding one binds its slots by name" do
      s = opened()
      s = event(s, "board_remove", %{"cell" => "latency"})
      assert s.assigns.binding.slots == %{{:errors, :primary} => :primary}
      assert_received {:visualize_board_bound, "b", {:board, 1}, %Binding{slots: slots}}
      assert map_size(slots) == 1

      s = event(s, "board_add", %{"ref" => "composite:1"})
      assert Binding.fetch(s.assigns.binding, :cell_1, :primary) == {:ok, :primary}
    end
  end

  describe "a binding of the wrong type is a fault panel, not a crash (§18.4, §22.6, D-153)" do
    alias Visualize.Board.Binding
    alias Visualize.Chart.Builder.Preview
    alias Visualize.Data.Schema

    import Phoenix.LiveViewTest, only: [render_component: 2]

    # Instants, which the uptime chart's linear x cannot take.
    @stamps [%{t: ~U[2026-10-11 12:00:00Z], v: 1}, %{t: ~U[2026-10-11 12:01:00Z], v: 2}]

    defp typed_catalog do
      %{
        clock: Schema.new!(%{t: %{type: :time}, v: %{type: :number}}),
        names: Schema.new!(%{t: %{type: :category}, v: %{type: :number}}),
        api: Schema.new!(%{t: %{type: :number, window: true}, v: %{type: :number}})
      }
    end

    defp body(html, cell) do
      [_, body] =
        Regex.run(
          ~r/data-board-cell="#{cell}".*?<div class="vis-builder-board-cell-body">(.*?)<\/article>/s,
          html
        )

      body
    end

    test "the single-chart preview checks the rows it draws before applying them" do
      s = BuilderFixture.socket(BuilderFixture.layers(), sources: %{primary: @stamps})
      html = BuilderFixture.render(s)

      assert html =~ ~s(<div class="vis-builder-fault">)
      assert html =~ ~s(data-vis-state="invalid")
      assert html =~ "Wrong binding: marks[0].channels.x: field :t of slot :primary is a time"
      refute html =~ ~s(class="vis-builder-chart")
    end

    test "the single-chart preview checks a catalog feed's schema too" do
      rows = [%{t: 1, v: 1}, %{t: 2, v: 2}]
      names = Schema.new!(%{t: %{type: :category}, v: %{type: :number}})
      design = Visualize.Chart.stack(BuilderFixture.layers())

      html =
        render_component(&Preview.panel/1, %{
          design: design,
          sources: %{primary: rows},
          catalog: %{primary: names}
        })

      assert html =~ "vis-builder-fault"
      assert html =~ "field :t of slot :primary is a category"

      html = render_component(&Preview.panel/1, %{design: design, sources: %{primary: rows}})
      assert html =~ ~s(class="vis-builder-chart")
      refute html =~ "vis-builder-fault"
    end

    test "a catalog feed's :time on a linear axis is reported by its schema alone (D-154)" do
      # The rows are numbers, so only the schema can say the field is instants.
      rows = [%{t: 1, v: 1}, %{t: 2, v: 2}]
      design = Visualize.Chart.stack(BuilderFixture.layers())

      html =
        render_component(&Preview.panel/1, %{
          design: design,
          sources: %{primary: rows},
          catalog: %{primary: typed_catalog().clock}
        })

      assert html =~ "vis-builder-fault"

      assert html =~
               "field :t of slot :primary is a time, and the scale it is read through needs a number"

      html =
        render_component(&Preview.panel/1, %{
          design: design,
          sources: %{primary: rows},
          catalog: %{primary: typed_catalog().api}
        })

      assert html =~ ~s(class="vis-builder-chart")
      refute html =~ "vis-builder-fault"
    end

    test "a board cell bound to a feed of the wrong type is drawn as the fault panel" do
      held = Binding.new(%{{:latency, :primary} => :names, {:errors, :primary} => :api})
      s = opened() |> Phoenix.Component.assign(catalog: typed_catalog(), board_bindings: %{})
      s = Phoenix.Component.assign(s, :binding, held)
      s = event(s, "board_select", %{"cell" => "latency"})

      html = BuilderFixture.render(s)
      latency = body(html, "latency")
      assert latency =~ ~s(<div class="vis-builder-fault">)
      assert latency =~ "Wrong binding"

      assert latency =~
               "cells.latency.marks[0].channels.x: field :t of slot :primary is a category"

      assert body(html, "errors") =~ "<svg"
      refute body(html, "errors") =~ "vis-builder-fault"

      # The fault stands under the slot it names, and the cell is marked faulty.
      mode = Visualize.Chart.Builder.Editing.editing(s.assigns).board_mode
      assert Enum.join(hd(mode.selected.slots).faults, "\n") =~ "is a category"
      assert html =~ "vis-builder-board-cell-faulty"
    end

    test "a catalog time feed previews over instants, which a linear axis cannot take" do
      # The schema's `:time` is instants (D-154), which the linear axis cannot take — the
      # schema check reports it, and so would the rows the preview draws: before D-153 this
      # binding took the builder down. A feed over ticks (`api`) is drawn.
      s = opened() |> Phoenix.Component.assign(catalog: typed_catalog())
      s = Phoenix.Component.assign(s, :binding, Binding.new(%{{:latency, :primary} => :clock}))
      s = event(s, "board_select", %{"cell" => "latency"})
      s = event(s, "board_bind", %{"_target" => ["slot.primary"], "slot.primary" => "clock"})

      latency = s |> BuilderFixture.render() |> body("latency")
      assert latency =~ "vis-builder-fault"
      assert latency =~ "is a time, and the scale it is read through needs a number"

      s = event(s, "board_bind", %{"_target" => ["slot.primary"], "slot.primary" => "api"})
      latency = s |> BuilderFixture.render() |> body("latency")
      refute latency =~ "vis-builder-fault"
      assert latency =~ "<svg"
    end

    test "with no catalog a sample of the wrong type is caught by what its rows show" do
      s = BuilderFixture.socket(BuilderFixture.layers(), store: store())
      s = Phoenix.Component.assign(s, :sources, Map.put(s.assigns.sources, :stamps, @stamps))
      s = event(s, "add_layer", %{"name" => "board:1"})
      s = event(s, "board_select", %{"cell" => "latency"})
      s = event(s, "board_bind", %{"_target" => ["slot.primary"], "slot.primary" => "stamps"})

      assert Binding.fetch(s.assigns.binding, :latency, :primary) == {:ok, :stamps}
      latency = s |> BuilderFixture.render() |> body("latency")
      assert latency =~ "vis-builder-fault"
      assert latency =~ "field :t of slot :primary is a time"
    end
  end
end
