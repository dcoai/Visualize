defmodule ExamplesWeb.HooksController do
  @moduledoc """
  Serves `Visualize.Hooks.js_code/0` as an ES module, so the gallery's LiveSocket
  registers the library's hooks exactly as a host that ran `Visualize.Hooks.install!/0`
  would — the bundle is generated, never copied.
  """
  use Phoenix.Controller, formats: [:js]

  def show(conn, _params) do
    conn
    |> put_resp_content_type("text/javascript")
    # Never stale: a reload revalidates, so a restarted server's hooks reach the browser (#306).
    |> put_resp_header("cache-control", "no-cache")
    |> send_resp(200, Visualize.Hooks.js_code())
  end
end
