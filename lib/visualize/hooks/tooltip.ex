defmodule Visualize.Hooks.Tooltip do
  @moduledoc """
  Phoenix LiveView hook that shows a datum's fields under the pointer (spec/10 §12).

  `TooltipHook` needs no round trip: the server writes each datum's fields onto the element
  that draws it — `Visualize.IR.Element.datum/2`, or a mark's `tooltip` node
  (spec/14 §5.7) — and the hook reads them from the element under the pointer (D-75). A
  `data-tooltip-template` on the element or an ancestor formats the text with `{field}`
  placeholders; without one the tooltip lists `field: value` per line. A click pushes the
  fields to the LiveView only when a `data-tooltip-event` names the event.

  ## Usage

      <svg id="chart" phx-hook="TooltipHook">
        <g class="mark mark-circle" data-tooltip-template="{t}: {v}" data-tooltip-event="point_click">
          <circle cx="10" cy="20" r="3" data-datum="t v" data-datum-t="1" data-datum-v="4"/>
        </g>
      </svg>

      def handle_event("point_click", %{"t" => t, "v" => v}, socket) do
        {:noreply, assign(socket, picked: {t, v})}
      end

  ## Configuration

  Data attributes on the hook element:
  - `data-tooltip-class` - class of the tooltip element the hook creates
    (default: "vis-tooltip")

  Data attributes on the elements, written by the server (spec/10 §12.2):
  - `data-datum` - the field names, space-separated, in order
  - `data-datum-<field>` - the value of each field, `_` in the name as `-`
  - `data-tooltip-template` - the text with `{field}` placeholders; the nearest wins
  - `data-tooltip-event` - the event a click pushes; absent, nothing is pushed
  """

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

        // Each handler is bound once and kept on the hook, so destroyed() removes the
        // same references it added.
        this.onMouseMove = this.handleMouseMove.bind(this);
        this.onMouseLeave = this.hide.bind(this);
        this.onTouchMove = this.handleTouchMove.bind(this);
        this.onTouchEnd = this.hide.bind(this);
        this.onClick = this.handleClick.bind(this);

        this.el.addEventListener('mousemove', this.onMouseMove);
        this.el.addEventListener('mouseleave', this.onMouseLeave);
        this.el.addEventListener('touchmove', this.onTouchMove, { passive: true });
        this.el.addEventListener('touchend', this.onTouchEnd);
        this.el.addEventListener('click', this.onClick);
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
      },

      // A touch event's target is where the touch began, so the element under the
      // finger is looked up by position.
      handleTouchMove(e) {
        if (e.touches.length !== 1) return;
        const touch = e.touches[0];
        this.show(document.elementFromPoint(touch.clientX, touch.clientY), touch.pageX, touch.pageY);
      },

      show(target, pageX, pageY) {
        const el = this.datumElement(target);
        if (!el) {
          this.hide();
          return;
        }
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
      },

      hide() {
        this.tip.style.display = 'none';
      },

      handleClick(e) {
        const el = this.datumElement(e.target);
        if (!el) return;
        const event = this.nearest(el, 'data-tooltip-event');
        if (!event) return;
        this.pushEvent(event, this.fields(el).values);
      },

      destroyed() {
        this.el.removeEventListener('mousemove', this.onMouseMove);
        this.el.removeEventListener('mouseleave', this.onMouseLeave);
        this.el.removeEventListener('touchmove', this.onTouchMove);
        this.el.removeEventListener('touchend', this.onTouchEnd);
        this.el.removeEventListener('click', this.onClick);
        if (this.tip.parentNode) this.tip.parentNode.removeChild(this.tip);
      }
    };
    """
  end
end
