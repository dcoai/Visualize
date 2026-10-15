defmodule Visualize.Feed.Monitor do
  @moduledoc """
  The loop over a set of feeds, as a value (spec/08 §11.4, D-140).

  A monitor subscribes where a feed can push, polls where it cannot, and hands a chart
  one finished delivery per slot. It is not a process: the process that owns the feeds —
  a board's (#540), a LiveView's — holds it in its state, calls `tick/2` each frame and
  `handle_message/2` from `handle_info/2`, and passes `deliveries/1` and `cache/1` to
  `Visualize.Chart.apply/2` or a compiled chart. That process subscribes, so the pushes
  arrive in its mailbox.

  Pushes buffer, and the next tick drains them: one merge, one trim and one reduction per
  feed per tick, whatever the push rate. A pull feed is polled every `every:`
  milliseconds. Errors and staleness are states, `status/1`, never raises.

  ## Examples

      iex> alias Visualize.Feed.Monitor
      iex> signal = Visualize.Signals.new(:sine, [:t, :v], window: 100)
      iex> feeds = %{wave: Visualize.Feed.Signals.new(signal, tick: 500)}
      iex> monitor = Monitor.new(feeds, budget: 20) |> Monitor.tick(now: 0)
      iex> Monitor.status(monitor)
      %{wave: :live}
      iex> %{wave: delivery} = Monitor.deliveries(monitor)
      iex> {length(delivery.rows), delivery.reduced_by}
      {20, :visualize}

  """

  alias Visualize.Data.{Delivery, Schema, Table}
  alias Visualize.Data.Schema.Cache
  alias Visualize.Feed
  alias Visualize.Feed.Window

  defstruct entries: %{},
            refs: %{},
            cache: %Cache{},
            window: nil,
            budget: nil,
            reduce: :lttb,
            every: 1000,
            stale_after: nil,
            limit: 100_000

  @type name :: term()
  @type status :: :loading | :live | :stale | {:down, term()}

  @type t :: %__MODULE__{
          entries: %{name() => map()},
          refs: %{reference() => name()},
          cache: Cache.t(),
          window: Feed.window(),
          budget: Feed.budget(),
          reduce: :lttb | :m4,
          every: non_neg_integer(),
          stale_after: pos_integer() | nil,
          limit: pos_integer()
        }

  @doc """
  A monitor over a map of feeds by slot name, calling nothing. Options: `window:` and
  `budget:` (the request), `reduce:` (`:lttb` or `:m4`), `every:` (a pull feed's poll
  interval, milliseconds, `1000`), `stale_after:` (milliseconds without an answer before
  a feed is `:stale`, `nil` for never) and `limit:` (the most rows held for a feed whose
  rows cannot be trimmed by a window field, `100_000`).
  """
  @spec new(%{name() => Feed.t()}, keyword()) :: t()
  def new(feeds, opts \\ []) when is_map(feeds) do
    opts =
      Keyword.validate!(opts,
        window: nil,
        budget: nil,
        reduce: :lttb,
        every: 1000,
        stale_after: nil,
        limit: 100_000
      )

    monitor = struct!(__MODULE__, opts)
    %{monitor | entries: Map.new(feeds, fn {name, feed} -> {name, entry(feed)} end)}
  end

  defp entry(feed) do
    %{
      feed: feed,
      supports: nil,
      ref: nil,
      held: nil,
      schema: nil,
      out: nil,
      pending: [],
      refetch: true,
      due: nil,
      last_ok: nil,
      status: :loading,
      error: nil
    }
  end

  @doc """
  One turn of the loop at `now:` (the owner's monotonic clock in milliseconds; read when
  absent): every feed, in name order, is described if it is not yet, fetched if it holds
  nothing, its window moved or its poll is due, its buffered pushes drained, every
  version resolved, and its holding finished for the window and the budget.
  """
  @spec tick(t(), keyword()) :: t()
  def tick(%__MODULE__{} = monitor, opts \\ []) do
    now = Keyword.get_lazy(opts, :now, fn -> System.monotonic_time(:millisecond) end)

    monitor.entries
    |> Map.keys()
    |> Enum.sort()
    |> Enum.reduce(monitor, &step(&2, &1, now))
  end

  defp step(monitor, name, now) do
    monitor = described(monitor, name, now)

    case refused(monitor.window, monitor.entries[name].schema) do
      nil ->
        monitor
        |> fetched(name, now)
        |> drained(name, now)
        |> finished(name, now)

      faults ->
        entry = monitor.entries[name]
        down = %{entry | status: {:down, {:window, faults}}, held: nil, out: nil, pending: []}
        put_entry(monitor, name, down)
    end
  end

  # A box the feed's schema cannot answer is not asked (spec/08 §11.4, D-168): the feed is
  # down with the faults until a window that holds is set. A feed not yet described, and a
  # window that is no box, are never refused here.
  defp refused(_window, nil), do: nil

  defp refused(window, schema) do
    case Window.check(window, schema) do
      :ok -> nil
      {:error, faults} -> faults
    end
  end

  # -- 1. describe and subscribe ----------------------------------------------------------

  defp described(monitor, name, now) do
    entry = monitor.entries[name]

    cond do
      entry.supports != nil -> subscribed(monitor, name, now)
      not due?(entry, now) -> monitor
      true -> describe(monitor, name, now)
    end
  end

  defp describe(monitor, name, now) do
    entry = monitor.entries[name]

    case Feed.describe(entry.feed) do
      {:error, reason} ->
        put_entry(monitor, name, %{entry | status: {:down, reason}, due: now + monitor.every})

      {_version, schema, supports} ->
        monitor = %{monitor | cache: Cache.put(monitor.cache, name, schema)}
        entry = %{entry | supports: supports, schema: entry.schema || schema, due: nil}
        monitor |> put_entry(name, entry) |> subscribed(name, now)
    end
  end

  defp subscribed(monitor, name, now) do
    entry = monitor.entries[name]

    if :push in entry.supports and entry.ref == nil and due?(entry, now) do
      case Feed.subscribe(entry.feed, self()) do
        {:ok, ref} ->
          %{monitor | refs: Map.put(monitor.refs, ref, name)}
          |> put_entry(name, %{entry | ref: ref})

        {:error, reason} ->
          # Polled meanwhile, as a pull feed is; subscribed again when due.
          put_entry(monitor, name, %{entry | status: {:down, reason}, due: now + monitor.every})
      end
    else
      monitor
    end
  end

  defp due?(%{due: nil}, _now), do: true
  defp due?(%{due: due}, now), do: now >= due

  # -- 2. fetch ---------------------------------------------------------------------------

  defp fetched(monitor, name, now) do
    entry = monitor.entries[name]

    cond do
      entry.supports == nil -> monitor
      fetch?(entry, now) -> fetch(monitor, name, now)
      true -> monitor
    end
  end

  defp fetch?(%{held: nil, due: due}, now), do: due == nil or now >= due
  defp fetch?(%{refetch: true}, _now), do: true
  defp fetch?(%{ref: nil, due: due}, now), do: due == nil or now >= due
  defp fetch?(_entry, _now), do: false

  defp fetch(monitor, name, now) do
    entry = monitor.entries[name]
    poll = %{entry | due: now + monitor.every}

    case Feed.fetch(entry.feed, request(monitor.window, entry.schema), monitor.budget) do
      {:error, reason} ->
        put_entry(monitor, name, %{poll | status: {:down, reason}})

      {:ok, delivery} ->
        case resolve(monitor, name, delivery) do
          {:ok, delivery, schema, monitor} ->
            held = %{delivery | rows: Table.rows(delivery)}
            entry = %{poll | held: held, schema: schema, refetch: false}
            put_entry(monitor, name, live(entry, now))

          {:error, reason, monitor} ->
            put_entry(monitor, name, %{poll | status: {:down, reason}, error: reason})
        end
    end
  end

  # A delivery's version, resolved through the cache and the feed's describe once
  # (spec/08 §11.3). A delivery naming none is the feed's described schema.
  defp resolve(monitor, name, %Delivery{schema: nil} = delivery) do
    entry = monitor.entries[name]
    {:ok, %{delivery | schema: Schema.version(entry.schema)}, entry.schema, monitor}
  end

  defp resolve(monitor, name, %Delivery{schema: version} = delivery) do
    feed = monitor.entries[name].feed
    describe = Feed.describer(%{name => feed})

    case Cache.resolve(monitor.cache, name, version, describe) do
      {:ok, schema, cache} -> {:ok, delivery, schema, %{monitor | cache: cache}}
      {:error, reason, cache} -> {:error, reason, %{monitor | cache: cache}}
    end
  end

  defp live(entry, now), do: %{entry | status: :live, last_ok: now, error: nil}

  # -- 3. drain the pushes ----------------------------------------------------------------

  defp drained(monitor, name, now) do
    entry = monitor.entries[name]

    entry.pending
    |> Enum.reverse()
    |> Enum.reduce(put_entry(monitor, name, %{entry | pending: []}), fn delivery, monitor ->
      case resolve(monitor, name, delivery) do
        {:ok, delivery, schema, monitor} ->
          entry = monitor.entries[name]
          held = merge(entry.held, delivery, schema, monitor.limit)
          put_entry(monitor, name, live(%{entry | held: held, schema: schema}, now))

        {:error, reason, monitor} ->
          put_entry(monitor, name, %{monitor.entries[name] | error: reason})
      end
    end)
  end

  # A push merged into the holding: by the window field, its rows strictly after what the
  # holding covers appended, and its late rows — at or before that — kept unless the
  # holding already has the very row, placed in time order when the holding is finished
  # (spec/15 §8.5, D-146); without a window field every row, keeping the newest `limit`.
  defp merge(nil, delivery, _schema, _limit), do: %{delivery | rows: Table.rows(delivery)}

  defp merge(held, delivery, schema, limit) do
    rows = Table.rows(delivery)

    case Feed.window_field(schema) do
      nil ->
        all = held.rows ++ rows
        cut = max(length(all) - limit, 0)

        %{held | rows: Enum.drop(all, cut), schema: delivery.schema}
        |> Map.update!(:capped, &(&1 or cut > 0))

      time ->
        held_to = window_to(held) || newest(held.rows, time)
        newer = Window.newer(rows, time, held_to)
        late = late(held.rows, rows, time, held_to)
        to = Window.latest(held_to, window_to(delivery) || newest(newer, time))
        from = window_from(held)

        %{held | rows: held.rows ++ late ++ newer, schema: delivery.schema, window: [from, to]}
    end
  end

  # The pushed rows at or before the holding's end that it does not already hold: only the
  # held rows from the earliest late time on are compared, so a push at the edge costs
  # little.
  defp late(_held, _rows, _time, nil), do: []

  defp late(held, rows, time, held_to) do
    case Enum.filter(rows, &late?(Table.get(&1, time), held_to)) do
      [] ->
        []

      late ->
        earliest = late |> Enum.map(&Table.get(&1, time)) |> Enum.reduce(&Window.earliest/2)

        seen =
          held
          |> Enum.filter(&(Window.compare(Table.get(&1, time), earliest) != :lt))
          |> MapSet.new()

        late |> Enum.reject(&MapSet.member?(seen, &1)) |> Enum.uniq()
    end
  end

  # A row with no time is not late, and `Window.newer/3` leaves it out as well.
  defp late?(t, held_to) do
    case {place(t), place(held_to)} do
      {nil, _held} -> false
      {_t, nil} -> false
      {t, held} -> t <= held
    end
  end

  defp window_from(%Delivery{window: [from, _to]}), do: from
  defp window_from(_delivery), do: nil

  defp window_to(%Delivery{window: [_from, to]}), do: to
  defp window_to(_delivery), do: nil

  defp newest(rows, time), do: Enum.reduce(rows, nil, &Window.latest(&2, Table.get(&1, time)))

  # -- 4. finish --------------------------------------------------------------------------

  defp finished(monitor, name, now) do
    entry = monitor.entries[name]

    case entry.held do
      nil ->
        monitor

      held ->
        # The holding is trimmed whatever the feed honors, so pushes never grow it past
        # the window; the delivery handed out is reduced for the budget.
        window = request(monitor.window, entry.schema)
        held = held |> ordered(entry.schema) |> Feed.finish(entry.schema, window: window)

        out =
          Feed.finish(held, entry.schema,
            supports: entry.supports,
            budget: monitor.budget,
            reduce: monitor.reduce
          )

        put_entry(monitor, name, stale(%{entry | held: held, out: out}, now, monitor))
    end
  end

  # The holding in window-field order (spec/08 §11.4): a stable sort, only when a row is out of
  # order, so a reduction reads its rows in `x` order and rows that tie keep theirs.
  defp ordered(held, schema) do
    case Feed.window_field(schema) do
      nil ->
        held

      time ->
        rows = held.rows

        if in_order?(rows, time),
          do: held,
          else: %{held | rows: Enum.sort_by(rows, &place(Table.get(&1, time)), &not_after?/2)}
    end
  end

  defp in_order?(rows, time) do
    rows
    |> Enum.reduce_while(nil, fn row, last ->
      t = place(Table.get(row, time))
      if not_after?(last, t), do: {:cont, t}, else: {:halt, :out}
    end)
    |> Kernel.!=(:out)
  end

  # A time as the number it is ordered by (`Window.position/1`), `nil` for a value that is
  # no time: a feed's bad row is ordered first and drawn as the cell decides, never a raise
  # in the owner's process.
  defp place(value), do: if(Window.time?(value), do: Window.position(value))

  # Time order with a row that has no time first, as `nil` is no instant.
  defp not_after?(nil, _b), do: true
  defp not_after?(_a, nil), do: false
  defp not_after?(a, b), do: a <= b

  defp stale(%{status: :live, last_ok: last} = entry, now, %{stale_after: after_ms})
       when is_integer(after_ms) and now - last > after_ms,
       do: %{entry | status: :stale}

  defp stale(entry, _now, _monitor), do: entry

  defp put_entry(monitor, name, entry),
    do: %{monitor | entries: Map.put(monitor.entries, name, entry)}

  # -- the owner's calls ------------------------------------------------------------------

  @doc """
  A message the owner received: `{:ok, monitor}` with a push buffered or a pushed schema
  cached (spec/08 §11.3), `:ignore` for any other message. A push of a subscription the
  monitor no longer holds is dropped.
  """
  @spec handle_message(t(), term()) :: {:ok, t()} | :ignore
  def handle_message(%__MODULE__{} = monitor, {:visualize_feed, ref, message})
      when is_reference(ref) do
    case Map.fetch(monitor.refs, ref) do
      {:ok, name} -> {:ok, received(monitor, name, message)}
      :error -> {:ok, monitor}
    end
  end

  def handle_message(%__MODULE__{}, _message), do: :ignore

  defp received(monitor, name, {:schema, _version, %Schema{} = schema}),
    do: %{monitor | cache: Cache.put(monitor.cache, name, schema)}

  defp received(monitor, name, {:delivery, %Delivery{} = delivery}) do
    entry = monitor.entries[name]
    put_entry(monitor, name, %{entry | pending: [delivery | entry.pending]})
  end

  @doc """
  The monitor with a new window. Each feed is asked the window that applies to its window
  field (spec/08 §11.2, D-154) — a feed over ticks is asked `nil`, its own span, by a
  window of instants, and is neither trimmed nor refetched as that window moves. A pull
  feed fetches at the next tick; a push feed only when the window starts before what it
  holds covers, and is otherwise trimmed.
  """
  @spec window(t(), Feed.window()) :: t()
  def window(%__MODULE__{window: window} = monitor, window), do: monitor

  def window(%__MODULE__{} = monitor, window) do
    entries =
      Map.new(monitor.entries, fn {name, entry} ->
        asked = request(window, entry.schema)
        was = request(monitor.window, entry.schema)
        moved? = asked != was

        {name, %{entry | refetch: entry.refetch or (moved? and not covers?(entry, was, asked))}}
      end)

    %{monitor | window: window, entries: entries}
  end

  # The window a feed is asked (spec/08 §11.2): the monitor's where it applies to the
  # feed's window field, or the feed has none or is not yet described; else `nil`. A box
  # is asked as it is (§11.1), checked against the schema before it is (`step/3`).
  defp request(window, nil), do: window
  defp request(%{} = box, _schema), do: box

  defp request(window, schema) do
    case Feed.window_type(schema) do
      nil -> window
      type -> if Window.applies?(window, type), do: window
    end
  end

  # Whether a push feed's holding answers the new window without a fetch (spec/08 §11.4):
  # its window field's range starts within what it holds, and a box's other ranges and its
  # `latest` are the old one's — under `latest`, with a `to` no earlier, since a holding of
  # the latest rows cannot give the rows an earlier `to` would make the latest.
  defp covers?(%{ref: nil}, _was, _asked), do: false
  defp covers?(%{schema: nil}, _was, _asked), do: false

  defp covers?(%{schema: schema} = entry, was, asked) do
    time = Feed.window_field(schema)
    old = Window.box(was, schema)
    new = Window.box(asked, schema)

    same_rest?(old, new, time) and to_kept?(old, new, time) and
      from_held?(entry, Window.range(new, time))
  end

  defp from_held?(%{held: %Delivery{window: [held, _]}}, [from, _])
       when held != nil and from != nil,
       do: Window.compare(from, held) != :lt

  defp from_held?(_entry, _range), do: false

  defp same_rest?(old, new, time), do: rest(old, time) == rest(new, time)

  defp rest(nil, _time), do: {%{}, false}

  defp rest(%{ranges: ranges, latest: latest}, time) do
    {Map.new(for {f, r} <- ranges, to_string(f) != to_string(time), do: {to_string(f), r}),
     latest}
  end

  defp to_kept?(%{latest: true} = old, new, time) do
    case {end_of(old, time), end_of(new, time)} do
      {_old, nil} -> true
      {nil, _new} -> false
      {old, new} -> Window.compare(new, old) != :lt
    end
  end

  defp to_kept?(_old, _new, _time), do: true

  defp end_of(box, time) do
    case Window.range(box, time) do
      [_from, to] -> to
      _none -> nil
    end
  end

  @doc """
  Every feed fetched again at the next tick, push feeds included, whatever it holds
  (spec/08 §11.4): what a board does when a person sets its window (spec/15 §8.2).
  """
  @spec refetch(t()) :: t()
  def refetch(%__MODULE__{} = monitor) do
    %{
      monitor
      | entries: Map.new(monitor.entries, fn {name, e} -> {name, %{e | refetch: true}} end)
    }
  end

  @doc "The monitor with a new budget, refinished at the next tick."
  @spec budget(t(), Feed.budget()) :: t()
  def budget(%__MODULE__{} = monitor, budget), do: %{monitor | budget: budget}

  @doc "A feed added or replaced under a name: the old one unsubscribed, the new one described at the next tick."
  @spec put(t(), name(), Feed.t()) :: t()
  def put(%__MODULE__{} = monitor, name, feed) do
    monitor = remove(monitor, name)
    put_entry(monitor, name, entry(feed))
  end

  @doc "A feed dropped, unsubscribed."
  @spec remove(t(), name()) :: t()
  def remove(%__MODULE__{} = monitor, name) do
    case Map.fetch(monitor.entries, name) do
      {:ok, entry} ->
        unsubscribe(entry)
        refs = Map.reject(monitor.refs, fn {_ref, n} -> n == name end)
        %{monitor | entries: Map.delete(monitor.entries, name), refs: refs}

      :error ->
        monitor
    end
  end

  @doc "Every push feed unsubscribed; the monitor's end."
  @spec stop(t()) :: :ok
  def stop(%__MODULE__{entries: entries}) do
    Enum.each(entries, fn {_name, entry} -> unsubscribe(entry) end)
  end

  defp unsubscribe(%{ref: nil}), do: :ok
  defp unsubscribe(%{feed: feed, ref: ref}), do: Feed.unsubscribe(feed, ref)

  # -- the answers ------------------------------------------------------------------------

  @doc "The finished delivery of every feed that has one, by name: a pool."
  @spec deliveries(t()) :: %{name() => Delivery.t()}
  def deliveries(%__MODULE__{entries: entries}),
    do: for({name, %{out: %Delivery{} = out}} <- entries, into: %{}, do: {name, out})

  @doc "Each feed's state: `:loading`, `:live`, `:stale` or `{:down, reason}`."
  @spec status(t()) :: %{name() => status()}
  def status(%__MODULE__{entries: entries}),
    do: Map.new(entries, fn {name, entry} -> {name, entry.status} end)

  @doc "Each feed's last unresolved delivery reason, for the feeds that have one."
  @spec errors(t()) :: %{name() => term()}
  def errors(%__MODULE__{entries: entries}),
    do: for({name, %{error: error}} <- entries, error != nil, into: %{}, do: {name, error})

  @doc "The schema cache, holding every version the deliveries name: `apply/2`'s `schemas:`."
  @spec cache(t()) :: Cache.t()
  def cache(%__MODULE__{cache: cache}), do: cache
end
