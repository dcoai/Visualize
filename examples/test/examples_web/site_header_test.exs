defmodule ExamplesWeb.SiteHeaderTest do
  @moduledoc "One header on every page, with the tab bar and the current tab marked (#329)."
  use ExUnit.Case, async: true

  import Phoenix.ConnTest
  import Plug.Conn

  @endpoint ExamplesWeb.Endpoint

  @pages [
    {"/", :charts},
    {"/chart/line", :charts},
    {"/performance", :performance},
    {"/high-performance", :performance},
    {"/hybrid", :performance},
    # /incremental raises on render before this change — pre-existing, filed #331; not listed until it renders
    {"/interaction", :interaction},
    {"/builder", :builder}
  ]

  test "every page renders the one header, the subtitle, the four tabs, and marks its own" do
    for {path, tab} <- @pages do
      html = build_conn() |> get(path) |> html_response(200)
      assert length(Regex.scan(~r/<header class="site-header">/, html)) == 1, path
      assert html =~ "<h1>Visualize Examples</h1>"
      assert html =~ "<p>Liveview data visualizations</p>"
      refute html =~ "D3-style data visualizations in Elixir"

      for {_tab, href, name, _icon} <- ExamplesWeb.SiteHeader.tabs() do
        assert html =~ ~s(href="#{href}" class="site-tab"), path
        assert html =~ name, path
      end

      {_tab, href, _name, _icon} = List.keyfind(ExamplesWeb.SiteHeader.tabs(), tab, 0)
      assert html =~ ~s(href="#{href}" class="site-tab" aria-current="page"), path
      assert length(Regex.scan(~r/class="site-tab" aria-current="page"/, html)) == 1, path
    end
  end

  test "the header is half its former height: the h1 and the padding halved" do
    html = build_conn() |> get("/") |> html_response(200)
    assert html =~ "header.site-header h1 { font-size: 1.25rem;"
    assert html =~ "padding: 1rem 2rem 0;"
    refute html =~ "header h1 { font-size: 2.5rem;"
  end
end
