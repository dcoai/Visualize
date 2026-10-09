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

ExUnit.start(exclude: [:benchmark | js ++ resvg])

# A zoned time scale reads the host's time zone database (spec/03 §7.4, D-115); the library
# ships none, so the suite configures the test-only `tz` here as a host would.
Calendar.put_time_zone_database(Tz.TimeZoneDatabase)
