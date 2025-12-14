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

      Visualize.Scale.Symlog.scale(scale, 0)     # => 200.0 (center)
      Visualize.Scale.Symlog.scale(scale, 100)   # => ~300
      Visualize.Scale.Symlog.scale(scale, -100)  # => ~100

  ## Formula

  The transformation is: sign(x) * log1p(|x| / constant)

  """

  defstruct domain: {-1, 1},
            range: {0, 1},
            constant: 1,
            clamp?: false

  @type t :: %__MODULE__{
          domain: {number(), number()},
          range: {number(), number()},
          constant: number(),
          clamp?: boolean()
        }

  @doc "Creates a new symlog scale"
  @spec new() :: t()
  def new, do: %__MODULE__{}

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

  @doc """
  Sets the constant that controls the linear/log transition.

  Smaller values make the linear region smaller.
  Default is 1.
  """
  @spec constant(t(), number()) :: t()
  def constant(%__MODULE__{} = scale, c) when is_number(c) and c > 0 do
    %{scale | constant: c}
  end

  @doc "Enables or disables clamping to the range"
  @spec clamp(t(), boolean()) :: t()
  def clamp(%__MODULE__{} = scale, clamp?) do
    %{scale | clamp?: clamp?}
  end

  @doc "Maps a value from the domain to the range using symlog transformation"
  @spec scale(t(), number()) :: number()
  def scale(%__MODULE__{} = scale, value) do
    {d0, d1} = scale.domain
    {r0, r1} = scale.range
    c = scale.constant

    # Transform domain bounds
    t_d0 = symlog_transform(d0, c)
    t_d1 = symlog_transform(d1, c)
    t_value = symlog_transform(value, c)

    # Normalize to [0, 1]
    t_range = t_d1 - t_d0
    t = if t_range == 0, do: 0, else: (t_value - t_d0) / t_range

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
    c = scale.constant

    # Normalize from range
    t = if r1 == r0, do: 0, else: (value - r0) / (r1 - r0)

    # Transform domain bounds
    t_d0 = symlog_transform(d0, c)
    t_d1 = symlog_transform(d1, c)

    # Interpolate in transformed domain
    t_value = t_d0 + t * (t_d1 - t_d0)

    # Inverse transform
    symlog_inverse(t_value, c)
  end

  @doc "Generates nice tick values for the scale"
  @spec ticks(t(), integer()) :: [number()]
  def ticks(%__MODULE__{} = scale, count \\ 10) do
    {d0, d1} = scale.domain
    c = scale.constant

    # Generate ticks that look nice on a symlog scale
    # Include 0 if it's in the domain
    min_d = min(d0, d1)
    max_d = max(d0, d1)

    ticks = []

    # Add negative powers if domain includes negatives
    ticks = if min_d < 0 do
      neg_ticks = generate_log_ticks(-min_d, c, count)
                  |> Enum.map(&(-&1))
                  |> Enum.filter(&(&1 >= min_d))
      neg_ticks ++ ticks
    else
      ticks
    end

    # Add zero if in domain
    ticks = if min_d <= 0 and max_d >= 0 do
      [0 | ticks]
    else
      ticks
    end

    # Add positive powers if domain includes positives
    ticks = if max_d > 0 do
      pos_ticks = generate_log_ticks(max_d, c, count)
                  |> Enum.filter(&(&1 <= max_d and &1 > 0))
      ticks ++ pos_ticks
    else
      ticks
    end

    ticks
    |> Enum.uniq()
    |> Enum.sort()
  end

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

  defp clamp_value(value, r0, r1) when r0 <= r1 do
    value |> max(r0) |> min(r1)
  end

  defp clamp_value(value, r0, r1) do
    value |> max(r1) |> min(r0)
  end
end
