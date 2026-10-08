# The benchmark-style tests state a measurement rather than gate one: `--only benchmark`.
ExUnit.start(exclude: [:benchmark])

# A zoned time scale reads the host's time zone database (spec/03 §7.4, D-115); the library
# ships none, so the suite configures the test-only `tz` here as a host would.
Calendar.put_time_zone_database(Tz.TimeZoneDatabase)
