defmodule ExamplesWeb.ChartLive do
  use Phoenix.LiveView

  alias Examples.Charts.Design
  alias Examples.ColorPalettes
  alias Examples.{Compare, Frames, Run}
  alias ExamplesWeb.PerformanceDrawer
  alias Visualize.Backend.CanvasBinary

  @charts %{
    # Basic Charts
    "bar" => Examples.Charts.BarChart,
    "horizontal_bar" => Examples.Charts.HorizontalBarChart,
    "grouped_bar" => Examples.Charts.GroupedBarChart,
    "stacked_bar" => Examples.Charts.StackedBarChart,
    "line" => Examples.Charts.LineChart,
    "scrolling_series" => Examples.Charts.ScrollingSeries,
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
    # Maps
    "world_map" => Examples.Charts.WorldMap,
    "globe" => Examples.Charts.Globe
  }

  # Charts that support animation
  @animatable_charts [
    "bar", "horizontal_bar", "line", "area", "pie", "donut",
    "scatter", "radial", "multi_line", "grouped_bar", "stacked_bar",
    "stacked_area", "streamgraph", "ridgeline", "bubble", "heatmap", "force", "contour",
    "sankey", "treemap", "circle_pack", "sunburst", "tree", "cluster", "chord",
    "world_map", "globe", "hexbin"
  ]

  # Time-series charts that support incremental canvas rendering
  @time_series_charts [
    "line", "multi_line", "area", "stacked_area", "streamgraph", "ridgeline"
  ]

  @animation_interval 50  # milliseconds between frames (20 fps)

  def mount(%{"chart" => chart_slug}, _session, socket) do
    case Map.get(@charts, chart_slug) do
      nil ->
        {:ok, push_navigate(socket, to: "/")}
      module ->
        palettes = ColorPalettes.list_palettes()
        palette_info = ColorPalettes.palette_info()

        {:ok, assign(socket,
          module: module,
          slug: chart_slug,
          title: module.title(),
          description: module.description(),
          current_palette: :default,
          palettes: palettes,
          palette_info: palette_info,
          animating: false,
          animation_tick: 0,
          animatable: chart_slug in @animatable_charts,
          is_time_series: chart_slug in @time_series_charts,
          backend: :svg,
          hex_radius: 20,
          # The performance drawer (spec/14 §12.6, #322): a run of this chart on a
          # backend, its frame, the compiled chart's state, and Compare's rows.
          drawer_open: false,
          run: Run.new(target_fps: 60, data_rate: 0, flow_control: true),
          run_backend: :svg,
          run_state: nil,
          run_frame: nil,
          # A streaming design's window (#327): an `Examples.Scroll` at the density the
          # data rate implies, nil for any other chart
          run_scroll: nil,
          compare: nil,
          compare_task: nil
        )}
    end
  end

  def handle_event("change_palette", %{"palette" => palette_key}, socket) do
    palette = case palette_key do
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
    {:noreply, assign(socket, current_palette: palette)}
  end

  def handle_event("toggle_animation", _params, socket) do
    if socket.assigns.animating do
      {:noreply, assign(socket, animating: false)}
    else
      schedule_animation()
      {:noreply, assign(socket, animating: true, animation_tick: 0)}
    end
  end

  def handle_event("change_hex_radius", %{"hex_radius" => radius_str}, socket) do
    radius = String.to_integer(radius_str)
    {:noreply, assign(socket, hex_radius: radius)}
  end

  def handle_event("set_backend", %{"backend" => backend_str}, socket) do
    backend = String.to_existing_atom(backend_str)
    {:noreply, assign(socket, backend: backend)}
  end

  # ── the performance drawer ──────────────────────────────────────────────────────────

  def handle_event("drawer_toggle", _params, socket) do
    {:noreply, assign(socket, drawer_open: not socket.assigns.drawer_open)}
  end

  def handle_event("run_backend", %{"backend" => backend}, %{assigns: %{run: %Run{running: false}}} = socket) do
    backend = String.to_existing_atom(backend)
    true = backend in Frames.backends(socket.assigns.module)
    {:noreply, assign(socket, run_backend: backend)}
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
    socket = assign(socket, run_scroll: fresh_scroll(socket.assigns))
    state = Frames.prepare(module, run_opts(socket.assigns, 0), backend)

    run =
      Run.start(
        %{socket.assigns.run | flow_control: socket.assigns.run.flow_control and Frames.acks?(backend)},
        System.monotonic_time(:millisecond),
        System.monotonic_time(:microsecond)
      )

    socket = assign(socket, run: run, run_state: state, run_frame: nil, animating: false)
    {:noreply, socket |> start_frame() |> schedule_run()}
  end

  # The data rate of a streaming design (#327): its density follows the rate, as the
  # High-Performance page's did — about five seconds of samples across the plot.
  def handle_event("run_data_rate", %{"data_rate" => rate}, %{assigns: %{run: %Run{running: false}}} = socket) do
    socket = update(socket, :run, &%{&1 | data_rate: String.to_integer(rate)})
    {:noreply, assign(socket, run_scroll: fresh_scroll(socket.assigns))}
  end

  def handle_event("run_data_rate", _params, socket), do: {:noreply, socket}

  def handle_event("run_stop", _params, socket) do
    {:noreply, socket |> update(:run, &Run.stop/1) |> assign(run_frame: nil)}
  end

  # Compare, headless in a task: a fixed count of ticks per backend.
  def handle_event("run_compare", _params, %{assigns: %{compare_task: nil}} = socket) do
    %{module: module} = socket.assigns
    assigns = socket.assigns
    opts_for = fn tick -> run_opts(assigns, tick) end
    task = Task.Supervisor.async_nolink(Examples.TaskSupervisor, fn -> {:compare, Compare.run(module, opts_for, 100)} end)
    {:noreply, assign(socket, compare_task: task, compare: nil)}
  end

  def handle_event("run_compare", _params, socket), do: {:noreply, socket}

  # The hook's ack (spec/10 §8.2).
  def handle_event("frame_drawn", %{"seq" => seq, "drawn" => drawn}, socket) do
    {:noreply, update(socket, :run, &Run.acked(&1, seq, drawn, System.monotonic_time(:millisecond)))}
  end

  def handle_info(:run_tick, %{assigns: %{run: %Run{running: false}}} = socket), do: {:noreply, socket}

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
        # A streaming design's window advances by the columns the samples filled; the
        # compiled chart then scrolls by exactly those pixels (spec/14 §12.5, §12.6). Any
        # other chart's frame is the chart at its next animation tick, a full render.
        incremental? = backend == :incremental and scroll != nil
        size = if scroll, do: {scroll.inner_width, 1}, else: {1, 1}
        {run, mode} = Run.decide(run, if(incremental?, do: columns, else: 1), incremental?, size, now)
        socket = assign(socket, run: run)

        cond do
          mode == :drop ->
            {:noreply, socket}

          incremental? ->
            socket = assign(socket, run_scroll: Examples.Scroll.advance(scroll, columns))
            {:noreply, start_frame(socket, mode)}

          true ->
            {:noreply, start_frame(socket)}
        end
    end
  end

  # A frame's render is back: numbered, shown or pushed, and measured.
  def handle_info({ref, {:frame, frame, state}}, socket) when is_reference(ref) do
    case Run.result(socket.assigns.run, ref) do
      :stale ->
        {:noreply, socket}

      {:ok, %Run{running: false} = run} ->
        {:noreply, assign(socket, run: run)}

      {:ok, run} ->
        now = System.monotonic_time(:millisecond)
        {run, seq} = Run.sending(run, if(frame.incremental, do: incremental_mode(frame), else: :full_redraw))
        run = Run.rendered(run, frame.bytes, now)
        socket = assign(socket, run: run, run_state: state, run_frame: frame)

        cond do
          frame.incremental ->
            {:noreply, push_event(socket, "canvas_incremental", Map.put(frame.incremental, :seq, seq))}

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

  def handle_info({ref, _stale}, socket) when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    {:noreply, socket}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, %{assigns: %{compare_task: %Task{ref: ref}}} = socket) do
    {:noreply, assign(socket, compare_task: nil, compare: [], run: %{socket.assigns.run | error: inspect(reason)})}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, socket) do
    case Run.down(socket.assigns.run, ref, reason) do
      :stale -> {:noreply, socket}
      {:ok, run} -> {:noreply, assign(socket, run: run, run_frame: nil)}
    end
  end

  def handle_info(:animate_tick, socket) do
    if socket.assigns.animating do
      schedule_animation()
      {:noreply, assign(socket, animation_tick: socket.assigns.animation_tick + 1)}
    else
      {:noreply, socket}
    end
  end

  defp schedule_animation do
    Process.send_after(self(), :animate_tick, @animation_interval)
  end

  defp incremental_mode(%{incremental: %{mode: "full"}}), do: :full_redraw
  defp incremental_mode(%{incremental: %{mode: "none"}}), do: :none
  defp incremental_mode(_frame), do: :scroll_x

  def terminate(_reason, socket) do
    Run.cancel(socket.assigns.run)
    if task = socket.assigns[:compare_task], do: Task.Supervisor.terminate_child(Examples.TaskSupervisor, task.pid)
    :ok
  end

  # The frame at the run's next tick, rendering in a task over a snapshot: a streaming
  # design's at its window, any other chart's at its next animation tick.
  defp start_frame(socket, _mode \\ :full_redraw) do
    %{module: module, run_backend: backend, run_state: state, run: run} = socket.assigns
    opts = run_opts(socket.assigns, run.frame)
    render = fn ->
      {frame, state} = Frames.frame(module, opts, backend, state)
      {:frame, frame, state}
    end

    update(socket, :run, &Run.rendering(&1, render))
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
    |> Keyword.merge(samples_per_px: scroll.samples_per_px, origin: scroll.origin, now: scroll.origin + count - 1)
  end

  defp run_opts(assigns, tick) do
    build_chart_opts(assigns.current_palette, tick, true, assigns.slug, assigns.hex_radius)
  end

  # A streaming design's window at the run's data rate: about five seconds across the plot.
  defp fresh_scroll(%{module: module, run: run}) do
    if Frames.stream?(module) do
      {_x, _y, width, _h} = module.plot()
      Examples.Scroll.new(width, Examples.Scroll.density(run.data_rate * 5, width))
    end
  end

  # The window a streaming design shows, for the drawer.
  defp stream_info(%{run_scroll: %Examples.Scroll{} = scroll, run: run}) do
    count = Examples.Scroll.count(scroll)
    %{samples_per_px: scroll.samples_per_px, count: count, span: if(run.data_rate > 0, do: count / run.data_rate, else: 0.0)}
  end

  defp stream_info(_assigns), do: nil

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
                type="button"
                phx-click="set_backend"
                phx-value-backend="svg"
                class={"backend-btn #{if @backend == :svg, do: "active", else: ""}"}
              >
                SVG
              </button>
              <button
                type="button"
                phx-click="set_backend"
                phx-value-backend="canvas"
                class={"backend-btn #{if @backend == :canvas, do: "active", else: ""}"}
              >
                Canvas
              </button>
              <%= if @is_time_series do %>
                <button
                  type="button"
                  phx-click="set_backend"
                  phx-value-backend="canvas_incremental"
                  class={"backend-btn #{if @backend == :canvas_incremental, do: "active", else: ""}"}
                >
                  Canvas-Incremental
                </button>
              <% end %>
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
                class={"animate-btn #{if @animating, do: "animating", else: ""}"}
              >
                <%= if @animating do %>
                  <span class="pulse-dot"></span>
                  Stop Animation
                <% else %>
                  <span class="play-icon">▶</span>
                  Animate Data
                <% end %>
              </button>
              <%= if @animating do %>
                <span class="tick-counter">Frame: <%= @animation_tick %></span>
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
          <%= if @run.running and @run_frame do %>
            <%!-- A run's frame (spec/14 §12.6, #322): the SVG whole, or the canvas pushed under the compiled chart's static furniture. --%>
            <%= if @run_backend == :svg do %>
              <%= Phoenix.HTML.raw(@run_frame.svg) %>
            <% else %>
            <%= if @run_backend == :incremental do %>
              <%!-- The incremental canvas is the plot area, at the margin's offset (spec/14 §12.5). --%>
              <div class="hybrid-wrapper" style={"position: relative; width: #{run_size(@run_state, :width)}px; height: #{run_size(@run_state, :height)}px;"}>
                <div id="incremental-chart" phx-hook="CanvasIncrementalChart" phx-update="ignore" data-ack="frame_drawn" data-ack-interval="50" data-width={@run_state.plot.width} data-height={@run_state.plot.height} style={"position: absolute; top: #{@run_state.margin.top}px; left: #{@run_state.margin.left}px; z-index: 1;"}>
                  <canvas width={@run_state.plot.width} height={@run_state.plot.height} style="display: block;"></canvas>
                </div>
                <div class="hybrid-static-layer" style="position: absolute; top: 0; left: 0; z-index: 2; pointer-events: none;">
                  <%= Phoenix.HTML.raw(Frames.static(@run_state)) %>
                </div>
                <div :if={@run_frame.dynamic_svg != ""} class="hybrid-dynamic-layer" style="position: absolute; top: 0; left: 0; z-index: 3; pointer-events: none;">
                  <%= Phoenix.HTML.raw(@run_frame.dynamic_svg) %>
                </div>
              </div>
            <% else %>
              <div class="hybrid-wrapper" style={"position: relative; width: #{run_size(@run_state, :width)}px; height: #{run_size(@run_state, :height)}px;"}>
                <div id="canvas-chart" phx-hook="CanvasBinaryChart" phx-update="ignore" data-ack="frame_drawn" data-ack-interval="50" data-binary={@run_frame.canvas} data-width={run_size(@run_state, :width)} data-height={run_size(@run_state, :height)} style="position: absolute; top: 0; left: 0; z-index: 1;">
                  <canvas width={run_size(@run_state, :width)} height={run_size(@run_state, :height)} style="display: block;"></canvas>
                </div>
                <div class="hybrid-static-layer" style="position: absolute; top: 0; left: 0; z-index: 2; pointer-events: none;">
                  <%= Phoenix.HTML.raw(Frames.static(@run_state)) %>
                </div>
                <div :if={@run_frame.dynamic_svg != ""} class="hybrid-dynamic-layer" style="position: absolute; top: 0; left: 0; z-index: 3; pointer-events: none;">
                  <%= Phoenix.HTML.raw(@run_frame.dynamic_svg) %>
                </div>
              </div>
            <% end %>
            <% end %>
          <% else %>
          <%= if @backend == :svg do %>
            <%= Phoenix.HTML.raw(render_chart_svg(@module, @current_palette, @animation_tick, @animating, @slug, @hex_radius)) %>
          <% else %>
            <%= if Design.design?(@module) do %>
              <%!-- Canvas mode is the hybrid split (spec/14 §12.6, #268): the marks on a binary canvas under the furniture as SVG. --%>
              <% hybrid = render_chart_hybrid(@module, @current_palette, @animation_tick, @animating, @slug, @hex_radius) %>
              <div class="hybrid-wrapper" style={"position: relative; width: #{hybrid.width}px; height: #{hybrid.height}px;"}>
                <div id="canvas-chart" phx-hook="CanvasBinaryChart" data-binary={hybrid.canvas} data-width={hybrid.width} data-height={hybrid.height} style="position: absolute; top: 0; left: 0; z-index: 1;">
                  <canvas width={hybrid.width} height={hybrid.height} style="display: block;"></canvas>
                </div>
                <div class="hybrid-static-layer" style="position: absolute; top: 0; left: 0; z-index: 2; pointer-events: none;">
                  <%= Phoenix.HTML.raw(hybrid.static) %>
                </div>
                <div :if={hybrid.dynamic_svg != ""} class="hybrid-dynamic-layer" style="position: absolute; top: 0; left: 0; z-index: 3; pointer-events: none;">
                  <%= Phoenix.HTML.raw(hybrid.dynamic_svg) %>
                </div>
              </div>
            <% else %>
              <div id="canvas-chart" phx-hook="CanvasBinaryChart" data-binary={render_chart_canvas(@module, @current_palette, @animation_tick, @animating, @slug, @hex_radius)}>
                <canvas width="700" height="450"></canvas>
              </div>
              <p class="canvas-note" style="margin-top: 0.5rem; color: #666; font-size: 0.9rem;">
                The binary stream carries the marks and no text (spec/09 §4.4), so this chart's axes and labels draw once it is a design (#124); the charts that are designs draw them as SVG over the canvas.
              </p>
            <% end %>
          <% end %>
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
        />

        <h3 style="margin-top: 2rem; margin-bottom: 0.5rem;"><%= backend_code_title(@backend, @module) %></h3>
        <pre><code><%= backend_sample_code(@backend, @module) %></code></pre>

        <%= if Design.design?(@module) do %>
          <h3 style="margin-top: 2rem; margin-bottom: 0.5rem;">The design (data)</h3>
          <p style="color: #666; font-size: 0.9rem; margin-bottom: 0.5rem;">
            What the Build calls fold to: the stored form the builder and a host exchange (spec/14 §1, §9).
            <code>Visualize.Chart.to_json/1</code> is the same map as JSON.
          </p>
          <pre><code><%= design_data(@module, @current_palette, @animation_tick, @animating, @slug, @hex_radius) %></code></pre>
        <% end %>

        <%= if @animatable do %>
          <h3 style="margin-top: 2rem; margin-bottom: 0.5rem;">LiveView Animation Code</h3>
          <pre><code><%= animation_sample_code(@backend) %></code></pre>
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
    opts = [width: 700, height: 450, palette: palette]

    opts = if animating do
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

  # A chart written as a design renders its own document (`Examples.Charts.Design`); an
  # imperative one returns the element tree the gallery names and serialises.
  defp render_chart_svg(module, palette, tick, animating, slug, hex_radius) do
    opts = build_chart_opts(palette, tick, animating, slug, hex_radius)

    case module.render(opts) do
      svg when is_binary(svg) ->
        svg

      element ->
        element
        |> Examples.Accessible.name(module.title(), module.description())
        |> Visualize.SVG.Renderer.render_to_string()
    end
  end

  # Canvas mode for a design: the hybrid split, the furniture as SVG over the binary
  # canvas of the marks (spec/14 §12.6, #268).
  defp render_chart_hybrid(module, palette, tick, animating, slug, hex_radius) do
    Design.hybrid(module, build_chart_opts(palette, tick, animating, slug, hex_radius))
  end

  defp render_chart_canvas(module, palette, tick, animating, slug, hex_radius) do
    opts = build_chart_opts(palette, tick, animating, slug, hex_radius)

    if Design.design?(module) do
      Design.canvas(module, opts)
    else
      case CanvasBinary.encode_element(module.render(opts)) do
        {:ok, binary} -> Base.encode64(binary)
        {:error, _} -> ""
      end
    end
  end

  defp backend_code_title(:svg, _module), do: "SVG Rendering Code"

  defp backend_code_title(:canvas, module) do
    if Design.design?(module),
      do: "The design (Build), then the canvas rendering (the split)",
      else: "Canvas Binary Rendering Code"
  end

  defp backend_code_title(:canvas_incremental, _module), do: "Canvas Incremental Rendering Code"

  defp backend_sample_code(:svg, module), do: module.sample_code()

  # A design chart's Canvas sample opens with the design the split takes (#318): the
  # module's Build calls up to `{:ok, design}`, then the split.
  defp backend_sample_code(:canvas, module) do
    if Design.design?(module),
      do: design_build_code(module) <> "\n" <> hybrid_sample_code(),
      else: binary_sample_code()
  end


  defp backend_sample_code(:canvas_incremental, _module) do
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

  # A chart that is not yet a design: the whole element on the binary stream.
  # The Build calls of a module's sample: everything before its `Visualize.Chart.apply`
  # line, which is where the SVG sample turns from the design to its rendering.
  @doc false
  def design_build_code(module) do
    [build | _] = String.split(module.sample_code(), ~r/\n[^\n]*Visualize\.Chart\.apply\(/, parts: 2)
    String.trim_trailing(build) <> "\n"
  end

  # The folded design as data: what the Build calls fold to (#318).
  @doc false
  def design_data(module, palette, tick, animating, slug, hex_radius) do
    {design, _sources} = module.design(build_chart_opts(palette, tick, animating, slug, hex_radius))
    inspect(design, pretty: true, limit: :infinity, width: 80)
  end

  defp binary_sample_code do
    ~S"""
    # Canvas Binary Rendering
    # Encodes chart as compact binary for efficient transfer

    # In LiveView:
    element = MyChart.render(opts)
    {:ok, binary} = Visualize.Backend.CanvasBinary.encode_element(element)

    {:noreply, push_event(socket, "canvas_update", %{
      binary: Base.encode64(binary)
    })}

    # In template - use the CanvasBinaryChart hook:
    <div id="chart" phx-hook="CanvasBinaryChart" data-binary={@binary}>
      <canvas width="700" height="450"></canvas>
    </div>

    # The hook decodes and renders:
    # - 0x01: Simple paths (move + line sequences)
    # - 0x02: Complex paths (bezier, quadratic, arcs)
    # - 0x03: Circles
    # - 0x04: Rectangles
    # - 0x10: Style (fill, stroke, lineWidth)
    # - 0x20: Transform (translate, scale, rotate)
    """
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
    # LiveView Animation Example
    # The chart re-renders on each tick with new data

    def handle_info(:animate_tick, socket) do
      if socket.assigns.animating do
        Process.send_after(self(), :animate_tick, 150)
        {:noreply, assign(socket, tick: socket.assigns.tick + 1)}
      else
        {:noreply, socket}
      end
    end

    # In render/1:
    <%= Phoenix.HTML.raw(
      MyChart.render(animation_tick: @tick)
    ) %>

    # In chart module - use tick to vary data:
    def render(opts) do
      tick = opts[:animation_tick] || 0
      data = generate_animated_data(tick)
      # ... render with data
    end

    defp generate_animated_data(tick) do
      # Use sine waves for smooth animation
      Enum.map(base_data, fn item ->
        variation = :math.sin(tick * 0.1 + item.index) * 20
        %{item | value: item.base_value + variation}
      end)
    end
    """
  end

  defp animation_sample_code(:canvas) do
    ~S"""
    # Canvas Animation with Binary Encoding
    # Re-encode and push binary on each tick

    def handle_info(:animate_tick, socket) do
      if socket.assigns.animating do
        Process.send_after(self(), :animate_tick, 50)
        tick = socket.assigns.tick + 1

        element = MyChart.render(animation_tick: tick)
        {:ok, binary} = CanvasBinary.encode_element(element)

        {:noreply,
          socket
          |> assign(tick: tick)
          |> push_event("canvas_update", %{binary: Base.encode64(binary)})}
      else
        {:noreply, socket}
      end
    end

    # Template with CanvasBinaryChart hook:
    <div id="chart" phx-hook="CanvasBinaryChart">
      <canvas width="700" height="450"></canvas>
    </div>

    # Benefits over SVG animation:
    # - Smaller payload (binary vs XML text)
    # - No DOM diffing overhead
    # - Direct GPU rendering path
    """
  end

  defp animation_sample_code(:canvas_incremental) do
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
