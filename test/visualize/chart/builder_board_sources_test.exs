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
    defsource(tripled(inputs), do: Enum.map(inputs["feed_1"], &%{v: &1.v * 3}))

    # A function of two arguments (D-228): its scope's variables shape its answer.
    defsource scaled(inputs, context) do
      %{"k" => k, "unit" => unit} = context["vars"]
      Enum.map(inputs["feed_1"], &%{v: &1.v * k, unit: unit})
    end
  end

  @scaled %{
    from: [{:feed_1, nil}],
    schema: %{v: %{type: :number}, unit: %{type: :category}},
    function: :scaled
  }

  # A stored function of two arguments reading a variable no scope gives (D-229).
  @unknown ~S|fn %{feed_1: rows}, context -> Enum.map(rows, fn r -> %{v: r.v * context["vars"]["nope"]} end) end|

  @t0 ~U[2026-10-16 00:00:00Z]
  @doubled "fn %{feed_1: rows} -> Enum.map(rows, fn r -> %{v: r.v * 2} end) end"

  defp entries do
    {uses, _labels} =
      Visualize.Chart.Composite.decompose(Visualize.Chart.stack(BuilderFixture.layers()))

    board =
      %{
        meta: %{name: "Ops"},
        vars: %{k: 5, unit: "%"},
        cells: %{
          a: %{
            x: 0,
            y: 0,
            w: 6,
            h: 3,
            ref: {:composite, 1},
            vars: %{unit: "ms"},
            virtual_sources: %{
              scaled: @scaled,
              unknown: %{from: [{:feed_1, nil}], schema: %{v: %{type: :number}}, elixir: @unknown}
            }
          }
        },
        virtual_sources: %{
          doubled: %{from: [{:feed_1, nil}], schema: %{v: %{type: :number}}, elixir: @doubled},
          tripled: %{from: [{:feed_1, nil}], schema: %{v: %{type: :number}}, function: :tripled},
          scaled: @scaled
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
    assert s.assigns.board.virtual_sources["doubled"].elixir == @doubled

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
    assert s.assigns.board.virtual_sources["doubled"].elixir == tenfold
    doubled = source(s, "doubled")
    refute doubled.draft?
    assert doubled.cells == [["10"], ["20"], ["30"], ["40"], ["50"]]
  end

  test "a source of two arguments previews with the board's variables, a cell's over them (D-229)" do
    s = opened()

    board = source(s, "scaled")
    assert board.state == "live"
    assert board.cells == [["%", "5"], ["%", "10"], ["%", "15"], ["%", "20"], ["%", "25"]]

    # The cell's own `unit` over the board's, the board's `k` beneath it.
    cell = source(s, "a.scaled")
    assert cell.state == "live"
    assert cell.cells == [["ms", "5"], ["ms", "10"], ["ms", "15"], ["ms", "20"], ["ms", "25"]]
  end

  test "a literal read of a variable the scope does not give is the fault the board would show" do
    s = opened()

    unknown = source(s, "a.unknown")
    assert unknown.state == "restricted"
    assert "line 1: nope is not a variable of the virtual source's scope" in unknown.faults

    # Written from the page, the text is checked against the scope's variables too.
    reads_k =
      ~S|fn %{feed_1: rows}, context -> Enum.map(rows, fn r -> %{v: r.v * context["vars"]["k"]} end) end|

    {:noreply, s} =
      Builder.handle_event("board_source", %{"source" => "a.unknown", "elixir" => reads_k}, s)

    s = BoardMode.keep(s)
    unknown = source(s, "a.unknown")
    refute unknown.draft?
    assert unknown.state == "live"
    assert unknown.cells == [["5"], ["10"], ["15"], ["20"], ["25"]]

    {:noreply, s} =
      Builder.handle_event("board_source", %{"source" => "doubled", "elixir" => @unknown}, s)

    doubled = source(BoardMode.keep(s), "doubled")
    assert doubled.draft?
    assert ["line 1: nope is not a variable of the virtual source's scope"] = doubled.faults
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
