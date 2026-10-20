defmodule Visualize.VirtualSource.SandboxAttackTest do
  # The attack suite (spec/12 §7, D-194), modeled on the attacks Dune's test suite defends
  # against: each attack is a stored function, and each test names the fault the checker
  # answers, or the kind the runner reports — never only that something failed.
  #
  # Not async: the atom test counts the node's atoms, which another test making atoms at
  # the same moment would move.
  use ExUnit.Case, async: false

  alias Visualize.VirtualSource.Sandbox
  alias Visualize.VirtualSource.Sandbox.Allowlist

  @moduletag :capture_log

  # The names the attacks use, made atoms when this module loads (`existing_atoms_only`).
  @names ~w(m xs row f y pid)a
  setup_all do
    {:ok, names: @names}
  end

  defp refused(source, opts \\ []) do
    {:error, faults} = Sandbox.check(source, opts)
    Enum.map(faults, &elem(&1, 1))
  end

  defp call(source, args, opts \\ []) do
    {:ok, compiled} = Sandbox.compile(source)
    Sandbox.run(compiled, args, opts)
  end

  # A name the node never saw is read as its string — a variable one of the sandbox's own —
  # so the check passes and no atom is made (D-195); a module named by a string names none.
  @strings [
    "fn x -> :never_made_before_by_any_attack end",
    "fn x -> never_made_variable_q9 = x end",
    "fn x -> %{never_made_key_q9: x} end",
    "fn x -> x.never_made_field_q9 end",
    ~S|fn x -> Map.put(x, :k, :"Elixir.File.Stream") end|
  ]

  @atoms [
    {"fn x -> String.to_atom(x) end", {:restricted, {String, :to_atom, 1}}},
    {"fn x -> String.to_existing_atom(x) end", {:restricted, {String, :to_existing_atom, 1}}},
    # Interpolation is allowed (#769); an atom written with it is `:erlang.binary_to_existing_atom/2`.
    {~S|fn x -> :"a#{x}" end|, {:restricted, {:erlang, :binary_to_existing_atom, 2}}},
    {"fn x -> List.to_atom(x) end", {:restricted, {"List", "to_atom", 1}}}
  ]

  @calls [
    {"fn m -> m.halt() end", {:dynamic_call, "halt"}},
    {"fn m -> m.cmd(1) end", {:dynamic_call, "cmd"}},
    {"fn x -> apply(Enum, :count, [x]) end", {:restricted, {:apply, 3}}},
    {"fn f -> apply(f, []) end", {:restricted, {:apply, 2}}},
    {"fn x -> :erlang.halt() end", {:restricted, {:erlang, :halt, 0}}},
    {"fn x -> :os.cmd(x) end", {:restricted, {:os, :cmd, 1}}},
    {"fn x -> :ets.new(x, []) end", {:restricted, {:ets, :new, 2}}},
    {"fn x -> :code.purge(x) end", {:restricted, {:code, :purge, 1}}},
    {"fn x -> Code.eval_string(x) end", {:restricted, {"Code", "eval_string", 1}}},
    {"fn x -> System.cmd(x, []) end", {:restricted, {"System", "cmd", 2}}},
    {"fn x -> File.read(x) end", {:restricted, {"File", "read", 1}}},
    {"fn x -> Process.exit(x, :kill) end", {:restricted, {"Process", "exit", 2}}},
    {"fn x -> Node.list() end",
     {:any, [{:restricted, {"Node", "list", 0}}, {:unknown_atom, "Node"}]}},
    {"fn x -> Port.open(x, []) end", {:restricted, {"Port", "open", 2}}},
    {"fn x -> IO.puts(x) end", {:restricted, {"IO", "puts", 1}}},
    {"fn x -> &String.to_atom/1 end", {:restricted, {String, :to_atom, 1}}},
    {"fn x -> &:os.cmd/1 end", {:restricted, {:os, :cmd, 1}}},
    {"fn x -> &apply/2 end", {:restricted, {:apply, 2}}},
    {"fn x -> Kernel.apply(x, []) end", {:restricted, {Kernel, :apply, 2}}},
    {"fn x -> then(x, & &1) end", {:restricted, {:then, 2}}},
    {"fn x -> x |> then(& &1) end", {:restricted, {:then, 2}}},
    {"fn x -> inspect(x) end", {:restricted, {:inspect, 1}}}
  ]

  @processes [
    {"fn x -> send(x, 1) end", {:restricted, {:send, 2}}},
    {"fn x -> receive do y -> y end end", {:restricted, {:receive, 1}}},
    {"fn x -> spawn(x) end", {:restricted, {:spawn, 1}}},
    {"fn x -> self() end", {:restricted, {:self, 0}}},
    {"fn x -> try do x after x end end", {:restricted, {:try, 1}}},
    {"fn x -> raise x end", {:restricted, {:raise, 1}}},
    {"fn x -> throw(x) end", {:restricted, {:throw, 1}}},
    {"fn x -> exit(x) end", {:restricted, {:exit, 1}}}
  ]

  @code [
    {"fn x -> quote do: x end", {:restricted, {:quote, 1}}},
    {"fn x -> unquote(x) end", {:restricted, {:unquote, 1}}},
    {"fn x -> import Enum end", {:restricted, {:import, 1}}},
    {"fn x -> require Logger end", {:restricted, {:require, 1}}},
    {"fn x -> alias Enum, as: E end", {:restricted, {:alias, 2}}},
    {"fn x -> defmodule String do end end", {:restricted, {:defmodule, 2}}},
    {"fn x -> binding() end", {:restricted, {:binding, 0}}},
    {"fn x -> @x end", {:restricted, {:@, 1}}},
    {"fn x -> ~r/x/ end", {:restricted, {:sigil_r, 2}}},
    {"fn x -> ~w(a b) end", {:restricted, {:sigil_w, 2}}},
    {"fn x -> ~s(a) end", {:restricted, {:sigil_s, 2}}},
    {"fn x -> ~c(a) end", {:restricted, {:sigil_c, 2}}},
    {"fn x -> __ENV__ end", {:restricted, {:__ENV__, 0}}},
    {"fn x -> __MODULE__ end", {:restricted, {:__MODULE__, 0}}},
    {"fn x -> dbg(x) end", {:restricted, {:dbg, 1}}}
  ]

  @structs [
    {"fn x -> %File.Stream{path: x} end", {:restricted, :struct}},
    {"fn x -> Map.put(x, :__struct__, File.Stream) end", {:restricted_atom, :__struct__}},
    {"fn x -> Map.put(x, :k, File.Stream) end", {:restricted_atom, "File.Stream"}},
    {"fn %File.Stream{} -> 1 end", {:restricted, :struct}}
  ]

  @collectables [
    {"fn xs -> for x <- xs, into: xs, do: x end", {:into, :literal}},
    {"fn xs -> for x <- xs, into: Map.new(), do: x end", {:into, :literal}},
    {"fn xs -> for x <- xs, into: [1], do: x end", {:into, :literal}},
    {"fn xs -> Enum.into(xs, xs) end", {:into, :literal}},
    {"fn xs -> Enum.into(xs, %{a: 1}) end", {:into, :literal}},
    {"fn xs -> Enum.into(xs, xs, & &1) end", {:into, :literal}},
    {"fn xs -> xs |> Enum.into(xs) end", {:into, :literal}},
    {"fn xs -> Enum.map(xs, &Enum.into/2) end", {:into, :literal}}
  ]

  for {group, attacks} <- [
        atoms: @atoms,
        calls: @calls,
        processes: @processes,
        code: @code,
        structs: @structs,
        collectables: @collectables
      ],
      {{source, reason}, i} <- Enum.with_index(attacks) do
    test "#{group} #{i}: #{source}" do
      reasons = refused(unquote(source))

      case unquote(Macro.escape(reason)) do
        # A name the node may or may not have seen is refused either way.
        {:any, alternatives} -> assert Enum.any?(alternatives, &(&1 in reasons))
        reason -> assert Enum.any?(reasons, &(spelled(&1) == spelled(reason)))
      end
    end
  end

  test "a name never seen is read as a string: the check passes" do
    for source <- @strings, do: assert({:ok, _} = Sandbox.check(source))
  end

  # A fault names a call by the atom the checker knows it by, or by its string when the
  # checker does not know the name; an attack is refused either way.
  defp spelled(atom) when is_atom(atom) and atom not in [nil, true, false], do: to_string(atom)
  defp spelled(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> Enum.map(&spelled/1)
  defp spelled(other), do: other

  test "every decided exclusion is refused when called, captured or piped into" do
    for module <- Allowlist.modules(), {{name, arity}, _reason} <- Allowlist.excluded(module) do
      receiver = if module == :math, do: ":math", else: inspect(module)
      args = Enum.map_join(1..arity//1, ", ", fn _ -> "x" end)
      fault = {:restricted, {module, name, arity}}

      assert fault in refused("fn x -> #{receiver}.#{name}(#{args}) end")
      assert fault in refused("fn x -> &#{receiver}.#{name}/#{arity} end")

      if arity >= 1 do
        rest = Enum.map_join(2..arity//1, ", ", fn _ -> "x" end)
        assert fault in refused("fn x -> x |> #{receiver}.#{name}(#{rest}) end")
      end
    end
  end

  test "a map read on an atom never calls the module it names" do
    assert {:error, :raised, BadMapError} = call("fn m -> m.halt end", [:erlang])
    assert {:error, :raised, BadMapError} = call("fn m -> m.node end", [:erlang])
  end

  test "a struct rebuilt from a row's time dispatches no protocol to a module that runs code" do
    # The `:__struct__` atom and the `DateTime` module reached through the data, not a
    # literal: `:__struct__` is the least of a struct's keys.
    source = """
    fn row ->
      {key, module} = Enum.min_by(Map.to_list(row.at), fn {k, _} -> k end)
      Enum.to_list(%{key => module, path: "/etc/passwd"})
    end
    """

    assert {:error, :raised, Protocol.UndefinedError} =
             call(source, [%{at: DateTime.utc_now()}])
  end

  test "interpolating a struct rebuilt from a row's time dispatches String.Chars only to it" do
    # Interpolation is `Kernel.to_string/1` (#769): the rebuilt map reaches `DateTime`'s
    # `String.Chars`, which reads fields the map lacks and raises, never another module.
    source = ~S"""
    fn row ->
      {key, module} = Enum.min_by(Map.to_list(row.at), fn {k, _} -> k end)
      "at #{%{key => module, path: "/etc/passwd"}}"
    end
    """

    assert {:error, :raised, _exception} = call(source, [%{at: DateTime.utc_now()}])
  end

  test "resources: the heap limit, the timeout and a raise end the call, never the caller" do
    assert {:error, :memory, 200_000} =
             call("fn _ -> Enum.to_list(1..100_000_000_000) end", [nil], max_heap: 200_000)

    assert {:error, :memory, 200_000} =
             call("fn _ -> for x <- 1..100_000_000_000, do: {x, x} end", [nil], max_heap: 200_000)

    assert {:error, :timeout, 30} =
             call(
               "fn _ -> Enum.reduce(1..100_000_000_000_000, 0, fn x, acc -> rem(acc + x, 7) end) end",
               [nil],
               timeout: 30
             )

    assert {:error, :raised, ArithmeticError} = call("fn x -> 1 / x end", [0])
  end

  test "the node makes no atom from any attack" do
    sources =
      Enum.map(@atoms ++ @calls ++ @processes ++ @code ++ @structs ++ @collectables, &elem(&1, 0)) ++
        @strings

    run = fn ->
      for source <- sources, do: Sandbox.check(source)
      for source <- sources, match?({:ok, _}, Sandbox.check(source)), do: Sandbox.compile(source)
      call("fn m -> m.halt end", [%{halt: 1}])
    end

    # A first run loads every module it reaches, which adds their atoms; a raise is not
    # run here, since the VM's report of it is formatted, and makes atoms, in the logger's
    # own time. What a raise can reach is the attacks above.
    run.()
    Logger.flush()
    before = :erlang.system_info(:atom_count)
    run.()
    assert :erlang.system_info(:atom_count) == before
  end
end
