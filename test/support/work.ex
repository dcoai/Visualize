defmodule Visualize.Work do
  @moduledoc """
  The work a function does, counted rather than timed (spec/12 §6, D-114, #462).

  A cost claim in the default suite — a scroll costs its strip, not its window; a curve
  is built in work linear in its points — is a claim about the **algorithm**, and a
  wall-clock reading of it is a claim about the machine: a scheduler preemption during
  the cheaper of two timed runs flips a ratio, and an absolute bound moves with the box.
  Reductions are the BEAM's own count of the work a process executes — function calls,
  BIF work, garbage collection — and are the same whatever else the machine is doing.

  The function runs in the calling process, so it must not hand its work to another
  process; everything the suite measures this way is synchronous.
  """

  @doc """
  The reductions the calling process spends on one run of `fun`, and its result.

  `fun` is run once before it is counted: the first call into a module not yet loaded
  loads it, and that costs the caller reductions the function's own work does not. The
  function must therefore be pure enough to run twice — every caller passes one that is.
  The process is collected before the counted run, so the collections the run pays for
  start from the same empty heap whatever ran before it.

      iex> {work, 6} = Visualize.Work.reductions(fn -> Enum.sum([1, 2, 3]) end)
      iex> work > 0
      true
  """
  @spec reductions((-> result)) :: {pos_integer(), result} when result: term()
  def reductions(fun) when is_function(fun, 0) do
    _warm = fun.()
    :erlang.garbage_collect()
    {:reductions, before} = Process.info(self(), :reductions)
    result = fun.()
    {:reductions, after_} = Process.info(self(), :reductions)
    {after_ - before, result}
  end
end
