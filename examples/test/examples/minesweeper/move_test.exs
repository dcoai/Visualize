defmodule Examples.Minesweeper.MoveTest do
  @moduledoc """
  The one step from a grid event to the next game (#800), which `/minesweeper` and the
  interaction page's panel both take: `"cell_click"` reveals, or flags in Flag mode or
  with Shift held; `"flag"` flags in either mode. The event's name stays the string it
  arrived as, and a name the design does not declare matches no clause.
  """
  use ExUnit.Case, async: true

  alias Examples.Minesweeper
  alias Examples.Minesweeper.Move
  alias Visualize.Event

  doctest Move

  defp event(name, {r, c}, modifiers \\ []),
    do: %Event{event: name, item: {:rect, %{"row" => r, "col" => c}}, modifiers: modifiers}

  defp opened, do: Minesweeper.reveal(Minesweeper.new(seed: 42), {4, 4})

  test "a click reveals in Reveal mode, and flags in Flag mode or with Shift held" do
    game = Minesweeper.new(seed: 42)

    assert Move.play(game, event("cell_click", {4, 4}), :reveal) ==
             Minesweeper.reveal(game, {4, 4})

    game = opened()
    flagged = Minesweeper.toggle_flag(game, {0, 0})
    assert Move.play(game, event("cell_click", {0, 0}), :flag) == flagged
    assert Move.play(game, event("cell_click", {0, 0}, [:shift]), :reveal) == flagged
    assert Move.play(game, event("cell_click", {0, 0}, [:alt]), :reveal).status == :lost
  end

  test "the flag event flags in either mode, and again takes the flag off" do
    game = opened()

    for mode <- [:reveal, :flag] do
      flagged = Move.play(game, event("flag", {0, 0}), mode)
      assert MapSet.member?(flagged.flagged, {0, 0})
      assert Move.play(flagged, event("flag", {0, 0}), mode) == game
    end
  end

  test "a name the design does not declare is no move" do
    assert_raise FunctionClauseError, fn ->
      Move.play(opened(), event("explode", {0, 0}), :reveal)
    end
  end
end
