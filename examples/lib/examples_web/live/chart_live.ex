defmodule ExamplesWeb.ChartLive do
  use Phoenix.LiveView

  alias Examples.ColorPalettes
  alias Examples.{Compare, Frames, Gallery, Run}
  alias ExamplesWeb.{Highlight, PerformanceDrawer}

  @doc """
  The gallery's charts by slug, for the performance view (#328): the map derived from the
  gallery's one ordered list, `Examples.Gallery.charts/0` (#484).
  """
  def charts, do: Gallery.by_slug()

  # Charts that support animation
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
    "load",
    "load_age_gauge",
    "context",
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
    "day_night_gps",
    "globe",
    "gps_track",
    "hexbin",
    "spectrum"
  ]

  # The page's own state — what the viewer chose about the page, kept from chart to chart
  # (spec/14 §12.6, #484) — then the chart's, on the path a patch to another chart takes.
  def mount(%{"chart" => chart_slug}, _session, socket) do
    case Gallery.module(chart_slug) do
      nil ->
        {:ok, push_navigate(socket, to: "/")}

      module ->
        {:ok,
         socket
         |> assign(
           current_palette: :default,
           palettes: ColorPalettes.list_palettes(),
           palette_info: ColorPalettes.palette_info(),
           # The performance drawer (spec/14 §12.6, #322), open or not.
           drawer_open: false,
           # The page measures itself (spec/10 §10, #434): the container's width once the
           # hook has pushed one, and the module's own size until then — a disconnected
           # mount has nothing to measure and must still draw. A patch to another chart
           # keeps it, so the next chart is drawn at once at the width the page knows.
           width: nil,
           run: nil,
           still_task: nil,
           compare_task: nil
         )
         |> load(module, chart_slug)}
    end
  end

  # Previous / Next and the arrow keys patch (#484): the view stays connected and loads the
  # chart the slug names. The mount's own params name the chart it has just loaded.
  def handle_params(%{"chart" => slug}, _uri, %{assigns: %{slug: slug}} = socket),
    do: {:noreply, socket}

  def handle_params(%{"chart" => slug}, _uri, socket) do
    case Gallery.module(slug) do
      nil -> {:noreply, push_navigate(socket, to: "/")}
      module -> {:noreply, load(socket, module, slug)}
    end
  end

  # A chart on the page, the one path for a mount and a patch (spec/14 §12.6, #484). The
  # outgoing chart's work ends first — a run's renderer, a still render and a Compare in
  # flight, whose late results then fall to the stale clauses — and everything that is the
  # chart's starts afresh; the page's own state (palette, drawer, width) is untouched.
  defp load(socket, module, chart_slug) do
    socket
    |> ended()
    |> assign(
      module: module,
      slug: chart_slug,
      title: module.title(),
      description: module.description(),
      neighbours: Gallery.neighbours(chart_slug),
      animatable: chart_slug in @animatable_charts,
      hex_radius: 20,
      # The still chart (#362): the last frame rendered outside a run — on mount and on
      # a palette, backend or hex-size change — in a task, with the design as data.
      still_frame: nil,
      still_state: nil,
      still_design: nil,
      still_access: nil,
      still_task: nil,
      # The performance drawer's run (spec/14 §12.6, #322): a run of this chart on a
      # backend, its frame, the compiled chart's state, and Compare's rows.
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
      # The wall-clock instant the run started at, passed to a design as `utc:` (#526).
      run_utc: nil,
      # A chart opens on SVG (#501); a patch keeps the backend the reader chose when
      # the new chart offers it among its own (#432).
      run_backend: opening_backend(Frames.backends(module), socket.assigns[:run_backend]),
      run_state: nil,
      # The state a backend switched to mid-run holds for the markup until the first
      # frame of that backend arrives (#502): `{:state, state}`, or nil.
      run_pending_state: nil,
      run_frame: nil,
      run_mode: nil,
      run_scroll: nil,
      run_series: series(module),
      compare: nil,
      compare_task: nil
    )
    |> then(&assign(&1, run_scroll: fresh_scroll(&1.assigns)))
    |> still()
  end

  @doc """
  The backend a chart opens on (spec/14 §12.6, #501): the one the reader chose, when the
  chart offers it, else SVG, else the chart's first. A mount has no choice yet (`nil`).
  """
  @spec opening_backend([atom(), ...], atom() | nil) :: atom()
  def opening_backend([first | _] = backends, chosen) do
    cond do
      chosen in backends -> chosen
      :svg in backends -> :svg
      true -> first
    end
  end

  # The outgoing chart's work, ended: its run's renderer stopped, a still render and a
  # Compare terminated. A mount has none.
  defp ended(%{assigns: assigns} = socket) do
    if run = assigns.run, do: Run.cancel(run)

    for %Task{pid: pid} <- [assigns.still_task, assigns.compare_task],
        do: Task.Supervisor.terminate_child(Examples.TaskSupervisor, pid)

    socket
  end

  # The arrow keys step through the gallery as Previous / Next do (#484), except while
  # focus is in a form field — a slider's or a caret's arrow — or a modifier is held
  # (Alt+← is the browser's back). The layout's LiveSocket reports both with every keyup
  # as event metadata (`field`, `modified`); a keyup without them is a plain key.
  def handle_event("key", %{"key" => key} = params, socket)
      when key in ["ArrowLeft", "ArrowRight"] do
    if params["field"] == true or params["modified"] == true do
      {:noreply, socket}
    else
      {previous, next} = socket.assigns.neighbours
      {_module, slug} = if key == "ArrowLeft", do: previous, else: next
      {:noreply, push_patch(socket, to: chart_path(slug))}
    end
  end

  def handle_event("key", _params, socket), do: {:noreply, socket}

  # The container's width (spec/10 §10, #434). The height is the chart's own aspect, not
  # the container's: a container sized by its content would observe the chart's height and
  # never settle. A resize is geometry — the rows, the tick counter and a streaming
  # window's origin are untouched — so a run re-prepares its renderer at the new size and
  # goes on, the easing carried (spec/14 §12.5). The chart is capped at its design size
  # (#457), so a width past the cap draws nothing new. A streaming window is the plot the
  # chart is drawn at (#459), so it is rebuilt at the new plot width first, keeping its
  # density and its newest sample, and the run's next frame is full.
  def handle_event("resize", %{"width" => width}, socket) when is_integer(width) and width > 0 do
    %{width: was, slug: slug} = socket.assigns

    if measured(width, slug) == measured(was, slug) do
      {:noreply, socket}
    else
      socket = assign(socket, width: width)
      {:noreply, socket |> rescrolled() |> resized() |> still()}
    end
  end

  def handle_event("resize", _params, socket), do: {:noreply, socket}

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
        "colour_safe" -> :colour_safe
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

  # A backend the chart offers, chosen by name — anything else is refused, and no atom is
  # made of it — live during a run (spec/14 §12.6, #502): mid-run the run switches without
  # stopping, and otherwise the still chart is drawn on it. The one the page is on is no
  # change.
  def handle_event("run_backend", %{"backend" => name}, socket) when is_binary(name) do
    %{module: module, run_backend: current, run: run} = socket.assigns
    backend = Enum.find(Frames.backends(module), &(Atom.to_string(&1) == name))

    cond do
      backend in [nil, current] -> {:noreply, socket}
      run.running -> {:noreply, switched(socket, backend)}
      true -> {:noreply, socket |> assign(run_backend: backend) |> still()}
    end
  end

  def handle_event("run_backend", _params, socket), do: {:noreply, socket}

  def handle_event("run_fps", %{"fps" => fps}, socket) do
    {:noreply, update(socket, :run, &%{&1 | target_fps: String.to_integer(fps)})}
  end

  def handle_event("run_flow_control", _params, socket) do
    {:noreply, update(socket, :run, &Run.toggle_flow_control/1)}
  end

  # A run: the page's own animation stops, the backend's state is prepared (a design's
  # compiled chart, once), and the first frame renders.
  def handle_event("run_start", _params, socket) do
    %{module: module, run_backend: backend} = socket.assigns
    socket = update(socket, :run, &Run.cancel/1)
    socket = assign(socket, run_scroll: fresh_scroll(socket.assigns))
    # A clock design starts its run at the real current UTC (#526); every tick of the
    # run, and the still frame after it, reads the same instant.
    socket = assign(socket, run_utc: DateTime.utc_now() |> DateTime.truncate(:second))
    opts = run_opts(socket.assigns, 0)
    # The view keeps the backend's state for its markup — the canvas's size and the static
    # SVG — and the run's renderer keeps its own to draw with (#413).
    state = Frames.prepare(module, opts, backend)

    run =
      Run.start(
        Run.on(socket.assigns.run, backend),
        System.monotonic_time(:millisecond),
        System.monotonic_time(:microsecond)
      )

    run = Run.renderer(run, module, backend, opts)

    socket =
      assign(socket,
        run: run,
        run_state: state,
        run_pending_state: nil,
        run_frame: nil,
        run_ticks: 0
      )

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
        density = density(socket.assigns.module, run)

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
    {:noreply,
     socket
     |> update(:run, &Run.stop/1)
     |> assign(run_frame: nil, run_pending_state: nil)
     |> still()}
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
        {run, seq} = Run.sending(run, mode_of(frame))
        run = Run.rendered(run, frame.bytes, now)

        socket =
          socket
          |> switched_markup()
          |> assign(run: run, run_frame: frame, run_mode: words(frame))

        # One event per plot, each named by its frame (spec/10 §9.2, #432): a design of
        # several frames has a canvas each, and a hook draws only what is its own.
        {:noreply, Enum.reduce(frame.plots, socket, &pushed(&2, &1, seq))}
    end
  end

  def handle_info({ref, {:compare, rows}}, %{assigns: %{compare_task: %Task{ref: ref}}} = socket) do
    Process.demonitor(ref, [:flush])
    {:noreply, assign(socket, compare: rows, compare_task: nil)}
  end

  # The still chart's frame (#362); a superseded one falls to the stale clause below.
  def handle_info(
        {ref, {:still, frame, state, design, access}},
        %{assigns: %{still_task: %Task{ref: ref}}} = socket
      ) do
    Process.demonitor(ref, [:flush])

    socket =
      assign(socket,
        still_frame: frame,
        still_state: state,
        still_design: design,
        still_access: access,
        still_task: nil
      )

    {:noreply, still_pushed(socket, frame)}
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

      {:still, frame, state, inspect(design, pretty: true, limit: :infinity, width: 80),
       access(module, opts)}
    end

    cond do
      not connected?(socket) ->
        {:still, frame, state, design, access} = render.()

        assign(socket,
          still_frame: frame,
          still_state: state,
          still_design: design,
          still_access: access
        )

      match?(:ok, Run.supervisor()) ->
        if task = assigns.still_task,
          do: Task.Supervisor.terminate_child(Examples.TaskSupervisor, task.pid)

        assign(socket, still_task: Task.Supervisor.async_nolink(Examples.TaskSupervisor, render))

      true ->
        {:error, message} = Run.supervisor()
        assign(socket, run: %{assigns.run | error: message})
    end
  end

  # A streaming window over the plot at the page's new width (spec/14 §12.6, #459): the
  # same density over the columns now drawn, its newest sample kept. A run repaints in full,
  # the copy-shift holding only within one plot; the renderer rebuilds its rows, whose
  # count is no longer the window's.
  defp rescrolled(%{assigns: %{run_scroll: %Examples.Scroll{} = scroll} = assigns} = socket) do
    socket = assign(socket, run_scroll: Examples.Scroll.resized(scroll, drawn_width(assigns)))
    if assigns.run.running, do: update(socket, :run, &Run.resync/1), else: socket
  end

  defp rescrolled(socket), do: socket

  # A backend chosen mid-run (spec/14 §12.6, #502, D-128): the renderer re-prepares for it
  # in place, carrying the easing, its rows, and the run's tick and window untouched; the
  # run closes the old backend's segment, marks the sequence floor its acks fall under,
  # forgets the frame in flight and draws the next one full. The view's own state for the
  # markup is the new backend's from the first frame of it, so the page never lays one
  # backend's furniture over another's frame.
  defp switched(%{assigns: %{run: run} = assigns} = socket, backend) do
    opts = run_opts(assigns, assigns.run_ticks)
    Examples.Renderer.switch(run.renderer, backend, opts)

    assign(socket,
      run: Run.switch(run, backend),
      run_backend: backend,
      run_pending_state: {:state, Frames.prepare(assigns.module, opts, backend)}
    )
  end

  # The first frame of a backend switched to mid-run brings its state into the markup.
  defp switched_markup(%{assigns: %{run_pending_state: {:state, state}}} = socket),
    do: assign(socket, run_state: state, run_pending_state: nil)

  defp switched_markup(socket), do: socket

  # A run goes on across a resize: its renderer re-prepares at the new size and carries
  # the easing, and the run's counters are untouched (#434); its window is the plot drawn
  # at the new size (#459).
  defp resized(%{assigns: %{run: %Run{running: true, renderer: renderer}}} = socket)
       when is_pid(renderer) do
    Examples.Renderer.resize(renderer, run_opts(socket.assigns, socket.assigns.run_ticks))
    socket
  end

  defp resized(socket), do: socket

  # The chart's text alternative at the still frame (spec/14 §21, #557): the summary that
  # names the hybrid layers' wrapper and is shown under the chart, the hidden data table
  # that follows the chart for a screen reader, and its points for the keyboard (#558).
  defp access(module, opts) do
    applied = Examples.Charts.Design.applied(module, opts)
    summary = Visualize.Chart.Summary.new(applied)
    %{
      summary: summary,
      table: Visualize.Chart.Summary.table(applied, id: "chart-data"),
      keyboard: Visualize.Hooks.Keyboard.attrs(applied)
    }
  end

  # A chart that has not run is at rest; one that has stays at the run's tick.
  defp still_opts(%{run_ticks: ticks} = assigns) when ticks > 0, do: run_opts(assigns, ticks)

  defp still_opts(assigns) do
    if assigns.run_scroll,
      do: run_opts(assigns, 0),
      else:
        build_chart_opts(
          assigns.current_palette,
          0,
          false,
          assigns.slug,
          assigns.hex_radius,
          assigns.width
        )
  end

  defp pushed(socket, %{incremental: record} = plot, seq) when is_map(record) do
    push_event(socket, "canvas_incremental", Map.merge(record, %{seq: seq, frame: plot.name}))
  end

  defp pushed(socket, %{canvas: canvas} = plot, seq) when is_binary(canvas) do
    push_event(socket, "canvas_update", %{binary: canvas, seq: seq, frame: plot.name})
  end

  defp pushed(socket, _plot, _seq), do: socket

  # An incremental canvas draws only what is pushed to it (spec/10 §9.2), so the still
  # frame is pushed too when no run is drawing (spec/14 §12.6, #457): each plot's record,
  # a fresh window's `"full"`, with no `seq` — it is no frame of a run, and not acked. A
  # binary canvas reads its `data-binary` from the markup and an SVG frame has no plots.
  defp still_pushed(%{assigns: %{run: %Run{running: true}}} = socket, _frame), do: socket

  defp still_pushed(socket, %{plots: plots}) do
    Enum.reduce(plots, socket, fn
      %{incremental: record} = plot, socket when is_map(record) ->
        push_event(socket, "canvas_incremental", Map.put(record, :frame, plot.name))

      _plot, socket ->
        socket
    end)
  end

  # The frame's mode for flow control and for the drawer: the strongest of its plots', a
  # full redraw of any plot being a full frame.
  defp mode_of(%{plots: plots}) do
    modes = for %{incremental: record} <- plots, is_map(record), do: incremental_mode(record)

    cond do
      modes == [] -> :full_redraw
      :full_redraw in modes -> :full_redraw
      :scroll_x in modes -> :scroll_x
      true -> :none
    end
  end

  defp words(%{plots: plots}) do
    case for(%{incremental: record} <- plots, is_map(record), do: record.mode) do
      [] -> "full"
      modes -> if "full" in modes, do: "full", else: hd(modes)
    end
  end

  # An incremental canvas is the plot area alone, since the copy-and-shift contract moves
  # pixels within one plot (spec/09 §5.3, D-106); a binary canvas is the frame's whole box.
  defp canvas_size(%{incremental: record, plot: plot}, key) when is_map(record),
    do: Map.fetch!(plot, key)

  defp canvas_size(%{box: box}, key), do: Map.fetch!(box, key)

  defp canvas_at(%{incremental: record, box: box, margin: margin}, key) when is_map(record) do
    case key do
      :top -> box.y + margin.top
      :left -> box.x + margin.left
    end
  end

  defp canvas_at(%{box: box}, :top), do: box.y
  defp canvas_at(%{box: box}, :left), do: box.x

  # A plot's element is named by its hook's kind as well as its frame (#502): a hook is
  # bound when its element mounts, so a switch that changes a plot's kind mid-run is a new
  # element, never the old hook handed the other kind's events.
  defp plot_kind(%{incremental: record}) when is_map(record), do: "incremental"
  defp plot_kind(_plot), do: "canvas"

  defp incremental_mode(%{mode: "full"}), do: :full_redraw
  defp incremental_mode(%{mode: "none"}), do: :none
  defp incremental_mode(_record), do: :scroll_x

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
    |> build_chart_opts(tick, true, assigns.slug, assigns.hex_radius, assigns.width)
    |> Keyword.merge(
      samples_per_px: scroll.samples_per_px,
      origin: scroll.origin,
      now: scroll.origin + count - 1
    )
  end

  defp run_opts(assigns, tick) do
    assigns.current_palette
    |> build_chart_opts(tick, true, assigns.slug, assigns.hex_radius, assigns.width)
    |> clock(assigns)
  end

  # The instant a run started at, as `utc:` (#526): a design that keeps a clock starts
  # there, and every other ignores it. None before a run.
  defp clock(opts, %{run_utc: %DateTime{} = utc}), do: Keyword.put(opts, :utc, utc)
  defp clock(opts, _assigns), do: opts

  # The series a streaming design binds — the sources of its design — for the drawer's
  # point counts; nil for any other chart.
  defp series(module) do
    if Frames.stream?(module), do: module.design([]) |> elem(1) |> map_size(), else: nil
  end

  # A streaming design's window at the run's data rate: the plot the chart is drawn at, at
  # the design's density — about five seconds across the design's plot — so a chart drawn
  # narrower than its design shows a shorter span, never a squeeze (spec/14 §12.6, #459).
  defp fresh_scroll(%{module: module, run: run} = assigns) do
    if Frames.stream?(module) do
      Examples.Scroll.new(drawn_width(assigns), density(module, run))
    end
  end

  # The samples per pixel column of a streaming design at the run's data rate: about five
  # seconds across the plot at the design's own size, whatever size it is drawn at.
  defp density(module, run) do
    {_x, _y, width, _h} = module.plot()
    Examples.Scroll.density(run.data_rate * 5, width)
  end

  # The width of a streaming design's plot at the size the page draws the chart.
  defp drawn_width(%{module: module, width: width, slug: slug}) do
    {_x, _y, inner_width, _h} = module.plot(measured(width, slug))
    inner_width
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
  # What each plot of the last frame cost (spec/14 §12.6, #433): a design of several
  # frames draws a canvas each, and the metrics above are their sum — this says which
  # plot the sum is made of. One plot has nothing to break down.
  defp frames_info(%{run_frame: %{plots: plots}}) when length(plots) > 1 do
    for plot <- plots do
      %{
        name: plot.name,
        bytes: plot.bytes,
        mode: (plot.incremental && plot.incremental.mode) || "full"
      }
    end
  end

  defp frames_info(_assigns), do: []

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
      <%!-- The gallery in its order, from any chart (spec/14 §12.6, #484): Previous / Next
            patch, so the view stays connected, and wrap; the arrow keys follow them. --%>
      <% {{prev_module, prev_slug}, {next_module, next_slug}} = @neighbours %>
      <nav class="chart-nav" phx-window-keyup="key">
        <a href="/" class="back-link">
          <span>&larr;</span> Back to Gallery
        </a>
        <span class="chart-nav-steps">
          <.link patch={chart_path(prev_slug)} id="chart-prev" class="chart-nav-link" rel="prev">
            <span>&larr;</span> Previous: <%= prev_module.title() %>
          </.link>
          <.link patch={chart_path(next_slug)} id="chart-next" class="chart-nav-link" rel="next">
            Next: <%= next_module.title() %> <span>&rarr;</span>
          </.link>
        </span>
      </nav>

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

        <%!-- The page measures itself (spec/10 §10, #434): the container's width is what
              the chart is drawn at, so what a person sees is what a host's container
              would show. The height is the chart's own aspect — a container sized by its
              content cannot also size it. --%>
        <div
          id="chart-box"
          phx-hook="ResizeHook"
          data-resize-event="resize"
          data-resize-debounce="150"
          class="chart-container"
          style={"background-color: #{ColorPalettes.background(@current_palette)}"}
        >
          <%!-- One frame loop (spec/14 §12.6, #362): the run's frame while a run is going, the still one
                otherwise — SVG whole, or the canvas under the compiled chart's static furniture. --%>
          <% {frame, state} = if(@run.running and @run_frame, do: {@run_frame, @run_state}, else: {@still_frame, @still_state}) %>
          <%!-- The chart is one tab stop: the arrow keys move between its points and a live
                region reads each one (spec/14 §21.5, #558). --%>
          <div id="chart-keys" phx-hook="KeyboardHook" {if @still_access, do: @still_access.keyboard, else: %{}}>
          <%= cond do %>
            <% frame == nil -> %>
              <p class="chart-pending">rendering…</p>
            <% frame.svg -> %>
              <%= Phoenix.HTML.raw(frame.svg) %>
            <% true -> %>
              <%!-- One canvas per plot at its own box (spec/14 §12.1, #432): an incremental
                    canvas is the plot area at the box's margin offset, a binary one the whole
                    box; the frames' static documents stack over them, and their backdrops — a
                    basemap's tiles — beneath them (spec/14 §12.4, #476): backdrop, canvas,
                    static SVG, dynamic SVG. --%>
              <%!-- The layers are one picture (spec/14 §21.4): the wrapper is the image a
                    screen reader meets, named and described by the summary, and every
                    SVG layer under it is aria-hidden. --%>
              <% summary = Frames.summary(state) %>
              <div class="hybrid-wrapper" style={"position: relative; width: #{run_size(state, :width)}px; height: #{run_size(state, :height)}px;"} {if summary, do: Visualize.Chart.Summary.attrs(summary, "chart-access"), else: []}>
                <%= if summary, do: Phoenix.HTML.raw(Visualize.Chart.Summary.description(summary, "chart-access")) %>
                <div :if={Frames.backdrop(state) != ""} class="hybrid-backdrop-layer" style="position: absolute; top: 0; left: 0; z-index: 0; pointer-events: none;">
                  <%= Phoenix.HTML.raw(Frames.backdrop(state)) %>
                </div>
                <div :for={plot <- frame.plots} :if={plot.backdrop != ""} class="hybrid-backdrop-layer" style="position: absolute; top: 0; left: 0; z-index: 0; pointer-events: none;">
                  <%= Phoenix.HTML.raw(plot.backdrop) %>
                </div>
                <div
                  :for={plot <- frame.plots}
                  id={"plot-#{plot_kind(plot)}-#{plot.name}"}
                  phx-hook={if plot.incremental, do: "CanvasIncrementalChart", else: "CanvasBinaryChart"}
                  phx-update="ignore"
                  data-ack="frame_drawn"
                  data-ack-interval="50"
                  data-frame={plot.name}
                  data-binary={plot.canvas}
                  data-width={canvas_size(plot, :width)}
                  data-height={canvas_size(plot, :height)}
                  style={"position: absolute; top: #{canvas_at(plot, :top)}px; left: #{canvas_at(plot, :left)}px; z-index: 1;"}
                >
                  <canvas width={canvas_size(plot, :width)} height={canvas_size(plot, :height)} style="display: block;"></canvas>
                </div>
                <div class="hybrid-static-layer" style="position: absolute; top: 0; left: 0; z-index: 2; pointer-events: none;">
                  <%= Phoenix.HTML.raw(Frames.static(state)) %>
                </div>
                <div :for={plot <- frame.plots} :if={plot.dynamic_svg != ""} class="hybrid-dynamic-layer" style="position: absolute; top: 0; left: 0; z-index: 3; pointer-events: none;">
                  <%= Phoenix.HTML.raw(plot.dynamic_svg) %>
                </div>
              </div>
          <% end %>
          </div>
        </div>
        <%!-- The data-table fallback, visually hidden (spec/14 §21.3), and the summary shown
              for the reader who wants to see what a screen reader is told. --%>
        <%= if @still_access do %>
          <%= Phoenix.HTML.raw(@still_access.table) %>
          <p class="chart-summary" aria-hidden="true" style="color: #666; font-size: 0.85rem; margin: 0.5rem 0 0;">
            <strong>Text alternative:</strong> <%= Visualize.Chart.Summary.text(@still_access.summary) %>
          </p>
        <% end %>
        <PerformanceDrawer.performance
          run={@run}
          backend={@run_backend}
          backends={Frames.backends(@module)}
          open={@drawer_open}
          compare={@compare}
          comparing={@compare_task != nil}
          stream={stream_info(assigns)}
          points={points_info(assigns)}
          frames={frames_info(assigns)}
        />

        <h3 style="margin-top: 2rem; margin-bottom: 0.5rem;"><%= backend_code_title(@run_backend) %></h3>
        <p style="color: #666; font-size: 0.9rem; margin-bottom: 0.5rem;">
          The design is the thing to copy: the <code>Visualize.Chart.Build</code> calls below fold to a map,
          and the map is the chart — applied to rows and rendered by the library, on any backend (spec/14 §16).
        </p>
        <Highlight.code code={backend_sample_code(@run_backend, @module)} />

        <h3 style="margin-top: 2rem; margin-bottom: 0.5rem;">The design (data)</h3>
        <p style="color: #666; font-size: 0.9rem; margin-bottom: 0.5rem;">
          What the Build calls fold to: the stored form the builder and a host exchange (spec/14 §1, §9).
          <code>Visualize.Chart.to_json/1</code> is the same map as JSON.
        </p>
        <Highlight.code code={@still_design || "# rendering…"} />

        <%= if @animatable do %>
          <h3 style="margin-top: 2rem; margin-bottom: 0.5rem;">LiveView Animation Code</h3>
          <Highlight.code code={animation_sample_code(@run_backend)} />
        <% end %>
      </div>
    </main>

    <style>
      <%= Phoenix.HTML.raw(PerformanceDrawer.css()) %>
      .chart-nav {
        display: flex;
        flex-wrap: wrap;
        align-items: baseline;
        justify-content: space-between;
        gap: 0.5rem 1.5rem;
        margin-bottom: 1.5rem;
      }

      .chart-nav .back-link {
        margin-bottom: 0;
      }

      .chart-nav-steps {
        display: flex;
        flex-wrap: wrap;
        gap: 0.5rem 1.5rem;
      }

      .chart-nav-link {
        color: #667eea;
        text-decoration: none;
        font-weight: 500;
      }

      .chart-nav-link:hover {
        text-decoration: underline;
      }

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

  defp chart_path(slug), do: "/chart/#{slug}"

  defp build_chart_opts(palette, tick, animating, slug, hex_radius, width) do
    # A design records no size (spec/14 §4.2, #427): the page gives one, the width its
    # container measured and the height that width at the chart's own aspect (#434).
    opts = [palette: palette] ++ measured(width, slug)

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

  # The measured width capped at the chart's design width, and the height at its aspect:
  # a design records no size and the page gives one (spec/14 §4.2, spec/10 §10.2, #434),
  # never larger than the design (#457).
  defp measured(nil, _slug), do: []

  defp measured(width, slug) do
    {w, h} = Examples.Charts.Design.fitted(Gallery.module(slug), width)
    [width: w, height: h]
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
    ~S'''
    # Canvas mode is the hybrid split (spec/14 §12): the furniture — axes, grid,
    # legend, labels — as SVG, the marks on a binary canvas beneath it.

    {:ok, applied} = Visualize.Chart.apply(design, sources: sources)
    {:ok, %{main: compiled}} = Visualize.Chart.compile(applied, ceiling: 1)
    static = Visualize.Chart.Compiled.static(compiled)          # the furniture, once
    backdrop = Visualize.Chart.Compiled.backdrop(compiled)      # a basemap's tiles, once
    {tick, compiled} = Visualize.Chart.Compiled.tick(compiled, applied.sources)
    # tick.canvas   — the marks as a base64 binary stream for the hook
    # tick.svg      — any SVG-layer marks (text, small marks) for the layer above
    # tick.backdrop — a fitted basemap's tiles, for beneath the canvas

    # In the template, the backdrop under the canvas under the static SVG:
    ~H"""
    <div style="position: relative">
      <div style="position: absolute; top: 0; left: 0; pointer-events: none">
        <%= Phoenix.HTML.raw(backdrop <> tick.backdrop) %>
      </div>
      <div id="chart" phx-hook="CanvasBinaryChart" data-binary={tick.canvas}
           style="position: absolute; top: 0; left: 0">
        <canvas width={width} height={height}></canvas>
      </div>
      <div style="position: absolute; top: 0; left: 0; pointer-events: none">
        <%= Phoenix.HTML.raw(static) %>
      </div>
    </div>
    """
    '''
  end

  defp animation_sample_code(:svg) do
    ~S'''
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
    ~H"""
    <%= Phoenix.HTML.raw(MyChart.render(animation_tick: @tick)) %>
    """

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
    '''
  end

  defp animation_sample_code(:canvas) do
    ~S"""
    # Canvas animation: compile the design once, tick it with each frame's rows.
    # The furniture (axes, grid, legend) is rendered once as SVG; a tick pushes only
    # the marks, as a binary stream, to the CanvasBinaryChart hook (spec/14 §12).

    {:ok, %{main: compiled}} = Visualize.Chart.compile(applied, ceiling: 1)
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
