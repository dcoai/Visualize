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
  - **Any board up to 50 × 50.** Beginner, Intermediate, Expert or a custom size, the
    board and the seed in the address (`?rows=&cols=&mines=&seed=`), so a game can be
    replayed or shared; each value is read as a whole number and clamped, and anything
    else is Beginner's. The design is built for the board, its cell the page's width shared
    among the columns (40 pixels at most, 24 at 50 columns, never under 16: a narrower
    window scrolls the board).
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

  # A cell is 40 pixels at most, the classic boards' size, and 16 at least, the smallest
  # that stays clickable and legible; between, a board takes the width the page gives its
  # panel (`@width`, the layout's 1,400-pixel main less its padding and the panel's) — 24
  # pixels at 50 columns. The grid sits inside a 4-pixel margin.
  @max_cell 40
  @min_cell 16
  @width 1200
  @margin 4

  @doc """
  The design the grid is drawn by, for a board of `rows × cols` cells of `cell` pixels:
  the band scales' domains are the board's rows and columns, and the counts' face and
  the glyphs follow the cell, at their 40-pixel sizes on a cell that large or larger.
  """
  @spec design(pos_integer(), pos_integer(), number()) :: map()
  def design(rows \\ 9, cols \\ 9, cell \\ @max_cell) do
    # A glyph's marker size is an area, so it scales with the cell's square.
    scale = min(cell / @max_cell, 1.0)
    area = fn size -> round(size * scale * scale) end

    %{
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
        count_face: %{extends: :label, font: %{size: min(18, round(cell * 0.6)), weight: :bold}},
        # A style per glyph, named by the cell's `glyph`: its marker shape and its color.
        flag: %{
          marker: %{shape: :triangle, size: area.(150)},
          fill: color(:red),
          enter: %{name: :grow, duration: 180},
          exit: %{name: :shrink, duration: 180}
        },
        bomb: %{marker: %{shape: :circle, size: area.(200)}, fill: color(:text)},
        cross: %{marker: %{shape: :cross, size: area.(200)}, fill: color(:red)}
      },
      frames: %{
        main: %{
          kind: :cartesian,
          margin: %{top: @margin, right: @margin, bottom: @margin, left: @margin},
          scales: %{
            x: %{kind: :band, domain: Enum.to_list(0..(cols - 1))},
            # A band's first category is at the bottom: the rows run down from the top.
            y: %{kind: :band, domain: Enum.to_list((rows - 1)..0//-1)},
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
          # The cell's events with nothing under the pointer (D-200); the template is the
          # keyboard readout's text for the cell (D-198).
          tooltip: %{
            fields: [:state, :count],
            template: "{state} {count}",
            event: :cell_click,
            context_event: :flag,
            show: false
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
  end

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
  The side of a cell, in pixels, on the full page for a board of `rows × cols`: the
  page's width shared among the columns, 40 at most and 16 at least. Below 16 a board
  would scroll rather than shrink (`board_css/0`); 50 columns are 24 pixels each.
  """
  @spec cell_size(pos_integer(), pos_integer()) :: pos_integer()
  def cell_size(_rows, cols), do: (@width / cols) |> floor() |> max(@min_cell) |> min(@max_cell)

  @doc "The size the full page draws `game`'s grid at: its cells and the margin around them."
  @spec size(Minesweeper.t()) :: {pos_integer(), pos_integer()}
  def size(%Minesweeper{rows: rows, cols: cols}) do
    cell = cell_size(rows, cols)
    {cols * cell + 2 * @margin, rows * cell + 2 * @margin}
  end

  @doc """
  The narrowest the full page lets `game`'s grid be drawn, in pixels: every cell at 16.
  A page narrower than that scrolls the board.
  """
  @spec min_width(Minesweeper.t()) :: pos_integer()
  def min_width(%Minesweeper{cols: cols}), do: cols * @min_cell + 2 * @margin

  @doc """
  The grid of `game` drawn: the design for its board applied to its rows, at `size` — the
  full page's (`size/1`) unless given, as the interaction page's panel gives its own
  (#800). The cell's side, which the counts and glyphs follow, is what `size` leaves
  each.
  """
  @spec applied(Minesweeper.t(), {pos_integer(), pos_integer()} | nil) :: Chart.Applied.t()
  def applied(%Minesweeper{rows: rows, cols: cols} = game, size \\ nil) do
    {width, height} = size = size || size(game)
    cell = min((width - 2 * @margin) / cols, (height - 2 * @margin) / rows)
    schema = schema()

    {:ok, applied} =
      Chart.apply(design(rows, cols, cell),
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

  # The boards a player picks by name, by the name the selector sends; a name not here is
  # refused, and no atom is made of it.
  @presets [
    {"beginner", "Beginner", {9, 9, 10}},
    {"intermediate", "Intermediate", {16, 16, 40}},
    {"expert", "Expert", {16, 30, 99}}
  ]
  @beginner {9, 9, 10}
  # A custom board's rows and columns, each.
  @sides 5..50
  # A custom board's mines when none are given: about one cell in six, between
  # Intermediate's density and Expert's.
  @density 0.16

  @doc "The boards the selector names: `{name, label, {rows, cols, mines}}`, in order."
  @spec presets() :: [{String.t(), String.t(), {pos_integer(), pos_integer(), pos_integer()}}]
  def presets, do: @presets

  @doc """
  The board `params` ask for, `{rows, cols, mines}`, from the address's or the Custom
  form's `"rows"`, `"cols"` and `"mines"`. Each is read as a whole number and clamped:
  rows and columns to 5–50, mines to 1 up to every cell but one; mines left out are
  about one cell in six. A board not asked for, or one with any value that is not a
  whole number, is Beginner's.

      iex> ExamplesWeb.MinesweeperLive.board(%{"rows" => "16", "cols" => "30", "mines" => "99"})
      {16, 30, 99}
      iex> ExamplesWeb.MinesweeperLive.board(%{"rows" => "80", "cols" => "2", "mines" => "0"})
      {50, 5, 1}
      iex> ExamplesWeb.MinesweeperLive.board(%{"rows" => "50", "cols" => "50"})
      {50, 50, 400}
      iex> ExamplesWeb.MinesweeperLive.board(%{"rows" => "ten", "cols" => "9"})
      {9, 9, 10}
  """
  @spec board(map()) :: {pos_integer(), pos_integer(), pos_integer()}
  def board(%{"rows" => rows, "cols" => cols} = params) do
    with {:ok, rows} <- whole(rows),
         {:ok, cols} <- whole(cols),
         {:ok, mines} <- whole(Map.get(params, "mines"), :default) do
      rows = clamp(rows, @sides)
      cols = clamp(cols, @sides)
      mines = if mines == :default, do: round(rows * cols * @density), else: mines
      {rows, cols, clamp(mines, 1..(rows * cols - 1))}
    else
      :error -> @beginner
    end
  end

  def board(_params), do: @beginner

  # A whole number written as one, as an address or a form gives it; `default` for a value
  # left out or left empty.
  defp whole(value, default \\ :error)
  defp whole(nil, default), do: if(default == :error, do: :error, else: {:ok, default})

  defp whole(value, default) when is_binary(value) do
    case value |> String.trim() |> Integer.parse() do
      {n, ""} -> {:ok, n}
      :error when value == "" and default != :error -> {:ok, default}
      _other -> :error
    end
  end

  defp whole(_value, _default), do: :error

  defp clamp(n, lo..hi//_), do: n |> max(lo) |> min(hi)

  @doc """
  The address of a game: its board and its seed, so the game can be replayed or shared.

      iex> ExamplesWeb.MinesweeperLive.path({16, 30, 99}, 7)
      "/minesweeper?rows=16&cols=30&mines=99&seed=7"
  """
  @spec path({pos_integer(), pos_integer(), pos_integer()}, integer()) :: String.t()
  def path({rows, cols, mines}, seed),
    do: "/minesweeper?" <> URI.encode_query(rows: rows, cols: cols, mines: mines, seed: seed)

  defp board_of(%Minesweeper{rows: rows, cols: cols, mines: mines}), do: {rows, cols, mines}

  # The preset `game` is played on, or nil for a custom board.
  defp preset(game) do
    Enum.find_value(@presets, fn {name, _label, board} -> board == board_of(game) && name end)
  end

  # The board and the `seed` in the address are the game: the seed replays it, and a board
  # without one is a new game, its seed then written into the address.
  @impl true
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(mode: :reveal, backend: "svg")
     |> start(board(params), seed(params) || new_seed())}
  end

  # A game the address names is played, unless it is the one already on the page; the
  # address is then rewritten to the game's own, so a clamped value or a missing seed is
  # what the address says.
  @impl true
  def handle_params(params, uri, socket) do
    board = board(params)
    game = socket.assigns.game
    seed = seed(params) || if(board == board_of(game), do: game.seed, else: new_seed())

    socket =
      if {board, seed} == {board_of(game), game.seed},
        do: socket,
        else: start(socket, board, seed)

    {:noreply, address(socket, uri)}
  end

  defp address(socket, uri) do
    %URI{path: path, query: query} = URI.parse(uri)
    own = path(board_of(socket.assigns.game), socket.assigns.game.seed)

    if connected?(socket) and "#{path}?#{query}" != own,
      do: push_patch(socket, to: own, replace: true),
      else: socket
  end

  defp seed(%{"seed" => seed}) do
    case whole(seed) do
      {:ok, n} -> n
      :error -> nil
    end
  end

  defp seed(_params), do: nil

  defp new_seed, do: :rand.uniform(1_000_000_000)

  defp start(socket, {rows, cols, mines}, seed) do
    game = Minesweeper.new(rows: rows, cols: cols, mines: mines, seed: seed)
    assign(socket, game: game, chart: applied(game), started: nil, elapsed: 0)
  end

  # A new game on `board`, in the address under a new seed.
  defp play(socket, board) do
    seed = new_seed()
    socket |> start(board, seed) |> push_patch(to: path(board, seed))
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

  def handle_event("new", _params, socket),
    do: {:noreply, play(socket, board_of(socket.assigns.game))}

  # A preset by its name, or the Custom form's rows, columns and mines, clamped.
  def handle_event("preset", %{"preset" => name}, socket) do
    case List.keyfind(@presets, name, 0) do
      {^name, _label, board} -> {:noreply, play(socket, board)}
      nil -> {:noreply, socket}
    end
  end

  def handle_event("custom", params, socket), do: {:noreply, play(socket, board(params))}

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

          <form class="mines-bar mines-size" phx-submit="custom">
            <span class="backend-buttons" role="group" aria-label="board size">
              <.toggle
                :for={{name, label, _board} <- presets()}
                event="preset"
                name="preset"
                value={name}
                on={preset(@game) == name}
              >
                {label}
              </.toggle>
              <button
                type="submit"
                class={"backend-btn" <> if(preset(@game), do: "", else: " active")}
                aria-pressed={to_string(preset(@game) == nil)}
              >
                Custom
              </button>
            </span>
            <span class="mines-custom">
              <input
                type="number"
                name="rows"
                aria-label="rows"
                min="5"
                max="50"
                value={@game.rows}
              /> ×
              <input
                type="number"
                name="cols"
                aria-label="columns"
                min="5"
                max="50"
                value={@game.cols}
              />,
              <%!-- No max: rows and columns may change in the same submit, and the page clamps. --%>
              <input
                type="number"
                name="mines"
                aria-label="mines"
                min="1"
                value={@game.mines}
              /> mines
            </span>
          </form>

          <div class="mines-bar">
            <span class="backend-buttons mines-mode" role="group" aria-label="click mode">
              <.toggle
                :for={{mode, name} <- [reveal: "Reveal", flag: "Flag"]}
                event="mode"
                name="mode"
                value={mode}
                on={@mode == mode}
              >
                {name}
              </.toggle>
            </span>
            <span class="backend-buttons">
              <button type="button" class="backend-btn" phx-click="new">New game</button>
            </span>
            <span class="backend-buttons mines-backend-switch" role="group" aria-label="backend">
              <.toggle
                :for={{name, label, _opts} <- backends()}
                event="backend"
                name="backend"
                value={name}
                on={@backend == name}
              >
                {label}
              </.toggle>
            </span>
          </div>

          <.status game={@game} elapsed={@elapsed} />

          <div
            class="chart-container mines-board mines-page-board"
            style={"--mines-min-width: #{min_width(@game)}px"}
          >
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
      .mines-bar { display: flex; flex-wrap: wrap; gap: 1rem; align-items: center; margin: 0.5rem 0; }
      .mines-custom { color: #444; font-size: 14px; }
      .mines-custom input { width: 4.5em; padding: 0.4rem; border: 2px solid #ddd; border-radius: 6px; font: inherit; }
      .mines-custom input:focus-visible { outline: 3px solid #667eea; outline-offset: 1px; }
      /* A cell shrinks with a narrow window to 16 pixels, and the board then scrolls (#806). */
      .mines-page-board { overflow-x: auto; justify-content: safe center; }
      .mines-page-board svg { min-width: var(--mines-min-width); }
      <%= Phoenix.HTML.raw(board_css()) %>
    </style>
    """
  end

  attr(:event, :string, required: true, doc: "the `phx-click` the button sends")
  attr(:name, :string, required: true, doc: "the value's name, `phx-value-<name>`")
  attr(:value, :any, required: true)
  attr(:on, :boolean, required: true, doc: "whether this is the group's current option")
  slot(:inner_block, required: true)

  # One option of a toggle group: the site's button (the layout's `.backend-btn`), the
  # current option marked `active` for the eye and `aria-pressed` for a screen reader.
  defp toggle(assigns) do
    ~H"""
    <button
      type="button"
      class={"backend-btn" <> if(@on, do: " active", else: "")}
      phx-click={@event}
      {%{"phx-value-#{@name}" => @value}}
      aria-pressed={to_string(@on)}
    >
      {render_slot(@inner_block)}
    </button>
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
      # show: false — the events, and nothing following the pointer; the template is
      # what the keyboard readout says for the cell.
      tooltip: %{fields: [:state, :count], template: "{state} {count}",
                 event: :cell_click, context_event: :flag, show: false}}

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
