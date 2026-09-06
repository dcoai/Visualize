defmodule Visualize.Shape.PercentileBandTest do
  @moduledoc "The `PercentileBand` composed mark (spec/04 §14, D-28)."
  use ExUnit.Case, async: true

  alias Visualize.Shape
  alias Visualize.Shape.{Area, Line, PercentileBand}

  # Six samples in pixels; the fourth is undefined so every path splits.
  @samples [
    %{x: 0, p5: 90, p25: 70, p50: 50, p75: 30, p95: 10},
    %{x: 20, p5: 80, p25: 60, p50: 45, p75: 35, p95: 20},
    %{x: 40, p5: 95, p25: 75, p50: 55, p75: 25, p95: 5},
    %{x: 60, p5: nil, p25: nil, p50: nil, p75: nil, p95: nil},
    %{x: 80, p5: 85, p25: 65, p50: 40, p75: 30, p95: 15},
    %{x: 100, p5: 70, p25: 55, p50: 50, p75: 45, p95: 30}
  ]

  defp band do
    PercentileBand.new()
    |> PercentileBand.x(:x)
    |> PercentileBand.median(:p50)
    |> PercentileBand.inner({:p25, :p75})
    |> PercentileBand.outer({:p5, :p95})
  end

  describe "generate/2" do
    test "the fixed dataset renders the three recorded paths" do
      assert PercentileBand.generate(band(), defined_samples()) == %{
               outer: "M0,10L20,20L40,5L80,15L100,30L100,70L80,85L40,95L20,80L0,90Z",
               inner: "M0,30L20,35L40,25L80,30L100,45L100,55L80,65L40,75L20,60L0,70Z",
               median: "M0,50L20,45L40,55L80,40L100,50"
             }
    end

    test "each path is byte-identical to the standalone generator's" do
      band = band() |> PercentileBand.curve(:monotone_x) |> PercentileBand.defined(&defined?/1)
      %{outer: outer, inner: inner, median: median} = PercentileBand.generate(band, @samples)

      assert outer ==
               Area.new()
               |> Area.x(:x)
               |> Area.y0(:p5)
               |> Area.y1(:p95)
               |> Area.defined(&defined?/1)
               |> Area.curve(:monotone_x)
               |> Area.generate(@samples)

      assert inner ==
               Area.new()
               |> Area.x(:x)
               |> Area.y0(:p25)
               |> Area.y1(:p75)
               |> Area.defined(&defined?/1)
               |> Area.curve(:monotone_x)
               |> Area.generate(@samples)

      assert median ==
               Line.new()
               |> Line.x(:x)
               |> Line.y(:p50)
               |> Line.defined(&defined?/1)
               |> Line.curve(:monotone_x)
               |> Line.generate(@samples)
    end

    test "the defined predicate splits every path at the gap" do
      %{outer: outer, median: median} =
        band() |> PercentileBand.defined(&defined?/1) |> PercentileBand.generate(@samples)

      assert outer == "M0,10L20,20L40,5L40,95L20,80L0,90ZM80,15L100,30L100,70L80,85Z"
      assert median == "M0,50L20,45L40,55M80,40L100,50"
    end

    test "an unset band or median is nil" do
      assert PercentileBand.new() |> PercentileBand.generate([{0, 1}]) ==
               %{outer: nil, inner: nil, median: nil}

      assert %{outer: nil, inner: "M" <> _, median: nil} =
               band()
               |> PercentileBand.outer(nil)
               |> PercentileBand.median(nil)
               |> PercentileBand.generate(defined_samples())
    end

    test "function accessors in the pairs" do
      %{inner: inner} =
        PercentileBand.new()
        |> PercentileBand.x(& &1.x)
        |> PercentileBand.inner({& &1.p25, fn d -> d.p75 end})
        |> PercentileBand.generate(defined_samples())

      assert inner == "M0,30L20,35L40,25L80,30L100,45L100,55L80,65L40,75L20,60L0,70Z"
    end
  end

  describe "generate_path/2" do
    test "returns IR paths in the same shape" do
      assert %{outer: %Visualize.IR.Path{}, inner: %Visualize.IR.Path{}, median: nil} =
               band() |> PercentileBand.median(nil) |> PercentileBand.generate_path(@samples)
    end
  end

  describe "through the facade" do
    test "every setter and both generators dispatch" do
      shape =
        Shape.percentile_band()
        |> Shape.x(:x)
        |> Shape.median(:p50)
        |> Shape.inner({:p25, :p75})
        |> Shape.outer({:p5, :p95})
        |> Shape.curve(:step_after)
        |> Shape.defined(&defined?/1)

      assert %{median: "M0,50H20V45H40V55M80,40H100V50"} = Shape.generate(shape, @samples)
      assert %{outer: %Visualize.IR.Path{}} = Shape.generate_path(shape, @samples)
    end
  end

  defp defined?(d), do: d.p50 != nil
  defp defined_samples, do: Enum.filter(@samples, &defined?/1)
end
