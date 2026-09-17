defmodule ExamplesWeb.HighPerformanceFlowTest do
  @moduledoc """
  The High-Performance page on `Examples.Run` (#322): a run opens with a full frame
  rendered in a task, a tick scrolls the window by the run's columns and renders the
  strips, a result is numbered and pushed, a no-column tick sends the empty update, and
  Stop cancels a render in flight. The loop's own rules are `Examples.RunTest`'s.
  """
  use ExUnit.Case, async: true

  alias Examples.Run
  alias ExamplesWeb.HighPerformanceLive, as: Page

  defp started do
    {:ok, s} = Page.mount(%{}, %{}, %Phoenix.LiveView.Socket{})
    {:noreply, s} = Page.handle_event("start", %{}, s)
    s
  end

  # The render in flight, awaited and handed back to the page.
  defp settled(s) do
    %Task{ref: ref} = s.assigns.run.task
    assert_receive {^ref, result}, 5_000
    {:noreply, s} = Page.handle_info({ref, result}, s)
    {s, result}
  end

  # A tick 16 ms after the last, as the clock would have it.
  defp tick(s) do
    s = Phoenix.Component.assign(s, run: %{s.assigns.run | last_tick: s.assigns.run.last_tick - 16})
    {:noreply, s} = Page.handle_info(:render_frame, s)
    s
  end

  defp pushed(s), do: for([_, p] <- Phoenix.LiveView.Utils.get_push_events(s), do: {p.mode, p.seq})

  test "a run opens with a full frame in a task, numbered 1 when it lands" do
    s = started()
    assert %Run{running: true, needs_full: true, task: %Task{}} = s.assigns.run
    assert pushed(s) == []
    {s, result} = settled(s)
    assert result.mode == :full_redraw and result.bytes > 0
    assert %Run{frame: 1, sent_seq: 1, needs_full: false, task: nil} = s.assigns.run
    assert pushed(s) == [{"full", 1}]
    assert s.assigns.points_rendered == s.assigns.total_points
  end

  test "a tick scrolls the window by the columns due and renders the strips; a no-column tick is the empty update" do
    {s, _} = settled(started())
    s = tick(s)
    origin = s.assigns.scroll.origin
    assert origin > 0
    assert s.assigns.viewport_x == div(origin, s.assigns.samples_per_px)
    {s, result} = settled(s)
    assert result.mode == :scroll_x and result.payload.dx == div(origin, s.assigns.samples_per_px)
    assert pushed(s) == [{"full", 1}, {"scroll_x", 2}]
    assert s.assigns.run.frame == 2 and s.assigns.points_rendered > 0

    # No time passed: no samples, no column, the empty update straight from the tick.
    {:noreply, s} = Page.handle_info(:render_frame, s)
    assert s.assigns.run.task == nil
    assert List.last(pushed(s)) == {"none", 3}
  end

  test "a tick during a render is skipped, and Stop cancels the render in flight" do
    {s, _} = settled(started())
    s = tick(s)
    %Task{pid: pid} = s.assigns.run.task
    s = tick(s)
    assert s.assigns.run.skipped == 1
    mon = Process.monitor(pid)
    {:noreply, s} = Page.handle_event("stop", %{}, s)
    assert %Run{running: false, task: nil} = s.assigns.run
    assert_receive {:DOWN, ^mon, :process, ^pid, _}, 5_000
    assert pushed(s) == [{"full", 1}]
  end

  test "the sliders write the run, and a rate that changes the density asks for a full frame" do
    {:ok, s} = Page.mount(%{}, %{}, %Phoenix.LiveView.Socket{})
    {:noreply, s} = Page.handle_event("set_fps", %{"fps" => "120"}, s)
    assert s.assigns.run.target_fps == 120
    {:noreply, s} = Page.handle_event("toggle_flow_control", %{}, s)
    refute s.assigns.run.flow_control
    {:noreply, s} = Page.handle_event("frame_drawn", %{"seq" => 3, "drawn" => 3}, s)
    assert s.assigns.run.acked_seq == 3
    {:noreply, s} = Page.handle_event("set_data_rate", %{"data_rate" => "10"}, s)
    assert s.assigns.run.data_rate == 10 and s.assigns.samples_per_px == 1 and s.assigns.run.needs_full
  end
end
