defmodule ExamplesWeb.HighPerformanceFlowTest do
  @moduledoc """
  The High-Performance page's frames in flight (#304, D-107): every frame carries its
  sequence, the hook's acks move `acked_seq`, flow control holds frames back while the
  window is in flight, and the first frame after a dropped scroll is a full render.
  """
  use ExUnit.Case, async: true

  alias ExamplesWeb.HighPerformanceLive, as: Page

  defp started(data_rate \\ nil) do
    {:ok, s} = Page.mount(%{}, %{}, %Phoenix.LiveView.Socket{})

    {:noreply, s} =
      if data_rate, do: Page.handle_event("set_data_rate", %{"data_rate" => "#{data_rate}"}, s), else: {:noreply, s}

    {:noreply, s} = Page.handle_event("start", %{}, s)
    s
  end

  # A tick 16 ms after the last, as the clock would have it.
  defp tick(s) do
    s = Phoenix.Component.assign(s, last_tick: s.assigns.last_tick - 16)
    {:noreply, s} = Page.handle_info(:render_frame, s)
    s
  end

  defp modes(s) do
    for [_, payload] <- Phoenix.LiveView.Utils.get_push_events(s), do: {payload.seq, payload.mode}
  end

  test "every frame carries its sequence and the start's full render is frame 1" do
    s = started()
    assert [{1, "full"}] = modes(s)
    assert s.assigns.sent_seq == 1 and s.assigns.acked_seq == 0

    s = tick(s)
    assert [{1, "full"}, {2, "scroll_x"}] = modes(s)
    assert Page.in_flight(s.assigns) == 2
  end

  test "the window is a lag budget: 250 ms of frames at the target rate (#310)" do
    assert Page.window(%{target_fps: 60}) == 15
    assert Page.window(%{target_fps: 500}) == 125
    assert Page.window(%{target_fps: 2010}) == 500
    assert Page.window(%{target_fps: 10}) == 3
  end

  test "flow control holds frames back at the window, and a dropped scroll resyncs with a full frame" do
    s = started()
    w = Page.window(s.assigns)
    s = Enum.reduce(1..(w + 4), s, fn _, s -> tick(s) end)
    # The window in flight and no ack: the later ticks sent nothing and were dropped.
    assert s.assigns.sent_seq == w
    assert s.assigns.dropped == 5
    assert s.assigns.needs_full
    assert Page.frame_mode(s.assigns, 4) == :drop

    # The hook acks the last frame: the window opens and the next frame is a full render —
    # the canvas missed scrolls, so a strip would be the wrong picture.
    {:noreply, s} = Page.handle_event("frame_drawn", %{"seq" => w, "drawn" => w}, s)
    assert Page.in_flight(s.assigns) == 0
    assert Page.frame_mode(s.assigns, 4) == :full_redraw
    s = tick(s)
    assert List.last(modes(s)) == {w + 1, "full"}
    refute s.assigns.needs_full
    assert s.assigns.sent_seq == w + 1

    # With that acked, the frames go as strips again.
    {:noreply, s} = Page.handle_event("frame_drawn", %{"seq" => w + 1, "drawn" => 1}, s)
    assert Page.frame_mode(s.assigns, 4) == :scroll_x
  end

  test "with flow control off every tick sends, and the backlog is visible" do
    {:noreply, s} = Page.handle_event("toggle_flow_control", %{}, started())
    s = Enum.reduce(1..20, s, fn _, s -> tick(s) end)
    assert s.assigns.sent_seq == 21
    assert s.assigns.dropped == 0
    assert Page.in_flight(s.assigns) == 21
  end

  test "a dropped tick that moved nothing needs no resync" do
    s = started(0)
    w = Page.window(s.assigns)
    s = Enum.reduce(1..w, s, fn _, s -> tick(s) end)
    assert [{1, "full"} | nones] = modes(s)
    assert Enum.all?(nones, &match?({_, "none"}, &1))
    assert Page.frame_mode(s.assigns, 0) == :drop
    {:noreply, s} = Page.handle_event("frame_drawn", %{"seq" => w, "drawn" => w}, s)
    assert Page.frame_mode(s.assigns, 0) == :none
  end
  # The current hold began `ms` ago.
  defp held_for(s, ms), do: Phoenix.Component.assign(s, hold_since: s.assigns.hold_since - ms)

  test "a client that never acks: the hold times out, the run stops holding and says so (#306)" do
    s = started()
    w = Page.window(s.assigns)
    s = Enum.reduce(1..(w + 1), s, fn _, s -> tick(s) end)
    assert s.assigns.sent_seq == w and s.assigns.dropped == 2
    assert s.assigns.hold_since != nil and s.assigns.acking == :unknown

    # Within the timeout the hold stands; past it, with no ack ever, frames flow again.
    s = tick(held_for(s, 1500))
    assert s.assigns.sent_seq == w and s.assigns.dropped == 3
    s = tick(held_for(s, 2001))
    assert s.assigns.acking == :no
    assert s.assigns.sent_seq == w + 1
    assert List.last(modes(s)) == {w + 1, "full"}
    s = tick(s)
    assert s.assigns.sent_seq == w + 2 and s.assigns.dropped == 3
    assert s.assigns.ack_age == nil
  end

  test "a client that stops acking: the window is released, the stall counted, a full frame sent (#306)" do
    s = Enum.reduce(1..4, started(), fn _, s -> tick(s) end)
    w = Page.window(s.assigns)
    {:noreply, s} = Page.handle_event("frame_drawn", %{"seq" => 5, "drawn" => 5}, s)
    assert s.assigns.acking == :yes
    s = Enum.reduce(1..(w + 2), s, fn _, s -> tick(s) end)
    assert Page.in_flight(s.assigns) == w and s.assigns.dropped == 2

    s = tick(held_for(s, 2001))
    assert s.assigns.stalls == 1
    assert s.assigns.acking == :yes
    assert List.last(modes(s)) == {w + 6, "full"}
    assert Page.in_flight(s.assigns) == 1
    assert is_integer(s.assigns.ack_age) and s.assigns.ack_age >= 0
  end
end
