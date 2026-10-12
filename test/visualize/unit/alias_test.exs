defmodule Visualize.Unit.AliasTest do
  # `Visualize.Unit.parse_alias/1` (spec/05 §4.1, D-155): the symbols people type, read as
  # codes, and the ambiguous ones refused with their choices.
  use ExUnit.Case, async: true

  alias Visualize.Unit
  alias Visualize.Unit.Alias

  test "every alias reads as a code, and every choice of an ambiguous one is a code" do
    for {symbol, target} <- Alias.table() do
      case target do
        code when is_binary(code) ->
          assert Unit.valid?(code), "#{symbol} → #{code}"

        [_, _ | _] = choices ->
          for {code, meaning} <- choices do
            assert Unit.valid?(code), "#{symbol} → #{code}"
            assert meaning != ""
          end
      end
    end
  end

  test "the symbols people type are their codes" do
    expected = %{
      "°C" => "Cel",
      "°F" => "[degF]",
      "lb" => "[lb_av]",
      "st" => "[stone_av]",
      "mph" => "[mi_i]/h",
      "kn" => "[kn_i]",
      "inHg" => "[in_i'Hg]",
      "mmHg" => "mm[Hg]",
      "psi" => "[psi]",
      "kWh" => "kW.h",
      "Wh" => "W.h",
      "B" => "By",
      "KiB" => "KiBy",
      "ha" => "har",
      "ac" => "[acr_us]",
      "hp" => "[HP]",
      "Cal" => "[Cal]",
      "°" => "deg",
      "mAh" => "mA.h",
      "bpm" => "{beat}/min",
      "ppm" => "[ppm]",
      "  ft  " => "[ft_i]"
    }

    for {symbol, code} <- expected, do: assert(Unit.parse_alias(symbol) == {:ok, code}, symbol)
  end

  test "a symbol the table does not hold is read as a code, or refused" do
    for code <- ~w(kPa ms kg km/h hPa mbar l ml kcal {request}/s),
        do: assert(Unit.parse_alias(code) == {:ok, code}, code)

    assert Unit.parse_alias("furlongs") == {:error, {:unknown_alias, "furlongs"}}
    assert Unit.parse_alias("") == {:error, {:unknown_alias, ""}}
  end

  test "an ambiguous symbol is refused, naming every code it could mean" do
    assert Unit.parse_alias("KB") ==
             {:error, {:ambiguous, "KB", [{"kBy", "1,000 bytes"}, {"KiBy", "1,024 bytes"}]}}

    choices = fn symbol ->
      {:error, {:ambiguous, ^symbol, choices}} = Unit.parse_alias(symbol)
      Enum.map(choices, &elem(&1, 0))
    end

    assert choices.("kB") == ["kBy", "KiBy"]
    assert choices.("MB") == ["MBy", "MiBy"]
    assert choices.("GB") == ["GBy", "GiBy"]
    assert choices.("TB") == ["TBy", "TiBy"]
    assert choices.("gal") == ["[gal_us]", "[gal_br]"]
    assert choices.("pt") == ["[pt_us]", "[pt_br]"]
    assert choices.("floz") == ["[foz_us]", "[foz_br]"]
    assert choices.("oz") == ["[oz_av]", "[foz_us]", "[foz_br]"]
    assert choices.("cal") == ["cal", "[Cal]"]
    assert choices.("C") == ["Cel", "C"]
    assert choices.("dB") == ["dB", "dB[SPL]"]
    assert choices.("kt") == ["[kn_i]", "kt"]
  end

  test "a refusal is worded for a person, its choices named" do
    {:error, reason} = Unit.parse_alias("gal")

    assert Unit.format_error(reason) ==
             ~s|"gal" is ambiguous: [gal_us] (US gallon) or [gal_br] (imperial gallon)|

    {:error, reason} = Unit.parse_alias("oz")

    assert Unit.format_error(reason) ==
             ~s|"oz" is ambiguous: [oz_av] (ounce, a mass), [foz_us] (US fluid ounce) or | <>
               ~s|[foz_br] (imperial fluid ounce)|

    assert Unit.format_error({:unknown_alias, "x"}) =~ "neither a unit symbol"
    assert Unit.format_error({:not_metric, "k", "min"}) =~ "takes no prefix"
  end
end
