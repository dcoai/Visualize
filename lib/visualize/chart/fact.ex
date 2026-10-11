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

  ## Examples

      iex> Visualize.Chart.fact(:primary, :latency, :unit)
      %Visualize.Chart.Fact{source: :primary, field: :latency, key: :unit}

  """

  @enforce_keys [:source, :field, :key]
  defstruct [:source, :field, :key]

  @type t :: %__MODULE__{source: atom(), field: atom(), key: atom()}
end
