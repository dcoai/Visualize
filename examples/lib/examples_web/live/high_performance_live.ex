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

  alias Examples.{Run, Scroll}
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
  @default_target_fps 60
  @default_data_rate 600  # samples per second per series
  @span_seconds 5  # the plot spans about this much data at the rate; the density follows (#308)

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
      # The run (`Examples.Run`, #322): the frame loop, its clock, samples, acks, flow
      # control and metrics, in one assign.
      run: Run.new(target_fps: @default_target_fps, data_rate: @default_data_rate),
      y_scale: y_scale,
      points_rendered: 0,
      viewport_x: 0,
      use_incremental: true
    )
    |> at_density(density_for(@default_data_rate))}
  end

  def handle_event("start", _params, socket) do
    run = Run.start(socket.assigns.run, System.monotonic_time(:millisecond), System.monotonic_time(:microsecond))
    # The run opens with a full render, rendered like any frame; the ticks build on it.
    socket = socket |> assign(run: run, viewport_x: 0) |> start_render(:full_redraw, 0)
    {:noreply, schedule_frame(socket)}
  end

  def handle_event("stop", _params, socket) do
    {:noreply, update(socket, :run, &Run.stop/1)}
  end

  def handle_event("toggle_incremental", _params, socket) do
    {:noreply, assign(socket, use_incremental: not socket.assigns.use_incremental)}
  end

  def handle_event("set_fps", %{"fps" => fps_str}, socket) do
    # A slider value above 2000 is unlimited (no delay)
    {:noreply, update(socket, :run, &%{&1 | target_fps: String.to_integer(fps_str)})}
  end

  # The rate sizes the window: a new density is a fresh window and a full next frame.
  def handle_event("set_data_rate", %{"data_rate" => rate}, socket) do
    rate = String.to_integer(rate)
    density = density_for(rate)
    socket = update(socket, :run, &%{&1 | data_rate: rate})

    if density == socket.assigns.samples_per_px,
      do: {:noreply, socket},
      else: {:noreply, socket |> at_density(density) |> update(:run, &%{&1 | needs_full: true})}
  end

  def handle_event("toggle_flow_control", _params, socket) do
    {:noreply, update(socket, :run, &%{&1 | flow_control: not &1.flow_control})}
  end

  # The hook's ack (spec/10 §9.2): the last frame it drew and how many since its last ack.
  def handle_event("frame_drawn", %{"seq" => seq, "drawn" => drawn}, socket) do
    {:noreply, update(socket, :run, &Run.acked(&1, seq, drawn, System.monotonic_time(:millisecond)))}
  end

  # A tick: the run accounts the samples due and, with no render in flight, the columns
  # they fill; the window advances by those columns and the frame goes as the run
  # decides — strips, the empty update, a full render, or held back (spec/14 §12.6).
  def handle_info(:render_frame, %{assigns: %{run: %Run{running: false}}} = socket), do: {:noreply, socket}

  def handle_info(:render_frame, socket) do
    now = System.monotonic_time(:millisecond)
    socket = schedule_frame(socket)

    case Run.tick(socket.assigns.run, now, socket.assigns.samples_per_px) do
      {run, :skipped} ->
        {:noreply, assign(socket, run: run)}

      {run, {:draw, px}} ->
        scroll = Scroll.advance(socket.assigns.scroll, px)
        random_data = Scroll.shift(scroll, socket.assigns.random_data, px, fn _ -> random_sample() end)
        socket = assign(socket, run: run, scroll: scroll, random_data: random_data, viewport_x: socket.assigns.viewport_x + px)

        {run, mode} = Run.decide(socket.assigns.run, px, socket.assigns.use_incremental, {@inner_width, @inner_height}, now)
        socket = assign(socket, run: run)

        case mode do
          :drop -> {:noreply, socket}
          :none -> {:noreply, send_none(socket, now)}
          mode -> {:noreply, start_render(socket, mode, px)}
        end
    end
  end

  # The frame's render is back (#323): numbered, pushed and measured — or dropped, if the
  # run was stopped meanwhile or the render was cancelled.
  def handle_info({ref, %{payload: payload, bytes: bytes, points: points, mode: mode}}, socket) when is_reference(ref) do
    case Run.result(socket.assigns.run, ref) do
      :stale ->
        {:noreply, socket}

      {:ok, %Run{running: false} = run} ->
        {:noreply, assign(socket, run: run)}

      {:ok, run} ->
        now = System.monotonic_time(:millisecond)
        {run, seq} = Run.sending(run, mode)
        run = Run.rendered(run, bytes, now)

        {:noreply,
         socket
         |> assign(run: run, points_rendered: points)
         |> push_event("canvas_incremental", Map.put(payload, :seq, seq))}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, socket) do
    case Run.down(socket.assigns.run, ref, reason) do
      :stale -> {:noreply, socket}
      {:ok, run} -> {:noreply, assign(socket, run: run)}
    end
  end

  def terminate(_reason, socket), do: Run.cancel(socket.assigns.run)

  # A frame rendering in a task: the full chart, or the strips a scroll of `px` exposes,
  # over a snapshot of the page's data.
  defp start_render(socket, mode, px) do
    inputs = Map.take(socket.assigns, [:scroll, :random_data, :points_per_series, :x_scale, :y_scale, :total_points])

    render =
      case mode do
        :full_redraw -> fn -> full_frame(inputs) end
        :scroll_x -> fn -> incremental_frame(inputs, px) end
      end

    update(socket, :run, &Run.rendering(&1, render))
  end

  # The frame with no new column: the "none" update of spec/09 §7.3, nothing to draw and
  # nothing to copy, zero bytes — what an incremental frame without data costs. It needs
  # no render, so it is sent from the tick.
  defp send_none(socket, now) do
    {run, seq} = Run.sending(socket.assigns.run, :none)
    run = Run.rendered(run, 0, now)

    socket
    |> assign(run: run, points_rendered: 0)
    |> push_event("canvas_incremental", %{binary: "", dx: 0, dy: 0, mode: "none", seq: seq})
  end

  @doc false
  # The whole chart as a full-redraw record, for the task. Public for the stream test.
  def full_frame(inputs) do
    binary = inputs |> build_chart_element() |> CanvasIncremental.encode_full_redraw({@width, @height})
    %{payload: %{binary: Base.encode64(binary), dx: 0, dy: 0, mode: "full"}, bytes: byte_size(binary), points: inputs.total_points, mode: :full_redraw}
  end

  @doc false
  # The frame as the strips a scroll of `dx` pixels exposes, for the task: the plot is
  # what scrolls, the margin's axes stay (D-106). Public for the stream test.
  def incremental_frame(inputs, dx) do
    regions = CanvasIncremental.exposed_regions({dx, 0}, {@inner_width, @inner_height})

    adjusted = Enum.map(regions, fn {rx, ry, rw, rh} -> {@margin.left + rx, @margin.top + ry, rw, rh} end)
    region_elements = Enum.map(adjusted, fn bounds -> {bounds, build_region_element(inputs, bounds)} end)

    binary =
      CanvasIncremental.encode_incremental({dx, 0}, {@width, @height}, region_elements,
        viewport: {@margin.left, @margin.top, @inner_width, @inner_height}
      )

    %{
      payload: %{binary: Base.encode64(binary), dx: dx, dy: 0, mode: "scroll_x"},
      bytes: byte_size(binary),
      points: calculate_region_points(inputs, adjusted),
      mode: :scroll_x
    }
  end

  # The next tick at the run's deadline (#302).
  defp schedule_frame(socket) do
    {run, delay} = Run.schedule(socket.assigns.run, System.monotonic_time(:microsecond))
    Process.send_after(self(), :render_frame, delay)
    assign(socket, run: run)
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
  # The density at a data rate: the whole samples per pixel column that put about
  # `@span_seconds` of data across the plot, at least one (#308).
  def density_for(data_rate), do: Scroll.density(data_rate * @span_seconds, @inner_width)

  @doc false
  # The seconds of data the plot spans at the page's density and rate.
  def span(%{points_per_series: count, run: %{data_rate: rate}}) when rate > 0, do: count / rate
  def span(_assigns), do: 0.0

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

  # The next tick at its deadline (#302): > 2000 fps is unlimited, no delay.
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
    assigns = assign(assigns, avg_render_time: Run.avg_render_us(assigns.run), series: @series)

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
          <div class="controls-row">
            <form phx-change="set_fps" class="control-group">
              <label>Target FPS:</label>
              <input type="range" name="fps" min="10" max="2010" step="10" value={@run.target_fps} class="fps-slider" />
              <span class="fps-value"><%= if @run.target_fps > 2000, do: "∞", else: @run.target_fps %></span>
            </form>

            <form phx-change="set_data_rate" class="control-group">
              <label>Data rate:</label>
              <input type="range" name="data_rate" min="10" max="5000" step="10" value={@run.data_rate} class="fps-slider" />
              <span class="fps-value rate-value"><%= format_number(@run.data_rate) %> samples/s per series</span>
              <span class="point-breakdown">
                <%= @samples_per_px %>/px · 1 area + 4 lines × <%= format_number(@points_per_series) %> pts · <%= Float.round(span(assigns), 1) %> s across
              </span>
            </form>
          </div>

          <div class="controls-row">
            <button type="button" phx-click="toggle_incremental" class={"btn mode #{if @use_incremental, do: "active", else: ""}"}>
            <%= if @use_incremental, do: "Incremental ON", else: "Incremental OFF" %>
          </button>

          <button type="button" phx-click="toggle_flow_control" class={"btn mode #{if @run.flow_control, do: "active", else: ""}"}
                  title="Hold frames back while 250 ms of them are in flight; resync with a full frame after a dropped scroll">
            <%= cond do
              not @run.flow_control -> "Flow control OFF"
              @run.acking == :no -> "Flow control: no acks"
              true -> "Flow control ON (250 ms)"
            end %>
          </button>

          <%= if @run.running do %>
            <button type="button" phx-click="stop" class="btn stop">Stop</button>
          <% else %>
            <button type="button" phx-click="start" class="btn start">Start Animation</button>
          <% end %>
          </div>
        </div>

        <div class="metrics-bar">
          <div class="metric big">
            <span class="value"><%= trunc(@run.fps) %></span>
            <span class="label">FPS</span>
          </div>
          <div class="metric">
            <span class="value"><%= if @run.target_fps > 2000, do: "∞", else: @run.target_fps %></span>
            <span class="label">Target</span>
          </div>
          <div class="metric">
            <span class="value"><%= trunc(@run.client_fps) %></span>
            <span class="label">Client FPS</span>
          </div>
          <div class="metric">
            <span class="value"><%= Run.in_flight(@run) %></span>
            <span class="label">In flight</span>
          </div>
          <div class="metric">
            <span class="value"><%= if @run.target_fps > 2000, do: "—", else: "#{round(@run.lag)} ms" %></span>
            <span class="label">Lag</span>
          </div>
          <div class="metric">
            <span class="value"><%= format_number(@run.dropped) %></span>
            <span class="label">Dropped</span>
          </div>
          <div class="metric">
            <span class="value"><%= if @run.ack_age, do: "#{format_number(@run.ack_age)} ms", else: "none" %></span>
            <span class="label">Last ack</span>
          </div>
          <div class="metric">
            <span class="value"><%= format_number(@run.stalls) %></span>
            <span class="label">Stalls</span>
          </div>
          <div class="metric" title="ticks that found a frame still rendering (#323)">
            <span class="value"><%= format_number(@run.skipped) %></span>
            <span class="label">Skipped</span>
          </div>
        </div>

        <div class="metrics-bar">
          <div class="metric">
            <span class="value"><%= format_number(round(@run.measured_rate)) %></span>
            <span class="label">Samples/s</span>
          </div>
          <div class="metric">
            <span class="value"><%= format_number(round(@run.measured_rate * @series)) %></span>
            <span class="label">Pts/s</span>
          </div>
          <div class="metric">
            <span class="value"><%= format_number(@total_points) %> <small>(<%= @samples_per_px %>/px · <%= Float.round(span(assigns), 1) %> s)</small></span>
            <span class="label">Total points</span>
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
            <span class="value"><%= Float.round(@run.payload_size / 1024, 1) %> KB</span>
            <span class="label">Payload</span>
          </div>
          <div class="metric">
            <span class="value"><%= if @use_incremental, do: "Inc", else: "Full" %></span>
            <span class="label">Mode</span>
          </div>
          <div class="metric">
            <span class="value"><%= @run.frame %></span>
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
              data-ack="frame_drawn"
              data-ack-interval="50"
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
        flex-direction: column;
        gap: 0.75rem;
        margin-bottom: 1rem;
        padding: 1rem;
        background: #f8f9fa;
        border-radius: 8px;
        flex-wrap: wrap;
      }

      /* The sliders on one row, the buttons on the next; a slider control is a grid of
         label, slider and a fixed-width value, with the rate's derivation beneath. */
      .controls-row {
        display: flex;
        align-items: center;
        gap: 1.5rem;
        flex-wrap: nowrap;
      }

      .control-group {
        display: grid;
        grid-template-columns: auto auto auto;
        align-items: center;
        column-gap: 0.5rem;
        row-gap: 0.15rem;
      }

      .control-group label {
        font-size: 13px;
        color: #666;
        font-weight: 500;
      }

      .point-breakdown {
        grid-column: 1 / -1;
        font-size: 12px;
        color: #888;
        font-variant-numeric: tabular-nums;
        white-space: nowrap;
      }

      .fps-slider {
        width: 120px;
        cursor: pointer;
      }

      .fps-value {
        font-size: 14px;
        font-weight: 600;
        color: #333;
        min-width: 2.5rem;
        text-align: left;
        font-variant-numeric: tabular-nums;
        white-space: nowrap;
      }

      .rate-value {
        min-width: 13.5rem;
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
        display: grid;
        grid-template-columns: repeat(9, 1fr);
        gap: 0.75rem;
        margin-bottom: 0.75rem;
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

      .metric .value small {
        font-size: 0.7rem;
        font-weight: 400;
        opacity: 0.85;
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
