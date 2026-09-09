defmodule Visualize.Hooks.Builder do
  @moduledoc """
  Phoenix LiveView hook for the chart builder's two browser gestures (spec/10 §16).

  `BuilderHook` serves the stack panel and the inspector of `Visualize.Chart.Builder`
  (spec/14 §18) and does the two things the browser knows something about and the server
  does not: where a dragged layer was dropped, and which inspector row was clicked. It moves
  nothing itself — the server owns the layer list and the next render is the move — and it
  pushes through `pushEventTo` when `data-builder-target` names the component, so the events
  reach the builder and not its host (D-87).

  The hook ships in the bundle whether or not the host has the builder: the JavaScript is a
  string, and only the builder's Elixir is behind the `Phoenix.Component` guard.

  ## Usage

      <ol id="layers" phx-hook="BuilderHook" data-builder-target={@myself}>
        <li data-builder-layer="0" draggable="true">…</li>
      </ol>

  ## Configuration

  Data attributes (spec/10 §16.2):
  - `data-builder-target` on the hook element - the `phx-target` the hook pushes to;
    absent, it pushes to the LiveView
  - `data-builder-layer` on a layer and on an inspector row - the layer's zero-based
    position
  - `data-builder-path` on an inspector row - the entry's path, as
    `Visualize.Chart.Validator.format/1` spells one

  ## Events

  - `reorder` with `%{"from" => integer, "to" => integer}` on a drop between two positions
  - `inspect` with `%{"path" => string, "layer" => string}` on a click on a row
  """

  @doc """
  Returns the JavaScript source of `BuilderHook`.
  """
  def js_hook do
    """
    export const BuilderHook = {
      mounted() {
        this.target = this.el.dataset.builderTarget || null;
        this.from = null;
        this.onDragStart = this.handleDragStart.bind(this);
        this.onDragOver = this.handleDragOver.bind(this);
        this.onDrop = this.handleDrop.bind(this);
        this.onDragEnd = this.handleDragEnd.bind(this);
        this.onClick = this.handleClick.bind(this);
        this.el.addEventListener('dragstart', this.onDragStart);
        this.el.addEventListener('dragover', this.onDragOver);
        this.el.addEventListener('drop', this.onDrop);
        this.el.addEventListener('dragend', this.onDragEnd);
        this.el.addEventListener('click', this.onClick);
      },

      // The element under the pointer that carries a layer position, or null.
      layerAt(e) {
        if (!e.target || !e.target.closest) return null;
        const layer = e.target.closest('[data-builder-layer]');
        return layer && this.el.contains(layer) ? layer : null;
      },

      position(layer) {
        return parseInt(layer.getAttribute('data-builder-layer'), 10);
      },

      push(event, payload) {
        if (this.target) this.pushEventTo(this.target, event, payload);
        else this.pushEvent(event, payload);
      },

      // A drag carries what was picked up, so a drop anywhere can tell a move of a layer
      // from an insert of a library fragment. dataTransfer is how the two hook instances —
      // the library's and the stack's — hear about each other.
      handleDragStart(e) {
        const fragment = this.fragmentAt(e);
        if (fragment) {
          const stored = fragment.getAttribute('data-builder-fragment');
          this.from = null;
          if (e.dataTransfer) {
            e.dataTransfer.effectAllowed = 'copy';
            e.dataTransfer.setData('application/x-visualize-fragment', stored);
            e.dataTransfer.setData('text/plain', stored);
          }
          fragment.classList.add('vis-builder-item-dragging');
          return;
        }

        const layer = this.layerAt(e);
        if (!layer) return;
        this.from = this.position(layer);
        if (e.dataTransfer) {
          e.dataTransfer.effectAllowed = 'move';
          e.dataTransfer.setData('text/plain', String(this.from));
        }
        layer.classList.add('vis-builder-layer-dragging');
      },

      // The element under the pointer that carries a library name, or null.
      fragmentAt(e) {
        if (!e.target || !e.target.closest) return null;
        const item = e.target.closest('[data-builder-fragment]');
        return item && this.el.contains(item) ? item : null;
      },

      dragged(e) {
        if (!e.dataTransfer) return null;
        const stored = e.dataTransfer.getData('application/x-visualize-fragment');
        return stored === '' ? null : stored;
      },

      // Without preventDefault the browser refuses the drop. A drag from the library is
      // accepted anywhere in the stack, including its empty space, which is what makes
      // dropping at the end possible.
      handleDragOver(e) {
        if (!this.accepts(e)) return;
        e.preventDefault();
        this.clearOver();
        const layer = this.layerAt(e);
        if (layer) layer.classList.add('vis-builder-layer-over');
      },

      accepts(e) {
        if (!this.el.hasAttribute('data-builder-stack')) return false;
        if (this.from !== null) return this.layerAt(e) !== null;
        return e.dataTransfer && Array.from(e.dataTransfer.types || [])
          .includes('application/x-visualize-fragment');
      },

      handleDrop(e) {
        if (!this.accepts(e)) return;
        e.preventDefault();
        this.clearOver();

        const layer = this.layerAt(e);

        // A move within the stack.
        if (this.from !== null) {
          if (!layer) return;
          const to = this.position(layer);
          if (to !== this.from) this.push('reorder', { from: this.from, to: to });
          return;
        }

        // An insert from the library: before the layer dropped on, or at the end when the
        // drop landed in the stack's empty space.
        const stored = this.dragged(e);
        if (stored === null) return;
        const at = layer ? this.dropIndex(e, layer) : this.count();
        this.push('insert', { name: stored, at: at });
      },

      // Which side of the layer the pointer is on, so a fragment can be put above or below
      // the one it was dropped over rather than always before it.
      dropIndex(e, layer) {
        const box = layer.getBoundingClientRect();
        const below = e.clientY > box.top + box.height / 2;
        return this.position(layer) + (below ? 1 : 0);
      },

      count() {
        return this.el.querySelectorAll('[data-builder-layer]').length;
      },

      // A drag that ended anywhere leaves no marks, dropped or not.
      handleDragEnd() {
        this.from = null;
        this.clearOver();
        this.el.querySelectorAll('.vis-builder-layer-dragging, .vis-builder-item-dragging')
          .forEach((node) => {
            node.classList.remove('vis-builder-layer-dragging');
            node.classList.remove('vis-builder-item-dragging');
          });
      },

      clearOver() {
        this.el.querySelectorAll('.vis-builder-layer-over').forEach((node) => {
          node.classList.remove('vis-builder-layer-over');
        });
      },

      // The highlight is the browser's: it needs no round trip. The selection is the
      // server's: it changes what the editor edits.
      handleClick(e) {
        if (!e.target || !e.target.closest) return;
        const row = e.target.closest('[data-builder-path]');
        if (!row || !this.el.contains(row)) return;
        this.el.querySelectorAll('.vis-builder-entry-open').forEach((node) => {
          node.classList.remove('vis-builder-entry-open');
        });
        row.classList.add('vis-builder-entry-open');
        this.push('inspect', {
          path: row.getAttribute('data-builder-path'),
          layer: row.getAttribute('data-builder-layer')
        });
      },

      destroyed() {
        this.el.removeEventListener('dragstart', this.onDragStart);
        this.el.removeEventListener('dragover', this.onDragOver);
        this.el.removeEventListener('drop', this.onDrop);
        this.el.removeEventListener('dragend', this.onDragEnd);
        this.el.removeEventListener('click', this.onClick);
      }
    };
    """
  end
end
