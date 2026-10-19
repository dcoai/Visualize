defmodule Examples.MinesweeperTest do
  @moduledoc """
  The game behind `/minesweeper` (#758): a seed and a first click are one layout, the
  first click is safe, counts are the mines around, zeros flood, flags hold, and a game
  ends won or lost.
  """
  use ExUnit.Case, async: true

  alias Examples.Minesweeper

  doctest Examples.Minesweeper

  # Seed 42 opened at the center: the layout the page and its LiveView test play.
  @seed_42 """
  *21.111..
  2*1.1*211
  111.112*1
  ......111
  .......11
  ..111.12*
  ..1*113*3
  .12211**2
  .1*1.1221\
  """

  defp opened(seed \\ 42, at \\ {4, 4}), do: Minesweeper.reveal(Minesweeper.new(seed: seed), at)

  test "a seed and a first click are one layout, asserted exactly" do
    game = opened()
    assert Minesweeper.picture(game) == @seed_42
    assert MapSet.size(game.mined) == 10
    assert Minesweeper.picture(opened()) == Minesweeper.picture(game)
    refute Minesweeper.picture(opened(43)) == Minesweeper.picture(game)
  end

  test "nothing is mined before the first reveal" do
    game = Minesweeper.new(seed: 42)
    assert game.status == :ready
    assert game.mined == nil
    refute Enum.any?(Minesweeper.cells(game), &Minesweeper.mine?(game, &1))
    assert Enum.all?(Minesweeper.rows(game), &(&1.state == :hidden and &1.count == nil))
  end

  test "the first click is safe, and so is every cell around it" do
    for seed <- 1..200, at <- [{0, 0}, {4, 4}, {8, 3}] do
      game = opened(seed, at)
      assert game.status == :playing, "seed #{seed} at #{inspect(at)}"

      for cell <- [at | Minesweeper.neighbors(game, at)],
          do: refute(Minesweeper.mine?(game, cell), "seed #{seed}: #{inspect(cell)} is mined")
    end
  end

  test "a grid too small to spare the neighbors spares the first cell alone" do
    game = Minesweeper.reveal(Minesweeper.new(rows: 3, cols: 3, mines: 8, seed: 1), {1, 1})
    assert game.mined == MapSet.new(Minesweeper.cells(game) -- [{1, 1}])
    assert game.status == :won
  end

  test "too many mines is refused" do
    assert_raise ArgumentError, fn -> Minesweeper.new(rows: 2, cols: 2, mines: 4) end
  end

  test "a count is the mines among the eight around" do
    game = opened()
    assert Minesweeper.count(game, {0, 1}) == 2
    assert Minesweeper.count(game, {6, 8}) == 3
    assert Minesweeper.count(game, {4, 4}) == 0
    assert Minesweeper.neighbors(game, {0, 0}) == [{0, 1}, {1, 0}, {1, 1}]
    assert length(Minesweeper.neighbors(game, {4, 4})) == 8
  end

  test "a zero reveals its area, bordered by counts" do
    game = opened()

    # The area of the center: every zero connected to it and the counts around them.
    assert MapSet.member?(game.revealed, {3, 0})
    assert MapSet.member?(game.revealed, {2, 0})
    assert MapSet.member?(game.revealed, {0, 3})
    refute MapSet.member?(game.revealed, {0, 1})
    refute MapSet.member?(game.revealed, {8, 4})
    refute Enum.any?(game.revealed, &Minesweeper.mine?(game, &1))

    for cell <- game.revealed,
        Minesweeper.count(game, cell) == 0,
        neighbor <- Minesweeper.neighbors(game, cell),
        do: assert(MapSet.member?(game.revealed, neighbor))
  end

  test "a flag stops a reveal, comes off again, and counts against the mines left" do
    game = opened() |> Minesweeper.toggle_flag({0, 0})
    assert Minesweeper.mines_left(game) == 9
    assert Minesweeper.reveal(game, {0, 0}) == game
    assert Minesweeper.state(game, {0, 0}) == :flagged

    # A revealed cell takes no flag; a flag comes off as it went on.
    assert Minesweeper.toggle_flag(game, {4, 4}) == game
    assert game |> Minesweeper.toggle_flag({0, 0}) |> Minesweeper.mines_left() == 10

    # Before the first reveal there is nothing to flag.
    fresh = Minesweeper.new(seed: 42)
    assert Minesweeper.toggle_flag(fresh, {0, 0}) == fresh
  end

  test "revealing a mine loses: every mine is shown, the one revealed exploded" do
    game = opened() |> Minesweeper.toggle_flag({1, 1}) |> Minesweeper.toggle_flag({0, 1})
    lost = Minesweeper.reveal(game, {0, 0})

    assert lost.status == :lost
    assert lost.hit == {0, 0}
    assert Minesweeper.over?(lost)
    assert Minesweeper.state(lost, {0, 0}) == :exploded
    assert Minesweeper.state(lost, {1, 1}) == :flagged
    assert Minesweeper.state(lost, {0, 1}) == :misflagged
    assert Minesweeper.state(lost, {1, 5}) == :mine

    rows = Map.new(Minesweeper.rows(lost), &{{&1.row, &1.col}, &1})
    assert rows[{0, 0}].glyph == :bomb
    assert rows[{1, 1}].glyph == :flag
    assert rows[{0, 1}].glyph == :cross
    assert rows[{1, 5}].glyph == :bomb

    # Nothing moves once it is over.
    assert Minesweeper.reveal(lost, {8, 0}) == lost
    assert Minesweeper.toggle_flag(lost, {8, 0}) == lost
  end

  test "revealing every safe cell wins, and every mine is flagged" do
    game = opened()
    safe = for cell <- Minesweeper.cells(game), not Minesweeper.mine?(game, cell), do: cell
    won = Enum.reduce(safe, game, &Minesweeper.reveal(&2, &1))

    assert won.status == :won
    assert won.flagged == won.mined
    assert Minesweeper.mines_left(won) == 0
    assert Enum.count(Minesweeper.rows(won), &(&1.glyph == :flag)) == 10
  end

  test "the rows: one per cell, row by row; a count only where a revealed cell shows one" do
    rows = Minesweeper.rows(opened())

    assert length(rows) == 81
    assert Enum.take(rows, 2) |> Enum.map(&{&1.row, &1.col}) == [{0, 0}, {0, 1}]

    for row <- rows do
      assert Map.keys(row) |> Enum.sort() == [:col, :count, :glyph, :row, :state]
      if row.state != :revealed, do: assert(row.count == nil)
    end

    assert Enum.find(rows, &(&1.row == 2 and &1.col == 0)).count == 1
    assert Enum.find(rows, &(&1.row == 4 and &1.col == 4)).count == nil
  end
end
