defmodule Visualize.Feed.Window do
  @moduledoc """
  Windows over a feed's window field (spec/08 §11.2, D-140, D-154).

  A window is `nil` — whatever a feed holds — or `[from, to]`, either bound `nil` for
  open. Its bounds are values of the feed's window field: numbers for a `:number` field,
  or instants — `DateTime`, `NaiveDateTime` or `Date` values — for a `:time` one, a window
  and a column of one kind (`applies?/2`). A window may also be a **box** (spec/08 §11.1,
  D-168), `%{ranges: %{field => [from, to]}, latest: boolean}`: ranges over any `:time` or
  `:number` field, and each identity's last row. `box/2` gives any window as its box,
  `range/2` reads one field's range, `check/2` holds a box to a schema and
  `latest_rows/3` keeps each identity's last row. These are the comparisons, the trims and
  the numeric position that `Visualize.Feed.finish/3`, `Visualize.Feed.Monitor` and
  `Visualize.Feed.Combine` share.

  ## Examples

      iex> Visualize.Feed.Window.within?(5, [0, 10])
      true
      iex> Visualize.Feed.Window.within?(~U[2026-10-11 12:00:00Z], [~U[2026-10-11 13:00:00Z], nil])
      false
      iex> Visualize.Feed.Window.trim([%{t: 1}, %{t: 5}, %{t: 9}], :t, [2, nil])
      [%{t: 5}, %{t: 9}]

  """

  alias Visualize.Data.{Schema, Table}
  alias Visualize.Feed

  @type time :: number() | DateTime.t() | NaiveDateTime.t() | Date.t()
  @type t :: [time() | nil] | nil

  @typedoc "A box (spec/08 §11.1, D-168): ranges over fields, and whether to keep each identity's last row."
  @type box :: %{ranges: %{Schema.name() => [time() | nil]}, latest: boolean()}

  @doc """
  `:lt`, `:eq` or `:gt` between two times of one kind: numbers by value, and `DateTime`,
  `NaiveDateTime` and `Date` each by their own `compare/2`.

      iex> Visualize.Feed.Window.compare(1, 1.0)
      :eq
  """
  @spec compare(time(), time()) :: :lt | :eq | :gt
  def compare(a, b) when is_number(a) and is_number(b) do
    cond do
      a < b -> :lt
      a > b -> :gt
      true -> :eq
    end
  end

  def compare(%DateTime{} = a, %DateTime{} = b), do: DateTime.compare(a, b)
  def compare(%NaiveDateTime{} = a, %NaiveDateTime{} = b), do: NaiveDateTime.compare(a, b)
  def compare(%Date{} = a, %Date{} = b), do: Date.compare(a, b)

  @doc "Whether a value is one a window can be over: a number, or an instant (`instant?/1`)."
  @spec time?(term()) :: boolean()
  def time?(value) when is_number(value), do: true
  def time?(%DateTime{}), do: true
  def time?(%NaiveDateTime{}), do: true
  def time?(%Date{}), do: true
  def time?(_value), do: false

  @doc """
  Whether a value is an instant: a `DateTime`, a `NaiveDateTime` or a `Date` — what a
  `:time` window field holds (spec/08 §10.1, D-154). A number is not one.

      iex> Visualize.Feed.Window.instant?(~D[2026-10-12])
      true
      iex> Visualize.Feed.Window.instant?(12)
      false
  """
  @spec instant?(term()) :: boolean()
  def instant?(%DateTime{}), do: true
  def instant?(%NaiveDateTime{}), do: true
  def instant?(%Date{}), do: true
  def instant?(_value), do: false

  @doc """
  Whether a window applies to a window field of the type, `:time` or `:number` (spec/08
  §11.2): its bounds instants for `:time`, numbers for `:number`. A `nil` window, and one
  with no bound, applies to either; a window that mixes kinds, or whose bounds are no
  times, applies to neither.

      iex> Visualize.Feed.Window.applies?([~U[2026-10-12 00:00:00Z], nil], :time)
      true
      iex> Visualize.Feed.Window.applies?([~U[2026-10-12 00:00:00Z], nil], :number)
      false
      iex> Visualize.Feed.Window.applies?([0, 10], :number)
      true
  """
  @spec applies?(t(), :time | :number) :: boolean()
  def applies?(nil, _type), do: true

  def applies?([from, to], type) when type in [:time, :number],
    do: of?(from, type) and of?(to, type)

  def applies?(_window, _type), do: false

  defp of?(nil, _type), do: true
  defp of?(value, :number), do: is_number(value)
  defp of?(value, :time), do: instant?(value)

  @doc """
  Whether a time lies within a window: both bounds inclusive, a `nil` bound open, a `nil`
  window everything. A `nil` time lies within no window but `nil`.
  """
  @spec within?(time() | nil, t()) :: boolean()
  def within?(_time, nil), do: true
  def within?(nil, _window), do: false
  def within?(time, [from, to]), do: after_from?(time, from) and before_to?(time, to)

  @doc """
  The rows whose `field` lies within the window (`within?/2`), in their order; every row
  for a `nil` window. The field is read by either spelling (`Visualize.Data.Table.get/2`).
  """
  @spec trim([map()], atom() | String.t(), t()) :: [map()]
  def trim(rows, _field, nil), do: rows
  def trim(rows, field, window), do: Enum.filter(rows, &within?(Table.get(&1, field), window))

  @doc """
  The rows whose `field` lies in `[from, upper)`: `from` inclusive and open when `nil`,
  `upper` exclusive and open when `nil`. The seam of a combination (spec/08 §11.5).

      iex> Visualize.Feed.Window.before([%{t: 1}, %{t: 5}, %{t: 9}], :t, nil, 5)
      [%{t: 1}]
  """
  @spec before([map()], atom() | String.t(), time() | nil, time() | nil) :: [map()]
  def before(rows, field, from, upper) do
    Enum.filter(rows, fn row ->
      time = Table.get(row, field)
      time != nil and after_from?(time, from) and (upper == nil or compare(time, upper) == :lt)
    end)
  end

  @doc """
  The rows whose `field` lies strictly after `time`, every row for `nil`. The seam
  between what a feed holds and a push (spec/08 §11.4).

      iex> Visualize.Feed.Window.newer([%{t: 1}, %{t: 5}, %{t: 9}], :t, 5)
      [%{t: 9}]
  """
  @spec newer([map()], atom() | String.t(), time() | nil) :: [map()]
  def newer(rows, _field, nil), do: rows

  def newer(rows, field, time) do
    Enum.filter(rows, fn row ->
      value = Table.get(row, field)
      value != nil and compare(value, time) == :gt
    end)
  end

  @doc """
  The intersection of two windows, either `nil` for everything. Bounds take the later
  `from` and the earlier `to`.

      iex> Visualize.Feed.Window.intersect([0, 10], [5, nil])
      [5, 10]
  """
  @spec intersect(t(), t()) :: t()
  def intersect(nil, window), do: window
  def intersect(window, nil), do: window
  def intersect([f1, t1], [f2, t2]), do: [latest(f1, f2), earliest(t1, t2)]

  @doc """
  The later of two times, a `nil` ignored.

      iex> Visualize.Feed.Window.latest(nil, 3)
      3
  """
  @spec latest(time() | nil, time() | nil) :: time() | nil
  def latest(nil, b), do: b
  def latest(a, nil), do: a
  def latest(a, b), do: if(compare(a, b) == :lt, do: b, else: a)

  @doc "The earlier of two times, a `nil` ignored."
  @spec earliest(time() | nil, time() | nil) :: time() | nil
  def earliest(nil, b), do: b
  def earliest(a, nil), do: a
  def earliest(a, b), do: if(compare(a, b) == :gt, do: b, else: a)

  @doc """
  A time as a number, for a reduction's `x`: a number itself, a `DateTime` its Unix
  microseconds, a `NaiveDateTime` its Gregorian seconds and a `Date` its Gregorian days.
  Anything else is `nil`, a gap.

      iex> Visualize.Feed.Window.position(~U[1970-01-01 00:00:01Z])
      1000000
  """
  @spec position(term()) :: number() | nil
  def position(value) when is_number(value), do: value
  def position(%DateTime{} = value), do: DateTime.to_unix(value, :microsecond)

  def position(%NaiveDateTime{} = value) do
    {seconds, micro} = NaiveDateTime.to_gregorian_seconds(value)
    seconds + micro / 1_000_000
  end

  def position(%Date{} = value), do: Date.to_gregorian_days(value)
  def position(_value), do: nil

  # -- the box (spec/08 §11.1, D-168) -----------------------------------------------------

  @doc """
  The box a window asks of a schema (spec/08 §11.1, D-168): `%{ranges: ranges, latest:
  boolean}`, or `nil` for no window. A map's absent `ranges` is `%{}` and its absent
  `latest` `false`; the shorthand `[from, to]` is the window field's range where it applies
  to the window field (`applies?/2`), and `nil` — the feed's own span — where it does not
  or the schema has no window field. The box is not checked (`check/2`).

      iex> alias Visualize.Data.Schema
      iex> schema = Schema.new!(%{t: %{type: :number, window: true}, v: %{type: :number}})
      iex> Visualize.Feed.Window.box([0, 10], schema)
      %{ranges: %{t: [0, 10]}, latest: false}
      iex> Visualize.Feed.Window.box([~U[2026-10-14 00:00:00Z], nil], schema)
      nil
      iex> Visualize.Feed.Window.box(%{ranges: %{v: [0, 1]}}, schema)
      %{ranges: %{v: [0, 1]}, latest: false}
  """
  @spec box(Feed.window(), Schema.t()) :: box() | nil
  def box(nil, %Schema{}), do: nil

  def box([_from, _to] = window, %Schema{} = schema) do
    field = Feed.window_field(schema)

    if field != nil and applies?(window, Feed.window_type(schema)),
      do: %{ranges: %{field => window}, latest: false}
  end

  def box(%{} = window, %Schema{}),
    do: %{ranges: Map.get(window, :ranges, %{}), latest: Map.get(window, :latest, false)}

  @doc """
  A field's range of a window (spec/08 §11.1): a box's `ranges` entry for the field, read by
  either spelling of its name; the shorthand `[from, to]` itself, which is the window
  field's; `nil` when there is none. Any other window is returned as it is, so a provider
  that reads its window field's range this way still refuses what it cannot read.

      iex> Visualize.Feed.Window.range(%{ranges: %{"t" => [1, 5], x: [0, 9]}}, :t)
      [1, 5]
      iex> Visualize.Feed.Window.range([1, 5], :t)
      [1, 5]
      iex> Visualize.Feed.Window.range(%{latest: true}, :t)
      nil
  """
  @spec range(term(), atom() | String.t()) :: term()
  def range(%{} = window, field) when not is_struct(window) do
    case Map.get(window, :ranges) do
      %{} = ranges when not is_struct(ranges) ->
        Enum.find_value(ranges, fn {name, range} -> if same?(name, field), do: range end)

      _none ->
        nil
    end
  end

  def range(window, _field), do: window

  defp same?(a, b) when (is_atom(a) or is_binary(a)) and (is_atom(b) or is_binary(b)),
    do: to_string(a) == to_string(b)

  defp same?(_a, _b), do: false

  @doc """
  Whether a schema can answer a window (spec/08 §11.1): `:ok`, or `{:error, faults}`, every
  fault `{path, reason}` from the box to the value, ordered by path. `nil` and the
  shorthand `[from, to]` are `:ok`, as they always were: a shorthand that does not apply is
  the feed's own span. A box is held to the schema — each ranged field described, `:time`
  or `:number`, its range two ends of its type, not inverted — and `latest: true` to a
  window field and a declared identity.

      iex> alias Visualize.Data.Schema
      iex> schema = Schema.new!(%{t: %{type: :number, window: true}, s: %{type: :category}})
      iex> Visualize.Feed.Window.check(%{ranges: %{t: [9, 1], s: ["a", "b"]}, latest: true}, schema)
      {:error,
       [
         {[:latest], {:window, :no_identity}},
         {[:ranges, :s], {:invalid_for, :category}},
         {[:ranges, :t], {:window, :inverted}}
       ]}
  """
  @spec check(term(), Schema.t()) :: :ok | {:error, [{list(), term()}, ...]}
  def check(nil, %Schema{}), do: :ok
  def check([_from, _to], %Schema{}), do: :ok

  def check(%{} = window, %Schema{} = schema) when not is_struct(window) do
    faults =
      for(key <- Map.keys(window), key not in [:ranges, :latest], do: {[key], :unknown_key}) ++
        ranges_faults(Map.get(window, :ranges, %{}), schema) ++
        latest_faults(Map.get(window, :latest, false), schema)

    case Enum.sort_by(faults, &elem(&1, 0)) do
      [] -> :ok
      faults -> {:error, faults}
    end
  end

  def check(_window, %Schema{}), do: {:error, [{[], {:type, :window}}]}

  defp ranges_faults(%{} = ranges, schema) when not is_struct(ranges),
    do: Enum.flat_map(ranges, fn {field, range} -> range_faults(field, range, schema) end)

  defp ranges_faults(_ranges, _schema), do: [{[:ranges], {:type, :ranges}}]

  defp range_faults(field, range, schema) do
    path = [:ranges, field]

    case described(schema, field) do
      nil -> [{path, {:window, :unknown_field}}]
      type when type not in [:time, :number] -> [{path, {:invalid_for, type}}]
      type -> ends_faults(path, range, type)
    end
  end

  defp described(schema, field) when is_atom(field) or is_binary(field) do
    case Schema.fetch(schema, field, :type) do
      {:ok, type} -> type
      :error -> nil
    end
  end

  defp described(_schema, _field), do: nil

  defp ends_faults(path, [from, to], type) do
    case for(
           {end_, i} <- [{from, 0}, {to, 1}],
           not of?(end_, type),
           do: {path ++ [i], {:type, type}}
         ) do
      [] -> order_faults(path, from, to)
      faults -> faults
    end
  end

  defp ends_faults(path, _range, _type), do: [{path, {:type, :range}}]

  defp order_faults(_path, from, to) when from == nil or to == nil, do: []

  defp order_faults(path, from, to) do
    cond do
      kind(from) != kind(to) -> [{path, {:window, :mixed}}]
      compare(from, to) == :gt -> [{path, {:window, :inverted}}]
      true -> []
    end
  end

  defp kind(value) when is_number(value), do: :number
  defp kind(%module{}), do: module

  defp latest_faults(false, _schema), do: []

  defp latest_faults(true, schema) do
    if(Feed.window_field(schema) == nil, do: [{[:latest], {:window, :no_window_field}}], else: []) ++
      if Schema.identity(schema) == [], do: [{[:latest], {:window, :no_identity}}], else: []
  end

  defp latest_faults(_latest, _schema), do: [{[:latest], {:type, :boolean}}]

  @doc """
  Each identity's last row (spec/08 §11.1, D-168): of the rows, for each identity
  `identify` gives a row, the row whose `time` — a function of a row giving a number, as
  `position/1` gives one — is greatest, the later row in order where two tie, kept in their
  order. A row whose identity or time is `nil` names nothing and is dropped. A feed's
  `latest` and a design's `:window` step's (spec/14 §5.4.1) are this function.

      iex> rows = [%{id: "a", t: 1}, %{id: "b", t: 2}, %{id: "a", t: 3}, %{id: nil, t: 4}]
      iex> Visualize.Feed.Window.latest_rows(rows, & &1.t, & &1.id)
      [%{id: "b", t: 2}, %{id: "a", t: 3}]
  """
  @spec latest_rows([map()], (map() -> number() | nil), (map() -> term())) :: [map()]
  def latest_rows(rows, time, identify) when is_function(time, 1) and is_function(identify, 1) do
    last =
      rows
      |> Enum.with_index()
      |> Enum.reduce(%{}, fn {row, i}, last ->
        with id when id != nil <- identify.(row),
             t when t != nil <- time.(row) do
          case Map.fetch(last, id) do
            {:ok, {held, _i}} when held > t -> last
            _later_or_first -> Map.put(last, id, {t, i})
          end
        else
          nil -> last
        end
      end)

    kept = MapSet.new(last, fn {_id, {_t, i}} -> i end)
    for {row, i} <- Enum.with_index(rows), MapSet.member?(kept, i), do: row
  end

  defp after_from?(_time, nil), do: true
  defp after_from?(time, from), do: compare(time, from) != :lt

  defp before_to?(_time, nil), do: true
  defp before_to?(time, to), do: compare(time, to) != :gt
end
