defmodule Examples.MixProject do
  use Mix.Project

  def project do
    [
      app: :examples,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      mod: {Examples.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp deps do
    [
      {:visualize, path: ".."},
      {:phoenix, "~> 1.7"},
      {:phoenix_live_view, "~> 1.0"},
      {:phoenix_html, "~> 4.0"},
      {:bandit, "~> 1.0"},
      {:jason, "~> 1.4"}
    ]
  end
end
