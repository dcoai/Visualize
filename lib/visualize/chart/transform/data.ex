defmodule Visualize.Chart.Transform.Data do
  @moduledoc false
  # The data steps of a mark's pipeline (spec/14 §5.4.1): `:bin` over `Visualize.Data.bin/2`,
  # `:stack` over `Visualize.Shape.Stack`, `:filter`, `:sum` and `:sort` over the rows
  # themselves, and `:lttb` and `:m4` over `Visualize.Data.lttb/3` and `m4/3` (#448).

  alias Visualize.Chart.Schema
  alias Visualize.Data
  alias Visualize.Data.{FFT, Table}
  alias Visualize.Shape.Stack

  # A window's units, each the seconds it names: an extent of time, never a calendar
  # walk, so a :day is 86,400 seconds and a :year 365 of those (spec/14 §5.4.1).
  @units %{
    second: 1,
    minute: 60,
    hour: 3_600,
    day: 86_400,
    week: 604_800,
    year: 31_536_000
  }

  @doc false
  @spec run(atom(), map(), [map()], map()) :: [map()]
  def run(op, node, rows, ctx \\ %{})

  def run(:filter, node, rows, _ctx), do: filter(node, rows)
  def run(:bin, node, rows, _ctx), do: bin(node, rows)
  def run(:stack, node, rows, _ctx), do: stack(node, rows)
  def run(:fold, node, rows, _ctx), do: fold(node, rows)
  def run(:sum, node, rows, _ctx), do: sum(node, rows)
  def run(:sort, node, rows, _ctx), do: sort(node, rows)
  def run(:spectrum, node, rows, _ctx), do: spectrum(node, rows)
  def run(:take, node, rows, _ctx), do: take(node, rows)
  def run(:window, node, rows, ctx), do: window(node, rows, ctx)
  def run(:lttb, node, rows, ctx), do: lttb(node, rows, ctx)
  def run(:m4, node, rows, ctx), do: m4(node, rows, ctx)

  # -- lttb and m4 (spec/14 §5.4.1, #448) -------------------------------------------------

  # Shape-preserving downsampling over `Visualize.Data.lttb/3` and `m4/3`: whole rows kept,
  # each run of gap rows kept as its first so `defined/2` still breaks the path.
  defp lttb(node, rows, ctx) do
    n = count!(:lttb, :n, Map.fetch!(node, :n), ctx)

    n >= 3 ||
      raise ArgumentError,
            "transform :lttb keeps its two ends and a point between, so n is at least 3, " <>
              "got #{n} (spec/14 §5.4.1)"

    Data.lttb(rows, n, reader(:lttb, node))
  end

  defp m4(node, rows, ctx) do
    width = count!(:m4, :width, Map.fetch!(node, :width), ctx)

    width >= 1 ||
      raise ArgumentError,
            "transform :m4 needs at least one pixel column, got width #{width} (spec/14 §5.4.1)"

    Data.m4(rows, width, reader(:m4, node))
  end

  # A count as given, or `:plot` — the plot area's width in whole pixels, the frame's
  # geometry the step binds to (spec/14 §5.4.1).
  defp count!(_op, _key, n, _ctx) when is_integer(n), do: n

  defp count!(_op, _key, :plot, ctx) do
    [width, _height] = Map.get(ctx, :size, [1, 1])
    ceil(width)
  end

  defp count!(op, key, other, _ctx) do
    raise ArgumentError,
          "transform #{inspect(op)}: #{inspect(key)} is an integer or :plot, got " <>
            "#{inspect(other)} (spec/14 §5.4.1)"
  end

  # The `{x, y}` a downsampling reads from a row: `x` a number or a time in seconds, as
  # `:window` reads one, `y` a number, and `nil` either way a gap.
  defp reader(op, node) do
    {x, y} = xy!(op, Map.fetch!(node, :fields))

    fn row ->
      {x_reading(Table.get(row, x), x, op), y_reading(Table.get(row, y), y, op)}
    end
  end

  defp xy!(_op, [x, y]), do: {x, y}

  defp xy!(op, other) do
    raise ArgumentError,
          "transform #{inspect(op)}: fields is [x, y], got #{inspect(other)} (spec/14 §5.4.1)"
  end

  defp x_reading(nil, _field, _op), do: nil
  defp x_reading(reading, field, op), do: seconds!(reading, field, op)

  defp y_reading(nil, _field, _op), do: nil
  defp y_reading(reading, _field, _op) when is_number(reading), do: reading

  defp y_reading(reading, field, op) do
    raise ArgumentError,
          "transform #{inspect(op)}: #{inspect(field)} reads #{inspect(reading)}, which is " <>
            "not a number (spec/14 §5.4.1)"
  end

  # -- take and window (spec/14 §5.4.1, #426) ---------------------------------------------

  # The last, or the first, `n` rows in order; `n` at or above the count is every row.
  defp take(node, rows) do
    n = Map.fetch!(node, :n)

    (is_integer(n) and n >= 0) ||
      raise ArgumentError,
            "transform :take needs a non-negative n, got #{inspect(n)} (spec/14 §5.4.1)"

    case Map.get(node, :side, Schema.default(:transform, :side)) do
      :end -> Enum.take(rows, -n)
      :start -> Enum.take(rows, n)
    end
  end

  # The rows whose reading lies in the half-open span `[now − from, now − to)`, so two
  # windows that share a bound do not share a row. An absent bound is open at that end.
  defp window(node, rows, ctx) do
    field = Map.fetch!(node, :field)

    read =
      for row <- rows,
          reading = Table.get(row, field),
          do: {row, seconds!(reading, field, :window)}

    case read do
      [] ->
        []

      read ->
        now = now(Map.get(ctx, :now), read, field)
        lo = lower(Map.get(node, :from), now)
        hi = upper(Map.get(node, :to), now)

        for {row, at} <- read, at_or_after?(at, lo), within?(at, hi), do: row
    end
  end

  # The instant the durations are measured back from: the caller's `now:` when it gave
  # one — a live dashboard means the wall clock — else the newest reading of the column,
  # which is what a test and a static render mean.
  defp now(nil, read, _field), do: read |> Enum.map(&elem(&1, 1)) |> Enum.max()
  defp now(given, _read, field), do: seconds!(given, field, :window)

  # There is no natural oldest instant, so an absent `from` is genuinely open; there is a
  # natural newest one, so an absent `to` closes the window at `now` **inclusively** — the
  # newest reading belongs to the last window. A `to` that is given is exclusive, which is
  # what keeps two adjacent windows from sharing a row.
  defp lower(nil, _now), do: :open
  defp lower(duration, now), do: now - duration!(duration)

  defp upper(nil, now), do: {:through, now}
  defp upper(duration, now), do: {:below, now - duration!(duration)}

  defp at_or_after?(_at, :open), do: true
  defp at_or_after?(at, lo), do: at >= lo

  defp within?(at, {:through, hi}), do: at <= hi
  defp within?(at, {:below, hi}), do: at < hi

  defp duration!([n, unit]) when is_number(n) do
    case Map.fetch(@units, unit) do
      {:ok, seconds} ->
        n * seconds

      :error ->
        raise ArgumentError,
              "transform :window: #{inspect(unit)} is not one of " <>
                "#{inspect(Map.keys(@units))} (spec/14 §5.4.1)"
    end
  end

  defp duration!(other) do
    raise ArgumentError,
          "transform :window: a duration is [n, unit], got #{inspect(other)} (spec/14 §5.4.1)"
  end

  # A reading as seconds from the epoch, the forms §4.3 reads a `:time` domain in.
  defp seconds!(%DateTime{} = at, _field, _op), do: DateTime.to_unix(at, :microsecond) / 1_000_000

  defp seconds!(%NaiveDateTime{} = at, _field, _op),
    do: NaiveDateTime.diff(at, ~N[1970-01-01 00:00:00], :microsecond) / 1_000_000

  defp seconds!(%Date{} = at, _field, _op), do: Date.diff(at, ~D[1970-01-01]) * 86_400.0
  defp seconds!(n, _field, _op) when is_number(n), do: n

  defp seconds!(string, field, op) when is_binary(string) do
    parsed =
      with :error <- iso(DateTime.from_iso8601(string)),
           :error <- iso(NaiveDateTime.from_iso8601(string)),
           do: iso(Date.from_iso8601(string))

    case parsed do
      {:ok, at} -> seconds!(at, field, op)
      :error -> not_temporal!(string, field, op)
    end
  end

  defp seconds!(other, field, op), do: not_temporal!(other, field, op)

  defp iso({:ok, at}), do: {:ok, at}
  defp iso({:ok, at, _offset}), do: {:ok, at}
  defp iso(_error), do: :error

  defp not_temporal!(value, field, op) do
    raise ArgumentError,
          "transform #{inspect(op)}: #{inspect(field)} reads #{inspect(value)}, which is not a " <>
            "time (spec/14 §5.4.1)"
  end

  # -- filter -----------------------------------------------------------------------------

  # The rows whose reading of `field` passes `test` against `value` (D-68): a `nil`
  # reading is what `:present` and `:absent` test, and never passes an ordering.
  defp filter(node, rows) do
    test = Map.get(node, :test, :present)
    value = Map.get(node, :value)
    Enum.filter(rows, &passes?(test, Table.get(&1, node.field), value))
  end

  defp passes?(:present, reading, _value), do: reading != nil
  defp passes?(:absent, reading, _value), do: reading == nil
  defp passes?(:eq, reading, value), do: reading == value
  defp passes?(:ne, reading, value), do: reading != value
  defp passes?(_ordering, nil, _value), do: false
  defp passes?(:lt, reading, value), do: reading < value
  defp passes?(:lte, reading, value), do: reading <= value
  defp passes?(:gt, reading, value), do: reading > value
  defp passes?(:gte, reading, value), do: reading >= value

  # -- bin --------------------------------------------------------------------------------

  defp bin(node, rows) do
    as = Map.get(node, :as, :count)
    values = column(rows, node.field)

    values
    |> Data.bin(thresholds: Map.get(node, :thresholds, 10))
    |> Enum.map(fn bin ->
      Map.put(%{x0: bin.x0, x1: bin.x1, y0: 0, values: bin.values}, as, length(bin.values))
    end)
  end

  # -- spectrum ---------------------------------------------------------------------------

  # A time series to its frequency spectrum (spec/14 §5.4.1, spec/08 §9, #375): the sample
  # interval from `every`, else the median gap of the time column, else 1; the rows with a
  # numeric reading of `field`, newest last, through `Visualize.Data.FFT.spectrum/3`.
  defp spectrum(node, rows) do
    as = Map.get(node, :as, [:frequency, :magnitude])
    {frequency, magnitude, phase} = spectrum_names(as)

    sampled = Enum.filter(rows, &is_number(Table.get(&1, node.field)))
    every = Map.get(node, :every) || median_gap(sampled, Map.get(node, :time)) || 1

    opts =
      [
        samples: Map.get(node, :samples),
        window: Map.get(node, :window, :hann),
        detrend: Map.get(node, :detrend, false)
      ]
      |> Enum.reject(fn {_k, v} -> v == nil end)

    sampled
    |> Enum.map(&Table.get(&1, node.field))
    |> FFT.spectrum(every, opts)
    |> Enum.map(fn line ->
      row = %{frequency => line.frequency, magnitude => line.magnitude}
      if phase, do: Map.put(row, phase, line.phase), else: row
    end)
  end

  defp spectrum_names([f, m]), do: {f, m, nil}
  defp spectrum_names([f, m, p | _]), do: {f, m, p}
  defp spectrum_names(name) when is_atom(name), do: {name, :magnitude, nil}

  # The median gap between consecutive readings of the time column: DateTimes in seconds,
  # numbers as they are; nil without a column or with fewer than two readings.
  defp median_gap(_rows, nil), do: nil

  defp median_gap(rows, time) do
    gaps =
      rows
      |> Enum.map(&Table.get(&1, time))
      |> Enum.reject(&is_nil/1)
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [a, b] -> gap(a, b) end)
      |> Enum.reject(&(is_nil(&1) or &1 <= 0))
      |> Enum.sort()

    case gaps do
      [] -> nil
      gaps -> Enum.at(gaps, div(length(gaps), 2))
    end
  end

  defp gap(%DateTime{} = a, %DateTime{} = b), do: DateTime.diff(b, a, :microsecond) / 1_000_000
  defp gap(a, b) when is_number(a) and is_number(b), do: b - a
  defp gap(_a, _b), do: nil

  # -- stack ------------------------------------------------------------------------------

  defp stack(node, rows) do
    keys = node.fields
    {stacked_keys, order} = order(Map.get(node, :order, :none), keys, rows)

    series =
      Stack.new()
      |> Stack.keys(stacked_keys)
      |> Stack.order(order)
      |> Stack.offset(Map.get(node, :offset, :none))
      |> Stack.generate(rows)

    by_key = Map.new(series, &{&1.key, &1})

    for key <- keys, s = Map.get(by_key, key), s != nil, point <- s.points do
      Map.merge(point.data, %{
        key: key,
        series: s.index,
        value: point.value,
        y0: point.y0,
        y1: point.y1
      })
    end
  end

  defp order(:inside_out, keys, _rows), do: {keys, :insideout}

  # d3's stackOrderAppearance: series in ascending order of the index of their peak.
  defp order(:appearance, keys, rows) do
    {Enum.sort_by(keys, &peak(rows, &1)), :none}
  end

  defp order(order, keys, _rows), do: {keys, order}

  defp peak(rows, key) do
    rows
    |> Enum.map(&(Table.get(&1, key) || 0))
    |> Enum.with_index()
    |> Enum.max_by(fn {v, _i} -> v end, fn -> {0, 0} end)
    |> elem(1)
  end

  # -- fold -------------------------------------------------------------------------------

  # Wide columns to long rows (spec/14 §5.4.1): one row per input row per listed column
  # the row has, the other columns carried, the column's name and value under `as`.
  defp fold(node, rows) do
    fields = node.fields
    {key, value} = as_pair(Map.get(node, :as, [:key, :value]))

    for row <- rows, field <- fields, (reading = Table.get(row, field)) != nil do
      row
      |> Map.drop(fields)
      |> Map.put(key, field)
      |> Map.put(value, reading)
    end
  end

  defp as_pair([key, value]) when is_atom(key) and is_atom(value), do: {key, value}

  defp as_pair(other) do
    raise ArgumentError,
          "a :fold step's as is a pair of names; got #{inspect(other)} (spec/14 §5.4)"
  end

  # -- sum --------------------------------------------------------------------------------

  defp sum(node, rows) do
    as = Map.get(node, :as, :sum)

    case Map.get(node, :by) do
      nil ->
        [%{as => total(rows, node.field)}]

      by ->
        rows
        |> Enum.map(&Table.get(&1, by))
        |> Enum.uniq()
        |> Enum.map(fn group ->
          members = Enum.filter(rows, &(Table.get(&1, by) == group))
          %{by => group, as => total(members, node.field)}
        end)
    end
  end

  defp total(rows, field), do: rows |> column(field) |> Enum.sum()

  # -- sort -------------------------------------------------------------------------------

  defp sort(node, rows) do
    direction = if Map.get(node, :order, :ascending) == :descending, do: :desc, else: :asc
    Enum.sort_by(rows, &Table.get(&1, node.field), direction)
  end

  defp column(rows, field), do: rows |> Enum.map(&Table.get(&1, field)) |> Enum.reject(&is_nil/1)
end
