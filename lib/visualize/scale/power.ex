defmodule Visualize.Scale.Power do
  @moduledoc """
  Power scale for non-linear transformations.

  Maps a continuous input domain to a continuous output range using
  a power function. The exponent determines the curve shape:
  - exponent = 1: linear
  - exponent = 0.5: square root (sqrt)
  - exponent = 2: quadratic
  - exponent = 3: cubic

  ## Examples

      # Square root scale (good for area-based sizing)
      scale = Visualize.Scale.Power.new()
        |> Visualize.Scale.Power.exponent(0.5)
        |> Visualize.Scale.Power.domain([0, 100])
        |> Visualize.Scale.Power.range([0, 10])

      Visualize.Scale.Power.scale(scale, 25)  # => 5.0
      Visualize.Scale.Power.scale(scale, 100) # => 10.0

      # Quadratic scale
      scale = Visualize.Scale.Power.new()
        |> Visualize.Scale.Power.exponent(2)
        |> Visualize.Scale.Power.domain([0, 10])
        |> Visualize.Scale.Power.range([0, 100])

      Visualize.Scale.Power.scale(scale, 5)   # => 25.0

  """

  defstruct domain: {0, 1},
            range: {0, 1},
            exponent: 1,
            clamp?: false

  @type t :: %__MODULE__{
          domain: {number(), number()},
          range: {number(), number()},
          exponent: number(),
          clamp?: boolean()
        }

  @doc "Creates a new power scale with exponent 1 (linear)"
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc "Creates a square root scale (exponent 0.5)"
  @spec sqrt() :: t()
  def sqrt, do: %__MODULE__{exponent: 0.5}

  @doc "Sets the input domain"
  @spec domain(t(), [number()] | {number(), number()}) :: t()
  def domain(%__MODULE__{} = scale, [d0, d1]) do
    %{scale | domain: {d0, d1}}
  end

  def domain(%__MODULE__{} = scale, {d0, d1}) do
    %{scale | domain: {d0, d1}}
  end

  @doc "Sets the output range"
  @spec range(t(), [number()] | {number(), number()}) :: t()
  def range(%__MODULE__{} = scale, [r0, r1]) do
    %{scale | range: {r0, r1}}
  end

  def range(%__MODULE__{} = scale, {r0, r1}) do
    %{scale | range: {r0, r1}}
  end

  @doc "Sets the exponent for the power function"
  @spec exponent(t(), number()) :: t()
  def exponent(%__MODULE__{} = scale, exp) when is_number(exp) do
    %{scale | exponent: exp}
  end

  @doc "Enables or disables clamping to the range"
  @spec clamp(t(), boolean()) :: t()
  def clamp(%__MODULE__{} = scale, clamp?) do
    %{scale | clamp?: clamp?}
  end

  @doc "Maps a value from the domain to the range using power transformation"
  @spec scale(t(), number()) :: number()
  def scale(%__MODULE__{} = scale, value) do
    {d0, d1} = scale.domain
    {r0, r1} = scale.range
    exp = scale.exponent

    # Handle negative values for odd exponents
    sign = if value < 0, do: -1, else: 1
    abs_value = abs(value)
    abs_d0 = abs(d0)

    # Normalize to [0, 1] using power transformation
    d_range = pow_transform(abs(d1), exp) - pow_transform(abs_d0, exp)

    t = if d_range == 0 do
      0
    else
      (pow_transform(abs_value, exp) - pow_transform(abs_d0, exp)) / d_range
    end

    # Apply sign for negative values
    t = t * sign

    # Interpolate in range
    result = r0 + t * (r1 - r0)

    # Clamp if enabled
    if scale.clamp? do
      clamp_value(result, r0, r1)
    else
      result
    end
  end

  @doc "Maps a value from the range back to the domain (inverse)"
  @spec invert(t(), number()) :: number()
  def invert(%__MODULE__{} = scale, value) do
    {d0, d1} = scale.domain
    {r0, r1} = scale.range
    exp = scale.exponent

    # Normalize to [0, 1]
    t = if r1 == r0, do: 0, else: (value - r0) / (r1 - r0)

    # Apply inverse power transformation
    d_range_powered = pow_transform(abs(d1), exp) - pow_transform(abs(d0), exp)
    powered_value = pow_transform(abs(d0), exp) + t * d_range_powered

    # Inverse power
    inv_pow_transform(powered_value, exp)
  end

  @doc "Generates nice tick values for the scale"
  @spec ticks(t(), integer()) :: [number()]
  def ticks(%__MODULE__{} = scale, count \\ 10) do
    {d0, d1} = scale.domain
    # Use linear scale's tick generation
    linear = Visualize.Scale.Linear.new()
             |> Visualize.Scale.Linear.domain([d0, d1])
    Visualize.Scale.Linear.ticks(linear, count)
  end

  defp pow_transform(value, exponent) do
    :math.pow(value, exponent)
  end

  defp inv_pow_transform(value, exponent) do
    :math.pow(value, 1 / exponent)
  end

  defp clamp_value(value, r0, r1) when r0 <= r1 do
    value |> max(r0) |> min(r1)
  end

  defp clamp_value(value, r0, r1) do
    value |> max(r1) |> min(r0)
  end
end
