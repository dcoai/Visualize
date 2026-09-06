defmodule Visualize.Audit.Headings do
  @moduledoc """
  The heading discipline `spec/README.md` §5 asks for, checked mechanically: one `#` title,
  a `**Status:**` line on line 3, and decimal numbering that is gap-free at every level
  (`## 1.`, `### 1.1`, `#### 1.1.1`). A lost or duplicated heading breaks the citations
  every other document and the golden's `Section` column rely on, and nobody notices by eye.
  """

  @heading ~r/^(\#{1,4})\s+(.*)$/
  @number ~r/^(\d+(?:\.\d+)*)\.?\s+\S/

  @doc "Problems across every document under `root/spec`; `[]` when the discipline holds."
  @spec run(String.t()) :: [String.t()]
  def run(root) do
    root
    |> Path.join("spec/*.md")
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.flat_map(fn path -> check(File.read!(path), Path.relative_to(path, root)) end)
  end

  @doc "Problems in one document, as `file: message` strings."
  @spec check(String.t(), String.t()) :: [String.t()]
  def check(markdown, file) do
    lines = String.split(markdown, "\n")

    headings =
      lines
      |> Enum.with_index(1)
      |> Enum.reject(fn {line, _} -> String.starts_with?(line, "    ") end)
      |> Enum.flat_map(fn {line, no} ->
        case Regex.run(@heading, line) do
          [_, hashes, rest] -> [{String.length(hashes), rest, no}]
          nil -> []
        end
      end)

    titles = for {1, _, no} <- headings, do: no

    status =
      case Enum.at(lines, 2) do
        "**Status:** " <> _ -> []
        _ -> ["#{file}: line 3 must be a `**Status:**` line"]
      end

    title_problems =
      case titles do
        [_] -> []
        [] -> ["#{file}: no `#` title"]
        many -> ["#{file}: #{length(many)} `#` titles (lines #{Enum.join(many, ", ")})"]
      end

    {_, numbering} =
      headings
      |> Enum.filter(fn {level, _, _} -> level > 1 end)
      |> Enum.reduce({%{}, []}, fn {level, rest, no}, {counters, problems} ->
        case Regex.run(@number, rest) do
          nil ->
            {counters, ["#{file}:#{no}: unnumbered heading" | problems]}

          [_, number] ->
            parts = number |> String.split(".") |> Enum.map(&String.to_integer/1)
            parent = Enum.drop(parts, -1)
            expected = Map.get(counters, parent, 0) + 1

            cond do
              parent != [] and not Map.has_key?(counters, parent) ->
                {counters, ["#{file}:#{no}: `#{number}` has no parent heading" | problems]}

              length(parts) != level - 1 ->
                {counters,
                 ["#{file}:#{no}: `#{number}` does not match heading level #{level}" | problems]}

              List.last(parts) != expected ->
                {Map.put(counters, parent, List.last(parts)),
                 [
                   "#{file}:#{no}: expected #{Enum.join(parent ++ [expected], ".")}, found #{number}"
                   | problems
                 ]}

              true ->
                {counters |> Map.put(parent, expected) |> Map.put(parts, 0), problems}
            end
        end
      end)

    status ++ title_problems ++ Enum.reverse(numbering)
  end
end
