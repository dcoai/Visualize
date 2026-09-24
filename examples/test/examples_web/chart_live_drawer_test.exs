defmodule ExamplesWeb.ChartLiveDrawerTest do
  @moduledoc """
  The performance drawer on a chart page (spec/14 §12.6, #322, #326): a run of the chart
  on SVG or Canvas through `Examples.Run`, frames rendered in a task, the canvas frames
  pushed with a sequence and acknowledged, Compare's rows from a task.
  """
  use ExUnit.Case, async: true

  alias Examples.Run
  alias ExamplesWeb.ChartLive

  # A page opens on the backend the chart is worth running on (#407); a test that means
  # SVG says so, as one that means Canvas or Incremental already did.
  defp page(slug, backend \\ :svg) do
    {:ok, s} = ChartLive.mount(%{"chart" => slug}, %{}, %Phoenix.LiveView.Socket{})
    {:noreply, s} = ChartLive.handle_event("set_backend", %{"backend" => to_string(backend)}, s)
    s
  end

  defp html(s),
    do:
      Phoenix.LiveViewTest.rendered_to_string(
        ChartLive.render(Map.put(s.assigns, :__changed__, %{}))
      )

  # A frame comes back from the run's renderer as `{:frame, id, frame}` (#413).
  defp settled(s) do
    id = s.assigns.run.render_id
    assert id != nil, "no frame is in flight"
    assert_receive {:frame, ^id, frame}, 10_000
    {:noreply, s} = ChartLive.handle_info({:frame, id, frame}, s)
    s
  end

  defp pushed(s), do: for([n, p] <- Phoenix.LiveView.Utils.get_push_events(s), do: {n, p[:seq]})

  test "a run's frames come from one renderer, which Stop and terminate take down (#413)" do
    s = page("incremental_line", :incremental)
    {:noreply, s} = ChartLive.handle_event("drawer_toggle", %{}, s)
    {:noreply, s} = ChartLive.handle_event("run_start", %{}, s)

    renderer = s.assigns.run.renderer
    assert is_pid(renderer) and Process.alive?(renderer)
    monitor = Process.monitor(renderer)

    # Several frames, all from the one process; the window's rows are its, never the
    # view's — the view keeps the scroll alone.
    s = settled(s)
    assert s.assigns.run_frame.incremental.mode == "full"
    refute Map.has_key?(s.assigns, :run_rows)

    s =
      Enum.reduce(1..3, s, fn _, s ->
        s =
          Phoenix.Component.assign(s,
            run: %{s.assigns.run | last_tick: s.assigns.run.last_tick - 40}
          )

        {:noreply, s} = ChartLive.handle_info(:run_tick, s)
        if s.assigns.run.render_id, do: settled(s), else: s
      end)

    assert s.assigns.run.renderer == renderer
    assert s.assigns.run_frame.incremental.mode in ["scroll_x", "none"]

    # A frame answered for a render that is no longer in flight is nothing.
    {:noreply, stale} = ChartLive.handle_info({:frame, :gone, s.assigns.run_frame}, s)
    assert stale.assigns.run_frame == s.assigns.run_frame

    {:noreply, stopped} = ChartLive.handle_event("run_stop", %{}, s)
    assert stopped.assigns.run.renderer == nil
    assert_receive {:DOWN, ^monitor, :process, ^renderer, _}, 5_000

    # A run that ends with the view takes its renderer with it.
    {:noreply, again} = ChartLive.handle_event("run_start", %{}, stopped)
    second = again.assigns.run.renderer
    assert is_pid(second) and second != renderer
    monitor = Process.monitor(second)
    ChartLive.terminate(:shutdown, again)
    assert_receive {:DOWN, ^monitor, :process, ^second, _}, 5_000
  end

  test "a renderer that dies stops the run with the reason, not the view (#413)" do
    s = page("incremental_line", :incremental)
    {:noreply, s} = ChartLive.handle_event("run_start", %{}, s)
    run = s.assigns.run
    assert is_pid(run.renderer)

    {:noreply, dead} =
      ChartLive.handle_info({:DOWN, run.monitor, :process, run.renderer, {:badarg, []}}, s)

    refute dead.assigns.run.running
    assert dead.assigns.run.error =~ "badarg"
    assert dead.assigns.run_frame == nil
  end

  test "a page opens on the backend the chart is worth running on (#407)" do
    {:ok, streaming} =
      ChartLive.mount(%{"chart" => "incremental_line"}, %{}, %Phoenix.LiveView.Socket{})

    assert streaming.assigns.run_backend == :incremental

    assert Examples.Frames.backends(Examples.Charts.IncrementalLine) == [
             :svg,
             :canvas,
             :incremental
           ]

    {:ok, scrolling} =
      ChartLive.mount(%{"chart" => "scrolling_series"}, %{}, %Phoenix.LiveView.Socket{})

    assert scrolling.assigns.run_backend == :incremental

    {:ok, still} = ChartLive.mount(%{"chart" => "line"}, %{}, %Phoenix.LiveView.Socket{})
    assert still.assigns.run_backend == :canvas
    assert Examples.Frames.backends(Examples.Charts.LineChart) == [:svg, :canvas]

    # SVG is a click away, and the buttons still switch.
    {:noreply, svg} = ChartLive.handle_event("set_backend", %{"backend" => "svg"}, still)
    assert svg.assigns.run_backend == :svg
  end

  test "the drawer is one collapsed line by default, and opens to the controls and metrics" do
    s = page("line")
    h = html(s)
    assert h =~ ~s(class="perf-drawer" id="performance-drawer")
    assert h =~ "Performance"
    assert h =~ "SVG ·\n          idle" or h =~ "SVG · idle" or h =~ ~r/SVG ·\s+idle/
    refute h =~ ~s(class="perf-drawer-body")

    {:noreply, s} = ChartLive.handle_event("drawer_toggle", %{}, s)
    h = html(s)
    assert h =~ ~s(class="perf-drawer-body")
    assert h =~ ~s(phx-click="run_backend" phx-value-backend="svg")
    assert h =~ ~s(phx-click="run_backend" phx-value-backend="canvas")
    assert h =~ ~s(phx-click="run_start")
    # An SVG frame is not acknowledged: no flow control and no ack metrics.
    refute h =~ "Flow control"
    refute h =~ "In flight"
  end

  test "an SVG run renders the chart at its animation tick in a task and shows the frame" do
    s = page("line")
    {:noreply, s} = ChartLive.handle_event("run_start", %{}, s)
    assert %Run{running: true, flow_control: false} = s.assigns.run
    assert is_pid(s.assigns.run.renderer)
    s = settled(s)
    assert %Run{frame: 1, sent_seq: 1, render_id: nil} = s.assigns.run
    assert s.assigns.run_frame.svg =~ "<svg"
    assert s.assigns.run_frame.points == 51
    assert html(s) =~ s.assigns.run_frame.svg
    assert pushed(s) == []

    {:noreply, s} = ChartLive.handle_info(:run_tick, s)
    assert is_pid(s.assigns.run.renderer)
    s = settled(s)
    assert s.assigns.run.frame == 2
    assert_receive :run_tick, 1_000

    {:noreply, s} = ChartLive.handle_event("run_stop", %{}, s)
    refute s.assigns.run.running
    assert s.assigns.run_frame == nil
  end

  test "a Canvas run compiles the design once, pushes each tick's canvas with a sequence, and is acknowledged" do
    s = page("line")
    {:noreply, s} = ChartLive.handle_event("drawer_toggle", %{}, s)
    {:noreply, s} = ChartLive.handle_event("run_backend", %{"backend" => "canvas"}, s)
    {:noreply, s} = ChartLive.handle_event("run_start", %{}, s)
    assert %{compiled: %Visualize.Chart.Compiled{}, static: static} = s.assigns.run_state
    assert s.assigns.run.flow_control
    s = settled(s)
    assert pushed(s) == [{"canvas_update", 1}]
    assert s.assigns.run_frame.canvas != nil and s.assigns.run_frame.svg == nil
    h = html(s)
    assert h =~ ~s(data-ack="frame_drawn")
    assert h =~ static
    assert h =~ "Flow control ON (250 ms)"

    {:noreply, s} = ChartLive.handle_event("frame_drawn", %{"seq" => 1, "drawn" => 1}, s)
    assert Run.in_flight(s.assigns.run) == 0

    {:noreply, s} = ChartLive.handle_info(:run_tick, s)
    s = settled(s)
    assert pushed(s) == [{"canvas_update", 1}, {"canvas_update", 2}]
    assert s.assigns.run.frame == 2
  end

  test "the last chart converted runs on the split like every other (#348)" do
    s = page("hexbin")
    {:noreply, s} = ChartLive.handle_event("run_backend", %{"backend" => "canvas"}, s)
    {:noreply, s} = ChartLive.handle_event("run_start", %{}, s)
    assert %{compiled: %Visualize.Chart.Compiled{}} = s.assigns.run_state
    s = settled(s)
    assert s.assigns.run_frame.canvas != nil
    assert pushed(s) == [{"canvas_update", 1}]
  end

  test "Compare runs the chart through each backend in a task and tables the rows" do
    s = page("line")
    {:noreply, s} = ChartLive.handle_event("run_compare", %{}, s)
    %Task{ref: ref} = s.assigns.compare_task
    assert_receive {^ref, {:compare, rows} = result}, 30_000
    {:noreply, s} = ChartLive.handle_info({ref, result}, s)
    assert s.assigns.compare_task == nil
    assert [%{backend: :svg, ticks: 100}, %{backend: :canvas, ticks: 100}] = rows
    {:noreply, s} = ChartLive.handle_event("drawer_toggle", %{}, s)
    h = html(s)
    assert h =~ "This chart, 100 ticks per backend, headless"
    assert h =~ "<td>SVG</td>" and h =~ "<td>Canvas</td>"
  end

  test "a streaming design runs incrementally at a data rate: the window advances by whole columns and the strip is pushed with a sequence (#327)" do
    s = page("scrolling_series")
    {:noreply, s} = ChartLive.handle_event("drawer_toggle", %{}, s)
    {:noreply, s} = ChartLive.handle_event("run_backend", %{"backend" => "incremental"}, s)
    {:noreply, s} = ChartLive.handle_event("run_data_rate", %{"data_rate" => "600"}, s)
    assert %Examples.Scroll{inner_width: 810, samples_per_px: 4, origin: 0} = s.assigns.run_scroll
    h = html(s)
    assert h =~ ~s(phx-value-backend="incremental")
    assert h =~ "Data rate" and h =~ "4/px · 3241 samples · 5.4 s across"

    {:noreply, s} = ChartLive.handle_event("run_start", %{}, s)
    assert s.assigns.run.data_rate == 600 and s.assigns.run.flow_control
    s = settled(s)
    assert s.assigns.run_frame.incremental.mode == "full"
    assert pushed(s) == [{"canvas_incremental", 1}]
    h = html(s)
    assert h =~ ~s(phx-hook="CanvasIncrementalChart")
    assert h =~ "top: 40px; left: 60px"

    # 16 ms at 600/s is 9 samples: two columns at four per pixel, one sample pending.
    s =
      Phoenix.Component.assign(s, run: %{s.assigns.run | last_tick: s.assigns.run.last_tick - 16})

    {:noreply, s} = ChartLive.handle_info(:run_tick, s)
    # The origin the frame was asked for: `settled/1` may let a later tick advance it.
    origin = s.assigns.run_scroll.origin
    assert origin >= 8 and rem(origin, 4) == 0
    s = settled(s)
    assert %{mode: "scroll_x", dx: dx} = s.assigns.run_frame.incremental
    assert dx == div(origin, 4)
    assert pushed(s) == [{"canvas_incremental", 1}, {"canvas_incremental", 2}]
    assert s.assigns.run_frame.bytes < 30_000

    {:noreply, s} = ChartLive.handle_event("run_stop", %{}, s)
    refute s.assigns.run.running
  end

  test "a streaming design's drawer opens with the data rate at 600 and its window; another chart's at 20 ticks/s (#359, #361)" do
    s = page("scrolling_series")
    assert s.assigns.run.data_rate == 600
    assert %Examples.Scroll{samples_per_px: 4, origin: 0} = s.assigns.run_scroll
    assert s.assigns.run_series == 5
    {:noreply, s} = ChartLive.handle_event("drawer_toggle", %{}, s)
    h = html(s)
    assert h =~ ~s(id="perf-rate") and h =~ ~s(value="600")
    assert h =~ "4/px · 3241 samples · 5.4 s across"
    assert h =~ "Pts/s" and h =~ "Total points" and h =~ "Pts/frame" and h =~ "Mode"
    assert h =~ ">16205<"

    line = page("line")
    assert line.assigns.run.data_rate == 20 and line.assigns.run_scroll == nil
    {:noreply, line} = ChartLive.handle_event("drawer_toggle", %{}, line)
    h = html(line)
    assert h =~ ~s(id="perf-rate") and h =~ ~s(value="20") and h =~ "20 ticks/s"
    assert h =~ "Ticks/s" and h =~ "Total points" and h =~ "Pts/frame"
    refute h =~ "samples across"
  end

  test "the data rate is live: a tick chart takes it at once, a streaming window keeps its instant and resyncs (#401)" do
    # The slider is never disabled, running or not.
    s = page("area")
    {:noreply, s} = ChartLive.handle_event("drawer_toggle", %{}, s)
    refute html(s) =~ ~s(class="perf-slider" disabled)
    {:noreply, s} = ChartLive.handle_event("run_start", %{}, s)
    s = settled(s)
    refute html(s) =~ ~s(class="perf-slider" disabled)

    # A tick chart takes the rate mid-run; nothing else changes.
    {:noreply, s} = ChartLive.handle_event("run_data_rate", %{"data_rate" => "7"}, s)
    assert s.assigns.run.data_rate == 7
    assert s.assigns.run.running
    assert s.assigns.run_scroll == nil
    assert html(s) =~ "7 ticks/s"

    # A streaming design: the window is retimed, its instant kept, and the next frame is
    # a full redraw rather than a copy-shift at the old density.
    t = page("scrolling_series")
    {:noreply, t} = ChartLive.handle_event("drawer_toggle", %{}, t)
    {:noreply, t} = ChartLive.handle_event("set_backend", %{"backend" => "incremental"}, t)
    {:noreply, t} = ChartLive.handle_event("run_start", %{}, t)
    t = settled(t)
    t = Phoenix.Component.assign(t, run_scroll: Examples.Scroll.advance(t.assigns.run_scroll, 40))
    %{origin: origin, samples_per_px: density} = t.assigns.run_scroll
    assert origin > 0
    t = update_in(t.assigns.run, &%{&1 | needs_full: false})

    {:noreply, t} = ChartLive.handle_event("run_data_rate", %{"data_rate" => "60"}, t)
    assert t.assigns.run.data_rate == 60
    assert t.assigns.run_scroll.origin == origin
    assert t.assigns.run_scroll.samples_per_px < density
    assert t.assigns.run.needs_full
    assert {_run, :full_redraw} = Run.decide(t.assigns.run, 1, true, {700, 1}, 0)
  end

  test "a chart that animates by tick moves its data at the data rate, not the frame rate (#361)" do
    s = page("area")
    {:noreply, s} = ChartLive.handle_event("drawer_toggle", %{}, s)
    {:noreply, s} = ChartLive.handle_event("run_data_rate", %{"data_rate" => "10"}, s)
    {:noreply, s} = ChartLive.handle_event("run_start", %{}, s)
    assert s.assigns.run_ticks == 0
    s = settled(s)
    frame0 = s.assigns.run_frame.svg

    # 100 ms at 10 ticks/s is one tick: the next frame is the chart at tick 1.
    s =
      Phoenix.Component.assign(s,
        run: %{s.assigns.run | last_tick: s.assigns.run.last_tick - 100, carry: 0.0}
      )

    {:noreply, s} = ChartLive.handle_info(:run_tick, s)
    assert s.assigns.run_ticks >= 1
    s = settled(s)
    refute s.assigns.run_frame.svg == frame0
    assert html(s) =~ ">full<"

    # At rate 0 frames keep coming and the tick stays: the frame rate moves nothing.
    still =
      Phoenix.Component.assign(s, run: %{s.assigns.run | data_rate: 0, carry: 0.0, pending: 0})

    ticks = still.assigns.run_ticks
    {:noreply, still} = ChartLive.handle_info(:run_tick, still)
    assert still.assigns.run_ticks == ticks and still.assigns.run.render_id != nil
    {:noreply, s} = ChartLive.handle_event("run_stop", %{}, s)
    refute s.assigns.run.running
  end

  test "an SVG run of a streaming design advances the window by the rate, not the frame rate (#359)" do
    s = page("scrolling_series")
    {:noreply, s} = ChartLive.handle_event("drawer_toggle", %{}, s)
    {:noreply, s} = ChartLive.handle_event("run_start", %{}, s)
    s = settled(s)
    assert s.assigns.run_frame.svg =~ "<svg" and s.assigns.run_mode == "full"
    origin = s.assigns.run_scroll.origin

    # 16 ms at 600/s is 9 samples, two whole columns at four per pixel — plus whatever
    # the render's own time let arrive; the window moves by whole columns of samples.
    s =
      Phoenix.Component.assign(s, run: %{s.assigns.run | last_tick: s.assigns.run.last_tick - 16})

    {:noreply, s} = ChartLive.handle_info(:run_tick, s)
    assert s.assigns.run_scroll.origin >= origin + 8 and rem(s.assigns.run_scroll.origin, 4) == 0
    s = settled(s)
    assert s.assigns.run_frame.svg =~ "<svg"
    h = html(s)
    assert h =~ ">full<" and h =~ ">16205<"

    # With no data rate nothing arrives, so a tick draws a frame and the window stays.
    still =
      Phoenix.Component.assign(s, run: %{s.assigns.run | data_rate: 0, carry: 0.0, pending: 0})

    {:noreply, still} = ChartLive.handle_info(:run_tick, still)
    assert still.assigns.run_scroll.origin == s.assigns.run_scroll.origin
    {:noreply, s} = ChartLive.handle_event("run_stop", %{}, s)
    refute s.assigns.run.running
  end

  test "a design with a transition runs on SVG through a compiled chart whose scale eases, and animates through one on the page (#360)" do
    s = page("area")
    assert Examples.Charts.Design.transitions?(Examples.Charts.AreaChart)
    {:noreply, s} = ChartLive.handle_event("run_start", %{}, s)
    assert %{compiled: %Visualize.Chart.Compiled{}} = s.assigns.run_state
    s = settled(s)

    assert s.assigns.run_frame.svg =~ "<svg" and
             s.assigns.run_frame.svg =~ ~s(class="mark mark-area")

    # The easing lives in the run's renderer, which holds the compiled chart (#413).
    assert %{y: %{shown: [+0.0, _]}} =
             Examples.Renderer.state(s.assigns.run.renderer).compiled.eased

    {:noreply, s} = ChartLive.handle_event("run_stop", %{}, s)
    refute s.assigns.run.running

    # The page's Animate button is the same run (#362): one frame loop, one renderer.
    {:noreply, s} = ChartLive.handle_event("toggle_animation", %{}, s)
    assert %Run{running: true} = s.assigns.run
    assert is_pid(s.assigns.run.renderer)
    assert %{compiled: %Visualize.Chart.Compiled{}} = s.assigns.run_state
    s = settled(s)
    assert html(s) =~ ~s(class="mark mark-area") and html(s) =~ "Stop Animation"
    {:noreply, s} = ChartLive.handle_event("toggle_animation", %{}, s)
    refute s.assigns.run.running
  end

  test "the still chart is rendered in place on a disconnected mount, and re-rendered on a change; no frame in render/1 (#362)" do
    s = page("line")
    assert %{svg: svg} = s.assigns.still_frame
    assert svg =~ ~s(class="mark mark-line") and s.assigns.still_design =~ "kind: :cartesian"
    assert html(s) =~ svg

    # A backend change renders the still frame for that backend: the split's layers.
    {:noreply, s} = ChartLive.handle_event("set_backend", %{"backend" => "canvas"}, s)
    assert s.assigns.run_backend == :canvas
    assert %{canvas: canvas, svg: nil} = s.assigns.still_frame
    assert is_binary(canvas) and s.assigns.still_state.static =~ "<svg"
    assert html(s) =~ ~s(phx-hook="CanvasBinaryChart")

    # A palette change re-renders it too; the page's backend buttons are the run's.
    {:noreply, s} = ChartLive.handle_event("change_palette", %{"palette" => "dark"}, s)
    assert s.assigns.still_frame.dynamic_svg =~ "#e6e6e6"
    assert html(s) =~ ~s(phx-value-backend="svg")
    refute html(s) =~ "Canvas-Incremental"
    assert html(page("scrolling_series")) =~ "Canvas-Incremental"
  end

  test "/high-performance is the Scrolling series chart's page now" do
    import Phoenix.ConnTest

    conn =
      build_conn() |> Phoenix.ConnTest.dispatch(ExamplesWeb.Endpoint, :get, "/high-performance")

    assert redirected_to(conn) == "/chart/scrolling_series"
  end
end
