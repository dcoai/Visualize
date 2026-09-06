defmodule Visualize.Audit.SpecScanTest do
  use ExUnit.Case, async: true

  alias Visualize.Audit.SpecScan

  @markdown """
  # Fixture

  **Status:** Implemented

  ## 1. First

  | Function | Contract |
  |---|---|
  | `Visualize.Fixture.one/0` | one |

  ### 1.2 Nested

  | Function | Contract |
  |---|---|
  | `Visualize.Fixture.two/2` | two |
  | not a declaration | `Visualize.Fixture.three/0` in the wrong cell |
  | `Visualize.Fixture.camelCase1/1` | digits and camel case |
  """

  test "rows are found with the section they sit under" do
    entries = SpecScan.scan_source(@markdown, "spec/07-fixture.md")

    assert Enum.map(entries, & &1.item) == [
             "Visualize.Fixture.one/0",
             "Visualize.Fixture.two/2",
             "Visualize.Fixture.camelCase1/1"
           ]

    assert Enum.map(entries, & &1.section) == ["spec/07 §1", "spec/07 §1.2", "spec/07 §1.2"]
  end

  test "a backticked function outside the first cell is not a declaration" do
    refute Enum.any?(SpecScan.scan_source(@markdown, "spec/x.md"), &(&1.item =~ "three"))
  end
end
