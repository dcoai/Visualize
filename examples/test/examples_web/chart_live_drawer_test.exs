defmodule ExamplesWeb.ChartLiveDrawerTest do
  @moduledoc """
  The performance drawer on a chart page (spec/14 §12.6, #322, #326): a run of the chart
  on SVG or Canvas through `Examples.Run`, frames rendered in a task, the canvas frames
  pushed with a sequence and acknowledged, Compare's rows from a task.
  """
  use ExUnit.Case, async: true

  alias Examples.Run
  alias ExamplesWeb.ChartLive

  defp page(slug) do
    {:ok, s} = ChartLive.mount(%{"chart" => slug}, %{}, %Phoenix.LiveView.Socket{})
    s
  end

  defp html(s),
    do:
      Phoenix.LiveViewTest.rendered_to_string(
        ChartLive.render(Map.put(s.assigns, :__changed__, %{}))
      )

  defp settled(s) do
    %Task{ref: ref} = s.assigns.run.task
    assert_receive {^ref, result}, 10_000
    {:noreply, s} = ChartLive.handle_info({ref, result}, s)
    s
  end

  defp pushed(s), do: for([n, p] <- Phoenix.LiveView.Utils.get_push_events(s), do: {n, p[:seq]})

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
    assert %Run{running: true, task: %Task{}, flow_control: false} = s.assigns.run
    refute s.assigns.animating
    s = settled(s)
    assert %Run{frame: 1, sent_seq: 1, task: nil} = s.assigns.run
    assert s.assigns.run_frame.svg =~ "<svg"
    assert s.assigns.run_frame.points == 51
    assert html(s) =~ s.assigns.run_frame.svg
    assert pushed(s) == []

    {:noreply, s} = ChartLive.handle_info(:run_tick, s)
    assert %Task{} = s.assigns.run.task
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
    assert s.assigns.run_scroll.origin >= 8 and rem(s.assigns.run_scroll.origin, 4) == 0
    s = settled(s)
    assert %{mode: "scroll_x", dx: dx} = s.assigns.run_frame.incremental
    assert dx == div(s.assigns.run_scroll.origin, 4)
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
    assert still.assigns.run_ticks == ticks and still.assigns.run.task != nil
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

    assert %{y: %{shown: [+0.0, _]}} = s.assigns.run_state.compiled.eased
    {:noreply, s} = ChartLive.handle_event("run_stop", %{}, s)
    refute s.assigns.run.running

    # The page's own animation keeps a compiled chart and shows its stepped frame.
    {:noreply, s} = ChartLive.handle_event("toggle_animation", %{}, s)
    assert %Visualize.Chart.Compiled{} = s.assigns.page_compiled
    assert s.assigns.page_svg =~ ~s(class="mark mark-area")
    {:noreply, s} = ChartLive.handle_info(:animate_tick, s)
    assert s.assigns.animation_tick == 1 and s.assigns.page_svg =~ "<svg"
    assert html(s) =~ ~s(class="mark mark-area")
    {:noreply, s} = ChartLive.handle_event("toggle_animation", %{}, s)
    assert s.assigns.page_compiled == nil and s.assigns.page_svg == nil

    # A chart with no transition keeps the stateless path.
    line = page("scrolling_series")
    refute Examples.Charts.Design.transitions?(Examples.Charts.ScrollingSeries)
    {:noreply, line} = ChartLive.handle_event("toggle_animation", %{}, line)
    assert line.assigns.page_compiled == nil
  end

  test "/high-performance is the Scrolling series chart's page now" do
    import Phoenix.ConnTest

    conn =
      build_conn() |> Phoenix.ConnTest.dispatch(ExamplesWeb.Endpoint, :get, "/high-performance")

    assert redirected_to(conn) == "/chart/scrolling_series"
  end
end
