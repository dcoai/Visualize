defmodule Visualize.Chart.Builder.BoardSourcesTest do
  @moduledoc """
  #753, D-194: the board mode runs a board's virtual sources over the preview's data, shows
  each one's function, faults and preview rows, and writes a function edited as text when
  it holds, keeping a refused one as a draft (spec/14 §22.9).
  """
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [assign: 3]

  alias Visualize.{Board, BuilderFixture}
  alias Visualize.Board.Binding
  alias Visualize.Chart.Builder
  alias Visualize.Chart.Builder.{BoardMode, Editing}
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

  @moduletag :capture_log

  defmodule Host do
    @moduledoc false
    use Visualize.VirtualSources
    defsource(tripled(inputs), do: Enum.map(inputs.feed_1, &%{v: &1.v * 3}))
  end

  @t0 ~U[2026-10-16 00:00:00Z]
  @doubled "fn %{feed_1: rows} -> Enum.map(rows, fn r -> %{v: r.v * 2} end) end"

  defp entries do
    {uses, _labels} =
      Visualize.Chart.Composite.decompose(Visualize.Chart.stack(BuilderFixture.layers()))

    board =
      %{
        meta: %{name: "Ops"},
        cells: %{a: %{x: 0, y: 0, w: 6, h: 3, ref: {:composite, 1}}},
        virtual_sources: %{
          doubled: %{from: [{:feed_1, nil}], schema: %{v: %{type: :number}}, elixir: @doubled},
          tripled: %{from: [{:feed_1, nil}], schema: %{v: %{type: :number}}, function: :tripled}
        }
      }
      |> Board.from_map!()
      |> Board.to_map()

    %{
      {:composite, 1} => %{
        name: "Charts::one",
        kind: :composite,
        fragment: %{composite: %{uses: uses, vars: %{}}}
      },
      {:board, 1} => %{name: "Boards::ops", kind: :board, fragment: %{board: board}}
    }
  end

  defp opened do
    rows = for i <- 1..10, do: %{t: DateTime.add(@t0, i, :second), v: i}

    s =
      BuilderFixture.socket(BuilderFixture.layers(),
        store: {Shelf, entries()},
        sources: %{feed_1: rows}
      )

    catalog = %{feed_1: Schema.new!(%{t: %{type: :time}, v: %{type: :number}})}
    {:ok, s} = Builder.update(%{catalog: catalog, virtual_sources: [Host]}, s)
    {:noreply, s} = Builder.handle_event("add_layer", %{"name" => "board:1"}, s)
    s |> assign(:binding, Binding.new(%{{:a, :primary} => :feed_1})) |> BoardMode.keep()
  end

  defp mode(s), do: Editing.editing(s.assigns).board_mode

  defp source(s, path), do: Enum.find(mode(s).sources, &(&1.path == path))

  test "every source runs over the preview's data, its function and rows shown" do
    s = opened()
    doubled = source(s, "doubled")

    assert doubled.state == "live" and doubled.stored? and doubled.text == @doubled
    assert doubled.columns == ["v"]
    assert doubled.cells == [["2"], ["4"], ["6"], ["8"], ["10"]]

    tripled = source(s, "tripled")
    refute tripled.stored?
    assert tripled.text =~ "&1.v * 3"
    assert tripled.cells == [["3"], ["6"], ["9"], ["12"], ["15"]]
  end

  test "a refused text is kept as a draft beside its faults; the board keeps the last that held" do
    s = opened()

    {:noreply, s} =
      Builder.handle_event(
        "board_source",
        %{"source" => "doubled", "elixir" => "fn x -> send(x, 1) end"},
        s
      )

    s = BoardMode.keep(s)
    doubled = source(s, "doubled")
    assert doubled.draft?
    assert doubled.text == "fn x -> send(x, 1) end"
    assert ["line 1: send/2 is not allowed in a virtual source"] = doubled.faults
    assert doubled.cells == [["2"], ["4"], ["6"], ["8"], ["10"]]
    assert s.assigns.board.virtual_sources.doubled.elixir == @doubled

    # A field no input has is named, in context.
    {:noreply, s} =
      Builder.handle_event(
        "board_source",
        %{
          "source" => "doubled",
          "elixir" => "fn %{feed_1: rows} -> Enum.map(rows, & %{v: &1.cpu}) end"
        },
        s
      )

    assert ["line 1: cpu is not a field" <> _] = source(BoardMode.keep(s), "doubled").faults
  end

  test "a text that holds is written and run at once" do
    s = opened()
    tenfold = "fn %{feed_1: rows} -> Enum.map(rows, fn r -> %{v: r.v * 10} end) end"

    {:noreply, s} =
      Builder.handle_event("board_source", %{"source" => "doubled", "elixir" => tenfold}, s)

    s = BoardMode.keep(s)
    assert s.assigns.board.virtual_sources.doubled.elixir == tenfold
    doubled = source(s, "doubled")
    refute doubled.draft?
    assert doubled.cells == [["10"], ["20"], ["30"], ["40"], ["50"]]
  end

  test "the panel shows the section: a text box for a stored function, the host's read-only" do
    s = opened()

    html =
      Phoenix.LiveViewTest.rendered_to_string(
        Visualize.Chart.Builder.Boards.panel(%{id: "p", mode: mode(s), target: nil})
      )

    assert html =~ ~s(data-board-source="doubled")
    assert html =~ ~s(<textarea name="elixir")
    assert html =~ ~s(<pre class="vis-builder-board-source-text")
  end
end
