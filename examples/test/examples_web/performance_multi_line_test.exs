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
  alias Visualize.Render

  # The page's plot: inside its margin {top: 20, right: 20, bottom: 30, left: 40} of 700 × 400.
  @plot {40, 20, 640, 350}

  defp lines(records), do: for({:path32, points} <- records, do: points)

  defp full(chart) do
    assert [{:full_redraw, {+0.0, +0.0, 700.0, 400.0}, records}] = chart |> MultiLine.full() |> Decoder.decode()
    records
  end

  test "the chart is 48 lines at a whole density over the plot's columns" do
    chart = MultiLine.init(200, @plot)
    assert chart.scroll == Scroll.new(640, 1)
    assert MultiLine.points(chart) == 48 * 641
    assert Enum.all?(chart.data, &(length(&1) == 641))
    assert length(lines(full(chart))) == 48

    dense = MultiLine.init(500_000, @plot)
    assert dense.scroll.samples_per_px == 16
    assert MultiLine.points(dense) == 48 * (16 * 640 + 1)
  end

  test "the ridges sit in the plot: the group at its origin, every column within its width (#298)" do
    chart = MultiLine.init(200, @plot)
    {px, py, w, _h} = @plot
    records = full(chart)
    # The outermost translate is the plot's origin; each ridge's is its offset within.
    assert [{:transform, :translate, {40.0, 20.0}} | _] = Enum.filter(records, &match?({:transform, _, _}, &1))
    assert {px * 1.0, py * 1.0} == {40.0, 20.0}

    for line <- lines(records), {x, _y} <- line do
      assert x >= -1.0e-3 and x <= w + 1.0e-3
    end
  end

  test "the page's ridgeline data element and its hybrid axes share the plot (#298)" do
    alias ExamplesWeb.PerformanceLive, as: Page
    ridges = for _ <- 1..4, do: for(i <- 0..20, do: %{x: i * 5, y: 40.0})
    element = Page.build_ridgeline_data_element(ridges, 700, 400)
    static = Page.render_static_svg_for_hybrid(700, 400, :ridgeline, 200)
    # The ridges' group is at the margin's origin, the axes' group likewise, and the x
    # axis sits at the plot's bottom: the two layers agree on the rectangle.
    assert Render.to_string(element, backend: :svg) =~ ~s|transform="translate(40,20)"| or
             Render.to_string(element, backend: :svg) =~ ~s|translate(40, 20)|
    assert static =~ "translate(40,20)" or static =~ "translate(40, 20)"
    assert static =~ "translate(0,350)" or static =~ "translate(0, 350)"
  end

  test "the next frame is this one translated by the scroll" do
    chart = MultiLine.init(200, @plot)
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

  test "an incremental frame's strip is the full render over its columns, the plot the viewport" do
    chart = MultiLine.init(1400, @plot) |> MultiLine.advance()

    # The viewport is the plot (D-106): the margin's axes are never copied over. The
    # strip is the plot's rightmost column, in canvas pixels.
    assert [{:incremental, :scroll_x, 1.0, +0.0, {40.0, 20.0, 640.0, 350.0}, [{bounds, records}]}] =
             chart |> MultiLine.incremental() |> Decoder.decode()

    assert bounds == {679.0, 20.0, 1.0, 350.0}
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
