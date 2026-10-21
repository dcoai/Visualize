defmodule Examples.MixProject do
  use Mix.Project

  def project do
    [
      app: :examples,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  # `test/support` compiles for tests alone, as the library's does (#838).
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

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
      # An Explorer data frame as a chart's source, on /sources (D-52, #781).
      {:explorer, "~> 0.12"},
      # The host's time zone database (D-115): the library reads whatever the host configures,
      # and the synced dashboard shows its time axes in a zone the viewer picks.
      {:tz, "~> 0.28"},
      # Code on the pages is highlighted server-side (#506): Elixir, and HEEx in its ~H sigil
      # (makeup_eex, which needs an HTML lexer for the markup).
      {:makeup_elixir, "~> 1.0"},
      {:makeup_eex, "~> 2.0"},
      {:makeup_html, "~> 0.2"}
    ]
  end
end
