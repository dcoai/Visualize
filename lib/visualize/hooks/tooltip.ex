defmodule Visualize.Hooks.Tooltip do
  @moduledoc """
  Phoenix LiveView hook that shows a datum's fields under the pointer (spec/10 §12).

  `TooltipHook` needs no round trip: the server writes each datum's fields onto the element
  that draws it — `Visualize.IR.Element.datum/2`, or a mark's `tooltip` node
  (spec/14 §5.7) — and the hook reads them from the element under the pointer (D-75). A
  `data-tooltip-template` on the element or an ancestor formats the text with `{field}`
  placeholders; without one the tooltip lists `field: value` per line.

  A click on a datum of a mark whose `tooltip` names an `event` pushes one wire event,
  `visualize_event`, with the element's key — its frame, its mark's position and its
  row's ordinal — the drawing's `data-tooltip-drawn` token, the pointer and the modifiers
  (spec/10 §12.3, D-170), to the component `data-tooltip-target` names, else to the
  LiveView. `Visualize.Components.Chart` and a board's cell are those components: they
  resolve the click to the row drawn and send the page a `Visualize.Event`.

  In a sync group (spec/10 §4.3, §12.4) the hook publishes the pointer's x in domain units
  on the group's bus, and shows the datum element nearest to another member's hover.

  ## Usage

      <svg id="chart" phx-hook="TooltipHook">
        <g class="mark mark-circle" data-tooltip-template="{t}: {v}">
          <circle cx="10" cy="20" r="3" data-datum="t v" data-datum-t="1" data-datum-v="4"/>
        </g>
      </svg>

  A chart whose marks declare events is rendered through `Visualize.Components.Chart`,
  which mounts the hook itself.

  ## Configuration

  Data attributes on the hook element:
  - `data-tooltip-class` - class of the tooltip element the hook creates
    (default: "vis-tooltip")
  - `data-tooltip-target` - the `phx-target` a click's event goes to with `pushEventTo`;
    unset, it goes to the LiveView (D-161)
  - `data-tooltip-drawn` - the holder's token for the drawing on screen, sent with a click
    (D-170)
  - `data-vis-hover` - the palette's `:hover`, from `attrs/1`: the datum element shown is
    outlined in it (spec/10 §4.4); absent, nothing is outlined

  Data attributes on the elements, written by the server (spec/10 §12.2):
  - `data-datum` - the field names, space-separated, in order
  - `data-datum-<field>` - the value of each field, `_` in the name as `-`
  - `data-tooltip-template` - the text with `{field}` placeholders; the nearest wins
  - `data-tooltip-event` - the declared event a click delivers; absent, nothing is pushed
  - `data-tooltip-show` - `"false"`: the element's mark takes clicks with nothing shown
    under the pointer, no tooltip and no outline (D-200)
  - `data-frame`, `data-mark` - on a mark's group with an event: its frame and position
  - `data-row` - on each datum element of such a mark: the row's ordinal in its rows
  """

  alias Visualize.Chart.Frame
  alias Visualize.Hooks.States
  alias Visualize.Hooks.Tooltip.Items
  alias Visualize.IR.Element

  @doc """
  The hook element's `data-vis-hover` for a realized frame (spec/10 §12.1, §4.4): the
  palette's `:hover` as the frame's design and theme resolve it, in `:literal` mode, as a
  JSON object of SVG attributes the hook outlines the datum element it shows with.

  ## Examples

      iex> chart = Visualize.Chart.from_map!(%{version: 2, frames: %{main: %{kind: :cartesian}}})
      iex> frame = Visualize.Chart.Frame.new(chart, size: {100, 100})
      iex> Visualize.Hooks.Tooltip.attrs(frame)
      %{"data-vis-hover" => ~s({"stroke":"#333333","stroke-width":"2"})}

  """
  @spec attrs(Frame.t()) :: %{String.t() => String.t()}
  def attrs(%Frame{} = frame), do: States.attrs(frame, :hover)

  @doc """
  The hit index of a drawing (spec/10 §12.5, D-197): the hook element's `data-vis-items`
  for a chart's generated element (`Visualize.Chart.generate/2`), as JSON. Every keyed
  datum element of a mark with an event — the elements a click on the SVG lands on — is
  its shape in the chart's user units, in drawing order, under its mark's event, frame and
  position, so a click on a canvas, which draws no element, sends the key the SVG would.
  `Visualize.Components.Chart` writes it on a canvas, with `data-size`.

  ## Examples

      iex> design = %{version: 3, sources: %{s: %{fields: [:x, :y]}},
      ...>   frames: %{main: %{kind: :cartesian, margin: %{top: 0, right: 0, bottom: 0, left: 0},
      ...>     scales: %{x: %{kind: :linear, domain: [0, 10]}, y: %{kind: :linear, domain: [0, 10]}}}},
      ...>   marks: [%{type: :circle, data: :s, channels: %{x: :x, y: :y},
      ...>             options: %{radius: 4}, tooltip: %{event: :pick}}]}
      iex> {:ok, applied} = Visualize.Chart.apply(design, sources: %{s: [%{x: 5, y: 5}]}, size: {100, 100})
      iex> Visualize.Hooks.Tooltip.items(Visualize.Chart.generate(applied))
      ~s([{"event":"pick","context":null,"frame":"main","mark":0,"items":[[0,"c",50,50,4]]}])

  """
  @spec items(Element.t()) :: String.t()
  def items(%Element{} = tree), do: Items.json(tree)

  @doc """
  Returns the JavaScript source of `VisualizeItems`, the hit index's reader (spec/10
  §12.5), which the bundle defines before `TooltipHook` and does not export.
  """
  def js_items do
    ~S"""
    const VisualizeItems = {
      // The index on a hook's element, parsed once per value it holds and kept on `cache`
      // (the hook, or any object with `el`); [] without one.
      read(cache) {
        const raw = cache.el.dataset.visItems || null;
        if (raw !== cache.itemsRaw) {
          cache.itemsRaw = raw;
          cache.items = raw ? JSON.parse(raw) : [];
        }
        return cache.items;
      },

      // A client point in the chart's units, through the chart's canvas (or SVG) and the
      // hook element's data-size; null outside the chart's rectangle.
      point(el, clientX, clientY) {
        if (typeof clientX !== 'number' || typeof clientY !== 'number') return null;
        const chart = el.querySelector('canvas') || el.querySelector('svg') || el;
        const rect = chart.getBoundingClientRect();
        if (!(rect.width > 0) || !(rect.height > 0)) return null;
        const size = el.dataset.size ? el.dataset.size.split(',').map(parseFloat) : [rect.width, rect.height];
        const x = (clientX - rect.left) * size[0] / rect.width;
        const y = (clientY - rect.top) * size[1] / rect.height;
        if (x < 0 || y < 0 || x > size[0] || y > size[1]) return null;
        return { x, y };
      },

      // The key under a pointer event, inside the tooltip's element `root`: the datum
      // element's on an SVG (spec/10 §12.3); on a canvas, which draws none, the topmost item
      // of the hit index (12.5, D-197), `cache` keeping the parsed index. null for a pointer
      // over nothing keyed, or over a datum of a mark without an event.
      // `kind` is 'click' (the default) for the mark's event, 'context' for its context
      // event (D-199): the key is named by it, and is null for a mark that declares none.
      key(root, cache, e, kind) {
        const context = kind === 'context';
        const target = e.target;
        const el = target && target.closest ? target.closest('[data-datum]') : null;
        if (el && root.contains(el)) {
          const event = this.nearest(root, el, context ? 'data-tooltip-context-event' : 'data-tooltip-event');
          const mark = this.nearest(root, el, 'data-mark');
          const row = el.getAttribute('data-row');
          if (!event || mark === null || row === null) return null;
          return { event, frame: this.nearest(root, el, 'data-frame'), mark: parseInt(mark, 10),
                   row: parseInt(row, 10), at: this.svgPoint(el, e) };
        }
        cache.el = root;
        const items = this.read(cache);
        if (items.length === 0) return null;
        const at = this.point(root, e.clientX, e.clientY);
        const hit = at && this.hit(items, at.x, at.y);
        const event = hit && (context ? hit.context : hit.event);
        return event ? { event, frame: hit.frame, mark: hit.mark, row: hit.row, at } : null;
      },

      // The nearest attribute on an element or an ancestor, searched no further than root.
      nearest(root, el, attribute) {
        for (let node = el; node; node = node.parentElement) {
          if (node.hasAttribute(attribute)) return node.getAttribute(attribute);
          if (node === root) return null;
        }
        return null;
      },

      // The pointer in the user units of the element's nearest <svg>, null without one.
      svgPoint(el, e) {
        const svg = el.closest('svg');
        if (!svg || typeof e.clientX !== 'number' || typeof e.clientY !== 'number') return null;
        const pt = svg.createSVGPoint();
        pt.x = e.clientX;
        pt.y = e.clientY;
        const p = pt.matrixTransform(svg.getScreenCTM().inverse());
        return { x: p.x, y: p.y };
      },

      // One wire event for a key, `visualize_event`: the key's event name, frame, mark and
      // row, the drawing's token on `root`, the point and the keys held; pushed by `hook`
      // to the component root's data-tooltip-target names, else to the LiveView (D-161).
      send(hook, root, key, e) {
        const payload = {
          event: key.event,
          frame: key.frame,
          mark: key.mark,
          row: key.row,
          drawn: root.dataset.tooltipDrawn || null,
          at: key.at,
          modifiers: ['shift', 'alt', 'ctrl', 'meta'].filter((name) => e && e[name + 'Key'])
        };
        const target = root.dataset.tooltipTarget;
        if (target) hook.pushEventTo(target, 'visualize_event', payload);
        else hook.pushEvent('visualize_event', payload);
      },

      // The topmost item under a point: the last drawn whose shape holds it, as `{event,
      // context, frame, mark, row}`; null for none.
      hit(items, x, y) {
        for (let e = items.length - 1; e >= 0; e--) {
          const entry = items[e];
          for (let i = entry.items.length - 1; i >= 0; i--) {
            if (this.holds(entry.items[i], x, y)) {
              return { event: entry.event, context: entry.context, frame: entry.frame, mark: entry.mark, row: entry.items[i][0] };
            }
          }
        }
        return null;
      },

      holds(item, x, y) {
        switch (item[1]) {
          case 'r': return x >= item[2] && x <= item[2] + item[4] && y >= item[3] && y <= item[3] + item[5];
          case 'c': return (x - item[2]) ** 2 + (y - item[3]) ** 2 <= item[4] ** 2;
          case 'p': {
            if (x < item[2] || x > item[2] + item[4] || y < item[3] || y > item[3] + item[5]) return false;
            return this.inPath(item, x, y);
          }
          default: return false;
        }
      },

      // A path's own test where the browser has one: its fill and its stroke, through a
      // context of its own with the path's matrix; its box where it has none.
      inPath(item, x, y) {
        if (typeof Path2D !== 'function') return true;
        if (!this.ctx) this.ctx = document.createElement('canvas').getContext('2d');
        const ctx = this.ctx;
        const path = new Path2D(item[6]);
        ctx.setTransform(...item[7]);
        ctx.lineWidth = item[9] || 0;
        const hit = (item[8] === 1 && ctx.isPointInPath(path, x, y)) ||
          (item[9] > 0 && ctx.isPointInStroke(path, x, y));
        ctx.setTransform(1, 0, 0, 1, 0, 0);
        return hit;
      }
    };
    """
  end

  @doc """
  Returns the JavaScript source of `TooltipHook`.
  """
  def js_hook do
    """
    export const TooltipHook = {
      mounted() {
        this.tip = document.createElement('div');
        this.tip.className = this.el.dataset.tooltipClass || 'vis-tooltip';
        this.tip.style.position = 'absolute';
        this.tip.style.pointerEvents = 'none';
        this.tip.style.whiteSpace = 'pre';
        this.tip.style.display = 'none';
        document.body.appendChild(this.tip);
        this.outline = null;
        this.readHover();

        // Each handler is bound once and kept on the hook, so destroyed() removes the
        // same references it added; onSync is the sync bus's listener (spec/10 §4.3).
        this.onMouseMove = this.handleMouseMove.bind(this);
        this.onMouseLeave = this.leave.bind(this);
        this.onTouchMove = this.handleTouchMove.bind(this);
        this.onTouchEnd = this.handleTouchEnd.bind(this);
        // A secondary gesture (spec/10 §12.3, D-199): a right-click, or a long-press.
        this.onContextMenu = this.handleContextMenu.bind(this);
        this.onTouchStart = this.handleTouchStart.bind(this);
        this.onTouchCancel = this.cancelPress.bind(this);
        this.press = null;
        this.pressedAt = null;
        this.onClick = this.handleClick.bind(this);
        this.onSync = this.handleSync.bind(this);
        VisualizeSync.attach(this);

        this.el.addEventListener('mousemove', this.onMouseMove);
        this.el.addEventListener('mouseleave', this.onMouseLeave);
        this.el.addEventListener('touchmove', this.onTouchMove, { passive: true });
        this.el.addEventListener('touchend', this.onTouchEnd);
        this.el.addEventListener('contextmenu', this.onContextMenu);
        this.el.addEventListener('touchstart', this.onTouchStart, { passive: true });
        this.el.addEventListener('touchcancel', this.onTouchCancel);
        this.el.addEventListener('click', this.onClick);
      },

      // The sync group and the hover's style are re-read after every patch.
      updated() {
        VisualizeSync.attach(this);
        this.readHover();
      },

      // The hover's style (spec/10 §4.4): with data-vis-hover the datum element shown is
      // outlined, the server's :hover laid over a 2-pixel currentColor rectangle; without
      // it nothing is drawn, as before. The overlay is made on the first style to draw.
      readHover() {
        const raw = this.el.dataset.visHover;
        this.hover = raw ? JSON.parse(raw) : null;
        if (!this.hover) {
          if (this.outline) this.outline.style.display = 'none';
          return;
        }
        if (!this.outline) {
          const ns = 'http://www.w3.org/2000/svg';
          this.outline = document.createElementNS(ns, 'svg');
          this.outline.setAttribute('class', 'vis-tooltip-hover');
          Object.assign(this.outline.style, {
            position: 'absolute', pointerEvents: 'none', overflow: 'visible', display: 'none'
          });
          this.outlineRect = document.createElementNS(ns, 'rect');
          this.outline.appendChild(this.outlineRect);
          document.body.appendChild(this.outline);
        }
        const style = Object.assign({ fill: 'none', stroke: 'currentColor', 'stroke-width': '2' }, this.hover);
        (this.outlined || []).forEach((name) => this.outlineRect.removeAttribute(name));
        this.outlined = Object.keys(style);
        this.outlined.forEach((name) => this.outlineRect.setAttribute(name, style[name]));
      },

      // The outline around a datum element's bounding rectangle, in page coordinates, padded
      // by its stroke width and 2 pixels so it surrounds the element rather than covering it.
      outlineAt(el) {
        if (!this.hover || !this.outline) return;
        const box = el.getBoundingClientRect();
        const pad = 2 + (parseFloat(this.outlineRect.getAttribute('stroke-width')) || 0);
        Object.assign(this.outline.style, {
          left: (box.left + window.scrollX - pad) + 'px',
          top: (box.top + window.scrollY - pad) + 'px',
          width: (box.width + 2 * pad) + 'px',
          height: (box.height + 2 * pad) + 'px',
          display: 'block'
        });
        this.outlineRect.setAttribute('x', pad);
        this.outlineRect.setAttribute('y', pad);
        this.outlineRect.setAttribute('width', box.width);
        this.outlineRect.setAttribute('height', box.height);
      },

      // The datum element: the target's nearest ancestor-or-self carrying data-datum,
      // inside the hook element; null when nothing under the pointer carries one.
      datumElement(target) {
        if (!target || !target.closest) return null;
        const el = target.closest('[data-datum]');
        return el && this.el.contains(el) ? el : null;
      },

      // A datum element the tooltip shows: not one under data-tooltip-show="false", whose
      // mark takes clicks with nothing under the pointer (spec/10 §12.3, D-200).
      shown(el) {
        return this.nearest(el, 'data-tooltip-show') !== 'false';
      },

      // The field names in the server's order and each one's attribute value, '' when
      // the value was nil and the attribute absent.
      fields(el) {
        const names = (el.getAttribute('data-datum') || '').split(' ').filter((n) => n !== '');
        const values = {};
        names.forEach((name) => {
          const value = el.getAttribute('data-datum-' + name.replace(/_/g, '-'));
          values[name] = value === null ? '' : value;
        });
        return { names, values };
      },

      // The nearest attribute on the datum element or an ancestor, searched no further
      // than the hook element.
      nearest(el, attribute) {
        for (let node = el; node; node = node.parentElement) {
          if (node.hasAttribute(attribute)) return node.getAttribute(attribute);
          if (node === this.el) return null;
        }
        return null;
      },

      text(el) {
        const { names, values } = this.fields(el);
        const template = this.nearest(el, 'data-tooltip-template');
        if (template !== null) {
          return template.replace(/\\{([^}]+)\\}/g, (_, name) => (name in values ? values[name] : ''));
        }
        return names.map((name) => name + ': ' + values[name]).join('\\n');
      },

      handleMouseMove(e) {
        this.show(e.target, e.pageX, e.pageY);
        this.publish(e.clientX);
      },

      // A touch event's target is where the touch began, so the element under the
      // finger is looked up by position.
      handleTouchMove(e) {
        if (this.press && (e.touches.length !== 1 ||
            Math.hypot(e.touches[0].clientX - this.press.x, e.touches[0].clientY - this.press.y) > 10)) {
          this.cancelPress();
        }
        if (e.touches.length !== 1) return;
        const touch = e.touches[0];
        this.show(document.elementFromPoint(touch.clientX, touch.clientY), touch.pageX, touch.pageY);
        this.publish(touch.clientX);
      },

      // In a sync group, the pointer's x in domain units on the group's bus (spec/10 §4.3).
      publish(clientX) {
        if (!this.sync) return;
        const rect = this.el.getBoundingClientRect();
        const chartX = (clientX - rect.left) * this.sync.width / rect.width;
        VisualizeSync.publish(this.sync, this.el, VisualizeSync.toDomain(this.sync, chartX));
        this.publishing = true;
      },

      // The pointer left: hidden here and, once after a hover this chart published, cleared
      // on every member of the group.
      leave() {
        this.hide();
        if (this.sync && this.publishing) VisualizeSync.publish(this.sync, this.el, null);
        this.publishing = false;
      },

      // Another member's hover (spec/10 §12.4): the datum element whose center is nearest
      // the value's x through this chart's own mapping; hidden for a clear, a value outside
      // the domain, or a chart with no datum element.
      handleSync(e) {
        if (VisualizeSync.own(this.el, e.detail.source)) return;
        this.syncTo(e.detail.x);
      },

      syncTo(value) {
        const chartX = this.sync ? VisualizeSync.toChart(this.sync, value) : null;
        if (chartX === null) {
          this.hide();
          return;
        }
        const rect = this.el.getBoundingClientRect();
        const clientX = rect.left + chartX * rect.width / this.sync.width;
        let best = null;
        let bestDistance = Infinity;
        let bestBox = null;
        this.el.querySelectorAll('[data-datum]').forEach((el) => {
          if (!this.shown(el)) return;
          const box = el.getBoundingClientRect();
          const distance = Math.abs(box.left + box.width / 2 - clientX);
          if (distance < bestDistance) {
            best = el;
            bestDistance = distance;
            bestBox = box;
          }
        });
        if (!best) {
          this.hide();
          return;
        }
        this.place(best, bestBox.left + bestBox.width / 2 + window.scrollX, bestBox.top + window.scrollY);
      },

      show(target, pageX, pageY) {
        const el = this.datumElement(target);
        if (!el || !this.shown(el)) {
          this.hide();
          return;
        }
        this.place(el, pageX, pageY);
      },

      // The tooltip with the datum element's text, beside a page position.
      place(el, pageX, pageY) {
        this.tip.textContent = this.text(el);
        this.tip.style.display = 'block';
        const width = this.tip.offsetWidth;
        const height = this.tip.offsetHeight;
        const right = window.scrollX + document.documentElement.clientWidth;
        const bottom = window.scrollY + document.documentElement.clientHeight;
        const x = pageX + 12 + width > right ? pageX - 12 - width : pageX + 12;
        const y = pageY + 12 + height > bottom ? pageY - 12 - height : pageY + 12;
        this.tip.style.left = x + 'px';
        this.tip.style.top = y + 'px';
        this.outlineAt(el);
      },

      hide() {
        this.tip.style.display = 'none';
        if (this.outline) this.outline.style.display = 'none';
      },

      // A click on a keyed datum of a mark with an event (spec/10 §12.3, D-170): one wire
      // event with the element's key, the drawing's token, the pointer and the modifiers,
      // never the datum's strings; the server resolves the row.
      handleClick(e) {
        if (this.swallowed(e)) return;
        const key = this.keyAt(e);
        if (key) this.send(key, e);
      },

      // A right-click on an item whose mark declares a context event: that event, and no
      // browser menu; over anything else the menu is the browser's (spec/10 §12.3, D-199).
      handleContextMenu(e) {
        if (this.swallowed(e)) return;
        const key = VisualizeItems.key(this.el, this, e, 'context');
        if (!key) return;
        e.preventDefault();
        this.send(key, e);
      },

      // A long-press: one touch held 500 ms within 10 pixels of where it began.
      handleTouchStart(e) {
        this.cancelPress();
        if (!e.touches || e.touches.length !== 1) return;
        const touch = e.touches[0];
        this.press = { x: touch.clientX, y: touch.clientY, timer: setTimeout(() => this.longPress(), 500) };
      },

      handleTouchEnd() {
        this.cancelPress();
        this.leave();
      },

      cancelPress() {
        if (this.press) clearTimeout(this.press.timer);
        this.press = null;
      },

      // The press held: the context event of the item under it, as a right-click there.
      longPress() {
        const press = this.press;
        this.press = null;
        if (!press) return;
        const target = typeof document.elementFromPoint === 'function' ?
          document.elementFromPoint(press.x, press.y) : null;
        const at = { target, clientX: press.x, clientY: press.y };
        const key = VisualizeItems.key(this.el, this, at, 'context');
        if (!key) return;
        this.pressedAt = performance.now();
        this.send(key, at);
      },

      // The click and the menu a browser fires after a long-press are the press's own.
      swallowed(e) {
        if (this.pressedAt === null || performance.now() - this.pressedAt > 800) return false;
        if (e.preventDefault) e.preventDefault();
        return true;
      },

      // The key under a pointer event (spec/10 §12.3, §12.5): VisualizeItems.key/3.
      keyAt(e) {
        return VisualizeItems.key(this.el, this, e);
      },

      // One wire event for a key, to this hook's holder (D-161, D-170).
      send(key, e) {
        VisualizeItems.send(this, this.el, key, e);
      },

      destroyed() {
        this.el.removeEventListener('mousemove', this.onMouseMove);
        this.el.removeEventListener('mouseleave', this.onMouseLeave);
        this.el.removeEventListener('touchmove', this.onTouchMove);
        this.el.removeEventListener('touchend', this.onTouchEnd);
        this.el.removeEventListener('click', this.onClick);
        this.el.removeEventListener('contextmenu', this.onContextMenu);
        this.el.removeEventListener('touchstart', this.onTouchStart);
        this.el.removeEventListener('touchcancel', this.onTouchCancel);
        this.cancelPress();
        VisualizeSync.detach(this);
        if (this.tip.parentNode) this.tip.parentNode.removeChild(this.tip);
        if (this.outline && this.outline.parentNode) this.outline.parentNode.removeChild(this.outline);
      }
    };
    """
  end
end
