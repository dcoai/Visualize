defmodule Visualize.Benchmark do
  @moduledoc """
  Performance benchmarking utilities for comparing rendering backends.

  Measures throughput and payload sizes across SVG, Canvas, Hybrid, and
  Canvas-Incremental backends.

  ## Example

      # Run a quick benchmark
      results = Visualize.Benchmark.run(data_points: 1000, iterations: 100)

      # Results include svg, canvas, hybrid, and incremental measurements
      IO.puts(Visualize.Benchmark.format_report(results))

  ## Hybrid Mode

  Hybrid mode simulates the pattern where static elements (axes, labels) are
  rendered once as SVG, and only the dynamic data is sent each frame as Canvas
  commands. This measures the "per-frame" cost for real-time updates.

  ## Hybrid-Incremental Mode

  Hybrid-Incremental combines the Hybrid approach (static SVG axes) with
  incremental scroll optimization for the data layer. Only newly exposed
  data regions are sent each frame.

  ## Canvas-Incremental Mode

  Canvas-Incremental renders the full chart to Canvas with incremental scroll
  optimization. Copies existing canvas content shifted and only renders newly
  exposed regions. Best for time-series visualizations with continuous scrolling.

  """

  alias Visualize.{Axis, Render, Scale, Shape}
  alias Visualize.Backend.{Canvas, CanvasIncremental, SVG}
  alias Visualize.IR.{Element, Transform}

  @margin %{top: 20, right: 20, bottom: 30, left: 40}
  @warmup_iterations 10
  @scroll_delta 20

  @doc """
  Runs a benchmark comparing SVG, Canvas, Hybrid, Hybrid-Incremental, and Canvas-Incremental backends.

  ## Options

    * `:data_points` - Number of data points per render (default: 500)
    * `:iterations` - Number of render iterations (default: 100)
    * `:chart_type` - Type of chart to benchmark: `:line`, `:area`, `:scatter` (default: `:line`)
    * `:width` - Chart width (default: 800)
    * `:height` - Chart height (default: 600)

  """
  @spec run(keyword()) :: map()
  def run(opts \\ []) do
    data_points = Keyword.get(opts, :data_points, 500)
    iterations = Keyword.get(opts, :iterations, 100)
    chart_type = Keyword.get(opts, :chart_type, :line)
    width = Keyword.get(opts, :width, 800)
    height = Keyword.get(opts, :height, 600)

    data = generate_data(chart_type, data_points)
    {x_scale, y_scale} = build_scales(chart_type, data, width, height)
    canvas_size = {width, height}

    # Run benchmarks
    svg_results = benchmark_backend(:svg, chart_type, data, width, height, iterations)
    canvas_results = benchmark_backend(:canvas, chart_type, data, width, height, iterations)

    hybrid_results =
      benchmark_hybrid(chart_type, data, x_scale, y_scale, width, height, iterations)

    hybrid_inc_results =
      benchmark_incremental(:hybrid, chart_type, data, x_scale, y_scale, canvas_size, iterations)

    canvas_inc_results =
      benchmark_incremental(:canvas, chart_type, data, x_scale, y_scale, canvas_size, iterations)

    build_run_results(
      %{
        data_points: data_points,
        iterations: iterations,
        chart_type: chart_type,
        dimensions: {width, height}
      },
      svg_results,
      canvas_results,
      hybrid_results,
      hybrid_inc_results,
      canvas_inc_results
    )
  end

  @doc """
  Runs a streaming benchmark simulating real-time data updates.

  Returns statistics about how many frames per second each backend can achieve.

  ## Options

    * `:duration_ms` - How long to run the benchmark (default: 5000)
    * `:data_points` - Points per frame (default: 200)
    * `:chart_type` - Chart type (default: `:line`)

  """
  @spec stream_benchmark(keyword()) :: map()
  def stream_benchmark(opts \\ []) do
    duration_ms = Keyword.get(opts, :duration_ms, 5000)
    data_points = Keyword.get(opts, :data_points, 200)
    chart_type = Keyword.get(opts, :chart_type, :line)
    width = Keyword.get(opts, :width, 800)
    height = Keyword.get(opts, :height, 600)

    sample_data = generate_data(chart_type, data_points)
    {x_scale, y_scale} = build_scales(chart_type, sample_data, width, height)
    static_svg = render_static_svg(x_scale, y_scale, width, height)
    canvas_size = {width, height}

    svg_results = stream_benchmark_full(:svg, duration_ms, data_points, chart_type, width, height)

    canvas_results =
      stream_benchmark_full(:canvas, duration_ms, data_points, chart_type, width, height)

    hybrid_results =
      stream_benchmark_data_only(
        :hybrid,
        x_scale,
        y_scale,
        static_svg,
        chart_type,
        data_points,
        duration_ms,
        nil
      )

    hybrid_inc_results =
      stream_benchmark_data_only(
        :hybrid_incremental,
        x_scale,
        y_scale,
        static_svg,
        chart_type,
        data_points,
        duration_ms,
        canvas_size
      )

    canvas_inc_results =
      stream_benchmark_data_only(
        :canvas_incremental,
        x_scale,
        y_scale,
        nil,
        chart_type,
        data_points,
        duration_ms,
        canvas_size
      )

    build_stream_results(
      %{duration_ms: duration_ms, data_points: data_points, chart_type: chart_type},
      svg_results,
      canvas_results,
      hybrid_results,
      hybrid_inc_results,
      canvas_inc_results
    )
  end

  @doc """
  Formats benchmark results as a human-readable report.
  """
  @spec format_report(map()) :: String.t()
  def format_report(results) do
    static_overhead = results.hybrid.static_svg_bytes
    per_frame_diff = results.hybrid.avg_payload_bytes - results.svg.avg_payload_bytes

    break_even_text =
      if per_frame_diff > 0 do
        "N/A (Canvas binary is larger than SVG)"
      else
        "#{ceil(static_overhead / abs(per_frame_diff))} frames"
      end

    svg_100_frames = results.svg.avg_payload_bytes * 100
    hybrid_100_frames = results.hybrid.static_svg_bytes + results.hybrid.avg_payload_bytes * 100
    bandwidth_at_100 = Float.round((1 - hybrid_100_frames / svg_100_frames) * 100, 1)

    """
    ═══════════════════════════════════════════════════════════════
    BACKEND PERFORMANCE BENCHMARK REPORT
    ═══════════════════════════════════════════════════════════════

    Configuration:
      Chart Type:    #{results.config.chart_type}
      Data Points:   #{results.config.data_points}
      Iterations:    #{results.config[:iterations] || "N/A"}
      Dimensions:    #{inspect(results.config[:dimensions] || "N/A")}

    ───────────────────────────────────────────────────────────────
    SVG Backend (full chart each frame):
      Average Render Time:   #{format_time(results.svg.avg_render_time_us)}
      Renders Per Second:    #{Float.round(results.svg.renders_per_second, 1)}
      Average Payload Size:  #{format_bytes(results.svg.avg_payload_bytes)}

    ───────────────────────────────────────────────────────────────
    Canvas Backend (full chart each frame):
      Average Render Time:   #{format_time(results.canvas.avg_render_time_us)}
      Renders Per Second:    #{Float.round(results.canvas.renders_per_second, 1)}
      Average Payload Size:  #{format_bytes(results.canvas.avg_payload_bytes)}

    ───────────────────────────────────────────────────────────────
    Hybrid Backend (static SVG + Canvas data):
      Average Render Time:   #{format_time(results.hybrid.avg_render_time_us)}
      Renders Per Second:    #{Float.round(results.hybrid.renders_per_second, 1)}
      Per-Frame Data Payload: #{format_bytes(results.hybrid.avg_payload_bytes)}
      Static SVG (once):     #{format_bytes(results.hybrid.static_svg_bytes)}

    ───────────────────────────────────────────────────────────────
    Hybrid-Incremental Backend (static SVG + incremental Canvas):
      Average Render Time:   #{format_time(results.hybrid_incremental.avg_render_time_us)}
      Renders Per Second:    #{Float.round(results.hybrid_incremental.renders_per_second, 1)}
      Per-Frame Data Payload: #{format_bytes(results.hybrid_incremental.avg_payload_bytes)}
      Scroll Delta:          #{results.hybrid_incremental.scroll_delta}px

    ───────────────────────────────────────────────────────────────
    Canvas-Incremental Backend (full canvas + scroll optimization):
      Average Render Time:   #{format_time(results.canvas_incremental.avg_render_time_us)}
      Renders Per Second:    #{Float.round(results.canvas_incremental.renders_per_second, 1)}
      Per-Frame Data Payload: #{format_bytes(results.canvas_incremental.avg_payload_bytes)}
      Scroll Delta:          #{results.canvas_incremental.scroll_delta}px

    ───────────────────────────────────────────────────────────────
    COMPARISON SUMMARY:

      Server-side (render speed):
        Fastest:             #{results.comparison.fastest}
        SVG vs Canvas:       #{results.comparison.svg_vs_canvas_speed}x
        SVG vs Hybrid:       #{results.comparison.svg_vs_hybrid_speed}x
        SVG vs Hybrid-Inc:   #{results.comparison.svg_vs_hybrid_inc_speed}x
        SVG vs Canvas-Inc:   #{results.comparison.svg_vs_canvas_inc_speed}x

      Per-frame payload:
        Smallest:            #{results.comparison.smallest_per_frame}
        SVG:                 #{format_bytes(results.svg.avg_payload_bytes)}
        Hybrid data-only:    #{format_bytes(results.hybrid.avg_payload_bytes)}
        Hybrid-Incremental:  #{format_bytes(results.hybrid_incremental.avg_payload_bytes)}
        Canvas-Incremental:  #{format_bytes(results.canvas_incremental.avg_payload_bytes)}

      Bandwidth over 100 frames:
        SVG total:           #{format_bytes(svg_100_frames)}
        Hybrid total:        #{format_bytes(round(hybrid_100_frames))}
        Difference:          #{bandwidth_at_100}%

      Hybrid break-even:     #{break_even_text}

    ───────────────────────────────────────────────────────────────
    NOTE: Incremental modes optimize for scrolling/panning:
      - Hybrid-Incremental: Static SVG axes + incremental Canvas data
      - Canvas-Incremental: Full canvas with scroll+copy optimization
      - Both copy existing content shifted, render only new regions

    ═══════════════════════════════════════════════════════════════
    """
  end

  @doc """
  Formats streaming benchmark results.
  """
  @spec format_stream_report(map()) :: String.t()
  def format_stream_report(results) do
    hybrid_total_with_static = results.hybrid.total_bytes + results.hybrid.static_svg_bytes

    actual_bandwidth_diff =
      Float.round((1 - hybrid_total_with_static / max(results.svg.total_bytes, 1)) * 100, 1)

    bytes_per_frame = fn r -> if r.frames > 0, do: round(r.total_bytes / r.frames), else: 0 end

    """
    ═══════════════════════════════════════════════════════════════
    STREAMING PERFORMANCE BENCHMARK REPORT
    ═══════════════════════════════════════════════════════════════

    Configuration:
      Chart Type:    #{results.config.chart_type}
      Data Points:   #{results.config.data_points} per frame
      Duration:      #{results.config.duration_ms} ms

    ───────────────────────────────────────────────────────────────
    SVG Backend (full chart each frame):
      Frames Rendered:       #{results.svg.frames}
      Frames Per Second:     #{Float.round(results.svg.fps, 1)} FPS
      Data Points/Second:    #{format_number(results.svg.data_points_per_second)}
      Total Bytes Sent:      #{format_bytes(results.svg.total_bytes)}
      Avg Bytes/Frame:       #{format_bytes(bytes_per_frame.(results.svg))}

    ───────────────────────────────────────────────────────────────
    Canvas Backend (full chart each frame):
      Frames Rendered:       #{results.canvas.frames}
      Frames Per Second:     #{Float.round(results.canvas.fps, 1)} FPS
      Data Points/Second:    #{format_number(results.canvas.data_points_per_second)}
      Total Bytes Sent:      #{format_bytes(results.canvas.total_bytes)}
      Avg Bytes/Frame:       #{format_bytes(bytes_per_frame.(results.canvas))}

    ───────────────────────────────────────────────────────────────
    Hybrid Backend (static SVG + Canvas data):
      Frames Rendered:       #{results.hybrid.frames}
      Frames Per Second:     #{Float.round(results.hybrid.fps, 1)} FPS
      Data Points/Second:    #{format_number(results.hybrid.data_points_per_second)}
      Data Bytes Sent:       #{format_bytes(results.hybrid.total_bytes)}
      Static SVG (once):     #{format_bytes(results.hybrid.static_svg_bytes)}
      Avg Bytes/Frame:       #{format_bytes(bytes_per_frame.(results.hybrid))}

    ───────────────────────────────────────────────────────────────
    Hybrid-Incremental Backend (static SVG + incremental Canvas):
      Frames Rendered:       #{results.hybrid_incremental.frames}
      Frames Per Second:     #{Float.round(results.hybrid_incremental.fps, 1)} FPS
      Data Points/Second:    #{format_number(results.hybrid_incremental.data_points_per_second)}
      Data Bytes Sent:       #{format_bytes(results.hybrid_incremental.total_bytes)}
      Static SVG (once):     #{format_bytes(results.hybrid_incremental.static_svg_bytes)}
      Avg Bytes/Frame:       #{format_bytes(bytes_per_frame.(results.hybrid_incremental))}

    ───────────────────────────────────────────────────────────────
    Canvas-Incremental Backend (full canvas + scroll optimization):
      Frames Rendered:       #{results.canvas_incremental.frames}
      Frames Per Second:     #{Float.round(results.canvas_incremental.fps, 1)} FPS
      Data Points/Second:    #{format_number(results.canvas_incremental.data_points_per_second)}
      Data Bytes Sent:       #{format_bytes(results.canvas_incremental.total_bytes)}
      Avg Bytes/Frame:       #{format_bytes(bytes_per_frame.(results.canvas_incremental))}

    ───────────────────────────────────────────────────────────────
    COMPARISON SUMMARY:

      FPS Rankings:          #{rank_fps(results)}

      Server-side throughput (FPS):
        SVG:                 #{Float.round(results.svg.fps, 1)}
        Canvas:              #{Float.round(results.canvas.fps, 1)}
        Hybrid:              #{Float.round(results.hybrid.fps, 1)}
        Hybrid-Inc:          #{Float.round(results.hybrid_incremental.fps, 1)}
        Canvas-Inc:          #{Float.round(results.canvas_incremental.fps, 1)}

      Total bandwidth:
        SVG:                 #{format_bytes(results.svg.total_bytes)}
        Hybrid (with static): #{format_bytes(round(hybrid_total_with_static))}
        Hybrid-Inc:          #{format_bytes(results.hybrid_incremental.total_bytes)}
        Canvas-Inc:          #{format_bytes(results.canvas_incremental.total_bytes)}
        Difference:          #{actual_bandwidth_diff}%

    ───────────────────────────────────────────────────────────────
    NOTE: Incremental modes optimize for scrolling/panning:
      - Hybrid-Incremental: Static SVG axes + incremental Canvas data
      - Canvas-Incremental: Full canvas with scroll+copy optimization
      - Both copy existing content shifted, render only new regions

    ═══════════════════════════════════════════════════════════════
    """
  end

  # ============================================================================
  # Benchmark Execution
  # ============================================================================

  defp benchmark_backend(backend, chart_type, data, width, height, iterations) do
    render_fn = fn -> render_full_chart(backend, chart_type, data, width, height) end

    warmup(render_fn)
    {total_time_us, payloads} = timed_iterations(render_fn, iterations)

    calculate_results(payloads, total_time_us, iterations)
  end

  defp benchmark_hybrid(chart_type, data, x_scale, y_scale, width, height, iterations) do
    static_svg = render_static_svg(x_scale, y_scale, width, height)
    render_fn = fn -> render_data_only(chart_type, data, x_scale, y_scale) end

    warmup(render_fn)
    {total_time_us, payloads} = timed_iterations(render_fn, iterations)

    calculate_results(payloads, total_time_us, iterations)
    |> Map.put(:static_svg_bytes, byte_size(static_svg))
  end

  defp benchmark_incremental(mode, chart_type, data, x_scale, y_scale, canvas_size, iterations) do
    render_fn = fn ->
      render_incremental(mode, chart_type, data, x_scale, y_scale, canvas_size)
    end

    warmup(render_fn)
    {total_time_us, payloads} = timed_iterations(render_fn, iterations)

    calculate_results(payloads, total_time_us, iterations)
    |> Map.put(:scroll_delta, @scroll_delta)
  end

  defp warmup(render_fn) do
    for _ <- 1..@warmup_iterations, do: render_fn.()
  end

  defp timed_iterations(render_fn, iterations) do
    :timer.tc(fn ->
      for _ <- 1..iterations, do: render_fn.()
    end)
  end

  defp calculate_results(payloads, total_time_us, iterations) do
    payload_sizes = Enum.map(payloads, &byte_size/1)
    avg_payload = Enum.sum(payload_sizes) / length(payload_sizes)
    avg_time_us = total_time_us / iterations

    %{
      avg_render_time_us: Float.round(avg_time_us, 2),
      renders_per_second: Float.round(1_000_000 / avg_time_us, 1),
      avg_payload_bytes: round(avg_payload),
      total_time_ms: total_time_us / 1000
    }
  end

  # ============================================================================
  # Stream Benchmark Execution
  # ============================================================================

  defp stream_benchmark_full(backend, duration_ms, data_points, chart_type, width, height) do
    end_time = System.monotonic_time(:millisecond) + duration_ms

    {frames, total_bytes, actual_ms} =
      stream_loop_full(backend, chart_type, data_points, width, height, end_time, 0, 0)

    build_stream_result(frames, total_bytes, actual_ms, data_points)
  end

  defp stream_benchmark_data_only(
         mode,
         x_scale,
         y_scale,
         static_svg,
         chart_type,
         data_points,
         duration_ms,
         canvas_size
       ) do
    end_time = System.monotonic_time(:millisecond) + duration_ms

    {frames, total_bytes, actual_ms} =
      stream_loop_data_only(
        mode,
        x_scale,
        y_scale,
        chart_type,
        data_points,
        canvas_size,
        end_time,
        0,
        0
      )

    result = build_stream_result(frames, total_bytes, actual_ms, data_points)

    if static_svg do
      Map.put(result, :static_svg_bytes, byte_size(static_svg))
    else
      result
    end
  end

  defp stream_loop_full(
         backend,
         chart_type,
         data_points,
         width,
         height,
         end_time,
         frames,
         total_bytes
       ) do
    now = System.monotonic_time(:millisecond)

    if now >= end_time do
      {frames, total_bytes, now - (end_time - frames)}
    else
      data = generate_animated_data(chart_type, data_points, frames)
      output = render_full_chart(backend, chart_type, data, width, height)

      stream_loop_full(
        backend,
        chart_type,
        data_points,
        width,
        height,
        end_time,
        frames + 1,
        total_bytes + byte_size(output)
      )
    end
  end

  defp stream_loop_data_only(
         mode,
         x_scale,
         y_scale,
         chart_type,
         data_points,
         canvas_size,
         end_time,
         frames,
         total_bytes
       ) do
    now = System.monotonic_time(:millisecond)

    if now >= end_time do
      {frames, total_bytes, now - (end_time - frames)}
    else
      data = generate_animated_data(chart_type, data_points, frames)

      output =
        case mode do
          :hybrid ->
            render_data_only(chart_type, data, x_scale, y_scale)

          :hybrid_incremental ->
            render_incremental(:hybrid, chart_type, data, x_scale, y_scale, canvas_size)

          :canvas_incremental ->
            render_incremental(:canvas, chart_type, data, x_scale, y_scale, canvas_size)
        end

      stream_loop_data_only(
        mode,
        x_scale,
        y_scale,
        chart_type,
        data_points,
        canvas_size,
        end_time,
        frames + 1,
        total_bytes + byte_size(output)
      )
    end
  end

  defp build_stream_result(frames, total_bytes, actual_ms, data_points) do
    fps = frames / max(actual_ms / 1000, 0.001)

    %{
      frames: frames,
      fps: fps,
      data_points_per_second: round(data_points * fps),
      total_bytes: total_bytes,
      actual_duration_ms: actual_ms
    }
  end

  # ============================================================================
  # Results Building
  # ============================================================================

  defp build_run_results(config, svg, canvas, hybrid, hybrid_inc, canvas_inc) do
    svg_time = svg.avg_render_time_us

    %{
      config: config,
      svg: svg,
      canvas: canvas,
      hybrid: hybrid,
      hybrid_incremental: hybrid_inc,
      canvas_incremental: canvas_inc,
      comparison: %{
        svg_vs_canvas_speed: Float.round(svg_time / max(canvas.avg_render_time_us, 1), 2),
        svg_vs_hybrid_speed: Float.round(svg_time / max(hybrid.avg_render_time_us, 1), 2),
        svg_vs_hybrid_inc_speed: Float.round(svg_time / max(hybrid_inc.avg_render_time_us, 1), 2),
        svg_vs_canvas_inc_speed: Float.round(svg_time / max(canvas_inc.avg_render_time_us, 1), 2),
        fastest:
          find_fastest(
            svg: svg,
            canvas: canvas,
            hybrid: hybrid,
            hybrid_incremental: hybrid_inc,
            canvas_incremental: canvas_inc
          ),
        smallest_per_frame:
          find_smallest(
            svg: svg,
            canvas: canvas,
            hybrid: hybrid,
            hybrid_incremental: hybrid_inc,
            canvas_incremental: canvas_inc
          )
      }
    }
  end

  defp build_stream_results(config, svg, canvas, hybrid, hybrid_inc, canvas_inc) do
    %{
      config: config,
      svg: svg,
      canvas: canvas,
      hybrid: hybrid,
      hybrid_incremental: hybrid_inc,
      canvas_incremental: canvas_inc,
      comparison: %{
        svg_fps: Float.round(svg.fps, 1),
        canvas_fps: Float.round(canvas.fps, 1),
        hybrid_fps: Float.round(hybrid.fps, 1),
        hybrid_inc_fps: Float.round(hybrid_inc.fps, 1),
        canvas_inc_fps: Float.round(canvas_inc.fps, 1),
        hybrid_vs_svg_fps: Float.round(hybrid.fps / max(svg.fps, 0.1), 2)
      }
    }
  end

  defp find_fastest(backends) do
    {name, _} = Enum.min_by(backends, fn {_, r} -> r.avg_render_time_us end)
    name
  end

  defp find_smallest(backends) do
    {name, _} = Enum.min_by(backends, fn {_, r} -> r.avg_payload_bytes end)
    name
  end

  defp rank_fps(results) do
    [
      {results.svg.fps, "SVG"},
      {results.canvas.fps, "Canvas"},
      {results.hybrid.fps, "Hybrid"},
      {results.hybrid_incremental.fps, "Hybrid-Inc"},
      {results.canvas_incremental.fps, "Canvas-Inc"}
    ]
    |> Enum.sort_by(fn {fps, _} -> -fps end)
    |> Enum.map(fn {fps, name} -> "#{name} (#{Float.round(fps, 1)})" end)
    |> Enum.join(" > ")
  end

  # ============================================================================
  # Rendering Functions
  # ============================================================================

  defp render_full_chart(:svg, chart_type, data, width, height) do
    build_full_chart(chart_type, data, width, height)
    |> Render.to_string(backend: :svg)
  end

  defp render_full_chart(:canvas, chart_type, data, width, height) do
    build_full_chart(chart_type, data, width, height)
    |> Canvas.render_element(format: :binary_base64)
  end

  defp render_data_only(chart_type, data, x_scale, y_scale) do
    build_data_element(chart_type, data, x_scale, y_scale)
    |> Canvas.render_element(format: :binary_base64)
  end

  # Hybrid incremental: data element only (axes rendered once as SVG)
  # Filters data to only points in the exposed region
  defp render_incremental(:hybrid, chart_type, data, x_scale, y_scale, canvas_size) do
    {width, _height} = canvas_size
    regions = CanvasIncremental.exposed_regions({@scroll_delta, 0}, canvas_size)

    region_elements =
      Enum.map(regions, fn {rx, _ry, rw, _rh} = bounds ->
        # Filter data to points in this region
        filtered_data = filter_data_to_region(data, x_scale, rx, rw, width)
        # Need at least 2 points for line/area charts
        min_points = if chart_type == :scatter, do: 1, else: 2

        element =
          if length(filtered_data) < min_points do
            Element.group([])
          else
            build_data_element(chart_type, filtered_data, x_scale, y_scale)
          end

        {bounds, element}
      end)

    CanvasIncremental.encode_incremental({@scroll_delta, 0}, canvas_size, region_elements)
    |> Base.encode64()
  end

  # Canvas incremental: full chart (including axes placeholder)
  # Filters data to only points in the exposed region
  defp render_incremental(:canvas, chart_type, data, x_scale, y_scale, canvas_size) do
    {width, height} = canvas_size
    regions = CanvasIncremental.exposed_regions({@scroll_delta, 0}, canvas_size)

    region_elements =
      Enum.map(regions, fn {rx, _ry, rw, _rh} = bounds ->
        # Filter data to points in this region
        filtered_data = filter_data_to_region(data, x_scale, rx, rw, width)
        # Need at least 2 points for line/area charts
        min_points = if chart_type == :scatter, do: 1, else: 2

        data_element =
          if length(filtered_data) < min_points do
            Element.group([])
          else
            build_data_element(chart_type, filtered_data, x_scale, y_scale)
          end

        element = Element.root(width, height, children: [data_element])
        {bounds, element}
      end)

    CanvasIncremental.encode_incremental({@scroll_delta, 0}, canvas_size, region_elements)
    |> Base.encode64()
  end

  # Filter data points to those that fall within the exposed region
  defp filter_data_to_region(data, x_scale, region_x, region_width, _canvas_width) do
    # Add buffer for line continuity
    buffer = 2
    region_end = region_x + region_width

    data
    |> Enum.with_index()
    |> Enum.filter(fn {d, _idx} ->
      px = Scale.Linear.apply(x_scale, d.x) + @margin.left
      px >= region_x - buffer and px <= region_end + buffer
    end)
    |> Enum.map(fn {d, _idx} -> d end)
  end

  defp render_static_svg(x_scale, y_scale, width, height) do
    inner_height = height - @margin.top - @margin.bottom

    x_axis_element = Axis.bottom(x_scale) |> Axis.ticks(10) |> Axis.generate()
    y_axis_element = Axis.left(y_scale) |> Axis.ticks(5) |> Axis.generate()

    x_axis_group =
      Element.group([x_axis_element], transform: Transform.translate(0, inner_height))

    static_group =
      Element.group([x_axis_group, y_axis_element],
        transform: Transform.translate(@margin.left, @margin.top)
      )

    Element.root(width, height, children: [static_group])
    |> SVG.render_element([])
    |> IO.iodata_to_binary()
  end

  # ============================================================================
  # Element Building
  # ============================================================================

  defp build_full_chart(chart_type, data, width, height) do
    {x_scale, y_scale} = build_scales(chart_type, data, width, height)
    element = build_data_element(chart_type, data, x_scale, y_scale)
    Element.root(width, height, children: [element])
  end

  defp build_data_element(:line, data, x_scale, y_scale) do
    path =
      Shape.Line.new()
      |> Shape.Line.x(fn d -> Scale.Linear.apply(x_scale, d.x) end)
      |> Shape.Line.y(fn d -> Scale.Linear.apply(y_scale, d.y) end)
      |> Shape.Line.curve(:monotone_x)
      |> Shape.Line.generate_path(data)

    Element.path(path, %{stroke: "#4e79a7", stroke_width: 2, fill: :none})
    |> Element.set_transform(Transform.translate(@margin.left, @margin.top))
  end

  defp build_data_element(:area, data, x_scale, y_scale) do
    inner_height = Scale.Linear.apply(y_scale, 0)

    path =
      Shape.Area.new()
      |> Shape.Area.x(fn d -> Scale.Linear.apply(x_scale, d.x) end)
      |> Shape.Area.y0(fn _ -> inner_height end)
      |> Shape.Area.y1(fn d -> Scale.Linear.apply(y_scale, d.y) end)
      |> Shape.Area.curve(:monotone_x)
      |> Shape.Area.generate_path(data)

    Element.path(path, %{fill: "#4e79a7", fill_opacity: 0.7, stroke: "#4e79a7"})
    |> Element.set_transform(Transform.translate(@margin.left, @margin.top))
  end

  defp build_data_element(:scatter, data, x_scale, y_scale) do
    circles =
      Enum.map(data, fn d ->
        Element.circle(
          Scale.Linear.apply(x_scale, d.x),
          Scale.Linear.apply(y_scale, d.y),
          d.r,
          %{fill: "#4e79a7", fill_opacity: 0.6}
        )
      end)

    Element.group(circles)
    |> Element.set_transform(Transform.translate(@margin.left, @margin.top))
  end

  defp build_scales(chart_type, data, width, height) do
    inner_width = width - @margin.left - @margin.right
    inner_height = height - @margin.top - @margin.bottom

    case chart_type do
      :scatter ->
        x_scale =
          Scale.Linear.new()
          |> Scale.Linear.domain([0, 100])
          |> Scale.Linear.range([0, inner_width])

        y_scale =
          Scale.Linear.new()
          |> Scale.Linear.domain([0, 100])
          |> Scale.Linear.range([inner_height, 0])

        {x_scale, y_scale}

      _ ->
        {min_x, max_x} = data |> Enum.map(& &1.x) |> Enum.min_max()
        {min_y, max_y} = data |> Enum.map(& &1.y) |> Enum.min_max()

        x_scale =
          Scale.Linear.new()
          |> Scale.Linear.domain([min_x, max_x])
          |> Scale.Linear.range([0, inner_width])

        y_scale =
          Scale.Linear.new()
          |> Scale.Linear.domain([min_y - 5, max_y + 5])
          |> Scale.Linear.range([inner_height, 0])

        {x_scale, y_scale}
    end
  end

  # ============================================================================
  # Data Generation
  # ============================================================================

  defp generate_data(:line, count) do
    for i <- 0..(count - 1) do
      x = i / max(count - 1, 1) * 100
      y = :math.sin(x / 10) * 40 + :math.cos(x / 7) * 20 + 50 + :rand.uniform() * 5
      %{x: x, y: y}
    end
  end

  defp generate_data(:area, count), do: generate_data(:line, count)

  defp generate_data(:scatter, count) do
    for _ <- 1..count do
      %{x: :rand.uniform() * 100, y: :rand.uniform() * 100, r: :rand.uniform() * 5 + 2}
    end
  end

  defp generate_animated_data(:line, count, frame) do
    phase = frame * 0.1

    for i <- 0..(count - 1) do
      x = i / max(count - 1, 1) * 100
      y = :math.sin(x / 10 + phase) * 40 + :math.cos(x / 7 + phase * 0.7) * 20 + 50
      %{x: x, y: y}
    end
  end

  defp generate_animated_data(:area, count, frame),
    do: generate_animated_data(:line, count, frame)

  defp generate_animated_data(:scatter, count, frame) do
    phase = frame * 0.05

    for i <- 1..count do
      angle = i / count * :math.pi() * 2 + phase
      radius = 30 + :math.sin(angle * 3 + phase) * 15

      %{
        x: 50 + :math.cos(angle) * radius,
        y: 50 + :math.sin(angle) * radius,
        r: 3 + :math.sin(i + frame * 0.2) * 2
      }
    end
  end

  # ============================================================================
  # Formatting Helpers
  # ============================================================================

  defp format_time(us) when us < 1000, do: "#{Float.round(us, 1)} μs"
  defp format_time(us), do: "#{Float.round(us / 1000, 2)} ms"

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / 1024 / 1024, 2)} MB"

  defp format_number(n) when n < 1000, do: "#{round(n)}"
  defp format_number(n) when n < 1_000_000, do: "#{Float.round(n / 1000, 1)}K"
  defp format_number(n), do: "#{Float.round(n / 1_000_000, 2)}M"
end
