defmodule Visualize.Scale.PowerTest do
  @moduledoc """
  `Power` uses D3's signed transform (spec/03 §5.2), and every continuous scale's
  `invert/2` undoes its `apply/2`.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Visualize.Scale
  alias Visualize.Scale.{Linear, Power, Symlog}

  describe "signed transform" do
    test "a symmetric domain maps symmetrically" do
      scale = Power.new() |> Power.exponent(2) |> Power.domain([-10, 10]) |> Power.range([0, 1])
      assert_in_delta Power.apply(scale, -10), 0.0, 1.0e-12
      assert_in_delta Power.apply(scale, 0), 0.5, 1.0e-12
      assert_in_delta Power.apply(scale, 10), 1.0, 1.0e-12
      assert_in_delta Power.apply(scale, -5), 0.5 - 0.125, 1.0e-12
      assert_in_delta Power.apply(scale, 5), 0.5 + 0.125, 1.0e-12
    end

    test "invert/2 returns negative domain values" do
      scale = Power.new() |> Power.exponent(2) |> Power.domain([-10, 10]) |> Power.range([0, 1])
      assert_in_delta Power.invert(scale, 0.0), -10.0, 1.0e-9
      assert_in_delta Power.invert(scale, 0.375), -5.0, 1.0e-9
      assert_in_delta Power.invert(scale, 0.5), 0.0, 1.0e-9
    end

    test "sqrt maps area to radius and back" do
      scale = Power.sqrt() |> Power.domain([0, 100]) |> Power.range([0, 10])
      assert_in_delta Power.apply(scale, 25), 5.0, 1.0e-12
      assert_in_delta Power.invert(scale, 5.0), 25.0, 1.0e-9
    end

    test "a negative-only domain no longer collapses to r0" do
      scale =
        Power.new() |> Power.exponent(0.5) |> Power.domain([-100, -1]) |> Power.range([0, 1])

      assert_in_delta Power.apply(scale, -100), 0.0, 1.0e-12
      assert_in_delta Power.apply(scale, -1), 1.0, 1.0e-12
      assert Power.apply(scale, -50) > 0 and Power.apply(scale, -50) < 1
    end

    test "clamping bounds the output in either range order" do
      scale = Power.new() |> Power.domain([0, 10]) |> Power.range([100, 0]) |> Power.clamp(true)
      assert Power.apply(scale, 20) == 0
      assert Power.apply(scale, -5) == 100
    end

    test "nice/1 extends the domain as Linear.nice/1 does" do
      scale = Power.new() |> Power.domain([0.3, 9.7]) |> Power.nice()
      assert scale.domain == Linear.nice(%Linear{domain: [0.3, 9.7]}).domain
    end
  end

  describe "apply/invert round trip" do
    # `invert(apply(v))` passes through `y = apply(v)`, a float in the range, so it comes
    # back only as close as that rounding allows. The rounding of `y` and of the
    # transformed bounds is an error `δ` in the transformed space (spec/03 §5.2's `T`),
    # and the tolerance is how far `δ` moves the inverse at `T(v)`. It is measured with
    # the inverse itself, not its derivative, which is unbounded at 0 for an exponent
    # above 1: there `apply/2` cannot tell a small `v` from 0 at all (#629).
    @eps 2.220446049250313e-16
    @slack 4

    defp round_trip_tolerance({t, t_inv}, [d0, d1], [r0, r1], v, y) do
      {td0, td1, tv} = {t.(d0), t.(d1), t.(v)}
      spread = abs(td1 - td0) * (abs(r0) + abs(r1) + abs(y)) / abs(r1 - r0)
      delta = @slack * @eps * (abs(td0) + abs(td1) + abs(tv) + spread)

      max(abs(t_inv.(tv + delta) - v), abs(t_inv.(tv - delta) - v)) + @slack * @eps * abs(v)
    end

    defp identity, do: {& &1, & &1}

    defp signed_power(e) do
      signed = fn x, p -> if x < 0, do: -:math.pow(-x, p), else: :math.pow(x, p) end
      {&signed.(&1, e), &signed.(&1, 1 / e)}
    end

    defp symlog(c) do
      sign = fn x -> if x < 0, do: -1, else: 1 end
      {&(sign.(&1) * :math.log(1 + abs(&1) / c)), &(sign.(&1) * c * (:math.exp(abs(&1)) - 1))}
    end

    defp assert_round_trip(scale, transform, v) do
      y = Scale.apply(scale, v)
      tolerance = round_trip_tolerance(transform, scale.domain, scale.range, v, y)
      assert_in_delta Scale.invert(scale, y), v, tolerance
    end

    defp bound, do: float(min: -1000.0, max: 1000.0)

    defp domain do
      gen all(d0 <- bound(), d1 <- bound(), abs(d1 - d0) > 1.0) do
        [d0, d1]
      end
    end

    defp value_in([d0, d1]), do: float(min: min(d0, d1), max: max(d0, d1))

    test "a cube over [-1000, 1000] cannot tell 0.001 from 0, and the tolerance says so" do
      scale =
        Scale.power()
        |> Power.exponent(3)
        |> Scale.domain([-1000.0, 1000.0])
        |> Scale.range([0, 1])

      # 0.001³ is 5e-19 of the 2e9 transformed span: below the rounding of the midpoint
      assert Power.apply(scale, 0.001) == 0.5
      assert Power.apply(scale, 0.0) == 0.5
      assert Power.invert(scale, 0.5) == 0.0

      assert round_trip_tolerance(signed_power(3), scale.domain, scale.range, 0.001, 0.5) >=
               0.001

      assert_round_trip(scale, signed_power(3), 0.001)
    end

    test "the gate's failure: v = 0.1 comes back 1.7e-5 away, inside the conditioning" do
      scale =
        Scale.power()
        |> Power.exponent(3)
        |> Scale.domain([-1000, 1000])
        |> Scale.range([100, 200])

      assert_in_delta Power.invert(scale, Power.apply(scale, 0.1)), 0.1, 2.0e-5
      refute_in_delta Power.invert(scale, Power.apply(scale, 0.1)), 0.1, 1.0e-6
      assert_round_trip(scale, signed_power(3), 0.1)
    end

    test "the tolerance stays tight where the scale is well conditioned" do
      scale =
        Scale.power()
        |> Power.exponent(3)
        |> Scale.domain([-1000.0, 1000.0])
        |> Scale.range([0, 1])

      assert round_trip_tolerance(signed_power(3), scale.domain, scale.range, 500.0, 0.5625) <
               1.0e-9

      linear = Scale.linear() |> Scale.domain([-1000.0, 1000.0]) |> Scale.range([0, 1])
      assert round_trip_tolerance(identity(), linear.domain, linear.range, 0.001, 0.5) < 1.0e-11
    end

    property "Linear" do
      check all(domain <- domain(), range <- domain(), v <- value_in(domain)) do
        scale = Scale.linear() |> Scale.domain(domain) |> Scale.range(range)
        assert_round_trip(scale, identity(), v)
      end
    end

    property "Power, with negative domains and fractional exponents" do
      check all(
              domain <- domain(),
              range <- domain(),
              exponent <- member_of([0.5, 1, 2, 3]),
              v <- value_in(domain)
            ) do
        scale =
          Scale.power()
          |> Power.exponent(exponent)
          |> Scale.domain(domain)
          |> Scale.range(range)

        assert_round_trip(scale, signed_power(exponent), v)
      end
    end

    property "Symlog" do
      check all(
              domain <- domain(),
              range <- domain(),
              constant <- member_of([0.1, 1, 10]),
              v <- value_in(domain)
            ) do
        scale =
          Scale.symlog()
          |> Symlog.constant(constant)
          |> Scale.domain(domain)
          |> Scale.range(range)

        assert_round_trip(scale, symlog(constant), v)
      end
    end
  end
end
