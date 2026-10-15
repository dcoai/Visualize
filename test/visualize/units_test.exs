defmodule Visualize.UnitsTest do
  @moduledoc """
  `Visualize.Units` (spec/08 §13, #651, #671): CSS's fixed ratios for the absolute screen
  units, `em` and `pct` measured against their context, and the world lengths a scene
  will convert by (#620).
  """
  use ExUnit.Case, async: true

  import Visualize.Units

  alias Visualize.Units

  doctest Visualize.Units

  test "each constructor builds its unit value" do
    assert [px(1), pt(1), pc(1), inch(1), cm(1), mm(1), em(1), pct(1)] ==
             Enum.map(Units.units(), &{1, &1})
  end

  test "the absolute units convert at CSS's ratios: 96 px = 1 in = 2.54 cm = 25.4 mm = 72 pt" do
    assert Units.to_px(px(3)) == 3.0
    assert Units.to_px(inch(1)) == 96.0
    assert Units.to_px(pt(72)) == 96.0
    assert Units.to_px(pc(1)) == 16.0
    assert_in_delta Units.to_px(cm(2.54)), 96.0, 1.0e-9
    assert_in_delta Units.to_px(mm(25.4)), 96.0, 1.0e-9
    assert Units.convert(1, :pc, :pt) == 12.0
    assert_in_delta Units.convert(1, :in, :mm), 25.4, 1.0e-9
    assert Units.to_px(7) == 7
  end

  test "a relative unit is measured against its context, and refused without one" do
    assert Units.resolve(em(2), %{em: 10}) == 20.0
    assert Units.resolve(pct(25), %{box: 40}) == 10.0
    assert Units.resolve(pt(3), %{}) == 4.0
    assert Units.resolve(5, %{}) == 5

    assert_raise ArgumentError, ~r/an em needs a font size/, fn -> Units.resolve(em(1), %{}) end
    assert_raise ArgumentError, ~r/relative/, fn -> Units.to_px(pct(10)) end
  end

  test "unit?/1 knows the library's units and nothing else" do
    assert Units.unit?({1.5, :em})
    refute Units.unit?({1, :furlong})
    refute Units.unit?({:color, :red})
    refute Units.unit?(12)
  end

  test "the world lengths are the international ones, in metres" do
    assert Units.length_units() == [:mm, :cm, :m, :km, :in, :ft, :yd, :mi]
    assert Units.to_meters(1, :in) == 0.0254
    assert Units.to_meters(1, :mi) == 1609.344
    assert_in_delta Units.convert_length(1, :mi, :ft), 5280, 1.0e-9
    assert_in_delta Units.convert_length(3, :ft, :yd), 1, 1.0e-12
  end
end
