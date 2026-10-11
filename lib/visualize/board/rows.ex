defmodule Visualize.Board.Rows do
  @moduledoc """
  A cell's rows placed by their timestamp, with a break in every gap (spec/15 §8.5,
  D-146).

  The board's monitor already holds each feed's rows in time order (spec/08 §11.4); a
  cell places them once more, so a delivery handed to it in any order is drawn in order,
  and then reads the schema's `continuity` (spec/08 §10.1, D-136): where two consecutive
  readings of one series are further apart in time than a field's `continuity`, a
  **break row** — the earlier row with that field `nil` — is put between them. A line or
  an area over the field breaks at a datum its scale cannot place (spec/14 §5.6), so a
  gap in the data is drawn as a gap, never as a straight line across it.

  ## Examples

      iex> alias Visualize.Data.{Delivery, Schema}
      iex> schema = Schema.new!(%{t: %{type: :time}, v: %{type: :number, continuity: 5}})
      iex> rows = [%{t: 12, v: 3}, %{t: 0, v: 1}, %{t: 2, v: 2}]
      iex> Visualize.Board.Rows.place(Delivery.new(rows), schema).rows
      [%{t: 0, v: 1}, %{t: 2, v: 2}, %{t: 2, v: nil}, %{t: 12, v: 3}]

  """

  alias Visualize.Data.{Delivery, Schema, Table}
  alias Visualize.Feed
  alias Visualize.Feed.Window

  @doc """
  The delivery with its rows in time order — a stable sort, so rows that tie keep their
  order — and a break row in every gap wider than a field's `continuity`, series by
  series, a series being the rows that share every `:category` field. A schema with no
  time field, or `nil`, leaves the rows as they are.
  """
  @spec place(Delivery.t(), Schema.t() | nil) :: Delivery.t()
  def place(%Delivery{} = delivery, nil), do: %{delivery | rows: Table.rows(delivery)}

  def place(%Delivery{} = delivery, %Schema{fields: fields} = schema) do
    rows = Table.rows(delivery)

    case Feed.time_field(schema) do
      nil ->
        %{delivery | rows: rows}

      time ->
        rows = Enum.sort_by(rows, &place(Table.get(&1, time)), &not_after?/2)
        gaps = for {name, %{continuity: c}} <- fields, name != time, do: {name, c}
        categories = for {name, %{type: :category}} <- fields, do: name
        %{delivery | rows: broken(rows, time, Enum.sort(gaps), Enum.sort(categories))}
    end
  end

  defp broken(rows, _time, [], _categories), do: rows

  defp broken(rows, time, gaps, categories) do
    {placed, _last} =
      Enum.flat_map_reduce(rows, %{}, fn row, last ->
        series = Enum.map(categories, &Table.get(row, &1))
        at = seconds(Table.get(row, time))

        breaks =
          case Map.fetch(last, series) do
            {:ok, {previous, was}} when is_number(at) and is_number(was) ->
              case for({field, c} <- gaps, at - was > c, do: field) do
                [] -> []
                fields -> [Enum.reduce(fields, previous, &put(&2, &1))]
              end

            _first_or_untimed ->
              []
          end

        {breaks ++ [row], Map.put(last, series, {row, at})}
      end)

    placed
  end

  # The field cleared by either spelling the row uses (`Visualize.Data.Table.get/2`).
  defp put(row, field) do
    cond do
      Map.has_key?(row, field) -> Map.put(row, field, nil)
      Map.has_key?(row, Atom.to_string(field)) -> Map.put(row, Atom.to_string(field), nil)
      true -> Map.put(row, field, nil)
    end
  end

  @doc """
  A time in seconds, for comparing a gap with `continuity` (spec/15 §8.5): a `DateTime`
  or a `NaiveDateTime` from its epoch, a `Date` by its days, and a number as itself — a
  time field has no unit (spec/08 §10.1), so a numeric clock is read as seconds. `nil`
  for anything else.

      iex> Visualize.Board.Rows.seconds(~U[1970-01-01 00:01:30Z])
      90.0
  """
  @spec seconds(term()) :: number() | nil
  def seconds(%DateTime{} = t), do: DateTime.to_unix(t, :microsecond) / 1_000_000
  def seconds(%NaiveDateTime{} = t), do: Window.position(t)
  def seconds(%Date{} = t), do: Date.to_gregorian_days(t) * 86_400
  def seconds(t) when is_number(t), do: t
  def seconds(_t), do: nil

  defp place(value), do: if(Window.time?(value), do: Window.position(value))

  defp not_after?(nil, _b), do: true
  defp not_after?(_a, nil), do: false
  defp not_after?(a, b), do: a <= b
end
