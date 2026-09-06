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

  # Only `lib/` reaches a consumer; test support compiles for tests alone.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
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
      {:nx, "~> 0.9", optional: true}
    ]
  end
end
