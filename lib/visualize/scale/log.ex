defmodule Visualize.Scale.Log do
  @moduledoc """
  A logarithmic scale for data with exponential distributions.

  Useful when data spans many orders of magnitude.
  """

  @behaviour Visualize.Scale.Behaviour

  alias Visualize.Data

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
  @impl true
  def domain(%__MODULE__{} = scale, [d0, d1]) when d0 > 0 and d1 > 0 do
    %{scale | domain: [d0, d1]}
  end

  @doc "Sets the range"
  @spec range(t(), [number()]) :: t()
  @impl true
  def range(%__MODULE__{} = scale, [r0, r1]) do
    %{scale | range: [r0, r1]}
  end

  @doc "Enables or disables clamping"
  @spec clamp(t(), boolean()) :: t()
  @impl true
  def clamp(%__MODULE__{} = scale, clamp?) do
    %{scale | clamp?: clamp?}
  end

  @doc "Applies the scale to a value"
  @spec apply(t(), number()) :: float()
  @impl true
  def apply(%__MODULE__{domain: [d0, d1], range: [r0, r1], base: base, clamp?: clamp?}, value)
      when value > 0 do
    log_d0 = log_base(d0, base)
    log_d1 = log_base(d1, base)
    log_v = log_base(value, base)

    t = Visualize.Scale.Behaviour.normalize(log_v, log_d0, log_d1)
    t = if clamp?, do: clamp_value(t, 0, 1), else: t

    r0 + t * (r1 - r0)
  end

  @doc "Inverts the scale"
  @spec invert(t(), number()) :: float()
  @impl true
  def invert(%__MODULE__{domain: [d0, d1], range: [r0, r1], base: base}, value) do
    log_d0 = log_base(d0, base)
    log_d1 = log_base(d1, base)

    t = Visualize.Scale.Behaviour.normalize(value, r0, r1)
    log_value = log_d0 + t * (log_d1 - log_d0)

    :math.pow(base, log_value)
  end

  @doc """
  Generates about `count` tick values, as d3-scale's log ticks do.

  When the domain spans fewer decades than `count` and the base is an integer, every
  `k · base^i` (`1 ≤ k < base`) inside the domain is a tick — the familiar
  1, 2, 3, … 9, 10, 20, 30 … — and, when that still yields fewer than `count / 2` ticks,
  linear ticks over the domain are used instead. Otherwise the exponents are thinned to
  about `count` nice values and mapped back through the base.
  """
  @spec ticks(t(), integer()) :: [number()]
  @impl true
  def ticks(%__MODULE__{domain: [d0, d1], base: base}, count) do
    {u, v, reverse?} = if d1 < d0, do: {d1, d0, true}, else: {d0, d1, false}
    i = log_base(u, base)
    j = log_base(v, base)
    n = max(count, 1)

    ticks =
      if integer?(base) and j - i < n do
        decade_ticks(u, v, trunc(Float.floor(i)), trunc(Float.ceil(j)), trunc(base), n)
      else
        Data.ticks(i, j, min(round(Float.ceil(j - i)), n))
        |> Enum.map(&pow(base, &1))
      end

    if reverse?, do: Enum.reverse(ticks), else: ticks
  end

  @doc "Extends domain to nice powers of the base"
  @spec nice(t()) :: t()
  @impl true
  def nice(%__MODULE__{domain: [d0, d1], base: base} = scale) do
    log_d0 = Float.floor(log_base(d0, base))
    log_d1 = Float.ceil(log_base(d1, base))

    %{scale | domain: [:math.pow(base, log_d0), :math.pow(base, log_d1)]}
  end

  @doc "Identity: a log scale has no padding"
  @impl true
  @spec padding(t(), number()) :: t()
  def padding(%__MODULE__{} = scale, _padding), do: scale

  @doc "Returns `0`: a log scale has no bandwidth"
  @impl true
  @spec bandwidth(t()) :: 0
  def bandwidth(%__MODULE__{}), do: 0

  # Exact for the common bases: `log(1.0e12) / log(10)` is 11.999999999999998, which would
  # lose the top decade from the ticks.
  defp log_base(value, 10), do: :math.log10(value)
  defp log_base(value, 2), do: :math.log2(value)
  defp log_base(value, base), do: :math.log(value) / :math.log(base)

  # Every k · base^i inside [u, v], falling back to linear ticks when too sparse.
  defp decade_ticks(u, v, i, j, base, n) do
    ticks =
      for exp <- i..j//1, k <- 1..(base - 1)//1, t = multiple(k, base, exp), t >= u, t <= v do
        t
      end

    if length(ticks) * 2 < n, do: Data.ticks(u, v, n), else: ticks
  end

  # k · base^exp; negative exponents divide so 0.3 is 3 / 10, not 3 · 0.1
  # (= 0.30000000000000004).
  defp multiple(k, base, exp) when exp < 0, do: k / :math.pow(base, -exp)
  defp multiple(k, base, exp), do: k * :math.pow(base, exp)

  defp pow(base, exp) when exp < 0, do: 1 / :math.pow(base, -exp)
  defp pow(base, exp), do: :math.pow(base, exp)

  defp integer?(base) when is_integer(base), do: true
  defp integer?(base), do: Float.floor(base) == base

  defp clamp_value(value, min, max) do
    value |> max(min) |> min(max)
  end
end
