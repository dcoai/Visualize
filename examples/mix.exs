defmodule Examples.MixProject do
  use Mix.Project

  def project do
    [
      app: :examples,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      listeners: [Phoenix.CodeReloader]
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
      {:jason, "~> 1.4"},
      # The live board's in-process metrics (`/board`, #576): definitions the library's
      # telemetry provider reads.
      {:telemetry_metrics, "~> 1.0"},
      {:nx, "~> 0.9"},
      # Code on the pages is highlighted server-side (#506): Elixir, and HEEx in its ~H sigil
      # (makeup_eex, which needs an HTML lexer for the markup).
      {:makeup_elixir, "~> 1.0"},
      {:makeup_eex, "~> 2.0"},
      {:makeup_html, "~> 0.2"}
    ]
  end
end
