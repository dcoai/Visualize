defmodule Visualize.HooksTest do
  @moduledoc "D-48: the generated hook module exports each name exactly once."
  use ExUnit.Case, async: true

  alias Visualize.Hooks

  @hooks ~w(ZoomHook BrushHook CanvasChart CanvasBinaryChart CanvasIncrementalChart ResizeHook)

  test "every export name appears once, so a bundler accepts the file" do
    names =
      ~r/^\s*export\s+(?:const|function|let|class)\s+(\w+)/m
      |> Regex.scan(Hooks.js_code())
      |> Enum.map(fn [_, name] -> name end)

    assert names == Enum.uniq(names)
    assert Enum.all?(@hooks, &(&1 in names))
    assert length(Regex.scan(~r/^\s*export\s+default\b/m, Hooks.js_code())) == 1
    refute Hooks.js_code() =~ ~r/^\s*export\s*\{/m
  end

  test "the default export lists every hook" do
    [[_, body]] = Regex.scan(~r/export default \{([^}]*)\}/, Hooks.js_code())
    assert body |> String.split(~r/[\s,]+/, trim: true) |> Enum.sort() == Enum.sort(@hooks)
  end
end
