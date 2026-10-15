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
  - `data-frame`, `data-mark` - on a mark's group with an event: its frame and position
  - `data-row` - on each datum element of such a mark: the row's ordinal in its rows
  """

  alias Visualize.Chart.Frame
  alias Visualize.Hooks.States

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
        this.onTouchEnd = this.leave.bind(this);
        this.onClick = this.handleClick.bind(this);
        this.onSync = this.handleSync.bind(this);
        VisualizeSync.attach(this);

        this.el.addEventListener('mousemove', this.onMouseMove);
        this.el.addEventListener('mouseleave', this.onMouseLeave);
        this.el.addEventListener('touchmove', this.onTouchMove, { passive: true });
        this.el.addEventListener('touchend', this.onTouchEnd);
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
        if (!el) {
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
        const el = this.datumElement(e.target);
        if (!el) return;
        const event = this.nearest(el, 'data-tooltip-event');
        if (!event) return;
        const mark = this.nearest(el, 'data-mark');
        const row = el.getAttribute('data-row');
        if (mark === null || row === null) return;
        const payload = {
          event: event,
          frame: this.nearest(el, 'data-frame'),
          mark: parseInt(mark, 10),
          row: parseInt(row, 10),
          drawn: this.el.dataset.tooltipDrawn || null,
          at: this.at(el, e),
          modifiers: ['shift', 'alt', 'ctrl', 'meta'].filter((key) => e[key + 'Key'])
        };
        // To the component data-tooltip-target names, else to the LiveView (D-161).
        const target = this.el.dataset.tooltipTarget;
        if (target) this.pushEventTo(target, 'visualize_event', payload);
        else this.pushEvent('visualize_event', payload);
      },

      // The pointer in the user units of the element's nearest <svg>, null without one.
      at(el, e) {
        const svg = el.closest('svg');
        if (!svg || typeof e.clientX !== 'number' || typeof e.clientY !== 'number') return null;
        const pt = svg.createSVGPoint();
        pt.x = e.clientX;
        pt.y = e.clientY;
        const p = pt.matrixTransform(svg.getScreenCTM().inverse());
        return { x: p.x, y: p.y };
      },

      destroyed() {
        this.el.removeEventListener('mousemove', this.onMouseMove);
        this.el.removeEventListener('mouseleave', this.onMouseLeave);
        this.el.removeEventListener('touchmove', this.onTouchMove);
        this.el.removeEventListener('touchend', this.onTouchEnd);
        this.el.removeEventListener('click', this.onClick);
        VisualizeSync.detach(this);
        if (this.tip.parentNode) this.tip.parentNode.removeChild(this.tip);
        if (this.outline && this.outline.parentNode) this.outline.parentNode.removeChild(this.outline);
      }
    };
    """
  end
end
