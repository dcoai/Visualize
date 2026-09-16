defmodule Visualize.Hooks.CanvasIncremental do
  @moduledoc """
  Phoenix LiveView hook for scroll-and-copy incremental canvas rendering.

  `CanvasIncrementalChart` handles the `canvas_incremental` events that
  `Visualize.Incremental` builds (spec/09 §7.3): a `"full"` payload clears the canvas and
  replays the whole stream; a scroll payload copies the existing pixels shifted by the
  delta and replays each exposed region of the `0x60` record clipped to its bounds
  (spec/09 §5.5); a `"none"` payload is ignored.

  ## Usage

      <div id="chart" phx-hook="CanvasIncrementalChart" phx-update="ignore"
           data-width="800" data-height="600">
        <canvas width="800" height="600"></canvas>
      </div>

      {event, payload, state} = Visualize.Incremental.scroll(state, {dx, dy})
      push_event(socket, event, payload)

  Decoding is `executeVisualizeBinary` from `Visualize.Hooks.CanvasBinary.js_decoder/0`.
  """

  @doc """
  Returns the JavaScript code for the CanvasIncrementalChart hook.

  Requires the decoder of `Visualize.Hooks.CanvasBinary.js_decoder/0` in the same module;
  `Visualize.Hooks.js_code/0` includes both.
  """
  def js_hook do
    ~S"""
    export const CanvasIncrementalChart = {
      mounted() {
        this.canvas = this.el.querySelector('canvas') || this.createCanvas();
        this.ctx = this.canvas.getContext('2d');

        // Offscreen buffer for the copy-shift
        this.offscreen = document.createElement('canvas');
        this.offscreen.width = this.canvas.width;
        this.offscreen.height = this.canvas.height;
        this.offscreenCtx = this.offscreen.getContext('2d');

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
        canvas.style.display = 'block';
        this.el.appendChild(canvas);
        return canvas;
      },

      handleIncremental({binary, dx, dy, mode}) {
        if (mode === 'none') return;
        try {
          const bytes = decodeBase64(binary);
          if (mode === 'full') {
            this.fullRender(bytes);
          } else {
            this.incrementalRender(bytes, dx, dy);
          }
          clearVisualizeError(this.el);
        } catch (error) {
          reportVisualizeError(this.el, error);
          throw error;
        }
      },

      // 0x60 mode:u8 dx:f32 dy:f32 vx:f32 vy:f32 vw:f32 vh:f32 region_count:u8, then the
      // whole stream (spec/09 §5.6).
      fullRender(bytes) {
        const ctx = this.ctx;
        ctx.setTransform(1, 0, 0, 1, 0, 0);
        ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);
        if (bytes[0] !== 0x60) {
          throw new Error('Expected incremental header 0x60, got 0x' + bytes[0].toString(16));
        }
        executeVisualizeBinary(ctx, bytes, 27);
      },

      // The viewport of the record at bytes 10-25: the rectangle that scrolls (D-106).
      readViewport(bytes) {
        const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
        return {
          x: view.getFloat32(10, true),
          y: view.getFloat32(14, true),
          w: view.getFloat32(18, true),
          h: view.getFloat32(22, true)
        };
      },

      incrementalRender(bytes, dx, dy) {
        const ctx = this.ctx;
        const offCtx = this.offscreenCtx;
        if (bytes[0] !== 0x60) {
          throw new Error('Expected incremental header 0x60, got 0x' + bytes[0].toString(16));
        }
        const v = this.readViewport(bytes);

        // Integer shifts: a sub-pixel copy blurs the canvas.
        const intDx = Math.round(dx);
        const intDy = Math.round(dy);

        offCtx.clearRect(0, 0, this.offscreen.width, this.offscreen.height);
        offCtx.drawImage(this.canvas, 0, 0);

        // Only the viewport scrolls: clear it, copy its own pixels back shifted, and
        // leave every pixel outside it — a margin's axes — as it was (spec/09 §5.5).
        ctx.setTransform(1, 0, 0, 1, 0, 0);
        ctx.save();
        ctx.beginPath();
        ctx.rect(v.x, v.y, v.w, v.h);
        ctx.clip();
        ctx.clearRect(v.x, v.y, v.w, v.h);
        // dx > 0 means the content moved left, so the copy lands at -dx.
        ctx.drawImage(this.offscreen, v.x, v.y, v.w, v.h, v.x - intDx, v.y - intDy, v.w, v.h);
        ctx.restore();

        this.executeRegions(ctx, bytes);
      },

      // After the 27-byte header, per region x:f32 y:f32 w:f32 h:f32 data_length:u32 data
      // (spec/09 §5.5).
      executeRegions(ctx, bytes) {
        const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
        let offset = 26;
        const regionCount = bytes[offset++];

        for (let r = 0; r < regionCount; r++) {
          const rx = view.getFloat32(offset, true); offset += 4;
          const ry = view.getFloat32(offset, true); offset += 4;
          const rw = view.getFloat32(offset, true); offset += 4;
          const rh = view.getFloat32(offset, true); offset += 4;
          const dataLength = view.getUint32(offset, true); offset += 4;

          ctx.save();
          ctx.beginPath();
          ctx.rect(rx, ry, rw, rh);
          ctx.clip();
          const endOffset = offset + dataLength;
          executeVisualizeBinary(ctx, bytes, offset, endOffset);
          offset = endOffset;
          ctx.restore();
        }
      }
    };
    """
  end
end
