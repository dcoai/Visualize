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

      Visualize.Scale.Quantize.apply(scale, 10)  # => "#f7fbff"
      Visualize.Scale.Quantize.apply(scale, 50)  # => "#6baed6"
      Visualize.Scale.Quantize.apply(scale, 90)  # => "#084594"

      # Get the thresholds
      Visualize.Scale.Quantize.thresholds(scale)  # => [20, 40, 60, 80]

  """

  @behaviour Visualize.Scale.Behaviour

  defstruct domain: [0, 1],
            range: []

  @type t :: %__MODULE__{
          domain: [number()],
          range: [any()]
        }

  @doc "Creates a new quantize scale"
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc "Sets the domain from a two-element list; a two-tuple is accepted and stored as a list"
  @impl true
  @spec domain(t(), [number()] | {number(), number()}) :: t()
  def domain(%__MODULE__{} = scale, [d0, d1]), do: %{scale | domain: [d0, d1]}
  def domain(%__MODULE__{} = scale, {d0, d1}), do: %{scale | domain: [d0, d1]}

  @doc "Sets the discrete output range"
  @impl true
  @spec range(t(), [any()]) :: t()
  def range(%__MODULE__{} = scale, values) when is_list(values) do
    %{scale | range: values}
  end

  @doc "Maps a continuous value to a discrete range value"
  @impl true
  @spec apply(t(), number()) :: any()
  def apply(%__MODULE__{range: []}, _value), do: nil

  def apply(%__MODULE__{domain: [d0, d1], range: range}, value) do
    n = length(range)

    # Normalize value to [0, 1], clamped
    t = if d1 == d0, do: 0, else: (value - d0) / (d1 - d0)
    t = t |> max(0) |> min(1)

    index = min(trunc(t * n), n - 1)
    Enum.at(range, index)
  end

  @doc "Alias of `apply/2`, kept for one release (spec/03 §1.3)"
  @spec scale(t(), number()) :: any()
  def scale(%__MODULE__{} = scale, value), do: __MODULE__.apply(scale, value)

  @doc """
  Returns the extent of values in the domain that map to a given range value.

  Returns {min, max} for the continuous values that map to the specified
  discrete value.
  """
  @spec invert_extent(t(), any()) :: {number(), number()} | nil
  def invert_extent(%__MODULE__{range: []}, _value), do: nil

  def invert_extent(%__MODULE__{domain: [d0, d1], range: range}, value) do
    n = length(range)

    case Enum.find_index(range, &(&1 == value)) do
      nil ->
        nil

      index ->
        step = (d1 - d0) / n
        {d0 + index * step, d0 + (index + 1) * step}
    end
  end

  @doc "Returns the threshold values that separate the buckets"
  @spec thresholds(t()) :: [number()]
  def thresholds(%__MODULE__{range: []}), do: []

  def thresholds(%__MODULE__{domain: [d0, d1], range: range}) do
    n = length(range)
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

  @doc "Returns `nil`: a quantize scale maps many values to one bucket"
  @impl true
  @spec invert(t(), any()) :: nil
  def invert(%__MODULE__{}, _value), do: nil

  @doc "Returns the bucket thresholds (`thresholds/1`); the count is ignored"
  @impl true
  @spec ticks(t(), integer()) :: [number()]
  def ticks(%__MODULE__{} = scale, _count), do: thresholds(scale)

  @doc "Identity"
  @impl true
  @spec nice(t()) :: t()
  def nice(%__MODULE__{} = scale), do: scale

  @doc "Identity: a quantize scale has no padding"
  @impl true
  @spec padding(t(), number()) :: t()
  def padding(%__MODULE__{} = scale, _padding), do: scale

  @doc "Returns `0`: a quantize scale has no bandwidth"
  @impl true
  @spec bandwidth(t()) :: 0
  def bandwidth(%__MODULE__{}), do: 0

  @doc "Identity: a quantize scale always clamps"
  @impl true
  @spec clamp(t(), boolean()) :: t()
  def clamp(%__MODULE__{} = scale, _clamp?), do: scale
end
