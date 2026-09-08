defmodule Visualize.Hooks.Resize do
  @moduledoc """
  Phoenix LiveView hook that reports a container's size to the LiveView (spec/10 §10).

  `ResizeHook` is the round-trip half of responsive sizing (D-54): a `ResizeObserver` on
  the container pushes `{width, height}` once the size has held for the debounce period,
  so the server re-renders the chart at the container's pixel width. The CSS-scaled half
  needs no hook: `Visualize.IR.Element.root/3` under `responsive: true`, or a component
  with `responsive={true}`, follows its container by `viewBox` and `preserveAspectRatio`.

  ## Usage

      <div id="chart-panel" phx-hook="ResizeHook" data-resize-event="resize">
        <.line_chart data={@data} x={& &1.at} y={& &1.value} width={@width} height={@height} />
      </div>

      def handle_event("resize", %{"width" => width, "height" => height}, socket) do
        {:noreply, assign(socket, width: width, height: height)}
      end

  ## Configuration

  Data attributes on the observed element:
  - `data-resize-event` - event name to push (default: "resize")
  - `data-resize-debounce` - milliseconds the size must hold before it is pushed
    (default: 150)
  """

  @doc """
  Returns the JavaScript source of `ResizeHook`.
  """
  def js_hook do
    """
    export const ResizeHook = {
      mounted() {
        this.eventName = this.el.dataset.resizeEvent || 'resize';
        this.debounce = parseInt(this.el.dataset.resizeDebounce, 10) || 150;
        this.pending = null;
        this.timer = null;
        this.last = null;
        this.observer = null;

        if (typeof ResizeObserver === 'undefined') return;

        this.observer = new ResizeObserver((entries) => this.observed(entries));
        this.observer.observe(this.el);
      },

      // Every observation records the content box and restarts the settle timer, so a
      // drag that fires many observations pushes once, when it stops.
      observed(entries) {
        const rect = entries[entries.length - 1].contentRect;
        this.pending = { width: Math.round(rect.width), height: Math.round(rect.height) };
        if (this.timer) clearTimeout(this.timer);
        this.timer = setTimeout(() => this.settled(), this.debounce);
      },

      settled() {
        this.timer = null;
        const size = this.pending;
        if (this.last && this.last.width === size.width && this.last.height === size.height) {
          return;
        }
        this.last = size;
        this.pushEvent(this.eventName, size);
      },

      destroyed() {
        if (this.observer) this.observer.disconnect();
        if (this.timer) clearTimeout(this.timer);
      }
    };
    """
  end
end
