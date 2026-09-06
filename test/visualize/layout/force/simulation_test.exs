defmodule Visualize.Layout.Force.SimulationTest do
  @moduledoc """
  The timer discipline of spec/06 §8.5, exercised on the callbacks directly so every
  interleaving the model found is reproduced deterministically, plus one live run.
  """
  use ExUnit.Case, async: true

  alias Visualize.Layout.Force.Simulation

  defp stopped do
    {:ok, state} = Simulation.init(nodes: [%{id: :a}], auto_start: false)
    state
  end

  defp running do
    {:noreply, state} = Simulation.handle_cast(:start, stopped())
    state
  end

  # A timer this process armed is still pending exactly when cancelling it returns a time.
  defp armed?(nil), do: false
  defp armed?(ref), do: is_integer(Process.read_timer(ref))

  test "start arms one timer and marks the simulation running" do
    state = running()
    assert state.running
    assert armed?(state.tick_ref)
    assert is_reference(state.tick_tag)
  end

  test "the deferred start after an explicit start does not arm a second timer" do
    state = running()
    {:noreply, after_deferred} = Simulation.handle_info(:start_simulation, state)
    assert after_deferred.tick_ref == state.tick_ref
    assert after_deferred.tick_tag == state.tick_tag
  end

  test "stop cancels the timer and clears running" do
    state = running()
    {:noreply, stopped} = Simulation.handle_cast(:stop, state)
    refute stopped.running
    assert stopped.tick_ref == nil
    refute armed?(state.tick_ref)
  end

  test "restart on a stopped simulation resets alpha and leaves it stopped" do
    state = %{stopped() | alpha: 0.2}
    {:noreply, restarted} = Simulation.handle_cast(:restart, state)
    assert restarted.alpha == 1.0
    refute restarted.running
    assert restarted.tick_ref == nil
  end

  test "restart on a running simulation resets alpha and keeps the single chain" do
    state = %{running() | alpha: 0.2}
    {:noreply, restarted} = Simulation.handle_cast(:restart, state)
    assert restarted.alpha == 1.0
    assert restarted.running
    assert restarted.tick_tag == state.tick_tag
  end

  test "a stale tick is ignored, so stop then start keeps one chain" do
    first = running()
    {:noreply, stopped} = Simulation.handle_cast(:stop, first)
    {:noreply, second} = Simulation.handle_cast(:start, stopped)
    # The first chain's tick reaches the mailbox after all: nothing happens.
    {:noreply, unchanged} = Simulation.handle_info({:tick, first.tick_tag}, second)
    assert unchanged == second
    # The live tick steps and re-arms exactly one timer.
    {:noreply, stepped} = Simulation.handle_info({:tick, second.tick_tag}, second)
    assert stepped.running
    assert stepped.tick_tag != second.tick_tag
    assert armed?(stepped.tick_ref)
  end

  test "a live tick that cools below alpha_min stops the simulation" do
    state = %{running() | alpha: 0.0005, alpha_target: 0}
    {:noreply, stopped} = Simulation.handle_info({:tick, state.tick_tag}, state)
    refute stopped.running
    assert stopped.tick_ref == nil
  end

  test "set_alpha and set_alpha_target clamp to [0, 1]" do
    {:noreply, s1} = Simulation.handle_cast({:set_alpha, 7}, stopped())
    {:noreply, s2} = Simulation.handle_cast({:set_alpha, -1}, s1)
    {:noreply, s3} = Simulation.handle_cast({:set_alpha_target, 2.5}, s2)
    assert s1.alpha == 1
    assert s2.alpha == 0
    assert s3.alpha_target == 1
  end

  test "a live simulation with a cold target stops on its own" do
    {:ok, pid} =
      Simulation.start_link(nodes: [%{id: :a}, %{id: :b}], alpha: 0.01, alpha_decay: 0.5)

    Simulation.subscribe(pid, self())
    assert_receive {:force_tick, %{nodes: _}}, 500
    wait_until_stopped(pid, 50)
    refute :sys.get_state(pid).running
    assert :sys.get_state(pid).tick_ref == nil
  end

  defp wait_until_stopped(pid, tries) when tries > 0 do
    if :sys.get_state(pid).running do
      Process.sleep(20)
      wait_until_stopped(pid, tries - 1)
    end
  end

  defp wait_until_stopped(_pid, 0), do: flunk("simulation never stopped")
end
