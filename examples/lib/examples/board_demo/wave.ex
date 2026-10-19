defmodule Examples.BoardDemo.Wave do
  @moduledoc """
  A `Visualize.Signals` signal on the wall clock (spec/08 §8, §11.6): the library's
  `Visualize.Feed.Signals` provider ticking once a second from an origin fifteen minutes
  before the feed was made, its tick read as that instant in UTC. A board's window is in
  UTC (spec/15 §1.5), and a signal counts ticks, so this is the one conversion between
  them: a window of instants asked as ticks, and the rows' ticks answered as instants.
  """
  @behaviour Visualize.Feed

  alias Visualize.Data.{Delivery, Schema}

  @enforce_keys [:inner, :origin, :every, :schema]
  defstruct [:inner, :origin, :every, :schema]

  @doc "A signal ticking every `every:` milliseconds (`1000`), with fifteen minutes behind it."
  def new(%{fields: [time | values]} = signal, opts \\ []) do
    every = Keyword.get(opts, :every, 1000)
    origin = System.os_time(:millisecond) - 15 * 60 * 1000
    clock = fn -> System.os_time(:millisecond) end
    inner = Visualize.Feed.Signals.new(signal, every: every, clock: clock, origin: origin)

    # A reading is one tick apart; three missed in a row is a gap (spec/08 §10.1).
    fields =
      values
      |> Map.new(&{&1, %{type: :number, continuity: every * 3 / 1000}})
      |> Map.put(time, %{type: :time, label: "Time"})

    %__MODULE__{inner: inner, origin: origin, every: every, schema: Schema.new!(fields)}
  end

  @impl true
  def describe(%__MODULE__{schema: schema}), do: {Schema.version(schema), schema, [:window]}

  @impl true
  def fetch(%__MODULE__{} = feed, window, budget) do
    with {:ok, ticks} <- ticks(feed, window),
         {:ok, %Delivery{} = delivery} <- Visualize.Feed.fetch(feed.inner, ticks, budget) do
      [time | _values] = feed.inner.signal.fields
      rows = Enum.map(delivery.rows, &Map.update!(&1, time, fn tick -> instant(feed, tick) end))
      window = delivery.window && Enum.map(delivery.window, &(&1 && instant(feed, &1)))

      {:ok, %{delivery | rows: rows, window: window, schema: Schema.version(feed.schema)}}
    end
  end

  # The window as ticks: the first tick at or after its start and the last at or before its
  # end, to the microsecond, so no reading is served outside the window asked (spec/08 §12).
  # A window of anything but instants is not one this feed can read: an error value.
  defp ticks(_feed, nil), do: {:ok, nil}

  defp ticks(feed, [from, to] = window) when from != nil or to != nil do
    if Enum.all?(window, &(&1 == nil or is_struct(&1, DateTime))),
      do:
        {:ok, [from && ceil(ms(from, feed) / feed.every), to && floor(ms(to, feed) / feed.every)]},
      else: {:error, {:window, window}}
  end

  defp ticks(_feed, window), do: {:error, {:window, window}}

  defp ms(%DateTime{} = t, feed), do: DateTime.to_unix(t, :microsecond) / 1000 - feed.origin

  defp instant(feed, tick),
    do: DateTime.from_unix!(feed.origin + tick * feed.every, :millisecond)
end
