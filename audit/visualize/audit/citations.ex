defmodule Visualize.Audit.Citations do
  @moduledoc """
  Every citation of a specification section names a heading that exists (spec/12 §3, #648).

  A citation is `spec/NN §id`, its long form `spec/NN-slug.md §id`, or a specification
  document's link form `[NN-slug](NN-slug.md) §id`. A list or a range continues it —
  `spec/08 §1.9, §7.3`, `spec/09 §4.3.8–4.3.9` — and every id in it is of that one document.
  An id is a heading's decimal number, and in spec/13 its `D-N` as well. A heading inside a
  code fence is an example and resolves nothing.

  A renumbered chapter leaves its citations pointing at headings that moved, and nothing
  else notices: `spec/06 §9.4` named the force simulation's timer discipline for as long as
  §8.5 held it.
  """

  @dirs ~w(spec lib test specs)
  @id ~S"(?:\d+(?:\.\d+)*|D-\d+)"
  @citation Regex.compile!(
              ~S"(?:spec/(\d{2})(?:-[a-z0-9-]+(?:\.md)?)?|\]\((\d{2})-[a-z0-9-]+\.md(?:#[^)]*)?\))" <>
                ~S"[ \t]+§[ ]?(" <>
                @id <>
                ~S")((?:(?:,[ ]*§|[ ]+and[ ]+§|[ ]+or[ ]+§|[ ]*[–-][ ]*§?)" <> @id <> ")*)",
              "u"
            )
  @each Regex.compile!(@id)
  @heading ~r/^\#{2,4}\s+(\d+(?:\.\d+)*)\.?\s+(?:(D-\d+)\s)?/

  @doc "Problems across `root`'s spec, lib, test and specs trees; `[]` when every citation resolves."
  @spec run(String.t()) :: [String.t()]
  def run(root) do
    headings =
      root
      |> Path.join("spec/[0-9][0-9]-*.md")
      |> Path.wildcard()
      |> Map.new(fn path ->
        {path |> Path.basename() |> binary_part(0, 2), ids(File.read!(path))}
      end)

    @dirs
    |> Enum.flat_map(&Path.wildcard(Path.join([root, &1, "**", "*"])))
    |> Enum.filter(&File.regular?/1)
    |> Enum.sort()
    |> Enum.flat_map(fn path ->
      check(File.read!(path), Path.relative_to(path, root), headings)
    end)
  end

  @doc """
  The section ids a specification document's headings give, outside code fences.

      iex> Visualize.Audit.Citations.ids("## 1. One\\n### 1.1 Sub\\n```\\n## 9. Example\\n```\\n")
      MapSet.new(["1", "1.1"])
  """
  @spec ids(String.t()) :: MapSet.t(String.t())
  def ids(markdown) do
    {_fenced?, ids} =
      markdown
      |> String.split("\n")
      |> Enum.reduce({false, MapSet.new()}, fn line, {fenced?, ids} ->
        cond do
          String.starts_with?(String.trim_leading(line), "```") -> {not fenced?, ids}
          fenced? -> {fenced?, ids}
          true -> {fenced?, heading_ids(line, ids)}
        end
      end)

    ids
  end

  defp heading_ids(line, ids) do
    case Regex.run(@heading, line) do
      [_, number, decision] -> ids |> MapSet.put(number) |> MapSet.put(decision)
      [_, number] -> MapSet.put(ids, number)
      nil -> ids
    end
  end

  @doc """
  The unresolved citations in one file's text, as `file:line: …` strings, against the ids of
  each document by its two-digit number. A file that is not text has none.
  """
  @spec check(String.t(), String.t(), %{String.t() => MapSet.t(String.t())}) :: [String.t()]
  def check(text, file, headings) do
    if String.valid?(text) do
      text
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {line, no} -> line_problems(line, "#{file}:#{no}", headings) end)
    else
      []
    end
  end

  defp line_problems(line, at, headings) do
    for [_, short, link, first, rest] <- Regex.scan(@citation, line, capture: :all),
        doc = if(short == "", do: link, else: short),
        id <- [first | List.flatten(Regex.scan(@each, rest))],
        not MapSet.member?(Map.get(headings, doc, MapSet.new()), id) do
      if Map.has_key?(headings, doc),
        do: "#{at}: spec/#{doc} §#{id} names no heading of spec/#{doc}",
        else: "#{at}: spec/#{doc} §#{id} names a document spec/ does not have"
    end
  end
end
