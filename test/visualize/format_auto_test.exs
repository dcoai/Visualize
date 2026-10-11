defmodule Visualize.Format.AutoTest do
  @moduledoc """
  The derived tick formats and counts of spec/05 §1.5 and §3 (#532, D-134): a time
  format from the span and the interval, a number notation from the magnitude, a tick
  count from the axis's length, and the `"en"` locale they all take.
  """
  use ExUnit.Case, async: true

  alias Visualize.{Axis, Scale}
  alias Visualize.Format.Auto

  doctest Auto
  doctest Axis

  @t0 ~U[2024-03-04 00:00:00Z]

  defp span(seconds), do: [@t0, DateTime.add(@t0, seconds, :second)]

  describe "time_format/2: by the span and the interval" do
    test "2 h, 3 d, 2 months and 2 years pick clock, day, date and month formats" do
      assert Auto.time_format(span(2 * 3600), count: 7) == "%H:%M"
      assert Auto.time_format(span(3 * 86_400), count: 7) == "%a %H:%M"
      assert Auto.time_format(span(61 * 86_400), count: 7) == "%b %d"
      assert Auto.time_format(span(730 * 86_400), count: 7) == "%b %Y"
    end

    test "the interval decides whether the time of day shows" do
      # Three days at two ticks: a daily interval, so the weekday and date alone.
      assert Auto.time_format(span(3 * 86_400), count: 2) == "%a %d"
      # Two months at forty ticks: a sub-day interval, so the time joins the date.
      assert Auto.time_format(span(61 * 86_400), count: 400) == "%b %d %H:%M"
      # Ninety seconds at ten ticks: seconds.
      assert Auto.time_format(span(90), count: 10) == "%H:%M:%S"
      # Twenty years: whole years, the year alone.
      assert Auto.time_format(span(20 * 365 * 86_400), count: 7) == "%Y"
    end

    test "the boundaries: a day, a week, 92 days" do
      assert Auto.time_format(span(86_400), count: 7) == "%H:%M"
      assert Auto.time_format(span(86_401), count: 7) == "%a %H:%M"
      assert Auto.time_format(span(7 * 86_400), count: 2) == "%a %d"
      assert Auto.time_format(span(7 * 86_400 + 1), count: 2) == "%b %d"
      assert Auto.time_format(span(92 * 86_400), count: 7) == "%b %d"
      assert Auto.time_format(span(93 * 86_400), count: 7) == "%b %Y"
    end

    test "a descending domain, dates and naive times read the same span" do
      [a, b] = span(2 * 3600)
      assert Auto.time_format([b, a]) == "%H:%M"
      assert Auto.time_format([~D[2024-01-01], ~D[2024-03-01]], count: 7) == "%b %d"
      assert Auto.time_format([~N[2024-01-01 00:00:00], ~N[2024-01-01 06:00:00]]) == "%H:%M"
    end
  end

  describe "notation/2 and number/2: by the magnitude" do
    test "0–900, 0–90,000 and 0–9 M are plain, grouped and SI" do
      assert Auto.notation([0, 900]) == :plain
      assert Auto.notation([0, 90_000]) == :grouped
      assert Auto.notation([0, 9_000_000]) == {:si, 6}

      assert Enum.map([0, 450, 900], Auto.number(:plain)) == ["0", "450", "900"]
      assert Enum.map([0, 45_000, 90_000], Auto.number(:grouped)) == ["0", "45,000", "90,000"]

      assert Enum.map([0, 4_500_000, 9_000_000], Auto.number({:si, 6})) == [
               "0",
               "4.5M",
               "9M"
             ]
    end

    test "the magnitude is the greatest |d|, negatives included" do
      assert Auto.notation([-1500, 10]) == :grouped
      assert Auto.notation([-2.0e9, 0]) == {:si, 9}
      assert Auto.notation([999.9, 0]) == :plain
      assert Auto.notation([1_000_000, 0]) == {:si, 6}
      assert Auto.notation([]) == :plain
    end

    test "one prefix across the axis, the fraction kept" do
      f = Auto.number({:si, 6})
      assert Enum.map([500_000, 1_000_000, 1_500_000], f) == ["0.5M", "1M", "1.5M"]
      assert f.(-2_500_000) == "-2.5M"
      assert Auto.number({:si, 12}).(3.2e12) == "3.2T"
    end

    test "grouping keeps the sign and the fraction" do
      f = Auto.number(:grouped)
      assert f.(-1_234_567) == "-1,234,567"
      assert f.(12_500.5) == "12,500.5"
      assert f.(100) == "100"
      assert f.(1000.0) == "1,000"
    end

    test ":si gives each value its own prefix, plain below a thousand" do
      assert Enum.map([0.01, 1, 100, 1000, 1.0e4, 1.0e6, 2.0e9], Auto.number(:si)) ==
               ["0.01", "1", "100", "1k", "10k", "1M", "2G"]
    end

    test "a non-number passes through to_string/1" do
      assert Auto.number(:grouped).("n/a") == "n/a"
    end
  end

  describe "formatter/2: one realised scale" do
    test "a time scale formats in its zone with the span's format" do
      scale =
        Scale.time()
        |> Scale.domain(span(2 * 3600))
        |> Scale.Time.zone("America/New_York")

      f = Auto.formatter(scale, count: 4)
      assert f.(~U[2024-03-04 01:00:00Z]) == "20:00"
      assert f.(:other) == "other"
    end

    test "linear, log and band scales" do
      linear = Scale.linear() |> Scale.domain([0, 2_000_000])
      assert Auto.formatter(linear).(1_500_000) == "1.5M"

      log = Scale.log() |> Scale.domain([1, 1.0e9])
      assert Enum.map([10, 1000, 1.0e6], Auto.formatter(log)) == ["10", "1k", "1M"]

      grouped_log = Scale.log() |> Scale.domain([1, 10_000])
      assert Auto.formatter(grouped_log).(10_000) == "10,000"

      assert Auto.formatter(Scale.band() |> Scale.domain(["a", "b"])) == nil
    end
  end

  describe "locale" do
    test "\"en\" is the default and the only locale; another raises naming it" do
      assert Auto.notation([0, 1], locale: "en") == :plain

      assert_raise ArgumentError, ~r/unknown locale "fr"/, fn ->
        Auto.notation([0, 1], locale: "fr")
      end

      assert_raise ArgumentError, ~r/unknown locale/, fn ->
        Auto.time_format(span(60), locale: "de")
      end

      assert_raise ArgumentError, ~r/unknown locale/, fn ->
        Auto.formatter(Scale.band(), locale: "de")
      end
    end
  end

  describe "Axis.tick_count/2: by the length" do
    test "grows with the length and is capped at 10, never under 2" do
      counts = for w <- [0, 100, 240, 400, 600, 800, 2000], do: Axis.tick_count(w, :bottom)
      assert counts == [2, 2, 3, 5, 7, 10, 10]
      assert counts == Enum.sort(counts)

      assert Enum.map([70, 140, 300, 350, 1000], &Axis.tick_count(&1, :left)) ==
               [2, 4, 8, 10, 10]
    end

    test "a side reads its own spacing; a negative length is its magnitude" do
      assert Axis.tick_count(400, :top) == Axis.tick_count(400, :bottom)
      assert Axis.tick_count(400, :right) == Axis.tick_count(400, :left)
      assert Axis.tick_count(-300, :left) == 8
    end

    test "the hand-built axis keeps d3's ten" do
      scale = Scale.linear() |> Scale.domain([0, 100]) |> Scale.range([0, 100])
      ticks = scale |> Axis.bottom() |> Axis.generate() |> Map.fetch!(:children) |> tl()
      assert length(ticks) == 11
    end
  end
end
