defmodule ExamplesWeb.RoutesTest do
  @moduledoc """
  Every page renders (#331): each parameterless route of the router answers a GET with
  200, and the chart route with a slug does — so a page that cannot render fails the
  suite the day it breaks, rather than in a browser months later.
  """
  use ExUnit.Case, async: true

  import Phoenix.ConnTest

  @endpoint ExamplesWeb.Endpoint

  # The router's routes as it declares them: a GET or a LiveView at a fixed path.
  defp fixed_routes do
    for %{path: path, verb: :get} <- Phoenix.Router.routes(ExamplesWeb.Router),
        not String.contains?(path, ":"),
        not String.starts_with?(path, "/hooks"),
        do: path
  end

  test "the router names every page, and each renders" do
    paths = fixed_routes()
    assert "/" in paths and "/incremental" in paths and "/builder" in paths

    for path <- paths do
      conn = build_conn() |> get(path)
      assert conn.status in [200, 302], "#{path} answered #{conn.status}"
      if conn.status == 200, do: assert(html_response(conn, 200) =~ "<html", path)
    end
  end

  test "the demo routes redirect to the designs that replaced them (#327, #402)" do
    assert redirected_to(build_conn() |> get("/high-performance")) == "/chart/scrolling_series"
    assert redirected_to(build_conn() |> get("/incremental")) == "/chart/incremental_line"
  end

  test "a chart page renders for every chart the gallery lists" do
    for {slug, _module} <- ExamplesWeb.ChartLive.charts() do
      assert build_conn() |> get("/chart/#{slug}") |> html_response(200) =~
               ~s(class="site-header"),
             slug
    end
  end

  test "the gallery says every chart is a design, and every chart it lists is one (#130)" do
    html = build_conn() |> get("/") |> html_response(200)
    assert html =~ "Every chart here is a design"

    for {slug, module} <- ExamplesWeb.ChartLive.charts() do
      assert Examples.Charts.Design.design?(module), slug
      assert html =~ ~s(href="/chart/#{slug}"), slug
    end
  end

  test "the hooks module is served as JavaScript, never cached stale" do
    conn = build_conn() |> get("/hooks/visualize_hooks.js")
    assert conn.status == 200
    assert Plug.Conn.get_resp_header(conn, "cache-control") == ["no-cache"]
    assert conn.resp_body =~ "export const CanvasIncrementalChart"
  end
end
