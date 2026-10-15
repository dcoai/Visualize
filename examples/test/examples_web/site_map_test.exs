defmodule ExamplesWeb.SiteMapTest do
  @moduledoc """
  No page is orphaned (#500): every page the router serves is a header tab, or is linked
  from the page of the tab its own header marks current. The gallery's tool buttons were
  the only way to two pages once; with them gone, a new page reaches a reader through its
  tab or this test fails.

  A redirect is not a page: its target must be reachable. A parameterized route is a
  family of pages, each of which must be linked; the expansions below say how to list
  them, and a parameterized route with none fails until it has one.
  """
  use ExUnit.Case, async: true

  import Phoenix.ConnTest

  @endpoint ExamplesWeb.Endpoint

  # Every concrete page of a parameterized route.
  defp expand("/chart/:chart"),
    do: for({slug, _module} <- ExamplesWeb.ChartLive.charts(), do: "/chart/#{slug}")

  defp expand(path),
    do: flunk("#{path} is parameterized and the site map cannot list its pages; add an expansion")

  defp pages do
    Phoenix.Router.routes(ExamplesWeb.Router)
    |> Enum.filter(&(&1.verb == :get and not String.starts_with?(&1.path, "/hooks")))
    |> Enum.flat_map(fn %{path: path} ->
      if String.contains?(path, ":"), do: expand(path), else: [path]
    end)
  end

  defp tab_hrefs, do: for({_tab, href, _name, _icon} <- ExamplesWeb.SiteHeader.tabs(), do: href)

  # The tab a page's header marks current.
  defp current_tab(path, html) do
    case Regex.run(~r/href="([^"]+)" class="site-tab" aria-current="page"/, html) do
      [_, href] -> href
      nil -> flunk("#{path} marks no header tab as current")
    end
  end

  test "every page is a header tab or is linked from its tab's page" do
    tabs = tab_hrefs()
    tab_html = Map.new(tabs, &{&1, build_conn() |> get(&1) |> html_response(200)})
    pages = pages()

    for path <- pages do
      conn = build_conn() |> get(path)

      case conn.status do
        302 ->
          target = redirected_to(conn)
          assert target in pages, "#{path} redirects to #{target}, which is no page of the router"

        200 ->
          tab = current_tab(path, html_response(conn, 200))

          assert path == tab or tab_html[tab] =~ ~s(href="#{path}"),
                 "#{path} is under the #{tab} tab, and #{tab} does not link to it"
      end
    end
  end

  test "the pages no tab names are linked from their tab's page" do
    assert build_conn() |> get("/interaction") |> html_response(200) =~ ~s(href="/dashboard")
    assert build_conn() |> get("/interaction") |> html_response(200) =~ ~s(href="/board")
    assert build_conn() |> get("/performance") |> html_response(200) =~ ~s(href="/hybrid")
  end

  test "the gallery index has no tool buttons" do
    html = build_conn() |> get("/") |> html_response(200)
    refute html =~ "tools-bar"
    refute html =~ "tool-link"
    refute html =~ "Hybrid SVG/Canvas Demo"
  end
end
