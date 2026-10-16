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

# The raster tests need a resvg binary (spec/12 §4, D-121). CI names its pinned download in
# VISUALIZE_RESVG, and a value that names no executable stops the suite rather than skipping
# it; unset, the library looks for `resvg` on the PATH, and without one the :resvg tests are
# excluded.
case System.get_env("VISUALIZE_RESVG") do
  nil ->
    :ok

  path ->
    System.find_executable(Path.expand(path)) ||
      raise "VISUALIZE_RESVG names no executable file: #{inspect(path)}"

    Application.put_env(:visualize, :resvg, path)
end

resvg =
  if Visualize.Render.Raster.available?() do
    []
  else
    IO.puts("Excluding the :resvg raster tests: no resvg binary (set VISUALIZE_RESVG or PATH).")
    [:resvg]
  end

# A test that needs both — a hook replayed under node, compared with resvg's raster (#652) —
# is tagged :js_resvg alone: `--only js` includes a :js test even when :resvg is excluded,
# so it carries neither, and runs only where both are present.
js_resvg = if js == [] and resvg == [], do: [], else: [:js_resvg]

# A message a test waits for must arrive, so an `assert_receive` with no timeout of its own
# waits as long as the test may run: the test's timeout ends a wait whose message never
# comes, and its report names the waiting line (spec/12 §6, #736).
#
# As many cases at once as there are schedulers, half ExUnit's default of twice as many: a
# CI runner runs several jobs at once, so 32 cases on its 16 cores each had a sliver of one
# and a long test crossed its timeout; measured, the suite takes as long either way
# (spec/12 §6, #735).
ExUnit.start(
  exclude: [:benchmark | js ++ resvg ++ js_resvg],
  timeout: 60_000,
  assert_receive_timeout: 60_000,
  max_cases: System.schedulers_online()
)

# A zoned time scale reads the host's time zone database (spec/03 §7.4, D-115); the library
# ships none, so the suite configures the test-only `tz` here as a host would.
Calendar.put_time_zone_database(Tz.TimeZoneDatabase)
