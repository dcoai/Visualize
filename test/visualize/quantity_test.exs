defmodule Visualize.QuantityTest do
  use ExUnit.Case, async: true

  alias Visualize.{Quantity, Scale, Unit}

  doctest Visualize.Quantity

  defp linear(domain), do: Scale.linear() |> Scale.domain(domain)
  defp log(domain), do: Scale.log() |> Scale.domain(domain)

  describe "the fixed list (spec/05 §4.2)" do
    test "twelve quantities in order, each with a base unit that reads" do
      assert Quantity.all() == [
               :duration,
               :information,
               :data_rate,
               :frequency,
               :ratio,
               :count,
               :temperature,
               :length,
               :speed,
               :power,
               :energy,
               :pressure
             ]

      for q <- Quantity.all(), do: assert(Unit.valid?(Quantity.base_unit(q)), "#{q}")
    end

    test "each base unit implies its own quantity; a ratio is the percent" do
      for q <- Quantity.all() -- [:ratio],
          do: assert(Quantity.of_unit(Quantity.base_unit(q)) == q, "#{q}")

      assert Quantity.of_unit("%") == :ratio
      assert Quantity.of_unit("{request}") == :count
      assert Quantity.of_unit("kW.h") == :energy
      assert Quantity.of_unit("km/h") == :speed
      assert Quantity.of_unit("{request}/s") == :frequency
      assert Quantity.of_unit("K") == :temperature
      assert Quantity.of_unit("g") == nil
      assert Quantity.of_unit("m2") == nil
    end

    test "every family member reads and has its quantity's dimension" do
      units = %{
        information: ["By", "MiBy", "bit"],
        data_rate: ["By/s", "MiBy/s", "bit/s"],
        frequency: ["Hz", "/s"],
        energy: ["J", "kW.h"]
      }

      for q <- Quantity.all(),
          unit <- Map.get(units, q, [Quantity.base_unit(q)]),
          member <- Quantity.family(q, unit) do
        assert Unit.dimension(member) == Unit.dimension(Quantity.base_unit(q)), member
      end
    end

    test "the unit picks the family: decimal by default, binary, bits, hertz, watt-hours" do
      assert Quantity.family(:information, "By") == ~w(By kBy MBy GBy)
      assert Quantity.family(:information, "kBy") == ~w(By kBy MBy GBy)
      assert Quantity.family(:information, nil) == ~w(By kBy MBy GBy)
      assert Quantity.family(:information, "MiBy") == ~w(By KiBy MiBy GiBy)
      assert Quantity.family(:information, "Mbit") == ~w(bit kbit Mbit Gbit)
      assert Quantity.family(:data_rate, "KiBy/s") == ~w(By/s KiBy/s MiBy/s GiBy/s)
      assert Quantity.family(:frequency, "kHz") == ~w(Hz kHz MHz GHz)
      assert Quantity.family(:frequency, "{request}/s") == ~w(/h /min /s)
      assert Quantity.family(:energy, "kW.h") == ~w(W.h kW.h MW.h GW.h)
      assert Quantity.family(:energy, "J") == ~w(J kJ MJ GJ)

      for q <- [:ratio, :count, :temperature, :speed], do: assert(Quantity.family(q, nil) == [])
    end
  end

  describe "resolve/1" do
    test "a unit implies its quantity and a quantity its base unit" do
      assert Quantity.resolve(%{unit: "ms"}) == {:ok, %{unit: "ms", quantity: :duration}}
      assert Quantity.resolve(%{quantity: :count}) == {:ok, %{unit: "1", quantity: :count}}
      assert Quantity.resolve(%{unit: "g"}) == {:ok, %{unit: "g", quantity: nil}}
      assert Quantity.resolve(%{}) == {:ok, %{unit: nil, quantity: nil}}
    end

    test "a pair whose dimensions agree resolves, one that does not is refused" do
      assert Quantity.resolve(%{unit: "%", quantity: :ratio}) ==
               {:ok, %{unit: "%", quantity: :ratio}}

      assert Quantity.resolve(%{unit: "1", quantity: :ratio}) ==
               {:ok, %{unit: "1", quantity: :ratio}}

      assert Quantity.resolve(%{unit: "{core}", quantity: :count}) ==
               {:ok, %{unit: "{core}", quantity: :count}}

      assert Quantity.resolve(%{unit: "By", quantity: :duration}) ==
               {:error, {:quantity, :duration, "By"}}

      assert Quantity.resolve(%{unit: "s", quantity: :count}) ==
               {:error, {:quantity, :count, "s"}}
    end

    test "a code that does not read and a quantity not in the list are refused" do
      assert Quantity.resolve(%{unit: "sec"}) == {:error, {:unit, "sec", {:unknown_atom, "sec"}}}
      assert Quantity.resolve(%{quantity: :mass}) == {:error, {:unknown_quantity, :mass}}
    end
  end

  describe "display_unit/2: each quantity scales across its range (spec/05 §4.3)" do
    @cases [
      {%{unit: "ns"}, 500, "ns"},
      {%{unit: "s"}, 0.0005, "us"},
      {%{unit: "ms"}, 900, "ms"},
      {%{unit: "ms"}, 1500, "s"},
      {%{unit: "s"}, 59, "s"},
      {%{unit: "s"}, 90, "min"},
      {%{unit: "s"}, 7_200, "h"},
      {%{unit: "s"}, 259_200, "d"},
      {%{unit: "ms"}, 1.0e12, "d"},
      {%{quantity: :information}, 999, "By"},
      {%{unit: "By"}, 1500, "kBy"},
      {%{unit: "By"}, 2_500_000, "MBy"},
      {%{unit: "kBy"}, 3_000_000, "GBy"},
      {%{unit: "MiBy"}, 2048, "GiBy"},
      {%{unit: "KiBy"}, 0.5, "By"},
      {%{unit: "bit"}, 1.0e6, "Mbit"},
      {%{unit: "By/s"}, 1500, "kBy/s"},
      {%{unit: "bit/s"}, 2.0e9, "Gbit/s"},
      {%{unit: "Hz"}, 1500, "kHz"},
      {%{unit: "{request}/s"}, 50, "/s"},
      {%{unit: "{request}/s"}, 0.5, "/min"},
      {%{unit: "/s"}, 0.001, "/h"},
      {%{unit: "%"}, 1500, "%"},
      {%{quantity: :count}, 1.0e6, "1"},
      {%{unit: "Cel"}, 1500, "Cel"},
      {%{unit: "m"}, 0.5, "mm"},
      {%{unit: "m"}, 1500, "km"},
      {%{unit: "km/h"}, 1500, "km/h"},
      {%{unit: "W"}, 3_000, "kW"},
      {%{unit: "kW"}, 2_000, "MW"},
      {%{unit: "J"}, 1500, "kJ"},
      {%{unit: "kW.h"}, 1500, "MW.h"},
      {%{unit: "Pa"}, 101_325, "kPa"},
      {%{unit: "kPa"}, 2_000, "MPa"}
    ]

    test "the largest member the magnitude fills to at least one, else the smallest" do
      for {measure, top, display} <- @cases do
        assert Quantity.display_unit([0, top], measure) == display, inspect({measure, top})
      end
    end

    test "the magnitude is the greatest |d|, and zero, no quantity or no unit keep the unit" do
      assert Quantity.display_unit([-1500, 10], %{unit: "ms"}) == "s"
      assert Quantity.display_unit([0, 0], %{unit: "ms"}) == "ms"
      assert Quantity.display_unit([0, 1500], %{unit: "g"}) == "g"
      assert Quantity.display_unit([0, 1500], %{}) == nil
    end
  end

  describe "formatter/3" do
    defp labels(scale, measure, values),
      do: Enum.map(values, Quantity.formatter(scale, measure))

    test "ticks are scaled into the display unit and followed by its symbol" do
      assert labels(linear([0, 1500]), %{unit: "ms"}, [0, 500, 1000, 1500]) ==
               ["0 s", "0.5 s", "1 s", "1.5 s"]

      assert labels(linear([0, 900]), %{unit: "ms"}, [0, 450, 900]) == [
               "0 ms",
               "450 ms",
               "900 ms"
             ]

      assert labels(linear([0, 2_500_000]), %{unit: "By"}, [0, 1_000_000, 2_500_000]) ==
               ["0 MB", "1 MB", "2.5 MB"]

      assert labels(linear([0, 100]), %{unit: "%"}, [0, 45]) == ["0%", "45%"]
      assert labels(linear([-10, 30]), %{unit: "Cel"}, [-10, 20]) == ["-10 °C", "20 °C"]
      assert labels(linear([0, 0.5]), %{unit: "{request}/s"}, [0.25, 0.5]) == ["15/min", "30/min"]
      assert labels(linear([0, 3_000]), %{quantity: :power}, [1500]) == ["1.5 kW"]
    end

    test "a count is SI from a thousand with one prefix, and has no symbol" do
      assert labels(linear([0, 90_000]), %{unit: "{conn}"}, [0, 45_000, 90_000]) ==
               ["0", "45k", "90k"]

      assert labels(linear([0, 900]), %{quantity: :count}, [450]) == ["450"]
      assert labels(linear([0, 2.0e6]), %{quantity: :count}, [500_000]) == ["0.5M"]
    end

    test "the scaled domain's notation groups and prefixes as #532's does" do
      assert labels(linear([0, 1500]), %{unit: "d"}, [1500]) == ["1,500 d"]
      assert labels(linear([0, 1500]), %{unit: "Cel"}, [1500]) == ["1,500 °C"]
    end

    test "a log axis gives each tick its own unit, a power of ten from the scale's" do
      assert labels(log([0.001, 1000]), %{unit: "s"}, [0.001, 0.01, 0.1, 1, 10, 100, 1000]) ==
               ["1 ms", "10 ms", "100 ms", "1 s", "10 s", "100 s", "1k s"]

      assert labels(log([1, 1.0e9]), %{unit: "By"}, [1, 1000, 1.0e6, 1.0e9]) ==
               ["1 B", "1 kB", "1 MB", "1 GB"]

      assert labels(log([1, 1.0e6]), %{unit: "{x}"}, [1, 1000, 1.0e6]) == ["1", "1k", "1M"]
    end

    test "a non-number is to_string/1, and the other scales are #532's formatter" do
      assert Quantity.formatter(linear([0, 1]), %{unit: "s"}).(:gap) == "gap"
      assert Quantity.formatter(Scale.band() |> Scale.domain([:a, :b]), %{unit: "s"}) == nil

      time = Scale.time() |> Scale.domain([~U[2024-03-01 00:00:00Z], ~U[2024-03-01 02:00:00Z]])
      assert Quantity.formatter(time, %{unit: "s"}).(~U[2024-03-01 01:00:00Z]) == "01:00"
    end

    test "no unit is #532's derived format; a refused measure and an unknown locale raise" do
      assert labels(linear([0, 90_000]), %{}, [90_000]) == ["90,000"]

      assert_raise ArgumentError, ~r/not a measure/, fn ->
        Quantity.formatter(linear([0, 1]), %{unit: "sec"})
      end

      assert_raise ArgumentError, ~r/locale/, fn ->
        Quantity.formatter(linear([0, 1]), %{unit: "s"}, locale: "fr")
      end

      assert_raise ArgumentError, ~r/locale/, fn ->
        Quantity.formatter(log([1, 10]), %{unit: "s"}, locale: "fr")
      end
    end
  end

  describe "the label rule: the unit, else the quantity, else nothing (spec/05 §4.3)" do
    test "the unit's symbol, its annotations written" do
      assert Quantity.label(%{unit: "ms"}) == "ms"
      assert Quantity.label(%{unit: "kW.h", quantity: :energy}) == "kW·h"
      assert Quantity.label(%{unit: "{request}/s"}) == "request/s"
      assert Quantity.label(%{unit: "{request}"}) == "request"
      assert Quantity.label(%{quantity: :duration}) == "s"
    end

    test "else the quantity's name, else nothing" do
      assert Quantity.label(%{quantity: :count}) == "count"
      assert Quantity.label(%{unit: "1", quantity: :ratio}) == "ratio"
      assert Quantity.label(%{unit: "1"}) == "count"
      assert Quantity.label(%{}) == nil
    end

    test "suffix/1 separates a symbol by a space, but % and a rate attach" do
      assert Quantity.suffix("s") == " s"
      assert Quantity.suffix("%") == "%"
      assert Quantity.suffix("/min") == "/min"
      assert Quantity.suffix("1") == ""
      assert Quantity.suffix(nil) == ""
    end
  end
end
