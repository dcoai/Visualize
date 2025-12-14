defmodule Visualize.Scale.Time do
  @moduledoc """
  A scale for temporal data (DateTime, Date, NaiveDateTime).

  Maps time values to a continuous numeric range.
  """

  defstruct domain: nil,
            range: [0, 1],
            clamp?: false

  @type t :: %__MODULE__{
          domain: [DateTime.t() | Date.t() | NaiveDateTime.t()] | nil,
          range: [number()],
          clamp?: boolean()
        }

  @doc "Creates a new time scale"
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc "Sets the domain"
  @spec domain(t(), [DateTime.t() | Date.t() | NaiveDateTime.t()]) :: t()
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

  @doc "Applies the scale to a time value"
  @spec apply(t(), DateTime.t() | Date.t() | NaiveDateTime.t()) :: float()
  def apply(%__MODULE__{domain: [d0, d1], range: [r0, r1], clamp?: clamp?}, value) do
    t0 = to_unix(d0)
    t1 = to_unix(d1)
    tv = to_unix(value)

    t = (tv - t0) / (t1 - t0)
    t = if clamp?, do: clamp_value(t, 0, 1), else: t

    r0 + t * (r1 - r0)
  end

  @doc "Inverts the scale to get a DateTime"
  @spec invert(t(), number()) :: DateTime.t()
  def invert(%__MODULE__{domain: [d0, d1], range: [r0, r1]}, value) do
    t0 = to_unix(d0)
    t1 = to_unix(d1)

    t = (value - r0) / (r1 - r0)
    unix = t0 + t * (t1 - t0)

    DateTime.from_unix!(round(unix))
  end

  @doc "Generates tick values"
  @spec ticks(t(), integer()) :: [DateTime.t()]
  def ticks(%__MODULE__{domain: [d0, d1]}, count) do
    t0 = to_unix(d0)
    t1 = to_unix(d1)
    span = t1 - t0

    # Choose appropriate interval
    {interval, step_fn} = choose_interval(span, count)

    # Generate ticks
    start_time = ceil_to_interval(d0, interval)
    generate_ticks(start_time, d1, step_fn, [])
  end

  @doc "Extends domain to nice time boundaries"
  @spec nice(t()) :: t()
  def nice(%__MODULE__{domain: [d0, d1]} = scale) do
    span = to_unix(d1) - to_unix(d0)
    {interval, _} = choose_interval(span, 10)

    %{scale | domain: [floor_to_interval(d0, interval), ceil_to_interval(d1, interval)]}
  end

  # Not applicable
  def padding(scale, _), do: scale
  def bandwidth(_), do: 0

  # Convert various time types to unix timestamp
  defp to_unix(%DateTime{} = dt), do: DateTime.to_unix(dt)
  defp to_unix(%NaiveDateTime{} = ndt), do: NaiveDateTime.diff(ndt, ~N[1970-01-01 00:00:00])
  defp to_unix(%Date{} = d), do: Date.diff(d, ~D[1970-01-01]) * 86400

  # Choose an appropriate time interval based on span
  defp choose_interval(span_seconds, count) do
    target = span_seconds / count

    intervals = [
      {1, :second},
      {5, :second},
      {15, :second},
      {30, :second},
      {60, :minute},
      {300, :minute},
      {900, :minute},
      {1800, :minute},
      {3600, :hour},
      {10800, :hour},
      {21600, :hour},
      {43200, :hour},
      {86400, :day},
      {172800, :day},
      {604800, :week},
      {2592000, :month},
      {7776000, :month},
      {31536000, :year}
    ]

    {secs, unit} =
      Enum.find(intervals, {86400, :day}, fn {secs, _} -> secs >= target end)

    step_fn =
      case unit do
        :second -> fn dt -> DateTime.add(dt, secs, :second) end
        :minute -> fn dt -> DateTime.add(dt, secs, :second) end
        :hour -> fn dt -> DateTime.add(dt, secs, :second) end
        :day -> fn dt -> DateTime.add(dt, secs, :second) end
        :week -> fn dt -> DateTime.add(dt, secs, :second) end
        :month -> fn dt -> shift_months(dt, div(secs, 2592000)) end
        :year -> fn dt -> shift_months(dt, div(secs, 2592000)) end
      end

    {{secs, unit}, step_fn}
  end

  defp shift_months(dt, months) do
    %{dt | month: rem(dt.month + months - 1, 12) + 1, year: dt.year + div(dt.month + months - 1, 12)}
  end

  defp ceil_to_interval(time, {_, :day}) do
    date = to_date(time)
    DateTime.new!(date, ~T[00:00:00])
  end

  defp ceil_to_interval(time, {secs, _unit}) when secs < 86400 do
    unix = to_unix(time)
    ceiled = Float.ceil(unix / secs) * secs
    DateTime.from_unix!(round(ceiled))
  end

  defp ceil_to_interval(time, _), do: ensure_datetime(time)

  defp floor_to_interval(time, {_, :day}) do
    date = to_date(time)
    DateTime.new!(date, ~T[00:00:00])
  end

  defp floor_to_interval(time, {secs, _unit}) when secs < 86400 do
    unix = to_unix(time)
    floored = Float.floor(unix / secs) * secs
    DateTime.from_unix!(round(floored))
  end

  defp floor_to_interval(time, _), do: ensure_datetime(time)

  defp to_date(%DateTime{} = dt), do: DateTime.to_date(dt)
  defp to_date(%NaiveDateTime{} = ndt), do: NaiveDateTime.to_date(ndt)
  defp to_date(%Date{} = d), do: d

  defp ensure_datetime(%DateTime{} = dt), do: dt
  defp ensure_datetime(%NaiveDateTime{} = ndt), do: DateTime.from_naive!(ndt, "Etc/UTC")
  defp ensure_datetime(%Date{} = d), do: DateTime.new!(d, ~T[00:00:00])

  defp generate_ticks(current, end_time, step_fn, acc) do
    if to_unix(current) > to_unix(end_time) do
      Enum.reverse(acc)
    else
      generate_ticks(step_fn.(current), end_time, step_fn, [current | acc])
    end
  end

  defp clamp_value(value, min_val, max_val) do
    value |> max(min_val) |> min(max_val)
  end
end
