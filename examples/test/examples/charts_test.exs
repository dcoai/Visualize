defmodule Examples.ChartsTest do
  @moduledoc """
  The gallery's charts written as designs (#124): every one renders, round-trips through
  `Visualize.Chart.from_map/1` and `to_map/1`, and draws exactly what is recorded.

  The rendered-SVG golden is `test/support/charts_golden.txt`, one line per chart.
  Regenerate it only when a chart's output changes on purpose:

      cd examples && MIX_ENV=test mix run -e 'ExUnit.start(autorun: false); Code.require_file("test/examples/charts_test.exs"); Examples.ChartsTest.write!()'

  A chart whose data is seeded at compile time (`:rand.uniform/1`, `Enum.random/1`) cannot
  hold a golden — a recompile reseeds it — so those charts are asserted on rather than
  recorded.
  """
  use ExUnit.Case, async: true

  alias Examples.Charts.Design
  alias Visualize.Chart

  # The families of #124 that have been through the layer, in the proposal's order:
  # work item 1 (#125, cartesian basics) and work item 2 (#126, angular and radial).
  @families [
    Examples.Charts.LineChart,
    Examples.Charts.MultiLineChart,
    Examples.Charts.AreaChart,
    Examples.Charts.StackedAreaChart,
    Examples.Charts.BarChart,
    Examples.Charts.GroupedBarChart,
    Examples.Charts.HorizontalBarChart,
    Examples.Charts.StackedBarChart,
    Examples.Charts.ScatterPlot,
    Examples.Charts.BubbleChart,
    Examples.Charts.PieChart,
    Examples.Charts.DonutChart,
    Examples.Charts.RadialBarChart,
    Examples.Charts.SunburstChart,
    Examples.Charts.ChordDiagram
  ]

  # Converted and deterministic: these hold the golden.
  @golden_charts [
    Examples.Charts.LineChart,
    Examples.Charts.MultiLineChart,
    Examples.Charts.BarChart,
    Examples.Charts.HorizontalBarChart,
    Examples.Charts.StackedBarChart,
    Examples.Charts.BubbleChart,
    Examples.Charts.PieChart,
    Examples.Charts.DonutChart,
    Examples.Charts.SunburstChart
  ]

  # Converted, but seeded at compile time: asserted on, never recorded.
  @seeded_charts [
    Examples.Charts.StackedAreaChart,
    Examples.Charts.ScatterPlot
  ]

  # Left imperative, each with a filed gap named in its `@moduledoc`.
  @filed [
    {Examples.Charts.AreaChart, "#133"},
    {Examples.Charts.GroupedBarChart, "#132"},
    {Examples.Charts.RadialBarChart, "#137"},
    {Examples.Charts.ChordDiagram, "#137"}
  ]

  @golden "test/support/charts_golden.txt"

  def charts, do: @golden_charts ++ @seeded_charts

  def render, do: Enum.map_join(@golden_charts, "", &"#{inspect(&1)} #{&1.render([])}\n")

  def write!, do: File.write!(@golden, render())

  test "every chart of a converted family is a design, or is left imperative with its gap filed" do
    assert Enum.sort(Enum.filter(@families, &Design.design?/1)) == Enum.sort(charts())

    for {module, issue} <- @filed do
      refute Design.design?(module), "#{inspect(module)} is a design now: drop it from @filed"
      {:docs_v1, _, _, _, %{"en" => doc}, _, _} = Code.fetch_docs(module)
      assert doc =~ issue, "#{inspect(module)} must name the gap that keeps it imperative"
    end

    assert Enum.sort(Enum.reject(@families, &Design.design?/1)) ==
             Enum.sort(Enum.map(@filed, &elem(&1, 0)))
  end

  test "every design validates, round-trips through from_map/to_map, and applies" do
    for module <- charts() do
      {design, sources} = module.design([])
      assert {:ok, chart} = Chart.from_map(design)
      assert {:ok, ^chart} = Chart.from_map(Chart.to_map(chart))
      assert {:ok, applied} = Chart.apply(chart, sources: sources, theme: Design.theme([]))
      assert Enum.sort(Map.keys(applied.sources)) == Enum.sort(Map.keys(chart.sources))
      assert applied.chart.vars == %{}
    end
  end

  test "every chart renders exactly as recorded" do
    assert File.read!(@golden) == render()
  end

  test "a seeded chart renders its marks over its own rows" do
    for module <- @seeded_charts do
      svg = module.render([])
      {design, sources} = module.design([])

      assert svg =~ ~s(<svg )
      assert svg =~ ~s(class="frame")

      for %{type: type} <- design.marks do
        assert svg =~ ~s(class="mark mark-#{type}"), "#{inspect(module)} drew no #{type}"
      end

      assert sources |> Map.values() |> Enum.all?(&(&1 != []))
    end
  end

  test "every rendered chart is one accessible svg document naming the chart" do
    for module <- charts() do
      svg = module.render([])

      assert svg =~ ~s(role="img")
      assert svg =~ "<title id="
      assert svg =~ "<desc id="
      assert svg =~ module.title()
      assert svg =~ module.description()
      assert String.ends_with?(svg, "</svg>")
      assert length(String.split(svg, "<svg ")) == 2
    end
  end

  test "the width and height options reach the frame, and the frame's size is the document's" do
    for module <- charts() do
      {design, _sources} = module.design(width: 320, height: 220)
      %{size: %{width: width, height: height}} = design.frame
      svg = module.render(width: 320, height: 220)

      # A chart may widen its own frame to reserve a margin — the donut does, for its
      # legend — but never below the size it was asked for.
      assert width >= 320
      assert height == 220
      assert svg =~ ~s(width="#{width}")
      assert svg =~ ~s(height="#{height}")
      assert svg =~ ~s(viewBox="0 0 #{width} #{height}")
    end
  end

  test "the palette option is the theme, so every chart recolours" do
    for module <- charts() do
      assert module.render(palette: :sunrise) =~ "#ffd098"
      refute module.render(palette: :sunrise) =~ "#3b6fa8"
    end
  end

  test "the animation tick moves the data" do
    for module <- charts() do
      refute module.render(animation_tick: 7) == module.render([])
    end
  end

  test "every chart renders on a canvas with literal paints and no CSS reference" do
    for module <- charts() do
      binary = Base.decode64!(Design.canvas(module, []))
      assert byte_size(binary) > 0
      assert :binary.match(binary, "var(") == :nomatch
    end
  end

  test "sample_code/0 is the design a reader would write" do
    for module <- charts() do
      code = module.sample_code()
      assert code =~ "import Visualize.Chart.Build"
      assert code =~ "Visualize.Chart.compose(["
      assert code =~ "Visualize.Chart.render(applied)"
    end
  end
end
