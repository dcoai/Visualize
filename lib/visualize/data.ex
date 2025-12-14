defmodule Visualize.Data do
  import Kernel, except: [min: 2, max: 2]

  @moduledoc """
  Data transformation and statistical utilities.

  Provides functions for summarizing data, computing statistics,
  and transforming data for visualization.

  ## Examples

      data = [
        %{category: "A", value: 10},
        %{category: "A", value: 20},
        %{category: "B", value: 15}
      ]

      Visualize.Data.extent(data, & &1.value)
      # => {10, 20}

      Visualize.Data.group(data, & &1.category)
      # => %{"A" => [...], "B" => [...]}

  """

  @doc """
  Returns the minimum value.

  ## Examples

      Visualize.Data.min([3, 1, 4, 1, 5])
      # => 1

      Visualize.Data.min(data, & &1.value)
      # => minimum value from data

  """
  @spec min([any()], (any() -> number()) | nil) :: number() | nil
  def min(data, accessor \\ nil)
  def min([], _), do: nil

  def min(data, nil) do
    Enum.min(data)
  end

  def min(data, accessor) when is_function(accessor, 1) do
    data
    |> Enum.map(accessor)
    |> Enum.min()
  end

  @doc """
  Returns the maximum value.
  """
  @spec max([any()], (any() -> number()) | nil) :: number() | nil
  def max(data, accessor \\ nil)
  def max([], _), do: nil

  def max(data, nil) do
    Enum.max(data)
  end

  def max(data, accessor) when is_function(accessor, 1) do
    data
    |> Enum.map(accessor)
    |> Enum.max()
  end

  @doc """
  Returns {min, max} as a tuple.

  ## Examples

      Visualize.Data.extent([3, 1, 4, 1, 5])
      # => {1, 5}

      Visualize.Data.extent(data, & &1.value)
      # => {min_value, max_value}

  """
  @spec extent([any()], (any() -> number()) | nil) :: {number(), number()} | nil
  def extent(data, accessor \\ nil)
  def extent([], _), do: nil

  def extent(data, nil) do
    Enum.min_max(data)
  end

  def extent(data, accessor) when is_function(accessor, 1) do
    data
    |> Enum.map(accessor)
    |> Enum.min_max()
  end

  @doc """
  Returns the sum of values.
  """
  @spec sum([any()], (any() -> number()) | nil) :: number()
  def sum(data, accessor \\ nil)
  def sum([], _), do: 0

  def sum(data, nil) do
    Enum.sum(data)
  end

  def sum(data, accessor) when is_function(accessor, 1) do
    data
    |> Enum.map(accessor)
    |> Enum.sum()
  end

  @doc """
  Returns the arithmetic mean.
  """
  @spec mean([any()], (any() -> number()) | nil) :: float() | nil
  def mean(data, accessor \\ nil)
  def mean([], _), do: nil

  def mean(data, nil) do
    sum(data) / length(data)
  end

  def mean(data, accessor) when is_function(accessor, 1) do
    values = Enum.map(data, accessor)
    Enum.sum(values) / length(values)
  end

  @doc """
  Returns the median value.
  """
  @spec median([any()], (any() -> number()) | nil) :: number() | nil
  def median(data, accessor \\ nil)
  def median([], _), do: nil

  def median(data, accessor) do
    values =
      case accessor do
        nil -> data
        f -> Enum.map(data, f)
      end
      |> Enum.sort()

    n = length(values)
    mid = div(n, 2)

    if rem(n, 2) == 0 do
      (Enum.at(values, mid - 1) + Enum.at(values, mid)) / 2
    else
      Enum.at(values, mid)
    end
  end

  @doc """
  Returns the p-quantile value.

  `p` should be between 0 and 1.
  """
  @spec quantile([any()], float(), (any() -> number()) | nil) :: number() | nil
  def quantile(data, p, accessor \\ nil)
  def quantile([], _, _), do: nil

  def quantile(data, p, accessor) when p >= 0 and p <= 1 do
    values =
      case accessor do
        nil -> data
        f -> Enum.map(data, f)
      end
      |> Enum.sort()

    n = length(values)

    if n == 0 do
      nil
    else
      i = (n - 1) * p
      i0 = trunc(i)
      i1 = Kernel.min(i0 + 1, n - 1)
      v0 = Enum.at(values, i0)
      v1 = Enum.at(values, i1)
      v0 + (v1 - v0) * (i - i0)
    end
  end

  @doc """
  Returns the variance of values.
  """
  @spec variance([any()], (any() -> number()) | nil) :: float() | nil
  def variance(data, accessor \\ nil)
  def variance([], _), do: nil
  def variance([_], _), do: nil

  def variance(data, accessor) do
    values =
      case accessor do
        nil -> data
        f -> Enum.map(data, f)
      end

    m = Enum.sum(values) / length(values)
    n = length(values)

    values
    |> Enum.map(fn v -> (v - m) * (v - m) end)
    |> Enum.sum()
    |> Kernel./(n - 1)
  end

  @doc """
  Returns the standard deviation.
  """
  @spec deviation([any()], (any() -> number()) | nil) :: float() | nil
  def deviation(data, accessor \\ nil) do
    case variance(data, accessor) do
      nil -> nil
      v -> :math.sqrt(v)
    end
  end

  @doc """
  Groups data by a key function.

  Returns a map where keys are the result of the key function
  and values are lists of matching elements.

  ## Examples

      data = [%{cat: "A", val: 1}, %{cat: "A", val: 2}, %{cat: "B", val: 3}]
      Visualize.Data.group(data, & &1.cat)
      # => %{"A" => [%{cat: "A", val: 1}, %{cat: "A", val: 2}], "B" => [%{cat: "B", val: 3}]}

  """
  @spec group([any()], (any() -> any())) :: map()
  def group(data, key_fn) when is_function(key_fn, 1) do
    Enum.group_by(data, key_fn)
  end

  @doc """
  Groups data and applies a reducer to each group.

  ## Examples

      data = [%{cat: "A", val: 1}, %{cat: "A", val: 2}, %{cat: "B", val: 3}]
      Visualize.Data.rollup(data, & &1.cat, &length/1)
      # => %{"A" => 2, "B" => 1}

      Visualize.Data.rollup(data, & &1.cat, fn items ->
        Visualize.Data.sum(items, & &1.val)
      end)
      # => %{"A" => 3, "B" => 3}

  """
  @spec rollup([any()], (any() -> any()), ([any()] -> any())) :: map()
  def rollup(data, key_fn, reduce_fn) when is_function(key_fn, 1) and is_function(reduce_fn, 1) do
    data
    |> Enum.group_by(key_fn)
    |> Map.new(fn {k, v} -> {k, reduce_fn.(v)} end)
  end

  @doc """
  Creates histogram bins from continuous data.

  ## Options

  - `:thresholds` - number of bins or list of threshold values
  - `:domain` - [min, max] range to bin

  ## Examples

      Visualize.Data.bin([1, 2, 3, 4, 5, 6, 7, 8, 9, 10], thresholds: 5)
      # Returns list of bins with :x0, :x1, :values keys

  """
  @spec bin([number()], keyword()) :: [map()]
  def bin(data, opts \\ []) do
    return_empty_bins(data, opts) || compute_bins(data, opts)
  end

  defp return_empty_bins([], _opts), do: []
  defp return_empty_bins(_data, _opts), do: nil

  defp compute_bins(data, opts) do
    {d0, d1} =
      case Keyword.get(opts, :domain) do
        [min, max] -> {min, max}
        nil -> Enum.min_max(data)
      end

    thresholds =
      case Keyword.get(opts, :thresholds, 10) do
        n when is_integer(n) -> compute_thresholds(d0, d1, n)
        ts when is_list(ts) -> ts
      end

    # Create bins
    bins =
      ([d0] ++ thresholds ++ [d1])
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [x0, x1] ->
        %{x0: x0, x1: x1, values: []}
      end)

    # Assign values to bins
    Enum.reduce(data, bins, fn value, bins ->
      bin_index = find_bin_index(value, bins)

      if bin_index do
        List.update_at(bins, bin_index, fn bin ->
          %{bin | values: [value | bin.values]}
        end)
      else
        bins
      end
    end)
    |> Enum.map(fn bin ->
      %{bin | values: Enum.reverse(bin.values)}
    end)
  end

  defp compute_thresholds(d0, d1, count) do
    step = (d1 - d0) / count

    1..(count - 1)
    |> Enum.map(fn i -> d0 + i * step end)
  end

  defp find_bin_index(value, bins) do
    Enum.find_index(bins, fn %{x0: x0, x1: x1} ->
      value >= x0 and value < x1
    end) || if value == List.last(bins).x1 do
      length(bins) - 1
    end
  end

  @doc """
  Creates a cross product of two arrays.

  ## Examples

      Visualize.Data.cross([1, 2], ["a", "b"])
      # => [{1, "a"}, {1, "b"}, {2, "a"}, {2, "b"}]

  """
  @spec cross([any()], [any()], (any(), any() -> any()) | nil) :: [any()]
  def cross(a, b, combine_fn \\ nil)

  def cross(a, b, nil) do
    for x <- a, y <- b, do: {x, y}
  end

  def cross(a, b, combine_fn) when is_function(combine_fn, 2) do
    for x <- a, y <- b, do: combine_fn.(x, y)
  end

  @doc """
  Generates a range of numbers.

  ## Examples

      Visualize.Data.range(0, 5)
      # => [0, 1, 2, 3, 4]

      Visualize.Data.range(0, 1, 0.2)
      # => [0, 0.2, 0.4, 0.6, 0.8]

  """
  @spec range(number(), number(), number()) :: [number()]
  def range(start, stop, step \\ 1) when step != 0 do
    n = max(0, ceil((stop - start) / step))

    0..(n - 1)
    |> Enum.map(fn i -> start + i * step end)
  end

  @doc """
  Generates evenly-spaced tick values for a domain.

  Useful for creating axis ticks without a scale.
  """
  @spec ticks(number(), number(), integer()) :: [number()]
  def ticks(start, stop, count) when count > 0 do
    step = tick_step(start, stop, count)

    if step == 0 do
      [start]
    else
      start_tick = ceil(start / step) * step
      stop_tick = floor(stop / step) * step
      n = round((stop_tick - start_tick) / step) + 1

      0..(n - 1)
      |> Enum.map(fn i ->
        start_tick + i * step
        |> Float.round(10)
      end)
    end
  end

  defp tick_step(start, stop, count) do
    span = abs(stop - start)
    raw_step = span / max(0, count)

    power = floor(:math.log10(raw_step))
    error = raw_step / :math.pow(10, power)

    step =
      cond do
        error >= :math.sqrt(50) -> 10
        error >= :math.sqrt(10) -> 5
        error >= :math.sqrt(2) -> 2
        true -> 1
      end

    step * :math.pow(10, power)
  end

  @doc """
  Sorts data by an accessor function.
  """
  @spec sort([any()], (any() -> any()), :asc | :desc) :: [any()]
  def sort(data, accessor, order \\ :asc)

  def sort(data, accessor, :asc) when is_function(accessor, 1) do
    Enum.sort_by(data, accessor)
  end

  def sort(data, accessor, :desc) when is_function(accessor, 1) do
    Enum.sort_by(data, accessor, :desc)
  end

  @doc """
  Returns unique values by accessor.
  """
  @spec unique([any()], (any() -> any()) | nil) :: [any()]
  def unique(data, accessor \\ nil)

  def unique(data, nil) do
    Enum.uniq(data)
  end

  def unique(data, accessor) when is_function(accessor, 1) do
    Enum.uniq_by(data, accessor)
  end
end
