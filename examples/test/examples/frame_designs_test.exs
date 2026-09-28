defmodule Examples.FrameDesignsTest do
  @moduledoc """
  The gallery designs frames exist for (#383, #429): *Load*, one source read twice in two
  frames; *Context*, one source at four time scales in four; and *Spectrum*, the two
  panels that were one frame's two scale pairs and are now two frames.

  The general guards — validity, the round trip, the golden, the gallery grid, the colour
  profiles — are `Examples.ChartsTest`'s and apply to these three like any other chart.
  What is held here is what makes each of them the acceptance of #383.
  """
  use ExUnit.Case, async: true

  alias Examples.Charts.{ContextChart, Design, LoadChart, SpectrumChart}
  alias Visualize.Chart

  defp applied(module, opts \\ []) do
    {design, sources} = module.design(opts)
    {:ok, applied} = Chart.apply(design, sources: sources, size: Design.size(module, opts))
    applied
  end

  describe "Load: one source, two frames" do
    test "the gauge draws the newest row of the same source the history line draws in full" do
      {design, sources} = LoadChart.design([])
      applied = applied(LoadChart)

      # Both frames' marks read `:load` — the gauge's through `take(1)`, nothing else.
      assert Enum.all?(design.marks, fn mark ->
               case mark.data do
                 :load -> true
                 :dial -> true
                 %{source: :load, transforms: [%{op: :take, n: 1}]} -> true
                 _other -> false
               end
             end)

      # The dial's reading is the last row of the rows the line draws.
      newest = List.last(sources.load)
      [reading | _] = Enum.filter(design.marks, &(&1[:frame] == :now and is_map(&1.data)))
      rows = Chart.Transform.apply(reading.data.transforms, sources.load)
      assert rows == [newest]

      # Two frames, each with its own scales; the history's `x` is time and the dial's
      # `angle` is the load, over the same ceiling.
      assert applied.frames |> Map.keys() |> Enum.sort() == [:history, :now]
      assert applied.frames.history.scales.x.__struct__ == Visualize.Scale.Time
      assert applied.frames.now.scales.angle.domain == [0, 4]
      assert applied.frames.now.z == 1
      assert applied.frames.now.box == [0.72, 0.04, 0.24, 0.24]
    end

    test "the dial is drawn over the history, at its own box, on its own background" do
      svg = LoadChart.render([])

      # z orders them: the history first, the dial over it with its background rect.
      assert [history, now] =
               Regex.scan(~r/class="frame frame-(\w+)"/, svg) |> Enum.map(&List.last/1)

      assert {history, now} == {"history", "now"}
      assert svg =~ ~s|<rect fill="var(--vis-background, #ffffff)"|
    end
  end

  describe "Context: one source at four time scales" do
    test "the four frames cover four disjoint, contiguous spans of one source" do
      applied = applied(ContextChart)
      names = [:year, :day, :hour, :recent]

      assert applied.frames |> Map.keys() |> Enum.sort() == Enum.sort(names)

      # Each frame's `x` domain is its own window's extent, inferred from the rows its
      # marks read after their transforms (spec/14 §4.3, D-62).
      [year, day, hour, recent] =
        for name <- names, do: applied.frames[name].scales.x.domain

      for [[_, older_end], [newer_start, _]] <- Enum.chunk_every([year, day, hour, recent], 2, 1, :discard) do
        assert DateTime.compare(older_end, newer_start) == :lt
      end

      # Left to right, a quarter of the box each, in order.
      assert for(name <- names, do: applied.frames[name].box) == [
               [0.0, 0, 0.25, 1],
               [0.25, 0, 0.25, 1],
               [0.5, 0, 0.25, 1],
               [0.75, 0, 0.25, 1]
             ]

      # The newest reading is in the last window and in no other.
      {_design, sources} = ContextChart.design([])
      newest = sources.load |> Enum.map(& &1.t) |> Enum.max(DateTime)
      [_, recent_end] = recent
      assert DateTime.compare(recent_end, newest) == :eq
    end

    test "the four frames read against one load axis, declared once (#384)" do
      applied = applied(ContextChart)
      {design, _sources} = ContextChart.design([])

      # The `year` frame declares the load axis; the other three adopt it (spec/14 §4.3).
      assert %{kind: :linear} = design.frames.year.scales.y

      for name <- [:day, :hour, :recent] do
        assert design.frames[name].scales.y == {:frame, :year, :y}, "#{name}"
      end

      # One domain, inferred over all four windows and drawn by all four.
      [domain] = applied.frames |> Map.values() |> Enum.map(& &1.scales.y.domain) |> Enum.uniq()
      assert [lo, hi] = domain
      assert lo == 0.0 and hi > 1

      # Four x axes and four y axes are drawn; the three ghosts carry the grid alone, so
      # only one y axis prints its tick labels.

      svg = ContextChart.render([])
      assert length(Regex.scan(~r/class="axis axis-bottom"/, svg)) == 4
      assert length(Regex.scan(~r/class="axis axis-left"/, svg)) == 4
      assert length(Regex.scan(~r/class="grid"/, svg)) == 4
    end
  end

  describe "Spectrum: two panels are two frames" do
    test "it renders as two frames and no scale in it carries an explicit range" do
      {design, _sources} = SpectrumChart.design([])
      applied = applied(SpectrumChart)

      assert applied.frames |> Map.keys() |> Enum.sort() == [:signal, :spectrum]
      assert applied.frames.signal.box == [0, 0, 1, 0.5]
      assert applied.frames.spectrum.box == [0, 0.5, 1, 0.5]

      # The trick it replaces: `fx`/`fy` with explicit ranges, read through `scales` renames.
      for {_name, frame} <- design.frames, {_name, scale} <- frame.scales do
        refute Map.has_key?(scale, :range)
      end

      for mark <- design.marks, do: refute(Map.has_key?(mark, :scales))
      assert design.frames.signal.scales |> Map.keys() |> Enum.sort() == [:x, :y]
      assert design.frames.spectrum.scales |> Map.keys() |> Enum.sort() == [:x, :y]
    end
  end
end
