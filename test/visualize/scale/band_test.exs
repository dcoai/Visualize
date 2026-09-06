defmodule Visualize.Scale.BandTest do
  @moduledoc "Band maths is d3-scale's `rescale` (spec/03 §9.3, D-17)."
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Visualize.Scale
  alias Visualize.Scale.Band

  test "a descending range lays the bands out in reverse with positive step and bandwidth" do
    scale = Scale.band() |> Scale.domain([:a, :b, :c, :d]) |> Scale.range([100, 0])
    assert Band.step(scale) == 25.0
    assert Scale.bandwidth(scale) == 25.0
    assert Enum.map([:a, :b, :c, :d], &Scale.apply(scale, &1)) == [75.0, 50.0, 25.0, 0.0]
  end

  test "an ascending range is unchanged" do
    scale = Scale.band() |> Scale.domain([:a, :b, :c, :d]) |> Scale.range([0, 100])
    assert Enum.map([:a, :b, :c, :d], &Scale.apply(scale, &1)) == [0.0, 25.0, 50.0, 75.0]
  end

  test "round floors the step and rounds start and bandwidth from the floored step" do
    scale =
      Scale.band()
      |> Scale.domain([:a, :b, :c])
      |> Scale.range([0, 100])
      |> Scale.padding(0.1)
      |> Band.round(true)

    # step = 100 / (3 − 0.1 + 0.2) = 32.26 → 32; start = (100 − 32 · 2.9) / 2 = 3.6 → 4
    assert Band.step(scale) == 32.0
    assert Scale.bandwidth(scale) == 29.0
    assert Enum.map([:a, :b, :c], &Scale.apply(scale, &1)) == [4.0, 36.0, 68.0]
  end

  test "an empty domain has no step or bandwidth and an absent category maps to nil" do
    scale = Scale.band() |> Scale.range([0, 100])
    assert Band.step(scale) == 0
    assert Scale.bandwidth(scale) == 0
    assert Scale.apply(scale, :missing) == nil
  end

  property "bands stay inside the range whichever way it runs" do
    check all(
            n <- integer(1..12),
            r0 <- float(min: -500.0, max: 500.0),
            r1 <- float(min: -500.0, max: 500.0),
            pi <- float(min: 0.0, max: 0.9),
            po <- float(min: 0.0, max: 2.0),
            align <- float(min: 0.0, max: 1.0),
            round? <- boolean()
          ) do
      domain = Enum.to_list(1..n)

      scale =
        Scale.band()
        |> Scale.domain(domain)
        |> Scale.range([r0, r1])
        |> Band.padding_inner(pi)
        |> Band.padding_outer(po)
        |> Band.align(align)
        |> Band.round(round?)

      lo = min(r0, r1)
      hi = max(r0, r1)
      bandwidth = Scale.bandwidth(scale)
      step = Band.step(scale)

      assert bandwidth >= 0
      assert step >= 0
      assert bandwidth <= step + 1.0e-9

      positions = Enum.map(domain, &Scale.apply(scale, &1))
      sorted = if r1 < r0, do: Enum.reverse(positions), else: positions
      assert sorted == Enum.sort(sorted)

      # Rounding the start up and the bandwidth up can overshoot the range by under one
      # unit, as it does in d3.
      slack = if round?, do: 1.0, else: 1.0e-9

      for pos <- positions do
        assert pos >= lo - slack
        assert pos + bandwidth <= hi + slack
        if round?, do: assert(pos == Float.round(pos))
      end
    end
  end
end
