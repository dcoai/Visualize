defmodule Visualize.MixProject do
  use Mix.Project

  # The version between releases carries `-dev`, so no commit claims to be the release it
  # merely follows. `~/Projects/claude-tools/release.exs` moves this attribute — it edits
  # `@version`, not an inline `version:` — and RELEASING.md describes the lifecycle.
  @version "0.6.0"

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
      extra_applications: [:logger, :crypto]
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
      # `Visualize.Feed.Telemetry` (spec/08 §11.6) attaches to `:telemetry`, optional like
      # Nx: a host without it builds warning-free and never starts the provider (D-50).
      {:telemetry, "~> 1.0", optional: true},
      # Real `Telemetry.Metrics` definitions in the telemetry provider's tests. The provider
      # reads a definition by its fields and takes no dependency on the package (D-140).
      {:telemetry_metrics, "~> 1.0", only: :test},
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
      {:surfex, "~> 0.9.0", only: [:dev, :test], runtime: false},
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
  # not internal documentation; the usage rules ship because the usage_rules tooling reads
  # them from `deps/`. The specification, the surface golden and the usage rules are not
  # docs extras (D-133). RELEASING.md is deliberately absent — it is a maintainer document.
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

  # Hexdocs carries the README, the guides and the changelog (D-133). The specification, the
  # surface golden and the usage rules ship in the package but are read on GitHub, so a
  # shipped document links them by absolute URL; test/visualize/doc_links_test.exs refuses a
  # relative link to a file that is not one of these extras.
  defp docs do
    [
      main: "readme",
      # The tag of the version being documented, which the mirror carries: a "View source"
      # link opens the code that was published, not main.
      source_ref: "v#{@version}",
      # The changelog records `Render.with_backend/2` as removed (D-2): a reference to a
      # function that no longer exists, on purpose, not a broken link. The rest of this list
      # served the specification's references to internal functions, and went with it (D-133).
      skip_code_autolink_to: ["Visualize.Render.with_backend/2"],
      extras: [
        {"README.md", title: "README"},
        # The guides, in reading order, ahead of the reference material: where a newcomer
        # starts, then the declarative layer, then the one-page summary.
        "guides/getting_started.md",
        "guides/liveview.md",
        "guides/designing_charts.md",
        "guides/cheatsheet.cheatmd",
        # The changelog ships in `files:`, so the README's Installation section links it
        # as the reference for moving a pinned tag. A link from a shipping document has
        # to resolve in the published docs too, which means being an extra.
        "CHANGELOG.md"
      ],
      # ExDoc lists ungrouped extras first, so the README alone stays ungrouped and the
      # guides follow it, ahead of the reference documents.
      groups_for_extras: [
        Guides: ~r"guides/",
        Reference: ["CHANGELOG.md"]
      ],
      groups_for_modules: [
        Facade: [Visualize],
        "Declarative chart": ~r"Visualize\.Chart",
        Boards: ~r"Visualize\.Board",
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
        Feeds: [
          ~r"Visualize\.Feed",
          Visualize.Data.Schema,
          Visualize.Data.Schema.Cache,
          Visualize.Data.Delivery,
          Visualize.Signals
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
