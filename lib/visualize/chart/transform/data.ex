defmodule Visualize.Chart.Transform.Data do
  @moduledoc false
  # The data steps of a mark's pipeline (spec/14 §5.4.1): `:bin` over `Visualize.Data.bin/2`,
  # `:stack` over `Visualize.Shape.Stack`, `:filter`, `:sum` and `:sort` over the rows
  # themselves.

  alias Visualize.Data
  alias Visualize.Data.{FFT, Table}
  alias Visualize.Shape.Stack

  @doc false
  @spec run(atom(), map(), [map()]) :: [map()]
  def run(:filter, node, rows), do: filter(node, rows)
  def run(:bin, node, rows), do: bin(node, rows)
  def run(:stack, node, rows), do: stack(node, rows)
  def run(:fold, node, rows), do: fold(node, rows)
  def run(:sum, node, rows), do: sum(node, rows)
  def run(:sort, node, rows), do: sort(node, rows)
  def run(:spectrum, node, rows), do: spectrum(node, rows)

  # -- filter -----------------------------------------------------------------------------

  # The rows whose reading of `field` passes `test` against `value` (D-68): a `nil`
  # reading is what `:present` and `:absent` test, and never passes an ordering.
  defp filter(node, rows) do
    test = Map.get(node, :test, :present)
    value = Map.get(node, :value)
    Enum.filter(rows, &passes?(test, Table.get(&1, node.field), value))
  end

  defp passes?(:present, reading, _value), do: reading != nil
  defp passes?(:absent, reading, _value), do: reading == nil
  defp passes?(:eq, reading, value), do: reading == value
  defp passes?(:ne, reading, value), do: reading != value
  defp passes?(_ordering, nil, _value), do: false
  defp passes?(:lt, reading, value), do: reading < value
  defp passes?(:lte, reading, value), do: reading <= value
  defp passes?(:gt, reading, value), do: reading > value
  defp passes?(:gte, reading, value), do: reading >= value

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

  # -- spectrum ---------------------------------------------------------------------------

  # A time series to its frequency spectrum (spec/14 §5.4.1, spec/08 §9, #375): the sample
  # interval from `every`, else the median gap of the time column, else 1; the rows with a
  # numeric reading of `field`, newest last, through `Visualize.Data.FFT.spectrum/3`.
  defp spectrum(node, rows) do
    as = Map.get(node, :as, [:frequency, :magnitude])
    {frequency, magnitude, phase} = spectrum_names(as)

    sampled = Enum.filter(rows, &is_number(Table.get(&1, node.field)))
    every = Map.get(node, :every) || median_gap(sampled, Map.get(node, :time)) || 1

    opts =
      [
        samples: Map.get(node, :samples),
        window: Map.get(node, :window, :hann),
        detrend: Map.get(node, :detrend, false)
      ]
      |> Enum.reject(fn {_k, v} -> v == nil end)

    sampled
    |> Enum.map(&Table.get(&1, node.field))
    |> FFT.spectrum(every, opts)
    |> Enum.map(fn line ->
      row = %{frequency => line.frequency, magnitude => line.magnitude}
      if phase, do: Map.put(row, phase, line.phase), else: row
    end)
  end

  defp spectrum_names([f, m]), do: {f, m, nil}
  defp spectrum_names([f, m, p | _]), do: {f, m, p}
  defp spectrum_names(name) when is_atom(name), do: {name, :magnitude, nil}

  # The median gap between consecutive readings of the time column: DateTimes in seconds,
  # numbers as they are; nil without a column or with fewer than two readings.
  defp median_gap(_rows, nil), do: nil

  defp median_gap(rows, time) do
    gaps =
      rows
      |> Enum.map(&Table.get(&1, time))
      |> Enum.reject(&is_nil/1)
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [a, b] -> gap(a, b) end)
      |> Enum.reject(&(is_nil(&1) or &1 <= 0))
      |> Enum.sort()

    case gaps do
      [] -> nil
      gaps -> Enum.at(gaps, div(length(gaps), 2))
    end
  end

  defp gap(%DateTime{} = a, %DateTime{} = b), do: DateTime.diff(b, a, :microsecond) / 1_000_000
  defp gap(a, b) when is_number(a) and is_number(b), do: b - a
  defp gap(_a, _b), do: nil

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

  # -- fold -------------------------------------------------------------------------------

  # Wide columns to long rows (spec/14 §5.4.1): one row per input row per listed column
  # the row has, the other columns carried, the column's name and value under `as`.
  defp fold(node, rows) do
    fields = node.fields
    {key, value} = as_pair(Map.get(node, :as, [:key, :value]))

    for row <- rows, field <- fields, (reading = Table.get(row, field)) != nil do
      row
      |> Map.drop(fields)
      |> Map.put(key, field)
      |> Map.put(value, reading)
    end
  end

  defp as_pair([key, value]) when is_atom(key) and is_atom(value), do: {key, value}

  defp as_pair(other) do
    raise ArgumentError,
          "a :fold step's as is a pair of names; got #{inspect(other)} (spec/14 §5.4)"
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
