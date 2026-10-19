defmodule Visualize.VirtualSource.Join do
  @moduledoc false
  # Joined fields (spec/15 §14.7, D-194): a slot's rows carry, for their own identity, the
  # fields of every per-identity virtual source whose identity input is what the slot
  # reads, each as `:"<id>.<field>"`, and the slot's schema describes them.

  alias Visualize.Data.{Delivery, Schema, Table}
  alias Visualize.VirtualSource
  alias Visualize.VirtualSource.Engine

  @doc false
  # For each bound slot, the sources joined into it: `{path, [{field, joined}]}`, the ones
  # the cell sees by id (spec/08 §10.5.9). The joined names are made here, once, when the
  # board starts: a bounded set of the host's definitions.
  @spec plan(Engine.t(), %{{atom(), atom()} => Engine.ref() | :error}) :: map()
  def plan(%Engine{} = engine, slot_refs) do
    joining =
      for {path, %VirtualSource{per: per} = source} <- engine.sources,
          per != nil,
          name = VirtualSource.identity_input(source),
          {_key, ^name, ref, _window} <- engine.inputs[path],
          do: {ref, path, source}

    Map.new(slot_refs, fn {{cell, _slot} = key, ref} ->
      joins =
        for {^ref, path, source} <- joining,
            Engine.resolve(engine, [cell], source.id) == {:source, path} do
          {path, fields(source)}
        end

      {key, Enum.sort(joins)}
    end)
  end

  defp fields(source) do
    identity = source.schema |> Schema.identity() |> Enum.map(&to_string/1)

    for {field, _description} <- source.schema.fields,
        to_string(field) not in identity,
        do: {field, String.to_atom("#{source.id}.#{field}")}
  end

  @doc false
  # The slot's delivery and schema with the joined fields, or as they were with no join.
  @spec join(Delivery.t() | nil, Schema.t() | nil, list(), Engine.t()) ::
          {Delivery.t() | nil, Schema.t() | nil}
  def join(delivery, schema, [], _engine), do: {delivery, schema}
  def join(nil, schema, _joins, _engine), do: {nil, schema}
  def join(delivery, nil, _joins, _engine), do: {delivery, nil}

  def join(%Delivery{} = delivery, %Schema{} = schema, joins, engine) do
    outputs = Engine.outputs(engine)

    indexes =
      for {path, fields} <- joins do
        source = Map.fetch!(engine.sources, path)

        index =
          case Map.get(outputs, path) do
            nil -> %{}
            output -> Map.new(output.rows, &{norm(Schema.identity(source.schema, &1)), &1})
          end

        {fields, index}
      end

    rows =
      delivery
      |> Delivery.source()
      |> Table.rows()
      |> Enum.map(fn row ->
        identity = norm(Schema.identity(schema, row))

        Enum.reduce(indexes, row, fn {fields, index}, row ->
          answer = Map.get(index, identity, %{})

          Enum.reduce(fields, row, fn {field, joined}, row ->
            Map.put(row, joined, Table.get(answer, field))
          end)
        end)
      end)

    schema = joined_schema(schema, joins, engine)
    {%{delivery | rows: rows, schema: Schema.version(schema)}, schema}
  end

  # The input's schema with each joined field described as the source's output does,
  # without identity (spec/15 §14.7).
  defp joined_schema(schema, joins, engine) do
    joined =
      for {path, fields} <- joins,
          source = Map.fetch!(engine.sources, path),
          {field, name} <- fields,
          {:ok, description} = Schema.fetch(source.schema, field),
          into: %{},
          do: {name, Map.drop(description, [:identity, :window])}

    Schema.new!(Map.merge(schema.fields, joined))
  end

  defp norm(identity) when is_map(identity),
    do: Map.new(identity, fn {field, value} -> {to_string(field), value} end)

  defp norm(identity), do: identity
end
