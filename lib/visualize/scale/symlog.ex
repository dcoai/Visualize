defmodule Visualize.Scale.Symlog do
  @moduledoc """
  Symmetric log scale for data spanning orders of magnitude including zero.

  Unlike a regular log scale, symlog can handle zero and negative values.
  It's linear near zero and logarithmic for larger absolute values.

  The `constant` parameter controls the transition point between linear
  and logarithmic behavior.

  ## Examples

      # Scale that handles -1000 to 1000 including zero
      scale = Visualize.Scale.Symlog.new()
        |> Visualize.Scale.Symlog.domain([-1000, 1000])
        |> Visualize.Scale.Symlog.range([0, 400])

      Visualize.Scale.Symlog.apply(scale, 0)     # => 200.0 (center)
      Visualize.Scale.Symlog.apply(scale, 100)   # => ~300
      Visualize.Scale.Symlog.apply(scale, -100)  # => ~100

  ## Formula

  The transformation is: sign(x) * log1p(|x| / constant)

  """

  @behaviour Visualize.Scale.Behaviour

  alias Visualize.Scale.Linear

  defstruct domain: [-1, 1],
            range: [0, 1],
            constant: 1,
            clamp?: false

  @type t :: %__MODULE__{
          domain: [number()],
          range: [number()],
          constant: number(),
          clamp?: boolean()
        }

  @doc "Creates a new symlog scale"
  @spec new() :: t()
  def new, do: %__MODULE__{}

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

  @doc """
  Sets the constant that controls the linear/log transition.

  Smaller values make the linear region smaller.
  Default is 1.
  """
  @spec constant(t(), number()) :: t()
  def constant(%__MODULE__{} = scale, c) when is_number(c) and c > 0 do
    %{scale | constant: c}
  end

  @doc "Enables or disables clamping of the output to the range"
  @impl true
  @spec clamp(t(), boolean()) :: t()
  def clamp(%__MODULE__{} = scale, clamp?) do
    %{scale | clamp?: clamp?}
  end

  @doc "Maps a value from the domain to the range using the symlog transform"
  @impl true
  @spec apply(t(), number()) :: number()
  def apply(%__MODULE__{domain: [d0, d1], range: [r0, r1], constant: c} = scale, value) do
    t_d0 = symlog_transform(d0, c)
    span = symlog_transform(d1, c) - t_d0

    t = if span == 0, do: 0, else: (symlog_transform(value, c) - t_d0) / span
    result = r0 + t * (r1 - r0)

    if scale.clamp?, do: clamp_value(result, r0, r1), else: result
  end

  @doc "Alias of `apply/2`, kept for one release (spec/03 §1.3)"
  @spec scale(t(), number()) :: number()
  def scale(%__MODULE__{} = scale, value), do: __MODULE__.apply(scale, value)

  @doc "Maps a value from the range back to the domain (inverse)"
  @impl true
  @spec invert(t(), number()) :: number()
  def invert(%__MODULE__{domain: [d0, d1], range: [r0, r1], constant: c}, value) do
    t = if r1 == r0, do: 0, else: (value - r0) / (r1 - r0)
    t_d0 = symlog_transform(d0, c)

    symlog_inverse(t_d0 + t * (symlog_transform(d1, c) - t_d0), c)
  end

  @doc "Generates nice tick values for the scale: signed decades and zero"
  @impl true
  @spec ticks(t(), integer()) :: [number()]
  def ticks(%__MODULE__{domain: [d0, d1], constant: c}, count \\ 10) do
    min_d = min(d0, d1)
    max_d = max(d0, d1)

    negative =
      if min_d < 0 do
        generate_log_ticks(-min_d, c, count)
        |> Enum.map(&(-&1))
        |> Enum.filter(&(&1 >= min_d))
      else
        []
      end

    zero = if min_d <= 0 and max_d >= 0, do: [0], else: []

    positive =
      if max_d > 0 do
        generate_log_ticks(max_d, c, count)
        |> Enum.filter(&(&1 <= max_d and &1 > 0))
      else
        []
      end

    (negative ++ zero ++ positive)
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc "Extends the domain to nice round values, as `Linear.nice/1` does"
  @impl true
  @spec nice(t()) :: t()
  def nice(%__MODULE__{domain: [d0, d1]} = scale) do
    %{scale | domain: Linear.nice(%Linear{domain: [d0, d1]}).domain}
  end

  @doc "Identity: a symlog scale has no padding"
  @impl true
  @spec padding(t(), number()) :: t()
  def padding(%__MODULE__{} = scale, _padding), do: scale

  @doc "Returns `0`: a symlog scale has no bandwidth"
  @impl true
  @spec bandwidth(t()) :: 0
  def bandwidth(%__MODULE__{}), do: 0

  # Symmetric log transformation: sign(x) * log(1 + |x| / c)
  defp symlog_transform(x, c) do
    sign = if x < 0, do: -1, else: 1
    sign * :math.log(1 + abs(x) / c)
  end

  # Inverse: sign(y) * c * (exp(|y|) - 1)
  defp symlog_inverse(y, c) do
    sign = if y < 0, do: -1, else: 1
    sign * c * (:math.exp(abs(y)) - 1)
  end

  defp generate_log_ticks(max_val, _c, _count) when max_val <= 0, do: []

  defp generate_log_ticks(max_val, _c, count) do
    max_exp = :math.log10(max_val) |> ceil() |> trunc()
    min_exp = 0

    step = max(1, div(max_exp - min_exp, count))

    for exp <- min_exp..max_exp//step do
      :math.pow(10, exp)
    end
  end

  defp clamp_value(value, r0, r1) when r0 <= r1, do: value |> max(r0) |> min(r1)
  defp clamp_value(value, r0, r1), do: value |> max(r1) |> min(r0)
end
