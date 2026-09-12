defmodule Visualize.Chart.DesignsGoldenTest do
  @moduledoc """
  Rendered-SVG golden of the twelve metresis panel types as stored designs
  (`test/support/designs/`, `Visualize.Designs`), each applied to the fixture pool and
  drawn through the frame and its marks (spec/14 §5, §7.3, D-61, D-62, D-65); the same
  designs render on a canvas with literal paints. Regenerate only when a mark's output
  changes on purpose:

      MIX_ENV=test mix run -e 'ExUnit.start(autorun: false); Code.require_file("test/visualize/chart/designs_golden_test.exs"); Visualize.Chart.DesignsGoldenTest.write!()'
  """
  use ExUnit.Case, async: true

  alias Visualize.Chart
  alias Visualize.Designs

  @golden "test/support/designs_golden.txt"

  def render, do: Enum.map_join(Designs.names(), "", &"#{&1} #{Designs.render(&1)}\n")

  def write!, do: File.write!(@golden, render())

  test "every stored design validates and applies to the fixture pool" do
    for name <- Designs.names() do
      chart = Designs.chart(name)
      assert chart.meta.name == to_string(name)
      assert {:ok, applied} = Chart.apply(chart, sources: Designs.sources())
      assert Enum.sort(Map.keys(applied.sources)) == Enum.sort(Map.keys(chart.sources))
      assert applied.chart.vars == %{}
    end
  end

  test "a slot with a default, a variable and a whole-node variable are what the designs use" do
    assert Designs.chart(:line).sources.primary.default == :series
    assert Designs.apply(:line).sources.primary == Designs.sources().series
    assert Enum.at(Designs.apply(:line, vars: %{unit: "lb"}).chart.labels, 1).text == "lb"
    assert hd(Designs.apply(:state_timeline).chart.marks).options == %{height: 50}
    assert Designs.render(:line, vars: %{title: "Mass"}) =~ "Mass"
  end

  test "every design renders exactly as recorded" do
    assert File.read!(@golden) == render()
  end

  test "every design renders on a canvas with literal paints and no CSS reference" do
    for name <- Designs.names() do
      js = Designs.render(name, backend: :canvas)
      refute js =~ "var(", "#{name}"
      assert js =~ "ctx.", "#{name}"
    end
  end

  test "a design bound to another source with the same fields renders without change" do
    sources = Designs.sources()
    other = Enum.map(sources.series, &%{&1 | v: &1.v + 1})
    svg = Designs.render(:line, sources: %{sources | series: other})
    assert svg =~ ~s(class="mark mark-line")
    refute svg == Designs.render(:line)

    {:ok, applied} =
      Chart.apply(Designs.chart(:line), sources: %{primary: other, events: sources.events})

    assert Chart.render(applied) == svg
  end
end
