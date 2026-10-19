defmodule Mix.Tasks.Vis.Atoms do
  @shortdoc "Check that lib/ makes no atom from a string outside the allowlist (spec/12 §3)"

  @moduledoc """
  Fails when `lib/` calls `String.to_atom`, `:erlang.binary_to_atom`, `List.to_atom` or
  `:erlang.list_to_atom`, or interpolates an atom literal, outside the allowlist of
  `audit/atoms_allowlist.exs`, or when an allowlist entry no longer matches what it says
  (`Visualize.Audit.Atoms`, D-195).

      mix vis.atoms
  """

  use Mix.Task

  alias Visualize.Audit.Atoms

  @impl Mix.Task
  def run(_argv) do
    case Atoms.run(File.cwd!()) do
      [] ->
        Mix.shell().info("no atom is made from a string outside the allowlist")

      problems ->
        Enum.each(problems, &Mix.shell().error(&1))
        Mix.raise("#{length(problems)} atom site(s) the allowlist does not hold")
    end
  end
end
