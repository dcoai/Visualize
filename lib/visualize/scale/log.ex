defmodule Visualize.Scale.Log do
  @moduledoc """
  A logarithmic scale for data with exponential distributions.

  Useful when data spans many orders of magnitude.
  """

  defstruct domain: [1, 10],
            range: [0, 1],
            base: 10,
            clamp?: false

  @type t :: %__MODULE__{
          domain: [number()],
          range: [number()],
          base: number(),
          clamp?: boolean()
        }

  @doc "Creates a new log scale with optional base"
  @spec new(number()) :: t()
  def new(base \\ 10), do: %__MODULE__{base: base}

  @doc "Sets the domain (must be positive for log scale)"
  @spec domain(t(), [number()]) :: t()
  def domain(%__MODULE__{} = scale, [d0, d1]) when d0 > 0 and d1 > 0 do
    %{scale | domain: [d0, d1]}
  end

  @doc "Sets the range"
  @spec range(t(), [number()]) :: t()
  def range(%__MODULE__{} = scale, [r0, r1]) do
    %{scale | range: [r0, r1]}
  end

  @doc "Enables or disables clamping"
  @spec clamp(t(), boolean()) :: t()
  def clamp(%__MODULE__{} = scale, clamp?) do
    %{scale | clamp?: clamp?}
  end

  @doc "Applies the scale to a value"
  @spec apply(t(), number()) :: float()
  def apply(%__MODULE__{domain: [d0, d1], range: [r0, r1], base: base, clamp?: clamp?}, value)
      when value > 0 do
    log_d0 = log_base(d0, base)
    log_d1 = log_base(d1, base)
    log_v = log_base(value, base)

    t = (log_v - log_d0) / (log_d1 - log_d0)
    t = if clamp?, do: clamp_value(t, 0, 1), else: t

    r0 + t * (r1 - r0)
  end

  @doc "Inverts the scale"
  @spec invert(t(), number()) :: float()
  def invert(%__MODULE__{domain: [d0, d1], range: [r0, r1], base: base}, value) do
    log_d0 = log_base(d0, base)
    log_d1 = log_base(d1, base)

    t = (value - r0) / (r1 - r0)
    log_value = log_d0 + t * (log_d1 - log_d0)

    :math.pow(base, log_value)
  end

  @doc "Generates tick values at powers of the base"
  @spec ticks(t(), integer()) :: [number()]
  def ticks(%__MODULE__{domain: [d0, d1], base: base}, _count) do
    log_start = Float.ceil(log_base(d0, base))
    log_stop = Float.floor(log_base(d1, base))

    round(log_start)..round(log_stop)
    |> Enum.map(&:math.pow(base, &1))
  end

  @doc "Extends domain to nice powers of the base"
  @spec nice(t()) :: t()
  def nice(%__MODULE__{domain: [d0, d1], base: base} = scale) do
    log_d0 = Float.floor(log_base(d0, base))
    log_d1 = Float.ceil(log_base(d1, base))

    %{scale | domain: [:math.pow(base, log_d0), :math.pow(base, log_d1)]}
  end

  # Not applicable
  def padding(scale, _), do: scale
  def bandwidth(_), do: 0

  defp log_base(value, base) do
    :math.log(value) / :math.log(base)
  end

  defp clamp_value(value, min, max) do
    value |> max(min) |> min(max)
  end
end
