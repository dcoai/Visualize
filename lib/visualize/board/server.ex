defmodule Visualize.Board.Server do
  @moduledoc """
  A live board: one process that owns the board's shared state and its feeds, and one
  process per cell under it (spec/15 §8, D-146).

  The board process owns the window (in UTC), the zone, the variables, the sync group
  and the board's single **now**, read once per turn from `clock:`. It holds the
  `Visualize.Feed.Monitor` over the host's feeds (spec/08 §11.4, D-140): each turn it
  resolves the window at now, ticks the monitor, and hands each cell its slots'
  deliveries, schemas and statuses. Pushes reach the monitor through this process's
  mailbox. Setting a window (`window/2`) re-asks every feed.

  The board also holds what its cells share when a person acts on one of them (spec/15
  §13, D-151): a brushed window (`brush/2`), applied once rapid brushes settle and undone
  by `reset_window/1`, and the one selection (`select/2`), its field read through the
  board's `links` and sent to every cell, which dims the data that do not hold it.
  `pick/4` reads the row behind a cell's keyboard point from that cell's process.

  Each cell is a `Visualize.Board.Cell`: heap-limited, `:temporary` under a
  `DynamicSupervisor` this process starts and is the parent of, and monitored here. A
  cell that dies is shown `{:crashed, reason}` to every subscriber at once and started
  again after a backoff — 100 ms, doubling to 10 s, reset after 30 s alive — so a design
  that dies on every frame never takes a supervisor's restart intensity, its siblings or
  the board with it.

  ## Starting

      children = [{Visualize.Board.Supervisor, name: MyApp.Boards}]

      {:ok, board} =
        Visualize.Board.Server.start(MyApp.Boards,
          board: board, store: store, binding: binding, feeds: feeds)

      {:ok, info} = Visualize.Board.Server.subscribe(board)

      def handle_info({:visualize_board, _board, {:cell, name, view}}, socket), do: …

  A board that does not validate given its store, or whose binding names a feed `feeds:`
  does not hold, is not started: `{:error, {:board, errors}}` or `{:error, {:feeds,
  names}}`, before any process runs.

  ## Options

    * `:board` - the `%Visualize.Board{}` (required)
    * `:store` - what resolution reads, spec/15 §3.2 (required)
    * `:binding` - the connector's `%Visualize.Board.Binding{}` (default empty)
    * `:feeds` - the feeds by the names the binding uses (default `%{}`)
    * `:theme` - the theme the cells and their states are drawn in
      (default `Visualize.Theme.default/0`)
    * `:system` - the unit system every cell's measures are shown in, `:metric`, `:us`,
      `:uk` or `:as_posted` (default); a viewer's preference, so a host serving several
      runs a board per system (spec/14 §4.4, D-156)
    * `:generators` - the generator modules (spec/14 §3.13) every cell's component is read
      with and every cell's frames call, beside `config :visualize, generators:`
      (default `[]`)
    * `:assigns` - the host's assigns every generator's context carries: the viewer's, so
      a host whose generators read the viewer runs a board per viewer (default `%{}`)
    * `:width` - the container width in pixels until a `resize/2` (default `1200`)
    * `:tick` - the data rate, milliseconds between turns; `nil` turns only on `tick/1`
      (default `1000`)
    * `:budget` - the point budget asked of every feed (default `nil`)
    * `:max_heap` - each cell's heap limit in words (default `25_000_000`)
    * `:clock` - the board's now, a function of no argument answering a UTC `DateTime`
      (default `DateTime.utc_now/0`)
    * `:limits` - the limits the components' designs are read under
    * `:boards` - the boards the cells' drill targets may name, as
      `Visualize.Board.validate/3` takes them (default `%{}`)
    * `:debounce` - milliseconds a brushed window waits for the next (default `250`);
      `0` applies each at once
    * `:name` - a registered name
  """

  use GenServer, restart: :transient

  alias Visualize.Board
  alias Visualize.Board.{Binding, Cell, Snapshot, State, View}
  alias Visualize.Data.Schema.Cache
  alias Visualize.Feed.Monitor

  @backoff 100
  @backoff_max 10_000
  @settled 30_000

  @type info :: %{
          board: Board.t(),
          window: {DateTime.t(), DateTime.t()} | nil,
          zone: String.t(),
          now: DateTime.t() | nil,
          width: number(),
          sync: String.t() | nil,
          selection: Board.identity() | nil,
          moved: boolean(),
          cells: %{atom() => %{pid: pid() | nil, state: State.t(), restarts: non_neg_integer()}}
        }

  # -- starting -----------------------------------------------------------------------------

  @doc """
  A board started under a `DynamicSupervisor` (spec/15 §8.1): `{:ok, pid}`, or
  `{:error, {:board, errors}}` or `{:error, {:feeds, names}}` for a board that cannot run.
  """
  @spec start(Supervisor.supervisor(), keyword()) :: DynamicSupervisor.on_start_child()
  def start(supervisor, opts), do: DynamicSupervisor.start_child(supervisor, {__MODULE__, opts})

  @doc "A board started linked to the caller, for a host's own supervisor; as `start/2` answers."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    with {:ok, prepared} <- prepare(opts) do
      case Keyword.fetch(opts, :name) do
        {:ok, name} -> GenServer.start_link(__MODULE__, prepared, name: name)
        :error -> GenServer.start_link(__MODULE__, prepared)
      end
    end
  end

  # Everything a board needs, checked in the caller before a process runs (spec/15 §8.2):
  # its components and slots through the store, and every feed its binding names.
  defp prepare(opts) do
    opts =
      Keyword.validate!(opts, [
        :board,
        :store,
        :name,
        :limits,
        boards: %{},
        debounce: 250,
        binding: Binding.new(),
        feeds: %{},
        theme: Visualize.Theme.default(),
        system: :as_posted,
        generators: [],
        assigns: %{},
        width: 1200,
        tick: 1000,
        budget: nil,
        max_heap: 25_000_000,
        clock: &DateTime.utc_now/0
      ])

    board = Keyword.fetch!(opts, :board)
    store = Keyword.fetch!(opts, :store)
    limits = Keyword.take(opts, [:limits, :generators])

    with {:ok, components} <-
           board_check(
             Board.components(board, store, Keyword.take(opts, [:limits, :boards, :generators]))
           ),
         {:ok, required} <- board_check(Board.required_sources(board, store, limits)),
         :ok <- feeds_check(opts[:binding], opts[:feeds]) do
      needs =
        Enum.reduce(Map.keys(required), Map.new(board.cells, fn {name, _} -> {name, []} end), fn
          {cell, slot}, acc -> Map.update!(acc, cell, &[slot | &1])
        end)

      {:ok, opts |> Map.new() |> Map.merge(%{components: components, needs: needs})}
    end
  end

  defp board_check({:ok, value}), do: {:ok, value}
  defp board_check({:error, errors}), do: {:error, {:board, errors}}

  defp feeds_check(%Binding{slots: slots}, feeds) do
    case slots |> Map.values() |> Enum.uniq() |> Enum.reject(&Map.has_key?(feeds, &1)) do
      [] -> :ok
      missing -> {:error, {:feeds, Enum.sort(missing)}}
    end
  end

  # -- the API ------------------------------------------------------------------------------

  @doc "As `subscribe/2` for the caller."
  @spec subscribe(GenServer.server()) :: {:ok, info()}
  def subscribe(board), do: subscribe(board, self())

  @doc """
  `pid` subscribed to the board's messages (spec/15 §8.2): `{:ok, info}`, and every cell
  sends it its present view. Every message is `{:visualize_board, board, message}`, with
  `message` `{:board, info}` or `{:cell, name, view}`.
  """
  @spec subscribe(GenServer.server(), pid()) :: {:ok, info()}
  def subscribe(board, pid) when is_pid(pid), do: GenServer.call(board, {:subscribe, pid})

  @doc "A subscriber removed; `:ok`."
  @spec unsubscribe(GenServer.server(), pid()) :: :ok
  def unsubscribe(board, pid) when is_pid(pid), do: GenServer.call(board, {:unsubscribe, pid})

  @doc """
  The board's window set — `nil`, `%{last: seconds}` or `%{from: t, to: t}` in UTC — and
  every feed re-asked (spec/15 §8.2): `:ok`, or `{:error, errors}` for a window the board
  refuses (spec/15 §3.1). The turn runs at once.
  """
  @spec window(GenServer.server(), Board.window()) :: :ok | {:error, [Board.error(), ...]}
  def window(board, window), do: GenServer.call(board, {:window, window})

  @doc """
  A brushed window (spec/15 §13.1): validated at once — `:ok`, or `{:error, errors}` as
  `window/2` answers — and set as `window/2` sets it once `debounce:` milliseconds pass
  with no later brush, so rapid brushes re-ask every feed once, for the last.
  """
  @spec brush(GenServer.server(), Board.window()) :: :ok | {:error, [Board.error(), ...]}
  def brush(board, window), do: GenServer.call(board, {:brush, window})

  @doc "The window the board was started with, set as `window/2` sets it (spec/15 §13.1)."
  @spec reset_window(GenServer.server()) :: :ok
  def reset_window(board), do: GenServer.call(board, :reset_window)

  @doc """
  The board's selection (spec/15 §13.2): `{field, value}`, or a map from field to value
  for a composite identity (D-167), each field read through the board's `links`, or `nil`
  to clear it. A map of one field is held as its pair. Every cell is sent it, and every
  subscriber the board's info. `:ok`.
  """
  @spec select(GenServer.server(), Board.identity() | nil) :: :ok
  def select(board, nil), do: GenServer.call(board, {:select, nil})

  def select(board, {field, _value} = identity) when is_atom(field) or is_binary(field),
    do: GenServer.call(board, {:select, identity})

  def select(board, identity) when is_map(identity) and map_size(identity) == 1,
    do: select(board, identity |> Map.to_list() |> hd())

  def select(board, identity) when is_map(identity) and map_size(identity) > 1 do
    GenServer.call(board, {:select, identity})
  end

  @doc """
  The row behind a cell's keyboard point, `{series, index}` (spec/10 §17.2), its identity
  (spec/15 §13.2), its item and its frame: `{:ok, %{row: row, identity: identity | nil,
  item: item | nil, frame: name}}`, the identity `{field, value}`, or a map for a composite
  one the slot's schema declares (D-167), the item as a `Visualize.Event`'s (D-170), or
  `:error` for a cell that is not running or a point it does not have.

  The board answers the cell's process and the caller asks it, so a pick never holds the
  board; a cell that dies meanwhile answers `:error`.
  """
  @spec pick(GenServer.server(), atom(), non_neg_integer(), non_neg_integer()) ::
          {:ok,
           %{
             row: map(),
             identity: Board.identity() | nil,
             item: Visualize.Event.item() | nil,
             frame: atom()
           }}
          | :error
  def pick(board, cell, series, index) do
    ask(board, cell, &{:pick, &1, &2, series, index})
  end

  @doc """
  A click a cell's `TooltipHook` pushed, as `Visualize.Event.decode/1` read it, resolved by
  the cell's process against the drawing it holds (spec/15 §9.2, D-170):
  `{:ok, %Visualize.Event{}}` with the cell, the declared name, the row as its mark drew
  it, typed, and its item — or `:error` for a cell that is not running, a click on a
  drawing it no longer holds, a key it has no row for, a name the mark does not declare,
  or the cell's own `pick`. Asked as `pick/4` asks, never holding the board.
  """
  @spec event(GenServer.server(), atom(), Visualize.Event.click()) ::
          {:ok, Visualize.Event.t()} | :error
  def event(board, cell, %{event: _, mark: _, row: _} = click) do
    ask(board, cell, &{:event, &1, &2, click})
  end

  # A question put to a cell's process from the caller's: the board names the process,
  # and the cell answers under the caller's reference.
  defp ask(board, cell, message) do
    case GenServer.call(board, {:cell, cell}) do
      pid when is_pid(pid) -> ask(pid, message)
      nil -> :error
    end
  end

  defp ask(pid, message) do
    ref = Process.monitor(pid)
    send(pid, message.(self(), ref))

    receive do
      {^ref, reply} ->
        Process.demonitor(ref, [:flush])
        reply

      {:DOWN, ^ref, :process, ^pid, _reason} ->
        :error
    end
  end

  @doc """
  Board variables merged over the board's, and every cell prepared again (spec/15 §5,

  §8.2): `:ok`, or `{:error, errors}`.
  """
  @spec vars(GenServer.server(), map()) :: :ok | {:error, [Board.error(), ...]}
  def vars(board, vars) when is_map(vars), do: GenServer.call(board, {:vars, vars})

  @doc "The container width set and every cell's box recomputed (spec/15 §1.6, §8.2); `:ok`."
  @spec resize(GenServer.server(), number()) :: :ok
  def resize(board, width) when is_number(width) and width > 0,
    do: GenServer.call(board, {:resize, width})

  @doc "One turn of the loop now (spec/15 §8.2); `:ok` once it is done."
  @spec tick(GenServer.server()) :: :ok
  def tick(board), do: GenServer.call(board, :tick)

  @doc "The board's present state (spec/15 §8.2)."
  @spec info(GenServer.server()) :: info()
  def info(board), do: GenServer.call(board, :info)

  @doc """
  The board frozen as it stands (spec/15 §12.2): a `Visualize.Board.Snapshot` of the
  board, its now and its resolved window, the width, the theme, and every cell's prepared
  component, variables and the slots the board last handed it — or the reason a cell that
  has crashed died. It holds no pid and no feed: `Visualize.Board.Export` draws it, and it
  reopens anywhere after the board has stopped.
  """
  @spec snapshot(GenServer.server()) :: Snapshot.t()
  def snapshot(board), do: GenServer.call(board, :snapshot)

  @doc "The board and its cells stopped; `:ok`."
  @spec stop(GenServer.server()) :: :ok
  def stop(board), do: GenServer.stop(board, :normal)

  # -- the process --------------------------------------------------------------------------

  @impl true
  def init(prepared) do
    Process.flag(:trap_exit, true)
    {:ok, cells_sup} = DynamicSupervisor.start_link(strategy: :one_for_one)
    board = prepared.board

    monitor =
      Monitor.new(prepared.feeds,
        # Turned only by `tick/1`, the board polls its pull feeds on every turn.
        every: prepared.tick || 0,
        budget: prepared.budget,
        stale_after: board.stale_after && round(board.stale_after * 1000)
      )

    state =
      prepared
      |> Map.take([
        :board,
        :store,
        :binding,
        :feeds,
        :theme,
        :system,
        :generators,
        :assigns,
        :width,
        :tick,
        :max_heap,
        :clock,
        :boards,
        :debounce
      ])
      |> Map.merge(%{
        limits: Map.get(prepared, :limits, []),
        given: board.window,
        selection: nil,
        brushed: 0,
        components: prepared.components,
        needs: prepared.needs,
        monitor: monitor,
        cells_sup: cells_sup,
        cells: %{},
        refs: %{},
        subscribers: %{},
        sent: %{},
        now: nil,
        window: nil,
        told: nil
      })

    {:ok, state, {:continue, :start}}
  end

  @impl true
  def handle_continue(:start, state) do
    state = Enum.reduce(Enum.sort(Map.keys(state.board.cells)), state, &start_cell(&2, &1))
    state = turn(state)
    schedule(state)
    {:noreply, state}
  end

  defp schedule(%{tick: nil}), do: :ok
  defp schedule(%{tick: ms}), do: Process.send_after(self(), :tick, ms)

  @impl true
  def handle_call({:subscribe, pid}, _from, state) do
    state =
      if Map.has_key?(state.subscribers, pid),
        do: state,
        else: %{state | subscribers: Map.put(state.subscribers, pid, Process.monitor(pid))}

    tell_cells(state, pid)

    # A crashed cell cannot speak for itself; the board draws it to the newcomer.
    for {name, %{pid: nil, state: {:crashed, _} = crashed}} <- state.cells,
        do: send(pid, message({:cell, name, crashed_view(state, name, crashed)}))

    {:reply, {:ok, present(state)}, state}
  end

  def handle_call({:unsubscribe, pid}, _from, state) do
    {:reply, :ok, drop_subscriber(state, pid)}
  end

  # A window set by a call drops a brush still waiting: it is the later choice.
  def handle_call({:window, window}, _from, state) do
    case Board.validate(%{state.board | window: window}) do
      :ok -> {:reply, :ok, windowed(%{state | brushed: state.brushed + 1}, window)}
      {:error, _errors} = error -> {:reply, error, state}
    end
  end

  # A brush waits `debounce` for the next; only the last one's timer finds its number.
  def handle_call({:brush, window}, _from, state) do
    case Board.validate(%{state.board | window: window}) do
      :ok when state.debounce == 0 ->
        {:reply, :ok, windowed(state, window)}

      :ok ->
        brushed = state.brushed + 1
        Process.send_after(self(), {:brush, brushed, window}, state.debounce)
        {:reply, :ok, %{state | brushed: brushed}}

      {:error, _errors} = error ->
        {:reply, error, state}
    end
  end

  def handle_call(:reset_window, _from, state) do
    {:reply, :ok, windowed(%{state | brushed: state.brushed + 1}, state.given)}
  end

  def handle_call({:select, identity}, _from, state) do
    selection =
      case identity do
        nil ->
          nil

        {field, value} ->
          {Board.link(state.board, field), value}

        fields ->
          Map.new(fields, fn {field, value} -> {Board.link(state.board, field), value} end)
      end

    state = %{state | selection: selection}

    for {_name, %{pid: pid}} when is_pid(pid) <- state.cells,
        do: send(pid, {:selection, selection_for(state)})

    {:reply, :ok, tell(state)}
  end

  def handle_call({:cell, name}, _from, state) do
    {:reply, get_in(state.cells, [name, :pid]), state}
  end

  def handle_call({:vars, vars}, _from, state) do
    board = %{state.board | vars: Map.merge(state.board.vars, vars)}

    read = [limits: state.limits, boards: state.boards, generators: state.generators]

    case Board.components(board, state.store, read) do
      {:ok, components} ->
        for {name, %{chart: chart, vars: v}} <- components,
            components[name] != state.components[name],
            %{pid: pid} when is_pid(pid) <- [state.cells[name]],
            do: send(pid, {:component, chart, v})

        {:reply, :ok, %{state | board: board, components: components}}

      {:error, _errors} = error ->
        {:reply, error, state}
    end
  end

  def handle_call({:resize, width}, _from, state) do
    old = Board.boxes(state.board, state.width)
    new = Board.boxes(state.board, width)

    for {name, box} <- new,
        size(box) != size(old[name]),
        %{pid: pid} when is_pid(pid) <- [state.cells[name]],
        do: send(pid, {:size, size(box)})

    {:reply, :ok, tell(%{state | width: width})}
  end

  def handle_call(:tick, _from, state), do: {:reply, :ok, turn(state)}
  def handle_call(:info, _from, state), do: {:reply, present(state), state}
  def handle_call(:snapshot, _from, state), do: {:reply, frozen(state), state}

  @impl true
  def handle_info(:tick, state) do
    state = turn(state)
    schedule(state)
    {:noreply, state}
  end

  def handle_info({:brush, brushed, window}, %{brushed: brushed} = state),
    do: {:noreply, windowed(state, window)}

  def handle_info({:brush, _superseded, _window}, state), do: {:noreply, state}

  def handle_info({:visualize_feed, _ref, _message} = message, state) do
    {:ok, monitor} = Monitor.handle_message(state.monitor, message)
    {:noreply, %{state | monitor: monitor}}
  end

  def handle_info({:cell_state, name, cell_state}, state) do
    {:noreply, update_cell(state, name, &%{&1 | state: cell_state})}
  end

  def handle_info({:restart, name}, state) do
    {:noreply, start_cell(state, name)}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    case Map.fetch(state.refs, ref) do
      {:ok, name} ->
        {:noreply, crashed(%{state | refs: Map.delete(state.refs, ref)}, name, reason)}

      :error ->
        {:noreply, drop_subscriber(state, ref)}
    end
  end

  def handle_info({:EXIT, sup, reason}, %{cells_sup: sup} = state), do: {:stop, reason, state}
  def handle_info({:EXIT, _pid, _reason}, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    Monitor.stop(state.monitor)
  end

  # The board's window set, every feed re-asked, and the turn run at once (spec/15 §8.2).
  defp windowed(state, window) do
    monitor = Monitor.refetch(state.monitor)
    turn(%{state | board: %{state.board | window: window}, monitor: monitor})
  end

  # The selection as a cell reads it: for each of its fields, the fields that may hold it
  # and the value, all of which a row must hold (D-167).
  defp selection_for(%{selection: nil}), do: nil

  defp selection_for(%{selection: {field, value}, board: board}),
    do: [%{fields: Board.linked(board, field), value: value}]

  defp selection_for(%{selection: fields, board: board}) do
    fields
    |> Enum.sort_by(fn {field, _value} -> to_string(field) end)
    |> Enum.map(fn {field, value} -> %{fields: Board.linked(board, field), value: value} end)
  end

  # -- a turn -------------------------------------------------------------------------------

  # One turn (spec/15 §8.2): now read once, the window resolved at it, the monitor ticked,
  # and each cell sent its slots when they changed — else only the new now.
  defp turn(state) do
    now = state.clock.()
    window = Board.window(state.board, now)

    monitor =
      state.monitor
      |> Monitor.window(window && Tuple.to_list(window))
      |> Monitor.tick(now: System.monotonic_time(:millisecond))

    state = %{state | monitor: monitor, now: now, window: window}
    deliveries = Monitor.deliveries(monitor)
    statuses = Monitor.status(monitor)
    cache = Monitor.cache(monitor)

    sent =
      Map.new(state.needs, fn {cell, slots} ->
        data = Map.new(slots, &{&1, slot(state, cell, &1, deliveries, statuses, cache)})
        pid = state.cells[cell][:pid]

        cond do
          pid == nil -> :ok
          data != state.sent[cell] -> send(pid, {:data, data, now})
          true -> send(pid, {:now, now})
        end

        {cell, data}
      end)

    tell(%{state | sent: sent})
  end

  defp slot(state, cell, slot, deliveries, statuses, cache) do
    case Binding.fetch(state.binding, cell, slot) do
      {:ok, feed} ->
        delivery = Map.get(deliveries, feed)
        %{delivery: delivery, schema: schema(cache, feed, delivery), status: statuses[feed]}

      :error ->
        %{delivery: nil, schema: nil, status: {:down, {:unbound, slot}}}
    end
  end

  defp schema(_cache, _feed, nil), do: nil

  defp schema(cache, feed, delivery) do
    case Cache.fetch(cache, feed, delivery.schema) do
      {:ok, schema} -> schema
      :error -> nil
    end
  end

  # The subscribers told the board's own state when the window, the zone or the width
  # moved (spec/15 §8.2).
  defp tell(state) do
    told =
      {state.window, state.board.zone, state.width, state.board.sync, state.selection,
       moved?(state)}

    if told != state.told do
      Enum.each(Map.keys(state.subscribers), &send(&1, message({:board, present(state, false)})))
    end

    %{state | told: told}
  end

  # -- cells --------------------------------------------------------------------------------

  defp start_cell(state, name) do
    cell = Map.fetch!(state.board.cells, name)
    %{chart: chart, vars: vars} = Map.fetch!(state.components, name)
    box = Map.fetch!(Board.boxes(state.board, state.width), name)
    data = if sent = state.sent[name], do: {:data, sent, state.now}

    spec =
      {Cell,
       name: name,
       board: self(),
       chart: chart,
       vars: vars,
       size: size(box),
       theme: state.theme,
       system: state.system,
       generators: state.generators,
       assigns: state.assigns,
       title: Map.get(cell, :title),
       stale_after: state.board.stale_after,
       subscribers: Map.keys(state.subscribers),
       max_heap: state.max_heap,
       selection: selection_for(state),
       data: data}

    entry = Map.get(state.cells, name, %{pid: nil, state: :loading, restarts: 0, since: nil})

    case DynamicSupervisor.start_child(state.cells_sup, spec) do
      {:ok, pid} ->
        ref = Process.monitor(pid)
        entry = %{entry | pid: pid, since: System.monotonic_time(:millisecond)}
        %{state | cells: Map.put(state.cells, name, entry), refs: Map.put(state.refs, ref, name)}

      {:error, reason} ->
        crashed(%{state | cells: Map.put(state.cells, name, entry)}, name, reason)
    end
  end

  # A cell that died (spec/15 §8.3): shown crashed to every subscriber at once, restarted
  # after the backoff. One that stopped normally is gone.
  defp crashed(state, name, reason) when reason in [:normal, :shutdown] do
    update_cell(state, name, &%{&1 | pid: nil})
  end

  defp crashed(state, name, reason) do
    entry = state.cells[name]
    now = System.monotonic_time(:millisecond)
    settled? = entry.since != nil and now - entry.since > @settled
    restarts = if settled?, do: 1, else: entry.restarts + 1
    view = crashed_view(state, name, {:crashed, reason})

    Enum.each(Map.keys(state.subscribers), &send(&1, message({:cell, name, view})))
    delay = min(@backoff * Integer.pow(2, restarts - 1), @backoff_max)
    Process.send_after(self(), {:restart, name}, delay)

    update_cell(state, name, fn entry ->
      %{entry | pid: nil, state: {:crashed, reason}, restarts: restarts}
    end)
  end

  defp crashed_view(state, name, crashed) do
    box = Board.boxes(state.board, state.width)[name]

    %View{
      cell: name,
      title: Map.get(state.board.cells[name], :title),
      state: crashed,
      size: size(box),
      note: State.render(crashed, state.theme, size(box))
    }
  end

  defp update_cell(state, name, fun) do
    case Map.fetch(state.cells, name) do
      {:ok, entry} -> %{state | cells: Map.put(state.cells, name, fun.(entry))}
      :error -> state
    end
  end

  defp tell_cells(state, newcomer) do
    pids = Map.keys(state.subscribers)

    for {_name, %{pid: pid}} when is_pid(pid) <- state.cells,
        do: send(pid, {:subscribers, pids, newcomer})

    :ok
  end

  defp drop_subscriber(state, ref) when is_reference(ref) do
    case Enum.find(state.subscribers, fn {_pid, r} -> r == ref end) do
      {pid, _ref} -> drop_subscriber(state, pid)
      nil -> state
    end
  end

  defp drop_subscriber(state, pid) when is_pid(pid) do
    case Map.pop(state.subscribers, pid) do
      {nil, _subscribers} ->
        state

      {ref, subscribers} ->
        Process.demonitor(ref, [:flush])
        state = %{state | subscribers: subscribers}
        tell_cells(state, nil)
        state
    end
  end

  defp size({_x, _y, w, h}), do: {w, h}
  defp size(nil), do: nil

  defp present(state, cells? \\ true) do
    base = %{
      board: state.board,
      window: state.window,
      zone: state.board.zone,
      now: state.now,
      width: state.width,
      sync: state.board.sync,
      selection: state.selection,
      moved: moved?(state)
    }

    if cells? do
      Map.put(
        base,
        :cells,
        Map.new(state.cells, fn {name, e} ->
          {name, %{pid: e.pid, state: e.state, restarts: e.restarts}}
        end)
      )
    else
      Map.drop(base, [:board])
    end
  end

  # The board as a snapshot (spec/15 §12.2): what each cell was last handed, never a
  # call to a cell, so a slow cell does not hold it.
  defp frozen(state) do
    cells =
      Map.new(state.components, fn {name, %{chart: chart, vars: vars}} ->
        crashed =
          case state.cells[name] do
            %{state: {:crashed, reason}} -> reason
            _running -> nil
          end

        {name, %{chart: chart, vars: vars, slots: state.sent[name], crashed: crashed}}
      end)

    Snapshot.new(
      board: state.board,
      now: state.now,
      window: state.window,
      width: state.width,
      theme: state.theme,
      cells: cells
    )
  end

  defp moved?(state), do: state.board.window != state.given

  defp message(message), do: {:visualize_board, self(), message}
end
