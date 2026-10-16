defmodule Visualize.NoCrossTestCallsTest do
  @moduledoc """
  No test file calls a function of a module another test file defines (spec/12 §6, #733).

  A test file is an `.exs` that `mix test` requires, in an order it does not promise, and
  ExUnit starts an async module's tests as soon as its file is loaded, before the rest are.
  So a call from one test file into a module of another — `ClipTest` reading
  `ProjectionGoldenTest.types/0` — works only when the other file happens to load first:
  it failed under load, and it fails every time the calling file is run alone. What two
  test files share is test support (`test/support`, compiled with the suite before any
  test file loads). This reads every test file of the library and the examples, parsed,
  and fails on such a call; a module the same file defines, test support, and a library's
  module whose name ends in `Test` (`Phoenix.LiveViewTest`) are not test files' modules.
  """
  use ExUnit.Case, async: true

  defp files do
    files = Path.wildcard("test/**/*.exs") ++ Path.wildcard("examples/test/**/*.exs")
    assert length(files) > 100, "the scan found #{length(files)} test files: is the cwd the root?"
    files
  end

  test "no test file calls a module another test file defines" do
    sources = Map.new(files(), &{&1, File.read!(&1)})
    violations = violations(sources)

    assert violations == [],
           "a test file calls a module another test file defines, which is loaded in no " <>
             "promised order (spec/12 §6, #733). Move what they share into test support:\n" <>
             Enum.join(violations, "\n")
  end

  describe "the scan" do
    test "finds a call by full name, through an alias, and a require of the file" do
      sources = %{
        "golden_test.exs" => """
        defmodule Probe.GoldenTest do
          use ExUnit.Case
          def types, do: [:a]
          defmodule Doc do
            def read, do: :ok
          end
        end
        """,
        "clip_test.exs" => """
        defmodule Probe.ClipTest do
          use ExUnit.Case
          alias Probe.GoldenTest
          alias Probe.GoldenTest.Doc, as: Shelf

          Code.require_file("test/golden_test.exs")
          Code.require_file("test/support/shared.ex")

          test "reads" do
            Probe.GoldenTest.types()
            GoldenTest.types()
            Shelf.read()
          end
        end
        """
      }

      assert [
               "clip_test.exs:10: Probe.GoldenTest.types/0, defined in golden_test.exs",
               "clip_test.exs:11: Probe.GoldenTest.types/0, defined in golden_test.exs",
               "clip_test.exs:12: Probe.GoldenTest.Doc.read/0, defined in golden_test.exs",
               "clip_test.exs:6: Code.require_file(\"test/golden_test.exs\"), another test file"
             ] = violations(sources)
    end

    test "passes its own modules, nested ones by their short name, and modules no test defines" do
      sources = %{
        "own_test.exs" => """
        defmodule Probe.OwnTest.Doc do
          def read, do: :ok
        end

        defmodule Probe.OwnTest do
          use ExUnit.Case
          import Phoenix.LiveViewTest

          defmodule Looks do
            def all, do: []
          end

          test "reads" do
            Probe.OwnTest.Doc.read()
            Looks.all()
            __MODULE__.Looks.all()
            Visualize.PNGPixels.size(<<>>)
            Phoenix.LiveViewTest.render_component(&Probe.f/1, %{})
          end
        end
        """
      }

      assert violations(sources) == []
    end
  end

  # `"path:line: Module.fun/arity, defined in other_path"` for every call in `sources` (path
  # to source) into a module that another of the files defines.
  defp violations(sources) do
    parsed = Map.new(sources, fn {path, source} -> {path, Code.string_to_quoted!(source)} end)

    owners =
      for {path, ast} <- parsed, module <- defined(ast), into: %{}, do: {module, path}

    for {path, ast} <- Enum.sort(parsed),
        {line, module, fun, arity} <- calls(ast),
        owner = Map.get(owners, module),
        owner not in [nil, path] do
      "#{path}:#{line}: #{inspect(module)}.#{fun}/#{arity}, defined in #{owner}"
    end
    |> Kernel.++(
      for {path, ast} <- Enum.sort(parsed),
          {line, fun, file} <- requires(ast),
          do: "#{path}:#{line}: Code.#{fun}(#{inspect(file)}), another test file"
    )
  end

  # A test file that loads another itself is the same reach, worked around: it loads the
  # other file outside the order `mix test` loads it in.
  defp requires(ast) do
    {_, found} =
      Macro.prewalk(ast, [], fn
        {{:., meta, [{:__aliases__, _, [:Code]}, fun]}, _, [path | _]} = node, acc
        when fun in [:require_file, :compile_file, :eval_file] and is_binary(path) ->
          if String.ends_with?(path, "_test.exs"),
            do: {node, [{meta[:line], fun, path} | acc]},
            else: {node, acc}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(found)
  end

  # Every module `ast` defines, nested ones by their full name.
  defp defined(ast), do: ast |> walk([], %{}) |> elem(0)

  # Every remote call in `ast` as `{line, module, fun, arity}`, the module resolved through
  # the file's aliases and its enclosing modules.
  defp calls(ast), do: ast |> walk([], %{}) |> elem(1) |> Enum.sort()

  # Walks `ast` inside the modules `scope` (innermost first) with `aliases` in force,
  # returning `{modules defined, calls}`. An alias holds from its line to the end of the
  # module that declares it; the walk takes them in a module's order, which is enough here.
  defp walk({:defmodule, _, [{:__aliases__, _, parts}, [do: body]]}, scope, aliases) do
    module = nest(scope, parts)

    {modules, calls} =
      walk_block(body, [module | scope], Map.put(aliases, List.last(parts), module))

    {[module | modules], calls}
  end

  defp walk({{:., meta, [{:__aliases__, _, parts}, fun]}, _, args} = node, scope, aliases)
       when is_atom(fun) and is_list(args) do
    {modules, calls} = walk_children(node, scope, aliases)
    {modules, [{meta[:line], resolve(parts, scope, aliases), fun, length(args)} | calls]}
  end

  defp walk(node, scope, aliases), do: walk_children(node, scope, aliases)

  defp walk_children({form, _meta, args}, scope, aliases) when is_list(args),
    do: walk_list([form | args], scope, aliases)

  defp walk_children({left, right}, scope, aliases), do: walk_list([left, right], scope, aliases)
  defp walk_children(list, scope, aliases) when is_list(list), do: walk_list(list, scope, aliases)
  defp walk_children(_leaf, _scope, _aliases), do: {[], []}

  defp walk_block({:__block__, _, forms}, scope, aliases), do: walk_list(forms, scope, aliases)
  defp walk_block(form, scope, aliases), do: walk_list([form], scope, aliases)

  # A list of forms in order, each `alias` putting its names in force for the forms after.
  defp walk_list(forms, scope, aliases) do
    {modules, calls, _aliases} =
      Enum.reduce(forms, {[], [], aliases}, fn form, {modules, calls, aliases} ->
        {more_modules, more_calls} = walk(form, scope, aliases)
        {modules ++ more_modules, calls ++ more_calls, declare(form, scope, aliases)}
      end)

    {modules, calls}
  end

  defp declare({:alias, _, [{:__aliases__, _, parts}]}, scope, aliases),
    do: Map.put(aliases, List.last(parts), resolve(parts, scope, aliases))

  defp declare(
         {:alias, _, [{:__aliases__, _, parts}, [as: {:__aliases__, _, [as]}]]},
         scope,
         aliases
       ),
       do: Map.put(aliases, as, resolve(parts, scope, aliases))

  defp declare({:alias, _, [{{:., _, [{:__aliases__, _, base}, :{}]}, _, names}]}, scope, aliases) do
    Enum.reduce(names, aliases, fn {:__aliases__, _, parts}, acc ->
      Map.put(acc, List.last(parts), resolve(base ++ parts, scope, aliases))
    end)
  end

  # A module defined inside another is aliased by its first name in the forms after it.
  defp declare({:defmodule, _, [{:__aliases__, _, [first | _]}, _]}, [_ | _] = scope, aliases),
    do: Map.put(aliases, first, nest(scope, [first]))

  defp declare(_form, _scope, aliases), do: aliases

  # A call's module: `__MODULE__.X` and a short name the file aliased resolve to their
  # module; anything else is the name as written.
  defp resolve([{:__MODULE__, _, _} | rest], [module | _], _aliases),
    do: Module.concat([module | rest])

  defp resolve([first | rest], _scope, aliases) when is_atom(first) do
    case Map.fetch(aliases, first) do
      {:ok, module} -> Module.concat([module | rest])
      :error -> Module.concat([first | rest])
    end
  end

  defp resolve(_parts, _scope, _aliases), do: nil

  # A module defined inside `scope` is nested in the innermost module, as Elixir names it.
  defp nest([], parts), do: Module.concat(parts)
  defp nest([outer | _], parts), do: Module.concat([outer | parts])
end
