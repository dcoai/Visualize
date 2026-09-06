defmodule Visualize.Scale.Time do
  @moduledoc """
  A scale for temporal data (DateTime, Date, NaiveDateTime).

  Maps time values to a continuous numeric range. Ticks follow d3-time: an interval
  (seconds, minutes, hours, days, weeks, months, years, or a multiple of years) is chosen
  so that about `count` ticks fit the domain, and every tick sits on a boundary of that
  interval — a whole multiple of the seconds below a day, midnight, Monday, the first of
  the month, or 1 January — inside the domain.
  """

  @behaviour Visualize.Scale.Behaviour

  defstruct domain: nil,
            range: [0, 1],
            clamp?: false

  @type t :: %__MODULE__{
          domain: [DateTime.t() | Date.t() | NaiveDateTime.t()] | nil,
          range: [number()],
          clamp?: boolean()
        }

  @typedoc "A tick interval: a unit and how many of it make one step."
  @type interval ::
          {:second | :minute | :hour | :day | :week | :month | :year, pos_integer()}

  # The candidate intervals in ascending order, with the seconds one step spans (calendar
  # units at their nominal length: 30-day months, 365-day years). Beyond the last row a
  # multi-year interval is derived from the nice-step sequence.
  @intervals [
    {{:second, 1}, 1},
    {{:second, 5}, 5},
    {{:second, 15}, 15},
    {{:second, 30}, 30},
    {{:minute, 1}, 60},
    {{:minute, 5}, 300},
    {{:minute, 15}, 900},
    {{:minute, 30}, 1800},
    {{:hour, 1}, 3600},
    {{:hour, 3}, 10_800},
    {{:hour, 6}, 21_600},
    {{:hour, 12}, 43_200},
    {{:day, 1}, 86_400},
    {{:day, 2}, 172_800},
    {{:week, 1}, 604_800},
    {{:month, 1}, 2_592_000},
    {{:month, 3}, 7_776_000},
    {{:year, 1}, 31_536_000}
  ]

  @year_seconds 31_536_000

  @doc "Creates a new time scale"
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc "Sets the domain"
  @impl true
  @spec domain(t(), [DateTime.t() | Date.t() | NaiveDateTime.t()]) :: t()
  def domain(%__MODULE__{} = scale, [d0, d1]) do
    %{scale | domain: [d0, d1]}
  end

  @doc "Sets the range"
  @impl true
  @spec range(t(), [number()]) :: t()
  def range(%__MODULE__{} = scale, [r0, r1]) do
    %{scale | range: [r0, r1]}
  end

  @doc "Enables or disables clamping"
  @impl true
  @spec clamp(t(), boolean()) :: t()
  def clamp(%__MODULE__{} = scale, clamp?) do
    %{scale | clamp?: clamp?}
  end

  @doc "Applies the scale to a time value"
  @impl true
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
  @impl true
  @spec invert(t(), number()) :: DateTime.t()
  def invert(%__MODULE__{domain: [d0, d1], range: [r0, r1]}, value) do
    t0 = to_unix(d0)
    t1 = to_unix(d1)

    t = (value - r0) / (r1 - r0)
    unix = t0 + t * (t1 - t0)

    DateTime.from_unix!(round(unix))
  end

  @doc """
  Generates tick values: every boundary of the chosen interval inside the domain, as UTC
  `DateTime` values. A descending domain yields the same ticks descending.
  """
  @impl true
  @spec ticks(t(), integer()) :: [DateTime.t()]
  def ticks(%__MODULE__{domain: [d0, d1]}, count) do
    t0 = ensure_datetime(d0)
    t1 = ensure_datetime(d1)

    case DateTime.compare(t0, t1) do
      :gt -> boundaries(t1, t0, count) |> Enum.reverse()
      _ -> boundaries(t0, t1, count)
    end
  end

  @doc "Extends the domain outward to the boundaries of the interval ten ticks would use"
  @impl true
  @spec nice(t()) :: t()
  def nice(%__MODULE__{domain: [d0, d1]} = scale) do
    t0 = ensure_datetime(d0)
    t1 = ensure_datetime(d1)
    interval = choose_interval(abs(to_unix(t1) - to_unix(t0)), 10)

    case DateTime.compare(t0, t1) do
      :gt -> %{scale | domain: [ceil_to_interval(t0, interval), floor_to_interval(t1, interval)]}
      _ -> %{scale | domain: [floor_to_interval(t0, interval), ceil_to_interval(t1, interval)]}
    end
  end

  @doc "Identity: a time scale has no padding"
  @impl true
  @spec padding(t(), number()) :: t()
  def padding(%__MODULE__{} = scale, _padding), do: scale

  @doc "Returns `0`: a time scale has no bandwidth"
  @impl true
  @spec bandwidth(t()) :: 0
  def bandwidth(%__MODULE__{}), do: 0

  @doc """
  The interval about `count` ticks would use over a span of `seconds` (spec/03 §7.3.1).

  Exposed for tests and for callers that format ticks by their interval; not part of the
  scale protocol.
  """
  @spec interval(non_neg_integer(), pos_integer()) :: interval()
  def interval(seconds, count), do: choose_interval(seconds, count)

  # -- ticks -------------------------------------------------------------------------------

  defp boundaries(t0, t1, count) do
    interval = choose_interval(to_unix(t1) - to_unix(t0), count)
    collect(ceil_to_interval(t0, interval), t1, interval, [])
  end

  defp collect(current, stop, interval, acc) do
    case DateTime.compare(current, stop) do
      :gt -> Enum.reverse(acc)
      _ -> collect(step(current, interval), stop, interval, [current | acc])
    end
  end

  # d3's `tickInterval`: of the two table rows around `target`, the one closer in ratio;
  # past the table, whole years from the 1-2-5 nice-step sequence.
  defp choose_interval(span_seconds, count) do
    target = span_seconds / max(count, 1)

    case Enum.split_while(@intervals, fn {_interval, secs} -> secs < target end) do
      {_, []} ->
        {:year, year_step(span_seconds / @year_seconds, count)}

      {[], [{first, _} | _]} ->
        first

      {below, [{above, above_secs} | _]} ->
        {below_interval, below_secs} = List.last(below)

        if target / below_secs < above_secs / target, do: below_interval, else: above
    end
  end

  # d3's `tickStep` over years: 10^k times 1, 2 or 5, never below one year.
  defp year_step(years, count) do
    raw = years / max(count, 1)
    power = :math.pow(10, Float.floor(:math.log10(raw)))
    error = raw / power

    factor =
      cond do
        error >= :math.sqrt(50) -> 10
        error >= :math.sqrt(10) -> 5
        error >= :math.sqrt(2) -> 2
        true -> 1
      end

    max(1, round(factor * power))
  end

  # -- snapping ----------------------------------------------------------------------------

  defp floor_to_interval(dt, {unit, n}) when unit in [:second, :minute, :hour] do
    secs = n * unit_seconds(unit)
    DateTime.from_unix!(Integer.floor_div(to_unix(dt), secs) * secs)
  end

  defp floor_to_interval(dt, {:day, n}) do
    date = DateTime.to_date(dt)
    midnight(%{date | day: div(date.day - 1, n) * n + 1})
  end

  defp floor_to_interval(dt, {:week, 1}) do
    dt |> DateTime.to_date() |> Date.beginning_of_week(:monday) |> midnight()
  end

  defp floor_to_interval(dt, {:month, n}) do
    date = DateTime.to_date(dt)
    midnight(%{date | month: div(date.month - 1, n) * n + 1, day: 1})
  end

  defp floor_to_interval(dt, {:year, n}) do
    date = DateTime.to_date(dt)
    midnight(%{date | year: Integer.floor_div(date.year, n) * n, month: 1, day: 1})
  end

  # The boundary at or after `dt`: the floor when `dt` already sits on one, else one step on.
  defp ceil_to_interval(dt, interval) do
    floored = floor_to_interval(dt, interval)

    if DateTime.compare(floored, dt) == :eq, do: floored, else: step(floored, interval)
  end

  # The next boundary after an aligned `dt`.
  defp step(dt, {unit, n}) when unit in [:second, :minute, :hour] do
    DateTime.add(dt, n * unit_seconds(unit), :second)
  end

  defp step(dt, {:day, n}) do
    date = DateTime.to_date(dt)
    day = date.day + n

    if day <= Date.days_in_month(date) do
      midnight(%{date | day: day})
    else
      midnight(%{shift_months(date, 1) | day: 1})
    end
  end

  defp step(dt, {:week, 1}), do: DateTime.add(dt, 7 * 86_400, :second)

  defp step(dt, {:month, n}) do
    dt |> DateTime.to_date() |> shift_months(n) |> midnight()
  end

  defp step(dt, {:year, n}) do
    date = DateTime.to_date(dt)
    midnight(%{date | year: date.year + n})
  end

  # Calendar month arithmetic with the day clamped to the target month's length, so
  # 31 January + 1 month is the last day of February.
  defp shift_months(%Date{} = date, months) do
    index = date.year * 12 + (date.month - 1) + months
    target = %{date | year: Integer.floor_div(index, 12), month: Integer.mod(index, 12) + 1}
    %{target | day: min(date.day, Date.days_in_month(%{target | day: 1}))}
  end

  defp midnight(%Date{} = date), do: DateTime.new!(date, ~T[00:00:00])

  defp unit_seconds(:second), do: 1
  defp unit_seconds(:minute), do: 60
  defp unit_seconds(:hour), do: 3600

  # -- value types -------------------------------------------------------------------------

  # Convert various time types to unix timestamp
  defp to_unix(%DateTime{} = dt), do: DateTime.to_unix(dt)
  defp to_unix(%NaiveDateTime{} = ndt), do: NaiveDateTime.diff(ndt, ~N[1970-01-01 00:00:00])
  defp to_unix(%Date{} = d), do: Date.diff(d, ~D[1970-01-01]) * 86_400

  defp ensure_datetime(%DateTime{} = dt), do: dt
  defp ensure_datetime(%NaiveDateTime{} = ndt), do: DateTime.from_naive!(ndt, "Etc/UTC")
  defp ensure_datetime(%Date{} = d), do: midnight(d)

  defp clamp_value(value, min_val, max_val) do
    value |> max(min_val) |> min(max_val)
  end
end
