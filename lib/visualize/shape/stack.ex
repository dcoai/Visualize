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
      # Returns list of series, each with :key and :points
      # Points have :data, :y0 (baseline), :y1 (top)

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

  @type series :: %{
          key: any(),
          points: [%{data: any(), y0: number(), y1: number(), index: non_neg_integer()}]
        }

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
  - `:diverging` - Positive above zero, negative below
  - `:silhouette` - Center the stack around zero
  - `:wiggle` - Minimize wiggle (for streamgraphs)
  """
  @spec offset(t(), atom()) :: t()
  def offset(%__MODULE__{} = stack, offset)
      when offset in [:none, :expand, :diverging, :silhouette, :wiggle] do
    %{stack | offset: offset}
  end

  @doc """
  Generates the stacked series data.

  Returns a list of series maps, each containing:
  - `:key` - The series key
  - `:points` - List of points with `:data`, `:y0`, `:y1`, `:index`
  """
  @spec generate(t(), [map()]) :: [series()]
  def generate(%__MODULE__{keys: keys, value: value_fn, order: order, offset: offset}, data) do
    n = length(data)

    if n == 0 or Enum.empty?(keys) do
      []
    else
      # Extract values for each key and datum
      values =
        for key <- keys do
          for {d, i} <- Enum.with_index(data) do
            %{key: key, index: i, data: d, value: value_fn.(d, key)}
          end
        end

      # Apply ordering
      ordered_values = apply_order(values, order)

      # Compute stack positions
      stacked = compute_stack(ordered_values, n)

      # Apply offset
      apply_offset(stacked, offset, n)
    end
  end

  # Order the series
  defp apply_order(values, :none), do: values

  defp apply_order(values, :reverse), do: Enum.reverse(values)

  defp apply_order(values, :ascending) do
    Enum.sort_by(values, fn series ->
      Enum.reduce(series, 0, fn %{value: v}, acc -> acc + v end)
    end)
  end

  defp apply_order(values, :descending) do
    Enum.sort_by(
      values,
      fn series ->
        Enum.reduce(series, 0, fn %{value: v}, acc -> acc + v end)
      end,
      :desc
    )
  end

  defp apply_order(values, :insideout) do
    # Sort by sum, then interleave (largest in middle)
    sorted =
      Enum.sort_by(values, fn series ->
        Enum.reduce(series, 0, fn %{value: v}, acc -> acc + v end)
      end, :desc)

    interleave(sorted, [], [])
  end

  defp interleave([], top, bottom), do: Enum.reverse(top) ++ bottom

  defp interleave([a], top, bottom), do: Enum.reverse([a | top]) ++ bottom

  defp interleave([a, b | rest], top, bottom) do
    interleave(rest, [a | top], [b | bottom])
  end

  # Compute basic stack positions (y0 and y1)
  defp compute_stack(ordered_values, n) do
    # Initialize baselines to zero
    baselines = List.duplicate(0, n)

    {stacked, _} =
      Enum.map_reduce(ordered_values, baselines, fn series, baselines ->
        {points, new_baselines} =
          series
          |> Enum.zip(baselines)
          |> Enum.map(fn {%{key: key, index: i, data: d, value: v}, baseline} ->
            y0 = baseline
            y1 = baseline + v
            {%{key: key, index: i, data: d, y0: y0, y1: y1, value: v}, y1}
          end)
          |> Enum.unzip()

        series_result = %{
          key: hd(series).key,
          points: points
        }

        {series_result, new_baselines}
      end)

    stacked
  end

  # Apply offset transformations
  defp apply_offset(stacked, :none, _n), do: stacked

  defp apply_offset(stacked, :expand, n) do
    # Normalize each column to sum to 1
    totals =
      for i <- 0..(n - 1) do
        Enum.reduce(stacked, 0, fn series, acc ->
          point = Enum.at(series.points, i)
          acc + point.value
        end)
      end

    Enum.map(stacked, fn series ->
      points =
        series.points
        |> Enum.with_index()
        |> Enum.map(fn {point, i} ->
          total = Enum.at(totals, i)

          if total == 0 do
            %{point | y0: 0, y1: 0}
          else
            %{point | y0: point.y0 / total, y1: point.y1 / total}
          end
        end)

      %{series | points: points}
    end)
  end

  defp apply_offset(stacked, :diverging, _n) do
    # Positive values above zero, negative below
    # Re-compute with diverging logic
    Enum.map(stacked, fn series ->
      points =
        Enum.map(series.points, fn point ->
          if point.value >= 0 do
            point
          else
            %{point | y0: point.value, y1: 0}
          end
        end)

      %{series | points: points}
    end)
  end

  defp apply_offset(stacked, :silhouette, n) do
    # Center around zero
    totals =
      for i <- 0..(n - 1) do
        Enum.reduce(stacked, 0, fn series, acc ->
          point = Enum.at(series.points, i)
          acc + point.value
        end)
      end

    Enum.map(stacked, fn series ->
      points =
        series.points
        |> Enum.with_index()
        |> Enum.map(fn {point, i} ->
          offset = -Enum.at(totals, i) / 2
          %{point | y0: point.y0 + offset, y1: point.y1 + offset}
        end)

      %{series | points: points}
    end)
  end

  defp apply_offset(stacked, :wiggle, n) do
    # Minimize weighted wiggle (Streamgraph algorithm)
    # Simplified version
    if n < 2 do
      stacked
    else
      apply_offset(stacked, :silhouette, n)
    end
  end
end
