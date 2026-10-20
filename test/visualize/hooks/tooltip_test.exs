defmodule Visualize.Hooks.TooltipTest do
  @moduledoc "The `TooltipHook` source (spec/10 §12.3, D-75): no round trip, no markup."
  use ExUnit.Case, async: true

  alias Visualize.Hooks
  alias Visualize.Hooks.Tooltip

  doctest Tooltip

  @listeners ~w(mousemove mouseleave touchmove touchend click contextmenu touchstart touchcancel)

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

  test "the listeners are bound once, kept, and removed with the same references (D-47)" do
    js = Tooltip.js_hook()
    # The five pointer listeners, the three of a secondary gesture (D-199) and the sync
    # bus's one (spec/10 §4.3), which the bus adds and removes on `document`.
    assert length(Regex.scan(~r/\.bind\(this\)/, js)) == 9
    assert js =~ "this.onSync = this.handleSync.bind(this);"
    assert js =~ "VisualizeSync.detach(this);"

    for name <- @listeners do
      assert js =~ ~r/this\.el\.addEventListener\('#{name}', this\.on\w+[,)]/
      assert js =~ ~r/this\.el\.removeEventListener\('#{name}', this\.on\w+\)/
    end

    assert length(Regex.scan(~r/addEventListener\(/, js)) == 8
    assert length(Regex.scan(~r/removeEventListener\(/, js)) == 8
  end

  test "the datum element is the nearest ancestor-or-self with data-datum inside the hook" do
    js = Tooltip.js_hook()
    assert js =~ "target.closest('[data-datum]')"
    assert js =~ "return el && this.el.contains(el) ? el : null;"
  end

  test "an element under data-tooltip-show=\"false\" is never shown, by pointer or sync (D-200)" do
    js = Tooltip.js_hook()
    assert js =~ "return this.nearest(el, 'data-tooltip-show') !== 'false';"
    assert js =~ "if (!el || !this.shown(el)) {"
    assert js =~ "if (!this.shown(el)) return;"
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

  # A click's key and its wire event are `VisualizeItems`' (spec/10 §12.5), which
  # `TooltipHook` and `KeyboardHook` share, so one click is one event whichever hears it.
  test "a click pushes one wire event, visualize_event, and never the datum's strings (D-170)" do
    js = Tooltip.js_hook()
    assert js =~ "return VisualizeItems.key(this.el, this, e);"
    assert js =~ "VisualizeItems.send(this, this.el, key, e);"
    refute js =~ "pushEvent("

    items = Tooltip.js_items()

    assert items =~
             "this.nearest(root, el, context ? 'data-tooltip-context-event' : 'data-tooltip-event')"

    assert items =~ "if (!event || mark === null || row === null) return null;"
    assert items =~ "else hook.pushEvent('visualize_event', payload);"
    assert items =~ "if (target) hook.pushEventTo(target, 'visualize_event', payload);"
    assert length(String.split(items, "pushEvent(")) == 2
    refute items =~ "data-datum-"
  end

  test "the payload is the element's key, the drawing's token, the pointer and the modifiers" do
    js = Tooltip.js_items()
    assert js =~ "frame: this.nearest(root, el, 'data-frame'), mark: parseInt(mark, 10),"
    assert js =~ "row: parseInt(row, 10), at: this.svgPoint(el, e) };"
    assert js =~ "drawn: root.dataset.tooltipDrawn || null,"
    assert js =~ "['shift', 'alt', 'ctrl', 'meta'].filter((name) => e && e[name + 'Key'])"
    # On a canvas the key is the hit index's (spec/10 §12.5, D-197).
    assert js =~ "const hit = at && this.hit(items, at.x, at.y);"
    assert js =~ "pt.matrixTransform(svg.getScreenCTM().inverse())"
  end

  @tag :js
  test "executed: a keyed click goes to data-tooltip-target, else to the LiveView (D-161, D-170)" do
    assert {:ok, %{"log" => log}} =
             Visualize.JsHooks.run("""
             const chart = (attrs) => {
               const dot = Stub.markup('circle', {'data-datum': 'id t', 'data-datum-id': '42', 'data-datum-t': '1', 'data-row': '3'});
               const bare = Stub.markup('circle', {'data-datum': 'id', 'data-datum-id': '43'});
               const mark = Stub.markup('g', {class: 'mark', 'data-tooltip-event': 'event_open', 'data-frame': 'main', 'data-mark': '1'}, [dot, bare]);
               const svg = Stub.markup('svg', {viewBox: '0 0 200 100'}, [mark]);
               svg.rect = {left: 10, top: 20, width: 400, height: 200};
               const el = Stub.markup('div', attrs, [svg]);
               Stub.mount(TooltipHook, el);
               return {el, dot, bare, mark};
             };
             const cell = chart({id: 'cell-tooltip', 'data-tooltip-target': '4', 'data-tooltip-drawn': '17'});
             Stub.mark('targeted');
             // The stub does not bubble: a click reaches the hook's element, its target the node.
             Stub.fire(cell.el, 'click', {target: cell.dot, clientX: 110, clientY: 70, shiftKey: true, metaKey: true});
             Stub.fire(cell.el, 'click', {target: cell.mark});
             Stub.fire(cell.el, 'click', {target: cell.bare});
             const page = chart({id: 'page-tooltip'});
             Stub.mark('untargeted');
             Stub.fire(page.el, 'click', {target: page.dot});
             Stub.done({});
             """)

    pushes = fn mark ->
      for %{"kind" => "push"} = p <- Visualize.JsHooks.after_mark(log, mark),
          do: {p["target"], p["name"], p["payload"]}
    end

    # The mark's group is no datum element, and a datum without data-row has no key: only
    # the keyed dot's click pushes, in the chart's user units (half the client pixels).
    assert pushes.("targeted") == [
             {"4", "visualize_event",
              %{
                "event" => "event_open",
                "frame" => "main",
                "mark" => 1,
                "row" => 3,
                "drawn" => "17",
                "at" => %{"x" => 50, "y" => 25},
                "modifiers" => ["shift", "meta"]
              }}
           ]

    assert [{nil, "visualize_event", %{"drawn" => nil, "at" => nil, "modifiers" => []}}] =
             pushes.("untargeted")
  end

  test "attrs/1 is the palette's :hover for the frame, a design's own winning (#638)" do
    design = fn styles ->
      %{version: 2, styles: styles, frames: %{main: %{kind: :cartesian}}}
      |> Visualize.Chart.from_map!()
      |> Visualize.Chart.Frame.new(size: {100, 100})
    end

    assert Tooltip.attrs(design.(%{})) ==
             %{"data-vis-hover" => ~s({"stroke":"#333333","stroke-width":"2"})}

    # A binding has no datum in the overlay and is left out; :none is the word.
    hover = %{fill: :none, stroke: {:field, :v}, stroke_width: 4, stroke_linecap: :round}

    assert Tooltip.attrs(design.(%{hover: hover})) ==
             %{
               "data-vis-hover" => ~s({"fill":"none","stroke-width":"4","stroke-linecap":"round"})
             }
  end

  @tag :js
  test "executed: data-vis-hover outlines the datum shown; absent, nothing is drawn (#638)" do
    assert {:ok, %{"report" => r}} =
             Visualize.JsHooks.run("""
             const chart = (attrs) => {
               const dot = Stub.markup('circle', {'data-datum': 'v', 'data-datum-v': '4'});
               dot.rect = {left: 40, top: 30, width: 10, height: 6};
               const el = Stub.markup('div', attrs, [Stub.markup('svg', {}, [dot])]);
               return {el, dot, hook: Stub.mount(TooltipHook, el)};
             };
             const outlines = () => document.body.querySelectorAll('.vis-tooltip-hover').length;
             const styled = chart({id: 'a', 'data-vis-hover': '{"stroke":"#c23238","stroke-width":"3"}'});
             Stub.fire(styled.el, 'mousemove', {target: styled.dot, pageX: 45, pageY: 33, clientX: 45});
             const o = styled.hook.outline;
             const rect = styled.hook.outlineRect;
             const report = {
               shown: [o.style.display, o.style.left, o.style.top, o.style.width, o.style.height],
               rect: ['x', 'y', 'width', 'height', 'fill', 'stroke', 'stroke-width'].map((n) => rect.getAttribute(n))
             };
             Stub.fire(styled.el, 'mouseleave', {});
             report.left = o.style.display;
             // A patch that drops the attribute draws no outline again.
             delete styled.el.dataset.visHover;
             styled.hook.updated();
             Stub.fire(styled.el, 'mousemove', {target: styled.dot, pageX: 45, pageY: 33, clientX: 45});
             report.dropped = o.style.display;
             const bare = chart({id: 'b'});
             Stub.fire(bare.el, 'mousemove', {target: bare.dot, pageX: 45, pageY: 33, clientX: 45});
             report.bare = [bare.hook.outline, outlines()];
             styled.hook.destroyed();
             report.removed = outlines();
             Stub.done(report);
             """)

    # Padded by the stroke width and 2 pixels around the dot's 10 by 6 box at (40, 30).
    assert r["shown"] == ["block", "35px", "25px", "20px", "16px"]
    assert r["rect"] == ["5", "5", "10", "6", "none", "#c23238", "3"]
    assert r["left"] == "none"
    assert r["dropped"] == "none"
    assert r["bare"] == [nil, 1]
    assert r["removed"] == 0
  end

  test "the bundle carries the hook once and exports it" do
    js = Hooks.js_code()
    assert length(String.split(js, "export const TooltipHook = {")) == 2
    assert js =~ ~r/export default \{[^}]*\bTooltipHook\b/
  end
end
