defmodule Visualize.Chart.MigrationTest do
  @moduledoc "Version handling of spec/14 §9."
  use ExUnit.Case, async: true

  alias Visualize.Chart.Migration

  test "the current version passes through unchanged" do
    design = %{version: Migration.current(), frame: %{kind: :cartesian}}
    assert Migration.migrate(design) == {:ok, design}
  end

  test "a version this library does not write is an error at [:version]" do
    assert Migration.migrate(%{version: 2}) == {:error, [{[:version], {:unsupported_version, 2}}]}
    assert Migration.migrate(%{version: 0}) == {:error, [{[:version], {:unsupported_version, 0}}]}
    assert Migration.migrate(%{version: "1"}) == {:error, [{[:version], {:type, :integer}}]}
    assert Migration.migrate(%{}) == {:error, [{[:version], :required}]}
    assert Migration.migrate([]) == {:error, [{[], {:type, {:node, :design}}}]}
  end
end
