defmodule ExamplesWeb.ChartLive do
  use Phoenix.LiveView

  alias Examples.ColorPalettes

  @charts %{
    # Basic Charts
    "bar" => Examples.Charts.BarChart,
    "horizontal_bar" => Examples.Charts.HorizontalBarChart,
    "grouped_bar" => Examples.Charts.GroupedBarChart,
    "stacked_bar" => Examples.Charts.StackedBarChart,
    "line" => Examples.Charts.LineChart,
    "multi_line" => Examples.Charts.MultiLineChart,
    "area" => Examples.Charts.AreaChart,
    "stacked_area" => Examples.Charts.StackedAreaChart,
    "streamgraph" => Examples.Charts.Streamgraph,
    "pie" => Examples.Charts.PieChart,
    "donut" => Examples.Charts.DonutChart,
    "scatter" => Examples.Charts.ScatterPlot,
    "bubble" => Examples.Charts.BubbleChart,
    "radial" => Examples.Charts.RadialBarChart,
    # Hierarchical Layouts
    "treemap" => Examples.Charts.TreemapChart,
    "circle_pack" => Examples.Charts.CirclePacking,
    "sunburst" => Examples.Charts.SunburstChart,
    "tree" => Examples.Charts.TreeLayout,
    "cluster" => Examples.Charts.ClusterDendrogram,
    # Network/Flow Layouts
    "force" => Examples.Charts.ForceGraph,
    "chord" => Examples.Charts.ChordDiagram,
    "sankey" => Examples.Charts.SankeyDiagram,
    # Scientific
    "contour" => Examples.Charts.ContourPlot,
    "heatmap" => Examples.Charts.Heatmap,
    "hexbin" => Examples.Charts.HexbinChart,
    # Maps
    "world_map" => Examples.Charts.WorldMap,
    "globe" => Examples.Charts.Globe
  }

  # Charts that support animation
  @animatable_charts [
    "bar", "horizontal_bar", "line", "area", "pie", "donut",
    "scatter", "radial", "multi_line", "grouped_bar", "stacked_bar",
    "stacked_area", "streamgraph", "bubble", "heatmap", "force", "contour",
    "sankey", "treemap", "circle_pack", "sunburst", "tree", "cluster", "chord",
    "world_map", "globe", "hexbin"
  ]

  @animation_interval 50  # milliseconds between frames (20 fps)

  def mount(%{"chart" => chart_slug}, _session, socket) do
    case Map.get(@charts, chart_slug) do
      nil ->
        {:ok, push_navigate(socket, to: "/")}
      module ->
        palettes = ColorPalettes.list_palettes()
        palette_info = ColorPalettes.palette_info()

        {:ok, assign(socket,
          module: module,
          slug: chart_slug,
          title: module.title(),
          description: module.description(),
          current_palette: :default,
          palettes: palettes,
          palette_info: palette_info,
          animating: false,
          animation_tick: 0,
          animatable: chart_slug in @animatable_charts
        )}
    end
  end

  def handle_event("change_palette", %{"palette" => palette_key}, socket) do
    palette = case palette_key do
      "default" -> :default
      "sunrise" -> :sunrise
      "winter" -> :winter
      "sunset" -> :sunset
      "fall" -> :fall
      "spring" -> :spring
      "summer" -> :summer
      _ -> :default
    end
    {:noreply, assign(socket, current_palette: palette)}
  end

  def handle_event("toggle_animation", _params, socket) do
    if socket.assigns.animating do
      {:noreply, assign(socket, animating: false)}
    else
      schedule_animation()
      {:noreply, assign(socket, animating: true, animation_tick: 0)}
    end
  end

  def handle_info(:animate_tick, socket) do
    if socket.assigns.animating do
      schedule_animation()
      {:noreply, assign(socket, animation_tick: socket.assigns.animation_tick + 1)}
    else
      {:noreply, socket}
    end
  end

  defp schedule_animation do
    Process.send_after(self(), :animate_tick, @animation_interval)
  end

  def render(assigns) do
    ~H"""
    <header>
      <h1>Visualize Examples</h1>
      <p>D3-style data visualizations in Elixir</p>
    </header>
    <main>
      <a href="/" class="back-link">
        <span>&larr;</span> Back to Gallery
      </a>

      <div class="chart-detail">
        <h2><%= @title %></h2>
        <p style="color: #666; margin-bottom: 1rem;"><%= @description %></p>

        <div class="controls-row">
          <div class="palette-selector">
            <span class="palette-label">Color Style:</span>
            <div class="palette-buttons">
              <%= for palette_key <- @palettes do %>
                <% info = @palette_info[palette_key] %>
                <button
                  type="button"
                  phx-click="change_palette"
                  phx-value-palette={Atom.to_string(palette_key)}
                  class={"palette-btn #{if @current_palette == palette_key, do: "active", else: ""}"}
                  title={info.description}
                >
                  <span class="palette-preview">
                    <%= for color <- info.preview do %>
                      <span class="color-dot" style={"background-color: #{color}"}></span>
                    <% end %>
                  </span>
                  <span class="palette-name"><%= info.name %></span>
                </button>
              <% end %>
            </div>
          </div>

          <%= if @animatable do %>
            <div class="animation-control">
              <button
                type="button"
                phx-click="toggle_animation"
                class={"animate-btn #{if @animating, do: "animating", else: ""}"}
              >
                <%= if @animating do %>
                  <span class="pulse-dot"></span>
                  Stop Animation
                <% else %>
                  <span class="play-icon">▶</span>
                  Animate Data
                <% end %>
              </button>
              <%= if @animating do %>
                <span class="tick-counter">Frame: <%= @animation_tick %></span>
              <% end %>
            </div>
          <% end %>
        </div>

        <div class="chart-container" style={"background-color: #{ColorPalettes.background(@current_palette)}"}>
          <%= Phoenix.HTML.raw(render_chart(@module, @current_palette, @animation_tick, @animating)) %>
        </div>

        <h3 style="margin-top: 2rem; margin-bottom: 0.5rem;">Sample Code</h3>
        <pre><code><%= @module.sample_code() %></code></pre>

        <%= if @animatable do %>
          <h3 style="margin-top: 2rem; margin-bottom: 0.5rem;">LiveView Animation Code</h3>
          <pre><code><%= animation_sample_code() %></code></pre>
        <% end %>
      </div>
    </main>

    <style>
      .controls-row {
        display: flex;
        flex-wrap: wrap;
        align-items: flex-start;
        gap: 1.5rem;
        margin-bottom: 1rem;
      }

      .palette-selector {
        display: flex;
        align-items: center;
        flex-wrap: wrap;
        gap: 0.5rem;
      }

      .palette-label {
        font-weight: 600;
        color: #444;
        margin-right: 0.5rem;
      }

      .palette-buttons {
        display: flex;
        flex-wrap: wrap;
        gap: 0.5rem;
      }

      .palette-btn {
        display: flex;
        flex-direction: column;
        align-items: center;
        padding: 0.5rem 0.75rem;
        border: 2px solid #ddd;
        border-radius: 8px;
        background: white;
        cursor: pointer;
        transition: all 0.2s ease;
      }

      .palette-btn:hover {
        border-color: #999;
        transform: translateY(-2px);
        box-shadow: 0 4px 8px rgba(0,0,0,0.1);
      }

      .palette-btn.active {
        border-color: #4e79a7;
        background: #f0f7ff;
        box-shadow: 0 0 0 2px rgba(78, 121, 167, 0.2);
      }

      .palette-preview {
        display: flex;
        gap: 2px;
        margin-bottom: 4px;
      }

      .color-dot {
        width: 12px;
        height: 12px;
        border-radius: 2px;
        border: 1px solid rgba(0,0,0,0.1);
      }

      .palette-name {
        font-size: 11px;
        color: #666;
        font-weight: 500;
      }

      .palette-btn.active .palette-name {
        color: #4e79a7;
        font-weight: 600;
      }

      .animation-control {
        display: flex;
        align-items: center;
        gap: 1rem;
      }

      .animate-btn {
        display: flex;
        align-items: center;
        gap: 0.5rem;
        padding: 0.6rem 1.2rem;
        border: 2px solid #10b981;
        border-radius: 8px;
        background: white;
        color: #10b981;
        font-weight: 600;
        font-size: 14px;
        cursor: pointer;
        transition: all 0.2s ease;
      }

      .animate-btn:hover {
        background: #10b981;
        color: white;
        transform: translateY(-2px);
        box-shadow: 0 4px 12px rgba(16, 185, 129, 0.3);
      }

      .animate-btn.animating {
        background: #ef4444;
        border-color: #ef4444;
        color: white;
      }

      .animate-btn.animating:hover {
        background: #dc2626;
        border-color: #dc2626;
      }

      .play-icon {
        font-size: 12px;
      }

      .pulse-dot {
        width: 10px;
        height: 10px;
        background: white;
        border-radius: 50%;
        animation: pulse 1s ease-in-out infinite;
      }

      @keyframes pulse {
        0%, 100% { opacity: 1; transform: scale(1); }
        50% { opacity: 0.5; transform: scale(0.8); }
      }

      .tick-counter {
        font-size: 12px;
        color: #666;
        font-family: monospace;
        background: #f3f4f6;
        padding: 0.3rem 0.6rem;
        border-radius: 4px;
      }
    </style>
    """
  end

  defp render_chart(module, palette, tick, animating) do
    opts = [width: 700, height: 450, palette: palette]

    opts = if animating do
      Keyword.put(opts, :animation_tick, tick)
    else
      opts
    end

    module.render(opts)
    |> Visualize.SVG.Renderer.render_to_string()
  end

  defp animation_sample_code do
    ~S"""
    # LiveView Animation Example
    # The chart re-renders on each tick with new data

    def handle_info(:animate_tick, socket) do
      if socket.assigns.animating do
        Process.send_after(self(), :animate_tick, 150)
        {:noreply, assign(socket, tick: socket.assigns.tick + 1)}
      else
        {:noreply, socket}
      end
    end

    # In render/1:
    <%= Phoenix.HTML.raw(
      MyChart.render(animation_tick: @tick)
    ) %>

    # In chart module - use tick to vary data:
    def render(opts) do
      tick = opts[:animation_tick] || 0
      data = generate_animated_data(tick)
      # ... render with data
    end

    defp generate_animated_data(tick) do
      # Use sine waves for smooth animation
      Enum.map(base_data, fn item ->
        variation = :math.sin(tick * 0.1 + item.index) * 20
        %{item | value: item.base_value + variation}
      end)
    end
    """
  end
end
