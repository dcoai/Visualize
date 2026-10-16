defmodule Visualize.Work do
  @moduledoc """
  The work a function does, counted rather than timed (spec/12 §6, D-114, #462).

  A cost claim in the default suite — a scroll costs its strip, not its window; a curve
  is built in work linear in its points — is a claim about the **algorithm**, and a
  wall-clock reading of it is a claim about the machine: a scheduler preemption during
  the cheaper of two timed runs flips a ratio, and an absolute bound moves with the box.
  Reductions are the BEAM's own count of the work a process executes: function calls and
  BIF work, which a preemption or a busy box does not add to.

  **The count is the run's execution, with no garbage collection in it** (#703). A
  collection is charged to the process that pays for it, and that charge is not a
  property of the code: how many collections a run takes depends on the heap its process
  brings to it, and what each one is charged moves with the load of the machine. A run
  that mostly allocates counted 233,000 to 528,000 reductions over the same 43
  collections, idle and loaded; in CI two counts of one gallery render in fresh processes
  were 8.5 % apart. So the run is counted in a process whose heap already holds
  everything the run allocates, and it collects nothing: that run counted 200,007 every
  time, and a render's counts agree within 0.2 %, most to a few dozen reductions, idle
  or loaded (the residue is how a yielding BIF is charged against its time slice).

  The function runs twice, each time in a process of its own. The first run loads any
  module it calls first and measures the words it allocates, read from the collections
  traced in it. The second is spawned with a minimum heap of those words and a margin,
  and with a binary heap that does not trigger a collection either. The counted run is
  traced too, and a collection in it is an error that says so, rather than a count with
  the collection in it.

  The function must do its work in the process it runs in — everything the suite
  measures this way is synchronous — and must not depend on the caller's process: its
  dictionary, its mailbox or `self()`.
  """

  # The counted heap's margin over what the first run allocated, and its floor in words.
  @margin 4
  @floor 100_000

  # A binary heap no run reaches, so binaries trigger no collection (words).
  @bin_vheap 1_000_000_000

  @doc """
  The reductions one run of `fun` spends, its collections excluded, and its result.

  The function must be pure enough to run twice, and every caller passes one that is.
  The result comes back as a message, so a function that raises raises again in the
  caller, with its stack trace.

      iex> {work, 6} = Visualize.Work.reductions(fn -> Enum.sum([1, 2, 3]) end)
      iex> work > 0
      true
  """
  @spec reductions((-> result)) :: {pos_integer(), result} when result: term()
  def reductions(fun) when is_function(fun, 0) do
    %{words: words} = run(fun, [])
    heap = words + div(words, @margin) + @floor

    case run(fun, min_heap_size: heap, min_bin_vheap_size: @bin_vheap) do
      %{collections: 0, work: work, result: result} ->
        {work, result}

      %{collections: n} ->
        raise "the counted run collected #{n} times in a heap of #{heap} words, sized " <>
                "for the #{words} its first run allocated: the function does not " <>
                "allocate the same on every run (Visualize.Work, #703)"
    end
  end

  # `fun` run in a process spawned for it alone, with `options`, its collections traced to
  # this process: the reductions it spent, its result, how many times it collected and
  # how many words it allocated — each collection's young heap at its start, less what
  # the one before it left, and what the last one left against the heap at the end. The
  # process knows its callers as a task does, so a log it writes is captured with the
  # test's. Every wait is on a message, with no `after`: the test's own timeout bounds a
  # run that never ends (spec/12 §6).
  defp run(fun, options) do
    parent = self()
    callers = [parent | Process.get(:"$callers", [])]
    tag = make_ref()

    {pid, monitor} =
      :erlang.spawn_opt(
        fn ->
          Process.put(:"$callers", callers)
          receive do: (^tag -> :ok)
          {:reductions, before} = Process.info(self(), :reductions)
          result = fun.()
          {:reductions, after_} = Process.info(self(), :reductions)
          {:heap_size, heap} = Process.info(self(), :heap_size)
          send(parent, {tag, after_ - before, heap, result})
        end,
        [:monitor | options]
      )

    :erlang.trace(pid, true, [:garbage_collection])
    send(pid, tag)

    receive do
      {^tag, work, heap, result} ->
        receive do: ({:DOWN, ^monitor, :process, ^pid, _reason} -> :ok)
        delivered = :erlang.trace_delivered(pid)
        receive do: ({:trace_delivered, ^pid, ^delivered} -> :ok)
        {collections, words} = collections(pid, heap, 0, 0, 0)
        %{work: work, result: result, collections: collections, words: words}

      {:DOWN, ^monitor, :process, ^pid, reason} ->
        crashed(reason)
    end
  end

  # The collections traced from `pid`, all delivered: how many, and the words allocated.
  # `after 0` reads the mailbox as it stands, which `:erlang.trace_delivered/1` has made
  # complete.
  defp collections(pid, heap, left, words, n) do
    receive do
      {:trace, ^pid, start, info} when start in [:gc_minor_start, :gc_major_start] ->
        collections(pid, heap, left, words + info[:heap_size] + info[:mbuf_size] - left, n + 1)

      {:trace, ^pid, finish, info} when finish in [:gc_minor_end, :gc_major_end] ->
        collections(pid, heap, info[:heap_size], words, n)
    after
      0 -> {n, words + heap - left}
    end
  end

  defp crashed({exception, stacktrace}) when is_exception(exception),
    do: reraise(exception, stacktrace)

  defp crashed(reason), do: exit(reason)
end
