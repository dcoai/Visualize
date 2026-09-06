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

  test "the committed spec/ passes" do
    assert Headings.run(File.cwd!()) == []
  end
end
