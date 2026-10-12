defmodule Visualize.Unit.CurrencyTest do
  # The currency extension (spec/05 §4.1, D-155) and the formats that moved from metresis
  # (spec/05 §2.6, §2.9, §4.3).
  use ExUnit.Case, async: true

  alias Visualize.{Format, Quantity, Scale, Unit}
  alias Visualize.Unit.Currency

  describe "the ISO 4217 table" do
    test "list one, 178 codes, each with its minor units" do
      assert length(Currency.table()) == 178

      assert Enum.map(~w(USD EUR GBP JPY BHD KWD CLF ISK XAU XXX), &Unit.minor_units/1) ==
               [2, 2, 2, 0, 3, 3, 4, 0, nil, nil]

      for {code, minor, name} <- Currency.table() do
        assert code =~ ~r/\A[A-Z]{3}\z/
        assert minor == nil or minor in 0..4
        assert name != ""
      end

      assert_raise ArgumentError, ~r/"ZZZ"/, fn -> Unit.minor_units("ZZZ") end
    end
  end

  describe "{iso4217:XXX} is a dimension per code" do
    test "each code its own dimension, composed like any unit" do
      assert Unit.dimension("{iso4217:USD}") == %{{:currency, "USD"} => 1}
      assert Unit.dimension("{iso4217:USD}/h") == %{{:currency, "USD"} => 1, time: -1}

      assert Unit.dimension("{iso4217:EUR}/kW/h") ==
               %{{:currency, "EUR"} => 1, mass: -1, length: -2, time: 2}

      assert Unit.dimension("{iso4217:EUR}/{iso4217:USD}") ==
               %{{:currency, "EUR"} => 1, {:currency, "USD"} => -1}

      refute Unit.dimension("{iso4217:USD}") == Unit.dimension("{iso4217:EUR}")
      assert Unit.factor("{iso4217:USD}/kW/h") == {1, 3_600_000_000}
    end

    test "a code not in the table is refused, a plain annotation is still the unity" do
      assert Unit.parse("{iso4217:ZZZ}") == {:error, {:unknown_currency, "ZZZ"}}
      assert Unit.parse("{iso4217:usd}") == {:error, {:unknown_currency, "usd"}}
      assert Unit.dimension("{USD}") == %{}
      assert Unit.format_error({:unknown_currency, "ZZZ"}) =~ "ISO 4217"
    end

    test "two currencies never convert; mixing them is refused" do
      assert Unit.conversion("{iso4217:USD}", "{iso4217:EUR}") ==
               {:error, {:currency, "{iso4217:USD}", "{iso4217:EUR}"}}

      assert Unit.conversion("{iso4217:EUR}/kW/h", "{iso4217:EUR}/MW/h") ==
               {:ok, {{1000, 1}, {0, 1}}}

      assert Quantity.resolve(%{unit: "{iso4217:EUR}", quantity: :currency}) ==
               {:ok, %{unit: "{iso4217:EUR}", quantity: :currency}}

      assert Quantity.resolve(%{unit: "{iso4217:EUR}", quantity: :count}) ==
               {:error, {:quantity, :count, "{iso4217:EUR}"}}

      assert Quantity.resolve(%{unit: "{iso4217:EUR}/h", quantity: :currency}) ==
               {:error, {:quantity, :currency, "{iso4217:EUR}/h"}}

      assert Quantity.resolve(%{unit: "1", quantity: :currency}) ==
               {:error, {:quantity, :currency, "1"}}
    end

    test "the code alone is the currency; its symbol is the code" do
      assert Unit.currency("{iso4217:GBP}") == "GBP"
      assert Unit.currency("{iso4217:GBP}/h") == nil
      assert Unit.currency("kg") == nil
      assert Unit.currency("sec") == nil
      assert Quantity.of_unit("{iso4217:GBP}") == :currency
      assert Quantity.of_unit("{iso4217:GBP}/h") == nil

      assert Unit.symbol("{iso4217:USD}") == "USD"
      assert Unit.symbol("{iso4217:USD}/h") == "USD/h"
      assert Unit.symbol("{iso4217:EUR}/kW/h") == "EUR/(kW·h)"
      assert Unit.symbol("{iso4217:EUR}/kW.h") == "EUR·h/kW"
      assert Quantity.label(%{unit: "{iso4217:USD}"}) == "USD"
    end

    test "a person's currency: a code in capitals, €, £; $ and ¥ name their choices" do
      assert Unit.parse_alias("USD") == {:ok, "{iso4217:USD}"}
      assert Unit.parse_alias("CHF") == {:ok, "{iso4217:CHF}"}
      assert Unit.parse_alias("€") == {:ok, "{iso4217:EUR}"}
      assert Unit.parse_alias("£") == {:ok, "{iso4217:GBP}"}
      assert Unit.parse_alias("ZZZ") == {:error, {:unknown_alias, "ZZZ"}}

      {:error, {:ambiguous, "$", dollars}} = Unit.parse_alias("$")
      assert "{iso4217:USD}" in Enum.map(dollars, &elem(&1, 0))
      assert length(dollars) == 6

      {:error, {:ambiguous, "¥", yen}} = Unit.parse_alias("¥")
      assert Enum.map(yen, &elem(&1, 0)) == ["{iso4217:JPY}", "{iso4217:CNY}"]
    end
  end

  describe "Format.currency/2 by code (spec/05 §2.6)" do
    test "the minor units, the locale's symbol before the number, else the code after it" do
      assert Format.currency(1240, code: "USD") == "$1,240.00"
      assert Format.currency(1240, code: "EUR") == "€1,240.00"
      assert Format.currency(1240, code: "GBP") == "£1,240.00"
      assert Format.currency(1240, code: "JPY") == "¥1,240"
      assert Format.currency(1240, code: "BHD") == "1,240.000 BHD"
      assert Format.currency(1240, code: "XAU") == "1,240.00 XAU"
      assert Format.currency(-9.5, code: "EUR") == "-€9.50"
      assert Format.currency(-0.001, code: "USD") == "$0.00"
      assert Format.currency(1_234_567.891, code: "USD", precision: 0) == "$1,234,568"
      assert Format.currency(1240, code: "USD", locale: "en") == "$1,240.00"
    end

    test "an unknown code or locale is refused, and the symbol form is unchanged" do
      assert_raise ArgumentError, fn -> Format.currency(1, code: "ZZZ") end

      assert_raise ArgumentError, ~r/unknown locale/, fn ->
        Format.currency(1, code: "USD", locale: "xx")
      end

      assert Format.currency(-1234.5) == "-$1,234.50"
      assert Format.currency(1234.5, symbol: "€") == "€1,234.50"
    end
  end

  describe "Format.duration/2, the compound form (spec/05 §2.9)" do
    test "two units from a second up, milliseconds and nanoseconds below" do
      cases = [
        {5040, "1h 24m"},
        {3603, "1h 3s"},
        {90_061, "1d 1h"},
        {45, "45s"},
        {172_800, "2d"},
        {59.9, "59s"},
        {0.84, "840ms"},
        {0.0005, "0.5ms"},
        {0.00125, "1.25ms"},
        {1.0e-7, "100ns"},
        {0, "0s"},
        {-0.0, "0s"},
        {-90, "-1m 30s"}
      ]

      for {seconds, label} <- cases,
          do: assert(Format.duration(seconds, style: :compound) == label, inspect(seconds))

      assert Format.duration(0.0012346, style: :compound, precision: 3) == "1.235ms"
      assert Format.duration(5430, style: :magnitude) == Format.duration(5430)
      assert Format.duration(5430, []) == "1.5h"
    end
  end

  describe "money and angles on an axis (spec/05 §4.3)" do
    test "a currency axis writes its symbol, one SI prefix for the axis" do
      scale = Scale.linear() |> Scale.domain([0, 1500])
      usd = Quantity.formatter(scale, %{unit: "{iso4217:USD}"})
      assert Enum.map([0, 500, 1500, -1500], usd) == ["$0", "$0.5k", "$1.5k", "-$1.5k"]

      chf = Quantity.formatter(scale, %{unit: "{iso4217:CHF}"})
      assert Enum.map([0, 1500], chf) == ["0 CHF", "1.5k CHF"]

      small =
        Quantity.formatter(Scale.linear() |> Scale.domain([0, 9.5]), %{unit: "{iso4217:EUR}"})

      assert small.(9.5) == "€9.5"
    end

    test "a rate of money is suffixed by its code" do
      scale = Scale.linear() |> Scale.domain([0, 30])
      assert Quantity.formatter(scale, %{unit: "{iso4217:USD}/h"}).(30) == "30 USD/h"
    end

    test "the degree sign attaches to its number" do
      assert Quantity.suffix("deg") == "°"
      scale = Scale.linear() |> Scale.domain([0, 360])
      assert Quantity.formatter(scale, %{unit: "deg"}).(350) == "350°"
      assert Quantity.suffix("Cel") == " °C"
    end
  end
end
