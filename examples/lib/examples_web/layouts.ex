defmodule ExamplesWeb.Layouts do
  use Phoenix.Component

  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8"/>
        <meta name="viewport" content="width=device-width, initial-scale=1"/>
        <title>Visualize Examples - D3-style Charts in Elixir</title>
        <style>
          * { box-sizing: border-box; margin: 0; padding: 0; }
          body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
            background: #f5f5f5;
            color: #333;
            line-height: 1.6;
          }
          header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 2rem;
            text-align: center;
          }
          header h1 { font-size: 2.5rem; margin-bottom: 0.5rem; }
          header p { opacity: 0.9; font-size: 1.1rem; }
          main { padding: 2rem; max-width: 1400px; margin: 0 auto; }
          .gallery {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(350px, 1fr));
            gap: 1.5rem;
          }
          .chart-card {
            background: white;
            border-radius: 12px;
            box-shadow: 0 4px 6px rgba(0,0,0,0.1);
            overflow: hidden;
            transition: transform 0.2s, box-shadow 0.2s;
          }
          .chart-card:hover {
            transform: translateY(-4px);
            box-shadow: 0 8px 25px rgba(0,0,0,0.15);
          }
          .chart-card a { text-decoration: none; color: inherit; display: block; }
          .chart-preview {
            background: white;
            padding: 1rem;
            display: flex;
            justify-content: center;
            align-items: center;
            min-height: 250px;
            border-bottom: 1px solid #eee;
          }
          .chart-preview svg { max-width: 100%; height: auto; }
          .chart-info { padding: 1rem 1.5rem; }
          .chart-info h3 { font-size: 1.1rem; color: #333; margin-bottom: 0.25rem; }
          .chart-info p { font-size: 0.85rem; color: #666; }
          .tools-bar {
            display: flex;
            gap: 1rem;
            margin-bottom: 1.5rem;
          }
          .tool-link {
            display: inline-flex;
            align-items: center;
            gap: 0.5rem;
            padding: 0.75rem 1.25rem;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            text-decoration: none;
            border-radius: 8px;
            font-weight: 500;
            transition: transform 0.2s, box-shadow 0.2s;
          }
          .tool-link:hover {
            transform: translateY(-2px);
            box-shadow: 0 4px 12px rgba(102, 126, 234, 0.4);
          }
          .tool-icon { font-size: 1.2rem; }
          .back-link {
            display: inline-flex;
            align-items: center;
            gap: 0.5rem;
            color: #667eea;
            text-decoration: none;
            margin-bottom: 1.5rem;
            font-weight: 500;
          }
          .back-link:hover { text-decoration: underline; }
          .chart-detail { background: white; border-radius: 12px; padding: 2rem; box-shadow: 0 4px 6px rgba(0,0,0,0.1); }
          .chart-detail h2 { margin-bottom: 1rem; color: #333; }
          .chart-detail .chart-container { margin: 1rem 0; display: flex; justify-content: center; }
          .chart-detail svg { max-width: 100%; height: auto; }
          pre {
            background: #1e1e1e;
            color: #d4d4d4;
            padding: 1rem;
            border-radius: 8px;
            overflow-x: auto;
            font-size: 0.85rem;
            line-height: 1.5;
            margin-top: 1.5rem;
          }
          code { font-family: 'Monaco', 'Menlo', 'Ubuntu Mono', monospace; }
        </style>
        <script defer src="https://unpkg.com/phoenix_html@4.2.0/priv/static/phoenix_html.js"></script>
        <script defer src="https://unpkg.com/phoenix@1.7.21/priv/static/phoenix.min.js"></script>
        <script defer src="https://unpkg.com/phoenix_live_view@1.1.19/priv/static/phoenix_live_view.min.js"></script>
        <script>
          // Canvas rendering hook for Visualize library (JSON format)
          const CanvasChart = {
            mounted() {
              this.canvas = this.el.querySelector('canvas') || this.createCanvas();
              this.ctx = this.canvas.getContext('2d');
              this.lastCommands = null;

              // Listen for push_event from LiveView
              this.handleEvent("canvas_commands", ({commands}) => {
                this.el.dataset.commands = commands;
                this.render();
              });
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
              const commands = this.el.dataset.commands;
              if (!commands || commands.length === 0 || commands === this.lastCommands) return;
              this.lastCommands = commands;

              const ctx = this.ctx;
              ctx.setTransform(1, 0, 0, 1, 0, 0);
              ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);

              try {
                const cmds = JSON.parse(commands);
                cmds.forEach(cmd => {
                  const method = cmd.cmd || cmd[0];
                  const args = cmd.args || cmd[1] || [];

                  if (method.startsWith('set_')) {
                    ctx[method.slice(4)] = args[0];
                  } else if (typeof ctx[method] === 'function') {
                    ctx[method](...args);
                  } else if (method in ctx) {
                    ctx[method] = args[0];
                  }
                });
              } catch (e) {
                console.warn('Canvas parse error:', e);
              }
            }
          };

          // SVG arc to Canvas ellipse conversion helper
          // Implements the endpoint-to-center parameterization from SVG spec
          function drawSvgArc(ctx, x1, y1, rx, ry, phi, fA, fS, x2, y2) {
            // Handle degenerate cases
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

            // Compute start angle
            let n = Math.sqrt(ux * ux + uy * uy);
            let p = ux;
            let theta1 = (uy < 0 ? -1 : 1) * Math.acos(p / n);

            // Compute delta angle
            n = Math.sqrt((ux * ux + uy * uy) * (vx * vx + vy * vy));
            p = ux * vx + uy * vy;
            let dtheta = (ux * vy - uy * vx < 0 ? -1 : 1) * Math.acos(Math.max(-1, Math.min(1, p / n)));

            if (fS === 0 && dtheta > 0) dtheta -= 2 * Math.PI;
            if (fS === 1 && dtheta < 0) dtheta += 2 * Math.PI;

            // Draw the arc using canvas ellipse
            ctx.ellipse(cx, cy, rx, ry, phi, theta1, theta1 + dtheta, fS === 0);
          }

          // Binary Canvas rendering hook - decodes compact binary format
          // Command types: 0x01=path, 0x02=cubic_path, 0x03=circles, 0x10=style, 0x20=transform
          const CanvasBinaryChart = {
            mounted() {
              this.canvas = this.el.querySelector('canvas') || this.createCanvas();
              this.ctx = this.canvas.getContext('2d');
              this.lastData = null;

              // Listen for push_event from LiveView
              this.handleEvent("canvas_update", ({binary}) => {
                this.el.dataset.binary = binary;
                this.render();
              });

              // Initial render from data-binary attribute
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
              this.el.appendChild(canvas);
              return canvas;
            },
            render() {
              const base64Data = this.el.dataset.binary;
              console.log('CanvasBinaryChart render called, data length:', base64Data ? base64Data.length : 0);
              if (!base64Data || base64Data === this.lastData) {
                console.log('Skipping render - no data or same data');
                return;
              }
              this.lastData = base64Data;

              const ctx = this.ctx;
              // Reset transform before clearing
              ctx.setTransform(1, 0, 0, 1, 0, 0);
              ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);

              try {
                // Decode base64 to binary
                const binaryStr = atob(base64Data);
                const bytes = new Uint8Array(binaryStr.length);
                for (let i = 0; i < binaryStr.length; i++) {
                  bytes[i] = binaryStr.charCodeAt(i);
                }
                console.log('Decoded binary, bytes:', bytes.length);
                this.executeBinary(ctx, bytes);
                console.log('executeBinary completed');
              } catch (e) {
                console.warn('Binary decode error:', e);
              }
            },
            executeBinary(ctx, bytes) {
              const view = new DataView(bytes.buffer);
              let offset = 0;
              let fillColor = null;
              let strokeColor = null;
              let stats = {save:0, restore:0, transform:0, style:0, path:0, cubicPath:0, stroke:0, fill:0, rect:0, circle:0};

              while (offset < bytes.length) {
                const cmd = bytes[offset++];

                switch (cmd) {
                  case 0x01: { // Simple path (moveTo + lineTo sequence)
                    stats.path++;
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

                  case 0x02: { // Cubic path with full commands
                    stats.cubicPath++;
                    const cmdCount = view.getUint32(offset, true);
                    offset += 4;
                    ctx.beginPath();
                    let curX = 0, curY = 0;
                    for (let i = 0; i < cmdCount; i++) {
                      const subcmd = bytes[offset++];
                      switch (subcmd) {
                        case 0x01: { // moveTo
                          curX = view.getFloat64(offset, true);
                          curY = view.getFloat64(offset + 8, true);
                          ctx.moveTo(curX, curY);
                          offset += 16;
                          break;
                        }
                        case 0x02: { // lineTo
                          curX = view.getFloat64(offset, true);
                          curY = view.getFloat64(offset + 8, true);
                          ctx.lineTo(curX, curY);
                          offset += 16;
                          break;
                        }
                        case 0x03: { // bezierCurveTo
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
                        case 0x04: { // quadraticCurveTo
                          const qx1 = view.getFloat64(offset, true);
                          const qy1 = view.getFloat64(offset + 8, true);
                          curX = view.getFloat64(offset + 16, true);
                          curY = view.getFloat64(offset + 24, true);
                          ctx.quadraticCurveTo(qx1, qy1, curX, curY);
                          offset += 32;
                          break;
                        }
                        case 0x05: // closePath
                          ctx.closePath();
                          break;
                        case 0x06: { // SVG arc (absolute)
                          const rx = view.getFloat64(offset, true);
                          const ry = view.getFloat64(offset + 8, true);
                          const rotation = view.getFloat64(offset + 16, true) * Math.PI / 180;
                          const largeArc = view.getInt32(offset + 24, true);
                          const sweep = view.getInt32(offset + 28, true);
                          const x = view.getFloat64(offset + 32, true);
                          const y = view.getFloat64(offset + 40, true);
                          offset += 48;
                          drawSvgArc(ctx, curX, curY, rx, ry, rotation, largeArc, sweep, x, y);
                          curX = x; curY = y;
                          break;
                        }
                        case 0x08: { // H - horizontal lineTo (absolute)
                          curX = view.getFloat64(offset, true);
                          ctx.lineTo(curX, curY);
                          offset += 8;
                          break;
                        }
                        case 0x09: { // V - vertical lineTo (absolute)
                          curY = view.getFloat64(offset, true);
                          ctx.lineTo(curX, curY);
                          offset += 8;
                          break;
                        }
                        case 0x0A: { // h - horizontal lineTo (relative)
                          const dx = view.getFloat64(offset, true);
                          curX += dx;
                          ctx.lineTo(curX, curY);
                          offset += 8;
                          break;
                        }
                        case 0x0B: { // v - vertical lineTo (relative)
                          const dy = view.getFloat64(offset, true);
                          curY += dy;
                          ctx.lineTo(curX, curY);
                          offset += 8;
                          break;
                        }
                        case 0x0C: { // m - relative moveTo
                          const dx = view.getFloat64(offset, true);
                          const dy = view.getFloat64(offset + 8, true);
                          curX += dx; curY += dy;
                          ctx.moveTo(curX, curY);
                          offset += 16;
                          break;
                        }
                        case 0x0D: { // l - relative lineTo
                          const dx = view.getFloat64(offset, true);
                          const dy = view.getFloat64(offset + 8, true);
                          curX += dx; curY += dy;
                          ctx.lineTo(curX, curY);
                          offset += 16;
                          break;
                        }
                        case 0x0E: { // c - relative bezierCurveTo
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
                        case 0x0F: { // q - relative quadraticCurveTo
                          const dx1 = view.getFloat64(offset, true);
                          const dy1 = view.getFloat64(offset + 8, true);
                          const dx = view.getFloat64(offset + 16, true);
                          const dy = view.getFloat64(offset + 24, true);
                          ctx.quadraticCurveTo(curX + dx1, curY + dy1, curX + dx, curY + dy);
                          curX += dx; curY += dy;
                          offset += 32;
                          break;
                        }
                      }
                    }
                    break;
                  }

                  case 0x03: { // Circles
                    const count = view.getUint32(offset, true);
                    offset += 4;
                    for (let i = 0; i < count; i++) {
                      const cx = view.getFloat64(offset, true);
                      const cy = view.getFloat64(offset + 8, true);
                      const r = view.getFloat64(offset + 16, true);
                      offset += 24;
                      ctx.beginPath();
                      ctx.arc(cx, cy, r, 0, Math.PI * 2);
                      if (fillColor) ctx.fill();
                      if (strokeColor) ctx.stroke();
                    }
                    break;
                  }

                  case 0x04: { // Rectangles
                    const count = view.getUint32(offset, true);
                    offset += 4;
                    for (let i = 0; i < count; i++) {
                      const x = view.getFloat64(offset, true);
                      const y = view.getFloat64(offset + 8, true);
                      const w = view.getFloat64(offset + 16, true);
                      const h = view.getFloat64(offset + 24, true);
                      offset += 32;
                      ctx.beginPath();
                      ctx.rect(x, y, w, h);
                      if (fillColor) ctx.fill();
                      if (strokeColor) ctx.stroke();
                    }
                    break;
                  }

                  case 0x10: { // Style
                    stats.style++;
                    const flags = bytes[offset++];
                    if (flags & 0x01) { // fill color
                      const r = bytes[offset++], g = bytes[offset++], b = bytes[offset++], a = bytes[offset++];
                      fillColor = `rgba(${r},${g},${b},${a/255})`;
                      ctx.fillStyle = fillColor;
                    }
                    if (flags & 0x02) { // stroke color
                      const r = bytes[offset++], g = bytes[offset++], b = bytes[offset++], a = bytes[offset++];
                      strokeColor = `rgba(${r},${g},${b},${a/255})`;
                      ctx.strokeStyle = strokeColor;
                    }
                    if (flags & 0x04) { // stroke width
                      ctx.lineWidth = view.getFloat32(offset, true);
                      offset += 4;
                    }
                    if (flags & 0x08) { // opacity
                      ctx.globalAlpha = view.getFloat32(offset, true);
                      offset += 4;
                    }
                    break;
                  }

                  case 0x20: { // Transform
                    stats.transform++;
                    const type = bytes[offset++];
                    if (type === 0x01) { // translate
                      ctx.translate(
                        view.getFloat64(offset, true),
                        view.getFloat64(offset + 8, true)
                      );
                      offset += 16;
                    } else if (type === 0x03) { // translate + scale
                      ctx.translate(
                        view.getFloat64(offset, true),
                        view.getFloat64(offset + 8, true)
                      );
                      ctx.scale(
                        view.getFloat64(offset + 16, true),
                        view.getFloat64(offset + 24, true)
                      );
                      offset += 32;
                    } else if (type === 0xFF) { // full matrix
                      ctx.transform(
                        view.getFloat64(offset, true),
                        view.getFloat64(offset + 8, true),
                        view.getFloat64(offset + 16, true),
                        view.getFloat64(offset + 24, true),
                        view.getFloat64(offset + 32, true),
                        view.getFloat64(offset + 40, true)
                      );
                      offset += 48;
                    }
                    break;
                  }

                  case 0x30: // save
                    stats.save++;
                    ctx.save();
                    break;

                  case 0x31: // restore
                    stats.restore++;
                    ctx.restore();
                    break;

                  case 0x40: // fill
                    stats.fill++;
                    ctx.fill();
                    break;

                  case 0x41: // stroke
                    stats.stroke++;
                    ctx.stroke();
                    break;

                  default:
                    console.warn('Unknown binary command:', cmd, 'at offset', offset - 1);
                    console.log('Partial stats:', stats);
                    return; // Stop processing on unknown command
                }
              }
              console.log('Render stats:', stats);
            }
          };

          // Multi-path Binary Canvas hook - handles comma-separated base64 paths
          const CanvasMultiBinaryChart = {
            mounted() {
              this.canvas = this.el.querySelector('canvas') || this.createCanvas();
              this.ctx = this.canvas.getContext('2d');
              this.lastData = null;
              this.render();

              // Listen for push_event from LiveView
              this.handleEvent("canvas_update", ({binary}) => {
                this.el.dataset.binary = binary;
                this.render();
              });
            },
            destroyed() {
              // No cleanup needed
            },
            updated() {
              this.render();
            },
            createCanvas() {
              const canvas = document.createElement('canvas');
              canvas.width = parseInt(this.el.dataset.width) || 800;
              canvas.height = parseInt(this.el.dataset.height) || 600;
              this.el.appendChild(canvas);
              return canvas;
            },
            render() {
              const base64Data = this.el.dataset.binary;
              if (!base64Data || base64Data === this.lastData) return;
              this.lastData = base64Data;

              const ctx = this.ctx;
              ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);

              // Handle multiple paths (comma-separated base64 strings)
              const paths = base64Data.split(',');
              for (const pathData of paths) {
                if (!pathData.trim()) continue;
                try {
                  const binaryStr = atob(pathData.trim());
                  const bytes = new Uint8Array(binaryStr.length);
                  for (let i = 0; i < binaryStr.length; i++) {
                    bytes[i] = binaryStr.charCodeAt(i);
                  }
                  this.executeBinary(ctx, bytes);
                } catch (e) {
                  console.warn('Binary decode error:', e);
                }
              }
            },
            executeBinary(ctx, bytes) {
              const view = new DataView(bytes.buffer);
              let offset = 0;
              let fillColor = null;
              let strokeColor = null;

              while (offset < bytes.length) {
                const cmd = bytes[offset++];

                switch (cmd) {
                  case 0x01: { // Simple path
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

                  case 0x10: { // Style
                    const flags = bytes[offset++];
                    if (flags & 0x01) {
                      const r = bytes[offset++], g = bytes[offset++], b = bytes[offset++], a = bytes[offset++];
                      fillColor = `rgba(${r},${g},${b},${a/255})`;
                      ctx.fillStyle = fillColor;
                    }
                    if (flags & 0x02) {
                      const r = bytes[offset++], g = bytes[offset++], b = bytes[offset++], a = bytes[offset++];
                      strokeColor = `rgba(${r},${g},${b},${a/255})`;
                      ctx.strokeStyle = strokeColor;
                    }
                    if (flags & 0x04) {
                      ctx.lineWidth = view.getFloat32(offset, true);
                      offset += 4;
                    }
                    if (flags & 0x08) {
                      ctx.globalAlpha = view.getFloat32(offset, true);
                      offset += 4;
                    }
                    break;
                  }

                  case 0x40: // fill
                    ctx.fill();
                    break;

                  case 0x41: // stroke
                    ctx.stroke();
                    break;

                  default:
                    return;
                }
              }
            }
          };

          // Incremental Canvas hook - uses copy+shift optimization for scrolling
          // Command 0x60: incremental update with scroll offset and exposed regions
          const CanvasIncrementalChart = {
            mounted() {
              this.canvas = this.el.querySelector('canvas') || this.createCanvas();
              this.ctx = this.canvas.getContext('2d');

              // Offscreen buffer for copy operations
              this.offscreen = document.createElement('canvas');
              this.offscreen.width = this.canvas.width;
              this.offscreen.height = this.canvas.height;
              this.offscreenCtx = this.offscreen.getContext('2d');

              this.lastData = null;

              // Listen for incremental updates from LiveView
              this.handleEvent("canvas_incremental", (payload) => {
                this.handleIncremental(payload);
              });
            },
            destroyed() {},
            updated() {},
            createCanvas() {
              const canvas = document.createElement('canvas');
              canvas.width = parseInt(this.el.dataset.width) || 800;
              canvas.height = parseInt(this.el.dataset.height) || 600;
              this.el.appendChild(canvas);
              return canvas;
            },

            handleIncremental(payload) {
              const {binary, dx, dy, mode} = payload;

              if (mode === 'full') {
                this.fullRender(binary);
                return;
              }

              // Decode base64 to binary
              let bytes;
              try {
                const binaryStr = atob(binary);
                bytes = new Uint8Array(binaryStr.length);
                for (let i = 0; i < binaryStr.length; i++) {
                  bytes[i] = binaryStr.charCodeAt(i);
                }
              } catch (e) {
                console.warn('Binary decode error:', e);
                return;
              }

              // Copy+shift optimization
              this.incrementalRender(bytes, dx, dy);
            },

            fullRender(base64Data) {
              try {
                const binaryStr = atob(base64Data);
                const bytes = new Uint8Array(binaryStr.length);
                for (let i = 0; i < binaryStr.length; i++) {
                  bytes[i] = binaryStr.charCodeAt(i);
                }

                const ctx = this.ctx;
                ctx.setTransform(1, 0, 0, 1, 0, 0);
                ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);

                // Skip the 0x60 header and mode bytes, then execute the element data
                this.executeFullRedraw(ctx, bytes);
              } catch (e) {
                console.warn('Full render error:', e);
              }
            },

            incrementalRender(bytes, dx, dy) {
              const ctx = this.ctx;
              const offCtx = this.offscreenCtx;

              // Round to integers to prevent canvas blur from sub-pixel rendering
              const intDx = Math.round(dx);
              const intDy = Math.round(dy);

              // 1. Copy current canvas to offscreen buffer
              offCtx.clearRect(0, 0, this.offscreen.width, this.offscreen.height);
              offCtx.drawImage(this.canvas, 0, 0);

              // 2. Clear main canvas
              ctx.setTransform(1, 0, 0, 1, 0, 0);
              ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);

              // 3. Draw shifted copy from offscreen buffer
              // dx > 0 means content moves left, so we draw at -intDx
              ctx.drawImage(this.offscreen, -intDx, -intDy);

              // 4. Parse and render the exposed regions
              this.executeIncrementalBinary(ctx, bytes);
            },

            executeFullRedraw(ctx, bytes) {
              const view = new DataView(bytes.buffer);
              let offset = 0;

              // Check for 0x60 header
              if (bytes[offset] === 0x60) {
                offset++; // Skip header
                offset++; // Skip mode (0x00 = full)
                offset += 4; // Skip dx
                offset += 4; // Skip dy
                offset++; // Skip region_count (0 for full redraw)
              }

              // Execute remaining commands
              this.executeBinaryCommands(ctx, bytes, view, offset);
            },

            executeIncrementalBinary(ctx, bytes) {
              const view = new DataView(bytes.buffer);
              let offset = 0;

              // Parse 0x60 header
              if (bytes[offset] !== 0x60) {
                console.warn('Expected incremental header 0x60, got', bytes[offset]);
                return;
              }
              offset++;

              const mode = bytes[offset++];
              const dxHeader = view.getFloat32(offset, true); offset += 4;
              const dyHeader = view.getFloat32(offset, true); offset += 4;
              const regionCount = bytes[offset++];

              // Process each region
              for (let r = 0; r < regionCount; r++) {
                const rx = view.getFloat32(offset, true); offset += 4;
                const ry = view.getFloat32(offset, true); offset += 4;
                const rw = view.getFloat32(offset, true); offset += 4;
                const rh = view.getFloat32(offset, true); offset += 4;
                const dataLength = view.getUint32(offset, true); offset += 4;

                // Clip to region and execute commands
                ctx.save();
                ctx.beginPath();
                ctx.rect(rx, ry, rw, rh);
                ctx.clip();

                // Execute commands for this region
                const endOffset = offset + dataLength;
                this.executeBinaryCommands(ctx, bytes, view, offset, endOffset);
                offset = endOffset;

                ctx.restore();
              }
            },

            executeBinaryCommands(ctx, bytes, view, startOffset, endOffset) {
              let offset = startOffset;
              const maxOffset = endOffset || bytes.length;
              let fillColor = null;
              let strokeColor = null;

              while (offset < maxOffset) {
                const cmd = bytes[offset++];

                switch (cmd) {
                  case 0x01: { // Simple path
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

                  case 0x02: { // Cubic path
                    const cmdCount = view.getUint32(offset, true);
                    offset += 4;
                    ctx.beginPath();
                    let curX = 0, curY = 0;
                    for (let i = 0; i < cmdCount; i++) {
                      const subcmd = bytes[offset++];
                      switch (subcmd) {
                        case 0x01: // moveTo
                          curX = view.getFloat64(offset, true);
                          curY = view.getFloat64(offset + 8, true);
                          ctx.moveTo(curX, curY);
                          offset += 16;
                          break;
                        case 0x02: // lineTo
                          curX = view.getFloat64(offset, true);
                          curY = view.getFloat64(offset + 8, true);
                          ctx.lineTo(curX, curY);
                          offset += 16;
                          break;
                        case 0x03: // bezierCurveTo
                          ctx.bezierCurveTo(
                            view.getFloat64(offset, true), view.getFloat64(offset + 8, true),
                            view.getFloat64(offset + 16, true), view.getFloat64(offset + 24, true),
                            view.getFloat64(offset + 32, true), view.getFloat64(offset + 40, true)
                          );
                          curX = view.getFloat64(offset + 32, true);
                          curY = view.getFloat64(offset + 40, true);
                          offset += 48;
                          break;
                        case 0x04: // quadraticCurveTo
                          ctx.quadraticCurveTo(
                            view.getFloat64(offset, true), view.getFloat64(offset + 8, true),
                            view.getFloat64(offset + 16, true), view.getFloat64(offset + 24, true)
                          );
                          curX = view.getFloat64(offset + 16, true);
                          curY = view.getFloat64(offset + 24, true);
                          offset += 32;
                          break;
                        case 0x05: // closePath
                          ctx.closePath();
                          break;
                        case 0x06: { // SVG arc (absolute)
                          const rx = view.getFloat64(offset, true);
                          const ry = view.getFloat64(offset + 8, true);
                          const rotation = view.getFloat64(offset + 16, true) * Math.PI / 180;
                          const largeArc = view.getInt32(offset + 24, true);
                          const sweep = view.getInt32(offset + 28, true);
                          const x = view.getFloat64(offset + 32, true);
                          const y = view.getFloat64(offset + 40, true);
                          offset += 48;
                          drawSvgArc(ctx, curX, curY, rx, ry, rotation, largeArc, sweep, x, y);
                          curX = x; curY = y;
                          break;
                        }
                        case 0x08: { // H - horizontal lineTo (absolute)
                          curX = view.getFloat64(offset, true);
                          ctx.lineTo(curX, curY);
                          offset += 8;
                          break;
                        }
                        case 0x09: { // V - vertical lineTo (absolute)
                          curY = view.getFloat64(offset, true);
                          ctx.lineTo(curX, curY);
                          offset += 8;
                          break;
                        }
                        case 0x0A: { // h - horizontal lineTo (relative)
                          const dx = view.getFloat64(offset, true);
                          curX += dx;
                          ctx.lineTo(curX, curY);
                          offset += 8;
                          break;
                        }
                        case 0x0B: { // v - vertical lineTo (relative)
                          const dy = view.getFloat64(offset, true);
                          curY += dy;
                          ctx.lineTo(curX, curY);
                          offset += 8;
                          break;
                        }
                        case 0x0C: { // m - relative moveTo
                          const dx = view.getFloat64(offset, true);
                          const dy = view.getFloat64(offset + 8, true);
                          curX += dx; curY += dy;
                          ctx.moveTo(curX, curY);
                          offset += 16;
                          break;
                        }
                        case 0x0D: { // l - relative lineTo
                          const dx = view.getFloat64(offset, true);
                          const dy = view.getFloat64(offset + 8, true);
                          curX += dx; curY += dy;
                          ctx.lineTo(curX, curY);
                          offset += 16;
                          break;
                        }
                        case 0x0E: { // c - relative bezierCurveTo
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
                        case 0x0F: { // q - relative quadraticCurveTo
                          const dx1 = view.getFloat64(offset, true);
                          const dy1 = view.getFloat64(offset + 8, true);
                          const dx = view.getFloat64(offset + 16, true);
                          const dy = view.getFloat64(offset + 24, true);
                          ctx.quadraticCurveTo(curX + dx1, curY + dy1, curX + dx, curY + dy);
                          curX += dx; curY += dy;
                          offset += 32;
                          break;
                        }
                      }
                    }
                    break;
                  }

                  case 0x03: { // Circles
                    const count = view.getUint32(offset, true);
                    offset += 4;
                    for (let i = 0; i < count; i++) {
                      const cx = view.getFloat64(offset, true);
                      const cy = view.getFloat64(offset + 8, true);
                      const r = view.getFloat64(offset + 16, true);
                      offset += 24;
                      ctx.beginPath();
                      ctx.arc(cx, cy, r, 0, Math.PI * 2);
                    }
                    break;
                  }

                  case 0x04: { // Rectangles
                    const count = view.getUint32(offset, true);
                    offset += 4;
                    for (let i = 0; i < count; i++) {
                      const x = view.getFloat64(offset, true);
                      const y = view.getFloat64(offset + 8, true);
                      const w = view.getFloat64(offset + 16, true);
                      const h = view.getFloat64(offset + 24, true);
                      offset += 32;
                      ctx.beginPath();
                      ctx.rect(x, y, w, h);
                    }
                    break;
                  }

                  case 0x10: { // Style
                    const flags = bytes[offset++];
                    if (flags & 0x01) {
                      const r = bytes[offset++], g = bytes[offset++], b = bytes[offset++], a = bytes[offset++];
                      fillColor = `rgba(${r},${g},${b},${a/255})`;
                      ctx.fillStyle = fillColor;
                    }
                    if (flags & 0x02) {
                      const r = bytes[offset++], g = bytes[offset++], b = bytes[offset++], a = bytes[offset++];
                      strokeColor = `rgba(${r},${g},${b},${a/255})`;
                      ctx.strokeStyle = strokeColor;
                    }
                    if (flags & 0x04) {
                      ctx.lineWidth = view.getFloat32(offset, true);
                      offset += 4;
                    }
                    if (flags & 0x08) {
                      ctx.globalAlpha = view.getFloat32(offset, true);
                      offset += 4;
                    }
                    break;
                  }

                  case 0x20: { // Transform
                    const type = bytes[offset++];
                    switch (type) {
                      case 0x01: // translate
                        ctx.translate(view.getFloat64(offset, true), view.getFloat64(offset + 8, true));
                        offset += 16;
                        break;
                      case 0x03: // translate + scale
                        ctx.translate(view.getFloat64(offset, true), view.getFloat64(offset + 8, true));
                        ctx.scale(view.getFloat64(offset + 16, true), view.getFloat64(offset + 24, true));
                        offset += 32;
                        break;
                      case 0xFF: // full matrix
                        ctx.setTransform(
                          view.getFloat64(offset, true), view.getFloat64(offset + 8, true),
                          view.getFloat64(offset + 16, true), view.getFloat64(offset + 24, true),
                          view.getFloat64(offset + 32, true), view.getFloat64(offset + 40, true)
                        );
                        offset += 48;
                        break;
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
                    console.warn('Unknown command:', cmd, 'at offset', offset - 1);
                    return offset;
                }
              }
              return offset;
            }
          };

          document.addEventListener("DOMContentLoaded", () => {
            let csrfToken = document.querySelector("meta[name='csrf-token']")?.getAttribute("content");
            let liveSocket = new window.LiveView.LiveSocket("/live", window.Phoenix.Socket, {
              params: { _csrf_token: csrfToken },
              hooks: { CanvasChart, CanvasBinaryChart, CanvasMultiBinaryChart, CanvasIncrementalChart }
            });
            liveSocket.connect();
            window.liveSocket = liveSocket;
          });
        </script>
        <meta name="csrf-token" content={Phoenix.Controller.get_csrf_token()} />
      </head>
      <body>
        <%= @inner_content %>
      </body>
    </html>
    """
  end

  def app(assigns) do
    ~H"""
    <%= @inner_content %>
    """
  end
end
