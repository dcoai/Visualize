defmodule Mix.Tasks.Vis.Headings do
  @shortdoc "Check spec/ heading numbering, titles and status lines (spec/README §5)"

  @moduledoc """
  Fails when any document under `spec/` breaks the heading discipline: more or fewer than one
  `#` title, no `**Status:**` line on line 3, an unnumbered heading, a number that does not
  match its level, or a gap or duplicate in the decimal numbering.

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
        Mix.raise("#{length(problems)} heading problem(s) in spec/")
    end
  end
end
