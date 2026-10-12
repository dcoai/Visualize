defmodule Visualize.Quantity.FactsTest do
  # The facts every quantity carries and the unit systems (spec/05 §4.2–4.3, D-155).
  use ExUnit.Case, async: true

  alias Visualize.{Quantity, Scale, Unit}

  describe "every quantity has every fact" do
    test "a base unit of its own dimension, a kind, bounds and additivity" do
      for q <- Quantity.all() do
        assert Quantity.kind(q) in [:linear, :affine, :logarithmic, :cyclic], "#{q}"
        assert {min, max} = Quantity.bounds(q)
        assert min == nil or is_number(min)
        assert max == nil or is_number(max)
        assert %{across: across, over_time: over_time} = Quantity.additivity(q)
        assert is_boolean(across) and is_boolean(over_time)

        if q != :currency do
          base = Quantity.base_unit(q)
          assert Quantity.resolve(%{unit: base, quantity: q}) == {:ok, %{unit: base, quantity: q}}
        end
      end
    end

    test "the kinds: a temperature is affine, a sound level logarithmic, an angle cyclic" do
      kinds = Map.new(Quantity.all(), &{&1, Quantity.kind(&1)})
      assert kinds.temperature == :affine
      assert kinds.sound_level == :logarithmic
      assert kinds.angle == :cyclic

      assert kinds
             |> Map.drop([:temperature, :sound_level, :angle])
             |> Map.values()
             |> Enum.uniq() ==
               [:linear]
    end

    test "every family member reads, has its quantity's dimension and one shape in its family" do
      for q <- Quantity.all(), q != :currency, system <- Quantity.systems() do
        family = Quantity.family(q, nil, system)

        for member <- family do
          assert Unit.dimension(member) == Unit.dimension(Quantity.base_unit(q)),
                 "#{q} #{system} #{member}"
        end

        if Quantity.kind(q) != :affine do
          factors = Enum.map(family, &Unit.convert(1, &1, Quantity.base_unit(q)))
          assert factors == Enum.sort(factors), "#{q} #{system}: smallest first"
        end
      end
    end
  end

  describe "bounds are a display hint (spec/05 §4.2)" do
    test "in the base unit, and converted into another unit of the quantity" do
      assert Quantity.bounds(:angle) == {0, 360}
      assert Quantity.bounds(:angle, "rad") == {0.0, 2 * :math.pi()}
      assert Quantity.bounds(:ratio) == {0, 1}
      assert Quantity.bounds(:ratio, "%") == {0.0, 100.0}
      assert Quantity.bounds(:duration, "ms") == {0.0, nil}
      assert Quantity.bounds(:temperature, "[degF]") == {nil, nil}
      assert Quantity.bounds(:currency, "{iso4217:USD}") == {nil, nil}
    end

    test "a value outside them is never refused" do
      assert {:ok, _} = Quantity.resolve(%{unit: "s", quantity: :duration})
      domain = [-30, -10]
      assert Quantity.display_unit(domain, %{unit: "s"}) == "s"

      formatter = Quantity.formatter(Scale.linear() |> Scale.domain(domain), %{unit: "s"})
      assert formatter.(-30) == "−30 s" or formatter.(-30) == "-30 s"
    end
  end

  describe "additivity depends on the aggregation (spec/05 §4.2)" do
    test "the physical defaults" do
      across_only = [:data_rate, :frequency, :power, :electric_current]
      both = [:duration, :information, :count, :length, :energy, :area, :volume, :mass]
      both = both ++ [:currency, :electric_charge]

      for q <- across_only,
          do: assert(Quantity.additivity(q) == %{across: true, over_time: false})

      for q <- both, do: assert(Quantity.additivity(q) == %{across: true, over_time: true})

      for q <- Quantity.all() -- (across_only ++ both),
          do: assert(Quantity.additivity(q) == %{across: false, over_time: false}, "#{q}")
    end

    test "a metric kind refines the sum over time and never the sum across" do
      for q <- [nil | Quantity.all()] do
        %{across: across} = Quantity.additivity(q)
        assert Quantity.additivity(q, :gauge) == %{across: across, over_time: false}
        assert Quantity.additivity(q, :rate) == %{across: across, over_time: false}
        assert Quantity.additivity(q, :counter) == %{across: across, over_time: across}
      end

      assert Quantity.additivity(nil) == %{across: true, over_time: true}
      assert Quantity.additivity(:count, :gauge) == %{across: true, over_time: false}
      assert Quantity.additivity(:data_rate, :counter) == %{across: true, over_time: true}
    end
  end

  describe "unit systems (spec/05 §4.2–4.3)" do
    test "the four systems" do
      assert Quantity.systems() == [:metric, :us, :uk, :as_posted]
    end

    test "a system shows a quantity in its own family, US and UK apart" do
      cases = [
        {[0, 80], "kg", :us, "[lb_av]"},
        {[0, 100], "kg", :uk, "[stone_av]"},
        {[0, 200], "[lb_av]", :metric, "kg"},
        {[0, 20], "l", :us, "[gal_us]"},
        {[0, 20], "l", :uk, "[gal_br]"},
        {[0, 1], "l", :uk, "[pt_br]"},
        {[0, 0.5], "l", :uk, "[foz_br]"},
        {[0, 5000], "m", :us, "[mi_i]"},
        {[0, 2], "m", :uk, "[ft_i]"},
        {[0, 3], "[mi_i]", :metric, "km"},
        {[0, 30], "Cel", :us, "[degF]"},
        {[0, 30], "Cel", :uk, "Cel"},
        {[0, 80], "[degF]", :metric, "Cel"},
        {[0, 100], "km/h", :us, "[mi_i]/h"},
        {[0, 6], "min/km", :us, "min/[mi_i]"},
        {[0, 30], "[psi]", :metric, "kPa"},
        {[0, 5000], "m2", :us, "[acr_us]"},
        {[0, 1500], "ms", :us, "s"},
        {[0, 2_500_000], "By", :uk, "MBy"}
      ]

      for {domain, unit, system, display} <- cases do
        assert Quantity.display_unit(domain, %{unit: unit}, system: system) == display,
               inspect({domain, unit, system})
      end
    end

    test "as posted, a value keeps its unit's own family, rescaled within it" do
      assert Quantity.display_unit([0, 32], %{unit: "[oz_av]"}) == "[lb_av]"
      assert Quantity.display_unit([0, 10_000], %{unit: "[ft_i]"}) == "[mi_i]"
      assert Quantity.display_unit([0, 5], %{unit: "[gal_br]"}) == "[gal_br]"
      assert Quantity.display_unit([0, 1500], %{unit: "g"}) == "kg"
      assert Quantity.display_unit([0, 900], %{unit: "mbar"}) == "mbar"
      assert Quantity.display_unit([0, 900], %{unit: "[nmi_i]"}) == "[nmi_i]"
      assert Quantity.display_unit([0, 90], %{unit: "K"}) == "K"
      assert Quantity.display_unit([0, 2000], %{unit: "mA.h"}) == "A.h"
    end

    test "a zero magnitude keeps a unit in the family, else takes the member nearest it" do
      assert Quantity.display_unit([0, 0], %{unit: "kg"}, system: :metric) == "kg"
      assert Quantity.display_unit([0, 0], %{unit: "kg"}, system: :us) == "[lb_av]"
      assert Quantity.display_unit([0, 0], %{unit: "mg"}, system: :us) == "[oz_av]"
    end

    test "a preference across dimensions is not a system: glucose and pace stay as given" do
      for system <- Quantity.systems() do
        assert Quantity.display_unit([0, 120], %{unit: "mg/dl"}, system: system) == "mg/dl"
        assert Quantity.display_unit([0, 7], %{unit: "mmol/l"}, system: system) == "mmol/l"

        assert Quantity.display_unit([0, 12], %{unit: "km/h"}, system: system) in [
                 "km/h",
                 "[mi_i]/h"
               ]
      end
    end

    test "the tick formatter follows the system" do
      scale = Scale.linear() |> Scale.domain([0, 1609.344])
      assert Quantity.formatter(scale, %{unit: "m"}, system: :us).(1609.344) == "1 mi"
      assert Quantity.formatter(scale, %{unit: "m"}).(1000) == "1 km"
      assert Quantity.formatter(scale, %{unit: "m"}, system: :metric).(1000) == "1 km"
    end
  end
end
