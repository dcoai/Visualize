defmodule Visualize.Scale.TimeZoneTest do
  @moduledoc """
  A time scale's display zone (spec/03 §7.4, D-115, #447): ticks and `nice/1` on the zone's
  local calendar across the spring-forward and fall-back transitions, sub-day ticks on real
  instants (the repeated hour twice, the skipped hour absent), zones off the whole hour,
  `invert/2` and the labels in the zone, the declarative `zone` key and its validation fault,
  and a scale without a zone unchanged. The suite's database is `tz` (test/test_helper.exs);
  a host without one is test/visualize/scale/time_zone_database_test.exs.
  """
  use ExUnit.Case, async: true

  import Visualize.Chart.Build, except: [scale: 3]

  alias Visualize.{Chart, Format, Scale}
  alias Visualize.Chart.{Frame, Validator}
  alias Visualize.Scale.Time

  @new_york "America/New_York"
  @london "Europe/London"

  defp scale(zone, d0, d1), do: Scale.time() |> Scale.zone(zone) |> Scale.domain([d0, d1])
  defp ticks(zone, d0, d1, count), do: zone |> scale(d0, d1) |> Scale.ticks(count)

  defp utc(ticks), do: Enum.map(ticks, &DateTime.shift_zone!(&1, "Etc/UTC"))
  defp local(ticks), do: Enum.map(ticks, &{DateTime.to_naive(&1), &1.zone_abbr})
  defp hours_between(ticks), do: ticks |> Enum.chunk_every(2, 1, :discard) |> Enum.map(&gap/1)
  defp gap([a, b]), do: DateTime.diff(b, a, :hour)

  describe "day ticks are local midnights across a transition" do
    test "New York, fall back: the day of 1 November is 25 hours" do
      ticks = ticks(@new_york, ~U[2026-10-30 16:00:00Z], ~U[2026-11-03 17:00:00Z], 4)

      assert utc(ticks) == [
               ~U[2026-10-31 04:00:00Z],
               ~U[2026-11-01 04:00:00Z],
               ~U[2026-11-02 05:00:00Z],
               ~U[2026-11-03 05:00:00Z]
             ]

      assert Enum.all?(
               ticks,
               &(&1.time_zone == @new_york and DateTime.to_time(&1) == ~T[00:00:00])
             )

      assert hours_between(ticks) == [24, 25, 24]
    end

    test "New York, spring forward: the day of 8 March is 23 hours" do
      ticks = ticks(@new_york, ~U[2026-03-06 17:00:00Z], ~U[2026-03-10 16:00:00Z], 4)

      assert utc(ticks) == [
               ~U[2026-03-07 05:00:00Z],
               ~U[2026-03-08 05:00:00Z],
               ~U[2026-03-09 04:00:00Z],
               ~U[2026-03-10 04:00:00Z]
             ]

      assert hours_between(ticks) == [24, 23, 24]
    end

    test "London, fall back and spring forward" do
      autumn = ticks(@london, ~U[2026-10-23 12:00:00Z], ~U[2026-10-26 12:00:00Z], 3)

      assert utc(autumn) == [
               ~U[2026-10-23 23:00:00Z],
               ~U[2026-10-24 23:00:00Z],
               ~U[2026-10-26 00:00:00Z]
             ]

      assert local(autumn) == [
               {~N[2026-10-24 00:00:00], "BST"},
               {~N[2026-10-25 00:00:00], "BST"},
               {~N[2026-10-26 00:00:00], "GMT"}
             ]

      spring = ticks(@london, ~U[2026-03-27 12:00:00Z], ~U[2026-03-30 12:00:00Z], 3)

      assert utc(spring) == [
               ~U[2026-03-28 00:00:00Z],
               ~U[2026-03-29 00:00:00Z],
               ~U[2026-03-29 23:00:00Z]
             ]

      assert hours_between(spring) == [24, 23]
    end
  end

  describe "week and month ticks are local boundaries" do
    test "weeks start at local Monday midnight on both sides of the fall back" do
      ticks = ticks(@new_york, ~U[2026-10-01 12:00:00Z], ~U[2026-12-01 12:00:00Z], 8)

      assert utc(ticks) == [
               ~U[2026-10-05 04:00:00Z],
               ~U[2026-10-12 04:00:00Z],
               ~U[2026-10-19 04:00:00Z],
               ~U[2026-10-26 04:00:00Z],
               ~U[2026-11-02 05:00:00Z],
               ~U[2026-11-09 05:00:00Z],
               ~U[2026-11-16 05:00:00Z],
               ~U[2026-11-23 05:00:00Z],
               ~U[2026-11-30 05:00:00Z]
             ]

      assert Enum.all?(ticks, &(Date.day_of_week(DateTime.to_date(&1)) == 1))
    end

    test "months start at local midnight on the 1st, in New York" do
      ticks = ticks(@new_york, ~U[2026-01-15 00:00:00Z], ~U[2026-12-15 00:00:00Z], 12)

      assert utc(ticks) == [
               ~U[2026-02-01 05:00:00Z],
               ~U[2026-03-01 05:00:00Z],
               ~U[2026-04-01 04:00:00Z],
               ~U[2026-05-01 04:00:00Z],
               ~U[2026-06-01 04:00:00Z],
               ~U[2026-07-01 04:00:00Z],
               ~U[2026-08-01 04:00:00Z],
               ~U[2026-09-01 04:00:00Z],
               ~U[2026-10-01 04:00:00Z],
               # midnight of 1 November precedes the fall back at 02:00 EDT
               ~U[2026-11-01 04:00:00Z],
               ~U[2026-12-01 05:00:00Z]
             ]
    end

    test "months start at local midnight on the 1st, in London" do
      ticks = ticks(@london, ~U[2026-02-15 00:00:00Z], ~U[2026-11-15 00:00:00Z], 9)

      assert utc(ticks) == [
               ~U[2026-03-01 00:00:00Z],
               ~U[2026-03-31 23:00:00Z],
               ~U[2026-04-30 23:00:00Z],
               ~U[2026-05-31 23:00:00Z],
               ~U[2026-06-30 23:00:00Z],
               ~U[2026-07-31 23:00:00Z],
               ~U[2026-08-31 23:00:00Z],
               ~U[2026-09-30 23:00:00Z],
               ~U[2026-11-01 00:00:00Z]
             ]
    end
  end

  describe "hour ticks are real instants" do
    test "across the fall back both 01:00s are ticked, at distinct instants" do
      ticks = ticks(@new_york, ~U[2026-11-01 03:30:00Z], ~U[2026-11-01 08:30:00Z], 5)

      assert utc(ticks) == [
               ~U[2026-11-01 04:00:00Z],
               ~U[2026-11-01 05:00:00Z],
               ~U[2026-11-01 06:00:00Z],
               ~U[2026-11-01 07:00:00Z],
               ~U[2026-11-01 08:00:00Z]
             ]

      assert Enum.map(ticks, &Format.time(&1, "%H:%M %Z")) ==
               ["00:00 EDT", "01:00 EDT", "01:00 EST", "02:00 EST", "03:00 EST"]
    end

    test "across the spring forward the skipped 02:00 is absent" do
      ticks = ticks(@new_york, ~U[2026-03-08 04:30:00Z], ~U[2026-03-08 09:30:00Z], 5)
      assert Enum.map(ticks, & &1.hour) == [0, 1, 3, 4, 5]
      assert hours_between(ticks) == [1, 1, 1, 1]
    end

    test "three-hour ticks keep to local hours divisible by three across the spring forward" do
      ticks = ticks(@new_york, ~U[2026-03-08 04:00:00Z], ~U[2026-03-09 04:00:00Z], 8)
      assert Enum.map(ticks, & &1.hour) == [0, 3, 6, 9, 12, 15, 18, 21, 0]
      assert Enum.all?(ticks, &(&1.minute == 0 and &1.second == 0))
      assert hours_between(ticks) == [2, 3, 3, 3, 3, 3, 3, 3]
    end

    test "fifteen-minute ticks in the repeated hour appear twice, in instant order" do
      ticks = ticks(@new_york, ~U[2026-11-01 05:30:00Z], ~U[2026-11-01 06:30:00Z], 4)

      assert Enum.map(ticks, &Format.time(&1, "%H:%M %Z")) ==
               ["01:30 EDT", "01:45 EDT", "01:00 EST", "01:15 EST", "01:30 EST"]

      assert ticks == Enum.sort(ticks, DateTime)
    end
  end

  describe "zones off the whole hour" do
    test "Asia/Kolkata (+05:30) and Asia/Kathmandu (+05:45) put day ticks at local midnight" do
      kolkata = ticks("Asia/Kolkata", ~U[2026-01-01 00:00:00Z], ~U[2026-01-05 00:00:00Z], 4)

      assert utc(kolkata) == [
               ~U[2026-01-01 18:30:00Z],
               ~U[2026-01-02 18:30:00Z],
               ~U[2026-01-03 18:30:00Z],
               ~U[2026-01-04 18:30:00Z]
             ]

      kathmandu = ticks("Asia/Kathmandu", ~U[2026-01-01 00:00:00Z], ~U[2026-01-05 00:00:00Z], 4)

      assert utc(kathmandu) == [
               ~U[2026-01-01 18:15:00Z],
               ~U[2026-01-02 18:15:00Z],
               ~U[2026-01-03 18:15:00Z],
               ~U[2026-01-04 18:15:00Z]
             ]

      assert Enum.all?(kolkata ++ kathmandu, &(DateTime.to_time(&1) == ~T[00:00:00]))
    end

    test "hour ticks are local hours, half past the UTC hour in Kolkata" do
      ticks = ticks("Asia/Kolkata", ~U[2026-01-01 00:00:00Z], ~U[2026-01-02 00:00:00Z], 8)
      assert Enum.map(ticks, & &1.hour) == [6, 9, 12, 15, 18, 21, 0, 3]
      assert Enum.all?(utc(ticks), &(&1.minute == 30))
    end
  end

  describe "nice, invert, apply and local" do
    test "nice/1 extends the domain to local boundaries, in the zone" do
      nice =
        @new_york |> scale(~U[2026-10-30 16:00:00Z], ~U[2026-11-03 17:00:00Z]) |> Scale.nice()

      [d0, d1] = nice.domain
      assert {DateTime.to_naive(d0), d0.time_zone} == {~N[2026-10-30 12:00:00], @new_york}
      assert {DateTime.to_naive(d1), d1.time_zone} == {~N[2026-11-03 12:00:00], @new_york}

      daily =
        @new_york |> scale(~U[2026-10-01 12:00:00Z], ~U[2026-10-20 12:00:00Z]) |> Scale.nice()

      assert utc(daily.domain) == [~U[2026-10-01 04:00:00Z], ~U[2026-10-21 04:00:00Z]]
    end

    test "invert/2 returns a DateTime in the zone; apply/2 is unchanged by the zone" do
      d0 = ~U[2026-11-01 04:00:00Z]
      d1 = ~U[2026-11-02 05:00:00Z]
      zoned = @new_york |> scale(d0, d1) |> Scale.range([0, 250])
      plain = Scale.time() |> Scale.domain([d0, d1]) |> Scale.range([0, 250])

      at = Scale.invert(zoned, 20)
      assert at.time_zone == @new_york
      assert DateTime.compare(at, Scale.invert(plain, 20)) == :eq
      assert Format.time(at, "%H:%M %Z") == "01:00 EST"

      for value <- [d0, ~U[2026-11-01 06:00:00Z], ~N[2026-11-01 12:00:00], ~D[2026-11-02]] do
        assert Scale.apply(zoned, value) == Scale.apply(plain, value)
      end
    end

    test "local/2 shifts a value into the zone, and is the identity without one" do
      scale = scale(@new_york, ~U[2026-01-01 00:00:00Z], ~U[2026-01-02 00:00:00Z])

      assert DateTime.to_naive(Time.local(scale, ~U[2026-11-01 06:00:00Z])) ==
               ~N[2026-11-01 01:00:00]

      assert Time.local(scale, ~D[2026-07-01]).zone_abbr == "EDT"
      assert Time.local(Scale.time(), ~N[2026-07-01 00:00:00]) == ~N[2026-07-01 00:00:00]
    end
  end

  describe "without a zone" do
    test "zone(nil) is a scale without a zone: the same struct, the same UTC ticks" do
      plain = Scale.time() |> Scale.domain([~U[2026-10-30 16:00:00Z], ~U[2026-11-03 17:00:00Z]])
      cleared = plain |> Scale.zone(@new_york) |> Scale.zone(nil)

      assert cleared == plain

      assert Scale.ticks(cleared, 4) == [
               ~U[2026-10-31 00:00:00Z],
               ~U[2026-11-01 00:00:00Z],
               ~U[2026-11-02 00:00:00Z],
               ~U[2026-11-03 00:00:00Z]
             ]
    end

    test "Etc/UTC ticks are the UTC ticks" do
      for {d0, d1, count} <- [
            {~U[2026-03-06 17:00:00Z], ~U[2026-03-10 16:00:00Z], 4},
            {~U[2026-11-01 03:30:00Z], ~U[2026-11-01 08:30:00Z], 5},
            {~U[2026-01-15 00:00:00Z], ~U[2026-12-15 00:00:00Z], 12},
            {~U[2000-01-01 00:00:00Z], ~U[2024-01-01 00:00:00Z], 10}
          ] do
        plain = Scale.time() |> Scale.domain([d0, d1])
        assert ticks("Etc/UTC", d0, d1, count) == Scale.ticks(plain, count)
      end
    end
  end

  describe "a zone the database cannot show" do
    test "an unknown name is refused by name at the setter" do
      assert Time.check_zone("Mars/Olympus_Mons") == {:error, :time_zone_not_found}
      assert Time.check_zone(@new_york) == :ok

      assert_raise ArgumentError, ~r/"Mars\/Olympus_Mons"/, fn ->
        Scale.zone(Scale.time(), "Mars/Olympus_Mons")
      end
    end

    test "zone/2 is a time scale's alone" do
      assert_raise FunctionClauseError, fn -> Scale.zone(Scale.linear(), @new_york) end
    end

    test "the declarative zone is a validation fault naming the zone" do
      {:ok, design} =
        Chart.compose([chart(), cartesian(), time_scale(:x, zone: "Mars/Olympus_Mons")])

      assert {:error, [{path, reason} = error]} = Validator.validate(design)
      assert path == [:frames, "main", :scales, "x", :zone]
      assert reason == {:zone, "Mars/Olympus_Mons", :time_zone_not_found}
      assert Validator.format(error) =~ ~s("Mars/Olympus_Mons")
    end
  end

  describe "the declarative layer (acceptance)" do
    # A design over the fall-back day in New York: its day ticks stand at local midnight and
    # the 25-hour day is drawn wider than the 24-hour days beside it.
    defp fall_back_frame(zone_opts) do
      rows =
        for h <- 0..102//6,
            do: %{t: DateTime.add(~U[2026-10-31 04:00:00Z], h * 3600, :second), v: rem(h, 7)}

      {:ok, design} =
        Chart.compose([
          chart(),
          source(:primary, [:t, :v]),
          cartesian(),
          time_scale(:x, zone_opts),
          linear_scale(:y),
          axis(:x, :bottom, ticks: 4, format: "%b %d %H:%M %Z"),
          line(:primary, %{x: :t, y: :v})
        ])

      Frame.new(Chart.from_map!(design), sources: %{primary: rows}, size: {400, 200})
    end

    defp tick_labels(frame) do
      svg = Frame.render(frame)

      Regex.scan(
        ~r/class="tick"[^>]*transform="translate\(([-\d.]+),0\)".*?<text[^>]*>([^<]*)<\/text>/s,
        svg
      )
      |> Enum.map(fn [_, x, label] -> {x |> Float.parse() |> elem(0), label} end)
    end

    test "time_scale(:x, zone: New York) over 1 November ticks local midnights, the days unequal" do
      frame = fall_back_frame(zone: @new_york)
      ticks = Scale.ticks(Frame.scale(frame, :x), 4)

      assert local(ticks) == [
               {~N[2026-10-31 00:00:00], "EDT"},
               {~N[2026-11-01 00:00:00], "EDT"},
               {~N[2026-11-02 00:00:00], "EST"},
               {~N[2026-11-03 00:00:00], "EST"},
               {~N[2026-11-04 00:00:00], "EST"}
             ]

      labels = tick_labels(frame)

      assert Enum.map(labels, &elem(&1, 1)) == [
               "Oct 31 00:00 EDT",
               "Nov 01 00:00 EDT",
               "Nov 02 00:00 EST",
               "Nov 03 00:00 EST",
               "Nov 04 00:00 EST"
             ]

      [a, b, c, d | _] = Enum.map(labels, &elem(&1, 0))
      assert_in_delta (c - b) / (b - a), 25 / 24, 1.0e-3
      assert_in_delta (d - c) / (b - a), 1.0, 1.0e-3
    end

    test "the same design without a zone ticks UTC midnights, as it always has" do
      labels = fall_back_frame([]) |> tick_labels() |> Enum.map(&elem(&1, 1))

      assert labels == [
               "Nov 01 00:00 UTC",
               "Nov 02 00:00 UTC",
               "Nov 03 00:00 UTC",
               "Nov 04 00:00 UTC"
             ]
    end
  end
end
