defmodule Visualize.IR.ModuledocExamplesTest do
  @moduledoc """
  Every module under `lib/visualize/ir/` whose moduledoc carries an `iex>` example is
  named by a `doctest` in some test file (spec/12 §6, D-90).

  `Visualize.IR.Element`'s example never compiled — no test file named the module, so the
  syntax error in its expected value was never executed (#90). This holds the whole
  neighbourhood to running what it documents, so an un-run example cannot return.
  """
  use ExUnit.Case, async: true

  test "every IR moduledoc example is run as a doctest" do
    doctested = doctested_modules()

    for module <- ir_modules_with_examples() do
      assert module in doctested,
             "#{inspect(module)} has an `iex>` example in its moduledoc that no test file " <>
               "runs: add `doctest #{inspect(module)}` to a test file, without excepting " <>
               "`:moduledoc`, so the example is compiled and checked."
    end
  end

  # The modules the IR namespace ships, with an example in the moduledoc itself.
  defp ir_modules_with_examples do
    {:ok, modules} = :application.get_key(:visualize, :modules)

    for module <- modules,
        module |> Atom.to_string() |> String.starts_with?("Elixir.Visualize.IR."),
        doc = moduledoc(module),
        is_binary(doc),
        String.contains?(doc, "iex>"),
        do: module
  end

  defp moduledoc(module) do
    case Code.fetch_docs(module) do
      {:docs_v1, _anno, _lang, _format, %{"en" => doc}, _meta, _docs} -> doc
      _other -> nil
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
