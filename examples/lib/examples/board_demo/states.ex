defmodule Examples.BoardDemo.States do
  @moduledoc """
  Feeds made to put a cell in one state each (spec/15 §8.4, #781, work item #821), so every
  state a board cell can be in is on `/board` at once:

  - `:stale` — a reading every five seconds that stopped ninety seconds ago, past the
    board's `stale_after`, so the chart is drawn under the stale banner with its age;
  - `:no_data` — a feed that answers, with no rows;
  - `:capped` — only the newest twelve readings, the delivery `capped: true`;
  - `:invalid` — `y` is text where the design reads a number, so application reports the
    type mismatch and the cell draws the binding's fault;
  - `:over_budget` — names `:budget` and ships 6,000 readings over the window whatever it
    is asked, past the board's ceiling (spec/15 §8.2, D-227), so the board hands the cell
    no rows and it draws the over-budget panel. It breaks the feed contract on purpose:
    the conformance kit names the overrun (spec/08 §12.3).

  Each answers the board's window as `Examples.BoardDemo.Clock` reads it, and an error value
  for a window it cannot read, as every feed of the demo does.
  """
  @behaviour Visualize.Feed

  alias Examples.BoardDemo.Clock
  alias Visualize.Data.{Delivery, Schema}

  @modes [:stale, :no_data, :capped, :invalid, :over_budget]
  @every 5
  @quiet 90
  @newest 12
  @overrun 6_000

  @enforce_keys [:mode, :schema]
  defstruct [:mode, :schema, clock: &DateTime.utc_now/0]

  @doc "The modes, each the state its cell is drawn in."
  def modes, do: @modes

  @doc "The feed for one mode; `clock:` is the now it reads (`Clock.clock/1`)."
  def new(mode, opts \\ []) when mode in @modes do
    y = if mode == :invalid, do: %{type: :category}, else: %{type: :number}

    %__MODULE__{
      mode: mode,
      clock: Clock.clock(opts),
      schema: Schema.new!(%{x: %{type: :time, label: "Time"}, y: y})
    }
  end

  @impl true
  def describe(%__MODULE__{mode: :over_budget, schema: schema}),
    do: {Schema.version(schema), schema, [:window, :budget]}

  def describe(%__MODULE__{schema: schema}), do: {Schema.version(schema), schema, [:window]}

  @impl true
  def fetch(%__MODULE__{} = feed, window, _budget) do
    now = feed.clock.()

    with {:ok, from, to} <- Clock.window(window, now) do
      {rows, served, capped} = rows(feed.mode, from, to, now)

      {:ok,
       Delivery.new(rows, window: served, capped: capped, schema: Schema.version(feed.schema))}
    end
  end

  defp rows(:no_data, from, to, _now), do: {[], [from, to], false}

  # Evenly over the window, every one of them, whatever budget the feed was asked.
  defp rows(:over_budget, from, to, _now) do
    span = DateTime.diff(to, from, :microsecond)

    rows =
      for i <- 0..(@overrun - 1),
          do: reading(DateTime.add(from, div(span * i, @overrun - 1), :microsecond))

    {rows, [from, to], false}
  end

  # The feed went quiet `@quiet` seconds ago: nothing after then, however late the window.
  defp rows(:stale, from, to, now) do
    last = Enum.min([to, DateTime.add(now, -@quiet)], DateTime)
    {readings(from, last, 200, &reading/1), [from, to], false}
  end

  defp rows(:capped, from, to, _now) do
    {ticks, served, capped} = Clock.ticks(from, to, @every, @newest)
    {for(tick <- ticks, do: reading(DateTime.from_unix!(tick * @every))), served, capped}
  end

  defp rows(:invalid, from, to, _now),
    do:
      {readings(
         from,
         to,
         200,
         &%{x: &1, y: if(rem(DateTime.to_unix(&1), 2) == 0, do: "high", else: "low")}
       ), [from, to], false}

  defp readings(from, to, most, row) do
    if DateTime.compare(from, to) == :gt do
      []
    else
      {ticks, _served, _capped} = Clock.ticks(from, to, @every, most)
      for tick <- ticks, do: row.(DateTime.from_unix!(tick * @every))
    end
  end

  defp reading(t), do: %{x: t, y: Float.round(50 + 30 * :math.sin(DateTime.to_unix(t) / 40), 1)}
end
