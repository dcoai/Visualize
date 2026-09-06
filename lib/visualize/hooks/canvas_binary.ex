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
  `path_cubic` sub-opcode has a case, and an unknown byte throws rather than desynchronise
  silently. A full-matrix transform (`0xFF`) composes with `ctx.transform`.
  """

  @doc """
  Returns the JavaScript of the shared decoder: `decodeBase64`, `drawSvgArc` and
  `executeVisualizeBinary(ctx, bytes, startOffset, endOffset)`, which replays one stream
  and returns the offset it reached.
  """
  def js_decoder do
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

    // Replays one canvas binary stream (Visualize.Backend.CanvasBinary, spec/09 §4) on ctx
    // from startOffset up to endOffset (default: the end of bytes). Returns the offset
    // reached. Opcodes are those of Visualize.Backend.CanvasBinary.Opcodes; an unknown
    // byte is an encoder/decoder mismatch and throws.
    export function executeVisualizeBinary(ctx, bytes, startOffset, endOffset) {
      const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
      let offset = startOffset || 0;
      const maxOffset = endOffset === undefined ? bytes.length : endOffset;

      while (offset < maxOffset) {
        const cmd = bytes[offset++];

        switch (cmd) {
          case 0x01: { // path: one open polyline
            const count = view.getUint32(offset, true);
            offset += 4;
            ctx.beginPath();
            for (let i = 0; i < count; i++) {
              const x = view.getFloat64(offset, true);
              const y = view.getFloat64(offset + 8, true);
              offset += 16;
              if (i === 0) ctx.moveTo(x, y);
              else ctx.lineTo(x, y);
            }
            break;
          }

          case 0x02: { // path_cubic: the full command stream
            const cmdCount = view.getUint32(offset, true);
            offset += 4;
            ctx.beginPath();
            let curX = 0, curY = 0, startX = 0, startY = 0;
            for (let i = 0; i < cmdCount; i++) {
              const subcmd = bytes[offset++];
              switch (subcmd) {
                case 0x01: { // M
                  curX = view.getFloat64(offset, true);
                  curY = view.getFloat64(offset + 8, true);
                  startX = curX; startY = curY;
                  ctx.moveTo(curX, curY);
                  offset += 16;
                  break;
                }
                case 0x02: { // L
                  curX = view.getFloat64(offset, true);
                  curY = view.getFloat64(offset + 8, true);
                  ctx.lineTo(curX, curY);
                  offset += 16;
                  break;
                }
                case 0x03: { // C
                  const x1 = view.getFloat64(offset, true);
                  const y1 = view.getFloat64(offset + 8, true);
                  const x2 = view.getFloat64(offset + 16, true);
                  const y2 = view.getFloat64(offset + 24, true);
                  curX = view.getFloat64(offset + 32, true);
                  curY = view.getFloat64(offset + 40, true);
                  ctx.bezierCurveTo(x1, y1, x2, y2, curX, curY);
                  offset += 48;
                  break;
                }
                case 0x04: { // Q
                  const qx1 = view.getFloat64(offset, true);
                  const qy1 = view.getFloat64(offset + 8, true);
                  curX = view.getFloat64(offset + 16, true);
                  curY = view.getFloat64(offset + 24, true);
                  ctx.quadraticCurveTo(qx1, qy1, curX, curY);
                  offset += 32;
                  break;
                }
                case 0x05: { // Z
                  ctx.closePath();
                  curX = startX; curY = startY;
                  break;
                }
                case 0x06: { // A (absolute end point)
                  const rx = view.getFloat64(offset, true);
                  const ry = view.getFloat64(offset + 8, true);
                  const rotation = view.getFloat64(offset + 16, true) * Math.PI / 180;
                  const largeArc = view.getUint32(offset + 24, true);
                  const sweep = view.getUint32(offset + 28, true);
                  const x = view.getFloat64(offset + 32, true);
                  const y = view.getFloat64(offset + 40, true);
                  offset += 48;
                  drawSvgArc(ctx, curX, curY, rx, ry, rotation, largeArc, sweep, x, y);
                  curX = x; curY = y;
                  break;
                }
                case 0x07: { // a (end point relative to the current point)
                  const rx = view.getFloat64(offset, true);
                  const ry = view.getFloat64(offset + 8, true);
                  const rotation = view.getFloat64(offset + 16, true) * Math.PI / 180;
                  const largeArc = view.getUint32(offset + 24, true);
                  const sweep = view.getUint32(offset + 28, true);
                  const x = curX + view.getFloat64(offset + 32, true);
                  const y = curY + view.getFloat64(offset + 40, true);
                  offset += 48;
                  drawSvgArc(ctx, curX, curY, rx, ry, rotation, largeArc, sweep, x, y);
                  curX = x; curY = y;
                  break;
                }
                case 0x08: { // H
                  curX = view.getFloat64(offset, true);
                  ctx.lineTo(curX, curY);
                  offset += 8;
                  break;
                }
                case 0x09: { // V
                  curY = view.getFloat64(offset, true);
                  ctx.lineTo(curX, curY);
                  offset += 8;
                  break;
                }
                case 0x0A: { // h
                  curX += view.getFloat64(offset, true);
                  ctx.lineTo(curX, curY);
                  offset += 8;
                  break;
                }
                case 0x0B: { // v
                  curY += view.getFloat64(offset, true);
                  ctx.lineTo(curX, curY);
                  offset += 8;
                  break;
                }
                case 0x0C: { // m
                  curX += view.getFloat64(offset, true);
                  curY += view.getFloat64(offset + 8, true);
                  startX = curX; startY = curY;
                  ctx.moveTo(curX, curY);
                  offset += 16;
                  break;
                }
                case 0x0D: { // l
                  curX += view.getFloat64(offset, true);
                  curY += view.getFloat64(offset + 8, true);
                  ctx.lineTo(curX, curY);
                  offset += 16;
                  break;
                }
                case 0x0E: { // c
                  const dx1 = view.getFloat64(offset, true);
                  const dy1 = view.getFloat64(offset + 8, true);
                  const dx2 = view.getFloat64(offset + 16, true);
                  const dy2 = view.getFloat64(offset + 24, true);
                  const dx = view.getFloat64(offset + 32, true);
                  const dy = view.getFloat64(offset + 40, true);
                  ctx.bezierCurveTo(curX + dx1, curY + dy1, curX + dx2, curY + dy2, curX + dx, curY + dy);
                  curX += dx; curY += dy;
                  offset += 48;
                  break;
                }
                case 0x0F: { // q
                  const dx1 = view.getFloat64(offset, true);
                  const dy1 = view.getFloat64(offset + 8, true);
                  const dx = view.getFloat64(offset + 16, true);
                  const dy = view.getFloat64(offset + 24, true);
                  ctx.quadraticCurveTo(curX + dx1, curY + dy1, curX + dx, curY + dy);
                  curX += dx; curY += dy;
                  offset += 32;
                  break;
                }
                default:
                  throw new Error('Unknown canvas binary path command 0x' + subcmd.toString(16) + ' at offset ' + (offset - 1));
              }
            }
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
              const r = bytes[offset++], g = bytes[offset++], b = bytes[offset++], a = bytes[offset++];
              ctx.fillStyle = `rgba(${r},${g},${b},${a / 255})`;
            }
            if (flags & 0x02) { // stroke colour
              const r = bytes[offset++], g = bytes[offset++], b = bytes[offset++], a = bytes[offset++];
              ctx.strokeStyle = `rgba(${r},${g},${b},${a / 255})`;
            }
            if (flags & 0x04) { // stroke width
              ctx.lineWidth = view.getFloat32(offset, true);
              offset += 4;
            }
            if (flags & 0x08) { // global alpha
              ctx.globalAlpha = view.getFloat32(offset, true);
              offset += 4;
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
            break;

          case 0x31: // restore
            ctx.restore();
            break;

          case 0x40: // fill
            ctx.fill();
            break;

          case 0x41: // stroke
            ctx.stroke();
            break;

          default:
            throw new Error('Unknown canvas binary opcode 0x' + cmd.toString(16) + ' at offset ' + (offset - 1));
        }
      }

      return offset;
    }
    """
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

        this.handleEvent("canvas_update", ({binary}) => {
          this.el.dataset.binary = binary;
          this.render();
        });

        this.render();
      },
      destroyed() {},
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
      render() {
        const base64Data = this.el.dataset.binary;
        if (!base64Data || base64Data === this.lastData) return;
        this.lastData = base64Data;

        const ctx = this.ctx;
        ctx.setTransform(1, 0, 0, 1, 0, 0);
        ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);
        executeVisualizeBinary(ctx, decodeBase64(base64Data));
      }
    };
    """
  end
end
