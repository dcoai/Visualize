defmodule Visualize.Chart.Facts do
  @moduledoc false
  # The schema step of application (spec/14 §7.4, D-136): a design's contract — each slot's
  # `requires` and every fact it reads — checked against the schema bound to the slot,
  # and every `%Fact{}` replaced by the attribute it names. Pure: the schema cache comes
  # in and the grown cache goes out with the result.

  import Visualize.Chart.Names, only: [is_name: 1]

  alias Visualize.Chart
  alias Visualize.Chart.{Coverage, Fact, Template, Types, Validator}
  alias Visualize.Data.{Delivery, Schema}
  alias Visualize.Data.Schema.Cache

  @typedoc "What the schema step found: each slot's schema and version, and the cache."
  @type described :: %{
          schemas: %{atom() => Schema.t()},
          versions: %{atom() => String.t() | nil},
          cache: Cache.t()
        }

  @doc false
  # Every slot's requirements: its `requires` with the keys its facts read, each field's
  # list in the order of `Visualize.Chart.Fact.keys/0` (D-225); a slot with none is absent.
  @spec contract(map()) :: %{atom() => %{atom() => [atom()]}}
  def contract(map) when is_map(map) do
    required =
      for {slot, %{requires: requires}} when is_map(requires) <- slots(map),
          {field, keys} when is_list(keys) <- requires,
          key <- keys,
          do: {slot, field, key}

    read = for {_path, %Fact{source: s, field: f, key: k}} <- uses(map), do: {s, f, k}

    (required ++ read)
    |> Enum.group_by(&elem(&1, 0), &Tuple.delete_at(&1, 0))
    |> Map.new(fn {slot, pairs} ->
      {slot,
       pairs
       |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
       |> Map.new(fn {field, keys} -> {field, ordered(keys)} end)}
    end)
  end

  defp ordered(keys), do: Enum.filter(Fact.keys(), &(&1 in keys))

  # The slot declarations, or none where `sources` is not a map of them — a whole-node
  # variable in a fragment, left for application to resolve.
  defp slots(map) do
    case Map.get(map, :sources) do
      slots when is_map(slots) and not is_struct(slots) -> slots
      _absent_or_variable -> %{}
    end
  end

  # Every fact the design holds, with the path it stands at — a text's key for a hole.
  defp uses(map) do
    {_map, uses} =
      Template.walk(map, fn
        %Fact{} = fact, path -> {fact, [{path, fact}]}
        other, _path -> {other, []}
      end)

    uses
  end

  @doc false
  # The chart with every fact resolved and what was described, or every fault of the
  # contract by path (spec/14 §7.4).
  @spec apply(Chart.t(), map(), Cache.t(), Cache.describe()) ::
          {:ok, Chart.t(), described()} | {:error, [Validator.error(), ...]}
  def apply(%Chart{sources: slots} = chart, pool, %Cache{} = cache, describe) do
    map = Chart.to_map(chart)
    contract = contract(map)
    entries = entries(slots, pool)
    versions = for {slot, {_feed, %Delivery{schema: v}}} <- entries, into: %{}, do: {slot, v}

    {schemas, cache, errors} =
      Enum.reduce(contract, {%{}, cache, []}, fn {slot, _fields}, {schemas, cache, errors} ->
        case schema(slot, Map.get(entries, slot), cache, describe) do
          {:ok, schema, cache} -> {Map.put(schemas, slot, schema), cache, errors}
          {:error, error, cache} -> {schemas, cache, [error | errors]}
          :unbound -> {schemas, cache, errors}
        end
      end)

    # The type check (D-153): a slot outside the contract whose fields are read through a
    # scale has its schema read too, where it resolves; nothing requires it, so one that
    # does not is no fault, and that slot's types go unchecked.
    reads = Types.reads(map)
    {schemas, cache} = typed(reads, contract, entries, schemas, cache, describe)

    # A mark that keeps each identity's latest row needs the identity its feed declares
    # (spec/14 §7.3, D-168).
    following = following(map)

    {schemas, cache, unresolved} =
      followed(following, contract, entries, schemas, cache, describe)

    # A mapping by a field reads its declared values (spec/14 §7.4, D-194), where the slot
    # resolves; nothing requires it.
    mapped =
      map |> Coverage.mapped() |> Enum.map(fn {i, slot, _kind, field} -> {i, slot, field} end)

    {schemas, cache} = typed(mapped, contract, entries, schemas, cache, describe)

    # A mark with a tooltip shows its values' declared names (spec/14 §5.7, D-225), where its
    # slot resolves; nothing requires it.
    {schemas, cache} = typed(tipped(map), contract, entries, schemas, cache, describe)

    errors =
      errors ++
        missing(map, schemas) ++
        disagreements(slots, schemas) ++
        Types.faults(reads, schemas) ++
        unresolved ++ identity_required(following, schemas, unresolved)

    case Enum.sort_by(errors, &elem(&1, 0)) do
      [] ->
        {resolved, []} =
          map |> declared_colors(schemas) |> Template.walk(&value(&1, &2, schemas))

        {:ok, struct(Chart, resolved), %{schemas: schemas, versions: versions, cache: cache}}

      errors ->
        {:error, errors}
    end
  end

  # Each slot's feed — the pool name it bound to — and the source the pool gave it.
  defp entries(slots, pool) when is_map(slots) do
    for {slot, node} <- slots,
        {:ok, feed, source} <- [Template.entry(pool, slot, node)],
        into: %{},
        do: {slot, {feed, source}}
  end

  defp entries(_slots, _pool), do: %{}

  defp typed(reads, contract, entries, schemas, cache, describe) do
    slots = reads |> Enum.map(&elem(&1, 1)) |> Enum.uniq()

    for slot <- slots,
        not is_map_key(contract, slot),
        {:ok, entry} <- [Map.fetch(entries, slot)],
        reduce: {schemas, cache} do
      {schemas, cache} ->
        case schema(slot, entry, cache, describe) do
          {:ok, schema, cache} -> {Map.put(schemas, slot, schema), cache}
          {:error, _unrequired, cache} -> {schemas, cache}
        end
    end
  end

  # Every mark with a tooltip, with the slot it reads: `{i, slot}`.
  defp tipped(map) do
    case Map.get(map, :marks) do
      marks when is_list(marks) ->
        for {%{tooltip: %{}, data: data}, i} <- Enum.with_index(marks),
            slot = slot_of(data),
            slot != nil,
            do: {i, slot}

      _none ->
        []
    end
  end

  defp slot_of(%{source: slot}) when is_name(slot), do: slot
  defp slot_of(slot) when is_name(slot), do: slot
  defp slot_of(_data), do: nil

  # Every mark whose data has a `:window` step asking `latest`, with the slot it reads.
  defp following(map) do
    case Map.get(map, :marks) do
      marks when is_list(marks) ->
        for {%{data: %{source: slot, transforms: steps}}, i} <- Enum.with_index(marks),
            is_list(steps),
            Enum.any?(steps, &match?(%{op: :window, latest: true}, &1)),
            do: {i, slot}

      _none ->
        []
    end
  end

  # The schema of each slot a `latest` mark reads, resolved as a typed slot's is. A source
  # that is no delivery naming a version has no schema and declares nothing, which the
  # refusal says; a version that does not resolve is reported as the contract's is.
  defp followed(following, contract, entries, schemas, cache, describe) do
    slots = following |> Enum.map(&elem(&1, 1)) |> Enum.uniq()

    for slot <- slots,
        not is_map_key(schemas, slot),
        {:ok, entry} <- [Map.fetch(entries, slot)],
        reduce: {schemas, cache, []} do
      {schemas, cache, errors} ->
        case schema(slot, entry, cache, describe) do
          {:ok, schema, cache} ->
            {Map.put(schemas, slot, schema), cache, errors}

          {:error, {_path, {:no_schema, _slot}}, cache} ->
            {schemas, cache, errors}

          # The contract already reported it.
          {:error, _error, cache} when is_map_key(contract, slot) ->
            {schemas, cache, errors}

          {:error, error, cache} ->
            {schemas, cache, [error | errors]}
        end
    end
  end

  # `{:identity_required, slot}` at each `latest` mark over a slot whose schema declares
  # no identity, or that has none — never at one whose version did not resolve, which is
  # its own fault.
  defp identity_required(following, schemas, unresolved) do
    for {i, slot} <- following,
        not Enum.any?(unresolved, &match?({[:sources, ^slot], _reason}, &1)),
        declares_none?(Map.get(schemas, slot)),
        do: {[:marks, i], {:identity_required, slot}}
  end

  defp declares_none?(nil), do: true
  defp declares_none?(schema), do: Schema.identity(schema) == []

  # An unbound slot is binding's fault, reported there; it never reaches this step.
  defp schema(_slot, nil, _cache, _describe), do: :unbound

  defp schema(slot, {feed, %Delivery{schema: version}}, cache, describe)
       when is_binary(version) do
    case Cache.resolve(cache, feed, version, describe) do
      {:ok, schema, cache} -> {:ok, schema, cache}
      {:error, reason, cache} -> {:error, {[:sources, slot], reason}, cache}
    end
  end

  defp schema(slot, _entry, cache, _describe),
    do: {:error, {[:sources, slot], {:no_schema, slot}}, cache}

  # Every required attribute the bound schema does not give: at the requirement for a
  # `requires` entry, at the use for a fact.
  defp missing(map, schemas) do
    required =
      for {slot, %{requires: requires}} when is_map(requires) <- slots(map),
          {:ok, schema} <- [Map.fetch(schemas, slot)],
          {field, keys} when is_list(keys) <- requires,
          key <- keys,
          Fact.fetch(schema, field, key) == :error,
          do: {[:sources, slot, :requires, field], {:missing_attribute, slot, field, key}}

    read =
      for {path, %Fact{source: s, field: f, key: k}} <- uses(map),
          {:ok, schema} <- [Map.fetch(schemas, s)],
          Fact.fetch(schema, f, k) == :error,
          do: {path, {:missing_attribute, s, f, k}}

    required ++ read
  end

  # A field whose declared type the schema contradicts (spec/14 §7.4).
  defp disagreements(slots, schemas) when is_map(slots) do
    for {slot, schema} <- schemas,
        %{types: types} when is_map(types) <- [Map.get(slots, slot)],
        {field, declared} <- types,
        {:ok, described} <- [Schema.fetch(schema, field, :type)],
        described != declared,
        do: {[:sources, slot, :types, field], {:schema_type, field, declared, described}}
  end

  defp disagreements(_slots, _schemas), do: []

  # Declared colors written into a color range (spec/14 §4.3, §7.4, D-225): the `:ordinal`
  # `color` scale of each frame whose range is `:auto` and whose domain is a `:values` fact
  # over a field with a declared color takes, per declared value in order, its color, else
  # the palette slot of its 1-based position — the one `:auto` gives it. Read from the node
  # as written, before its facts are replaced; every other scale is left as it is.
  defp declared_colors(%{frames: frames} = map, schemas) when is_map(frames) do
    frames =
      Map.new(frames, fn
        {name, %{scales: scales} = frame} when is_map(scales) ->
          {name, %{frame | scales: Map.new(scales, &colored(&1, schemas))}}

        other ->
          other
      end)

    %{map | frames: frames}
  end

  defp declared_colors(map, _schemas), do: map

  defp colored({"color", %{kind: :ordinal, domain: %Fact{key: :values} = fact} = node}, schemas) do
    with :auto <- Map.get(node, :range, :auto),
         {:ok, colors} <- Fact.fetch(Map.fetch!(schemas, fact.source), fact.field, :colors) do
      {:ok, values} = Fact.fetch(Map.fetch!(schemas, fact.source), fact.field, :values)

      range =
        values
        |> Enum.with_index(1)
        |> Enum.map(fn {value, i} -> Map.get(colors, value, {:series, i}) end)

      {"color", Map.put(node, :range, range)}
    else
      _given_or_none -> {"color", node}
    end
  end

  defp colored(entry, _schemas), do: entry

  # Only a chart whose contract held reaches this: every fact's slot has a schema that
  # gives what its key reads (`Fact.fetch/3`). A field's `values` are its bare values, never
  # a value entry's map (spec/08 §10.1, D-224); `names` and `colors` its maps (D-225).
  defp value(%Fact{source: s, field: f, key: k}, _path, schemas) do
    {:ok, value} = Fact.fetch(Map.fetch!(schemas, s), f, k)
    {value, []}
  end

  defp value(other, _path, _schemas), do: {other, []}
end
