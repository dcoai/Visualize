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

  Every command of the `:json` output names a Canvas 2D method (`set_*` commands assign
  the property), so the hook needs no path helpers (D-37).
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

        this.handleEvent("canvas_commands", ({commands, script}) => {
          if (commands !== undefined) this.el.dataset.commands = commands;
          if (script !== undefined) this.el.dataset.script = script;
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
        const commands = this.el.dataset.commands;
        const script = this.el.dataset.script;
        const key = commands || script;
        if (!key || key === this.lastKey) return;
        this.lastKey = key;

        const ctx = this.ctx;
        ctx.setTransform(1, 0, 0, 1, 0, 0);
        ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);

        if (commands) {
          JSON.parse(commands).forEach(({cmd, args}) => {
            if (cmd.startsWith('set_')) {
              ctx[cmd.slice(4)] = args[0];
            } else {
              ctx[cmd](...args);
            }
          });
        } else {
          new Function('ctx', script)(ctx);
        }
      }
    };
    """
  end
end
