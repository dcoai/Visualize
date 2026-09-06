defmodule Visualize.Scale.Band do
  @moduledoc """
  A discrete scale that divides the range into uniform bands.

  Essential for bar charts where each category gets an equal-width band. The band maths
  is d3-scale's: a descending range lays the bands out in reverse with positive `step`
  and `bandwidth`, and `round/2` floors the step and rounds the start and bandwidth so
  every position is an integer.
  """

  @behaviour Visualize.Scale.Behaviour

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
  @impl true
  @spec domain(t(), [any()]) :: t()
  def domain(%__MODULE__{} = scale, categories) when is_list(categories) do
    %{scale | domain: categories}
  end

  @doc "Sets the range"
  @impl true
  @spec range(t(), [number()]) :: t()
  def range(%__MODULE__{} = scale, [r0, r1]) do
    %{scale | range: [r0, r1]}
  end

  @doc "Sets both inner and outer padding (0 to 1)"
  @impl true
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

  @doc "Enables rounding: the step is floored, the start and bandwidth rounded"
  @spec round(t(), boolean()) :: t()
  def round(%__MODULE__{} = scale, round?) do
    %{scale | round?: round?}
  end

  @doc "Returns the start position for a category, or `nil` when it is not in the domain"
  @impl true
  @spec apply(t(), any()) :: number() | nil
  def apply(%__MODULE__{} = scale, value) do
    case Enum.find_index(scale.domain, &(&1 == value)) do
      nil -> nil
      index -> position(scale, index)
    end
  end

  @doc "Returns `nil`: a band scale is not invertible"
  @impl true
  @spec invert(t(), number()) :: nil
  def invert(%__MODULE__{}, _value), do: nil

  @doc "Returns the width of each band"
  @impl true
  @spec bandwidth(t()) :: number()
  def bandwidth(%__MODULE__{} = scale) do
    {_start, _step, bandwidth, _reverse?} = layout(scale)
    bandwidth
  end

  @doc "Returns the step (band + padding); floored when `round?`"
  @spec step(t()) :: number()
  def step(%__MODULE__{} = scale) do
    {_start, step, _bandwidth, _reverse?} = layout(scale)
    step
  end

  @doc "Returns the domain as ticks"
  @impl true
  @spec ticks(t(), integer()) :: [any()]
  def ticks(%__MODULE__{domain: domain}, _count), do: domain

  @doc "Identity"
  @impl true
  @spec nice(t()) :: t()
  def nice(%__MODULE__{} = scale), do: scale

  @doc "Identity: a band scale never extrapolates"
  @impl true
  @spec clamp(t(), boolean()) :: t()
  def clamp(%__MODULE__{} = scale, _clamp?), do: scale

  defp position(scale, index) do
    {start, step, _bandwidth, reverse?} = layout(scale)
    n = length(scale.domain)
    slot = if reverse?, do: n - 1 - index, else: index
    start + slot * step
  end

  # d3-scale's `rescale`: {start, step, bandwidth, reverse?}. `start` is the first band's
  # position along the ascending range; a descending range reverses the slot order.
  defp layout(%__MODULE__{domain: []} = scale) do
    [r0, _r1] = scale.range
    {r0, 0, 0, false}
  end

  defp layout(%__MODULE__{} = scale) do
    %{domain: domain, range: [r0, r1], padding_inner: pi, padding_outer: po, align: align} =
      scale

    n = length(domain)
    reverse? = r1 < r0
    {lo, hi} = if reverse?, do: {r1, r0}, else: {r0, r1}

    step = (hi - lo) / max(1, n - pi + po * 2)
    step = if scale.round?, do: Float.floor(step), else: step

    start = lo + (hi - lo - step * (n - pi)) * align
    bandwidth = step * (1 - pi)

    if scale.round? do
      {Float.round(start), step, Float.round(bandwidth), reverse?}
    else
      {start, step, bandwidth, reverse?}
    end
  end
end
