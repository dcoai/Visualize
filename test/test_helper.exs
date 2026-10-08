# The benchmark-style tests state a measurement rather than gate one: `--only benchmark`.
# The executed hook tests need node (spec/12 §6, #458): without it they are excluded, and
# `mix test --only js` is the CI job that always runs them.
js =
  if Visualize.JsHooks.node_path() do
    []
  else
    IO.puts("Excluding the :js hook tests: no node on the path (mix test --only js runs them).")
    [:js]
  end

ExUnit.start(exclude: [:benchmark | js])

# A zoned time scale reads the host's time zone database (spec/03 §7.4, D-115); the library
# ships none, so the suite configures the test-only `tz` here as a host would.
Calendar.put_time_zone_database(Tz.TimeZoneDatabase)
