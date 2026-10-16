defmodule Visualize.Chart.Builder.BoardKeptTest do
  @moduledoc """
  #723, D-191: the board mode keeps each cell's preview and slots by the cell's inputs and
  the board's validation by the board and its components (spec/14 §22.5, §22.6). Each input
  is changed in turn: what is a function of it is made again and nothing else is, and the
  pass draws what a pass with nothing kept draws.
  """
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [assign: 3]

  alias Visualize.{Board, BuilderFixture}
  alias Visualize.Board.Binding
  alias Visualize.Chart.Builder
  alias Visualize.Chart.Builder.{BoardMode, Editing, Typed}
  alias Visualize.Data.Schema

  # A read-only library over a map, its entries by id.
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

  @t0 ~U[2026-10-16 00:00:00Z]

  # The fixture's chart as two components, `a` and `b` on the first and `c` and `d` on the
  # second, and a board of four cells over them.
  defp entries(vars \\ %{}) do
    {uses, _labels} =
      Visualize.Chart.Composite.decompose(Visualize.Chart.stack(BuilderFixture.layers()))

    refs = %{a: {:composite, 1}, b: {:composite, 1}, c: {:composite, 2}, d: {:composite, 2}}

    cells =
      for {name, i} <- Enum.with_index([:a, :b, :c, :d]), into: %{} do
        {name, %{x: rem(i, 2) * 6, y: div(i, 2) * 3, w: 6, h: 3, ref: refs[name]}}
      end

    board = %{meta: %{name: "Ops"}, cells: cells} |> Board.from_map!() |> Board.to_map()
    component = %{composite: %{uses: uses, vars: vars}}

    %{
      {:composite, 1} => %{name: "Charts::one", kind: :composite, fragment: component},
      {:composite, 2} => %{name: "Charts::two", kind: :composite, fragment: component},
      {:board, 1} => %{name: "Boards::ops", kind: :board, fragment: %{board: board}}
    }
  end

  defp rows(scale) do
    for i <- 1..30, do: %{t: DateTime.add(@t0, i, :second), v: i * scale}
  end

  # The host's rows for the feeds the cells bind, so the samples are the host's terms.
  defp sources, do: %{feed_1: rows(1), feed_2: rows(2), feed_3: rows(3)}

  defp catalog do
    for n <- 1..3, into: %{} do
      {:"feed_#{n}", Schema.new!(%{t: %{type: :time}, v: %{type: :number}})}
    end
  end

  # The board open with each cell bound — `a` to feed 1, `b` to feed 2, `c` and `d` to
  # feed 3 — and what a pass over it draws kept.
  defp opened do
    s =
      BuilderFixture.socket(BuilderFixture.layers(),
        store: {Shelf, entries()},
        sources: sources()
      )

    {:ok, s} = Builder.update(%{catalog: catalog()}, s)
    {:noreply, s} = Builder.handle_event("add_layer", %{"name" => "board:1"}, s)

    binding =
      Binding.new(%{
        {:a, :primary} => :feed_1,
        {:b, :primary} => :feed_2,
        {:c, :primary} => :feed_3,
        {:d, :primary} => :feed_3
      })

    s |> assign(:binding, binding) |> BoardMode.keep()
  end

  # What a pass over the changed assigns makes again, beside the kept map of the pass
  # before; and the pass's drawing, which must be the one a pass with nothing kept draws.
  defp remade(s, change) do
    assigns = change.(s).assigns
    {_kept, computed} = BoardMode.kept(assigns)

    assert Editing.editing(assigns).board_mode ==
             Editing.editing(Map.delete(assigns, :board_kept)).board_mode

    computed
  end

  @all [:a, :b, :c, :d]

  test "a pass over what was kept makes nothing again" do
    s = opened()
    assert remade(s, & &1) == %{facts: false, required: [], previews: []}

    # A selection is no input of either.
    assert remade(s, &assign(&1, :board_cell, :b)) == %{facts: false, required: [], previews: []}
  end

  test "a cell's own fields remake its slots, its preview and the board's validation" do
    s = opened()
    board = s.assigns.board
    retitled = put_in(board.cells.a[:title], "Renamed")

    assert remade(s, &assign(&1, :board, retitled)) ==
             %{facts: true, required: [:a], previews: [:a]}
  end

  test "the board's shared state remakes every preview and the validation, no slots" do
    s = opened()
    board = %{s.assigns.board | vars: %{threshold: 3}}
    assert remade(s, &assign(&1, :board, board)) == %{facts: true, required: [], previews: @all}
  end

  test "what the store says of a component remakes its cells, and only theirs" do
    s = opened()
    changed = Map.put(entries(), {:composite, 2}, entries(%{label: "x"})[{:composite, 2}])

    assert remade(s, &assign(&1, :store, {Shelf, changed})) ==
             %{facts: true, required: [:c, :d], previews: [:c, :d]}

    # An entry no cell reaches is no input.
    more = Map.put(entries(), {:composite, 9}, entries()[{:composite, 1}])

    assert remade(s, &assign(&1, :store, {Shelf, more})) ==
             %{facts: false, required: [], previews: []}
  end

  test "a cell's binding remakes its preview alone" do
    s = opened()
    binding = Binding.put(s.assigns.binding, :a, :primary, :feed_2)

    assert remade(s, &assign(&1, :binding, binding)) == %{
             facts: false,
             required: [],
             previews: [:a]
           }
  end

  test "a feed's rows remake the previews of the cells bound to it" do
    s = opened()
    sources = %{sources() | feed_3: rows(7)}

    changed = fn s ->
      s
      |> assign(:sources, sources)
      |> assign(:typed, Typed.typed(sources, s.assigns.catalog))
    end

    assert remade(s, changed) == %{facts: false, required: [], previews: [:c, :d]}
  end

  test "the theme and the catalog remake every preview, and neither the slots nor the validation" do
    s = opened()

    assert remade(s, &assign(&1, :theme, Visualize.Theme.dark())) ==
             %{facts: false, required: [], previews: @all}

    catalog = Map.put(catalog(), :feed_4, Schema.new!(%{t: %{type: :time}}))

    changed = fn s ->
      s
      |> assign(:catalog, catalog)
      |> assign(:typed, Typed.typed(s.assigns.sources, catalog))
    end

    assert remade(s, changed) == %{facts: false, required: [], previews: @all}
  end

  test "an event keeps what it made, so the render after it makes nothing" do
    s = opened()
    retitle = %{"_target" => ["title"], "title" => "Renamed"}
    {:noreply, s} = Builder.handle_event("board_select", %{"cell" => "a"}, s)
    {:noreply, s} = Builder.handle_event("board_cell", retitle, s)

    assert {_kept, %{facts: false, required: [], previews: []}} = BoardMode.kept(s.assigns)
    assert %{cells: [%{title: "Renamed"} | _]} = Editing.editing(s.assigns).board_mode
  end
end
