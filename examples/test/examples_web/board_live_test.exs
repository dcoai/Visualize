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
  alias Visualize.Board.Server

  @endpoint ExamplesWeb.Endpoint

  test "the page renders the board's grid, every cell one tab stop, before it connects" do
    html = build_conn() |> get("/board") |> html_response(200)

    assert html =~ ~s(phx-hook="BoardHook")
    assert html =~ "<h2 class=\"vis-board-title\">Live board</h2>"

    for cell <-
          ~w(load memory queue wave offline requests errors services hosts weather latency status) do
      assert html =~ ~s(data-vis-cell="#{cell}"), cell
    end

    assert html =~ ~s(phx-click="window")
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
    assert %{state: :live, fault: nil} = sources[[:health]]
    assert %{state: :live, fault: nil} = sources[[:trend]]

    %{delivery: delivery} = Server.snapshot(board).cells.hosts.slots.hosts

    for row <- delivery.rows do
      assert row[:"health.state"] in [:good, :warning, :bad]
      assert row[:"trend.trend"] in [:increasing, :decreasing, :neutral]
    end

    Server.unsubscribe(board, self())
  end

  test "the trend is the host's own function, tested as any function" do
    rows = for cpu <- [10, 12, 30], do: %{cpu: cpu}
    assert Examples.BoardDemo.Sources.trend(rows) == %{trend: :increasing}
    assert [trend: source] = Examples.BoardDemo.Sources.__virtual_sources__()
    assert source =~ "delta > 5 -> :increasing"
  end

  # The hosts cell's first view whose icons are drawn from the virtual sources' answers:
  # their pulse comes after the board's debounce, so a live view with none may precede it.
  defp hosts_view do
    receive do
      {:visualize_board, _board, {:cell, :hosts, %{state: :live, svg: svg} = view}}
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
      views = views_of(board, %{}, ~w(weather memory)a)
      Server.unsubscribe(board, self())
      views.weather.svg <> views.memory.svg
    end

    posted = ticks.(posted)
    assert posted =~ " °C<" and posted =~ " km/h<" and posted =~ " MB<"
    us = ticks.(us)
    assert us =~ " °F<" and us =~ " mi/h<" and us =~ " MB<"
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
    views = views_of(board, %{}, ~w(memory queue latency status)a)
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
    assert views.status.svg =~ ~r/fill="var\(--vis-good/
    for state <- ~w(ok degraded down), do: assert(views.status.svg =~ ">#{state}<")
  end

  test "the station's readings are rewritten in the page's system" do
    {:ok, socket} = BoardLive.mount(%{"units" => "uk"}, %{}, %Phoenix.LiveView.Socket{})
    assert socket.assigns.system == :uk

    {:noreply, socket} = BoardLive.handle_info(:station, socket)
    readings = Map.new(socket.assigns.station, &{&1.label, &1})
    assert %{value: "" <> _ = celsius, conversion: nil} = readings["Temperature"]
    assert celsius =~ " °C"
    # Shown in another unit than posted, a reading says how it was converted.
    assert readings["Wind"].value =~ " mi/h"
    assert readings["Wind"].conversion == "from km/h: × 0.6214"
    assert readings["Pressure"].value =~ " hPa"

    {:ok, us} = BoardLive.mount(%{"units" => "us"}, %{}, %Phoenix.LiveView.Socket{})
    us = Map.new(us.assigns.station, &{&1.label, &1})
    assert us["Temperature"].conversion == "from °C: × 9/5 + 32"
  end

  test "the page forwards the board's messages and its buttons set the board's window" do
    {:ok, socket} = BoardLive.mount(%{}, %{}, %Phoenix.LiveView.Socket{})
    board = socket.assigns.board
    view = %Visualize.Board.View{cell: :load, state: :loading, size: {1, 1}}

    assert {:noreply, _socket} =
             BoardLive.handle_info({:visualize_board, board, {:cell, :load, view}}, socket)

    assert_received {:phoenix, :send_update,
                     {{Visualize.Components.Board.Cell, "demo-board-load"}, %{view: ^view}}}

    {:noreply, socket} = BoardLive.handle_event("window", %{"last" => "60"}, socket)
    assert Server.info(board).board.window == %{last: 60}
    {:noreply, _socket} = BoardLive.handle_event("window", %{"last" => "300"}, socket)
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
             ~w(errors hosts latency load memory offline queue requests services status wave weather)a

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
    assert {:ok, %{identity: {:service, "api"}}} = Server.pick(board, :requests, 0, 0)
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

    # A selection change is the board's own: the page stays where it is.
    select = %Visualize.Event{event: :select, value: %{identity: {:service, "db"}}}

    assert {:noreply, %{redirected: nil}} =
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

  # The first view of each cell whose chart dims something.
  defp dimmed(seen, []), do: seen

  defp dimmed(seen, waiting) do
    receive do
      {:visualize_board, _board, {:cell, cell, %{svg: svg}}} when is_binary(svg) ->
        if cell in waiting and svg =~ ~s(opacity="0.25"),
          do: dimmed(Map.put(seen, cell, svg), List.delete(waiting, cell)),
          else: dimmed(seen, waiting)

      {:visualize_board, _board, _other} ->
        dimmed(seen, waiting)
    end
  end

  # The first view of each cell of one board that is no longer loading: several boards'
  # messages may be in the mailbox at once.
  defp views_of(_board, seen, []), do: seen

  defp views_of(board, seen, waiting) do
    receive do
      {:visualize_board, ^board, {:cell, cell, %{state: state} = view}} when state != :loading ->
        if cell in waiting,
          do: views_of(board, Map.put(seen, cell, view), List.delete(waiting, cell)),
          else: views_of(board, seen, waiting)

      {:visualize_board, _board, _other} ->
        views_of(board, seen, waiting)
    end
  end

  # The first view of each cell that is no longer loading.

  defp views(seen, []), do: seen

  defp views(seen, waiting) do
    receive do
      {:visualize_board, _board, {:cell, cell, %{state: state} = view}} when state != :loading ->
        if cell in waiting,
          do: views(Map.put(seen, cell, view), List.delete(waiting, cell)),
          else: views(seen, waiting)

      {:visualize_board, _board, _other} ->
        views(seen, waiting)
    end
  end
end
