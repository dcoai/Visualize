defmodule ExamplesWeb.BoardExportController do
  @moduledoc """
  The live board's exports (#578, spec/15 §12): the demo board exported with
  `Visualize.Board.Server.export/3`, which draws it with the board's own generators and
  assigns (#681), and handed back as a file — the board as SVG or PNG, its
  `Visualize.Board.Server.snapshot/1` as JSON — or, for print, as the printed pages in one
  HTML document the browser prints to paper or a PDF.

  The routes are `POST`s from the board page's buttons: an export is an action on the
  running board, not a page of the site.
  """
  use Phoenix.Controller, formats: [:html]

  alias Visualize.Board.{Server, Snapshot}

  # The board the viewer was looking at: the system its page was showing (D-156).
  def export(conn, %{"format" => format} = params) do
    {:ok, board} = Examples.BoardDemo.board(Examples.BoardDemo.system(params["units"]))
    send_export(conn, format, board)
  end

  defp send_export(conn, "svg", board) do
    send_download(conn, {:binary, Server.export(board, :svg)},
      filename: "board.svg",
      content_type: "image/svg+xml"
    )
  end

  defp send_export(conn, "png", board) do
    case Server.export(board, :png) do
      {:ok, png, _warnings} ->
        send_download(conn, {:binary, png}, filename: "board.png", content_type: "image/png")

      {:error, reason} ->
        conn
        |> put_status(503)
        |> text("The PNG is drawn by resvg, which this host cannot run: #{inspect(reason)}")
    end
  end

  defp send_export(conn, "snapshot", board) do
    {:ok, json} = Snapshot.to_json(Server.snapshot(board))

    send_download(conn, {:binary, json},
      filename: "board-snapshot.json",
      content_type: "application/json"
    )
  end

  defp send_export(conn, "print", board) do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, Server.export(board, :html))
  end

  defp send_export(conn, _format, _board) do
    conn |> put_status(404) |> text("No such export")
  end
end
