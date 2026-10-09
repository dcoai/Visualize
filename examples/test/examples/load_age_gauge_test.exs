defmodule Examples.LoadAgeGaugeTest do
  @moduledoc """
  *Load age + gauge* (#498): the log-age view filling the box and the dial inset over its
  plot's upper-left corner, one design of two overlapping frames — the inset's place and
  order, one clock, the two source charts' own pieces, and a run on canvas of one plot per
  frame.

  The general guards — validity, the round trip, the golden, the colour profiles — are
  `Examples.ChartsTest`'s and apply to this chart like any other.
  """
  use ExUnit.Case, async: true

  alias Examples.Charts.{ContextChart, Design, Load, LoadAge, LoadAgeGauge, LoadChart, LoadGauge}
  alias Examples.{Compare, Frames, Gallery}
  alias Visualize.Chart

  defp applied(opts), do: Design.applied(LoadAgeGauge, opts)

  test "the design validates and applies, two frames: the age view and the dial over it" do
    {design, sources} = LoadAgeGauge.design([])
    assert {:ok, chart} = Chart.from_map(design)
    assert {:ok, applied} = Chart.apply(chart, sources: sources, theme: Design.theme([]))

    assert applied.frames |> Map.keys() |> Enum.sort() == [:age, :gauge]
    assert applied.frames.age.box == [0, 0, 1, 1]
    assert design.frames.gauge.background == :background
  end

  describe "the inset" do
    test "the dial's box lies inside the age plot, in its upper-left quadrant" do
      for size <- [LoadAgeGauge.size(), {900, 500}] do
        {width, height} = size
        frames = applied(width: width, height: height).frames
        [x, y, w, h] = frames.gauge.box
        assert [x, y, w, h] == LoadAgeGauge.box()

        # The age plot in pixels: its margin's offset and its own width and height.
        margin = frames.age.margin
        plot = frames.age.plot
        {left, top} = {margin.left, margin.top}
        {right, bottom} = {left + plot.width, top + plot.height}

        # The dial's box in pixels: clear of the y axis on the left and of the plot's top,
        # and no further than the plot's centre either way.
        {x0, y0, x1, y1} = {x * width, y * height, (x + w) * width, (y + h) * height}
        assert x0 > left and y0 > top
        assert x1 < (left + right) / 2 and y1 < (top + bottom) / 2
      end
    end

    test "the dial is drawn above the age view, on its own background" do
      frames = applied([]).frames
      assert frames.gauge.z > frames.age.z
      assert frames.gauge.background != nil

      # Drawn later in the document: the gauge's group follows the age view's.
      svg = Design.render(LoadAgeGauge, [])
      {age, _} = :binary.match(svg, "frame-age")
      {gauge, _} = :binary.match(svg, "frame-gauge")
      assert gauge > age
    end

    test "the age view keeps its key in the top-right, and the dial draws none" do
      {design, _sources} = LoadAgeGauge.design([])
      assert design.frames.age.legend.position == :top_right
      assert design.frames.gauge[:legend] == nil
    end
  end

  test "the dial and the age view show the same instant at every tick" do
    for tick <- [0, 1, 37, 400] do
      {_design, sources} = LoadAgeGauge.design(animation_tick: tick)
      now = LoadAgeGauge.now(animation_tick: tick)
      assert now == tick * 3 + LoadAge.oldest()

      # The needles read each window at `now`…
      for %{window: name, load: load} <- sources.reading do
        {window, ^name} = List.keyfind(Load.windows(), name, 1)
        assert load == Load.at(window, now)
      end

      # …and every age on the axis is measured back from that same `now`.
      assert sources.loads == LoadAge.sources(now).loads
      assert sources.reading == LoadGauge.sources(now).reading
    end
  end

  test "the pieces are the two charts' own, so the three cannot drift" do
    {combined, _} = LoadAgeGauge.design([])
    {gauge, _} = LoadGauge.design([])
    {age, _} = LoadAge.design([])

    # Nothing is renamed: the two charts' styles and sources, as they declare them.
    assert Map.take(combined.styles, Map.keys(age.styles)) == age.styles
    assert Map.take(combined.styles, Map.keys(gauge.styles)) == gauge.styles

    assert Map.take(combined.sources, [:loads, :reading, :rim]) ==
             Map.merge(age.sources, gauge.sources)

    # The age view's line and the dial's rim and needles, as their own charts draw them.
    strip = &Map.delete(&1, :frame)
    assert combined.marks |> Enum.filter(&(&1[:frame] == :age)) |> Enum.map(strip) == age.marks

    assert combined.marks |> Enum.filter(&(&1[:frame] == :gauge)) |> Enum.map(strip) ==
             gauge.marks
  end

  test "a run on canvas draws one plot per frame, and a tick moves them" do
    # The run's clock is given, so the needles' easing (450 ms, #417) has finished by the
    # later frame rather than depending on how fast the test runs: the first frame seeds
    # where the needles stand, the next retargets them, and by the later one they have
    # arrived and set off again.
    canvas = Frames.prepare(LoadAgeGauge, [], :canvas)
    {_seed, canvas} = Frames.frame(LoadAgeGauge, [animation_tick: 0, at: 0], :canvas, canvas)
    {first, canvas} = Frames.frame(LoadAgeGauge, [animation_tick: 1, at: 0], :canvas, canvas)

    {later, _canvas} =
      Frames.frame(LoadAgeGauge, [animation_tick: 20, at: 1_000], :canvas, canvas)

    assert Frames.frames(LoadAgeGauge) == 2

    for frame <- [first, later] do
      assert frame.plots |> Enum.map(& &1.name) |> Enum.sort() == [:age, :gauge]
    end

    # Each plot's canvas sits in its frame's own box: two canvases, two places.
    assert first.plots |> Enum.map(& &1.box) |> Enum.uniq() |> length() == 2

    moved = for {a, b} <- Enum.zip(first.plots, later.plots), a.canvas != b.canvas, do: a.name
    assert :age in moved and :gauge in moved
  end

  test "it is a light chart, within the light budget (spec/14 §12.6, #469)" do
    assert Compare.cost(LoadAgeGauge) == :light

    {work, svg} =
      Visualize.Work.reductions(fn ->
        Design.render(LoadAgeGauge, width: 700, height: 450, palette: :default)
      end)

    assert svg =~ "<svg"
    assert work < 4_000_000
  end

  describe "the gallery" do
    test "it stands after Load, where Load + age stood, so Previous and Next reach it" do
      assert Gallery.module("load_age_gauge") == LoadAgeGauge

      assert Gallery.neighbours("load_age_gauge") ==
               {{LoadChart, "load"}, {ContextChart, "context"}}

      assert {_previous, {LoadAgeGauge, "load_age_gauge"}} = Gallery.neighbours("load")
      assert {{LoadAgeGauge, "load_age_gauge"}, _next} = Gallery.neighbours("context")

      # The two charts it is made of stay in the gallery.
      assert Gallery.module("load_gauge") == LoadGauge
      assert Gallery.module("load_age") == LoadAge
    end

    test "Load + age is gone from the gallery and from the charts golden" do
      assert Gallery.module("load_and_age") == nil
      refute Enum.any?(Gallery.charts(), fn {_module, slug} -> slug == "load_and_age" end)
      refute Code.ensure_loaded?(Examples.Charts.LoadAndAge)

      golden = File.read!(Path.expand("../support/charts_golden.txt", __DIR__))
      refute golden =~ "Examples.Charts.LoadAndAge "
      refute golden =~ "Load + age"
      assert golden =~ "Examples.Charts.LoadAgeGauge "
    end
  end
end
