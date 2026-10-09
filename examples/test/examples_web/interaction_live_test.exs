defmodule ExamplesWeb.InteractionLiveTest do
  @moduledoc """
  The interaction page's crosshairs sit on the series they snap to (#507, spec/10 §13.3).

  The hook tests hold `CrosshairHook` to the arrays it is given; this holds the arrays to
  the chart the page draws. For both demos — the crosshair over the SVG and the one over
  the binary canvas — and at two sizes, every point of `data-xs` × `data-ys`, offset by
  `data-plot`'s origin, is the vertex the line mark draws for the same row within a pixel:
  the SVG path's in the frame group's coordinates, the canvas stream's through its
  transform. And the canvas draws at the arrays' `data-size`, the `viewBox` of the SVG,
  since a stream draws one canvas pixel per chart unit.

  The legend chart names every series' points as it names their line (#508):
  `LegendHook` hides by `data-series`, so a point without it stayed drawn when its series
  was toggled off.
  """
  use ExUnit.Case, async: true

  alias ExamplesWeb.InteractionLive
  alias Visualize.Backend.CanvasBinary.Decoder

  # The page's own size, and a narrower one.
  @sizes [{720, 380}, {480, 320}]

  defp page(size) do
    size
    |> InteractionLive.build()
    |> Map.merge(%{picked: nil, hovered: nil, hidden: %{}, __changed__: %{}})
    |> InteractionLive.render()
    |> Phoenix.LiveViewTest.rendered_to_string()
  end

  # The opening tag of the element with `id`, and the markup after it.
  defp element(html, id) do
    [_, tag, rest] = Regex.run(~r/<div id="#{id}"([^>]*)>(.*)/s, html)
    {tag, rest}
  end

  defp attr(tag, name) do
    [_, value] = Regex.run(~r/\b#{name}="([^"]*)"/, tag)
    value
  end

  defp numbers(text) do
    ~r/-?\d+(?:\.\d+)?(?:e-?\d+)?/
    |> Regex.scan(text)
    |> Enum.map(fn [n] -> n |> Float.parse() |> elem(0) end)
  end

  # Each series' points in chart units, from the crosshair's attributes.
  defp crosshair_points(tag) do
    [left, top | _] = numbers(attr(tag, "data-plot"))
    xs = tag |> attr("data-xs") |> Jason.decode!()

    for ys <- Jason.decode!(attr(tag, "data-ys")) do
      for {x, y} <- Enum.zip(xs, ys), y != nil, do: {left + x, top + y}
    end
  end

  # The line mark's vertices per series in chart units: each path's moveto and curve
  # endpoints, offset by the frame group's translation.
  defp svg_vertices(svg) do
    [_, translate] = Regex.run(~r/<g class="frame" transform="translate\(([^)]+)\)"/, svg)
    [dx, dy] = numbers(translate)
    [_, mark] = Regex.run(~r/<g class="mark mark-line"[^>]*>(.*?)<\/g>/s, svg)

    for [_, d] <- Regex.scan(~r/<path[^>]* d="([^"]*)"/, mark) do
      for [_, args] <- Regex.scan(~r/[MLC]([^MLC]*)/, d) do
        [y, x | _] = args |> numbers() |> Enum.reverse()
        {dx + x, dy + y}
      end
    end
  end

  # The curves the canvas stream draws, per series, in canvas pixels: each cubic run's
  # start and endpoints through the translation in force.
  defp canvas_vertices(binary) do
    {_, runs} =
      binary
      |> Base.decode64!()
      |> Decoder.decode()
      |> Enum.reduce({[{0.0, 0.0}], []}, fn
        :save, {[t | _] = stack, runs} ->
          {[t | stack], runs}

        :restore, {[_ | stack], runs} ->
          {stack, runs}

        {:transform, :translate, {x, y}}, {[{tx, ty} | stack], runs} ->
          {[{tx + x, ty + y} | stack], runs}

        {:cubic_run, {x0, y0}, curves}, {[{tx, ty} | _] = stack, runs} ->
          points = [{x0, y0} | Enum.map(curves, fn {_, _, _, _, x, y} -> {x, y} end)]
          {stack, [Enum.map(points, fn {x, y} -> {tx + x, ty + y} end) | runs]}

        _record, acc ->
          acc
      end)

    Enum.reverse(runs)
  end

  defp assert_on(points, vertices, demo) do
    assert length(points) == length(vertices), "#{demo}: one array per drawn series"

    for {series, drawn} <- Enum.zip(points, vertices) do
      assert length(series) == length(drawn), "#{demo}: one point per drawn vertex"

      for {{px, py}, {vx, vy}} <- Enum.zip(series, drawn) do
        assert abs(px - vx) <= 1 and abs(py - vy) <= 1,
               "#{demo}: crosshair point #{inspect({px, py})} is not the drawn vertex #{inspect({vx, vy})}"
      end
    end
  end

  for {width, height} <- @sizes do
    @size {width, height}

    test "at #{width}x#{height} the SVG crosshair's points are the drawn vertices" do
      {tag, rest} = page(@size) |> element("crosshair-svg")
      [svg] = Regex.run(~r/<svg.*?<\/svg>/s, rest)

      assert attr(svg, "viewBox") == "0 0 #{elem(@size, 0)} #{elem(@size, 1)}"
      assert attr(tag, "data-size") == "#{elem(@size, 0)},#{elem(@size, 1)}"
      assert_on(crosshair_points(tag), svg_vertices(svg), "svg")
    end

    test "at #{width}x#{height} the canvas crosshair's points are the drawn vertices" do
      {tag, rest} = page(@size) |> element("crosshair-canvas")
      {canvas, _} = element(rest, "crosshair-canvas-chart")

      # The stream draws at one canvas pixel per chart unit: the canvas is the frame's size.
      assert "#{attr(canvas, "data-width")},#{attr(canvas, "data-height")}" ==
               attr(tag, "data-size")

      assert attr(tag, "data-size") == "#{elem(@size, 0)},#{elem(@size, 1)}"
      assert_on(crosshair_points(tag), canvas_vertices(attr(canvas, "data-binary")), "canvas")
    end
  end

  test "the legend chart's every line, point and entry names one of the three series (#508)" do
    {_tag, rest} = page({720, 380}) |> element("legend-chart")
    [chart] = Regex.run(~r/<svg.*?<\/svg>/s, rest)
    series = ~w(alpha beta gamma)

    circles = Regex.scan(~r/<circle\b[^>]*>/, chart) |> List.flatten()
    named = for c <- circles, [_, s] <- Regex.scan(~r/data-series="([^"]+)"/, c), do: s

    # A point per hour per series, each naming its series.
    assert length(circles) == 24 * 3
    assert Enum.frequencies(named) == Map.new(series, &{&1, 24})

    for s <- series do
      assert chart =~ ~r/<path\b[^>]*data-series="#{s}"/
      assert chart =~ ~s(class="legend-item" data-series="#{s}")
    end
  end

  # Every demo's panel, its heading and the id of the chart it holds (#505); the code
  # section holds its markup in place of a chart.
  @panels [
    {"panel-tooltip", "Tooltip", "tooltip-chart"},
    {"panel-crosshair-svg", "Crosshair over the SVG", "crosshair-svg"},
    {"panel-crosshair-canvas", "Crosshair over the canvas", "crosshair-canvas"},
    {"panel-legend", "Legend toggling", "legend-chart"},
    {"panel-code", "The design and the markup", nil}
  ]

  defp panels(html) do
    for [_, id, body] <-
          Regex.scan(~r/<section id="([^"]+)" class="panel">(.*?)<\/section>/s, html),
        do: {id, body}
  end

  test "each demo is one panel holding its heading, its explanation and its chart (#505)" do
    found = panels(page({720, 380}))

    assert Enum.map(found, &elem(&1, 0)) == Enum.map(@panels, &elem(&1, 0))

    for {{id, body}, {id, heading, chart}} <- Enum.zip(found, @panels) do
      assert body =~ ~s(<h2 class="panel-title">#{heading}</h2>), "#{id}: its heading"
      assert body =~ ~s(<p class="panel-note">), "#{id}: its explanation"

      if chart,
        do: assert(body =~ ~s(<div id="#{chart}"), "#{id}: its chart"),
        else: assert(body =~ ~s(<pre><code class="highlight), "#{id}: its markup")
    end

    # Every chart sits in exactly one panel.
    for {_, _, chart} <- @panels, chart do
      assert Enum.count(found, fn {_, body} -> body =~ ~s(<div id="#{chart}") end) == 1
    end
  end

  for {width, height} <- @sizes do
    @size {width, height}

    test "at #{width}x#{height} every SVG demo's legend sits right of the plot, inside the chart" do
      html = page(@size)
      {crosshair, _} = element(html, "crosshair-svg")
      [left, _top, plot_width, _plot_height] = numbers(attr(crosshair, "data-plot"))

      for id <- ~w(tooltip-chart crosshair-svg legend-chart) do
        {_tag, rest} = element(html, id)
        [svg] = Regex.run(~r/<svg.*?<\/svg>/s, rest)

        [_, translate] =
          Regex.run(~r/<g class="legend"[^>]* transform="translate\(([^)]+)\)"/, svg)

        # The legend group is placed in the frame group's coordinates, the plot's origin.
        [x, _y] = numbers(translate)

        assert x >= plot_width,
               "#{id}: the legend at x #{x} is over the plot (width #{plot_width})"

        # Its estimated width (spec/14 §4.5) ends inside the chart's own width.
        assert left + x + 67.2 <= elem(@size, 0), "#{id}: the legend runs off the chart"
      end
    end
  end
end
