defmodule Examples.PaintsChartTest do
  @moduledoc """
  The Paints chart's swatches and blend (#786, spec/14 §3.1): every hatch pattern, a
  stroke inside, outside and doubled, and incidents that multiply where they overlap.
  """
  use ExUnit.Case, async: true

  alias Examples.Charts.{Design, PaintsChart}
  alias Visualize.Chart

  setup_all do
    svg = Chart.render(Design.applied(PaintsChart, []), root: true, resolve: :literal)
    %{svg: svg}
  end

  test "the swatches fill with lines and dots, beside the window's crosshatch", %{svg: svg} do
    patterns = Regex.scan(~r/<pattern [^>]*>(.*?)<\/pattern>/s, svg, capture: :all_but_first)
    bodies = Enum.map(patterns, &hd/1)

    # A dots pattern holds a circle; lines one line; the crosshatch two.
    assert Enum.any?(bodies, &(&1 =~ "<circle"))
    assert Enum.any?(bodies, &(length(Regex.scan(~r/<line /, &1)) == 1))
    assert Enum.any?(bodies, &(length(Regex.scan(~r/<line /, &1)) == 2))
  end

  test "a stroke sits inside, outside or doubled on its edge", %{svg: svg} do
    # Inside: a doubled width clipped to the shape; double: a thinner line over the stroke.
    assert svg =~ ~r/<clipPath id="vis-clip-/
    assert svg =~ ~s(stroke-width="12")
    assert svg =~ ~s(stroke-width="3.0")
  end

  test "the incidents multiply where they overlap", %{svg: svg} do
    assert length(Regex.scan(~r/style="mix-blend-mode: multiply"/, svg)) == 4
  end
end
