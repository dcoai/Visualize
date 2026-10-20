defmodule Examples.Minesweeper.Move do
  @moduledoc """
  The step from a click on the grid to the next game (#800), the one both pages that play
  Minesweeper call: `/minesweeper` (`ExamplesWeb.MinesweeperLive`) and the panel on
  `/interaction` (`ExamplesWeb.InteractionLive`).

  `Visualize.Components.Chart` resolves a click to the cell drawn and sends the page one
  `Visualize.Event` (D-170) whose `item` is the cell's identity. Its name is one of the two
  the grid's design declares, kept as the strings they arrive as — `"cell_click"`, a click
  or Enter on a cell, and `"flag"`, a right-click, a long-press or the Menu key (D-199) —
  so no atom is ever made of an event.
  """

  alias Examples.Minesweeper
  alias Visualize.Event

  @typedoc "What a plain click does: reveal, or flag (the full page's *Flag* mode)."
  @type mode :: :reveal | :flag

  @doc """
  The game after `event` on its grid. `"flag"` flags in either mode. `"cell_click"` flags
  in `:flag` mode or with Shift held (the event's `modifiers`), and reveals otherwise.

      iex> alias Examples.Minesweeper
      iex> alias Examples.Minesweeper.Move
      iex> click = %Visualize.Event{event: "cell_click", item: {:rect, %{"row" => 4, "col" => 4}}}
      iex> game = Move.play(Minesweeper.new(seed: 42), click, :reveal)
      iex> game.status
      :playing
      iex> flag = %Visualize.Event{event: "flag", item: {:rect, %{"row" => 0, "col" => 0}}}
      iex> game |> Move.play(flag, :reveal) |> Minesweeper.mines_left()
      9
  """
  @spec play(Minesweeper.t(), Event.t(), mode()) :: Minesweeper.t()
  def play(game, %Event{event: "flag", item: {_mark, %{"row" => r, "col" => c}}}, _mode),
    do: Minesweeper.toggle_flag(game, {r, c})

  def play(
        game,
        %Event{event: "cell_click", item: {_mark, %{"row" => r, "col" => c}}} = event,
        mode
      ) do
    if mode == :flag or :shift in event.modifiers,
      do: Minesweeper.toggle_flag(game, {r, c}),
      else: Minesweeper.reveal(game, {r, c})
  end
end
