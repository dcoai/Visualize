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

  test "categories equal by == are one category, and a repeated one keeps its first slot" do
    scale = Scale.band() |> Scale.domain([1.0, -0.0, :a, :b, :a]) |> Scale.range([0, 50])

    assert Scale.apply(scale, 1) == 0.0
    assert Scale.apply(scale, 1.0) == 0.0
    assert Scale.apply(scale, 0) == 10.0
    assert Scale.apply(scale, 0.0) == 10.0
    assert Scale.apply(scale, :a) == 20.0
    assert Scale.apply(scale, :b) == 30.0
    assert Scale.apply(scale, 1.5) == nil
  end

  test "every setter lays the bands out again" do
    scale = Scale.band() |> Scale.domain([:a, :b]) |> Scale.range([0, 100])
    assert Scale.apply(scale, :b) == 50.0
    assert Scale.apply(Scale.range(scale, [100, 0]), :b) == 0.0
    assert Scale.apply(Scale.domain(scale, [:b, :a]), :b) == 0.0
    assert Scale.apply(Band.padding_outer(scale, 1), :b) == 50.0
    assert Band.step(Band.padding_outer(scale, 1)) == 25.0
    assert Scale.apply(Band.align(Band.padding_outer(scale, 1), 0), :a) == 0.0
    assert Scale.bandwidth(Band.padding_inner(scale, 0.5)) == 100 / 1.5 * 0.5
    assert Scale.bandwidth(Scale.padding(scale, 0.5)) == 100 / 2.5 * 0.5
    # step = floor(99 / 2) = 49, start = round(1 · 0.5) = 1
    assert Scale.apply(Band.round(Scale.range(scale, [0, 99]), true), :b) == 50.0
  end

  # #809, D-202: a lookup reads the category's slot; it walks no domain and recomputes no
  # layout, so a 2,500-item band × band chart is not O(n²). Counted, not timed (D-114).
  test "apply/2 over a thousand categories costs what it costs over ten" do
    work = fn n ->
      scale = Scale.band() |> Scale.domain(Enum.to_list(1..n)) |> Scale.range([0, 1000])
      # The last category, which a linear search reaches last.
      {reductions, _} =
        Visualize.Work.reductions(fn -> for _ <- 1..100, do: Scale.apply(scale, n) end)

      reductions
    end

    small = work.(10)
    large = work.(1000)
    assert large <= small * 1.1, "1,000 categories: #{large}; 10: #{small}"
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
