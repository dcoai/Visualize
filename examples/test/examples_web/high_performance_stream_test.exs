defmodule ExamplesWeb.HighPerformanceStreamTest do
  @moduledoc """
  The High-Performance page's streams decoded under test (#270): the full redraw and an
  incremental frame, built by the page's own functions, run through the library's
  reference decoder — so a stream the browser cannot draw fails here and not as a blank
  canvas — and the scroll contract of spec/09 §5.3 held (#292): a frame is the previous
  one translated by the scroll, and a strip is the full render over its columns.
  """
  use ExUnit.Case, async: true

  alias Examples.Scroll
  alias ExamplesWeb.HighPerformanceLive, as: Page
  alias Visualize.Backend.CanvasIncremental
  alias Visualize.Backend.CanvasBinary.Decoder
  alias Visualize.Scale

  # The page's frame is 900 by 500 with the plot at (60, 40), 810 by 410.
  @margin {60, 40}
  @inner {810, 410}
  @scroll 5

  # The page's own assigns as mount/3 makes them at a density, with a random line that
  # is not random so two frames can be compared.
  defp assigns(samples_per_px) do
    y = Scale.Linear.new() |> Scale.Linear.domain([-100, 100]) |> Scale.Linear.range([410, 0])

    %Phoenix.LiveView.Socket{}
    |> Phoenix.Component.assign(y_scale: y, run: Examples.Run.new(data_rate: 600))
    |> Page.at_density(samples_per_px)
    |> Map.fetch!(:assigns)
    |> then(&%{&1 | random_data: Enum.map(1..&1.points_per_series, fn i -> rem(i, 7) * 10.0 end)})
  end

  # The frame after `assigns`: the window on by the scroll, the random line too.
  defp scrolled(assigns) do
    scroll = Scroll.advance(assigns.scroll, @scroll)
    %{assigns | scroll: scroll, random_data: Scroll.shift(scroll, assigns.random_data, @scroll, fn _ -> 5.0 end)}
  end

  defp full(assigns) do
    assert [{:full_redraw, {+0.0, +0.0, 900.0, 500.0}, records}] =
             assigns
             |> Page.build_chart_element()
             |> CanvasIncremental.encode_full_redraw({900, 500})
             |> Decoder.decode()

    records
  end

  defp lines(records), do: for({:path32, points} <- records, do: points)

  test "the full redraw decodes to the five series' paths" do
    records = full(assigns(2))
    kinds = records |> Enum.map(&if(is_tuple(&1), do: elem(&1, 0), else: &1)) |> Enum.frequencies()
    # The area as one cubic path, the four lines as f32 polylines, each styled and stroked,
    # the area filled, all inside one save/translate/restore.
    assert kinds[:path_cubic32] == 1
    assert kinds[:path32] == 4
    assert kinds[:style] == 5 and kinds[:stroke] == 5 and kinds[:fill] == 1
    assert kinds[:save] == 1 and kinds[:restore] == 1 and kinds[:transform] == 1
    # One point per sample: two per pixel column and one more.
    assert Enum.all?(lines(records), &(length(&1) == 2 * 810 + 1))
  end

  test "a density is a whole number of samples per pixel, and follows the data rate (#308)" do
    for d <- [1, 2, 5, 12] do
      a = assigns(d)
      assert a.points_per_series == d * 810 + 1
      assert a.total_points == a.points_per_series * 5
      assert Scroll.samples(a.scroll, @scroll) == @scroll * d
      # A sample is exactly 1/d pixels: the scroll's samples are the scroll's pixels.
      assert_in_delta Scale.Linear.apply(a.x_scale, @scroll * d), @scroll, 1.0e-9
    end

    # About five seconds of data across 810 columns: 600/s is four per pixel (3000/810 =
    # 3.7), 10/s the one-per-pixel floor, 5,000/s thirty-one.
    assert Page.density_for(600) == 4
    assert Page.density_for(10) == 1
    assert Page.density_for(5000) == 31
    a = assigns(4)
    assert_in_delta Page.span(a), 3241 / 600, 1.0e-9
  end

  test "the next frame is this one translated by the scroll (spec/09 §5.3)" do
    a = assigns(2)
    step = Scroll.samples(a.scroll, @scroll)
    before = lines(full(a))
    after_ = lines(full(scrolled(a)))

    for {was, now} <- Enum.zip(before, after_) do
      # Every point that stays on the canvas keeps its y and moves left by the scroll.
      for {{x1, y1}, {x0, y0}} <- Enum.zip(now, Enum.drop(was, step)) do
        assert_in_delta x1, x0 - @scroll, 1.0e-3
        assert_in_delta y1, y0, 1.0e-3
      end
    end
  end

  test "an incremental frame decodes to its exposed region, the full render over its columns" do
    a = assigns(2) |> scrolled()
    {mx, my} = @margin
    regions = CanvasIncremental.exposed_regions({@scroll * 1.0, 0}, @inner)
    adjusted = Enum.map(regions, fn {rx, ry, rw, rh} -> {mx + rx, my + ry, rw, rh} end)
    elements = Enum.map(adjusted, fn bounds -> {bounds, Page.build_region_element(a, bounds)} end)
    {iw, ih} = @inner
    plot = {mx, my, iw, ih}
    binary = CanvasIncremental.encode_incremental({@scroll * 1.0, 0}, {900, 500}, elements, viewport: plot)
    # The plot is what scrolls: the margin, and the y axis in it, is outside the viewport (#294).
    assert [{:incremental, :scroll_x, dx, +0.0, {60.0, 40.0, 810.0, 410.0}, [region]}] = Decoder.decode(binary)
    assert dx == @scroll * 1.0

    # The strip's lines are the full render's points at the same columns: the same x, the
    # same y, for every point the strip carries.
    {_bounds, records} = region
    whole = lines(full(a))

    for {strip, line} <- Enum.zip(lines(records), whole) do
      assert length(strip) > 1
      by_x = Map.new(line)

      for {x, y} <- strip do
        assert_in_delta y, Map.fetch!(by_x, x), 1.0e-3
      end
    end
  end
end
