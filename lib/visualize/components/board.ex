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

    ## Interaction across cells (spec/15 §13, D-151)

    A brush sets the board's window once rapid brushes settle, and the header's *Reset
    window* restores the window the board was started with. A click on a chart, or Enter on
    a point the keyboard reached, **picks** the point: in a cell with a `drill` target it
    opens that target, and in any other it selects the datum's `{field, value}` across the
    board. The header shows the selection and *Clear selection*; Escape clears it too.

    The component does not navigate. A drill is sent to the page's process as
    `{:visualize_board_drill, id, %{cell: cell, board: ref, vars: vars}}`, and the page,
    which knows its routes, follows it:

        def handle_info({:visualize_board_drill, "ops", %{board: :detail, vars: vars}}, socket) do
          {:noreply, push_navigate(socket, to: "/detail?" <> URI.encode_query(vars))}
        end

    A click on a datum whose mark's `tooltip` names an `event` (spec/14 §5.7) is sent the
    same way, as `{:visualize_board_event, id, %{cell: cell, event: event, fields: fields}}`,
    `fields` the strings the cell's `TooltipHook` read (D-161).

    ## A host-owned window (`brush: :host`, D-161)

    A page that keeps the window in its URL takes the brush itself. A brush, pushed once
    when its drag ends, is sent to the page as
    `{:visualize_board_brush, id, %{domain: [from, to]}}`, the ends UTC `DateTime`s, and
    the header's *Reset window* as `{:visualize_board_brush, id, %{domain: nil}}`; the
    component calls no window function. The page updates its URL and applies the window
    with `Visualize.Board.Server.window/2` — `%{from: from, to: to}`, or its own default
    for `nil` — which is never debounced; `Visualize.Board.Server.brush/2` takes the same
    window and debounces rapid re-brushes, if the page would rather.

    ## Assigns

      * `id` - the component's id, the board's DOM id and the prefix of its cells' (required)
      * `server` - the board process: a pid or a registered name (required)
      * `board` - the `%Visualize.Board{}` it runs (required): its cells, titles and layout
      * `theme` - the theme a cell is drawn in before its first view
        (default `Visualize.Theme.default/0`)
      * `title` - the board's heading (default the board's `meta.name`)
      * `width` - the width the grid is arranged at until `BoardHook` pushes one
        (default `1200`)
      * `brush` - who sets a brushed window: `:server`, the board process, or `:host`, the
        page (default `:server`)
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
        |> assign(:brush, brush_mode(Map.get(assigns, :brush, :server)))

      {:ok, subscribe(socket)}
    end

    defp brush_mode(mode) when mode in [:server, :host], do: mode

    defp brush_mode(mode) do
      raise ArgumentError, "a board's brush is :server or :host, got: #{inspect(mode)}"
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
    # board's window in UTC, or, under `brush: :host`, the page's to apply (D-161).
    def handle_event("brush", %{"domain" => [from, to]}, socket)
        when is_number(from) and is_number(to) and from < to do
      brushed(socket.assigns, [instant(from), instant(to)])
      {:noreply, socket}
    end

    # A cleared brush is a click as often as an undo, so it keeps the window; the header's
    # Reset window is the undo (spec/15 §13.1).
    def handle_event("brush_clear", _params, socket), do: {:noreply, socket}

    def handle_event("reset_window", _params, socket) do
      brushed(socket.assigns, nil)
      {:noreply, socket}
    end

    def handle_event("select_clear", _params, socket) do
      :ok = Server.select(socket.assigns.server, nil)
      {:noreply, socket}
    end

    def handle_event(_event, _params, socket), do: {:noreply, socket}

    defp instant(ms), do: DateTime.from_unix!(round(ms), :millisecond)

    # A window chosen on the board: the board process sets it, or the page is told
    # (spec/15 §9.2). `nil` is the undo, the window the board was started with.
    defp brushed(%{brush: :host, id: id}, domain) do
      send(self(), {:visualize_board_brush, id, %{domain: domain}})
    end

    defp brushed(%{server: server}, [from, to]),
      do: :ok = Server.brush(server, %{from: from, to: to})

    defp brushed(%{server: server}, nil), do: :ok = Server.reset_window(server)

    @impl true
    def render(assigns) do
      layout = Board.layout(assigns.board)
      width = assigns.width

      assigns =
        assign(assigns,
          layout: layout,
          placed: Board.arrange(assigns.board, width),
          stacked: width < layout.breakpoint,
          window: window_text(assigns.info),
          moved: match?(%{moved: true}, assigns.info),
          selection: selection_text(assigns.info)
        )

      ~H"""
      <section
        id={@id}
        class={if @stacked, do: "vis-board vis-board-stacked", else: "vis-board"}
        phx-hook="BoardHook"
        data-board-event="resize"
        data-board-selection={@selection}
        aria-label={@title || "Board"}
      >
        <header :if={@title || @window} class="vis-board-header">
          <h2 :if={@title} class="vis-board-title">{@title}</h2>
          <p :if={@window} class="vis-board-window">{@window}</p>
          <button
            :if={@moved}
            type="button"
            class="vis-board-reset"
            phx-click="reset_window"
            phx-target={@myself}
          >
            Reset window
          </button>
          <p :if={@selection} class="vis-board-selection" aria-live="polite">
            Selected: {@selection}
            <button type="button" phx-click="select_clear" phx-target={@myself}>
              Clear selection
            </button>
          </p>
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
            server={@server}
            board={@board}
            board_id={@id}
          />
        </div>
      </section>
      """
    end

    # The window in the board's zone (spec/15 §1.5): UTC in, the zone out.
    defp window_text(%{window: window, zone: zone}), do: Board.window_text(window, zone)
    defp window_text(_info), do: nil

    # The selection as a person reads it: the field and the value.
    defp selection_text(%{selection: {field, value}}) do
      text = if String.Chars.impl_for(value), do: to_string(value), else: inspect(value)
      "#{field} #{text}"
    end

    defp selection_text(_info), do: nil

    defmodule Cell do
      @moduledoc """
      One cell of `Visualize.Components.Board` (spec/15 §9.1): placed on the grid, one tab
      stop carrying `data-vis-cell`, its chart wrapped in `CrosshairHook`, `BrushHook` and
      `KeyboardHook`, and its state drawn over or instead of the chart. Updated by
      `Visualize.Components.Board.forward/2` with a `Visualize.Board.View`; never blank, a
      cell with no view yet shows `:loading`.

      Its chart's `KeyboardHook` pushes `pick` here (spec/15 §13): the board answers the
      row behind the point, and the cell opens its `drill` target through the page, or
      selects the datum's identity across the board.

      Its chart's `TooltipHook` pushes a mark's `data-tooltip-event` here too (D-161), and
      the cell sends it to the page as `{:visualize_board_event, board_id, %{cell:, event:,
      fields:}}`. Every event other than `pick` is a mark's.
      """

      use Phoenix.LiveComponent

      alias Visualize.Board
      alias Visualize.Board.{Server, State}

      @impl true
      def mount(socket), do: {:ok, assign(socket, view: nil)}

      @impl true
      def update(assigns, socket), do: {:ok, assign(socket, assigns)}

      @impl true
      def handle_event("pick", %{"series" => series, "index" => index}, socket)
          when is_integer(series) and series >= 0 and is_integer(index) and index >= 0 do
        %{server: server, cell: cell, board: board} = socket.assigns

        with {:ok, %{row: row, identity: identity}} <- Server.pick(server, cell, series, index) do
          picked(Board.drill(board, cell, row), identity, socket.assigns)
        end

        {:noreply, socket}
      end

      # `pick` is the cell's own, whatever its params: a mark naming its event `pick` is
      # never forwarded (spec/15 §9.2).
      def handle_event("pick", _params, socket), do: {:noreply, socket}

      # A mark's click, its datum's fields as the hook read them, is the page's (D-161).
      def handle_event(event, fields, socket) when is_map(fields) do
        %{board_id: board_id, cell: cell} = socket.assigns

        send(
          self(),
          {:visualize_board_event, board_id, %{cell: cell, event: event, fields: fields}}
        )

        {:noreply, socket}
      end

      # A drill goes to the page, which knows its routes; a datum with an identity is the
      # board's selection; a datum with neither does nothing (spec/15 §13.2, §13.3).
      defp picked({:ok, target}, _identity, assigns) do
        send(
          self(),
          {:visualize_board_drill, assigns.board_id, Map.put(target, :cell, assigns.cell)}
        )
      end

      defp picked(:none, nil, _assigns), do: :ok
      defp picked(:none, identity, assigns), do: Server.select(assigns.server, identity)
      defp picked({:error, _errors}, _identity, _assigns), do: :ok

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
              <div
                id={"#{@id}-keys"}
                phx-hook="KeyboardHook"
                tabindex="-1"
                data-keyboard-pick-event="pick"
                data-keyboard-target={@myself}
                {@keyboard}
              >
                <div id={"#{@id}-tooltip"} phx-hook="TooltipHook" data-tooltip-target={@myself}>
                  {Phoenix.HTML.raw(@svg)}
                </div>
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
