defmodule Examples.GalleryCostTest do
  @moduledoc """
  Every gallery chart's still render within a reduction budget for its cost class
  (spec/14 §12.6, #469): the next expensive example is noticed here, by a count at the
  test that names it, rather than by the comparison over every design running out of
  time under load. Counted with `Visualize.Work.reductions/1` (spec/12 §6), which the
  load of the machine does not move.
  """
  use ExUnit.Case, async: true

  alias Examples.Charts.Design
  alias Examples.Compare

  # The most any light chart costs is about 2 million (the Globe over Natural Earth's 5,143
  # land positions, #499; Context, four plots, about 1.4 million); the heavy one,
  # Downsampling's 50,000 unreduced rows, about 26 million.
  @budget %{light: 4_000_000, heavy: 40_000_000}
  @opts [width: 700, height: 450, palette: :default]

  test "no chart's still render exceeds its class's budget, and a heavy chart is heavy" do
    costs =
      for {slug, module} <- ExamplesWeb.ChartLive.charts() do
        {work, svg} = Visualize.Work.reductions(fn -> Design.render(module, @opts) end)
        assert svg =~ "<svg"
        {slug, Compare.cost(module), work}
      end

    over = for {slug, class, work} <- costs, work > @budget[class], do: {slug, class, work}
    assert over == [], "over the #{inspect(@budget)} budget: #{inspect(over)}"

    # A class that no longer describes its chart is stale: a heavy chart costs more than a
    # light one may.
    light_enough = for {slug, :heavy, work} <- costs, work <= @budget.light, do: {slug, work}

    assert light_enough == [],
           "declared heavy but within the light budget: #{inspect(light_enough)}"
  end
end
