if Code.ensure_loaded?(Phoenix.Component) do
  defmodule Visualize.Components.Board do
    @moduledoc """
    A live board in LiveView (spec/15 §9, D-146): the grid, its cells, and the hooks that
    make them interactive, over a running `Visualize.Board.Server`.

    A `Phoenix.LiveComponent`. It subscribes the page's process to the board when the page
    connects, lays the cells on the board's 12-column grid at the arrangement for the
    container's width (spec/15 §1.6), and renders each cell as its own
    `Visualize.Components.Board.Cell` component, so a frame updates one cell's component
    and the diff the page sends is that cell's alone.

        <.live_component module={Visualize.Components.Board} id="ops"
                         server={@board} board={@board_value} />

        def handle_info({:visualize_board, _board, _message} = message, socket) do
          Visualize.Components.Board.forward("ops", message)
          {:noreply, socket}
        end

    The board process sends its messages to the page's process, which hands them on with
    `forward/2`: a cell's view goes to that cell's component, and the board's window, zone
    and width to the board's. The hooks' pushes come back to this component —
    `BoardHook`'s width (`pushEventTo`) and each cell's brushed window (`BrushHook` with
    `data-brush-target`) — and become calls on the board process, so the page handles no
    event of the board's.

    ## Assigns

      * `id` - the component's id, the board's DOM id and the prefix of its cells' (required)
      * `server` - the board process: a pid or a registered name (required)
      * `board` - the `%Visualize.Board{}` it runs (required): its cells, titles and layout
      * `theme` - the theme a cell is drawn in before its first view
        (default `Visualize.Theme.default/0`)
      * `title` - the board's heading (default the board's `meta.name`)
      * `width` - the width the grid is arranged at until `BoardHook` pushes one
        (default `1200`)
    """

    use Phoenix.LiveComponent

    alias Visualize.Board
    alias Visualize.Board.{Server, State}
    alias Visualize.Components.Board.Cell

    @doc "The DOM and component id of a board's cell."
    @spec cell_id(String.t(), atom()) :: String.t()
    def cell_id(board_id, cell), do: "#{board_id}-#{cell}"

    @doc """
    A board process's message handed to its component (spec/15 §9.2): a cell's view to the
    cell's component, the board's state to the board's. `:ignore` for any other message.
    """
    @spec forward(String.t(), term()) :: :ok | :ignore
    def forward(id, {:visualize_board, _board, {:cell, name, view}}) do
      send_update(Cell, id: cell_id(id, name), view: view)
    end

    def forward(id, {:visualize_board, _board, {:board, info}}) do
      send_update(__MODULE__, id: id, info: info)
    end

    def forward(_id, _message), do: :ignore

    @impl true
    def mount(socket) do
      {:ok, assign(socket, subscribed: false, info: nil, width: nil)}
    end

    @impl true
    def update(%{info: info} = assigns, socket) when not is_map_key(assigns, :board) do
      {:ok, assign(socket, info: info, width: info.width)}
    end

    def update(assigns, socket) do
      socket =
        socket
        |> assign(Map.take(assigns, [:id, :server, :board, :info]))
        |> assign(:theme, Map.get(assigns, :theme, Visualize.Theme.default()))
        |> assign(:title, Map.get(assigns, :title) || get_in(assigns.board.meta, [:name]))
        |> assign(:width, socket.assigns.width || Map.get(assigns, :width, 1200))

      {:ok, subscribe(socket)}
    end

    # The page's process subscribed once it is connected: the component runs in it, so
    # the board's messages arrive at the page, which forwards them (spec/15 §9.2).
    defp subscribe(%{assigns: %{subscribed: true}} = socket), do: socket

    defp subscribe(socket) do
      if connected?(socket) do
        {:ok, info} = Server.subscribe(socket.assigns.server, self())
        assign(socket, subscribed: true, info: info, width: info.width)
      else
        socket
      end
    end

    @impl true
    def handle_event("resize", %{"width" => width}, socket) when is_number(width) and width > 0 do
      :ok = Server.resize(socket.assigns.server, width)
      {:noreply, assign(socket, width: width)}
    end

    # A brushed window, in the milliseconds a time `x` shares (spec/10 §6.4), becomes the
    # board's window in UTC; a cleared brush restores the window the board was given.
    def handle_event("brush", %{"domain" => [from, to]}, socket)
        when is_number(from) and is_number(to) and from < to do
      window = %{from: instant(from), to: instant(to)}
      :ok = Server.window(socket.assigns.server, window)
      {:noreply, socket}
    end

    def handle_event("brush_clear", _params, socket) do
      :ok = Server.window(socket.assigns.server, socket.assigns.board.window)
      {:noreply, socket}
    end

    def handle_event(_event, _params, socket), do: {:noreply, socket}

    defp instant(ms), do: DateTime.from_unix!(round(ms), :millisecond)

    @impl true
    def render(assigns) do
      layout = Board.layout(assigns.board)
      width = assigns.width

      assigns =
        assign(assigns,
          layout: layout,
          placed: Board.arrange(assigns.board, width),
          stacked: width < layout.breakpoint,
          window: window_text(assigns.info)
        )

      ~H"""
      <section
        id={@id}
        class={if @stacked, do: "vis-board vis-board-stacked", else: "vis-board"}
        phx-hook="BoardHook"
        data-board-event="resize"
        aria-label={@title || "Board"}
      >
        <header :if={@title || @window} class="vis-board-header">
          <h2 :if={@title} class="vis-board-title">{@title}</h2>
          <p :if={@window} class="vis-board-window">{@window}</p>
        </header>
        <div
          class="vis-board-grid"
          style={"display:grid;grid-template-columns:repeat(12,minmax(0,1fr));grid-auto-rows:#{@layout.row_height}px;gap:#{@layout.gap}px"}
        >
          <.live_component
            :for={{name, rect} <- @placed}
            module={Cell}
            id={cell_id(@id, name)}
            cell={name}
            rect={rect}
            title={Map.get(@board.cells[name], :title)}
            theme={@theme}
            target={@myself}
          />
        </div>
      </section>
      """
    end

    # The window in the board's zone (spec/15 §1.5): UTC in, the zone out.
    defp window_text(%{window: window, zone: zone}), do: Board.window_text(window, zone)
    defp window_text(_info), do: nil

    defmodule Cell do
      @moduledoc """
      One cell of `Visualize.Components.Board` (spec/15 §9.1): placed on the grid, one tab
      stop carrying `data-vis-cell`, its chart wrapped in `CrosshairHook`, `BrushHook` and
      `KeyboardHook`, and its state drawn over or instead of the chart. Updated by
      `Visualize.Components.Board.forward/2` with a `Visualize.Board.View`; never blank, a
      cell with no view yet shows `:loading`.
      """

      use Phoenix.LiveComponent

      alias Visualize.Board.State

      @impl true
      def mount(socket), do: {:ok, assign(socket, view: nil)}

      @impl true
      def update(assigns, socket), do: {:ok, assign(socket, assigns)}

      @impl true
      def render(assigns) do
        %{x: x, y: y, w: w, h: h} = assigns.rect
        view = assigns.view
        state = if view, do: view.state, else: :loading

        assigns =
          assign(assigns,
            state: state,
            name: State.name(state),
            placement: "grid-column:#{x + 1} / span #{w};grid-row:#{y + 1} / span #{h}",
            svg: view && view.svg,
            note:
              (view && view.note) ||
                (view == nil && State.render(:loading, assigns.theme, {300, 150})),
            crosshair: (view && view.crosshair) || %{},
            keyboard: (view && view.keyboard) || %{},
            label: label(assigns.title, assigns.cell, state)
          )

        ~H"""
        <article
          id={@id}
          class={["vis-cell", "vis-cell-#{@name}"]}
          data-vis-cell={@cell}
          data-vis-state={@name}
          tabindex="0"
          role="group"
          aria-label={@label}
          style={@placement}
        >
          <h3 :if={@title} class="vis-cell-title">{@title}</h3>
          <div :if={@note && @svg} class="vis-cell-banner">{Phoenix.HTML.raw(@note)}</div>
          <div :if={@svg} id={"#{@id}-crosshair"} class="vis-cell-chart" phx-hook="CrosshairHook" {@crosshair}>
            <div
              id={"#{@id}-brush"}
              phx-hook="BrushHook"
                data-brush-type="x"
              data-brush-event="brush"
              data-brush-target={@target}
            >
              <div id={"#{@id}-keys"} phx-hook="KeyboardHook" tabindex="-1" {@keyboard}>
                {Phoenix.HTML.raw(@svg)}
              </div>
            </div>
          </div>
          <div :if={@note && !@svg} class="vis-cell-placeholder">{Phoenix.HTML.raw(@note)}</div>
        </article>
        """
      end

      defp label(title, cell, :live), do: "#{title || cell}: cell, Enter for its chart"
      defp label(title, cell, state), do: "#{title || cell}: #{State.words(state)}"
    end
  end
end
