defmodule Visualize.GuidesTest.Doc do
  @moduledoc false
  # The reading of a guide the tests are generated from; a module of its own because the
  # tests are generated at compile time, before the test module's own functions exist.

  @doc "The documents whose `elixir` blocks are run: every guide, and the README."
  def paths do
    root = Path.expand("../..", __DIR__)

    guides =
      Path.join(root, "guides/*.{md,cheatmd}")
      |> Path.wildcard()
      |> Enum.sort()

    guides ++ [Path.join(root, "README.md")]
  end

  # A block that cannot run outside a host — a LiveView, a `deps/0` fragment — is marked on
  # the line directly above its fence (spec/12 §6).
  def marker_regex, do: ~r/^<!-- compile only:(.*)-->$/

  @doc """
  The document's fenced blocks, in order, as `%{line, lang, source, marker}`: `line` is the
  first line of the source, `marker` `{:compile_only, reason}` or `nil`. A fence may be
  indented, inside a list item; its indentation is stripped from the source.
  """
  def parse(text) do
    text
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.reduce(%{fence: nil, prev: "", blocks: []}, &step/2)
    |> Map.fetch!(:blocks)
    |> Enum.reverse()
  end

  defp step({line, n}, %{fence: nil} = st) do
    case Regex.run(~r/^(\s*)```+\s*(\S*)/, line) do
      [_, indent, lang] ->
        fence = %{indent: indent, line: n + 1, lang: lang, src: [], marker: marker(st.prev)}
        %{st | fence: fence, prev: line}

      nil ->
        %{st | prev: line}
    end
  end

  defp step({line, _n}, %{fence: f} = st) do
    if Regex.match?(~r/^\s*```+\s*$/, line) do
      source = f.src |> Enum.reverse() |> Enum.join("\n")
      block = %{line: f.line, lang: f.lang, source: source, marker: f.marker}
      %{st | fence: nil, blocks: [block | st.blocks], prev: line}
    else
      %{st | fence: %{f | src: [String.replace_prefix(line, f.indent, "") | f.src]}, prev: line}
    end
  end

  @doc """
  A block cut at its `#=> value` lines, as `{source, first_line, expected}`: each stretch of
  code and the value the guide says its last expression returns (`nil` after the last
  `#=>`). A stretch with no code — two `#=>` lines in a row — is a guide error, and parsing
  it fails the test.
  """
  def chunks(source, first_line) do
    {done, current, start} =
      source
      |> String.split("\n")
      |> Enum.with_index(first_line)
      |> Enum.reduce({[], [], first_line}, fn {line, n}, {done, current, start} ->
        case Regex.run(~r/^#=>\s*(.+)$/, String.trim(line)) do
          [_, expected] ->
            {[{join(current), start, expected} | done], [], n + 1}

          nil ->
            {done, [line | current], start}
        end
      end)

    rest = if String.trim(join(current)) == "", do: [], else: [{join(current), start, nil}]
    Enum.reverse(done) ++ rest
  end

  defp join(reversed_lines), do: reversed_lines |> Enum.reverse() |> Enum.join("\n")

  def marker(line) do
    case Regex.run(marker_regex(), String.trim(line)) do
      [_, reason] -> {:compile_only, String.trim(reason)}
      nil -> nil
    end
  end
end

defmodule Visualize.GuidesTest do
  @moduledoc """
  Every `elixir` block of every guide and of the README, read from the documents and run
  (spec/12 §6, #518). A guide's code is the first code a newcomer runs, and an example
  that is not run rots (#118, #454): this makes a change that breaks one a red test.

  One test per document. Its blocks run in order and share one evaluation environment —
  the binding, and the imports and aliases a block made — so a later block uses what an
  earlier one defined, as a reader typing them into IEx would. Each block is evaluated with
  the document as its file and its own first line as its line, so an error, a stack trace
  and a warning all name `guides/<file>.md:<line>`. A block may not warn. A line
  `#=> value` after an expression is the guide's claim about what it returns, and is held
  to it with `==`.

  A block that cannot run outside a host carries `<!-- compile only: <reason> -->` on the
  line directly above its fence: a LiveView needs a socket, a `deps/0` fragment a
  `mix.exs`. It is parsed, and a block of module definitions is compiled — without
  warnings — and purged, so a guide's LiveView is held to the library's real functions.
  The glob picks up a new guide with no edit here.
  """
  # Compile-only blocks define and purge modules by name; nothing else may see them.
  use ExUnit.Case, async: false

  alias Visualize.GuidesTest.Doc

  @paths Doc.paths()
  for path <- @paths, do: @external_resource(path)

  @root Path.expand("../..", __DIR__)

  defp relative(path), do: Path.relative_to(path, @root)

  defp run_document(path) do
    blocks = path |> File.read!() |> Doc.parse() |> Enum.filter(&(&1.lang == "elixir"))
    env = Code.env_for_eval(file: path, line: 1)

    {_binding, _env} =
      Enum.reduce(blocks, {[], env}, fn block, {binding, env} ->
        where = "#{relative(path)}:#{block.line}"

        case block.marker do
          {:compile_only, _reason} ->
            compile_only(block.source, path, block.line, where)
            {binding, env}

          nil ->
            block.source
            |> Doc.chunks(block.line)
            |> Enum.reduce({binding, env}, &run_chunk(&1, &2, path))
        end
      end)

    length(blocks)
  end

  # One stretch of a block, evaluated in the document's environment, and its value held to
  # the `#=>` line that ends it, if one does.
  defp run_chunk({source, line, expected}, {binding, env}, path) do
    where = "#{relative(path)}:#{line}"
    quoted = Code.string_to_quoted!(source, file: path, line: line)

    {{value, binding, env}, diagnostics} =
      Code.with_diagnostics(fn -> Code.eval_quoted_with_env(quoted, binding, env) end)

    refute_warnings(diagnostics, where)

    if expected do
      {wanted, _} = Code.eval_string(expected, [], file: path, line: line)

      assert value == wanted,
             "#{where}: the guide says `#=> #{expected}`, the code returns #{inspect(value)}"
    end

    {binding, env}
  end

  # Parsed always; compiled, then purged, when every top-level form is a module definition.
  defp compile_only(source, path, line, where) do
    quoted = Code.string_to_quoted!(source, file: path, line: line)

    forms =
      case quoted do
        {:__block__, _, forms} -> forms
        form -> [form]
      end

    if Enum.all?(forms, &match?({:defmodule, _, _}, &1)) do
      {modules, diagnostics} = Code.with_diagnostics(fn -> Code.compile_quoted(quoted, path) end)
      refute_warnings(diagnostics, where)
      assert modules != [], "#{where}: a compile-only block compiled no module"

      for {module, _binary} <- modules do
        :code.purge(module)
        :code.delete(module)
      end
    end
  end

  defp refute_warnings(diagnostics, where) do
    warnings = for %{severity: :warning} = d <- diagnostics, do: d

    assert warnings == [],
           "#{where}: the block warns:\n" <>
             Enum.map_join(warnings, "\n", &"  #{inspect(&1.position)}: #{&1.message}")
  end

  test "the guides and the README are found" do
    names = Enum.map(@paths, &relative/1)
    assert "README.md" in names
    assert "guides/getting_started.md" in names
    assert "guides/liveview.md" in names
  end

  # Guides that are mostly code: an empty run there is a parse gone wrong, not a pass.
  @must_have_code ~w(README.md guides/getting_started.md guides/liveview.md)

  for path <- @paths do
    @path path
    test "every elixir block of #{Path.relative_to(path, Path.expand("../..", __DIR__))} runs" do
      count = run_document(@path)

      if relative(@path) in @must_have_code do
        assert count > 1, "#{relative(@path)}: #{count} elixir block(s) found"
      end
    end
  end

  test "a compile-only marker gives a reason and sits directly above an elixir fence" do
    for path <- @paths do
      blocks = path |> File.read!() |> Doc.parse()

      for %{line: line, lang: lang, marker: {:compile_only, reason}} <- blocks do
        where = "#{relative(path)}:#{line - 2}"
        assert lang == "elixir", "#{where}: a compile-only marker above a #{lang} fence"
        assert reason != "", "#{where}: a compile-only marker with no reason"
      end

      # A marker anywhere else marks nothing: it must sit directly above a fence.
      lines = path |> File.read!() |> String.split("\n")

      marked =
        for {l, i} <- Enum.with_index(lines, 1),
            Regex.match?(Doc.marker_regex(), String.trim(l)),
            do: i

      fenced = for %{line: line, marker: {:compile_only, _}} <- blocks, do: line - 2
      assert marked == fenced, "#{relative(path)}: a compile-only marker above no fence"
    end
  end
end
