defmodule Examples.Charts.ScrollingSeriesTest do
  @moduledoc """
  The High-Performance chart as a design (#327): every series a function of its absolute
  sample, the window `Examples.Scroll`'s, and the compiled chart scrolling by exactly the
  columns the window moved — the copy-shift contract of spec/09 §5.3 through the
  library's own path (spec/14 §12.5), with a strip a fraction of the full redraw (D-108).
  """
  use ExUnit.Case, async: true

  alias Examples.Charts.{Design, ScrollingSeries}
  alias Examples.{Frames, Scroll}
  alias Visualize.Backend.CanvasBinary.Decoder
  alias Visualize.Chart.Compiled

  test "the design streams: a viewport on x spanning the window, five sources, a value per absolute sample" do
    assert ScrollingSeries.stream?()
    assert Frames.backends(ScrollingSeries) == [:svg, :canvas, :incremental]
    assert ScrollingSeries.plot() == {60, 40, 810, 410}

    {design, rows} = ScrollingSeries.design(samples_per_px: 2, origin: 100)
    assert design.frames.main.viewport == %{scale: :x, span: 1620}
    assert Map.keys(rows) |> Enum.sort() == [:area, :line_1, :line_2, :line_3, :line_4]
    assert length(rows.area) == 1621
    assert hd(rows.area).t == 100 and List.last(rows.area).t == 1720

    # A value is a function of t and the window's count alone: the same at any origin.
    {_, later} = ScrollingSeries.design(samples_per_px: 2, origin: 300)
    assert Enum.at(rows.line_1, 250) == Enum.at(later.line_1, 50)
    assert Enum.at(rows.area, 250) == Enum.at(later.area, 50)
  end

  test "the area is a volume under the curve, closing on the plot's bottom corners (#419)" do
    {design, rows} = ScrollingSeries.design(samples_per_px: 8)
    {:ok, chart} = Visualize.Chart.from_map(design)

    {:ok, applied} =
      Visualize.Chart.apply(chart,
        sources: rows,
        theme: Design.theme([]),
        size: Design.size(ScrollingSeries, [])
      )

    {_x, _y, width, height} = ScrollingSeries.plot()

    [path] =
      Regex.run(~r/<path d="(M[^"]+)"/U, Visualize.Chart.render(applied), capture: :all_but_first)

    points =
      for [_, x, y] <- Regex.scan(~r/[ML](-?[\d.]+),(-?[\d.]+)/, path),
          do: {elem(Float.parse(x), 0), elem(Float.parse(y), 0)}

    # The volume reaches the floor and never goes below it: the baseline is the domain's
    # own end, not data zero — which on [-100, 100] would be half way up the plot.
    assert Enum.max(Enum.map(points, &elem(&1, 1))) == height
    refute Enum.any?(points, fn {_x, y} -> y > height end)

    # It returns along the floor from the bottom-right corner to the bottom-left.
    assert List.last(points) == {0.0, height * 1.0}
    assert Enum.any?(points, &(&1 == {width * 1.0, height * 1.0}))
  end

  test "the compiled chart scrolls by exactly the columns the window moved, with the strip a fraction of the full redraw" do
    opts = [samples_per_px: 2, origin: 0]
    state = Frames.prepare(ScrollingSeries, opts, :incremental)

    assert %{
             compiled: %Compiled{},
             plot: %{width: 810, height: 410},
             margin: %{left: 60, top: 40}
           } = state

    scroll = ScrollingSeries.scroll(opts)
    count = Scroll.count(scroll)
    {first, state} = Frames.frame(ScrollingSeries, opts ++ [now: count - 1], :incremental, state)
    assert first.incremental.mode == "full" and first.points == 5 * count

    # Twelve columns at two per pixel: the window on by 24 samples.
    scroll = Scroll.advance(scroll, 12)
    opts2 = [samples_per_px: 2, origin: scroll.origin, now: scroll.origin + count - 1]
    {second, _state} = Frames.frame(ScrollingSeries, opts2, :incremental, state)
    assert %{mode: "scroll_x", dx: 12} = second.incremental
    assert second.bytes < first.bytes / 8

    # The strip decodes to the plot's rightmost 12 px with five series in it.
    [{:incremental, :scroll_x, 12.0, +0.0, {+0.0, +0.0, 810.0, 410.0}, [{bounds, records}]}] =
      second.incremental.binary |> Base.decode64!() |> Decoder.decode()

    assert bounds == {798.0, 0.0, 12.0, 410.0}
    assert length(for({:path32, _} <- records, do: 1)) == 4
    assert length(for({:path_cubic32, _} <- records, do: 1)) == 1
  end

  test "the window slides: rows/3 gives the rows rows/1 would build, per series (#408)" do
    scroll = ScrollingSeries.scroll(samples_per_px: 2, origin: 0)
    held = ScrollingSeries.rows(scroll)

    for px <- [1, 4, 30] do
      advanced = Scroll.advance(scroll, px)
      assert ScrollingSeries.rows(advanced, px, held) == ScrollingSeries.rows(advanced)
    end

    {slid, final} =
      Enum.reduce(1..8, {held, scroll}, fn _, {rows, sc} ->
        advanced = Scroll.advance(sc, 5)
        {ScrollingSeries.rows(advanced, 5, rows), advanced}
      end)

    assert slid == ScrollingSeries.rows(final)
    assert Map.keys(slid) |> Enum.sort() == [:area, :line_1, :line_2, :line_3, :line_4]
    assert ScrollingSeries.rows(final, 5, nil) == ScrollingSeries.rows(final)
  end

  test "the SVG and Canvas backends draw the window whole, as any design's" do
    {frame, _} = Frames.frame(ScrollingSeries, [samples_per_px: 1], :svg, nil)
    assert frame.svg =~ "<svg" and frame.points == 5 * 811
    assert Design.design?(ScrollingSeries)
  end
end
