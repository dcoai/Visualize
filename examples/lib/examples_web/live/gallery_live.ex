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
    {Examples.Charts.Globe, "globe"}
  ]

  def mount(_params, _session, socket) do
    {:ok, assign(socket, charts: @charts)}
  end

  def render(assigns) do
    ~H"""
    <ExamplesWeb.SiteHeader.header tab={:charts} />
    <main>
      <div class="tools-bar">
        <a href="/chart/scrolling_series" class="tool-link" style="background: linear-gradient(135deg, #10b981 0%, #059669 100%);">
          <span class="tool-icon">🚀</span>
          <span>Scrolling series (incremental, with a data rate)</span>
        </a>
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
                <%= Phoenix.HTML.raw(render_preview(module)) %>
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

  # Every chart is a design and renders its own document (`Examples.Charts.Design`, #335).
  defp render_preview(module), do: Examples.Charts.Design.render(module, width: 320, height: 220)
end
