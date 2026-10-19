defmodule Examples.BoardDemo.Unreachable do
  @moduledoc """
  A feed whose source cannot be reached: it describes itself, and every fetch answers
  `{:error, :unreachable}`, which a cell draws as its "feed down" state (spec/15 §8.4).
  """
  @behaviour Visualize.Feed

  alias Visualize.Data.Schema

  defstruct [:schema]

  def new(fields), do: %__MODULE__{schema: Schema.new!(fields)}

  @impl true
  def describe(%__MODULE__{schema: schema}), do: {Schema.version(schema), schema, [:window]}

  @impl true
  def fetch(_feed, _window, _budget), do: {:error, :unreachable}
end
