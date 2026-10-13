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

      celsius = Scale.linear() |> Scale.domain([0, 100])
      assert Quantity.formatter(celsius, %{unit: "Cel"}, system: :us).(100) == "212 °F"
      assert Quantity.formatter(celsius, %{unit: "Cel"}, system: :us).(-40) == "-40 °F"
    end
  end

  describe "conventions: a system picks within one, never across (spec/05 §4.2, D-158)" do
    test "the proposal's four calls" do
      assert Quantity.display_unit([], %{unit: "hPa"}, system: :us) == "[in_i'Hg]"
      assert Quantity.display_unit([], %{unit: "mm[Hg]"}, system: :metric) == "mm[Hg]"
      assert Quantity.display_unit([], %{unit: "mm[Hg]"}, system: :us) == "mm[Hg]"
      assert Quantity.display_unit([0, 300_000], %{unit: "kPa"}, system: :us) == "[psi]"
    end

    test "barometric: hPa and mbar are hPa under metric and UK, inches of mercury under US" do
      assert Quantity.display_unit([0, 1013], %{unit: "mbar"}, system: :metric) == "hPa"
      assert Quantity.display_unit([0, 1013], %{unit: "mbar"}, system: :uk) == "hPa"
      assert Quantity.display_unit([0, 1013], %{unit: "mbar"}, system: :us) == "[in_i'Hg]"
      assert Quantity.display_unit([0, 1013], %{unit: "hPa"}, system: :uk) == "hPa"
      assert Quantity.display_unit([0, 30], %{unit: "[in_i'Hg]"}, system: :metric) == "hPa"
      assert Quantity.display_unit([0, 30], %{unit: "[in_i'Hg]"}, system: :us) == "[in_i'Hg]"
      assert Quantity.format(1013.25, %{unit: "hPa"}, system: :us) == "29.92 inHg"
    end

    test "as posted keeps the unit's own ladder inside its convention" do
      assert Quantity.display_unit([900, 1100], %{unit: "hPa"}) == "hPa"
      assert Quantity.display_unit([0, 3], %{unit: "bar"}) == "bar"
      assert Quantity.display_unit([0, 1013], %{unit: "mbar"}) == "mbar"
      assert Quantity.display_unit([0, 120], %{unit: "mm[Hg]"}) == "mm[Hg]"
      assert Quantity.display_unit([0, 300_000], %{unit: "Pa"}) == "kPa"
    end

    test "gauge: bar is gauge's but out of the metric ladder, so 3 bar is 300 kPa" do
      assert Quantity.family(:pressure, "bar", :metric) == ~w(Pa kPa MPa)
      assert Quantity.display_unit([0, 3], %{unit: "bar"}, system: :metric) == "kPa"
      assert Quantity.display_unit([0, 3], %{unit: "bar"}, system: :us) == "[psi]"
      assert Quantity.display_unit([0, 30], %{unit: "[psi]"}, system: :metric) == "kPa"
    end

    test "exact code first, then shape: a prefix no convention lists falls back to gauge" do
      assert Quantity.family(:pressure, "hPa", :metric) == ~w(hPa)
      assert Quantity.family(:pressure, "kPa", :metric) == ~w(Pa kPa MPa)
      assert Quantity.family(:pressure, "dPa", :metric) == ~w(Pa kPa MPa)
      assert Quantity.family(:pressure, "dPa", :us) == ~w([psi])
      assert Quantity.family(:pressure, "dPa") == ~w(Pa kPa MPa)
      assert Quantity.display_unit([0, 50_000], %{unit: "dPa"}, system: :metric) == "kPa"
      assert Quantity.family(:pressure, nil, :us) == ~w([psi])
    end

    test "clinical: mm[Hg] keeps its unit in every system" do
      for system <- Quantity.systems() do
        assert Quantity.family(:pressure, "mm[Hg]", system) == ~w(mm[Hg])
        assert Quantity.display_unit([60, 180], %{unit: "mm[Hg]"}, system: system) == "mm[Hg]"
      end
    end

    test "an axis over hPa under US ticks in round inches of mercury" do
      scale = Scale.linear() |> Scale.domain([950, 1050])
      measure = %{unit: "hPa"}
      ticks = Quantity.ticks(scale, measure, system: :us, count: 5)
      labels = Enum.map(ticks, Quantity.formatter(scale, measure, system: :us, count: 5))

      assert labels == ["28.5 inHg", "29 inHg", "29.5 inHg", "30 inHg", "30.5 inHg", "31 inHg"]

      for {tick, inches} <- Enum.zip(ticks, [28.5, 29.0, 29.5, 30.0, 30.5, 31.0]),
          do: assert_in_delta(Unit.convert(tick, "hPa", "[in_i'Hg]"), inches, 1.0e-9)
    end

    # Every family/3 answer of every other quantity as origin/main gave it before D-158,
    # computed there over each quantity's base unit, every family member and some units
    # of no family: `{quantity, units, [metric, us, uk, as_posted]}`.
    @before [
      {:duration, [nil, "s", "ns", "us", "ms", "min", "h", "d", "ks"],
       [
         ~w(ns us ms s min h d),
         ~w(ns us ms s min h d),
         ~w(ns us ms s min h d),
         ~w(ns us ms s min h d)
       ]},
      {:information, [nil, "By", "kBy", "MBy", "GBy", "TBy"],
       [
         ~w(By kBy MBy GBy TBy),
         ~w(By kBy MBy GBy TBy),
         ~w(By kBy MBy GBy TBy),
         ~w(By kBy MBy GBy TBy)
       ]},
      {:information, ["KiBy", "MiBy", "GiBy", "TiBy"],
       [
         ~w(By KiBy MiBy GiBy TiBy),
         ~w(By KiBy MiBy GiBy TiBy),
         ~w(By KiBy MiBy GiBy TiBy),
         ~w(By KiBy MiBy GiBy TiBy)
       ]},
      {:information, ["bit", "kbit", "Mbit", "Gbit", "Tbit"],
       [
         ~w(bit kbit Mbit Gbit Tbit),
         ~w(bit kbit Mbit Gbit Tbit),
         ~w(bit kbit Mbit Gbit Tbit),
         ~w(bit kbit Mbit Gbit Tbit)
       ]},
      {:data_rate, [nil, "By/s", "kBy/s", "MBy/s", "GBy/s", "TBy/s"],
       [
         ~w(By/s kBy/s MBy/s GBy/s TBy/s),
         ~w(By/s kBy/s MBy/s GBy/s TBy/s),
         ~w(By/s kBy/s MBy/s GBy/s TBy/s),
         ~w(By/s kBy/s MBy/s GBy/s TBy/s)
       ]},
      {:data_rate, ["KiBy/s", "MiBy/s", "GiBy/s", "TiBy/s"],
       [
         ~w(By/s KiBy/s MiBy/s GiBy/s TiBy/s),
         ~w(By/s KiBy/s MiBy/s GiBy/s TiBy/s),
         ~w(By/s KiBy/s MiBy/s GiBy/s TiBy/s),
         ~w(By/s KiBy/s MiBy/s GiBy/s TiBy/s)
       ]},
      {:data_rate, ["bit/s", "kbit/s", "Mbit/s", "Gbit/s", "Tbit/s"],
       [
         ~w(bit/s kbit/s Mbit/s Gbit/s Tbit/s),
         ~w(bit/s kbit/s Mbit/s Gbit/s Tbit/s),
         ~w(bit/s kbit/s Mbit/s Gbit/s Tbit/s),
         ~w(bit/s kbit/s Mbit/s Gbit/s Tbit/s)
       ]},
      {:frequency, [nil, "Hz", "kHz", "MHz", "GHz"],
       [~w(Hz kHz MHz GHz), ~w(Hz kHz MHz GHz), ~w(Hz kHz MHz GHz), ~w(Hz kHz MHz GHz)]},
      {:frequency, ["/h", "/min", "/s"],
       [~w(/h /min /s), ~w(/h /min /s), ~w(/h /min /s), ~w(/h /min /s)]},
      {:ratio, [nil, "1"], [[], [], [], []]},
      {:count, [nil, "1"], [[], [], [], []]},
      {:temperature, [nil, "Cel"], [~w(Cel), ~w([degF]), ~w(Cel), ~w(Cel)]},
      {:temperature, ["[degF]"], [~w(Cel), ~w([degF]), ~w(Cel), ~w([degF])]},
      {:temperature, ["K"], [~w(Cel), ~w([degF]), ~w(Cel), []]},
      {:length, [nil, "m", "mm", "cm", "km", "dm"],
       [~w(mm cm m km), ~w([in_i] [ft_i] [mi_i]), ~w([in_i] [ft_i] [mi_i]), ~w(mm cm m km)]},
      {:length, ["[in_i]", "[ft_i]", "[mi_i]"],
       [
         ~w(mm cm m km),
         ~w([in_i] [ft_i] [mi_i]),
         ~w([in_i] [ft_i] [mi_i]),
         ~w([in_i] [ft_i] [mi_i])
       ]},
      {:length, ["[nmi_i]"],
       [~w(mm cm m km), ~w([in_i] [ft_i] [mi_i]), ~w([in_i] [ft_i] [mi_i]), []]},
      {:speed, [nil, "m/s"], [~w(km/h), ~w([mi_i]/h), ~w([mi_i]/h), []]},
      {:speed, ["km/h"], [~w(km/h), ~w([mi_i]/h), ~w([mi_i]/h), ~w(km/h)]},
      {:speed, ["[mi_i]/h"], [~w(km/h), ~w([mi_i]/h), ~w([mi_i]/h), ~w([mi_i]/h)]},
      {:power, [nil, "W", "kW", "MW", "GW"],
       [~w(W kW MW GW), ~w(W kW MW GW), ~w(W kW MW GW), ~w(W kW MW GW)]},
      {:energy, [nil, "J", "kJ", "MJ", "GJ"],
       [~w(J kJ MJ GJ), ~w(J kJ MJ GJ), ~w(J kJ MJ GJ), ~w(J kJ MJ GJ)]},
      {:energy, ["W.h", "kW.h", "MW.h", "GW.h"],
       [
         ~w(W.h kW.h MW.h GW.h),
         ~w(W.h kW.h MW.h GW.h),
         ~w(W.h kW.h MW.h GW.h),
         ~w(W.h kW.h MW.h GW.h)
       ]},
      {:energy, ["cal", "kcal"], [~w(cal kcal), ~w(cal kcal), ~w(cal kcal), ~w(cal kcal)]},
      {:area, [nil, "m2", "cm2", "har", "km2"],
       [
         ~w(cm2 m2 har km2),
         ~w([ft_i]2 [acr_us] [mi_i]2),
         ~w([ft_i]2 [acr_us] [mi_i]2),
         ~w(cm2 m2 har km2)
       ]},
      {:area, ["[ft_i]2", "[acr_us]", "[mi_i]2"],
       [
         ~w(cm2 m2 har km2),
         ~w([ft_i]2 [acr_us] [mi_i]2),
         ~w([ft_i]2 [acr_us] [mi_i]2),
         ~w([ft_i]2 [acr_us] [mi_i]2)
       ]},
      {:volume, [nil, "l", "ml", "m3", "dl"],
       [~w(ml l m3), ~w([foz_us] [pt_us] [gal_us]), ~w([foz_br] [pt_br] [gal_br]), ~w(ml l m3)]},
      {:volume, ["[foz_us]", "[pt_us]", "[gal_us]"],
       [
         ~w(ml l m3),
         ~w([foz_us] [pt_us] [gal_us]),
         ~w([foz_br] [pt_br] [gal_br]),
         ~w([foz_us] [pt_us] [gal_us])
       ]},
      {:volume, ["[foz_br]", "[pt_br]", "[gal_br]"],
       [
         ~w(ml l m3),
         ~w([foz_us] [pt_us] [gal_us]),
         ~w([foz_br] [pt_br] [gal_br]),
         ~w([foz_br] [pt_br] [gal_br])
       ]},
      {:mass, [nil, "g", "mg", "kg", "t"],
       [~w(mg g kg t), ~w([oz_av] [lb_av]), ~w([oz_av] [lb_av] [stone_av]), ~w(mg g kg t)]},
      {:mass, ["[oz_av]", "[lb_av]"],
       [~w(mg g kg t), ~w([oz_av] [lb_av]), ~w([oz_av] [lb_av] [stone_av]), ~w([oz_av] [lb_av])]},
      {:mass, ["[stone_av]"],
       [
         ~w(mg g kg t),
         ~w([oz_av] [lb_av]),
         ~w([oz_av] [lb_av] [stone_av]),
         ~w([oz_av] [lb_av] [stone_av])
       ]},
      {:pace, [nil, "s/m"], [~w(min/km), ~w(min/[mi_i]), ~w(min/[mi_i]), []]},
      {:pace, ["min/km"], [~w(min/km), ~w(min/[mi_i]), ~w(min/[mi_i]), ~w(min/km)]},
      {:pace, ["min/[mi_i]"], [~w(min/km), ~w(min/[mi_i]), ~w(min/[mi_i]), ~w(min/[mi_i])]},
      {:angle, [nil, "deg"], [[], [], [], []]},
      {:electric_potential, [nil, "V", "mV", "kV"],
       [~w(mV V kV), ~w(mV V kV), ~w(mV V kV), ~w(mV V kV)]},
      {:electric_current, [nil, "A", "mA"], [~w(mA A), ~w(mA A), ~w(mA A), ~w(mA A)]},
      {:electric_charge, [nil, "C"], [[], [], [], []]},
      {:electric_charge, ["mA.h", "A.h"],
       [~w(mA.h A.h), ~w(mA.h A.h), ~w(mA.h A.h), ~w(mA.h A.h)]},
      {:illuminance, [nil, "lx", "klx"], [~w(lx klx), ~w(lx klx), ~w(lx klx), ~w(lx klx)]},
      {:sound_level, [nil, "dB[SPL]"], [[], [], [], []]},
      {:mass_concentration, [nil, "g/l"], [[], [], [], []]},
      {:amount_concentration, [nil, "mol/l"], [[], [], [], []]}
    ]

    test "every other quantity's family/3 answers are unchanged" do
      for {quantity, units, answers} <- @before,
          unit <- units,
          {system, answer} <- Enum.zip(Quantity.systems(), answers) do
        assert Quantity.family(quantity, unit, system) == answer,
               inspect({quantity, unit, system})
      end

      assert @before |> Enum.map(&elem(&1, 0)) |> Enum.uniq() ==
               Quantity.all() -- [:pressure, :currency]
    end
  end
end
