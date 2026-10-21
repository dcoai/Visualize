defmodule Visualize.Feed.Conformance.Call do
  @moduledoc false
  # One callback of the kit (spec/08 §12.2, #852, D-221): run in a process of its own
  # through `Visualize.Bounded`, monitored, with the caller in `$callers`, its cost the
  # reductions it spends and its liveness a wall-clock bound.

  # The callbacks a `reductions:` budget holds: the feed's own. The `push:` function and the
  # reading of a delivery's rows are held to liveness only.
  @budgeted [:describe, :subscribe, :unsubscribe]

  @doc false
  # `{:ok, answer}`, or `{:error, finding}` for a raise or an exit, a hang past `timeout`, or
  # a budgeted callback over `reductions` — its own process's count, with the named
  # `processes`' reductions during the call added.
  def run(fun, call, o) do
    budget = if budgeted?(call), do: o.reductions
    before = if budget, do: elsewhere(o.processes)

    case Visualize.Bounded.run(fun, reductions: budget, timeout: o.timeout) do
      {:ok, answer, spent} ->
        spent = if budget, do: spent + elsewhere(o.processes) - before, else: spent

        if budget != nil and spent > budget,
          do: {:error, {:reductions, call, spent, budget}},
          else: {:ok, answer}

      {:reductions, spent} ->
        {:error, {:reductions, call, spent, budget}}

      :hung ->
        {:error, {:hung, call, o.timeout}}

      {:down, reason} ->
        {:error, {:raised, call, reason}}
    end
  end

  defp budgeted?({:fetch, _window, _budget}), do: true
  defp budgeted?(call), do: call in @budgeted

  # The reductions the named processes have spent so far; a process that is not running
  # counts none.
  defp elsewhere(processes) do
    Enum.reduce(processes, 0, fn process, sum ->
      pid = if is_pid(process), do: process, else: Process.whereis(process)

      case pid && Process.info(pid, :reductions) do
        {:reductions, n} -> sum + n
        _gone -> sum
      end
    end)
  end
end
