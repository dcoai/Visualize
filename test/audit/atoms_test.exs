defmodule Visualize.Audit.AtomsTest do
  use ExUnit.Case, async: true

  alias Visualize.Audit.Atoms

  @moduletag :tmp_dir

  defp lib(dir, text) do
    File.mkdir_p!(Path.join(dir, "lib"))
    File.write!(Path.join(dir, "lib/x.ex"), text)
  end

  defp entry(match, count, class \\ :d),
    do: %{file: "lib/x.ex", match: match, count: count, class: class, reason: "bounded"}

  test "the library holds no site the allowlist does not" do
    assert Atoms.run(File.cwd!()) == []
  end

  test "every way of making an atom from a string fails at its line", %{tmp_dir: dir} do
    lib(dir, """
    a = String.to_atom(s)
    b = :erlang.binary_to_atom(s, :utf8)
    c = List.to_atom(cs)
    d = :erlang.list_to_atom(cs)
    e = :"cell_\#{n}"
    f = String.to_existing_atom(s)
    # String.to_atom(s) in a comment makes none
    """)

    problems = Atoms.run(dir, [])
    assert length(problems) == 5
    assert Enum.map(problems, &hd(String.split(&1, ": "))) == Enum.map(1..5, &"lib/x.ex:#{&1}")
  end

  test "an allowlisted site passes, and an entry that no longer matches fails", %{tmp_dir: dir} do
    lib(dir, "a = :\"series_\#{k}\"\n")

    assert Atoms.run(dir, [entry("series_", 1)]) == []
    assert [stale] = Atoms.run(dir, [entry("series_", 2)])
    assert stale =~ "holds 1 line(s)"
    assert [_unallowed, _stale] = Atoms.run(dir, [entry("style_", 1)])
  end

  test "an entry needs a class of D-195 and a reason", %{tmp_dir: dir} do
    lib(dir, "a = :\"series_\#{k}\"\n")
    assert [problem] = Atoms.run(dir, [entry("series_", 1, :e)])
    assert problem =~ "an entry needs"
  end

  test "a declared name is a string: an entry of class (b) or (c) fails", %{tmp_dir: dir} do
    lib(dir, "a = String.to_atom(name)\n")

    for class <- [:b, :c] do
      assert [problem] = Atoms.run(dir, [entry("String.to_atom(name)", 1, class)])
      assert problem =~ "is a string (D-195)"
    end
  end
end
