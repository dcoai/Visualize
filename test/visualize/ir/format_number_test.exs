defmodule Visualize.IR.FormatNumberTest do
  @moduledoc """
  `Visualize.IR.Path.format_number/1` (spec/09 §1.3, D-12, D-32) writes every number of
  every drawing; #812 made it build only the text it returns, and held it to the form it
  wrote before.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Visualize.IR.Path

  # The form before #812: four decimals, then the zeros and the point trimmed.
  defp before(n) do
    :erlang.float_to_binary(Float.round(n, 4) + 0.0, decimals: 4)
    |> String.trim_trailing("0")
    |> String.trim_trailing(".")
  end

  property "a float is written as it was" do
    check all(
            mantissa <- float(min: -1.0, max: 1.0),
            exponent <- integer(-12..30)
          ) do
      n = mantissa * :math.pow(10, exponent)
      assert Path.format_number(n) == before(n)
    end
  end

  test "whole values, halves at the fourth decimal, and the signs of zero" do
    for n <- [0.0, -0.0, -0.00001, 0.00005, 2.99999, 9.99995, -9.99995, 1.0e20, 0.1 + 0.2] do
      assert Path.format_number(n) == before(n), "#{n}"
    end

    assert Path.format_number(-0.0) == "0"
    assert Path.format_number(12.5) == "12.5"
    assert Path.format_number(3) == "3"
  end

  test "a float past what four decimals can write is its digits" do
    assert Path.format_number(1.0e300) == Integer.to_string(trunc(1.0e300))
  end
end
