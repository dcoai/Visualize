defmodule Visualize.AxisFormatTest do
  @moduledoc "Regressions for the `Axis` and `Format` defects of #14 (#27)."
  use ExUnit.Case, async: true

  alias Visualize.{Axis, Format, Scale}
  alias Visualize.Scale.Band

  defp tick_texts(axis) do
    axis
    |> Axis.generate()
    |> Map.fetch!(:children)
    |> Enum.drop(1)
    |> Enum.map(fn tick -> {tick.transform, Enum.at(tick.children, 1).attrs} end)
  end

  describe "Axis :top label (spec/05 §1.4, D-23)" do
    test "sits above the line, at −(tick_size_inner + tick_padding)" do
      scale = Scale.linear() |> Scale.domain([0, 1]) |> Scale.range([0, 10])
      [{_, attrs} | _] = Axis.top(scale) |> Axis.tick_values([0]) |> tick_texts()
      assert attrs.y == -9
      assert attrs.dy == "0em"
    end

    test "the other orientations are unchanged" do
      scale = Scale.linear() |> Scale.domain([0, 1]) |> Scale.range([0, 10])
      [{_, bottom} | _] = Axis.bottom(scale) |> Axis.tick_values([0]) |> tick_texts()
      [{_, left} | _] = Axis.left(scale) |> Axis.tick_values([0]) |> tick_texts()
      [{_, right} | _] = Axis.right(scale) |> Axis.tick_values([0]) |> tick_texts()
      assert bottom.y == 9
      assert left.x == -9
      assert right.x == 9
    end
  end

  describe "Axis band centring (spec/05 §1.5, D-23)" do
    test "ticks sit at the band centre" do
      scale = Scale.band() |> Scale.domain([:a, :b]) |> Scale.range([0, 100])
      positions = Axis.bottom(scale) |> tick_texts() |> Enum.map(fn {t, _} -> t.operations end)
      assert positions == [[{:translate, 25.0, 0}], [{:translate, 75.0, 0}]]
    end

    test "the centring offset shrinks by the pixel offset and is rounded for a rounded band" do
      scale =
        Scale.band()
        |> Scale.domain([:a, :b, :c])
        |> Scale.range([0, 100])
        |> Scale.padding(0.1)
        |> Band.round(true)

      # step 32, bandwidth 29, start 4; centre = round(max(0, 29 − 1) / 2) = 14
      positions =
        Axis.left(scale)
        |> Axis.offset(0.5)
        |> tick_texts()
        |> Enum.map(fn {t, _} -> t.operations end)

      assert positions == [
               [{:translate, 0, 18.5}],
               [{:translate, 0, 50.5}],
               [{:translate, 0, 82.5}]
             ]
    end

    test "a continuous scale is unaffected" do
      scale = Scale.linear() |> Scale.domain([0, 100]) |> Scale.range([0, 200])
      positions = Axis.bottom(scale) |> Axis.tick_values([50]) |> tick_texts()
      assert [{%{operations: [{:translate, 100.0, 0}]}, _}] = positions
    end
  end

  describe "Format.number/2 (spec/05 §2.1, D-24)" do
    test "groups the magnitude and prepends the sign" do
      assert Format.number(-123_456) == "-123,456"
      assert Format.number(-1_234_567) == "-1,234,567"
      assert Format.number(-0.5) == "-0.500"
      assert Format.number(1_234_567) == "1,234,567"
    end

    test "a negative that rounds to zero has no sign" do
      assert Format.number(-0.0001, precision: 2) == "0.00"
    end
  end

  describe "Format.formatter/1 (spec/05 §2.7, D-24)" do
    # Outputs from d3-format's documentation and reference implementation.
    @cases [
      {".2s", 1_234_567, "1.2M"},
      {".3s", 42_000_000, "42.0M"},
      {".3s", 0.000042, "42.0µ"},
      {"s", 0, "0.00000"},
      {",.0f", 1_234_567, "1,234,567"},
      {".2f", 3.14159, "3.14"},
      {"f", 2, "2.000000"},
      {".0f", 2.5, "3"},
      {".1%", 0.123, "12.3%"},
      {"+.1%", 0.123, "+12.3%"},
      {".0%", -0.5, "-50%"},
      {"p", 0.123456, "12.3456%"},
      {".2e", 1234, "1.23e+3"},
      {".2e", 0.001234, "1.23e-3"},
      {"e", 0, "0.000000e+0"},
      {"d", 42.7, "43"},
      {",d", 1_234_567, "1,234,567"},
      {"d", -3, "-3"},
      {".3r", 123.456, "123"},
      {".3r", 0.00123456, "0.00123"},
      {".2r", 12_345, "12000"},
      {".3g", 123_456, "1.23e+5"},
      {".3g", 12.3456, "12.3"},
      {".3g", 0.000001234, "0.00000123"},
      {".3g", 0.0000001234, "1.23e-7"},
      {"g", 1234.5, "1234.50"},
      {"", 1234.5, "1234.5"},
      {"", 0.1 + 0.2, "0.3"},
      {"", 1_000_000_000_000_000, "1e+15"},
      {"~s", 1_500_000, "1.5M"},
      {"~f", 1.5, "1.5"},
      {"~f", 2, "2"},
      {".3~g", 1.10, "1.1"},
      {"n", 1234.5, "1,234.50"},
      {"$.2f", 1234.5, "$1,234.50"} |> then(fn {s, v, _} -> {s, v, "$1234.50"} end),
      {"$,.2f", 1234.5, "$1,234.50"},
      {"($.2f", -12.5, "($12.50)"},
      {"($.2f", 12.5, "$12.50"},
      {"+d", 5, "+5"},
      {"+d", -5, "-5"},
      {" d", 5, " 5"},
      {" d", -5, "-5"},
      {"08.2f", 3.14159, "00003.14"},
      {"08.2f", -3.14159, "-0003.14"},
      {"8.2f", 3.14159, "    3.14"},
      {"<8.2f", 3.14159, "3.14    "},
      {"^8.2f", 3.14159, "  3.14  "},
      {"^9.2f", 3.14159, "  3.14   "},
      {"*>8d", 42, "******42"},
      {"*=+8d", 42, "+*****42"},
      {"010,.0f", 1_234_567, "01,234,567"},
      {"012,d", 1_234_567, "0,001,234,567"},
      {"b", 5, "101"},
      {"#b", 5, "0b101"},
      {"o", 8, "10"},
      {"#o", 8, "0o10"},
      {"x", 255, "ff"},
      {"#x", 255, "0xff"},
      {"#X", 255, "0xFF"},
      {"c", 42, "42"},
      {"5c", "ab", "   ab"},
      {"+.1f", -0.01, "-0.0"},
      {".1f", -0.01, "0.0"},
      {".2s", 0.0000000000000000000000001, "0.1y"}
    ]

    for {spec, value, expected} <- @cases do
      test "#{inspect(spec)} formats #{inspect(value)} as #{inspect(expected)}" do
        assert Format.formatter(unquote(spec)).(unquote(value)) == unquote(expected)
      end
    end

    test "an invalid specifier raises" do
      assert_raise ArgumentError, fn -> Format.formatter("..2f") end
      assert_raise ArgumentError, fn -> Format.formatter("q!") end
    end

    test "precision is clamped" do
      assert Format.formatter(".30f").(1) == "1." <> String.duplicate("0", 20)
      assert Format.formatter(".0r").(123.456) == "100"
    end

    test "NaN and non-numbers" do
      assert Format.formatter(".2f").(nil) == "NaN"
      assert Format.formatter(">6.2f").(nil) == "   NaN"
    end
  end

  describe "Format.time/2 (spec/05 §2.8, D-25)" do
    @dt DateTime.new!(~D[2024-03-03], ~T[14:05:09.123456], "Etc/UTC")

    test "the eight original directives" do
      assert Format.time(@dt, "%Y-%m-%d %H:%M:%S %b %B") == "2024-03-03 14:05:09 Mar March"
    end

    test "%% is a literal percent and one pass means no re-substitution" do
      assert Format.time(@dt, "100%% %%Y %Y") == "100% %Y 2024"
    end

    test "the extended directives" do
      assert Format.time(@dt, "%y %e %j %I %p %L %a %A %U %w %Z %z") ==
               "24  3 063 02 PM 123 Sun Sunday 09 0 UTC +0000"
    end

    test "midnight and noon under %I and %p" do
      assert Format.time(~N[2024-01-01 00:30:00], "%I %p") == "12 AM"
      assert Format.time(~N[2024-01-01 12:00:00], "%I %p") == "12 PM"
    end

    test "a Date has zero time fields and no zone" do
      assert Format.time(~D[2024-12-25], "%H:%M:%S %L [%Z] [%z]") == "00:00:00 000 [] []"
      assert Format.time(~D[2024-12-25]) == "2024-12-25"
    end

    test "a NaiveDateTime has no zone" do
      assert Format.time(~N[2024-03-03 14:05:09], "%H%Z%z") == "14"
    end

    test "%U counts weeks from the first Sunday" do
      assert Format.time(~D[2024-01-01], "%U") == "00"
      assert Format.time(~D[2024-01-07], "%U") == "01"
    end

    test "an unknown directive and a trailing percent pass through" do
      assert Format.time(@dt, "%Q %") == "%Q %"
    end

    test "a non-UTC offset" do
      dt =
        DateTime.new!(~D[2024-06-01], ~T[10:00:00], "Etc/UTC")
        |> DateTime.add(0)
        |> Map.merge(%{utc_offset: -19_800, std_offset: 0, zone_abbr: "X"})

      assert Format.time(dt, "%z %Z") == "-0530 X"
    end
  end
end
