defmodule Examples.DonutChartTest do
  @moduledoc """
  #487: the Donut is visible. Its slices are filled by category, the values its colour
  scale's domain holds, so SVG and canvas both draw five coloured slices; and its ring is
  sized from the plot area its legend's margin leaves, so no slice reaches past the plot.
  """
  use ExUnit.Case, async: true

  alias Examples.Charts.{Design, DonutChart}
  alias Visualize.Backend.CanvasBinary.Decoder

  @legend_width 120

  defp arcs(svg) do
    [group] =
      Regex.run(~r/<g class="mark mark-arc"[^>]*>(.*?)<\/g>/s, svg, capture: :all_but_first)

    Regex.scan(~r/<path d="([^"]+)" fill="([^"]+)"/, group, capture: :all_but_first)
  end

  test "SVG draws five slices, each in its own series colour" do
    fills = DonutChart.render() |> arcs() |> Enum.map(fn [_d, fill] -> fill end)

    assert fills ==
             for(
               i <- 1..5,
               do: Visualize.Theme.resolve(Visualize.Theme.default(), {:series, i}, :css)
             )
  end

  test "the canvas draws five slices, each filled in its own colour" do
    records = Decoder.decode(Base.decode64!(Design.canvas(DonutChart, [])))

    # The arc mark's records — one style with a fill, then the path and its fill, per
    # slice — and not the legend's swatches, which are rects.
    fills =
      records
      |> Enum.chunk_every(3, 1, :discard)
      |> Enum.flat_map(fn
        [{:style, %{fill: {_, _, _, 255} = fill}}, {kind, _}, :fill] when kind != :rects -> [fill]
        _other -> []
      end)

    assert length(Enum.uniq(fills)) == 5, inspect(records, limit: :infinity)
  end

  # The ring's centre is the polar group's translate; every slice's points lie within the
  # outer radius of it, and the circle of that radius lies within the plot area — the box
  # less the legend's margin.
  for {width, height} <- [{400, 400}, {320, 220}, {600, 300}] do
    test "the ring lies inside the plot at #{width} x #{height}" do
      {width, height} = {unquote(width), unquote(height)}
      svg = DonutChart.render(width: width, height: height)

      [cx, cy] =
        Regex.run(~r/<g class="polar" transform="translate\(([-\d.]+),([-\d.]+)\)"/, svg,
          capture: :all_but_first
        )

      {cx, cy} = {number(cx), number(cy)}

      radius =
        svg
        |> arcs()
        |> Enum.flat_map(fn [d, _fill] -> points(d) end)
        |> Enum.map(fn {x, y} -> :math.sqrt(x * x + y * y) end)
        |> Enum.max()

      plot_width = width - @legend_width

      assert cx - radius >= 0 and cx + radius <= plot_width,
             "x: #{cx} ± #{radius} in #{plot_width}"

      assert cy - radius >= 0 and cy + radius <= height, "y: #{cy} ± #{radius} in #{height}"
    end
  end

  # The end points of a path's commands, in the group's own coordinates: `M x,y`, `L x,y`
  # and the end of `A rx,ry,rot,large,sweep,x,y`.
  defp points(d) do
    ~r/([MLA])([^MLAZ]+)/
    |> Regex.scan(d, capture: :all_but_first)
    |> Enum.map(fn [_command, args] ->
      [x, y] = args |> String.split(",") |> Enum.map(&number/1) |> Enum.take(-2)
      {x, y}
    end)
  end

  defp number(text) do
    {n, ""} = Float.parse(text)
    n
  end
end
