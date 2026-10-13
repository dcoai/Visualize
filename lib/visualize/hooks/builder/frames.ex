defmodule Visualize.Hooks.Builder.Frames do
  @moduledoc false
  # `BuilderHook`'s frames on the graph (spec/14 §18.16, spec/10 §16.3; #614, #617): the
  # open frame dragged by its body or a corner handle, snapping to thirds, halves, the
  # other frames' edges and the layout's cells, a frame placed by a cell dragged by whole
  # cells, and the keyboard's arrows — pushing `frame_box` or `frame_cell`.
  #
  # Split from `Visualize.Hooks.Builder` by area: these are methods of the one hook object,
  # spliced into its literal, so `this` is the hook and the methods call its others
  # (`frames/0`, `chartPoint/1`, `push/2`) as their own.

  @doc false
  def js_methods do
    """
      // -- frames placed on the graph (spec/14 §18.16, spec/10 §16.3, #614) -------------

      // The chart's size in its own units, its viewBox: a frame's box is a fraction of it.
      chartSize() {
        const svg = this.el.querySelector('svg.vis-builder-chart');
        const box = svg ? (svg.getAttribute('viewBox') || '').split(/[\\s,]+/).map(Number) : [];
        return box.length === 4 && box[2] > 0 && box[3] > 0 ? { w: box[2], h: box[3] } : null;
      },

      // The open frame's name when the open node is a frame itself, else null.
      openFrame() {
        const svg = this.el.querySelector('svg[data-builder-selected]');
        const label = svg ? svg.getAttribute('data-builder-selected') : null;
        const m = label ? label.match(/^frames\\.([^.\\[]+)$/) : null;
        return m ? m[1] : null;
      },

      // A frame's box as fractions of the chart: [x, y, w, h].
      fractions(f, size) {
        return [f.x / size.w, f.y / size.h, f.w / size.w, f.h / size.h];
      },

      // The lines an edge snaps to on one axis: 0, a third, a half, two thirds, 1, and the
      // other frames' edges, as fractions.
      snapLines(name, size, axis) {
        const lines = [0, 1 / 3, 1 / 2, 2 / 3, 1];
        this.frames().forEach((f) => {
          if (f.name === name) return;
          const [x, y, w, h] = this.fractions(f, size);
          if (axis === 'x') lines.push(x, x + w); else lines.push(y, y + h);
        });
        // On a layout, the cells' edges too (#617).
        const grid = this.grid();
        if (grid) (axis === 'x' ? grid.columns : grid.rows).forEach(([at, span]) => lines.push(at, at + span));
        return lines;
      },

      // The layout's columns and rows as fractions, `[[x, w], …]` and `[[y, h], …]`, from
      // the open frame's overlay; null without a layout (#617).
      grid() {
        const overlay = this.el.querySelector('[data-builder-frame-box]');
        const text = overlay ? overlay.getAttribute('data-builder-grid') : null;
        if (!text) return null;
        const spans = (part) => part.split(',').map((pair) => pair.trim().split(/\s+/).map(Number));
        const [columns, rows] = text.split(';');
        return { columns: spans(columns), rows: spans(rows) };
      },

      // The open frame's cell and span, `[c, r, a, d]`, when it is placed by a cell.
      frameCell() {
        const overlay = this.el.querySelector('[data-builder-frame-box]');
        const text = overlay ? overlay.getAttribute('data-builder-frame-cell') : null;
        return text ? text.trim().split(/\s+/).map(Number) : null;
      },

      // The index of the line nearest a value.
      nearest(lines, value) {
        let best = 0;
        lines.forEach((line, i) => { if (Math.abs(line - value) < Math.abs(lines[best] - value)) best = i; });
        return best;
      },

      // A cell and span dragged by `dx`, `dy` (fractions): moved by whole cells, or one
      // edge of it, as the corner `handle` says, moved to the nearest cell edge (#617).
      celled(cell, dx, dy, handle, grid) {
        const [c, r, a, d] = cell;
        const one = (index, span, d0, lines, low, high, count) => {
          const starts = lines.map(([at]) => at);
          const ends = lines.map(([at, len]) => at + len);
          if (!high && !low) {
            const at = this.nearest(starts, starts[index] + d0);
            return [Math.max(0, Math.min(count - span, at)), span];
          }
          if (low) {
            const last = index + span - 1;
            const at = Math.min(last, this.nearest(starts, starts[index] + d0));
            return [at, last - at + 1];
          }
          const end = Math.max(index, this.nearest(ends, ends[index + span - 1] + d0));
          return [index, end - index + 1];
        };
        const h = handle || '';
        const [nc, na] = one(c, a, dx, grid.columns, h.indexOf('w') >= 0, h.indexOf('e') >= 0, grid.columns.length);
        const [nr, nd] = one(r, d, dy, grid.rows, h.indexOf('n') >= 0, h.indexOf('s') >= 0, grid.rows.length);
        return [nc, nr, na, nd];
      },

      // The box a cell and span take on the grid, as fractions.
      cellBox(cell, grid) {
        const [c, r, a, d] = cell;
        const x = grid.columns[c][0], y = grid.rows[r][0];
        const right = grid.columns[c + a - 1][0] + grid.columns[c + a - 1][1];
        const bottom = grid.rows[r + d - 1][0] + grid.rows[r + d - 1][1];
        return [x, y, right - x, bottom - y];
      },

      pushCell(name, cell) {
        this.push('frame_cell', { frame: name, cell: [cell[0], cell[1]], span: [cell[2], cell[3]] });
      },

      // The nearest line within the threshold, else null.
      snapTo(value, lines, threshold) {
        let best = null, distance = threshold;
        lines.forEach((line) => {
          const d = Math.abs(line - value);
          if (d <= distance) { best = line; distance = d; }
        });
        return best;
      },

      // One axis of a box moved by `d`: the start or the end edge snapped, whichever is
      // nearer a line, then kept inside [0, 1].
      slide(start, size, d, lines, threshold) {
        let at = start + d;
        const lead = this.snapTo(at, lines, threshold);
        const trail = this.snapTo(at + size, lines, threshold);
        if (lead !== null && (trail === null || Math.abs(lead - at) <= Math.abs(trail - at - size))) at = lead;
        else if (trail !== null) at = trail - size;
        return [Math.max(0, Math.min(1 - size, at)), size];
      },

      // One axis of a box with one edge dragged by `d`: `low` the start edge, else the end;
      // the edge snapped, the side at least a twentieth, inside [0, 1].
      stretch(start, size, d, low, lines, threshold) {
        const least = 0.05;
        if (low) {
          let edge = start + d;
          const s = this.snapTo(edge, lines, threshold);
          if (s !== null) edge = s;
          edge = Math.max(0, Math.min(start + size - least, edge));
          return [edge, start + size - edge];
        }
        let edge = start + size + d;
        const s = this.snapTo(edge, lines, threshold);
        if (s !== null) edge = s;
        edge = Math.min(1, Math.max(start + least, edge));
        return [start, edge - start];
      },

      // The box a drag gives: moved by the body, or stretched by the corner `handle`.
      dragged(name, from, dx, dy, handle, size) {
        const xs = this.snapLines(name, size, 'x');
        const ys = this.snapLines(name, size, 'y');
        const tx = 8 / size.w, ty = 8 / size.h;
        if (!handle) {
          const [x, w] = this.slide(from[0], from[2], dx, xs, tx);
          const [y, h] = this.slide(from[1], from[3], dy, ys, ty);
          return [x, y, w, h];
        }
        const [x, w] = this.stretch(from[0], from[2], dx, handle.indexOf('w') >= 0, xs, tx);
        const [y, h] = this.stretch(from[1], from[3], dy, handle.indexOf('n') >= 0, ys, ty);
        return [x, y, w, h];
      },

      // The outline and its handles drawn where the box now is, as it moves.
      showFrame(box, size) {
        const overlay = this.el.querySelector('[data-builder-frame-box]');
        if (!overlay) return;
        const [x, y, w, h] = [box[0] * size.w, box[1] * size.h, box[2] * size.w, box[3] * size.h];
        overlay.querySelectorAll('.vis-builder-frame-outline').forEach((rect) => {
          rect.setAttribute('x', x); rect.setAttribute('y', y);
          rect.setAttribute('width', w); rect.setAttribute('height', h);
        });
        overlay.querySelectorAll('[data-builder-frame-handle]').forEach((rect) => {
          const at = rect.getAttribute('data-builder-frame-handle');
          const side = parseFloat(rect.getAttribute('width')) || 10;
          const clamp = (v, last) => Math.max(0, Math.min(last, v));
          rect.setAttribute('x', clamp((at.indexOf('w') >= 0 ? x : x + w) - side / 2, size.w - side));
          rect.setAttribute('y', clamp((at.indexOf('n') >= 0 ? y : y + h) - side / 2, size.h - side));
        });
      },

      pushFrame(name, box) {
        const r = (n) => Math.round(n * 10000) / 10000;
        this.push('frame_box', { frame: name, box: box.map(r) });
      },

      // A press on the open frame — its body, or one of its corner handles — starts a
      // move or a resize (spec/14 §18.16, #614); past four pixels the outline follows the
      // pointer, snapping, and the release pushes `frame_box`. A press that does not travel
      // is a click, and picks as any click does.
      startFrame(e) {
        const name = this.openFrame();
        const size = this.chartSize();
        const start = this.chartPoint(e);
        if (name === null || size === null || start === null) return;
        const f = this.frames().find((frame) => frame.name === name);
        if (!f) return;
        const grip = e.target.closest('[data-builder-frame-handle]');
        const handle = grip && this.el.contains(grip) ? grip.getAttribute('data-builder-frame-handle') : null;
        const over = this.frameAt(start, true);
        if (handle === null && (!over || over.name !== name)) return;
        const from = this.fractions(f, size);
        // A frame placed by a cell of the layout moves by whole cells (#617).
        const grid = this.grid();
        const fromCell = grid ? this.frameCell() : null;
        let box = from;
        let cell = fromCell;
        let moved = false;
        if (this.el.setPointerCapture && e.pointerId !== undefined) this.el.setPointerCapture(e.pointerId);
        const move = (ev) => {
          const p = this.chartPoint(ev);
          if (!p) return;
          if (!moved && Math.abs(p.x - start.x) + Math.abs(p.y - start.y) < 4) return;
          moved = true;
          this.el.classList.add('vis-builder-moving');
          const dx = (p.x - start.x) / size.w, dy = (p.y - start.y) / size.h;
          if (fromCell) {
            cell = this.celled(fromCell, dx, dy, handle, grid);
            box = this.cellBox(cell, grid);
          } else {
            box = this.dragged(name, from, dx, dy, handle, size);
          }
          this.showFrame(box, size);
        };
        const up = () => {
          this.el.removeEventListener('pointermove', move);
          this.el.removeEventListener('pointerup', up);
          this.el.classList.remove('vis-builder-moving');
          if (!moved) return;
          this.dragEnded = true;
          this.showFrame(from, size);
          if (fromCell) {
            if (cell.some((n, i) => n !== fromCell[i])) this.pushCell(name, cell);
          } else if (box.some((n, i) => n !== from[i])) {
            this.pushFrame(name, box);
          }
        };
        this.el.addEventListener('pointermove', move);
        this.el.addEventListener('pointerup', up);
      },

      // With a frame open and the graph focused, an arrow moves it a twelfth of the box and
      // Shift with an arrow grows or shrinks its right or bottom edge by a twelfth, through
      // the same push; true when the key was the frame's.
      frameKey(e) {
        const steps = { ArrowLeft: [-1, 0], ArrowRight: [1, 0], ArrowUp: [0, -1], ArrowDown: [0, 1] };
        const step = steps[e.key];
        const name = this.openFrame();
        const size = this.chartSize();
        if (!step || name === null || size === null) return false;
        const f = this.frames().find((frame) => frame.name === name);
        if (!f) return false;
        e.preventDefault();
        // On a layout, a frame placed by a cell steps a cell, and Shift grows its span.
        const grid = this.grid();
        const cell = grid ? this.frameCell() : null;
        if (cell) {
          const [c, r, a, d] = cell;
          const next = e.shiftKey
            ? [c, r, Math.max(1, Math.min(grid.columns.length - c, a + step[0])), Math.max(1, Math.min(grid.rows.length - r, d + step[1]))]
            : [Math.max(0, Math.min(grid.columns.length - a, c + step[0])), Math.max(0, Math.min(grid.rows.length - d, r + step[1])), a, d];
          if (next.some((n, i) => n !== cell[i])) this.pushCell(name, next);
          return true;
        }
        const [x, y, w, h] = this.fractions(f, size);
        const t = 1 / 12;
        const box = e.shiftKey
          ? [x, y, Math.max(0.05, Math.min(1 - x, w + step[0] * t)), Math.max(0.05, Math.min(1 - y, h + step[1] * t))]
          : [Math.max(0, Math.min(1 - w, x + step[0] * t)), Math.max(0, Math.min(1 - h, y + step[1] * t)), w, h];
        if (box.some((n, i) => Math.abs(n - [x, y, w, h][i]) > 1e-9)) this.pushFrame(name, box);
        return true;
      },

    """
  end
end
