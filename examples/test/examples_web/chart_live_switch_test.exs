defmodule ExamplesWeb.ChartLiveSwitchTest do
  @moduledoc """
  A backend switched while a run goes on (spec/14 §12.6, #502, D-128): the renderer
  re-prepares in place, the run's tick, rows and window carry over, the next frame is
  full, acks from the old backend do not count, the drawer starts a new segment, and a
  backend the chart does not offer is refused.
  """
  use ExUnit.Case, async: true

  alias Examples.{Renderer, Run}
  alias ExamplesWeb.ChartLive

  defp page(slug, backend) do
    {:ok, s} = ChartLive.mount(%{"chart" => slug}, %{}, %Phoenix.LiveView.Socket{})
    {:noreply, s} = ChartLive.handle_event("set_backend", %{"backend" => to_string(backend)}, s)
    {:noreply, s} = ChartLive.handle_event("drawer_toggle", %{}, s)
    {:noreply, s} = ChartLive.handle_event("run_start", %{}, s)
    settled(s)
  end

  defp html(s),
    do:
      Phoenix.LiveViewTest.rendered_to_string(
        ChartLive.render(Map.put(s.assigns, :__changed__, %{}))
      )

  defp settled(s) do
    id = s.assigns.run.render_id
    assert id != nil, "no frame is in flight"
    assert_receive {:frame, ^id, frame}, 10_000
    {:noreply, s} = ChartLive.handle_info({:frame, id, frame}, s)
    s
  end

  # A tick `ms` after the last, its frame settled. The tick reads the real clock, so its
  # elapsed time is `ms` plus however long the test took since the last one — under load,
  # long enough for a sample or two at the line's 20 a second (#512).
  defp ticked(s, ms) do
    s =
      Phoenix.Component.assign(s, run: %{s.assigns.run | last_tick: s.assigns.run.last_tick - ms})

    {:noreply, s} = ChartLive.handle_info(:run_tick, s)
    settled(s)
  end

  # The samples the last tick counted at the data rate, from the run's own record of it:
  # a chart that animates by tick advances by exactly these (#361), so a test asserts the
  # tick against them rather than against a clock it does not hold (#512).
  defp arrived(s), do: s.assigns.run.arrivals |> hd() |> elem(1)

  defp switch(s, backend) do
    {:noreply, s} = ChartLive.handle_event("run_backend", %{"backend" => to_string(backend)}, s)
    s
  end

  # A canvas backend's state: compiled charts at a ceiling of one, with the static layers;
  # SVG's: compiled charts at a ceiling past any mark, nothing else.
  defp canvas_state?(%{compiled: [{_, %{ceiling: 1}} | _], static: _, backdrop: _}), do: true
  defp canvas_state?(_state), do: false

  defp svg_state?(%{compiled: [{_, %{ceiling: ceiling}} | _]} = state),
    do: Enum.sort(Map.keys(state)) == [:compiled, :summary] and ceiling > 1

  defp svg_state?(_state), do: false

  defp pushed(s), do: for([n, p] <- Phoenix.LiveView.Utils.get_push_events(s), do: {n, p[:seq]})
  defp rows(s), do: :sys.get_state(s.assigns.run.renderer).rows

  defp ack(s, seq),
    do: elem(ChartLive.handle_event("frame_drawn", %{"seq" => seq, "drawn" => 1}, s), 1)

  test "SVG → Canvas mid-run: one renderer re-prepared in place, tick and rows kept, the markup swapped with the first full frame" do
    s = page("line", :svg) |> ticked(100) |> ticked(100)
    renderer = s.assigns.run.renderer
    ticks = s.assigns.run_ticks
    assert ticks > 0
    assert s.assigns.run_frame.svg =~ "<svg"
    # The line eases its y scale, so SVG keeps a compiled chart too — with no canvas.
    assert svg_state?(Renderer.state(renderer))
    sent = s.assigns.run.sent_seq

    s = switch(s, :canvas)

    # The run goes on — the same renderer, now on Canvas — at the tick it was at.
    assert s.assigns.run.running and s.assigns.run_backend == :canvas
    assert s.assigns.run.renderer == renderer and Renderer.backend(renderer) == :canvas
    assert canvas_state?(Renderer.state(renderer))
    assert s.assigns.run_ticks == ticks
    assert s.assigns.run.needs_full and s.assigns.run.seq_floor == sent

    # Until the first Canvas frame arrives, the page shows the last SVG frame over no
    # canvas furniture.
    h = html(s)
    assert h =~ "<svg" and not (h =~ "hybrid-wrapper")

    s = ticked(s, 1)
    # The tick carried over: the first Canvas frame is the chart at the tick the SVG run
    # was at, plus what this tick counted — never a counter started again.
    assert s.assigns.run_ticks == ticks + arrived(s)
    assert %{svg: nil, plots: [%{canvas: canvas}]} = s.assigns.run_frame
    assert is_binary(canvas)
    assert [{"canvas_update", seq}] = pushed(s)
    assert seq == sent + 1
    h = html(s)
    assert h =~ ~s(id="plot-canvas-main") and h =~ ~s(phx-hook="CanvasBinaryChart")
    assert h =~ Examples.Frames.static(s.assigns.run_state)
    refute s.assigns.run.needs_full
  end

  test "Canvas → SVG mid-run: the canvas state is released and the next frame is the whole SVG" do
    s = page("line", :canvas) |> ticked(100)
    renderer = s.assigns.run.renderer
    ticks = s.assigns.run_ticks
    assert canvas_state?(Renderer.state(renderer))
    [{_name, %{eased: eased}}] = Renderer.state(renderer).compiled

    s = switch(s, :svg)
    # Released: the canvas's compiled chart and static furniture are gone from the
    # renderer, which holds SVG's own state — the easing carried over (#434).
    state = Renderer.state(renderer)
    assert svg_state?(state) and Renderer.backend(renderer) == :svg
    assert [{_name, %{eased: ^eased}}] = state.compiled
    refute s.assigns.run.flow_control
    canvas_pushes = pushed(s)

    s = ticked(s, 1)
    assert s.assigns.run_ticks == ticks + arrived(s)
    assert s.assigns.run_frame.svg =~ "<svg" and s.assigns.run_frame.plots == []
    # An SVG frame travels in the diff: nothing more is pushed.
    assert pushed(s) == canvas_pushes
    h = html(s)
    refute h =~ "plot-canvas-main"
    assert h =~ "<svg"
  end

  test "a streaming design keeps its rows and window origin across SVG → Incremental → Canvas → SVG; each first frame is full" do
    s = page("scrolling_series", :svg) |> ticked(40) |> ticked(40)
    origin = s.assigns.run_scroll.origin
    assert origin > 0
    held = rows(s)

    s = switch(s, :incremental)
    assert rows(s) == held
    assert s.assigns.run_scroll.origin == origin

    # The incremental chart is compiled afresh, so its first record is the full one.
    s = ticked(s, 1)
    %{plots: [%{incremental: record}]} = s.assigns.run_frame
    assert record.mode == "full"

    assert [{:full_redraw, _viewport, _records}] =
             record.binary |> Base.decode64!() |> Visualize.Backend.CanvasBinary.Decoder.decode()

    assert html(s) =~ ~s(id="plot-incremental-main")

    # Then it scrolls, as a run on Incremental does.
    s = ticked(s, 40)
    %{plots: [%{incremental: next}]} = s.assigns.run_frame
    assert next.mode in ["scroll_x", "none"]

    # To Canvas: a streaming design's compiled chart draws incremental records there too,
    # so the element and its hook are the same kind — and the chart, compiled afresh,
    # starts again from a full record, which the hook draws whole.
    origin = s.assigns.run_scroll.origin
    s = switch(s, :canvas)
    assert s.assigns.run_scroll.origin == origin
    s = ticked(s, 1)
    %{plots: [%{incremental: again}]} = s.assigns.run_frame
    assert again.mode == "full"
    assert html(s) =~ ~s(id="plot-incremental-main")

    s = switch(s, :svg) |> ticked(1)
    assert s.assigns.run_frame.svg =~ "<svg"
    assert s.assigns.run.running
  end

  test "a frame asked of the old backend before the switch is stale and never reaches the page" do
    s = page("line", :canvas)

    s =
      Phoenix.Component.assign(s,
        run: %{s.assigns.run | last_tick: s.assigns.run.last_tick - 100}
      )

    {:noreply, s} = ChartLive.handle_info(:run_tick, s)
    old = s.assigns.run.render_id
    assert old != nil

    s = switch(s, :svg)
    assert s.assigns.run.render_id == nil
    assert_receive {:frame, ^old, frame}, 10_000
    assert frame.svg == nil
    {:noreply, after_stale} = ChartLive.handle_info({:frame, old, frame}, s)
    assert after_stale.assigns.run_frame == s.assigns.run_frame
    assert after_stale.assigns.run == s.assigns.run
    assert after_stale.assigns.run_ticks == s.assigns.run_ticks
  end

  test "acks for the old backend's sequences do not count; the new backend's do, with flow control as the reader left it" do
    s = page("line", :canvas) |> ticked(100) |> ticked(100)
    assert s.assigns.run.flow_control
    {:noreply, s} = ChartLive.handle_event("run_flow_control", %{}, s)
    {:noreply, s} = ChartLive.handle_event("run_flow_control", %{}, s)
    sent = s.assigns.run.sent_seq
    s = ack(s, 1)
    assert s.assigns.run.acked_seq == 1

    s = switch(s, :svg)
    assert Run.in_flight(s.assigns.run) == 0

    # The old hook's trailing acks arrive: neither a frame drawn nor a sign of life.
    stale = ack(s, sent)
    assert stale.assigns.run == s.assigns.run
    assert stale.assigns.run.acking == :unknown and stale.assigns.run.last_ack_at == nil

    # Through SVG and back: flow control as the reader chose it, the floor raised again.
    s = ticked(s, 1)
    s = switch(s, :canvas)
    assert s.assigns.run.flow_control
    floor = s.assigns.run.seq_floor
    assert floor == sent + 1
    assert ack(s, floor).assigns.run == s.assigns.run

    s = ticked(s, 1)
    s = ack(s, floor + 1)
    assert s.assigns.run.acked_seq == floor + 1 and s.assigns.run.acking == :yes
    assert Run.in_flight(s.assigns.run) == 0
  end

  test "the drawer starts a new segment at the switch, and segments never mix" do
    s = page("line", :canvas) |> ticked(100) |> ticked(100)
    assert s.assigns.run.frame == 3
    refute html(s) =~ "This run, by backend"
    render_times = s.assigns.run.render_times

    s = switch(s, :svg)
    run = s.assigns.run
    assert run.frame == 0 and run.fps == 0.0 and run.render_times == [] and run.payload_size == 0
    assert run.acks == [] and run.dropped == 0 and run.skipped == 0
    assert [%{backend: :canvas, frames: 3} = canvas] = run.segments
    assert canvas.avg_render_us == Enum.sum(render_times) / length(render_times)

    s = ticked(s, 1)
    assert s.assigns.run.frame == 1 and length(s.assigns.run.render_times) == 1
    assert s.assigns.run.payload_size == s.assigns.run_frame.bytes
    assert [^canvas] = s.assigns.run.segments

    h = html(s)
    assert h =~ "This run, by backend"
    [table] = Regex.run(~r/<table[^>]*perf-segments.*?<\/table>/s, h)
    assert table =~ ~r/SVG\s*\(now\)/
    assert [_now, _canvas] = Regex.scan(~r/<tr class="perf-segment/, table)

    # A new run starts with no segments.
    {:noreply, s} = ChartLive.handle_event("run_stop", %{}, s)
    {:noreply, s} = ChartLive.handle_event("run_start", %{}, s)
    assert s.assigns.run.segments == []
  end

  test "a backend the chart does not offer is refused, running or not, and makes no atom" do
    s = page("line", :canvas)

    assert {:noreply, ^s} =
             ChartLive.handle_event("run_backend", %{"backend" => "incremental"}, s)

    assert {:noreply, ^s} = ChartLive.handle_event("set_backend", %{"backend" => "canvas"}, s)
    name = "no_backend_#{System.unique_integer([:positive])}"
    assert {:noreply, ^s} = ChartLive.handle_event("run_backend", %{"backend" => name}, s)
    assert_raise ArgumentError, fn -> String.to_existing_atom(name) end

    {:noreply, s} = ChartLive.handle_event("run_stop", %{}, s)

    assert {:noreply, ^s} =
             ChartLive.handle_event("run_backend", %{"backend" => "incremental"}, s)
  end

  test "the backend buttons and the drawer's chips stay live during a run" do
    s = page("line", :svg)
    h = html(s)
    buttons = Regex.scan(~r/<button[^>]*phx-value-backend="[^"]*"[^>]*>/, h) |> List.flatten()
    assert length(buttons) == 4
    for button <- buttons, do: refute(button =~ "disabled")
  end
end
