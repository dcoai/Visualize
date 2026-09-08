defmodule Visualize.Hooks.ResizeTest do
  @moduledoc "The `ResizeHook` source (spec/10 §10, D-54): observe, settle once, disconnect."
  use ExUnit.Case, async: true

  alias Visualize.Hooks
  alias Visualize.Hooks.Resize

  test "the hook observes its element with a ResizeObserver and stops on destroyed()" do
    js = Resize.js_hook()
    assert js =~ "export const ResizeHook = {"
    assert js =~ "new ResizeObserver("
    assert js =~ "this.observer.observe(this.el)"
    assert js =~ "if (typeof ResizeObserver === 'undefined') return;"
    assert js =~ "destroyed() {"
    assert js =~ "this.observer.disconnect()"
    assert js =~ "clearTimeout(this.timer)"
  end

  test "the event name and debounce come from data attributes with the specified defaults" do
    js = Resize.js_hook()
    assert js =~ "this.el.dataset.resizeEvent || 'resize'"
    assert js =~ "parseInt(this.el.dataset.resizeDebounce, 10) || 150"
  end

  test "a settle pushes {width, height} once, rounded, and never the same size twice" do
    js = Resize.js_hook()
    assert js =~ "setTimeout(() => this.settled(), this.debounce)"
    assert js =~ "Math.round(rect.width)"
    assert js =~ "Math.round(rect.height)"
    assert js =~ "this.last.width === size.width && this.last.height === size.height"
    assert js =~ "this.pushEvent(this.eventName, size)"
    assert length(String.split(js, "pushEvent(")) == 2
  end

  test "the bundle carries the hook once and exports it" do
    js = Hooks.js_code()
    assert length(String.split(js, "export const ResizeHook = {")) == 2
    assert js =~ ~r/export default \{[^}]*\bResizeHook\b/
  end
end
