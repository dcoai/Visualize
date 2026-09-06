defmodule Mix.Tasks.Vis.SurfaceTest do
  @moduledoc """
  `check!/2`'s two failure branches, which CI's success-path job never exercises.
  """
  use ExUnit.Case, async: true

  @moduletag :tmp_dir

  alias Mix.Tasks.Vis.Surface

  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
    :ok
  end

  test "passes when the file matches", %{tmp_dir: tmp} do
    path = Path.join(tmp, "API_SURFACE.md")
    File.write!(path, "same")
    Surface.check!(path, "same")
    assert_received {:mix_shell, :info, [msg]}
    assert msg =~ "is current"
  end

  test "raises on drift, naming the remedy", %{tmp_dir: tmp} do
    path = Path.join(tmp, "API_SURFACE.md")
    File.write!(path, "committed")
    error = assert_raise Mix.Error, fn -> Surface.check!(path, "rendered") end
    assert error.message =~ "has drifted"
    assert error.message =~ "mix vis.surface --write"
  end

  test "raises when the file is missing", %{tmp_dir: tmp} do
    path = Path.join(tmp, "API_SURFACE.md")
    error = assert_raise Mix.Error, fn -> Surface.check!(path, "anything") end
    assert error.message =~ "is missing"
  end
end
