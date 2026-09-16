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
    |> Phoenix.Component.assign(y_scale: y, frame: 0)
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

  test "a density is a whole number of samples per pixel and the select's totals are its" do
    for d <- [1, 2, 5, 12] do
      a = assigns(d)
      assert a.points_per_series == d * 810 + 1
      assert a.total_points == a.points_per_series * 5
      assert Page.total_at(d) == a.total_points
      assert Scroll.samples(a.scroll, @scroll) == @scroll * d
      # A sample is exactly 1/d pixels: the scroll's samples are the scroll's pixels.
      assert_in_delta Scale.Linear.apply(a.x_scale, @scroll * d), @scroll, 1.0e-9
    end
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
  test "samples arrive by the clock and a frame scrolls by the whole columns they fill (#300)" do
    a = assigns(2) |> Map.merge(%{data_rate: 600, pending: 0, carry: 0.0})

    # 600 samples/s for 16 ms is 9.6 samples: 9 arrive, 0.6 carries; at two per column that is
    # four columns with one sample pending.
    assert {4, 9, %{pending: 1, carry: carry}} = Page.arrivals(a, 16)
    assert_in_delta carry, 0.6, 1.0e-9

    # The next tick adds its samples to the pending one and the carry: 0.6 + 9.6 = 10.2 →
    # 10 arrive, 11 pending → five columns, one pending, 0.2 carried.
    assert {5, 10, %{pending: 1, carry: carry}} = Page.arrivals(%{a | pending: 1, carry: carry}, 16)
    assert_in_delta carry, 0.2, 1.0e-9

    # A slow rate fills no column on most ticks: the frame draws nothing, and nothing is lost.
    slow = %{a | data_rate: 60}
    assert {0, 0, %{pending: 0, carry: c1}} = Page.arrivals(slow, 16)
    assert_in_delta c1, 0.96, 1.0e-9
    assert {0, 1, %{pending: 1, carry: c2}} = Page.arrivals(%{slow | carry: c1}, 16)
    assert_in_delta c2, 0.92, 1.0e-9

    # The columns a tick yields are what the frame scrolls by: whole pixels, whole samples.
    scroll = Scroll.advance(a.scroll, 4)
    assert scroll.origin == 8
    assert length(Scroll.shift(scroll, a.random_data, 4, fn _ -> 0.0 end)) == a.points_per_series
  end
  test "ticks follow a deadline: a 600 fps target alternates 1 and 2 ms and averages its period (#302)" do
    # Each tick fires when its delay elapses; the deadline advances by the period, not by
    # the delay, so rounding never accumulates.
    {delays, _} =
      Enum.map_reduce(1..6, {0, 0}, fn _, {due, now} ->
        {next, delay} = Page.deadline(due, now, 600)
        {delay, {next, now + delay * 1000}}
      end)

    assert delays == [2, 1, 2, 2, 1, 2]
    assert Enum.sum(delays) * 1000 == 6 * 1_000_000 / 600 * 1.0 |> round()

    # 500 fps is whole milliseconds; a late tick is due now, not caught up in a burst.
    assert {2000.0, 2} = Page.deadline(0, 0, 500)
    assert {9_000, 0} = Page.deadline(0, 9_000, 500)
  end
end
