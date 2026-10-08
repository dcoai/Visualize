defmodule Visualize.Hooks.TooltipTest do
  @moduledoc "The `TooltipHook` source (spec/10 §12.3, D-75): no round trip, no markup."
  use ExUnit.Case, async: true

  alias Visualize.Hooks
  alias Visualize.Hooks.Tooltip

  @listeners ~w(mousemove mouseleave touchmove touchend click)

  test "the tooltip element is created on mount with the configured class and removed on destroy" do
    js = Tooltip.js_hook()
    assert js =~ "export const TooltipHook = {"
    assert js =~ "this.tip = document.createElement('div');"
    assert js =~ "this.el.dataset.tooltipClass || 'vis-tooltip'"
    assert js =~ "this.tip.style.pointerEvents = 'none';"
    assert js =~ "this.tip.style.whiteSpace = 'pre';"
    assert js =~ "document.body.appendChild(this.tip);"
    assert js =~ "if (this.tip.parentNode) this.tip.parentNode.removeChild(this.tip);"
  end

  test "five listeners are bound once, kept, and removed with the same references (D-47)" do
    js = Tooltip.js_hook()
    # The five pointer listeners and the sync bus's one (spec/10 §4.3), which the bus adds
    # and removes on `document`.
    assert length(Regex.scan(~r/\.bind\(this\)/, js)) == 6
    assert js =~ "this.onSync = this.handleSync.bind(this);"
    assert js =~ "VisualizeSync.detach(this);"

    for name <- @listeners do
      assert js =~ ~r/this\.el\.addEventListener\('#{name}', this\.on\w+[,)]/
      assert js =~ ~r/this\.el\.removeEventListener\('#{name}', this\.on\w+\)/
    end

    assert length(Regex.scan(~r/addEventListener\(/, js)) == 5
    assert length(Regex.scan(~r/removeEventListener\(/, js)) == 5
  end

  test "the datum element is the nearest ancestor-or-self with data-datum inside the hook" do
    js = Tooltip.js_hook()
    assert js =~ "target.closest('[data-datum]')"
    assert js =~ "return el && this.el.contains(el) ? el : null;"
  end

  test "fields come from data-datum in order and data-datum-<field> with _ as -" do
    js = Tooltip.js_hook()
    assert js =~ "el.getAttribute('data-datum')"
    assert js =~ "el.getAttribute('data-datum-' + name.replace(/_/g, '-'))"
    assert js =~ "values[name] = value === null ? '' : value;"
  end

  test "the nearest template formats {field} placeholders; without one, field: value lines" do
    js = Tooltip.js_hook()
    assert js =~ "this.nearest(el, 'data-tooltip-template')"
    assert js =~ "if (node === this.el) return null;"

    assert js =~
             ~S|template.replace(/\{([^}]+)\}/g, (_, name) => (name in values ? values[name] : ''))|

    assert js =~ ~S|names.map((name) => name + ': ' + values[name]).join('\n')|
    assert js =~ "this.tip.textContent = this.text(el);"
    refute js =~ "innerHTML"
  end

  test "the tooltip sits 12px right of and below the pointer and flips at the viewport edges" do
    js = Tooltip.js_hook()
    assert js =~ "pageX + 12 + width > right ? pageX - 12 - width : pageX + 12"
    assert js =~ "pageY + 12 + height > bottom ? pageY - 12 - height : pageY + 12"
    assert js =~ "document.elementFromPoint(touch.clientX, touch.clientY)"
  end

  test "a click pushes the fields only when a data-tooltip-event names the event" do
    js = Tooltip.js_hook()
    assert js =~ "this.nearest(el, 'data-tooltip-event')"
    assert js =~ "if (!event) return;"
    assert js =~ "this.pushEvent(event, this.fields(el).values);"
    assert length(String.split(js, "pushEvent(")) == 2
  end

  test "the bundle carries the hook once and exports it" do
    js = Hooks.js_code()
    assert length(String.split(js, "export const TooltipHook = {")) == 2
    assert js =~ ~r/export default \{[^}]*\bTooltipHook\b/
  end
end
