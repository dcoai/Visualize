defmodule ExamplesWeb.PerformanceMultiLineTest do
  @moduledoc """
  The performance page's Multi-Line chart keeps the scroll contract (spec/09 §5.3, #296):
  the next frame's decoded ridges are this frame's moved left by the scroll, and a strip's
  points are the full render's at the same columns.
  """
  use ExUnit.Case, async: true

  alias Examples.Scroll
  alias ExamplesWeb.PerformanceLive.MultiLine
  alias Visualize.Backend.CanvasBinary.Decoder

  defp lines(records), do: for({:path32, points} <- records, do: points)

  defp full(chart) do
    assert [{:full_redraw, {+0.0, +0.0, 700.0, 400.0}, records}] = chart |> MultiLine.full() |> Decoder.decode()
    records
  end

  test "the chart is 48 lines at a whole density, one sample per column at the default" do
    chart = MultiLine.init(200)
    assert chart.scroll == Scroll.new(700, 1)
    assert MultiLine.points(chart) == 48 * 701
    assert Enum.all?(chart.data, &(length(&1) == 701))
    assert length(lines(full(chart))) == 48

    dense = MultiLine.init(500_000)
    assert dense.scroll.samples_per_px == 15
    assert MultiLine.points(dense) == 48 * (15 * 700 + 1)
  end

  test "the next frame is this one translated by the scroll" do
    chart = MultiLine.init(200)
    before = lines(full(chart))
    next = MultiLine.advance(chart)
    assert next.scroll.origin == 1
    after_ = lines(full(next))

    for {was, now} <- Enum.zip(before, after_) do
      for {{x1, y1}, {x0, y0}} <- Enum.zip(now, Enum.drop(was, Scroll.samples(chart.scroll, 1))) do
        assert_in_delta x1, x0 - MultiLine.px_per_frame(), 1.0e-3
        assert_in_delta y1, y0, 1.0e-3
      end
    end
  end

  test "an incremental frame's strip is the full render over its columns, the canvas the viewport" do
    chart = MultiLine.init(1400) |> MultiLine.advance()

    assert [{:incremental, :scroll_x, 1.0, +0.0, {+0.0, +0.0, 700.0, 400.0}, [{bounds, records}]}] =
             chart |> MultiLine.incremental() |> Decoder.decode()

    assert bounds == {699.0, 0.0, 1.0, 400.0}
    whole = lines(full(chart))
    strips = lines(records)
    assert length(strips) == 48

    for {strip, line} <- Enum.zip(strips, whole) do
      assert length(strip) > 1
      by_x = Map.new(line)

      for {x, y} <- strip do
        assert_in_delta y, Map.fetch!(by_x, x), 1.0e-3
      end
    end
  end
end
