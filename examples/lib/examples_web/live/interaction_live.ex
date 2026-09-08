defmodule ExamplesWeb.InteractionLive do
  @moduledoc """
  The client-side interaction page (#56): a chart drawn by the declarative layer whose
  marks carry the datum attributes of spec/10 §12, with `TooltipHook` attached — a
  tooltip with no round trip, and a click that reaches the LiveView.
  """
  use Phoenix.LiveView

  alias Visualize.Chart
  alias Visualize.IR.Element
  alias Visualize.Render

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
    {:ok, assign(socket, svg: render_chart(), picked: nil)}
  end

  def handle_event("point_click", %{"series" => series, "hour" => hour, "value" => value}, socket) do
    {:noreply, assign(socket, picked: {series, hour, value})}
  end

  defp render_chart do
    chart = Chart.from_map!(@design)
    {:ok, applied} = Chart.apply(chart, sources: %{primary: rows()})
    group = Visualize.Chart.Frame.generate(applied.frame, sources: applied.sources)

    @width
    |> Element.root(@height, children: [group], title: "Three series over a day")
    |> Render.to_string()
  end

  def render(assigns) do
    ~H"""
    <header>
      <h1>Visualize Examples</h1>
      <p>Client-side interaction: tooltip from data attributes, no round trip</p>
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
          <div id="interaction-chart" phx-hook="TooltipHook" data-tooltip-class="vis-tooltip">
            <%= Phoenix.HTML.raw(@svg) %>
          </div>
        </div>

        <p :if={@picked} class="picked">
          <% {series, hour, value} = @picked %>
          Clicked: <strong><%= series %></strong> at <%= hour %>:00, value <%= value %>
        </p>
        <p :if={!@picked} class="picked">No point clicked yet.</p>

        <h3 style="margin-top: 2rem; margin-bottom: 0.5rem;">The design</h3>
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
      .picked { margin-top: 1rem; color: #444; }
      #interaction-chart .mark-circle circle { cursor: pointer; }
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

    # The hook reads the attributes the mark wrote; nothing is fetched on hover.
    <div id="chart" phx-hook="TooltipHook">{raw(svg)}</div>
    """
  end
end
