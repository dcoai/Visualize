defmodule Examples.SummaryTest do
  @moduledoc """
  Every gallery chart describes itself (spec/14 §21, #557, D-142): its summary names the
  right kind, says its series, axes and extremes as the chart draws them, reaches the
  `<svg>`'s description with nothing written by the chart, and comes with a data table.
  """
  use ExUnit.Case, async: true

  alias Examples.Charts
  alias Examples.Charts.{Design, Templates}
  alias Visualize.Chart.Summary

  # The kind each gallery chart is, by the rules of §21.1, frame by frame.
  @kinds %{
    Charts.AreaChart => ["area chart"],
    Charts.BarChart => ["bar chart"],
    Charts.BubbleChart => ["bubble chart"],
    Charts.ChordDiagram => ["chord diagram"],
    Charts.CirclePacking => ["circle packing"],
    Charts.ClusterDendrogram => ["dendrogram"],
    Charts.ColorsChart => ["bar chart", "bar chart"],
    Charts.CompositionChart => ["bar chart", "line chart", "line chart"],
    Charts.ContextChart => ["area chart", "area chart", "area chart", "area chart"],
    Charts.ContourPlot => ["contour plot"],
    Charts.DayNightGps => ["map"],
    Charts.DonutChart => ["donut chart"],
    Charts.Downsampling => ["line chart", "line chart", "line chart"],
    Charts.ForceGraph => ["network graph"],
    Charts.GaugeChart => ["gauge"],
    Charts.Globe => ["map"],
    Charts.PaintsChart => ["area chart", "bar chart"],
    Charts.GroupedBarChart => ["grouped bar chart"],
    Charts.Heatmap => ["heatmap"],
    Charts.HexbinChart => ["hexbin chart"],
    Charts.HorizontalBarChart => ["bar chart"],
    Charts.IncrementalLine => ["line chart"],
    Charts.LineChart => ["line chart"],
    Charts.LoadAge => ["line chart"],
    Charts.LoadAgeGauge => ["line chart", "gauge"],
    Charts.LoadChart => ["area chart", "radial bar chart"],
    Charts.LoadGauge => ["gauge"],
    # The clock frame is a text alone, which the rules call a chart (#783).
    Charts.Marathon => ["chart", "map", "map", "bar chart"],
    Charts.MultiLineChart => ["line chart"],
    Charts.PieChart => ["pie chart"],
    Charts.PolarTransformChart => ["radar chart"],
    Charts.RadarChart => ["radar chart"],
    Charts.RadialBarChart => ["rose chart"],
    Charts.RidgelinePlot => ["area chart"],
    Charts.SankeyDiagram => ["Sankey diagram"],
    Charts.ScatterPlot => ["Voronoi diagram", "bubble chart"],
    Charts.ScrollingSeries => ["area chart"],
    Charts.SpectrumChart => ["area chart", "spectrum"],
    Charts.StackedAreaChart => ["stacked area chart"],
    Charts.StackedBarChart => ["stacked bar chart"],
    Charts.Streamgraph => ["streamgraph"],
    Charts.SunburstChart => ["sunburst"],
    Charts.TreeLayout => ["tree diagram"],
    Charts.TreemapChart => ["treemap"],
    Charts.WorldMap => ["map"]
  }

  # Whole summaries of the deterministic charts, one of each family the rules tell apart:
  # what a screen reader is told, word for word.
  @texts %{
    Charts.LineChart =>
      "Line chart, 1 series (y) of 51 points. Bottom axis x, from 0 to 50. Left axis y, " <>
        "from 10 to 110. Highest y 101 at x 41; lowest y 15.96 at x 50.",
    Charts.BarChart =>
      "Bar chart, 1 series (frequency) of 26 bars. Bottom axis letter, 26 categories from " <>
        "A to Z. Left axis frequency, from 0.0% to 13.0%. Highest frequency 12.7% at letter " <>
        "E; lowest frequency 0.1% at letter Z.",
    Charts.GaugeChart =>
      "Gauge, 1 series (value) of 1 reading. Angle axis value, from 0% to 100%. Value 42%.",
    Charts.PieChart =>
      "Pie chart, 1 series (value) of 6 slices. Highest value 64.5 at Chrome; lowest value " <>
        "2.3 at Opera.",
    Charts.StackedBarChart =>
      "Stacked bar chart, 4 series: desktop, mobile, tablet and other. Bottom axis year, 5 " <>
        "categories: 2019, 2020, 2021, 2022 and 2023. Left axis value, from 0% to 100%. " <>
        "Highest value 55% at year 2023 in mobile; lowest value 5% at year 2019 in other.",
    Charts.Heatmap =>
      "Heatmap, 1 series (value) of 168 cells. Bottom axis Hour, from 0 to 24. Left axis " <>
        "day, 7 categories: Mon, Tue, Wed, Thu, Fri, Sat and Sun. Highest value 100 at hour " <>
        "12, day Mon; lowest value 1 at hour 0, day Tue.",
    Charts.TreemapChart =>
      "Treemap, 1 series (value) of 22 cells. Highest value 8,500 at Cluster; lowest value " <>
        "2,100 at DataUtil."
  }

  test "every gallery chart has its kind stated" do
    assert Enum.sort(Templates.gallery_modules()) == Enum.sort(Map.keys(@kinds))
  end

  # One test a chart (#735).
  describe "every gallery chart is the kind the rules make it" do
    for {module, kinds} <- @kinds do
      test "#{inspect(module)}", do: assert_kinds(unquote(module), unquote(kinds))
    end
  end

  defp assert_kinds(module, kinds) do
    summary = Summary.new(Design.applied(module, []))
    assert Enum.map(summary.frames, & &1.kind) == kinds, inspect(module)
    assert summary.name == module.title(), inspect(module)
  end

  test "the deterministic charts' summaries are said word for word" do
    for {module, text} <- @texts do
      assert Summary.text(Design.applied(module, [])) == text, inspect(module)
    end
  end

  describe "every chart's <svg> is named by its title and described by its description and summary" do
    for module <- Templates.gallery_modules() do
      test "#{inspect(module)}", do: assert_named_and_described(unquote(module))
    end
  end

  defp assert_named_and_described(module) do
    text = module |> Design.applied([]) |> Summary.text() |> escape()
    svg = Design.render(module, [])

    assert svg =~ ~r/aria-describedby="vis-[a-z0-9]+-desc" aria-label="/, inspect(module)
    assert svg =~ ~s(aria-label="#{escape(module.title())}"), inspect(module)
    refute svg =~ "<title", inspect(module)
    assert svg =~ "#{text}</desc>", inspect(module)
  end

  describe "every chart that draws a value has a data table, captioned by its name" do
    for module <- Templates.gallery_modules() do
      test "#{inspect(module)}", do: assert_data_table(unquote(module))
    end
  end

  defp assert_data_table(module) do
    applied = Design.applied(module, [])
    summary = Summary.new(applied)
    html = Summary.table(applied)

    if Enum.any?(summary.frames, &(&1.extremes != [])) do
      # The table is HTML, escaped as Phoenix escapes it: an apostrophe is `&#39;` (#783).
      caption = module.title() |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
      assert html =~ "<table><caption>#{caption}", inspect(module)
      assert html =~ ~s(<th scope="col">), inspect(module)
    end
  end

  defp escape(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end
end
