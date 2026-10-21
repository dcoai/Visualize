defmodule Visualize.Bounded do
  @moduledoc false
  # One call in a monitored process of its own, its cost counted rather than timed (spec/08
  # §10.5.4, #852, D-220): the sandbox's runner and the conformance kit's (spec/08 §12.2).
  #
  # The cost is the reductions the call's process spends, collections included, which a
  # loaded host does not change. A call that answers is judged by its own count, read as
  # its function returns; a call still running is read every `@poll` ms and killed at the
  # first reading over the cap. Liveness is a separate wall-clock bound, `timeout`, for a
  # call blocked in `receive`, which spends no reductions and so is never stopped by a cap.
  #
  # Nothing is rescued: a raise or an exit is read from the process's `:DOWN`.

  # Milliseconds between two readings of a running call's reductions.
  @poll 10

  @typedoc "How a bounded call ended."
  @type outcome ::
          {:ok, term(), non_neg_integer()}
          | {:reductions, non_neg_integer()}
          | :hung
          | {:down, term()}

  @doc false
  # `thunk` called in a process spawned with `spawn` options and `:monitor`, the caller in
  # its `$callers`: `{:ok, value, reductions}`; `{:reductions, spent}` when it spent more
  # than `reductions:` (`nil`, no cap); `:hung` when it had not answered within `timeout:`
  # ms; `{:down, reason}` when it exited first, a heap limit's kill as `:killed`. A process
  # the caller kills is waited for, so nothing it does outlives the call.
  @spec run((-> term()), keyword()) :: outcome()
  def run(thunk, opts) when is_function(thunk, 0) do
    cap = Keyword.get(opts, :reductions)
    timeout = Keyword.fetch!(opts, :timeout)
    parent = self()
    tag = make_ref()
    callers = [parent | Process.get(:"$callers", [])]

    {pid, monitor} =
      :erlang.spawn_opt(
        fn ->
          Process.put(:"$callers", callers)
          value = thunk.()
          {:reductions, spent} = Process.info(self(), :reductions)
          send(parent, {tag, value, spent})
        end,
        [:monitor | Keyword.get(opts, :spawn, [])]
      )

    call = %{pid: pid, monitor: monitor, tag: tag, cap: cap}
    await(call, System.monotonic_time(:millisecond) + timeout)
  end

  defp await(%{pid: pid, monitor: monitor, tag: tag} = call, deadline) do
    receive do
      {^tag, value, spent} ->
        Process.demonitor(monitor, [:flush])
        judged(value, spent, call.cap)

      {:DOWN, ^monitor, :process, ^pid, reason} ->
        {:down, reason}
    after
      wait(call.cap, deadline) ->
        if System.monotonic_time(:millisecond) >= deadline do
          stop(call, :hung)
        else
          case over(pid, call.cap) do
            nil -> await(call, deadline)
            spent -> stop(call, {:reductions, spent})
          end
        end
    end
  end

  # With no cap there is nothing to read, and the wait is the deadline's.
  defp wait(cap, deadline) do
    left = max(deadline - System.monotonic_time(:millisecond), 0)
    if cap == nil, do: left, else: min(@poll, left)
  end

  # The running call's reductions when they are over the cap, else `nil` (and `nil` for a
  # process that has just ended, whose `:DOWN` or result is in the mailbox).
  defp over(_pid, nil), do: nil

  defp over(pid, cap) do
    case Process.info(pid, :reductions) do
      {:reductions, spent} when spent > cap -> spent
      _within_or_ended -> nil
    end
  end

  # The call killed and waited for. A result it sent before the kill landed is its answer,
  # judged by its own count, so the moment of a reading is never a verdict.
  defp stop(%{pid: pid, monitor: monitor, tag: tag, cap: cap}, verdict) do
    Process.exit(pid, :kill)

    receive do
      {:DOWN, ^monitor, :process, ^pid, _reason} -> :ok
    end

    receive do
      {^tag, value, spent} -> judged(value, spent, cap)
    after
      0 -> verdict
    end
  end

  defp judged(_value, spent, cap) when cap != nil and spent > cap, do: {:reductions, spent}
  defp judged(value, spent, _cap), do: {:ok, value, spent}
end
