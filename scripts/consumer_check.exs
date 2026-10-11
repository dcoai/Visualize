# The consumer-compile gate (spec/12 §4): what a project that depends on visualize and on
# nothing else actually builds. A throwaway Mix project is generated under the system temp
# directory with `{:visualize, path: <this checkout>}` as its only dependency, compiled in
# `MIX_ENV=prod`, and asked what it can load. Phoenix and Nx are optional dependencies of
# visualize, so neither may arrive: neither the components nor the chart builder (spec/14
# §18, D-85) may be loadable, since both compile only under the `Phoenix.Component` guard.
# Nor may `Resvg` or its NIF loader: PNG output runs the resvg binary over a port and takes
# no package (D-121). Nor Makeup, the examples' code highlighter (#506): its lexers are
# dependencies of the examples app alone. Nor `:telemetry`, optional for the telemetry feed
# (D-140), nor `Telemetry.Metrics`, which that feed reads by its fields and only the tests
# depend on. The probe calls `Visualize.Render.to_png/2` with
# no `:resvg` setting and its own PATH set to an empty directory, so it is the run of that
# function on a host without the binary whatever this host has installed:
# `{:error, :no_rasterizer}` (spec/12 §4).
# The audit, the models and the golden renderer compile from directories a consumer never
# sees (`elixirc_paths/1` in mix.exs).
#
# Run from the repository root: `elixir scripts/consumer_check.exs`. Exits non-zero, with
# the failing assertion, when the consumer build carries anything it should not.
defmodule Visualize.ConsumerCheck do
  @absent ~w(Phoenix.Component Phoenix.HTML.Safe Nx Jason Visualize.Components
             Visualize.Components.Tree Visualize.Chart.Builder
             Visualize.Chart.Builder.Store Visualize.Chart.Builder.Preview
             Visualize.Chart.Builder.Editor Visualize.Chart.Builder.Layers
             Visualize.Chart.Builder.Inspector Visualize.Chart.Builder.Params
             Visualize.Chart.Builder.Document
             Visualize.Audit ExTLA.Spec Surfex.Golden Tz.TimeZoneDatabase
             Resvg RustlerPrecompiled Makeup :telemetry Telemetry.Metrics)
  @present ~w(Visualize Visualize.Scale Visualize.Hooks Visualize.Hooks.Builder
              Visualize.Backend.CanvasBinary Visualize.Render.Raster
              Visualize.Feed.Monitor Visualize.Feed.Telemetry)

  def run do
    root = File.cwd!()
    dir = Path.join(System.tmp_dir!(), "visualize_consumer_#{System.os_time(:millisecond)}")
    File.mkdir_p!(Path.join(dir, "lib"))
    File.write!(Path.join(dir, "mix.exs"), mix_exs(root))

    IO.puts("consumer project in #{dir}")
    mix(dir, ~w(deps.get))
    compile_warning_free(dir)
    mix(dir, ["run", "-e", probe()])

    File.rm_rf!(dir)

    IO.puts(
      "consumer build is lib/ only - no Phoenix, no Nx, no Jason, no table, no Explorer/tz, no Resvg, no Makeup, no telemetry; no binary, no PNG"
    )
  end

  defp mix_exs(root) do
    """
    defmodule Consumer.MixProject do
      use Mix.Project

      def project do
        [app: :consumer, version: "0.1.0", deps: [{:visualize, path: #{inspect(root)}}]]
      end
    end
    """
  end

  # One `=` per module: a match error names the module that broke the claim.
  defp probe do
    absent = Enum.map(@absent, &"false = Code.ensure_loaded?(#{&1})")
    present = Enum.map(@present, &"true = Code.ensure_loaded?(#{&1})")

    png = [
      "nil = Application.get_env(:visualize, :resvg)",
      ~S{System.put_env("PATH", Path.expand("lib"))},
      "nil = System.find_executable(\"resvg\")",
      "{:error, :no_rasterizer} = Visualize.Render.to_png(Visualize.IR.Element.root(4, 4))"
    ]

    Enum.join(absent ++ present ++ png, "; ")
  end

  # `--warnings-as-errors` only covers the consumer's own (empty) code; a warning printed
  # while compiling the visualize dependency is what an optional-dependency slip looks like.
  defp compile_warning_free(dir) do
    {output, status} =
      System.cmd("mix", ~w(compile --force),
        cd: dir,
        env: [{"MIX_ENV", "prod"}],
        stderr_to_stdout: true
      )

    IO.write(output)
    warnings = output |> String.split("\n") |> Enum.filter(&String.contains?(&1, "warning:"))

    if status != 0 or warnings != [] do
      IO.puts(
        :stderr,
        "consumer check failed: exit #{status}, #{length(warnings)} warning(s) while compiling visualize"
      )

      System.halt(1)
    end
  end

  defp mix(dir, args) do
    {_, status} =
      System.cmd("mix", args,
        cd: dir,
        env: [{"MIX_ENV", "prod"}],
        into: IO.stream(:stdio, :line)
      )

    if status != 0 do
      IO.puts(:stderr, "consumer check failed at mix #{Enum.join(args, " ")} (exit #{status})")
      System.halt(status)
    end
  end
end

Visualize.ConsumerCheck.run()
