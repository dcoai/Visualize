defmodule Visualize.Unit.MetresisParityTest do
  # The metresis parity table (#589, D-155; `Visualize.MetresisParity`): every unit
  # metresis's §4.4 holds has a code here. This is the test metresis deletes its own
  # vocabulary against (metresis#429).
  use ExUnit.Case, async: true

  alias Visualize.{MetresisParity, Unit}

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
end
