defmodule Visualize.Data.Delivery do
  @moduledoc """
  One answer of a feed: its rows, and the facts of this answer (spec/08 §10.4, D-136).

  `rows` is any source `Visualize.Data.Table.rows/1` reads — a row list, a column map, a
  tensor, a `Table.Reader` struct. Beside it, a handful of terms per delivery, never per
  row: the `window` actually served, the `resolution` of the rows, whether the feed
  `capped` the answer short of the window asked for, who reduced the rows to a budget
  (`reduced_by`), and the `schema` **version** the rows were produced under — never the
  schema itself, which `Visualize.Data.Schema.Cache` holds by version.

  A delivery is one more source shape: `Visualize.Data.Table.rows/1` reads it as the rows
  of the source it carries, and `Visualize.Chart.apply/2` and a compiled chart take one
  wherever they take a source.

  ## Examples

      iex> delivery = Visualize.Data.Delivery.new(%{t: [1, 2], v: [3, 4]}, window: [0, 10], schema: "ab12")
      iex> Visualize.Data.Table.rows(delivery)
      [%{t: 1, v: 3}, %{t: 2, v: 4}]
      iex> {delivery.capped, delivery.reduced_by}
      {false, nil}

  """

  alias Visualize.Data.Table

  @enforce_keys [:rows]
  defstruct [:rows, window: nil, resolution: nil, capped: false, reduced_by: nil, schema: nil]

  @type t :: %__MODULE__{
          rows: Table.source(),
          window: [term()] | nil,
          resolution: term(),
          capped: boolean(),
          reduced_by: :feed | :visualize | nil,
          schema: String.t() | nil
        }

  @fields [:window, :resolution, :capped, :reduced_by, :schema]

  @doc """
  A delivery of the rows with the given facts (spec/08 §10.4): `window`, `resolution`,
  `capped`, `reduced_by` and `schema`. Raises `ArgumentError` for a key that is not one
  of them or a value the field does not take.
  """
  @spec new(Table.source(), keyword()) :: t()
  def new(rows, facts \\ [])

  def new(%__MODULE__{}, _facts),
    do: raise(ArgumentError, "a delivery carries a source, not another delivery")

  def new(rows, facts) when is_list(facts) do
    facts = Keyword.validate!(facts, @fields)
    Enum.each(facts, &check/1)
    struct!(__MODULE__, [rows: rows] ++ facts)
  end

  @doc """
  The source a delivery carries; any other source as it is.

      iex> Visualize.Data.Delivery.source(Visualize.Data.Delivery.new([%{v: 1}]))
      [%{v: 1}]
      iex> Visualize.Data.Delivery.source([%{v: 1}])
      [%{v: 1}]
  """
  @spec source(t() | Table.source()) :: Table.source()
  def source(%__MODULE__{rows: rows}), do: rows
  def source(source), do: source

  defp check({:window, nil}), do: :ok
  defp check({:window, [_from, _to]}), do: :ok
  defp check({:resolution, _any}), do: :ok
  defp check({:capped, capped}) when is_boolean(capped), do: :ok
  defp check({:reduced_by, by}) when by in [nil, :feed, :visualize], do: :ok
  defp check({:schema, version}) when is_nil(version) or is_binary(version), do: :ok

  defp check({key, value}),
    do: raise(ArgumentError, "not a delivery's #{key}: #{inspect(value)} (spec/08 §10.4)")
end
