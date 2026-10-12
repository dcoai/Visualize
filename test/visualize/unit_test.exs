defmodule Visualize.UnitTest do
  use ExUnit.Case, async: true

  alias Visualize.Unit

  doctest Visualize.Unit

  # spec/05 §4.1's list of codes, every one of which reads.
  @codes ~w(s ms us ns min h d By kBy MBy GBy KiBy MiBy GiBy bit kbit Mbit % Hz kHz Cel
            [degF] K m mm km m/s km/h m2 s-1 W kW J kW.h Pa kPa 1 {request} {request}/s /s
            By{heap})

  describe "parse/1 (spec/05 §4.1)" do
    test "every listed code parses" do
      for code <- @codes, do: assert({:ok, [_ | _]} = Unit.parse(code), code)
    end

    test "every atom and every prefix on a metric atom reads" do
      for atom <- ~w(s min h d By bit % Hz Cel [degF] K m g W J Pa), do: assert(Unit.valid?(atom))

      for prefix <- ~w(k M G m u n Ki Mi Gi),
          atom <- ~w(s By bit Hz K m g W J Pa),
          do: assert(Unit.valid?(prefix <> atom), prefix <> atom)
    end

    test "typos and what UCUM does not say are refused, each with its reason" do
      assert Unit.parse("sec") == {:error, {:unknown_atom, "sec"}}
      assert Unit.parse("ft") == {:error, {:unknown_atom, "ft"}}
      assert Unit.parse("k[in_i]") == {:error, {:not_metric, "k", "[in_i]"}}
      assert Unit.parse("[in_i") == {:error, {:syntax, "[in_i"}}
      assert Unit.parse("mm[Hg") == {:error, {:syntax, "[Hg"}}
      assert Unit.parse("kmin") == {:error, {:not_metric, "k", "min"}}
      assert Unit.parse("k%") == {:error, {:not_metric, "k", "%"}}
      assert Unit.parse("{x") == {:error, {:syntax, "{x"}}
      assert Unit.parse("{}") == {:error, {:syntax, "{}"}}
      assert Unit.parse("m//s") == {:error, {:syntax, "/s"}}
      assert Unit.parse(".s") == {:error, {:syntax, ".s"}}
      assert Unit.parse("s^2") == {:error, {:syntax, "^2"}}
      assert Unit.parse("s-") == {:error, {:syntax, "-"}}
      assert Unit.parse("0") == {:error, {:syntax, "0"}}
      assert Unit.parse("10m") == {:error, {:syntax, "m"}}
      assert Unit.parse("(m)") == {:error, {:syntax, "(m)"}}
      assert Unit.parse("") == {:error, :empty}
      refute Unit.valid?(:s)
    end

    test "a symbol is matched whole before it is split into a prefix and an atom" do
      assert {:ok, [%{prefix: nil, atom: "min"}]} = Unit.parse("min")
      assert {:ok, [%{prefix: "m", atom: "m"}]} = Unit.parse("mm")
      assert {:ok, [%{prefix: "Mi", atom: "By"}]} = Unit.parse("MiBy")
      assert {:ok, [%{prefix: nil, atom: "Pa"}]} = Unit.parse("Pa")
    end

    test "a quotient negates its exponent, left-associatively, and a leading / the whole term" do
      assert {:ok,
              [%{atom: "g", exponent: 1}, %{atom: "m", exponent: -1}, %{atom: "s", exponent: 2}]} =
               Unit.parse("g/m.s2")

      assert {:ok, [%{atom: "s", exponent: -1}, %{atom: "m", exponent: -1}]} = Unit.parse("/s.m")
      assert {:ok, [%{atom: "s", exponent: -1}]} = Unit.parse("s-1")
      assert {:ok, [%{atom: "m", exponent: 2}]} = Unit.parse("m+2")
    end

    test "an annotation stands alone or follows a unit or a factor" do
      assert {:ok, [%{annotation: "request", atom: nil}, %{atom: "s", exponent: -1}]} =
               Unit.parse("{request}/s")

      assert {:ok, [%{atom: "By", annotation: "heap"}]} = Unit.parse("By{heap}")
      assert {:ok, [%{factor: 1, annotation: "core"}]} = Unit.parse("1{core}")
    end
  end

  describe "dimension/1 and factor/1" do
    test "a code's dimension sums its components' and its factor is exact" do
      assert Unit.dimension("kW.h") == %{mass: 1, length: 2, time: -2}
      assert Unit.dimension("J") == Unit.dimension("kW.h")
      assert Unit.dimension("{request}/s") == %{time: -1}
      assert Unit.dimension("%") == %{}
      assert Unit.dimension("m/s.s") == %{length: 1}

      assert Unit.factor("us") == {1, 1_000_000}
      assert Unit.factor("kW.h") == {3_600_000_000, 1}
      assert Unit.factor("MiBy") == {1_048_576, 1}
      assert Unit.factor("bit") == {1, 8}
      assert Unit.factor("%") == {1, 100}
      assert Unit.factor("Cel") == nil
      assert Unit.factor("Cel/s") == nil
    end

    test "a string that is not a code raises" do
      assert_raise ArgumentError, ~r/"sec"/, fn -> Unit.dimension("sec") end
      assert_raise ArgumentError, fn -> Unit.factor("") end
    end
  end

  describe "convert/3" do
    test "values scale between codes of one dimension" do
      assert Unit.convert(1500, "ms", "s") == 1.5
      assert Unit.convert(1500, "us", "ms") == 1.5
      assert Unit.convert(90, "s", "min") == 1.5
      assert Unit.convert(1, "kW.h", "J") == 3.6e6
      assert Unit.convert(8, "bit", "By") == 1.0
      assert Unit.convert(1, "{request}/s", "/min") == 60.0
    end

    test "conversion between unit systems or dimensions is refused" do
      assert_raise ArgumentError, ~r/cannot convert/, fn -> Unit.convert(20, "Cel", "[degF]") end
      assert_raise ArgumentError, ~r/cannot convert/, fn -> Unit.convert(20, "Cel", "K") end
      assert_raise ArgumentError, ~r/cannot convert/, fn -> Unit.convert(1, "s", "By") end
    end
  end

  describe "symbol/2" do
    test "codes are written as a reader reads them" do
      expected = %{
        "s" => "s",
        "us" => "µs",
        "By" => "B",
        "kBy" => "kB",
        "MiBy" => "MiB",
        "Cel" => "°C",
        "[degF]" => "°F",
        "%" => "%",
        "kW.h" => "kW·h",
        "By/s" => "B/s",
        "m2" => "m²",
        "s-1" => "/s",
        "/s" => "/s",
        "g/m.s2" => "g·s²/m",
        "g/m/s2" => "g/(m·s²)",
        "1" => "",
        "{request}" => "",
        "{request}/s" => "/s",
        "By{heap}" => "B",
        "10.m" => "10·m"
      }

      for {code, symbol} <- expected, do: assert(Unit.symbol(code) == symbol, code)
    end

    test "annotations: true writes an annotation standing alone, never one on a unit" do
      assert Unit.symbol("{request}/s", annotations: true) == "request/s"
      assert Unit.symbol("{request}", annotations: true) == "request"
      assert Unit.symbol("By{heap}", annotations: true) == "B"
    end
  end

  describe "from_telemetry/1 (spec/05 §4.1)" do
    test "Telemetry.Metrics units map to UCUM codes" do
      expected = [
        second: "s",
        millisecond: "ms",
        microsecond: "us",
        nanosecond: "ns",
        minute: "min",
        hour: "h",
        day: "d",
        byte: "By",
        kilobyte: "kBy",
        megabyte: "MBy",
        gigabyte: "GBy",
        kibibyte: "KiBy",
        mebibyte: "MiBy",
        gibibyte: "GiBy",
        bit: "bit",
        kilobit: "kbit",
        megabit: "Mbit",
        percent: "%",
        unit: "1",
        hertz: "Hz",
        celsius: "Cel",
        fahrenheit: "[degF]",
        kelvin: "K",
        meter: "m",
        metre: "m",
        watt: "W",
        kilowatt: "kW",
        joule: "J",
        pascal: "Pa"
      ]

      for {atom, code} <- expected do
        assert Unit.from_telemetry(atom) == {:ok, code}
        assert Unit.valid?(code), code
      end
    end

    test "a conversion maps its target; native and an unknown atom are refused" do
      assert Unit.from_telemetry({:native, :millisecond}) == {:ok, "ms"}
      assert Unit.from_telemetry({:byte, :kilobyte}) == {:ok, "kBy"}
      assert Unit.from_telemetry(:native) == {:error, :native}
      assert Unit.from_telemetry(:milisecond) == {:error, {:unknown, :milisecond}}
    end
  end
end
