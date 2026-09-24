defmodule ExamplesWeb.ChartLive do
  use Phoenix.LiveView

  alias Examples.ColorPalettes
  alias Examples.{Compare, Frames, Run}
  alias ExamplesWeb.PerformanceDrawer

  @charts %{
    # Basic Charts
    "bar" => Examples.Charts.BarChart,
    "horizontal_bar" => Examples.Charts.HorizontalBarChart,
    "grouped_bar" => Examples.Charts.GroupedBarChart,
    "stacked_bar" => Examples.Charts.StackedBarChart,
    "line" => Examples.Charts.LineChart,
    "scrolling_series" => Examples.Charts.ScrollingSeries,
    "incremental_line" => Examples.Charts.IncrementalLine,
    "multi_line" => Examples.Charts.MultiLineChart,
    "area" => Examples.Charts.AreaChart,
    "stacked_area" => Examples.Charts.StackedAreaChart,
    "streamgraph" => Examples.Charts.Streamgraph,
    "ridgeline" => Examples.Charts.RidgelinePlot,
    "pie" => Examples.Charts.PieChart,
    "donut" => Examples.Charts.DonutChart,
    "scatter" => Examples.Charts.ScatterPlot,
    "bubble" => Examples.Charts.BubbleChart,
    "radial" => Examples.Charts.RadialBarChart,
    "gauge" => Examples.Charts.GaugeChart,
    "radar" => Examples.Charts.RadarChart,
    "load_gauge" => Examples.Charts.LoadGauge,
    "load_age" => Examples.Charts.LoadAge,
    "polar" => Examples.Charts.PolarTransformChart,
    # Hierarchical Layouts
    "treemap" => Examples.Charts.TreemapChart,
    "circle_pack" => Examples.Charts.CirclePacking,
    "sunburst" => Examples.Charts.SunburstChart,
    "tree" => Examples.Charts.TreeLayout,
    "cluster" => Examples.Charts.ClusterDendrogram,
    # Network/Flow Layouts
    "force" => Examples.Charts.ForceGraph,
    "chord" => Examples.Charts.ChordDiagram,
    "sankey" => Examples.Charts.SankeyDiagram,
    # Scientific
    "contour" => Examples.Charts.ContourPlot,
    "heatmap" => Examples.Charts.Heatmap,
    "hexbin" => Examples.Charts.HexbinChart,
    "spectrum" => Examples.Charts.SpectrumChart,
    # Maps
    "world_map" => Examples.Charts.WorldMap,
    "globe" => Examples.Charts.Globe
  }

  # Charts that support animation
  @doc "The gallery's charts by slug, for the performance view (#328)."
  def charts, do: @charts

  @animatable_charts [
    "bar",
    "horizontal_bar",
    "line",
    "area",
    "pie",
    "donut",
    "scatter",
    "radial",
    "gauge",
    "radar",
    "polar",
    "load_gauge",
    "load_age",
    "multi_line",
    "grouped_bar",
    "stacked_bar",
    "stacked_area",
    "streamgraph",
    "ridgeline",
    "bubble",
    "heatmap",
    "force",
    "contour",
    "sankey",
    "treemap",
    "circle_pack",
    "sunburst",
    "tree",
    "cluster",
    "chord",
    "world_map",
    "globe",
    "hexbin",
    "spectrum"
  ]

  def mount(%{"chart" => chart_slug}, _session, socket) do
    case Map.get(@charts, chart_slug) do
      nil ->
        {:ok, push_navigate(socket, to: "/")}

      module ->
        palettes = ColorPalettes.list_palettes()
        palette_info = ColorPalettes.palette_info()

        {:ok,
         assign(socket,
           module: module,
           slug: chart_slug,
           title: module.title(),
           description: module.description(),
           current_palette: :default,
           palettes: palettes,
           palette_info: palette_info,
           animatable: chart_slug in @animatable_charts,
           hex_radius: 20,
           # The still chart (#362): the last frame rendered outside a run — on mount and on
           # a palette, backend or hex-size change — in a task, with the design as data.
           still_frame: nil,
           still_state: nil,
           still_design: nil,
           still_task: nil,
           # The performance drawer (spec/14 §12.6, #322): a run of this chart on a
           # backend, its frame, the compiled chart's state, and Compare's rows.
           drawer_open: false,
           # A streaming design starts at 600 samples/s per series, as the High-Performance
           # page did, with its window at that density from the moment the drawer opens
           # (#359); any other chart has no rate and no window.
           # Any other chart's rate is ticks per second of its animation, 20 by default, the
           # page's own cadence (#361); the run's tick counter advances by its arrivals.
           run:
             Run.new(
               target_fps: 60,
               data_rate: if(Frames.stream?(module), do: 600, else: 20),
               flow_control: true
             ),
           run_ticks: 0,
           # A chart opens on the backend that makes it worth having (#407): Incremental
           # for a streaming design, Canvas for any other; SVG is a click away.
           run_backend: List.last(Frames.backends(module)),
           run_state: nil,
           run_frame: nil,
           run_mode: nil,
           run_scroll: nil,
           run_series: series(module),
           compare: nil,
           compare_task: nil
         )
         |> then(&assign(&1, run_scroll: fresh_scroll(&1.assigns)))
         |> still()}
    end
  end

  def handle_event("change_palette", %{"palette" => palette_key}, socket) do
    palette =
      case palette_key do
        "default" -> :default
        "sunrise" -> :sunrise
        "winter" -> :winter
        "sunset" -> :sunset
        "fall" -> :fall
        "spring" -> :spring
        "summer" -> :summer
        "dark" -> :dark
        _ -> :default
      end

    {:noreply, socket |> assign(current_palette: palette) |> still()}
  end

  # Animate is the drawer's run on the page's backend (#362): one frame loop.
  def handle_event("toggle_animation", _params, %{assigns: %{run: %Run{running: true}}} = socket),
    do: handle_event("run_stop", %{}, socket)

  def handle_event("toggle_animation", _params, socket),
    do: handle_event("run_start", %{}, socket)

  def handle_event("change_hex_radius", %{"hex_radius" => radius_str}, socket) do
    radius = String.to_integer(radius_str)
    {:noreply, socket |> assign(hex_radius: radius) |> still()}
  end

  # The page's backend buttons and the drawer's are one choice (#362).
  def handle_event("set_backend", params, socket), do: handle_event("run_backend", params, socket)

  # ── the performance drawer ──────────────────────────────────────────────────────────

  def handle_event("drawer_toggle", _params, socket) do
    {:noreply, assign(socket, drawer_open: not socket.assigns.drawer_open)}
  end

  def handle_event(
        "run_backend",
        %{"backend" => backend},
        %{assigns: %{run: %Run{running: false}}} = socket
      ) do
    backend = String.to_existing_atom(backend)
    true = backend in Frames.backends(socket.assigns.module)
    {:noreply, socket |> assign(run_backend: backend) |> still()}
  end

  def handle_event("run_backend", _params, socket), do: {:noreply, socket}

  def handle_event("run_fps", %{"fps" => fps}, socket) do
    {:noreply, update(socket, :run, &%{&1 | target_fps: String.to_integer(fps)})}
  end

  def handle_event("run_flow_control", _params, socket) do
    {:noreply, update(socket, :run, &%{&1 | flow_control: not &1.flow_control})}
  end

  # A run: the page's own animation stops, the backend's state is prepared (a design's
  # compiled chart, once), and the first frame renders.
  def handle_event("run_start", _params, socket) do
    %{module: module, run_backend: backend} = socket.assigns
    socket = update(socket, :run, &Run.cancel/1)
    socket = assign(socket, run_scroll: fresh_scroll(socket.assigns))
    opts = run_opts(socket.assigns, 0)
    # The view keeps the backend's state for its markup — the canvas's size and the static
    # SVG — and the run's renderer keeps its own to draw with (#413).
    state = Frames.prepare(module, opts, backend)

    run =
      Run.start(
        %{
          socket.assigns.run
          | flow_control: socket.assigns.run.flow_control and Frames.acks?(backend)
        },
        System.monotonic_time(:millisecond),
        System.monotonic_time(:microsecond)
      )

    run = Run.renderer(run, module, backend, opts)
    socket = assign(socket, run: run, run_state: state, run_frame: nil, run_ticks: 0)

    if run.running,
      do: {:noreply, socket |> start_frame() |> schedule_run()},
      else: {:noreply, socket}
  end

  # The data rate of a streaming design (#327): its density follows the rate, as the
  # High-Performance page's did — about five seconds of samples across the plot.
  # The rate is live (spec/14 §12.6, #401): a chart that animates by tick takes it from
  # the next tick, and a streaming design keeps its instant — the window is retimed to the
  # new density with its origin carried over, and the next frame is a full redraw, since
  # the copy-shift contract holds only while the density is constant.
  def handle_event("run_data_rate", %{"data_rate" => rate}, socket) do
    socket = update(socket, :run, &%{&1 | data_rate: String.to_integer(rate)})
    %{run: run, run_scroll: scroll} = socket.assigns

    case {run.running, scroll} do
      {true, %Examples.Scroll{} = scroll} ->
        {_x, _y, width, _h} = socket.assigns.module.plot()
        density = Examples.Scroll.density(run.data_rate * 5, width)

        {:noreply,
         socket
         |> assign(run_scroll: Examples.Scroll.retimed(scroll, density))
         |> update(:run, &Run.resync/1)}

      {true, _none} ->
        {:noreply, socket}

      {false, _} ->
        {:noreply, assign(socket, run_scroll: fresh_scroll(socket.assigns))}
    end
  end

  def handle_event("run_data_rate", _params, socket), do: {:noreply, socket}

  def handle_event("run_stop", _params, socket) do
    {:noreply, socket |> update(:run, &Run.stop/1) |> assign(run_frame: nil) |> still()}
  end

  # Compare, headless in a task: a fixed count of ticks per backend.
  def handle_event("run_compare", _params, %{assigns: %{compare_task: nil}} = socket) do
    %{module: module} = socket.assigns
    assigns = socket.assigns
    opts_for = fn tick -> run_opts(assigns, tick) end

    case Run.supervisor() do
      :ok ->
        task =
          Task.Supervisor.async_nolink(Examples.TaskSupervisor, fn ->
            {:compare, Compare.run(module, opts_for, 100)}
          end)

        {:noreply, assign(socket, compare_task: task, compare: nil)}

      {:error, message} ->
        # Fail open with the reason in the drawer (#340).
        {:noreply, update(socket, :run, &%{&1 | error: message})}
    end
  end

  def handle_event("run_compare", _params, socket), do: {:noreply, socket}

  # The hook's ack (spec/10 §8.2).
  def handle_event("frame_drawn", %{"seq" => seq, "drawn" => drawn}, socket) do
    {:noreply,
     update(socket, :run, &Run.acked(&1, seq, drawn, System.monotonic_time(:millisecond)))}
  end

  def handle_info(:run_tick, %{assigns: %{run: %Run{running: false}}} = socket),
    do: {:noreply, socket}

  # A tick of the run: no data rate here, so every frame is the chart at its next
  # animation tick — a full render, decided by the run for flow control's sake.
  def handle_info(:run_tick, socket) do
    now = System.monotonic_time(:millisecond)
    socket = schedule_run(socket)
    %{run_scroll: scroll, run_backend: backend} = socket.assigns
    density = if scroll, do: scroll.samples_per_px, else: 1

    case Run.tick(socket.assigns.run, now, density) do
      {run, :skipped} ->
        {:noreply, assign(socket, run: run)}

      {run, {:draw, columns}} ->
        # A streaming design's window advances by the columns the samples filled, on every
        # backend (#359): Incremental scrolls the compiled chart by exactly those pixels
        # (spec/14 §12.5, §12.6), SVG and Canvas render the full frame of the advanced
        # window. Any other chart's frame is the chart at its next animation tick.
        incremental? = backend == :incremental and scroll != nil
        size = if scroll, do: {scroll.inner_width, 1}, else: {1, 1}
        {run, mode} = Run.decide(run, if(scroll, do: columns, else: 1), incremental?, size, now)
        socket = assign(socket, run: run)

        cond do
          mode == :drop ->
            {:noreply, socket}

          scroll != nil ->
            # The window slides; its rows are the renderer's, slid by these columns (#413).
            socket = assign(socket, run_scroll: Examples.Scroll.advance(scroll, columns))
            {:noreply, start_frame(socket, columns)}

          true ->
            # A chart that animates by tick: the run's tick advances by the arrivals at its
            # rate (density one), whatever the frame rate (#361).
            {:noreply, start_frame(update(socket, :run_ticks, &(&1 + columns)))}
        end
    end
  end

  # A frame's render is back from the run's renderer: numbered, shown or pushed, measured.
  def handle_info({:frame, id, frame}, socket) do
    case Run.result(socket.assigns.run, id) do
      :stale ->
        {:noreply, socket}

      {:ok, %Run{running: false} = run} ->
        {:noreply, assign(socket, run: run)}

      {:ok, run} ->
        now = System.monotonic_time(:millisecond)

        {run, seq} =
          Run.sending(run, if(frame.incremental, do: incremental_mode(frame), else: :full_redraw))

        run = Run.rendered(run, frame.bytes, now)
        mode = if frame.incremental, do: frame.incremental.mode, else: "full"
        socket = assign(socket, run: run, run_frame: frame, run_mode: mode)

        cond do
          frame.incremental ->
            {:noreply,
             push_event(socket, "canvas_incremental", Map.put(frame.incremental, :seq, seq))}

          frame.canvas ->
            {:noreply, push_event(socket, "canvas_update", %{binary: frame.canvas, seq: seq})}

          true ->
            {:noreply, socket}
        end
    end
  end

  def handle_info({ref, {:compare, rows}}, %{assigns: %{compare_task: %Task{ref: ref}}} = socket) do
    Process.demonitor(ref, [:flush])
    {:noreply, assign(socket, compare: rows, compare_task: nil)}
  end

  # The still chart's frame (#362); a superseded one falls to the stale clause below.
  def handle_info(
        {ref, {:still, frame, state, design}},
        %{assigns: %{still_task: %Task{ref: ref}}} = socket
      ) do
    Process.demonitor(ref, [:flush])

    {:noreply,
     assign(socket, still_frame: frame, still_state: state, still_design: design, still_task: nil)}
  end

  def handle_info({ref, _stale}, socket) when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    {:noreply, socket}
  end

  def handle_info(
        {:DOWN, ref, :process, _pid, reason},
        %{assigns: %{still_task: %Task{ref: ref}}} = socket
      ) do
    {:noreply,
     assign(socket, still_task: nil, run: %{socket.assigns.run | error: inspect(reason)})}
  end

  def handle_info(
        {:DOWN, ref, :process, _pid, reason},
        %{assigns: %{compare_task: %Task{ref: ref}}} = socket
      ) do
    {:noreply,
     assign(socket,
       compare_task: nil,
       compare: [],
       run: %{socket.assigns.run | error: inspect(reason)}
     )}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, socket) do
    case Run.down(socket.assigns.run, ref, reason) do
      :stale -> {:noreply, socket}
      {:ok, run} -> {:noreply, assign(socket, run: run, run_frame: nil)}
    end
  end

  # The still chart (#362): one frame of the page's backend at the run's tick, with the
  # design as data — in a task when the socket is connected, so the view answers while
  # it renders; in place on the disconnected first render, which nothing can wait behind.
  defp still(%{assigns: assigns} = socket) do
    %{module: module, run_backend: backend} = assigns
    opts = still_opts(assigns)

    render = fn ->
      state = Frames.prepare(module, opts, backend)
      {frame, state} = Frames.frame(module, opts, backend, state)
      {design, _sources} = module.design(opts)
      {:still, frame, state, inspect(design, pretty: true, limit: :infinity, width: 80)}
    end

    cond do
      not connected?(socket) ->
        {:still, frame, state, design} = render.()
        assign(socket, still_frame: frame, still_state: state, still_design: design)

      match?(:ok, Run.supervisor()) ->
        if task = assigns.still_task,
          do: Task.Supervisor.terminate_child(Examples.TaskSupervisor, task.pid)

        assign(socket, still_task: Task.Supervisor.async_nolink(Examples.TaskSupervisor, render))

      true ->
        {:error, message} = Run.supervisor()
        assign(socket, run: %{assigns.run | error: message})
    end
  end

  # A chart that has not run is at rest; one that has stays at the run's tick.
  defp still_opts(%{run_ticks: ticks} = assigns) when ticks > 0, do: run_opts(assigns, ticks)

  defp still_opts(assigns) do
    if assigns.run_scroll,
      do: run_opts(assigns, 0),
      else: build_chart_opts(assigns.current_palette, 0, false, assigns.slug, assigns.hex_radius)
  end

  defp incremental_mode(%{incremental: %{mode: "full"}}), do: :full_redraw
  defp incremental_mode(%{incremental: %{mode: "none"}}), do: :none
  defp incremental_mode(_frame), do: :scroll_x

  def terminate(_reason, socket) do
    Run.cancel(socket.assigns.run)

    if task = socket.assigns[:compare_task],
      do: Task.Supervisor.terminate_child(Examples.TaskSupervisor, task.pid)

    :ok
  end

  # The frame at the run's next tick, asked of the run's renderer (#413): a streaming
  # design's at its window — whose rows the renderer holds and slides by the columns the
  # tick advanced — any other chart's at its next animation tick.
  defp start_frame(socket, columns \\ 0) do
    opts = run_opts(socket.assigns, socket.assigns.run_ticks) |> Keyword.delete(:rows)
    {run, _id} = Run.asking(socket.assigns.run, opts, columns)
    assign(socket, run: run)
  end

  defp schedule_run(socket) do
    {run, delay} = Run.schedule(socket.assigns.run, System.monotonic_time(:microsecond))
    Process.send_after(self(), :run_tick, delay)
    assign(socket, run: run)
  end

  # The canvas a run draws on: the compiled chart's size for a design, the page's otherwise.
  defp run_size(%{width: w}, :width), do: w
  defp run_size(%{height: h}, :height), do: h
  defp run_size(_state, :width), do: 700
  defp run_size(_state, :height), do: 450

  # A run's frame is the chart at an animation tick, whatever the page's animation; a
  # streaming design's is its window — origin, density, and `now` the window's upper end.
  defp run_opts(%{run_scroll: %Examples.Scroll{} = scroll} = assigns, tick) do
    count = Examples.Scroll.count(scroll)

    assigns.current_palette
    |> build_chart_opts(tick, true, assigns.slug, assigns.hex_radius)
    |> Keyword.merge(
      samples_per_px: scroll.samples_per_px,
      origin: scroll.origin,
      now: scroll.origin + count - 1
    )
  end

  defp run_opts(assigns, tick) do
    build_chart_opts(assigns.current_palette, tick, true, assigns.slug, assigns.hex_radius)
  end

  # The series a streaming design binds — the sources of its design — for the drawer's
  # point counts; nil for any other chart.
  defp series(module) do
    if Frames.stream?(module), do: module.design([]) |> elem(1) |> map_size(), else: nil
  end

  # A streaming design's window at the run's data rate: about five seconds across the plot.
  defp fresh_scroll(%{module: module, run: run}) do
    if Frames.stream?(module) do
      {_x, _y, width, _h} = module.plot()
      Examples.Scroll.new(width, Examples.Scroll.density(run.data_rate * 5, width))
    end
  end

  # The window a streaming design shows, for the drawer.
  defp stream_info(%{run_scroll: %Examples.Scroll{} = scroll, run: run} = assigns) do
    count = Examples.Scroll.count(scroll)

    %{
      samples_per_px: scroll.samples_per_px,
      count: count,
      span: if(run.data_rate > 0, do: count / run.data_rate, else: 0.0),
      series: assigns.run_series,
      points: (assigns.run_frame && assigns.run_frame.points) || 0,
      mode: assigns.run_mode
    }
  end

  defp stream_info(_assigns), do: nil

  # The point metrics of any run (#361): the rows the last frame drew, the rows the chart
  # holds, the points a second moves at the measured rate, the frame's mode — and the
  # slider's unit and span, samples for a streaming design, ticks for any other chart.
  defp points_info(%{run: run, run_frame: frame, run_mode: mode} = assigns) do
    per_frame = (frame && frame.points) || 0

    case stream_info(assigns) do
      nil ->
        %{
          per_frame: per_frame,
          total: per_frame,
          per_second: round(run.measured_rate * per_frame),
          mode: mode,
          unit: "ticks/s",
          rate_label: "Ticks/s",
          min: 1,
          max: 100,
          step: 1
        }

      stream ->
        %{
          per_frame: per_frame,
          total: stream.count * stream.series,
          per_second: round(run.measured_rate * stream.series),
          mode: mode,
          unit: "samples/s per series",
          rate_label: "Samples/s",
          min: 10,
          max: 5000,
          step: 10
        }
    end
  end

  def render(assigns) do
    ~H"""
    <ExamplesWeb.SiteHeader.header tab={:charts} />
    <main>
      <a href="/" class="back-link">
        <span>&larr;</span> Back to Gallery
      </a>

      <div class="chart-detail">
        <h2><%= @title %></h2>
        <p style="color: #666; margin-bottom: 1rem;"><%= @description %></p>

        <div class="controls-row">
          <div class="backend-selector">
            <span class="backend-label">Render Backend:</span>
            <div class="backend-buttons">
              <button
                :for={backend <- Frames.backends(@module)}
                type="button"
                phx-click="set_backend"
                phx-value-backend={backend}
                disabled={@run.running}
                class={"backend-btn #{if @run_backend == backend, do: "active", else: ""}"}
              >
                <%= backend_word(backend) %>
              </button>
            </div>
          </div>

          <div class="palette-selector">
            <span class="palette-label">Color Style:</span>
            <div class="palette-buttons">
              <%= for palette_key <- @palettes do %>
                <% info = @palette_info[palette_key] %>
                <button
                  type="button"
                  phx-click="change_palette"
                  phx-value-palette={Atom.to_string(palette_key)}
                  class={"palette-btn #{if @current_palette == palette_key, do: "active", else: ""}"}
                  title={info.description}
                >
                  <span class="palette-preview">
                    <%= for color <- info.preview do %>
                      <span class="color-dot" style={"background-color: #{color}"}></span>
                    <% end %>
                  </span>
                  <span class="palette-name"><%= info.name %></span>
                </button>
              <% end %>
            </div>
          </div>

          <%= if @animatable do %>
            <div class="animation-control">
              <button
                type="button"
                phx-click="toggle_animation"
                class={"animate-btn #{if @run.running, do: "animating", else: ""}"}
              >
                <%= if @run.running do %>
                  <span class="pulse-dot"></span>
                  Stop Animation
                <% else %>
                  <span class="play-icon">▶</span>
                  Animate Data
                <% end %>
              </button>
              <%= if @run.running do %>
                <span class="tick-counter">Tick: <%= @run_ticks %></span>
              <% end %>
            </div>
          <% end %>

          <%= if @slug == "hexbin" do %>
            <form phx-change="change_hex_radius" class="slider-control">
              <label for="hex-radius-slider">Hex Size: <%= @hex_radius %>px</label>
              <input
                type="range"
                id="hex-radius-slider"
                min="8"
                max="50"
                value={@hex_radius}
                name="hex_radius"
              />
            </form>
          <% end %>
        </div>

        <div class="chart-container" style={"background-color: #{ColorPalettes.background(@current_palette)}"}>
          <%!-- One frame loop (spec/14 §12.6, #362): the run's frame while a run is going, the still one
                otherwise — SVG whole, or the canvas under the compiled chart's static furniture. --%>
          <% {frame, state} = if(@run.running and @run_frame, do: {@run_frame, @run_state}, else: {@still_frame, @still_state}) %>
          <%= cond do %>
            <% frame == nil -> %>
              <p class="chart-pending">rendering…</p>
            <% frame.svg -> %>
              <%= Phoenix.HTML.raw(frame.svg) %>
            <% frame.incremental -> %>
              <%!-- The incremental canvas is the plot area, at the margin's offset (spec/14 §12.5). --%>
              <div class="hybrid-wrapper" style={"position: relative; width: #{run_size(state, :width)}px; height: #{run_size(state, :height)}px;"}>
                <div id="incremental-chart" phx-hook="CanvasIncrementalChart" phx-update="ignore" data-ack="frame_drawn" data-ack-interval="50" data-width={state.plot.width} data-height={state.plot.height} style={"position: absolute; top: #{state.margin.top}px; left: #{state.margin.left}px; z-index: 1;"}>
                  <canvas width={state.plot.width} height={state.plot.height} style="display: block;"></canvas>
                </div>
                <div class="hybrid-static-layer" style="position: absolute; top: 0; left: 0; z-index: 2; pointer-events: none;">
                  <%= Phoenix.HTML.raw(Frames.static(state)) %>
                </div>
                <div :if={frame.dynamic_svg != ""} class="hybrid-dynamic-layer" style="position: absolute; top: 0; left: 0; z-index: 3; pointer-events: none;">
                  <%= Phoenix.HTML.raw(frame.dynamic_svg) %>
                </div>
              </div>
            <% true -> %>
              <div class="hybrid-wrapper" style={"position: relative; width: #{run_size(state, :width)}px; height: #{run_size(state, :height)}px;"}>
                <div id="canvas-chart" phx-hook="CanvasBinaryChart" phx-update="ignore" data-ack="frame_drawn" data-ack-interval="50" data-binary={frame.canvas} data-width={run_size(state, :width)} data-height={run_size(state, :height)} style="position: absolute; top: 0; left: 0; z-index: 1;">
                  <canvas width={run_size(state, :width)} height={run_size(state, :height)} style="display: block;"></canvas>
                </div>
                <div class="hybrid-static-layer" style="position: absolute; top: 0; left: 0; z-index: 2; pointer-events: none;">
                  <%= Phoenix.HTML.raw(Frames.static(state)) %>
                </div>
                <div :if={frame.dynamic_svg != ""} class="hybrid-dynamic-layer" style="position: absolute; top: 0; left: 0; z-index: 3; pointer-events: none;">
                  <%= Phoenix.HTML.raw(frame.dynamic_svg) %>
                </div>
              </div>
          <% end %>
        </div>
        <PerformanceDrawer.performance
          run={@run}
          backend={@run_backend}
          backends={Frames.backends(@module)}
          open={@drawer_open}
          compare={@compare}
          comparing={@compare_task != nil}
          stream={stream_info(assigns)}
          points={points_info(assigns)}
        />

        <h3 style="margin-top: 2rem; margin-bottom: 0.5rem;"><%= backend_code_title(@run_backend) %></h3>
        <p style="color: #666; font-size: 0.9rem; margin-bottom: 0.5rem;">
          The design is the thing to copy: the <code>Visualize.Chart.Build</code> calls below fold to a map,
          and the map is the chart — applied to rows and rendered by the library, on any backend (spec/14 §16).
        </p>
        <pre><code><%= backend_sample_code(@run_backend, @module) %></code></pre>

        <h3 style="margin-top: 2rem; margin-bottom: 0.5rem;">The design (data)</h3>
        <p style="color: #666; font-size: 0.9rem; margin-bottom: 0.5rem;">
          What the Build calls fold to: the stored form the builder and a host exchange (spec/14 §1, §9).
          <code>Visualize.Chart.to_json/1</code> is the same map as JSON.
        </p>
        <pre><code><%= @still_design || "rendering…" %></code></pre>

        <%= if @animatable do %>
          <h3 style="margin-top: 2rem; margin-bottom: 0.5rem;">LiveView Animation Code</h3>
          <pre><code><%= animation_sample_code(@run_backend) %></code></pre>
        <% end %>
      </div>
    </main>

    <style>
      <%= Phoenix.HTML.raw(PerformanceDrawer.css()) %>
      .controls-row {
        display: flex;
        flex-wrap: wrap;
        align-items: flex-start;
        gap: 1.5rem;
        margin-bottom: 1rem;
      }

      .backend-selector {
        display: flex;
        align-items: center;
        gap: 0.5rem;
      }

      .backend-label {
        font-weight: 600;
        color: #444;
        margin-right: 0.5rem;
      }

      .backend-buttons {
        display: flex;
        gap: 0.25rem;
      }

      .backend-btn {
        padding: 0.5rem 1rem;
        border: 2px solid #ddd;
        background: white;
        cursor: pointer;
        font-weight: 500;
        font-size: 13px;
        transition: all 0.2s ease;
      }

      .backend-btn:first-child {
        border-radius: 6px 0 0 6px;
      }

      .backend-btn:last-child {
        border-radius: 0 6px 6px 0;
      }

      .backend-btn:not(:first-child):not(:last-child) {
        border-radius: 0;
      }

      .backend-btn:not(:first-child) {
        border-left: 1px solid #ddd;
      }

      .backend-btn:hover {
        background: #f5f5f5;
        border-color: #999;
      }

      .backend-btn.active {
        background: #4e79a7;
        border-color: #4e79a7;
        color: white;
      }

      .backend-btn.active:hover {
        background: #3d6089;
        border-color: #3d6089;
      }

      .palette-selector {
        display: flex;
        align-items: center;
        flex-wrap: wrap;
        gap: 0.5rem;
      }

      .palette-label {
        font-weight: 600;
        color: #444;
        margin-right: 0.5rem;
      }

      .palette-buttons {
        display: flex;
        flex-wrap: wrap;
        gap: 0.5rem;
      }

      .palette-btn {
        display: flex;
        flex-direction: column;
        align-items: center;
        padding: 0.5rem 0.75rem;
        border: 2px solid #ddd;
        border-radius: 8px;
        background: white;
        cursor: pointer;
        transition: all 0.2s ease;
      }

      .palette-btn:hover {
        border-color: #999;
        transform: translateY(-2px);
        box-shadow: 0 4px 8px rgba(0,0,0,0.1);
      }

      .palette-btn.active {
        border-color: #4e79a7;
        background: #f0f7ff;
        box-shadow: 0 0 0 2px rgba(78, 121, 167, 0.2);
      }

      .palette-preview {
        display: flex;
        gap: 2px;
        margin-bottom: 4px;
      }

      .color-dot {
        width: 12px;
        height: 12px;
        border-radius: 2px;
        border: 1px solid rgba(0,0,0,0.1);
      }

      .palette-name {
        font-size: 11px;
        color: #666;
        font-weight: 500;
      }

      .palette-btn.active .palette-name {
        color: #4e79a7;
        font-weight: 600;
      }

      .animation-control {
        display: flex;
        align-items: center;
        gap: 1rem;
      }

      .animate-btn {
        display: flex;
        align-items: center;
        gap: 0.5rem;
        padding: 0.6rem 1.2rem;
        border: 2px solid #10b981;
        border-radius: 8px;
        background: white;
        color: #10b981;
        font-weight: 600;
        font-size: 14px;
        cursor: pointer;
        transition: all 0.2s ease;
      }

      .animate-btn:hover {
        background: #10b981;
        color: white;
        transform: translateY(-2px);
        box-shadow: 0 4px 12px rgba(16, 185, 129, 0.3);
      }

      .animate-btn.animating {
        background: #ef4444;
        border-color: #ef4444;
        color: white;
      }

      .animate-btn.animating:hover {
        background: #dc2626;
        border-color: #dc2626;
      }

      .play-icon {
        font-size: 12px;
      }

      .pulse-dot {
        width: 10px;
        height: 10px;
        background: white;
        border-radius: 50%;
        animation: pulse 1s ease-in-out infinite;
      }

      @keyframes pulse {
        0%, 100% { opacity: 1; transform: scale(1); }
        50% { opacity: 0.5; transform: scale(0.8); }
      }

      .tick-counter {
        font-size: 12px;
        color: #666;
        font-family: monospace;
        background: #f3f4f6;
        padding: 0.3rem 0.6rem;
        border-radius: 4px;
      }

      .slider-control {
        display: flex;
        align-items: center;
        gap: 1rem;
      }

      .slider-control label {
        font-weight: 600;
        color: #444;
        font-size: 14px;
        min-width: 110px;
      }

      .slider-control input[type="range"] {
        width: 150px;
        height: 6px;
        -webkit-appearance: none;
        appearance: none;
        background: #ddd;
        border-radius: 3px;
        outline: none;
        cursor: pointer;
      }

      .slider-control input[type="range"]::-webkit-slider-thumb {
        -webkit-appearance: none;
        appearance: none;
        width: 18px;
        height: 18px;
        background: #4e79a7;
        border-radius: 50%;
        cursor: pointer;
        transition: background 0.2s ease;
      }

      .slider-control input[type="range"]::-webkit-slider-thumb:hover {
        background: #3d6089;
      }

      .slider-control input[type="range"]::-moz-range-thumb {
        width: 18px;
        height: 18px;
        background: #4e79a7;
        border-radius: 50%;
        cursor: pointer;
        border: none;
      }

      .slider-control input[type="range"]::-moz-range-thumb:hover {
        background: #3d6089;
      }
    </style>
    """
  end

  defp build_chart_opts(palette, tick, animating, slug, hex_radius) do
    # A chart is drawn at its own size (`size/0`, spec/14 §4.2, #427): the page no
    # longer imposes one, which a streaming design's window would disagree with.
    opts = [palette: palette]

    opts =
      if animating do
        Keyword.put(opts, :animation_tick, tick)
      else
        opts
      end

    if slug == "hexbin" do
      Keyword.put(opts, :hex_radius, hex_radius)
    else
      opts
    end
  end

  defp backend_word(:svg), do: "SVG"
  defp backend_word(:canvas), do: "Canvas"
  defp backend_word(:incremental), do: "Canvas-Incremental"

  defp backend_code_title(:svg), do: "The design (Build), then the SVG rendering"

  defp backend_code_title(:canvas),
    do: "The design (Build), then the canvas rendering (the split)"

  defp backend_code_title(:incremental), do: "Canvas Incremental Rendering Code"

  defp backend_sample_code(:svg, module), do: module.sample_code()

  # The Canvas sample opens with the design the split takes (#318): the module's Build
  # calls up to `{:ok, design}`, then the split.
  defp backend_sample_code(:canvas, module),
    do: design_build_code(module) <> "\n" <> hybrid_sample_code()

  defp backend_sample_code(:incremental, _module) do
    ~S"""
    # Canvas Incremental Rendering
    # Only redraws changed regions for scrolling time-series

    # Key concept: shift existing pixels, draw only new data

    # In LiveView mount:
    {:ok, assign(socket,
      viewport_x: 0,
      scroll_offset: 0,
      data: generate_initial_data()
    )}

    # On scroll/tick:
    def handle_info(:scroll_tick, socket) do
      {new_data, exposed_region} = shift_data(socket.assigns)

      # Encode only the exposed region
      binary = encode_incremental_update(new_data, exposed_region)

      {:noreply,
        socket
        |> assign(data: new_data, viewport_x: viewport_x + shift)
        |> push_event("canvas_incremental", %{
          binary: Base.encode64(binary),
          dx: shift_pixels,
          mode: "scroll"
        })}
    end

    # Client-side hook:
    # 1. Copy canvas to offscreen buffer
    # 2. Clear and draw shifted copy
    # 3. Clip to exposed region
    # 4. Render new commands
    """
  end

  # The Build calls of a module's sample: everything before its `Visualize.Chart.apply`
  # line, which is where the SVG sample turns from the design to its rendering.
  @doc false
  def design_build_code(module) do
    [build | _] =
      String.split(module.sample_code(), ~r/\n[^\n]*Visualize\.Chart\.apply\(/, parts: 2)

    String.trim_trailing(build) <> "\n"
  end

  # The compile-and-render call the page makes for a design in Canvas mode (#268).
  defp hybrid_sample_code do
    ~S"""
    # Canvas mode is the hybrid split (spec/14 §12): the furniture — axes, grid,
    # legend, labels — as SVG, the marks on a binary canvas beneath it.

    {:ok, applied} = Visualize.Chart.apply(design, sources: sources)
    {:ok, compiled} = Visualize.Chart.compile(applied, ceiling: 1)
    static = Visualize.Chart.Compiled.static(compiled)          # the furniture, once
    {tick, compiled} = Visualize.Chart.Compiled.tick(compiled, applied.sources)
    # tick.canvas — the marks as a base64 binary stream for the hook
    # tick.svg    — any SVG-layer marks (text, small marks) for the layer above

    # In the template, the canvas under the static SVG:
    <div style="position: relative">
      <div id="chart" phx-hook="CanvasBinaryChart" data-binary={tick.canvas}
           style="position: absolute; top: 0; left: 0">
        <canvas width={width} height={height}></canvas>
      </div>
      <div style="position: absolute; top: 0; left: 0; pointer-events: none">
        <%= Phoenix.HTML.raw(static) %>
      </div>
    </div>
    """
  end

  defp animation_sample_code(:svg) do
    ~S"""
    # LiveView animation: the design is fixed, the rows move.
    # On each tick the chart module binds new rows to the same design and the page
    # re-renders it whole as SVG.

    def handle_info(:animate_tick, socket) do
      if socket.assigns.animating do
        Process.send_after(self(), :animate_tick, 150)
        {:noreply, assign(socket, tick: socket.assigns.tick + 1)}
      else
        {:noreply, socket}
      end
    end

    # In render/1:
    <%= Phoenix.HTML.raw(MyChart.render(animation_tick: @tick)) %>

    # In the chart module — design/1 returns the design and the rows it binds at the
    # tick; render/1 applies and renders it (Examples.Charts.Design):
    def design(opts) do
      tick = opts[:animation_tick]
      {design(), %{points: rows(tick)}}
    end

    defp rows(nil), do: @rows

    defp rows(tick) do
      for row <- @rows do
        %{row | value: row.base + :math.sin(tick * 0.1 + row.index) * 20}
      end
    end
    """
  end

  defp animation_sample_code(:canvas) do
    ~S"""
    # Canvas animation: compile the design once, tick it with each frame's rows.
    # The furniture (axes, grid, legend) is rendered once as SVG; a tick pushes only
    # the marks, as a binary stream, to the CanvasBinaryChart hook (spec/14 §12).

    {:ok, compiled} = Visualize.Chart.compile(applied, ceiling: 1)
    static = Visualize.Chart.Compiled.static(compiled)

    def handle_info(:animate_tick, socket) do
      if socket.assigns.animating do
        Process.send_after(self(), :animate_tick, 50)
        tick = socket.assigns.tick + 1

        {_design, sources} = MyChart.design(animation_tick: tick)
        {frame, compiled} = Visualize.Chart.Compiled.tick(socket.assigns.compiled, sources)

        {:noreply,
          socket
          |> assign(tick: tick, compiled: compiled)
          |> push_event("canvas_update", %{binary: frame.canvas})}
      else
        {:noreply, socket}
      end
    end
    """
  end

  defp animation_sample_code(:incremental) do
    ~S"""
    # Incremental Canvas Animation
    # Optimized for scrolling time-series data

    def handle_info(:scroll_tick, socket) do
      if socket.assigns.animating do
        Process.send_after(self(), :scroll_tick, 16)  # 60fps target

        # Shift data and calculate exposed region
        {shifted_data, exposed} = shift_viewport(socket.assigns)

        # Only encode data in the exposed region
        binary = encode_exposed_region(shifted_data, exposed)

        {:noreply,
          socket
          |> assign(data: shifted_data, viewport_x: viewport_x + dx)
          |> push_event("canvas_incremental", %{
            binary: Base.encode64(binary),
            dx: dx,
            mode: "scroll"
          })}
      else
        {:noreply, socket}
      end
    end

    # Client-side rendering:
    # 1. drawImage() to shift existing content
    # 2. clip() to exposed region
    # 3. Render only new data points

    # Performance gains:
    # - Server: encode ~5% of data per frame
    # - Client: copy pixels instead of redraw
    # - Result: 2-5x faster for scrolling charts
    """
  end
end
