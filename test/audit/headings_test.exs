defmodule Visualize.Audit.HeadingsTest do
  use ExUnit.Case, async: true

  alias Visualize.Audit.Headings

  @good """
  # Title

  **Status:** Implemented

  ## 1. One
  ### 1.1 One one
  ### 1.2 One two
  ## 2. Two
  #### 2.1.1 No parent heading 2.1 exists
  """

  test "a well-numbered document has one problem: 2.1.1 has no parent 2.1" do
    assert [problem] = Headings.check(@good, "spec/x.md")
    assert problem =~ "2.1.1"
  end

  test "gaps, duplicates, missing status and extra titles are reported" do
    bad = """
    # Title

    not a status line

    ## 1. One
    ## 3. Gap
    ## 3. Duplicate
    # Second title
    """

    problems = Headings.check(bad, "spec/x.md")
    assert Enum.any?(problems, &(&1 =~ "Status"))
    assert Enum.any?(problems, &(&1 =~ "expected 2, found 3"))
    assert Enum.any?(problems, &(&1 =~ "expected 4, found 3"))
    assert Enum.any?(problems, &(&1 =~ "2 `#` titles"))
  end

  describe "tables (#599)" do
    @titled "# Title\n\n**Status:** Implemented\n\n## 1. One\n\n"

    test "a table with a header and separator passes" do
      assert Headings.check(
               @titled <> "| Key | Meaning |\n|---|---|\n| `a` | one |\n",
               "spec/x.md"
             ) ==
               []
    end

    test "rows cut off from their table by a blank line or a paragraph are reported" do
      blank = "| Key | Meaning |\n|---|---|\n| `a` | one |\n\n| `b` | two |\n"
      paragraph = "| Key | Meaning |\n|---|---|\n| `a` | one |\n\nA paragraph.\n| `b` | two |\n"

      assert ["spec/x.md:11: table rows without a header and separator row"] =
               Headings.check(@titled <> blank, "spec/x.md")

      assert ["spec/x.md:12: table rows without a header and separator row"] =
               Headings.check(@titled <> paragraph, "spec/x.md")
    end

    test "a blank first cell is reported" do
      table = "| Type | Option |\n|---|---|\n| `:a` | `:x` |\n| | `:y` |\n"

      assert ["spec/x.md:10: a table row with a blank first cell"] =
               Headings.check(@titled <> table, "spec/x.md")
    end

    test "pipes inside a code fence are not a table" do
      fenced = "```elixir\n| :a\n| :b\n```\n"
      assert Headings.check(@titled <> fenced, "spec/x.md") == []
    end
  end

  test "the committed spec/ passes" do
    assert Headings.run(File.cwd!()) == []
  end
end
