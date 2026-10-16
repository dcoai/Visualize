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

    @typedoc "An entry: the key it was made under and what it made."
    @type entry :: {term(), term()}

    @typedoc "What the last pass kept: the facts' entry, and each cell's slots and preview."
    @type t :: %{
            facts: entry() | nil,
            required: %{atom() => entry()},
            previews: %{atom() => entry()}
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
    # Each cell's value under its key in `keys` — its preview, its slots: the kept one when
    # its key is the same, and for every other cell `compute.(names)`, one call for all of
    # them, a map by name. `{values, entries, computed}`, `computed` the cells made now, in
    # name order; a cell the board no longer holds is dropped.
    @spec each(%{atom() => entry()} | nil, %{atom() => term()}, ([atom()] -> map())) ::
            {%{atom() => term()}, %{atom() => entry()}, [atom()]}
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
  end
end
