defmodule ExamplesWeb.LayoutTest do
  @moduledoc """
  The root layout's hook wiring, which has broken twice in ways nothing caught.

  Both failures presented identically — every `phx-click` working and every hook silently
  absent — because the LiveSocket is built with `{ ...(window.VisualizeHooks || {}) }`, and
  an empty spread is not an error. The first was the route answering 403; the second was a
  dynamic `import()`, which is a promise and loses the race against `DOMContentLoaded`.
  """
  use ExUnit.Case, async: true

  @layout File.read!("lib/examples_web/layouts.ex")

  describe "the hooks module" do
    test "is imported statically, so it is loaded before the socket is built" do
      assert @layout =~ ~s(import VisualizeHooks from "/hooks/visualize_hooks.js";)

      refute @layout =~ ~s|import("/hooks/visualize_hooks.js")|,
             """
             The hooks import must stay static. A dynamic import() is a promise; the module
             body finishes without it and DOMContentLoaded builds the LiveSocket with no
             hooks, which presents as every hook quietly doing nothing.
             """
    end

    test "is registered on the socket, and a failure to load says so" do
      assert @layout =~ "window.VisualizeHooks = VisualizeHooks;"
      assert @layout =~ "hooks: { ...(window.VisualizeHooks || {})"
      assert @layout =~ "the hooks module did not load"
    end

    # The layout defines no hook of its own (#270): it once redefined CanvasChart,
    # CanvasBinaryChart and CanvasIncrementalChart with copies whose decoder was frozen
    # before D-73's f32 records, so every canvas page ran a decoder that did not know the
    # bytes the library sends, and the High-Performance page drew nothing.
    test "defines no hook of its own; the canvas hooks are the library's" do
      refute @layout =~ ~r/const \w+Hook\s*=\s*\{/
      refute @layout =~ ~r/const Canvas\w+\s*=\s*\{/
      refute @layout =~ "executeBinaryCommands"
      assert @layout =~ "hooks: { ...(window.VisualizeHooks || {}) }"

      hooks = Visualize.Hooks.js_code()

      for name <- ~w(CanvasChart CanvasBinaryChart CanvasIncrementalChart) do
        assert hooks =~ "export const #{name}", "#{name} is not in Visualize.Hooks.js_code/0"
      end

      # The library's decoder knows every record the encoder writes, the f32 ones included.
      for opcode <- ["0x05", "0x06", "0x07"], do: assert(hooks =~ "case #{opcode}:")
    end

    test "carries the hook the builder needs, and the rest of them" do
      hooks = Visualize.Hooks.js_code()

      for name <- ~w(BuilderHook ZoomHook BrushHook TooltipHook CrosshairHook LegendHook
                     ResizeHook) do
        assert hooks =~ "export const #{name}", "#{name} is not in Visualize.Hooks.js_code/0"
        assert hooks =~ ~r/export default \{[^}]*\b#{name}\b/, "#{name} is not exported by default"
      end
    end
  end

  describe "the hooks route" do
    test "is not behind protect_from_forgery, which raises on a JavaScript response" do
      router = File.read!("lib/examples_web/router.ex")

      [_, asset_scope] = String.split(router, "pipe_through :asset", parts: 2)
      assert asset_scope =~ ~s(get "/hooks/visualize_hooks.js")

      [browser_scope, _] = String.split(router, "pipe_through :asset", parts: 2)
      [_, browser_scope] = String.split(browser_scope, "pipe_through :browser", parts: 2)

      refute browser_scope =~ "visualize_hooks.js",
             "the hooks asset is in the browser pipeline again; it will answer 403"
    end
  end
end
