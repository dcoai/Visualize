defmodule Examples.DownsamplingTest do
  @moduledoc """
  The downsampling chart (#448): three frames over one 50,000-row series, whole and
  through `:m4` and `:lttb` bound to the plot's width, each captioned with the count of
  the rows it draws.
  """
  use ExUnit.Case, async: true

  alias Examples.Charts.{Design, Downsampling}
  alias Visualize.Chart
  alias Visualize.Chart.Mark

  setup_all do
    {design, sources} = Downsampling.design([])
    {width, height} = Downsampling.size()

    {:ok, applied} =
      Chart.apply(design, sources: sources, theme: Design.theme([]), size: {width, height})

    %{applied: applied, sources: sources}
  end

  # The rows a frame's line draws, and its caption's count, through the frame's own pipeline.
  defp drawn(applied, name) do
    frame = applied.frames[name]
    [line, caption] = Enum.filter(applied.chart.marks, &(&1.frame == name))
    {frame, Mark.rows(frame, line, applied.sources), Mark.rows(frame, caption, applied.sources)}
  end

  test "the whole frame draws every row and says so", %{applied: applied} do
    {_frame, rows, [caption]} = drawn(applied, :whole)
    assert length(rows) == 50_000
    assert caption.rows == 50_000
  end

  test "the reduced frames bind to the plot width and caption what they draw", %{applied: applied} do
    {frame, m4, [m4_caption]} = drawn(applied, :m4)
    {_frame, lttb, [lttb_caption]} = drawn(applied, :lttb)
    width = ceil(frame.plot.width)

    assert m4_caption.rows == length(m4)
    assert lttb_caption.rows == length(lttb)
    assert length(m4) <= 4 * width * 2 + 1
    assert abs(length(lttb) - width) <= 2
  end

  test "the dropout stays a gap in both reductions", %{applied: applied} do
    for name <- [:m4, :lttb] do
      {_frame, rows, _caption} = drawn(applied, name)
      gaps = Enum.filter(rows, &is_nil(&1.v))
      assert [%{t: 31_000}] = gaps, "#{name} kept #{length(gaps)} gap rows"
    end
  end

  test "the rows are the same on every call" do
    assert Downsampling.design([]) == Downsampling.design([])
  end
end
