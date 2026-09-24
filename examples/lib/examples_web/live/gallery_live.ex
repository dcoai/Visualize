defmodule ExamplesWeb.GalleryLive do
  use Phoenix.LiveView

  @charts [
    # Basic Charts
    {Examples.Charts.BarChart, "bar"},
    {Examples.Charts.HorizontalBarChart, "horizontal_bar"},
    {Examples.Charts.GroupedBarChart, "grouped_bar"},
    {Examples.Charts.StackedBarChart, "stacked_bar"},
    {Examples.Charts.LineChart, "line"},
    {Examples.Charts.MultiLineChart, "multi_line"},
    {Examples.Charts.AreaChart, "area"},
    {Examples.Charts.StackedAreaChart, "stacked_area"},
    {Examples.Charts.Streamgraph, "streamgraph"},
    {Examples.Charts.RidgelinePlot, "ridgeline"},
    {Examples.Charts.PieChart, "pie"},
    {Examples.Charts.DonutChart, "donut"},
    {Examples.Charts.ScatterPlot, "scatter"},
    {Examples.Charts.BubbleChart, "bubble"},
    {Examples.Charts.RadialBarChart, "radial"},
    {Examples.Charts.GaugeChart, "gauge"},
    {Examples.Charts.RadarChart, "radar"},
    {Examples.Charts.PolarTransformChart, "polar"},
    # Hierarchical Layouts
    {Examples.Charts.TreemapChart, "treemap"},
    {Examples.Charts.CirclePacking, "circle_pack"},
    {Examples.Charts.SunburstChart, "sunburst"},
    {Examples.Charts.TreeLayout, "tree"},
    {Examples.Charts.ClusterDendrogram, "cluster"},
    # Network/Flow Layouts
    {Examples.Charts.ForceGraph, "force"},
    {Examples.Charts.ChordDiagram, "chord"},
    {Examples.Charts.SankeyDiagram, "sankey"},
    # Scientific
    {Examples.Charts.ContourPlot, "contour"},
    {Examples.Charts.Heatmap, "heatmap"},
    {Examples.Charts.HexbinChart, "hexbin"},
    {Examples.Charts.SpectrumChart, "spectrum"},
    # Maps
    {Examples.Charts.WorldMap, "world_map"},
    {Examples.Charts.Globe, "globe"},
    # A machine's load, two ways (#415), and one source in two frames (#429)
    {Examples.Charts.LoadGauge, "load_gauge"},
    {Examples.Charts.LoadAge, "load_age"},
    {Examples.Charts.LoadChart, "load"},
    # One source at four time scales, four frames across the box (#429)
    {Examples.Charts.ContextChart, "context"},
    # Streaming: a viewport on x, so the drawer offers Incremental (#327, #402)
    {Examples.Charts.ScrollingSeries, "scrolling_series"},
    {Examples.Charts.IncrementalLine, "incremental_line"}
  ]

  @size {320, 220}

  # The previews are never rendered in this process (#397): the cached ones are assigned at
  # mount, and once connected a task per missing one renders and sends it; a dead render
  # shows a placeholder where the cache is empty.
  def mount(_params, _session, socket) do
    previews =
      for {module, _slug} <- @charts,
          {:ok, svg} <- [Examples.Previews.get(module, @size)],
          into: %{},
          do: {module, svg}

    socket = assign(socket, charts: @charts, previews: previews)
    {:ok, if(connected?(socket), do: start_previews(socket), else: socket)}
  end

  def handle_info({ref, {:preview, module, svg}}, socket) when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    {:noreply, update(socket, :previews, &Map.put(&1, module, svg))}
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, socket), do: {:noreply, socket}

  defp start_previews(socket) do
    for {module, _slug} <- @charts, not Map.has_key?(socket.assigns.previews, module) do
      Task.Supervisor.async_nolink(Examples.TaskSupervisor, fn ->
        {:preview, module, Examples.Previews.render(module, @size)}
      end)
    end

    socket
  end

  def render(assigns) do
    ~H"""
    <ExamplesWeb.SiteHeader.header tab={:charts} />
    <main>
      <div class="tools-bar">
        <a href="/performance" class="tool-link">
          <span class="tool-icon">⚡</span>
          <span>Performance Test — compare the backends on any chart</span>
        </a>
        <a href="/hybrid" class="tool-link">
          <span class="tool-icon">🔀</span>
          <span>Hybrid SVG/Canvas Demo</span>
        </a>
        <a href="/interaction" class="tool-link" style="background: linear-gradient(135deg, #f59e0b 0%, #d97706 100%);">
          <span class="tool-icon">🎯</span>
          <span>Client-side Interaction (tooltip, crosshair, legend)</span>
        </a>
        <a href="/builder" class="tool-link" style="background: linear-gradient(135deg, #8b5cf6 0%, #6d28d9 100%);">
          <span class="tool-icon">🧩</span>
          <span>Chart Builder (edit a stack of fragments)</span>
        </a>
      </div>
      <p class="gallery-note">
        Every chart here is a design (spec/14): a map that says what the chart is, applied to rows and rendered by the
        library on any backend. Open one for the <code>Visualize.Chart.Build</code> calls that make it — the thing to copy — the map
        they fold to, and the same design on SVG and canvas.
      </p>
      <div class="gallery">
        <%= for {module, slug} <- @charts do %>
          <div class="chart-card">
            <a href={"/chart/#{slug}"}>
              <div class="chart-preview">
                <%= if svg = @previews[module] do %>
                  <%= Phoenix.HTML.raw(svg) %>
                <% else %>
                  <div class="chart-preview-pending" aria-label="rendering"></div>
                <% end %>
              </div>
              <div class="chart-info">
                <h3><%= module.title() %></h3>
                <p><%= module.description() %></p>
              </div>
            </a>
          </div>
        <% end %>
      </div>
    </main>
    """
  end
end
