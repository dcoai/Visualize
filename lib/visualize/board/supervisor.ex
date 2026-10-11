defmodule Visualize.Board.Supervisor do
  @moduledoc """
  Where a host's boards live: a `DynamicSupervisor` the host adds to its own tree
  (spec/15 §8.1, D-146).

  The library starts no process of its own. A host places this supervisor, names it, and
  starts each board under it with `Visualize.Board.Server.start/2`:

      children = [
        {Visualize.Board.Supervisor, name: MyApp.Boards},
        MyAppWeb.Endpoint
      ]

      {:ok, board} =
        Visualize.Board.Server.start(MyApp.Boards,
          board: board, store: store, binding: binding, feeds: feeds)

  `Visualize.Board.Server.start/2` takes any `DynamicSupervisor`, so a host that has one
  already starts boards under it, and `Visualize.Board.Server.child_spec/1` places one
  board under a supervisor of any kind. A board is `:transient`: one that crashes is
  started again with its start options, and one stopped with
  `Visualize.Board.Server.stop/1` is not.
  """

  use DynamicSupervisor

  @doc "Starts the supervisor; `name:` as `DynamicSupervisor.start_link/1` takes it."
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    case Keyword.fetch(opts, :name) do
      {:ok, name} -> DynamicSupervisor.start_link(__MODULE__, :ok, name: name)
      :error -> DynamicSupervisor.start_link(__MODULE__, :ok)
    end
  end

  @doc "Its child spec, for a host's tree: a supervisor, permanent, its id the name given."
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: Keyword.get(opts, :name, __MODULE__),
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor
    }
  end

  @impl true
  def init(:ok), do: DynamicSupervisor.init(strategy: :one_for_one)
end
