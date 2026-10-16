defmodule Visualize.Chart.Builder.CostTest do
  @moduledoc """
  The builder's editing pass within a reduction budget (spec/12 §6, spec/14 §19.10, #704,
  D-184). `Visualize.Chart.Builder.Editing.editing/1` is what every builder event and every
  render derives first, so a table rebuilt per name or per field inside it is paid on every
  click; counted here, it fails at a test that names it rather than as a timeout of a test
  that happens to run the pass many times.

  Each count is the second of two (#703): a first run may fill what the second only reads.

  In board mode (#714, D-189) the pass is counted over a board whose cells bind a catalog,
  beside a host pool of many sources: the pool and the catalog are typed when the host gives
  them, so a pass that types them again fails here by name. Its cell previews and the
  board's validation are kept by their inputs (#723, D-191), so a pass that draws them
  again fails here too, and an event that touches one cell draws that cell's preview alone.
  """
  use ExUnit.Case, async: true

  alias Visualize.{Board, BuilderFixture}
  alias Visualize.Chart.Builder
  alias Visualize.Chart.Builder.{Editing, Picker}
  alias Visualize.Data.Schema
  alias Visualize.Theme

  # A read-only library over a map, its entries by id: the component and the board.
  defmodule Shelf do
    @moduledoc false
    @behaviour Visualize.Chart.Builder.Store

    @impl true
    def list(entries),
      do: for({id, entry} <- entries, do: %{id: id, name: entry.name, kind: entry.kind})

    @impl true
    def get(id, entries) do
      case Map.fetch(entries, id) do
        {:ok, entry} -> {:ok, Map.put(entry, :id, id)}
        :error -> :error
      end
    end

    @impl true
    def put(_entry, _entries), do: {:error, :read_only}

    @impl true
    def delete(_id, _entries), do: {:error, :read_only}

    @impl true
    def import(_bundle, _entries), do: {:error, :read_only}
  end

  # Measured with #704's fix (reductions, default theme): the pass below about 143,000, the
  # picker's groups about 21,000. Before it the pass was about 708,000 and the groups about
  # 332,000 — the theme's ~190 color names rebuilt and sorted per name resolved, and a node
  # kind's key specs rebuilt on every schema lookup. Each budget is about twice the cost.
  #
  # Board mode (#714): measured on the board below, the pass was about 1,520,000 reductions
  # while it typed the pool's 40 sources twice and the catalog's 6 feeds once a pass, and is
  # about 405,000 reading what `update/2` typed. Its budget, about twice that, is under the
  # cost of typing them again.
  #
  # Board mode (#723): with the previews and the validation kept by their inputs, the pass
  # is about 36,000 (405,000 before; on the examples' board about 73,000, from 2,120,000),
  # and an event that retitles one cell, with the pass after it, about 175,000 with the
  # cells bound — the board's validation and the one cell's slots and preview, where
  # drawing every cell again is about 285,000. Each budget is about twice the cost, but the
  # one-cell edit's, which stays under the cost of drawing every cell.
  @budget %{editing: 300_000, groups: 50_000, board: 80_000, one_cell: 260_000}

  defp counted(fun) do
    {_first, _} = Visualize.Work.reductions(fun)
    Visualize.Work.reductions(fun)
  end

  test "one editing pass, a color field selected, is within its budget" do
    s = BuilderFixture.socket(BuilderFixture.layers())
    {:noreply, s} = Builder.handle_event("select_node", %{"node" => "styles.series"}, s)
    {:noreply, s} = Builder.handle_event("select_field", %{"field" => "stroke.color"}, s)

    {work, editing} = counted(fn -> Editing.editing(s.assigns) end)

    # The pass is the one the chooser draws from: the field selected, the table grouped.
    assert editing.color.key == "stroke.color"
    assert [{"series", _} | _] = editing.color.groups
    assert work <= @budget.editing, "editing/1 spent #{work} reductions, over #{@budget.editing}"
  end

  # The fixture's uptime chart as a component, and a board of four cells over it.
  defp shelf do
    {uses, _labels} =
      Visualize.Chart.Composite.decompose(Visualize.Chart.stack(BuilderFixture.layers()))

    cells =
      for {name, i} <- Enum.with_index([:a, :b, :c, :d]), into: %{} do
        {name, %{x: rem(i, 2) * 6, y: div(i, 2) * 3, w: 6, h: 3, ref: {:composite, 1}}}
      end

    board = %{meta: %{name: "Ops"}, cells: cells} |> Board.from_map!() |> Board.to_map()

    %{
      {:composite, 1} => %{
        name: "Charts::uptime",
        kind: :composite,
        fragment: %{composite: %{uses: uses, vars: %{}}}
      },
      {:board, 1} => %{name: "Boards::ops", kind: :board, fragment: %{board: board}}
    }
  end

  # A host pool of many sources, each of 200 rows.
  defp pool do
    t0 = ~U[2026-10-16 00:00:00Z]

    for n <- 1..40, into: %{} do
      rows =
        for i <- 1..200,
            do: %{t: DateTime.add(t0, i, :second), v: i * 1.5, k: :"k#{rem(i, 4)}", s: "#{n}"}

      {:"source_#{n}", rows}
    end
  end

  defp catalog do
    for n <- 1..6, into: %{} do
      {:"feed_#{n}", Schema.new!(%{t: %{type: :time}, v: %{type: :number, unit: "ms"}})}
    end
  end

  defp board_mode do
    s = BuilderFixture.socket(BuilderFixture.layers(), store: {Shelf, shelf()}, sources: pool())
    {:ok, s} = Builder.update(%{catalog: catalog()}, s)
    {:noreply, s} = Builder.handle_event("add_layer", %{"name" => "board:1"}, s)
    {:noreply, s} = Builder.handle_event("board_select", %{"cell" => "a"}, s)
    s
  end

  test "one editing pass in board mode reads the pool's and the catalog's types, within its budget" do
    s = board_mode()
    assert s.assigns.open.kind == :board

    {work, editing} = counted(fn -> Editing.editing(s.assigns) end)
    assert %{cells: [_, _, _, _]} = editing.board_mode

    assert work <= @budget.board,
           "editing/1 (board) spent #{work} reductions, over #{@budget.board}"

    # The same pass given data other than what was typed types it itself, and costs more.
    {untyped, _} = counted(fn -> Editing.editing(Map.delete(s.assigns, :typed)) end)
    assert untyped > work

    # And one with nothing kept draws every preview and validates the board (#723).
    {unkept, _} = counted(fn -> Editing.editing(Map.delete(s.assigns, :board_kept)) end)
    assert unkept > 4 * work
  end

  test "an event that touches one cell draws that cell alone, within its budget" do
    s = board_mode()

    binding =
      Visualize.Board.Binding.new(
        for {cell, n} <- [a: 1, b: 2, c: 3, d: 4], into: %{}, do: {{cell, :primary}, :"feed_#{n}"}
      )

    s =
      s |> Phoenix.Component.assign(:binding, binding) |> Visualize.Chart.Builder.BoardMode.keep()

    retitle = %{"_target" => ["title"], "title" => "Renamed"}

    {work, editing} =
      counted(fn ->
        {:noreply, s} = Builder.handle_event("board_cell", retitle, s)
        Editing.editing(s.assigns)
      end)

    assert %{cells: [%{title: "Renamed"} | _]} = editing.board_mode

    {:noreply, edited} = Builder.handle_event("board_cell", retitle, s)

    {_kept, computed} =
      Visualize.Chart.Builder.BoardMode.kept(%{edited.assigns | board_kept: s.assigns.board_kept})

    assert computed.previews == [:a]

    assert work <= @budget.one_cell,
           "a one-cell edit spent #{work} reductions, over #{@budget.one_cell}"
  end

  test "the picker's color table is linear in the theme's names" do
    for theme <- [Theme.default(), Theme.dark()] do
      {work, groups} = counted(fn -> Picker.groups(theme) end)
      assert length(groups) == 5

      assert work <= @budget.groups,
             "Picker.groups/1 (#{theme.name}) spent #{work} reductions, over #{@budget.groups}"
    end
  end
end
