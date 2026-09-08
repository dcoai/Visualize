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

  scope "/", ExamplesWeb do
    pipe_through :browser

    live "/", GalleryLive, :index
    live "/chart/:chart", ChartLive, :show
    live "/performance", PerformanceLive, :index
    live "/hybrid", HybridLive, :index
    live "/high-performance", HighPerformanceLive, :index
    live "/incremental", IncrementalLive, :index
    live "/interaction", InteractionLive, :index
    get "/hooks/visualize_hooks.js", HooksController, :show
  end
end
