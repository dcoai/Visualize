defmodule Visualize.VirtualSource.SandboxTest do
  # The checker, compiling once and the bounded runner (spec/08 §10.5, D-194).
  use ExUnit.Case, async: true

  alias Visualize.VirtualSource.Sandbox
  alias Visualize.VirtualSource.Sandbox.{Allowlist, Cache, Compiled}

  @moduletag :capture_log

  doctest Visualize.VirtualSource.Sandbox

  # The names these functions use, made atoms when this module loads: a stored function's
  # names must already exist (`existing_atoms_only`), as a design's schema makes them.
  @names ~w(xs row cpu mean hosts acc i y z mem a b n v host load t trend change)a
  setup_all do
    {:ok, names: @names}
  end

  defp ok?(source, opts \\ []), do: match?({:ok, _quoted}, Sandbox.check(source, opts))

  defp reasons(source, opts \\ []) do
    {:error, faults} = Sandbox.check(source, opts)
    Enum.map(faults, &elem(&1, 1))
  end

  defp call(source, args, opts \\ []) do
    {:ok, compiled} = Sandbox.compile(source)
    Sandbox.run(compiled, args, opts)
  end

  describe "check/2: what a function may say" do
    test "calculation and mapping over rows" do
      assert ok?("""
             fn %{hosts: rows} ->
               cpu = Enum.map(rows, & &1.cpu)
               [%{n: Enum.count(rows), mean: Enum.sum(cpu) / max(length_of(cpu), 1)}]
             end
             """) == false

      assert ok?("""
             fn %{hosts: rows} ->
               cpu = Enum.map(rows, & &1.cpu)
               [%{n: Enum.count(rows), mean: Enum.sum(cpu) / max(Enum.count(cpu), 1)}]
             end
             """)
    end

    test "control structures, patterns and guards" do
      assert ok?("""
             fn
               [a, b | _] when a.cpu > b.cpu and is_number(a.cpu) -> :ok
               [_ | _] = rows ->
                 case Enum.count(rows) do
                   n when rem(n, 2) == 0 -> cond do n > 4 -> :error; true -> :ok end
                   _ -> if Integer.is_even(3), do: :ok, else: :error
                 end
               [] -> unless false, do: nil
             end
             """)
    end

    test "with, for, ranges, binaries, access and pipes" do
      assert ok?("""
             fn row ->
               with {:ok, x} <- Map.fetch(row, :a), y = x * 2 do
                 for i <- 1..y//1, i > 1, into: [], do: {i, row[:b]}
               else
                 _ -> <<"no", 0::size(8)>> <> String.duplicate("-", 2)
               end
               |> Enum.take(3)
             end
             """)
    end

    test "captures of allowed functions and anonymous functions" do
      assert ok?("fn rows -> Enum.map(rows, &Integer.to_string/1) |> Enum.reduce(&max/2) end")
      assert ok?("fn rows -> f = fn x -> x + 1 end; Enum.map(rows, &f.(&1)) end")
      assert ok?("fn rows -> :math.pi() * :math.sqrt(Enum.count(rows)) + :math.pi end")
    end

    test "a for with reduce: takes accumulator clauses" do
      assert ok?("fn xs -> for x <- xs, reduce: 0 do acc -> acc + x end end")
    end
  end

  describe "check/2: the faults" do
    test "too long, unknown atoms and syntax" do
      assert [{:too_long, 10, 19}] = reasons("fn rows -> rows end", max_source: 10)

      assert [{:unknown_atom, "zz_never_seen_atom_42"}] =
               reasons("fn r -> :zz_never_seen_atom_42 end")

      assert [{:syntax, _message}] = reasons("fn rows -> ")
    end

    test "the source is one fn of the arity" do
      assert [{:not_a_function, 1}] = reasons("1 + 1")
      assert [{:not_a_function, 1}] = reasons("fn a, b -> a end")
      assert [{:not_a_function, 2}] = reasons("fn a -> a end", arity: 2)
      assert ok?("fn a, b -> {a, b} end", arity: 2)
    end

    test "every fault, by line" do
      assert {:error, faults} =
               Sandbox.check("""
               fn rows ->
                 x = File.read("a")
                 send(self(), x)
                 y
               end
               """)

      assert faults == [
               {2, {:restricted, {"File", :read, 1}}},
               {3, {:restricted, {:send, 2}}},
               {4, {:undefined_variable, :y}}
             ]
    end

    test "a map read on a variable is allowed; a call on one is dynamic" do
      assert ok?("fn row -> row.cpu end")
      assert [{:dynamic_call, :cpu}] = reasons("fn row -> row.cpu() end")
      assert [{:dynamic_call, :cpu}] = reasons("fn row -> row.cpu(1) end")
    end

    test "fields: a map read names a schema's field, by either spelling" do
      assert ok?("fn row -> row.cpu end", fields: [:cpu])
      assert ok?("fn row -> row.cpu end", fields: ["cpu"])
      assert [{:unknown_field, :mem}] = reasons("fn row -> row.mem end", fields: [:cpu])
    end

    test "into: and Enum.into take a literal empty target" do
      for target <- ["%{}", "[]", ~s("")] do
        assert ok?("fn xs -> for x <- xs, into: #{target}, do: x end")
        assert ok?("fn xs -> Enum.into(xs, #{target}) end")
      end

      assert [{:into, :literal}] = reasons("fn xs -> for x <- xs, into: xs, do: x end")
      assert [{:into, :literal}] = reasons("fn xs -> Enum.into(xs, [1]) end")
      assert [{:into, :literal}] = reasons("fn xs -> xs |> Enum.into(%{a: 1}) end")
      assert ok?("fn xs -> Enum.into(xs, [], & &1) end")
      assert [{:into, :literal}] = reasons("fn xs -> Enum.map(xs, &Enum.into/2) end")
      assert [{:uniq, :literal}] = reasons("fn xs -> for x <- xs, uniq: xs, do: x end")
    end

    test "guards hold the guard-safe part" do
      assert [{:guard, {Enum, :count, 1}}] = reasons("fn xs when Enum.count(xs) > 1 -> xs end")
      assert [{:guard, {:<>, 2}}] = reasons(~S|fn x when x <> "a" == "ba" -> x end|)
    end

    test "patterns hold patterns" do
      assert {:pattern, :+} in reasons("fn x + 1 -> x end")
      assert [{:undefined_variable, :y}] = reasons("fn ^y -> 1 end")
      assert [{:pattern, :^}] = reasons("fn x -> ^x end")
    end

    test "the clauses of an inner fn take one arity" do
      assert [{:fn_arity, [1, 2]}] = reasons("fn x -> fn a -> a; a, b -> b end end")
    end

    test "variables are scoped" do
      assert [{:undefined_variable, :a}] = reasons("fn x -> case x do a -> a end; a end")
      assert [{:undefined_variable, :i}] = reasons("fn x -> for i <- x, do: i; i end")
      assert ok?("fn x -> y = x; z = y + 1; z end")
    end
  end

  describe "compile/2" do
    test "a closure, its hash and its warnings" do
      assert {:ok, %Compiled{fun: fun, arity: 1, hash: hash, warnings: warnings}} =
               Sandbox.compile("fn x -> 1 end")

      assert is_function(fun, 1)
      assert hash == Sandbox.hash("fn x -> 1 end")
      assert [{1, message}] = warnings
      assert message =~ "unused"
    end

    test "the checker's faults are the compile's" do
      assert {:error, [{1, {:restricted, {:send, 2}}}]} =
               Sandbox.compile("fn x -> send(x, 1) end")
    end

    test "a map read never calls a function, whatever its receiver holds" do
      assert {:error, :raised, BadMapError} = call("fn m -> m.halt end", [:erlang])
      assert {:ok, 3} = call("fn m -> m.halt end", [%{halt: 3}])
      assert {:ok, :ok} = call("fn m when m.cpu > 1 -> :ok; _ -> nil end", [%{cpu: 2}])
    end

    test "Integer's guards compile" do
      assert {:ok, :ok} = call("fn x when Integer.is_even(x) -> :ok; _ -> nil end", [2])
    end
  end

  describe "string interpolation and Visualize.Data (#769)" do
    test "interpolation checks: it is a binary over Kernel.to_string/1" do
      assert ok?(~S|fn row -> "#{row.host}: #{row.load}" end|)
      assert ok?(~S|fn row -> "load " <> "#{row.load * 2}%" end|)
      assert ok?("fn row -> to_string(row.load) end")
      assert ok?("fn row -> Kernel.to_string(row.load) end")
      assert ok?("fn rows -> Enum.map(rows, &to_string/1) end")
    end

    test "interpolation is not guard-safe, and its holes are walked" do
      assert [{:guard, {:to_string, 1}}] =
               reasons(~S|fn x when to_string(x) == "1" -> x end|)

      assert [{:restricted, {"File", :read, 1}}] = reasons(~S|fn x -> "#{File.read(x)}" end|)
      assert [{:undefined_variable, :y}] = reasons(~S|fn x -> "#{y}" end|)
    end

    test "every allowed Visualize.Data function checks, called and captured" do
      for {name, arity} <- Allowlist.allowed(Visualize.Data) do
        args = Enum.map_join(1..arity//1, ", ", fn _ -> "rows" end)
        assert ok?("fn rows -> Visualize.Data.#{name}(#{args}) end"), "#{name}/#{arity}"
        assert ok?("fn rows -> &Visualize.Data.#{name}/#{arity} end"), "#{name}/#{arity}"
      end
    end

    test "a function Visualize.Data does not export is refused" do
      assert [{:restricted, {Visualize.Data, :mode, 1}}] =
               reasons("fn rows -> Visualize.Data.mode(rows) end")
    end

    test "a stored function with interpolation and slope runs through the bounded runner" do
      source = ~S"""
      fn rows ->
        trend = Visualize.Data.slope(rows, &{&1.t, &1.load})
        change = Visualize.Data.delta(rows, & &1.load)
        mean = Visualize.Data.mean(rows, & &1.load)
        "#{Enum.count(rows)} samples, mean #{mean}, change #{change}, trend #{trend}/s"
      end
      """

      rows = [%{t: 0, load: 1}, %{t: 10, load: 3}, %{t: 20, load: 5}]

      assert {:ok, "3 samples, mean 3.0, change 4, trend 0.2/s"} = call(source, [rows])
      assert {:ok, "0 samples, mean , change , trend /s"} = call(source, [[]])
    end
  end

  describe "run/3" do
    test "a value" do
      assert {:ok, [2, 4]} =
               call("fn rows -> Enum.map(rows, & &1.v * 2) end", [[%{v: 1}, %{v: 2}]])
    end

    test "a raise is the exception's module, read from the exit" do
      assert {:error, :raised, ArithmeticError} = call("fn x -> 1 / x end", [0])
      assert {:error, :raised, FunctionClauseError} = call("fn 1 -> 1 end", [2])
      assert {:error, :raised, KeyError} = call("fn x -> Map.fetch!(x, :a) end", [%{}])
    end

    test "the heap limit" do
      assert {:error, :memory, 100_000} =
               call("fn _ -> Enum.to_list(1..100_000_000_000) end", [nil], max_heap: 100_000)
    end

    test "the timeout kills the process" do
      assert {:error, :timeout, 20} =
               call(
                 "fn _ -> Enum.reduce(1..100_000_000_000_000, 0, fn x, acc -> rem(acc + x, 7) end) end",
                 [nil],
                 timeout: 20
               )
    end

    test "a host's function runs bounded too" do
      assert {:ok, 3} = Sandbox.run(&(&1 + &2), [1, 2])
      assert {:error, :raised, :exit} = Sandbox.run(fn -> exit(:boom) end, [])
    end
  end

  describe "the cache" do
    test "a source compiles once, a refusal included" do
      cache = Cache.new()
      {:ok, a, cache} = Cache.compile(cache, "fn x -> x end")
      {:ok, b, cache} = Cache.compile(cache, "fn x -> x end")
      assert a.fun == b.fun
      assert map_size(cache.entries) == 1

      {:error, faults, cache} = Cache.compile(cache, "fn x -> send(x, 1) end")
      {:error, ^faults, cache} = Cache.compile(cache, "fn x -> send(x, 1) end")
      assert map_size(cache.entries) == 2
    end

    test "keyed by the arity and the fields too" do
      {:ok, _c, cache} = Cache.compile(Cache.new(), "fn x -> x.cpu end", fields: [:cpu])

      {:error, [{1, {:unknown_field, :cpu}}], cache} =
        Cache.compile(cache, "fn x -> x.cpu end", fields: [:mem])

      assert map_size(cache.entries) == 2
    end
  end

  test "format_error/1 words every reason" do
    for fault <- [
          {nil, {:too_long, 10, 20}},
          {1, {:unknown_atom, "zz"}},
          {1, {:syntax, "x"}},
          {nil, {:not_a_function, 1}},
          {1, {:restricted, {Enum, :random, 1}}},
          {1, {:restricted, {:send, 2}}},
          {1, {:restricted, :struct}},
          {1, {:restricted_atom, :__struct__}},
          {1, {:dynamic_call, :x}},
          {1, {:unknown_field, :x}},
          {1, {:into, :literal}},
          {1, {:uniq, :literal}},
          {1, {:undefined_variable, :x}},
          {1, {:guard, {Enum, :count, 1}}},
          {1, {:guard, {:<>, 2}}},
          {1, {:pattern, :+}},
          {1, {:fn_arity, [1, 2]}},
          {nil, {:compile, "no"}},
          {nil, {:compile, {:timeout, 1}}}
        ] do
      assert is_binary(Sandbox.format_error(fault))
    end
  end
end
