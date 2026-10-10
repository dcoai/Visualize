defmodule Visualize.MixProject do
  use Mix.Project

  # The version between releases carries `-dev`, so no commit claims to be the release it
  # merely follows. `~/Projects/claude-tools/release.exs` moves this attribute — it edits
  # `@version`, not an inline `version:` — and RELEASING.md describes the lifecycle.
  @version "0.2.4"

  def project do
    [
      app: :visualize,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      name: "Visualize",
      description:
        "Server-side SVG and canvas visualization for Phoenix LiveView, in the shape of D3.",
      # The public home (#516): GitLab push-mirrors main and the tags here.
      source_url: "https://github.com/dcoai/Visualize",
      package: package(),
      docs: docs(),
      aliases: [
        "vis.verify": &verify_models/1,
        # Every gate CI runs, in CI's order; see scripts/check.exs.
        "vis.check": ["cmd elixir scripts/check.exs"]
      ],
      test_coverage: [summary: [threshold: 0]],
      deps: deps()
    ]
  end

  # Only `lib/` reaches a consumer. `audit/` holds the surface scanner and its mix tasks
  # (dev and test); `test/support` compiles for tests alone.
  defp elixirc_paths(:test), do: ["lib", "audit", "specs", "test/support"]
  defp elixirc_paths(:dev), do: ["lib", "audit", "specs"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:nx, "~> 0.9", optional: true},
      # `Visualize.Chart.to_json/1` and `from_json/1` (spec/14 §11): optional like Nx, so a
      # consumer without Jason builds silently and the two functions return an error value.
      {:jason, "~> 1.4", optional: true},
      # `Data.Table.rows/1` (spec/08 §6) reads Explorer frames, and anything else that
      # implements `Table.Reader`, through the protocol. The package is the protocol and
      # two impls, optional like Nx: without it lists, column maps and tensors still work
      # and a struct source raises at the call (D-52).
      {:table, "~> 0.1.2", optional: true},
      # Explorer frames in the `Data.Table` tests only; scripts/consumer_check.exs proves
      # neither Explorer nor `Table.Reader` reaches a consumer.
      {:explorer, "~> 0.12", only: :test},
      # A time zone database for the zoned time scale's tests (spec/03 §7.5, #447). The library
      # reads the host's `Calendar.TimeZoneDatabase` and takes no tz dependency (D-115); the
      # tests configure this one in test/test_helper.exs. `only:` is load-bearing: test deps
      # are not transitive, and scripts/consumer_check.exs proves `Tz` never reaches a consumer.
      {:tz, "~> 0.28", only: :test},
      # The LiveView components (spec/10 §2-3) compile only when `Phoenix.Component` is
      # loaded. `optional:` is load-bearing, and `only:` would not do: Mix prunes the code
      # path to a dependency's declared deps while compiling it, so a guard over an
      # undeclared Phoenix never fires in a host. A host without LiveView never fetches it;
      # scripts/consumer_check.exs proves that on every pipeline (D-45).
      {:phoenix_live_view, "~> 1.0", optional: true},
      # `mix vis.surface` (spec/12 §2): the source-scan primitives and the golden renderer
      # shared with extc and extla. `only:` is load-bearing: dev/test deps are not transitive,
      # so nothing here reaches a consumer of visualize.
      {:surfex, "~> 0.6.2", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      # Property tests over the scale protocol (spec/03 §1.3; test/visualize/scale/).
      {:stream_data, "~> 1.4", only: [:dev, :test]},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      # `mix vis.verify` (spec/12 §5): the model of the force simulation. Pinned by tag, with
      # the lock entry committed, so CI and every workstation build the same extla (#441).
      {:extla, extla_source() ++ [only: [:dev, :test], runtime: false]}
    ]
  end

  # A local extla checkout is an explicit opt-in (`EXTLA_PATH=../extla`), never inferred
  # from a sibling directory: that is how an unannounced rename reached the build.
  defp extla_source do
    case System.get_env("EXTLA_PATH") do
      nil -> [git: "git@gitlab.conet.yarina.org:dco-tek/extla.git", tag: "v0.4.0"]
      path -> [path: path]
    end
  end

  # Every model, checked one at a time. `Mix.Task.rerun/2`, not a list alias: Mix remembers
  # a task by name and silently skips it the second time.
  @models ~w(Visualize.Specs.ForceSimulation)
  defp verify_models(_args), do: Enum.each(@models, &Mix.Task.rerun("extla.check", [&1]))

  # The guides ship with the package, as hexdocs extras a reader starts from. The
  # specification, the surface golden and the changelog ship with it too: they are
  # the contract a consumer holds the library to, and the record of what an upgrade brings,
  # not internal documentation. RELEASING.md is deliberately absent — it is a maintainer
  # document, and nothing that ships may link to a file that does not.
  defp package do
    [
      files:
        ~w(lib guides spec mix.exs README.md LICENSE CHANGELOG.md usage-rules.md API_SURFACE.md .formatter.exs),
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/dcoai/Visualize",
        "Changelog" => "https://hexdocs.pm/visualize/changelog.html"
      }
    ]
  end

  # The references the specification makes on purpose to functions that are internal
  # (behaviour callbacks; the family modules behind `Geo.Projection` and `CanvasBinary`; the
  # one module that calls the resvg binary, spec/09 §9) or that the decisions log
  # records as removed or as never having existed (D-2, D-13).
  @internal_prefixes [
    "Visualize.Backend.SVG.",
    "Visualize.Backend.Canvas.",
    "Visualize.Backend.CanvasBinary.SVG.",
    "Visualize.Backend.CanvasBinary.PathEncoder.",
    "Visualize.Backend.CanvasBinary.Opcodes.",
    "Visualize.Render.Raster"
  ]
  @recorded_absent [
    "Visualize.Geo.Projection.family/1",
    "Visualize.Render.with_backend/2",
    "Visualize.Scale.scale/2",
    "Visualize.Scale.color/0",
    "Visualize.Scale.scheme/2"
  ]

  @doc false
  def internal_reference?(reference) do
    reference in @recorded_absent or
      Enum.any?(@internal_prefixes, &String.starts_with?(reference, &1))
  end

  # `spec/README.md` gets an explicit filename: two README.md extras otherwise collide.
  defp docs do
    [
      main: "readme",
      # The tag of the version being documented, which the mirror carries: a "View source"
      # link opens the code that was published, not main.
      source_ref: "v#{@version}",
      # The specification refers, on purpose, to internal functions (behaviour callbacks and
      # the family modules behind `Geo.Projection` and `CanvasBinary`) and to functions the
      # decisions log records as removed or as called by code that has never run (D-2, D-13).
      # Those references are the document's content, not broken links.
      skip_code_autolink_to: &__MODULE__.internal_reference?/1,
      extras:
        [
          "README.md",
          # The guides, in reading order, ahead of the reference material: where a newcomer
          # starts, then the declarative layer, then the one-page summary.
          "guides/getting_started.md",
          "guides/liveview.md",
          "guides/designing_charts.md",
          "guides/cheatsheet.cheatmd",
          "usage-rules.md",
          # The changelog ships in `files:`, so the README's Installation section links it
          # as the reference for moving a pinned tag. A link from a shipping document has
          # to resolve in the published docs too, which means being an extra.
          "CHANGELOG.md",
          {"spec/README.md", filename: "specification", title: "Specification index"}
          | Path.wildcard("spec/[0-9]*.md")
        ] ++ ["API_SURFACE.md"],
      # ExDoc lists ungrouped extras first, so the README alone stays ungrouped and the
      # guides follow it, ahead of the reference documents.
      groups_for_extras: [
        Guides: ~r"guides/",
        Reference: ["usage-rules.md", "CHANGELOG.md"],
        Specification: ~r"spec/",
        Conformance: ["API_SURFACE.md"]
      ],
      groups_for_modules: [
        Facade: [Visualize],
        "Declarative chart": ~r"Visualize\.Chart",
        Scales: ~r"Visualize\.Scale",
        Shapes: ~r"Visualize\.Shape",
        "Axes and formatting": [Visualize.Axis, Visualize.Format],
        Layouts: ~r"Visualize\.Layout",
        Geo: [~r"Visualize\.Geo", Visualize.Polygon, ~r"Visualize\.Contour"],
        Utilities: [
          Visualize.Color,
          Visualize.Interpolate,
          Visualize.Ease,
          Visualize.Random,
          Visualize.Data,
          Visualize.Data.Table
        ],
        "IR and rendering": [
          ~r"Visualize\.IR",
          ~r"Visualize\.Backend",
          Visualize.Render,
          Visualize.Incremental,
          Visualize.Benchmark
        ],
        "SVG elements": ~r"Visualize\.SVG",
        LiveView: [~r"Visualize\.Components", ~r"Visualize\.Hooks"]
      ]
    ]
  end
end
