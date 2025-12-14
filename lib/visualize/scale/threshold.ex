defmodule Visualize.Scale.Threshold do
  @moduledoc """
  Threshold scale for mapping continuous values to discrete outputs.

  Unlike quantize scales which divide the domain into uniform segments,
  threshold scales use explicit breakpoints. This is useful when you have
  specific cutoff values (e.g., grades, risk levels, categories with
  defined boundaries).

  ## Examples

      # Map test scores to letter grades
      scale = Visualize.Scale.Threshold.new()
        |> Visualize.Scale.Threshold.domain([60, 70, 80, 90])
        |> Visualize.Scale.Threshold.range(["F", "D", "C", "B", "A"])

      Visualize.Scale.Threshold.scale(scale, 55)   # => "F"
      Visualize.Scale.Threshold.scale(scale, 65)   # => "D"
      Visualize.Scale.Threshold.scale(scale, 75)   # => "C"
      Visualize.Scale.Threshold.scale(scale, 85)   # => "B"
      Visualize.Scale.Threshold.scale(scale, 95)   # => "A"

      # Map values to colors for a choropleth
      scale = Visualize.Scale.Threshold.new()
        |> Visualize.Scale.Threshold.domain([100, 500, 1000, 5000])
        |> Visualize.Scale.Threshold.range(["#f7fbff", "#c6dbef", "#6baed6", "#2171b5", "#084594"])

      # Get the extent that maps to a specific range value
      Visualize.Scale.Threshold.invert_extent(scale, "#6baed6")  # => {500, 1000}

  ## Note

  The range must have exactly one more element than the domain.
  For n thresholds, you need n+1 output values.

  """

  defstruct domain: [],
            range: []

  @type t :: %__MODULE__{
          domain: [number()],
          range: [any()]
        }

  @doc "Creates a new threshold scale"
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc """
  Sets the domain (threshold values).

  The domain should be a sorted list of threshold values.
  Values below the first threshold map to the first range value.
  """
  @spec domain(t(), [number()]) :: t()
  def domain(%__MODULE__{} = scale, thresholds) when is_list(thresholds) do
    %{scale | domain: Enum.sort(thresholds)}
  end

  @doc """
  Sets the range (output values).

  The range must have exactly one more element than the domain.
  """
  @spec range(t(), [any()]) :: t()
  def range(%__MODULE__{} = scale, values) when is_list(values) do
    %{scale | range: values}
  end

  @doc """
  Maps a continuous value to a discrete range value.

  Uses binary search to efficiently find the appropriate bucket.
  """
  @spec scale(t(), number()) :: any()
  def scale(%__MODULE__{range: []} = _scale, _value), do: nil

  def scale(%__MODULE__{domain: thresholds, range: values}, value) do
    # Count how many thresholds the value is >= to
    index = binary_search(thresholds, value)
    Enum.at(values, index)
  end

  @doc """
  Returns the extent of domain values that map to a given range value.

  Returns `{lower_bound, upper_bound}` where:
  - lower_bound is the threshold at or below which values map to this range value
  - upper_bound is the threshold above which values no longer map to this range value

  For the first bucket, lower_bound is `:neg_infinity`.
  For the last bucket, upper_bound is `:infinity`.
  """
  @spec invert_extent(t(), any()) :: {number() | :neg_infinity, number() | :infinity} | nil
  def invert_extent(%__MODULE__{range: []} = _scale, _value), do: nil

  def invert_extent(%__MODULE__{domain: thresholds, range: values}, value) do
    case Enum.find_index(values, &(&1 == value)) do
      nil ->
        nil

      0 ->
        # First bucket: (-∞, first_threshold)
        {:neg_infinity, List.first(thresholds) || :infinity}

      index when index == length(values) - 1 ->
        # Last bucket: [last_threshold, ∞)
        {Enum.at(thresholds, index - 1), :infinity}

      index ->
        # Middle bucket: [threshold[index-1], threshold[index])
        {Enum.at(thresholds, index - 1), Enum.at(thresholds, index)}
    end
  end

  @doc """
  Returns the thresholds (same as domain).
  """
  @spec thresholds(t()) :: [number()]
  def thresholds(%__MODULE__{domain: thresholds}), do: thresholds

  @doc """
  Returns a copy of the scale with a new domain inferred from data.

  Creates thresholds that divide the data into n+1 approximately equal groups
  (similar to quantiles but with fixed bucket count).
  """
  @spec copy_with_domain(t(), [number()], non_neg_integer()) :: t()
  def copy_with_domain(%__MODULE__{} = scale, data, n) when n > 0 do
    sorted = Enum.sort(data)
    len = length(sorted)

    thresholds =
      if len == 0 do
        []
      else
        for i <- 1..n do
          index = trunc(i * len / (n + 1))
          Enum.at(sorted, min(index, len - 1))
        end
        |> Enum.uniq()
      end

    %{scale | domain: thresholds}
  end

  # Binary search to find the number of thresholds <= value
  defp binary_search(thresholds, value) do
    binary_search(thresholds, value, 0, length(thresholds))
  end

  defp binary_search(_thresholds, _value, lo, hi) when lo >= hi, do: lo

  defp binary_search(thresholds, value, lo, hi) do
    mid = div(lo + hi, 2)
    threshold = Enum.at(thresholds, mid)

    if value < threshold do
      binary_search(thresholds, value, lo, mid)
    else
      binary_search(thresholds, value, mid + 1, hi)
    end
  end
end
