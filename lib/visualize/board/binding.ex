defmodule Visualize.Board.Binding do
  @moduledoc """
  Which feed fills each of a board's slots: the connector's value, never the board's
  (spec/15 §4.2, D-141).

  A board says what is shown and where; it names no feed. A **connector** — metresis,
  Exio, any host that knows its feeds — supplies a binding from a cell's slot, `{cell,
  slot}`, to a **feed**: any term that names a feed or a pool entry, as the pool of
  spec/14 §7.2 names a source. A board travels between hosts and a binding does not,
  because the feeds it names are one host's.

  `check/3` holds a binding to the board's required sources (`Visualize.Board.required_sources/3`)
  and the feeds' schemas before any data flows: every unbound slot, every contract a
  bound schema cannot meet and every binding to nothing, by path. `pools/2` turns a
  binding and a host's sources into one pool per cell, the pool `Visualize.Chart.apply/2`
  binds a component from.

  ## Examples

      iex> alias Visualize.Board.Binding
      iex> binding = Binding.new(%{{:latency, :primary} => :api_latency})
      iex> Binding.fetch(binding, :latency, :primary)
      {:ok, :api_latency}
      iex> required = %{
      ...>   {:latency, :primary} => %{fields: [:t, :v], types: %{}, requires: %{v: [:unit]}},
      ...>   {:errors, :primary} => %{fields: [:t, :n], types: %{}, requires: %{}}
      ...> }
      iex> schema = Visualize.Data.Schema.new!(%{v: %{type: :number, label: "Latency"}})
      iex> Binding.check(binding, required, %{api_latency: schema})
      {:error,
       [
         {[:cells, :errors, :sources, :primary], {:unbound, :binding, :primary}},
         {[:cells, :latency, :sources, :primary, :requires, :v],
          {:missing_attribute, :primary, :v, :unit}}
       ]}

  """

  alias Visualize.Chart.Types
  alias Visualize.Data.Schema

  defstruct slots: %{}

  @typedoc "A cell's slot: the cell's name and the slot's own (spec/15 §4.1)."
  @type key :: {atom(), atom()}

  @typedoc "Anything that names a feed or a pool entry."
  @type feed :: term()

  @type t :: %__MODULE__{slots: %{key() => feed()}}

  @typedoc "What one slot of a board needs, as `Visualize.Board.required_sources/3` gives it."
  @type need :: %{
          required(:fields) => [atom()],
          required(:types) => %{atom() => atom()},
          required(:requires) => %{atom() => [atom()]},
          optional(:reads) => [{list(), atom(), Visualize.Chart.need()}]
        }

  @typedoc "The feeds' schemas: a map from feed to schema, or a feed's describe function."
  @type schemas :: %{feed() => Schema.t()} | (feed() -> {:ok, Schema.t()} | {:error, term()})

  @doc "The empty binding."
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc """
  A binding of a map, or a list, of `{{cell, slot}, feed}` pairs. Raises `ArgumentError`
  for a key that is not a pair of atoms.
  """
  @spec new(map() | [{key(), feed()}]) :: t()
  def new(pairs) when is_map(pairs) or is_list(pairs) do
    Enum.reduce(pairs, new(), fn
      {{cell, slot}, feed}, binding -> put(binding, cell, slot, feed)
      other, _binding -> raise ArgumentError, "not a {{cell, slot}, feed} pair: #{inspect(other)}"
    end)
  end

  @doc "The binding with one cell's slot bound to a feed."
  @spec put(t(), atom(), atom(), feed()) :: t()
  def put(%__MODULE__{slots: slots} = binding, cell, slot, feed) do
    unless name?(cell) and name?(slot) do
      raise ArgumentError,
            "a binding's key is {cell, slot}, two atoms; got: #{inspect({cell, slot})}"
    end

    %{binding | slots: Map.put(slots, {cell, slot}, feed)}
  end

  defp name?(name), do: is_atom(name) and not is_boolean(name) and not is_nil(name)

  @doc "The feed a cell's slot is bound to, or `:error`."
  @spec fetch(t(), atom(), atom()) :: {:ok, feed()} | :error
  def fetch(%__MODULE__{slots: slots}, cell, slot), do: Map.fetch(slots, {cell, slot})

  @doc """
  `:ok`, or every fault of the binding against a board's required sources and the feeds'
  schemas (spec/15 §4.3), each at `[:cells, cell, :sources, slot]` or under it, ordered
  by path:

    * a required slot the binding does not bind is `{:unbound, :binding, slot}`;
    * for a bound slot whose contract is not empty, a feed with no schema is
      `{:undescribed, feed}` and a describe answering `{:error, reason}` is
      `{:describe, feed, reason}`; each attribute the schema does not give is
      `{:missing_attribute, slot, field, key}` under `:requires`, and each declared
      type it contradicts `{:schema_type, field, declared, described}` under `:types` —
      the reasons and words of `Visualize.Chart.apply/2` (spec/14 §7.4);
    * for a bound slot whose `reads` is not empty, each field its schema types as its
      scale cannot take is `{:type_mismatch, slot, field, expected, given}` at
      `[:cells, cell | path]`, the read's path in the component (D-153); a schema wanted
      only for this is no fault where it cannot be had;
    * a binding of a slot nothing requires is `:not_required`.

  A slot whose contract and `reads` are empty is not looked up, and a feed is described at
  most once.
  """
  @spec check(t(), %{key() => need()}, schemas()) :: :ok | {:error, [{list(), term()}, ...]}
  def check(%__MODULE__{slots: slots}, required, schemas) when is_map(required) do
    {errors, _seen} =
      required
      |> Enum.sort()
      |> Enum.reduce({[], %{}}, fn {{cell, slot} = key, need}, {errors, seen} ->
        path = [:cells, cell, :sources, slot]

        case Map.fetch(slots, key) do
          :error ->
            {[{path, {:unbound, :binding, slot}} | errors], seen}

          {:ok, feed} ->
            {faults, seen} = contract(path, {cell, slot}, need, feed, schemas, seen)
            {faults ++ errors, seen}
        end
      end)

    stale =
      for {{cell, slot} = key, _feed} <- slots,
          not Map.has_key?(required, key),
          do: {[:cells, cell, :sources, slot], :not_required}

    case Enum.sort_by(errors ++ stale, &elem(&1, 0)) do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  # The facts a slot did not ask for are not read (spec/14 §7.4): an empty contract with
  # nothing read through a scale needs no schema, and a schema wanted only for the type
  # check (D-153) is no fault where it cannot be had.
  defp contract(path, {cell, slot}, need, feed, schemas, seen) do
    required? = map_size(Map.get(need, :requires, %{})) > 0
    reads = Map.get(need, :reads, [])

    if required? or reads != [] do
      {answer, seen} = schema(feed, schemas, seen)

      faults =
        case answer do
          {:ok, schema} ->
            missing(path, slot, need, schema) ++
              disagreements(path, need, schema) ++ mismatches(cell, slot, reads, schema)

          {:error, reason} ->
            if required?, do: [{path, reason}], else: []
        end

      {faults, seen}
    else
      {[], seen}
    end
  end

  defp schema(feed, _schemas, seen) when is_map_key(seen, feed),
    do: {Map.fetch!(seen, feed), seen}

  defp schema(feed, schemas, seen) do
    answer =
      cond do
        is_function(schemas, 1) ->
          case schemas.(feed) do
            {:ok, %Schema{} = schema} -> {:ok, schema}
            {:error, reason} -> {:error, {:describe, feed, reason}}
          end

        is_map_key(schemas, feed) ->
          {:ok, Map.fetch!(schemas, feed)}

        true ->
          {:error, {:undescribed, feed}}
      end

    {answer, Map.put(seen, feed, answer)}
  end

  # Each read whose field's known type its scale cannot take (spec/14 §7.4, D-153), at
  # the read's path under the cell.
  defp mismatches(cell, slot, reads, known) do
    reads
    |> Enum.map(fn {path, field, need} -> {path, slot, field, need} end)
    |> Types.faults(%{slot => known})
    |> Enum.map(fn {path, reason} -> {[:cells, cell | path], reason} end)
  end

  defp missing(path, slot, %{requires: requires}, schema) do
    for {field, keys} <- requires,
        key <- keys,
        Schema.fetch(schema, field, key) == :error,
        do: {path ++ [:requires, field], {:missing_attribute, slot, field, key}}
  end

  defp disagreements(path, need, schema) do
    for {field, declared} <- Map.get(need, :types, %{}),
        {:ok, described} <- [Schema.fetch(schema, field, :type)],
        described != declared,
        do: {path ++ [:types, field], {:schema_type, field, declared, described}}
  end

  @doc """
  `:ok`, or every field a bound slot's component reads through a scale whose known type
  the scale's kind cannot take (spec/15 §4.3, spec/14 §7.4, D-153):
  `{:type_mismatch, slot, field, expected, given}` at `[:cells, cell | path]`, the read's
  path in the component, ordered by path.

  `types` maps a feed to what is known of its fields: a `Visualize.Data.Schema`, or a map
  from field to type, as `Visualize.Data.Table.column_types/1` reads it from a sample's
  rows. An unbound slot, and a feed the map does not hold, are not checked — that is
  `check/3`'s to report.

      iex> alias Visualize.Board.Binding
      iex> binding = Binding.new(%{{:wave, :points} => :clock})
      iex> required = %{
      ...>   {:wave, :points} => %{fields: [:t, :v], types: %{}, requires: %{},
      ...>     reads: [{[:marks, 0, :channels, :x], :t, :number}]}
      ...> }
      iex> Binding.check_types(binding, required, %{clock: %{t: :time, v: :number}})
      {:error,
       [{[:cells, :wave, :marks, 0, :channels, :x], {:type_mismatch, :points, :t, :number, :time}}]}
  """
  @spec check_types(t(), %{key() => need()}, %{feed() => Visualize.Chart.field_types()}) ::
          :ok | {:error, [{list(), term()}, ...]}
  def check_types(%__MODULE__{slots: slots}, required, types)
      when is_map(required) and is_map(types) do
    faults =
      for {{cell, slot} = key, need} <- required,
          {:ok, feed} <- [Map.fetch(slots, key)],
          {:ok, known} <- [Map.fetch(types, feed)],
          fault <- mismatches(cell, slot, Map.get(need, :reads, []), known),
          do: fault

    case Enum.sort_by(faults, &elem(&1, 0)) do
      [] -> :ok
      faults -> {:error, faults}
    end
  end

  @doc """
  One pool per cell (spec/15 §4.4): `%{cell => %{slot => source}}` from the binding and the
  host's sources by feed. A slot whose feed has no source is left out, so application
  reports it unbound.

      iex> binding = Visualize.Board.Binding.new(%{{:a, :primary} => :cpu, {:b, :primary} => :mem})
      iex> Visualize.Board.Binding.pools(binding, %{cpu: [%{t: 1, v: 2}]})
      %{a: %{primary: [%{t: 1, v: 2}]}}
  """
  @spec pools(t(), %{feed() => term()}) :: %{atom() => %{atom() => term()}}
  def pools(%__MODULE__{slots: slots}, sources) when is_map(sources) do
    for {{cell, slot}, feed} <- slots, is_map_key(sources, feed), reduce: %{} do
      pools ->
        Map.update(pools, cell, %{slot => sources[feed]}, &Map.put(&1, slot, sources[feed]))
    end
  end
end
