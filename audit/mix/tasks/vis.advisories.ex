defmodule Mix.Tasks.Vis.Advisories do
  @shortdoc "Check that neither lock carries a dependency advisory or retirement (spec/12 §3)"

  @moduledoc """
  Fails when `mix hex.audit` reports a security advisory or a retired package in the
  library's `mix.lock` or in `examples/mix.lock` that `audit/advisories_allowlist.exs` does
  not allow, or when an allowlist entry is malformed or stale (`Visualize.Audit.Advisories`,
  D-207). Both projects need their dependencies fetched.

      mix vis.advisories
  """

  use Mix.Task

  alias Visualize.Audit.Advisories

  @impl Mix.Task
  def run(_argv) do
    case Advisories.run(File.cwd!()) do
      [] ->
        Mix.shell().info(
          "neither lock carries an advisory or a retirement the allowlist does not hold"
        )

      problems ->
        Enum.each(problems, &Mix.shell().error(&1))
        Mix.raise("#{length(problems)} dependency audit problem(s)")
    end
  end
end
