defmodule Visualize.Hooks.Canvas do
  @moduledoc """
  Phoenix LiveView hook that replays Canvas 2D commands on a `<canvas>`.

  `CanvasChart` executes the `:json` output of `Visualize.Backend.Canvas` from the
  element's `data-commands` attribute, or its `:js` output from `data-script` — the two
  attributes `Visualize.Backend.Hybrid` emits — on mount, on update, and on
  `canvas_commands` events pushed by the LiveView.

  ## Usage

      <div id="chart" phx-hook="CanvasChart" phx-update="ignore"
           data-commands={@commands} data-width="800" data-height="600">
        <canvas width="800" height="600"></canvas>
      </div>

      # Push a new frame
      push_event(socket, "canvas_commands", %{commands: Visualize.Render.to_canvas_string(el, format: :json)})

  An element carrying `data-stream` reads its commands in segments instead (spec/10 §7.2,
  D-203): the `data-c` of each child of the element beside it that carries
  `data-vis-stream`, as `Visualize.Render.Segments.json/2` writes them, drawn again when
  `data-drawn` names another drawing. `Visualize.Components.Chart` draws this way.

  Every command of the `:json` output names a Canvas 2D method (`set_*` commands assign
  the property), so the hook needs no path helpers (D-37) — but `nonScalingLineWidth`, the
  width divided by the scale of the current transform (spec/09 §3.3.3, spec/14 §3.9), and
  `linearGradient` and `radialGradient`, which build a gradient with `visualizeGradient`
  from `Visualize.Hooks.CanvasBinary.js_decoder/0` (spec/10 §7.2, #652).
  """

  @doc """
  Returns the JavaScript code for the CanvasChart hook.
  """
  def js_hook do
    ~S"""
    export const CanvasChart = {
      mounted() {
        this.canvas = this.el.querySelector('canvas') || this.createCanvas();
        this.ctx = this.canvas.getContext('2d');
        this.lastKey = null;
        // A style's motion (spec/10 §4.5): what each identity shows, and the pending frame.
        this.motion = VisualizeMotion.create();
        this.parsed = null;
        this.motionFrame = null;

        this.handleEvent("canvas_commands", ({commands, script}) => {
          if (commands !== undefined) this.el.dataset.commands = commands;
          if (script !== undefined) this.el.dataset.script = script;
          this.render();
        });

        this.render();
      },
      destroyed() {
        if (this.motionFrame !== null) cancelAnimationFrame(this.motionFrame);
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
      render() {
        if (this.el.dataset.stream !== undefined) return this.renderSegments();
        const commands = this.el.dataset.commands;
        const script = this.el.dataset.script;
        const key = commands || script;
        if (!key || key === this.lastKey) return;
        this.lastKey = key;
        this.parsed = commands ? JSON.parse(commands) : null;
        this.draw();
      },
      // The commands in segments (spec/10 §7.1, D-203): each a run of the commands, the
      // data-c of one child of the element beside this one carrying data-vis-stream, in
      // order; data-drawn names the drawing, so the same drawing is not parsed again.
      renderSegments() {
        const list = this.el.parentNode && this.el.parentNode.querySelector('[data-vis-stream]');
        const drawn = this.el.dataset.drawn;
        if (!list || drawn === this.lastKey) return;
        this.lastKey = drawn;
        this.parsed = JSON.parse('[' + Array.from(list.children, (n) => n.dataset.c).join(',') + ']');
        this.draw();
      },
      // One replay of the last value; while a motion runs, one per animation frame.
      draw() {
        const ctx = this.ctx;
        ctx.setTransform(1, 0, 0, 1, 0, 0);
        ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);

        if (this.parsed) {
          const motion = this.motion;
          VisualizeMotion.begin(motion, performance.now());
          this.run(ctx, this.parsed, 0, this.parsed.length, motion);
          if (VisualizeMotion.end(motion, ctx)) this.loop();
        } else {
          new Function('ctx', this.el.dataset.script)(ctx);
        }
      },
      // The commands from `from` up to `to` on the context, a motion span's fills and strokes
      // at the shown values (spec/09 §3.3.5); a span with an exit keeps how to draw it again.
      run(ctx, commands, from, to, motion) {
        let opened = from;
        for (let i = from; i < to; i++) {
          const {cmd, args} = commands[i];
          if (cmd === 'motion') {
            opened = i + 1;
            VisualizeMotion.open(motion, ctx, args);
          } else if (cmd === 'motionEnd') {
            const [s, e] = [opened, i];
            VisualizeMotion.close(motion, ctx, () => (c, m) => this.run(c, commands, s, e, m));
          } else if (cmd === 'fill' || cmd === 'stroke') {
            VisualizeMotion.draw(motion, ctx, cmd, () => ctx[cmd](...args));
          } else if (cmd.startsWith('set_')) {
            ctx[cmd.slice(4)] = args[0];
          } else if (cmd === 'nonScalingLineWidth') {
            // A stroke that keeps its width on screen (spec/09 §3.3.3).
            const t = ctx.getTransform();
            ctx.lineWidth = args[0] / Math.sqrt(Math.abs(t.a * t.d - t.b * t.c));
          } else if (cmd === 'hatchPattern') {
            // A hatch's pattern (spec/09 §3.3.3, #673): target, then the hatch.
            visualizePattern(ctx, ...args);
          } else if (cmd === 'linearGradient' || cmd === 'radialGradient') {
            // A gradient in user units (spec/09 §3.3.3, #652): target, geometry, stops.
            const [target, ...rest] = args;
            const stops = rest.pop();
            visualizeGradient(ctx, target, cmd === 'linearGradient' ? 'linear' : 'radial', rest, stops);
          } else {
            ctx[cmd](...args);
          }
        }
      },
      loop() {
        if (this.motionFrame !== null) return;
        this.motionFrame = requestAnimationFrame(() => { this.motionFrame = null; this.draw(); });
      }
    };
    """
  end
end
