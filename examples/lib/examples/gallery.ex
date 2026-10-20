defmodule Examples.Gallery do
  @moduledoc """
  The gallery's charts, in the one order every page shows them (spec/14 §12.6, #484).

  The index draws a card per chart in this order, the chart page finds its module by
  slug here and steps to its neighbors in this order, so a chart added here is on both
  pages and a chart missing here is on neither.
  """

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
    # The night side and the GPS constellation over the turning World Map (#526)
    {Examples.Charts.DayNightGps, "day_night_gps"},
    {Examples.Charts.Globe, "globe"},
    # An elite field on Grandma's Marathon over OpenStreetMap tiles: the course beneath
    # the canvas, an inset fitted to the field every tick, and the standings (#476, #783)
    {Examples.Charts.Marathon, "grandmas_marathon"},
    # A machine's load, two ways (#415), one source in two frames (#429), and the dial
    # inset over the log-age plot's corner (#498)
    {Examples.Charts.LoadGauge, "load_gauge"},
    {Examples.Charts.LoadAge, "load_age"},
    {Examples.Charts.LoadChart, "load"},
    {Examples.Charts.LoadAgeGauge, "load_age_gauge"},
    # One source at four time scales, four frames across the box (#429)
    {Examples.Charts.ContextChart, "context"},
    # 50,000 rows reduced to the plot's width, :m4 and :lttb (#448)
    {Examples.Charts.Downsampling, "downsampling"},
    # Streaming: a viewport on x, so the drawer offers Incremental (#327, #402)
    {Examples.Charts.ScrollingSeries, "scrolling_series"},
    {Examples.Charts.IncrementalLine, "incremental_line"},
    # The style grammar of 0.7.0 (#705): typed colors and their transforms, paints
    {Examples.Charts.ColorsChart, "colors"},
    {Examples.Charts.PaintsChart, "paints"},
    # Palette modifiers, style lists, extends, defaults, units, a non-scaling stroke
    {Examples.Charts.CompositionChart, "composition"}
  ]

  @by_slug Map.new(@charts, fn {module, slug} -> {slug, module} end)

  @doc "The gallery's charts as `{module, slug}` pairs, in the order the index shows them."
  @spec charts() :: [{module(), String.t()}]
  def charts, do: @charts

  @doc "The same charts as a map from slug to module, derived from `charts/0`."
  @spec by_slug() :: %{String.t() => module()}
  def by_slug, do: @by_slug

  @doc "The module of a slug, or `nil` for a slug the gallery does not list."
  @spec module(String.t()) :: module() | nil
  def module(slug), do: Map.get(@by_slug, slug)

  @doc """
  The charts either side of a slug in the gallery's order, `{previous, next}`, each a
  `{module, slug}` pair. The order wraps: the first chart's previous is the last, and the
  last chart's next is the first.
  """
  @spec neighbors(String.t()) :: {{module(), String.t()}, {module(), String.t()}}
  def neighbors(slug) do
    count = length(@charts)

    index =
      Enum.find_index(@charts, fn {_module, s} -> s == slug end) ||
        raise ArgumentError, "the gallery lists no chart #{inspect(slug)}"

    {Enum.at(@charts, rem(index - 1 + count, count)), Enum.at(@charts, rem(index + 1, count))}
  end
end
