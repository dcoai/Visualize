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
    defp bound, do: float(min: -1000.0, max: 1000.0)

    defp domain do
      gen all(d0 <- bound(), d1 <- bound(), abs(d1 - d0) > 1.0) do
        [d0, d1]
      end
    end

    defp value_in([d0, d1]), do: float(min: min(d0, d1), max: max(d0, d1))

    property "Linear" do
      check all(domain <- domain(), range <- domain(), v <- value_in(domain)) do
        scale = Scale.linear() |> Scale.domain(domain) |> Scale.range(range)
        assert_in_delta Scale.invert(scale, Scale.apply(scale, v)), v, 1.0e-6
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

        assert_in_delta Scale.invert(scale, Scale.apply(scale, v)), v, 1.0e-6 * max(1, abs(v))
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

        assert_in_delta Scale.invert(scale, Scale.apply(scale, v)), v, 1.0e-6 * max(1, abs(v))
      end
    end
  end
end
