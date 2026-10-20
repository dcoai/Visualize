defmodule ExamplesWeb.MinesweeperLive do
  @moduledoc """
  Minesweeper (#758): a clickable grid drawn by a chart design, the game's state in the
  host. It is written as a host would write a dashboard's status grid, and shows the
  seams one needs in one page.

  - **The grid is a design.** One `:rect` per cell on two `:band` scales, styled by a stack
    whose last entry is `{:field, :state}`: each cell's state names its style (spec/14
    §3.6). A `:text` mark writes the counts, colored through a `:threshold` color scale
    whose range is typed colors (spec/14 §3.2), and a `:symbol` mark draws the flags and
    the mines, each glyph's style, and with it its marker shape, chosen by `{:field,
    :glyph}`.
  - **A cell is an identity.** The page binds its rows as a `Visualize.Data.Delivery`
    under a schema that declares `row` and `col` together as the cell's identity (D-167),
    and the design requires it.
  - **A click is an event.** The cells declare `event: :cell_click` and `context_event:
    :flag`, so `Visualize.Components.Chart` resolves a click to the cell drawn and sends the
    page one `Visualize.Event` (D-170), the cell in its `item`. Flag mode, or a click with
    Shift held (the event's `modifiers`), flags instead of revealing; a right-click, a
    long-press or the Menu key sends `flag` (D-199), which flags in either mode.
  - **Every backend, and the keyboard.** The grid is drawn as SVG, on the JSON canvas or on
    the binary canvas, a click resolving through the drawing's hit index on a canvas
    (D-197), and the chart is one tab stop whose cells the arrows reach by row and by
    column, Enter revealing the focused cell (D-198).
  - **The host owns the game.** `Examples.Minesweeper` is the state and the rules; each
    move is a new game value, and the chart is drawn again from its rows. A cell's fill
    fades between its states and a glyph grows in, by identity (spec/14 §3.10, §3.12).
  """
  use Phoenix.LiveView

  import Visualize.Color, only: [color: 1]

  alias Examples.Minesweeper
  alias Examples.Minesweeper.Move
  alias ExamplesWeb.{Highlight, Panel}
  alias Visualize.Chart
  alias Visualize.Data.{Delivery, Schema}
  alias Visualize.Event

  # A 9 × 9 grid of 40-pixel cells inside a 4-pixel margin.
  @size {368, 368}
  @cells Enum.to_list(0..8)

  @design %{
    version: 3,
    meta: %{name: "Minesweeper"},
    sources: %{
      cells: %{
        fields: [:row, :col, :state, :count, :glyph],
        # The cell is the identity its feed declares (D-167).
        requires: %{row: [:identity], col: [:identity]}
      }
    },
    styles: %{
      # Every cell: a gap of the page's background between neighbors, and its fill fading
      # from one state's to the next.
      cell: %{
        stroke: %{color: color(:background), width: 2},
        transition: %{fill: %{duration: 180}}
      },
      # A style per state, named by the cell's `state` (spec/14 §3.6).
      hidden: %{fill: %{color: color(:gray), opacity: 0.45}},
      flagged: %{fill: %{color: color(:gray), opacity: 0.45}},
      revealed: %{fill: %{color: color(:gray), opacity: 0.08}},
      mine: %{fill: %{color: color(:gray), opacity: 0.08}},
      misflagged: %{fill: %{color: color(:gray), opacity: 0.08}},
      # The mine that was revealed: the palette's `:bad`.
      exploded: %{extends: :bad},
      # The count's face; its fill is the count through the color scale.
      count: %{fill: {:field, :count}},
      count_face: %{extends: :label, font: %{size: 18, weight: :bold}},
      # A style per glyph, named by the cell's `glyph`: its marker shape and its color.
      flag: %{
        marker: %{shape: :triangle, size: 150},
        fill: color(:red),
        enter: %{name: :grow, duration: 180},
        exit: %{name: :shrink, duration: 180}
      },
      bomb: %{marker: %{shape: :circle, size: 200}, fill: color(:text)},
      cross: %{marker: %{shape: :cross, size: 200}, fill: color(:red)}
    },
    frames: %{
      main: %{
        kind: :cartesian,
        margin: %{top: 4, right: 4, bottom: 4, left: 4},
        scales: %{
          x: %{kind: :band, domain: @cells},
          # A band's first category is at the bottom: the rows run down from the top.
          y: %{kind: :band, domain: Enum.reverse(@cells)},
          # The classic colors of the counts, one to eight.
          color: %{
            kind: :threshold,
            domain: Enum.to_list(2..8),
            range: [
              color(:blue),
              color(:green),
              color(:red),
              color(:navy),
              color(:maroon),
              color(:teal),
              color(:text),
              color(:gray)
            ]
          }
        }
      }
    },
    marks: [
      %{
        type: :rect,
        data: :cells,
        channels: %{x0: :col, x1: :col, y0: :row, y1: :row},
        options: %{corner_radius: 3},
        style: [:cell, {:field, :state}],
        tooltip: %{
          fields: [:state, :count],
          template: "{state} {count}",
          event: :cell_click,
          context_event: :flag
        }
      },
      %{
        type: :text,
        data: %{source: :cells, transforms: [%{op: :filter, field: :count, test: :present}]},
        channels: %{x: :col, y: :row},
        label: %{text: [{:field, :count}], anchor: :middle, style: :count_face},
        style: :count
      },
      %{
        type: :symbol,
        data: %{source: :cells, transforms: [%{op: :filter, field: :glyph, test: :present}]},
        channels: %{x: :col, y: :row},
        style: {:field, :glyph}
      }
    ]
  }

  @doc "The design the grid is drawn by."
  @spec design() :: map()
  def design, do: @design

  @doc """
  The schema the cells are delivered under: `row` and `col` together are a cell's
  identity (D-167).
  """
  @spec schema() :: Schema.t()
  def schema do
    Schema.new!(%{
      row: %{type: :category, label: "Row", identity: true},
      col: %{type: :category, label: "Column", identity: true},
      state: %{type: :category, label: "State"},
      count: %{type: :number, label: "Mines around"},
      glyph: %{type: :category, label: "Glyph"}
    })
  end

  @doc """
  The grid of `game` drawn: the design applied to the game's rows, at `size` — the page's
  own unless given, as the interaction page's panel gives its own (#800).
  """
  @spec applied(Minesweeper.t(), {pos_integer(), pos_integer()}) :: Chart.Applied.t()
  def applied(game, size \\ @size) do
    schema = schema()

    {:ok, applied} =
      Chart.apply(@design,
        sources: %{cells: Delivery.new(Minesweeper.rows(game), schema: Schema.version(schema))},
        schemas: Schema.Cache.new([{:cells, schema}]),
        size: size
      )

    applied
  end

  # The backends the grid is drawn on, by the name the switch sends: the component's
  # `backend` and `canvas_format` (spec/10 §19.3). A name not here is refused, and no atom
  # is made of it.
  @backends %{
    "svg" => {"SVG", []},
    "json" => {"Canvas (JSON)", [backend: :canvas, canvas_format: :json]},
    "binary" => {"Canvas (binary)", [backend: :canvas, canvas_format: :binary]}
  }

  @doc "The backends the page draws on: `{name, label, component options}`, in order."
  @spec backends() :: [{String.t(), String.t(), keyword()}]
  def backends,
    do: for(name <- ~w(svg json binary), {label, opts} = @backends[name], do: {name, label, opts})

  # A `seed` in the address replays its game; without one each game is new.
  @impl true
  def mount(params, _session, socket) do
    {:ok, socket |> assign(mode: :reveal, backend: "svg") |> start(seed(params))}
  end

  defp seed(%{"seed" => seed}) do
    case Integer.parse(seed) do
      {n, ""} -> n
      _other -> nil
    end
  end

  defp seed(_params), do: nil

  defp start(socket, seed) do
    game = if seed, do: Minesweeper.new(seed: seed), else: Minesweeper.new()
    assign(socket, game: game, chart: applied(game), started: nil, elapsed: 0)
  end

  # A click on a cell, resolved by the chart's component to the cell drawn (D-170), or a
  # right-click, a long-press or the Menu key on one (D-199): the step to the next game is
  # the one the interaction page's panel takes too (`Move.play/3`).
  @impl true
  def handle_info({:visualize_event, "mines-chart", %Event{} = event}, socket) do
    game = Move.play(socket.assigns.game, event, socket.assigns.mode)
    {:noreply, socket |> clock(game) |> assign(game: game, chart: applied(game))}
  end

  # The clock, once a second while its game is under way; a tick of a game *New game*
  # replaced finds another start, and stops.
  def handle_info({:tick, started}, %{assigns: %{started: started}} = socket) do
    if socket.assigns.game.status == :playing do
      Process.send_after(self(), {:tick, started}, 1000)
      {:noreply, assign(socket, elapsed: seconds_since(started))}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:tick, _started}, socket), do: {:noreply, socket}

  # The clock starts at the first reveal and stops when the game is over.
  defp clock(%{assigns: %{started: nil}} = socket, %{status: :playing}) do
    started = System.monotonic_time(:millisecond)
    if connected?(socket), do: Process.send_after(self(), {:tick, started}, 1000)
    assign(socket, started: started)
  end

  defp clock(%{assigns: %{started: started, game: before}} = socket, game)
       when started != nil and before.status == :playing and game.status != :playing,
       do: assign(socket, elapsed: seconds_since(started))

  defp clock(socket, _game), do: socket

  defp seconds_since(started),
    do: div(System.monotonic_time(:millisecond) - started, 1000)

  @impl true
  def handle_event("mode", %{"mode" => mode}, socket) when mode in ~w(reveal flag),
    do: {:noreply, assign(socket, mode: String.to_existing_atom(mode))}

  def handle_event("new", _params, socket), do: {:noreply, start(socket, nil)}

  def handle_event("backend", %{"backend" => name}, socket) when is_map_key(@backends, name),
    do: {:noreply, assign(socket, backend: name)}

  def handle_event("backend", _params, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <ExamplesWeb.SiteHeader.header tab={:interaction} />
    <main>
      <a href="/interaction" class="back-link"><span>&larr;</span> Back to Interactions</a>

      <div class="panels">
        <Panel.panel id="panel-minesweeper">
          <:title>Minesweeper</:title>
          <p class="panel-note">
            Reveal every cell without a mine. A number is how many of the eight cells
            around it hold one. The first click is always safe. Flag a cell you think is
            mined with a right-click, a long-press, <em>Flag</em> mode, or by holding Shift
            as you click. From the keyboard, Tab to the grid, move with the arrows, reveal
            with Enter and flag with the Menu key or Shift+F10.
          </p>

          <div class="mines-bar">
            <span class="mines-mode" role="group" aria-label="click mode">
              <button
                :for={{mode, name} <- [reveal: "Reveal", flag: "Flag"]}
                type="button"
                phx-click="mode"
                phx-value-mode={mode}
                aria-pressed={to_string(@mode == mode)}
              >
                {name}
              </button>
            </span>
            <button type="button" phx-click="new">New game</button>
            <span class="mines-backend-switch" role="group" aria-label="backend">
              <button
                :for={{name, label, _opts} <- backends()}
                type="button"
                phx-click="backend"
                phx-value-backend={name}
                aria-pressed={to_string(@backend == name)}
              >
                {label}
              </button>
            </span>
          </div>

          <.status game={@game} elapsed={@elapsed} />

          <div class="chart-container mines-board">
            <.live_component
              module={Visualize.Components.Chart}
              id="mines-chart"
              chart={@chart}
              {component_backend(@backend)}
            />
          </div>

          <p class="panel-note mines-backend">
            The same game on every backend. On the SVG a click lands on the cell's element;
            on a canvas, which draws none, <code>TooltipHook</code>
            finds the cell in the hit index drawn beside the stream, so the page receives
            the same <code>Visualize.Event</code>
            either way. <code>KeyboardHook</code>
            reaches the cells by row and column.
          </p>
        </Panel.panel>

        <Panel.panel id="panel-mines-code">
          <:title>The host's part</:title>
          <p class="panel-note">
            The design draws the rows the game gives it; the page turns each click into
            the next game.
          </p>
          <Highlight.code code={code()} />
        </Panel.panel>
      </div>
    </main>

    <style>
      .mines-bar { display: flex; gap: 1rem; align-items: center; margin: 0.5rem 0; }
      .mines-mode button[aria-pressed="true"], .mines-backend-switch button[aria-pressed="true"] { font-weight: bold; }
      <%= Phoenix.HTML.raw(board_css()) %>
    </style>
    """
  end

  # The component's options for the backend chosen.
  defp component_backend(name), do: @backends |> Map.fetch!(name) |> elem(1)

  @doc """
  The stylesheet a page drawing the grid includes: the status line's colors, a pointer
  over the cells, and the counts and glyphs drawn over a cell letting its click through.
  """
  @spec board_css() :: String.t()
  def board_css do
    """
    .mines-status { margin: 0.5rem 0; color: #444; }
    .mines-won { color: #2e7d32; }
    .mines-lost { color: #c23238; }
    .mines-board .mark-rect rect { cursor: pointer; }
    .mines-board .mark-text, .mines-board .mark-symbol { pointer-events: none; }
    """
  end

  @doc """
  The status line: the mines left, the time when the page keeps a clock, and how the game
  stands.
  """
  attr(:game, Minesweeper, required: true)
  attr(:elapsed, :integer, default: nil, doc: "the game's time in seconds; `nil` shows none")

  def status(assigns) do
    ~H"""
    <p class="mines-status" aria-live="polite">
      <span class="mines-left">{Minesweeper.mines_left(@game)} mines left</span>
      <span :if={@elapsed}>· <span class="mines-time">{clock_text(@elapsed)}</span></span>
      · <strong class={"mines-outcome mines-#{@game.status}"}>{outcome(@game.status)}</strong>
    </p>
    """
  end

  defp clock_text(seconds),
    do: "#{div(seconds, 60)}:#{String.pad_leading(Integer.to_string(rem(seconds, 60)), 2, "0")}"

  defp outcome(:ready), do: "Click any cell to start"
  defp outcome(:playing), do: "Playing"
  defp outcome(:won), do: "Cleared: you won"
  defp outcome(:lost), do: "Boom: you lost"

  # Elixir a reader can paste: the marks, the styles they name, and the page's one clause.
  defp code do
    ~S'''
    # A rect per cell on two band scales; each cell's state names its style.
    %{type: :rect, data: :cells, channels: %{x0: :col, x1: :col, y0: :row, y1: :row},
      style: [:cell, {:field, :state}],
      tooltip: %{fields: [:state, :count], template: "{state} {count}",
                 event: :cell_click, context_event: :flag}}

    # The counts, colored through a threshold scale whose range is typed colors.
    %{type: :text, data: %{source: :cells, transforms: [%{op: :filter, field: :count, test: :present}]},
      channels: %{x: :col, y: :row}, label: %{text: [{:field, :count}], anchor: :middle},
      style: %{fill: {:field, :count}}}

    # A flag, a mine or a cross: the glyph names the style, and the style the marker.
    %{type: :symbol, data: %{source: :cells, transforms: [%{op: :filter, field: :glyph, test: :present}]},
      channels: %{x: :col, y: :row}, style: {:field, :glyph}}

    styles: %{
      hidden: %{fill: %{color: color(:gray), opacity: 0.45}},
      revealed: %{fill: %{color: color(:gray), opacity: 0.08}},
      exploded: %{extends: :bad},
      flag: %{marker: %{shape: :triangle, size: 150}, fill: color(:red)},
      bomb: %{marker: %{shape: :circle, size: 200}, fill: color(:text)}
    }

    # The cell is the identity its feed declares (D-167).
    schema = Schema.new!(%{row: %{type: :category, identity: true},
                           col: %{type: :category, identity: true}, ...})

    ~H"""
    <.live_component module={Visualize.Components.Chart} id="mines-chart" chart={@chart}
                     backend={:canvas} />
    """

    # A right-click, a long-press or the Menu key on a cell flags it.
    def handle_info({:visualize_event, "mines-chart",
                     %Visualize.Event{event: "flag", item: {_mark, %{"row" => r, "col" => c}}}}, socket) do
      game = Minesweeper.toggle_flag(socket.assigns.game, {r, c})
      {:noreply, assign(socket, game: game, chart: applied(game))}
    end

    def handle_info({:visualize_event, "mines-chart",
                     %Visualize.Event{event: "cell_click", item: {_mark, %{"row" => r, "col" => c}}}}, socket) do
      game = Minesweeper.reveal(socket.assigns.game, {r, c})
      {:noreply, assign(socket, game: game, chart: applied(game))}
    end
    '''
  end
end
