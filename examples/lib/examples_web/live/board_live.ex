defmodule ExamplesWeb.BoardLive do
  @moduledoc """
  A live board (#576, spec/15 §8–§10, D-146): `Examples.BoardDemo`'s eight cells, drawn by
  `Visualize.Components.Board` over the board process the library runs.

  The page holds nothing of the board's but its pid: the component subscribes the page
  when it connects, and the page's one `handle_info/2` clause forwards the board's
  messages to it. The window buttons set the board's window, which re-asks every feed;
  brushing a time chart does the same, and the header's Reset window restores it. The
  export buttons post to `ExamplesWeb.BoardExportController`, which freezes the board
  and hands back its SVG, its PNG, its snapshot or its printed pages (#578).

  The three cells of the last row interact (spec/15 §13, #545): a service picked in one is
  selected in all three, and a click on a bar drills down. The component hands the drill to
  this page, which follows it to `/board/detail` with the bar's service: the page knows its
  routes, the library does not.
  """
  use Phoenix.LiveView

  alias ExamplesWeb.{Highlight, Panel}
  alias Visualize.Board.Server

  @windows [{"1 min", 60}, {"5 min", 300}, {"15 min", 900}]

  @impl true
  def mount(_params, _session, socket) do
    {:ok, board} = Examples.BoardDemo.board()
    {:ok, assign(socket, board: board, value: Examples.BoardDemo.value(), windows: @windows)}
  end

  @impl true
  def handle_info({:visualize_board, _board, _message} = message, socket) do
    Visualize.Components.Board.forward("demo-board", message)
    {:noreply, socket}
  end

  # A drill the component resolved from the clicked bar (spec/15 §13.3): the page follows it.
  def handle_info({:visualize_board_drill, "demo-board", %{board: :detail, vars: vars}}, socket) do
    {:noreply, push_navigate(socket, to: "/board/detail?" <> URI.encode_query(vars))}
  end

  @impl true
  def handle_event("window", %{"last" => last}, socket) do
    :ok = Server.window(socket.assigns.board, %{last: String.to_integer(last)})
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <ExamplesWeb.SiteHeader.header tab={:interaction} />
    <main>
      <a href="/" class="back-link"><span>&larr;</span> Back to Gallery</a>

      <div class="panels">
        <Panel.panel id="panel-board">
          <:title>Live board</:title>
          <p class="panel-note">
            A board is designs on a 12-column grid sharing a window, a zone and a sync group.
            One process runs the board and its feeds; each cell is its own process under a
            heap limit, so a slow or failing cell is only that cell. <em>Offline</em> is bound
            to a feed that cannot be reached: its state is drawn, not left blank. Narrow the
            window to stack the cells.
          </p>
          <p class="panel-note">
            The last row interacts across cells. <em>Requests</em> and <em>Errors</em> are one
            design over two feeds: click a line, or press Enter on a point, to select its service
            in every cell, the others dimmed. <em>Services</em> names the field <code>name</code>,
            and the board's <code>{"links: %{name: :service}"}</code> makes it the same selection.
            Click a bar to drill down to that service's detail board. Escape clears the selection.
          </p>

          <p class="board-windows">
            Window:
            <button
              :for={{name, last} <- @windows}
              type="button"
              phx-click="window"
              phx-value-last={last}
            >
              {name}
            </button>
            — or brush a time chart; Reset window restores it.
          </p>

          <form class="board-exports" method="post" action="/board/export/svg">
            <input type="hidden" name="_csrf_token" value={Phoenix.Controller.get_csrf_token()} />
            Export: <button type="submit" formaction="/board/export/svg">SVG</button>
            <button type="submit" formaction="/board/export/png">PNG</button>
            <button type="submit" formaction="/board/export/snapshot">Snapshot</button>
            <button type="submit" formaction="/board/export/print" formtarget="_blank">Print</button>
            — the board frozen as it stands; a snapshot reopens with no feeds.
          </form>

          <.live_component
            module={Visualize.Components.Board}
            id="demo-board"
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
      .board-windows button, .board-exports button { margin: 0 0.25rem; }
      .vis-board-header { display: flex; gap: 1rem; align-items: baseline; }
      .vis-board-title { font-size: 1.1rem; margin: 0.25rem 0; }
      .vis-board-window { color: #555; margin: 0; }
      .vis-board-selection { margin: 0; }
      .vis-board-header button { margin-left: 0.25rem; }
      .vis-cell { background: var(--vis-background, #fff); border: 1px solid #e0e0e0; border-radius: 4px; padding: 4px; overflow: hidden; display: flex; flex-direction: column; }
      .vis-cell:focus { outline: 2px solid #3b6fa8; outline-offset: 1px; }
      .vis-cell-title { font-size: 0.85rem; margin: 0 0 2px 0; color: #444; }
      .vis-cell-chart, .vis-cell-placeholder { flex: 1; min-height: 0; }
      .vis-cell-banner svg { width: 100%; height: auto; display: block; }
    </style>
    """
  end

  # Elixir a reader can paste: the tree, the start, the component and the one clause.
  defp code do
    ~S'''
    # In the host's tree: where boards live (spec/15 §8.1).
    children = [{Visualize.Board.Supervisor, name: MyApp.Boards}]

    {:ok, board} =
      Visualize.Board.Server.start(MyApp.Boards,
        board: board, store: store, binding: binding, feeds: feeds)

    ~H"""
    <.live_component module={Visualize.Components.Board} id="ops" server={@board} board={@value} />
    """

    # The board's messages arrive at the page; one clause hands them on.
    def handle_info({:visualize_board, _, _} = message, socket) do
      Visualize.Components.Board.forward("ops", message)
      {:noreply, socket}
    end

    # A drill-down the component resolved; the page knows where it leads.
    def handle_info({:visualize_board_drill, "ops", %{board: :detail, vars: vars}}, socket) do
      {:noreply, push_navigate(socket, to: "/board/detail?" <> URI.encode_query(vars))}
    end
    '''
  end
end
