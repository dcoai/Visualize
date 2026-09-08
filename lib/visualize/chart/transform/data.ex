defmodule Visualize.Chart.Transform.Data do
  @moduledoc false
  # The data steps of a mark's pipeline (spec/14 §5.4.1): `:bin` over `Visualize.Data.bin/2`,
  # `:stack` over `Visualize.Shape.Stack`, `:sum` and `:sort` over the rows themselves.

  alias Visualize.Data
  alias Visualize.Data.Table
  alias Visualize.Shape.Stack

  @doc false
  @spec run(atom(), map(), [map()]) :: [map()]
  def run(:bin, node, rows), do: bin(node, rows)
  def run(:stack, node, rows), do: stack(node, rows)
  def run(:sum, node, rows), do: sum(node, rows)
  def run(:sort, node, rows), do: sort(node, rows)

  # -- bin --------------------------------------------------------------------------------

  defp bin(node, rows) do
    as = Map.get(node, :as, :count)
    values = column(rows, node.field)

    values
    |> Data.bin(thresholds: Map.get(node, :thresholds, 10))
    |> Enum.map(fn bin ->
      Map.put(%{x0: bin.x0, x1: bin.x1, y0: 0, values: bin.values}, as, length(bin.values))
    end)
  end

  # -- stack ------------------------------------------------------------------------------

  defp stack(node, rows) do
    keys = node.fields
    {stacked_keys, order} = order(Map.get(node, :order, :none), keys, rows)

    series =
      Stack.new()
      |> Stack.keys(stacked_keys)
      |> Stack.order(order)
      |> Stack.offset(Map.get(node, :offset, :none))
      |> Stack.generate(rows)

    by_key = Map.new(series, &{&1.key, &1})

    for key <- keys, s = Map.get(by_key, key), s != nil, point <- s.points do
      Map.merge(point.data, %{
        key: key,
        series: s.index,
        value: point.value,
        y0: point.y0,
        y1: point.y1
      })
    end
  end

  defp order(:inside_out, keys, _rows), do: {keys, :insideout}

  # d3's stackOrderAppearance: series in ascending order of the index of their peak.
  defp order(:appearance, keys, rows) do
    {Enum.sort_by(keys, &peak(rows, &1)), :none}
  end

  defp order(order, keys, _rows), do: {keys, order}

  defp peak(rows, key) do
    rows
    |> Enum.map(&(Table.get(&1, key) || 0))
    |> Enum.with_index()
    |> Enum.max_by(fn {v, _i} -> v end, fn -> {0, 0} end)
    |> elem(1)
  end

  # -- sum --------------------------------------------------------------------------------

  defp sum(node, rows) do
    as = Map.get(node, :as, :sum)

    case Map.get(node, :by) do
      nil ->
        [%{as => total(rows, node.field)}]

      by ->
        rows
        |> Enum.map(&Table.get(&1, by))
        |> Enum.uniq()
        |> Enum.map(fn group ->
          members = Enum.filter(rows, &(Table.get(&1, by) == group))
          %{by => group, as => total(members, node.field)}
        end)
    end
  end

  defp total(rows, field), do: rows |> column(field) |> Enum.sum()

  # -- sort -------------------------------------------------------------------------------

  defp sort(node, rows) do
    direction = if Map.get(node, :order, :ascending) == :descending, do: :desc, else: :asc
    Enum.sort_by(rows, &Table.get(&1, node.field), direction)
  end

  defp column(rows, field), do: rows |> Enum.map(&Table.get(&1, field)) |> Enum.reject(&is_nil/1)
end
