defmodule Visualize.Chart.Builder.FormSchema do
  @moduledoc false
  # The design schema as the builder's form reads it (spec/14 §18.7, D-172). It is
  # `Visualize.Chart.Schema` but for one kind: the form edits a style in the flat keys every
  # earlier version wrote, one control per key in its group, until #655 gives the compound
  # parts a form of their own. A flat style the builder writes is the shape the design's
  # migration reads (`Visualize.Chart.Migration.canonical/1`), so what it writes renders,
  # validates and is stored in parts.

  alias Visualize.Chart.Schema

  @doc false
  @spec describe(Schema.kind()) :: [Schema.key_spec(), ...]
  # A node's `defaults` (spec/14 §3.8, #651) have no form until #655, as the parts have none:
  # the builder neither shows nor writes them, and a fragment that carries them keeps them.
  def describe(kind),
    do: kind |> form() |> Schema.describe() |> Enum.reject(&(&1.key == :defaults))

  @doc false
  @spec key(Schema.kind(), atom()) :: Schema.key_spec() | nil
  def key(_kind, :defaults), do: nil
  def key(kind, key), do: Schema.key(form(kind), key)

  @doc false
  @spec default(Schema.kind(), atom()) :: term()
  def default(kind, key), do: Schema.default(form(kind), key)

  defp form(:style), do: :flat_style
  defp form(kind), do: kind
end
