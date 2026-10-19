defmodule Examples.ScatterPlotTest do
  @moduledoc """
  The scatter plot's Voronoi cells and Delaunay hull (spec/14 §5.4.4): laid in pixels over
  the columns the chart places through its axes' own mapping, so every point lies in the
  hull and each cell holds its own point.
  """
  use ExUnit.Case, async: true

  alias Examples.Charts.ScatterPlot

  @points (for i <- 0..19 do
             %{x: 5 + rem(i * 37, 90), y: 5 + rem(i * 53, 90), size: 10, category: "A"}
           end)

  test "behind the points: a cell per point and the hull of their triangulation" do
    svg = ScatterPlot.render(data: @points)

    [cells, hull] =
      Regex.scan(~r/<g class="mark mark-path"[^>]*>(.*?)<\/g>/s, svg, capture: :all_but_first)

    assert length(Regex.scan(~r/<path d="M/, hd(cells))) == length(@points)
    assert [_one] = Regex.scan(~r/<path d="M/, hd(hull))
    assert svg =~ ~s(stroke-dasharray="4 3")
    assert length(Regex.scan(~r/<circle /, svg)) == length(@points)
  end

  test "the pixel columns are the axes' mapping of 0..100 onto the plot" do
    {_design, %{points: [row | _]}} = ScatterPlot.design(data: @points)
    # 600 x 400 less the margins: a 530 x 340 plot, y running down.
    assert_in_delta row.px, row.x / 100 * 530, 1.0e-9
    assert_in_delta row.py, 340 - row.y / 100 * 340, 1.0e-9
  end
end
