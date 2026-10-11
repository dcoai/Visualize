defmodule ExamplesWeb.BoardExportController do
  @moduledoc """
  The live board's exports (#578, spec/15 §12): the demo board frozen with
  `Visualize.Board.Server.snapshot/1` and handed back as a file — the board as SVG or PNG,
  the snapshot itself as JSON — or, for print, as the printed pages in one HTML document
  the browser prints to paper or a PDF.

  The routes are `POST`s from the board page's buttons: an export is an action on the
  running board, not a page of the site.
  """
  use Phoenix.Controller, formats: [:html]

  alias Visualize.Board.{Export, Server, Snapshot}

  def export(conn, %{"format" => format}) do
    {:ok, board} = Examples.BoardDemo.board()
    snapshot = Server.snapshot(board)
    send_export(conn, format, snapshot)
  end

  defp send_export(conn, "svg", snapshot) do
    send_download(conn, {:binary, Export.svg(snapshot)},
      filename: "board.svg",
      content_type: "image/svg+xml"
    )
  end

  defp send_export(conn, "png", snapshot) do
    case Export.png(snapshot) do
      {:ok, png, _warnings} ->
        send_download(conn, {:binary, png}, filename: "board.png", content_type: "image/png")

      {:error, reason} ->
        conn
        |> put_status(503)
        |> text("The PNG is drawn by resvg, which this host cannot run: #{inspect(reason)}")
    end
  end

  defp send_export(conn, "snapshot", snapshot) do
    {:ok, json} = Snapshot.to_json(snapshot)

    send_download(conn, {:binary, json},
      filename: "board-snapshot.json",
      content_type: "application/json"
    )
  end

  defp send_export(conn, "print", snapshot) do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, Export.html(snapshot))
  end

  defp send_export(conn, _format, _snapshot) do
    conn |> put_status(404) |> text("No such export")
  end
end
