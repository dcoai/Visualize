defmodule Visualize.Scale.Quantize do
  @moduledoc """
  Quantize scale for mapping continuous values to discrete buckets.

  Divides the continuous domain into uniform segments, each mapped to
  a discrete value from the range. Useful for choropleth maps and
  heat maps where you want to bin continuous data into categories.

  ## Examples

      # Map values 0-100 to colors
      scale = Visualize.Scale.Quantize.new()
        |> Visualize.Scale.Quantize.domain([0, 100])
        |> Visualize.Scale.Quantize.range(["#f7fbff", "#c6dbef", "#6baed6", "#2171b5", "#084594"])

      Visualize.Scale.Quantize.scale(scale, 10)  # => "#f7fbff"
      Visualize.Scale.Quantize.scale(scale, 50)  # => "#6baed6"
      Visualize.Scale.Quantize.scale(scale, 90)  # => "#084594"

      # Get the thresholds
      Visualize.Scale.Quantize.thresholds(scale)  # => [20, 40, 60, 80]

  """

  defstruct domain: {0, 1},
            range: []

  @type t :: %__MODULE__{
          domain: {number(), number()},
          range: [any()]
        }

  @doc "Creates a new quantize scale"
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc "Sets the continuous input domain"
  @spec domain(t(), [number()] | {number(), number()}) :: t()
  def domain(%__MODULE__{} = scale, [d0, d1]) do
    %{scale | domain: {d0, d1}}
  end

  def domain(%__MODULE__{} = scale, {d0, d1}) do
    %{scale | domain: {d0, d1}}
  end

  @doc "Sets the discrete output range"
  @spec range(t(), [any()]) :: t()
  def range(%__MODULE__{} = scale, values) when is_list(values) do
    %{scale | range: values}
  end

  @doc "Maps a continuous value to a discrete range value"
  @spec scale(t(), number()) :: any()
  def scale(%__MODULE__{range: []} = _scale, _value), do: nil

  def scale(%__MODULE__{} = scale, value) do
    {d0, d1} = scale.domain
    n = length(scale.range)

    # Normalize value to [0, 1]
    t = if d1 == d0, do: 0, else: (value - d0) / (d1 - d0)

    # Clamp to [0, 1]
    t = t |> max(0) |> min(1)

    # Find bucket index
    index = trunc(t * n)
    index = min(index, n - 1)

    Enum.at(scale.range, index)
  end

  @doc """
  Returns the extent of values in the domain that map to a given range value.

  Returns {min, max} for the continuous values that map to the specified
  discrete value.
  """
  @spec invert_extent(t(), any()) :: {number(), number()} | nil
  def invert_extent(%__MODULE__{range: []} = _scale, _value), do: nil

  def invert_extent(%__MODULE__{} = scale, value) do
    {d0, d1} = scale.domain
    n = length(scale.range)

    case Enum.find_index(scale.range, &(&1 == value)) do
      nil ->
        nil

      index ->
        step = (d1 - d0) / n
        {d0 + index * step, d0 + (index + 1) * step}
    end
  end

  @doc "Returns the threshold values that separate the buckets"
  @spec thresholds(t()) :: [number()]
  def thresholds(%__MODULE__{range: []} = _scale), do: []

  def thresholds(%__MODULE__{} = scale) do
    {d0, d1} = scale.domain
    n = length(scale.range)
    step = (d1 - d0) / n

    for i <- 1..(n - 1) do
      d0 + i * step
    end
  end

  @doc "Returns the number of buckets"
  @spec bucket_count(t()) :: non_neg_integer()
  def bucket_count(%__MODULE__{} = scale) do
    length(scale.range)
  end
end
