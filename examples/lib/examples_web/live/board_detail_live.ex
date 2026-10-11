defmodule ExamplesWeb.BoardDetailLive do
  @moduledoc """
  The detail board a click on `/board`'s *Services* opens (spec/15 §10, §13.3, #545): one
  service's requests and errors, the board's variable `service` taken from the bar that was
  clicked and carried in the URL.

  The page starts its own detail board, linked to its process (`Examples.BoardDemo.detail/1`),
  so each visitor's detail board shows their service and stops when they leave. A service
  the demo does not have reads as `api`.
  """
  use Phoenix.LiveView

  alias Examples.BoardDemo
  alias Examples.BoardDemo.Services

  @impl true
  def mount(params, _session, socket) do
    service = if params["service"] in Services.services(), do: params["service"], else: "api"
    {:ok, board} = BoardDemo.detail(service)

    {:ok, assign(socket, board: board, service: service, value: BoardDemo.detail_value(service))}
  end

  @impl true
  def handle_info({:visualize_board, _board, _message} = message, socket) do
    Visualize.Components.Board.forward("detail-board", message)
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <ExamplesWeb.SiteHeader.header tab={:interaction} />
    <main>
      <a href="/board" class="back-link"><span>&larr;</span> Back to the live board</a>

      <div class="panels">
        <ExamplesWeb.Panel.panel id="panel-detail">
          <:title>Service: {@service}</:title>
          <p class="panel-note">
            A drill-down from the live board: this board's variable <code>service</code>
            is <code>{inspect(@service)}</code>, taken from the bar you clicked, and both cells
            filter their rows by it. Other services:
            <a
              :for={other <- Services.services() -- [@service]}
              href={"/board/detail?service=#{other}"}
              class="board-detail-link"
            >
              {other}
            </a>
          </p>

          <.live_component
            module={Visualize.Components.Board}
            id="detail-board"
            server={@board}
            board={@value}
          />
        </ExamplesWeb.Panel.panel>
      </div>
    </main>

    <style>
      .board-detail-link { margin: 0 0.25rem; }
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
end
