defmodule Visualize.Hooks.Board do
  @moduledoc """
  Phoenix LiveView hook for a live board's container (spec/10 §18, spec/15 §9, D-146).

  `BoardHook` does two things for `Visualize.Components.Board`:

  - **The width.** It pushes the container's width once it has held for the debounce
    period, and on mount, so the board process draws its cells at their boxes and the grid
    reflows below the board's breakpoint (spec/15 §1.6). The push goes to the component
    that rendered the container (`pushEventTo`), so the host's LiveView handles nothing.
  - **The order across cells** (spec/14 §21.5). Each cell, an element carrying
    `data-vis-cell`, is one tab stop. With focus on a cell the arrow keys move to the next
    and the previous cell in reading order — the order the cells are rendered in — and
    Home and End to the first and the last; Enter moves focus into the cell's chart, its
    first descendant with a `tabindex`. A key pressed inside a chart is the chart's: the
    hook acts only on a key whose target is the cell itself. Escape inside a chart is
    `KeyboardHook`'s, which hands focus back to the cell.
  - **The selection** (spec/15 §13.2). While the container carries
    `data-board-selection`, an Escape anywhere in it — on a cell or inside a chart —
    pushes the clear event to the component, so one Escape inside a chart both returns
    focus to the cell and clears the board's selection.

  ## Usage

      <section id="ops" phx-hook="BoardHook" data-board-event="resize">
        <article data-vis-cell="latency" tabindex="0">…</article>
        <article data-vis-cell="errors" tabindex="0">…</article>
      </section>

  ## Configuration

  - `data-board-event` - the event pushed with `{width}` (default: `"resize"`)
  - `data-board-debounce` - milliseconds the width must hold before it is pushed
    (default: 150)
  - `data-board-clear-event` - the event Escape pushes to clear the selection
    (default: "select_clear")
  - `data-board-selection` - set by the component while the board holds a selection
  """

  @doc "Returns the JavaScript source of `BoardHook`."
  def js_hook do
    """
    export const BoardHook = {
      mounted() {
        this.eventName = this.el.dataset.boardEvent || 'resize';
        this.debounce = parseInt(this.el.dataset.boardDebounce, 10) || 150;
        this.clearEvent = this.el.dataset.boardClearEvent || 'select_clear';
        this.timer = null;
        this.last = null;

        // Each handler is bound once and kept, so destroyed() removes the same references.
        this.onKeyDown = this.handleKeyDown.bind(this);
        this.el.addEventListener('keydown', this.onKeyDown);

        this.observer = typeof ResizeObserver === 'function'
          ? new ResizeObserver(() => this.measure()) : null;
        if (this.observer) this.observer.observe(this.el);
        this.push(this.width());
      },

      width() {
        return Math.round(this.el.getBoundingClientRect().width || this.el.offsetWidth || 0);
      },

      // A width observed; pushed once it has held for the debounce period.
      measure() {
        if (this.timer) clearTimeout(this.timer);
        this.timer = setTimeout(() => { this.timer = null; this.push(this.width()); }, this.debounce);
      },

      push(width) {
        if (!(width > 0) || width === this.last) return;
        this.last = width;
        this.pushEventTo(this.el, this.eventName, { width });
      },

      // The cells in reading order: the order they are rendered in.
      cells() {
        return Array.from(this.el.querySelectorAll('[data-vis-cell]'));
      },

      handleKeyDown(e) {
        // Escape anywhere in the board clears its selection; the chart's own hook still
        // hands focus back, so nothing is prevented (spec/10 §18.2).
        if (e.key === 'Escape' && this.el.hasAttribute('data-board-selection')) {
          this.pushEventTo(this.el, this.clearEvent, {});
        }
        const cell = e.target;
        if (!cell || !cell.hasAttribute || !cell.hasAttribute('data-vis-cell')) return;
        const cells = this.cells();
        const at = cells.indexOf(cell);
        if (at < 0) return;
        let next = null;
        switch (e.key) {
          case 'ArrowRight': case 'ArrowDown': next = cells[Math.min(at + 1, cells.length - 1)]; break;
          case 'ArrowLeft': case 'ArrowUp': next = cells[Math.max(at - 1, 0)]; break;
          case 'Home': next = cells[0]; break;
          case 'End': next = cells[cells.length - 1]; break;
          case 'Enter': next = cell.querySelector('[tabindex]'); break;
          default: return;
        }
        e.preventDefault();
        if (next && next !== cell && next.focus) next.focus();
      },

      destroyed() {
        this.el.removeEventListener('keydown', this.onKeyDown);
        if (this.observer) this.observer.disconnect();
        if (this.timer) clearTimeout(this.timer);
      }
    };
    """
  end
end
