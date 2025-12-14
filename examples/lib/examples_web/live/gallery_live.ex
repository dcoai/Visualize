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
    {Examples.Charts.PieChart, "pie"},
    {Examples.Charts.DonutChart, "donut"},
    {Examples.Charts.ScatterPlot, "scatter"},
    {Examples.Charts.BubbleChart, "bubble"},
    {Examples.Charts.RadialBarChart, "radial"},
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
    # Maps
    {Examples.Charts.WorldMap, "world_map"},
    {Examples.Charts.Globe, "globe"}
  ]

  def mount(_params, _session, socket) do
    {:ok, assign(socket, charts: @charts)}
  end

  def render(assigns) do
    ~H"""
    <header>
      <h1>Visualize Examples</h1>
      <p>D3-style data visualizations in Elixir</p>
    </header>
    <main>
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

  defp render_preview(module) do
    module.render(width: 320, height: 220)
    |> Visualize.SVG.Renderer.render_to_string()
  end
end
