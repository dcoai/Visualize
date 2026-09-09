defmodule Mix.Tasks.Vis.SurfaceTest do
  @moduledoc """
  The check's failure branches, which CI's success-path job never exercises: drift of the
  golden, a missing golden, and — since #96 — any row whose status is not `specified`
  (spec/12 §2).
  """
  use ExUnit.Case, async: true

  @moduletag :tmp_dir

  alias Mix.Tasks.Vis.Surface

  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
    :ok
  end

  defp clean, do: %{unspecified: [], unimplemented: []}

  test "passes when the file matches and every row is specified", %{tmp_dir: tmp} do
    path = Path.join(tmp, "API_SURFACE.md")
    File.write!(path, "same")
    Surface.check!(path, "same", clean())
    assert_received {:mix_shell, :info, [msg]}
    assert msg =~ "is current"
    assert msg =~ "every row specified"
  end

  test "raises on drift, naming the remedy", %{tmp_dir: tmp} do
    path = Path.join(tmp, "API_SURFACE.md")
    File.write!(path, "committed")
    error = assert_raise Mix.Error, fn -> Surface.check!(path, "rendered", clean()) end
    assert error.message =~ "has drifted"
    assert error.message =~ "mix vis.surface --write"
  end

  test "raises when the file is missing", %{tmp_dir: tmp} do
    path = Path.join(tmp, "API_SURFACE.md")
    error = assert_raise Mix.Error, fn -> Surface.check!(path, "anything", clean()) end
    assert error.message =~ "is missing"
  end

  test "raises on an unspecified row, naming the function", %{tmp_dir: tmp} do
    path = Path.join(tmp, "API_SURFACE.md")
    File.write!(path, "same")
    result = %{clean() | unspecified: ["Visualize.Undeclared.thing/2"]}
    error = assert_raise Mix.Error, fn -> Surface.check!(path, "same", result) end
    assert error.message =~ "1 row(s) that are not `specified`"
    assert error.message =~ "Visualize.Undeclared.thing/2"
    assert error.message =~ "Write the row in spec/"
    refute error.message =~ "unimplemented —"
  end

  test "raises on an unimplemented row, naming the row", %{tmp_dir: tmp} do
    path = Path.join(tmp, "API_SURFACE.md")
    File.write!(path, "same")
    result = %{clean() | unimplemented: ["Visualize.Gone.removed/0"]}
    error = assert_raise Mix.Error, fn -> Surface.check!(path, "same", result) end
    assert error.message =~ "Visualize.Gone.removed/0"
    assert error.message =~ "Build it, or delete the row"
    refute error.message =~ "unspecified —"
  end

  test "names both backlogs at once, and counts them together", %{tmp_dir: tmp} do
    path = Path.join(tmp, "API_SURFACE.md")
    File.write!(path, "same")
    result = %{unspecified: ["A.b/0", "A.c/1"], unimplemented: ["D.e/2"]}
    error = assert_raise Mix.Error, fn -> Surface.check!(path, "same", result) end
    assert error.message =~ "3 row(s) that are not `specified`"
    for item <- ["A.b/0", "A.c/1", "D.e/2"], do: assert(error.message =~ item)
  end

  test "reports drift before the row statuses", %{tmp_dir: tmp} do
    # A stale file makes any statement about its rows an answer about the wrong document.
    path = Path.join(tmp, "API_SURFACE.md")
    File.write!(path, "committed")
    result = %{clean() | unspecified: ["A.b/0"]}
    error = assert_raise Mix.Error, fn -> Surface.check!(path, "rendered", result) end
    assert error.message =~ "has drifted"
  end
end
