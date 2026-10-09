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

  # -- during a run (#490) ---------------------------------------------------------------

  # A run scrolls the window 250 rows a tick (`rows/1`); each tick is applied afresh, as the
  # gallery's run applies `design(animation_tick: tick)`.
  @ticks [0, 60, 120]

  defp at_tick(tick), do: Design.applied(Downsampling, animation_tick: tick)

  # The x of every point the line's paths draw, in plot pixels, in drawing order.
  defp path_xs(applied, name) do
    frame = applied.frames[name]
    [line, _caption] = Enum.filter(applied.chart.marks, &(&1.frame == name))

    frame
    |> Mark.generate(line, sources: applied.sources)
    |> Map.fetch!(:children)
    |> Enum.filter(&(&1.type == :path))
    |> Enum.flat_map(& &1.path.commands)
    |> Enum.flat_map(fn
      {op, x, _y} when op in [:M, :L] -> [x]
      _other -> []
    end)
  end

  test "during a run every frame's x domain is the series' own extent and its line spans the plot" do
    for tick <- @ticks, name <- [:whole, :m4, :lttb] do
      applied = at_tick(tick)
      frame = applied.frames[name]
      first = tick * 250

      assert frame.scales.x.domain == [first, first + 49_999],
             "tick #{tick}, #{name}: x domain #{inspect(frame.scales.x.domain)}"

      xs = path_xs(applied, name)
      assert hd(xs) == 0.0, "tick #{tick}, #{name}: the line starts at #{hd(xs)} px"
      assert Enum.min(xs) == 0.0
      assert_in_delta Enum.max(xs), frame.plot.width, 1.0e-9
    end
  end

  test "the caption still counts what its frame draws during a run" do
    for tick <- @ticks, name <- [:whole, :m4, :lttb] do
      {_frame, rows, [caption]} = drawn(at_tick(tick), name)
      assert caption.rows == length(rows), "tick #{tick}, #{name}"
    end
  end

  # spec/14 §5.4.1: under an inferred, not-nice x domain the m4 columns are the plot's pixel
  # columns, so per pixel column the reduced line keeps at most four rows and the whole
  # line's lowest and highest readings. A domain held open by a constant breaks both.
  test "m4 keeps its per-pixel-column guarantee during a run" do
    for tick <- @ticks do
      applied = at_tick(tick)
      {frame, m4, _caption} = drawn(applied, :m4)
      {_frame, whole, _caption} = drawn(applied, :whole)
      width = trunc(frame.plot.width)
      column = fn %{t: t} -> min(width - 1, floor(Visualize.Scale.apply(frame.scales.x, t))) end

      extremes = fn rows ->
        rows
        |> Enum.reject(&is_nil(&1.v))
        |> Enum.group_by(column, & &1.v)
        |> Map.new(fn {c, vs} -> {c, Enum.min_max(vs)} end)
      end

      per_column = Enum.frequencies_by(Enum.reject(m4, &is_nil(&1.v)), column)
      assert Enum.max(Map.values(per_column)) <= 4, "tick #{tick}: a column kept more than four"
      assert extremes.(m4) == extremes.(whole), "tick #{tick}: a column's extremes differ"
    end
  end

  test "the rows are the same on every call" do
    assert Downsampling.design([]) == Downsampling.design([])
  end
end
