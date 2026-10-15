defmodule Visualize.Hooks.CanvasBinary do
  @moduledoc """
  Phoenix LiveView hook that replays the canvas binary format on a `<canvas>`.

  `CanvasBinaryChart` decodes the stream `Visualize.Backend.CanvasBinary` produces
  (spec/09 §4) — from the element's `data-binary` attribute on mount and update, and from
  `canvas_update` events pushed by the LiveView — and draws it on a Canvas 2D context.

  ## Usage

      <div id="chart" phx-hook="CanvasBinaryChart" phx-update="ignore"
           data-binary={@binary} data-width="800" data-height="600">
        <canvas width="800" height="600"></canvas>
      </div>

      # Push a new frame
      push_event(socket, "canvas_update", %{binary: Visualize.Backend.CanvasBinary.to_base64(bin)})

  The decoder (`js_decoder/0`) is shared with `Visualize.Hooks.CanvasIncremental` and is
  written against `Visualize.Backend.CanvasBinary.Opcodes`: every opcode and every
  command-stream sub-opcode has a case — the f64 and the f32 path records (D-73) share one
  reader taking the coordinate width, and the cubic run (D-74) has its own — and an unknown
  byte throws rather than
  desynchronise silently. A full-matrix transform (`0xFF`) composes with `ctx.transform`.

  The canvas's drawing size is the element's `data-width` × `data-height` at every draw
  (spec/10 §8.2, #456): a size change re-sizes the canvas, which clears it, and redraws
  the current `data-binary` even when it is the value last drawn.
  """

  @doc """
  Returns the JavaScript of the shared decoder: `decodeBase64`, `drawSvgArc` and
  `executeVisualizeBinary(ctx, bytes, startOffset, endOffset)`, which replays one stream
  and returns the offset it reached, with the module-private readers of the path records
  it calls.
  """
  def js_decoder do
    pattern_js() <>
      ~S"""
      // Standard base64 (as Base.encode64/1 writes it) to bytes.
      export function decodeBase64(base64) {
        const binaryStr = atob(base64);
        const bytes = new Uint8Array(binaryStr.length);
        for (let i = 0; i < binaryStr.length; i++) {
          bytes[i] = binaryStr.charCodeAt(i);
        }
        return bytes;
      }

      // SVG arc to Canvas ellipse: the endpoint-to-center parameterization of the SVG
      // specification (implementation notes B.2.4).
      export function drawSvgArc(ctx, x1, y1, rx, ry, phi, fA, fS, x2, y2) {
        if (x1 === x2 && y1 === y2) return;
        if (rx === 0 || ry === 0) {
          ctx.lineTo(x2, y2);
          return;
        }

        rx = Math.abs(rx);
        ry = Math.abs(ry);

        const cosPhi = Math.cos(phi);
        const sinPhi = Math.sin(phi);

        // Step 1: Compute (x1', y1')
        const dx2 = (x1 - x2) / 2;
        const dy2 = (y1 - y2) / 2;
        const x1p = cosPhi * dx2 + sinPhi * dy2;
        const y1p = -sinPhi * dx2 + cosPhi * dy2;

        // Step 2: Compute (cx', cy')
        let rxSq = rx * rx;
        let rySq = ry * ry;
        const x1pSq = x1p * x1p;
        const y1pSq = y1p * y1p;

        // Check if radii are large enough
        let lambda = x1pSq / rxSq + y1pSq / rySq;
        if (lambda > 1) {
          const lambdaSqrt = Math.sqrt(lambda);
          rx *= lambdaSqrt;
          ry *= lambdaSqrt;
          rxSq = rx * rx;
          rySq = ry * ry;
        }

        let sq = ((rxSq * rySq) - (rxSq * y1pSq) - (rySq * x1pSq)) /
                 ((rxSq * y1pSq) + (rySq * x1pSq));
        sq = sq < 0 ? 0 : sq;
        const coef = (fA !== fS ? 1 : -1) * Math.sqrt(sq);
        const cxp = coef * ((rx * y1p) / ry);
        const cyp = coef * -((ry * x1p) / rx);

        // Step 3: Compute (cx, cy) from (cx', cy')
        const cx = cosPhi * cxp - sinPhi * cyp + (x1 + x2) / 2;
        const cy = sinPhi * cxp + cosPhi * cyp + (y1 + y2) / 2;

        // Step 4: Compute theta1 and dtheta
        const ux = (x1p - cxp) / rx;
        const uy = (y1p - cyp) / ry;
        const vx = (-x1p - cxp) / rx;
        const vy = (-y1p - cyp) / ry;

        let n = Math.sqrt(ux * ux + uy * uy);
        let p = ux;
        let theta1 = (uy < 0 ? -1 : 1) * Math.acos(p / n);

        n = Math.sqrt((ux * ux + uy * uy) * (vx * vx + vy * vy));
        p = ux * vx + uy * vy;
        let dtheta = (ux * vy - uy * vx < 0 ? -1 : 1) * Math.acos(Math.max(-1, Math.min(1, p / n)));

        if (fS === 0 && dtheta > 0) dtheta -= 2 * Math.PI;
        if (fS === 1 && dtheta < 0) dtheta += 2 * Math.PI;

        ctx.ellipse(cx, cy, rx, ry, phi, theta1, theta1 + dtheta, fS === 0);
      }

      // A gradient as ctx[target + 'Style'] (spec/10 §8.1, #652): a linear one from
      // [x0, y0, x1, y1], a radial one [cx, cy, r] about its focus at its centre, with one
      // addColorStop per [at, colour].
      export function visualizeGradient(ctx, target, kind, g, stops) {
        const gradient = kind === 'linear' ?
          ctx.createLinearGradient(g[0], g[1], g[2], g[3]) :
          ctx.createRadialGradient(g[0], g[1], 0, g[0], g[1], g[2]);
        stops.forEach(([at, colour]) => gradient.addColorStop(at, colour));
        ctx[target + 'Style'] = gradient;
      }

      // The current path's fill or stroke (op) drawn with a paint in box units over a box
      // [x, y, w, h], as spec/09 §3.3.3 maps it: a linear gradient exactly into user units, a
      // radial fill under the box transform, a radial stroke the circle of the same area;
      // nothing on a box without area. In a save/restore, so the gradient is never state.
      export function drawVisualizePaint(ctx, op, paint, box) {
        // A hatch is laid from the origin in user units and needs no box (#673).
        if (paint.kind === 'hatch') {
          ctx.save();
          visualizePattern(ctx, op, ...paint.args);
          ctx[op]();
          ctx.restore();
          return;
        }
        const [x, y, w, h] = box;
        if (!(w > 0 && h > 0)) return;
        const g = paint.geometry;
        ctx.save();
        if (paint.kind === 'linear') {
          const dx = g[2] - g[0], dy = g[3] - g[1], dd = dx * dx + dy * dy;
          const gx = dx / w / dd, gy = dy / h / dd, gg = gx * gx + gy * gy;
          const x0 = x + g[0] * w, y0 = y + g[1] * h;
          visualizeGradient(ctx, op, 'linear', [x0, y0, x0 + gx / gg, y0 + gy / gg], paint.stops);
        } else if (op === 'fill') {
          ctx.transform(w, 0, 0, h, x, y);
          visualizeGradient(ctx, op, 'radial', g, paint.stops);
        } else {
          visualizeGradient(ctx, op, 'radial', [x + g[0] * w, y + g[1] * h, g[2] * Math.sqrt(w * h)], paint.stops);
        }
        ctx[op]();
        ctx.restore();
      }

      // One coordinate of a path record: 8 bytes (f64) or 4 (f32), little-endian.
      function readCoord(view, offset, width) {
        return width === 4 ? view.getFloat32(offset, true) : view.getFloat64(offset, true);
      }

      // The point-list records `path` (f64) and `path32` (f32): moveTo the first point,
      // lineTo the rest, the path left open. Returns the offset after the last point.
      function drawPolyline(ctx, view, offset, count, width) {
        ctx.beginPath();
        for (let i = 0; i < count; i++) {
          const x = readCoord(view, offset, width);
          const y = readCoord(view, offset + width, width);
          offset += 2 * width;
          if (i === 0) ctx.moveTo(x, y);
          else ctx.lineTo(x, y);
        }
        return offset;
      }

      // The command-stream records `path_cubic` (f64) and `path_cubic32` (f32): one
      // sub-opcode per command (spec/09 §4.3.2, §4.3.9) against a tracked current point and
      // subpath start; the arc flags are u32 at either width. Returns the offset reached.
      function drawPathCommands(ctx, view, bytes, offset, cmdCount, width) {
        const f = (o) => readCoord(view, o, width);
        const w = width;
        ctx.beginPath();
        let curX = 0, curY = 0, startX = 0, startY = 0;
        for (let i = 0; i < cmdCount; i++) {
          const subcmd = bytes[offset++];
          switch (subcmd) {
            case 0x01: { // M
              curX = f(offset); curY = f(offset + w);
              startX = curX; startY = curY;
              ctx.moveTo(curX, curY);
              offset += 2 * w;
              break;
            }
            case 0x02: { // L
              curX = f(offset); curY = f(offset + w);
              ctx.lineTo(curX, curY);
              offset += 2 * w;
              break;
            }
            case 0x03: { // C
              const x1 = f(offset), y1 = f(offset + w), x2 = f(offset + 2 * w), y2 = f(offset + 3 * w);
              curX = f(offset + 4 * w); curY = f(offset + 5 * w);
              ctx.bezierCurveTo(x1, y1, x2, y2, curX, curY);
              offset += 6 * w;
              break;
            }
            case 0x04: { // Q
              const qx1 = f(offset), qy1 = f(offset + w);
              curX = f(offset + 2 * w); curY = f(offset + 3 * w);
              ctx.quadraticCurveTo(qx1, qy1, curX, curY);
              offset += 4 * w;
              break;
            }
            case 0x05: { // Z
              ctx.closePath();
              curX = startX; curY = startY;
              break;
            }
            case 0x06: { // A (absolute end point)
              const rx = f(offset), ry = f(offset + w);
              const rotation = f(offset + 2 * w) * Math.PI / 180;
              const largeArc = view.getUint32(offset + 3 * w, true);
              const sweep = view.getUint32(offset + 3 * w + 4, true);
              const x = f(offset + 3 * w + 8), y = f(offset + 4 * w + 8);
              offset += 5 * w + 8;
              drawSvgArc(ctx, curX, curY, rx, ry, rotation, largeArc, sweep, x, y);
              curX = x; curY = y;
              break;
            }
            case 0x07: { // a (end point relative to the current point)
              const rx = f(offset), ry = f(offset + w);
              const rotation = f(offset + 2 * w) * Math.PI / 180;
              const largeArc = view.getUint32(offset + 3 * w, true);
              const sweep = view.getUint32(offset + 3 * w + 4, true);
              const x = curX + f(offset + 3 * w + 8), y = curY + f(offset + 4 * w + 8);
              offset += 5 * w + 8;
              drawSvgArc(ctx, curX, curY, rx, ry, rotation, largeArc, sweep, x, y);
              curX = x; curY = y;
              break;
            }
            case 0x08: { // H
              curX = f(offset);
              ctx.lineTo(curX, curY);
              offset += w;
              break;
            }
            case 0x09: { // V
              curY = f(offset);
              ctx.lineTo(curX, curY);
              offset += w;
              break;
            }
            case 0x0A: { // h
              curX += f(offset);
              ctx.lineTo(curX, curY);
              offset += w;
              break;
            }
            case 0x0B: { // v
              curY += f(offset);
              ctx.lineTo(curX, curY);
              offset += w;
              break;
            }
            case 0x0C: { // m
              curX += f(offset); curY += f(offset + w);
              startX = curX; startY = curY;
              ctx.moveTo(curX, curY);
              offset += 2 * w;
              break;
            }
            case 0x0D: { // l
              curX += f(offset); curY += f(offset + w);
              ctx.lineTo(curX, curY);
              offset += 2 * w;
              break;
            }
            case 0x0E: { // c
              const dx1 = f(offset), dy1 = f(offset + w), dx2 = f(offset + 2 * w), dy2 = f(offset + 3 * w);
              const dx = f(offset + 4 * w), dy = f(offset + 5 * w);
              ctx.bezierCurveTo(curX + dx1, curY + dy1, curX + dx2, curY + dy2, curX + dx, curY + dy);
              curX += dx; curY += dy;
              offset += 6 * w;
              break;
            }
            case 0x0F: { // q
              const dx1 = f(offset), dy1 = f(offset + w);
              const dx = f(offset + 2 * w), dy = f(offset + 3 * w);
              ctx.quadraticCurveTo(curX + dx1, curY + dy1, curX + dx, curY + dy);
              curX += dx; curY += dy;
              offset += 4 * w;
              break;
            }
            default:
              throw new Error('Unknown canvas binary path command 0x' + subcmd.toString(16) + ' at offset ' + (offset - 1));
          }
        }
        return offset;
      }

      // The cubic run `cubic_run` (spec/09 §4.3.10): the start point, then six f32 per curve
      // with no sub-opcode. Returns the offset after the last curve.
      function drawCubicRun(ctx, view, offset, count) {
        ctx.beginPath();
        ctx.moveTo(view.getFloat32(offset, true), view.getFloat32(offset + 4, true));
        offset += 8;
        for (let i = 0; i < count; i++) {
          ctx.bezierCurveTo(
            view.getFloat32(offset, true), view.getFloat32(offset + 4, true),
            view.getFloat32(offset + 8, true), view.getFloat32(offset + 12, true),
            view.getFloat32(offset + 16, true), view.getFloat32(offset + 20, true)
          );
          offset += 24;
        }
        return offset;
      }

      // Replays one canvas binary stream (Visualize.Backend.CanvasBinary, spec/09 §4) on ctx
      // from startOffset up to endOffset (default: the end of bytes). Returns the offset
      // reached. Opcodes are those of Visualize.Backend.CanvasBinary.Opcodes; an unknown
      // byte is an encoder/decoder mismatch and throws.
      // A decode failure is visible on the page (spec/10 §9.2, #270): the message goes on
      // the hook element as data-vis-error and under the canvas as a line of text, and the
      // error is rethrown so the console keeps the stack. A stream that replays clears both.
      export function reportVisualizeError(el, error) {
        const message = error && error.message ? error.message : String(error);
        el.setAttribute('data-vis-error', message);
        let note = el.querySelector('.vis-canvas-error');
        if (!note) {
          note = document.createElement('p');
          note.className = 'vis-canvas-error';
          note.setAttribute('role', 'alert');
          el.appendChild(note);
        }
        note.textContent = 'canvas stream failed: ' + message;
      }

      export function clearVisualizeError(el) {
        el.removeAttribute('data-vis-error');
        const note = el.querySelector('.vis-canvas-error');
        if (note) note.remove();
      }

      // `motion`, a VisualizeMotion state, runs the stream's motion spans (spec/10 §4.5);
      // without it a span is skipped and every element drawn at its target.
      export function executeVisualizeBinary(ctx, bytes, startOffset, endOffset, motion) {
        const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
        let offset = startOffset || 0;
        const maxOffset = endOffset === undefined ? bytes.length : endOffset;
        // Version 2 (spec/09 §4.2): the stream's paints, the fill and stroke paint as state that
        // save and restore scope, and the box the next draw's paint is built over.
        const paints = [];
        const scopes = [];
        let fillPaint = null, strokePaint = null, box = null;
        // Where the open motion span's records begin (#678).
        let opened = 0;

        while (offset < maxOffset) {
          const cmd = bytes[offset++];

          switch (cmd) {
            case 0x01: { // path: one open polyline, f64
              const count = view.getUint32(offset, true);
              offset = drawPolyline(ctx, view, offset + 4, count, 8);
              break;
            }

            case 0x05: { // path32: one open polyline, f32
              const count = view.getUint32(offset, true);
              offset = drawPolyline(ctx, view, offset + 4, count, 4);
              break;
            }

            case 0x02: { // path_cubic: the full command stream, f64
              const cmdCount = view.getUint32(offset, true);
              offset = drawPathCommands(ctx, view, bytes, offset + 4, cmdCount, 8);
              break;
            }

            case 0x06: { // path_cubic32: the full command stream, f32
              const cmdCount = view.getUint32(offset, true);
              offset = drawPathCommands(ctx, view, bytes, offset + 4, cmdCount, 4);
              break;
            }

            case 0x07: { // cubic_run: a start point and a run of cubic curves, f32
              const count = view.getUint32(offset, true);
              offset = drawCubicRun(ctx, view, offset + 4, count);
              break;
            }

            case 0x03: { // circles: one path holding every circle
              const count = view.getUint32(offset, true);
              offset += 4;
              ctx.beginPath();
              for (let i = 0; i < count; i++) {
                const cx = view.getFloat64(offset, true);
                const cy = view.getFloat64(offset + 8, true);
                const r = view.getFloat64(offset + 16, true);
                offset += 24;
                ctx.moveTo(cx + r, cy);
                ctx.arc(cx, cy, r, 0, Math.PI * 2);
              }
              break;
            }

            case 0x04: { // rects: one path holding every rectangle
              const count = view.getUint32(offset, true);
              offset += 4;
              ctx.beginPath();
              for (let i = 0; i < count; i++) {
                const x = view.getFloat64(offset, true);
                const y = view.getFloat64(offset + 8, true);
                const w = view.getFloat64(offset + 16, true);
                const h = view.getFloat64(offset + 24, true);
                offset += 32;
                ctx.rect(x, y, w, h);
              }
              break;
            }

            case 0x10: { // style
              const flags = bytes[offset++];
              if (flags & 0x01) { // fill colour
                fillPaint = null;
                const r = bytes[offset++], g = bytes[offset++], b = bytes[offset++], a = bytes[offset++];
                ctx.fillStyle = `rgba(${r},${g},${b},${a / 255})`;
              }
              if (flags & 0x02) { // stroke colour
                strokePaint = null;
                const r = bytes[offset++], g = bytes[offset++], b = bytes[offset++], a = bytes[offset++];
                ctx.strokeStyle = `rgba(${r},${g},${b},${a / 255})`;
              }
              if (flags & 0x04) { // stroke width, divided by the scale when it does not scale
                const w = view.getFloat32(offset, true);
                if (flags & 0x10) {
                  const t = ctx.getTransform();
                  ctx.lineWidth = w / Math.sqrt(Math.abs(t.a * t.d - t.b * t.c));
                } else {
                  ctx.lineWidth = w;
                }
                offset += 4;
              }
              if (flags & 0x08) { // global alpha
                ctx.globalAlpha = view.getFloat32(offset, true);
                offset += 4;
              }
              if (flags & 0x20) { // version 2: the fill is a paint
                fillPaint = paints[view.getUint16(offset, true)];
                offset += 2;
              }
              if (flags & 0x40) { // version 2: the stroke is a paint
                strokePaint = paints[view.getUint16(offset, true)];
                offset += 2;
              }
              break;
            }

            case 0x20: { // transform
              const kind = bytes[offset++];
              switch (kind) {
                case 0x01: // translate
                  ctx.translate(view.getFloat64(offset, true), view.getFloat64(offset + 8, true));
                  offset += 16;
                  break;
                case 0x03: // translate then scale
                  ctx.translate(view.getFloat64(offset, true), view.getFloat64(offset + 8, true));
                  ctx.scale(view.getFloat64(offset + 16, true), view.getFloat64(offset + 24, true));
                  offset += 32;
                  break;
                case 0xFF: // full matrix, composed onto the current transform
                  ctx.transform(
                    view.getFloat64(offset, true), view.getFloat64(offset + 8, true),
                    view.getFloat64(offset + 16, true), view.getFloat64(offset + 24, true),
                    view.getFloat64(offset + 32, true), view.getFloat64(offset + 40, true)
                  );
                  offset += 48;
                  break;
                default:
                  throw new Error('Unknown canvas binary transform kind 0x' + kind.toString(16) + ' at offset ' + (offset - 1));
              }
              break;
            }

            case 0x30: // save
              ctx.save();
              scopes.push([fillPaint, strokePaint]);
              break;

            case 0x31: // restore
              ctx.restore();
              [fillPaint, strokePaint] = scopes.pop() || [null, null];
              break;

            case 0x40: // fill, with the fill paint over the box when there is one
              if (fillPaint) drawVisualizePaint(ctx, 'fill', fillPaint, box);
              else if (motion && motion.span) VisualizeMotion.draw(motion, ctx, 'fill', () => ctx.fill());
              else ctx.fill();
              break;

            case 0x41: // stroke
              if (strokePaint) drawVisualizePaint(ctx, 'stroke', strokePaint, box);
              else if (motion && motion.span) VisualizeMotion.draw(motion, ctx, 'stroke', () => ctx.stroke());
              else ctx.stroke();
              break;

            case 0x53: { // motion: a span begins, its arguments as JSON (§4.3.15, #653)
              const length = view.getUint16(offset, true);
              if (motion) {
                const text = new TextDecoder().decode(bytes.subarray(offset + 2, offset + 2 + length));
                VisualizeMotion.open(motion, ctx, VisualizeMotion.parseSpan(text));
              }
              offset += 2 + length;
              opened = offset;
              break;
            }

            case 0x54: { // motion_end (§4.3.16): a span with an exit keeps its bytes (#678)
              const [s, e] = [opened, offset - 1];
              if (motion) VisualizeMotion.close(motion, ctx, () => (c, m) => executeVisualizeBinary(c, bytes, s, e, m));
              break;
            }

            case 0x00: { // version (spec/09 §4.3.11)
              const version = bytes[offset++];
              if (version > 2) throw new Error('Unknown canvas binary stream version ' + version + ' at offset ' + (offset - 2));
              break;
            }

            case 0x50: { // paint: a gradient in box units or a hatch, defined for the stream (§4.3.12)
              const index = view.getUint16(offset, true);
              const kind = bytes[offset + 2];
              offset += 3;
              if (kind === 0x03) { // hatch: pattern, angle, spacing, width, colour, ground
                const pattern = ['lines', 'crosshatch', 'dots'][bytes[offset] - 1];
                if (!pattern) throw new Error('Unknown canvas binary hatch pattern 0x' + bytes[offset].toString(16) + ' at offset ' + offset);
                const f = (i) => view.getFloat32(offset + 1 + 4 * i, true);
                const c = (o) => `rgba(${bytes[o]},${bytes[o + 1]},${bytes[o + 2]},${bytes[o + 3] / 255})`;
                const ground = bytes[offset + 20] === 0 ? null : c(offset + 17);
                paints[index] = {kind: 'hatch', args: [pattern, f(0), f(1), f(2), c(offset + 13), ground]};
                offset += 21;
                break;
              }
              if (kind !== 0x01 && kind !== 0x02) throw new Error('Unknown canvas binary paint kind 0x' + kind.toString(16) + ' at offset ' + (offset - 1));
              const geometry = [];
              for (let i = 0; i < (kind === 0x01 ? 4 : 3); i++, offset += 4) geometry.push(view.getFloat32(offset, true));
              const stops = [];
              const count = bytes[offset++];
              for (let i = 0; i < count; i++, offset += 8) {
                const r = bytes[offset + 4], g = bytes[offset + 5], b = bytes[offset + 6], a = bytes[offset + 7];
                stops.push([view.getFloat32(offset, true), `rgba(${r},${g},${b},${a / 255})`]);
              }
              paints[index] = {kind: kind === 0x01 ? 'linear' : 'radial', geometry, stops};
              break;
            }

            case 0x52: { // effect: a shadow or a blur, context state (§4.3.14, #674)
            const kind = bytes[offset];
            const radius = view.getFloat32(offset + 1, true);
            if (kind === 0x01) {
              const o = offset + 13;
              ctx.shadowColor = `rgba(${bytes[o]},${bytes[o + 1]},${bytes[o + 2]},${bytes[o + 3] / 255})`;
              ctx.shadowBlur = radius;
              ctx.shadowOffsetX = view.getFloat32(offset + 5, true);
              ctx.shadowOffsetY = view.getFloat32(offset + 9, true);
              offset += 17;
            } else if (kind === 0x02) {
              ctx.filter = `blur(${radius}px)`;
              offset += 5;
            } else {
              throw new Error('Unknown canvas binary effect kind 0x' + kind.toString(16) + ' at offset ' + offset);
            }
            break;
          }

          case 0x51: // box: what the next draw's paint is built over (§4.3.13)
              box = [view.getFloat32(offset, true), view.getFloat32(offset + 4, true),
                     view.getFloat32(offset + 8, true), view.getFloat32(offset + 12, true)];
              offset += 16;
              break;

            default:
              throw new Error('Unknown canvas binary opcode 0x' + cmd.toString(16) + ' at offset ' + (offset - 1));
          }
        }

        return offset;
      }
      """
  end

  # A hatch's CanvasPattern as ctx[target + 'Style'] (spec/10 §8.1, #673): the tile source the
  # server writes into a `:js` script, `Visualize.Backend.Canvas.hatch_js/0`, so the two never
  # draw different tiles.
  defp pattern_js do
    "    export function visualizePattern(ctx, target, pattern, angle, spacing, width, colour, background) {\n" <>
      "      ctx[target + 'Style'] = (" <>
      Visualize.Backend.Canvas.hatch_js() <>
      ")(ctx, pattern, angle, spacing, width, colour, background);\n    }\n\n"
  end

  @doc """
  Returns the JavaScript code for the CanvasBinaryChart hook.

  Requires the decoder of `js_decoder/0` in the same module; `Visualize.Hooks.js_code/0`
  includes both.
  """
  def js_hook do
    ~S"""
    export const CanvasBinaryChart = {
      mounted() {
        this.canvas = this.el.querySelector('canvas') || this.createCanvas();
        this.ctx = this.canvas.getContext('2d');
        this.lastData = null;
        // A style's motion (spec/10 §4.5): what each identity shows, and the pending frame.
        this.motion = VisualizeMotion.create();
        this.bytes = null;
        this.motionFrame = null;

        // Acknowledge frames when asked (spec/10 §8.2, D-107), as CanvasIncrementalChart
        // does: data-ack names the event, data-ack-interval the most often it is pushed.
        this.ackEvent = this.el.dataset.ack || null;
        this.ackInterval = parseInt(this.el.dataset.ackInterval, 10) || 100;
        this.ackSeq = null;
        this.ackDrawn = 0;
        this.ackTimer = null;

        // A design has one canvas per frame (spec/14 §12.1, #432): data-frame names this
        // one's, and a payload for another frame is not this canvas's to draw.
        this.frame = this.el.dataset.frame || null;

        this.handleEvent("canvas_update", (payload) => {
          if (!this.mine(payload)) return;
          this.el.dataset.binary = payload.binary;
          this.render();
          if (payload.seq !== undefined) this.acknowledge(payload.seq);
        });

        this.render();
      },
      mine(payload) {
        return this.frame === null || payload.frame === undefined || payload.frame === this.frame;
      },
      destroyed() {
        if (this.ackTimer !== null) clearTimeout(this.ackTimer);
        if (this.motionFrame !== null) cancelAnimationFrame(this.motionFrame);
      },
      acknowledge(seq) {
        if (this.ackEvent === null) return;
        this.ackSeq = seq;
        this.ackDrawn += 1;
        if (this.ackTimer === null) {
          this.ackTimer = setTimeout(() => this.flushAck(), this.ackInterval);
        }
      },
      flushAck() {
        this.ackTimer = null;
        this.pushEvent(this.ackEvent, { seq: this.ackSeq, drawn: this.ackDrawn, at: performance.now() });
        this.ackDrawn = 0;
      },
      updated() {
        this.render();
      },
      createCanvas() {
        const canvas = document.createElement('canvas');
        canvas.width = parseInt(this.el.dataset.width) || 800;
        canvas.height = parseInt(this.el.dataset.height) || 600;
        canvas.style.display = 'block';
        this.el.appendChild(canvas);
        return canvas;
      },
      // The canvas's drawing size is the element's data-width x data-height at every draw
      // (spec/10 §8.2, #456): a page that measures itself re-renders at a new size, and a
      // canvas sized once at mount draws the stream off its edges. Returns whether the
      // size changed, which clears the canvas.
      sizeToElement() {
        const width = parseInt(this.el.dataset.width, 10);
        const height = parseInt(this.el.dataset.height, 10);
        if (!(width > 0 && height > 0)) return false;
        if (this.canvas.width === width && this.canvas.height === height) return false;
        this.canvas.width = width;
        this.canvas.height = height;
        return true;
      },
      render() {
        // A resize cleared the canvas, so the same data is drawn again.
        if (this.sizeToElement()) this.lastData = null;
        const base64Data = this.el.dataset.binary;
        if (!base64Data || base64Data === this.lastData) return;
        this.lastData = base64Data;
        this.bytes = decodeBase64(base64Data);
        this.draw();
      },
      // One replay of the last stream; while a motion runs, one per animation frame
      // (spec/10 §4.5).
      draw() {
        const ctx = this.ctx;
        ctx.setTransform(1, 0, 0, 1, 0, 0);
        ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);
        VisualizeMotion.begin(this.motion, performance.now());
        try {
          executeVisualizeBinary(ctx, this.bytes, 0, this.bytes.length, this.motion);
          clearVisualizeError(this.el);
        } catch (error) {
          reportVisualizeError(this.el, error);
          throw error;
        }
        if (VisualizeMotion.end(this.motion, ctx)) this.loop();
      },
      loop() {
        if (this.motionFrame !== null) return;
        this.motionFrame = requestAnimationFrame(() => { this.motionFrame = null; this.draw(); });
      }
    };
    """
  end
end
