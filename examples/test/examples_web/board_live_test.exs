defmodule ExamplesWeb.BoardLiveTest do
  @moduledoc """
  The live board page (#576, spec/15 §10): the demo board runs under the examples'
  `Visualize.Board.Supervisor`, the page renders its nine cells through
  `Visualize.Components.Board`, a connected page receives every cell's view — the
  offline cell's designed "feed down" among them — and the window buttons move the
  board's window. The last row interacts (#545, spec/15 §13): a service picked in one
  cell is selected in all three, through `links` for the bars, and a bar drills down to
  the detail board the page opens.
  """
  use ExUnit.Case, async: false

  import Phoenix.ConnTest

  alias ExamplesWeb.BoardLive
  alias ExamplesWeb.BoardLive.Station
  alias Visualize.Board.Server
  alias Visualize.Event

  @endpoint ExamplesWeb.Endpoint

  test "the page renders the board's grid, every cell one tab stop, before it connects" do
    html = build_conn() |> get("/board") |> html_response(200)

    assert html =~ ~s(phx-hook="BoardHook")
    assert html =~ "<h2 class=\"vis-board-title\">Live board</h2>"

    for cell <-
          ~w(load memory queue wave offline requests errors services hosts weather latency status histogram) do
      assert html =~ ~s(data-vis-cell="#{cell}"), cell
    end

    assert html =~ ~s(phx-click="window")
    assert html =~ ~s(phx-click="bin_domain")
  end

  test "the board runs under the examples' board supervisor, one process for every visitor" do
    {:ok, board} = Examples.BoardDemo.board()
    assert {:ok, ^board} = Examples.BoardDemo.board()

    assert {:undefined, ^board, :worker, [Visualize.Board.Server]} =
             List.keyfind(DynamicSupervisor.which_children(Examples.Boards), board, 1)
  end

  test "every cell of the demo board draws, the offline one in its designed state" do
    {:ok, board} = Examples.BoardDemo.board()
    {:ok, _info} = Server.subscribe(board)
    :ok = Server.tick(board)
    views = views(%{}, ~w(load wave memory queue offline)a)

    for cell <- ~w(load wave memory queue)a do
      assert views[cell].state in [:live, :capped] or match?({:stale, _}, views[cell].state),
             "#{cell}: #{inspect(views[cell].state)}"

      assert views[cell].svg =~ ~s(class="mark mark-)
    end

    assert views.offline.state == {:down, :unreachable}
    assert views.offline.note =~ "Feed down: :unreachable"

    # One component in two cells, each bound to its own metric.
    assert views.memory.svg != views.queue.svg
    Server.unsubscribe(board, self())
  end

  test "the hosts cell is drawn by virtual sources: a stored health and a defsource trend" do
    {:ok, board} = Examples.BoardDemo.board()
    {:ok, _info} = Server.subscribe(board)
    :ok = Server.tick(board)

    view = hosts_view()
    assert view.svg =~ ~s(class="mark mark-choose")
    assert view.svg =~ ~s(class="legend")

    for state <- ~w(good warning bad), do: assert(view.svg =~ ~s(data-series="#{state}"))

    sources = Server.info(board).virtual_sources
    assert %{state: :live, fault: nil} = sources[["health"]]
    assert %{state: :live, fault: nil} = sources[["trend"]]

    %{delivery: delivery} = Server.snapshot(board).cells["hosts"].slots["hosts"]

    for row <- delivery.rows do
      assert row["health.state"] in ["good", "warning", "bad"]
      assert row["trend.trend"] in [:increasing, :decreasing, :neutral]
      # A label the stored function built with interpolation and `Visualize.Data.mean` (#769).
      assert row["health.note"] =~ ~r/^h\d+ averaged \d+(\.\d)?% over its last \d+$/
      assert String.starts_with?(row["health.note"], row["host"] || row[:host])
    end

    Server.unsubscribe(board, self())
  end

  test "the trend is the host's own function, tested as any function" do
    rows = for cpu <- [10, 12, 30], do: %{cpu: cpu}
    assert Examples.BoardDemo.Sources.trend(rows) == %{trend: :increasing}

    assert {:trend, 1, source} =
             List.keyfind(Examples.BoardDemo.Sources.__virtual_sources__(), :trend, 0)

    assert source =~ "Visualize.Data.slope()"
    assert Examples.BoardDemo.Sources.trend([%{cpu: 40}]) == %{trend: :neutral}
    assert Examples.BoardDemo.Sources.trend([%{cpu: 40}, %{cpu: 39.5}]) == %{trend: :neutral}
  end

  test "the wave's bins are the host's function of two arguments: a variable's bounds, else the extent" do
    rows = for y <- [12, 18, 30, 55, 88], do: %{y: y}
    inputs = %{"wave" => rows}

    # No `bin_domain`: ten bins over the data's extent, 12 to 88.
    extent = Examples.BoardDemo.Sources.wave_bins(inputs, %{"vars" => %{}})
    assert length(extent) == 10
    assert hd(extent).lo == 12 and List.last(extent).hi == 88
    assert Enum.sum(Enum.map(extent, & &1.count)) == 5

    # `:auto`, the component's default, is the extent too.
    assert Examples.BoardDemo.Sources.wave_bins(inputs, %{"vars" => %{"bin_domain" => :auto}}) ==
             extent

    # A pair of numbers: ten bins of ten over 0 to 100.
    fixed =
      Examples.BoardDemo.Sources.wave_bins(inputs, %{"vars" => %{"bin_domain" => [0, 100]}})

    assert Enum.map(fixed, &{&1.lo, &1.hi}) |> hd() == {0, 10.0}
    assert List.last(fixed).hi == 100
    assert Enum.map(fixed, & &1.count) == [0, 2, 0, 1, 0, 1, 0, 0, 1, 0]

    assert {:wave_bins, 2, source} =
             List.keyfind(Examples.BoardDemo.Sources.__virtual_sources__(), :wave_bins, 0)

    assert source =~ ~s(context["vars"]["bin_domain"])
    assert Examples.BoardDemo.bin_domain("fixed") == [0, 100]
    assert Examples.BoardDemo.bin_domain("bogus") == :auto
  end

  test "the bins buttons set the cell's variable, and the board re-shapes the cell" do
    {:ok, socket} = BoardLive.mount(%{}, %{}, %Phoenix.LiveView.Socket{})
    board = socket.assigns.board
    {:ok, _info} = Server.subscribe(board)
    :ok = Server.tick(board)
    bins = fn -> Server.snapshot(board).cells["histogram"].slots["bins"] end
    extent? = fn -> match?(%{delivery: %{rows: [_ | _]}}, bins.()) and not fixed?(bins.()) end
    first = drawn_until(board, "histogram", extent?)
    before = Server.info(board).virtual_sources

    {:noreply, _socket} = BoardLive.handle_event("bin_domain", %{"domain" => "fixed"}, socket)
    assert Server.info(board).board.cells["histogram"].vars == %{"bin_domain" => [0, 100]}

    fixed = drawn_until(board, "histogram", fn -> fixed?(bins.()) end)
    assert fixed.state == :live and fixed.svg != first.svg

    # The cell's own source re-ran with the new bounds.
    sources = Server.info(board).virtual_sources
    assert sources[["histogram", "bins"]].runs > before[["histogram", "bins"]].runs
    assert sources[["histogram", "bins"]].state == :live

    {:noreply, _socket} = BoardLive.handle_event("bin_domain", %{"domain" => "extent"}, socket)
    assert Server.info(board).board.cells["histogram"].vars == %{"bin_domain" => :auto}
    assert drawn_until(board, "histogram", extent?).state == :live
    Server.unsubscribe(board, self())
  end

  # Whether a slot's bins span 0 to 100: the cell's `bin_domain` set.
  defp fixed?(%{delivery: %{rows: [first | _] = rows}}),
    do: first["lo"] == 0 and List.last(rows)["hi"] == 100

  defp fixed?(_slot), do: false

  # The cell's next drawn view once the board's state passes `test`.
  defp drawn_until(board, cell, test) do
    receive do
      {:visualize_board, ^board, {:cell, ^cell, %{svg: svg} = view}} when is_binary(svg) ->
        if test.(), do: view, else: drawn_until(board, cell, test)
    end
  end

  # The hosts cell's first view whose icons are drawn from the virtual sources' answers:
  # their pulse comes after the board's debounce, so a live view with none may precede it.
  defp hosts_view do
    receive do
      {:visualize_board, _board, {:cell, "hosts", %{state: :live, svg: svg} = view}}
      when is_binary(svg) ->
        if svg =~ ~s(mark-choose"><g class="mark mark-), do: view, else: hosts_view()

      {:visualize_board, _board, _other} ->
        hosts_view()
    end
  end

  test "the units switch: a board per system, its own process, every measure in its units" do
    html = build_conn() |> get("/board?units=us") |> html_response(200)

    for system <- ~w(as_posted metric us uk),
        do: assert(html =~ ~s(href="/board?units=#{system}"), system)

    assert html =~ ~r/aria-current="true"[^>]*>\s*US\s*</
    assert html =~ ~r/Temperature <strong>-?[\d.]+ °F/
    assert html =~ ~r/Pressure <strong>[\d.]+ inHg/

    {:ok, posted} = Examples.BoardDemo.board()
    {:ok, us} = Examples.BoardDemo.board(:us)
    {:ok, uk} = Examples.BoardDemo.board(:uk)
    assert Enum.uniq([posted, us, uk]) |> length() == 3
    assert {:ok, ^us} = Examples.BoardDemo.board(Examples.BoardDemo.system("us"))
    assert Examples.BoardDemo.system("bogus") == :as_posted

    # The weather's axes and the memory axis, each measure read from its feed's facts.
    ticks = fn board ->
      {:ok, _info} = Server.subscribe(board)
      :ok = Server.tick(board)
      views = drawn_of(board, %{}, ~w(weather memory)a)
      Server.unsubscribe(board, self())
      views.weather.svg <> views.memory.svg
    end

    # Memory is in bytes, scaled to whatever its readings need — MB on one node, GB on a
    # busier one — so the test asks for a byte unit, not one magnitude of it.
    bytes = ~r/ [kMGT]?B</

    posted = ticks.(posted)
    assert posted =~ " °C<" and posted =~ " km/h<" and posted =~ bytes
    us = ticks.(us)
    assert us =~ " °F<" and us =~ " mi/h<" and us =~ bytes
    refute us =~ " °C<" or us =~ " km/h<"
    uk = ticks.(uk)
    assert uk =~ " °C<" and uk =~ " mi/h<"

    # The export is the board the viewer was looking at.
    svg = build_conn() |> post("/board/export/svg", %{"units" => "us"}) |> response(200)
    assert svg =~ " °F<"
  end

  test "overlays are marks read from the feeds' facts: targets, status colors, a timeline" do
    {:ok, board} = Examples.BoardDemo.board()
    {:ok, _info} = Server.subscribe(board)
    :ok = Server.tick(board)
    views = drawn_of(board, %{}, ~w(memory queue latency status)a)
    Server.unsubscribe(board, self())

    # The telemetry definitions carry the facts (D-160) the metric design reads.
    %{"examples.vm.memory" => memory} =
      Visualize.Feed.Telemetry.feeds(Examples.BoardDemo.Telemetry)

    {_version, schema, _supports} = Visualize.Feed.describe(memory)
    assert %{target: 200, polarity: :lower_is_better, bounds: [0, nil]} = schema.fields.value

    # A rule at the target, the newest reading a dot in its status, the brush the design's.
    for cell <- ~w(memory queue latency)a do
      svg = views[cell].svg
      assert svg =~ ~s(class="mark mark-rule"), "#{cell}"
      assert svg =~ ~r/<circle[^>]*fill="var\(--vis-(good|bad)/, "#{cell}"
      assert svg =~ ~s(data-vis-brush="x"), "#{cell}"
    end

    assert views.latency.svg =~ ~s(class="mark mark-percentile_band")
    assert views.latency.svg =~ " ms<"

    # The timeline's stretches are colored by the feed's own meaning of each state.
    assert views.status.svg =~ ~s(class="mark mark-band")
    assert views.status.svg =~ ~r/class="band"[^>]* fill="var\(--vis-(good|warning|bad)/
    # The legend shows each state by the name its feed declares (D-225); a stretch's tooltip
    # carries the name beside the raw value.
    for state <- ~w(OK Degraded Down), do: assert(views.status.svg =~ ">#{state}<")
    assert views.status.svg =~ ~s(data-datum-state="ok" data-named-state="OK")
  end

  test "the station's readings are written in the page's system, from the page's own loop" do
    uk = build_conn() |> get("/board?units=uk") |> html_response(200)
    assert uk =~ ~r/Temperature <strong>-?[\d.]+ °C<\/strong>/
    # Shown in another unit than posted, a reading says how it was converted.
    assert uk =~
             ~r/Wind <strong>[\d.]+ mi\/h<\/strong>\s*<small class="board-conversion">\(from km\/h: × 0.6214\)/

    assert uk =~ ~r/Pressure <strong>[\d.]+ hPa<\/strong>/
    refute uk =~ "(from °C"

    us = build_conn() |> get("/board?units=us") |> html_response(200)
    assert us =~ "(from °C: × 9/5 + 32)"

    {:ok, socket} = BoardLive.mount(%{"units" => "uk"}, %{}, %Phoenix.LiveView.Socket{})
    assert socket.assigns.system == :uk
    {:noreply, socket} = BoardLive.handle_info(:station, socket)
    assert Station.status(socket.assigns.station) == :live
    assert socket.assigns.station.svg =~ " °C<"
  end

  test "new firmware: the page's loop finds its chart stale, compiles again, and compares" do
    {:ok, socket} = BoardLive.mount(%{}, %{}, %Phoenix.LiveView.Socket{})
    before = socket.assigns.station
    assert before.change == nil and Station.posts?(before, "°C")

    {:noreply, socket} = BoardLive.handle_event("firmware", %{"symbol" => "°F"}, socket)
    station = socket.assigns.station
    assert Station.posts?(station, "°F")
    assert station.schema.version != before.schema.version
    assert %{unit: {"Cel", "[degF]"}, compatibility: :ok} = station.change
    assert station.svg =~ " °F<"

    # The chart compiled over the old schema is stale for a delivery of the new.
    delivery = Visualize.Feed.Monitor.deliveries(station.monitor).station
    assert Visualize.Chart.Compiled.stale?(before.compiled, %{station: delivery})
    refute Visualize.Chart.Compiled.stale?(station.compiled, %{station: delivery})

    # A symbol the page does not offer is the station's own, °C.
    {:noreply, socket} = BoardLive.handle_event("firmware", %{"symbol" => "°R"}, socket)
    assert Station.posts?(socket.assigns.station, "°C")
  end

  test "memory is the live telemetry with a store's history behind it, one Feed.Combine" do
    assert Examples.BoardDemo.memory_compatibility() == :ok
    html = build_conn() |> get("/board") |> html_response(200)
    assert html =~ ~s(<code class="board-memory-compatibility">:ok</code>)

    memory = Map.fetch!(Examples.BoardDemo.feeds(), "examples.vm.memory")
    assert %Visualize.Feed.Combine{} = memory
    # An hour ago, long before this test node started, the live feed holds nothing: the
    # store serves the window, its rows read in the live names and converted from its
    # kilobytes into the live feed's megabytes.
    now = DateTime.utc_now()
    window = [DateTime.add(now, -3600), DateTime.add(now, -3000)]
    {:ok, delivery} = Visualize.Feed.fetch(memory, window, nil)

    assert [_ | _] = delivery.rows

    for row <- delivery.rows do
      assert Map.keys(row) |> Enum.sort() == [:t, :value]

      assert_in_delta row.value,
                      Examples.BoardDemo.MemoryHistory.reading(row.t)["value"] / 1000,
                      1.0e-9
    end
  end

  test "the page forwards the board's messages and its buttons set the board's window" do
    {:ok, socket} = BoardLive.mount(%{}, %{}, %Phoenix.LiveView.Socket{})
    board = socket.assigns.board
    view = %Visualize.Board.View{cell: :load, state: :loading, size: {1, 1}}

    assert {:noreply, _socket} =
             BoardLive.handle_info({:visualize_board, board, {:cell, :load, view}}, socket)

    assert_received {:phoenix, :send_update,
                     {{Visualize.Components.Board.Cell, "demo-board-load"}, %{view: ^view}}}

    # The page owns the window: a button patches the URL, and the URL sets the window.
    {:noreply, socket} = BoardLive.handle_params(%{}, "/board", socket)
    {:noreply, patched} = BoardLive.handle_event("window", %{"last" => "60"}, socket)
    assert {:live, :patch, %{to: "/board?last=60"}} = patched.redirected
    {:noreply, socket} = BoardLive.handle_params(%{"last" => "60"}, "/board?last=60", socket)
    assert Server.info(board).board.window == %{last: 60}
    {:noreply, _socket} = BoardLive.handle_params(%{"last" => "300"}, "/board?last=300", socket)
    assert Server.info(board).board.window == %{last: 300}
  end

  test "brush: :host — a brush, a reset and a selection are the page's URL, which sets the board" do
    {:ok, socket} = BoardLive.mount(%{}, %{}, %Phoenix.LiveView.Socket{})
    {:noreply, socket} = BoardLive.handle_params(%{"units" => "as_posted"}, "/board", socket)
    board = socket.assigns.board
    html = build_conn() |> get("/board") |> html_response(200)
    assert html =~ "brush: :host"

    from = ~U[2026-10-19 10:00:00Z]
    to = ~U[2026-10-19 10:05:00Z]
    brushed = %Event{event: :brush, value: %{domain: [from, to]}}
    {:noreply, patched} = BoardLive.handle_info({:visualize_event, "demo-board", brushed}, socket)
    assert {:live, :patch, %{to: url}} = patched.redirected
    %{query: query} = URI.parse(url)
    params = URI.decode_query(query)
    assert params["from"] == "2026-10-19T10:00:00Z" and params["units"] == "as_posted"

    {:noreply, socket} = BoardLive.handle_params(params, url, socket)
    assert Server.info(board).board.window == %{from: from, to: to}

    # The selection is kept in the URL, and a URL holding one selects it.
    selected = %Event{event: :select, value: %{identity: {:service, "web"}}}

    {:noreply, patched} =
      BoardLive.handle_info({:visualize_event, "demo-board", selected}, socket)

    assert {:live, :patch, %{to: url}} = patched.redirected
    assert URI.decode_query(URI.parse(url).query)["select"] == "service:web"
    {:noreply, socket} = BoardLive.handle_params(%{"select" => "service:web"}, url, socket)
    assert Server.info(board).selection == {"service", "web"}

    # A field the board does not select by is not made an atom: the URL is ignored.
    {:noreply, socket} = BoardLive.handle_params(%{"select" => "nope:web"}, url, socket)
    assert Server.info(board).selection == {"service", "web"}
    :ok = Server.select(board, nil)

    # Reset window: the board's own window again, and the URL loses the brushed one.
    reset = %Event{event: :brush, value: %{domain: nil}}
    {:noreply, patched} = BoardLive.handle_info({:visualize_event, "demo-board", reset}, socket)
    assert {:live, :patch, %{to: url}} = patched.redirected
    refute url =~ "from="
    assert Server.info(board).board.window == %{last: 300}
  end

  test "the export buttons hand back the board as SVG, its snapshot and its printed pages (#578)" do
    html = build_conn() |> get("/board") |> html_response(200)

    for format <- ~w(svg png snapshot print) do
      assert html =~ ~s(formaction="/board/export/#{format}"), format
    end

    {:ok, board} = Examples.BoardDemo.board()
    :ok = Server.tick(board)

    svg = build_conn() |> post("/board/export/svg")
    assert response(svg, 200) =~ ~s(class="vis-board-export")
    assert Plug.Conn.get_resp_header(svg, "content-type") |> hd() =~ "image/svg+xml"
    assert Plug.Conn.get_resp_header(svg, "content-disposition") |> hd() =~ "board.svg"

    for cell <-
          ~w(load memory queue wave offline requests errors services hosts weather latency status) do
      assert svg.resp_body =~ ~s(data-vis-cell="#{cell}"), cell
    end

    snapshot = build_conn() |> post("/board/export/snapshot")
    assert {:ok, frozen} = Visualize.Board.Snapshot.from_json(response(snapshot, 200))

    assert Map.keys(frozen.cells) |> Enum.sort() ==
             ~w(capped colored errors histogram hosts invalid latency links load memory no_data offline over_budget queue requests services stale status wave weather)

    assert Visualize.Board.Export.svg(frozen) =~ ~s(data-vis-cell="offline" data-vis-state="down")

    print = build_conn() |> post("/board/export/print")
    assert html_response(print, 200) =~ "@page { size: 210mm 297mm"

    png = build_conn() |> post("/board/export/png")
    assert png.status in [200, 503]
    if png.status == 200, do: assert(<<137, 80, 78, 71, _::binary>> = png.resp_body)
  end

  test "a service picked in one cell is selected in all three, and Escape's event clears it" do
    {:ok, board} = Examples.BoardDemo.board()
    {:ok, _info} = Server.subscribe(board)
    :ok = Server.tick(board)
    views(%{}, ~w(requests errors services)a)

    # The first series of Requests is `api`; its first point is picked.
    assert {:ok, %{identity: {"service", "api"}}} = Server.pick(board, :requests, 0, 0)
    :ok = Server.select(board, {:service, "api"})

    # Errors dims web and db; Services, whose field is `name`, dims their bars.
    dimmed = dimmed(%{}, ~w(errors services)a)
    assert dimmed.errors =~ ~s(opacity="0.25")
    assert dimmed.services =~ ~s(opacity="0.25")

    # The bars are a drill-down, not a selection: their pick names the bar's service.
    assert {:ok, %{row: %{name: name}}} = Server.pick(board, :services, 0, 1)
    assert name in Examples.BoardDemo.Services.services()

    :ok = Server.select(board, nil)
    assert Server.info(board).selection == nil
    Server.unsubscribe(board, self())
  end

  test "a drill the component resolved is followed to the detail board" do
    {:ok, socket} = BoardLive.mount(%{}, %{}, %Phoenix.LiveView.Socket{})

    drill = %Visualize.Event{
      event: :drill,
      cell: :services,
      row: %{name: "db"},
      value: %{board: :detail, vars: %{service: "db"}}
    }

    assert {:noreply, %{redirected: {:live, :redirect, %{to: "/board/detail?service=db"}}}} =
             BoardLive.handle_info({:visualize_event, "demo-board", drill}, socket)

    # A selection change keeps the page where it is: only its URL takes the selection.
    select = %Visualize.Event{event: :select, value: %{identity: {:service, "db"}}}

    assert {:noreply, %{redirected: {:live, :patch, %{to: "/board?select=service%3Adb"}}}} =
             BoardLive.handle_info({:visualize_event, "demo-board", select}, socket)
  end

  test "the detail board shows one service, its variable filtering both cells" do
    html = build_conn() |> get("/board/detail?service=web") |> html_response(200)
    assert html =~ "Service: web"
    assert html =~ ~s(data-vis-cell="requests") and html =~ ~s(data-vis-cell="errors")

    {:ok, board} = Examples.BoardDemo.detail("web")
    {:ok, _info} = Server.subscribe(board)
    :ok = Server.tick(board)
    views(%{}, ~w(requests errors)a)

    assert {:ok, %{row: %{service: "web"}}} = Server.pick(board, :requests, 0, 0)
    assert Server.pick(board, :requests, 1, 0) == :error
    Server.stop(board)
  end

  test "the detail board's endpoints legend cuts long names and keeps them whole for a reader" do
    html = build_conn() |> get("/board/detail?service=db") |> html_response(200)
    assert html =~ ~s(data-vis-cell="endpoints")

    {:ok, board} = Examples.BoardDemo.detail("db")
    {:ok, _info} = Server.subscribe(board)
    :ok = Server.tick(board)
    %{endpoints: %{svg: svg}} = drawn_of(board, %{}, [:endpoints])
    Server.stop(board)

    # max_label: 24 — a longer name is cut to 23 characters and "…", its entry carrying the
    # whole name as its aria-label and its <title>; a short one is drawn as it is.
    long = "SELECT orders JOIN customers (by customer_id)"
    assert svg =~ ~s(aria-label="#{long}")
    assert svg =~ "<title>#{long}</title>"
    assert svg =~ ">SELECT orders JOIN cust…</text>"
    assert svg =~ ">VACUUM</text>"
    # Only the chosen service's endpoints are sliced.
    refute svg =~ "/api/v2/health"
  end

  # The cell's crashes are logged, as a host's would be; the test keeps them out of its output.
  @tag :capture_log
  test "a cell whose host function raises is drawn crashed and restarted, alone" do
    {:ok, board} = Examples.BoardDemo.board()
    {:ok, _info} = Server.subscribe(board)
    :ok = Server.tick(board)
    assert %{colored: %{state: :live}} = drawn_of(board, %{}, [:colored])

    {:ok, socket} = BoardLive.mount(%{}, %{}, %Phoenix.LiveView.Socket{})
    {:noreply, _socket} = BoardLive.handle_event("chaos", %{}, socket)
    assert Examples.BoardDemo.Chaos.failing?()
    :ok = Server.tick(board)

    assert {:crashed, {%RuntimeError{message: "the palette service is unreachable"}, _}} =
             crashed(board, :colored)

    # Its siblings draw on.
    assert %{hosts: %{state: state}} = drawn_of(board, %{}, [:hosts])
    assert state in [:live, :capped]

    Examples.BoardDemo.Chaos.recover()
    :ok = Server.tick(board)
    assert %{colored: %{state: :live}} = live_again(board, :colored)
    Server.unsubscribe(board, self())
  end

  test "before its first view every cell is drawn loading, each panel its own root id" do
    html = build_conn() |> get("/board") |> html_response(200)
    cells = Map.keys(Examples.BoardDemo.value().cells)

    for cell <- cells do
      assert html =~ ~r/data-vis-cell="#{cell}" data-vis-state="loading"/, "#{cell}"
      assert html =~ ~s(id="demo-board-#{cell}-chart"), "#{cell}"
    end

    assert html =~ "Loading…"
  end

  test "a host bar's tooltip names its health and trend, and a click is the page's event" do
    {:ok, board} = Examples.BoardDemo.board()
    {:ok, _info} = Server.subscribe(board)
    :ok = Server.tick(board)
    %{svg: svg} = hosts_view()
    Server.unsubscribe(board, self())

    assert svg =~
             ~s(data-tooltip-template="{host}: {cpu}% CPU, {health.state}, {trend.trend}\n{health.note}")

    assert svg =~ ~s(data-tooltip-event="host_picked")

    {:ok, socket} = BoardLive.mount(%{}, %{}, %Phoenix.LiveView.Socket{})
    row = %{host: "h2", cpu: 64.5, "health.state": :warning, "trend.trend": :increasing}
    picked = %Event{event: "host_picked", cell: :hosts, row: row}
    {:noreply, socket} = BoardLive.handle_info({:visualize_event, "demo-board", picked}, socket)
    assert socket.assigns.picked == row
  end

  # The first crashed view of a board's cell; the test's own timeout bounds the wait.
  defp crashed(board, cell) do
    cell = to_string(cell)

    receive do
      {:visualize_board, ^board, {:cell, ^cell, %{state: {:crashed, reason}}}} ->
        {:crashed, reason}

      {:visualize_board, _board, _other} ->
        crashed(board, cell)
    end
  end

  # The first live view of a board's cell after a crash, the backoff waited out.
  defp live_again(board, cell) do
    name = to_string(cell)

    receive do
      {:visualize_board, ^board, {:cell, ^name, %{state: :live} = view}} -> %{cell => view}
      {:visualize_board, _board, _other} -> live_again(board, cell)
    end
  end

  # The first view of each cell whose chart dims something.
  defp dimmed(seen, []), do: seen

  defp dimmed(seen, waiting) do
    receive do
      {:visualize_board, _board, {:cell, name, %{svg: svg}}} when is_binary(svg) ->
        cell = Enum.find(waiting, &(to_string(&1) == name))

        if cell != nil and svg =~ ~s(opacity="0.25"),
          do: dimmed(Map.put(seen, cell, svg), List.delete(waiting, cell)),
          else: dimmed(seen, waiting)

      {:visualize_board, _board, _other} ->
        dimmed(seen, waiting)
    end
  end

  # The first view of each cell of one board that draws its chart — a view whose marks are
  # drawn, not a state panel such as "No data yet" before a feed's first reading (spec/12
  # §6): the wait is on the board's own messages, bounded by the test's timeout, and other
  # boards' messages in the mailbox are passed over.
  defp drawn_of(_board, seen, []), do: seen

  defp drawn_of(board, seen, waiting) do
    receive do
      {:visualize_board, ^board, {:cell, name, %{svg: svg} = view}} when is_binary(svg) ->
        # A cell is named by its string (D-195); the views are keyed as the test asked.
        case Enum.find(waiting, &(to_string(&1) == name)) do
          cell when cell != nil ->
            if svg =~ ~s(class="mark mark-),
              do: drawn_of(board, Map.put(seen, cell, view), List.delete(waiting, cell)),
              else: drawn_of(board, seen, waiting)

          nil ->
            drawn_of(board, seen, waiting)
        end

      {:visualize_board, _board, _other} ->
        drawn_of(board, seen, waiting)
    end
  end

  # The first view of each cell that is no longer loading.

  defp views(seen, []), do: seen

  defp views(seen, waiting) do
    receive do
      {:visualize_board, _board, {:cell, cell, %{state: state} = view}} when state != :loading ->
        case Enum.find(waiting, &(to_string(&1) == cell)) do
          nil -> views(seen, waiting)
          asked -> views(Map.put(seen, asked, view), List.delete(waiting, asked))
        end

      {:visualize_board, _board, _other} ->
        views(seen, waiting)
    end
  end
end
