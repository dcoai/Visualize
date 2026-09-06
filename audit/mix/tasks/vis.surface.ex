defmodule Mix.Tasks.Vis.Surface do
  @shortdoc "Cross-reference spec/ against lib/ and render API_SURFACE.md (spec/12 §2)"

  @moduledoc """
  Cross-references every function `spec/` declares against every public function `lib/`
  defines, and renders the result to `API_SURFACE.md`.

      mix vis.surface            # print the two backlogs
      mix vis.surface --write    # regenerate API_SURFACE.md
      mix vis.surface --check    # fail if the golden has drifted from spec/ and lib/

  `--check` is HARD: the golden is generated, so a difference means it was hand-edited, or
  the code or the spec changed without a regenerate. It does not fail on `unspecified` or
  `unimplemented` counts; reporting those is the document's purpose.
  """

  use Mix.Task

  alias Visualize.Audit

  @golden "API_SURFACE.md"
  @switches [write: :boolean, check: :boolean]

  @impl Mix.Task
  def run(argv) do
    {opts, _, _} = OptionParser.parse(argv, strict: @switches)

    root = File.cwd!()
    result = Audit.run(root)
    rendered = Audit.render(result)
    path = Path.join(root, @golden)

    cond do
      opts[:write] ->
        File.write!(path, rendered)
        Mix.shell().info("wrote #{path}")

      opts[:check] ->
        check!(path, rendered)

      true ->
        report(result)
    end
  end

  # Public so both failure branches are testable without re-scanning the tree.
  @doc false
  def check!(path, rendered) do
    case File.read(path) do
      {:ok, ^rendered} ->
        Mix.shell().info("#{@golden} is current")

      {:ok, _stale} ->
        Mix.raise(
          "#{@golden} has drifted from spec/ and lib/. Regenerate: mix vis.surface --write"
        )

      {:error, :enoent} ->
        Mix.raise("#{@golden} is missing. Generate it: mix vis.surface --write")
    end
  end

  defp report(result) do
    shell = Mix.shell()
    shell.info("#{length(result.rows)} public functions · specified #{result.specified}")
    section(shell, "unspecified (defined in lib/, declared nowhere)", result.unspecified)
    section(shell, "unimplemented (declared in spec/, not defined)", result.unimplemented)
  end

  defp section(shell, label, []), do: shell.info("#{label}: none")

  defp section(shell, label, items) do
    shell.info("#{label} (#{length(items)}):")
    Enum.each(items, &shell.info("  #{&1}"))
  end
end
