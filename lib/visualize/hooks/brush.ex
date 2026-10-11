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

      ```elixir
      def handle_event("brush_select", %{"x0" => x0, "y0" => y0, "x1" => x1, "y1" => y1}, socket) do
        # Filter data within selection
        {:noreply, assign(socket, selection: {x0, y0, x1, y1})}
      end

      def handle_event("brush_clear", _params, socket) do
        {:noreply, assign(socket, selection: nil)}
      end
      ```

  The hook may also sit on a container around the chart's `<svg>`, as the other hooks do:
  it maps the pointer through, and draws in, the first `<svg>` inside it.

  ## In a sync group

  A chart whose design names a sync group (`interaction: %{sync: "dash-42"}`, spec/14
  §2.9) shares its brush (spec/10 §6.4, D-117): the chart brushed publishes the brushed x
  extent in **domain** units on the group's bus, and every other member draws it as a band
  through its own scale, clipped to its domain, at once. Only the chart brushed pushes
  `brush_select`, once, on release, with the window as `"domain" => [lo, hi]` too, so one
  window change is one server request:

      def handle_event("brush_select", %{"domain" => [from, to]}, socket) do
        {:noreply, assign(socket, window: {from, to})}
      end

  ## The design's brush

  A design that says `interaction: %{brush: :x}` (spec/14 §2.9, D-143) writes its brush on
  its frame's group — the kind, the plot area and the `x` mapping
  (`Visualize.Chart.Frame.brush_attrs/1`) — and the hook reads them from the first
  descendant carrying `data-vis-brush` when its own element gives no type or extent
  (spec/10 §6.5). Every `brush_select` then carries the window in domain units, so a host
  attaches the hook to a container around the rendered chart and holds no margin and no
  scale to invert:

      <div id="cpu" phx-hook="BrushHook" data-brush-event="zoom">{raw(svg)}</div>

      def handle_event("zoom", %{"domain" => [from, to]}, socket) do
        {:noreply, assign(socket, window: {from, to})}
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
  - `data-brush-color` - Selection rectangle fill color (default: "rgba(119, 119, 119, 0.2)")
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

        // The SVG the brush maps the pointer through and draws in: the element itself, or
        // the first <svg> of a container around a server-rendered chart (spec/10 §6.2).
        this.svg = this.el.tagName.toLowerCase() === 'svg' ? this.el : this.el.querySelector('svg');

        // The design's own brush, when the chart carries one (spec/10 §6.5): its kind, its
        // x mapping and its plot area. The element's own attributes win over it.
        this.design = this.readDesign();

        // Configuration from data attributes
        this.brushType = this.el.dataset.brushType || (this.design && this.design.type) || 'xy';
        this.selectEvent = this.el.dataset.brushEvent || 'brush_select';
        this.clearEvent = this.el.dataset.brushClearEvent || 'brush_clear';
        this.target = this.el.dataset.brushTarget || null;
        this.fillColor = this.el.dataset.brushColor || 'rgba(119, 119, 119, 0.2)';
        this.strokeColor = this.el.dataset.brushStroke || '#666';

        // Parse extent if provided, else take the design's plot area
        this.extent = this.readExtent();

        // Create brush overlay group
        this.overlay = this.svg.querySelector('.brush-overlay');
        if (!this.overlay) {
          this.overlay = document.createElementNS('http://www.w3.org/2000/svg', 'g');
          this.overlay.classList.add('brush-overlay');
          this.svg.appendChild(this.overlay);
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

        this.placeCapture();
        this.overlay.insertBefore(this.captureRect, this.selectionRect);

        // Each handler is bound once and kept on the hook: removeEventListener only
        // matches the reference that was added, so destroyed() removes these same ones;
        // onSync is the sync bus's listener (spec/10 §4.3, §6.4).
        this.onMouseDown = this.handleMouseDown.bind(this);
        this.onMouseMove = this.handleMouseMove.bind(this);
        this.onMouseUp = this.handleMouseUp.bind(this);
        this.onTouchStart = this.handleTouchStart.bind(this);
        this.onTouchMove = this.handleTouchMove.bind(this);
        this.onTouchEnd = this.handleTouchEnd.bind(this);
        this.onClear = this.handleClear.bind(this);
        this.onSync = this.handleSync.bind(this);

        this.captureRect.addEventListener('mousedown', this.onMouseDown);
        document.addEventListener('mousemove', this.onMouseMove);
        document.addEventListener('mouseup', this.onMouseUp);

        // Touch support
        this.captureRect.addEventListener('touchstart', this.onTouchStart, { passive: false });
        document.addEventListener('touchmove', this.onTouchMove, { passive: false });
        document.addEventListener('touchend', this.onTouchEnd);

        // Double-click to clear
        this.captureRect.addEventListener('dblclick', this.onClear);

        this.joinSync();
      },

      // An event to the component `data-brush-target` names, else to the LiveView
      // (spec/10 §6.2).
      push(event, payload) {
        if (this.target) this.pushEventTo(this.target, event, payload);
        else this.pushEvent(event, payload);
      },

      // A chart the server redrew: its present <svg> found again, and the overlay — the
      // same capture and selection, the same listeners — appended to it when the redraw
      // dropped it (spec/10 §6.2, spec/15 §9.1).
      reattach() {
        const svg = this.el.tagName.toLowerCase() === 'svg' ? this.el : this.el.querySelector('svg');
        if (svg) this.svg = svg;
        if (!this.svg.contains(this.overlay)) this.svg.appendChild(this.overlay);
      },

      // The capture area: the extent, else the SVG's box; a band received from the group
      // spans its height (spec/10 §6.4).
      placeCapture() {
        const bbox = this.svg.getBBox ? this.svg.getBBox() : this.svg.getBoundingClientRect();
        const width = this.extent ? this.extent.x1 - this.extent.x0 : (bbox.width || this.svg.clientWidth);
        const height = this.extent ? this.extent.y1 - this.extent.y0 : (bbox.height || this.svg.clientHeight);
        const x = this.extent ? this.extent.x0 : 0;
        const y = this.extent ? this.extent.y0 : 0;

        this.area = { x, y, width, height };
        this.captureRect.setAttribute('x', x);
        this.captureRect.setAttribute('y', y);
        this.captureRect.setAttribute('width', width);
        this.captureRect.setAttribute('height', height);
      },

      // The design's brush from the element, or its first descendant carrying
      // data-vis-brush: {type, map, extent}, the map as VisualizeSync reads a group's x;
      // null for none, or for numbers that do not parse (spec/10 §6.5).
      readDesign() {
        const node = this.el.hasAttribute('data-vis-brush') ? this.el : this.el.querySelector('[data-vis-brush]');
        if (!node) return null;
        const x = (node.getAttribute('data-vis-brush-x') || '').split(',').map(parseFloat);
        const e = (node.getAttribute('data-vis-brush-extent') || '').split(',').map(parseFloat);
        if (x.length !== 5 || x.some((n) => Number.isNaN(n))) return null;
        if (e.length !== 4 || e.some((n) => Number.isNaN(n))) return null;
        return {
          type: node.getAttribute('data-vis-brush'),
          map: { d0: x[0], d1: x[1], x0: x[2], x1: x[3], width: x[4] },
          extent: { x0: e[0], y0: e[1], x1: e[2], y1: e[3] }
        };
      },

      // The element's own data-brush-extent, else the design's plot area, else none.
      readExtent() {
        if (this.el.dataset.brushExtent) {
          const parts = this.el.dataset.brushExtent.split(',').map(parseFloat);
          if (parts.length === 4) return { x0: parts[0], y0: parts[1], x1: parts[2], y1: parts[3] };
        }
        return this.design ? this.design.extent : null;
      },

      // The x mapping a selection's edges are read through: the sync group's, else the
      // design's brush's; null when the chart says neither.
      mapping() {
        return this.sync || (this.design && this.design.map) || null;
      },

      // The group shares x, so a "y" brush joins none (spec/10 §6.4).
      joinSync() {
        if (this.brushType === 'y') VisualizeSync.detach(this);
        else VisualizeSync.attach(this, 'brush');
      },

      getSVGPoint(clientX, clientY) {
        const svg = this.svg;
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

      // A clear on this chart: the group's band cleared too, and the one push.
      handleClear() {
        this.selection = null;
        this.selectionRect.setAttribute('visibility', 'hidden');
        if (this.sync) VisualizeSync.publishBrush(this.sync, this.el, null);
        this.push(this.clearEvent, {});
      },

      // The x extent of a selection in domain units, ascending (spec/10 §6.4, §6.5).
      domainOf(sel) {
        const map = this.mapping();
        const a = VisualizeSync.toDomain(map, sel.x0);
        const b = VisualizeSync.toDomain(map, sel.x1);
        return [Math.min(a, b), Math.max(a, b)];
      },

      // Another member's window, drawn through this chart's own scale and never pushed:
      // only the chart brushed talks to its server (spec/10 §6.4).
      handleSync(e) {
        if (VisualizeSync.own(this.el, e.detail.source) || this.isBrushing) return;
        this.syncTo(e.detail.extent);
      },

      // Shows a domain extent as this chart's band, clipped to its domain; hides it for a
      // clear or a disjoint extent.
      syncTo(extent) {
        const span = this.sync ? VisualizeSync.toChartExtent(this.sync, extent) : null;
        if (!span) {
          this.selection = null;
          this.selectionRect.setAttribute('visibility', 'hidden');
          return;
        }
        this.selection = { x0: span[0], y0: this.area.y, x1: span[1], y1: this.area.y + this.area.height };
        this.selectionRect.setAttribute('visibility', 'visible');
        this.updateSelectionRect();
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
        // The members follow the rubber band as it is drawn; nothing goes to the server.
        if (this.sync) VisualizeSync.publishBrush(this.sync, this.el, this.domainOf(this.selection));
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
          if (this.mapping()) {
            // The final window on the bus, and once to the server with its domain — in a
            // sync group or under the design's brush (spec/10 §6.4, §6.5).
            const domain = this.domainOf(sel);
            if (this.sync) VisualizeSync.publishBrush(this.sync, this.el, domain);
            this.push(this.selectEvent, Object.assign({}, sel, { domain }));
          } else {
            this.push(this.selectEvent, sel);
          }
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

      // Programmatically set selection from server; the sync group and the design's brush
      // are re-read first — a chart re-rendered for a new window or width has new numbers —
      // and a selection the server set is not published (spec/10 §6.4, §6.5).
      updated() {
        this.reattach();
        this.joinSync();
        this.design = this.readDesign();
        this.extent = this.readExtent();
        this.placeCapture();
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

      // The capture rect's listeners go with the element; the document's must be removed
      // by hand, with the references mounted() stored, and so must the bus listener.
      destroyed() {
        document.removeEventListener('mousemove', this.onMouseMove);
        document.removeEventListener('mouseup', this.onMouseUp);
        document.removeEventListener('touchmove', this.onTouchMove);
        document.removeEventListener('touchend', this.onTouchEnd);
        VisualizeSync.detach(this);
      }
    };
    """
  end

  @doc """
  Keeps the data within the selection on every axis whose scale is given (spec/10 §6.3,
  D-29).

  `opts` takes `:x_accessor` with `:x_scale`, `:y_accessor` with `:y_scale`, or both pairs;
  an axis without a scale is not tested, so an `"x"` brush needs no y scale. Neither scale
  is an `ArgumentError`.

  ## Example

      filtered = Visualize.Hooks.Brush.filter_selection(
        data,
        selection,
        x_accessor: & &1.date,
        x_scale: x_scale
      )
  """
  @spec filter_selection([any()], map(), keyword()) :: [any()]
  def filter_selection(data, selection, opts) do
    tests =
      Enum.flat_map(axes(opts), fn {scale, accessor_key, p0_key, p1_key} ->
        accessor = Keyword.fetch!(opts, accessor_key)
        p0 = Map.fetch!(selection, p0_key)
        p1 = Map.fetch!(selection, p1_key)

        [
          fn d ->
            p = Visualize.Scale.apply(scale, accessor.(d))
            p >= p0 and p <= p1
          end
        ]
      end)

    Enum.filter(data, fn d -> Enum.all?(tests, & &1.(d)) end)
  end

  @doc """
  Converts a pixel selection to domain values through the scales given (spec/10 §6.3,
  D-29).

  With both `:x_scale` and `:y_scale`: `%{x0:, x1:, y0:, y1:}`. With one: the `{start, stop}`
  pair of that axis in domain units, in pixel order — for a y brush under the usual flipped
  range `start` is the larger value. Neither scale is an `ArgumentError`.

  ## Example

      {from, to} = Visualize.Hooks.Brush.selection_to_domain(selection, x_scale: x_scale)
  """
  @spec selection_to_domain(map(), keyword()) :: map() | {any(), any()}
  def selection_to_domain(selection, opts) do
    case axes(opts) do
      [{x_scale, _, _, _}, {y_scale, _, _, _}] ->
        %{
          x0: Visualize.Scale.invert(x_scale, Map.fetch!(selection, :x0)),
          x1: Visualize.Scale.invert(x_scale, Map.fetch!(selection, :x1)),
          y0: Visualize.Scale.invert(y_scale, Map.fetch!(selection, :y0)),
          y1: Visualize.Scale.invert(y_scale, Map.fetch!(selection, :y1))
        }

      [{scale, _, p0_key, p1_key}] ->
        {Visualize.Scale.invert(scale, Map.fetch!(selection, p0_key)),
         Visualize.Scale.invert(scale, Map.fetch!(selection, p1_key))}
    end
  end

  # The axes in use, x first: {scale, accessor key, first edge key, second edge key}.
  defp axes(opts) do
    axes =
      for {scale_key, accessor_key, p0, p1} <- [
            {:x_scale, :x_accessor, :x0, :x1},
            {:y_scale, :y_accessor, :y0, :y1}
          ],
          scale = Keyword.get(opts, scale_key),
          scale != nil,
          do: {scale, accessor_key, p0, p1}

    if axes == [] do
      raise ArgumentError, "a brush selection needs :x_scale, :y_scale, or both"
    end

    axes
  end
end
