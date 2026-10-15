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

    ## Events (spec/15 §9.2, D-170)

    Everything the page is sent is one `Visualize.Event`, as
    `{:visualize_event, id, %Visualize.Event{}}`, `id` this component's:

      * a mark's declared event — a click on a datum whose mark's `tooltip` names an
        `event` (spec/14 §5.7) — with the cell, and the row as the mark drew it, typed,
        resolved by the cell's process against the drawing it holds;
      * `:drill`, `value: %{board: ref, vars: vars}`, when a pick in a cell with a `drill`
        resolves its target, with the picked row;
      * `:brush`, `value: %{domain: [from, to] | nil}`, under `brush: :host`;
      * `:select`, `value: %{identity: identity | nil}`, whenever the board's selection
        changes.

    The component does not navigate. The page, which knows its routes, follows a drill:

        def handle_info({:visualize_event, "ops", %Visualize.Event{event: :drill, value: %{board: :detail, vars: vars}}}, socket) do
          {:noreply, push_navigate(socket, to: "/detail?" <> URI.encode_query(vars))}
        end

    ## A host-owned window (`brush: :host`, D-161)

    A page that keeps the window in its URL takes the brush itself. A brush, pushed once
    when its drag ends, is sent to the page as the `:brush` event with
    `value: %{domain: [from, to]}`, the ends UTC `DateTime`s, and the header's
    *Reset window* with `value: %{domain: nil}`; the component calls no window function. The page updates its URL and applies the window
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
    alias Visualize.Event

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
      selected(socket.assigns, info)
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

    # A change of the board's selection is the page's to know (spec/15 §9.2, D-170), so a
    # host can keep it in its URL; the selection held when the page subscribed is not one.
    defp selected(%{info: %{selection: before}, id: id}, %{selection: now}) when before != now do
      send(self(), {:visualize_event, id, %Event{event: :select, value: %{identity: now}}})
    end

    defp selected(_assigns, _info), do: :ok

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
      send(self(), {:visualize_event, id, %Event{event: :brush, value: %{domain: domain}}})
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

    # The selection as a person reads it: the field and the value, a composite one's
    # fields in name order (spec/15 §9.2, D-167).
    defp selection_text(%{selection: {field, value}}), do: "#{field} #{value_text(value)}"

    defp selection_text(%{selection: %{} = fields}) do
      fields
      |> Enum.sort_by(fn {field, _value} -> to_string(field) end)
      |> Enum.map_join(", ", fn {field, value} -> "#{field} #{value_text(value)}" end)
    end

    defp selection_text(_info), do: nil

    defp value_text(value),
      do: if(String.Chars.impl_for(value), do: to_string(value), else: inspect(value))

    defmodule Cell do
      @moduledoc """
      One cell of `Visualize.Components.Board` (spec/15 §9.1): placed on the grid, one tab
      stop carrying `data-vis-cell`, its chart wrapped in `CrosshairHook`, `BrushHook` and
      `KeyboardHook`, and its state drawn over or instead of the chart. Updated by
      `Visualize.Components.Board.forward/2` with a `Visualize.Board.View`; never blank, a
      cell with no view yet shows `:loading`.

      Its chart's `KeyboardHook` pushes `pick` here (spec/15 §13): the board answers the
      row behind the point, and the cell opens its `drill` target through the page, as the
      `:drill` event, or selects the datum's identity across the board.

      Its chart's `TooltipHook` pushes a mark's click here as `visualize_event` (D-161,
      D-170), carrying the view's `drawn` token: the cell's process resolves it against the
      drawing it holds (`Visualize.Board.Server.event/3`), and the page is sent the
      resolved `Visualize.Event`. A click it cannot resolve sends nothing.
      """

      use Phoenix.LiveComponent

      alias Visualize.Board
      alias Visualize.Board.{Server, State}
      alias Visualize.Event

      @impl true
      def mount(socket), do: {:ok, assign(socket, view: nil)}

      @impl true
      def update(assigns, socket), do: {:ok, assign(socket, assigns)}

      @impl true
      def handle_event("pick", %{"series" => series, "index" => index}, socket)
          when is_integer(series) and series >= 0 and is_integer(index) and index >= 0 do
        %{server: server, cell: cell, board: board} = socket.assigns

        with {:ok, point} <- Server.pick(server, cell, series, index) do
          picked(Board.drill(board, cell, point.row), point, socket.assigns)
        end

        {:noreply, socket}
      end

      def handle_event("pick", _params, socket), do: {:noreply, socket}

      # A mark's click, resolved by the cell's process against the drawing it holds, is the
      # page's (spec/15 §9.2, D-161, D-170); a click it cannot resolve — another drawing's,
      # an undeclared name, the cell's own `pick` — sends nothing.
      def handle_event("visualize_event", params, socket) do
        %{server: server, cell: cell, board_id: board_id} = socket.assigns

        with {:ok, click} <- Event.decode(params),
             {:ok, event} <- Server.event(server, cell, click) do
          send(self(), {:visualize_event, board_id, event})
        end

        {:noreply, socket}
      end

      def handle_event(_event, _params, socket), do: {:noreply, socket}

      # A drill goes to the page, which knows its routes; a datum with an identity is the
      # board's selection; a datum with neither does nothing (spec/15 §13.2, §13.3).
      defp picked({:ok, target}, point, assigns) do
        event = %Event{
          event: :drill,
          cell: assigns.cell,
          frame: point.frame,
          item: point.item,
          path: List.wrap(point.item),
          row: point.row,
          value: target
        }

        send(self(), {:visualize_event, assigns.board_id, event})
      end

      defp picked(:none, %{identity: nil}, _assigns), do: :ok

      defp picked(:none, %{identity: identity}, assigns),
        do: Server.select(assigns.server, identity)

      defp picked({:error, _errors}, _point, _assigns), do: :ok

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
            drawn: view && view.drawn,
            # A drawing that names identities plays its exits and enters (spec/15 §9.1).
            motion:
              view != nil and is_binary(view.svg) and String.contains?(view.svg, "data-vis-id"),
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
                <div
                  id={"#{@id}-tooltip"}
                  phx-hook="TooltipHook"
                  data-tooltip-target={@myself}
                  data-tooltip-drawn={@drawn}
                >
                  <div :if={@motion} id={"#{@id}-motion"} phx-hook="MotionHook">
                    {Phoenix.HTML.raw(@svg)}
                  </div>
                  {if @motion, do: nil, else: Phoenix.HTML.raw(@svg)}
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
