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

  alias Examples.Frames
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
    Examples.Charts.LoadChart,
    Examples.Charts.LoadAgeGauge,
    Examples.Charts.ContextChart,
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
    Examples.Charts.Downsampling,
    Examples.Charts.WorldMap,
    Examples.Charts.DayNightGps,
    Examples.Charts.Globe,
    Examples.Charts.GpsTrack,
    # The style grammar of 0.7.0 (#705).
    Examples.Charts.ColorsChart,
    Examples.Charts.PaintsChart,
    Examples.Charts.CompositionChart
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
    Examples.Charts.LoadChart,
    Examples.Charts.LoadAgeGauge,
    Examples.Charts.ContextChart,
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
    Examples.Charts.DayNightGps,
    Examples.Charts.Globe,
    Examples.Charts.GpsTrack,
    Examples.Charts.HexbinChart,
    Examples.Charts.SpectrumChart,
    Examples.Charts.ColorsChart,
    Examples.Charts.PaintsChart,
    Examples.Charts.CompositionChart
  ]

  # Converted, but asserted on rather than recorded: seeded at compile time, or — the
  # force graph — a layout a golden would pin across any change to the simulation (#127),
  # or — downsampling — deterministic but drawing a 50,000-row line whole, close to a
  # megabyte of SVG a golden line would carry; its reductions are asserted on below and
  # in the library's own acceptance test (#448).
  @seeded_charts [
    Examples.Charts.StackedAreaChart,
    Examples.Charts.ScatterPlot,
    Examples.Charts.Streamgraph,
    Examples.Charts.ForceGraph,
    Examples.Charts.Downsampling
  ]

  # Left imperative, each with the filed gap named in its `@moduledoc`: none, since #348
  # (#335); the list stays so the next family's conversions have somewhere to file.
  @filed []

  @golden "test/support/charts_golden.txt"

  @charts @golden_charts ++ @seeded_charts

  def charts, do: @charts

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

  describe "every design validates, round-trips through from_map/to_map, and applies" do
    for module <- @charts do
      test "#{inspect(module)}", do: assert_applies(unquote(module))
    end
  end

  defp assert_applies(module) do
    {design, sources} = module.design([])
    assert {:ok, chart} = Chart.from_map(design)
    assert {:ok, ^chart} = Chart.from_map(Chart.to_map(chart))
    assert {:ok, applied} = Chart.apply(chart, sources: sources, theme: Design.theme([]))
    assert Enum.sort(Map.keys(applied.sources)) == Enum.sort(Map.keys(chart.sources))
    assert applied.chart.vars == %{}
  end

  # Every term a gallery design holds has a JSON form (spec/14 §11.2, #554): a tuple the
  # validator accepts without one makes `to_json/1` fail on a valid chart.
  describe "every design round-trips through to_json/from_json" do
    for module <- @charts do
      test "#{inspect(module)}", do: assert_json_round_trip(unquote(module))
    end
  end

  defp assert_json_round_trip(module) do
    {design, _sources} = module.design([])
    chart = Chart.from_map!(design)
    assert {:ok, json} = Chart.to_json(chart), inspect(module)
    assert {:ok, ^chart} = Chart.from_json(json), inspect(module)
  end

  # The sanity limits' defaults are generous (spec/14 §9.2, #541, D-137): every gallery
  # design passes them, as a map and through the JSON reader, which checks the parsed
  # document's structure before decoding it. `from_map/1` applies them too, so the test
  # above holds it as well; this one says so by name.
  describe "every design passes the default sanity limits" do
    for module <- @charts do
      test "#{inspect(module)}", do: assert_within_limits(unquote(module))
    end
  end

  defp assert_within_limits(module) do
    {design, _sources} = module.design([])
    assert Chart.Limits.check(design) == :ok, inspect(module)
    assert {:ok, chart} = Chart.from_map(design, limits: Chart.Limits.defaults())
    {:ok, json} = Chart.to_json(chart)

    assert {:ok, _chart} = Chart.from_json(json, limits: Chart.Limits.defaults()),
           inspect(module)
  end

  # A chart that still names an absolute color, with the issue that keeps it there
  # (#421). Empty: the maps' ocean, the last entry, is the theme's `:surface` since #422.
  # A future gap goes here with its issue, and the guard below fails the moment an
  # entry stops needing its exemption.
  @absolute_colors %{}

  # `#rgb`, `#rrggbb` and the functional forms; a named color would slip through, and
  # nothing in the gallery writes one.
  @color ~r/^(#[0-9a-fA-F]{3,8}|(rgb|hsl)a?\()/

  # The guard this class needed and did not have: the force graph, the world map and the
  # globe all emitted a byte-identical canvas payload on every tick while animating
  # correctly on SVG, because the compiled chart is built once and only the rows were
  # re-read. A design animating through its *frame* is now ticked with it; one animating
  # through a *mark* — the force graph's link distance — is a different chart and the
  # caller compiles it again. One test a chart (#735): the whole gallery's frames on two
  # backends was one test of 11 s alone, and it crossed its timeout on a loaded runner.
  describe "no chart animates on one backend and stands still on another (#424)" do
    for module <- Templates.gallery_modules(), not Frames.stream?(module) do
      test "#{inspect(module)}", do: assert_moves_alike(unquote(module))
    end
  end

  defp assert_moves_alike(module) do
    svg = Frames.prepare(module, [], :svg)
    {a_svg, svg} = Frames.frame(module, [animation_tick: 1], :svg, svg)
    {b_svg, _} = Frames.frame(module, [animation_tick: 20], :svg, svg)

    canvas = Frames.prepare(module, [], :canvas)
    {a_canvas, canvas} = Frames.frame(module, [animation_tick: 1], :canvas, canvas)
    {b_canvas, _} = Frames.frame(module, [animation_tick: 20], :canvas, canvas)

    # A hybrid frame is its canvas stream *and* its SVG layer: a mark under the
    # compile ceiling draws as SVG, so the canvas alone is not the picture.
    still_svg? = a_svg.svg == b_svg.svg

    still_canvas? = plots(a_canvas) == plots(b_canvas)

    assert still_svg? == still_canvas?,
           "#{inspect(module)} moves on one backend and not the other: " <>
             "svg #{if still_svg?, do: "still", else: "moves"}, " <>
             "canvas #{if still_canvas?, do: "still", else: "moves"}"
  end

  describe "every chart draws in the theme (spec/14 §5.6, #421)" do
    # Every chart of the grid, not just the recorded ones: the two streaming designs are
    # outside `charts/0`, and they are exactly where the literals were. One test a chart
    # (#735), and one for the gaps, so the guard holds for an empty list as for a full one.
    for module <- Templates.gallery_modules(), module not in Map.keys(@absolute_colors) do
      test "#{inspect(module)} names no absolute color",
        do: assert_theme_colors(unquote(module))
    end

    test "every gap filed against the theme still names its absolute color" do
      for {module, issue} <- @absolute_colors do
        {design, _sources} = module.design([])

        refute literal_colors(design) == [],
               "#{inspect(module)} names no absolute color now: drop it from @absolute_colors"

        {:docs_v1, _, _, _, %{"en" => doc}, _, _} = Code.fetch_docs(module)
        assert doc =~ issue, "#{inspect(module)} must name the gap that keeps its literal"
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

    test "a map's ocean is the theme's :surface, and differs between light and dark (#422)" do
      light = Visualize.Theme.default().surface
      dark = Visualize.Theme.dark().surface

      for module <- [Examples.Charts.WorldMap, Examples.Charts.DayNightGps, Examples.Charts.Globe] do
        light_svg = svg_under(module, :default)
        dark_svg = svg_under(module, :dark)

        assert light_svg =~ ~s{fill="var(--vis-surface, #{light})"}
        assert dark_svg =~ ~s{fill="var(--vis-surface, #{dark})"}
        refute light_svg =~ "#a8d5e5"
        refute light_svg == dark_svg
      end
    end

    test "every gallery palette gives a surface apart from its grid and its page" do
      for key <- Examples.ColorPalettes.list_palettes() do
        theme = Examples.ColorPalettes.theme(key)
        refute theme.surface in [theme.grid, theme.background], "#{key}: surface #{theme.surface}"
      end

      assert Examples.ColorPalettes.theme(:dark).surface == Visualize.Theme.dark().surface
    end
  end

  defp assert_theme_colors(module) do
    {design, _sources} = module.design([])
    found = literal_colors(design)
    assert found == [], "#{inspect(module)} names #{inspect(found)} instead of a theme slot"
  end

  defp svg_under(module, palette) do
    {design, sources} = module.design([])
    {:ok, chart} = Chart.from_map(design)
    {:ok, applied} = Chart.apply(chart, sources: sources, theme: Design.theme(palette: palette))
    Chart.render(applied)
  end

  # Every binary anywhere in the design that reads as a CSS color.
  defp literal_colors(term) when is_map(term),
    do: term |> Map.values() |> Enum.flat_map(&literal_colors/1)

  defp literal_colors(term) when is_list(term), do: Enum.flat_map(term, &literal_colors/1)

  defp literal_colors(term) when is_binary(term),
    do: if(Regex.match?(@color, term), do: [term], else: [])

  defp literal_colors(_term), do: []

  test "every chart renders exactly as recorded" do
    assert File.read!(@golden) == render()
  end

  test "a seeded chart renders its marks over its own rows" do
    for module <- @seeded_charts do
      svg = module.render([])
      {design, sources} = module.design([])

      assert svg =~ ~s(<svg )
      # One frame is `class="frame"`; a frame of several is `class="frame frame-<name>"`.
      assert svg =~ ~s(class="frame)

      for %{type: type} <- design.marks do
        assert svg =~ ~s(class="mark mark-#{type}"), "#{inspect(module)} drew no #{type}"
      end

      assert sources |> Map.values() |> Enum.all?(&(&1 != []))
    end
  end

  describe "every rendered chart is one accessible svg document naming the chart" do
    for module <- @charts do
      test "#{inspect(module)}", do: assert_accessible(unquote(module))
    end
  end

  defp assert_accessible(module) do
    svg = module.render([])

    assert svg =~ ~s(role="img")
    assert svg =~ "<title id="
    assert svg =~ "<desc id="
    assert svg =~ module.title()
    assert svg =~ module.description()
    assert String.ends_with?(svg, "</svg>")
    assert length(String.split(svg, "<svg ")) == 2
  end

  describe "the width and height options reach the frame, and the frame's size is the document's" do
    for module <- @charts do
      test "#{inspect(module)}", do: assert_sized(unquote(module))
    end
  end

  defp assert_sized(module) do
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

  # The charts that color by names of the theme's table — `color(:blue)`, `color(:info)` —
  # rather than by its series (#705): a palette that changes only the series leaves a name
  # as it is, so these recolor under a theme that changes the names, the dark one.
  @named_colors [Examples.Charts.ColorsChart, Examples.Charts.PaintsChart]

  describe "the palette option is the theme, so every chart recolors" do
    for module <- @charts -- @named_colors do
      test "#{inspect(module)}", do: assert_recolors(unquote(module))
    end
  end

  defp assert_recolors(module) do
    assert module.render(palette: :sunrise) =~ "#ffd098"
    refute module.render(palette: :sunrise) =~ "#3b6fa8"
  end

  test "a chart that colors by the theme's names recolors under a theme that changes them" do
    for module <- @named_colors do
      assert module.render([]) =~ "#3b6fa8"
      assert module.render(palette: :dark) =~ "#7fb3e6"
      refute module.render(palette: :dark) =~ "#3b6fa8"
    end
  end

  describe "the animation tick moves the data" do
    for module <- @charts do
      test "#{inspect(module)}", do: assert_tick_moves(unquote(module))
    end
  end

  defp assert_tick_moves(module) do
    refute module.render(animation_tick: 7) == module.render([])
  end

  describe "every chart renders on a canvas with literal paints and no CSS reference" do
    for module <- @charts do
      test "#{inspect(module)}", do: assert_literal_canvas(unquote(module))
    end
  end

  defp assert_literal_canvas(module) do
    binary = Base.decode64!(Design.canvas(module, []))
    assert byte_size(binary) > 0
    assert :binary.match(binary, "var(") == :nomatch
  end

  # Canvas mode on the gallery page is the split (spec/14 §12.6, #268): the furniture as
  # SVG, the marks on the binary canvas — so the axes a whole-chart binary stream drops
  # (spec/09 §4.4) are drawn.
  describe "every design's hybrid draws its furniture as SVG over a binary canvas of its marks" do
    for module <- @charts do
      test "#{inspect(module)}", do: assert_hybrid(unquote(module))
    end
  end

  defp assert_hybrid(module) do
    hybrid = Design.hybrid(module, [])
    applied = Design.applied(module, [])
    axes = Enum.flat_map(applied.frames, fn {_name, frame} -> frame.axes || [] end)

    assert hybrid.static =~ "<svg"
    assert hybrid.width > 0 and hybrid.height > 0
    # One plot per frame, in drawing order (spec/14 §12.1, #432).
    assert length(hybrid.plots) == map_size(applied.frames)

    # The furniture is SVG — static where its scales are fixed, in the tick's SVG layer
    # where a domain is :auto (spec/14 §12.2); the page draws both over the canvases.
    furniture = hybrid.static <> hybrid.dynamic_svg
    assert length(Regex.scan(~r/class="axis /, furniture)) == length(axes)

    # Each plot's marks are on its own canvas — literal paints, no CSS reference — or,
    # for a facet frame, in its SVG layer (§12.3).
    for plot <- hybrid.plots do
      if plot.canvas != "" do
        binary = Base.decode64!(plot.canvas)
        assert byte_size(binary) > 0
        assert :binary.match(binary, "var(") == :nomatch
        # Every mark on the canvas draws: a fill or a stroke record per mark, the paint
        # that sits on the mark's group reaching its elements (spec/09 §4.4, #231).
        records = Visualize.Backend.CanvasBinary.Decoder.decode(binary)
        draws = Enum.count(records, &(&1 in [:fill, :stroke]))
        assert draws > 0, "#{inspect(module)} draws nothing on the canvas of #{plot.name}"
      else
        assert plot.dynamic_svg =~ ~s(class="mark ),
               "#{inspect(module)}: #{plot.name} draws nothing at all"
      end
    end
  end

  # What a canvas frame carries per plot: the stream and the SVG layer over it.
  defp plots(frame), do: for(plot <- frame.plots, do: {plot.canvas, plot.dynamic_svg})

  describe "sample_code/0 is the design a reader would write" do
    for module <- @charts do
      test "#{inspect(module)}", do: assert_sample_code(unquote(module))
    end
  end

  defp assert_sample_code(module) do
    code = module.sample_code()
    assert code =~ "import Visualize.Chart.Build"
    # A design of several frames folds a list built with `in_frame/2`, so the bracket
    # need not follow the call on the same line (#429).
    assert code =~ "Visualize.Chart.compose("
    assert code =~ "Visualize.Chart.render(applied)"
  end
end
