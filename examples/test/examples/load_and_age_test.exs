defmodule Examples.LoadAndAgeTest do
  @moduledoc """
  *Load + age* (#493): the recent history and its dial over the long log-age view, one
  design of three frames — one load axis, one clock, the two source charts' own pieces,
  and a run on canvas of one plot per frame.

  The general guards — validity, the round trip, the golden, the colour profiles — are
  `Examples.ChartsTest`'s and apply to this chart like any other.
  """
  use ExUnit.Case, async: true

  alias Examples.Charts.{ContextChart, Design, Load, LoadAge, LoadAndAge, LoadChart}
  alias Examples.{Compare, Frames, Gallery}
  alias Visualize.Chart

  defp applied(opts), do: Design.applied(LoadAndAge, opts)

  test "the design validates and applies, three frames stacked on a grid of two rows" do
    {design, sources} = LoadAndAge.design([])
    assert {:ok, chart} = Chart.from_map(design)
    assert {:ok, applied} = Chart.apply(chart, sources: sources, theme: Design.theme([]))

    assert applied.frames |> Map.keys() |> Enum.sort() == [:age, :history, :now]
    assert design.frames.history.cell == [0, 0]
    assert design.frames.age.cell == [0, 1]
    assert applied.frames.now.z == 1

    # The history over the age view, each the full width, and the dial in the history's
    # top-right corner.
    [+0.0, +0.0, 1.0, top] = applied.frames.history.box
    [+0.0, below, 1.0, bottom] = applied.frames.age.box
    assert top == bottom and below > top
    assert applied.frames.history.plot.width == applied.frames.age.plot.width
    [x, y, w, h] = applied.frames.now.box
    assert x > 0.5 and y + h < 0.5 and w > 0
  end

  describe "one clock" do
    test "both views show the same instant at every tick" do
      for tick <- [0, 1, 37, 400] do
        {_design, sources} = LoadAndAge.design(animation_tick: tick)
        now = LoadAndAge.now(animation_tick: tick)
        assert now == tick * 3 + LoadAge.oldest()

        # The history's newest row is `now`, and the dial reads that row.
        newest = List.last(sources.load)
        assert LoadChart.second_of(newest) == now
        assert newest.v == Float.round(Load.at(:one, now), 2)

        # The age view's rows are measured back from the same `now`.
        assert sources.loads == LoadAge.sources(now).loads
      end
    end

    test "the age view's newest one-minute point is the reading five seconds before now" do
      {_design, sources} = LoadAndAge.design(animation_tick: 5)
      now = LoadAndAge.now(animation_tick: 5)
      newest = Enum.min(LoadAge.ages())

      [%{load: load}] =
        for %{window: "1 min", age: ^newest} = row <- sources.loads, do: row

      assert load == Load.at(:one, now - 5)
    end
  end

  test "the history's and the age view's y axes are one scale: one domain, one set of ticks" do
    {design, _sources} = LoadAndAge.design([])
    assert design.frames.age.scales.y == {:frame, :history, :y}

    for tick <- [0, 400] do
      frames = applied(animation_tick: tick).frames
      history = frames.history.scales.y
      age = frames.age.scales.y

      assert history.domain == [0, 4]
      assert age.domain == history.domain
      assert Visualize.Scale.ticks(age, 4) == Visualize.Scale.ticks(history, 4)

      # The range stays each frame's own pixels: its plot's height, floor to ceiling.
      assert age.range == [frames.age.plot.height, 0]
      assert history.range == [frames.history.plot.height, 0]
    end
  end

  test "the pieces are the two charts' own, so the three cannot drift" do
    {combined, _} = LoadAndAge.design([])
    {load, _} = LoadChart.design([])
    {age, _} = LoadAge.design([])

    # Load's history and dial marks, as Load draws them.
    for frame <- [:history, :now] do
      assert Enum.filter(combined.marks, &(&1[:frame] == frame)) ==
               Enum.filter(load.marks, &(&1[:frame] == frame))
    end

    # Load age's line, in the `age` frame and in its renamed style.
    [line] = Enum.filter(combined.marks, &(&1[:frame] == :age))
    [own] = age.marks
    assert Map.drop(line, [:frame, :style]) == Map.drop(own, [:frame, :style])
    assert {own.style, line.style} == {:trace, :age_trace}

    # The renamed style is the age view's `:trace`, and Load's `:trace` is untouched.
    assert combined.styles.age_trace == age.styles.trace
    assert combined.styles.trace == load.styles.trace

    assert Map.take(combined.sources, [:load, :dial, :loads]) ==
             Map.merge(load.sources, age.sources)
  end

  test "a run on canvas draws one plot per frame, and a tick moves them" do
    canvas = Frames.prepare(LoadAndAge, [], :canvas)
    {first, canvas} = Frames.frame(LoadAndAge, [animation_tick: 1], :canvas, canvas)
    {later, _canvas} = Frames.frame(LoadAndAge, [animation_tick: 20], :canvas, canvas)

    assert Frames.frames(LoadAndAge) == 3

    for frame <- [first, later] do
      assert frame.plots |> Enum.map(& &1.name) |> Enum.sort() == [:age, :history, :now]
    end

    # Each plot's canvas sits in its frame's own box: three canvases, three places.
    assert first.plots |> Enum.map(& &1.box) |> Enum.uniq() |> length() == 3

    moved = for {a, b} <- Enum.zip(first.plots, later.plots), a.canvas != b.canvas, do: a.name
    assert :history in moved and :age in moved
  end

  test "it is a light chart, within the light budget (spec/14 §12.6, #469)" do
    assert Compare.cost(LoadAndAge) == :light

    {work, svg} =
      Visualize.Work.reductions(fn ->
        Design.render(LoadAndAge, width: 700, height: 450, palette: :default)
      end)

    assert svg =~ "<svg"
    assert work < 4_000_000
  end

  test "it stands after Load in the gallery's order, so Previous and Next reach it" do
    assert Gallery.module("load_and_age") == LoadAndAge

    assert Gallery.neighbours("load_and_age") ==
             {{LoadChart, "load"}, {ContextChart, "context"}}

    assert {_previous, {LoadAndAge, "load_and_age"}} = Gallery.neighbours("load")
    assert {{LoadAndAge, "load_and_age"}, _next} = Gallery.neighbours("context")

    # The two charts it is made of stay in the gallery.
    assert Gallery.module("load") == LoadChart
    assert Gallery.module("load_age") == LoadAge
  end
end
