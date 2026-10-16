defmodule Visualize.Work do
  @moduledoc """
  The work a function does, counted rather than timed (spec/12 §6, D-114, #462).

  A cost claim in the default suite — a scroll costs its strip, not its window; a curve
  is built in work linear in its points — is a claim about the **algorithm**, and a
  wall-clock reading of it is a claim about the machine: a scheduler preemption during
  the cheaper of two timed runs flips a ratio, and an absolute bound moves with the box.
  Reductions are the BEAM's own count of the work a process executes — function calls,
  BIF work, garbage collection — and a preemption or a busy box does not add calls.

  **The count is taken in a fresh process** (#703). The collections a run pays for are
  part of its reductions, and how many it takes depends on the heap the process brings to
  it, not only on the code: counted in the caller after a warm run there, the same render
  took 407 minor collections one time and 479 the next, and up to 9 % more reductions.
  A process that has done nothing before the run takes the same collections every time.
  What the machine still moves is the charge for those collections, and only upward: a
  render's counts stay within about 1 % of each other, an allocation-bound function's
  less so. A cost test therefore asserts its budget on the lower of two counts and holds
  the two to agree (spec/12 §6).

  The function must do its work in the process it runs in — everything the suite
  measures this way is synchronous — and must not depend on the caller's process: its
  dictionary, its mailbox or `self()`.
  """

  @doc """
  The reductions one run of `fun` spends, and its result.

  `fun` is run first in one spawned process, which loads any module it calls first — a
  cost the function's own work does not have — and then counted in a second, which has
  done nothing before it. The function must therefore be pure enough to run twice, and
  every caller passes one that is. The result comes back as a message, so a function
  that raises raises again in the caller, with its stack trace.

      iex> {work, 6} = Visualize.Work.reductions(fn -> Enum.sum([1, 2, 3]) end)
      iex> work > 0
      true
  """
  @spec reductions((-> result)) :: {pos_integer(), result} when result: term()
  def reductions(fun) when is_function(fun, 0) do
    {_warm, _result} = fresh(fun)
    fresh(fun)
  end

  # `fun` counted in a process spawned for it alone. It knows its callers as a task does,
  # so a log it writes is captured with the test's. The wait is on the process's answer
  # or its exit, with no `after`: the test's own timeout bounds a run that never ends
  # (spec/12 §6).
  defp fresh(fun) do
    parent = self()
    callers = [parent | Process.get(:"$callers", [])]
    tag = make_ref()

    {pid, monitor} =
      spawn_monitor(fn ->
        Process.put(:"$callers", callers)
        {:reductions, before} = Process.info(self(), :reductions)
        result = fun.()
        {:reductions, after_} = Process.info(self(), :reductions)
        send(parent, {tag, after_ - before, result})
      end)

    receive do
      {^tag, work, result} ->
        Process.demonitor(monitor, [:flush])
        {work, result}

      {:DOWN, ^monitor, :process, ^pid, reason} ->
        crashed(reason)
    end
  end

  defp crashed({exception, stacktrace}) when is_exception(exception),
    do: reraise(exception, stacktrace)

  defp crashed(reason), do: exit(reason)
end
