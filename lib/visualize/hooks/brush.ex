defmodule Visualize.Hooks.Brush do
  @moduledoc """
  Phoenix LiveView hook for brush selection interactions.

  Enables rectangular or 1D brush selection on SVG elements for
  selecting data ranges, filtering, or zooming.

  ## Usage

  1. Add the hook to your app.js:

      import { BrushHook } from "visualize/hooks"

      let liveSocket = new LiveSocket("/live", Socket, {
        hooks: { BrushHook }
      })

  2. Use in your LiveView template:

      <svg phx-hook="BrushHook"
           id="my-chart"
           data-brush-type="xy"
           data-brush-event="brush_select">
        <g class="chart-content">
          <!-- Your chart content -->
        </g>
        <g class="brush-overlay"></g>
      </svg>

  3. Handle brush events in your LiveView:

      def handle_event("brush_select", %{"x0" => x0, "y0" => y0, "x1" => x1, "y1" => y1}, socket) do
        # Filter data within selection
        {:noreply, assign(socket, selection: {x0, y0, x1, y1})}
      end

      def handle_event("brush_clear", _params, socket) do
        {:noreply, assign(socket, selection: nil)}
      end

  ## Brush Types

  - `xy` - 2D rectangular brush (default)
  - `x` - Horizontal brush only
  - `y` - Vertical brush only

  ## Configuration

  Data attributes on the SVG element:
  - `data-brush-type` - Brush type: "xy", "x", or "y" (default: "xy")
  - `data-brush-event` - Event name for selection (default: "brush_select")
  - `data-brush-clear-event` - Event name for clearing (default: "brush_clear")
  - `data-brush-extent` - Constrains brush to "x0,y0,x1,y1" (optional)
  - `data-brush-color` - Selection rectangle fill color (default: "rgba(0,0,0,0.1)")
  - `data-brush-stroke` - Selection rectangle stroke color (default: "#666")

  """

  @doc """
  Returns the JavaScript code for the BrushHook.

  Include this in your app.js or as a separate file.
  """
  def js_hook do
    """
    export const BrushHook = {
      mounted() {
        this.selection = null;
        this.isBrushing = false;
        this.startPoint = null;

        // Configuration from data attributes
        this.brushType = this.el.dataset.brushType || 'xy';
        this.selectEvent = this.el.dataset.brushEvent || 'brush_select';
        this.clearEvent = this.el.dataset.brushClearEvent || 'brush_clear';
        this.fillColor = this.el.dataset.brushColor || 'rgba(119, 119, 119, 0.2)';
        this.strokeColor = this.el.dataset.brushStroke || '#666';

        // Parse extent if provided
        this.extent = null;
        if (this.el.dataset.brushExtent) {
          const parts = this.el.dataset.brushExtent.split(',').map(parseFloat);
          if (parts.length === 4) {
            this.extent = { x0: parts[0], y0: parts[1], x1: parts[2], y1: parts[3] };
          }
        }

        // Create brush overlay group
        this.overlay = this.el.querySelector('.brush-overlay');
        if (!this.overlay) {
          this.overlay = document.createElementNS('http://www.w3.org/2000/svg', 'g');
          this.overlay.classList.add('brush-overlay');
          this.el.appendChild(this.overlay);
        }

        // Create selection rectangle
        this.selectionRect = document.createElementNS('http://www.w3.org/2000/svg', 'rect');
        this.selectionRect.setAttribute('class', 'brush-selection');
        this.selectionRect.setAttribute('fill', this.fillColor);
        this.selectionRect.setAttribute('stroke', this.strokeColor);
        this.selectionRect.setAttribute('stroke-width', '1');
        this.selectionRect.setAttribute('visibility', 'hidden');
        this.overlay.appendChild(this.selectionRect);

        // Invisible overlay for capturing mouse events
        this.captureRect = document.createElementNS('http://www.w3.org/2000/svg', 'rect');
        this.captureRect.setAttribute('class', 'brush-capture');
        this.captureRect.setAttribute('fill', 'transparent');
        this.captureRect.setAttribute('cursor', 'crosshair');

        const bbox = this.el.getBBox ? this.el.getBBox() : this.el.getBoundingClientRect();
        const width = this.extent ? this.extent.x1 - this.extent.x0 : (bbox.width || this.el.clientWidth);
        const height = this.extent ? this.extent.y1 - this.extent.y0 : (bbox.height || this.el.clientHeight);
        const x = this.extent ? this.extent.x0 : 0;
        const y = this.extent ? this.extent.y0 : 0;

        this.captureRect.setAttribute('x', x);
        this.captureRect.setAttribute('y', y);
        this.captureRect.setAttribute('width', width);
        this.captureRect.setAttribute('height', height);
        this.overlay.insertBefore(this.captureRect, this.selectionRect);

        // Bind event handlers
        this.captureRect.addEventListener('mousedown', this.handleMouseDown.bind(this));
        document.addEventListener('mousemove', this.handleMouseMove.bind(this));
        document.addEventListener('mouseup', this.handleMouseUp.bind(this));

        // Touch support
        this.captureRect.addEventListener('touchstart', this.handleTouchStart.bind(this), { passive: false });
        document.addEventListener('touchmove', this.handleTouchMove.bind(this), { passive: false });
        document.addEventListener('touchend', this.handleTouchEnd.bind(this));

        // Double-click to clear
        this.captureRect.addEventListener('dblclick', this.handleClear.bind(this));
      },

      getSVGPoint(clientX, clientY) {
        const svg = this.el;
        const pt = svg.createSVGPoint();
        pt.x = clientX;
        pt.y = clientY;
        const svgP = pt.matrixTransform(svg.getScreenCTM().inverse());
        return { x: svgP.x, y: svgP.y };
      },

      constrainPoint(point) {
        let { x, y } = point;

        if (this.extent) {
          x = Math.max(this.extent.x0, Math.min(this.extent.x1, x));
          y = Math.max(this.extent.y0, Math.min(this.extent.y1, y));
        }

        return { x, y };
      },

      handleMouseDown(e) {
        if (e.button !== 0) return;
        e.preventDefault();

        const point = this.constrainPoint(this.getSVGPoint(e.clientX, e.clientY));
        this.startBrush(point);
      },

      handleMouseMove(e) {
        if (!this.isBrushing) return;
        e.preventDefault();

        const point = this.constrainPoint(this.getSVGPoint(e.clientX, e.clientY));
        this.updateBrush(point);
      },

      handleMouseUp(e) {
        if (!this.isBrushing) return;
        this.endBrush();
      },

      handleTouchStart(e) {
        if (e.touches.length !== 1) return;
        e.preventDefault();

        const touch = e.touches[0];
        const point = this.constrainPoint(this.getSVGPoint(touch.clientX, touch.clientY));
        this.startBrush(point);
      },

      handleTouchMove(e) {
        if (!this.isBrushing || e.touches.length !== 1) return;
        e.preventDefault();

        const touch = e.touches[0];
        const point = this.constrainPoint(this.getSVGPoint(touch.clientX, touch.clientY));
        this.updateBrush(point);
      },

      handleTouchEnd(e) {
        if (!this.isBrushing) return;
        this.endBrush();
      },

      handleClear() {
        this.selection = null;
        this.selectionRect.setAttribute('visibility', 'hidden');
        this.pushEvent(this.clearEvent, {});
      },

      startBrush(point) {
        this.isBrushing = true;
        this.startPoint = point;
        this.selection = { x0: point.x, y0: point.y, x1: point.x, y1: point.y };
        this.selectionRect.setAttribute('visibility', 'visible');
        this.updateSelectionRect();
      },

      updateBrush(point) {
        if (this.brushType === 'x') {
          this.selection.x1 = point.x;
          // Use full height for x-only brush
          if (this.extent) {
            this.selection.y0 = this.extent.y0;
            this.selection.y1 = this.extent.y1;
          }
        } else if (this.brushType === 'y') {
          this.selection.y1 = point.y;
          // Use full width for y-only brush
          if (this.extent) {
            this.selection.x0 = this.extent.x0;
            this.selection.x1 = this.extent.x1;
          }
        } else {
          this.selection.x1 = point.x;
          this.selection.y1 = point.y;
        }

        this.updateSelectionRect();
      },

      endBrush() {
        this.isBrushing = false;

        // Normalize selection (ensure x0 < x1, y0 < y1)
        const sel = {
          x0: Math.min(this.selection.x0, this.selection.x1),
          y0: Math.min(this.selection.y0, this.selection.y1),
          x1: Math.max(this.selection.x0, this.selection.x1),
          y1: Math.max(this.selection.y0, this.selection.y1)
        };

        // Only emit if selection has meaningful size
        const minSize = 5;
        if ((sel.x1 - sel.x0) > minSize || (sel.y1 - sel.y0) > minSize) {
          this.selection = sel;
          this.pushEvent(this.selectEvent, sel);
        } else {
          // Too small, treat as click and clear
          this.handleClear();
        }
      },

      updateSelectionRect() {
        const x = Math.min(this.selection.x0, this.selection.x1);
        const y = Math.min(this.selection.y0, this.selection.y1);
        const width = Math.abs(this.selection.x1 - this.selection.x0);
        const height = Math.abs(this.selection.y1 - this.selection.y0);

        this.selectionRect.setAttribute('x', x);
        this.selectionRect.setAttribute('y', y);
        this.selectionRect.setAttribute('width', width);
        this.selectionRect.setAttribute('height', height);
      },

      // Programmatically set selection from server
      updated() {
        const x0 = parseFloat(this.el.dataset.selectionX0);
        const y0 = parseFloat(this.el.dataset.selectionY0);
        const x1 = parseFloat(this.el.dataset.selectionX1);
        const y1 = parseFloat(this.el.dataset.selectionY1);

        if (!isNaN(x0) && !isNaN(y0) && !isNaN(x1) && !isNaN(y1)) {
          this.selection = { x0, y0, x1, y1 };
          this.selectionRect.setAttribute('visibility', 'visible');
          this.updateSelectionRect();
        } else if (this.el.dataset.selectionClear === 'true') {
          this.handleClear();
        }
      },

      destroyed() {
        document.removeEventListener('mousemove', this.handleMouseMove.bind(this));
        document.removeEventListener('mouseup', this.handleMouseUp.bind(this));
        document.removeEventListener('touchmove', this.handleTouchMove.bind(this));
        document.removeEventListener('touchend', this.handleTouchEnd.bind(this));
      }
    };
    """
  end

  @doc """
  Helper to filter data points within a brush selection.

  ## Example

      filtered = Visualize.Hooks.Brush.filter_selection(
        data,
        selection,
        x_accessor: & &1.date,
        y_accessor: & &1.value,
        x_scale: x_scale,
        y_scale: y_scale
      )
  """
  def filter_selection(data, selection, opts) do
    x_accessor = Keyword.fetch!(opts, :x_accessor)
    y_accessor = Keyword.fetch!(opts, :y_accessor)
    x_scale = Keyword.fetch!(opts, :x_scale)
    y_scale = Keyword.fetch!(opts, :y_scale)

    %{x0: x0, y0: y0, x1: x1, y1: y1} = selection

    Enum.filter(data, fn d ->
      x = Visualize.Scale.apply(x_scale, x_accessor.(d))
      y = Visualize.Scale.apply(y_scale, y_accessor.(d))

      x >= x0 and x <= x1 and y >= y0 and y <= y1
    end)
  end

  @doc """
  Converts pixel selection to data domain values.

  ## Example

      domain = Visualize.Hooks.Brush.selection_to_domain(
        selection,
        x_scale: x_scale,
        y_scale: y_scale
      )
      # Returns %{x0: date1, x1: date2, y0: 0, y1: 100}
  """
  def selection_to_domain(selection, opts) do
    x_scale = Keyword.fetch!(opts, :x_scale)
    y_scale = Keyword.fetch!(opts, :y_scale)

    %{x0: x0, y0: y0, x1: x1, y1: y1} = selection

    %{
      x0: Visualize.Scale.invert(x_scale, x0),
      x1: Visualize.Scale.invert(x_scale, x1),
      y0: Visualize.Scale.invert(y_scale, y0),
      y1: Visualize.Scale.invert(y_scale, y1)
    }
  end
end
