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
  @default_target_fps 60
  @default_data_rate 600  # samples per second per series
  @span_seconds 5  # the plot spans about this much data at the rate; the density follows (#308)
  @lag_alpha 2 / 31  # the lag's moving average, about thirty ticks
  @max_lag_ms 250  # the lag budget: flow control holds a frame while this much is in flight (#310)
  @ack_timeout 2000  # ms a hold may last without an ack before it fails open (#306)

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
      data_rate: @default_data_rate,
      # Samples arrive by the clock (spec/14 §12.6): `pending` whole samples not yet a
      # column, `carry` the fraction of one, `last_tick` when they were last counted, and
      # `arrivals` the last second's `{at, samples}` for the measured rate.
      pending: 0,
      carry: 0.0,
      last_tick: nil,
      # The next tick's deadline in microseconds (#302): ticks follow it, not a whole-ms timer
      next_due: nil,
      arrivals: [],
      measured_rate: 0.0,
      # Frames in flight (#304, D-107): every frame carries `sent_seq`, the hook acks the
      # last it drew (`acked_seq`, `acks` as `{at, drawn}` for the client's rate); with
      # `flow_control` the page holds a frame back while `@window` are in flight, counts
      # it `dropped`, and resyncs with a full frame after a dropped scroll (`needs_full`).
      sent_seq: 0,
      acked_seq: 0,
      acks: [],
      client_fps: 0.0,
      flow_control: true,
      dropped: 0,
      needs_full: false,
      # A hold fails open (#306): `hold_since` when the current hold began, `last_ack_at`
      # the last ack's time (nil until one arrives), `acking` `:unknown` → `:yes` on the
      # first ack or `:no` when a hold outlives `@ack_timeout` with none, `stalls` the
      # holds released because an acking client stopped, `ack_age` for the metrics.
      hold_since: nil,
      last_ack_at: nil,
      acking: :unknown,
      stalls: 0,
      ack_age: nil,
      lag: 0.0,
      y_scale: y_scale,
      frame_times: [],
      render_times: [],
      payload_size: 0,
      viewport_x: 0,
      use_incremental: true,
      last_full_render: true,
      points_rendered: 0
    )
    |> at_density(density_for(@default_data_rate))}
  end

  def handle_event("start", _params, socket) do
    socket =
      assign(socket,
        running: true,
        last_tick: System.monotonic_time(:millisecond),
        pending: 0,
        carry: 0.0,
        arrivals: [],
        sent_seq: 0,
        acked_seq: 0,
        acks: [],
        dropped: 0,
        needs_full: false,
        hold_since: nil,
        last_ack_at: nil,
        acking: :unknown,
        stalls: 0,
        ack_age: nil,
        frame: 0,
        frame_times: [],
        render_times: []
      )

    # The run opens with a full render; the ticks build on it.
    socket = socket |> send_full_render() |> assign(last_full_render: false)
    {:noreply, socket |> assign(next_due: System.monotonic_time(:microsecond)) |> schedule_frame()}
  end

  def handle_event("stop", _params, socket) do
    {:noreply, assign(socket, running: false)}
  end

  def handle_event("toggle_incremental", _params, socket) do
    {:noreply, assign(socket, use_incremental: not socket.assigns.use_incremental)}
  end

  def handle_event("set_fps", %{"fps" => fps_str}, socket) do
    # Slider value 130 = unlimited (no delay)
    target_fps = String.to_integer(fps_str)
    {:noreply, assign(socket, target_fps: target_fps)}
  end

  # The rate sizes the window: a new density is a fresh window and a full next frame.
  def handle_event("set_data_rate", %{"data_rate" => rate}, socket) do
    rate = String.to_integer(rate)
    density = density_for(rate)
    socket = assign(socket, data_rate: rate)

    if density == socket.assigns.samples_per_px,
      do: {:noreply, socket},
      else: {:noreply, socket |> at_density(density) |> assign(last_full_render: true)}
  end

  def handle_event("toggle_flow_control", _params, socket) do
    {:noreply, assign(socket, flow_control: not socket.assigns.flow_control)}
  end

  # The hook's ack (spec/10 §9.2): the last frame it drew and how many since its last ack.
  def handle_event("frame_drawn", %{"seq" => seq, "drawn" => drawn}, socket) do
    now = System.monotonic_time(:millisecond)
    acks = Enum.take([{now, drawn} | socket.assigns.acks], 120)

    {:noreply,
     assign(socket,
       acked_seq: max(socket.assigns.acked_seq, seq),
       acks: acks,
       client_fps: rate_over(acks, now),
       last_ack_at: now,
       acking: :yes
     )}
  end

  def handle_info(:render_frame, socket) do
    if socket.assigns.running do
      now = System.monotonic_time(:millisecond)
      socket = schedule_frame(socket)

      # The samples due since the last tick, and the whole columns they fill: the frame
      # scrolls by those columns and keeps the rest pending (spec/14 §12.6, #300).
      {px, arrived, arrival} = arrivals(socket.assigns, now - socket.assigns.last_tick)
      arrivals = Enum.take([{now, arrived} | socket.assigns.arrivals], 120)

      socket =
        assign(socket, arrival)
        |> assign(last_tick: now, arrivals: arrivals, measured_rate: measured_rate(arrivals, now))

      # Every tick sends a frame, columns or none (#302).
      {:noreply, draw(socket, px, now)}
    else
      {:noreply, socket}
    end
  end

  # A frame: the window advances by `px` columns, the random line drops and appends
  # their samples (`Examples.Scroll`), and the frame goes as strips when the scroll is
  # one `scroll_mode/2` calls a scroll, as the empty "none" update when no column filled
  # (D-38), and in full otherwise — or always, with Incremental OFF.
  defp draw(socket, px, now) do
    render_start = System.monotonic_time(:microsecond)

    scroll = Scroll.advance(socket.assigns.scroll, px)
    random_data = Scroll.shift(scroll, socket.assigns.random_data, px, fn _ -> random_sample() end)
    viewport_x = socket.assigns.viewport_x + px
    socket = assign(socket, random_data: random_data, scroll: scroll, viewport_x: viewport_x)

    socket = socket |> hold(now) |> assign(ack_age: ack_age(socket.assigns, now))

    socket =
      case frame_mode(socket.assigns, px) do
        :scroll_x -> send_incremental_render(socket, px)
        :none -> send_none(socket)
        :full_redraw -> socket |> send_full_render() |> assign(last_full_render: false, needs_full: false)
        :drop -> drop(socket, px)
      end

    render_time = System.monotonic_time(:microsecond) - render_start

    # Track metrics
    frame_times = Enum.take([now | socket.assigns.frame_times], 60)
    render_times = Enum.take([render_time | socket.assigns.render_times], 60)

    assign(socket,
      frame: socket.assigns.frame + 1,
      frame_times: frame_times,
      render_times: render_times,
      fps: calculate_fps(frame_times),
      lag: lag(socket.assigns)
    )
  end

  @doc false
  # What this tick sends for a scroll of `px` columns: `:drop` when flow control holds it
  # back (the window is in flight); a full render with Incremental OFF, on the first frame
  # of a run, or after a dropped scroll (D-107); otherwise what `scroll_mode/2` says —
  # strips, or the empty "none" update. Public for the page test.
  def frame_mode(assigns, px) do
    cond do
      holding?(assigns) -> :drop
      not assigns.use_incremental or assigns.last_full_render or assigns.needs_full -> :full_redraw
      true -> CanvasIncremental.scroll_mode({px, 0}, {@inner_width, @inner_height})
    end
  end

  @doc false
  def in_flight(%{sent_seq: sent, acked_seq: acked}), do: sent - acked

  defp holding?(assigns) do
    assigns.flow_control and assigns.acking != :no and in_flight(assigns) >= window(assigns)
  end

  @doc false
  # The frames the lag budget allows in flight at the target rate — fifteen at 60 fps —
  # taken at 2,000 fps when the target is unlimited. Public for the page test.
  def window(%{target_fps: fps}), do: max(2, ceil(@max_lag_ms * min(fps, 2000) / 1000))

  @doc false
  # A hold fails open (#306, D-107): a hold that outlives `@ack_timeout` without an ack
  # ends — when no ack has ever arrived the client does not acknowledge and the run stops
  # holding (`acking: :no`); when acks had arrived the client is stalled, the window is
  # released and the stall counted. Public for the page test.
  def hold(socket, now) do
    a = socket.assigns

    cond do
      not holding?(a) -> assign(socket, hold_since: nil)
      a.hold_since == nil -> assign(socket, hold_since: now)
      now - a.hold_since <= @ack_timeout -> socket
      a.last_ack_at == nil -> assign(socket, acking: :no, hold_since: nil)
      true -> assign(socket, acked_seq: a.sent_seq, stalls: a.stalls + 1, hold_since: nil)
    end
  end

  # The lag's moving average of `in flight × period` ms: the instantaneous figure swings
  # between acks, which come in bursts every ack interval (#308).
  defp lag(%{target_fps: fps} = assigns) when fps > 2000, do: assigns.lag
  defp lag(%{target_fps: fps, lag: lag} = assigns) do
    lag + @lag_alpha * (in_flight(assigns) * 1000 / fps - lag)
  end

  defp ack_age(%{last_ack_at: nil}, _now), do: nil
  defp ack_age(%{last_ack_at: at}, now), do: now - at

  # A frame held back: the data has advanced, nothing is sent, and if the picture moved
  # the next frame sent must be a full one — a strip against a canvas that missed a
  # scroll is the wrong picture.
  defp drop(socket, px) do
    assign(socket,
      dropped: socket.assigns.dropped + 1,
      needs_full: socket.assigns.needs_full or px > 0,
      payload_size: 0,
      points_rendered: 0
    )
  end

  # Every frame carries its sequence number, which the hook acks (data-ack).
  defp push_frame(socket, payload) do
    seq = socket.assigns.sent_seq + 1

    socket
    |> assign(sent_seq: seq)
    |> push_event("canvas_incremental", Map.put(payload, :seq, seq))
  end

  @doc false
  # The samples due after `elapsed` ms at the page's data rate, on top of what was pending:
  # `{columns, arrived, %{pending, carry}}` — the whole columns the pending samples fill,
  # the samples that arrived this tick, and what stays pending (a column's worth at most)
  # with the fraction of a sample carried. Public for the stream test.
  def arrivals(%{data_rate: rate, carry: carry, pending: pending, scroll: scroll}, elapsed) do
    due = carry + rate * elapsed / 1000
    arrived = trunc(due)
    pending = pending + arrived
    columns = div(pending, scroll.samples_per_px)
    {columns, arrived, %{pending: rem(pending, scroll.samples_per_px), carry: due - arrived}}
  end

  # Samples per second per series over the last second of ticks.
  defp measured_rate(arrivals, now), do: rate_over(arrivals, now)

  # Events per second over the last second of `{at, count}` entries, newest first.
  defp rate_over(entries, now) do
    recent = Enum.take_while(entries, fn {at, _} -> now - at <= 1000 end)

    case recent do
      [] -> 0.0
      [_] -> 0.0
      _ ->
        {oldest, _} = List.last(recent)
        span = now - oldest
        if span > 0, do: Enum.sum(for {_, n} <- recent, do: n) * 1000 / span, else: 0.0
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
  # The density at a data rate: the whole samples per pixel column that put about
  # `@span_seconds` of data across the plot, at least one (#308).
  def density_for(data_rate), do: Scroll.density(data_rate * @span_seconds, @inner_width)

  @doc false
  # The seconds of data the plot spans at the page's density and rate.
  def span(%{points_per_series: count, data_rate: rate}) when rate > 0, do: count / rate
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

  defp send_full_render(socket) do
    element = build_chart_element(socket.assigns)
    binary = CanvasIncremental.encode_full_redraw(element, {@width, @height})
    encoded = Base.encode64(binary)

    socket
    |> assign(:payload_size, byte_size(binary))
    |> assign(:points_rendered, socket.assigns.total_points)
    |> push_frame(%{binary: encoded, dx: 0, dy: 0, mode: "full"})
  end

  # The frame with no new column: the "none" update of spec/09 §7.3, nothing to draw and
  # nothing to copy, zero bytes — what an incremental frame without data costs.
  defp send_none(socket) do
    socket
    |> assign(payload_size: 0, points_rendered: 0)
    |> push_frame(%{binary: "", dx: 0, dy: 0, mode: "none"})
  end

  # The frame as the strips a scroll of `dx` pixels exposes.
  defp send_incremental_render(socket, dx) do
    # Use inner chart dimensions for exposed region calculation
    # This ensures the region falls within the data area, not the margins
    inner_size = {@inner_width, @inner_height}

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
    |> push_frame(%{binary: encoded, dx: dx, dy: 0, mode: "scroll_x"})
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

  # The next tick at its deadline (#302): > 2000 fps is unlimited, no delay.
  defp schedule_frame(%{assigns: %{target_fps: fps, next_due: due}} = socket) do
    now = System.monotonic_time(:microsecond)
    {next, delay} = if fps > 2000, do: {now, 0}, else: deadline(due, now, fps)
    Process.send_after(self(), :render_frame, delay)
    assign(socket, next_due: next)
  end

  @doc false
  # The next deadline after `due` at `fps`, never before `now` — a late tick is not caught
  # up in a burst — and the whole milliseconds to wait for it, rounded to the nearest, so
  # a target between whole-millisecond rates averages to it. Public for the stream test.
  def deadline(due, now, fps) do
    next = max(due + 1_000_000 / fps, now)
    {next, round((next - now) / 1000)}
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

    assigns = assign(assigns, avg_render_time: avg_render_time, series: @series)

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
              <input type="range" name="fps" min="10" max="2010" step="10" value={@target_fps} class="fps-slider" />
              <span class="fps-value"><%= if @target_fps > 2000, do: "∞", else: @target_fps %></span>
            </form>

            <form phx-change="set_data_rate" class="control-group">
              <label>Data rate:</label>
              <input type="range" name="data_rate" min="10" max="5000" step="10" value={@data_rate} class="fps-slider" />
              <span class="fps-value rate-value"><%= format_number(@data_rate) %> samples/s per series</span>
              <span class="point-breakdown">
                <%= @samples_per_px %>/px · 1 area + 4 lines × <%= format_number(@points_per_series) %> pts · <%= Float.round(span(assigns), 1) %> s across
              </span>
            </form>
          </div>

          <div class="controls-row">
            <button type="button" phx-click="toggle_incremental" class={"btn mode #{if @use_incremental, do: "active", else: ""}"}>
            <%= if @use_incremental, do: "Incremental ON", else: "Incremental OFF" %>
          </button>

          <button type="button" phx-click="toggle_flow_control" class={"btn mode #{if @flow_control, do: "active", else: ""}"}
                  title="Hold frames back while 250 ms of them are in flight; resync with a full frame after a dropped scroll">
            <%= cond do
              not @flow_control -> "Flow control OFF"
              @acking == :no -> "Flow control: no acks"
              true -> "Flow control ON (250 ms)"
            end %>
          </button>

          <%= if @running do %>
            <button type="button" phx-click="stop" class="btn stop">Stop</button>
          <% else %>
            <button type="button" phx-click="start" class="btn start">Start Animation</button>
          <% end %>
          </div>
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
            <span class="value"><%= trunc(@client_fps) %></span>
            <span class="label">Client FPS</span>
          </div>
          <div class="metric">
            <span class="value"><%= @sent_seq - @acked_seq %></span>
            <span class="label">In flight</span>
          </div>
          <div class="metric">
            <span class="value"><%= if @target_fps > 2000, do: "—", else: "#{round(@lag)} ms" %></span>
            <span class="label">Lag</span>
          </div>
          <div class="metric">
            <span class="value"><%= format_number(@dropped) %></span>
            <span class="label">Dropped</span>
          </div>
          <div class="metric">
            <span class="value"><%= if @ack_age, do: "#{format_number(@ack_age)} ms", else: "none" %></span>
            <span class="label">Last ack</span>
          </div>
          <div class="metric">
            <span class="value"><%= format_number(@stalls) %></span>
            <span class="label">Stalls</span>
          </div>
        </div>

        <div class="metrics-bar">
          <div class="metric">
            <span class="value"><%= format_number(round(@measured_rate)) %></span>
            <span class="label">Samples/s</span>
          </div>
          <div class="metric">
            <span class="value"><%= format_number(round(@measured_rate * @series)) %></span>
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
        grid-template-columns: repeat(8, 1fr);
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
