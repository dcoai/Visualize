defmodule Visualize.Feed.Signals do
  @moduledoc """
  A signal (`Visualize.Signals`) as a feed: generated, pulled (spec/08 §11.6, D-140).

  The feed's present tick is fixed (`tick:`, moved with `at/2`) or read from a clock
  (`every:` milliseconds per tick). Its schema describes the first field, the tick, as
  its window field — `:number`, since a tick is a count and not an instant, with
  `window: true` and labeled `"Tick"` (spec/08 §10.1, D-154) — and every other field
  `:number`, under whatever `describe:` adds. It honors `:window`: a window is ticks,
  served up to the present tick, at most `limit:` rows and `capped` beyond. A budget is
  left to visualize, and it does not push.

  ## Examples

      iex> signal = Visualize.Signals.new(:discrete, [:t, :n], window: 3)
      iex> feed = Visualize.Feed.Signals.new(signal, tick: 10, describe: %{n: %{label: "Count"}})
      iex> {_version, schema, [:window]} = Visualize.Feed.describe(feed)
      iex> Visualize.Data.Schema.fetch(schema, :n, :label)
      {:ok, "Count"}
      iex> {:ok, delivery} = Visualize.Feed.fetch(feed, [4, 99], nil)
      iex> {Enum.map(delivery.rows, & &1.t), delivery.window}
      {[4, 5, 6, 7, 8, 9, 10], [4, 10]}

  """

  @behaviour Visualize.Feed

  alias Visualize.Data.{Delivery, Schema}
  alias Visualize.Feed
  alias Visualize.Feed.Window
  alias Visualize.Signals

  @enforce_keys [:signal, :schema]
  defstruct [:signal, :schema, tick: 0, every: nil, clock: nil, origin: 0, limit: 10_000]

  @type t :: %__MODULE__{
          signal: Signals.t(),
          schema: Schema.t(),
          tick: non_neg_integer(),
          every: pos_integer() | nil,
          clock: (-> integer()) | nil,
          origin: integer(),
          limit: pos_integer()
        }

  @doc """
  A signal as a feed. Options: `describe:` (descriptions merged over the defaults, field
  by field), `tick:` (the present tick, `0`), `every:` (milliseconds per tick, read from
  `clock:` — a function of no argument in milliseconds, the monotonic clock by default —
  counted from `origin:`, the clock now), and `limit:` (the most rows one fetch serves,
  `10_000`). Raises `ArgumentError` for a description the schema refuses.
  """
  @spec new(Signals.t(), keyword()) :: t()
  def new(%{fields: [time | values]} = signal, opts \\ []) do
    opts =
      Keyword.validate!(opts, [:describe, :every, :clock, :origin, tick: 0, limit: 10_000])

    extra = Keyword.get(opts, :describe, %{})

    defaults =
      values
      |> Map.new(&{&1, %{type: :number}})
      |> Map.put(time, %{type: :number, window: true, label: "Tick"})

    schema = Schema.new!(Map.merge(defaults, extra, fn _field, d, e -> Map.merge(d, e) end))
    clock = opts[:clock] || fn -> System.monotonic_time(:millisecond) end

    %__MODULE__{
      signal: signal,
      schema: schema,
      tick: opts[:tick],
      every: opts[:every],
      clock: if(opts[:every], do: clock),
      origin: opts[:origin] || if(opts[:every], do: clock.(), else: 0),
      limit: opts[:limit]
    }
  end

  @doc "A ticked feed moved to a tick."
  @spec at(t(), non_neg_integer()) :: t()
  def at(%__MODULE__{} = feed, tick) when is_integer(tick) and tick >= 0, do: %{feed | tick: tick}

  @impl Visualize.Feed
  def describe(%__MODULE__{schema: schema}), do: {Schema.version(schema), schema, [:window]}

  @impl Visualize.Feed
  def fetch(%__MODULE__{} = feed, window, _budget) do
    now = present(feed)

    # A box is served by its tick's range; its region and `latest` are the monitor's to
    # finish (spec/08 §11.6, D-168).
    case span(Window.range(window, Feed.window_field(feed.schema)), now, feed.signal) do
      {:ok, from, to} ->
        first = max(from, to - feed.limit + 1)
        rows = Signals.rows(feed.signal, first, to)

        {:ok,
         Delivery.new(rows,
           window: [max(first, 0), to],
           resolution: 1,
           capped: first > max(from, 0),
           schema: Schema.version(feed.schema)
         )}

      :error ->
        {:error, {:window, window}}
    end
  end

  defp present(%__MODULE__{every: nil, tick: tick}), do: tick

  defp present(%__MODULE__{every: every, clock: clock, origin: origin}),
    do: max(div(clock.() - origin, every), 0)

  # The ticks a window asks for, bounded by the present: `nil` is the signal's own window.
  defp span(nil, now, signal), do: {:ok, now - Map.get(signal, :window, 24) + 1, now}

  defp span([from, to], now, _signal)
       when (is_number(from) or is_nil(from)) and (is_number(to) or is_nil(to)) do
    from = if from == nil, do: 0, else: ceil(from)
    to = if to == nil, do: now, else: min(floor(to), now)
    {:ok, from, to}
  end

  defp span(_window, _now, _signal), do: :error
end
