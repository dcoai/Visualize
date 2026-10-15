defmodule Visualize.DocumentedExamplesTest do
  @moduledoc """
  Every module the library ships whose moduledoc or function documentation carries an
  `iex>` example is named by a `doctest` in some test file (spec/12 §6, D-90, D-93).

  `Visualize.IR.Element`'s example never compiled — no test file named the module, so the
  syntax error in its expected value was never executed (#90). D-90 gated the IR
  neighborhood on it and said the same scan over the whole library would fail; it did, on
  ten modules, three of whose examples were wrong (#118). This holds the library to
  running what it documents, so an un-run example cannot return.
  """
  use ExUnit.Case, async: true

  # An example that genuinely cannot be a doctest — a random seed, a timestamp, a process
  # identifier — is named here WITH its reason, so a skip is a row a reviewer reads rather
  # than an absence nobody sees (D-93). An entry whose reason is "it fails" is a corrected
  # example wearing a disguise. Nothing in the library documents a non-deterministic
  # value, so the list is empty.
  @excluded []

  test "every documented example in lib/ is run as a doctest" do
    doctested = doctested_modules()
    excluded = Enum.map(@excluded, &elem(&1, 0))

    for module <- modules_with_examples(), module not in excluded do
      assert module in doctested,
             "#{inspect(module)} has an `iex>` example in its documentation that no test " <>
               "file runs: add `doctest #{inspect(module)}` to a test file, without " <>
               "excepting `:moduledoc`, so the example is compiled and checked."
    end
  end

  test "every excluded module still carries the example its exclusion is about" do
    with_examples = MapSet.new(modules_with_examples())

    for {module, reason} <- @excluded do
      assert is_binary(reason) and reason != "",
             "#{inspect(module)} is excluded without a reason: say why it cannot be a " <>
               "doctest, or run it."

      assert module in with_examples,
             "#{inspect(module)} is excluded from the documented-example guard but no " <>
               "longer documents an `iex>` example: drop the exclusion."
    end
  end

  # Every module the application ships, with an example in the moduledoc or in the
  # documentation of one of its functions. A hidden chunk (`@doc false`) is not
  # documentation and carries no claim to a reader.
  defp modules_with_examples do
    {:ok, modules} = :application.get_key(:visualize, :modules)

    for module <- modules,
        Enum.any?(doc_chunks(module), &String.contains?(&1, "iex>")),
        do: module
  end

  defp doc_chunks(module) do
    case Code.fetch_docs(module) do
      {:docs_v1, _anno, _lang, _format, moduledoc, _meta, docs} ->
        [moduledoc | Enum.map(docs, fn {_kfa, _anno, _sig, doc, _meta} -> doc end)]
        |> Enum.flat_map(fn
          %{"en" => text} when is_binary(text) -> [text]
          _other -> []
        end)

      _other ->
        []
    end
  end

  # Every module a `doctest` in the suite names, resolved through that file's aliases. A
  # `doctest` that excepts `:moduledoc` does not count: the example would not be run.
  defp doctested_modules do
    "test/**/*.exs"
    |> Path.wildcard()
    |> Enum.flat_map(&doctested_in/1)
    |> MapSet.new()
  end

  defp doctested_in(file) do
    source = File.read!(file)
    aliases = aliases_in(source)

    for [_line, name, rest] <- Regex.scan(~r/^\s*doctest\s+([A-Z][\w.]*)(.*)$/m, source),
        not excepts_moduledoc?(rest),
        do: resolve(name, aliases)
  end

  defp excepts_moduledoc?(rest) do
    String.contains?(rest, "except:") and String.contains?(rest, ":moduledoc")
  end

  # `alias A.B.C` and `alias A.B.{C, D}`, by the short name each one binds.
  defp aliases_in(source) do
    multi =
      for [_line, base, parts] <- Regex.scan(~r/alias\s+([A-Z][\w.]*)\.\{([^}]*)\}/, source),
          part <- String.split(parts, ","),
          part = String.trim(part),
          part != "",
          into: %{},
          do: {last_segment(part), base <> "." <> part}

    single =
      for [_line, name] <- Regex.scan(~r/^\s*alias\s+([A-Z][\w.]*)\s*$/m, source),
          into: %{},
          do: {last_segment(name), name}

    Map.merge(multi, single)
  end

  defp last_segment(name), do: name |> String.split(".") |> List.last()

  defp resolve(name, aliases) do
    Module.concat([Map.get(aliases, name, name)])
  end
end
