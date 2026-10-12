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

  describe "conversion (spec/05 §4.1)" do
    @values [0, 1, -3.5, 37, 1234.5, 1.0e6]

    test "every pair of units in a family converts as metresis converts it" do
      differs = MetresisParity.conversion_differs()

      for {family, rows} <- Enum.group_by(MetresisParity.units(), &elem(&1, 0)),
          {_, from, _, from_code} <- rows,
          {_, to, _, to_code} <- rows,
          value <- @values do
        theirs = MetresisParity.metresis_convert(value, family, from, to)
        ours = Unit.convert(value, from_code, to_code)
        label = "#{value} #{from} → #{to}: metresis #{theirs}, visualize #{ours}"

        if from != to and (Map.has_key?(differs, from) or Map.has_key?(differs, to)) do
          # UCUM's mercury, not metresis's: within 3 ppm, and not the same.
          assert_in_delta ours, theirs, abs(theirs) * 3.0e-6 + 1.0e-12, label
          if value != 0, do: refute(ours == theirs, label)
        else
          assert_in_delta ours, theirs, abs(theirs) * 1.0e-12 + 1.0e-9, label
        end
      end
    end

    test "°C↔°F is exact, including absolute zero and where the scales cross" do
      assert Unit.convert(-40, "Cel", "[degF]") ==
               MetresisParity.metresis_convert(-40, :temperature, "°C", "°F")

      assert Unit.convert(0, "K", "Cel") ==
               MetresisParity.metresis_convert(0, :temperature, "K", "°C")

      assert Unit.convert(100, "Cel", "[degF]") ==
               MetresisParity.metresis_convert(100, :temperature, "°C", "°F")
    end

    test "metresis's refusals are refusals here, named" do
      assert {:error, {:dimension, _, _}} = Unit.conversion("kg", "Cel")

      assert {:error, {:currency, _, _}} =
               Unit.conversion("{iso4217:USD}", "{iso4217:EUR}")

      assert Unit.conversion("{iso4217:USD}", "{iso4217:USD}") == {:ok, {{1, 1}, {0, 1}}}
    end
  end

  describe "formatting (spec/05 §2.6, §2.9, §4.3)" do
    @format_values [0, 1, 0.84, 91.4, 1234.5, -3.25, 5040, 90_061]

    test "every unit formats as metresis renders it, up to the named differences" do
      quantities = MetresisParity.quantities()
      symbols = MetresisParity.symbol_differs()

      for {family, unit, _factor, code} <- MetresisParity.units(),
          value <- @format_values,
          precision <- [0, 1, 2] do
        theirs = MetresisParity.metresis_render(value, family, unit, precision)

        expected =
          theirs
          |> String.replace(~r/(\d)(°[CF])$/, "\\1 \\2")
          |> then(fn s ->
            case symbols do
              %{^unit => ours} -> String.replace_suffix(s, unit, ours)
              _ -> s
            end
          end)

        measure = %{unit: code, quantity: quantities[family]}

        assert Quantity.format(value, measure, precision: precision) == expected,
               "#{family} #{unit} #{value} p#{precision}: metresis #{inspect(theirs)}"
      end
    end

    test "the unitless families format as metresis renders them" do
      for value <- @format_values, precision <- [0, 2] do
        assert Quantity.format(value, %{}, precision: precision) ==
                 MetresisParity.metresis_render(value, :number, nil, precision)

        assert Quantity.format(value, %{quantity: :count}, precision: precision) ==
                 MetresisParity.metresis_render(value, :count, nil, precision)

        assert Quantity.format(value, %{unit: "1", quantity: :ratio}, precision: precision) ==
                 MetresisParity.metresis_render(value, :ratio, nil, precision)
      end
    end

    test "currencies format as metresis renders them, but to their minor units" do
      for code <- MetresisParity.currencies(), value <- [0, 1240, -9.5, 1_234_567.891] do
        theirs = MetresisParity.metresis_render(value, :currency, code)
        ours = Quantity.format(value, %{unit: "{iso4217:#{code}}"})

        cond do
          Unit.minor_units(code) == 2 -> assert ours == theirs, "#{code} #{value}"
          value == trunc(value) -> assert ours == String.replace(theirs, ".00", ""), code
          true -> :rounded_to_its_minor_units
        end
      end

      assert Quantity.format(-9.5, %{unit: "{iso4217:JPY}"}) == "-¥10"

      assert Quantity.format(1240, %{unit: "{iso4217:JPY}"}) == "¥1,240"
      assert MetresisParity.metresis_render(1240, :currency, "JPY") == "¥1,240.00"
    end

    test "the formats that move: 1h 24m, 840ms, $1,240.00, 350°" do
      assert Quantity.format(5040, %{unit: "s"}) == "1h 24m"
      assert Quantity.format(0.84, %{unit: "s"}) == "840ms"
      assert Quantity.format(1240, %{unit: "{iso4217:USD}"}) == "$1,240.00"
      assert Quantity.format(350, %{unit: "deg"}, precision: 0) == "350°"
    end
  end
end
