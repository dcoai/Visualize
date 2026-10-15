defmodule Visualize.Audit.CitationsTest do
  use ExUnit.Case, async: true

  alias Visualize.Audit.Citations

  doctest Citations

  @headings %{
    "06" => Citations.ids("# Layouts\n\n## 8. Force\n### 8.5 State machine\n## 9. Hexbin\n"),
    "13" => Citations.ids("# Decisions\n\n## 180. D-180 — A paint's own opacity\n")
  }

  defp check(text), do: Citations.check(text, "lib/x.ex", @headings)

  # A citation spelled apart, so this file's own text cites nothing the gate would refuse.
  defp cite(doc, ids), do: "spec/" <> doc <> " §" <> ids

  test "a citation of a heading that exists passes, in every form" do
    assert check("# The timer discipline (spec/06 §8.5).") == []
    assert check("see spec/06-layouts.md §8.5") == []
    assert check("([06-layouts](06-layouts.md) §8.5)") == []
    assert check("spec/13 §180, and spec/13 §D-180") == []
  end

  test "a citation of a section the document has no heading for fails at its line" do
    assert [problem] = check("first line\n# The timer discipline (#{cite("06", "9.4")}).")
    assert problem == "lib/x.ex:2: #{cite("06", "9.4")} names no heading of spec/06"
  end

  test "every id of a list or a range is of the one document and is checked" do
    assert check("spec/06 §8.5, §9") == []
    assert check("spec/06 §8–9") == []
    assert [problem] = check(cite("06", "8.5, §3.9"))
    assert problem =~ cite("06", "3.9")
    assert [_] = check(cite("06", "8–§10"))
  end

  test "a heading inside a code fence resolves nothing" do
    ids = Citations.ids("# T\n\n## 1. One\n```markdown\n## 2. Example\n```\n")
    assert [_] = Citations.check(cite("06", "2"), "lib/x.ex", %{"06" => ids})
  end

  test "a document spec/ does not have is named as such" do
    assert [problem] = check(cite("42", "1"))
    assert problem =~ "a document spec/ does not have"
  end

  test "a bare section with no document is the citing document's own and is not checked" do
    assert check("as §9.4 says") == []
  end

  test "a file that is not text has no citations" do
    assert Citations.check(<<0xFF, 0xFE>> <> cite("06", "9.4"), "test/x.png", @headings) == []
  end

  test "the tree's own citations all resolve" do
    assert Citations.run(File.cwd!()) == []
  end
end
