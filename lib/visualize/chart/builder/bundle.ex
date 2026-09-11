if Code.ensure_loaded?(Phoenix.Component) do
  defmodule Visualize.Chart.Builder.Bundle do
    @moduledoc """
    A collection of entries that can cross from one store into another (spec/14 §19.7).

    **Export takes the closure.** Exporting an entry exports every entry it refers to,
    transitively, with their ids, so an import cannot dangle by construction. The bundle
    carries **provenance** — which store it came from, and when — and each entry keeps its
    original id, so a repeated import of the same collection is detectable rather than a
    second copy of everything.

    Importing one is the store's `import/2` callback: a relocation through one
    `old => new` table, committed whole or not at all (D-103).

    This module compiles only when `Phoenix.Component` is loaded (spec/10 §1.1, D-45, D-85).
    """

    alias Visualize.Chart.Builder.Store
    alias Visualize.Chart.Fragment

    @enforce_keys [:provenance, :entries]
    defstruct [:provenance, :entries]

    @typedoc "Where a bundle came from, and when."
    @type provenance :: %{store: term(), exported_at: DateTime.t()}

    @type t :: %__MODULE__{provenance: provenance(), entries: [Store.entry()]}

    @doc """
    The closure of an id through a store: the entry, and every entry it refers to,
    transitively, each once, in dependency order — an entry after everything it refers to.

    `source` names the store in the provenance; it is the host's to choose and the store
    is never asked. An id the store does not hold is skipped: it was a mask before export
    and stays one after import (§19.2).
    """
    @spec export(Store.store(), Fragment.id() | [Fragment.id()], term()) :: t()
    def export(store, ids, source) do
      entries =
        ids
        |> List.wrap()
        |> Enum.reduce({[], MapSet.new()}, fn id, acc -> close(store, id, acc) end)
        |> elem(0)
        |> Enum.reverse()

      %__MODULE__{
        provenance: %{store: source, exported_at: DateTime.utc_now()},
        entries: entries
      }
    end

    # Depth first, so an entry is added after everything it refers to; `seen` is what has
    # been visited, so a cycle terminates and a shared entry appears once.
    defp close(store, id, {entries, seen}) do
      if id in seen do
        {entries, seen}
      else
        seen = MapSet.put(seen, id)

        case Store.get(store, id) do
          :error ->
            {entries, seen}

          {:ok, entry} ->
            {entries, seen} =
              entry.fragment
              |> Fragment.refs()
              |> Enum.reduce({entries, seen}, fn ref, acc -> close(store, ref, acc) end)

            {[Map.put(entry, :id, id) | entries], seen}
        end
      end
    end
  end
end
