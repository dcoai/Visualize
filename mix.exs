defmodule Visualize.MixProject do
  use Mix.Project

  def project do
    [
      app: :visualize,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
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
       runtime: false}
    ]
  end
end
