defmodule Visualize.Scale.Band do
  @moduledoc """
  A discrete scale that divides the range into uniform bands.

  Essential for bar charts where each category gets an equal-width band.
  """

  defstruct domain: [],
            range: [0, 1],
            padding_inner: 0,
            padding_outer: 0,
            align: 0.5,
            round?: false

  @type t :: %__MODULE__{
          domain: [any()],
          range: [number()],
          padding_inner: number(),
          padding_outer: number(),
          align: number(),
          round?: boolean()
        }

  @doc "Creates a new band scale"
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc "Sets the domain (list of categories)"
  @spec domain(t(), [any()]) :: t()
  def domain(%__MODULE__{} = scale, categories) when is_list(categories) do
    %{scale | domain: categories}
  end

  @doc "Sets the range"
  @spec range(t(), [number()]) :: t()
  def range(%__MODULE__{} = scale, [r0, r1]) do
    %{scale | range: [r0, r1]}
  end

  @doc "Sets both inner and outer padding (0 to 1)"
  @spec padding(t(), number()) :: t()
  def padding(%__MODULE__{} = scale, p) when p >= 0 and p < 1 do
    %{scale | padding_inner: p, padding_outer: p}
  end

  @doc "Sets inner padding between bands"
  @spec padding_inner(t(), number()) :: t()
  def padding_inner(%__MODULE__{} = scale, p) when p >= 0 and p < 1 do
    %{scale | padding_inner: p}
  end

  @doc "Sets outer padding at range edges"
  @spec padding_outer(t(), number()) :: t()
  def padding_outer(%__MODULE__{} = scale, p) when p >= 0 do
    %{scale | padding_outer: p}
  end

  @doc "Sets alignment (0 to 1) for distributing outer space"
  @spec align(t(), number()) :: t()
  def align(%__MODULE__{} = scale, a) when a >= 0 and a <= 1 do
    %{scale | align: a}
  end

  @doc "Enables rounding of output values"
  @spec round(t(), boolean()) :: t()
  def round(%__MODULE__{} = scale, round?) do
    %{scale | round?: round?}
  end

  @doc "Returns the start position for a category"
  @spec apply(t(), any()) :: number() | nil
  def apply(%__MODULE__{} = scale, value) do
    case Enum.find_index(scale.domain, &(&1 == value)) do
      nil -> nil
      index -> band_start(scale, index)
    end
  end

  @doc "Not applicable for band scales"
  @spec invert(t(), number()) :: nil
  def invert(%__MODULE__{}, _value), do: nil

  @doc "Returns the width of each band"
  @spec bandwidth(t()) :: number()
  def bandwidth(%__MODULE__{} = scale) do
    {band_width, _step, _start} = compute_band_params(scale)
    maybe_round(band_width, scale.round?)
  end

  @doc "Returns the step (band + padding)"
  @spec step(t()) :: number()
  def step(%__MODULE__{} = scale) do
    {_band_width, step, _start} = compute_band_params(scale)
    step
  end

  @doc "Returns the domain as ticks"
  @spec ticks(t(), integer()) :: [any()]
  def ticks(%__MODULE__{domain: domain}, _count), do: domain

  @doc "Returns the scale unchanged"
  @spec nice(t()) :: t()
  def nice(%__MODULE__{} = scale), do: scale

  # Not applicable
  def clamp(scale, _), do: scale

  defp band_start(scale, index) do
    {_band_width, step, start} = compute_band_params(scale)
    result = start + index * step
    maybe_round(result, scale.round?)
  end

  defp compute_band_params(%__MODULE__{
         domain: domain,
         range: [r0, r1],
         padding_inner: pi,
         padding_outer: po,
         align: align
       }) do
    n = length(domain)

    if n == 0 do
      {0, 0, r0}
    else
      span = r1 - r0
      # step = span / (n - pi + 2 * po)
      step = span / max(1, n - pi + 2 * po)
      band_width = step * (1 - pi)
      start = r0 + (span - step * (n - pi)) * align

      {band_width, step, start}
    end
  end

  defp maybe_round(value, true), do: Kernel.round(value)
  defp maybe_round(value, false), do: value
end
