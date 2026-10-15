defmodule Mix.Tasks.Vis.Citations do
  @shortdoc "Check that every spec/NN §id citation names a heading (spec/12 §3)"

  @moduledoc """
  Fails when a citation of a specification section in `spec/`, `lib/`, `test/` or `specs/`
  names a heading its document does not have: `spec/NN §id`, `spec/NN-slug.md §id`, a
  specification document's `[NN-slug](NN-slug.md) §id`, and every id of a list or range
  that continues one. spec/13's `D-N` headings are ids; a heading in a code fence is not.

      mix vis.citations
  """

  use Mix.Task

  alias Visualize.Audit.Citations

  @impl Mix.Task
  def run(_argv) do
    case Citations.run(File.cwd!()) do
      [] ->
        Mix.shell().info("every spec citation names a heading")

      problems ->
        Enum.each(problems, &Mix.shell().error(&1))
        Mix.raise("#{length(problems)} unresolved spec citation(s)")
    end
  end
end
