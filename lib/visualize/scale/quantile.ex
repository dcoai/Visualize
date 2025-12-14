defmodule Visualize.Scale.Quantile do
  @moduledoc """
  Quantile scale for mapping sorted data to discrete buckets.

  Unlike quantize scales which divide the domain uniformly, quantile
  scales divide the data into buckets with equal numbers of samples.
  This is useful when you want each color/category to represent the
  same number of data points.

  ## Examples

      # Divide data into quartiles
      data = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 100]

      scale = Visualize.Scale.Quantile.new()
        |> Visualize.Scale.Quantile.domain(data)
        |> Visualize.Scale.Quantile.range(["Q1", "Q2", "Q3", "Q4"])

      Visualize.Scale.Quantile.scale(scale, 2)   # => "Q1"
      Visualize.Scale.Quantile.scale(scale, 5)   # => "Q2"
      Visualize.Scale.Quantile.scale(scale, 100) # => "Q4"

      # Get the quantile thresholds
      Visualize.Scale.Quantile.quantiles(scale)  # => [3.5, 6.0, 8.5]

  """

  defstruct domain: [],
            range: [],
            thresholds: []

  @type t :: %__MODULE__{
          domain: [number()],
          range: [any()],
          thresholds: [number()]
        }

  @doc "Creates a new quantile scale"
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc """
  Sets the domain from a list of sample values.

  The domain values will be sorted and used to compute quantile thresholds.
  """
  @spec domain(t(), [number()]) :: t()
  def domain(%__MODULE__{} = scale, values) when is_list(values) do
    sorted = Enum.sort(values)
    %{scale | domain: sorted}
    |> recompute_thresholds()
  end

  @doc "Sets the discrete output range"
  @spec range(t(), [any()]) :: t()
  def range(%__MODULE__{} = scale, values) when is_list(values) do
    %{scale | range: values}
    |> recompute_thresholds()
  end

  @doc "Maps a value to a discrete range value based on quantiles"
  @spec scale(t(), number()) :: any()
  def scale(%__MODULE__{range: []} = _scale, _value), do: nil
  def scale(%__MODULE__{thresholds: []} = scale, _value), do: List.first(scale.range)

  def scale(%__MODULE__{} = scale, value) do
    index = find_bucket_index(value, scale.thresholds, 0)
    Enum.at(scale.range, index)
  end

  @doc """
  Returns the extent of domain values that map to a given range value.

  Returns {min, max} for the values that map to the specified discrete value.
  """
  @spec invert_extent(t(), any()) :: {number(), number()} | nil
  def invert_extent(%__MODULE__{domain: []} = _scale, _value), do: nil
  def invert_extent(%__MODULE__{range: []} = _scale, _value), do: nil

  def invert_extent(%__MODULE__{} = scale, value) do
    case Enum.find_index(scale.range, &(&1 == value)) do
      nil ->
        nil

      index ->
        min_val = if index == 0 do
          List.first(scale.domain)
        else
          Enum.at(scale.thresholds, index - 1)
        end

        max_val = if index >= length(scale.thresholds) do
          List.last(scale.domain)
        else
          Enum.at(scale.thresholds, index)
        end

        {min_val, max_val}
    end
  end

  @doc "Returns the quantile thresholds"
  @spec quantiles(t()) :: [number()]
  def quantiles(%__MODULE__{} = scale) do
    scale.thresholds
  end

  defp recompute_thresholds(%__MODULE__{domain: []} = scale), do: scale
  defp recompute_thresholds(%__MODULE__{range: []} = scale), do: scale

  defp recompute_thresholds(%__MODULE__{} = scale) do
    n = length(scale.range)

    if n <= 1 do
      %{scale | thresholds: []}
    else
      # Compute quantile thresholds
      thresholds =
        for i <- 1..(n - 1) do
          p = i / n
          quantile_value(scale.domain, p)
        end

      %{scale | thresholds: thresholds}
    end
  end

  defp quantile_value(sorted_data, p) do
    n = length(sorted_data)

    if n == 0 do
      0
    else
      # Use linear interpolation between data points
      index = p * (n - 1)
      lower = trunc(index)
      upper = min(lower + 1, n - 1)
      fraction = index - lower

      lower_val = Enum.at(sorted_data, lower)
      upper_val = Enum.at(sorted_data, upper)

      lower_val + fraction * (upper_val - lower_val)
    end
  end

  defp find_bucket_index(value, [], _index), do: 0

  defp find_bucket_index(value, [threshold | rest], index) do
    if value < threshold do
      index
    else
      find_bucket_index(value, rest, index + 1)
    end
  end
end
