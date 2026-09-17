defmodule Examples.RunTest do
  @moduledoc """
  The frame loop as a value (spec/14 §12.6, #322): the clock, samples as whole columns,
  what a frame goes as, flow control with acks and its fail-open hold, the render in a
  task, and the metrics — the model the High-Performance page held, now `Examples.Run`.
  """
  use ExUnit.Case, async: true

  alias Examples.Run

  @size {810, 410}

  defp started(opts \\ []) do
    Run.new(Keyword.merge([target_fps: 60, data_rate: 600], opts)) |> Run.start(0, 0)
  end

  # A run through one frame sent as `mode`, acked or not.
  defp sent(run, mode), do: run |> Run.sending(mode) |> elem(0)

  test "ticks follow a deadline: a 600 fps target alternates 1 and 2 ms and averages its period (#302)" do
    {delays, _} =
      Enum.map_reduce(1..6, {0, 0}, fn _, {due, now} ->
        {next, delay} = Run.deadline(due, now, 600)
        {delay, {next, now + delay * 1000}}
      end)

    assert delays == [2, 1, 2, 2, 1, 2]
    assert {2000.0, 2} = Run.deadline(0, 0, 500)
    assert {9_000, 0} = Run.deadline(0, 9_000, 500)

    # Unlimited: no wait, the deadline now.
    assert {%Run{next_due: 5}, 0} = Run.schedule(Run.new(target_fps: 2010, next_due: 0), 5)
    assert {%Run{next_due: next}, 17} = Run.schedule(Run.new(target_fps: 60, next_due: 0), 0)
    assert_in_delta next, 16_666.67, 0.01
  end

  test "samples arrive by the clock and a tick yields the whole columns they fill (#300)" do
    run = started()
    # 600/s for 16 ms is 9.6 samples: 9 arrive, 0.6 carries; at two per column, four
    # columns with one sample pending.
    assert {%Run{pending: 1, carry: carry} = run, {:draw, 4}} = Run.tick(run, 16, 2)
    assert_in_delta carry, 0.6, 1.0e-9
    # 0.6 + 9.6 = 10.2 → 10 arrive, 11 pending → five columns, one pending, 0.2 carried.
    assert {%Run{pending: 1, carry: carry}, {:draw, 5}} = Run.tick(run, 32, 2)
    assert_in_delta carry, 0.2, 1.0e-9

    # A slow rate fills no column on most ticks, and nothing is lost.
    slow = started(data_rate: 60)
    assert {%Run{pending: 0, carry: c1} = slow, {:draw, 0}} = Run.tick(slow, 16, 2)
    assert_in_delta c1, 0.96, 1.0e-9
    assert {%Run{pending: 1}, {:draw, 0}} = Run.tick(slow, 32, 2)
  end

  test "a tick during a render is skipped and its samples wait for the next frame (#323)" do
    run = started()
    run = Run.rendering(run, fn -> :frame end)
    assert {%Run{skipped: 1, pending: 9} = run, :skipped} = Run.tick(run, 16, 4)
    %Task{ref: ref} = run.task
    assert_receive {^ref, :frame}
    assert {:ok, run} = Run.result(run, ref)
    assert run.task == nil
    # The samples of the skipped tick and this one fill the frame's columns together.
    assert {%Run{pending: 3}, {:draw, 4}} = Run.tick(run, 32, 4)
  end

  test "what a frame goes as: full first, then strips or the empty update; a full clears the need" do
    run = started()
    assert {run, :full_redraw} = Run.decide(run, 4, true, @size, 0)
    assert run.needs_full
    run = sent(run, :full_redraw)
    refute run.needs_full
    assert {_, :scroll_x} = Run.decide(run, 4, true, @size, 16)
    assert {_, :none} = Run.decide(run, 0, true, @size, 16)
    # Incremental off: full every frame. A scroll past half the plot: full.
    assert {_, :full_redraw} = Run.decide(run, 4, false, @size, 16)
    assert {_, :full_redraw} = Run.decide(run, 500, true, @size, 16)
  end

  test "the window is a lag budget (#310) and flow control holds at it; a dropped scroll resyncs with a full frame" do
    assert Run.window(Run.new(target_fps: 60)) == 15
    assert Run.window(Run.new(target_fps: 500)) == 125
    assert Run.window(Run.new(target_fps: 2010)) == 500
    assert Run.window(Run.new(target_fps: 10)) == 3

    run = started() |> sent(:full_redraw)
    run = Enum.reduce(1..14, run, fn _, r -> sent(r, :scroll_x) end)
    assert Run.in_flight(run) == 15
    assert {run, :drop} = Run.decide(run, 4, true, @size, 100)
    assert run.dropped == 1 and run.needs_full and run.hold_since == 100

    # The ack opens the window; the next frame is a full render, then strips again.
    run = Run.acked(run, 15, 15, 120)
    assert Run.in_flight(run) == 0 and run.acking == :yes
    assert {run, :full_redraw} = Run.decide(run, 4, true, @size, 130)
    run = sent(run, :full_redraw)
    assert {_, :scroll_x} = Run.decide(run, 4, true, @size, 140)

    # A drop that moved nothing needs no resync.
    still = started() |> sent(:full_redraw)
    still = Enum.reduce(1..14, still, fn _, r -> sent(r, :none) end)
    assert {still, :drop} = Run.decide(still, 0, true, @size, 100)
    refute still.needs_full

    # Flow control off: nothing is held.
    open = %{run | flow_control: false}
    open = Enum.reduce(1..30, open, fn _, r -> sent(r, :scroll_x) end)
    assert {_, :scroll_x} = Run.decide(open, 4, true, @size, 200)
  end

  test "a hold fails open: never acked → the run stops holding; stopped acking → the window is released (#306)" do
    run = started() |> sent(:full_redraw)
    run = Enum.reduce(1..14, run, fn _, r -> sent(r, :scroll_x) end)
    {run, :drop} = Run.decide(run, 4, true, @size, 100)
    # Within the timeout the hold stands; past it, with no ack ever, the client does not
    # acknowledge and the next frame goes.
    assert {run, :drop} = Run.decide(run, 4, true, @size, 1_600)
    assert {run, :full_redraw} = Run.decide(run, 4, true, @size, 2_200)
    assert run.acking == :no and run.hold_since == nil

    # With acks before, a hold past the timeout is a stall: released and counted.
    stalled = started() |> sent(:full_redraw) |> Run.acked(1, 1, 10)
    stalled = Enum.reduce(1..15, stalled, fn _, r -> sent(r, :scroll_x) end)
    {stalled, :drop} = Run.decide(stalled, 4, true, @size, 100)
    assert {stalled, :full_redraw} = Run.decide(stalled, 4, true, @size, 2_200)
    assert stalled.stalls == 1 and stalled.acking == :yes and Run.in_flight(stalled) == 0
    assert stalled.ack_age == 2_190
  end

  test "a frame rendered counts, measures and smooths the lag; an ack measures the client" do
    run = started() |> sent(:full_redraw) |> Run.rendered(1000, 0)
    assert run.frame == 1 and run.payload_size == 1000
    run = run |> sent(:scroll_x) |> Run.rendered(100, 16)
    assert run.frame == 2
    assert_in_delta run.fps, 62.5, 0.01
    # Two in flight at 60 fps is 33 ms of lag; the average moves a thirty-first of the way.
    assert_in_delta run.lag, 2 / 31 * 2 * 1000 / 60 + (1 - 2 / 31) * (2 / 31 * 1000 / 60), 1.0e-6

    acked = run |> Run.acked(1, 1, 500) |> Run.acked(2, 1, 1000)
    assert acked.acked_seq == 2 and acked.last_ack_at == 1000
    assert_in_delta acked.client_fps, 4.0, 1.0e-9
  end

  test "stop terminates a render in flight; a stale result or DOWN is nothing; a dead render stops the run" do
    run = started()
    run = Run.rendering(run, fn -> Process.sleep(10_000) end)
    %Task{ref: ref, pid: pid} = run.task
    mon = Process.monitor(pid)
    run = Run.stop(run)
    refute run.running
    assert run.task == nil
    assert_receive {:DOWN, ^mon, :process, ^pid, _}, 5_000
    assert :stale = Run.result(run, ref)
    assert :stale = Run.down(run, ref, :shutdown)

    dying = Run.rendering(started(), fn -> :ok end)
    %Task{ref: ref} = dying.task
    assert {:ok, dead} = Run.down(dying, ref, {:badarg, []})
    refute dead.running
    assert dead.error =~ "badarg"
  end
end
