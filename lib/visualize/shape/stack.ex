defmodule Visualize.Shape.Stack do
  @moduledoc """
  Stack generator for creating stacked bar and area charts.

  Computes a baseline value for each datum, so you can stack layers
  of data on top of each other.

  ## Examples

      data = [
        %{month: "Jan", apples: 10, oranges: 20, bananas: 15},
        %{month: "Feb", apples: 15, oranges: 25, bananas: 10},
        %{month: "Mar", apples: 20, oranges: 15, bananas: 25}
      ]

      stack = Visualize.Shape.Stack.new()
        |> Visualize.Shape.Stack.keys([:apples, :oranges, :bananas])

      series = Visualize.Shape.Stack.generate(stack, data)
      # Returns one series per key, in key order, each with :key, :index (its position
      # in the stacking order) and :points. Points have :data, :y0 (baseline), :y1 (top).

  """

  defstruct keys: [],
            value: nil,
            order: :none,
            offset: :none

  @type t :: %__MODULE__{
          keys: [any()],
          value: (map(), any() -> number()) | nil,
          order: :none | :ascending | :descending | :reverse | :insideout,
          offset: :none | :expand | :diverging | :silhouette | :wiggle
        }

  @type point :: %{
          key: any(),
          index: non_neg_integer(),
          data: any(),
          value: number(),
          y0: number(),
          y1: number()
        }
  @type series :: %{key: any(), index: non_neg_integer(), points: [point()]}

  @doc "Creates a new stack generator"
  @spec new() :: t()
  def new do
    %__MODULE__{
      value: fn d, key -> Map.get(d, key, 0) end
    }
  end

  @doc """
  Sets the keys to stack.

  Keys determine the layers in the stack, typically field names.
  """
  @spec keys(t(), [any()]) :: t()
  def keys(%__MODULE__{} = stack, keys) when is_list(keys) do
    %{stack | keys: keys}
  end

  @doc """
  Sets the value accessor function.

  The function receives (datum, key) and returns a number.
  """
  @spec value(t(), (map(), any() -> number())) :: t()
  def value(%__MODULE__{} = stack, func) when is_function(func, 2) do
    %{stack | value: func}
  end

  @doc """
  Sets the stack order.

  - `:none` - Use key order (default)
  - `:ascending` - Smallest series on bottom
  - `:descending` - Largest series on bottom
  - `:reverse` - Reverse key order
  - `:insideout` - Larger series in middle (good for streamgraphs)
  """
  @spec order(t(), atom()) :: t()
  def order(%__MODULE__{} = stack, order)
      when order in [:none, :ascending, :descending, :reverse, :insideout] do
    %{stack | order: order}
  end

  @doc """
  Sets the stack offset.

  - `:none` - Zero baseline (default)
  - `:expand` - Normalize to 0-1 (100% stacked)
  - `:diverging` - Positive values stack up from zero, negative values stack down from zero
  - `:silhouette` - Center the stack around zero
  - `:wiggle` - Minimize weighted wiggle (for streamgraphs)
  """
  @spec offset(t(), atom()) :: t()
  def offset(%__MODULE__{} = stack, offset)
      when offset in [:none, :expand, :diverging, :silhouette, :wiggle] do
    %{stack | offset: offset}
  end

  @doc """
  Generates the stacked series data.

  Returns one series per key, **in key order**, each a map with:
  - `:key` - The series key
  - `:index` - The series' position in the stacking order (0 is the bottom)
  - `:points` - One point per datum with `:data`, `:value`, `:y0`, `:y1`, `:index`
  """
  @spec generate(t(), [map()]) :: [series()]
  def generate(%__MODULE__{keys: []}, _data), do: []
  def generate(%__MODULE__{}, []), do: []

  def generate(%__MODULE__{keys: keys, value: value_fn, order: order, offset: offset}, data) do
    # `series` is a tuple of series in key order; each series is a list of points with
    # `value` and provisional `y0 = 0`, `y1 = value`, as d3 initialises `[0, value]`.
    series =
      keys
      |> Enum.map(fn key ->
        points =
          data
          |> Enum.with_index()
          |> Enum.map(fn {d, j} ->
            v = value_fn.(d, key)
            %{key: key, index: j, data: d, value: v, y0: 0, y1: v}
          end)

        %{key: key, index: 0, points: points}
      end)
      |> List.to_tuple()

    # The stacking order is a permutation of key indexes (d3's `order(series)`).
    order_ix = stacking_order(series, order)

    series
    |> apply_offset(order_ix, offset, length(data))
    |> Tuple.to_list()
    |> Enum.with_index()
    |> Enum.map(fn {s, key_index} ->
      %{s | index: Enum.find_index(order_ix, &(&1 == key_index))}
    end)
  end

  # --- Order: a permutation of key indexes -------------------------------------------------

  defp stacking_order(series, :none), do: Enum.to_list(0..(tuple_size(series) - 1)//1)
  defp stacking_order(series, :reverse), do: Enum.reverse(stacking_order(series, :none))

  defp stacking_order(series, :ascending) do
    series |> stacking_order(:none) |> Enum.sort_by(&series_sum(series, &1))
  end

  defp stacking_order(series, :descending) do
    series |> stacking_order(:none) |> Enum.sort_by(&series_sum(series, &1), :desc)
  end

  defp stacking_order(series, :insideout) do
    # Sort by sum, then interleave (largest in middle)
    series |> stacking_order(:descending) |> interleave([], [])
  end

  defp series_sum(series, i) do
    series |> elem(i) |> Map.fetch!(:points) |> Enum.reduce(0, fn %{value: v}, acc -> acc + v end)
  end

  defp interleave([], top, bottom), do: Enum.reverse(top) ++ bottom
  defp interleave([a], top, bottom), do: Enum.reverse([a | top]) ++ bottom
  defp interleave([a, b | rest], top, bottom), do: interleave(rest, [a | top], [b | bottom])

  # --- Offsets ------------------------------------------------------------------------------

  # `:none` stacks each series in stacking order on the previous one's top; the bottom
  # series keeps whatever `y0` the offset set (0 unless an offset moved the baseline).
  defp apply_offset(series, order_ix, :none, _n), do: stack_none(series, order_ix)

  defp apply_offset(series, order_ix, :expand, n) do
    totals = column_totals(series, n)

    series
    |> map_points(fn %{index: j, value: v} = p ->
      total = elem(totals, j)
      v = if total == 0, do: 0, else: v / total
      %{p | value: v, y0: 0, y1: v}
    end)
    |> stack_none(order_ix)
  end

  defp apply_offset(series, order_ix, :silhouette, n) do
    totals = column_totals(series, n)
    baselines = Enum.map(0..(n - 1)//1, fn j -> -elem(totals, j) / 2 end)

    series
    |> with_baselines(hd(order_ix), baselines)
    |> stack_none(order_ix)
  end

  # d3's `stackOffsetDiverging`: positives accumulate upward from zero, negatives downward,
  # each independently of the other; a zero value sits at the origin.
  defp apply_offset(series, order_ix, :diverging, n) do
    Enum.reduce(0..(n - 1)//1, series, fn j, series ->
      {series, _yp, _yn} =
        Enum.reduce(order_ix, {series, 0, 0}, fn i, {series, yp, yn} ->
          s = elem(series, i)
          p = Enum.at(s.points, j)

          {p, yp, yn} =
            cond do
              p.value > 0 -> {%{p | y0: yp, y1: yp + p.value}, yp + p.value, yn}
              p.value < 0 -> {%{p | y1: yn, y0: yn + p.value}, yp, yn + p.value}
              true -> {%{p | y0: 0, y1: 0}, yp, yn}
            end

          {put_elem(series, i, %{s | points: List.replace_at(s.points, j, p)}), yp, yn}
        end)

      series
    end)
  end

  # d3's `stackOffsetWiggle` (Byron & Wattenberg's streamgraph baseline): the baseline
  # moves between columns so as to minimise the weighted change in slope of the layers.
  defp apply_offset(series, order_ix, :wiggle, n) do
    values =
      order_ix
      |> Enum.map(fn i ->
        series |> elem(i) |> Map.fetch!(:points) |> Enum.map(& &1.value) |> List.to_tuple()
      end)
      |> List.to_tuple()

    m = tuple_size(values)

    {baselines, y} =
      Enum.reduce(1..(n - 1)//1, {[], 0}, fn j, {acc, y} ->
        {s1, s2} =
          Enum.reduce(0..(m - 1)//1, {0, 0}, fn i, {s1, s2} ->
            sij0 = elem(elem(values, i), j)
            sij1 = elem(elem(values, i), j - 1)

            s3 =
              Enum.reduce(0..(i - 1)//1, (sij0 - sij1) / 2, fn k, s3 ->
                s3 + (elem(elem(values, k), j) - elem(elem(values, k), j - 1))
              end)

            {s1 + sij0, s2 + s3 * sij0}
          end)

        y_next = if s1 == 0, do: y, else: y - s2 / s1
        {[y | acc], y_next}
      end)

    baselines = Enum.reverse([y | baselines])

    series
    |> with_baselines(hd(order_ix), baselines)
    |> stack_none(order_ix)
  end

  # Sets the bottom series' y0/y1 to the given per-column baselines.
  defp with_baselines(series, bottom_ix, baselines) do
    s = elem(series, bottom_ix)

    points =
      Enum.zip_with(s.points, baselines, fn p, b -> %{p | y0: b, y1: b + p.value} end)

    put_elem(series, bottom_ix, %{s | points: points})
  end

  # d3's `stackOffsetNone`.
  defp stack_none(series, [first | rest]) do
    {series, _} =
      Enum.reduce(rest, {series, first}, fn i, {series, prev_ix} ->
        prev = elem(series, prev_ix)
        s = elem(series, i)

        points =
          Enum.zip_with(s.points, prev.points, fn p, %{y1: base} ->
            %{p | y0: base, y1: base + p.value}
          end)

        {put_elem(series, i, %{s | points: points}), i}
      end)

    series
  end

  defp column_totals(series, n) do
    Enum.map(0..(n - 1)//1, fn j ->
      series
      |> Tuple.to_list()
      |> Enum.reduce(0, fn s, acc -> acc + Enum.at(s.points, j).value end)
    end)
    |> List.to_tuple()
  end

  defp map_points(series, fun) do
    series
    |> Tuple.to_list()
    |> Enum.map(fn s -> %{s | points: Enum.map(s.points, fun)} end)
    |> List.to_tuple()
  end
end
