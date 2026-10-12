defmodule Visualize.Unit.MetresisParityTest do
  # The metresis parity table (#589, D-155; `Visualize.MetresisParity`): every unit
  # metresis's §4.4 holds has a code here. This is the test metresis deletes its own
  # vocabulary against (metresis#429).
  use ExUnit.Case, async: true

  alias Visualize.{MetresisParity, Quantity, Unit}

  test "the table covers every family metresis declares" do
    covered =
      MapSet.new(
        Enum.map(MetresisParity.units(), &elem(&1, 0)) ++
          Map.keys(MetresisParity.unitless()) ++ [:currency]
      )

    assert covered == MapSet.new(MetresisParity.families())
    assert length(MetresisParity.families()) == 15
  end

  test "every metresis unit is expressible as a UCUM code visualize reads" do
    for {family, unit, _factor, code} <- MetresisParity.units() do
      assert Unit.valid?(code), "#{family} #{unit} → #{code}"
    end

    for {_family, code} <- MetresisParity.unitless(), code != nil, do: assert(Unit.valid?(code))
    for iso <- MetresisParity.currencies(), do: assert(Unit.valid?("{iso4217:#{iso}}"))
  end

  test "a family's units share one dimension, so each converts within its family" do
    for {family, rows} <- Enum.group_by(MetresisParity.units(), &elem(&1, 0)) do
      dimensions = rows |> Enum.map(&Unit.dimension(elem(&1, 3))) |> Enum.uniq()
      assert [_one] = dimensions, "#{family}: #{inspect(dimensions)}"
    end
  end

  test "two metresis units are two codes, so no unit is folded into another" do
    codes = Enum.map(MetresisParity.units(), &elem(&1, 3))
    assert codes == Enum.uniq(codes)
  end

  test "metresis's symbols are read by parse_alias/1 or named among its choices" do
    for {_family, unit, _factor, code} <- MetresisParity.units() do
      case Unit.parse_alias(unit) do
        {:ok, read} ->
          assert Unit.dimension(read) == Unit.dimension(code), unit
          assert Unit.factor(read) == Unit.factor(code), unit

        {:error, {:ambiguous, ^unit, choices}} ->
          assert code in Enum.map(choices, &elem(&1, 0)), unit
      end
    end
  end

  describe "quantities (spec/05 §4.2)" do
    test "every metresis family is a quantity here, and every unit implies it" do
      quantities = MetresisParity.quantities()
      assert Map.keys(quantities) |> Enum.sort() == Enum.sort(MetresisParity.families())

      for {family, unit, _factor, code} <- MetresisParity.units() do
        quantity = Map.fetch!(quantities, family)
        assert Quantity.of_unit(code) == quantity, "#{family} #{unit}"
        assert {:ok, _} = Quantity.resolve(%{unit: code, quantity: quantity})
      end

      for iso <- MetresisParity.currencies(),
          do: assert(Quantity.of_unit("{iso4217:#{iso}}") == :currency)
    end

    test "every sum metresis excludes is excluded here, and the further ones are named" do
      quantities = MetresisParity.quantities()

      for family <- MetresisParity.families(), quantity = quantities[family], quantity != nil do
        additive = Quantity.additivity(quantity)
        excluded? = not additive.across and not additive.over_time

        cond do
          family in MetresisParity.excludes_sum() -> assert excluded?, "#{family}"
          family in MetresisParity.excludes_more() -> assert excluded?, "#{family}"
          true -> refute excluded?, "#{family}"
        end
      end
    end

    test "metresis's bounds are the quantity's here, but where #589 decided otherwise" do
      quantities = MetresisParity.quantities()

      for {family, {min, max}} <- MetresisParity.bounds(),
          family not in MetresisParity.bounds_differ() do
        quantity = quantities[family]
        unit = if family == :percent, do: "%", else: Quantity.base_unit(quantity)

        {vmin, vmax} =
          if unit, do: Quantity.bounds(quantity, unit), else: Quantity.bounds(quantity)

        assert {vmin && vmin * 1.0, vmax && vmax * 1.0} == {min, max}, "#{family}"
      end
    end
  end
end
