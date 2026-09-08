defmodule Visualize.Chart.DesignsGoldenTest do
  @moduledoc """
  Rendered-SVG golden of the twelve metresis panel types as stored designs
  (`test/support/designs/`, `Visualize.Designs`), each drawn through the frame and its
  marks from the fixture sources (spec/14 §5, D-61, D-62); the same designs render on a
  canvas with literal paints. Regenerate only when a mark's output changes on purpose:

      MIX_ENV=test mix run -e 'ExUnit.start(autorun: false); Code.require_file("test/visualize/chart/designs_golden_test.exs"); Visualize.Chart.DesignsGoldenTest.write!()'
  """
  use ExUnit.Case, async: true

  alias Visualize.Designs

  @golden "test/support/designs_golden.txt"

  def render, do: Enum.map_join(Designs.names(), "", &"#{&1} #{Designs.render(&1)}\n")

  def write!, do: File.write!(@golden, render())

  test "every stored design validates and binds to the fixture sources" do
    for name <- Designs.names() do
      chart = Designs.chart(name)
      assert chart.meta.name == to_string(name)

      for {source, %{fields: fields}} <- chart.sources do
        rows = Map.fetch!(Designs.sources(), source)
        assert Enum.all?(fields, &Map.has_key?(hd(rows), &1)), "#{name}: #{source} lacks a field"
      end
    end
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
    frame = Visualize.Chart.Frame.new(Designs.chart(:line), sources: %{sources | series: other})
    svg = Visualize.Chart.Frame.render(frame, sources: %{sources | series: other})
    assert svg =~ ~s(class="mark mark-line")
    refute svg == Designs.render(:line)
  end
end
