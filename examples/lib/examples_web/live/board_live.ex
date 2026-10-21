defmodule ExamplesWeb.BoardLive do
  @moduledoc """
  A live board (#576, spec/15 §8–§10, D-146): `Examples.BoardDemo`'s cells, drawn by
  `Visualize.Components.Board` over the board process the library runs.

  The page owns the board's window (`brush: :host`, D-161): the window buttons, a brush and
  *Reset window* each become the page's URL, and `handle_params/3` applies the URL's window
  to the board, so a link reopens it; a selection is kept in the URL the same way. A click
  on a host's bar is the design's declared event `host_picked`, which the page shows; and a
  button makes the host function one cell calls raise for a while, so that cell is drawn
  crashed and restarted.

  The *Units* switch is the viewer's unit system (D-156): `?units=us` mounts the board
  that runs in it, every axis with a measure drawn in its units, and the station's newest
  readings above the board are written in it with `Visualize.Quantity.format/3`.

  The page holds nothing of the board's but its pid: the component subscribes the page
  when it connects, and the page's one `handle_info/2` clause forwards the board's
  messages to it. The window buttons set the board's window, which re-asks every feed;
  brushing a time chart does the same, and the header's Reset window restores it. The
  export buttons post to `ExamplesWeb.BoardExportController`, which freezes the board
  and hands back its SVG, its PNG, its snapshot or its printed pages (#578).

  The three cells of the last row interact (spec/15 §13, #545): a service picked in one is
  selected in all three, and a click on a bar drills down. The component hands the drill to
  this page, which follows it to `/board/detail` with the bar's service: the page knows its
  routes, the library does not.

  Beneath the board, *The board outside its process* (`ExamplesWeb.BoardLive.Lifecycle`,
  #822) reopens a snapshot from its JSON — uploaded, or the board frozen now — carries the
  board in a bundle to a second library, and runs the feed conformance kit in a task.
  """
  use Phoenix.LiveView

  alias Examples.BoardDemo
  alias ExamplesWeb.BoardLive.{Lifecycle, Station}
  alias ExamplesWeb.{Highlight, Panel}
  alias Visualize.Board.Server
  alias Visualize.{Event, Quantity, Unit}

  @windows [{"1 min", 60}, {"5 min", 300}, {"15 min", 900}]
  # The page's own loop over the station turns this often (spec/08 §11.4).
  @station_every 2000
  @firmware [{"°C", "°C"}, {"°F", "°F"}, {"K", "K"}]
  # How long the board's host function fails when the page asks it to.
  @outage 20_000
  # The largest snapshot document the page reopens.
  @snapshot_max 16_000_000

  @impl true
  def mount(params, _session, socket) do
    system = BoardDemo.system(params["units"])
    {:ok, board} = BoardDemo.board(system)
    if connected?(socket), do: :timer.send_interval(@station_every, :station)

    {:ok,
     assign(socket,
       board: board,
       value: BoardDemo.value(),
       windows: @windows,
       system: system,
       firmware: @firmware,
       memory_compatibility: BoardDemo.memory_compatibility(),
       station: system |> Station.new() |> Station.tick(),
       params: %{},
       picked: nil,
       reopened: nil,
       bundle: nil,
       conformance: nil
     )
     |> allow_upload(:snapshot, accept: ~w(.json), max_entries: 1, max_file_size: @snapshot_max)}
  end

  # The station's newest readings, written in the viewer's system (D-156): what a host's
  # header writes beside a board, read from the page's own loop over the station. A reading
  # shown in another unit than the station posts says how it was converted, exactly
  # (`Visualize.Unit.conversion/2`, D-155).
  defp readings(station, system) do
    for %{label: label, value: value, measure: measure} <- Station.readings(station) do
      shown = Quantity.display_unit([value, value], measure, system: system)

      %{
        label: label,
        value: Quantity.format(value, measure, system: system, precision: 1),
        conversion: conversion(measure.unit, shown)
      }
    end
  end

  defp conversion(unit, unit), do: nil

  defp conversion(from, to) do
    {:ok, {scale, offset}} = Unit.conversion(from, to)

    "from #{Unit.symbol(from)}: × #{ratio(scale)}" <>
      if(offset == {0, 1}, do: "", else: " + #{ratio(offset)}")
  end

  # A ratio as a person reads it: a small fraction as itself, any other to four places.
  defp ratio({n, 1}), do: Integer.to_string(n)
  defp ratio({n, d}) when d <= 10, do: "#{n}/#{d}"
  defp ratio({n, d}), do: :erlang.float_to_binary(n / d, decimals: 4)

  @impl true
  def handle_info(:station, socket),
    do: {:noreply, update(socket, :station, &Station.tick/1)}

  @impl true
  def handle_info({:visualize_board, _board, _message} = message, socket) do
    Visualize.Components.Board.forward("demo-board", message)
    {:noreply, socket}
  end

  # A drill the component resolved from the clicked bar (spec/15 §13.3, D-170): the page
  # follows it. Every other event of the board's — a selection made or cleared — is the
  # board's own business here, and the page ignores it.
  def handle_info(
        {:visualize_event, "demo-board",
         %Event{event: :drill, value: %{board: :detail, vars: vars}}},
        socket
      ) do
    {:noreply, push_navigate(socket, to: "/board/detail?" <> URI.encode_query(vars))}
  end

  # The page owns the window (`brush: :host`, D-161): a brush, or the header's Reset window,
  # arrives as an event and becomes the page's URL, which `handle_params/3` applies.
  def handle_info(
        {:visualize_event, "demo-board", %Event{event: :brush, value: %{domain: nil}}},
        socket
      ) do
    :ok = Server.reset_window(socket.assigns.board)
    {:noreply, push_patch(socket, to: path(socket, %{"from" => nil, "to" => nil, "last" => nil}))}
  end

  def handle_info(
        {:visualize_event, "demo-board", %Event{event: :brush, value: %{domain: [from, to]}}},
        socket
      ) do
    window = %{
      "from" => DateTime.to_iso8601(from),
      "to" => DateTime.to_iso8601(to),
      "last" => nil
    }

    {:noreply, push_patch(socket, to: path(socket, window))}
  end

  # The selection is kept in the URL too, so a link reopens the board with it (D-170).
  def handle_info(
        {:visualize_event, "demo-board", %Event{event: :select, value: %{identity: identity}}},
        socket
      ) do
    {:noreply, push_patch(socket, to: path(socket, %{"select" => selection(identity)}))}
  end

  # A host bar clicked: the event the design declares on the mark, with the row it drew.
  def handle_info(
        {:visualize_event, "demo-board", %Event{event: "host_picked", row: row}},
        socket
      ) do
    {:noreply, assign(socket, picked: row)}
  end

  def handle_info({:visualize_event, "demo-board", %Event{}}, socket), do: {:noreply, socket}

  @impl true
  def handle_async(:conformance, {:ok, rows}, socket),
    do: {:noreply, assign(socket, conformance: rows)}

  @impl true
  def handle_params(params, _uri, socket) do
    board = socket.assigns.board

    case window(params) do
      nil -> :ok
      window -> :ok = Server.window(board, window)
    end

    case identity(params["select"]) do
      nil -> :ok
      identity -> :ok = Server.select(board, identity)
    end

    {:noreply, assign(socket, params: Map.take(params, ~w(units from to last select)))}
  end

  # The window a URL holds: a brushed span, the last so many seconds, or none.
  defp window(%{"from" => from, "to" => to}) do
    with {:ok, from, _} <- DateTime.from_iso8601(from),
         {:ok, to, _} <- DateTime.from_iso8601(to),
         do: %{from: from, to: to},
         else: (_ -> nil)
  end

  defp window(%{"last" => last}) do
    case Integer.parse(last) do
      {seconds, ""} when seconds > 0 -> %{last: seconds}
      _ -> nil
    end
  end

  defp window(_params), do: nil

  # A selection as the URL writes it, `field:value`, for the fields the board selects by; a
  # composite one (D-167) its fields' pairs sorted and joined, `host:h2,iface:eth1`.
  @selectable ~w(service host iface)

  defp selection({field, value}), do: selection(%{field => value})

  defp selection(identity) when is_map(identity) do
    pairs = for {field, value} <- identity, do: {to_string(field), to_string(value)}

    if Enum.all?(pairs, fn {field, _value} -> field in @selectable end),
      do: pairs |> Enum.sort() |> Enum.map_join(",", fn {field, value} -> "#{field}:#{value}" end)
  end

  defp selection(_identity), do: nil

  # The identity a URL's selection names, its fields kept as the strings the board reads
  # them as (D-195): a pair for one field, a map for several, `nil` for a field the board
  # does not select by — never an atom made from the URL.
  defp identity(nil), do: nil

  defp identity(param) do
    pairs =
      for part <- String.split(param, ","),
          [field, value] <- [String.split(part, ":", parts: 2)],
          do: {field, value}

    cond do
      pairs == [] or Enum.any?(pairs, fn {field, _value} -> field not in @selectable end) -> nil
      length(pairs) == 1 -> hd(pairs)
      true -> Map.new(pairs)
    end
  end

  # The page's URL with some parameters changed, `nil` dropping one.
  defp path(socket, changes) do
    query =
      socket.assigns.params
      |> Map.merge(changes)
      |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
      |> Enum.sort()

    if query == [], do: "/board", else: "/board?" <> URI.encode_query(query)
  end

  @impl true
  # New firmware for the station: what it posts changes, and the page's loop sees it.
  def handle_event("firmware", %{"symbol" => symbol}, socket) do
    symbol = if List.keymember?(@firmware, symbol, 1), do: symbol, else: "°C"
    {:noreply, update(socket, :station, &(&1 |> Station.firmware(symbol) |> Station.tick()))}
  end

  # The host function behind *Services, colored by a host function* raises for a while: that
  # cell alone is shown crashed and restarted until it works again (spec/15 §8.3).
  def handle_event("chaos", _params, socket) do
    :ok = Examples.BoardDemo.Chaos.fail_for(@outage)
    {:noreply, socket}
  end

  # One link, named by both its fields: a composite selection made directly (D-167).
  def handle_event("select_link", _params, socket) do
    link = %{"host" => "h2", "iface" => "eth1"}
    {:noreply, push_patch(socket, to: path(socket, %{"select" => selection(link)}))}
  end

  # The board outside its process (#822): a snapshot reopened from its JSON — uploaded, or
  # the board frozen now — the board carried in a bundle, and the conformance kit's report.
  def handle_event("reopen_pick", _params, socket), do: {:noreply, socket}

  def handle_event("reopen", _params, socket) do
    reopened =
      consume_uploaded_entries(socket, :snapshot, fn %{path: path}, _entry ->
        {:ok, Lifecycle.reopen(File.read!(path))}
      end)

    {:noreply, assign(socket, reopened: List.first(reopened, socket.assigns.reopened))}
  end

  def handle_event("freeze", _params, socket),
    do: {:noreply, assign(socket, reopened: Lifecycle.freeze(socket.assigns.board))}

  def handle_event("carry", _params, socket),
    do: {:noreply, assign(socket, bundle: Lifecycle.carry())}

  def handle_event("conformance", _params, socket) do
    {:noreply,
     socket
     |> assign(conformance: :running)
     |> start_async(:conformance, fn -> Lifecycle.conformance() end)}
  end

  def handle_event("window", %{"last" => last}, socket) do
    window = %{"last" => last, "from" => nil, "to" => nil}
    {:noreply, push_patch(socket, to: path(socket, window))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <ExamplesWeb.SiteHeader.header tab={:interaction} />
    <main>
      <a href="/" class="back-link"><span>&larr;</span> Back to Gallery</a>

      <div class="panels">
        <Panel.panel id="panel-board">
          <:title>Live board</:title>
          <p class="panel-note">
            A board is designs on a 12-column grid sharing a window, a zone and a sync group.
            One process runs the board and its feeds; each cell is its own process under a
            heap limit, so a slow or failing cell is only that cell. <em>Offline</em> is bound
            to a feed that cannot be reached: its state is drawn, not left blank. Narrow the
            window to stack the cells.
          </p>
          <p class="panel-note">
            <em>Memory</em>, <em>Run queue</em> and <em>Weather station</em> read their axes'
            units from their feeds' schemas — the telemetry definition's <code>:megabyte</code>,
            the station's <code>°C</code> and <code>km/h</code> — and draw them in the unit
            system chosen below. The station goes quiet for forty seconds every four minutes;
            its readings' <code>continuity</code> makes that a gap, not a bridge.
          </p>
          <p class="panel-note">
            <em>Memory</em>
            is one <code>Visualize.Feed.Combine</code>: the live <code>:telemetry</code>
            feed, holding what it has seen since the node started, with
            a store's history behind it, which says <code>"t"</code>
            and kilobytes where the live
            feed says <code>:t</code>
            and megabytes. Widen the window past the node's uptime and
            the store fills the rest, converted. Their schemas' compatibility: <code class="board-memory-compatibility">{inspect(@memory_compatibility)}</code>.
          </p>
          <p class="panel-note">
            Overlays are marks of the designs, read from the feeds' facts: the dashed rule is
            each feed's <code>target</code>, and the dots are good or bad by it through a
            threshold scale placed by the feed's <code>polarity</code>. <em>Latency</em> is a
            percentile band; <em>Service status</em> is a state timeline colored by the feed's
            own <code>status</code> map.
          </p>
          <p class="panel-note">
            The last row interacts across cells. <em>Requests</em> and <em>Errors</em> are one
            design over two feeds: click a line, or press Enter on a point, to select its service
            in every cell, the others dimmed. <em>Services</em> names the field <code>name</code>,
            and the board's <code>{"links: %{name: :service}"}</code> makes it the same selection.
            Click a bar to drill down to that service's detail board. Escape clears the selection.
          </p>

          <p class="board-windows">
            Window:
            <button
              :for={{name, last} <- @windows}
              type="button"
              phx-click="window"
              phx-value-last={last}
            >
              {name}
            </button>
            — or brush a time chart; Reset window restores it. The page owns the window
            (<code>brush: :host</code>): every one is kept in its URL, and so is a selection,
            so a link reopens the board as it stands.
          </p>

          <p class="board-units">
            Units:
            <.link
              :for={{name, system} <- BoardDemo.systems()}
              navigate={"/board?units=#{system}"}
              class={["board-unit", system == @system && "board-unit-current"]}
              aria-current={system == @system && "true"}
            >
              {name}
            </.link>
            — the viewer's choice, never the design's: a board runs per system, and every
            axis with a measure redraws in it.
          </p>
          <p class="board-station">
            Weather station now:
            <span :for={reading <- readings(@station, @system)} class="board-reading">
              {reading.label} <strong>{reading.value}</strong>
              <small :if={reading.conversion} class="board-conversion">({reading.conversion})</small>
            </span>
          </p>

          <form class="board-exports" method="post" action="/board/export/svg">
            <input type="hidden" name="_csrf_token" value={Phoenix.Controller.get_csrf_token()} />
            <input type="hidden" name="units" value={@system} /> Export:
            <button type="submit" formaction="/board/export/svg">SVG</button>
            <button type="submit" formaction="/board/export/png">PNG</button>
            <button type="submit" formaction="/board/export/snapshot">Snapshot</button>
            <button type="submit" formaction="/board/export/print" formtarget="_blank">Print</button>
            — the board frozen as it stands; a snapshot reopens with no feeds.
          </form>

          <p class="board-cell-states">
            <button type="button" phx-click="chaos">Make the host function raise for 20 s</button>
            — <em>Services, colored by a host function</em>
            calls the host's own function to
            color each bar. While it raises, only that cell is down: it is drawn
            <em>Crashed, restarting</em>
            and retried with a backoff, its siblings drawing on.
            Before a cell's first view it is drawn <em>Loading…</em>, and <em>Offline</em>
            is
            always <em>Feed down</em>.
          </p>
          <p class="board-every-state">
            The last rows are one chart over five feeds, each made to be in one state: <em>Stale</em>
            stopped reporting ninety seconds ago, past the board's <code>stale_after: 30</code>;
            <em>No data</em>
            answers no rows; <em>Capped</em>
            answers only its newest readings; <em>Invalid binding</em>
            sends text where
            the design reads a number, so the cell names the mismatch rather than crash; and
            <em>Over budget</em>
            ships 6,000 readings past the board's ceiling of 5,000, so the board never hands the cell its rows.
          </p>
          <p class="board-links">
            <em>Links</em>
            names a link by two fields, <code>host</code>
            and <code>iface</code>:
            click a bar to select that one link, a composite selection the URL keeps as <code>?select=host:h2,iface:eth1</code>, or <button
              type="button"
              phx-click="select_link"
            >select h2's eth1</button>.
            Picking a host on <em>Hosts</em>
            selects the pair <code>host: h2</code>, both its links.
          </p>
          <p class="board-picked">
            Hover a host's bar for its reading, health and trend; click one and the page is told:
            <span :if={@picked} class="board-picked-host">
              <strong>{@picked.host}</strong>
              at {@picked.cpu}% CPU, {@picked[:"health.state"]}, {@picked[:"trend.trend"]}
            </span>
            <span :if={!@picked}>nothing picked yet.</span>
          </p>

          <.live_component
            module={Visualize.Components.Board}
            id="demo-board"
            server={@board}
            board={@value}
            brush={:host}
          />
        </Panel.panel>

        <Panel.panel id="panel-lifecycle">
          <:title>The board outside its process</:title>
          <Lifecycle.panel
            uploads={@uploads}
            reopened={@reopened}
            bundle={@bundle}
            conformance={@conformance}
          />
        </Panel.panel>

        <Panel.panel id="panel-station">
          <:title>The station, on the page's own loop</:title>
          <p class="panel-note">
            Outside a board a page runs its own loop: it holds a <code>Visualize.Feed.Monitor</code>
            over the station, ticks it every two seconds and
            draws the chart it compiled over the deliveries. The readings above come from it.
            New firmware changes what the station posts: the next delivery names another schema
            version, <code>Compiled.stale?/2</code>
            says the chart no longer holds, and the
            page compiles it again and says whether the two schemas are compatible.
          </p>
          <p class="board-firmware">
            Firmware posts the temperature in:
            <button
              :for={{name, symbol} <- @firmware}
              type="button"
              phx-click="firmware"
              phx-value-symbol={symbol}
              aria-pressed={to_string(Station.posts?(@station, symbol))}
            >
              {name}
            </button>
            — feed <strong class="board-station-status">{inspect(Station.status(@station))}</strong>,
            schema <code>{@station.schema && String.slice(@station.schema.version, 0, 8)}</code>
          </p>
          <svg
            :if={@station.svg}
            class="board-station-chart"
            viewBox={"0 0 #{elem(Station.size(), 0)} #{elem(Station.size(), 1)}"}
            width={elem(Station.size(), 0)}
            height={elem(Station.size(), 1)}
            role="img"
            aria-label="The station's temperature"
          >
            {Phoenix.HTML.raw(@station.svg)}
          </svg>
          <p :if={@station.change} class="board-station-change">
            Schema changed <code>{@station.change.from}</code>
            → <code>{@station.change.to}</code>:
            the temperature was <code>{elem(@station.change.unit, 0)}</code>
            and is <code>{elem(@station.change.unit, 1)}</code>. The chart was stale and is compiled
            again. <code>Schema.compatibility/2</code>:
            <strong>{inspect(@station.change.compatibility)}</strong>
            — {if @station.change.compatibility == :ok,
              do:
                "the old rows read as the new, so a Feed.Combine could keep the old history behind the new.",
              else: "the old rows do not read as the new."}
          </p>
        </Panel.panel>

        <Panel.panel id="panel-code">
          <:title>The host's part</:title>
          <Highlight.code code={code()} />
        </Panel.panel>
      </div>
    </main>

    <style>
      .board-windows button, .board-exports button { margin: 0 0.25rem; }
      .board-unit { margin: 0 0.25rem; }
      .board-lifecycle table { border-collapse: collapse; font-size: 0.8rem; margin: 0.5rem 0; }
      .board-lifecycle th, .board-lifecycle td { padding: 0.2rem 0.5rem; text-align: left; border-bottom: 1px solid #eee; vertical-align: top; }
      .board-lifecycle td.pass { color: #1d6b2b; }
      .board-lifecycle td.fail { color: #a3171c; }
      .board-finding { display: block; font-size: 0.75rem; }
      .board-fault { color: #a3171c; font-family: monospace; font-size: 0.85rem; }
      .board-bundle-json { max-height: 20rem; overflow: auto; font-size: 0.75rem; }
      .board-reopened-svg svg { max-width: 100%; height: auto; border: 1px solid #e0e0e0; }
      .board-unit-current { font-weight: 600; text-decoration: none; color: inherit; }
      .board-reading { margin-right: 1rem; }
      .vis-board-header { display: flex; gap: 1rem; align-items: baseline; }
      .vis-board-title { font-size: 1.1rem; margin: 0.25rem 0; }
      .vis-board-window { color: #555; margin: 0; }
      .vis-board-selection { margin: 0; }
      .vis-board-header button { margin-left: 0.25rem; }
      .vis-cell { background: var(--vis-background, #fff); border: 1px solid #e0e0e0; border-radius: 4px; padding: 4px; overflow: hidden; display: flex; flex-direction: column; }
      .vis-cell:focus { outline: 2px solid #3b6fa8; outline-offset: 1px; }
      .vis-cell-title { font-size: 0.85rem; margin: 0 0 2px 0; color: #444; }
      .vis-cell-chart, .vis-cell-placeholder { flex: 1; min-height: 0; }
      .vis-cell-banner svg { width: 100%; height: auto; display: block; }
    </style>
    """
  end

  # Elixir a reader can paste: the tree, the start, the component and the one clause.
  defp code do
    ~S'''
    # In the host's tree: where boards live (spec/15 §8.1).
    children = [{Visualize.Board.Supervisor, name: MyApp.Boards}]

    # One board per unit system, the viewer's choice (D-156): :as_posted, :metric, :us or :uk.
    {:ok, board} =
      Visualize.Board.Server.start(MyApp.Boards,
        board: board, store: store, binding: binding, feeds: feeds, system: :us)

    # Live data with its history behind it: one slot, the store's rows read as the live ones.
    memory = Visualize.Feed.Combine.new([live_telemetry, history_store])

    # Outside a board, the page's own loop: a monitor in its assigns, ticked by its timer,
    # and a chart compiled again when a delivery names a schema it was not compiled with.
    monitor = Visualize.Feed.Monitor.new(%{station: feed}) |> Visualize.Feed.Monitor.tick()
    sources = Visualize.Feed.Monitor.deliveries(monitor)
    if Visualize.Chart.Compiled.stale?(compiled, sources), do: compile_again(sources)

    # An axis says what its values are from the feed's own facts, and is drawn in the system.
    axis(:y, :left, measure: %{unit: fact(:weather, :temperature, :unit)})

    ~H"""
    <.live_component module={Visualize.Components.Board} id="ops" server={@board} board={@value} />
    """

    # The board's messages arrive at the page; one clause hands them on.
    def handle_info({:visualize_board, _, _} = message, socket) do
      Visualize.Components.Board.forward("ops", message)
      {:noreply, socket}
    end

    # Every interaction arrives as one Visualize.Event. A drill-down the component
    # resolved: the page knows where it leads. Any other event — a selection — it ignores.
    def handle_info(
          {:visualize_event, "ops", %Visualize.Event{event: :drill, value: %{board: :detail, vars: vars}}},
          socket
        ) do
      {:noreply, push_navigate(socket, to: "/board/detail?" <> URI.encode_query(vars))}
    end

    def handle_info({:visualize_event, "ops", _event}, socket), do: {:noreply, socket}
    '''
  end
end
