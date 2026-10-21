defmodule Visualize.Board.Server.Vars do
  @moduledoc false
  # The board process's variables (spec/15 §5, §8.2, §14.2, D-229): new variables at a
  # scope — `[]` the board's, `[cell]` one cell's own — merged into the board, the board
  # checked given the store, every cell prepared again and sent what changed, the budgets
  # recomputed, and the virtual sources' engine shown every scope's own variables, so the
  # context-taking sources whose cascade changed are marked. Running the pulse that makes
  # due is the board's, as for a feed's change.

  alias Visualize.Board
  alias Visualize.Board.Server.Budgets
  alias Visualize.VirtualSource.Engine

  @type scope :: [] | [String.t()]

  # `{:ok, state}` with the variables applied at the owner's monotonic millisecond `ms`, or
  # `{:error, errors}`, the state unchanged, for variables the board does not take.
  @doc false
  @spec change(map(), scope(), map(), integer()) :: {:ok, map()} | {:error, [Board.error()]}
  def change(state, scope, vars, ms) do
    read = [limits: state.limits, boards: state.boards, generators: state.generators]

    with {:ok, board} <- merged(state.board, scope, vars),
         {:ok, components} <- Board.components(board, state.store, read) do
      for {name, %{chart: chart, vars: v}} <- components,
          components[name] != state.components[name],
          %{pid: pid} when is_pid(pid) <- [state.cells[name]],
          do: send(pid, {:component, chart, v})

      state = Budgets.budgeted(%{state | board: board, components: components})
      {:ok, %{state | engine: Engine.vars(state.engine, Board.own_vars(board), ms)}}
    end
  end

  defp merged(board, [], vars), do: {:ok, %{board | vars: Map.merge(board.vars, vars)}}

  defp merged(board, [cell], vars) do
    case Map.fetch(board.cells, cell) do
      {:ok, own} ->
        own = Map.update(own, :vars, vars, &Map.merge(&1, vars))
        {:ok, %{board | cells: Map.put(board.cells, cell, own)}}

      :error ->
        {:error, [{[:cells, cell], :unknown_key}]}
    end
  end
end
