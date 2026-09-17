defmodule ExamplesWeb.HybridLive do
  @moduledoc """
  Demonstrates hybrid SVG/Canvas rendering.

  - Static axes rendered once as SVG (only re-renders on scale change)
  - Dynamic data rendered as Canvas commands (updates every frame)
  """

  use Phoenix.LiveView

  alias Visualize.{Scale, Shape, Axis}
  alias Visualize.IR.{Element, Transform}
  alias Visualize.Backend.{SVG, Canvas}

  @width 800
  @height 500
  @margin %{top: 30, right: 30, bottom: 50, left: 60}
  @inner_width @width - @margin.left - @margin.right
  @inner_height @height - @margin.top - @margin.bottom

  @data_points 300
  @update_interval 16  # ~60 FPS

  def mount(_params, _session, socket) do
    # Create scales (these determine axis rendering)
    x_scale = Scale.Linear.new()
      |> Scale.Linear.domain([0, @data_points - 1])
      |> Scale.Linear.range([0, @inner_width])

    y_scale = Scale.Linear.new()
      |> Scale.Linear.domain([0, 100])
      |> Scale.Linear.range([@inner_height, 0])

    # Pre-render static SVG (axes) - only changes if scales change
    static_svg = render_static_svg(x_scale, y_scale)

    {:ok, assign(socket,
      running: false,
      frame: 0,
      fps: 0.0,
      width: @width,
      height: @height,
      x_scale: x_scale,
      y_scale: y_scale,
      static_svg: static_svg,
      canvas_commands: "",
      frame_times: [],
      render_times: []
    )}
  end

  def handle_event("start", _params, socket) do
    schedule_frame()
    {:noreply, assign(socket,
      running: true,
      frame: 0,
      frame_times: [],
      render_times: []
    )}
  end

  def handle_event("stop", _params, socket) do
    {:noreply, assign(socket, running: false)}
  end

  def handle_info(:render_frame, socket) do
    if socket.assigns.running do
      render_start = System.monotonic_time(:microsecond)

      # Generate animated data
      data = generate_wave_data(socket.assigns.frame)

      # Render ONLY the data path as Canvas commands
      canvas_commands = render_data_canvas(data, socket.assigns.x_scale, socket.assigns.y_scale)

      render_time = System.monotonic_time(:microsecond) - render_start
      now = System.monotonic_time(:millisecond)

      # Track metrics
      frame_times = Enum.take([now | socket.assigns.frame_times], 60)
      render_times = Enum.take([render_time | socket.assigns.render_times], 60)
      fps = calculate_fps(frame_times)

      schedule_frame()

      {:noreply, assign(socket,
        frame: socket.assigns.frame + 1,
        canvas_commands: canvas_commands,
        frame_times: frame_times,
        render_times: render_times,
        fps: fps
      )}
    else
      {:noreply, socket}
    end
  end

  defp schedule_frame do
    Process.send_after(self(), :render_frame, @update_interval)
  end

  defp calculate_fps([]), do: 0.0
  defp calculate_fps([_]), do: 0.0
  defp calculate_fps(times) do
    oldest = List.last(times)
    newest = hd(times)
    duration_ms = newest - oldest
    if duration_ms > 0, do: (length(times) - 1) / (duration_ms / 1000), else: 0.0
  end

  defp generate_wave_data(frame) do
    phase = frame * 0.08
    for i <- 0..(@data_points - 1) do
      x = i
      # Multiple sine waves with different frequencies
      y = 50 +
          :math.sin(i / 20 + phase) * 25 +
          :math.sin(i / 7 + phase * 1.3) * 12 +
          :math.sin(i / 3 + phase * 0.7) * 5
      %{x: x, y: y}
    end
  end

  # Render static SVG (axes, grid, labels) - called once or on scale change
  defp render_static_svg(x_scale, y_scale) do
    # Create axes
    x_axis = Axis.bottom(x_scale) |> Axis.ticks(10)
    y_axis = Axis.left(y_scale) |> Axis.ticks(5)

    x_axis_element = Axis.generate(x_axis)
    y_axis_element = Axis.generate(y_axis)

    # Position x-axis at bottom
    x_axis_group = Element.group([x_axis_element],
      transform: Transform.translate(0, @inner_height)
    )

    # Create grid lines
    grid_lines = create_grid_lines(x_scale, y_scale)

    # Title
    title = Element.text("Hybrid SVG/Canvas Chart",
      x: @inner_width / 2,
      y: -10,
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

    # Combine all static elements
    static_group = Element.group([grid_lines, x_axis_group, y_axis_element, title, x_label, y_label],
      transform: Transform.translate(@margin.left, @margin.top)
    )

    root = Element.root(@width, @height,
      children: [static_group],
      style: %{background: "transparent"}
    )

    SVG.render_element(root, [])
    |> IO.iodata_to_binary()
  end

  defp create_grid_lines(x_scale, y_scale) do
    x_ticks = Scale.ticks(x_scale, 10)
    y_ticks = Scale.ticks(y_scale, 5)

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

  # Render ONLY the data as Canvas commands - called every frame
  defp render_data_canvas(data, x_scale, y_scale) do
    line = Shape.Line.new()
      |> Shape.Line.x(fn d -> Scale.Linear.apply(x_scale, d.x) end)
      |> Shape.Line.y(fn d -> Scale.Linear.apply(y_scale, d.y) end)
      |> Shape.Line.curve(:monotone_x)

    path = Shape.Line.generate_path(line, data)

    # Create path element with styling
    element = Element.path(path, %{
      stroke: "#4e79a7",
      stroke_width: 2,
      fill: :none
    })
    |> Element.set_transform(Transform.translate(@margin.left, @margin.top))

    Canvas.render_element(element, format: :json)
    |> IO.iodata_to_binary()
  end

  def render(assigns) do
    avg_render_time = if length(assigns.render_times) > 0 do
      Enum.sum(assigns.render_times) / length(assigns.render_times)
    else
      0
    end

    assigns = assign(assigns, avg_render_time: avg_render_time)

    ~H"""
    <ExamplesWeb.SiteHeader.header tab={:performance} />
    <div class="page-intro" style="padding: 1.5rem 2rem 0;">
      <h2>Hybrid SVG/Canvas Rendering</h2>
      <p>Static axes in SVG, dynamic data on Canvas</p>
    </div>

    <main>
      <a href="/" class="back-link">
        <span>&larr;</span> Back to Gallery
      </a>

      <div class="hybrid-demo">
        <div class="controls">
          <%= if @running do %>
            <button type="button" phx-click="stop" class="btn stop">Stop Animation</button>
          <% else %>
            <button type="button" phx-click="start" class="btn start">Start Animation</button>
          <% end %>

          <div class="metrics">
            <div class="metric">
              <span class="label">Frame:</span>
              <span class="value"><%= @frame %></span>
            </div>
            <div class="metric">
              <span class="label">FPS:</span>
              <span class="value"><%= Float.round(@fps, 1) %></span>
            </div>
            <div class="metric">
              <span class="label">Render Time:</span>
              <span class="value"><%= Float.round(@avg_render_time / 1000, 2) %> ms</span>
            </div>
            <div class="metric">
              <span class="label">Canvas Payload:</span>
              <span class="value"><%= Float.round(byte_size(@canvas_commands) / 1024, 1) %> KB</span>
            </div>
          </div>
        </div>

        <div class="chart-wrapper">
          <div class="explanation">
            <div class="layer svg-layer">
              <span class="dot"></span>
              <strong>SVG Layer (static):</strong> Axes, grid, labels - rendered once
            </div>
            <div class="layer canvas-layer">
              <span class="dot"></span>
              <strong>Canvas Layer (dynamic):</strong> Data line - updates every frame
            </div>
          </div>

          <div
            class="hybrid-chart"
            style={"position: relative; width: #{@width}px; height: #{@height}px; background: white; border-radius: 8px; box-shadow: 0 2px 8px rgba(0,0,0,0.1);"}
          >
            <!-- Static SVG background - axes, grid, labels -->
            <div style="position: absolute; top: 0; left: 0; pointer-events: none;">
              <%= Phoenix.HTML.raw(@static_svg) %>
            </div>

            <!-- Dynamic Canvas overlay - data line only -->
            <div
              id="data-canvas"
              phx-hook="CanvasChart"
              phx-update="ignore"
              data-commands={@canvas_commands}
              data-width={@width}
              data-height={@height}
              style="position: absolute; top: 0; left: 0;"
            >
              <canvas width={@width} height={@height} style="display: block;"></canvas>
            </div>
          </div>
        </div>

        <div class="benefits">
          <h3>Why Hybrid Rendering?</h3>
          <ul>
            <li><strong>Reduced payload:</strong> Only the data path is sent each frame (~<%= Float.round(byte_size(@canvas_commands) / 1024, 1) %> KB), not the entire chart</li>
            <li><strong>No DOM churn:</strong> SVG axes aren't recreated on updates</li>
            <li><strong>Fast Canvas rendering:</strong> Browser just executes draw commands on bitmap</li>
            <li><strong>Crisp axes:</strong> SVG keeps text and lines sharp at any zoom</li>
          </ul>
        </div>
      </div>
    </main>

    <style>
      .hybrid-demo {
        max-width: 900px;
        margin: 0 auto;
      }

      .controls {
        display: flex;
        align-items: center;
        gap: 2rem;
        margin-bottom: 1.5rem;
        padding: 1rem;
        background: #f8f9fa;
        border-radius: 8px;
      }

      .btn {
        padding: 0.75rem 1.5rem;
        border: none;
        border-radius: 6px;
        font-weight: 600;
        cursor: pointer;
        transition: all 0.2s;
      }

      .btn.start {
        background: #10b981;
        color: white;
      }

      .btn.stop {
        background: #ef4444;
        color: white;
      }

      .btn:hover {
        transform: translateY(-2px);
        box-shadow: 0 4px 12px rgba(0,0,0,0.2);
      }

      .metrics {
        display: flex;
        gap: 1.5rem;
      }

      .metric {
        display: flex;
        flex-direction: column;
        align-items: center;
      }

      .metric .label {
        font-size: 11px;
        color: #666;
        text-transform: uppercase;
      }

      .metric .value {
        font-size: 1.25rem;
        font-weight: 600;
        font-family: monospace;
        color: #333;
      }

      .chart-wrapper {
        margin-bottom: 1.5rem;
      }

      .explanation {
        display: flex;
        gap: 2rem;
        margin-bottom: 0.75rem;
        font-size: 13px;
      }

      .layer {
        display: flex;
        align-items: center;
        gap: 0.5rem;
      }

      .layer .dot {
        width: 12px;
        height: 12px;
        border-radius: 3px;
      }

      .svg-layer .dot {
        background: #f97316;
      }

      .canvas-layer .dot {
        background: #4e79a7;
      }

      .hybrid-chart {
        overflow: hidden;
      }

      .benefits {
        background: #f0fdf4;
        padding: 1.5rem;
        border-radius: 8px;
      }

      .benefits h3 {
        margin-top: 0;
        color: #166534;
      }

      .benefits ul {
        margin: 0;
        padding-left: 1.25rem;
      }

      .benefits li {
        margin-bottom: 0.5rem;
        color: #333;
      }
    </style>
    """
  end
end
