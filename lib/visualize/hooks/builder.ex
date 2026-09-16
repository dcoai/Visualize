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
  - `drop_colour` with `%{"field" => string, "colour" => string, "edit" => string}` when a
    patch of the colour chooser is dropped on a colour well (spec/14 §19.10)
  - `context_width` with `%{"width" => integer}` when the inspector's edge is released
    after a drag (spec/14 §18.16)
  - `pick` with `%{"node" => string}` in scope `graph` when an element of the chart that
    carries `data-node` is clicked (spec/14 §18.16); the hook also outlines the drawn node
    whose path is the longest prefix of the `<svg>`'s `data-builder-selected`
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
        // Which list this instance is. The queries below are already scoped to this element,
        // so two stacks on a page never see each other; the component needs only to know
        // which one a reorder came from. Absent means the layer stack (spec/14 §18.18).
        this.scope = this.el.dataset.builderScope || null;
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
        // The scrubber's bar follows the dot while it is dragged (spec/14 §18.6); the
        // render sets it on every other change.
        this.onInput = this.handleInput.bind(this);
        this.el.addEventListener('input', this.onInput);
        // Focus follows a layer moved from the keyboard: the rows are re-rendered by
        // position, so the builder says which row to land on (spec/14 §18.17).
        // The pool list's chosen entry is scrolled into view (spec/14 §19.10).
        this.reveal();
        // The graph outlines the open node (spec/14 §18.16); the render carries its label.
        this.outline();
        // The inspector's edge (spec/14 §18.16): a drag on the handle reports the width
        // once the pointer is released; while it moves the column follows it.
        this.onPointerDown = this.handlePointerDown.bind(this);
        this.el.addEventListener('pointerdown', this.onPointerDown);
        this.handleEvent('vis:focus', ({ id }) => {
          const row = document.getElementById(id);
          if (row && this.el.contains(row)) row.focus();
        });
      },

      updated() {
        this.reveal();
        this.outline();
      },

      // In scope `graph`, the drawn node whose path is the longest prefix of the open
      // node's label — equal to it, or followed in it by `.` or `[` — is marked
      // `vis-builder-graph-selected` and every other element is not (spec/14 §18.16,
      // spec/10 §16.3). A facet frame draws one node several times; every copy is marked.
      outline() {
        if (this.scope !== 'graph') return;
        const svg = this.el.querySelector('svg[data-builder-selected]');
        const label = svg ? svg.getAttribute('data-builder-selected') : null;
        const nodes = Array.from(this.el.querySelectorAll('[data-node]'));
        let best = null;
        nodes.forEach((node) => {
          const path = node.getAttribute('data-node');
          const fits = label !== null && (label === path || label.startsWith(path + '.') || label.startsWith(path + '['));
          if (fits && (best === null || path.length > best.length)) best = path;
        });
        nodes.forEach((node) => {
          node.classList.toggle('vis-builder-graph-selected', best !== null && node.getAttribute('data-node') === best);
        });
      },

      handlePointerDown(e) {
        if (this.scope !== 'resize' || !e.target || !e.target.closest) return;
        const handle = e.target.closest('[data-builder-resize]');
        if (!handle || !this.el.contains(handle)) return;
        e.preventDefault();
        // The width is a custom property of the panels grid, which lays the columns out.
        const grid = this.el.closest('.vis-builder-panels') || this.el;
        const right = this.el.getBoundingClientRect().right;
        const move = (ev) => {
          const width = Math.max(300, Math.min(800, right - ev.clientX));
          grid.style.setProperty('--vis-builder-context', width + 'px');
        };
        const up = (ev) => {
          window.removeEventListener('pointermove', move);
          window.removeEventListener('pointerup', up);
          const width = Math.max(300, Math.min(800, Math.round(right - ev.clientX)));
          this.push('context_width', { width: width });
        };
        window.addEventListener('pointermove', move);
        window.addEventListener('pointerup', up);
      },

      reveal() {
        const chosen = this.el.querySelector('.vis-builder-pool-name-on');
        if (chosen && chosen.scrollIntoView) chosen.scrollIntoView({ block: 'nearest' });
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

      // A push from inside a node's form aims at that node (spec/14 §18.15).
      aimed(el, payload) {
        const form = el && el.closest ? el.closest('[data-builder-node]') : null;
        const node = form && form.getAttribute('data-builder-node');
        return node ? { ...payload, node: node } : payload;
      },

      push(event, payload) {
        const carried = this.scope ? { ...payload, scope: this.scope } : payload;
        if (this.target) this.pushEventTo(this.target, event, carried);
        else this.pushEvent(event, carried);
      },

      // A drag carries what was picked up, so a drop anywhere can tell a move of a layer
      // from an insert of a library fragment. dataTransfer is how the two hook instances —
      // the library's and the stack's — hear about each other.
      // A variable chip, or a field's promote handle, carries its name the same way a
      // library fragment does (spec/14 §19.9).
      carried(e, selector) {
        if (!e.target || !e.target.closest) return null;
        const el = e.target.closest(selector);
        return el && this.el.contains(el) ? el : null;
      },

      dragType(e) {
        const types = e.dataTransfer ? Array.from(e.dataTransfer.types || []) : [];
        if (types.includes('application/x-visualize-colour')) return 'colour';
        if (types.includes('application/x-visualize-variable')) return 'variable';
        if (types.includes('application/x-visualize-promote')) return 'promote';
        if (types.includes('application/x-visualize-fragment')) return 'fragment';
        return null;
      },

      handleDragStart(e) {
        // A patch of the colour chooser carries its colour — a slot's word or a hex — so
        // a well anywhere can take it (spec/14 §19.10).
        const patch = this.carried(e, '[data-builder-colour]');
        if (patch) {
          this.from = null;
          if (e.dataTransfer) {
            e.dataTransfer.effectAllowed = 'copy';
            e.dataTransfer.setData('application/x-visualize-colour', patch.getAttribute('data-builder-colour'));
            e.dataTransfer.setData('text/plain', patch.getAttribute('data-builder-colour'));
          }
          return;
        }

        const chip = this.carried(e, '[data-builder-variable]');
        if (chip) {
          this.from = null;
          if (e.dataTransfer) {
            e.dataTransfer.effectAllowed = 'copy';
            e.dataTransfer.setData('application/x-visualize-variable', chip.getAttribute('data-builder-variable'));
            e.dataTransfer.setData('text/plain', 'var(:' + chip.getAttribute('data-builder-variable') + ')');
          }
          return;
        }

        const handle = this.carried(e, '[data-builder-promote]');
        if (handle) {
          this.from = null;
          e.stopPropagation();
          if (e.dataTransfer) {
            e.dataTransfer.effectAllowed = 'copy';
            e.dataTransfer.setData('application/x-visualize-promote', handle.getAttribute('data-builder-promote'));
            e.dataTransfer.setData('text/plain', handle.getAttribute('data-builder-promote'));
          }
          return;
        }

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
      // A reference field takes a library entry of its kind: the drop is the field's write
      // (spec/14 §19.10). The builder refuses a wrong kind by name.
      fieldAt(e) {
        if (this.scope !== 'ref' || this.from !== null || this.dragType(e) !== 'fragment') return null;
        if (!e.target || !e.target.closest) return null;
        const field = e.target.closest('[data-builder-ref]');
        return field && this.el.contains(field) ? field : null;
      },

      // Where a chip may land: a field row (bind it), a strip tab (bind the first key of
      // that root), the create area (promote a field's value). Marked while over.
      chipTarget(e) {
        const kind = this.dragType(e);
        if (kind === 'colour') return this.carried(e, '[data-builder-well]');
        if (kind === 'variable') {
          return this.carried(e, '[data-builder-bind]') || this.carried(e, '[data-builder-bind-root]');
        }
        if (kind === 'promote') return this.carried(e, '[data-builder-promote-target]');
        return null;
      },

      handleDragOver(e) {
        const chipTarget = this.chipTarget(e);
        if (chipTarget) {
          e.preventDefault();
          if (e.dataTransfer) e.dataTransfer.dropEffect = 'copy';
          chipTarget.classList.add('vis-builder-field-over');
          return;
        }

        const field = this.fieldAt(e);
        if (field) {
          e.preventDefault();
          if (e.dataTransfer) e.dataTransfer.dropEffect = 'copy';
          field.classList.add('vis-builder-field-over');
          return;
        }
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
        this.el.querySelectorAll('.vis-builder-field-over').forEach((node) => {
          node.classList.remove('vis-builder-field-over');
        });
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
        const chipTarget = this.chipTarget(e);
        if (chipTarget) {
          e.preventDefault();
          chipTarget.classList.remove('vis-builder-field-over');
          const kind = this.dragType(e);
          if (kind === 'colour') {
            // The well's own form says which edit writes it: the node's, or the style
            // panel's (spec/14 §19.10).
            const form = chipTarget.closest('form');
            this.push('drop_colour', this.aimed(chipTarget, {
              field: chipTarget.getAttribute('data-builder-well'),
              colour: e.dataTransfer.getData('application/x-visualize-colour'),
              edit: (form && form.dataset.builderEdit) || 'edit'
            }));
          } else if (kind === 'variable') {
            const name = e.dataTransfer.getData('application/x-visualize-variable');
            const box = chipTarget.querySelector('[data-builder-text]');
            if (box) {
              // A text field takes the variable as text among text (spec/14 §7.1): the hole
              // goes in at the caret, and the field's own change event writes the string.
              this.insertAtCaret(box, '\#{var(:' + name + ')}');
            } else if (chipTarget.hasAttribute('data-builder-bind')) {
              this.push('bind_field', this.aimed(chipTarget, { field: chipTarget.getAttribute('data-builder-bind'), name: name }));
            } else {
              this.push('bind_root', { root: chipTarget.getAttribute('data-builder-bind-root'), name: name });
            }
          } else if (kind === 'promote') {
            this.push('promote', this.aimed(chipTarget, { field: e.dataTransfer.getData('application/x-visualize-promote') }));
          }
          return;
        }

        const field = this.fieldAt(e);
        if (field) {
          e.preventDefault();
          field.classList.remove('vis-builder-field-over');
          const stored = this.dragged(e);
          if (stored !== null) {
            this.push('insert', this.aimed(field, { field: field.getAttribute('data-builder-ref'), name: stored }));
          }
          return;
        }
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

      insertAtCaret(box, text) {
        const start = box.selectionStart == null ? box.value.length : box.selectionStart;
        const end = box.selectionEnd == null ? start : box.selectionEnd;
        box.value = box.value.slice(0, start) + text + box.value.slice(end);
        const at = start + text.length;
        box.focus();
        if (box.setSelectionRange) box.setSelectionRange(at, at);
        box.dispatchEvent(new Event('input', { bubbles: true }));
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
      handleInput(e) {
        const slider = e.target;
        if (!slider || !slider.classList || !slider.classList.contains('vis-builder-scrubber')) return;
        const min = parseFloat(slider.min) || 0;
        const max = parseFloat(slider.max);
        const value = parseFloat(slider.value);
        if (isNaN(max) || isNaN(value) || max <= min) return;
        const fraction = Math.min(Math.max((value - min) / (max - min), 0), 1);
        slider.style.setProperty('--vis-builder-scrub', (fraction * 100).toFixed(1) + '%');
      },

      handleClick(e) {
        if (!e.target || !e.target.closest) return;
        // The graph (spec/14 §18.16): the nearest drawn node under the pointer is picked;
        // the server selects its owning layer and opens it, and the re-render outlines it.
        if (this.scope === 'graph') {
          const node = e.target.closest('[data-node]');
          if (node && this.el.contains(node)) this.push('pick', { node: node.getAttribute('data-node') });
          return;
        }
        // The one listener that selects a field (spec/14 §19.10): a well selects its own
        // field — a gradient's stop, not the fill row it sits in — and any other click in
        // a row selects the row's key. Rows carry no click binding, so this is the only
        // selection a click makes.
        const well = e.target.closest('[data-builder-well]');
        if (well && this.el.contains(well)) {
          this.push('select_field', this.aimed(well, { field: well.getAttribute('data-builder-well') }));
          return;
        }
        const field = e.target.closest('[data-builder-bind]');
        if (field && this.el.contains(field) && field.hasAttribute('phx-keyup')) {
          this.push('select_field', this.aimed(field, { field: field.getAttribute('data-builder-bind') }));
          return;
        }
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
        this.el.removeEventListener('input', this.onInput);
        this.el.removeEventListener('pointerdown', this.onPointerDown);
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
