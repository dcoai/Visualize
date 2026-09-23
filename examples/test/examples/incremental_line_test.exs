defmodule Examples.Charts.IncrementalLineTest do
  @moduledoc """
  The incremental demo's chart as a design (#402): one line whose value is a function of
  its absolute sample, the window `Examples.Scroll`'s, and the compiled chart scrolling by
  exactly the columns the window moved — the copy-shift contract of spec/09 §5.3 through
  the library's own path (spec/14 §12.5).
  """
  use ExUnit.Case, async: true

  alias Examples.Charts.{Design, IncrementalLine}
  alias Examples.{Frames, Scroll}
  alias Visualize.Backend.CanvasBinary.Decoder
  alias Visualize.Chart.Compiled

  test "the design streams: a viewport on x spanning the window, one source, a value per absolute sample" do
    assert Design.design?(IncrementalLine)
    assert IncrementalLine.stream?()
    assert Frames.backends(IncrementalLine) == [:svg, :canvas, :incremental]
    assert IncrementalLine.plot() == {40, 20, 740, 450}

    {design, rows} = IncrementalLine.design(samples_per_px: 2, origin: 100)
    assert design.frame.viewport == %{scale: :x, span: 1480}
    assert Map.keys(rows) == [:signal]
    assert length(rows.signal) == 1481
    assert hd(rows.signal).t == 100 and List.last(rows.signal).t == 1580

    # A value is a function of t alone: the same row at any origin, which is what lets a
    # strip drawn fresh agree with the pixels a scroll copied.
    {_, later} = IncrementalLine.design(samples_per_px: 2, origin: 300)
    assert Enum.at(rows.signal, 250) == Enum.at(later.signal, 50)
    assert IncrementalLine.value(7) == IncrementalLine.value(7)
  end

  test "the compiled chart scrolls by exactly the columns the window moved, the strip a fraction of the full redraw" do
    opts = [samples_per_px: 2, origin: 0]
    state = Frames.prepare(IncrementalLine, opts, :incremental)

    assert %{
             compiled: %Compiled{},
             plot: %{width: 740, height: 450},
             margin: %{left: 40, top: 20}
           } = state

    scroll = IncrementalLine.scroll(opts)
    count = Scroll.count(scroll)
    {first, state} = Frames.frame(IncrementalLine, opts ++ [now: count - 1], :incremental, state)
    assert first.incremental.mode == "full" and first.points == count

    # Ten columns at two samples per pixel: the window on by 20 samples.
    scroll = Scroll.advance(scroll, 10)
    opts2 = [samples_per_px: 2, origin: scroll.origin, now: scroll.origin + count - 1]
    {second, _state} = Frames.frame(IncrementalLine, opts2, :incremental, state)
    assert %{mode: "scroll_x", dx: 10} = second.incremental
    assert second.bytes < first.bytes / 8

    # The strip decodes to the plot's rightmost 10 px with the line in it.
    [{:incremental, :scroll_x, 10.0, +0.0, {+0.0, +0.0, 740.0, 450.0}, [{bounds, records}]}] =
      second.incremental.binary |> Base.decode64!() |> Decoder.decode()

    assert bounds == {730.0, 0.0, 10.0, 450.0}
    # The monotone line decodes as one cubic run, stroked: the strip is the line alone.
    kinds = Enum.map(records, fn r -> if(is_tuple(r), do: elem(r, 0), else: r) end)
    assert :cubic_run in kinds and :stroke in kinds
    assert Enum.count(kinds, &(&1 == :cubic_run)) == 1
  end

  test "the window slides: rows/3 gives the rows rows/1 would build, without rebuilding them (#408)" do
    scroll = IncrementalLine.scroll(samples_per_px: 4, origin: 0)
    held = IncrementalLine.rows(scroll)

    for px <- [1, 3, 25] do
      advanced = Scroll.advance(scroll, px)
      assert IncrementalLine.rows(advanced, px, held) == IncrementalLine.rows(advanced)
    end

    # Slid frame by frame, it stays the window rows/1 builds.
    {slid, final} =
      Enum.reduce(1..12, {held, scroll}, fn _, {rows, sc} ->
        advanced = Scroll.advance(sc, 3)
        {IncrementalLine.rows(advanced, 3, rows), advanced}
      end)

    assert slid == IncrementalLine.rows(final)
    assert length(slid.signal) == Scroll.count(final)
    # With nothing held, the whole window is built.
    assert IncrementalLine.rows(final, 3, nil) == IncrementalLine.rows(final)
  end

  test "a design takes the rows a caller holds (#408)" do
    scroll = IncrementalLine.scroll(samples_per_px: 2, origin: 40)
    rows = IncrementalLine.rows(scroll)
    opts = [samples_per_px: 2, origin: 40]
    assert {design, ^rows} = IncrementalLine.design(opts ++ [rows: rows])
    assert {^design, ^rows} = IncrementalLine.design(opts)
  end

  test "the SVG and Canvas backends draw the window whole, as any design's" do
    {frame, _} = Frames.frame(IncrementalLine, [samples_per_px: 1], :svg, nil)
    assert frame.svg =~ "<svg" and frame.points == 741

    state = Frames.prepare(IncrementalLine, [samples_per_px: 1], :canvas)
    {canvas, _} = Frames.frame(IncrementalLine, [samples_per_px: 1], :canvas, state)
    assert is_binary(canvas.canvas) and canvas.svg == nil
    assert Frames.static(state) =~ "<svg"
  end
end
