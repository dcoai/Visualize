defmodule Mix.Tasks.Vis.Headings do
  @shortdoc "Check spec/ heading numbering, titles, status lines and tables (spec/README §5)"

  @moduledoc """
  Fails when any document under `spec/` breaks the heading discipline: more or fewer than one
  `#` title, no `**Status:**` line on line 3, an unnumbered heading, a number that does not
  match its level, a gap or duplicate in the decimal numbering, table rows without a header
  and separator row, or a table row whose first cell is blank.

      mix vis.headings
  """

  use Mix.Task

  alias Visualize.Audit.Headings

  @impl Mix.Task
  def run(_argv) do
    case Headings.run(File.cwd!()) do
      [] ->
        Mix.shell().info("spec/ headings are numbered gap-free")

      problems ->
        Enum.each(problems, &Mix.shell().error(&1))
        Mix.raise("#{length(problems)} heading or table problem(s) in spec/")
    end
  end
end
