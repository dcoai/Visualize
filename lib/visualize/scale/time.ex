defmodule Visualize.Scale.Time do
  @moduledoc """
  A scale for temporal data (DateTime, Date, NaiveDateTime).

  Maps time values to a continuous numeric range. Ticks follow d3-time: an interval
  (seconds, minutes, hours, days, weeks, months, years, or a multiple of years) is chosen
  so that about `count` ticks fit the domain, and every tick sits on a boundary of that
  interval — a whole multiple of the seconds below a day, midnight, Monday, the first of
  the month, or 1 January — inside the domain.

  ## Display zone

  `zone/2` gives the scale an IANA zone (spec/03 §7.4, D-115). Values are still Unix
  seconds, so `apply/2` and every position are unchanged; the boundaries are read in the
  zone's local calendar instead of UTC — local midnights, local Mondays, the 1st of a local
  month — and sub-day ticks are the real instants whose local time is aligned, so the hour
  a transition repeats is ticked twice and the hour it skips not at all. `ticks/2`,
  `nice/1` and `invert/2` return `DateTime` values in the zone. The zone is read through
  the host's `Calendar.TimeZoneDatabase`; a name it cannot show raises `ArgumentError`.
  """

  @behaviour Visualize.Scale.Behaviour

  defstruct domain: nil,
            range: [0, 1],
            clamp?: false,
            zone: nil

  @type t :: %__MODULE__{
          domain: [DateTime.t() | Date.t() | NaiveDateTime.t()] | nil,
          range: [number()],
          clamp?: boolean(),
          zone: Calendar.time_zone() | nil
        }

  @typedoc "Why the host's time zone database cannot show a zone."
  @type zone_error :: :time_zone_not_found | :utc_only_time_zone_database

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

  @doc """
  Sets the display zone: an IANA name such as `"America/New_York"`, or `nil` for UTC
  (spec/03 §7.4).

  Raises `ArgumentError` naming the zone when the host's `Calendar.TimeZoneDatabase` does
  not know it, or when the host has configured none — never a silent fallback to UTC.
  """
  @spec zone(t(), Calendar.time_zone() | nil) :: t()
  def zone(%__MODULE__{} = scale, nil), do: %{scale | zone: nil}

  def zone(%__MODULE__{} = scale, zone) when is_binary(zone) do
    case check_zone(zone) do
      :ok -> %{scale | zone: zone}
      {:error, reason} -> raise ArgumentError, zone_message(zone, reason)
    end
  end

  @doc """
  Whether the host's time zone database can show `zone`: `:ok`, or the database's reason,
  `{:error, :time_zone_not_found}` or `{:error, :utc_only_time_zone_database}` (a host
  with no database configured).
  """
  @spec check_zone(Calendar.time_zone()) :: :ok | {:error, zone_error()}
  def check_zone(zone) when is_binary(zone) do
    case DateTime.shift_zone(~U[2000-01-01 00:00:00Z], zone) do
      {:ok, _shifted} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  A time value as the scale shows it: a `DateTime` in the scale's zone, the value reduced
  as `apply/2` reduces it (a `NaiveDateTime` read as UTC, a `Date` as midnight UTC). A
  scale without a zone returns the value unchanged.
  """
  @spec local(t(), DateTime.t() | Date.t() | NaiveDateTime.t()) ::
          DateTime.t() | Date.t() | NaiveDateTime.t()
  def local(%__MODULE__{zone: nil}, value), do: value

  def local(%__MODULE__{zone: zone}, value),
    do: value |> ensure_datetime() |> DateTime.shift_zone!(zone)

  @doc "Applies the scale to a time value"
  @impl true
  @spec apply(t(), DateTime.t() | Date.t() | NaiveDateTime.t()) :: float()
  def apply(%__MODULE__{domain: [d0, d1], range: [r0, r1], clamp?: clamp?}, value) do
    t0 = to_unix(d0)
    t1 = to_unix(d1)
    tv = to_unix(value)

    t = Visualize.Scale.Behaviour.normalize(tv, t0, t1)
    t = if clamp?, do: clamp_value(t, 0, 1), else: t

    r0 + t * (r1 - r0)
  end

  @doc "Inverts the scale to get a DateTime, in the scale's zone (UTC without one)"
  @impl true
  @spec invert(t(), number()) :: DateTime.t()
  def invert(%__MODULE__{domain: [d0, d1], range: [r0, r1], zone: zone}, value) do
    t0 = to_unix(d0)
    t1 = to_unix(d1)

    t = Visualize.Scale.Behaviour.normalize(value, r0, r1)
    unix = t0 + t * (t1 - t0)

    unix |> round() |> instant(zone)
  end

  @doc """
  Generates tick values: every boundary of the chosen interval inside the domain, as
  `DateTime` values in the scale's zone (UTC without one), the boundaries read in that
  zone's local calendar. A descending domain yields the same ticks descending.
  """
  @impl true
  @spec ticks(t(), integer()) :: [DateTime.t()]
  def ticks(%__MODULE__{domain: [d0, d1], zone: zone}, count) do
    t0 = ensure_datetime(d0)
    t1 = ensure_datetime(d1)

    case DateTime.compare(t0, t1) do
      :gt -> boundaries(t1, t0, count, zone) |> Enum.reverse()
      _ -> boundaries(t0, t1, count, zone)
    end
  end

  @doc "Extends the domain outward to the boundaries of the interval ten ticks would use"
  @impl true
  @spec nice(t()) :: t()
  def nice(%__MODULE__{domain: [d0, d1], zone: zone} = scale) do
    t0 = ensure_datetime(d0)
    t1 = ensure_datetime(d1)
    interval = choose_interval(abs(to_unix(t1) - to_unix(t0)), 10)

    case DateTime.compare(t0, t1) do
      :gt ->
        %{scale | domain: [ceil_to(t0, interval, zone), floor_to(t1, interval, zone)]}

      _ ->
        %{scale | domain: [floor_to(t0, interval, zone), ceil_to(t1, interval, zone)]}
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

  defp boundaries(t0, t1, count, zone) do
    interval = choose_interval(to_unix(t1) - to_unix(t0), count)
    collect(ceil_to(t0, interval, zone), t1, interval, zone, [])
  end

  defp collect(current, stop, interval, zone, acc) do
    case DateTime.compare(current, stop) do
      :gt -> Enum.reverse(acc)
      _ -> collect(step(current, interval, zone), stop, interval, zone, [current | acc])
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

  # Every function here takes the scale's zone. `nil` is UTC, exactly as before zones
  # existed (spec/03 §7.3.2); a zone reads the same boundaries in its local calendar
  # (§7.4): calendar units on local dates at local midnight, sub-day units at the real
  # instants whose local time is aligned.

  defp floor_to(dt, {unit, n}, nil) when unit in [:second, :minute, :hour] do
    secs = n * unit_seconds(unit)
    DateTime.from_unix!(Integer.floor_div(to_unix(dt), secs) * secs)
  end

  defp floor_to(dt, {unit, n}, zone) when unit in [:second, :minute, :hour] do
    dt |> to_unix() |> local_floor(n * unit_seconds(unit), zone) |> instant(zone)
  end

  defp floor_to(dt, {:day, n}, zone) do
    date = local_date(dt, zone)
    midnight(%{date | day: div(date.day - 1, n) * n + 1}, zone)
  end

  defp floor_to(dt, {:week, 1}, zone) do
    dt |> local_date(zone) |> Date.beginning_of_week(:monday) |> midnight(zone)
  end

  defp floor_to(dt, {:month, n}, zone) do
    date = local_date(dt, zone)
    midnight(%{date | month: div(date.month - 1, n) * n + 1, day: 1}, zone)
  end

  defp floor_to(dt, {:year, n}, zone) do
    date = local_date(dt, zone)
    midnight(%{date | year: Integer.floor_div(date.year, n) * n, month: 1, day: 1}, zone)
  end

  # The boundary at or after `dt`: the floor when `dt` already sits on one, else one step on.
  defp ceil_to(dt, interval, zone) do
    floored = floor_to(dt, interval, zone)

    if DateTime.compare(floored, dt) == :eq, do: floored, else: step(floored, interval, zone)
  end

  # The next boundary after an aligned `dt`.
  defp step(dt, {unit, n}, nil) when unit in [:second, :minute, :hour] do
    DateTime.add(dt, n * unit_seconds(unit), :second)
  end

  defp step(dt, {unit, n}, zone) when unit in [:second, :minute, :hour] do
    dt |> to_unix() |> Kernel.+(1) |> local_ceil(n * unit_seconds(unit), zone) |> instant(zone)
  end

  defp step(dt, {:day, n}, zone) do
    date = local_date(dt, zone)
    day = date.day + n

    if day <= Date.days_in_month(date) do
      midnight(%{date | day: day}, zone)
    else
      midnight(%{shift_months(date, 1) | day: 1}, zone)
    end
  end

  defp step(dt, {:week, 1}, nil), do: DateTime.add(dt, 7 * 86_400, :second)

  # A local week is seven local days, which across a transition is not 604 800 seconds.
  defp step(dt, {:week, 1}, zone), do: dt |> local_date(zone) |> Date.add(7) |> midnight(zone)

  defp step(dt, {:month, n}, zone) do
    dt |> local_date(zone) |> shift_months(n) |> midnight(zone)
  end

  defp step(dt, {:year, n}, zone) do
    date = local_date(dt, zone)
    midnight(%{date | year: date.year + n}, zone)
  end

  # Calendar month arithmetic with the day clamped to the target month's length, so
  # 31 January + 1 month is the last day of February.
  defp shift_months(%Date{} = date, months) do
    index = date.year * 12 + (date.month - 1) + months
    target = %{date | year: Integer.floor_div(index, 12), month: Integer.mod(index, 12) + 1}
    %{target | day: min(date.day, Date.days_in_month(%{target | day: 1}))}
  end

  # The date a boundary is counted on: the value's own date without a zone (a `DateTime`
  # in another zone keeps its own date, as it always has), the local date with one.
  defp local_date(dt, nil), do: DateTime.to_date(dt)
  defp local_date(dt, zone), do: dt |> DateTime.shift_zone!(zone) |> DateTime.to_date()

  # The first instant of a local day: its midnight, or — when a transition skips midnight —
  # the instant the day resumes; a repeated midnight is the earlier of the two.
  defp midnight(%Date{} = date, nil), do: DateTime.new!(date, ~T[00:00:00])

  defp midnight(%Date{} = date, zone) do
    case DateTime.new(date, ~T[00:00:00], zone) do
      {:ok, dt} -> dt
      {:ambiguous, first, _second} -> first
      {:gap, _before, resumed} -> resumed
    end
  end

  defp instant(unix, nil), do: DateTime.from_unix!(unix)
  defp instant(unix, zone), do: unix |> DateTime.from_unix!() |> DateTime.shift_zone!(zone)

  # -- sub-day boundaries in a zone ---------------------------------------------------------

  # A sub-day boundary of `secs` in a zone is an instant `t` whose local time
  # `t + offset(t)` is a multiple of `secs` (every sub-day step divides a day, so the
  # multiple is aligned to local midnight). Within one offset the boundaries are evenly
  # spaced; where the offset changes the search restarts at the change, so a repeated
  # local hour is found twice and a skipped one never. The database reports the offset at
  # an instant, not where it changes, so a change is found by bisection.

  # The first boundary at or after `t`.
  defp local_ceil(t, secs, zone) do
    offset = offset(t, zone)
    candidate = t + Integer.mod(-(t + offset), secs)

    if offset(candidate, zone) == offset,
      do: candidate,
      else: local_ceil(change(t, candidate, offset, zone), secs, zone)
  end

  # The last boundary at or before `t`.
  defp local_floor(t, secs, zone) do
    offset = offset(t, zone)
    candidate = t - Integer.mod(t + offset, secs)
    before = offset(candidate, zone)

    if before == offset,
      do: candidate,
      else: local_floor(change(candidate, t, before, zone) - 1, secs, zone)
  end

  # The first instant in `(a, b]` whose offset is not `offset`, the offset at `a`; the
  # offset at `b` differs, so there is one.
  defp change(a, b, _offset, _zone) when b - a <= 1, do: b

  defp change(a, b, offset, zone) do
    mid = Integer.floor_div(a + b, 2)

    if offset(mid, zone) == offset,
      do: change(mid, b, offset, zone),
      else: change(a, mid, offset, zone)
  end

  defp offset(unix, zone) do
    local = instant(unix, zone)
    local.utc_offset + local.std_offset
  end

  defp unit_seconds(:second), do: 1
  defp unit_seconds(:minute), do: 60
  defp unit_seconds(:hour), do: 3600

  defp zone_message(zone, :utc_only_time_zone_database) do
    "time zone #{inspect(zone)} cannot be shown: no time zone database is configured " <>
      "(Calendar.UTCOnlyTimeZoneDatabase); configure one with " <>
      "Calendar.put_time_zone_database/1 or config :elixir, :time_zone_database"
  end

  defp zone_message(zone, reason) do
    "time zone #{inspect(zone)} cannot be shown: #{inspect(reason)}"
  end

  # -- value types -------------------------------------------------------------------------

  # Convert various time types to unix timestamp
  defp to_unix(%DateTime{} = dt), do: DateTime.to_unix(dt)
  defp to_unix(%NaiveDateTime{} = ndt), do: NaiveDateTime.diff(ndt, ~N[1970-01-01 00:00:00])
  defp to_unix(%Date{} = d), do: Date.diff(d, ~D[1970-01-01]) * 86_400

  defp ensure_datetime(%DateTime{} = dt), do: dt
  defp ensure_datetime(%NaiveDateTime{} = ndt), do: DateTime.from_naive!(ndt, "Etc/UTC")
  defp ensure_datetime(%Date{} = d), do: midnight(d, nil)

  defp clamp_value(value, min_val, max_val) do
    value |> max(min_val) |> min(max_val)
  end
end
