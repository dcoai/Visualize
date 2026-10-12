defmodule Visualize.MetresisParity do
  @moduledoc """
  The metresis parity table (#589, D-155): every unit metresis's vocabulary holds, and the
  UCUM code it is here.

  Transcribed, read only, from metresis at commit
  `dab77ec08c349d5dbdbf2105aa0f11a46a23f018`: its `spec.md` §4.4 (*Quantity — the unit
  family*) and `lib/metresis/units.ex` (`Metresis.Units`, last changed at
  `aed19f62a6401cb9b1784c45c17a785943a01a1b`, 2026-10-02). metresis deletes that module
  against this table (metresis#429), so the table is the proof that nothing it holds is
  lost.

  Each row is `{family, unit, factor, code}`: metresis's family and its unit as metresis
  spells it, metresis's factor to the family's base exactly as `Metresis.Units` writes it
  (`:affine` for temperature, whose conversion is a pair of functions), and the UCUM code
  visualize reads for it. A unit metresis's spelling leaves ambiguous is the code metresis
  means by its factor: its `KB` is 1,000 bytes (`kBy`), its `gal` the US gallon
  (`[gal_us]`), its `cal` 4.184 J (`cal`, the thermochemical calorie).
  """

  @doc "The fifteen families of metresis's §4.4, in its table's order."
  def families,
    do: ~w(number count duration bytes percent ratio currency mass length temperature speed
         pressure energy volume angle)a

  @doc "Every unit of every family, as `{family, unit, factor, code}`."
  def units do
    [
      {:percent, "%", 1.0, "%"},
      {:duration, "ns", 1.0e-9, "ns"},
      {:duration, "ms", 1.0e-3, "ms"},
      {:duration, "s", 1.0, "s"},
      {:duration, "min", 60.0, "min"},
      {:duration, "h", 3600.0, "h"},
      {:duration, "d", 86_400.0, "d"},
      {:bytes, "B", 1.0, "By"},
      {:bytes, "KB", 1.0e3, "kBy"},
      {:bytes, "MB", 1.0e6, "MBy"},
      {:bytes, "GB", 1.0e9, "GBy"},
      {:bytes, "TB", 1.0e12, "TBy"},
      {:bytes, "KiB", 1024.0, "KiBy"},
      {:bytes, "MiB", 1_048_576.0, "MiBy"},
      {:bytes, "GiB", 1_073_741_824.0, "GiBy"},
      {:bytes, "TiB", 1_099_511_627_776.0, "TiBy"},
      {:mass, "g", 1.0, "g"},
      {:mass, "kg", 1000.0, "kg"},
      {:mass, "oz", 28.349523125, "[oz_av]"},
      {:mass, "lb", 453.59237, "[lb_av]"},
      {:mass, "st", 6350.29318, "[stone_av]"},
      {:length, "mm", 0.001, "mm"},
      {:length, "cm", 0.01, "cm"},
      {:length, "m", 1.0, "m"},
      {:length, "km", 1000.0, "km"},
      {:length, "in", 0.0254, "[in_i]"},
      {:length, "ft", 0.3048, "[ft_i]"},
      {:length, "mi", 1609.344, "[mi_i]"},
      {:speed, "m/s", 1.0, "m/s"},
      {:speed, "km/h", 0.2777777777777778, "km/h"},
      {:speed, "mph", 0.44704, "[mi_i]/h"},
      {:speed, "kn", 0.5144444444444445, "[kn_i]"},
      {:pressure, "Pa", 1.0, "Pa"},
      {:pressure, "hPa", 100.0, "hPa"},
      {:pressure, "mbar", 100.0, "mbar"},
      {:pressure, "inHg", 3386.388, "[in_i'Hg]"},
      {:pressure, "mmHg", 133.322387415, "mm[Hg]"},
      {:energy, "J", 1.0, "J"},
      {:energy, "kJ", 1000.0, "kJ"},
      {:energy, "cal", 4.184, "cal"},
      {:energy, "kcal", 4184.0, "kcal"},
      {:energy, "Wh", 3600.0, "W.h"},
      {:energy, "kWh", 3_600_000.0, "kW.h"},
      {:volume, "ml", 0.001, "ml"},
      {:volume, "l", 1.0, "l"},
      {:volume, "floz", 0.0295735295625, "[foz_us]"},
      {:volume, "pt", 0.473176473, "[pt_us]"},
      {:volume, "gal", 3.785411784, "[gal_us]"},
      {:angle, "deg", 1.0, "deg"},
      {:angle, "rad", 57.29577951308232, "rad"},
      {:temperature, "°C", :affine, "Cel"},
      {:temperature, "°F", :affine, "[degF]"},
      {:temperature, "K", :affine, "K"}
    ]
  end

  @doc """
  metresis's dimensionless families, which hold no unit there: a number is the absence of
  a quantity, and a count and a ratio are the unity `1`.
  """
  def unitless, do: %{number: nil, count: "1", ratio: "1"}

  @doc """
  metresis's currency family: any ISO 4217 code, which visualize writes as the annotation
  `{iso4217:XXX}` (spec/05 §4.1's extension, D-155). A sample of the codes metresis's
  formatter names.
  """
  def currencies, do: ~w(USD EUR GBP JPY CHF)
end
