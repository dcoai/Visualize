defmodule Visualize.Specs.ForceSimulationConformanceTest do
  @moduledoc """
  The model and the GenServer agree (spec/12 §5). Each script is a message sequence; the
  GenServer is driven through its callbacks and abstracted to the model's variables after
  every step, and the abstraction must match the model's own transitions, written out by
  hand from `Visualize.Specs.ForceSimulation`.

  Abstraction: `running` is the state field; `live` is 1 when the current timer is still
  armed; `stale` counts ticks cancelled too late that are still in the mailbox; `heat` is
  `0` below `alpha_min`, `1` at or above it, `2` at 1.0.
  """
  use ExUnit.Case, async: true

  alias Visualize.Layout.Force.Simulation

  @alpha_min 0.001

  defp init do
    {:ok, state} = Simulation.init(nodes: [%{id: :a}], auto_start: false, alpha_min: @alpha_min)
    {state, []}
  end

  defp abstract({state, stale_tags}) do
    %{
      running: state.running,
      live: if(state.tick_ref && is_integer(Process.read_timer(state.tick_ref)), do: 1, else: 0),
      stale: length(stale_tags),
      heat: heat(state.alpha)
    }
  end

  defp heat(alpha) when alpha < @alpha_min, do: 0
  defp heat(alpha) when alpha < 1.0, do: 1
  defp heat(_), do: 2

  # One model action, applied to the real callbacks. `{:stop, :late}` is a stop whose
  # cancel came too late: the tick is already in the mailbox and stays deliverable.
  defp step({state, stale}, :deferred_start) do
    {:noreply, s} = Simulation.handle_info(:start_simulation, state)
    {s, stale}
  end

  defp step({state, stale}, :start) do
    {:noreply, s} = Simulation.handle_cast(:start, state)
    {s, stale}
  end

  defp step({state, stale}, {:stop, :late}) do
    tag = state.tick_tag
    {:noreply, s} = Simulation.handle_cast(:stop, state)
    {s, [tag | stale]}
  end

  defp step({state, stale}, :stop) do
    {:noreply, s} = Simulation.handle_cast(:stop, state)
    {s, stale}
  end

  defp step({state, stale}, :restart) do
    {:noreply, s} = Simulation.handle_cast(:restart, state)
    {s, stale}
  end

  defp step({state, stale}, :live_tick) do
    {:noreply, s} = Simulation.handle_info({:tick, state.tick_tag}, state)
    {s, stale}
  end

  defp step({state, [tag | rest]}, :stale_tick) do
    {:noreply, s} = Simulation.handle_info({:tick, tag}, state)
    {s, rest}
  end

  defp step({state, stale}, {:set_alpha, a}) do
    {:noreply, s} = Simulation.handle_cast({:set_alpha, a}, state)
    {s, stale}
  end

  # Abstract after every step, not at the end: a later stop cancels an earlier timer.
  defp run(script) do
    script
    |> Enum.map_reduce(init(), fn action, acc ->
      next = step(acc, action)
      {abstract(next), next}
    end)
    |> elem(0)
  end

  test "deferred start after start: one chain" do
    assert run([:start, :deferred_start]) == [
             %{running: true, live: 1, stale: 0, heat: 2},
             %{running: true, live: 1, stale: 0, heat: 2}
           ]
  end

  test "restart from stopped stays stopped; restart while running keeps the chain" do
    assert run([{:set_alpha, 0.5}, :restart, :start, {:set_alpha, 0.5}, :restart]) == [
             %{running: false, live: 0, stale: 0, heat: 1},
             %{running: false, live: 0, stale: 0, heat: 2},
             %{running: true, live: 1, stale: 0, heat: 2},
             %{running: true, live: 1, stale: 0, heat: 1},
             %{running: true, live: 1, stale: 0, heat: 2}
           ]
  end

  test "stop too late, start again, stale tick arrives: still one chain" do
    assert run([:start, {:stop, :late}, :start, :stale_tick, :live_tick]) == [
             %{running: true, live: 1, stale: 0, heat: 2},
             %{running: false, live: 0, stale: 1, heat: 2},
             %{running: true, live: 1, stale: 1, heat: 2},
             %{running: true, live: 1, stale: 0, heat: 2},
             %{running: true, live: 1, stale: 0, heat: 1}
           ]
  end

  test "cooling below alpha_min stops the chain" do
    assert run([:start, {:set_alpha, 0.0005}, :live_tick]) == [
             %{running: true, live: 1, stale: 0, heat: 2},
             %{running: true, live: 1, stale: 0, heat: 0},
             %{running: false, live: 0, stale: 0, heat: 0}
           ]
  end
end
