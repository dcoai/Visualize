# The library's work counter (spec/12 §6, #462), so the gallery's cost guard counts
# reductions with the same helper as the library's suite (spec/14 §12.6, #469).
Code.require_file("../../test/support/work.ex", __DIR__)

# The measured tests run the resvg binary (spec/12 §4, D-121), found as the library's suite
# finds it: VISUALIZE_RESVG, which must name an executable, else `resvg` on the PATH; with
# neither the :resvg tests are excluded in one printed line (#489).
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
    IO.puts("Excluding the :resvg measured tests: no resvg binary (set VISUALIZE_RESVG or PATH).")
    [:resvg]
  end

ExUnit.start(exclude: resvg)
