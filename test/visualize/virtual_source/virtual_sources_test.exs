defmodule Visualize.VirtualSourcesTest do
  # A host's functions: defsource and the registry (spec/08 §10.5.8, D-194).
  use ExUnit.Case, async: false

  alias Visualize.VirtualSource.Sandbox

  doctest Visualize.VirtualSources

  defmodule Sources do
    use Visualize.VirtualSources

    defsource(doubled(rows), do: Enum.map(rows, &(&1 * 2)))

    defsource last([row | _]) when is_map(row) do
      row.cpu
    end

    defsource(last([]), do: nil)

    defsource(runaway(_rows), do: Enum.to_list(1..100_000_000_000))

    defsource bins(inputs, context) do
      {map_size(inputs), context["vars"]["bin_domain"]}
    end
  end

  defmodule Other do
    use Visualize.VirtualSources
    defsource(doubled(rows), do: rows)
  end

  test "a defsource is a def, tested as any function" do
    assert Sources.doubled([1, 2]) == [2, 4]
    assert Sources.last([%{cpu: 3}]) == 3
    assert Sources.last([]) == nil
  end

  test "its source is captured when the module compiles, every clause once" do
    assert Sources.__virtual_sources__() == [
             {:doubled, 1, "fn rows -> Enum.map(rows, &(&1 * 2)) end"},
             {:last, 1, "fn\n  [row | _] when is_map(row) -> row.cpu\n  [] -> nil\nend"},
             {:runaway, 1, "fn _rows -> Enum.to_list(1..100_000_000_000) end"},
             {:bins, 2,
              "fn inputs, context -> {map_size(inputs), context[\"vars\"][\"bin_domain\"]} end"}
           ]
  end

  test "a head of two arguments takes the context, and its arity is recorded (D-228)" do
    assert Sources.bins(%{"a" => []}, %{"vars" => %{"bin_domain" => [0, 9]}}) == {1, [0, 9]}
    assert {:ok, {0, nil}} = Sandbox.run(&Sources.bins/2, [%{}, %{"vars" => %{}}])
  end

  test "trusted, but bounded: it runs through the same runner" do
    assert {:ok, [2]} = Sandbox.run(&Sources.doubled/1, [[1]])
    assert {:error, :memory, 100_000} = Sandbox.run(&Sources.runaway/1, [[]], max_heap: 100_000)
  end

  test "the registry: the modules given, then the configuration's" do
    assert Visualize.VirtualSources.registry([Sources]) ==
             %{doubled: Sources, last: Sources, runaway: Sources, bins: Sources}

    assert Visualize.VirtualSources.registry() == %{}

    Application.put_env(:visualize, :virtual_sources, [Sources])
    on_exit(fn -> Application.delete_env(:visualize, :virtual_sources) end)

    assert Visualize.VirtualSources.registry() |> Map.keys() |> Enum.sort() == [
             :bins,
             :doubled,
             :last,
             :runaway
           ]

    assert_raise ArgumentError, ~r/defined by both/, fn ->
      Visualize.VirtualSources.registry([Sources, Other])
    end

    assert_raise ArgumentError, ~r/not a virtual-source module/, fn ->
      Visualize.VirtualSources.registry([Enum])
    end
  end

  test "a head of another arity, or a body other than do, is a compile error" do
    assert_raise CompileError, ~r/one argument/, fn ->
      Code.eval_string("""
      defmodule Visualize.VirtualSourcesTest.Bad do
        use Visualize.VirtualSources
        defsource three(a, b, c), do: {a, b, c}
      end
      """)
    end

    assert_raise CompileError, ~r/clauses of 1 and 2 arguments/, fn ->
      Code.eval_string("""
      defmodule Visualize.VirtualSourcesTest.Bad3 do
        use Visualize.VirtualSources
        defsource both(a), do: a
        defsource both(a, b), do: {a, b}
      end
      """)
    end

    assert_raise CompileError, ~r/do block alone/, fn ->
      Code.eval_string("""
      defmodule Visualize.VirtualSourcesTest.Bad2 do
        use Visualize.VirtualSources
        defsource one(a), do: a, else: a
      end
      """)
    end
  end
end
