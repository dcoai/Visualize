defmodule Visualize.VirtualSource.AllowlistTest do
  # The allowlist held to the exports (spec/12 §7, spec/08 §10.5.2, D-194): each module's
  # allowed and excluded lists together are its exports on Elixir 1.20.4 / OTP 29, exactly,
  # so a function a new release adds fails here until it is reviewed and listed — and a
  # function the library adds to `Visualize.Data` likewise (#769).
  use ExUnit.Case, async: true

  alias Visualize.VirtualSource.Sandbox.Allowlist

  defp exports(:math) do
    for {name, arity} <- :math.module_info(:exports), name != :module_info, do: {name, arity}
  end

  defp exports(module) do
    functions =
      for {name, arity} <- module.module_info(:exports),
          name not in [:module_info, :__info__],
          not String.starts_with?(Atom.to_string(name), "MACRO-"),
          do: {name, arity}

    Enum.uniq(functions ++ module.__info__(:macros))
  end

  @modules [Enum, Map, Keyword, String, Integer, Float, :math, Visualize.Data]

  test "the eight modules, in order" do
    assert Allowlist.modules() == @modules
  end

  for module <- @modules do
    test "#{inspect(module)}'s exports are its allowed and excluded lists, exactly" do
      module = unquote(module)
      allowed = Allowlist.allowed(module)
      excluded = for {fa, _reason} <- Allowlist.excluded(module), do: fa

      assert allowed -- Enum.uniq(allowed) == [], "#{inspect(module)} lists a function twice"
      assert MapSet.disjoint?(MapSet.new(allowed), MapSet.new(excluded))
      assert Enum.sort(allowed ++ excluded) == Enum.sort(exports(module))
    end
  end

  test "the decided exclusions are excluded" do
    for {module, fa} <- [
          {Enum, {:random, 1}},
          {Enum, {:shuffle, 1}},
          {Enum, {:take_random, 2}},
          {String, {:to_atom, 1}},
          {String, {:to_existing_atom, 1}},
          {String, {:strip, 1}},
          {Integer, {:to_char_list, 1}},
          {Float, {:to_char_list, 1}}
        ] do
      assert fa in Enum.map(Allowlist.excluded(module), &elem(&1, 0))
      refute fa in Allowlist.allowed(module)
    end
  end

  test "every reason is one of the four" do
    for module <- Allowlist.modules(), {_fa, reason} <- Allowlist.excluded(module) do
      assert reason in [:nondeterministic, :deprecated, :atoms, :internal]
    end
  end

  test "the Kernel list names only what Kernel or its special forms define" do
    kernel =
      Kernel.__info__(:functions) ++
        Kernel.__info__(:macros) ++ Kernel.SpecialForms.__info__(:macros)

    for fa <- Allowlist.kernel(), do: assert(fa in kernel, "#{inspect(fa)} is not Kernel's")
  end

  test "Visualize.Data excludes nothing: its statistics are pure" do
    assert Allowlist.excluded(Visualize.Data) == []
    assert {:slope, 2} in Allowlist.allowed(Visualize.Data)
    assert {:delta, 1} in Allowlist.allowed(Visualize.Data)
  end

  test "to_string/1, string interpolation's call, is on the Kernel list (#769)" do
    assert {:to_string, 1} in Allowlist.kernel()
    assert Allowlist.remote?(Kernel, :to_string, 1)
    refute Allowlist.guard?(:to_string, 1)
  end

  test "every is_* guard of Kernel is on the Kernel list" do
    for {name, _arity} = fa <- Kernel.__info__(:functions) ++ Kernel.__info__(:macros),
        String.starts_with?(Atom.to_string(name), "is_"),
        do: assert(fa in Allowlist.kernel(), "#{inspect(fa)} is missing")
  end
end
