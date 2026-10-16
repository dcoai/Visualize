defmodule Examples.NoGalleryLoopTest do
  @moduledoc """
  No test walks the whole gallery in its body; a test per chart is generated instead
  (spec/12 §6, #735).

  A test that renders every gallery chart in one body carries the whole gallery's work on
  one test's 60 s timeout, and the suite's other cases share the runner with it: alone it
  takes seconds, beside the rest of a loaded runner it crossed the timeout (charts_test's
  "no chart animates on one backend…", builder_live_test before #704, the cost test before
  #731). Generated per chart — `for {slug, module} <- ChartLive.charts() do test … end` at
  the module's top — each chart is its own test, with its own timeout, spread over the
  async cases, and a failure names the chart.

  This reads every test file of the examples, parsed, and fails on a loop inside a test's
  body — a comprehension's generator, or the subject of an `Enum` or `Stream` function —
  over the gallery: a call to one of `@listers`, to a function of the same file that calls
  one, or a variable bound to either in the test. A test that walks the gallery without
  rendering a chart per step, or whose subject is the walk itself, is on `@allowed` with
  its reason.
  """
  use ExUnit.Case, async: true

  # The functions that return the gallery's charts, and the files' own helpers that do.
  @listers [
    {Examples.Gallery, :charts},
    {Examples.Gallery, :by_slug},
    {ExamplesWeb.ChartLive, :charts},
    {Examples.Charts.Templates, :gallery_modules}
  ]

  # A test's own helpers the scan cannot see return the gallery: `{path, function}`.
  @local_listers [
    # The recorded designs and the seeded ones: the gallery's designs, asserted equal to
    # them by the test of the families.
    {"test/examples/charts_test.exs", :charts},
    # The index's own list, as its socket carries it.
    {"test/examples_web/gallery_live_test.exs", :charts}
  ]

  # The tests that walk the gallery in one body, each with its reason: `{path, test name,
  # reason}`. An entry that matches no site fails, so the list cannot outlive its sites.
  @allowed [
    {"test/examples_web/gallery_live_test.exs",
     "every design of the gallery is a card in the grid, the streaming ones included (#403)",
     "reads each chart's link and title in the index rendered once; renders no chart"},
    {"test/examples_web/gallery_live_test.exs",
     "a dead render has a placeholder per chart and no chart document",
     "asks the preview cache about each chart; renders nothing"},
    {"test/examples_web/gallery_live_test.exs",
     "a connected mount starts a task per preview; each arrives by message and fills its card; the cache then hits",
     "the index's fan-out is the subject: one mount renders every preview, each in a task " <>
       "of its own, and the test takes their messages"},
    {"test/examples/load_age_gauge_test.exs",
     "Load + age is gone from the gallery and from the charts golden",
     "looks a slug up in the list; renders nothing"},
    {"test/examples_web/builder_live_test.exs",
     "every gallery design and every preset without one is a Charts:: entry",
     "reads each chart's title against the builder's template names; renders nothing"},
    {"test/examples_web/chart_live_design_test.exs",
     "every chart of the gallery is a design, so every Canvas tab is the split (#335)",
     "asks each module whether it is a design; renders one page, not one a chart"},
    {"test/examples_web/chart_live_nav_test.exs",
     "one list: the index and the chart pages show the same charts in the same order",
     "the list is the subject: it compares the gallery's list with the index's and the " <>
       "chart pages' maps, element by element; renders the index once"},
    {"test/examples_web/routes_test.exs",
     "the gallery says every chart is a design, and every chart it lists is one (#130)",
     "asks each module whether it is a design and reads the index's links; renders the " <>
       "index once"}
  ]

  defp files do
    files = Path.wildcard("test/**/*.exs") -- [Path.relative_to_cwd(__ENV__.file)]
    assert length(files) > 30, "the scan found #{length(files)} test files: is the cwd examples/?"
    files
  end

  test "no test walks the whole gallery in its body, outside the allow-list" do
    sites = Enum.flat_map(files(), &loops(&1, File.read!(&1)))

    {allowed, violations} =
      Enum.split_with(sites, fn {path, name, _line} ->
        Enum.any?(@allowed, &match?({^path, ^name, _}, &1))
      end)

    assert violations == [],
           "a test walks the whole gallery in its body (spec/12 §6, #735): generate one " <>
             "test per chart at the module's top, or put the test on @allowed with its " <>
             "reason:\n" <>
             Enum.map_join(violations, "\n", fn {path, name, line} ->
               "#{path}:#{line}: #{inspect(name)}"
             end)

    stale =
      Enum.reject(@allowed, fn {path, name, _} ->
        Enum.any?(allowed, &match?({^path, ^name, _}, &1))
      end)

    assert stale == [], "@allowed names a test that walks the gallery no more: #{inspect(stale)}"
  end

  test "the listers are the gallery's" do
    for {module, fun} <- @listers do
      assert Code.ensure_loaded?(module) and function_exported?(module, fun, 0),
             "#{inspect(module)}.#{fun}/0 is gone"
    end
  end

  describe "the scan" do
    test "finds a comprehension, an Enum call, a pipe, a variable and a helper over the gallery" do
      source = """
      defmodule ProbeTest do
        use ExUnit.Case
        alias ExamplesWeb.ChartLive

        defp pages, do: for({slug, _} <- ChartLive.charts(), do: "/chart/" <> slug)

        test "a" do
          for {slug, module} <- ChartLive.charts(), do: render(slug, module)
        end

        test "b" do
          Enum.each(Examples.Gallery.charts(), &render/1)
        end

        test "c" do
          Examples.Charts.Templates.gallery_modules() |> Enum.map(& &1.design([]))
        end

        test "d" do
          charts = Examples.Gallery.charts()
          Enum.reduce(charts, 0, fn _, n -> n + 1 end)
        end

        test "e" do
          for path <- pages(), do: get(path)
        end
      end
      """

      assert [
               {"probe_test.exs", "a", 8},
               {"probe_test.exs", "b", 12},
               {"probe_test.exs", "c", 16},
               {"probe_test.exs", "d", 21},
               {"probe_test.exs", "e", 25}
             ] = loops("probe_test.exs", source)
    end

    test "passes tests generated per chart, a lookup, and a loop outside any test" do
      source = """
      defmodule ProbeTest do
        use ExUnit.Case
        alias ExamplesWeb.ChartLive

        for {slug, module} <- ChartLive.charts() do
          @slug slug
          test "renders \#{slug}" do
            render(@slug)
          end
        end

        test "a lookup" do
          module = ChartLive.charts()["bar"]
          assert length(Examples.Gallery.charts()) > 1
          for x <- [1, 2], do: render(module, x)
        end
      end
      """

      assert loops("probe_test.exs", source) == []
    end
  end

  # `{path, test name, line}` for every loop over the gallery inside a test's body.
  defp loops(path, source) do
    ast = Code.string_to_quoted!(source)
    aliases = aliases(ast)
    locals = local_listers(path, ast, aliases)

    {_, found} =
      Macro.prewalk(ast, [], fn
        {:test, _, [name | rest]} = node, acc when is_binary(name) ->
          body = rest |> List.last() |> Keyword.get(:do)
          {node, acc ++ test_loops(path, name, body, aliases, locals)}

        node, acc ->
          {node, acc}
      end)

    found
  end

  defp test_loops(path, name, body, aliases, locals) do
    {_, {_vars, lines}} =
      Macro.prewalk(body, {MapSet.new(), []}, fn node, {vars, lines} = acc ->
        gallery? = &gallery?(&1, aliases, locals, vars)

        case node do
          {:=, _, [{var, _, context}, value]} when is_atom(var) and is_atom(context) ->
            if gallery?.(value), do: {node, {MapSet.put(vars, var), lines}}, else: {node, acc}

          {:for, meta, args} when is_list(args) ->
            sources = for {:<-, _, [_, source]} <- args, do: source

            if Enum.any?(sources, gallery?),
              do: {node, {vars, [meta[:line] | lines]}},
              else: {node, acc}

          {:|>, meta, [subject, {{:., _, [{:__aliases__, _, [mod]}, _]}, _, args}]}
          when mod in [:Enum, :Stream] ->
            if gallery?.(subject) and Enum.any?(args, &function?/1),
              do: {node, {vars, [meta[:line] | lines]}},
              else: {node, acc}

          {{:., meta, [{:__aliases__, _, [mod]}, _]}, _, [subject | args]}
          when mod in [:Enum, :Stream] ->
            if gallery?.(subject) and Enum.any?(args, &function?/1),
              do: {node, {vars, [meta[:line] | lines]}},
              else: {node, acc}

          _ ->
            {node, acc}
        end
      end)

    lines |> Enum.uniq() |> Enum.sort() |> Enum.take(1) |> Enum.map(&{path, name, &1})
  end

  # An `Enum` call does work per chart only through a function it is given: sorting or
  # counting the list, or comparing it with another, renders nothing.
  defp function?({:fn, _, _}), do: true
  defp function?({:&, _, _}), do: true
  defp function?(_arg), do: false

  # The expression is the gallery: a lister's call, a helper's that returns it, or a
  # variable bound to one, possibly piped through a function that keeps it a list.
  defp gallery?(expr, aliases, locals, vars) do
    case expr do
      {{:., _, [{:__aliases__, _, parts}, fun]}, _, []} ->
        {resolve(parts, aliases), fun} in @listers

      {:@, _, [{name, _, context}]} when is_atom(name) and is_atom(context) ->
        name in locals

      {fun, _, args} when is_atom(fun) and (args == [] or is_nil(args)) ->
        fun in locals or (is_nil(args) and MapSet.member?(vars, fun))

      {:|>, _, [subject, _]} ->
        gallery?(subject, aliases, locals, vars)

      {:--, _, [left, _]} ->
        gallery?(left, aliases, locals, vars)

      _ ->
        false
    end
  end

  # The names `@local_listers` gives this file, and its own functions that call a lister or
  # one of those, however deep: taken until no function is added.
  defp local_listers(path, ast, aliases) do
    named = for {^path, fun} <- @local_listers, do: fun

    {_, functions} =
      Macro.prewalk(ast, [], fn
        {kind, _, [{fun, _, _}, [do: body]]} = node, acc when kind in [:def, :defp] ->
          {node, [{fun, body} | acc]}

        node, acc ->
          {node, acc}
      end)

    grow(named, functions, aliases)
  end

  defp grow(locals, functions, aliases) do
    more =
      for {fun, body} <- functions,
          fun not in locals,
          mentions_lister?(body, aliases, locals),
          uniq: true,
          do: fun

    if more == [], do: locals, else: grow(locals ++ more, functions, aliases)
  end

  defp mentions_lister?(body, aliases, locals) do
    {_, found?} =
      Macro.prewalk(body, false, fn
        {{:., _, [{:__aliases__, _, parts}, fun]}, _, []} = node, found? ->
          {node, found? or {resolve(parts, aliases), fun} in @listers}

        {fun, _, args} = node, found? when is_atom(fun) and is_list(args) ->
          {node, found? or fun in locals}

        node, found? ->
          {node, found?}
      end)

    found?
  end

  defp aliases(ast) do
    {_, found} =
      Macro.prewalk(ast, %{}, fn
        {:alias, _, [{:__aliases__, _, parts}]} = node, acc ->
          {node, Map.put(acc, List.last(parts), Module.concat(parts))}

        {:alias, _, [{{:., _, [{:__aliases__, _, base}, :{}]}, _, names}]} = node, acc ->
          {node,
           Enum.reduce(names, acc, fn {:__aliases__, _, parts}, acc ->
             Map.put(acc, List.last(parts), Module.concat(base ++ parts))
           end)}

        node, acc ->
          {node, acc}
      end)

    found
  end

  defp resolve([first | rest], aliases) when is_atom(first) do
    case Map.fetch(aliases, first) do
      {:ok, module} -> Module.concat([module | rest])
      :error -> Module.concat([first | rest])
    end
  end

  defp resolve(_parts, _aliases), do: nil
end
