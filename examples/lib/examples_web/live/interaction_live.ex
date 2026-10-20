defmodule ExamplesWeb.InteractionLive do
  @moduledoc """
  The client-side interaction page (#56): one chart drawn by the declarative layer, with
  `TooltipHook` reading the datum attributes its marks carry (spec/10 §12) and
  `CrosshairHook` snapping to the arrays `Visualize.Hooks.Crosshair.attrs/3` wrote once
  (spec/10 §13) — over the SVG and over the same chart on a binary canvas — and
  `LegendHook` hiding a series from its legend entry (spec/10 §14). The tooltip's chart is
  drawn through `Visualize.Components.Chart`, so a click on a point reaches this page as
  one `Visualize.Event` with the point's row, typed (spec/10 §19, D-170).

  Each demo is one `ExamplesWeb.Panel` — its heading, its explanation and its chart
  together — and the chart's legend sits in the frame's right margin, beside the plot
  rather than over a series (#505).

  The Minesweeper panel (#800) plays the game of `/minesweeper` in place: the same design
  (`ExamplesWeb.MinesweeperLive.applied/2`), the game in this page's process, and each
  click made the next game by the step that page takes (`Examples.Minesweeper.Move`).
  """
  use Phoenix.LiveView

  alias Examples.Minesweeper
  alias Examples.Minesweeper.Move
  alias ExamplesWeb.{AnimationsDemo, Highlight, MinesweeperLive, MotionDemo, Panel}
  alias Visualize.Chart
  alias Visualize.Event
  alias Visualize.Hooks.Crosshair
  alias Visualize.Theme

  # The page's one size. The design records none (#427): `build/1` realizes the frame at
  # it, and the canvas and the crosshair's arrays read it back from that frame (#507).
  @size {720, 380}

  @series ~w(alpha beta gamma)
  @title "Three series over a day"

  defp rows do
    for i <- 0..23, s <- @series do
      %{
        hour: i,
        series: s,
        value: Float.round(50 + 30 * :math.sin(i / 3 + phase(s)) + 8 * phase(s), 1)
      }
    end
  end

  defp phase("alpha"), do: 0.0
  defp phase("beta"), do: 1.2
  defp phase("gamma"), do: 2.4

  @design %{
    version: 2,
    sources: %{primary: %{fields: [:hour, :series, :value]}},
    frames: %{
      main: %{
        kind: :cartesian,
        # The right margin holds the legend (#505): `inside: false` puts it there, beside the
        # plot and never over a series; its estimated width is 67 of the 96.
        margin: %{top: 30, right: 96, bottom: 40, left: 50},
        scales: %{
          x: %{kind: :linear, domain: [0, 23]},
          y: %{kind: :linear, domain: [0, :auto], nice: true},
          color: %{kind: :ordinal}
        },
        axes: [
          %{scale: :x, side: :bottom, ticks: 12, grid: true},
          %{scale: :y, side: :left, ticks: 5, grid: true}
        ],
        legend: %{scale: :color, position: :top_right, inside: false, title: ["series"]}
      }
    },
    marks: [
      %{
        type: :line,
        data: :primary,
        channels: %{x: :hour, y: :value, series: :series},
        style: :smooth,
        tooltip: %{fields: [:series], template: "series {series}"}
      },
      # The points name their series as the line does (#508), so a legend toggle hides
      # both, and they take the line's color without a style of their own.
      %{
        type: :circle,
        data: :primary,
        channels: %{x: :hour, y: :value, series: :series},
        options: %{radius: 4},
        tooltip: %{
          fields: [:series, :hour, :value],
          template: "{series} at {hour}:00\nvalue {value}",
          event: :point_click
        }
      }
    ],
    styles: %{smooth: %{curve: :monotone_x, stroke_width: 2}},
    labels: [%{anchor: :title, text: ["Hover a point; click one to send it to the LiveView"]}]
  }

  # The page at its one size; a session may name another, as its tests draw it at two (#507),
  # and a seed for the Minesweeper panel's first game, as its tests play a known layout.
  def mount(_params, session, socket) do
    size = Map.get(session, "size", @size)

    {:ok,
     socket
     |> assign(build(size))
     |> assign(picked: nil, hovered: nil, hidden: %{}, size: size)
     |> assign(animations_chart: AnimationsDemo.applied(size), animations_run: 0)
     |> motion(MotionDemo.rows(), 0)
     |> mines(mines_game(session))}
  end

  defp mines_game(%{"mines_seed" => seed}) when is_integer(seed), do: Minesweeper.new(seed: seed)
  defp mines_game(_session), do: Minesweeper.new()

  # The Minesweeper panel's game and its grid, drawn square at the page's chart height:
  # the panel's chart size (#513), its cells kept square.
  defp mines(socket, game) do
    {_width, height} = socket.assigns.size
    assign(socket, mines_game: game, mines_chart: MinesweeperLive.applied(game, {height, height}))
  end

  # The motion demo's rows, the next service whose state changes, and its chart (#653).
  defp motion(socket, rows, turn) do
    assign(socket,
      motion_rows: rows,
      motion_turn: turn,
      motion_chart: MotionDemo.applied(rows, socket.assigns.size)
    )
  end

  # A click on a point, resolved by the chart's component to the row drawn (D-170).
  def handle_info(
        {:visualize_event, "tooltip-chart", %Event{event: "point_click", row: row}},
        socket
      ) do
    {:noreply, assign(socket, picked: {row.series, row.hour, row.value})}
  end

  # A click on a bar deletes its row, which leaves by exploding (spec/14 §3.12).
  def handle_info({:visualize_event, "motion-chart", %Event{event: "delete", row: row}}, socket) do
    rows = MotionDemo.delete(socket.assigns.motion_rows, row.name)
    {:noreply, motion(socket, rows, socket.assigns.motion_turn)}
  end

  # A click, Enter, a right-click, a long-press or the Menu key on a Minesweeper cell: the
  # next game, by the step `/minesweeper` takes. The panel has no Flag mode; Shift flags.
  def handle_info({:visualize_event, "mines-panel-chart", %Event{} = event}, socket) do
    {:noreply, mines(socket, Move.play(socket.assigns.mines_game, event, :reveal))}
  end

  def handle_event("mines_new", _params, socket),
    do: {:noreply, mines(socket, Minesweeper.new())}

  def handle_event("motion_next", _params, socket) do
    %{motion_rows: rows, motion_turn: turn} = socket.assigns
    {:noreply, motion(socket, MotionDemo.next_state(rows, turn), turn + 1)}
  end

  def handle_event("motion_reset", _params, socket) do
    {:noreply, motion(socket, MotionDemo.rows(), 0)}
  end

  # A new id remounts the chart, so the browser inserts its elements again and the
  # animations that ran out start over.
  def handle_event("animations_replay", _params, socket),
    do: {:noreply, update(socket, :animations_run, &(&1 + 1))}

  def handle_event("hover", %{"index" => index}, socket) do
    {:noreply, assign(socket, hovered: index)}
  end

  def handle_event("legend_toggle", %{"series" => series, "hidden" => hidden?}, socket) do
    {:noreply, update(socket, :hidden, &Map.put(&1, series, hidden?))}
  end

  @doc """
  The chart once, realized at `size` (`{width, height}`): the applied chart, which
  `Visualize.Components.Chart` draws and resolves a click against, its SVG, the same frame on a
  binary canvas with literal paints, and the crosshair's arrays for the line mark (the
  first). Every size the page shows — the SVG's `viewBox`, the canvas's `data-width` and
  `data-height`, the arrays' `data-size` — is the realized frame's, so the crosshair's
  marks sit on the drawn series (#507).
  """
  @spec build({pos_integer(), pos_integer()}) :: map()
  def build(size) do
    chart = Chart.from_map!(@design)
    {:ok, applied} = Chart.apply(chart, sources: %{primary: rows()}, size: size)
    %{width: width, height: height} = applied.frame.size

    colors =
      Enum.map_join(1..length(@series), ",", fn i ->
        ~s|"#{Theme.resolve(Theme.default(), {:series, i}, :literal)}"|
      end)

    %{
      applied: applied,
      title: @title,
      svg: Chart.render(applied, root: true, title: @title),
      binary:
        Chart.render(applied, root: true, title: @title, backend: :canvas, format: :binary_base64),
      crosshair: Crosshair.attrs(applied.frame, applied.sources),
      colors: "[" <> colors <> "]",
      width: width,
      height: height
    }
  end

  # A demo panel is as wide as its chart (#513): the page's one chart size, handed to the
  # stylesheet as `--chart-w`, so wide screens show several demos per row.
  @doc false
  def panel_width, do: "--chart-w: #{elem(@size, 0)}px"

  def render(assigns) do
    ~H"""
    <ExamplesWeb.SiteHeader.header tab={:interaction} />
    <main class="main-wide">
      <a href="/" class="back-link"><span>&larr;</span> Back to Gallery</a>

      <p class="tab-pages">
        Also under this tab: the <a href="/dashboard">Synced dashboard</a>
        — one crosshair and one brush across three panels — a <a href="/board">Live board</a>, eight cells over live feeds, each its own process, whose services drill down to a <a href="/board/detail">detail board</a>, a <a href="/tenants">Tenant chat</a>, a board whose messages are styled by the host's generators, and <a href="/minesweeper">Minesweeper</a>, a clickable grid drawn by a design, the game in the host.
      </p>

      <div class="panels panels-row" style={panel_width()}>
        <Panel.panel id="panel-tooltip">
          <:title>Tooltip</:title>
          <p class="panel-note">
            Every point carries its datum as <code>data-datum-*</code>
            attributes, written by
            the mark's <code>tooltip</code>
            node; <code>TooltipHook</code>
            formats them with
            the mark's template. The chart is a <code>Visualize.Components.Chart</code>:
            clicking a point sends this page <code>point_click</code>
            as a <code>Visualize.Event</code>, with the point's row as the chart drew it.
          </p>

          <div class="chart-container">
            <.live_component
              module={Visualize.Components.Chart}
              id="tooltip-chart"
              chart={@applied}
              render={[title: @title]}
            />
          </div>

          <p :if={@picked} class="picked">
            <% {series, hour, value} = @picked %> Clicked: <strong>{series}</strong>
            at {hour}:00, value {value}
          </p>
          <p :if={!@picked} class="picked">No point clicked yet.</p>
        </Panel.panel>

        <Panel.panel id="panel-crosshair-svg">
          <:title>Crosshair over the SVG</:title>
          <p class="panel-note">
            <code>Visualize.Hooks.Crosshair.attrs/3</code>
            wrote the line mark's x pixels and
            each series' y pixels once, as <code>data-xs</code>
            and <code>data-ys</code>; <code>CrosshairHook</code>
            snaps to the nearest x by binary search and pushes <code>hover</code>
            with the index when it changes.
          </p>

          <div class="chart-container">
            <div
              id="crosshair-svg"
              phx-hook="CrosshairHook"
              {@crosshair}
              data-crosshair-event="hover"
              data-crosshair-colors={@colors}
            >
              {Phoenix.HTML.raw(@svg)}
            </div>
          </div>

          <p :if={@hovered} class="picked">Hovered index: <strong>{@hovered}</strong></p>
          <p :if={!@hovered} class="picked">Move over the plot to see the hovered index.</p>
        </Panel.panel>

        <Panel.panel id="panel-crosshair-canvas">
          <:title>Crosshair over the canvas</:title>
          <p class="panel-note">
            The same chart through the binary canvas backend: no element per datum exists,
            and the crosshair reads the same arrays, so nothing changes for the hook.
          </p>

          <div class="chart-container">
            <div
              id="crosshair-canvas"
              phx-hook="CrosshairHook"
              {@crosshair}
              data-crosshair-colors={@colors}
            >
              <div
                id="crosshair-canvas-chart"
                phx-hook="CanvasBinaryChart"
                phx-update="ignore"
                data-binary={@binary}
                data-width={@width}
                data-height={@height}
              >
                <canvas width={@width} height={@height}></canvas>
              </div>
            </div>
          </div>
        </Panel.panel>

        <Panel.panel id="panel-legend">
          <:title>Legend toggling</:title>
          <p class="panel-note">
            Every legend entry and every element a series draws, its line and each of its
            points, carry the same <code>data-series</code>: both marks have the <code>series</code>
            channel. <code>LegendHook</code>
            hides a series with <code>display="none"</code>
            when its
            entry is clicked and pushes <code>legend_toggle</code>. The hidden set survives a
            patch: the LiveView re-renders on every event and the series stays hidden.
          </p>

          <div class="chart-container">
            <div id="legend-chart" phx-hook="LegendHook" data-legend-event="legend_toggle">
              {Phoenix.HTML.raw(@svg)}
            </div>
          </div>

          <p class="picked">
            Hidden on the server's record:
            <strong>{@hidden
            |> Enum.filter(fn {_, h} -> h end)
            |> Enum.map(&elem(&1, 0))
            |> Enum.join(", ")}</strong>
            {if Enum.all?(@hidden, fn {_, h} -> not h end), do: "none"}
          </p>
        </Panel.panel>

        <Panel.panel id="panel-motion">
          <:title>Motion by identity</:title>
          <p class="panel-note">
            Each bar's <code>state</code>
            names its style. <em>Next state</em>
            moves one service on: its bar fades to the new color (<code>transition</code>),
            and a service in error pulses while it is (<code>animation</code>). A click on a bar
            deletes its row; <code>MotionHook</code>
            keeps a copy of it and explodes it over the chart
            (<code>exit: :explode</code>). A reader who asks for less motion sees each change at once.
          </p>

          <div class="chart-container">
            <.live_component
              module={Visualize.Components.Chart}
              id="motion-chart"
              chart={@motion_chart}
            />
          </div>

          <p class="picked">
            <button phx-click="motion_next">Next state</button>
            <button phx-click="motion_reset">Reset</button>
            {length(@motion_rows)} services drawn.
          </p>
        </Panel.panel>

        <Panel.panel id="panel-animations">
          <:title>Animations</:title>
          <p class="panel-note">
            A style's <code>animation</code>
            runs while the style holds: each tile's row names
            its style, and each style one of the built-ins — <code>:pulse</code>, <code>:blink</code>, <code>:shake</code>,
            <code>:spin</code>
            — with its own <code>duration</code>, <code>easing</code>, <code>iterations</code>
            and <code>delay</code>, or a string, <code>"wiggle"</code>, naming keyframes this
            page's stylesheet defines. The canvas hooks run the same keyframes, and a host
            registers its own with <code>VisualizeMotion.register/2</code>.
            <strong>A reader who asks for less motion</strong>
            (<code>prefers-reduced-motion: reduce</code>) sees every tile still: the chart's
            own stylesheet turns every animation off, and a design cannot override it.
          </p>

          <div class="chart-container">
            <.live_component
              module={Visualize.Components.Chart}
              id={"animations-chart-#{@animations_run}"}
              chart={@animations_chart}
            />
          </div>

          <p class="picked">
            <button phx-click="animations_replay">Replay</button>
            The blink and the shake run a few times and stop; <em>Replay</em>
            starts them again.
          </p>
          <Highlight.code code={AnimationsDemo.code()} />
        </Panel.panel>

        <Panel.panel id="panel-minesweeper">
          <:title>Minesweeper</:title>
          <p class="panel-note">
            The grid is a design: a <code>:rect</code>
            per cell on two <code>:band</code>
            scales, each cell's <code>state</code>
            naming its style, and the game is this page's. A click reveals and sends <code>cell_click</code>; a right-click, a long-press or the Menu key sends the mark's <code>context_event</code>, <code>flag</code>, as does a click with Shift held.
            <code>KeyboardHook</code>
            moves on the band × band grid by row and column, and Enter reveals. On a canvas
            the same click resolves through the hit index to the same <code>Visualize.Event</code>.
          </p>

          <MinesweeperLive.status game={@mines_game} />

          <div class="chart-container mines-board">
            <.live_component
              module={Visualize.Components.Chart}
              id="mines-panel-chart"
              chart={@mines_chart}
            />
          </div>

          <p class="picked">
            <button phx-click="mines_new">New game</button>
            <a href="/minesweeper">The full page</a>, with a Flag mode, a clock and every backend.
          </p>
        </Panel.panel>

        <Panel.panel id="panel-code" class="panel-wide">
          <:title>The design and the markup</:title>
          <p class="panel-note">
            The marks every demo above draws, and the markup each hook reads: the legend sits
            in the frame's right margin (<code>inside: false</code>), beside the plot.
          </p>
          <Highlight.code code={design_code()} />
        </Panel.panel>
      </div>
    </main>

    <style>
      .vis-tooltip {
        background: rgba(30, 30, 30, 0.92);
        color: #fff;
        font: 12px/1.4 -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
        padding: 6px 8px;
        border-radius: 4px;
        z-index: 10;
      }
      .crosshair-rule { stroke-dasharray: 3 3; }
      .picked { margin-top: 1rem; color: #444; }
      #tooltip-chart .mark-circle circle { cursor: pointer; }
      #motion-chart .mark-rect rect { cursor: pointer; }
      <%= Phoenix.HTML.raw(AnimationsDemo.keyframes()) %>
      <%= Phoenix.HTML.raw(MinesweeperLive.board_css()) %>
      #crosshair-svg, #crosshair-canvas { display: inline-block; }
      #crosshair-canvas canvas { max-width: 100%; height: auto; }
    </style>
    """
  end

  # Elixir a reader can paste: each template sits in its ~H sigil, highlighted as HEEx.
  defp design_code do
    ~S'''
    # The legend in the frame's right margin, beside the plot (spec/14 §4.5).
    legend: %{scale: :color, position: :top_right, inside: false, title: ["series"]}

    marks: [
      %{type: :line, channels: %{x: :hour, y: :value, series: :series},
        tooltip: %{fields: [:series], template: "series {series}"}},
      %{type: :circle, channels: %{x: :hour, y: :value, series: :series},
        tooltip: %{fields: [:series, :hour, :value],
                   template: "{series} at {hour}:00\nvalue {value}",
                   event: :point_click}}
    ]

    # The tooltip reads the attributes the mark wrote; nothing is fetched on hover. A click
    # reaches the page as one Visualize.Event, its row resolved on the server.
    ~H"""
    <.live_component module={Visualize.Components.Chart} id="chart" chart={applied} />
    """

    def handle_info({:visualize_event, "chart", %Visualize.Event{event: "point_click", row: row}}, socket) do
      {:noreply, assign(socket, picked: row)}
    end

    # The legend's entries and every element of a series share data-series; the hook joins them.
    ~H"""
    <div id="chart" phx-hook="LegendHook" data-legend-event="legend_toggle">{raw(svg)}</div>
    """

    # The crosshair reads the arrays attrs/3 wrote once, over SVG or canvas alike.
    crosshair = Visualize.Hooks.Crosshair.attrs(applied.frame, applied.sources)

    ~H"""
    <div id="chart" phx-hook="CrosshairHook" {crosshair} data-crosshair-event="hover">
      {raw(svg)}
    </div>
    """
    '''
  end
end
