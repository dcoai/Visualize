if Code.ensure_loaded?(Phoenix.Component) do
  defmodule Visualize.Chart.Builder.BoardKept do
    @moduledoc false
    # What a board-mode pass draws and checks, kept in the builder's assigns by the inputs it
    # is a function of (spec/14 §22.5, §22.6, #723, D-191): each cell's preview and each
    # cell's slots by the cell's own key, and the board's facts — its validation faults and
    # the variables its components declare — by the board and what the store says of its
    # components.
    #
    # A pass reads an entry whose key is the one it computes now and computes every other
    # one, so nothing is ever read stale: an entry is a value beside the very inputs it was
    # made from, compared with `==` (which the VM answers at once for the same term, as
    # D-189's types are). Nothing lives outside the socket: the kept map is an assign, and
    # what a pass made replaces it after each event (`Visualize.Chart.Builder.BoardMode.keep/1`).
    #
    # Each component's flattening is kept by the entries it reads (#838, D-219): `reads/2`
    # is its key, every entry the flatten can fetch beside what the store answers for it now,
    # so a pass fetches each one rather than flattening the component again.

    @typedoc "An entry: the key it was made under and what it made."
    @type entry :: {term(), term()}

    @typedoc """
    What the last pass kept: the facts' entry, each component's flattening by its ref, each
    cell's slots and preview, the virtual sources' run, and what a pass read of the run for
    its binding.
    """
    @type t :: %{
            facts: entry() | nil,
            flat: %{Visualize.Chart.Fragment.id() => entry()},
            required: %{String.t() => entry()},
            previews: %{String.t() => entry()},
            ran: entry() | nil,
            virtual: entry() | nil
          }

    @doc false
    # The facts under `key`: the kept ones when their key is `key`, else `compute.()`.
    # `{facts, entry, computed?}`.
    @spec facts(entry() | nil, term(), (-> term())) :: {term(), entry(), boolean()}
    def facts({key, facts} = entry, key, _compute), do: {facts, entry, false}

    def facts(_stale, key, compute) do
      facts = compute.()
      {facts, {key, facts}, true}
    end

    @doc false
    # Each cell's value under its key in `keys` — its preview, its slots, or a component's
    # flattening by its ref: the kept one when its key is the same, and for every other
    # `compute.(names)`, one call for all of them, a map by name. `{values, entries,
    # computed}`, `computed` the names made now, in order; a name `keys` lacks is dropped.
    @spec each(%{term() => entry()} | nil, %{term() => term()}, ([term()] -> map())) ::
            {%{term() => term()}, %{term() => entry()}, [term()]}
    def each(kept, keys, compute) do
      kept = kept || %{}

      stale =
        for {name, key} <- Enum.sort(keys),
            not match?({^key, _drawn}, Map.get(kept, name)),
            do: name

      drawn = if stale == [], do: %{}, else: compute.(stale)

      entries =
        Map.new(keys, fn {name, key} ->
          case Map.fetch(drawn, name) do
            {:ok, preview} -> {name, {key, preview}}
            :error -> {name, Map.fetch!(kept, name)}
          end
        end)

      {Map.new(entries, fn {name, {_key, preview}} -> {name, preview} end), entries, stale}
    end

    @doc false
    # What a flatten of `ref` through `fetch` is a function of (spec/14 §19.6): `ref` and
    # every id the entries it reaches refer to (`Visualize.Chart.Fragment.refs/1`), each
    # with what `fetch` answers for it now, by id. A composite fetches its sites' refs and
    # the reference sites of its flat design; both are ids its entries hold.
    @spec reads(Visualize.Chart.Fragment.id(), (term() -> {:ok, map()} | :error)) :: map()
    def reads(ref, fetch), do: reads([ref], fetch, %{})

    defp reads([], _fetch, seen), do: seen
    defp reads([id | rest], fetch, seen) when is_map_key(seen, id), do: reads(rest, fetch, seen)

    defp reads([id | rest], fetch, seen) do
      case fetch.(id) do
        {:ok, fragment} = got ->
          reads(Visualize.Chart.Fragment.refs(fragment) ++ rest, fetch, Map.put(seen, id, got))

        :error ->
          reads(rest, fetch, Map.put(seen, id, :error))
      end
    end
  end
end
