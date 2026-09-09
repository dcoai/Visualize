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
        // Says the hook is registered AND attached to this element. Without it, a hook that
        // never loaded and a hook that loaded but does nothing look identical from outside.
        this.el.setAttribute('data-builder-mounted', 'true');
        this.target = this.el.dataset.builderTarget || null;
        this.from = null;
        this.onDragStart = this.handleDragStart.bind(this);
        this.onDragOver = this.handleDragOver.bind(this);
        this.onDrop = this.handleDrop.bind(this);
        this.onDragEnd = this.handleDragEnd.bind(this);
        this.onDragLeave = this.handleDragLeave.bind(this);
        this.onClick = this.handleClick.bind(this);
        this.el.addEventListener('dragstart', this.onDragStart);
        this.el.addEventListener('dragover', this.onDragOver);
        this.el.addEventListener('drop', this.onDrop);
        this.el.addEventListener('dragend', this.onDragEnd);
        this.el.addEventListener('dragleave', this.onDragLeave);
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

      // Without preventDefault the browser refuses the drop. The whole stack accepts, not
      // just its rows: the space above the first layer and below the last is how the ends
      // are reached, and requiring the pointer to be over a row made them unreachable.
      handleDragOver(e) {
        if (!this.accepts(e)) return;
        e.preventDefault();
        if (e.dataTransfer) e.dataTransfer.dropEffect = this.from === null ? 'copy' : 'move';
        this.markPoint(this.insertionPoint(e));
      },

      // A drag that leaves the stack leaves no mark behind. dragend fires on the source,
      // which for a library drag is in another element entirely, so the stack must clear
      // its own.
      handleDragLeave(e) {
        if (e.relatedTarget && this.el.contains(e.relatedTarget)) return;
        this.clearOver();
      },

      accepts(e) {
        if (!this.el.hasAttribute('data-builder-stack')) return false;
        if (this.from !== null) return true;
        return e.dataTransfer && Array.from(e.dataTransfer.types || [])
          .includes('application/x-visualize-fragment');
      },

      // Where the drop lands, as a position BETWEEN layers: 0 above the first, n below the
      // last. One rule for both drags, and the only one that can name either end — the
      // pointer is compared with each row's midpoint, so there is no row it must be inside.
      insertionPoint(e) {
        const layers = this.layers();
        for (let i = 0; i < layers.length; i++) {
          const box = layers[i].getBoundingClientRect();
          if (e.clientY < box.top + box.height / 2) return i;
        }
        return layers.length;
      },

      layers() {
        return Array.from(this.el.querySelectorAll('[data-builder-layer]'));
      },

      handleDrop(e) {
        if (!this.accepts(e)) return;
        e.preventDefault();
        this.clearOver();

        const at = this.insertionPoint(e);

        // A move within the stack. `at` is a gap in the list as it stands; once the dragged
        // layer is lifted out, every gap after it shifts down by one.
        if (this.from !== null) {
          const to = at > this.from ? at - 1 : at;
          if (to !== this.from) this.push('reorder', { from: this.from, to: to });
          return;
        }

        const stored = this.dragged(e);
        if (stored === null) return;
        this.push('insert', { name: stored, at: at });
      },

      // The gap the drop would land in, drawn on the row below it, or under the last row
      // when the gap is the end.
      markPoint(at) {
        this.clearOver();
        const layers = this.layers();
        if (layers.length === 0) return;

        if (at >= layers.length) {
          layers[layers.length - 1].classList.add('vis-builder-layer-over-end');
        } else {
          layers[at].classList.add('vis-builder-layer-over');
        }
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
        this.el.querySelectorAll('.vis-builder-layer-over, .vis-builder-layer-over-end')
          .forEach((node) => {
            node.classList.remove('vis-builder-layer-over');
            node.classList.remove('vis-builder-layer-over-end');
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
        this.el.removeEventListener('dragleave', this.onDragLeave);
        this.el.removeEventListener('click', this.onClick);
      }
    };
    """
  end
end
