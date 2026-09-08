defmodule Visualize.Hooks.LegendTest do
  @moduledoc "The `LegendHook` source (spec/10 §14.3, D-77): display, not hidden; re-applied on patch."
  use ExUnit.Case, async: true

  alias Visualize.Hooks
  alias Visualize.Hooks.Legend

  test "one click listener is bound once, kept, and removed with the same reference (D-47)" do
    js = Legend.js_hook()
    assert js =~ "export const LegendHook = {"
    assert length(Regex.scan(~r/\.bind\(this\)/, js)) == 1
    assert js =~ "this.el.addEventListener('click', this.onClick);"
    assert js =~ "this.el.removeEventListener('click', this.onClick);"
    assert length(Regex.scan(~r/addEventListener\(/, js)) == 1
  end

  test "an entry is found by its data-series inside the hook element and made clickable" do
    js = Legend.js_hook()
    assert js =~ "this.el.querySelectorAll('.legend-item[data-series]')"
    assert js =~ "e.target.closest('.legend-item[data-series]')"
    assert js =~ "if (!entry || !this.el.contains(entry)) return;"
    assert js =~ "entry.setAttribute('cursor', 'pointer')"
  end

  test "a hidden series gets display=none on its mark elements and a dimmed entry; never hidden" do
    js = Legend.js_hook()
    assert js =~ "this.el.querySelectorAll('.mark [data-series]')"
    assert js =~ "node.setAttribute('display', 'none')"
    assert js =~ "node.removeAttribute('display')"
    assert js =~ "'legend-item legend-item-hidden' : 'legend-item'"
    assert js =~ "entry.setAttribute('opacity', '0.35')"
    refute js =~ "'hidden'"
    refute js =~ "setAttribute('hidden'"
  end

  test "the hidden set is re-applied on updated() and the event is optional" do
    js = Legend.js_hook()
    assert js =~ "this.hidden = new Set();"
    assert js =~ "updated() {\n    this.decorate();\n    this.apply();"
    assert js =~ "this.eventName = this.el.dataset.legendEvent || null;"
    assert js =~ "if (this.eventName) this.pushEvent(this.eventName, { series, hidden });"
    assert length(String.split(js, "pushEvent(")) == 2
  end

  test "the bundle carries the hook once and exports it" do
    js = Hooks.js_code()
    assert length(String.split(js, "export const LegendHook = {")) == 2
    assert js =~ ~r/export default \{[^}]*\bLegendHook\b/
  end
end
