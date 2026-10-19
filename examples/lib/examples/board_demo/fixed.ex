defmodule Examples.BoardDemo.Fixed do
  @moduledoc "A feed that always answers the same rows: a design's constant slot, such as a dial's track."
  @behaviour Visualize.Feed

  alias Visualize.Data.{Delivery, Schema}

  defstruct [:rows, :schema]

  def new(rows, fields), do: %__MODULE__{rows: rows, schema: Schema.new!(fields)}

  @impl true
  def describe(%__MODULE__{schema: schema}), do: {Schema.version(schema), schema, []}

  @impl true
  def fetch(%__MODULE__{rows: rows, schema: schema}, _window, _budget),
    do: {:ok, Delivery.new(rows, schema: Schema.version(schema))}
end
