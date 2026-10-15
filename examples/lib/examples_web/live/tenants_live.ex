defmodule ExamplesWeb.TenantsLive do
  @moduledoc """
  The tenant chat (spec/14 §3.13, spec/15 §10, #654): `Examples.Tenants`' board, two
  tenants in one conversation, each message drawn in its sender's tenant style by the
  host's generators.

  The page starts its own board, linked to its process, with the viewer's tenant in the
  board's `assigns:`; *View as* restarts it for the other viewer, whose own messages then
  carry the heavier outline.
  """
  use Phoenix.LiveView

  alias ExamplesWeb.{Highlight, Panel}
  alias Visualize.Board.Server

  @impl true
  def mount(params, _session, socket) do
    viewer =
      if params["viewer"] in Map.keys(Examples.Tenants.tenants()),
        do: params["viewer"],
        else: "acme"

    {:ok, board} = Examples.Tenants.start(viewer)
    {:ok, assign(socket, board: board, viewer: viewer, value: Examples.Tenants.value())}
  end

  @impl true
  def handle_info({:visualize_board, _board, _message} = message, socket) do
    Visualize.Components.Board.forward("tenant-board", message)
    {:noreply, socket}
  end

  def handle_info({:visualize_event, "tenant-board", %Visualize.Event{}}, socket),
    do: {:noreply, socket}

  # The viewer is the board's assigns: another viewer is another board.
  @impl true
  def handle_event("viewer", %{"tenant" => tenant}, socket) do
    if tenant in Map.keys(Examples.Tenants.tenants()) and tenant != socket.assigns.viewer do
      :ok = Server.stop(socket.assigns.board)
      {:ok, board} = Examples.Tenants.start(tenant)
      {:noreply, assign(socket, board: board, viewer: tenant)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <ExamplesWeb.SiteHeader.header tab={:interaction} />
    <main>
      <a href="/interaction" class="back-link"><span>&larr;</span> Back to Interactions</a>

      <div class="panels">
        <Panel.panel id="panel-tenants">
          <:title>Tenant chat</:title>
          <p class="panel-note">
            One conversation, two tenants. Each message is drawn in its <em>sender's</em>
            tenant style, which the design cannot hold: it stores <code>generate(:tenant_style, [{"{:field, :tenant}"}])</code>, and the host's
            generator answers it per message when the chart is drawn. The bars take each
            tenant's brand color the same way. Your own tenant's messages are outlined
            more heavily: the generator reads the viewer from the board's <code>assigns</code>.
          </p>

          <p class="tenant-viewer">
            View as:
            <button
              :for={{id, tenant} <- Enum.sort(Examples.Tenants.tenants())}
              type="button"
              phx-click="viewer"
              phx-value-tenant={id}
              aria-pressed={to_string(id == @viewer)}
            >
              {tenant.name}
            </button>
          </p>

          <.live_component
            module={Visualize.Components.Board}
            id="tenant-board"
            server={@board}
            board={@value}
          />
        </Panel.panel>

        <Panel.panel id="panel-code">
          <:title>The host's part</:title>
          <Highlight.code code={code()} />
        </Panel.panel>
      </div>
    </main>

    <style>
      .tenant-viewer button { margin: 0 0.25rem; }
      .tenant-viewer button[aria-pressed="true"] { font-weight: bold; }
      .vis-board-header { display: flex; gap: 1rem; align-items: baseline; }
      .vis-board-title { font-size: 1.1rem; margin: 0.25rem 0; }
      .vis-board-window { color: #555; margin: 0; }
      .vis-cell { background: var(--vis-background, #fff); border: 1px solid #e0e0e0; border-radius: 4px; padding: 4px; overflow: hidden; display: flex; flex-direction: column; }
      .vis-cell:focus { outline: 2px solid #3b6fa8; outline-offset: 1px; }
      .vis-cell-title { font-size: 0.85rem; margin: 0 0 2px 0; color: #444; }
      .vis-cell-chart, .vis-cell-placeholder { flex: 1; min-height: 0; }
      .vis-cell-banner svg { width: 100%; height: auto; display: block; }
    </style>
    """
  end

  # Elixir a reader can paste: the generators, their registration and the design's call.
  defp code do
    ~S'''
    defmodule MyApp.Generators do
      use Visualize.Generators

      defgenerator tenant_style(tenant, ctx) do
        MyApp.Tenants.style(tenant, ctx.assigns[:viewer])
      end

      defgenerator brand_color(tenant, _ctx), do: MyApp.Tenants.brand(tenant)
    end

    # config/config.exs
    config :visualize, generators: [MyApp.Generators]

    # The design stores the call; the frame answers it per message.
    import Visualize.Generators, only: [generate: 2]
    style: [:message, generate(:tenant_style, [{:field, :tenant}])]

    # The viewer travels with the board.
    Visualize.Board.Server.start_link(board: board, store: store, binding: binding,
      feeds: feeds, assigns: %{viewer: current_tenant})
    '''
  end
end
