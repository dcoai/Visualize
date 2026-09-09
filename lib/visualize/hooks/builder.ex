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

      handleDragStart(e) {
        const layer = this.layerAt(e);
        if (!layer) return;
        this.from = this.position(layer);
        layer.classList.add('vis-builder-layer-dragging');
      },

      // Without preventDefault the browser refuses the drop.
      handleDragOver(e) {
        const layer = this.layerAt(e);
        if (this.from === null || !layer) return;
        e.preventDefault();
        this.clearOver();
        layer.classList.add('vis-builder-layer-over');
      },

      handleDrop(e) {
        const layer = this.layerAt(e);
        if (this.from === null || !layer) return;
        e.preventDefault();
        const to = this.position(layer);
        if (to !== this.from) this.push('reorder', { from: this.from, to: to });
      },

      // A drag that ended anywhere leaves no marks, dropped or not.
      handleDragEnd() {
        this.from = null;
        this.clearOver();
        this.el.querySelectorAll('.vis-builder-layer-dragging').forEach((node) => {
          node.classList.remove('vis-builder-layer-dragging');
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
