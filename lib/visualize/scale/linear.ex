defmodule Visualize.Scale.Linear do
  @moduledoc """
  A continuous linear scale that maps a numeric domain to a numeric range.

  Linear scales are the most common scale type, useful for quantitative data.
  """

  defstruct domain: [0, 1],
            range: [0, 1],
            clamp?: false

  @type t :: %__MODULE__{
          domain: [number()],
          range: [number()],
          clamp?: boolean()
        }

  @doc "Creates a new linear scale"
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc "Sets the domain"
  @spec domain(t(), [number()]) :: t()
  def domain(%__MODULE__{} = scale, [d0, d1]) do
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
  def apply(%__MODULE__{domain: [d0, d1], range: [r0, r1], clamp?: clamp?}, value) do
    # Normalize to [0, 1]
    t = (value - d0) / (d1 - d0)

    # Clamp if needed
    t = if clamp?, do: clamp_value(t, 0, 1), else: t

    # Interpolate to range
    r0 + t * (r1 - r0)
  end

  @doc "Inverts the scale"
  @spec invert(t(), number()) :: float()
  def invert(%__MODULE__{domain: [d0, d1], range: [r0, r1]}, value) do
    t = (value - r0) / (r1 - r0)
    d0 + t * (d1 - d0)
  end

  @doc "Generates tick values"
  @spec ticks(t(), integer()) :: [number()]
  def ticks(%__MODULE__{domain: [d0, d1]}, count) do
    tick_step = nice_step(d0, d1, count)
    start = Float.ceil(d0 / tick_step) * tick_step
    stop = Float.floor(d1 / tick_step) * tick_step

    # Generate ticks
    num_ticks = round((stop - start) / tick_step) + 1

    0..(num_ticks - 1)
    |> Enum.map(fn i -> start + i * tick_step end)
    |> Enum.map(&round_to_precision(&1, tick_step))
  end

  @doc "Extends domain to nice round values"
  @spec nice(t()) :: t()
  def nice(%__MODULE__{domain: [d0, d1]} = scale) do
    step = nice_step(d0, d1, 10)
    %{scale | domain: [Float.floor(d0 / step) * step, Float.ceil(d1 / step) * step]}
  end

  # Not applicable but required by protocol
  def padding(scale, _), do: scale
  def bandwidth(_), do: 0

  # Calculate a nice step size
  defp nice_step(start, stop, count) do
    span = abs(stop - start)
    raw_step = span / max(count, 1)

    # Find the order of magnitude
    magnitude = :math.pow(10, Float.floor(:math.log10(raw_step)))

    # Normalize to [1, 10)
    normalized = raw_step / magnitude

    # Choose a nice step: 1, 2, 5, or 10
    nice_factor =
      cond do
        normalized < 1.5 -> 1
        normalized < 3 -> 2
        normalized < 7 -> 5
        true -> 10
      end

    nice_factor * magnitude
  end

  defp round_to_precision(value, step) do
    precision = max(0, -Float.floor(:math.log10(step)))
    Float.round(value, round(precision))
  end

  defp clamp_value(value, min, max) do
    value |> max(min) |> min(max)
  end
end
