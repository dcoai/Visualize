defmodule Visualize.Unit.Alias do
  @moduledoc false
  # The symbols people type and hosts have stored, each the UCUM code it means or the codes
  # it could mean (spec/05 §4.1, D-155). `Visualize.Unit.parse_alias/1` reads this table
  # before UCUM, so an alias wins over a UCUM reading of the same spelling: a person who
  # types `B` or `MB` means bytes, not bels. A symbol is ambiguous when two units people
  # use are written that way — a kilobyte of 1,000 or 1,024 bytes, a US or an imperial
  # gallon — and then it is refused with its choices rather than guessed at.

  @bytes [
    {"KB", "k", "Ki", "1,000 bytes", "1,024 bytes"},
    {"kB", "k", "Ki", "1,000 bytes", "1,024 bytes"},
    {"MB", "M", "Mi", "1,000,000 bytes", "1,048,576 bytes"},
    {"GB", "G", "Gi", "10⁹ bytes", "2³⁰ bytes"},
    {"TB", "T", "Ti", "10¹² bytes", "2⁴⁰ bytes"}
  ]

  @gallon [{"[gal_us]", "US gallon"}, {"[gal_br]", "imperial gallon"}]
  @pint [{"[pt_us]", "US pint"}, {"[pt_br]", "imperial pint"}]
  @fluid_ounce [{"[foz_us]", "US fluid ounce"}, {"[foz_br]", "imperial fluid ounce"}]

  @ambiguous Map.merge(
               Map.new(@bytes, fn {symbol, si, binary, si_words, binary_words} ->
                 {symbol, [{si <> "By", si_words}, {binary <> "By", binary_words}]}
               end),
               %{
                 "gal" => @gallon,
                 "gallon" => @gallon,
                 "gallons" => @gallon,
                 "pt" => @pint,
                 "pint" => @pint,
                 "pints" => @pint,
                 "floz" => @fluid_ounce,
                 "fl oz" => @fluid_ounce,
                 "fl. oz." => @fluid_ounce,
                 "oz" => [{"[oz_av]", "ounce, a mass"} | @fluid_ounce],
                 "cal" => [{"cal", "calorie"}, {"[Cal]", "food Calorie, a kilocalorie"}],
                 "C" => [{"Cel", "degree Celsius"}, {"C", "coulomb"}],
                 "dB" => [{"dB", "a level ratio"}, {"dB[SPL]", "sound pressure level"}],
                 "kt" => [{"[kn_i]", "knot"}, {"kt", "kilotonne"}]
               }
             )

  @codes %{
    # time
    "sec" => "s",
    "secs" => "s",
    "second" => "s",
    "seconds" => "s",
    "µs" => "us",
    "μs" => "us",
    "mins" => "min",
    "minute" => "min",
    "minutes" => "min",
    "hr" => "h",
    "hrs" => "h",
    "hour" => "h",
    "hours" => "h",
    "day" => "d",
    "days" => "d",
    # information
    "B" => "By",
    "byte" => "By",
    "bytes" => "By",
    "KiB" => "KiBy",
    "MiB" => "MiBy",
    "GiB" => "GiBy",
    "TiB" => "TiBy",
    "bits" => "bit",
    "kbps" => "kbit/s",
    "Mbps" => "Mbit/s",
    "Gbps" => "Gbit/s",
    "B/s" => "By/s",
    # ratios
    "percent" => "%",
    "ppm" => "[ppm]",
    "ppb" => "[ppb]",
    # temperature
    "°C" => "Cel",
    "℃" => "Cel",
    "degC" => "Cel",
    "°F" => "[degF]",
    "℉" => "[degF]",
    "degF" => "[degF]",
    # length
    "in" => "[in_i]",
    "inch" => "[in_i]",
    "inches" => "[in_i]",
    "ft" => "[ft_i]",
    "foot" => "[ft_i]",
    "feet" => "[ft_i]",
    "yd" => "[yd_i]",
    "mi" => "[mi_i]",
    "mile" => "[mi_i]",
    "miles" => "[mi_i]",
    "nmi" => "[nmi_i]",
    "NM" => "[nmi_i]",
    # area
    "m²" => "m2",
    "cm²" => "cm2",
    "km²" => "km2",
    "ha" => "har",
    "ac" => "[acr_us]",
    "acre" => "[acr_us]",
    "acres" => "[acr_us]",
    "ft²" => "[ft_i]2",
    "sq ft" => "[ft_i]2",
    "mi²" => "[mi_i]2",
    # volume
    "mL" => "ml",
    "m³" => "m3",
    "US gal" => "[gal_us]",
    "UK gal" => "[gal_br]",
    "imp gal" => "[gal_br]",
    "US pt" => "[pt_us]",
    "UK pt" => "[pt_br]",
    "imp pt" => "[pt_br]",
    "US fl oz" => "[foz_us]",
    "UK fl oz" => "[foz_br]",
    "imp fl oz" => "[foz_br]",
    # mass
    "lb" => "[lb_av]",
    "lbs" => "[lb_av]",
    "pound" => "[lb_av]",
    "pounds" => "[lb_av]",
    "st" => "[stone_av]",
    "stone" => "[stone_av]",
    "tonne" => "t",
    # speed and pace
    "kph" => "km/h",
    "kmh" => "km/h",
    "km/hr" => "km/h",
    "mph" => "[mi_i]/h",
    "kn" => "[kn_i]",
    "knot" => "[kn_i]",
    "knots" => "[kn_i]",
    "min/mi" => "min/[mi_i]",
    # power and energy
    "hp" => "[HP]",
    "HP" => "[HP]",
    "Wh" => "W.h",
    "kWh" => "kW.h",
    "MWh" => "MW.h",
    "GWh" => "GW.h",
    "Cal" => "[Cal]",
    # pressure
    "mmHg" => "mm[Hg]",
    "inHg" => "[in_i'Hg]",
    "psi" => "[psi]",
    # angle
    "°" => "deg",
    "degree" => "deg",
    "degrees" => "deg",
    # electricity and light
    "Ah" => "A.h",
    "mAh" => "mA.h",
    "lux" => "lx",
    # sound
    "dB SPL" => "dB[SPL]",
    "dB(SPL)" => "dB[SPL]",
    # concentration
    "µg/m³" => "ug/m3",
    "μg/m³" => "ug/m3",
    "mg/dL" => "mg/dl",
    "mmol/L" => "mmol/l",
    # events
    "bpm" => "{beat}/min",
    "rpm" => "{rev}/min"
  }

  @doc false
  # The table's reading of a symbol: the code it means, the codes it could mean, or
  # nothing, when `parse/1` reads it.
  @spec lookup(String.t()) ::
          {:code, String.t()} | {:ambiguous, [{String.t(), String.t()}]} | :none
  def lookup(symbol) do
    case @codes do
      %{^symbol => code} -> {:code, code}
      _codes -> if choices = @ambiguous[symbol], do: {:ambiguous, choices}, else: :none
    end
  end

  @doc false
  # Every alias and what it reads as, for the tests that hold each target to a code.
  @spec table() :: %{String.t() => String.t() | [{String.t(), String.t()}]}
  def table, do: Map.merge(@ambiguous, @codes)
end
