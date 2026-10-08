defmodule Visualize.Scale.TimeZoneDatabaseTest do
  @moduledoc """
  A host without a time zone database (spec/03 §7.4, D-115, #447): Elixir's default
  `Calendar.UTCOnlyTimeZoneDatabase` cannot show any zone but `Etc/UTC`, and a zoned time
  scale says so by name — `ArgumentError` at the setter, the validation fault
  `{:zone, name, :utc_only_time_zone_database}` in a design — never a silent fallback to
  UTC. The database is global, so this module swaps it synchronously and restores the
  suite's own on exit.
  """
  use ExUnit.Case, async: false

  import Visualize.Chart.Build

  alias Visualize.{Chart, Scale}
  alias Visualize.Chart.Validator
  alias Visualize.Scale.Time

  setup do
    suite = Calendar.get_time_zone_database()
    Calendar.put_time_zone_database(Calendar.UTCOnlyTimeZoneDatabase)
    on_exit(fn -> Calendar.put_time_zone_database(suite) end)
  end

  test "the setter refuses the zone by name and says the host has no database" do
    assert Time.check_zone("America/New_York") == {:error, :utc_only_time_zone_database}

    error = assert_raise ArgumentError, fn -> Scale.zone(Scale.time(), "America/New_York") end
    assert error.message =~ ~s("America/New_York")
    assert error.message =~ "no time zone database"
  end

  test "Etc/UTC needs no database" do
    assert Time.check_zone("Etc/UTC") == :ok
    assert Scale.zone(Scale.time(), "Etc/UTC").zone == "Etc/UTC"
  end

  test "a design is refused with a fault naming the zone, not drawn in UTC" do
    {:ok, design} = Chart.compose([chart(), cartesian(), time_scale(:x, zone: "Europe/London")])

    assert {:error, [{[:frames, :main, :scales, :x, :zone], reason} = error]} =
             Validator.validate(design)

    assert reason == {:zone, "Europe/London", :utc_only_time_zone_database}
    assert Validator.format(error) =~ ~s(time zone "Europe/London" cannot be shown)
    assert {:error, _errors} = Chart.from_map(design)
  end
end
