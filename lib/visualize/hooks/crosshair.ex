defmodule Visualize.Hooks.Crosshair do
  @moduledoc """
  Phoenix LiveView hook that snaps a rule and per-series markers to the nearest x of
  the data (spec/10 §13).

  `CrosshairHook` never reads the chart's DOM: the server writes the mark's x pixels once,
  as `data-xs`, and the hook finds the nearest one to the pointer by binary search, so the
  same attributes serve a mark drawn as SVG and one the compiler sent to the canvas layer
  (D-76). `attrs/3` computes them from a realised `Visualize.Chart.Frame`; the hook draws
  in an overlay it appends to `document.body`, so a LiveView patch of the chart never
  removes it, and re-reads the arrays on `updated()`. The overlay is placed over the chart
  itself — the container's first `<svg>` or `<canvas>` — not over the container, whose box
  the page lays out (spec/10 §13.3, #507).

  In a sync group (spec/10 §4.3, §13.4) the hook publishes the pointer's x in domain units
  on the group's bus and draws every other member's hover at the nearest x of its own
  data; `attrs/3` adds the frame's `data-vis-sync` and `data-vis-sync-x` when the frame is
  a group's (`Visualize.Chart.Frame.sync_attrs/1`).

  ## Usage

      <div id="chart" phx-hook="CrosshairHook" {@crosshair} data-crosshair-event="hover">
        {Phoenix.HTML.raw(@svg)}
      </div>

      crosshair = Visualize.Hooks.Crosshair.attrs(applied.frame, applied.sources)

      def handle_event("hover", %{"index" => index}, socket) do
        {:noreply, assign(socket, hovered: index)}
      end

  ## Configuration

  Data attributes on the container, from `attrs/3` (spec/10 §13.2):
  - `data-xs` - the distinct x pixels, ascending, in plot coordinates
  - `data-ys` - one array per series of the y pixel at each x, `null` where absent
  - `data-plot` - `left,top,width,height` of the plot area inside the chart
  - `data-size` - `width,height` of the chart; absent, the chart element's own size. Over
    a canvas, the canvas's `data-width`/`data-height` are this size, from the same frame

  Set by the host:
  - `data-crosshair-event` - the event pushed with `{index}` when the nearest index
    changes; unset, nothing is pushed
  - `data-crosshair-color` - the rule's stroke and the default marker fill
    (default: "#666")
  - `data-crosshair-colors` - a JSON array of one marker fill per series
  """

  alias Visualize.Chart.{Frame, Mark}
  alias Visualize.Chart.Mark.Channels
  alias Visualize.IR.Path

  @doc "As `attrs/3` with no options: the first mark."
  @spec attrs(Frame.t(), map()) :: %{String.t() => String.t()}
  def attrs(%Frame{} = frame, sources), do: attrs(frame, sources, [])

  @doc """
  The data attributes of spec/10 §13.2 for one mark of the frame, computed once.

  ## Options

    * `:mark` - the one-based position of the mark among the frame's marks (default `1`)

  Raises `ArgumentError` for a `:facet` or `:polar` frame, or a mark without `x` and `y`
  channels.
  """
  @spec attrs(Frame.t(), map(), keyword()) :: %{String.t() => String.t()}
  def attrs(%Frame{kind: kind}, _sources, _opts) when kind in [:facet, :polar] do
    raise ArgumentError,
          "the crosshair is a cartesian interaction over one plot area; " <>
            "got a #{inspect(kind)} frame (spec/10 §13.1)"
  end

  def attrs(%Frame{} = frame, sources, opts) do
    index = Keyword.get(opts, :mark, 1)
    mark = mark(frame, index)
    rows = Mark.rows(frame, mark, sources)
    ctx = %{frame: frame, mark: mark, rows: rows}
    pixels = ctx |> Channels.pixels() |> Channels.placed([:x, :y])
    xs = pixels |> Enum.map(& &1.x) |> Enum.uniq() |> Enum.sort()

    series =
      if Channels.has?(ctx, :series),
        do: pixels |> Enum.map(& &1.series) |> Enum.uniq(),
        else: [nil]

    ys = for value <- series, do: series_ys(pixels, value, xs)

    %{
      "data-xs" => array(xs),
      "data-ys" => "[" <> Enum.map_join(ys, ",", &array/1) <> "]",
      "data-plot" =>
        numbers([frame.margin.left, frame.margin.top, frame.plot.width, frame.plot.height]),
      "data-size" => numbers([frame.size.width, frame.size.height])
    }
    |> Map.merge(Frame.sync_attrs(frame))
  end

  defp mark(frame, index) do
    mark =
      Enum.at(frame.marks, index - 1) ||
        raise ArgumentError, "the frame has no mark #{index} (spec/10 §13.1)"

    channels = Map.get(mark, :channels, %{})

    (Map.has_key?(channels, :x) and Map.has_key?(channels, :y)) ||
      raise ArgumentError, "the crosshair needs a mark with x and y channels (spec/10 §13.1)"

    mark
  end

  # The series' y at each x: the first row's when it has several, `nil` where none.
  defp series_ys(pixels, value, xs) do
    lookup =
      pixels
      |> Enum.filter(&(Map.get(&1, :series) == value))
      |> Enum.reverse()
      |> Map.new(&{&1.x, &1.y})

    Enum.map(xs, &Map.get(lookup, &1))
  end

  defp array(values), do: "[" <> Enum.map_join(values, ",", &number/1) <> "]"
  defp numbers(values), do: Enum.map_join(values, ",", &number/1)
  defp number(nil), do: "null"
  defp number(n), do: Path.format_number(n)

  @doc """
  Returns the JavaScript source of `CrosshairHook`.
  """
  def js_hook do
    """
    export const CrosshairHook = {
      mounted() {
        this.overlay = this.svg('svg', 'crosshair');
        this.overlay.style.position = 'absolute';
        this.overlay.style.pointerEvents = 'none';
        this.overlay.style.display = 'none';
        this.group = this.svg('g', 'crosshair-plot');
        this.rule = this.svg('line', 'crosshair-rule');
        this.group.appendChild(this.rule);
        this.overlay.appendChild(this.group);
        document.body.appendChild(this.overlay);
        this.markers = [];
        this.lastIndex = null;

        // Each handler is bound once and kept on the hook, so destroyed() removes the
        // same references it added; onSync is the sync bus's listener (spec/10 §4.3).
        this.onMouseMove = this.handleMouseMove.bind(this);
        this.onMouseLeave = this.leave.bind(this);
        this.onTouchMove = this.handleTouchMove.bind(this);
        this.onTouchEnd = this.leave.bind(this);
        this.onSync = this.handleSync.bind(this);
        this.read();

        this.el.addEventListener('mousemove', this.onMouseMove);
        this.el.addEventListener('mouseleave', this.onMouseLeave);
        this.el.addEventListener('touchmove', this.onTouchMove, { passive: true });
        this.el.addEventListener('touchend', this.onTouchEnd);
      },

      svg(tag, className) {
        const node = document.createElementNS('http://www.w3.org/2000/svg', tag);
        node.setAttribute('class', className);
        return node;
      },

      // The arrays and the plot area from the data attributes (spec/10 §13.2), read on
      // mount and again after every patch.
      read() {
        const ds = this.el.dataset;
        this.xs = JSON.parse(ds.xs || '[]');
        this.ys = JSON.parse(ds.ys || '[]');
        const plot = (ds.plot || '0,0,0,0').split(',').map(parseFloat);
        this.plot = { left: plot[0], top: plot[1], width: plot[2], height: plot[3] };
        this.size = ds.size ? ds.size.split(',').map(parseFloat) : null;
        this.eventName = ds.crosshairEvent || null;
        this.color = ds.crosshairColor || '#666';
        this.colors = ds.crosshairColors ? JSON.parse(ds.crosshairColors) : [];
        this.build();
        VisualizeSync.attach(this);
      },

      // The rule spans the plot's height; one marker per series, rebuilt when the
      // series count changed.
      build() {
        this.group.setAttribute('transform', `translate(${this.plot.left}, ${this.plot.top})`);
        this.rule.setAttribute('y1', 0);
        this.rule.setAttribute('y2', this.plot.height);
        this.rule.setAttribute('stroke', this.color);
        if (this.markers.length !== this.ys.length) {
          this.markers.forEach((marker) => marker.remove());
          this.markers = this.ys.map(() => {
            const marker = this.svg('circle', 'crosshair-marker');
            marker.setAttribute('r', 4);
            this.group.appendChild(marker);
            return marker;
          });
        }
        this.markers.forEach((marker, i) => marker.setAttribute('fill', this.colors[i] || this.color));
      },

      // The pointer in chart units: the chart's rectangle scaled to its viewBox, with the
      // overlay placed over that rectangle.
      chartPoint(clientX, clientY) {
        const { rect, width, height } = this.place();
        return {
          x: (clientX - rect.left) * width / rect.width - this.plot.left,
          y: (clientY - rect.top) * height / rect.height - this.plot.top
        };
      },

      // The overlay sized and placed over the chart, with the chart's viewBox. The chart is
      // the container's first svg or canvas, looked up on every move since a patch may
      // replace it; the container's own box is the page's layout, a descender gap taller
      // than an inline chart (spec/10 §13.3, #507).
      place() {
        const rect = this.chart().getBoundingClientRect();
        const width = this.size ? this.size[0] : rect.width;
        const height = this.size ? this.size[1] : rect.height;
        this.overlay.setAttribute('viewBox', `0 0 ${width} ${height}`);
        this.overlay.style.left = (rect.left + window.scrollX) + 'px';
        this.overlay.style.top = (rect.top + window.scrollY) + 'px';
        this.overlay.style.width = rect.width + 'px';
        this.overlay.style.height = rect.height + 'px';
        return { rect, width, height };
      },

      // The drawing the arrays describe; the container itself when it holds none.
      chart() {
        return this.el.querySelector('svg, canvas') || this.el;
      },

      // The index of the nearest x by binary search, the lower of two equidistant ones.
      nearest(x) {
        const xs = this.xs;
        let lo = 0;
        let hi = xs.length - 1;
        while (lo < hi) {
          const mid = (lo + hi) >> 1;
          if (xs[mid] < x) lo = mid + 1; else hi = mid;
        }
        if (lo > 0 && x - xs[lo - 1] <= xs[lo] - x) return lo - 1;
        return lo;
      },

      handleMouseMove(e) {
        this.show(e.clientX, e.clientY);
      },

      handleTouchMove(e) {
        if (e.touches.length !== 1) return;
        const touch = e.touches[0];
        this.show(touch.clientX, touch.clientY);
      },

      show(clientX, clientY) {
        if (this.xs.length === 0) return;
        const p = this.chartPoint(clientX, clientY);
        if (p.x < 0 || p.x > this.plot.width || p.y < 0 || p.y > this.plot.height) {
          this.leave();
          return;
        }
        if (this.sync) {
          VisualizeSync.publish(this.sync, this.el, VisualizeSync.toDomain(this.sync, p.x + this.plot.left));
          this.publishing = true;
        }
        this.draw(p.x, true);
      },

      // Another member's hover (spec/10 §13.4): drawn at the same domain x through this
      // chart's own mapping, the overlay hidden for a clear or a value outside the domain.
      handleSync(e) {
        if (VisualizeSync.own(this.el, e.detail.source)) return;
        this.syncTo(e.detail.x);
      },

      syncTo(value) {
        const chartX = this.sync ? VisualizeSync.toChart(this.sync, value) : null;
        if (chartX === null || this.xs.length === 0) {
          this.hide();
          return;
        }
        this.place();
        this.draw(chartX - this.plot.left, false);
      },

      // The rule and the markers at the nearest x to a plot x; only the chart's own
      // pointer pushes the event.
      draw(plotX, local) {
        const index = this.nearest(plotX);
        const x = this.xs[index];
        this.rule.setAttribute('x1', x);
        this.rule.setAttribute('x2', x);
        this.markers.forEach((marker, i) => {
          const y = this.ys[i][index];
          if (y === null || y === undefined) {
            marker.setAttribute('visibility', 'hidden');
            return;
          }
          marker.removeAttribute('visibility');
          marker.setAttribute('cx', x);
          marker.setAttribute('cy', y);
        });
        this.overlay.style.display = 'block';
        if (local && this.eventName && index !== this.lastIndex) {
          this.lastIndex = index;
          this.pushEvent(this.eventName, { index });
        }
      },

      hide() {
        this.overlay.style.display = 'none';
      },

      // The pointer left: hidden here and, once after a hover this chart published, cleared
      // on every member of the group.
      leave() {
        this.hide();
        if (this.sync && this.publishing) VisualizeSync.publish(this.sync, this.el, null);
        this.publishing = false;
      },

      updated() {
        this.read();
      },

      destroyed() {
        this.el.removeEventListener('mousemove', this.onMouseMove);
        this.el.removeEventListener('mouseleave', this.onMouseLeave);
        this.el.removeEventListener('touchmove', this.onTouchMove);
        this.el.removeEventListener('touchend', this.onTouchEnd);
        VisualizeSync.detach(this);
        if (this.overlay.parentNode) this.overlay.parentNode.removeChild(this.overlay);
      }
    };
    """
  end
end
