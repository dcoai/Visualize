defmodule Visualize.Scale.TicksTest do
  @moduledoc """
  Tick, degenerate-domain and empty-range cases from #13 for the linear, log, symlog,
  ordinal and quantize scales (spec/03 §3.2, §4.2, §6.2, §8.2, §11.2; D-17).
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Visualize.Scale
  alias Visualize.Scale.Symlog

  describe "Linear on a degenerate domain" do
    test "ticks/2 returns the single value and nice/1 is identity" do
      scale = Scale.linear() |> Scale.domain([5, 5])
      assert Scale.ticks(scale) == [5]
      assert Scale.nice(scale).domain == [5, 5]
    end

    test "a descending domain yields the same ticks descending" do
      up = Scale.linear() |> Scale.domain([0, 10]) |> Scale.ticks(5)
      down = Scale.linear() |> Scale.domain([10, 0]) |> Scale.ticks(5)
      assert down == Enum.reverse(up)
    end

    test "a domain that contains no multiple of the step yields no ticks, not two outside it" do
      # Found by the property below: `0..-1` descends.
      assert Scale.linear() |> Scale.domain([-9843.75, -9533.68]) |> Scale.ticks(1) == []
    end
  end

  describe "Log.ticks/2" do
    test "one decade lists every integer multiple" do
      scale = Scale.log() |> Scale.domain([1, 10])
      assert Scale.ticks(scale) == [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0]
    end

    test "negative exponents divide, so the values print cleanly" do
      scale = Scale.log() |> Scale.domain([0.01, 1])
      list = Scale.ticks(scale)
      assert Enum.take(list, 3) == [0.01, 0.02, 0.03]
      assert 0.3 in list
      assert List.last(list) == 1.0
    end

    test "many decades are thinned to about count powers" do
      scale = Scale.log() |> Scale.domain([1, 1.0e12])
      assert Scale.ticks(scale, 5) == [1.0, 100.0, 1.0e4, 1.0e6, 1.0e8, 1.0e10, 1.0e12]
      assert length(Scale.ticks(scale, 10)) == 13
      assert length(Scale.ticks(scale, 5)) < length(Scale.ticks(scale, 10))
    end

    test "a sub-decade domain falls back to linear ticks instead of []" do
      scale = Scale.log() |> Scale.domain([2, 5])
      list = Scale.ticks(scale)
      assert list != []
      assert 2.2 in list
      assert List.first(list) == 2.0 and List.last(list) == 5.0
    end

    test "a descending domain reverses" do
      assert Scale.log() |> Scale.domain([10, 1]) |> Scale.ticks(3) ==
               Scale.log() |> Scale.domain([1, 10]) |> Scale.ticks(3) |> Enum.reverse()
    end

    test "base 2 lists powers of two" do
      scale = Scale.log(2) |> Scale.domain([1, 64])
      assert Scale.ticks(scale) == [1.0, 2.0, 4.0, 8.0, 16.0, 32.0, 64.0]
    end
  end

  describe "Symlog.ticks/2" do
    test "decades start at the constant" do
      base = Scale.symlog() |> Scale.domain([0, 1000])
      assert Scale.ticks(base) == [0, 1.0, 10.0, 100.0, 1000.0]
      assert base |> Symlog.constant(10) |> Scale.ticks() == [0, 10.0, 100.0, 1000.0]
      assert base |> Symlog.constant(0.1) |> Scale.ticks() |> List.first() == 0
      assert base |> Symlog.constant(0.1) |> Scale.ticks() |> Enum.at(1) == 0.1
    end

    test "negative decades mirror the positive ones around zero" do
      scale = Scale.symlog() |> Scale.domain([-100, 100])
      assert Scale.ticks(scale) == [-100.0, -10.0, -1.0, 0, 1.0, 10.0, 100.0]
    end

    test "decades below a positive lower bound, or above a negative upper one, are dropped" do
      # Found by the property below: the positive decades were only filtered from above.
      assert Scale.symlog() |> Scale.domain([50, 5000]) |> Scale.ticks() == [100.0, 1000.0]
      assert Scale.symlog() |> Scale.domain([-5000, -50]) |> Scale.ticks() == [-1000.0, -100.0]
      assert Scale.symlog() |> Scale.domain([1.0e6 + 1, 1.0e6 + 2]) |> Scale.ticks() == []
    end
  end

  describe "Ordinal.apply/2" do
    test "an empty range returns unknown instead of raising" do
      scale = Scale.ordinal() |> Scale.domain([:a, :b])
      assert Scale.apply(scale, :a) == nil
      assert scale |> Scale.Ordinal.unknown(:none) |> Scale.apply(:a) == :none
    end
  end

  describe "Quantize.thresholds/1" do
    test "a single-element range has no interior threshold" do
      scale = Scale.quantize() |> Scale.domain([0, 100]) |> Scale.range([:only])
      assert Scale.Quantize.thresholds(scale) == []
      assert Scale.ticks(scale) == []
      assert Scale.apply(scale, 50) == :only
    end
  end

  describe "tick properties" do
    defp ascending_domain(min, max) do
      gen all(d0 <- float(min: min, max: max), fraction <- float(min: 0.0, max: 1.0)) do
        [d0, d0 + 0.01 + fraction * (max - d0)]
      end
    end

    defp assert_ticks([d0, d1], list) do
      assert list == Enum.sort(list)
      assert list == Enum.uniq(list)
      tolerance = 1.0e-9 * max(1, max(abs(d0), abs(d1)))
      assert Enum.all?(list, &(&1 >= d0 - tolerance and &1 <= d1 + tolerance)), inspect(list)
    end

    property "Linear ticks are ascending, distinct, inside the domain, about count long" do
      check all(domain <- ascending_domain(-1.0e4, 1.0e4), count <- integer(1..30)) do
        list = Scale.linear() |> Scale.domain(domain) |> Scale.ticks(count)
        assert_ticks(domain, list)
        assert length(list) <= 2 * count + 2
      end
    end

    property "Log ticks are ascending, distinct and inside the domain" do
      check all(domain <- ascending_domain(1.0e-3, 1.0e9), count <- integer(1..30)) do
        list = Scale.log() |> Scale.domain(domain) |> Scale.ticks(count)
        assert_ticks(domain, list)
      end
    end

    property "Symlog ticks are ascending, distinct and inside the domain" do
      check all(
              domain <- ascending_domain(-1.0e6, 1.0e6),
              constant <- member_of([0.1, 1, 10]),
              count <- integer(1..30)
            ) do
        scale = Scale.symlog() |> Symlog.constant(constant) |> Scale.domain(domain)
        assert_ticks(domain, Scale.ticks(scale, count))
      end
    end
  end
end
