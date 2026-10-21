if Code.ensure_loaded?(Phoenix.Component) do
  defmodule Visualize.Chart.Builder.Bundle do
    @moduledoc """
    A collection of entries that can cross from one store into another (spec/14 §19.7).

    **Export takes the closure.** Exporting an entry exports every entry it refers to,
    transitively, with their ids, so an import cannot dangle by construction. The bundle
    carries **provenance** — which store it came from, when, and the schema version it was
    exported at (spec/14 §9.1) — and each entry keeps its
    original id, so a repeated import of the same collection is detectable rather than a
    second copy of everything.

    Importing one is the store's `import/2` callback: a relocation through one
    `old => new` table, committed whole or not at all (D-103).

    **A bundle may carry a board** (spec/15 §11, D-147): `export_board/3` adds the board's
    map form, the closure of every component its cells reference and every stored theme it
    or its components name; `import_board/3` checks all of it before any entry is put, then
    imports the entries through the store's own `import/2` and rewrites the board's cell
    refs through the same table. A bundle carries no binding: bindings are the host's.

    This module compiles only when `Phoenix.Component` is loaded (spec/10 §1.1, D-45, D-85).
    """

    alias Visualize.Board
    alias Visualize.Board.Validator, as: BoardValidator
    alias Visualize.Chart.Builder.Bundle.Codec
    alias Visualize.Chart.Builder.Store
    alias Visualize.Chart.{Composite, Fragment, Limits, Migration, Var}

    @enforce_keys [:provenance, :entries]
    defstruct [:provenance, :entries, board: nil]

    @typedoc """
    Where a bundle came from, when, and the schema version it was exported at, which an
    importer older than it refuses (spec/14 §9.1).
    """
    @type provenance :: %{store: term(), exported_at: DateTime.t(), schema: pos_integer()}

    @typedoc """
    A bundle: its provenance, its entries in dependency order, and — for one
    `export_board/3` made — the board in its map form (spec/15 §2.1), else `nil`.
    """
    @type t :: %__MODULE__{
            provenance: provenance(),
            entries: [Store.entry()],
            board: map() | nil
          }

    @typedoc "What a board's import gives: the board re-keyed, the id table, and the masks."
    @type imported :: %{board: Board.t(), ids: %{Store.id() => Store.id()}, outside: [Store.id()]}

    @doc """
    The closure of an id through a store: the entry, and every entry it refers to,
    transitively, each once, in dependency order — an entry after everything it refers to.

    `source` names the store in the provenance; it is the host's to choose and the store
    is never asked. An id the store does not hold is skipped: it was a mask before export
    and stays one after import (§19.2).
    """
    @spec export(Store.store(), Fragment.id() | [Fragment.id()], term()) :: t()
    def export(store, ids, source) do
      %__MODULE__{provenance: provenance(source), entries: closure(store, List.wrap(ids))}
    end

    defp provenance(source),
      do: %{store: source, exported_at: DateTime.utc_now(), schema: Migration.current()}

    defp closure(store, ids) do
      ids
      |> Enum.reduce({[], MapSet.new()}, fn id, acc -> close(store, id, acc) end)
      |> elem(0)
      |> Enum.reverse()
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

    # -- the map and JSON forms (spec/14 §19.7, #818, D-217) ------------------------------

    @doc """
    The bundle as plain data: `provenance`, `entries` as `%{id, name, fragment}` — an
    entry's `kind` is derived from its fragment (spec/14 §19.8), so the form leaves it out —
    and `board`, the board's map form or `nil`.
    """
    @spec to_map(t()) :: map()
    def to_map(%__MODULE__{} = bundle), do: Codec.to_map(bundle)

    @doc """
    The bundle of a map (spec/14 §19.7), or every fault of it by path.

    The provenance's `schema` is gated first (`{:newer_schema, needs, this}` at
    `[:provenance, :schema]`), then the map is held to the `depth` and `items` limits —
    `limits:` as `Visualize.Board.from_map/2` takes them — then every key is read: the
    provenance's `store` (any JSON-representable term), `exported_at` (a UTC `DateTime`) and
    `schema`; each entry's `id` (an id of a kind a fragment has, carried once), `name` and
    `fragment`; the board by `Visualize.Board.from_map/2`, kept in its map form, its faults
    under `[:board]`. An entry's `kind` is derived from its fragment. A fragment is not
    validated as a design: `import_board/3` checks what a board's import needs.
    `from_map(to_map(b))` is `{:ok, b}`.

        iex> Visualize.Chart.Builder.Bundle.from_map(%{provenance: %{schema: 9}, entries: []})
        {:error, [{[:provenance, :schema], {:newer_schema, 9, 3}}]}
    """
    @spec from_map(term(), keyword()) :: {:ok, t()} | {:error, [Board.error(), ...]}
    def from_map(map, opts \\ []), do: Codec.from_map(map, opts)

    @doc """
    The bundle as one JSON document stamped `"$version"` (spec/14 §19.7, D-217): the
    provenance with `exported_at` in ISO 8601, each entry's `id` as `Store.encode_id/1`
    writes it and its `fragment` as the document `Fragment.to_json/1` writes, and the board
    in its own JSON form (spec/15 §2.2). A store named by a string or an atom is written as
    the name's string; any other term as its tagged term (spec/14 §11.2), and one the table
    has no form for is `{:error, [{[:provenance, :store], {:type, :term}}]}`.
    `{:error, {:missing_dependency, :jason}}` without Jason.
    """
    @spec to_json(t()) ::
            {:ok, String.t()} | {:error, [Board.error(), ...] | {:missing_dependency, :jason}}
    def to_json(%__MODULE__{} = bundle), do: Codec.to_json(bundle)

    @doc """
    The bundle of a JSON document `to_json/1` wrote, with `limits:` as `from_map/2` takes
    them. The document's `"$version"` and the provenance's `schema` are gated, and the
    whole document held to the limits, before a key is decoded; then each part is read by
    its own reader — an entry's fragment by the fragment's, gated and held to the tag table
    (D-182), its faults under `[:entries, i, :fragment]`; the board by the board's — and the
    map read as `from_map/2` reads it. An id is read by `Store.decode_id/1`, so no atom is
    made from a document's kind (D-195). Text that is not a JSON object is
    `{:error, [{[], {:json, message}}]}`.

    `from_json(to_json(b))` is `{:ok, b}` with each fragment as `Fragment.from_json/2`
    reads it and a store named by an atom as its string.

        iex> Visualize.Chart.Builder.Bundle.from_json(~s({"$version": 9, "entries": []}))
        {:error, [{["$version"], {:newer_schema, 9, 3}}]}
    """
    @spec from_json(String.t(), keyword()) ::
            {:ok, t()} | {:error, [Board.error(), ...] | {:missing_dependency, :jason}}
    def from_json(json, opts \\ []) when is_binary(json), do: Codec.from_json(json, opts)

    # -- a board (spec/15 §11) ------------------------------------------------------------

    @doc """
    A board as a bundle (spec/15 §11.1): the board's map form, the closure of every
    component its cells reference, and the closure of every stored theme the board or its
    components name, dependencies first, with provenance as `export/3` gives it.

    A component names a theme by its flattened design's `theme`; a variable there is read
    through the cell's cascade (spec/15 §5), which is how a board names one. A built-in
    name is not carried, nor one the store does not hold. A cell whose component the store
    does not hold is exported as it is, and `import_board/3` reports it. No binding is
    carried: a binding names one host's feeds.
    """
    @spec export_board(Store.store(), Board.t(), term()) :: t()
    def export_board(store, %Board{} = board, source) do
      components = board.cells |> Enum.sort() |> Enum.map(fn {_name, cell} -> cell.ref end)
      themes = board |> themes(fetch(store)) |> Enum.flat_map(&stored_theme(store, &1))

      %__MODULE__{
        provenance: provenance(source),
        entries: closure(store, Enum.uniq(components ++ themes)),
        board: Board.to_map(board)
      }
    end

    # A store's entries as resolution reads them: an id to its fragment.
    defp fetch(store) do
      fn id ->
        case Store.get(store, id) do
          {:ok, entry} -> {:ok, entry.fragment}
          :error -> :error
        end
      end
    end

    # Every theme name the board's cells draw in, built-in names left out, each once.
    defp themes(board, fetch) do
      board.cells
      |> Enum.sort()
      |> Enum.flat_map(fn {name, cell} ->
        with {:ok, fragment} <- fetch.(cell.ref),
             {:ok, design, _report} <- Composite.flatten(fragment, fetch),
             theme when is_atom(theme) or is_binary(theme) <-
               named(Map.get(design, :theme), design, Board.vars(board, name)),
             false <- builtin?(theme) do
          [theme]
        else
          _ -> []
        end
      end)
      |> Enum.uniq()
    end

    # A design's theme as a name: a variable read through the cell's cascade, then the
    # design's default for it.
    # A variable is named by its string and a host's map read by spelling (D-195).
    defp named(%Var{name: var}, design, vars) do
      case Visualize.Chart.Names.fetch(vars, var) do
        {:ok, value} -> value
        :error -> design |> Map.get(:vars, %{}) |> Map.get(var, %{}) |> default()
      end
    end

    defp named(theme, _design, _vars), do: theme

    defp default(%{default: value}), do: value
    defp default(_declaration), do: nil

    defp builtin?(name), do: to_string(name) in Enum.map(Visualize.Theme.builtins(), &to_string/1)

    defp stored_theme(store, name) do
      case Store.theme_entry(store, name) do
        {:ok, %{id: id}} when id != nil -> [id]
        _ -> []
      end
    end

    @doc "As `import_board/3` with `[]` options."
    @spec import_board(Store.store(), t()) :: {:ok, imported()} | {:error, [Board.error(), ...]}
    def import_board(store, bundle), do: import_board(store, bundle, [])

    @doc """
    A board bundle into a store (spec/15 §11.2): `{:ok, %{board: board, ids: table, outside:
    ids}}`, the board with every cell's ref rewritten to its component's new id, or
    `{:error, errors}`, every fault in the board's path shape.

    Every check comes before any entry is put, so a refused bundle leaves the store as it
    was: the provenance's `schema` (spec/14 §9.1); the board read by `Visualize.Board.from_map/2`
    under `limits:`; the entries' count and each entry's `depth` and `items`; the board
    validated with the bundle's entries as its store, a cell whose component the bundle
    does not carry being `{:not_carried, id}` at its `ref`; and each carried theme's name,
    which the store may not already give a different theme (`{:theme_taken, name}`). Then
    the entries go through the store's own `import/2`, which issues every new id, and a
    store's refusal is `{:store, reason}` at `[]`. The board is returned, never put: where
    a host keeps its boards is its own.

    ## Options

      * `:limits` - as `Visualize.Board.from_map/2` takes them, for the board, the entries
        and every component's design
    """
    @spec import_board(Store.store(), t(), keyword()) ::
            {:ok, imported()} | {:error, [Board.error(), ...]}
    def import_board(store, %__MODULE__{} = bundle, opts) do
      limits = Keyword.get(opts, :limits, [])

      with :ok <- schema(bundle),
           {:ok, board} <- board(bundle, limits),
           :ok <- BoardValidator.done(entry_limits(bundle.entries, Limits.new(limits))),
           :ok <- carried(board, bundle.entries, limits),
           :ok <- BoardValidator.done(theme_names(store, bundle.entries)),
           {:ok, %{ids: ids, outside: outside}} <- relocate(store, bundle) do
        {:ok, %{board: rekey(board, ids), ids: ids, outside: outside}}
      end
    end

    defp schema(%{provenance: %{schema: schema}}) do
      with {:error, reason} <- Migration.readable(schema),
           do: {:error, [{[:provenance, :schema], reason}]}
    end

    defp schema(_bundle), do: :ok

    defp board(%{board: nil}, _limits), do: {:error, [{[:board], :required}]}
    defp board(%{board: map}, limits), do: Board.from_map(map, limits: limits)

    defp entry_limits(entries, %{items: max} = limits) do
      count =
        case length(entries) do
          n when n > max -> [{[:entries], {:limit, :items, max, n}}]
          _n -> []
        end

      count ++
        Enum.flat_map(entries, fn entry ->
          for {path, reason} <- Limits.structure(entry.fragment, limits),
              do: {[:entries, Store.encode_id(entry.id) | path], reason}
        end)
    end

    # The board given the bundle as its store: read as the receiving store will hold it, a
    # component the bundle does not carry named at its cell.
    defp carried(board, entries, limits) do
      store = Map.new(entries, &{&1.id, &1.fragment})

      case Board.validate(board, store, limits: limits) do
        :ok ->
          :ok

        {:error, errors} ->
          {:error,
           Enum.map(errors, fn
             {[:cells, _name, :ref] = path, {:dangling, id}} -> {path, {:not_carried, id}}
             error -> error
           end)}
      end
    end

    # A carried theme whose name the store already gives a different body.
    defp theme_names(store, entries) do
      for entry <- entries,
          name = Store.theme_name(entry),
          name != nil,
          {:ok, held} <- [Store.theme_entry(store, name)],
          held.fragment != entry.fragment,
          do: {[:entries, Store.encode_id(entry.id)], {:theme_taken, name}}
    end

    # The entries through the store's own import; the board is the host's, not the store's.
    defp relocate(store, bundle) do
      case Store.import(store, %{bundle | board: nil}) do
        {:ok, result} -> {:ok, result}
        {:error, reason} -> {:error, [{[], {:store, reason}}]}
      end
    end

    defp rekey(board, ids) do
      %{
        board
        | cells:
            Map.new(board.cells, fn {name, cell} ->
              {name, %{cell | ref: Map.fetch!(ids, cell.ref)}}
            end)
      }
    end
  end
end
