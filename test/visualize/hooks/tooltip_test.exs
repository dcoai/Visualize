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
    assert js =~ "else this.pushEvent(event, this.fields(el).values);"
    assert length(String.split(js, "pushEvent(")) == 2
  end

  test "a click's event goes to the component data-tooltip-target names (D-161)" do
    js = Tooltip.js_hook()
    assert js =~ "const target = this.el.dataset.tooltipTarget;"
    assert js =~ "if (target) this.pushEventTo(target, event, this.fields(el).values);"
  end

  @tag :js
  test "executed: a click goes to data-tooltip-target, else to the LiveView (D-161)" do
    assert {:ok, %{"log" => log}} =
             Visualize.JsHooks.run("""
             const chart = (attrs) => {
               const dot = Stub.markup('circle', {'data-datum': 'id t', 'data-datum-id': '42', 'data-datum-t': '1'});
               const mark = Stub.markup('g', {class: 'mark', 'data-tooltip-event': 'event_open'}, [dot]);
               const el = Stub.markup('div', attrs, [Stub.markup('svg', {}, [mark])]);
               Stub.mount(TooltipHook, el);
               return {el, dot, mark};
             };
             const cell = chart({id: 'cell-tooltip', 'data-tooltip-target': '4'});
             Stub.mark('targeted');
             // The stub does not bubble: a click reaches the hook's element, its target the node.
             Stub.fire(cell.el, 'click', {target: cell.dot});
             Stub.fire(cell.el, 'click', {target: cell.mark});
             const page = chart({id: 'page-tooltip'});
             Stub.mark('untargeted');
             Stub.fire(page.el, 'click', {target: page.dot});
             Stub.done({});
             """)

    pushes = fn mark ->
      for %{"kind" => "push"} = p <- Visualize.JsHooks.after_mark(log, mark),
          do: {p["target"], p["name"], p["payload"]}
    end

    fields = %{"id" => "42", "t" => "1"}
    # The mark's group is no datum element: only the dot's click pushes.
    assert pushes.("targeted") == [{"4", "event_open", fields}]
    assert pushes.("untargeted") == [{nil, "event_open", fields}]
  end

  test "the bundle carries the hook once and exports it" do
    js = Hooks.js_code()
    assert length(String.split(js, "export const TooltipHook = {")) == 2
    assert js =~ ~r/export default \{[^}]*\bTooltipHook\b/
  end
end
