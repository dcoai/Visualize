defmodule ExamplesWeb.PerformanceLive do
  @moduledoc """
  LiveView for interactive performance testing of SVG vs Canvas backends.

  Measures real-world throughput over Phoenix channels by streaming chart
  updates and tracking frames per second.
  """

  use Phoenix.LiveView

  alias Visualize.{Chart, Scale, Shape, Render}
  alias Visualize.Chart.Compiled
  alias Visualize.IR.Element
  alias Visualize.Backend.CanvasIncremental

  @default_data_points 200
  @default_update_interval 16  # ~60 FPS target
  @scroll_delta 20
  @margin %{top: 20, right: 20, bottom: 30, left: 40}

  # Multi-line scrolling chart config (48 ridgelines)
  @num_lines 48

  # Chord diagram config
  @chord_groups 6
  @line_colors ["#4e79a7", "#f28e2c", "#e15759", "#76b7b2", "#59a14f", "#edc949", "#af7aa1", "#ff9da7"]

  def mount(_params, _session, socket) do
    {:ok, assign(socket,
      # Test configuration
      backend: :svg,
      data_points: @default_data_points,
      update_interval: @default_update_interval,
      chart_type: :line,

      # Running state
      running: false,
      frame: 0,

      # Metrics
      fps: 0.0,
      avg_render_time_us: 0.0,
      avg_payload_bytes: 0,
      total_frames: 0,
      total_bytes: 0,

      # History for comparison
      svg_results: nil,
      canvas_results: nil,
      hybrid_results: nil,
      canvas_inc_results: nil,
      hybrid_inc_results: nil,

      # Chart output
      chart_output: "",

      # Hybrid mode: static SVG rendered once
      hybrid_static_svg: nil,
      hybrid_static_svg_bytes: 0,

      # Compiled design (spec/14 §12): the compiled chart, its static SVG rendered
      # once, the dynamic SVG of the last tick, the results of live runs and of the
      # headless measurement
      compiled: nil,
      compiled_static: nil,
      compiled_svg: "",
      compiled_results: nil,
      compiled_measure: nil,

      # Internal timing
      frame_times: [],
      render_times: [],
      payload_sizes: [],
      last_fps_calc: nil,

      # Multi-line scrolling state (for true incremental rendering)
      scrolling_data: nil,
      line_params: nil,
      scroll_offset: 0,
      viewport_x: 0,
      # Accumulator for sub-pixel shifts (accumulates until >= 1 data point worth)
      pixel_accumulator: 0.0
    )}
  end

  def handle_event("set_backend", %{"backend" => backend}, socket) do
    backend_atom = String.to_existing_atom(backend)
    {:noreply, assign(socket, backend: backend_atom)}
  end

  def handle_event("update_sliders", params, socket) do
    socket = case params do
      %{"data_points" => points_str} ->
        assign(socket, data_points: String.to_integer(points_str))
      _ ->
        socket
    end

    socket = case params do
      %{"update_interval" => interval_str} ->
        assign(socket, update_interval: String.to_integer(interval_str))
      _ ->
        socket
    end

    {:noreply, socket}
  end

  def handle_event("set_chart_type", %{"type" => type}, socket) do
    type_atom = String.to_existing_atom(type)
    {:noreply, assign(socket, chart_type: type_atom)}
  end

  def handle_event("start_test", _params, socket) do
    schedule_frame(socket.assigns.update_interval)

    # Compiled modes: compile the line design once over the first frame; the static
    # furniture is rendered here and never again (spec/14 §12.4)
    socket = if socket.assigns.backend in [:compiled_svg, :compiled_binary] do
      target = if socket.assigns.backend == :compiled_svg, do: :svg, else: :binary
      data = generate_animated_data(:line, socket.assigns.data_points, 0)
      {:ok, compiled} = Chart.compile(compiled_design(target), sources: %{primary: data})
      assign(socket,
        chart_type: :line,
        compiled: compiled,
        compiled_static: Compiled.static(compiled),
        compiled_svg: ""
      )
    else
      socket
    end

    # For hybrid modes, pre-render static SVG (axes) once
    {hybrid_static_svg, hybrid_static_svg_bytes} = if socket.assigns.backend in [:hybrid, :hybrid_incremental] do
      static_svg = render_static_svg_for_hybrid(700, 400, socket.assigns.chart_type, socket.assigns.data_points)
      {static_svg, byte_size(static_svg)}
    else
      {nil, 0}
    end

    socket = assign(socket,
      running: true,
      frame: 0,
      total_frames: 0,
      total_bytes: 0,
      frame_times: [],
      render_times: [],
      payload_sizes: [],
      last_fps_calc: System.monotonic_time(:millisecond),
      hybrid_static_svg: hybrid_static_svg,
      hybrid_static_svg_bytes: hybrid_static_svg_bytes
    )

    # Reset scrolling data when starting with multi_line
    socket = if socket.assigns.chart_type == :multi_line do
      {data, params} = init_scrolling_data(socket.assigns.data_points)
      assign(socket,
        scrolling_data: data,
        line_params: params,
        scroll_offset: 0,
        pixel_accumulator: 0.0
      )
    else
      socket
    end

    # For incremental modes, send initial full render immediately
    socket = if socket.assigns.backend in [:canvas_incremental, :hybrid_incremental] do
      data = if socket.assigns.chart_type == :multi_line do
        socket.assigns.scrolling_data
      else
        generate_animated_data(socket.assigns.chart_type, socket.assigns.data_points, 0)
      end
      full_output = render_full_for_incremental(socket.assigns.backend, socket.assigns.chart_type, data, 700, 400)
      push_event(socket, "canvas_incremental", %{binary: full_output, dx: 0, dy: 0, mode: "full"})
    else
      socket
    end

    {:noreply, socket}
  end

  def handle_event("stop_test", _params, socket) do
    # Save results for this backend
    results = %{
      backend: socket.assigns.backend,
      fps: socket.assigns.fps,
      avg_render_time_us: socket.assigns.avg_render_time_us,
      avg_payload_bytes: socket.assigns.avg_payload_bytes,
      total_frames: socket.assigns.total_frames,
      total_bytes: socket.assigns.total_bytes,
      data_points: socket.assigns.data_points,
      update_interval: socket.assigns.update_interval
    }

    # Add static_svg_bytes for hybrid modes
    results = if socket.assigns.backend in [:hybrid, :hybrid_incremental] do
      Map.put(results, :static_svg_bytes, socket.assigns.hybrid_static_svg_bytes)
    else
      results
    end

    # Add the static SVG bytes for the compiled modes
    results = if socket.assigns.backend in [:compiled_svg, :compiled_binary] do
      Map.put(results, :static_svg_bytes, byte_size(socket.assigns.compiled_static || ""))
    else
      results
    end

    # Add scroll_delta for incremental modes
    results = if socket.assigns.backend in [:canvas_incremental, :hybrid_incremental] do
      Map.put(results, :scroll_delta, @scroll_delta)
    else
      results
    end

    socket = case socket.assigns.backend do
      :svg -> assign(socket, svg_results: results)
      :canvas -> assign(socket, canvas_results: results)
      :hybrid -> assign(socket, hybrid_results: results)
      :canvas_incremental -> assign(socket, canvas_inc_results: results)
      :hybrid_incremental -> assign(socket, hybrid_inc_results: results)
      backend when backend in [:compiled_svg, :compiled_binary] ->
        compiled_results = Map.put(socket.assigns.compiled_results || %{}, backend, results)
        assign(socket, compiled_results: compiled_results)
    end

    {:noreply, assign(socket, running: false)}
  end

  def handle_event("clear_results", _params, socket) do
    {:noreply, assign(socket,
      svg_results: nil,
      canvas_results: nil,
      hybrid_results: nil,
      canvas_inc_results: nil,
      hybrid_inc_results: nil,
      compiled_results: nil,
      compiled_measure: nil
    )}
  end

  def handle_event("measure_compiled", _params, socket) do
    measure = measure_compiled(data_points: socket.assigns.data_points, updates: 100)
    {:noreply, assign(socket, compiled_measure: measure)}
  end

  def handle_event("run_quick_benchmark", _params, socket) do
    # Run the library benchmark
    results = Visualize.Benchmark.run(
      data_points: socket.assigns.data_points,
      iterations: 100,
      chart_type: socket.assigns.chart_type
    )

    {:noreply, assign(socket,
      svg_results: %{
        backend: :svg,
        fps: results.svg.renders_per_second,
        avg_render_time_us: results.svg.avg_render_time_us,
        avg_payload_bytes: results.svg.avg_payload_bytes,
        total_frames: 100,
        total_bytes: results.svg.avg_payload_bytes * 100,
        data_points: socket.assigns.data_points,
        update_interval: 0
      },
      canvas_results: %{
        backend: :canvas,
        fps: results.canvas.renders_per_second,
        avg_render_time_us: results.canvas.avg_render_time_us,
        avg_payload_bytes: results.canvas.avg_payload_bytes,
        total_frames: 100,
        total_bytes: results.canvas.avg_payload_bytes * 100,
        data_points: socket.assigns.data_points,
        update_interval: 0
      },
      hybrid_results: %{
        backend: :hybrid,
        fps: results.hybrid.renders_per_second,
        avg_render_time_us: results.hybrid.avg_render_time_us,
        avg_payload_bytes: results.hybrid.avg_payload_bytes,
        static_svg_bytes: results.hybrid.static_svg_bytes,
        total_frames: 100,
        total_bytes: results.hybrid.avg_payload_bytes * 100,
        data_points: socket.assigns.data_points,
        update_interval: 0
      },
      canvas_inc_results: %{
        backend: :canvas_incremental,
        fps: results.canvas_incremental.renders_per_second,
        avg_render_time_us: results.canvas_incremental.avg_render_time_us,
        avg_payload_bytes: results.canvas_incremental.avg_payload_bytes,
        scroll_delta: results.canvas_incremental.scroll_delta,
        total_frames: 100,
        total_bytes: results.canvas_incremental.avg_payload_bytes * 100,
        data_points: socket.assigns.data_points,
        update_interval: 0
      },
      hybrid_inc_results: %{
        backend: :hybrid_incremental,
        fps: results.hybrid_incremental.renders_per_second,
        avg_render_time_us: results.hybrid_incremental.avg_render_time_us,
        avg_payload_bytes: results.hybrid_incremental.avg_payload_bytes,
        scroll_delta: results.hybrid_incremental.scroll_delta,
        total_frames: 100,
        total_bytes: results.hybrid_incremental.avg_payload_bytes * 100,
        data_points: socket.assigns.data_points,
        update_interval: 0
      }
    )}
  end

  def handle_info(:render_frame, socket) do
    if socket.assigns.running do
      # Handle multi_line specially - it uses scrolling data with accumulator
      {data, socket, pixel_shift} = if socket.assigns.chart_type == :multi_line do
        {scrolling_data, pixel_shift, new_accumulator, new_scroll_offset} =
          shift_scrolling_data(
            socket.assigns.scrolling_data,
            socket.assigns.line_params,
            socket.assigns.scroll_offset,
            socket.assigns.pixel_accumulator
          )
        socket = assign(socket,
          scrolling_data: scrolling_data,
          pixel_accumulator: new_accumulator,
          scroll_offset: new_scroll_offset
        )
        {scrolling_data, socket, pixel_shift}
      else
        data = generate_animated_data(
          socket.assigns.chart_type,
          socket.assigns.data_points,
          socket.assigns.frame
        )
        {data, socket, @scroll_delta}
      end

      # Schedule next frame regardless of whether we render
      schedule_frame(socket.assigns.update_interval)

      # For incremental multi_line, skip rendering if pixel_shift is 0 (accumulating)
      if pixel_shift == 0.0 and socket.assigns.chart_type == :multi_line and
         socket.assigns.backend in [:canvas_incremental, :hybrid_incremental] do
        # Just accumulating pixels, no visual update this frame
        {:noreply, socket}
      else
        render_start = System.monotonic_time(:microsecond)

        {output, socket} = if socket.assigns.backend in [:compiled_svg, :compiled_binary] do
          compiled_frame(socket, data)
        else
          {case socket.assigns.backend do
          :hybrid ->
            # Hybrid mode: render data only using binary format
            render_data_only_binary(socket.assigns.chart_type, data, 700, 400)
          :canvas ->
            # Canvas mode: render full chart using binary format
            element = build_chart(socket.assigns.chart_type, data, 700, 400)
            Visualize.Backend.Canvas.render_element(element, format: :binary_base64)
          :svg ->
            # SVG mode: render full chart as SVG
            element = build_chart(socket.assigns.chart_type, data, 700, 400)
            Render.to_string(element, backend: :svg)
          :canvas_incremental ->
            # Canvas incremental: render based on chart type
            if socket.assigns.chart_type == :multi_line do
              # True incremental for scrolling multi-line
              render_multiline_incremental(:canvas, data, 700, 400, pixel_shift)
            else
              render_incremental(:canvas, socket.assigns.chart_type, data, 700, 400)
            end
          :hybrid_incremental ->
            # Hybrid incremental: render based on chart type
            if socket.assigns.chart_type == :multi_line do
              render_multiline_incremental(:hybrid, data, 700, 400, pixel_shift)
            else
              render_incremental(:hybrid, socket.assigns.chart_type, data, 700, 400)
            end
          end, socket}
        end

        render_time = System.monotonic_time(:microsecond) - render_start
        payload_size = byte_size(output)
        now = System.monotonic_time(:millisecond)

        # Update rolling metrics (keep last 60 samples)
        render_times = Enum.take([render_time | socket.assigns.render_times], 60)
        payload_sizes = Enum.take([payload_size | socket.assigns.payload_sizes], 60)
        frame_times = Enum.take([now | socket.assigns.frame_times], 60)

        # Calculate FPS from frame times
        fps = calculate_fps(frame_times)
        avg_render = Enum.sum(render_times) / length(render_times)
        avg_payload = round(Enum.sum(payload_sizes) / length(payload_sizes))

        socket = assign(socket,
          frame: socket.assigns.frame + 1,
          total_frames: socket.assigns.total_frames + 1,
          total_bytes: socket.assigns.total_bytes + payload_size,
          fps: fps,
          avg_render_time_us: avg_render,
          avg_payload_bytes: avg_payload,
          render_times: render_times,
          payload_sizes: payload_sizes,
          frame_times: frame_times,
          chart_output: output
        )

        # Push canvas commands via event for canvas/hybrid modes (both use binary format)
        socket = cond do
          socket.assigns.backend in [:canvas, :hybrid] ->
            push_event(socket, "canvas_update", %{binary: output})
          socket.assigns.backend in [:canvas_incremental, :hybrid_incremental] ->
            # Initial full render was already sent in handle_event("start_test")
            # All subsequent frames use incremental mode
            push_event(socket, "canvas_incremental", %{binary: output, dx: pixel_shift, dy: 0, mode: "scroll_x"})
          true ->
            socket
        end

        {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  @doc """
  The line design of spec/14 §12.6 over the page's animated line data: fixed `x` and `y`
  domains so the whole frame is static, both axes with a grid, a title, and one `:line`
  mark whose `render` is the target given (`:svg`, `:binary`, or `:auto`).
  """
  def compiled_design(target \\ :auto) do
    %{
      version: 1,
      meta: %{name: "Performance line"},
      sources: %{primary: %{fields: [:x, :y]}},
      styles: %{series: %{stroke_width: 2, curve: :monotone_x}},
      frame: %{
        kind: :cartesian,
        size: %{width: 700, height: 400},
        margin: @margin,
        scales: %{x: %{kind: :linear, domain: [0, 100]}, y: %{kind: :linear, domain: [-10, 110]}},
        axes: [%{scale: :x, side: :bottom, grid: true}, %{scale: :y, side: :left, grid: true}]
      },
      marks: [
        %{type: :line, data: :primary, channels: %{x: :x, y: :y}, style: :series, render: target}
      ],
      labels: [%{anchor: :title, text: ["Compiled line"]}]
    }
  end

  @doc """
  The measurement of spec/14 §12.6: bytes per update over `:updates` (100) frames of
  `:data_points` (#{@default_data_points}) points — the old path, `Visualize.Chart.render/2`
  of the design applied to each frame as one SVG string, against the compiled path,
  `Visualize.Chart.Compiled.static/1` once and the tick payload's `bytes` per frame, for
  `render: :svg` and `render: :binary`.
  """
  def measure_compiled(opts \\ []) do
    points = Keyword.get(opts, :data_points, @default_data_points)
    updates = Keyword.get(opts, :updates, 100)
    frames = for frame <- 1..updates, do: generate_animated_data(:line, points, frame)
    old = frames |> Enum.map(&byte_size(old_path(&1))) |> Enum.sum()

    compiled =
      Map.new([:svg, :binary], fn target ->
        {:ok, compiled} = Chart.compile(compiled_design(target), sources: %{primary: hd(frames)})

        {bytes, raw, _compiled} =
          Enum.reduce(frames, {0, 0, compiled}, fn data, {sum, raw, compiled} ->
            {payload, compiled} = Compiled.tick(compiled, %{primary: data})
            {sum + payload.bytes, raw + raw_bytes(payload), compiled}
          end)

        {target,
         %{
           static_bytes: byte_size(Compiled.static(compiled)),
           bytes_per_update: div(bytes, updates),
           raw_bytes_per_update: div(raw, updates)
         }}
      end)

    %{
      updates: updates,
      data_points: points,
      old_bytes_per_update: div(old, updates),
      compiled: compiled
    }
  end

  # What a tick would transmit without the base64 of the canvas layer (#73 item 3): the SVG
  # layer as it is and the canvas stream decoded — the bytes a binary frame would carry.
  defp raw_bytes(%{svg: svg, canvas: canvas}),
    do: byte_size(svg) + byte_size(Base.decode64!(canvas))

  # The old path: the design applied to the frame's data and rendered whole.
  defp old_path(data) do
    {:ok, applied} = Chart.apply(compiled_design(:svg), sources: %{primary: data})
    Chart.render(applied)
  end

  # One frame of a compiled mode: the tick's dynamic SVG replaces the last, its canvas
  # (binary) is pushed to the hook; the transmitted bytes are the two together.
  defp compiled_frame(socket, data) do
    {payload, compiled} = Compiled.tick(socket.assigns.compiled, %{primary: data})
    socket = assign(socket, compiled: compiled, compiled_svg: payload.svg)

    socket =
      if payload.canvas == "",
        do: socket,
        else: push_event(socket, "canvas_update", %{binary: payload.canvas})

    {payload.svg <> payload.canvas, socket}
  end

  defp schedule_frame(interval) do
    Process.send_after(self(), :render_frame, interval)
  end

  defp calculate_fps([]), do: 0.0
  defp calculate_fps([_]), do: 0.0
  defp calculate_fps(times) do
    oldest = List.last(times)
    newest = hd(times)
    duration_ms = newest - oldest

    if duration_ms > 0 do
      (length(times) - 1) / (duration_ms / 1000)
    else
      0.0
    end
  end

  # Initialize scrolling data for multi-line chart (random values for each line)
  # count is total data points across all lines
  defp init_scrolling_data(total_count) do
    points_per_line = max(10, div(total_count, @num_lines))

    # Generate unique parameters for each line
    line_params = for line_idx <- 0..(@num_lines - 1) do
      # Each line gets unique amplitude, frequency, and phase
      # Use deterministic but varied values based on line index
      base_amplitude = 30 + :rand.uniform() * 20  # 30-50
      frequency1 = 0.02 + (line_idx / @num_lines) * 0.03  # Primary wave
      frequency2 = 0.05 + :rand.uniform() * 0.03  # Secondary wave
      phase1 = line_idx * 0.5 + :rand.uniform() * :math.pi()
      phase2 = :rand.uniform() * 2 * :math.pi()
      amplitude_ratio = 0.3 + :rand.uniform() * 0.4  # Ratio of secondary to primary

      %{
        amplitude: base_amplitude,
        freq1: frequency1,
        freq2: frequency2,
        phase1: phase1,
        phase2: phase2,
        amp_ratio: amplitude_ratio
      }
    end

    # Generate initial data using the parameters
    data = line_params
    |> Enum.map(fn params ->
      for i <- 0..(points_per_line - 1) do
        generate_sine_value(params, i)
      end
    end)

    {data, line_params}
  end

  # Generate a sine wave value for a given x position and line parameters
  defp generate_sine_value(params, x) do
    primary = :math.sin(x * params.freq1 + params.phase1) * params.amplitude
    secondary = :math.sin(x * params.freq2 + params.phase2) * params.amplitude * params.amp_ratio
    # Center around 50 with the wave oscillations
    50 + primary + secondary
  end

  # Fixed pixel shift per frame (1 pixel for smooth scrolling)
  @pixel_shift_per_frame 1.0
  # inner_width = 700 (full canvas width with zero margins)
  @inner_width 700

  # Shift scrolling data left and add new sine wave values on right
  # Uses accumulator to handle sub-pixel shifts - data only shifts when
  # accumulated pixels >= 1 data point worth
  # Returns {shifted_data, pixel_shift, new_accumulator, new_scroll_offset}
  # pixel_shift is always an integer (0 when not enough accumulated) to avoid blur
  defp shift_scrolling_data(data, line_params, scroll_offset, accumulator) do
    count = length(hd(data))
    pixels_per_point = @inner_width / (count - 1)

    # Add this frame's pixel shift to accumulator
    total_pixels = accumulator + @pixel_shift_per_frame

    # Calculate how many whole data points we can shift
    points_to_shift = trunc(total_pixels / pixels_per_point)

    if points_to_shift >= 1 do
      # New scroll offset for generating new values
      new_scroll_offset = scroll_offset + points_to_shift

      # Shift the data by the calculated number of points
      shifted_data = data
      |> Enum.zip(line_params)
      |> Enum.map(fn {line_data, params} ->
        remaining = Enum.drop(line_data, points_to_shift)
        # Generate new sine wave values at the new x positions
        new_values = for i <- 0..(points_to_shift - 1) do
          # x position is the scroll offset plus position within the window
          x = new_scroll_offset + count - points_to_shift + i
          generate_sine_value(params, x)
        end
        remaining ++ new_values
      end)

      # Calculate pixel shift and round to integer to avoid canvas blur
      exact_pixel_shift = points_to_shift * pixels_per_point
      rounded_pixel_shift = round(exact_pixel_shift)
      # Accumulate the rounding error to maintain long-term accuracy
      rounding_error = exact_pixel_shift - rounded_pixel_shift
      new_accumulator = (total_pixels - exact_pixel_shift) + rounding_error

      {shifted_data, rounded_pixel_shift, new_accumulator, new_scroll_offset}
    else
      # Not enough accumulated to shift data - don't shift canvas either
      # Return original data with 0 pixel shift (no visual change this frame)
      {data, 0, total_pixels, scroll_offset}
    end
  end

  defp generate_animated_data(:line, count, frame) do
    phase = frame * 0.1
    for i <- 0..(count - 1) do
      x = i / (count - 1) * 100
      y = :math.sin(x / 10 + phase) * 40 + :math.cos(x / 7 + phase * 0.7) * 20 + 50
      %{x: x, y: y}
    end
  end

  defp generate_animated_data(:area, count, frame), do: generate_animated_data(:line, count, frame)

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

  # Multi-line scrolling - data is pre-generated and shifted each frame
  # This returns the scrolling_data directly (handled specially in render_frame)
  defp generate_animated_data(:multi_line, _count, _frame) do
    # Placeholder - actual data comes from socket.assigns.scrolling_data
    []
  end

  # Ridgeline plot - multiple overlapping density curves (48 ridges)
  @ridgeline_count 48

  defp generate_animated_data(:ridgeline, count, frame) do
    phase = frame * 0.08
    points_per_ridge = max(10, div(count, @ridgeline_count))

    for ridge <- 0..(@ridgeline_count - 1) do
      ridge_phase = phase + ridge * 0.15
      for i <- 0..(points_per_ridge - 1) do
        x = i / (points_per_ridge - 1) * 100
        # Create wave-like density with multiple peaks
        y = :math.sin(x / 15 + ridge_phase) * 20 +
            :math.cos(x / 10 + ridge_phase * 1.3) * 15 +
            :math.sin(x / 5 + ridge_phase * 0.7) * 10 +
            40
        %{x: x, y: max(0, y)}
      end
    end
  end

  # Chord diagram - relationships between groups (matrix format)
  defp generate_animated_data(:chord, _count, frame) do
    phase = frame * 0.02
    # Generate a flow matrix between groups
    for i <- 0..(@chord_groups - 1) do
      for j <- 0..(@chord_groups - 1) do
        if i == j do
          0
        else
          base = 10 + :rand.uniform() * 40
          # Add some animation to the flows
          base * (0.8 + 0.4 * :math.sin(phase + i * 0.5 + j * 0.3))
        end
      end
    end
  end

  defp build_chart(:line, data, width, height) do
    margin = %{top: 20, right: 20, bottom: 30, left: 40}
    inner_width = width - margin.left - margin.right
    inner_height = height - margin.top - margin.bottom

    {min_x, max_x} = data |> Enum.map(& &1.x) |> Enum.min_max()
    {min_y, max_y} = data |> Enum.map(& &1.y) |> Enum.min_max()

    x_scale = Scale.Linear.new()
      |> Scale.Linear.domain([min_x, max_x])
      |> Scale.Linear.range([0, inner_width])

    y_scale = Scale.Linear.new()
      |> Scale.Linear.domain([min_y - 5, max_y + 5])
      |> Scale.Linear.range([inner_height, 0])

    line = Shape.Line.new()
      |> Shape.Line.x(fn d -> Scale.Linear.apply(x_scale, d.x) end)
      |> Shape.Line.y(fn d -> Scale.Linear.apply(y_scale, d.y) end)
      |> Shape.Line.curve(:monotone_x)

    path = Shape.Line.generate_path(line, data)

    line_element = Element.path(path, %{
      stroke: "#4e79a7",
      stroke_width: 2,
      fill: :none
    })

    chart_group = Element.group([line_element],
      transform: Visualize.IR.Transform.translate(margin.left, margin.top)
    )

    Element.root(width, height, children: [chart_group])
  end

  defp build_chart(:area, data, width, height) do
    margin = %{top: 20, right: 20, bottom: 30, left: 40}
    inner_width = width - margin.left - margin.right
    inner_height = height - margin.top - margin.bottom

    {min_x, max_x} = data |> Enum.map(& &1.x) |> Enum.min_max()
    {min_y, max_y} = data |> Enum.map(& &1.y) |> Enum.min_max()

    x_scale = Scale.Linear.new()
      |> Scale.Linear.domain([min_x, max_x])
      |> Scale.Linear.range([0, inner_width])

    y_scale = Scale.Linear.new()
      |> Scale.Linear.domain([0, max_y + 5])
      |> Scale.Linear.range([inner_height, 0])

    area = Shape.Area.new()
      |> Shape.Area.x(fn d -> Scale.Linear.apply(x_scale, d.x) end)
      |> Shape.Area.y0(fn _ -> inner_height end)
      |> Shape.Area.y1(fn d -> Scale.Linear.apply(y_scale, d.y) end)
      |> Shape.Area.curve(:monotone_x)

    path = Shape.Area.generate_path(area, data)

    area_element = Element.path(path, %{
      fill: "#4e79a7",
      fill_opacity: 0.7,
      stroke: "#4e79a7",
      stroke_width: 1
    })

    chart_group = Element.group([area_element],
      transform: Visualize.IR.Transform.translate(margin.left, margin.top)
    )

    Element.root(width, height, children: [chart_group])
  end

  defp build_chart(:scatter, data, width, height) do
    margin = %{top: 20, right: 20, bottom: 30, left: 40}
    inner_width = width - margin.left - margin.right
    inner_height = height - margin.top - margin.bottom

    x_scale = Scale.Linear.new()
      |> Scale.Linear.domain([0, 100])
      |> Scale.Linear.range([0, inner_width])

    y_scale = Scale.Linear.new()
      |> Scale.Linear.domain([0, 100])
      |> Scale.Linear.range([inner_height, 0])

    circles = Enum.map(data, fn d ->
      Element.circle(
        Scale.Linear.apply(x_scale, d.x),
        Scale.Linear.apply(y_scale, d.y),
        d.r,
        %{fill: "#4e79a7", fill_opacity: 0.6}
      )
    end)

    chart_group = Element.group(circles,
      transform: Visualize.IR.Transform.translate(margin.left, margin.top)
    )

    Element.root(width, height, children: [chart_group])
  end

  # Multi-line scrolling chart - ridgeline style (48 layered lines)
  defp build_chart(:multi_line, scrolling_data, width, height) do
    margin = %{top: 0, right: 0, bottom: 0, left: 0}
    inner_width = width - margin.left - margin.right
    inner_height = height - margin.top - margin.bottom

    count = length(hd(scrolling_data))
    num_ridges = length(scrolling_data)

    # Calculate spacing to fill vertical space evenly
    ridge_spacing = inner_height / num_ridges
    ridge_height = ridge_spacing * 3  # Allow ridges to overlap visually

    x_scale = Scale.Linear.new()
      |> Scale.Linear.domain([0, count - 1])
      |> Scale.Linear.range([0, inner_width])

    ridge_elements = scrolling_data
    |> Enum.with_index()
    |> Enum.map(fn {line_data, idx} ->
      # Position from bottom to top
      y_offset = inner_height - (idx + 1) * ridge_spacing

      y_scale = Scale.Linear.new()
        |> Scale.Linear.domain([0, 100])
        |> Scale.Linear.range([ridge_height, 0])

      data = line_data
      |> Enum.with_index()
      |> Enum.map(fn {y, i} -> %{x: i, y: y} end)

      # Use linear interpolation for incremental rendering compatibility
      line = Shape.Line.new()
        |> Shape.Line.x(fn d -> Scale.Linear.apply(x_scale, d.x) end)
        |> Shape.Line.y(fn d -> Scale.Linear.apply(y_scale, d.y) end)

      path = Shape.Line.generate_path(line, data)

      # Interpolate from deep purple (bottom) to orange (top)
      color = interpolate_purple_orange(idx / (num_ridges - 1))

      line_element = Element.path(path, %{
        fill: :none,
        stroke: color,
        stroke_width: 1.5
      })

      Element.group([line_element],
        transform: Visualize.IR.Transform.translate(0, y_offset)
      )
    end)

    chart_group = Element.group(ridge_elements,
      transform: Visualize.IR.Transform.translate(margin.left, margin.top)
    )

    Element.root(width, height, children: [chart_group])
  end

  # Interpolate from deep purple to orange
  defp interpolate_purple_orange(t) when t >= 0 and t <= 1 do
    # Deep purple: #5B21B6, Orange: #F97316
    r1 = 0x5B; g1 = 0x21; b1 = 0xB6
    r2 = 0xF9; g2 = 0x73; b2 = 0x16

    r = round(r1 + (r2 - r1) * t)
    g = round(g1 + (g2 - g1) * t)
    b = round(b1 + (b2 - b1) * t)

    r_hex = r |> Integer.to_string(16) |> String.pad_leading(2, "0")
    g_hex = g |> Integer.to_string(16) |> String.pad_leading(2, "0")
    b_hex = b |> Integer.to_string(16) |> String.pad_leading(2, "0")

    "##{r_hex}#{g_hex}#{b_hex}"
  end

  # Ridgeline plot - layered line charts with vertical offset (48 ridges)
  defp build_chart(:ridgeline, ridges_data, width, height) do
    margin = %{top: 10, right: 20, bottom: 10, left: 40}
    inner_width = width - margin.left - margin.right
    inner_height = height - margin.top - margin.bottom

    num_ridges = length(ridges_data)

    # Calculate spacing to fill vertical space evenly
    ridge_spacing = inner_height / num_ridges
    ridge_height = ridge_spacing * 3  # Allow ridges to overlap visually

    x_scale = Scale.Linear.new()
      |> Scale.Linear.domain([0, 100])
      |> Scale.Linear.range([0, inner_width])

    ridge_elements = ridges_data
    |> Enum.with_index()
    |> Enum.map(fn {ridge_data, idx} ->
      # Position from bottom to top
      y_offset = inner_height - (idx + 1) * ridge_spacing

      y_scale = Scale.Linear.new()
        |> Scale.Linear.domain([0, 80])
        |> Scale.Linear.range([ridge_height, 0])

      # Use linear interpolation for incremental rendering compatibility
      line = Shape.Line.new()
        |> Shape.Line.x(fn d -> Scale.Linear.apply(x_scale, d.x) end)
        |> Shape.Line.y(fn d -> Scale.Linear.apply(y_scale, d.y) end)

      path = Shape.Line.generate_path(line, ridge_data)

      # Interpolate from deep purple (bottom) to orange (top)
      color = interpolate_purple_orange(idx / max(1, num_ridges - 1))

      line_element = Element.path(path, %{
        fill: :none,
        stroke: color,
        stroke_width: 1.5
      })

      Element.group([line_element],
        transform: Visualize.IR.Transform.translate(0, y_offset)
      )
    end)

    chart_group = Element.group(ridge_elements,
      transform: Visualize.IR.Transform.translate(margin.left, margin.top)
    )

    Element.root(width, height, children: [chart_group])
  end

  # Chord diagram - shows interconnected relationships (not suitable for incremental)
  defp build_chart(:chord, matrix, width, height) do
    # Center the chord diagram
    cx = width / 2
    cy = height / 2
    outer_radius = min(width, height) / 2 - 40
    inner_radius = outer_radius - 20

    num_groups = length(matrix)

    # Calculate totals for each group
    row_totals = Enum.map(matrix, &Enum.sum/1)
    grand_total = Enum.sum(row_totals)

    # Calculate arc angles for each group
    {group_arcs, _} = row_totals
    |> Enum.with_index()
    |> Enum.map_reduce(0, fn {total, idx}, start_angle ->
      angle_span = if grand_total > 0, do: (total / grand_total) * 2 * :math.pi() * 0.95, else: 0
      end_angle = start_angle + angle_span
      gap = 2 * :math.pi() * 0.05 / num_groups
      {{idx, start_angle, end_angle}, end_angle + gap}
    end)

    # Build group arcs
    group_elements = Enum.map(group_arcs, fn {idx, start_angle, end_angle} ->
      color = Enum.at(@line_colors, rem(idx, length(@line_colors)))
      arc_path = build_arc_path(cx, cy, inner_radius, outer_radius, start_angle, end_angle)
      Element.path(arc_path, %{fill: color, fill_opacity: 0.8})
    end)

    # Build chords (connections between groups)
    chord_elements = build_chord_elements(matrix, group_arcs, cx, cy, inner_radius)

    Element.root(width, height, children: group_elements ++ chord_elements)
  end

  # Build an arc path for chord diagram groups
  defp build_arc_path(cx, cy, inner_r, outer_r, start_angle, end_angle) do
    alias Visualize.IR.Path

    # Outer arc start
    x1 = cx + outer_r * :math.cos(start_angle)
    y1 = cy + outer_r * :math.sin(start_angle)
    # Outer arc end
    x2 = cx + outer_r * :math.cos(end_angle)
    y2 = cy + outer_r * :math.sin(end_angle)
    # Inner arc end
    x3 = cx + inner_r * :math.cos(end_angle)
    y3 = cy + inner_r * :math.sin(end_angle)
    # Inner arc start
    x4 = cx + inner_r * :math.cos(start_angle)
    y4 = cy + inner_r * :math.sin(start_angle)

    large_arc = if end_angle - start_angle > :math.pi(), do: 1, else: 0

    Path.new()
    |> Path.move_to(x1, y1)
    |> Path.arc_to(outer_r, outer_r, 0, large_arc, 1, x2, y2)
    |> Path.line_to(x3, y3)
    |> Path.arc_to(inner_r, inner_r, 0, large_arc, 0, x4, y4)
    |> Path.close()
  end

  # Build chord connection elements
  defp build_chord_elements(matrix, group_arcs, cx, cy, radius) do
    alias Visualize.IR.Path

    # For simplicity, draw chords between adjacent groups with significant flow
    matrix
    |> Enum.with_index()
    |> Enum.flat_map(fn {row, i} ->
      row
      |> Enum.with_index()
      |> Enum.filter(fn {val, j} -> j > i and val > 5 end)  # Only draw significant flows
      |> Enum.map(fn {val, j} ->
        {_, start_i, end_i} = Enum.at(group_arcs, i)
        {_, start_j, end_j} = Enum.at(group_arcs, j)

        # Use midpoints of arcs
        angle_i = (start_i + end_i) / 2
        angle_j = (start_j + end_j) / 2

        x1 = cx + radius * :math.cos(angle_i)
        y1 = cy + radius * :math.sin(angle_i)
        x2 = cx + radius * :math.cos(angle_j)
        y2 = cy + radius * :math.sin(angle_j)

        color = Enum.at(@line_colors, rem(i, length(@line_colors)))
        opacity = min(0.6, val / 50)

        # Quadratic bezier through center
        path = Path.new()
        |> Path.move_to(x1, y1)
        |> Path.quad_to(cx, cy, x2, y2)

        Element.path(path, %{stroke: color, stroke_width: max(1, val / 10), stroke_opacity: opacity, fill: :none})
      end)
    end)
  end

  def render(assigns) do
    ~H"""
    <header>
      <h1>Backend Performance Test</h1>
      <p>Compare SVG vs Canvas rendering throughput over LiveView</p>
    </header>

    <main>
      <a href="/" class="back-link">
        <span>&larr;</span> Back to Gallery
      </a>

      <div class="performance-container">
        <div class="controls-panel">
          <h3>Configuration</h3>

          <div class="control-group">
            <label>Backend:</label>
            <div class="button-group">
              <button
                type="button"
                phx-click="set_backend"
                phx-value-backend="svg"
                class={"btn #{if @backend == :svg, do: "active"}"}
                disabled={@running}
              >
                SVG
              </button>
              <button
                type="button"
                phx-click="set_backend"
                phx-value-backend="canvas"
                class={"btn #{if @backend == :canvas, do: "active"}"}
                disabled={@running}
              >
                Canvas
              </button>
              <button
                type="button"
                phx-click="set_backend"
                phx-value-backend="hybrid"
                class={"btn #{if @backend == :hybrid, do: "active"}"}
                disabled={@running}
              >
                Hybrid
              </button>
            </div>
            <div class="button-group" style="margin-top: 0.5rem;">
              <button
                type="button"
                phx-click="set_backend"
                phx-value-backend="canvas_incremental"
                class={"btn #{if @backend == :canvas_incremental, do: "active"}"}
                disabled={@running}
              >
                Canvas-Inc
              </button>
              <button
                type="button"
                phx-click="set_backend"
                phx-value-backend="hybrid_incremental"
                class={"btn #{if @backend == :hybrid_incremental, do: "active"}"}
                disabled={@running}
              >
                Hybrid-Inc
              </button>
            </div>
            <div class="button-group" style="margin-top: 0.5rem;">
              <button
                type="button"
                phx-click="set_backend"
                phx-value-backend="compiled_svg"
                class={"btn #{if @backend == :compiled_svg, do: "active"}"}
                disabled={@running}
                title="Compiled design (spec/14 §12): static furniture once, the line as SVG per update"
              >
                Compiled-SVG
              </button>
              <button
                type="button"
                phx-click="set_backend"
                phx-value-backend="compiled_binary"
                class={"btn #{if @backend == :compiled_binary, do: "active"}"}
                disabled={@running}
                title="Compiled design (spec/14 §12): static furniture once, the line as binary canvas per update"
              >
                Compiled-Binary
              </button>
            </div>
          </div>

          <div class="control-group">
            <label>Chart Type:</label>
            <div class="button-group">
              <button
                type="button"
                phx-click="set_chart_type"
                phx-value-type="line"
                class={"btn #{if @chart_type == :line, do: "active"}"}
                disabled={@running}
              >
                Line
              </button>
              <button
                type="button"
                phx-click="set_chart_type"
                phx-value-type="area"
                class={"btn #{if @chart_type == :area, do: "active"}"}
                disabled={@running}
              >
                Area
              </button>
              <button
                type="button"
                phx-click="set_chart_type"
                phx-value-type="scatter"
                class={"btn #{if @chart_type == :scatter, do: "active"}"}
                disabled={@running}
              >
                Scatter
              </button>
              <button
                type="button"
                phx-click="set_chart_type"
                phx-value-type="multi_line"
                class={"btn #{if @chart_type == :multi_line, do: "active"}"}
                disabled={@running}
                title="Scrolling multi-line - ideal for incremental rendering"
              >
                Multi-Line
              </button>
              <button
                type="button"
                phx-click="set_chart_type"
                phx-value-type="ridgeline"
                class={"btn #{if @chart_type == :ridgeline, do: "active"}"}
                disabled={@running}
                title="Ridgeline plot - layered distributions"
              >
                Ridgeline
              </button>
              <button
                type="button"
                phx-click="set_chart_type"
                phx-value-type="chord"
                class={"btn #{if @chart_type == :chord, do: "active"}"}
                disabled={@running}
                title="Chord diagram - not suitable for incremental"
              >
                Chord
              </button>
            </div>
          </div>

          <form phx-change="update_sliders">
            <div class="control-group">
              <label>Total Data Points: <%= format_number(@data_points) %></label>
              <input
                type="range"
                min="50"
                max="500000"
                step="50"
                value={@data_points}
                name="data_points"
                disabled={@running}
                phx-debounce="50"
              />
            </div>

            <div class="control-group">
              <label>Update Interval: <%= @update_interval %>ms (<%= round(1000 / @update_interval) %> target FPS)</label>
              <input
                type="range"
                min="8"
                max="100"
                step="1"
                value={@update_interval}
                name="update_interval"
                disabled={@running}
                phx-debounce="50"
              />
            </div>
          </form>

          <div class="control-group action-buttons">
            <%= if @running do %>
              <button type="button" phx-click="stop_test" class="btn stop">
                Stop Test
              </button>
            <% else %>
              <button type="button" phx-click="start_test" class="btn start">
                Start Streaming Test
              </button>
            <% end %>

            <button
              type="button"
              phx-click="run_quick_benchmark"
              class="btn benchmark"
              disabled={@running}
            >
              Run Quick Benchmark
            </button>

            <button
              type="button"
              phx-click="clear_results"
              class="btn clear"
              disabled={@running}
            >
              Clear Results
            </button>
          </div>
        </div>

        <div class="metrics-panel">
          <h3>Live Metrics (<%= @backend %>)</h3>

          <div class="metric">
            <span class="label">Frame:</span>
            <span class="value"><%= @frame %></span>
          </div>

          <div class="metric highlight">
            <span class="label">FPS:</span>
            <span class="value"><%= Float.round(@fps, 1) %></span>
          </div>

          <div class="metric">
            <span class="label">Render Time:</span>
            <span class="value"><%= format_time(@avg_render_time_us) %></span>
          </div>

          <div class="metric">
            <span class="label">Payload Size:</span>
            <span class="value"><%= format_bytes(@avg_payload_bytes) %></span>
          </div>

          <div class="metric">
            <span class="label">Total Data:</span>
            <span class="value"><%= format_bytes(@total_bytes) %></span>
          </div>

          <div class="metric">
            <span class="label">Data Points/sec:</span>
            <span class="value"><%= format_number(round(@fps * @data_points)) %></span>
          </div>
        </div>

        <div class="chart-info-panel">
          <h4>Chart Type: <%= chart_type_label(@chart_type) %></h4>
          <div class={"chart-description #{chart_type_class(@chart_type)}"}>
            <span class={"tag #{chart_type_class(@chart_type)}"}><%= chart_type_tag(@chart_type) %></span>
            <p><%= chart_type_description(@chart_type) %></p>
          </div>
        </div>

        <div class="chart-panel">
          <h3>Live Chart Preview (<%= @backend %>)</h3>
          <div class="chart-container">
            <%= if @backend == :svg do %>
              <%= Phoenix.HTML.raw(@chart_output) %>
            <% else %>
              <%= if @backend in [:compiled_svg, :compiled_binary] do %>
              <!-- Compiled modes: the canvas under the static SVG under the dynamic SVG (spec/14 §12.4) -->
              <div class="canvas-wrapper" style="position: relative; width: 700px; height: 400px; background: white; border: 1px solid #ddd;">
                <%= if @backend == :compiled_binary do %>
                  <div id="perf-compiled-binary" phx-hook="CanvasBinaryChart" phx-update="ignore" data-binary="" data-width="700" data-height="400" style="position: absolute; top: 0; left: 0; z-index: 1;">
                    <canvas width="700" height="400" style="display: block;"></canvas>
                  </div>
                <% end %>
                <div class="compiled-static-layer" style="position: absolute; top: 0; left: 0; z-index: 2; pointer-events: none;">
                  <%= Phoenix.HTML.raw(@compiled_static || "") %>
                </div>
                <div class="compiled-dynamic-layer" style="position: absolute; top: 0; left: 0; z-index: 3; pointer-events: none;">
                  <%= Phoenix.HTML.raw(@compiled_svg) %>
                </div>
              </div>
              <% else %>
              <div class="canvas-wrapper" style="position: relative; width: 700px; height: 400px; background: white; border: 1px solid #ddd;">
                <%= if @backend in [:hybrid, :hybrid_incremental] && @hybrid_static_svg do %>
                  <!-- Hybrid modes: static SVG axes layer -->
                  <div class="hybrid-svg-layer" style="position: absolute; top: 0; left: 0; z-index: 1; pointer-events: none;">
                    <%= Phoenix.HTML.raw(@hybrid_static_svg) %>
                  </div>
                <% end %>
                <%= if @backend in [:canvas_incremental, :hybrid_incremental] do %>
                  <!-- Incremental modes use CanvasIncrementalChart hook -->
                  <div id="perf-canvas-incremental" phx-hook="CanvasIncrementalChart" phx-update="ignore" data-width="700" data-height="400" style="position: absolute; top: 0; left: 0; z-index: 2;">
                    <canvas width="700" height="400" style="display: block;"></canvas>
                  </div>
                <% else %>
                  <!-- Canvas and Hybrid use binary format -->
                  <div id="perf-canvas-binary" phx-hook="CanvasBinaryChart" phx-update="ignore" data-binary="" data-width="700" data-height="400" style="position: absolute; top: 0; left: 0; z-index: 2;">
                    <canvas width="700" height="400" style="display: block;"></canvas>
                  </div>
                <% end %>
              </div>
              <% end %>
            <% end %>
          </div>
        </div>

        <%= if @svg_results || @canvas_results || @hybrid_results || @canvas_inc_results || @hybrid_inc_results do %>
          <div class="comparison-panel">
            <h3>Results Comparison</h3>

            <table class="results-table">
              <thead>
                <tr>
                  <th>Metric</th>
                  <th>SVG</th>
                  <th>Canvas</th>
                  <th>Hybrid</th>
                  <th>Canvas-Inc</th>
                  <th>Hybrid-Inc</th>
                  <th>Best</th>
                </tr>
              </thead>
              <tbody>
                <tr>
                  <td>FPS</td>
                  <td><%= if @svg_results, do: Float.round(@svg_results.fps, 1), else: "-" %></td>
                  <td><%= if @canvas_results, do: Float.round(@canvas_results.fps, 1), else: "-" %></td>
                  <td><%= if @hybrid_results, do: Float.round(@hybrid_results.fps, 1), else: "-" %></td>
                  <td><%= if @canvas_inc_results, do: Float.round(@canvas_inc_results.fps, 1), else: "-" %></td>
                  <td><%= if @hybrid_inc_results, do: Float.round(@hybrid_inc_results.fps, 1), else: "-" %></td>
                  <td><%= fastest_of_five(@svg_results, @canvas_results, @hybrid_results, @canvas_inc_results, @hybrid_inc_results, :fps) %></td>
                </tr>
                <tr>
                  <td>Render Time</td>
                  <td><%= if @svg_results, do: format_time(@svg_results.avg_render_time_us), else: "-" %></td>
                  <td><%= if @canvas_results, do: format_time(@canvas_results.avg_render_time_us), else: "-" %></td>
                  <td><%= if @hybrid_results, do: format_time(@hybrid_results.avg_render_time_us), else: "-" %></td>
                  <td><%= if @canvas_inc_results, do: format_time(@canvas_inc_results.avg_render_time_us), else: "-" %></td>
                  <td><%= if @hybrid_inc_results, do: format_time(@hybrid_inc_results.avg_render_time_us), else: "-" %></td>
                  <td><%= fastest_of_five(@svg_results, @canvas_results, @hybrid_results, @canvas_inc_results, @hybrid_inc_results, :avg_render_time_us, true) %></td>
                </tr>
                <tr>
                  <td>Payload Size</td>
                  <td><%= if @svg_results, do: format_bytes(@svg_results.avg_payload_bytes), else: "-" %></td>
                  <td><%= if @canvas_results, do: format_bytes(@canvas_results.avg_payload_bytes), else: "-" %></td>
                  <td><%= if @hybrid_results, do: format_bytes(@hybrid_results.avg_payload_bytes), else: "-" %></td>
                  <td><%= if @canvas_inc_results, do: format_bytes(@canvas_inc_results.avg_payload_bytes), else: "-" %></td>
                  <td><%= if @hybrid_inc_results, do: format_bytes(@hybrid_inc_results.avg_payload_bytes), else: "-" %></td>
                  <td><%= fastest_of_five(@svg_results, @canvas_results, @hybrid_results, @canvas_inc_results, @hybrid_inc_results, :avg_payload_bytes, true) %></td>
                </tr>
                <tr>
                  <td>Data Pts/sec</td>
                  <td><%= if @svg_results, do: format_number(round(@svg_results.fps * @svg_results.data_points)), else: "-" %></td>
                  <td><%= if @canvas_results, do: format_number(round(@canvas_results.fps * @canvas_results.data_points)), else: "-" %></td>
                  <td><%= if @hybrid_results, do: format_number(round(@hybrid_results.fps * @hybrid_results.data_points)), else: "-" %></td>
                  <td><%= if @canvas_inc_results, do: format_number(round(@canvas_inc_results.fps * @canvas_inc_results.data_points)), else: "-" %></td>
                  <td><%= if @hybrid_inc_results, do: format_number(round(@hybrid_inc_results.fps * @hybrid_inc_results.data_points)), else: "-" %></td>
                  <td><%= throughput_winner_five(@svg_results, @canvas_results, @hybrid_results, @canvas_inc_results, @hybrid_inc_results) %></td>
                </tr>
              </tbody>
            </table>

            <p class="comparison-note">
              <strong>Note:</strong> Incremental modes (Canvas-Inc, Hybrid-Inc) optimize for scrolling/panning -
              they only render newly exposed regions instead of the full chart each frame.
            </p>
          </div>
        <% end %>

        <div class="comparison-panel">
          <h3>Compiled design (spec/14 §12)</h3>
          <p class="comparison-note">
            The line design of <code>compiled_design/1</code> streamed through
            <code>Visualize.Chart.Compiled.tick/3</code>: the static furniture is sent once, the
            mark per update. The old path applies the design and renders one SVG string per update.
          </p>
          <button type="button" phx-click="measure_compiled" class="btn" disabled={@running}>
            Measure 100 updates
          </button>
          <%= if @compiled_measure do %>
            <table class="results-table">
              <thead>
                <tr><th>Path</th><th>Bytes / update</th><th>Before base64</th><th>Static, once</th></tr>
              </thead>
              <tbody>
                <tr>
                  <td>Old: the design rendered as one SVG string per update</td>
                  <td><%= format_bytes(@compiled_measure.old_bytes_per_update) %></td>
                  <td>-</td>
                  <td>-</td>
                </tr>
                <tr>
                  <td>Compiled, <code>render: :svg</code></td>
                  <td><%= format_bytes(@compiled_measure.compiled.svg.bytes_per_update) %></td>
                  <td><%= format_bytes(@compiled_measure.compiled.svg.raw_bytes_per_update) %></td>
                  <td><%= format_bytes(@compiled_measure.compiled.svg.static_bytes) %></td>
                </tr>
                <tr>
                  <td>Compiled, <code>render: :binary</code></td>
                  <td><%= format_bytes(@compiled_measure.compiled.binary.bytes_per_update) %></td>
                  <td><%= format_bytes(@compiled_measure.compiled.binary.raw_bytes_per_update) %></td>
                  <td><%= format_bytes(@compiled_measure.compiled.binary.static_bytes) %></td>
                </tr>
              </tbody>
            </table>
            <p class="comparison-note">
              <%= @compiled_measure.data_points %> points, <%= @compiled_measure.updates %> updates.
            </p>
          <% end %>
          <%= if @compiled_results do %>
            <table class="results-table">
              <thead>
                <tr><th>Live run</th><th>FPS</th><th>Render Time</th><th>Payload / update</th><th>Static, once</th></tr>
              </thead>
              <tbody>
                <%= for {backend, r} <- @compiled_results do %>
                  <tr>
                    <td><%= backend %></td>
                    <td><%= Float.round(r.fps, 1) %></td>
                    <td><%= format_time(r.avg_render_time_us) %></td>
                    <td><%= format_bytes(r.avg_payload_bytes) %></td>
                    <td><%= format_bytes(r.static_svg_bytes) %></td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          <% end %>
        </div>
      </div>
    </main>

    <style>
      .performance-container {
        display: grid;
        grid-template-columns: 300px 1fr;
        grid-template-rows: auto auto auto;
        gap: 1.5rem;
        max-width: 1200px;
        margin: 0 auto;
      }

      .controls-panel {
        background: #f8f9fa;
        padding: 1.5rem;
        border-radius: 8px;
        grid-row: span 3;
      }

      .controls-panel h3 {
        margin-top: 0;
        margin-bottom: 1rem;
        color: #333;
      }

      .control-group {
        margin-bottom: 1.5rem;
      }

      .control-group label {
        display: block;
        font-weight: 600;
        color: #555;
        margin-bottom: 0.5rem;
        font-size: 14px;
      }

      .button-group {
        display: flex;
        flex-wrap: wrap;
        gap: 0.5rem;
        max-width: 320px;
      }

      .btn {
        padding: 0.5rem 1rem;
        border: 2px solid #ddd;
        border-radius: 6px;
        background: white;
        cursor: pointer;
        font-weight: 500;
        transition: all 0.2s;
      }

      .btn:hover:not(:disabled) {
        border-color: #999;
      }

      .btn.active {
        background: #4e79a7;
        border-color: #4e79a7;
        color: white;
      }

      .btn:disabled {
        opacity: 0.5;
        cursor: not-allowed;
      }

      .btn.start {
        background: #10b981;
        border-color: #10b981;
        color: white;
        width: 100%;
      }

      .btn.stop {
        background: #ef4444;
        border-color: #ef4444;
        color: white;
        width: 100%;
      }

      .btn.benchmark {
        background: #8b5cf6;
        border-color: #8b5cf6;
        color: white;
        width: 100%;
        margin-top: 0.5rem;
      }

      .btn.clear {
        width: 100%;
        margin-top: 0.5rem;
      }

      .action-buttons {
        display: flex;
        flex-direction: column;
      }

      .chart-info-panel {
        background: #f8f9fa;
        padding: 1rem 1.25rem;
        border-radius: 8px;
        grid-column: 2;
      }

      .chart-info-panel h4 {
        margin: 0 0 0.5rem 0;
        font-size: 14px;
        color: #333;
      }

      .chart-description {
        padding: 0.75rem;
        border-radius: 6px;
        border-left: 4px solid #ddd;
        background: white;
      }

      .chart-description.animated {
        border-left-color: #f59e0b;
        background: #fffbeb;
      }

      .chart-description.scrolling {
        border-left-color: #10b981;
        background: #ecfdf5;
      }

      .chart-description.interconnected {
        border-left-color: #ef4444;
        background: #fef2f2;
      }

      .chart-description.layered {
        border-left-color: #8b5cf6;
        background: #f5f3ff;
      }

      .chart-description p {
        margin: 0.5rem 0 0 0;
        color: #555;
        font-size: 13px;
        line-height: 1.5;
      }

      .tag {
        display: inline-block;
        font-size: 11px;
        padding: 3px 8px;
        border-radius: 4px;
        font-weight: 600;
      }

      .tag.animated {
        background: #fef3c7;
        color: #92400e;
      }

      .tag.scrolling {
        background: #d1fae5;
        color: #065f46;
      }

      .tag.interconnected {
        background: #fee2e2;
        color: #991b1b;
      }

      .tag.layered {
        background: #ede9fe;
        color: #5b21b6;
      }

      input[type="range"] {
        width: 100%;
        height: 6px;
        -webkit-appearance: none;
        appearance: none;
        background: #ddd;
        border-radius: 3px;
        outline: none;
      }

      input[type="range"]::-webkit-slider-thumb {
        -webkit-appearance: none;
        width: 18px;
        height: 18px;
        background: #4e79a7;
        border-radius: 50%;
        cursor: pointer;
      }

      .metrics-panel {
        background: #f8f9fa;
        padding: 1.5rem;
        border-radius: 8px;
      }

      .metrics-panel h3 {
        margin-top: 0;
        margin-bottom: 1rem;
        color: #333;
      }

      .metric {
        display: flex;
        justify-content: space-between;
        padding: 0.5rem 0;
        border-bottom: 1px solid #eee;
      }

      .metric.highlight {
        background: #e0f2fe;
        padding: 0.75rem;
        margin: 0 -1rem;
        border-radius: 6px;
        border: none;
      }

      .metric.highlight .value {
        font-size: 1.5rem;
        color: #0369a1;
      }

      .metric .label {
        color: #666;
        font-size: 14px;
      }

      .metric .value {
        font-weight: 600;
        font-family: monospace;
        color: #333;
      }

      .comparison-panel {
        grid-column: span 2;
        background: #f0fdf4;
        padding: 1.5rem;
        border-radius: 8px;
      }

      .comparison-panel h3 {
        margin-top: 0;
        color: #166534;
      }

      .results-table {
        width: 100%;
        border-collapse: collapse;
      }

      .results-table th,
      .results-table td {
        padding: 0.75rem;
        text-align: left;
        border-bottom: 1px solid #ddd;
      }

      .results-table th {
        background: #dcfce7;
        font-weight: 600;
        color: #166534;
      }

      .results-table td:last-child {
        font-weight: 600;
        color: #166534;
      }

      .comparison-note {
        margin-top: 1rem;
        font-size: 13px;
        color: #555;
      }

      .chart-panel {
        grid-column: 2;
        background: white;
        padding: 1.5rem;
        border-radius: 8px;
        border: 1px solid #eee;
      }

      .chart-panel h3 {
        margin-top: 0;
        color: #333;
      }

      .chart-container {
        display: flex;
        justify-content: center;
        min-height: 400px;
        background: #fafafa;
        border-radius: 8px;
        overflow: hidden;
      }

      .canvas-output {
        width: 100%;
        padding: 1rem;
        overflow: auto;
        max-height: 400px;
      }

      .canvas-output pre {
        margin: 0;
        font-size: 11px;
        white-space: pre-wrap;
        word-break: break-all;
      }
    </style>
    """
  end

  defp format_time(us) when us < 1000, do: "#{Float.round(us, 1)} μs"
  defp format_time(us), do: "#{Float.round(us / 1000, 2)} ms"

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / 1024 / 1024, 2)} MB"

  # Chart type helpers for description panel
  defp chart_type_label(:line), do: "Line"
  defp chart_type_label(:area), do: "Area"
  defp chart_type_label(:scatter), do: "Scatter"
  defp chart_type_label(:multi_line), do: "Multi-Line"
  defp chart_type_label(:ridgeline), do: "Ridgeline"
  defp chart_type_label(:chord), do: "Chord"

  defp chart_type_class(:multi_line), do: "scrolling"
  defp chart_type_class(:chord), do: "interconnected"
  defp chart_type_class(:ridgeline), do: "layered"
  defp chart_type_class(_), do: "animated"

  defp chart_type_tag(:multi_line), do: "Scrolling"
  defp chart_type_tag(:chord), do: "Interconnected"
  defp chart_type_tag(:ridgeline), do: "Layered"
  defp chart_type_tag(_), do: "Animated"

  defp chart_type_description(:line), do: "Phase-shifting sine wave. All data changes each frame - incremental mode renders full data in exposed region."
  defp chart_type_description(:area), do: "Filled area chart. Same animation model as Line - incremental provides visual effect but not true optimization."
  defp chart_type_description(:scatter), do: "Orbiting points. All positions change each frame - requires full re-render for accuracy."
  defp chart_type_description(:multi_line), do: "48 scrolling ridgelines. Ideal for incremental - only new right-edge data is rendered, existing content is shifted."
  defp chart_type_description(:ridgeline), do: "48 overlapping density curves. Layered rendering with occlusion - partial incremental possible but layers complicate clipping."
  defp chart_type_description(:chord), do: "Relationship diagram. Not suitable for incremental - all elements are interconnected, clipping would break visual coherence."

  defp format_number(n) when n < 1000, do: "#{n}"
  defp format_number(n) when n < 1_000_000, do: "#{Float.round(n / 1000, 1)}K"
  defp format_number(n), do: "#{Float.round(n / 1_000_000, 2)}M"

  defp format_ratio(nil, _, _), do: "-"
  defp format_ratio(_, nil, _), do: "-"
  defp format_ratio(svg, canvas, field, invert \\ false) do
    svg_val = Map.get(svg, field)
    canvas_val = Map.get(canvas, field)

    if svg_val > 0 and canvas_val > 0 do
      ratio = if invert do
        svg_val / canvas_val
      else
        canvas_val / svg_val
      end

      if ratio > 1 do
        "Canvas #{Float.round(ratio, 1)}x faster"
      else
        "SVG #{Float.round(1/ratio, 1)}x faster"
      end
    else
      "-"
    end
  end

  defp format_throughput_ratio(nil, _), do: "-"
  defp format_throughput_ratio(_, nil), do: "-"
  defp format_throughput_ratio(svg, canvas) do
    svg_throughput = svg.fps * svg.data_points
    canvas_throughput = canvas.fps * canvas.data_points

    if svg_throughput > 0 and canvas_throughput > 0 do
      ratio = canvas_throughput / svg_throughput

      if ratio > 1 do
        "Canvas #{Float.round(ratio, 1)}x more"
      else
        "SVG #{Float.round(1/ratio, 1)}x more"
      end
    else
      "-"
    end
  end

  defp fastest_of_three(svg, canvas, hybrid, field, lower_is_better \\ false) do
    candidates = [
      svg && {:svg, Map.get(svg, field)},
      canvas && {:canvas, Map.get(canvas, field)},
      hybrid && {:hybrid, Map.get(hybrid, field)}
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.reject(fn {_, v} -> is_nil(v) or v == 0 end)

    case candidates do
      [] -> "-"
      list ->
        {name, _val} = if lower_is_better do
          Enum.min_by(list, fn {_, v} -> v end)
        else
          Enum.max_by(list, fn {_, v} -> v end)
        end
        format_backend_name(name)
    end
  end

  defp fastest_of_five(svg, canvas, hybrid, canvas_inc, hybrid_inc, field, lower_is_better \\ false) do
    candidates = [
      svg && {:svg, Map.get(svg, field)},
      canvas && {:canvas, Map.get(canvas, field)},
      hybrid && {:hybrid, Map.get(hybrid, field)},
      canvas_inc && {:canvas_inc, Map.get(canvas_inc, field)},
      hybrid_inc && {:hybrid_inc, Map.get(hybrid_inc, field)}
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.reject(fn {_, v} -> is_nil(v) or v == 0 end)

    case candidates do
      [] -> "-"
      list ->
        {name, _val} = if lower_is_better do
          Enum.min_by(list, fn {_, v} -> v end)
        else
          Enum.max_by(list, fn {_, v} -> v end)
        end
        format_backend_name(name)
    end
  end

  defp throughput_winner(svg, canvas, hybrid) do
    candidates = [
      svg && {:svg, svg.fps * svg.data_points},
      canvas && {:canvas, canvas.fps * canvas.data_points},
      hybrid && {:hybrid, hybrid.fps * hybrid.data_points}
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.reject(fn {_, v} -> v == 0 end)

    case candidates do
      [] -> "-"
      list ->
        {name, _val} = Enum.max_by(list, fn {_, v} -> v end)
        format_backend_name(name)
    end
  end

  defp throughput_winner_five(svg, canvas, hybrid, canvas_inc, hybrid_inc) do
    candidates = [
      svg && {:svg, svg.fps * svg.data_points},
      canvas && {:canvas, canvas.fps * canvas.data_points},
      hybrid && {:hybrid, hybrid.fps * hybrid.data_points},
      canvas_inc && {:canvas_inc, canvas_inc.fps * canvas_inc.data_points},
      hybrid_inc && {:hybrid_inc, hybrid_inc.fps * hybrid_inc.data_points}
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.reject(fn {_, v} -> v == 0 end)

    case candidates do
      [] -> "-"
      list ->
        {name, _val} = Enum.max_by(list, fn {_, v} -> v end)
        format_backend_name(name)
    end
  end

  defp format_backend_name(:svg), do: "SVG"
  defp format_backend_name(:canvas), do: "Canvas"
  defp format_backend_name(:hybrid), do: "Hybrid"
  defp format_backend_name(:canvas_inc), do: "Canvas-Inc"
  defp format_backend_name(:hybrid_inc), do: "Hybrid-Inc"

  # Hybrid mode: render data only (no axes) using Canvas backend
  defp render_data_only(chart_type, data, width, height) do
    margin = %{top: 20, right: 20, bottom: 30, left: 40}
    inner_width = width - margin.left - margin.right
    inner_height = height - margin.top - margin.bottom

    {x_scale, y_scale} = build_data_scales(chart_type, data, inner_width, inner_height)

    element = case chart_type do
      :line ->
        line = Shape.Line.new()
          |> Shape.Line.x(fn d -> Scale.Linear.apply(x_scale, d.x) end)
          |> Shape.Line.y(fn d -> Scale.Linear.apply(y_scale, d.y) end)
          |> Shape.Line.curve(:monotone_x)

        path = Shape.Line.generate_path(line, data)
        Element.path(path, %{stroke: "#4e79a7", stroke_width: 2, fill: :none})
          |> Element.set_transform(Visualize.IR.Transform.translate(margin.left, margin.top))

      :area ->
        area = Shape.Area.new()
          |> Shape.Area.x(fn d -> Scale.Linear.apply(x_scale, d.x) end)
          |> Shape.Area.y0(fn _ -> inner_height end)
          |> Shape.Area.y1(fn d -> Scale.Linear.apply(y_scale, d.y) end)
          |> Shape.Area.curve(:monotone_x)

        path = Shape.Area.generate_path(area, data)
        Element.path(path, %{fill: "#4e79a7", fill_opacity: 0.7, stroke: "#4e79a7"})
          |> Element.set_transform(Visualize.IR.Transform.translate(margin.left, margin.top))

      :scatter ->
        circles = Enum.map(data, fn d ->
          Element.circle(
            Scale.Linear.apply(x_scale, d.x),
            Scale.Linear.apply(y_scale, d.y),
            d.r,
            %{fill: "#4e79a7", fill_opacity: 0.6}
          )
        end)
        Element.group(circles)
          |> Element.set_transform(Visualize.IR.Transform.translate(margin.left, margin.top))
    end

    Visualize.Backend.Canvas.render_element(element, format: :json)
    |> IO.iodata_to_binary()
  end

  # Binary version for hybrid mode - ~60% smaller than JSON
  defp render_data_only_binary(chart_type, data, width, height) do
    margin = %{top: 20, right: 20, bottom: 30, left: 40}
    inner_width = width - margin.left - margin.right
    inner_height = height - margin.top - margin.bottom

    {x_scale, y_scale} = build_data_scales(chart_type, data, inner_width, inner_height)

    element = case chart_type do
      :line ->
        line = Shape.Line.new()
          |> Shape.Line.x(fn d -> Scale.Linear.apply(x_scale, d.x) end)
          |> Shape.Line.y(fn d -> Scale.Linear.apply(y_scale, d.y) end)
          |> Shape.Line.curve(:monotone_x)

        path = Shape.Line.generate_path(line, data)
        Element.path(path, %{stroke: "#4e79a7", stroke_width: 2, fill: :none})
          |> Element.set_transform(Visualize.IR.Transform.translate(margin.left, margin.top))

      :area ->
        area = Shape.Area.new()
          |> Shape.Area.x(fn d -> Scale.Linear.apply(x_scale, d.x) end)
          |> Shape.Area.y0(fn _ -> inner_height end)
          |> Shape.Area.y1(fn d -> Scale.Linear.apply(y_scale, d.y) end)
          |> Shape.Area.curve(:monotone_x)

        path = Shape.Area.generate_path(area, data)
        Element.path(path, %{fill: "#4e79a7", fill_opacity: 0.7, stroke: "#4e79a7"})
          |> Element.set_transform(Visualize.IR.Transform.translate(margin.left, margin.top))

      :scatter ->
        circles = Enum.map(data, fn d ->
          Element.circle(
            Scale.Linear.apply(x_scale, d.x),
            Scale.Linear.apply(y_scale, d.y),
            d.r,
            %{fill: "#4e79a7", fill_opacity: 0.6}
          )
        end)
        Element.group(circles)
          |> Element.set_transform(Visualize.IR.Transform.translate(margin.left, margin.top))

      :multi_line ->
        # data is scrolling_data (list of lists) - ridgeline style with 48 lines
        count = length(hd(data))
        num_ridges = length(data)
        ridge_spacing = inner_height / num_ridges
        ridge_height = ridge_spacing * 3

        ml_x_scale = Scale.Linear.new() |> Scale.Linear.domain([0, count - 1]) |> Scale.Linear.range([0, inner_width])

        ridge_elements = data
        |> Enum.with_index()
        |> Enum.map(fn {line_data, idx} ->
          y_offset = inner_height - (idx + 1) * ridge_spacing

          ml_y_scale = Scale.Linear.new() |> Scale.Linear.domain([0, 100]) |> Scale.Linear.range([ridge_height, 0])

          line_points = line_data |> Enum.with_index() |> Enum.map(fn {y, i} -> %{x: i, y: y} end)

          line = Shape.Line.new()
            |> Shape.Line.x(fn d -> Scale.Linear.apply(ml_x_scale, d.x) end)
            |> Shape.Line.y(fn d -> Scale.Linear.apply(ml_y_scale, d.y) end)

          path = Shape.Line.generate_path(line, line_points)

          color = interpolate_purple_orange(idx / max(1, num_ridges - 1))

          line_element = Element.path(path, %{fill: :none, stroke: color, stroke_width: 1.5})
          Element.group([line_element], transform: Visualize.IR.Transform.translate(0, y_offset))
        end)
        Element.group(ridge_elements)
          |> Element.set_transform(Visualize.IR.Transform.translate(margin.left, margin.top))

      :ridgeline ->
        # Ridgeline uses layered lines
        build_ridgeline_data_element(data, width, height)

      :chord ->
        # For chord, build the full diagram (can't be split)
        build_chord_data_element(data, width, height)
    end

    # Use binary_base64 format for compact encoding
    Visualize.Backend.Canvas.render_element(element, format: :binary_base64)
  end

  # Build ridgeline elements for hybrid/incremental modes (48 lines)
  defp build_ridgeline_data_element(ridges_data, width, height) do
    margin = %{top: 10, right: 20, bottom: 10, left: 40}
    inner_width = width - margin.left - margin.right
    inner_height = height - margin.top - margin.bottom

    num_ridges = length(ridges_data)

    # Calculate spacing to fill vertical space evenly
    ridge_spacing = inner_height / num_ridges
    ridge_height = ridge_spacing * 3  # Allow ridges to overlap visually

    x_scale = Scale.Linear.new()
      |> Scale.Linear.domain([0, 100])
      |> Scale.Linear.range([0, inner_width])

    ridge_elements = ridges_data
    |> Enum.with_index()
    |> Enum.map(fn {ridge_data, idx} ->
      # Position from bottom to top
      y_offset = inner_height - (idx + 1) * ridge_spacing

      y_scale = Scale.Linear.new()
        |> Scale.Linear.domain([0, 80])
        |> Scale.Linear.range([ridge_height, 0])

      line = Shape.Line.new()
        |> Shape.Line.x(fn d -> Scale.Linear.apply(x_scale, d.x) end)
        |> Shape.Line.y(fn d -> Scale.Linear.apply(y_scale, d.y) end)

      path = Shape.Line.generate_path(line, ridge_data)

      # Interpolate from deep purple (bottom) to orange (top)
      color = interpolate_purple_orange(idx / max(1, num_ridges - 1))

      line_element = Element.path(path, %{
        fill: :none,
        stroke: color,
        stroke_width: 1.5
      })

      Element.group([line_element],
        transform: Visualize.IR.Transform.translate(0, y_offset)
      )
    end)

    Element.group(ridge_elements)
      |> Element.set_transform(Visualize.IR.Transform.translate(margin.left, margin.top))
  end

  # Build chord diagram elements for hybrid/incremental modes
  defp build_chord_data_element(matrix, width, height) do
    cx = width / 2
    cy = height / 2
    outer_radius = min(width, height) / 2 - 40
    inner_radius = outer_radius - 20

    num_groups = length(matrix)
    row_totals = Enum.map(matrix, &Enum.sum/1)
    grand_total = Enum.sum(row_totals)

    {group_arcs, _} = row_totals
    |> Enum.with_index()
    |> Enum.map_reduce(0, fn {total, idx}, start_angle ->
      angle_span = if grand_total > 0, do: (total / grand_total) * 2 * :math.pi() * 0.95, else: 0
      end_angle = start_angle + angle_span
      gap = 2 * :math.pi() * 0.05 / num_groups
      {{idx, start_angle, end_angle}, end_angle + gap}
    end)

    group_elements = Enum.map(group_arcs, fn {idx, start_angle, end_angle} ->
      color = Enum.at(@line_colors, rem(idx, length(@line_colors)))
      arc_path = build_arc_path(cx, cy, inner_radius, outer_radius, start_angle, end_angle)
      Element.path(arc_path, %{fill: color, fill_opacity: 0.8})
    end)

    chord_elements = build_chord_elements(matrix, group_arcs, cx, cy, inner_radius)
    Element.group(group_elements ++ chord_elements)
  end

  # Render full chart for first frame of incremental modes
  defp render_full_for_incremental(backend, chart_type, data, width, height) do
    element = build_chart(chart_type, data, width, height)

    # For hybrid mode, we only render the data element (axes are static SVG)
    element = if backend == :hybrid_incremental do
      inner_width = width - @margin.left - @margin.right
      inner_height = height - @margin.top - @margin.bottom
      {x_scale, y_scale} = build_data_scales(chart_type, data, inner_width, inner_height)
      build_data_element(chart_type, data, x_scale, y_scale, inner_height)
    else
      element
    end

    CanvasIncremental.encode_full_redraw(element)
    |> Base.encode64()
  end

  # Incremental rendering: only render exposed region for scrolling charts
  # NOTE: For animated (phase-shifting) data, we render the full data in the exposed region
  # because the visual content changes every frame. True incremental optimization
  # works best with scrolling data where only edge data is new.
  defp render_incremental(mode, chart_type, data, width, height) do
    inner_width = width - @margin.left - @margin.right
    inner_height = height - @margin.top - @margin.bottom
    canvas_size = {width, height}

    # Use inner dimensions for exposed region calculation (like high_performance_live)
    inner_size = {inner_width, inner_height}

    {x_scale, y_scale} = build_data_scales(chart_type, data, inner_width, inner_height)

    # Calculate exposed region relative to inner chart area
    regions = CanvasIncremental.exposed_regions({@scroll_delta, 0}, inner_size)

    # Adjust region coordinates to account for margins
    adjusted_regions = Enum.map(regions, fn {rx, ry, rw, rh} ->
      {@margin.left + rx, @margin.top + ry, rw, rh}
    end)

    region_elements = Enum.map(adjusted_regions, fn bounds ->
      # Render full chart data - client-side clipping shows only the exposed region.
      # Note: For animated data (phase-shifting), all values change each frame,
      # so we render the full dataset. True incremental optimization requires
      # scrolling data where only edge data is new (see high_performance_live).
      element = build_data_element(chart_type, data, x_scale, y_scale, inner_height)

      # For canvas mode, wrap in root element
      element = if mode == :canvas do
        Element.root(width, height, children: [element])
      else
        element
      end

      {bounds, element}
    end)

    # The plot is what scrolls; the margin's axes stay (D-106)
    CanvasIncremental.encode_incremental({@scroll_delta, 0}, canvas_size, region_elements,
      viewport: {@margin.left, @margin.top, inner_width, inner_height}
    )
    |> Base.encode64()
  end

  # True incremental rendering for multi-line scrolling chart (ridgeline style, 48 lines)
  # Only renders the data points in the newly exposed region (right edge)
  # pixel_shift is the exact pixel amount that corresponds to the data shift
  defp render_multiline_incremental(mode, scrolling_data, width, height, pixel_shift) do
    margin = %{top: 0, right: 0, bottom: 0, left: 0}
    inner_width = width - margin.left - margin.right
    inner_height = height - margin.top - margin.bottom
    canvas_size = {width, height}
    inner_size = {inner_width, inner_height}

    count = length(hd(scrolling_data))
    num_ridges = length(scrolling_data)

    # Calculate spacing to fill vertical space evenly
    ridge_spacing = inner_height / num_ridges
    ridge_height = ridge_spacing * 3  # Allow ridges to overlap visually

    x_scale = Scale.Linear.new()
      |> Scale.Linear.domain([0, count - 1])
      |> Scale.Linear.range([0, inner_width])

    # Calculate exposed region relative to inner chart area
    regions = CanvasIncremental.exposed_regions({pixel_shift, 0}, inner_size)

    # Only draw the data points in the newly exposed region (right edge)
    # This prevents smearing caused by overlapping with shifted bitmap content
    points_per_pixel = (count - 1) / inner_width
    region_elements = Enum.map(regions, fn {inner_rx, inner_ry, inner_rw, inner_rh} ->
      # Calculate which data indices fall in the exposed region
      # Add a small buffer on the left to ensure line segments connect properly
      pixel_start = max(0, inner_rx - 2)
      pixel_end = inner_rx + inner_rw

      start_idx = max(0, floor(pixel_start * points_per_pixel) - 1)
      end_idx = min(count - 1, ceil(pixel_end * points_per_pixel) + 1)

      # Clip to the exposed region (in canvas coordinates with margin offset)
      # This prevents drawing over the shifted bitmap content
      bounds = {margin.left + inner_rx, margin.top + inner_ry, inner_rw, inner_rh}

      # Build ridgeline elements for ONLY the data in this region
      ridge_elements = scrolling_data
      |> Enum.with_index()
      |> Enum.map(fn {line_data, idx} ->
        # Position from bottom to top
        y_offset = inner_height - (idx + 1) * ridge_spacing

        y_scale = Scale.Linear.new()
          |> Scale.Linear.domain([0, 100])
          |> Scale.Linear.range([ridge_height, 0])

        region_data = line_data
        |> Enum.slice(start_idx..end_idx)
        |> Enum.with_index(start_idx)
        |> Enum.map(fn {y, i} -> %{x: i, y: y} end)

        if length(region_data) >= 2 do
          # Use linear interpolation for incremental rendering - curves don't align
          # with shifted bitmap content due to B-spline's dependency on surrounding points
          line = Shape.Line.new()
            |> Shape.Line.x(fn d -> Scale.Linear.apply(x_scale, d.x) end)
            |> Shape.Line.y(fn d -> Scale.Linear.apply(y_scale, d.y) end)

          path = Shape.Line.generate_path(line, region_data)

          # Interpolate from deep purple (bottom) to orange (top)
          color = interpolate_purple_orange(idx / max(1, num_ridges - 1))

          line_element = Element.path(path, %{fill: :none, stroke: color, stroke_width: 1.5})
          Element.group([line_element], transform: Visualize.IR.Transform.translate(0, y_offset))
        else
          nil
        end
      end)
      |> Enum.reject(&is_nil/1)

      element = Element.group(ridge_elements)
        |> Element.set_transform(Visualize.IR.Transform.translate(margin.left, margin.top))

      element = if mode == :canvas do
        Element.root(width, height, children: [element])
      else
        element
      end

      {bounds, element}
    end)

    # The plot is what scrolls; the margin's axes stay (D-106)
    CanvasIncremental.encode_incremental({pixel_shift, 0}, canvas_size, region_elements,
      viewport: {margin.left, margin.top, inner_width, inner_height}
    )
    |> Base.encode64()
  end

  defp build_data_element(:line, data, x_scale, y_scale, _inner_height) do
    line = Shape.Line.new()
      |> Shape.Line.x(fn d -> Scale.Linear.apply(x_scale, d.x) end)
      |> Shape.Line.y(fn d -> Scale.Linear.apply(y_scale, d.y) end)
      |> Shape.Line.curve(:monotone_x)

    path = Shape.Line.generate_path(line, data)
    Element.path(path, %{stroke: "#4e79a7", stroke_width: 2, fill: :none})
      |> Element.set_transform(Visualize.IR.Transform.translate(@margin.left, @margin.top))
  end

  defp build_data_element(:area, data, x_scale, y_scale, inner_height) do
    area = Shape.Area.new()
      |> Shape.Area.x(fn d -> Scale.Linear.apply(x_scale, d.x) end)
      |> Shape.Area.y0(fn _ -> inner_height end)
      |> Shape.Area.y1(fn d -> Scale.Linear.apply(y_scale, d.y) end)
      |> Shape.Area.curve(:monotone_x)

    path = Shape.Area.generate_path(area, data)
    Element.path(path, %{fill: "#4e79a7", fill_opacity: 0.7, stroke: "#4e79a7"})
      |> Element.set_transform(Visualize.IR.Transform.translate(@margin.left, @margin.top))
  end

  defp build_data_element(:scatter, data, x_scale, y_scale, _inner_height) do
    circles = Enum.map(data, fn d ->
      Element.circle(
        Scale.Linear.apply(x_scale, d.x),
        Scale.Linear.apply(y_scale, d.y),
        Map.get(d, :r, 3),
        %{fill: "#4e79a7", fill_opacity: 0.6}
      )
    end)
    Element.group(circles)
      |> Element.set_transform(Visualize.IR.Transform.translate(@margin.left, @margin.top))
  end

  defp build_data_element(:multi_line, scrolling_data, _x_scale, _y_scale, _inner_height) do
    # Ridgeline style for multi_line with 48 lines
    count = length(hd(scrolling_data))
    num_ridges = length(scrolling_data)
    inner_width = 700 - 40 - 20  # margin.left=40, margin.right=20
    inner_height = 400 - 10 - 10  # margin.top=10, margin.bottom=10

    # Calculate spacing to fill vertical space evenly
    ridge_spacing = inner_height / num_ridges
    ridge_height = ridge_spacing * 3  # Allow ridges to overlap visually

    ml_x_scale = Scale.Linear.new() |> Scale.Linear.domain([0, count - 1]) |> Scale.Linear.range([0, inner_width])

    ridge_elements = scrolling_data
    |> Enum.with_index()
    |> Enum.map(fn {line_data, idx} ->
      # Position from bottom to top
      y_offset = inner_height - (idx + 1) * ridge_spacing

      ml_y_scale = Scale.Linear.new() |> Scale.Linear.domain([0, 100]) |> Scale.Linear.range([ridge_height, 0])

      data = line_data |> Enum.with_index() |> Enum.map(fn {y, i} -> %{x: i, y: y} end)

      line = Shape.Line.new()
        |> Shape.Line.x(fn d -> Scale.Linear.apply(ml_x_scale, d.x) end)
        |> Shape.Line.y(fn d -> Scale.Linear.apply(ml_y_scale, d.y) end)

      path = Shape.Line.generate_path(line, data)

      # Interpolate from deep purple (bottom) to orange (top)
      color = interpolate_purple_orange(idx / max(1, num_ridges - 1))

      line_element = Element.path(path, %{fill: :none, stroke: color, stroke_width: 1.5})
      Element.group([line_element], transform: Visualize.IR.Transform.translate(0, y_offset))
    end)
    Element.group(ridge_elements)
      |> Element.set_transform(Visualize.IR.Transform.translate(40, 10))
  end

  defp build_data_element(:ridgeline, ridges_data, _x_scale, _y_scale, _inner_height) do
    # Ridgeline uses its own coordinate system
    build_ridgeline_data_element(ridges_data, 700, 400)
  end

  defp build_data_element(:chord, matrix, _x_scale, _y_scale, _inner_height) do
    # Chord uses its own coordinate system
    build_chord_data_element(matrix, 700, 400)
  end

  defp build_data_scales(:scatter, _data, inner_width, inner_height) do
    x_scale = Scale.Linear.new()
      |> Scale.Linear.domain([0, 100])
      |> Scale.Linear.range([0, inner_width])

    y_scale = Scale.Linear.new()
      |> Scale.Linear.domain([0, 100])
      |> Scale.Linear.range([inner_height, 0])

    {x_scale, y_scale}
  end

  defp build_data_scales(:multi_line, data, inner_width, inner_height) do
    count = length(hd(data))
    x_scale = Scale.Linear.new()
      |> Scale.Linear.domain([0, count - 1])
      |> Scale.Linear.range([0, inner_width])

    y_scale = Scale.Linear.new()
      |> Scale.Linear.domain([0, 100])
      |> Scale.Linear.range([inner_height, 0])

    {x_scale, y_scale}
  end

  defp build_data_scales(:ridgeline, _data, inner_width, inner_height) do
    # Ridgeline uses its own layered coordinate system, return placeholders
    x_scale = Scale.Linear.new() |> Scale.Linear.domain([0, 100]) |> Scale.Linear.range([0, inner_width])
    y_scale = Scale.Linear.new() |> Scale.Linear.domain([0, 80]) |> Scale.Linear.range([inner_height, 0])
    {x_scale, y_scale}
  end

  defp build_data_scales(:chord, _data, inner_width, inner_height) do
    # Chord doesn't use traditional x/y scales, but return placeholders
    x_scale = Scale.Linear.new() |> Scale.Linear.domain([0, 1]) |> Scale.Linear.range([0, inner_width])
    y_scale = Scale.Linear.new() |> Scale.Linear.domain([0, 1]) |> Scale.Linear.range([inner_height, 0])
    {x_scale, y_scale}
  end

  defp build_data_scales(_chart_type, data, inner_width, inner_height) do
    {min_x, max_x} = data |> Enum.map(& &1.x) |> Enum.min_max()
    {min_y, max_y} = data |> Enum.map(& &1.y) |> Enum.min_max()

    x_scale = Scale.Linear.new()
      |> Scale.Linear.domain([min_x, max_x])
      |> Scale.Linear.range([0, inner_width])

    y_scale = Scale.Linear.new()
      |> Scale.Linear.domain([min_y - 5, max_y + 5])
      |> Scale.Linear.range([inner_height, 0])

    {x_scale, y_scale}
  end

  # Render static SVG (axes only) for hybrid mode - called once at start
  defp render_static_svg_for_hybrid(width, height, chart_type, data_points) do
    margin = %{top: 20, right: 20, bottom: 30, left: 40}
    inner_width = width - margin.left - margin.right
    inner_height = height - margin.top - margin.bottom

    # Build scales based on expected data range
    {x_scale, y_scale} = case chart_type do
      :scatter ->
        x = Scale.Linear.new() |> Scale.Linear.domain([0, 100]) |> Scale.Linear.range([0, inner_width])
        y = Scale.Linear.new() |> Scale.Linear.domain([0, 100]) |> Scale.Linear.range([inner_height, 0])
        {x, y}
      _ ->
        # For line/area, estimate domain from data point count
        x = Scale.Linear.new() |> Scale.Linear.domain([0, 100]) |> Scale.Linear.range([0, inner_width])
        y = Scale.Linear.new() |> Scale.Linear.domain([0, 100]) |> Scale.Linear.range([inner_height, 0])
        {x, y}
    end

    alias Visualize.{Axis}
    alias Visualize.IR.{Element, Transform}
    alias Visualize.Backend.SVG

    x_axis = Axis.bottom(x_scale) |> Axis.ticks(10)
    y_axis = Axis.left(y_scale) |> Axis.ticks(5)

    x_axis_element = Axis.generate(x_axis)
    y_axis_element = Axis.generate(y_axis)

    x_axis_group = Element.group([x_axis_element],
      transform: Transform.translate(0, inner_height)
    )

    static_group = Element.group([x_axis_group, y_axis_element],
      transform: Transform.translate(margin.left, margin.top)
    )

    root = Element.root(width, height, children: [static_group])

    SVG.render_element(root, [])
    |> IO.iodata_to_binary()
  end
end
