defmodule Visualize.Chart.Fact do
  @moduledoc """
  A fact of a feed's schema in a design (spec/14 §7.4, D-136).

  `Visualize.Chart.fact/3` builds one: the attribute `key` of `field` in the schema bound
  to slot `source` — a field's `label`, its `unit`, the `order` of its states. The term is
  allowed wherever a value can appear, and in a text as the hole
  `\#{fact(:source, :field, :key)}`; `Visualize.Chart.apply/2` replaces it by the
  attribute, as it replaces a variable by its value. Reading a fact is a requirement: a
  schema that does not give the attribute fails application, naming the slot, the field
  and the attribute.

  The keys are `keys/0`: the attributes of `Visualize.Data.Schema.attributes/0` and two
  derived from a field's declared values, `:names` and `:colors` (D-225). `fetch/3` says
  what a key gives.

  ## Examples

      iex> Visualize.Chart.fact(:primary, :latency, :unit)
      %Visualize.Chart.Fact{source: "primary", field: "latency", key: :unit}

  """

  alias Visualize.Data.Schema

  @enforce_keys [:source, :field, :key]
  defstruct [:source, :field, :key]

  @type t :: %__MODULE__{source: String.t(), field: String.t(), key: atom()}

  # The two facts derived from a field's declared values (spec/14 §7.4, D-225).
  @derived [:names, :colors]
  @keys Schema.attributes() ++ @derived

  @doc """
  The fact keys, in order: the description attributes, then `:names` and `:colors`
  (spec/14 §7.4, D-225).

      iex> Visualize.Chart.Fact.keys() |> Enum.take(-3)
      [:values, :names, :colors]
  """
  @spec keys() :: [atom(), ...]
  def keys, do: @keys

  @doc """
  What the fact key `key` gives `field` in `schema` (spec/14 §7.4, D-225): `{:ok, value}`,
  or `:error` when it gives nothing.

  An attribute is the description's as written, except `:values`, which is the bare
  values (`Visualize.Data.Schema.values/2`). `:names` and `:colors` are the maps of
  `Visualize.Data.Schema.value_names/2` and `value_colors/2`, given when not empty.

      iex> schema = Visualize.Data.Schema.new!(%{state: %{type: :category, values: [
      ...>   %{value: "ok", name: "OK"}, %{value: "down", color: "#c62828"}, "unknown"]}})
      iex> Visualize.Chart.Fact.fetch(schema, :state, :values)
      {:ok, ["ok", "down", "unknown"]}
      iex> Visualize.Chart.Fact.fetch(schema, "state", :names)
      {:ok, %{"ok" => "OK"}}
      iex> Visualize.Chart.Fact.fetch(schema, :state, :colors)
      {:ok, %{"down" => "#c62828"}}
      iex> Visualize.Chart.Fact.fetch(schema, :state, :unit)
      :error
  """
  @spec fetch(Schema.t(), Schema.name(), atom()) :: {:ok, term()} | :error
  def fetch(%Schema{} = schema, field, :values) do
    case Schema.values(schema, field) do
      nil -> :error
      values -> {:ok, values}
    end
  end

  def fetch(%Schema{} = schema, field, :names), do: given(Schema.value_names(schema, field))
  def fetch(%Schema{} = schema, field, :colors), do: given(Schema.value_colors(schema, field))

  def fetch(%Schema{} = schema, field, key) when is_atom(key),
    do: Schema.fetch(schema, field, key)

  defp given(map) when map_size(map) == 0, do: :error
  defp given(map), do: {:ok, map}
end
