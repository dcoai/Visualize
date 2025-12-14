defmodule Visualize.Hooks.Zoom do
  @moduledoc """
  Phoenix LiveView hook for zoom and pan interactions.

  Enables mouse wheel zoom and drag-to-pan on SVG elements.
  Transform state is synced back to the LiveView for server-side updates.

  ## Usage

  1. Add the hook to your app.js:

      import { ZoomHook } from "visualize/hooks"

      let liveSocket = new LiveSocket("/live", Socket, {
        hooks: { ZoomHook }
      })

  2. Use in your LiveView template:

      <svg phx-hook="ZoomHook"
           id="my-chart"
           data-min-zoom="0.5"
           data-max-zoom="10"
           phx-update="ignore">
        <g class="zoom-container">
          <!-- Your chart content -->
        </g>
      </svg>

  3. Handle zoom events in your LiveView:

      def handle_event("zoom", %{"k" => scale, "x" => x, "y" => y}, socket) do
        {:noreply, assign(socket, transform: %{k: scale, x: x, y: y})}
      end

  ## Configuration

  Data attributes on the SVG element:
  - `data-min-zoom` - Minimum zoom level (default: 0.1)
  - `data-max-zoom` - Maximum zoom level (default: 10)
  - `data-zoom-event` - Event name to push (default: "zoom")
  - `data-disable-wheel` - Set to "true" to disable wheel zoom
  - `data-disable-drag` - Set to "true" to disable drag pan

  """

  @doc """
  Returns the JavaScript code for the ZoomHook.

  Include this in your app.js or as a separate file.
  """
  def js_hook do
    """
    export const ZoomHook = {
      mounted() {
        this.transform = { k: 1, x: 0, y: 0 };
        this.container = this.el.querySelector('.zoom-container') || this.el.firstElementChild;

        // Configuration from data attributes
        this.minZoom = parseFloat(this.el.dataset.minZoom) || 0.1;
        this.maxZoom = parseFloat(this.el.dataset.maxZoom) || 10;
        this.eventName = this.el.dataset.zoomEvent || 'zoom';
        this.disableWheel = this.el.dataset.disableWheel === 'true';
        this.disableDrag = this.el.dataset.disableDrag === 'true';

        // Drag state
        this.isDragging = false;
        this.dragStart = { x: 0, y: 0 };

        // Bind event handlers
        if (!this.disableWheel) {
          this.el.addEventListener('wheel', this.handleWheel.bind(this), { passive: false });
        }

        if (!this.disableDrag) {
          this.el.addEventListener('mousedown', this.handleMouseDown.bind(this));
          this.el.addEventListener('mousemove', this.handleMouseMove.bind(this));
          this.el.addEventListener('mouseup', this.handleMouseUp.bind(this));
          this.el.addEventListener('mouseleave', this.handleMouseUp.bind(this));

          // Touch support
          this.el.addEventListener('touchstart', this.handleTouchStart.bind(this), { passive: false });
          this.el.addEventListener('touchmove', this.handleTouchMove.bind(this), { passive: false });
          this.el.addEventListener('touchend', this.handleTouchEnd.bind(this));
        }

        this.applyTransform();
      },

      handleWheel(e) {
        e.preventDefault();

        const rect = this.el.getBoundingClientRect();
        const mouseX = e.clientX - rect.left;
        const mouseY = e.clientY - rect.top;

        // Zoom factor
        const delta = -e.deltaY * 0.001;
        const newK = Math.min(this.maxZoom, Math.max(this.minZoom, this.transform.k * (1 + delta)));

        // Zoom toward mouse position
        const ratio = newK / this.transform.k;
        this.transform.x = mouseX - (mouseX - this.transform.x) * ratio;
        this.transform.y = mouseY - (mouseY - this.transform.y) * ratio;
        this.transform.k = newK;

        this.applyTransform();
        this.pushTransform();
      },

      handleMouseDown(e) {
        if (e.button !== 0) return; // Only left click
        this.isDragging = true;
        this.dragStart = { x: e.clientX - this.transform.x, y: e.clientY - this.transform.y };
        this.el.style.cursor = 'grabbing';
      },

      handleMouseMove(e) {
        if (!this.isDragging) return;
        this.transform.x = e.clientX - this.dragStart.x;
        this.transform.y = e.clientY - this.dragStart.y;
        this.applyTransform();
      },

      handleMouseUp() {
        if (this.isDragging) {
          this.isDragging = false;
          this.el.style.cursor = 'grab';
          this.pushTransform();
        }
      },

      handleTouchStart(e) {
        if (e.touches.length === 1) {
          e.preventDefault();
          const touch = e.touches[0];
          this.isDragging = true;
          this.dragStart = { x: touch.clientX - this.transform.x, y: touch.clientY - this.transform.y };
        }
      },

      handleTouchMove(e) {
        if (!this.isDragging || e.touches.length !== 1) return;
        e.preventDefault();
        const touch = e.touches[0];
        this.transform.x = touch.clientX - this.dragStart.x;
        this.transform.y = touch.clientY - this.dragStart.y;
        this.applyTransform();
      },

      handleTouchEnd() {
        if (this.isDragging) {
          this.isDragging = false;
          this.pushTransform();
        }
      },

      applyTransform() {
        if (this.container) {
          this.container.setAttribute('transform',
            `translate(${this.transform.x}, ${this.transform.y}) scale(${this.transform.k})`
          );
        }
      },

      pushTransform() {
        this.pushEvent(this.eventName, {
          k: this.transform.k,
          x: this.transform.x,
          y: this.transform.y
        });
      },

      // Allow external transform updates
      updated() {
        const k = parseFloat(this.el.dataset.transformK);
        const x = parseFloat(this.el.dataset.transformX);
        const y = parseFloat(this.el.dataset.transformY);

        if (!isNaN(k) && !isNaN(x) && !isNaN(y)) {
          this.transform = { k, x, y };
          this.applyTransform();
        }
      },

      destroyed() {
        // Cleanup handled automatically by removing element
      }
    };
    """
  end

  @doc """
  Returns helper functions for transform calculations on the server side.
  """
  def transform_point({x, y}, %{k: k, x: tx, y: ty}) do
    {x * k + tx, y * k + ty}
  end

  def inverse_transform_point({x, y}, %{k: k, x: tx, y: ty}) do
    {(x - tx) / k, (y - ty) / k}
  end

  def identity_transform do
    %{k: 1, x: 0, y: 0}
  end

  def scale_transform(%{k: k, x: tx, y: ty}, scale, {cx, cy}) do
    new_k = k * scale
    %{
      k: new_k,
      x: cx - (cx - tx) * scale,
      y: cy - (cy - ty) * scale
    }
  end

  def translate_transform(%{k: k, x: tx, y: ty}, dx, dy) do
    %{k: k, x: tx + dx, y: ty + dy}
  end
end
