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

  alias Examples.Charts.{Design, Templates}
  alias Visualize.Chart

  # The families of #124 that have been through the layer, in the proposal's order:
  # work item 1 (#125, cartesian basics), work item 2 (#126, angular and radial),
  # work item 3 (#127, hierarchy and graph), work item 4 (#128, statistical and dense) and
  # work item 5 (#129, geographic).
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
    Examples.Charts.GaugeChart,
    Examples.Charts.RadarChart,
    Examples.Charts.PolarTransformChart,
    Examples.Charts.LoadGauge,
    Examples.Charts.LoadAge,
    Examples.Charts.SunburstChart,
    Examples.Charts.ChordDiagram,
    Examples.Charts.TreemapChart,
    Examples.Charts.CirclePacking,
    Examples.Charts.TreeLayout,
    Examples.Charts.ClusterDendrogram,
    Examples.Charts.SankeyDiagram,
    Examples.Charts.ForceGraph,
    Examples.Charts.Heatmap,
    Examples.Charts.ContourPlot,
    Examples.Charts.RidgelinePlot,
    Examples.Charts.Streamgraph,
    Examples.Charts.HexbinChart,
    Examples.Charts.SpectrumChart,
    Examples.Charts.WorldMap,
    Examples.Charts.Globe
  ]

  # Converted and deterministic: these hold the golden.
  @golden_charts [
    Examples.Charts.LineChart,
    Examples.Charts.MultiLineChart,
    Examples.Charts.AreaChart,
    Examples.Charts.BarChart,
    Examples.Charts.HorizontalBarChart,
    Examples.Charts.StackedBarChart,
    Examples.Charts.BubbleChart,
    Examples.Charts.PieChart,
    Examples.Charts.DonutChart,
    Examples.Charts.SunburstChart,
    Examples.Charts.RadialBarChart,
    Examples.Charts.GaugeChart,
    Examples.Charts.RadarChart,
    Examples.Charts.PolarTransformChart,
    Examples.Charts.LoadGauge,
    Examples.Charts.LoadAge,
    Examples.Charts.ChordDiagram,
    Examples.Charts.GroupedBarChart,
    Examples.Charts.TreemapChart,
    Examples.Charts.CirclePacking,
    Examples.Charts.TreeLayout,
    Examples.Charts.ClusterDendrogram,
    Examples.Charts.SankeyDiagram,
    Examples.Charts.Heatmap,
    Examples.Charts.ContourPlot,
    Examples.Charts.RidgelinePlot,
    Examples.Charts.WorldMap,
    Examples.Charts.Globe,
    Examples.Charts.HexbinChart,
    Examples.Charts.SpectrumChart
  ]

  # Converted, but asserted on rather than recorded: seeded at compile time, or — the
  # force graph — a layout a golden would pin across any change to the simulation (#127).
  @seeded_charts [
    Examples.Charts.StackedAreaChart,
    Examples.Charts.ScatterPlot,
    Examples.Charts.Streamgraph,
    Examples.Charts.ForceGraph
  ]

  # Left imperative, each with the filed gap named in its `@moduledoc`: none, since #348
  # (#335); the list stays so the next family's conversions have somewhere to file.
  @filed []

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

  # A chart that still names an absolute colour, with the issue that keeps it there
  # (#421). The maps' ocean is a semantic backdrop the theme has no slot for — `:grid` is
  # the graticule's own stroke and `:background` would make it vanish — which is #422.
  @absolute_colours %{
    Examples.Charts.WorldMap => "#422",
    Examples.Charts.Globe => "#422"
  }

  # `#rgb`, `#rrggbb` and the functional forms; a named colour would slip through, and
  # nothing in the gallery writes one.
  @colour ~r/^(#[0-9a-fA-F]{3,8}|(rgb|hsl)a?\()/

  describe "every chart draws in the theme (spec/14 §5.6, #421)" do
    test "no design names an absolute colour, but for the gaps filed against it" do
      # Every chart of the grid, not just the recorded ones: the two streaming designs
      # are outside `charts/0`, and they are exactly where the literals were.
      for module <- Templates.gallery_modules() do
        {design, _sources} = module.design([])
        found = literal_colours(design)

        case Map.fetch(@absolute_colours, module) do
          {:ok, issue} ->
            refute found == [],
                   "#{inspect(module)} names no absolute colour now: drop it from @absolute_colours"

            {:docs_v1, _, _, _, %{"en" => doc}, _, _} = Code.fetch_docs(module)
            assert doc =~ issue, "#{inspect(module)} must name the gap that keeps its literal"

          :error ->
            assert found == [],
                   "#{inspect(module)} names #{inspect(found)} instead of a theme slot"
        end
      end
    end

    test "a streaming chart's paint follows the palette it is rendered under" do
      for module <- [Examples.Charts.ScrollingSeries, Examples.Charts.IncrementalLine] do
        light = svg_under(module, :default)
        dark = svg_under(module, :dark)

        # The slot reaches the SVG as its CSS variable, and the fallback differs by theme.
        assert light =~ "var(--vis-series-1,"
        assert dark =~ "var(--vis-series-1,"
        refute light == dark
        refute light =~ "#4e79a7"
      end
    end
  end

  defp svg_under(module, palette) do
    {design, sources} = module.design([])
    {:ok, chart} = Chart.from_map(design)
    {:ok, applied} = Chart.apply(chart, sources: sources, theme: Design.theme(palette: palette))
    Chart.render(applied)
  end

  # Every binary anywhere in the design that reads as a CSS colour.
  defp literal_colours(term) when is_map(term),
    do: term |> Map.values() |> Enum.flat_map(&literal_colours/1)

  defp literal_colours(term) when is_list(term), do: Enum.flat_map(term, &literal_colours/1)

  defp literal_colours(term) when is_binary(term),
    do: if(Regex.match?(@colour, term), do: [term], else: [])

  defp literal_colours(_term), do: []

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
      {width, height} = Design.size(module, width: 320, height: 220)
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

  # Canvas mode on the gallery page is the split (spec/14 §12.6, #268): the furniture as
  # SVG, the marks on the binary canvas — so the axes a whole-chart binary stream drops
  # (spec/09 §4.4) are drawn.
  test "every design's hybrid draws its furniture as SVG over a binary canvas of its marks" do
    for module <- charts() do
      hybrid = Design.hybrid(module, [])
      axes = Design.applied(module, []).chart.frame |> Map.get(:axes, [])

      assert hybrid.static =~ "<svg"
      assert hybrid.width > 0 and hybrid.height > 0

      # The furniture is SVG — static where its scales are fixed, in the tick's SVG layer
      # where a domain is :auto (spec/14 §12.2); the page draws both over the canvas.
      furniture = hybrid.static <> hybrid.dynamic_svg
      assert length(Regex.scan(~r/class="axis /, furniture)) == length(axes)

      # The marks are on the canvas — literal paints, no CSS reference — or, for a facet
      # frame, in the SVG layer (§12.3).
      if hybrid.canvas != "" do
        binary = Base.decode64!(hybrid.canvas)
        assert byte_size(binary) > 0
        assert :binary.match(binary, "var(") == :nomatch
        # Every mark on the canvas draws: a fill or a stroke record per mark, the paint
        # that sits on the mark's group reaching its elements (spec/09 §4.4, #231).
        records = Visualize.Backend.CanvasBinary.Decoder.decode(binary)
        draws = Enum.count(records, &(&1 in [:fill, :stroke]))
        assert draws > 0, "#{inspect(module)} draws nothing on the canvas"
      else
        assert hybrid.dynamic_svg =~ ~s(class="mark )
      end
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
