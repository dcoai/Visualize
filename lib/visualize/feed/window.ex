defmodule Visualize.Feed.Window do
  @moduledoc """
  Windows over a feed's time field (spec/08 §11.2, D-140).

  A window is `nil` — whatever a feed holds — or `[from, to]`, either bound `nil` for
  open. Its bounds are values of the feed's time field: numbers, or `DateTime`,
  `NaiveDateTime` or `Date` values, a window and a column of one kind. These are the
  comparisons, the trim and the numeric position that `Visualize.Feed.finish/3`,
  `Visualize.Feed.Monitor` and `Visualize.Feed.Combine` share.

  ## Examples

      iex> Visualize.Feed.Window.within?(5, [0, 10])
      true
      iex> Visualize.Feed.Window.within?(~U[2026-10-11 12:00:00Z], [~U[2026-10-11 13:00:00Z], nil])
      false
      iex> Visualize.Feed.Window.trim([%{t: 1}, %{t: 5}, %{t: 9}], :t, [2, nil])
      [%{t: 5}, %{t: 9}]

  """

  alias Visualize.Data.Table

  @type time :: number() | DateTime.t() | NaiveDateTime.t() | Date.t()
  @type t :: [time() | nil] | nil

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

  @doc "Whether a time is a value a window can be over: a number, a `DateTime`, a `NaiveDateTime` or a `Date`."
  @spec time?(term()) :: boolean()
  def time?(value) when is_number(value), do: true
  def time?(%DateTime{}), do: true
  def time?(%NaiveDateTime{}), do: true
  def time?(%Date{}), do: true
  def time?(_value), do: false

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

  defp after_from?(_time, nil), do: true
  defp after_from?(time, from), do: compare(time, from) != :lt

  defp before_to?(_time, nil), do: true
  defp before_to?(time, to), do: compare(time, to) != :gt
end
