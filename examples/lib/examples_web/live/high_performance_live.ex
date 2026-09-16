defmodule ExamplesWeb.HighPerformanceLive do
  @moduledoc """
  High-performance chart demo: five series at a whole number of samples per pixel column.

  Demonstrates:
  - Combined area chart + multi-line overlay (8,105 points at the default density)
  - Incremental rendering with scroll+copy optimization
  - Binary Canvas encoding (60% smaller than JSON)
  - Hybrid rendering (static SVG axes + dynamic Canvas data)
  - Real-time FPS monitoring

  The animation is the scroll (spec/14 §12.6, #292): a copy-shift frame is the previous
  frame translated by exactly `scroll_delta` pixels, so every series is a function of an
  absolute sample index, a sample is `1 / samples_per_px` pixels, and the frame's `origin`
  advances by a whole number of samples. Nothing else changes between frames.
  """

  use Phoenix.LiveView

  alias Examples.Scroll
  alias Visualize.{Scale, Shape, Axis}
  alias Visualize.IR.{Element, Transform}
  alias Visualize.Backend.{SVG, CanvasIncremental}

  @width 900
  @height 500
  @margin %{top: 40, right: 30, bottom: 50, left: 60}
  @inner_width @width - @margin.left - @margin.right
  @inner_height @height - @margin.top - @margin.bottom

  @num_lines 4  # 4 lines on top of area = 5 series total
  @series @num_lines + 1
  @densities [1, 2, 5, 12]  # samples per pixel column the page offers
  @default_samples_per_px 2
  @default_target_fps 60
  @scroll_delta 5  # pixels to scroll per frame

  # Color palette: first is area fill, rest are lines
  @area_color "#4e79a7"
  @line_colors ["#f28e2c", "#e15759", "#76b7b2", "#59a14f"]

  def mount(_params, _session, socket) do
    y_scale = Scale.Linear.new()
      |> Scale.Linear.domain([-100, 100])
      |> Scale.Linear.range([@inner_height, 0])

    {:ok, assign(socket,
      width: @width,
      height: @height,
      running: false,
      frame: 0,
      fps: 0.0,
      target_fps: @default_target_fps,
      densities: @densities,
      y_scale: y_scale,
      frame_times: [],
      render_times: [],
      payload_size: 0,
      viewport_x: 0,
      use_incremental: true,
      last_full_render: true,
      points_rendered: 0
    )
    |> at_density(@default_samples_per_px)}
  end

  def handle_event("start", _params, socket) do
    # Send initial full render
    socket = send_full_render(socket)
    schedule_frame(socket.assigns.target_fps)
    {:noreply, assign(socket,
      running: true,
      frame: 0,
      frame_times: [],
      render_times: [],
      last_full_render: true
    )}
  end

  def handle_event("stop", _params, socket) do
    {:noreply, assign(socket, running: false)}
  end

  def handle_event("toggle_incremental", _params, socket) do
    {:noreply, assign(socket, use_incremental: not socket.assigns.use_incremental)}
  end

  def handle_event("set_points", %{"points" => density}, socket) do
    samples_per_px = String.to_integer(density)
    true = samples_per_px in @densities
    {:noreply, socket |> at_density(samples_per_px) |> assign(:last_full_render, true)}
  end

  def handle_event("set_fps", %{"fps" => fps_str}, socket) do
    # Slider value 130 = unlimited (no delay)
    target_fps = String.to_integer(fps_str)
    {:noreply, assign(socket, target_fps: target_fps)}
  end

  def handle_info(:render_frame, socket) do
    if socket.assigns.running do
      render_start = System.monotonic_time(:microsecond)

      # The scroll is the animation: the window advances by the frame's scroll in samples,
      # and the random line drops and appends that many (spec/14 §12.6, `Examples.Scroll`).
      scroll = Scroll.advance(socket.assigns.scroll, @scroll_delta)
      random_data = Scroll.shift(scroll, socket.assigns.random_data, @scroll_delta, fn _ -> random_sample() end)

      # Update viewport (scrolling right exposes new data on right)
      viewport_x = socket.assigns.viewport_x + @scroll_delta

      socket = assign(socket, random_data: random_data, scroll: scroll, viewport_x: viewport_x)

      # Choose rendering mode
      socket = if socket.assigns.use_incremental and not socket.assigns.last_full_render do
        send_incremental_render(socket)
      else
        send_full_render(socket)
        |> assign(:last_full_render, false)
      end

      render_time = System.monotonic_time(:microsecond) - render_start
      now = System.monotonic_time(:millisecond)

      # Track metrics
      frame_times = Enum.take([now | socket.assigns.frame_times], 60)
      render_times = Enum.take([render_time | socket.assigns.render_times], 60)
      fps = calculate_fps(frame_times)

      schedule_frame(socket.assigns.target_fps)

      {:noreply, assign(socket,
        frame: socket.assigns.frame + 1,
        frame_times: frame_times,
        render_times: render_times,
        fps: fps
      )}
    else
      {:noreply, socket}
    end
  end

  # ============================================================
  # The data model: samples per pixel column (spec/14 §12.6)
  # ============================================================

  @doc false
  # The page at `samples_per_px`: a fresh `Examples.Scroll` window over the plot's columns,
  # its x scale, and a fresh random line. Public for the stream test.
  def at_density(socket, samples_per_px) do
    scroll = Scroll.new(@inner_width, samples_per_px)
    points_per_series = Scroll.count(scroll)
    x_scale = Scroll.x_scale(scroll)

    assign(socket,
      samples_per_px: samples_per_px,
      scroll: scroll,
      points_per_series: points_per_series,
      total_points: points_per_series * @series,
      x_scale: x_scale,
      static_svg: render_static_svg(x_scale, socket.assigns.y_scale, points_per_series),
      random_data: for(_ <- 1..points_per_series, do: random_sample())
    )
  end

  @doc false
  # The total the page offers at a density, for the select.
  def total_at(samples_per_px), do: Scroll.count(Scroll.new(@inner_width, samples_per_px)) * @series

  defp random_sample, do: :rand.uniform() * 60 + 40

  @doc false
  # A series' value at absolute sample `j` of a series `count` samples long: one function
  # for the full render and a region render, with no term that changes between frames, so
  # a frame is the previous one translated by the scroll (spec/09 §5.3). Line 0 is the
  # random line and is read from `random_data`, not computed.
  def series_y(:area, j, count) do
    t = j / count
    :math.sin(t * 8) * 25 + :math.sin(t * 3) * 15 - 20
  end

  def series_y({:line, line_idx}, j, count) when line_idx > 0 do
    offset = line_idx * 0.8
    amplitude = 35 - line_idx * 5
    frequency = 12 + line_idx * 4
    t = j / count

    :math.sin(t * frequency + offset) * amplitude +
      :math.cos(t * (frequency / 2.5) + offset) * (amplitude / 3) +
      (line_idx - 1.5) * 15
  end

  # ============================================================
  # Rendering
  # ============================================================

  defp send_full_render(socket) do
    element = build_chart_element(socket.assigns)
    binary = CanvasIncremental.encode_full_redraw(element, {@width, @height})
    encoded = Base.encode64(binary)

    socket
    |> assign(:payload_size, byte_size(binary))
    |> assign(:points_rendered, socket.assigns.total_points)
    |> push_event("canvas_incremental", %{
      binary: encoded,
      dx: 0,
      dy: 0,
      mode: "full"
    })
  end

  defp send_incremental_render(socket) do
    # Use inner chart dimensions for exposed region calculation
    # This ensures the region falls within the data area, not the margins
    inner_size = {@inner_width, @inner_height}

    # Positive dx = scroll right = RIGHT edge exposed (where new data appears)
    dx = @scroll_delta

    # Calculate exposed region relative to inner chart area
    regions = CanvasIncremental.exposed_regions({dx, 0}, inner_size)

    # Adjust region coordinates to account for margins
    adjusted_regions = Enum.map(regions, fn {rx, ry, rw, rh} ->
      {@margin.left + rx, @margin.top + ry, rw, rh}
    end)

    # Build elements ONLY for the exposed region's data
    region_elements = Enum.map(adjusted_regions, fn {rx, ry, rw, rh} = bounds ->
      element = build_region_element(socket.assigns, {rx, ry, rw, rh})
      {bounds, element}
    end)

    # Encode incremental update: the plot is what scrolls, the margin's axes stay (D-106)
    binary =
      CanvasIncremental.encode_incremental({dx, 0}, {@width, @height}, region_elements,
        viewport: {@margin.left, @margin.top, @inner_width, @inner_height}
      )
    encoded = Base.encode64(binary)

    socket
    |> assign(:payload_size, byte_size(binary))
    |> assign(:points_rendered, calculate_region_points(socket.assigns, adjusted_regions))
    |> push_event("canvas_incremental", %{
      binary: encoded,
      dx: dx,
      dy: 0,
      mode: "scroll_x"
    })
  end

  # Calculate how many points are in the exposed regions
  defp calculate_region_points(%{scroll: scroll}, regions) do
    Enum.reduce(regions, 0, fn {rx, _ry, rw, _rh}, acc ->
      case Scroll.columns(scroll, {rx - @margin.left, rw}, 0) do
        {first, last} -> acc + (last - first + 1) * @series
        nil -> acc
      end
    end)
  end

  @doc false
  # The chart over ONLY the samples under the exposed region: the same series function as
  # the full render over the region's columns, with a two-sample buffer each side so a
  # path enters and leaves the strip on its own line. Public for the stream test.
  def build_region_element(%{scroll: scroll} = assigns, {rx, _ry, rw, _rh}) do
    # The region is in canvas pixels; the window's columns are the plot's.
    case Scroll.columns(scroll, {rx - @margin.left, rw}) do
      {first, last} -> chart(assigns, first, last)
      nil -> Element.root(@width, @height, children: [])
    end
  end

  @doc false
  # The whole chart. Public for the stream test of #270: the page's own bytes decoded under test.
  def build_chart_element(assigns) do
    chart(assigns, 0, assigns.points_per_series - 1)
  end

  # The chart over columns `start_idx..end_idx`: the area under four lines, each series
  # `series_y/3` at `origin + i` for column `i`, in a group at the plot's margin.
  defp chart(assigns, start_idx, end_idx) do
    %{scroll: %{origin: origin}, points_per_series: count, x_scale: x_scale, y_scale: y_scale} = assigns

    xs = for i <- start_idx..end_idx, do: i * 1.0

    # 1. Area chart (bottom layer) - smooth wave
    area_ys = for i <- start_idx..end_idx, do: series_y(:area, origin + i, count)
    area_data = Enum.zip(xs, area_ys) |> Enum.map(fn {x, y} -> %{x: x, y: y} end)

    area = Shape.Area.new()
      |> Shape.Area.x(fn d -> Scale.Linear.apply(x_scale, d.x) end)
      |> Shape.Area.y0(fn _ -> @inner_height end)
      |> Shape.Area.y1(fn d -> Scale.Linear.apply(y_scale, d.y) end)

    area_path = Shape.Area.generate_path(area, area_data)
    area_element = Element.path(area_path, %{fill: @area_color, fill_opacity: 0.7, stroke: @area_color, stroke_width: 1})

    # 2. Line series
    line_elements = for {color, line_idx} <- Enum.with_index(@line_colors) do
      ys = if line_idx == 0 do
        Enum.slice(assigns.random_data, start_idx..end_idx)
      else
        for i <- start_idx..end_idx, do: series_y({:line, line_idx}, origin + i, count)
      end

      line_data = Enum.zip(xs, ys) |> Enum.map(fn {x, y} -> %{x: x, y: y} end)

      line = Shape.Line.new()
        |> Shape.Line.x(fn d -> Scale.Linear.apply(x_scale, d.x) end)
        |> Shape.Line.y(fn d -> Scale.Linear.apply(y_scale, d.y) end)

      line_path = Shape.Line.generate_path(line, line_data)
      Element.path(line_path, %{stroke: color, stroke_width: 2, fill: :none})
    end

    # Combine all elements in a group with margin transform
    chart_group = Element.group([area_element | line_elements],
      transform: Transform.translate(@margin.left, @margin.top)
    )

    Element.root(@width, @height, children: [chart_group])
  end

  defp schedule_frame(target_fps) do
    # > 2000 = unlimited (no delay), otherwise convert FPS to milliseconds
    interval = if target_fps > 2000, do: 0, else: div(1000, target_fps)
    Process.send_after(self(), :render_frame, interval)
  end

  defp calculate_fps([]), do: 0.0
  defp calculate_fps([_]), do: 0.0
  defp calculate_fps(times) do
    oldest = List.last(times)
    newest = hd(times)
    duration_ms = newest - oldest
    if duration_ms > 0, do: (length(times) - 1) / (duration_ms / 1000), else: 0.0
  end

  # ============================================================
  # Static SVG (Axes, Grid, Labels)
  # ============================================================

  defp render_static_svg(x_scale, y_scale, points_per_series) do
    x_axis = Axis.bottom(x_scale) |> Axis.ticks(10)
    y_axis = Axis.left(y_scale) |> Axis.ticks(10)

    x_axis_element = Axis.generate(x_axis)
    y_axis_element = Axis.generate(y_axis)

    x_axis_group = Element.group([x_axis_element],
      transform: Transform.translate(0, @inner_height)
    )

    # Grid lines
    grid_lines = create_grid_lines(x_scale, y_scale)

    # Title with point breakdown
    total = points_per_series * @series
    title = Element.text("Area + Multi-Line Chart (#{format_number(total)} points total)",
      x: @inner_width / 2,
      y: -15,
      style: %{text_anchor: :middle, font_size: 16, font_weight: :bold, fill: "#333"}
    )

    # Axis labels
    x_label = Element.text("Data Point Index",
      x: @inner_width / 2,
      y: @inner_height + 40,
      style: %{text_anchor: :middle, font_size: 12, fill: "#666"}
    )

    y_label = Element.text("Value",
      x: -@inner_height / 2,
      y: -45,
      style: %{text_anchor: :middle, font_size: 12, fill: "#666"},
      transform: Transform.rotate(-90)
    )

    static_group = Element.group(
      [grid_lines, x_axis_group, y_axis_element, title, x_label, y_label],
      transform: Transform.translate(@margin.left, @margin.top)
    )

    root = Element.root(@width, @height,
      children: [static_group],
      style: %{background: "transparent"}
    )

    SVG.render_element(root, [])
    |> IO.iodata_to_binary()
  end

  defp format_number(n) do
    n
    |> Integer.to_string()
    |> String.replace(~r/(\d)(?=(\d{3})+(?!\d))/, "\\1,")
  end

  defp create_grid_lines(x_scale, y_scale) do
    x_ticks = Scale.ticks(x_scale, 10)
    y_ticks = Scale.ticks(y_scale, 10)

    x_lines = Enum.map(x_ticks, fn tick ->
      x = Scale.Linear.apply(x_scale, tick)
      Element.line(x, 0, x, @inner_height, %{stroke: "#e0e0e0", stroke_width: 1})
    end)

    y_lines = Enum.map(y_ticks, fn tick ->
      y = Scale.Linear.apply(y_scale, tick)
      Element.line(0, y, @inner_width, y, %{stroke: "#e0e0e0", stroke_width: 1})
    end)

    Element.group(x_lines ++ y_lines)
  end

  def render(assigns) do
    avg_render_time = if length(assigns.render_times) > 0 do
      Enum.sum(assigns.render_times) / length(assigns.render_times)
    else
      0
    end

    assigns = assign(assigns, avg_render_time: avg_render_time)

    ~H"""
    <header>
      <h1>High-Performance Charts</h1>
      <p>Area + Multi-Line with 10,000 total data points</p>
    </header>

    <main>
      <a href="/" class="back-link">
        <span>&larr;</span> Back to Gallery
      </a>

      <div class="performance-demo">
        <div class="controls">
          <form phx-change="set_points" class="control-group">
            <label>Total Points:</label>
            <select name="points" class="points-select">
              <option :for={d <- @densities} value={d} selected={@samples_per_px == d}>
                <%= format_number(total_at(d)) %> (<%= d %>/px)
              </option>
            </select>
            <span class="point-breakdown">
              (1 area + 4 lines × <%= format_number(@points_per_series) %> pts each)
            </span>
          </form>

          <form phx-change="set_fps" class="control-group">
            <label>Target FPS:</label>
            <input type="range" name="fps" min="10" max="2010" step="10" value={@target_fps} class="fps-slider" />
            <span class="fps-value"><%= if @target_fps > 2000, do: "∞", else: @target_fps %></span>
          </form>

          <button type="button" phx-click="toggle_incremental" class={"btn mode #{if @use_incremental, do: "active", else: ""}"}>
            <%= if @use_incremental, do: "Incremental ON", else: "Incremental OFF" %>
          </button>

          <%= if @running do %>
            <button type="button" phx-click="stop" class="btn stop">Stop</button>
          <% else %>
            <button type="button" phx-click="start" class="btn start">Start Animation</button>
          <% end %>
        </div>

        <div class="metrics-bar">
          <div class="metric big">
            <span class="value"><%= trunc(@fps) %></span>
            <span class="label">FPS</span>
          </div>
          <div class="metric">
            <span class="value"><%= if @target_fps > 2000, do: "∞", else: @target_fps %></span>
            <span class="label">Target</span>
          </div>
          <div class="metric">
            <span class="value"><%= format_number(@total_points) %></span>
            <span class="label">Total Points</span>
          </div>
          <div class="metric">
            <span class="value"><%= format_number(@points_rendered) %></span>
            <span class="label">Pts/Frame</span>
          </div>
          <div class="metric">
            <span class="value"><%= Float.round(@avg_render_time / 1000, 2) %> ms</span>
            <span class="label">Render Time</span>
          </div>
          <div class="metric">
            <span class="value"><%= Float.round(@payload_size / 1024, 1) %> KB</span>
            <span class="label">Payload</span>
          </div>
          <div class="metric">
            <span class="value"><%= if @use_incremental, do: "Inc", else: "Full" %></span>
            <span class="label">Mode</span>
          </div>
          <div class="metric">
            <span class="value"><%= @frame %></span>
            <span class="label">Frame</span>
          </div>
        </div>

        <div class="chart-container">
          <div
            class="chart"
            style={"position: relative; width: #{@width}px; height: #{@height}px; background: white; border-radius: 8px; box-shadow: 0 2px 8px rgba(0,0,0,0.1);"}
          >
            <!-- Static SVG (axes, grid) - rendered once -->
            <div style="position: absolute; top: 0; left: 0; pointer-events: none;">
              <%= Phoenix.HTML.raw(@static_svg) %>
            </div>

            <!-- Dynamic Canvas (data) - updates each frame with incremental optimization -->
            <div
              id="high-perf-canvas"
              phx-hook="CanvasIncrementalChart"
              phx-update="ignore"
              data-width={@width}
              data-height={@height}
              style="position: absolute; top: 0; left: 0;"
            >
              <canvas width={@width} height={@height} style="display: block;"></canvas>
            </div>
          </div>
        </div>

        <div class="tech-info">
          <h3>Technology Stack</h3>
          <ul>
            <li><strong>Combined Chart:</strong> 1 area (filled) + 4 line series rendered in layers</li>
            <li><strong>Incremental Mode:</strong> Copy+shift existing canvas, render only new exposed region</li>
            <li><strong>Binary Encoding:</strong> ~60% smaller than JSON, direct Float64Array decode</li>
            <li><strong>Hybrid Rendering:</strong> Static SVG axes + Dynamic Canvas data</li>
            <li><strong>LiveView:</strong> WebSocket push, minimal DOM updates</li>
          </ul>
          <p style="margin-top: 1rem; font-size: 13px; color: #666;">
            <strong>Tip:</strong> Toggle "Incremental" to compare full redraw vs scroll+copy optimization.
            Incremental mode copies existing pixels and only renders the newly exposed strip.
          </p>
        </div>
      </div>
    </main>

    <style>
      .performance-demo {
        max-width: 950px;
        margin: 0 auto;
      }

      .controls {
        display: flex;
        align-items: center;
        gap: 1.5rem;
        margin-bottom: 1rem;
        padding: 1rem;
        background: #f8f9fa;
        border-radius: 8px;
        flex-wrap: wrap;
      }

      .control-group {
        display: flex;
        align-items: center;
        gap: 0.5rem;
      }

      .control-group label {
        font-size: 13px;
        color: #666;
        font-weight: 500;
      }

      .points-select {
        padding: 0.5rem;
        border: 1px solid #ddd;
        border-radius: 6px;
        font-size: 13px;
        background: white;
      }

      .point-breakdown {
        font-size: 12px;
        color: #888;
        margin-left: 0.5rem;
      }

      .fps-slider {
        width: 120px;
        cursor: pointer;
      }

      .fps-value {
        font-size: 14px;
        font-weight: 600;
        color: #333;
        min-width: 2rem;
        text-align: center;
      }

      .btn {
        padding: 0.6rem 1.2rem;
        border: none;
        border-radius: 6px;
        font-weight: 600;
        cursor: pointer;
        transition: all 0.2s;
        font-size: 14px;
      }

      .btn.start {
        background: linear-gradient(135deg, #10b981 0%, #059669 100%);
        color: white;
      }

      .btn.stop {
        background: linear-gradient(135deg, #ef4444 0%, #dc2626 100%);
        color: white;
      }

      .btn.mode {
        background: #e5e7eb;
        color: #374151;
      }

      .btn.mode.active {
        background: linear-gradient(135deg, #3b82f6 0%, #2563eb 100%);
        color: white;
      }

      .btn:hover {
        transform: translateY(-2px);
        box-shadow: 0 4px 12px rgba(0,0,0,0.2);
      }

      .metrics-bar {
        display: flex;
        gap: 1.5rem;
        margin-bottom: 1rem;
        padding: 1rem 1.5rem;
        background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
        border-radius: 8px;
        color: white;
      }

      .metric {
        display: flex;
        flex-direction: column;
        align-items: center;
      }

      .metric .value {
        font-size: 1.25rem;
        font-weight: 700;
        font-family: 'Monaco', 'Menlo', monospace;
      }

      .metric .label {
        font-size: 11px;
        opacity: 0.9;
        text-transform: uppercase;
        letter-spacing: 0.5px;
      }

      .metric.big .value {
        font-size: 2rem;
      }

      .chart-container {
        margin-bottom: 1.5rem;
      }

      .tech-info {
        background: #f0fdf4;
        padding: 1.5rem;
        border-radius: 8px;
        border-left: 4px solid #10b981;
      }

      .tech-info h3 {
        margin: 0 0 1rem 0;
        color: #166534;
        font-size: 1rem;
      }

      .tech-info ul {
        margin: 0;
        padding-left: 1.25rem;
      }

      .tech-info li {
        margin-bottom: 0.5rem;
        color: #333;
        font-size: 14px;
      }
    </style>
    """
  end
end
