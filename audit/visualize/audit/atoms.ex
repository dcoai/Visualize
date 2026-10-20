defmodule Visualize.Audit.Atoms do
  @moduledoc """
  No atom from untrusted input (spec/12 §3, #778, D-195).

  Fails on a call that makes an atom from a string — `String.to_atom`,
  `:erlang.binary_to_atom`, `List.to_atom`, `:erlang.list_to_atom` — or an interpolated atom
  literal (`:"…\#{…}…"`) on any line of a `.ex` file under `lib/`, outside the allowlist
  `audit/atoms_allowlist.exs`. Each entry names a file, a fragment of the lines it allows,
  how many lines of the file hold that fragment, its class of D-195 and its reason; an entry
  whose count is not what the file holds fails too, so the list cannot go stale. A comment
  line makes no atom and is passed over. `String.to_existing_atom` is not matched: it makes
  none.

  The classes are (a) a closed library vocabulary, (a-host) a vocabulary host code
  registers and (d) a set the library bounds. A name a document or a client declares —
  class (b) — and one derived from such names — class (c) — is a string (D-195), so an
  entry of either fails.
  """

  @scanned "lib"
  @allowlist "audit/atoms_allowlist.exs"
  @classes [:a, :"a-host", :d]
  @pattern ~r/String\.to_atom|binary_to_atom|List\.to_atom|list_to_atom|:"[^"]*#\{|:'[^']*#\{/

  @doc "Every problem under `root`, one line each; `[]` when there is none."
  @spec run(Path.t()) :: [String.t()]
  def run(root) do
    {entries, _binding} = root |> Path.join(@allowlist) |> Code.eval_file()
    run(root, entries)
  end

  @doc false
  # The check against a given allowlist, for the task's own test.
  @spec run(Path.t(), [map()]) :: [String.t()]
  def run(root, entries) do
    sites = sites(root)
    malformed(entries) ++ unallowed(sites, entries) ++ stale(sites, entries)
  end

  @doc false
  @spec pattern() :: Regex.t()
  def pattern, do: @pattern

  # Every `{file, line_number, text}` that makes an atom from a string.
  defp sites(root) do
    root
    |> Path.join(@scanned <> "/**/*.ex")
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.flat_map(fn path ->
      file = Path.relative_to(path, root)

      path
      |> File.read!()
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.filter(fn {text, _n} -> site?(text) end)
      |> Enum.map(fn {text, n} -> {file, n, String.trim(text)} end)
    end)
  end

  defp site?(text) do
    not String.starts_with?(String.trim_leading(text), "#") and Regex.match?(@pattern, text)
  end

  defp malformed(entries) do
    for entry <- entries, problem = malformed_entry(entry), do: problem
  end

  defp malformed_entry(%{file: file, match: match, count: count, class: class, reason: reason})
       when is_binary(file) and is_binary(match) and is_integer(count) and count > 0 and
              class in @classes and is_binary(reason) and reason != "",
       do: nil

  defp malformed_entry(%{class: class} = entry) when class in [:b, :c],
    do:
      "#{@allowlist}: a name a document declares is a string (D-195), never an allowed " <>
        "atom; got #{inspect(entry)}"

  defp malformed_entry(entry),
    do:
      "#{@allowlist}: an entry needs file, match, count, a class of #{inspect(@classes)} " <>
        "and a reason; got #{inspect(entry)}"

  defp unallowed(sites, entries) do
    for {file, n, text} <- sites,
        not Enum.any?(entries, &(&1.file == file and String.contains?(text, &1.match))),
        do: "#{file}:#{n}: makes an atom from a string (D-195): #{text}"
  end

  defp stale(sites, entries) do
    for %{file: file, match: match, count: count} <- entries,
        held =
          Enum.count(sites, fn {f, _n, text} -> f == file and String.contains?(text, match) end),
        held != count,
        do:
          "#{@allowlist}: #{file} holds #{held} line(s) with #{inspect(match)}, the entry says #{count}"
  end
end
