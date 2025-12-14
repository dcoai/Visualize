defmodule Visualize.Scale do
  @moduledoc """
  Scale functions that map from a data domain to a visual range.

  Scales are the fundamental building blocks for encoding data visually.
  They map abstract data values (the domain) to visual variables (the range)
  such as position, length, or color.

  ## Scale Types

  ### Continuous
  - `linear/0` - Continuous linear mapping
  - `log/0` - Logarithmic scale
  - `power/0` - Power/polynomial scale
  - `sqrt/0` - Square root scale (power with exponent 0.5)
  - `symlog/0` - Symmetric log (handles zero and negatives)
  - `time/0` - DateTime scale

  ### Discrete
  - `ordinal/0` - Discrete categorical mapping
  - `band/0` - Discrete with bandwidth (for bar charts)
  - `quantize/0` - Continuous to discrete (uniform buckets)
  - `quantile/0` - Continuous to discrete (equal-count buckets)

  ## Examples

      # Linear scale
      scale = Visualize.Scale.linear()
        |> Visualize.Scale.domain([0, 100])
        |> Visualize.Scale.range([0, 500])

      Visualize.Scale.apply(scale, 50)  # => 250.0

      # Band scale for bar charts
      scale = Visualize.Scale.band()
        |> Visualize.Scale.domain(["A", "B", "C"])
        |> Visualize.Scale.range([0, 300])
        |> Visualize.Scale.padding(0.1)

      Visualize.Scale.apply(scale, "B")  # => 105.0
      Visualize.Scale.bandwidth(scale)   # => 90.0

  """

  alias Visualize.Scale.{Linear, Log, Power, Symlog, Time, Ordinal, Band, Quantize, Quantile, Color}

  @doc "Creates a linear scale"
  defdelegate linear(), to: Linear, as: :new

  @doc "Creates a logarithmic scale"
  defdelegate log(base \\ 10), to: Log, as: :new

  @doc "Creates a power scale"
  defdelegate power(), to: Power, as: :new

  @doc "Creates a square root scale (power with exponent 0.5)"
  defdelegate sqrt(), to: Power, as: :sqrt

  @doc "Creates a symmetric log scale (handles zero and negatives)"
  defdelegate symlog(), to: Symlog, as: :new

  @doc "Creates a time scale"
  defdelegate time(), to: Time, as: :new

  @doc "Creates an ordinal scale"
  defdelegate ordinal(), to: Ordinal, as: :new

  @doc "Creates a band scale"
  defdelegate band(), to: Band, as: :new

  @doc "Creates a quantize scale (continuous to discrete, uniform buckets)"
  defdelegate quantize(), to: Quantize, as: :new

  @doc "Creates a quantile scale (continuous to discrete, equal-count buckets)"
  defdelegate quantile(), to: Quantile, as: :new

  @doc "Creates a sequential color scale"
  defdelegate sequential(interpolator), to: Color, as: :sequential

  @doc "Creates a diverging color scale"
  defdelegate diverging(interpolator), to: Color, as: :diverging

  @doc """
  Sets the input domain for the scale.

  For continuous scales, domain is [min, max].
  For ordinal/band scales, domain is a list of categories.
  """
  @spec domain(struct(), [any()]) :: struct()
  def domain(scale, domain_values) do
    scale.__struct__.domain(scale, domain_values)
  end

  @doc """
  Sets the output range for the scale.

  For position scales, typically [0, width] or [height, 0].
  For color scales, a list of colors.
  """
  @spec range(struct(), [any()]) :: struct()
  def range(scale, range_values) do
    scale.__struct__.range(scale, range_values)
  end

  @doc """
  Applies the scale to transform a domain value to a range value.
  """
  @spec apply(struct(), any()) :: any()
  def apply(scale, value) do
    scale.__struct__.apply(scale, value)
  end

  @doc """
  Inverts the scale to get a domain value from a range value.

  Only supported by continuous scales.
  """
  @spec invert(struct(), number()) :: any()
  def invert(scale, value) do
    scale.__struct__.invert(scale, value)
  end

  @doc """
  Returns nice round tick values for the scale.
  """
  @spec ticks(struct(), integer()) :: [any()]
  def ticks(scale, count \\ 10) do
    scale.__struct__.ticks(scale, count)
  end

  @doc """
  Extends the domain to nice round values.
  """
  @spec nice(struct()) :: struct()
  def nice(scale) do
    scale.__struct__.nice(scale)
  end

  @doc """
  Sets padding for band scales.
  """
  @spec padding(struct(), number()) :: struct()
  def padding(scale, padding) do
    scale.__struct__.padding(scale, padding)
  end

  @doc """
  Returns the bandwidth for band scales.
  """
  @spec bandwidth(struct()) :: number()
  def bandwidth(scale) do
    scale.__struct__.bandwidth(scale)
  end

  @doc """
  Clamps output to the range bounds.
  """
  @spec clamp(struct(), boolean()) :: struct()
  def clamp(scale, clamp?) do
    scale.__struct__.clamp(scale, clamp?)
  end
end
