defmodule ExamplesWeb.Router do
  use Phoenix.Router
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ExamplesWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  # The hooks module is a static asset, and `protect_from_forgery` raises on any GET that
  # returns a JavaScript content type — the guard against cross-origin script inclusion,
  # which fires on a same-origin request because it inspects the response and not the
  # origin. Served through the browser pipeline the route answered 403 and the layout's
  # `import` failed silently, so every hook the library ships was inert.
  pipeline :asset do
    plug :accepts, ["js"]
  end

  scope "/", ExamplesWeb do
    pipe_through :browser

    live "/", GalleryLive, :index
    live "/chart/:chart", ChartLive, :show
    live "/performance", PerformanceLive, :index
    live "/hybrid", HybridLive, :index
    # The High-Performance page is the Scrolling series chart's drawer now (#327)
    get "/high-performance", RedirectController, :scrolling_series
    # The Incremental demo is the Incremental line chart's drawer now (#402)
    get "/incremental", RedirectController, :incremental_line
    live "/interaction", InteractionLive, :index
    live "/dashboard", DashboardLive, :index
    live "/board", BoardLive, :index
    # The board's exports are actions on the running board, not pages (#578).
    post "/board/export/:format", BoardExportController, :export
    live "/board/detail", BoardDetailLive, :index
    live "/tenants", TenantsLive, :index
    live "/minesweeper", MinesweeperLive, :index
    live "/builder", BuilderLive, :index
  end

  scope "/", ExamplesWeb do
    pipe_through :asset

    get "/hooks/visualize_hooks.js", HooksController, :show
  end
end
