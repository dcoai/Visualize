if Code.ensure_loaded?(Phoenix.Component) do
  defmodule Visualize.Chart.Builder.Store do
    @moduledoc """
    The library of saved fragments a host may give `Visualize.Chart.Builder` (spec/14 §19.7).

    The library is the host's: this behaviour is the whole of what the builder knows about
    it, so the builder never learns where a fragment is kept or when it is written. A host
    with no library gives no `store` and loses only the library pane.

    **An entry is where a fragment gets its identity** (§19.1, D-99). The store issues each
    entry an id — `{:style, 11}`, `{:theme, 32}` — from a per-kind sequence it never repeats
    (§19.2, D-100), and the entry's name is an attribute nothing references. A fragment's
    body carries no name and no id of its own.

    **The context** is whatever the host passes as the second element of a
    `{module, context}` store assign — who is saving, from where — and every callback
    receives it. A bare module is `{module, nil}`.

    ## Example

        defmodule MyApp.FragmentStore do
          @behaviour Visualize.Chart.Builder.Store

          @impl true
          def list(_context), do: MyApp.Repo.all(from f in Fragment, select: %{id: ..., name: ...})

          @impl true
          def get(id, _context), do: ...

          @impl true
          def put(%{id: nil} = entry, %{user: user}), do: insert(entry, user)
          def put(%{id: id} = entry, %{user: user}), do: update(id, entry, user)

          @impl true
          def delete(id, _context), do: ...

          @impl true
          def import(bundle, context), do: Visualize.Chart.Builder.Store.relocate(bundle, context, &put/2)
        end

    `relocate/3` is the reference implementation of `import/2` over `put/2`; a store with a
    transaction wraps it in one.

    This module compiles only when `Phoenix.Component` is loaded, as every module of the
    builder does (spec/10 §1.1, D-45, D-85).
    """

    alias Visualize.Chart.{Fragment, Migration}
    alias Visualize.Chart.Theme, as: ChartTheme

    @typedoc "An entry's identity: its kind and a number the store never repeats (§19.2)."
    @type id :: {atom(), pos_integer()}

    @typedoc "Whatever the host says about who is saving and from where; `nil` when it says nothing."
    @type context :: term()

    @typedoc """
    A stored entry. `id` is `nil` for one that has not been stored yet; `name` is the
    `<group>:<sub-group>:<name>` attribute of §18.16; `kind` is derived from the fragment
    (§19.8) and carried so a listing need not load every body.
    """
    @type entry :: %{
            optional(:id) => id() | nil,
            name: String.t(),
            kind: atom(),
            fragment: map()
          }

    @typedoc "What `list/1` returns for each entry: everything but the body."
    @type summary :: %{id: id(), name: String.t(), kind: atom()}

    @typedoc "A store as the builder holds it: a module, or a module with its context."
    @type store :: module() | {module(), context()}

    @doc "Every entry, without its body, in the order the library shows them."
    @callback list(context()) :: [summary()]

    @doc "The entry stored under an id, or `:error` when the store no longer holds it."
    @callback get(id(), context()) :: {:ok, entry()} | :error

    @doc """
    Stores an entry. One with no `id` is new and is issued one; one with an `id` replaces
    what that id holds. `{:error, reason}` is shown by the builder and not interpreted.
    """
    @callback put(entry(), context()) :: {:ok, id()} | {:error, term()}

    @doc "Removes an entry. A later reference to its id is a mask (§19.2)."
    @callback delete(id(), context()) :: :ok | {:error, term()}

    @doc """
    Imports a bundle: every entry is issued a new id, references inside the bundle are
    rewritten through the `old => new` table, and the whole is committed or nothing is
    (§19.7, D-103). References to ids outside the bundle are reported, never a failure.
    """
    @callback import(Visualize.Chart.Builder.Bundle.t(), context()) ::
                {:ok, %{ids: %{id() => id()}, outside: [id()]}} | {:error, term()}

    # -- calling a store as the builder holds it --------------------------------------

    @doc "The module and context of a store assign; a bare module has a `nil` context."
    @spec split(store()) :: {module(), context()}
    def split({module, context}) when is_atom(module), do: {module, context}
    def split(module) when is_atom(module), do: {module, nil}

    @doc false
    def list(store), do: with({m, c} <- split(store), do: m.list(c))
    @doc false
    def get(store, id), do: with({m, c} <- split(store), do: m.get(id, c))
    @doc false
    def put(store, entry), do: with({m, c} <- split(store), do: m.put(entry, c))
    @doc false
    def delete(store, id), do: with({m, c} <- split(store), do: m.delete(id, c))
    @doc false
    def import(store, bundle), do: with({m, c} <- split(store), do: m.import(bundle, c))

    # -- a stored theme, by name -------------------------------------------------------

    @doc """
    The stored theme of a name (spec/14 §2.5, §9.3, D-139): the `:theme` entry whose theme
    names itself `name` — or, for one that gives no name, whose entry name's last `:`
    segment is `name` — read by `Visualize.Chart.Theme.from_map/2`. `{:error, errors}` for one stored that does not read,
    `:error` when the store holds no theme of that name.

    This is how a host ships a theme as a value: it stores one, and a design that names it
    previews in it.
    """
    @spec theme(store(), atom() | String.t()) ::
            {:ok, Visualize.Theme.t()} | {:error, [Visualize.Chart.Validator.error()]} | :error
    def theme(store, name) when is_atom(name) or is_binary(name) do
      with {:ok, entry} <- theme_entry(store, name), do: ChartTheme.from_map(entry.fragment)
    end

    @doc """
    The stored theme entry `theme/2` reads — `{:ok, entry}`, its `id`, `name` and fragment —
    or `:error` (spec/14 §20.1): what the theme mode opens when a chart's design names a
    stored theme, so saving updates the entry the chart draws in.
    """
    @spec theme_entry(store(), atom() | String.t()) :: {:ok, entry()} | :error
    def theme_entry(store, name) when is_atom(name) or is_binary(name) do
      wanted = to_string(name)

      store
      |> list()
      |> Enum.filter(&(&1.kind == :theme))
      |> Enum.find_value(:error, fn summary ->
        case get(store, summary.id) do
          {:ok, entry} ->
            if theme_name(entry) == wanted, do: {:ok, Map.put(entry, :id, summary.id)}

          :error ->
            nil
        end
      end)
    end

    @doc """
    The name a stored theme entry answers to, as a string (spec/14 §19.7): the name its
    theme gives itself, or, for one that gives none, its entry name's last `:` segment.
    `nil` for an entry that is not a theme. This is what `theme/2` matches a name against,
    and what a board bundle's import checks a carried theme by (spec/15 §11.2).

        iex> Visualize.Chart.Builder.Store.theme_name(%{name: "house:ocean", fragment: %{theme: %{series: ["#036"]}}})
        "ocean"
        iex> Visualize.Chart.Builder.Store.theme_name(%{name: "house:x", fragment: %{style: %{}}})
        nil
    """
    @spec theme_name(entry()) :: String.t() | nil
    def theme_name(%{fragment: %{theme: theme}} = entry) do
      case theme do
        %{name: name} when is_atom(name) and name != nil -> to_string(name)
        name when is_atom(name) and name != nil -> to_string(name)
        _unnamed -> last_segment(Map.get(entry, :name))
      end
    end

    def theme_name(_entry), do: nil

    defp last_segment(name) when is_binary(name), do: name |> String.split(":") |> List.last()
    defp last_segment(_name), do: nil

    # -- ids as the DOM and the wire carry them ---------------------------------------

    @doc """
    An id as one string, for a `data-` attribute or an event value.

        iex> Visualize.Chart.Builder.Store.encode_id({:style, 11})
        "style:11"
    """
    @spec encode_id(id()) :: String.t()
    def encode_id({kind, n}) when is_atom(kind) and is_integer(n), do: "#{kind}:#{n}"

    @doc """
    A string back to an id, or `:error`. The kind must be one a fragment can have, so no
    atom is created from a client's string.

        iex> Visualize.Chart.Builder.Store.decode_id("style:11")
        {:ok, {:style, 11}}

        iex> Visualize.Chart.Builder.Store.decode_id("nonsense:11")
        :error
    """
    @spec decode_id(String.t()) :: {:ok, id()} | :error
    def decode_id(string) when is_binary(string) do
      with [kind, digits] <- String.split(string, ":", parts: 2),
           {n, ""} when n > 0 <- Integer.parse(digits),
           {:ok, kind} <- kind(kind) do
        {:ok, {kind, n}}
      else
        _ -> :error
      end
    end

    def decode_id(_other), do: :error

    defp kind(string) do
      Enum.find_value(Fragment.kinds(), :error, fn kind ->
        if to_string(kind) == string, do: {:ok, kind}
      end)
    end

    # -- the reference implementation of import ---------------------------------------

    @doc """
    Imports a bundle through a store's own `put/2`: the relocation of §19.7.

    Every entry is put with no id, in bundle order, so the store issues a fresh one; the
    `old => new` table is built as it goes; then every entry's fragment is rewritten through
    the table and put again under its new id. A reference to an id the bundle does not
    carry is left as it is and reported in `outside`, and resolves as a mask (§19.2).

    A bundle exported at a schema version newer than this library reads is refused before
    any entry is put, as `{:error, {:newer_schema, needs, this}}` (spec/14 §9.1); one whose
    provenance carries no `schema` is read as the current version.

    A store that can wrap this in a transaction should, so the bundle lands whole or not at
    all; this function itself has no way to undo a put that succeeded.
    """
    @spec relocate(Visualize.Chart.Builder.Bundle.t(), context(), (entry(), context() ->
                                                                     {:ok, id()}
                                                                     | {:error, term()})) ::
            {:ok, %{ids: %{id() => id()}, outside: [id()]}} | {:error, term()}
    def relocate(%{entries: entries} = bundle, context, put) do
      carried = MapSet.new(entries, & &1.id)

      with :ok <- Migration.readable(schema(bundle)),
           {:ok, table} <- issue(entries, context, put),
           {:ok, outside} <- rewrite(entries, table, context, put) do
        {:ok, %{ids: table, outside: Enum.reject(outside, &(&1 in carried))}}
      end
    end

    # The schema version a bundle was exported at; `nil`, read as the current, for one
    # exported before provenance carried it.
    defp schema(%{provenance: %{schema: schema}}), do: schema
    defp schema(_bundle), do: nil

    defp issue(entries, context, put) do
      Enum.reduce_while(entries, {:ok, %{}}, fn entry, {:ok, table} ->
        case put.(Map.put(entry, :id, nil), context) do
          {:ok, new} -> {:cont, {:ok, Map.put(table, entry.id, new)}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
    end

    defp rewrite(entries, table, context, put) do
      Enum.reduce_while(entries, {:ok, []}, fn entry, {:ok, outside} ->
        {fragment, missed} = Fragment.relocate(entry.fragment, table)
        relocated = %{entry | id: Map.fetch!(table, entry.id), fragment: fragment}

        case put.(relocated, context) do
          {:ok, _id} -> {:cont, {:ok, outside ++ missed}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
    end
  end
end
