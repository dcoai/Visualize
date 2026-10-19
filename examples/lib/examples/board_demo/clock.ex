defmodule Examples.BoardDemo.Clock do
  @moduledoc """
  The window a wall-clock feed of the board demo serves (spec/08 §10.2, §11.2): what the
  demo's feeds share so each honors the contract the conformance kit holds it to
  (`examples/test/examples/board_demo_feeds_test.exs`, spec/08 §12).

  A window is over instants. `nil` is the feed's own span, the last five minutes; an open
  end is closed at now or five minutes before the other end; an end past now is now, since
  no reading is held beyond it. Anything else — numbers, a box of ranges, a mixed pair —
  is not a window such a feed can read, and is an error value, never a raise.

  The readings fall on whole multiples of a feed's period, and a window's bounds may fall
  anywhere between them, to the microsecond: the first reading served is the first at or
  after the window's start *to the microsecond*, so no row lies outside the window a
  delivery says it served, whatever the sub-second phase of the clock (spec/08 §12).

  Each feed reads now from its own `clock`, `DateTime.utc_now/0` unless it is given one
  (`clock/1`), so a test can pin it at the phase that matters.
  """

  @span 300

  @doc """
  The bounds a window asks for, closed and clamped at now: `{:ok, from, to}`, or
  `{:error, {:window, window}}` for a window this feed cannot read.
  """
  @spec window(term(), DateTime.t()) :: {:ok, DateTime.t(), DateTime.t()} | {:error, term()}
  def window(window, now \\ DateTime.utc_now())

  def window(nil, now), do: {:ok, DateTime.add(now, -@span), now}

  def window([from, to] = window, now) when (from != nil or to != nil) and length(window) == 2 do
    if instant?(from) and instant?(to) do
      to = if to == nil or DateTime.compare(to, now) == :gt, do: now, else: to
      from = from || DateTime.add(to, -@span)
      {:ok, from, if(DateTime.compare(from, to) == :gt, do: from, else: to)}
    else
      {:error, {:window, window}}
    end
  end

  def window(window, _now), do: {:error, {:window, window}}

  defp instant?(value), do: value == nil or is_struct(value, DateTime)

  @doc "A feed's clock from its options: `clock:`, a function of no argument answering a UTC `DateTime`."
  @spec clock(keyword()) :: (-> DateTime.t())
  def clock(opts), do: Keyword.get(opts, :clock, &DateTime.utc_now/0)

  @doc """
  The readings `every` seconds apart from `from` to `to`, at most `most` of them, newest
  kept: the ticks, the window they serve and whether `most` cut the answer short.
  """
  @spec ticks(DateTime.t(), DateTime.t(), pos_integer(), pos_integer()) ::
          {Range.t(), [DateTime.t()], boolean()}
  def ticks(from, to, every, most) do
    step = every * 1_000_000
    asked = ceil_div(DateTime.to_unix(from, :microsecond), step)
    last = Integer.floor_div(DateTime.to_unix(to, :microsecond), step)
    first = max(asked, last - most + 1)
    served = if first > asked, do: DateTime.from_unix!(first * every), else: from
    {first..last//1, [served, to], first > asked}
  end

  defp ceil_div(n, d), do: -Integer.floor_div(-n, d)
end
