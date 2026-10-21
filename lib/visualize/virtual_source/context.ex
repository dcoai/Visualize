defmodule Visualize.VirtualSource.Context do
  @moduledoc false
  # The context a virtual source's function of two arguments is called with (spec/08
  # §10.5.6, D-228): each input's schema in its wire form and its delivery's facts, and the
  # variables of the source's scope — the facts beside the rows, never a clock.
  #
  # Every name is a string (D-195): a field's, a description's key, a value entry's key, a
  # variable's. A value is the term the schema, the delivery or the variable holds, read
  # through `value`: a stored function's by the rule its literals follow, a host's as given.

  alias Visualize.Data.{Delivery, Schema}

  @typedoc "An input as the engine gathered it: its key, its delivery and its schema."
  @type input :: %{key: term(), delivery: Delivery.t(), schema: Schema.t()}

  @doc false
  # `new(inputs, vars, key, value)`: `key` gives an input's key as the first argument keys
  # it, `value` a value as the function reads it.
  @spec new([input()], map(), (term() -> term()), (term() -> term())) :: map()
  def new(inputs, vars, key, value) do
    %{
      "inputs" => Map.new(inputs, &{key.(&1.key), input(&1, value)}),
      "vars" => Map.new(vars, fn {name, var} -> {to_string(name), term(var, value)} end)
    }
  end

  defp input(%{delivery: %Delivery{} = delivery, schema: %Schema{} = schema}, value) do
    %{
      "schema" => schema(schema, value),
      "window" => term(delivery.window, value),
      "resolution" => term(delivery.resolution, value),
      "capped" => delivery.capped
    }
  end

  @doc false
  # A schema as a snapshot writes it (spec/15 §12.3), as a term: each field's name its
  # string, each description's keys their strings, a value entry a map of its keys' strings
  # (D-224), and every value read through `value`.
  @spec schema(Schema.t(), (term() -> term())) :: map()
  def schema(%Schema{fields: fields}, value) do
    Map.new(fields, fn {name, description} ->
      {to_string(name), Map.new(description, &description(&1, value))}
    end)
  end

  defp description({:values, values}, value) when is_list(values),
    do: {"values", Enum.map(values, &entry(&1, value))}

  defp description({key, term}, value), do: {to_string(key), term(term, value)}

  defp entry(entry, value) when is_map(entry) and not is_struct(entry),
    do: Map.new(entry, fn {key, term} -> {to_string(key), term(term, value)} end)

  defp entry(term, value), do: term(term, value)

  # A value within a term: a map's keys and values (a `status` maps values to roles), a
  # list's and a tuple's elements; a struct (an instant) is a value whole.
  defp term(map, value) when is_map(map) and not is_struct(map),
    do: Map.new(map, fn {k, v} -> {term(k, value), term(v, value)} end)

  defp term(list, value) when is_list(list), do: Enum.map(list, &term(&1, value))

  defp term(tuple, value) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> Enum.map(&term(&1, value)) |> List.to_tuple()

  defp term(other, value), do: value.(other)
end
