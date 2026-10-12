defmodule Visualize.Unit.ConversionTest do
  # Conversion between units (spec/05 §4.1, D-155): exact, affine for the temperatures,
  # logarithmic units only to their own level, currency never.
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Visualize.Unit

  # Codes of one dimension each.
  @groups [
    ~w(ns us ms s min h d),
    ~w(By kBy MBy KiBy GiBy bit Mbit),
    ~w(mm cm m km [in_i] [ft_i] [yd_i] [mi_i] [nmi_i]),
    ~w(cm2 m2 har km2 [ft_i]2 [acr_us] [mi_i]2),
    ~w(ml cl dl l L m3 [foz_us] [pt_us] [gal_us] [foz_br] [pt_br] [gal_br]),
    ~w(mg g kg t [oz_av] [lb_av] [stone_av]),
    ~w(m/s km/h [mi_i]/h [kn_i]),
    ~w(s/m min/km min/[mi_i]),
    ~w(W kW MW [HP]),
    ~w(J kJ cal kcal [Cal] W.h kW.h),
    ~w(Pa hPa kPa bar mbar [psi] mm[Hg] [in_i'Hg]),
    ~w(deg rad),
    ~w(Cel [degF] K mK),
    ~w(B dB),
    ~w(B[SPL] dB[SPL]),
    ~w(mV V kV),
    ~w(mA A),
    ~w(C mA.h A.h),
    ~w(% [ppm] [ppb] 1),
    ~w(ug/m3 mg/dl g/l)
  ]

  describe "conversion/2" do
    test "two codes of one dimension convert by their factors, exactly" do
      assert Unit.conversion("[lb_av]", "kg") == {:ok, {{45_359_237, 100_000_000}, {0, 1}}}
      assert Unit.conversion("[mi_i]/h", "km/h") == {:ok, {{25_146, 15_625}, {0, 1}}}
      assert Unit.conversion("[gal_br]", "[pt_br]") == {:ok, {{8, 1}, {0, 1}}}
      assert Unit.conversion("deg", "rad") == {:ok, {{1, 180, 1}, {0, 1}}}
      assert Unit.conversion("rad", "deg") == {:ok, {{180, 1, -1}, {0, 1}}}
      assert Unit.conversion("s", "s") == {:ok, {{1, 1}, {0, 1}}}
    end

    test "the affine units convert with their offsets, through the kelvin" do
      assert Unit.conversion("Cel", "[degF]") == {:ok, {{9, 5}, {32, 1}}}
      assert Unit.conversion("[degF]", "Cel") == {:ok, {{5, 9}, {-160, 9}}}
      assert Unit.conversion("Cel", "K") == {:ok, {{1, 1}, {5463, 20}}}
      assert Unit.conversion("[degF]", "K") == {:ok, {{5, 9}, {45_967, 180}}}
      assert Unit.conversion("mK", "Cel") == {:ok, {{1, 1000}, {-5463, 20}}}

      assert Unit.convert(100, "Cel", "[degF]") == 212.0
      assert Unit.convert(-40, "Cel", "[degF]") == -40.0
      assert Unit.convert(-40, "[degF]", "Cel") == -40.0
      assert Unit.convert(0, "K", "Cel") == -273.15
      assert Unit.convert(0, "K", "[degF]") == -459.67
      assert Unit.convert(32, "[degF]", "Cel") == 0.0
      assert Unit.convert(37, "Cel", "[degF]") == 98.6
    end

    test "an affine unit inside a term has no offset and is refused" do
      assert Unit.conversion("Cel/h", "K/h") == {:error, {:affine_in_term, "Cel/h"}}
      assert Unit.conversion("K/h", "[degF]/h") == {:error, {:affine_in_term, "[degF]/h"}}
      assert Unit.conversion("Cel2", "K2") == {:error, {:affine_in_term, "Cel2"}}
      assert Unit.conversion("Cel/h", "Cel/h") == {:ok, {{1, 1}, {0, 1}}}
    end

    test "a level converts only to its own level" do
      assert Unit.conversion("B", "dB") == {:ok, {{10, 1}, {0, 1}}}
      assert Unit.conversion("dB[SPL]", "B[SPL]") == {:ok, {{1, 10}, {0, 1}}}
      assert Unit.conversion("dB", "1") == {:error, {:logarithmic, "dB", "1"}}
      assert Unit.conversion("%", "dB") == {:error, {:logarithmic, "%", "dB"}}
      assert Unit.conversion("dB[SPL]", "Pa") == {:error, {:logarithmic, "dB[SPL]", "Pa"}}
      assert Unit.conversion("dB", "dB[SPL]") == {:error, {:logarithmic, "dB", "dB[SPL]"}}
    end

    test "two currencies never convert; one currency over other units does" do
      assert Unit.conversion("{iso4217:USD}", "{iso4217:EUR}") ==
               {:error, {:currency, "{iso4217:USD}", "{iso4217:EUR}"}}

      assert Unit.conversion("{iso4217:USD}/h", "{iso4217:EUR}/h") ==
               {:error, {:currency, "{iso4217:USD}/h", "{iso4217:EUR}/h"}}

      assert Unit.conversion("{iso4217:USD}", "1") == {:error, {:currency, "{iso4217:USD}", "1"}}
      assert Unit.conversion("{iso4217:USD}/h", "{iso4217:USD}/min") == {:ok, {{1, 60}, {0, 1}}}

      assert Unit.conversion("{iso4217:EUR}/kW.h", "{iso4217:EUR}/MW.h") ==
               {:ok, {{1000, 1}, {0, 1}}}

      assert_raise ArgumentError, ~r/exchange rate is data/, fn ->
        Unit.convert(1, "{iso4217:USD}", "{iso4217:EUR}")
      end
    end

    test "other dimensions and codes that do not read are refused" do
      assert Unit.conversion("s", "By") == {:error, {:dimension, "s", "By"}}

      assert Unit.conversion("[lb_av]", "[gal_us]") ==
               {:error, {:dimension, "[lb_av]", "[gal_us]"}}

      assert Unit.conversion("sec", "s") == {:error, {:unknown_atom, "sec"}}
      assert Unit.format_error({:dimension, "s", "By"}) =~ "different dimensions"
      assert Unit.format_error({:logarithmic, "dB", "1"}) =~ "its own level"
    end
  end

  describe "properties" do
    property "a value converts there and back to itself" do
      check all(
              group <- member_of(@groups),
              from <- member_of(group),
              to <- member_of(group),
              value <- float(min: -1.0e6, max: 1.0e6)
            ) do
        back = value |> Unit.convert(from, to) |> Unit.convert(to, from)
        assert_in_delta back, value, max(abs(value) * 1.0e-12, 1.0e-9), "#{from} ⇄ #{to}"
      end
    end

    property "conversions compose exactly: from a to b then c is from a to c" do
      check all(
              group <- member_of(@groups),
              a <- member_of(group),
              b <- member_of(group),
              c <- member_of(group)
            ) do
        {:ok, ab} = Unit.conversion(a, b)
        {:ok, bc} = Unit.conversion(b, c)
        assert compose(ab, bc) == Unit.conversion(a, c) |> elem(1), "#{a} → #{b} → #{c}"
      end
    end

    property "codes of two dimensions never convert" do
      check all(
              [g1, g2] <- uniq_list_of(member_of(@groups), length: 2),
              from <- member_of(g1),
              to <- member_of(g2)
            ) do
        assert {:error, {reason, ^from, ^to}} = Unit.conversion(from, to)
        assert reason in [:dimension, :logarithmic]
        assert_raise ArgumentError, fn -> Unit.convert(1, from, to) end
      end
    end
  end

  # (value × s1 + o1) × s2 + o2: scale s1·s2, offset o1·s2 + o2, exactly.
  defp compose({s1, o1}, {s2, o2}) do
    {exact(mul3(s1, s2)), add(mul(o1, rational(s2)), o2)}
  end

  defp mul3(a, b) do
    {an, ad, ak} = three(a)
    {bn, bd, bk} = three(b)
    {n, d} = reduce(an * bn, ad * bd)
    {n, d, ak + bk}
  end

  defp three({n, d}), do: {n, d, 0}
  defp three(t), do: t

  defp exact({n, d, 0}), do: {n, d}
  defp exact(t), do: t

  # An offset is never paired with π, so a scale with π meets only a zero offset.
  defp rational({n, d}), do: {n, d}
  defp rational({n, d, _k}), do: {n, d}

  defp mul({0, _}, _), do: {0, 1}
  defp mul({a, b}, {c, d}), do: reduce(a * c, b * d)
  defp add({a, b}, {c, d}), do: reduce(a * d + c * b, b * d)

  defp reduce(0, _d), do: {0, 1}

  defp reduce(n, d) do
    g = Integer.gcd(n, d)
    {div(n, g), div(d, g)}
  end
end
