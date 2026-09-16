defmodule ExamplesWeb.HighPerformanceStreamTest do
  @moduledoc """
  The High-Performance page's streams decoded under test (#270): the full redraw and an
  incremental frame, built by the page's own functions, run through the reference
  decoder of `test/support` — so a stream the browser cannot draw fails here and not as
  a blank canvas.
  """
  use ExUnit.Case, async: true

  alias ExamplesWeb.HighPerformanceLive, as: Page
  alias Visualize.Backend.CanvasIncremental
  alias Visualize.Backend.CanvasBinary.Decoder
  alias Visualize.Scale

  # The page's own assigns as mount/3 makes them, for a frame.
  defp assigns(frame) do
    points = div(1000, 5)

    x = Scale.Linear.new() |> Scale.Linear.domain([0, points - 1]) |> Scale.Linear.range([0, 640])
    y = Scale.Linear.new() |> Scale.Linear.domain([-100, 100]) |> Scale.Linear.range([340, 0])

    %{
      frame: frame,
      points_per_series: points,
      x_scale: x,
      y_scale: y,
      random_data: for(_ <- 1..points, do: 50.0)
    }
  end

  test "the full redraw decodes to the five series' paths" do
    element = Page.build_chart_element(assigns(0))
    binary = CanvasIncremental.encode_full_redraw(element)
    assert [{:full_redraw, records}] = Decoder.decode(binary)
    kinds = records |> Enum.map(&if(is_tuple(&1), do: elem(&1, 0), else: &1)) |> Enum.frequencies()
    # The area as one cubic path, the four lines as f32 polylines, each styled and stroked,
    # the area filled, all inside one save/translate/restore.
    assert kinds[:path_cubic32] == 1
    assert kinds[:path32] == 4
    assert kinds[:style] == 5 and kinds[:stroke] == 5 and kinds[:fill] == 1
    assert kinds[:save] == 1 and kinds[:restore] == 1 and kinds[:transform] == 1
  end

  test "an incremental frame decodes to its exposed region" do
    a = assigns(3)
    regions = CanvasIncremental.exposed_regions({2.0, 0}, {640, 340})
    adjusted = Enum.map(regions, fn {rx, ry, rw, rh} -> {60 + rx, 20 + ry, rw, rh} end)
    elements = Enum.map(adjusted, fn bounds -> {bounds, Page.build_region_element(a, bounds)} end)
    binary = CanvasIncremental.encode_incremental({2.0, 0}, {700, 400}, elements)
    assert [{:incremental, _mode, dx, 0.0, decoded}] = Decoder.decode(binary)
    assert dx == 2.0
    assert length(decoded) == length(adjusted)
  end
end
