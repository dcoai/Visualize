defmodule Visualize.Unit.UcumTest do
  # The atoms and prefixes #589 adds, each held to UCUM's own definition (the UCUM essence
  # table, version 2.2): the definition is written here as UCUM writes it, a number times
  # a code, and the factor visualize keeps must equal it exactly (spec/05 §4.1, D-155).
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Visualize.Unit

  # {atom, numerator, denominator, code}: 1 atom = (numerator / denominator) code.
  @definitions [
    {"min", 60, 1, "s"},
    {"h", 60, 1, "min"},
    {"d", 24, 1, "h"},
    {"Hz", 1, 1, "s-1"},
    {"By", 8, 1, "bit"},
    {"%", 1, 100, "1"},
    {"[ppm]", 1, 1_000_000, "1"},
    {"[ppb]", 1, 1_000_000_000, "1"},
    {"mol", 602_214_076 * 1_000_000_000_000_000, 1, "1"},
    {"[in_i]", 254, 100, "cm"},
    {"[ft_i]", 12, 1, "[in_i]"},
    {"[yd_i]", 3, 1, "[ft_i]"},
    {"[mi_i]", 5280, 1, "[ft_i]"},
    {"[nmi_i]", 1852, 1, "m"},
    {"ar", 100, 1, "m2"},
    {"l", 1, 1, "dm3"},
    {"L", 1, 1, "l"},
    {"[gal_us]", 231, 1, "[in_i]3"},
    {"[pt_us]", 1, 8, "[gal_us]"},
    {"[foz_us]", 1, 128, "[gal_us]"},
    {"[gal_br]", 454_609, 100_000, "l"},
    {"[pt_br]", 1, 8, "[gal_br]"},
    {"[foz_br]", 1, 160, "[gal_br]"},
    {"t", 1000, 1, "kg"},
    {"[lb_av]", 7000 * 6_479_891, 100_000, "mg"},
    {"[oz_av]", 1, 16, "[lb_av]"},
    {"[stone_av]", 14, 1, "[lb_av]"},
    {"[kn_i]", 1, 1, "[nmi_i]/h"},
    {"W", 1, 1, "J/s"},
    {"J", 1, 1, "kg.m2/s2"},
    {"cal", 4184, 1000, "J"},
    {"[Cal]", 1, 1, "kcal"},
    {"Pa", 1, 1, "kg/m/s2"},
    {"bar", 100_000, 1, "Pa"},
    # [lbf_av] is [lb_av].[g], the standard acceleration of free fall 9.80665 m/s2
    {"[psi]", 980_665, 100_000, "[lb_av].m/s2/[in_i]2"},
    {"[HP]", 550 * 980_665, 100_000, "[ft_i].[lb_av].m/s2/s"},
    {"m[Hg]", 1_333_220, 10_000, "kPa"},
    {"[in_i'Hg]", 1, 1, "m[Hg].[in_i]/m"},
    {"A", 1, 1, "C/s"},
    {"V", 1, 1, "J/C"}
  ]

  describe "the atoms are UCUM's (spec/05 §4.1)" do
    test "each atom's factor and dimension is its UCUM definition, exactly" do
      for {atom, n, d, code} <- @definitions do
        assert Unit.dimension(atom) == Unit.dimension(code), atom
        assert Unit.factor(atom) == times(Unit.factor(code), {n, d}), atom
      end
    end

    test "the acre is 160 square rods of 16.5 US survey feet, the foot 1,200/3,937 m" do
      rod = times({33, 2}, {1200, 3937})
      assert Unit.factor("[acr_us]") == times(times({160, 1}, rod), rod)
      assert Unit.dimension("[acr_us]") == %{length: 2}
    end

    test "the degree is π/180 of the radian, and π cancels between two angles" do
      assert Unit.factor("deg") == {1, 180, 1}
      assert Unit.factor("rad") == {1, 1}
      assert Unit.factor("deg/rad") == {1, 180, 1}
      assert Unit.factor("deg/deg") == {1, 1}
      assert Unit.factor("deg2") == {1, 32_400, 2}
      assert Unit.convert(180, "deg", "rad") == :math.pi()
      assert Unit.convert(:math.pi(), "rad", "deg") == 180.0
      assert Unit.convert(90, "deg", "deg") == 90.0
    end

    test "new dimensions follow UCUM's base units" do
      assert Unit.dimension("lx") == %{luminous_intensity: 1, angle: 2, length: -2}
      assert Unit.dimension("mA.h") == %{charge: 1}
      assert Unit.dimension("V") == %{mass: 1, length: 2, time: -2, charge: -1}
      assert Unit.dimension("mmol/l") == %{length: -3}
      assert Unit.dimension("ug/m3") == %{mass: 1, length: -3}
      assert Unit.dimension("min/km") == %{time: 1, length: -1}
      assert Unit.dimension("[mi_i]/h") == %{length: 1, time: -1}
    end

    test "a level has a dimension of its own per reference, and a decibel is a tenth of a bel" do
      assert Unit.dimension("B") == %{level: 1}
      assert Unit.dimension("dB") == %{level: 1}
      assert Unit.dimension("dB[SPL]") == %{sound_pressure_level: 1}
      refute Unit.dimension("dB[SPL]") == Unit.dimension("Pa")
      refute Unit.dimension("dB") == Unit.dimension("1")
      assert Unit.factor("dB") == {1, 10}
      assert Unit.convert(30, "dB", "B") == 3.0
      assert Unit.convert(3, "B[SPL]", "dB[SPL]") == 30.0
      assert_raise ArgumentError, fn -> Unit.convert(30, "dB", "dB[SPL]") end
    end

    test "kind/1 tells a linear code from an affine and a logarithmic one" do
      for code <- ~w(s kW.h [lb_av] deg mmol/l), do: assert(Unit.kind(code) == :linear, code)
      for code <- ~w(Cel [degF] Cel/h), do: assert(Unit.kind(code) == :affine, code)
      for code <- ~w(B dB dB[SPL] B[SPL]), do: assert(Unit.kind(code) == :logarithmic, code)
      assert Unit.kind("K") == :linear
      assert_raise ArgumentError, fn -> Unit.kind("sec") end
    end
  end

  describe "prefixes and symbols (spec/05 §4.1)" do
    test "the new prefixes read, a symbol matched whole first and the longest prefix next" do
      expected = %{
        "cm" => {"c", "m"},
        "dl" => {"d", "l"},
        "hPa" => {"h", "Pa"},
        "har" => {"h", "ar"},
        "dam" => {"da", "m"},
        "TBy" => {"T", "By"},
        "TiBy" => {"Ti", "By"},
        "pm" => {"p", "m"},
        "dB" => {"d", "B"},
        "mm[Hg]" => {"m", "m[Hg]"},
        "dB[SPL]" => {"d", "B[SPL]"},
        "mbar" => {"m", "bar"},
        "kcal" => {"k", "cal"},
        "mmol" => {"m", "mol"}
      }

      for {code, {prefix, atom}} <- expected,
          do: assert({:ok, [%{prefix: ^prefix, atom: ^atom}]} = Unit.parse(code), code)

      for atom <- ~w(h d t cal bar min mol lx) do
        assert {:ok, [%{prefix: nil, atom: ^atom}]} = Unit.parse(atom), atom
      end
    end

    test "a prefix on a customary atom is refused" do
      assert Unit.parse("k[in_i]") == {:error, {:not_metric, "k", "[in_i]"}}
      assert Unit.parse("k[lb_av]") == {:error, {:not_metric, "k", "[lb_av]"}}
      assert Unit.parse("mdeg") == {:error, {:not_metric, "m", "deg"}}
      assert Unit.parse("cd") == {:error, {:not_metric, "c", "d"}}
    end

    test "a symbol mixing letters and brackets is one symbol, ended by an exponent or a note" do
      assert {:ok, [%{atom: "[ft_i]", exponent: 2}]} = Unit.parse("[ft_i]2")
      assert {:ok, [%{atom: "[in_i'Hg]"}]} = Unit.parse("[in_i'Hg]")
      assert {:ok, [%{atom: "B[SPL]", annotation: "A"}]} = Unit.parse("B[SPL]{A}")
      assert Unit.parse("[ft_i]x") == {:error, {:unknown_atom, "[ft_i]x"}}
    end

    test "the new codes are written as a reader reads them" do
      expected = %{
        "[ft_i]2" => "ft²",
        "[mi_i]/h" => "mi/h",
        "har" => "ha",
        "mm[Hg]" => "mmHg",
        "[in_i'Hg]" => "inHg",
        "dB[SPL]" => "dB(SPL)",
        "deg" => "°",
        "ug/m3" => "µg/m³",
        "mA.h" => "mA·h",
        "[lb_av]" => "lb",
        "[stone_av]" => "st",
        "[gal_br]" => "gal",
        "[foz_us]" => "fl oz",
        "TiBy" => "TiB",
        "[HP]" => "hp",
        "[Cal]" => "Cal",
        "min/km" => "min/km"
      }

      for {code, symbol} <- expected, do: assert(Unit.symbol(code) == symbol, code)
    end
  end

  describe "properties" do
    property "a product's dimension and factor are its components', a quotient's inverted" do
      check all(a <- code(), b <- code()) do
        assert Unit.dimension(a <> "." <> b) == add(Unit.dimension(a), Unit.dimension(b))
        assert Unit.dimension(a <> "/" <> b) == add(Unit.dimension(a), negate(Unit.dimension(b)))
        assert exact(a <> "." <> b) == mul(exact(a), exact(b))
        assert exact(a <> "/" <> b) == mul(exact(a), inv(exact(b)))
      end
    end

    property "a code converts to itself unchanged" do
      check all(a <- code(), value <- float(min: -1.0e6, max: 1.0e6)) do
        assert Unit.convert(value, a, a) == value
      end
    end

    property "every atom's symbol reads back as its code, or names it among the choices" do
      check all(code <- member_of(readable_codes())) do
        case Unit.parse_alias(Unit.symbol(code)) do
          {:ok, read} ->
            assert Unit.dimension(read) == Unit.dimension(code), code
            assert Unit.factor(read) == Unit.factor(code), code

          {:error, {:ambiguous, _symbol, choices}} ->
            assert code in Enum.map(choices, &elem(&1, 0)), code
        end
      end
    end
  end

  # Every atom of the table and common prefixed codes, but those whose symbol a person
  # writes for something else: the bel's `B` is a person's byte, the are's `a` and the
  # meter of mercury's `mHg` are not typed, and `B(SPL)` is UCUM's print form.
  defp readable_codes do
    ~w(s min h d Hz By bit % [ppm] [ppb] mol Cel [degF] K m [in_i] [ft_i] [yd_i] [mi_i]
       [nmi_i] har [acr_us] l L [gal_us] [pt_us] [foz_us] [gal_br] [pt_br] [foz_br] g t
       [lb_av] [oz_av] [stone_av] [kn_i] W [HP] J cal [Cal] Pa bar [psi] mm[Hg] [in_i'Hg]
       rad deg C A V lx dB dB[SPL] ms us ns kBy MBy GBy TBy KiBy MiBy GiBy TiBy kbit km cm
       mm kg mg ml cl dl kW MW kJ kcal hPa kPa mbar mA mV kV klx mmol)
  end

  # Linear codes of a prefix, a metric atom and a small exponent, or a customary atom.
  defp code do
    metric = ~w(s By bit m g l W J Pa bar C A V rad lx Hz mol t cal)
    customary = ~w(min h d % [ppm] [in_i] [ft_i] [mi_i] [lb_av] [oz_av] [gal_us] [gal_br]
                   [kn_i] [psi] [HP] [Cal] [in_i'Hg] deg)
    prefixes = ["" | ~w(da h k M G T d c m u n p Ki Mi Gi Ti)]

    one_of([
      gen all(
            prefix <- member_of(prefixes),
            atom <- member_of(metric),
            exponent <- member_of(["", "2", "3", "-1"])
          ) do
        prefix <> atom <> exponent
      end,
      gen(
        all(atom <- member_of(customary), exponent <- member_of(["", "2"]), do: atom <> exponent)
      )
    ])
  end

  defp exact(code) do
    case Unit.factor(code) do
      {n, d} -> {n, d, 0}
      {n, d, k} -> {n, d, k}
    end
  end

  defp mul({a, b, j}, {c, d, k}), do: reduce(a * c, b * d, j + k)
  defp inv({n, d, k}), do: {d, n, -k}

  defp reduce(n, d, k) do
    g = Integer.gcd(n, d)
    {div(n, g), div(d, g), k}
  end

  defp times({a, b}, {c, d}) do
    {n, d, 0} = reduce(a * c, b * d, 0)
    {n, d}
  end

  defp add(x, y),
    do: Map.merge(x, y, fn _k, a, b -> a + b end) |> Map.reject(fn {_k, n} -> n == 0 end)

  defp negate(x), do: Map.new(x, fn {k, n} -> {k, -n} end)
end
