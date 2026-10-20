defmodule Visualize.Board.VirtualSourcesTest do
  # A board's virtual sources: the board's and its cells' keys, their validation, their
  # canonical form and their codecs (spec/15 §1.2, §1.3, §2.2, §3.1; spec/08 §10.5, D-194).
  use ExUnit.Case, async: true

  alias Visualize.Board
  alias Visualize.VirtualSource

  @names ~w(hosts host cpu state health load trend)a
  setup_all do
    {:ok, names: @names}
  end

  @health %{
    from: [{:hosts, {:window, last: 20}}],
    per: :identity,
    schema: %{
      host: %{type: :category, identity: true},
      state: %{
        type: :category,
        values: [:ok, :warning, :error],
        status: %{ok: :good, error: :bad}
      }
    },
    elixir: "fn rows -> %{state: :ok} end"
  }

  @load %{
    from: [
      # A feed's own name, which no virtual source shadows (spec/08 §10.5.6, D-195).
      {{:feed, "vm.load"}, %{ranges: %{t: [~U[2026-10-16 00:00:00Z], nil]}, latest: false}},
      {[:health], nil}
    ],
    schema: %{"load" => %{type: :number}, trend: %{type: :category}},
    function: :load
  }

  defp board(extra \\ %{}) do
    Map.merge(
      %{
        cells: %{
          fleet: %{
            x: 0,
            y: 0,
            w: 6,
            h: 2,
            ref: {:composite, 1},
            virtual_sources: %{health: @health}
          }
        },
        virtual_sources: %{health: @health, load: @load}
      },
      extra
    )
  end

  test "a board and its cells hold virtual sources, kept in their canonical form" do
    assert {:ok, board} = Board.from_map(board())

    assert board.virtual_sources["health"].from == [{"hosts", %{last: 20}}]
    assert board.virtual_sources["health"].function == nil
    assert board.cells["fleet"].virtual_sources["health"].per == :identity
    assert {:ok, ^board} = board |> Board.to_map() |> Board.from_map()
  end

  test "virtual_sources/1: every source by path" do
    sources = Board.virtual_sources(Board.from_map!(board()))

    assert Map.keys(sources) |> Enum.sort() == [["fleet", "health"], ["health"], ["load"]]
    assert %VirtualSource{id: "health"} = sources[["fleet", "health"]]
    assert %VirtualSource{id: "load", function: "load"} = sources[["load"]]

    # From the cell, its own definition shadows the board's.
    assert VirtualSource.resolve(sources, [:fleet], :health) == {:ok, ["fleet", "health"]}
    assert VirtualSource.resolve(sources, [:fleet], :load) == {:ok, ["load"]}
  end

  test "every fault, under its id" do
    bad = %{@health | per: :sideways}

    assert {:error, errors} =
             Board.from_map(
               board(%{
                 virtual_sources: %{1 => %{}, health: bad, three: 3},
                 cells: %{
                   fleet: %{x: 0, y: 0, w: 6, h: 2, ref: {:composite, 1}, virtual_sources: 4}
                 }
               })
             )

    assert errors == [
             {[:cells, "fleet", :virtual_sources], {:type, {:map, {:node, :virtual_source}}}},
             {[:virtual_sources, 1], {:type, :name}},
             {[:virtual_sources, "health", :per], {:enum, [:identity]}},
             {[:virtual_sources, "three"], {:type, {:node, :virtual_source}}}
           ]

    for error <- errors, do: assert(is_binary(Board.format_error(error)))
  end

  test "the JSON form round-trips, with no tag of its own" do
    board = Board.from_map!(board())
    assert {:ok, json} = Board.to_json(board)
    assert {:ok, ^board} = Board.from_json(json)

    document = Jason.decode!(json)
    health = document["virtual_sources"]["health"]
    assert health["from"] == [[%{"$atom" => "hosts"}, %{"last" => 20}]]
    assert health["per"] == "identity"
    assert health["elixir"] == "fn rows -> %{state: :ok} end"

    load = document["virtual_sources"]["load"]

    assert [
             [
               "vm.load",
               %{"ranges" => [[%{"$atom" => "t"}, [%{"$time" => _}, nil]]], "latest" => false}
             ],
             [[%{"$atom" => "health"}], nil]
           ] = load["from"]

    assert load["function"] == "load"
    # A field is a name, its string, written as an atom was whichever spelling gave it (D-195).
    assert [%{"$atom" => "load"}, %{"type" => %{"$atom" => "number"}}] in load["schema"]
  end

  test "a JSON key a virtual source does not know stays a string and is refused" do
    {:ok, json} = Board.to_json(Board.from_map!(board()))

    document =
      json
      |> Jason.decode!()
      |> put_in(["virtual_sources", "health", "frm"], 1)

    assert {:error, [{[:virtual_sources, "health", "frm"], :unknown_key}]} =
             Board.from_json(Jason.encode!(document))
  end
end
