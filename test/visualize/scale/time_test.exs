defmodule Visualize.Scale.TimeTest do
  @moduledoc """
  `Scale.Time.ticks/2` and `nice/1` snap on every interval (spec/03 §7.3, D-16).
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Visualize.Scale
  alias Visualize.Scale.Time

  defp ticks(d0, d1, count \\ 10) do
    Scale.time() |> Scale.domain([d0, d1]) |> Scale.ticks(count)
  end

  defp midnight?(dt), do: DateTime.to_time(dt) == ~T[00:00:00]

  describe "sub-day intervals" do
    test "seconds snap to multiples of the step" do
      list = ticks(~U[2024-01-01 00:00:03Z], ~U[2024-01-01 00:00:47Z])
      assert Enum.map(list, & &1.second) == [5, 10, 15, 20, 25, 30, 35, 40, 45]
    end

    test "fifteen-minute ticks start at the first quarter hour inside the domain" do
      list = ticks(~U[2024-01-01 10:07:00Z], ~U[2024-01-01 12:07:00Z])
      assert List.first(list) == ~U[2024-01-01 10:15:00Z]
      assert List.last(list) == ~U[2024-01-01 12:00:00Z]
      assert Enum.all?(list, &(&1.minute in [0, 15, 30, 45] and &1.second == 0))
      assert length(list) == 8
    end

    test "hours align to the day, not to the domain start" do
      list = ticks(~U[2024-01-01 01:30:00Z], ~U[2024-01-02 01:30:00Z])
      assert Enum.map(list, & &1.hour) == [3, 6, 9, 12, 15, 18, 21, 0]
    end
  end

  describe "days and weeks" do
    test "the day ceiling is the next midnight when the domain starts mid-day" do
      list = ticks(~U[2024-01-01 12:00:00Z], ~U[2024-01-11 12:00:00Z])
      assert List.first(list) == ~U[2024-01-02 00:00:00Z]
      assert List.last(list) == ~U[2024-01-11 00:00:00Z]
      assert Enum.all?(list, &midnight?/1)
      assert length(list) == 10
    end

    test "a domain already at midnight keeps its first day" do
      list = ticks(~U[2024-01-01 00:00:00Z], ~U[2024-01-08 00:00:00Z], 7)
      assert List.first(list) == ~U[2024-01-01 00:00:00Z]
      assert length(list) == 8
    end

    test "two-day ticks fall on odd days of the month and restart each month" do
      list = ticks(~D[2024-01-20], ~D[2024-02-10])
      assert Enum.map(list, &DateTime.to_date(&1).day) == [21, 23, 25, 27, 29, 31, 1, 3, 5, 7, 9]
    end

    test "weeks snap to Monday" do
      list = ticks(~D[2024-01-03], ~D[2024-03-01])
      assert List.first(list) == ~U[2024-01-08 00:00:00Z]
      assert Enum.all?(list, &(Date.day_of_week(DateTime.to_date(&1)) == 1))
      assert length(list) == 8
    end
  end

  describe "months and years" do
    test "months snap to the first, and stepping from 31 January never builds day 31" do
      list = ticks(~D[2024-01-31], ~D[2024-08-15])

      assert Enum.map(list, &DateTime.to_date/1) == [
               ~D[2024-02-01],
               ~D[2024-03-01],
               ~D[2024-04-01],
               ~D[2024-05-01],
               ~D[2024-06-01],
               ~D[2024-07-01],
               ~D[2024-08-01]
             ]
    end

    test "quarters land on January, April, July and October" do
      list = ticks(~D[2024-01-15], ~D[2026-01-15])
      assert Enum.all?(list, &(DateTime.to_date(&1).month in [1, 4, 7, 10]))
      assert Enum.all?(list, &(DateTime.to_date(&1).day == 1))
      assert List.first(list) == ~U[2024-04-01 00:00:00Z]
      assert List.last(list) == ~U[2026-01-01 00:00:00Z]
    end

    test "years snap to 1 January" do
      list = ticks(~D[2000-06-01], ~D[2010-06-01])
      assert Enum.map(list, &DateTime.to_date(&1).year) == Enum.to_list(2001..2010)
      assert Enum.all?(list, &(DateTime.to_date(&1).month == 1 and DateTime.to_date(&1).day == 1))
    end

    test "a 24-year span takes two-year steps, not 8,767 daily ticks" do
      list = ticks(~D[2000-01-01], ~D[2024-01-01])
      assert Enum.map(list, &DateTime.to_date(&1).year) == Enum.to_list(2000..2024//2)
    end

    test "a century takes decades, three centuries take twenty-year steps" do
      assert ticks(~D[1900-01-01], ~D[2000-01-01]) |> Enum.map(&DateTime.to_date(&1).year) ==
               Enum.to_list(1900..2000//10)

      assert ticks(~D[1700-06-01], ~D[2000-06-01]) |> Enum.map(&DateTime.to_date(&1).year) ==
               Enum.to_list(1720..2000//20)
    end
  end

  describe "interval choice" do
    test "picks the neighbor closer to span / count in ratio, as d3 does" do
      # 58 days / 10 = 5.0 days: between 2 days (2.5×) and a week (1.4×) — the week.
      assert Time.interval(58 * 86_400, 10) == {:week, 1}
      # 1 year / 10 = 36.5 days: between a month (1.2×) and a quarter (2.5×) — the month.
      assert Time.interval(365 * 86_400, 10) == {:month, 1}
      # 200 days / 10 = 20 days: between a week (2.9×) and a month (1.5×) — the month.
      assert Time.interval(200 * 86_400, 10) == {:month, 1}
      assert Time.interval(3 * 3600, 10) == {:minute, 15}
      assert Time.interval(0, 10) == {:second, 1}
      assert Time.interval(1000 * 365 * 86_400, 10) == {:year, 100}
    end
  end

  describe "edge cases and value types" do
    test "a degenerate domain yields the single aligned value" do
      assert ticks(~U[2024-01-01 00:00:05Z], ~U[2024-01-01 00:00:05Z]) ==
               [~U[2024-01-01 00:00:05Z]]
    end

    test "a descending domain yields the same ticks descending" do
      up = ticks(~D[2024-01-01], ~D[2024-01-08])
      assert ticks(~D[2024-01-08], ~D[2024-01-01]) == Enum.reverse(up)
    end

    test "Date and NaiveDateTime domains produce UTC DateTime ticks" do
      for list <- [
            ticks(~D[2024-01-01], ~D[2024-01-04], 3),
            ticks(~N[2024-01-01 00:00:00], ~N[2024-01-04 00:00:00], 3)
          ] do
        assert Enum.all?(list, &match?(%DateTime{time_zone: "Etc/UTC"}, &1))
        assert length(list) == 4
      end
    end

    test "nice/1 extends outward to the interval's boundaries" do
      scale = Scale.time() |> Scale.domain([~U[2024-01-01 12:00:00Z], ~U[2024-01-11 12:00:00Z]])
      assert Scale.nice(scale).domain == [~U[2024-01-01 00:00:00Z], ~U[2024-01-12 00:00:00Z]]

      scale = Scale.time() |> Scale.domain([~D[2000-06-01], ~D[2010-06-01]])
      assert Scale.nice(scale).domain == [~U[2000-01-01 00:00:00Z], ~U[2011-01-01 00:00:00Z]]
    end

    test "nice/1 leaves an aligned domain alone" do
      scale = Scale.time() |> Scale.domain([~U[2024-01-01 00:00:00Z], ~U[2024-01-08 00:00:00Z]])
      assert Scale.nice(scale).domain == [~U[2024-01-01 00:00:00Z], ~U[2024-01-08 00:00:00Z]]
    end
  end

  describe "properties" do
    # From 1970 to 2100, spans from one minute to two centuries.
    defp domain_gen do
      gen all(
            start <- integer(0..4_000_000_000),
            span <- integer(60..(200 * 365 * 86_400)),
            count <- integer(2..20)
          ) do
        {DateTime.from_unix!(start), DateTime.from_unix!(start + span), count}
      end
    end

    property "ticks are ascending, inside the domain, and about count in number" do
      check all({d0, d1, count} <- domain_gen()) do
        list = ticks(d0, d1, count)

        assert list == Enum.sort(list, DateTime)
        assert list == Enum.uniq(list)
        assert Enum.all?(list, &(DateTime.compare(&1, d0) != :lt))
        assert Enum.all?(list, &(DateTime.compare(&1, d1) != :gt))
        # The ratio between neighboring intervals is at most 4.3, so the closer neighbor
        # is within 2.1× of the target; the nice-step years within 1.5×.
        assert length(list) <= 2.2 * count + 2
        assert length(list) >= count / 2.2 - 2
      end
    end

    property "every tick sits on a boundary of the interval that produced it" do
      check all({d0, d1, count} <- domain_gen()) do
        list = ticks(d0, d1, count)
        {unit, n} = Time.interval(DateTime.to_unix(d1) - DateTime.to_unix(d0), count)

        for tick <- list do
          unix = DateTime.to_unix(tick)
          date = DateTime.to_date(tick)

          case unit do
            :second -> assert rem(unix, n) == 0
            :minute -> assert rem(unix, 60 * n) == 0
            :hour -> assert rem(unix, 3600 * n) == 0
            :day -> assert midnight?(tick) and rem(date.day - 1, n) == 0
            :week -> assert midnight?(tick) and Date.day_of_week(date) == 1
            :month -> assert midnight?(tick) and date.day == 1 and rem(date.month - 1, n) == 0
            :year -> assert midnight?(tick) and date.month == 1 and date.day == 1
          end

          if unit == :year, do: assert(rem(date.year, n) == 0)
        end
      end
    end
  end
end
