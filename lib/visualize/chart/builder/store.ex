if Code.ensure_loaded?(Phoenix.Component) do
  defmodule Visualize.Chart.Builder.Store do
    @moduledoc """
    The library of saved fragments a host may give `Visualize.Chart.Builder` (spec/14 §18.3).

    The library is the host's: this behaviour is the whole of what the builder knows about
    it, so the builder never learns where a fragment is kept, when it is written or what a
    name means. A host with no library gives no `store` and loses only the picker.

    A stored fragment is a fragment (spec/14 §8) — a design map, valid or not — and nothing
    here validates one: a store that hands back a map the design cannot use fails where
    every other bad fragment fails, in the preview, by path.

    ## Example

        defmodule MyApp.FragmentStore do
          @behaviour Visualize.Chart.Builder.Store

          @impl true
          def list, do: MyApp.Repo.all(from f in Fragment, select: f.name)

          @impl true
          def get(name) do
            case MyApp.Repo.get_by(Fragment, name: name) do
              nil -> :error
              fragment -> {:ok, fragment.design}
            end
          end

          @impl true
          def put(name, fragment), do: MyApp.Repo.insert_or_update(...)
        end

    This module compiles only when `Phoenix.Component` is loaded, as every module of the
    builder does (spec/10 §1.1, D-45, D-85).
    """

    @typedoc "A stored fragment's name: any term the host chooses (spec/14 §18.3)."
    @type name :: term()

    @doc """
    Every stored fragment's name, in the order the picker offers them.

    The builder prints a name with `to_string/1` and hands it back unchanged.
    """
    @callback list() :: [name()]

    @doc """
    The fragment stored under a name, or `:error` when nothing is stored under it.
    """
    @callback get(name()) :: {:ok, map()} | :error

    @doc """
    Stores a fragment under a name, replacing what was there.

    `{:error, reason}` is shown by the builder and not interpreted by it.
    """
    @callback put(name(), map()) :: :ok | {:error, term()}
  end
end
