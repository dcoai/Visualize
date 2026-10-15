defmodule Mix.Tasks.Vis.Spelling do
  @shortdoc "Check that everything the library names and writes is spelled American (spec/12 §3)"

  @moduledoc """
  Fails when a British spelling appears in `lib/`, `test/`, `specs/`, `spec/`, `guides/`,
  `README.md`, the CHANGELOG's unreleased entries or the examples app, outside the
  allowlist of `Visualize.Audit.Spelling` (Elixir's behaviour, quoted third-party text,
  released CHANGELOG entries and lines marked `spelling: allow`).

      mix vis.spelling
  """

  use Mix.Task

  alias Visualize.Audit.Spelling

  @impl Mix.Task
  def run(_argv) do
    case Spelling.run(File.cwd!()) do
      [] ->
        Mix.shell().info("everything is spelled American")

      problems ->
        Enum.each(problems, &Mix.shell().error(&1))
        Mix.raise("#{length(problems)} British spelling(s)")
    end
  end
end
