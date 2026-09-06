defmodule Visualize.Audit.SpecScan do
  @moduledoc """
  Every function the specification declares: each `` `Module.function/arity` `` in the first
  cell of a table row under `spec/*.md`, with the numbered section it sits in.

  The row grammar is the one `spec/README.md` §5 asks writers to keep:
  `| \`Visualize.Scale.linear/0\` | contract |`. Anything else in a table is not a declaration.
  """

  @type entry :: %{item: String.t(), file: String.t(), section: String.t()}

  @row ~r/^\|\s*`(Visualize(?:\.[A-Z]\w*)*\.[a-z_][A-Za-z0-9_?!]*\/\d+)`\s*\|/
  @heading ~r/^(\#{2,4})\s+(\d+(?:\.\d+)*)\.?\s+(.*)$/

  @doc "Every declaration under `root/spec`, in file then line order."
  @spec run(String.t()) :: [entry]
  def run(root) do
    root
    |> Path.join("spec/*.md")
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.flat_map(fn path -> scan_source(File.read!(path), Path.relative_to(path, root)) end)
  end

  @doc "Scans one markdown document; `file` is the path the entries record."
  @spec scan_source(String.t(), String.t()) :: [entry]
  def scan_source(markdown, file) do
    label = doc_label(file)

    markdown
    |> String.split("\n")
    |> Enum.reduce({"§0", []}, fn line, {section, acc} ->
      case Regex.run(@heading, line) do
        [_, _hashes, number, _title] ->
          {"§" <> number, acc}

        nil ->
          case Regex.run(@row, line) do
            [_, item] ->
              {section, [%{item: item, file: file, section: label <> " " <> section} | acc]}

            nil ->
              {section, acc}
          end
      end
    end)
    |> elem(1)
    |> Enum.reverse()
  end

  # `spec/03-scales.md` → `spec/03`; `spec/README.md` → `spec/README`.
  defp doc_label(file) do
    base = file |> Path.basename(".md")

    case Regex.run(~r/^(\d\d)-/, base) do
      [_, n] -> "spec/" <> n
      nil -> "spec/" <> base
    end
  end
end
