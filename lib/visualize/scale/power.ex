defmodule Visualize.Scale.Power do
  @moduledoc """
  Power scale for non-linear transformations.

  Maps a continuous input domain to a continuous output range using
  a power function. The exponent determines the curve shape:
  - exponent = 1: linear
  - exponent = 0.5: square root (sqrt)
  - exponent = 2: quadratic
  - exponent = 3: cubic

  The transform is D3's signed power `T(x) = sign(x) · |x|^e`, applied to the domain
  bounds and the value alike, so domains that include negative values map symmetrically
  and `invert/2` returns negative domain values.

  ## Examples

      # Square root scale (good for area-based sizing)
      scale = Visualize.Scale.Power.new()
        |> Visualize.Scale.Power.exponent(0.5)
        |> Visualize.Scale.Power.domain([0, 100])
        |> Visualize.Scale.Power.range([0, 10])

      Visualize.Scale.Power.apply(scale, 25)  # => 5.0
      Visualize.Scale.Power.apply(scale, 100) # => 10.0

      # Quadratic scale
      scale = Visualize.Scale.Power.new()
        |> Visualize.Scale.Power.exponent(2)
        |> Visualize.Scale.Power.domain([0, 10])
        |> Visualize.Scale.Power.range([0, 100])

      Visualize.Scale.Power.apply(scale, 5)   # => 25.0

  """

  @behaviour Visualize.Scale.Behaviour

  alias Visualize.Scale.Linear

  defstruct domain: [0, 1],
            range: [0, 1],
            exponent: 1,
            clamp?: false

  @type t :: %__MODULE__{
          domain: [number()],
          range: [number()],
          exponent: number(),
          clamp?: boolean()
        }

  @doc "Creates a new power scale with exponent 1 (linear)"
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc "Creates a square root scale (exponent 0.5)"
  @spec sqrt() :: t()
  def sqrt, do: %__MODULE__{exponent: 0.5}

  @doc "Sets the domain from a two-element list; a two-tuple is accepted and stored as a list"
  @impl true
  @spec domain(t(), [number()] | {number(), number()}) :: t()
  def domain(%__MODULE__{} = scale, [d0, d1]), do: %{scale | domain: [d0, d1]}
  def domain(%__MODULE__{} = scale, {d0, d1}), do: %{scale | domain: [d0, d1]}

  @doc "Sets the range from a two-element list; a two-tuple is accepted and stored as a list"
  @impl true
  @spec range(t(), [number()] | {number(), number()}) :: t()
  def range(%__MODULE__{} = scale, [r0, r1]), do: %{scale | range: [r0, r1]}
  def range(%__MODULE__{} = scale, {r0, r1}), do: %{scale | range: [r0, r1]}

  @doc "Sets the exponent for the power function"
  @spec exponent(t(), number()) :: t()
  def exponent(%__MODULE__{} = scale, exp) when is_number(exp) do
    %{scale | exponent: exp}
  end

  @doc "Enables or disables clamping of the output to the range"
  @impl true
  @spec clamp(t(), boolean()) :: t()
  def clamp(%__MODULE__{} = scale, clamp?) do
    %{scale | clamp?: clamp?}
  end

  @doc "Maps a value from the domain to the range using the signed power transform"
  @impl true
  @spec apply(t(), number()) :: number()
  def apply(%__MODULE__{domain: [d0, d1], range: [r0, r1], exponent: e} = scale, value) do
    t_d0 = transform(d0, e)
    t = Visualize.Scale.Behaviour.normalize(transform(value, e), t_d0, transform(d1, e))
    result = r0 + t * (r1 - r0)

    if scale.clamp?, do: clamp_value(result, r0, r1), else: result
  end

  @doc "Alias of `apply/2`, kept for one release (spec/03 §1.3)"
  @spec scale(t(), number()) :: number()
  def scale(%__MODULE__{} = scale, value), do: __MODULE__.apply(scale, value)

  @doc "Maps a value from the range back to the domain (inverse)"
  @impl true
  @spec invert(t(), number()) :: number()
  def invert(%__MODULE__{domain: [d0, d1], range: [r0, r1], exponent: e}, value) do
    t = Visualize.Scale.Behaviour.normalize(value, r0, r1)
    t_d0 = transform(d0, e)

    untransform(t_d0 + t * (transform(d1, e) - t_d0), e)
  end

  @doc "Generates nice tick values, linearly spaced over the domain"
  @impl true
  @spec ticks(t(), integer()) :: [number()]
  def ticks(%__MODULE__{domain: [d0, d1]}, count \\ 10) do
    Linear.ticks(%Linear{domain: [d0, d1]}, count)
  end

  @doc "Extends the domain to nice round values, as `Linear.nice/1` does"
  @impl true
  @spec nice(t()) :: t()
  def nice(%__MODULE__{domain: [d0, d1]} = scale) do
    %{scale | domain: Linear.nice(%Linear{domain: [d0, d1]}).domain}
  end

  @doc "Identity: a power scale has no padding"
  @impl true
  @spec padding(t(), number()) :: t()
  def padding(%__MODULE__{} = scale, _padding), do: scale

  @doc "Returns `0`: a power scale has no bandwidth"
  @impl true
  @spec bandwidth(t()) :: 0
  def bandwidth(%__MODULE__{}), do: 0

  # T(x) = sign(x) · |x|^e
  defp transform(x, e) when x < 0, do: -:math.pow(-x, e)
  defp transform(x, e), do: :math.pow(x, e)

  defp untransform(y, e) when y < 0, do: -:math.pow(-y, 1 / e)
  defp untransform(y, e), do: :math.pow(y, 1 / e)

  defp clamp_value(value, r0, r1) when r0 <= r1, do: value |> max(r0) |> min(r1)
  defp clamp_value(value, r0, r1), do: value |> max(r1) |> min(r0)
end
