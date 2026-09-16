defmodule ExamplesWeb.HighPerformanceLive do
  @moduledoc """
  High-performance chart demo with 10,000 total data points.

  Demonstrates:
  - Combined area chart + multi-line overlay (10,000 points total)
  - Incremental rendering with scroll+copy optimization
  - Binary Canvas encoding (60% smaller than JSON)
  - Hybrid rendering (static SVG axes + dynamic Canvas data)
  - Real-time FPS monitoring
  """

  use Phoenix.LiveView

  alias Visualize.{Scale, Shape, Axis}
  alias Visualize.IR.{Element, Transform}
  alias Visualize.Backend.{SVG, CanvasIncremental}

  @width 900
  @height 500
  @margin %{top: 40, right: 30, bottom: 50, left: 60}
  @inner_width @width - @margin.left - @margin.right
  @inner_height @height - @margin.top - @margin.bottom

  @total_points 10_000
  @num_lines 4  # 4 lines on top of area = 5 series total
  @default_target_fps 60
  @scroll_delta 5  # pixels to scroll per frame

  # Color palette: first is area fill, rest are lines
  @area_color "#4e79a7"
  @line_colors ["#f28e2c", "#e15759", "#76b7b2", "#59a14f"]

  def mount(_params, _session, socket) do
    # Points per series (area + 4 lines = 5 series)
    points_per_series = div(@total_points, @num_lines + 1)

    # Create scales
    x_scale = Scale.Linear.new()
      |> Scale.Linear.domain([0, points_per_series - 1])
      |> Scale.Linear.range([0, @inner_width])

    y_scale = Scale.Linear.new()
      |> Scale.Linear.domain([-100, 100])
      |> Scale.Linear.range([@inner_height, 0])

    # Pre-render static SVG axes
    static_svg = render_static_svg(x_scale, y_scale, points_per_series)

    # Initialize random data for the scrolling random line
    random_data = for _i <- 1..points_per_series, do: :rand.uniform() * 60 + 40

    {:ok, assign(socket,
      width: @width,
      height: @height,
      running: false,
      frame: 0,
      fps: 0.0,
      target_fps: @default_target_fps,
      total_points: @total_points,
      points_per_series: points_per_series,
      x_scale: x_scale,
      y_scale: y_scale,
      static_svg: static_svg,
      frame_times: [],
      render_times: [],
      payload_size: 0,
      random_data: random_data,
      viewport_x: 0,
      use_incremental: true,
      last_full_render: true,
      points_rendered: 0
    )}
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

  def handle_event("set_points", %{"points" => points_str}, socket) do
    total = String.to_integer(points_str)
    points_per_series = div(total, @num_lines + 1)

    # Update scales for new point count
    x_scale = Scale.Linear.new()
      |> Scale.Linear.domain([0, points_per_series - 1])
      |> Scale.Linear.range([0, @inner_width])

    static_svg = render_static_svg(x_scale, socket.assigns.y_scale, points_per_series)

    # Regenerate random data for new point count
    random_data = for _i <- 1..points_per_series, do: :rand.uniform() * 60 + 40

    {:noreply, assign(socket,
      total_points: total,
      points_per_series: points_per_series,
      x_scale: x_scale,
      static_svg: static_svg,
      random_data: random_data,
      last_full_render: true
    )}
  end

  def handle_event("set_fps", %{"fps" => fps_str}, socket) do
    # Slider value 130 = unlimited (no delay)
    target_fps = String.to_integer(fps_str)
    {:noreply, assign(socket, target_fps: target_fps)}
  end

  def handle_info(:render_frame, socket) do
    if socket.assigns.running do
      render_start = System.monotonic_time(:microsecond)

      # Shift random data left and add new value on right
      [_first | rest] = socket.assigns.random_data
      new_value = :rand.uniform() * 60 + 40
      random_data = rest ++ [new_value]

      # Update viewport (scrolling right exposes new data on right)
      viewport_x = socket.assigns.viewport_x + @scroll_delta

      socket = assign(socket, random_data: random_data, viewport_x: viewport_x)

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

  defp send_full_render(socket) do
    element = build_chart_element(socket.assigns)
    binary = CanvasIncremental.encode_full_redraw(element)
    encoded = Base.encode64(binary)

    # Full render processes all points (5 series × points_per_series)
    total_points = socket.assigns.points_per_series * 5

    socket
    |> assign(:payload_size, byte_size(binary))
    |> assign(:points_rendered, total_points)
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

    # Encode incremental update
    binary = CanvasIncremental.encode_incremental({dx, 0}, {@width, @height}, region_elements)
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
  defp calculate_region_points(assigns, regions) do
    %{points_per_series: count, x_scale: x_scale} = assigns

    Enum.reduce(regions, 0, fn {rx, _ry, rw, _rh}, acc ->
      # Convert pixel bounds to data indices
      {start_idx, end_idx} = pixel_to_data_range(rx - @margin.left, rw, x_scale, count)
      points_in_region = max(0, end_idx - start_idx + 1)
      # Multiply by number of series (1 area + 4 lines)
      acc + points_in_region * 5
    end)
  end

  # Build element for ONLY the data in the exposed region
  @doc false
  def build_region_element(assigns, {rx, _ry, rw, _rh}) do
    %{frame: frame, points_per_series: count, x_scale: x_scale, y_scale: y_scale} = assigns

    # Convert pixel bounds to data index range
    # Account for margin offset - region might be in margin area
    pixel_x = rx - @margin.left
    {raw_start, raw_end} = pixel_to_data_range(pixel_x, rw, x_scale, count)

    # Check for invalid range BEFORE applying buffer
    # (region might be entirely in margin area)
    if raw_start > raw_end do
      Element.root(@width, @height, children: [])
    else
      # Add 2 points buffer on each side for smooth line entry/exit
      buffer = 2
      start_idx = max(0, raw_start - buffer)
      end_idx = min(count - 1, raw_end + buffer)

      # Need at least 2 points to draw lines/areas
      if end_idx - start_idx < 1 do
        Element.root(@width, @height, children: [])
      else
        build_region_chart(assigns, frame, count, x_scale, y_scale, start_idx, end_idx)
      end
    end
  end

  # Build the actual chart elements for the region
  defp build_region_chart(assigns, frame, count, x_scale, y_scale, start_idx, end_idx) do
    phase = frame * 0.04

    # Generate data ONLY for the region
    xs = for i <- start_idx..end_idx, do: i * 1.0

    # 1. Area chart (bottom layer) - only for region
    area_ys = for i <- start_idx..end_idx do
      t = i / count
      :math.sin(t * 8 + phase) * 25 + :math.sin(t * 3 + phase * 0.7) * 15 - 20
    end

    area_data = Enum.zip(xs, area_ys) |> Enum.map(fn {x, y} -> %{x: x, y: y} end)

    area = Shape.Area.new()
      |> Shape.Area.x(fn d -> Scale.Linear.apply(x_scale, d.x) end)
      |> Shape.Area.y0(fn _ -> @inner_height end)
      |> Shape.Area.y1(fn d -> Scale.Linear.apply(y_scale, d.y) end)

    area_path = Shape.Area.generate_path(area, area_data)
    area_element = Element.path(area_path, %{fill: @area_color, fill_opacity: 0.7, stroke: @area_color, stroke_width: 1})

    # 2. Line series - only for region
    line_elements = for {color, line_idx} <- Enum.with_index(@line_colors) do
      ys = if line_idx == 0 do
        # Extract only the region slice from random_data
        Enum.slice(assigns.random_data, start_idx..end_idx)
      else
        offset = line_idx * 0.8
        amplitude = 35 - line_idx * 5
        frequency = 12 + line_idx * 4

        for i <- start_idx..end_idx do
          t = i / count
          :math.sin(t * frequency + phase + offset) * amplitude +
          :math.cos(t * (frequency / 2.5) + phase * 1.3 + offset) * (amplitude / 3) +
          (line_idx - 1.5) * 15
        end
      end

      line_data = Enum.zip(xs, ys) |> Enum.map(fn {x, y} -> %{x: x, y: y} end)

      line = Shape.Line.new()
        |> Shape.Line.x(fn d -> Scale.Linear.apply(x_scale, d.x) end)
        |> Shape.Line.y(fn d -> Scale.Linear.apply(y_scale, d.y) end)

      line_path = Shape.Line.generate_path(line, line_data)
      Element.path(line_path, %{stroke: color, stroke_width: 2, fill: :none})
    end

    chart_group = Element.group([area_element | line_elements],
      transform: Transform.translate(@margin.left, @margin.top)
    )

    Element.root(@width, @height, children: [chart_group])
  end

  # Convert pixel x position and width to data index range
  defp pixel_to_data_range(pixel_x, pixel_width, _x_scale, count) do
    # Invert the scale to get data values from pixels
    # x_scale maps [0, count-1] -> [0, @inner_width]
    points_per_pixel = (count - 1) / @inner_width

    # Clamp pixel values to valid chart area
    # Region might extend into margin areas (negative or beyond inner_width)
    effective_start = max(0, pixel_x)
    effective_end = min(@inner_width, pixel_x + pixel_width)

    # If region is entirely outside chart area, return invalid range
    if effective_start >= effective_end do
      {1, 0}  # Invalid range (start > end)
    else
      start_idx = max(0, floor(effective_start * points_per_pixel))
      end_idx = min(count - 1, ceil(effective_end * points_per_pixel))
      {start_idx, end_idx}
    end
  end

  @doc false
  # Public for the stream test of #270: the page's own bytes decoded under test.
  def build_chart_element(assigns) do
    %{frame: frame, points_per_series: count, x_scale: x_scale, y_scale: y_scale} = assigns

    phase = frame * 0.04

    # Generate data for all series
    xs = for i <- 0..(count - 1), do: i * 1.0

    # 1. Area chart (bottom layer) - smooth wave
    area_ys = for i <- 0..(count - 1) do
      t = i / count
      :math.sin(t * 8 + phase) * 25 + :math.sin(t * 3 + phase * 0.7) * 15 - 20
    end

    area_data = Enum.zip(xs, area_ys) |> Enum.map(fn {x, y} -> %{x: x, y: y} end)

    # Build area element
    area = Shape.Area.new()
      |> Shape.Area.x(fn d -> Scale.Linear.apply(x_scale, d.x) end)
      |> Shape.Area.y0(fn _ -> @inner_height end)
      |> Shape.Area.y1(fn d -> Scale.Linear.apply(y_scale, d.y) end)

    area_path = Shape.Area.generate_path(area, area_data)
    area_element = Element.path(area_path, %{fill: @area_color, fill_opacity: 0.7, stroke: @area_color, stroke_width: 1})

    # 2. Line series
    line_elements = for {color, line_idx} <- Enum.with_index(@line_colors) do
      ys = if line_idx == 0 do
        assigns.random_data
      else
        offset = line_idx * 0.8
        amplitude = 35 - line_idx * 5
        frequency = 12 + line_idx * 4

        for i <- 0..(count - 1) do
          t = i / count
          :math.sin(t * frequency + phase + offset) * amplitude +
          :math.cos(t * (frequency / 2.5) + phase * 1.3 + offset) * (amplitude / 3) +
          (line_idx - 1.5) * 15
        end
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
    total = points_per_series * (@num_lines + 1)
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
              <option value="5000" selected={@total_points == 5000}>5,000</option>
              <option value="10000" selected={@total_points == 10000}>10,000</option>
              <option value="20000" selected={@total_points == 20000}>20,000</option>
              <option value="50000" selected={@total_points == 50000}>50,000</option>
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
