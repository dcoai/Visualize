defmodule ExamplesWeb.InteractionLive do
  @moduledoc """
  The client-side interaction page (#56): one chart drawn by the declarative layer, with
  `TooltipHook` reading the datum attributes its marks carry (spec/10 §12) and
  `CrosshairHook` snapping to the arrays `Visualize.Hooks.Crosshair.attrs/3` wrote once
  (spec/10 §13) — over the SVG and over the same chart on a binary canvas.
  """
  use Phoenix.LiveView

  alias Visualize.Chart
  alias Visualize.Chart.Frame
  alias Visualize.Hooks.Crosshair
  alias Visualize.IR.Element
  alias Visualize.{Render, Theme}

  @width 720
  @height 380

  @series ~w(alpha beta gamma)

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
    version: 1,
    sources: %{primary: %{fields: [:hour, :series, :value]}},
    frame: %{
      kind: :cartesian,
      size: %{width: @width, height: @height},
      margin: %{top: 30, right: 120, bottom: 40, left: 50},
      scales: %{
        x: %{kind: :linear, domain: [0, 23]},
        y: %{kind: :linear, domain: [0, :auto], nice: true},
        color: %{kind: :ordinal}
      },
      axes: [
        %{scale: :x, side: :bottom, ticks: 12, grid: true},
        %{scale: :y, side: :left, ticks: 5, grid: true}
      ],
      legend: %{scale: :color, position: :top_right, title: ["series"]}
    },
    marks: [
      %{
        type: :line,
        data: :primary,
        channels: %{x: :hour, y: :value, series: :series},
        style: :smooth,
        tooltip: %{fields: [:series], template: "series {series}"}
      },
      %{
        type: :circle,
        data: :primary,
        channels: %{x: :hour, y: :value},
        options: %{radius: 4},
        style: :dots,
        tooltip: %{
          fields: [:series, :hour, :value],
          template: "{series} at {hour}:00\nvalue {value}",
          event: :point_click
        }
      }
    ],
    styles: %{
      smooth: %{curve: :monotone_x, stroke_width: 2},
      dots: %{fill: {:field, :series}}
    },
    labels: [%{anchor: :title, text: ["Hover a point; click one to send it to the LiveView"]}]
  }

  def mount(_params, _session, socket) do
    {:ok, socket |> assign(build()) |> assign(picked: nil, hovered: nil)}
  end

  def handle_event("point_click", %{"series" => series, "hour" => hour, "value" => value}, socket) do
    {:noreply, assign(socket, picked: {series, hour, value})}
  end

  def handle_event("hover", %{"index" => index}, socket) do
    {:noreply, assign(socket, hovered: index)}
  end

  # The chart once: its SVG, the same frame on a binary canvas with literal paints, and
  # the crosshair's arrays for the line mark (the first).
  defp build do
    chart = Chart.from_map!(@design)
    {:ok, applied} = Chart.apply(chart, sources: %{primary: rows()})
    svg_group = Frame.generate(applied.frame, sources: applied.sources)
    canvas_group = Frame.generate(applied.frame, sources: applied.sources, resolve: :literal)

    colours =
      Enum.map_join(1..length(@series), ",", fn i ->
        ~s|"#{Theme.resolve(Theme.default(), {:series, i}, :literal)}"|
      end)

    %{
      svg: root(svg_group) |> Render.to_string(),
      binary: root(canvas_group) |> Render.to_string(backend: :canvas, format: :binary_base64),
      crosshair: Crosshair.attrs(applied.frame, applied.sources),
      colors: "[" <> colours <> "]",
      width: @width,
      height: @height
    }
  end

  defp root(group) do
    Element.root(@width, @height, children: [group], title: "Three series over a day")
  end

  def render(assigns) do
    ~H"""
    <header>
      <h1>Visualize Examples</h1>
      <p>Client-side interaction: tooltip and crosshair with no round trip</p>
    </header>
    <main>
      <a href="/" class="back-link"><span>&larr;</span> Back to Gallery</a>

      <div class="chart-detail">
        <h2>Tooltip</h2>
        <p style="color: #666; margin-bottom: 1rem;">
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

        <h2 style="margin-top: 2.5rem;">Crosshair over the SVG</h2>
        <p style="color: #666; margin-bottom: 1rem;">
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

        <h2 style="margin-top: 2.5rem;">Crosshair over the canvas</h2>
        <p style="color: #666; margin-bottom: 1rem;">
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

        <h3 style="margin-top: 2rem; margin-bottom: 0.5rem;">The design and the markup</h3>
        <pre><code><%= design_code() %></code></pre>
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
    </style>
    """
  end

  defp design_code do
    """
    marks: [
      %{type: :line, channels: %{x: :hour, y: :value, series: :series},
        tooltip: %{fields: [:series], template: "series {series}"}},
      %{type: :circle, channels: %{x: :hour, y: :value}, style: :dots,
        tooltip: %{fields: [:series, :hour, :value],
                   template: "{series} at {hour}:00\\nvalue {value}",
                   event: :point_click}}
    ]

    # The tooltip reads the attributes the mark wrote; nothing is fetched on hover.
    <div id="chart" phx-hook="TooltipHook">{raw(svg)}</div>

    # The crosshair reads the arrays attrs/3 wrote once, over SVG or canvas alike.
    crosshair = Visualize.Hooks.Crosshair.attrs(applied.frame, applied.sources)
    <div id="chart" phx-hook="CrosshairHook" {crosshair} data-crosshair-event="hover">
      {raw(svg)}
    </div>
    """
  end
end
