defmodule Examples.GalleryCostTest do
  @moduledoc """
  Every gallery chart's still render within a reduction budget for its cost class
  (spec/14 §12.6, #469): the next expensive example is noticed here, by a count at the
  test that names it, rather than by the comparison over every design running out of
  time under load. Counted with `Visualize.Work.reductions/1` (spec/12 §6): the render's
  execution in a process of its own, with no garbage collection in the count.

  **The count is checked before the budget** (#703). Each chart is counted twice, and the
  two counts must agree within `@agree`; a count that is not a property of the code fails
  as that, with both numbers, and is not read as a chart past its budget. Counted in one
  process after a warm run there, the 45 charts in one test, a count inherited the heap
  of the chart before it: `day_night_gps` counted 4.39 million in CI against 3.15
  million alone; counted in fresh processes that still collected, two counts on a loaded
  CI runner were 8.5 % apart (pipeline 6230). With the collections out of the count, the
  two agree to a few dozen reductions.
  """
  use ExUnit.Case, async: true

  alias Examples.Charts.Design
  alias Examples.Compare

  # The most any light chart costs is about 2.5 million (the world maps over Natural
  # Earth's 5,143 land positions, #499, and Day, Night and GPS over them); the heavy one,
  # Downsampling's 50,000 unreduced rows, about 30 million.
  @budget %{light: 4_000_000, heavy: 40_000_000}
  @opts [width: 700, height: 450]

  # How far two counts of one render may be apart: half a percent. Measured over every
  # chart counted four times in a CI suite (pipeline 6232), the widest spread is 0.18 %
  # (incremental_line, 427,232 against 428,007) and most are a few dozen reductions. The
  # residue is not a path through the code: the calls made are the same, counted, on two
  # runs a thousand reductions apart. It is how a BIF that yields is charged against the
  # time slice it lands in.
  @agree 0.005

  # One test per chart, so no test carries the whole gallery's work (spec/12 §6).
  for {slug, module} <- ExamplesWeb.ChartLive.charts() do
    @module module
    test "#{slug}'s still render is within its class's budget, counted the same twice" do
      class = Compare.cost(@module)
      {first, svg} = Visualize.Work.reductions(fn -> Design.render(@module, @opts) end)
      {second, _svg} = Visualize.Work.reductions(fn -> Design.render(@module, @opts) end)
      assert svg =~ "<svg"

      assert abs(first - second) <= @agree * min(first, second),
             "#{unquote(slug)}: two counts of one render are #{first} and #{second}, more " <>
               "than #{@agree * 100} % apart: the count is not a property of the code"

      work = max(first, second)

      assert work <= @budget[class],
             "#{unquote(slug)} (#{class}) costs #{work} reductions, over #{@budget[class]}"

      # A class that no longer describes its chart is stale: a heavy chart costs more than
      # a light one may.
      if class == :heavy do
        assert work > @budget.light,
               "#{unquote(slug)} is declared heavy but costs #{work}, within the light budget"
      end
    end
  end
end
