defmodule ExamplesWeb.InteractionLive do
  @moduledoc """
  The client-side interaction page (#56): one chart drawn by the declarative layer, with
  `TooltipHook` reading the datum attributes its marks carry (spec/10 §12) and
  `CrosshairHook` snapping to the arrays `Visualize.Hooks.Crosshair.attrs/3` wrote once
  (spec/10 §13) — over the SVG and over the same chart on a binary canvas — and
  `LegendHook` hiding a series from its legend entry (spec/10 §14).

  Each demo is one `ExamplesWeb.Panel` — its heading, its explanation and its chart
  together — and the chart's legend sits in the frame's right margin, beside the plot
  rather than over a series (#505).
  """
  use Phoenix.LiveView

  alias ExamplesWeb.{Highlight, Panel}
  alias Visualize.Chart
  alias Visualize.Hooks.Crosshair
  alias Visualize.Theme

  # The page's one size. The design records none (#427): `build/1` realises the frame at
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
    frames: %{main: %{
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
    }},
    marks: [
      %{
        type: :line,
        data: :primary,
        channels: %{x: :hour, y: :value, series: :series},
        style: :smooth,
        tooltip: %{fields: [:series], template: "series {series}"}
      },
      # The points name their series as the line does (#508), so a legend toggle hides
      # both, and they take the line's colour without a style of their own.
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

  def mount(_params, _session, socket) do
    {:ok, socket |> assign(build(@size)) |> assign(picked: nil, hovered: nil, hidden: %{})}
  end

  def handle_event("point_click", %{"series" => series, "hour" => hour, "value" => value}, socket) do
    {:noreply, assign(socket, picked: {series, hour, value})}
  end

  def handle_event("hover", %{"index" => index}, socket) do
    {:noreply, assign(socket, hovered: index)}
  end

  def handle_event("legend_toggle", %{"series" => series, "hidden" => hidden?}, socket) do
    {:noreply, update(socket, :hidden, &Map.put(&1, series, hidden?))}
  end

  @doc """
  The chart once, realised at `size` (`{width, height}`): its SVG, the same frame on a
  binary canvas with literal paints, and the crosshair's arrays for the line mark (the
  first). Every size the page shows — the SVG's `viewBox`, the canvas's `data-width` and
  `data-height`, the arrays' `data-size` — is the realised frame's, so the crosshair's
  marks sit on the drawn series (#507).
  """
  @spec build({pos_integer(), pos_integer()}) :: map()
  def build(size) do
    chart = Chart.from_map!(@design)
    {:ok, applied} = Chart.apply(chart, sources: %{primary: rows()}, size: size)
    %{width: width, height: height} = applied.frame.size

    colours =
      Enum.map_join(1..length(@series), ",", fn i ->
        ~s|"#{Theme.resolve(Theme.default(), {:series, i}, :literal)}"|
      end)

    %{
      svg: Chart.render(applied, root: true, title: @title),
      binary: Chart.render(applied, root: true, title: @title, backend: :canvas, format: :binary_base64),
      crosshair: Crosshair.attrs(applied.frame, applied.sources),
      colors: "[" <> colours <> "]",
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
        Also under this tab: the <a href="/dashboard">Synced dashboard</a> — one crosshair and one brush across three panels.
      </p>

      <div class="panels panels-row" style={panel_width()}>
        <Panel.panel id="panel-tooltip">
          <:title>Tooltip</:title>
          <p class="panel-note">
            Every point carries its datum as <code>data-datum-*</code> attributes, written by
            the mark's <code>tooltip</code> node; <code>TooltipHook</code> formats them with
            the mark's template. Clicking a point pushes <code>point_click</code>.
          </p>

          <div class="chart-container">
            <div id="tooltip-chart" phx-hook="TooltipHook" data-tooltip-class="vis-tooltip">
              <%= Phoenix.HTML.raw(@svg) %>
            </div>
          </div>

          <p :if={@picked} class="picked">
            <% {series, hour, value} = @picked %>
            Clicked: <strong><%= series %></strong> at <%= hour %>:00, value <%= value %>
          </p>
          <p :if={!@picked} class="picked">No point clicked yet.</p>
        </Panel.panel>

        <Panel.panel id="panel-crosshair-svg">
          <:title>Crosshair over the SVG</:title>
          <p class="panel-note">
            <code>Visualize.Hooks.Crosshair.attrs/3</code> wrote the line mark's x pixels and
            each series' y pixels once, as <code>data-xs</code> and <code>data-ys</code>;
            <code>CrosshairHook</code> snaps to the nearest x by binary search and pushes
            <code>hover</code> with the index when it changes.
          </p>

          <div class="chart-container">
            <div
              id="crosshair-svg"
              phx-hook="CrosshairHook"
              {@crosshair}
              data-crosshair-event="hover"
              data-crosshair-colors={@colors}
            >
              <%= Phoenix.HTML.raw(@svg) %>
            </div>
          </div>

          <p :if={@hovered} class="picked">Hovered index: <strong><%= @hovered %></strong></p>
          <p :if={!@hovered} class="picked">Move over the plot to see the hovered index.</p>
        </Panel.panel>

        <Panel.panel id="panel-crosshair-canvas">
          <:title>Crosshair over the canvas</:title>
          <p class="panel-note">
            The same chart through the binary canvas backend: no element per datum exists,
            and the crosshair reads the same arrays, so nothing changes for the hook.
          </p>

          <div class="chart-container">
            <div id="crosshair-canvas" phx-hook="CrosshairHook" {@crosshair} data-crosshair-colors={@colors}>
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
            points, carry the same <code>data-series</code>: both marks have the
            <code>series</code> channel. <code>LegendHook</code> hides a series with
            <code>display="none"</code> when its
            entry is clicked and pushes <code>legend_toggle</code>. The hidden set survives a
            patch: the LiveView re-renders on every event and the series stays hidden.
          </p>

          <div class="chart-container">
            <div id="legend-chart" phx-hook="LegendHook" data-legend-event="legend_toggle">
              <%= Phoenix.HTML.raw(@svg) %>
            </div>
          </div>

          <p class="picked">
            Hidden on the server's record:
            <strong><%= @hidden |> Enum.filter(fn {_, h} -> h end) |> Enum.map(&elem(&1, 0)) |> Enum.join(", ") %></strong>
            <%= if Enum.all?(@hidden, fn {_, h} -> not h end), do: "none" %>
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

    # The tooltip reads the attributes the mark wrote; nothing is fetched on hover.
    ~H"""
    <div id="chart" phx-hook="TooltipHook">{raw(svg)}</div>
    """

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
