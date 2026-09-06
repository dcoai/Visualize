defmodule Visualize.MixProject do
  use Mix.Project

  def project do
    [
      app: :visualize,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      name: "Visualize",
      description:
        "Server-side SVG and canvas visualization for Phoenix LiveView, in the shape of D3.",
      source_url: "https://gitlab.conet.yarina.org/dco-tek/visualize",
      package: package(),
      docs: docs(),
      test_coverage: [summary: [threshold: 0]],
      deps: deps()
    ]
  end

  # Only `lib/` reaches a consumer. `audit/` holds the surface scanner and its mix tasks
  # (dev and test); `test/support` compiles for tests alone.
  defp elixirc_paths(:test), do: ["lib", "audit", "test/support"]
  defp elixirc_paths(:dev), do: ["lib", "audit"]
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
      # `mix vis.surface` (spec/12 §2): the source-scan primitives and the golden renderer
      # shared with extc and extla. `only:` is load-bearing: dev/test deps are not transitive,
      # so nothing here reaches a consumer of visualize.
      {:surfex,
       git: "git@gitlab.conet.yarina.org:dco-tek/surfex.git",
       tag: "v0.1.0",
       only: [:dev, :test],
       runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  # The specification and the surface golden ship with the package: they are the contract
  # a consumer holds the library to, not internal documentation.
  defp package do
    [
      files: ~w(lib spec mix.exs README.md usage-rules.md API_SURFACE.md .formatter.exs),
      licenses: [],
      links: %{"GitLab" => "https://gitlab.conet.yarina.org/dco-tek/visualize"}
    ]
  end

  # The references the specification makes on purpose to functions that are internal
  # (behaviour callbacks; the family modules behind `Geo.Projection` and `CanvasBinary`) or
  # that the decisions log records as removed or as never having existed (D-2, D-13).
  @internal_prefixes [
    "Visualize.Backend.SVG.",
    "Visualize.Backend.Canvas.",
    "Visualize.Backend.CanvasBinary.SVG.",
    "Visualize.Backend.CanvasBinary.PathEncoder.",
    "Visualize.Backend.CanvasBinary.Opcodes."
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
      # The specification refers, on purpose, to internal functions (behaviour callbacks and
      # the family modules behind `Geo.Projection` and `CanvasBinary`) and to functions the
      # decisions log records as removed or as called by code that has never run (D-2, D-13).
      # Those references are the document's content, not broken links.
      skip_code_autolink_to: &__MODULE__.internal_reference?/1,
      extras:
        [
          "README.md",
          "usage-rules.md",
          {"spec/README.md", filename: "specification", title: "Specification index"}
          | Path.wildcard("spec/[0-9]*.md")
        ] ++ ["API_SURFACE.md"],
      groups_for_extras: [
        Specification: ~r"spec/",
        Conformance: ["API_SURFACE.md"]
      ],
      groups_for_modules: [
        Facade: [Visualize],
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
          Visualize.Data
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
