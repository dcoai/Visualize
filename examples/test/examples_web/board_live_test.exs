defmodule ExamplesWeb.BoardLiveTest do
  @moduledoc """
  The live board page (#576, spec/15 §10): the demo board runs under the examples'
  `Visualize.Board.Supervisor`, the page renders its five cells through
  `Visualize.Components.Board`, a connected page receives every cell's view — the
  offline cell's designed "feed down" among them — and the window buttons move the
  board's window.
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

    for cell <- ~w(load memory queue wave offline) do
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

    for cell <- ~w(load memory queue wave offline) do
      assert svg.resp_body =~ ~s(data-vis-cell="#{cell}"), cell
    end

    snapshot = build_conn() |> post("/board/export/snapshot")
    assert {:ok, frozen} = Visualize.Board.Snapshot.from_json(response(snapshot, 200))
    assert Map.keys(frozen.cells) |> Enum.sort() == ~w(load memory offline queue wave)a
    assert Visualize.Board.Export.svg(frozen) =~ ~s(data-vis-cell="offline" data-vis-state="down")

    print = build_conn() |> post("/board/export/print")
    assert html_response(print, 200) =~ "@page { size: 210mm 297mm"

    png = build_conn() |> post("/board/export/png")
    assert png.status in [200, 503]
    if png.status == 200, do: assert(<<137, 80, 78, 71, _::binary>> = png.resp_body)
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
    after
      10_000 -> flunk("no view of #{inspect(waiting)}")
    end
  end
end
