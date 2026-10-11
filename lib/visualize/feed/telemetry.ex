defmodule Visualize.Feed.Telemetry do
  @moduledoc """
  An in-process `:telemetry` provider: a collector over `Telemetry.Metrics` definitions,
  one push feed per metric (spec/08 §11.6, D-140).

  `start_link(metrics: definitions)` attaches one handler for the definitions' events and
  collects. A definition is read by its fields — `name`, `event_name`, `measurement`,
  `tags`, `tag_values`, `keep`, `unit`, `description` — and its struct's name, so this
  library takes no dependency on `telemetry_metrics`. `:telemetry` itself is optional:
  without it the module compiles and the provider is never started.

  Each metric is a feed (`feeds/1`, `feed/2`) whose rows are `%{t: DateTime, value: v}`
  plus the metric's tags, and whose schema says so: `t` the time field, `value` labelled
  with the definition's description (else its name), in the definition's unit as a UCUM
  code (`Visualize.Unit.from_telemetry/1`) with the quantity it implies, each tag a
  category. A counter's value is the count so far for its tags and a sum's the running
  total; a last value's, a summary's and a distribution's the measurement.

  The collector stamps every row on receipt with its own clock, strictly increasing, and
  keeps the newest `keep:` rows of each metric. It honours a window of `DateTime` bounds
  and pushes: every `every:` milliseconds each subscriber gets the rows new since the last
  flush, its schema sent first at subscription.
  """

  use GenServer

  @behaviour Visualize.Feed

  @compile {:no_warn_undefined, :telemetry}

  alias Visualize.Data.{Delivery, Schema}
  alias Visualize.{Quantity, Unit}

  @enforce_keys [:server, :metric]
  defstruct [:server, :metric]

  @type t :: %__MODULE__{server: GenServer.server(), metric: String.t()}

  @kinds %{
    Telemetry.Metrics.Counter => :counter,
    Telemetry.Metrics.Sum => :sum,
    Telemetry.Metrics.LastValue => :last_value,
    Telemetry.Metrics.Summary => :summary,
    Telemetry.Metrics.Distribution => :distribution
  }

  # How long a feed's call waits for the collector before answering `{:error, :timeout}`.
  @call_timeout 5_000

  # -- starting -----------------------------------------------------------------------------

  @doc """
  The collector over `metrics:`, a list of `Telemetry.Metrics` definitions, attached.
  Options: `name:`, `keep:` (rows kept per metric, `10_000`), `every:` (the push interval
  in milliseconds, `1000`; `nil` pushes only on `flush/1`) and `clock:` (a function of no
  argument answering microseconds, `System.os_time(:microsecond)` by default).
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    GenServer.start_link(__MODULE__, opts, if(name, do: [name: name], else: []))
  end

  @doc "Each metric's feed, by its dotted name (`\"vm.memory.total\"`)."
  @spec feeds(GenServer.server()) :: %{String.t() => t()}
  def feeds(server) do
    server
    |> GenServer.call(:names)
    |> Map.new(&{&1, %__MODULE__{server: server, metric: &1}})
  end

  @doc "One metric's feed, by its dotted name. A name the collector lacks answers `{:error, {:unknown_metric, name}}`."
  @spec feed(GenServer.server(), String.t()) :: t()
  def feed(server, name) when is_binary(name), do: %__MODULE__{server: server, metric: name}

  @doc "Every subscriber sent the rows new since the last flush, now."
  @spec flush(GenServer.server()) :: :ok
  def flush(server), do: GenServer.call(server, :flush)

  # -- the feed ------------------------------------------------------------------------------

  @impl Visualize.Feed
  def describe(%__MODULE__{server: server, metric: metric}), do: call(server, {:describe, metric})

  @impl Visualize.Feed
  def fetch(%__MODULE__{server: server, metric: metric}, window, _budget),
    do: call(server, {:fetch, metric, window})

  @impl Visualize.Feed
  def subscribe(%__MODULE__{server: server, metric: metric}, pid) when is_pid(pid),
    do: call(server, {:subscribe, metric, pid})

  @impl Visualize.Feed
  def unsubscribe(%__MODULE__{server: server, metric: metric}, ref) do
    case call(server, {:unsubscribe, metric, ref}) do
      {:error, _reason} -> :ok
      :ok -> :ok
    end
  end

  # A call that answers a value whatever the collector does: it monitors the collector
  # instead of linking the caller's fate to it, and the monitor is an alias, so a reply
  # that arrives after the timeout is dropped rather than left in the caller's mailbox.
  defp call(server, request) do
    case GenServer.whereis(server) do
      nil ->
        {:error, :noproc}

      pid ->
        ref = Process.monitor(pid, alias: :demonitor)
        send(pid, {:"$gen_call", {ref, ref}, request})

        receive do
          {^ref, reply} ->
            Process.demonitor(ref, [:flush])
            reply

          {:DOWN, ^ref, :process, _pid, :noproc} ->
            {:error, :noproc}

          {:DOWN, ^ref, :process, _pid, reason} ->
            {:error, {:down, reason}}
        after
          @call_timeout ->
            Process.demonitor(ref, [:flush])
            {:error, :timeout}
        end
    end
  end

  # -- the handler, in the emitting process ---------------------------------------------------

  @doc false
  # Runs in the process that emits the event, as a reporter's handler does: `keep`, the
  # measurement and the tags are read here, and the collector only stamps and keeps.
  def handle_event(event, measurements, metadata, %{server: server, events: events}) do
    for {index, kind, metric} <- Map.get(events, event, []),
        keep?(metric, metadata, measurements) do
      case measure(kind, metric, measurements, metadata) do
        nil -> :skipped
        value -> send(server, {:measure, index, value, tags(metric, metadata)})
      end
    end

    :ok
  end

  defp keep?(metric, metadata, measurements) do
    case Map.get(metric, :keep) do
      nil -> true
      keep when is_function(keep, 1) -> keep.(metadata)
      keep when is_function(keep, 2) -> keep.(metadata, measurements)
    end
  end

  # A counter counts the event whatever it measured; every other kind reads its measurement.
  defp measure(:counter, _metric, _measurements, _metadata), do: 1

  defp measure(_kind, %{measurement: m}, measurements, _metadata) when is_atom(m),
    do: Map.get(measurements, m)

  defp measure(_kind, %{measurement: m}, measurements, _metadata) when is_function(m, 1),
    do: m.(measurements)

  defp measure(_kind, %{measurement: m}, measurements, metadata) when is_function(m, 2),
    do: m.(measurements, metadata)

  defp tags(%{tags: []}, _metadata), do: %{}

  defp tags(%{tags: tags} = metric, metadata) do
    values = (Map.get(metric, :tag_values) || (& &1)).(metadata)
    Map.new(tags, &{&1, Map.get(values, &1)})
  end

  # -- the collector --------------------------------------------------------------------------

  @impl GenServer
  def init(opts) do
    opts = Keyword.validate!(opts, [:metrics, keep: 10_000, every: 1000, clock: nil])
    clock = opts[:clock] || fn -> System.os_time(:microsecond) end
    Process.flag(:trap_exit, true)

    shared = opts[:metrics] |> Enum.map(&dotted/1) |> Enum.frequencies()

    metrics =
      opts[:metrics]
      |> Enum.with_index()
      |> Map.new(fn {definition, index} -> {index, metric(definition, shared)} end)

    events =
      Enum.group_by(
        Enum.sort(metrics),
        fn {_index, m} -> m.definition.event_name end,
        fn {index, m} -> {index, m.kind, m.definition} end
      )

    id = {__MODULE__, self()}

    :ok =
      :telemetry.attach_many(id, Map.keys(events), &__MODULE__.handle_event/4, %{
        server: self(),
        events: events
      })

    started = clock.()
    if opts[:every], do: Process.send_after(self(), :flush, opts[:every])

    {:ok,
     %{
       id: id,
       metrics: metrics,
       names: Map.new(metrics, fn {index, m} -> {m.name, index} end),
       subscribers: %{},
       keep: opts[:keep],
       every: opts[:every],
       clock: clock,
       last: started,
       started: started
     }}
  end

  defp dotted(definition), do: Enum.map_join(definition.name, ".", &to_string/1)

  # A metric's feed is its dotted name; two definitions of one name (a summary and a
  # counter of `duration`) are each keyed by their kind as well.
  defp metric(%struct{} = definition, shared) do
    kind = Map.fetch!(@kinds, struct)
    dotted = dotted(definition)
    name = if shared[dotted] > 1, do: "#{dotted}:#{kind}", else: dotted

    %{
      definition: definition,
      kind: kind,
      name: name,
      schema: schema(kind, dotted, definition),
      rows: :queue.new(),
      count: 0,
      fresh: [],
      totals: %{},
      coverage: nil
    }
  end

  defp schema(kind, name, definition) do
    value =
      %{type: :number, label: Map.get(definition, :description) || name}
      |> Map.merge(measure_of(kind, definition.unit))

    tags = Map.new(definition.tags, &{&1, %{type: :category}})

    tags
    |> Map.merge(%{t: %{type: :time, label: "Time"}, value: value})
    |> Schema.new!()
  end

  # A counter counts events, whatever unit its definition gives; a unit the mapping
  # refuses leaves the value without a unit rather than a guess.
  defp measure_of(:counter, _unit), do: %{unit: "1", quantity: Quantity.of_unit("1")}

  defp measure_of(_kind, unit) do
    case Unit.from_telemetry(unit) do
      {:ok, code} -> %{unit: code, quantity: Quantity.of_unit(code)} |> drop_nil()
      {:error, _reason} -> %{}
    end
  end

  defp drop_nil(map), do: Map.reject(map, fn {_k, v} -> is_nil(v) end)

  @impl GenServer
  def handle_call(:names, _from, state),
    do: {:reply, state.metrics |> Map.values() |> Enum.map(& &1.name) |> Enum.sort(), state}

  def handle_call(:flush, _from, state), do: {:reply, :ok, push(state)}

  def handle_call({:describe, name}, _from, state) do
    reply =
      with {:ok, m} <- lookup(state, name),
           do: {Schema.version(m.schema), m.schema, [:window, :push]}

    {:reply, reply, state}
  end

  def handle_call({:fetch, name, window}, _from, state) do
    reply =
      with {:ok, m} <- lookup(state, name),
           {:ok, from, to} <- bounds(window) do
        {:ok, served(m, from, to, state)}
      end

    {:reply, reply, state}
  end

  def handle_call({:subscribe, name, pid}, _from, state) do
    case lookup(state, name) do
      {:ok, m} ->
        ref = make_ref()
        monitor = Process.monitor(pid)
        # The handshake: the schema before any delivery, before `subscribe/2` returns.
        send(pid, {:visualize_feed, ref, {:schema, Schema.version(m.schema), m.schema}})
        subscribers = Map.put(state.subscribers, ref, {name, pid, monitor})
        {:reply, {:ok, ref}, %{state | subscribers: subscribers}}

      error ->
        {:reply, error, state}
    end
  end

  def handle_call({:unsubscribe, _name, ref}, _from, state) do
    case Map.pop(state.subscribers, ref) do
      {{_name, _pid, monitor}, subscribers} ->
        Process.demonitor(monitor, [:flush])
        {:reply, :ok, %{state | subscribers: subscribers}}

      {nil, _subscribers} ->
        {:reply, :ok, state}
    end
  end

  defp lookup(state, name) do
    case Map.fetch(state.names, name) do
      {:ok, index} -> {:ok, Map.fetch!(state.metrics, index)}
      :error -> {:error, {:unknown_metric, name}}
    end
  end

  # A window's bounds in microseconds: `DateTime` or `nil`, anything else refused.
  defp bounds(nil), do: {:ok, nil, nil}

  defp bounds([from, to] = window) do
    case {micro(from), micro(to)} do
      {{:ok, f}, {:ok, t}} -> {:ok, f, t}
      _other -> {:error, {:window, window}}
    end
  end

  defp bounds(window), do: {:error, {:window, window}}

  defp micro(nil), do: {:ok, nil}
  defp micro(%DateTime{} = time), do: {:ok, DateTime.to_unix(time, :microsecond)}
  defp micro(_other), do: :error

  # The rows within `[from, to]`, up to the last stamp; the window starts where the
  # collector's data does, and a `from` before that is capped.
  defp served(m, from, to, state) do
    coverage = m.coverage || state.started
    upper = if to, do: min(to, state.last), else: state.last
    lower = if from, do: max(from, coverage), else: coverage

    rows =
      for {stamp, row} <- :queue.to_list(m.rows),
          (from == nil or stamp >= from) and stamp <= upper,
          do: row

    Delivery.new(rows,
      window: [datetime(lower), datetime(upper)],
      capped: from != nil and from < coverage,
      schema: Schema.version(m.schema)
    )
  end

  defp datetime(micro), do: DateTime.from_unix!(micro, :microsecond)

  @impl GenServer
  def handle_info({:measure, index, value, tags}, state) do
    stamp = max(state.clock.(), state.last + 1)
    m = Map.fetch!(state.metrics, index)
    {value, totals} = shown(m.kind, value, tags, m.totals)
    row = tags |> Map.put(:t, datetime(stamp)) |> Map.put(:value, value)
    fresh = if subscribed?(state, m.name), do: [row | m.fresh], else: m.fresh
    m = retained(%{m | totals: totals, fresh: fresh}, {stamp, row}, state.keep)
    {:noreply, %{state | last: stamp, metrics: Map.put(state.metrics, index, m)}}
  end

  def handle_info(:flush, state) do
    if state.every, do: Process.send_after(self(), :flush, state.every)
    {:noreply, push(state)}
  end

  def handle_info({:DOWN, monitor, :process, _pid, _reason}, state) do
    subscribers = Map.reject(state.subscribers, fn {_ref, {_n, _p, m}} -> m == monitor end)
    {:noreply, %{state | subscribers: subscribers}}
  end

  def handle_info({:EXIT, _pid, reason}, state), do: {:stop, reason, state}

  @impl GenServer
  def terminate(_reason, state), do: :telemetry.detach(state.id)

  # Rows wait for a flush only while someone will receive them.
  defp subscribed?(state, name),
    do: Enum.any?(state.subscribers, fn {_ref, {n, _pid, _monitor}} -> n == name end)

  # What a reporter shows: a counter's count so far and a sum's running total, per tag set.
  defp shown(kind, value, tags, totals) when kind in [:counter, :sum] do
    total = Map.get(totals, tags, 0) + value
    {total, Map.put(totals, tags, total)}
  end

  defp shown(_kind, value, _tags, totals), do: {value, totals}

  # The newest `keep` rows; once one is dropped the collector covers from its oldest.
  defp retained(m, entry, keep) do
    rows = :queue.in(entry, m.rows)

    if m.count + 1 > keep do
      {{:value, _dropped}, rows} = :queue.out(rows)
      {:value, {oldest, _row}} = :queue.peek(rows)
      %{m | rows: rows, coverage: oldest}
    else
      %{m | rows: rows, count: m.count + 1}
    end
  end

  # Each metric's rows since the last flush, one delivery to each of its subscribers.
  defp push(state) do
    metrics =
      Map.new(state.metrics, fn
        {index, %{fresh: []} = m} ->
          {index, m}

        {index, m} ->
          rows = Enum.reverse(m.fresh)
          delivery = increment(m, rows)

          for {ref, {name, pid, _monitor}} <- state.subscribers,
              name == m.name,
              do: send(pid, {:visualize_feed, ref, {:delivery, delivery}})

          {index, %{m | fresh: []}}
      end)

    %{state | metrics: metrics}
  end

  defp increment(m, rows) do
    Delivery.new(rows,
      window: [hd(rows).t, List.last(rows).t],
      schema: Schema.version(m.schema)
    )
  end
end
