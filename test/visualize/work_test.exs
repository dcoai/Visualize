defmodule Visualize.WorkTest do
  @moduledoc """
  `Visualize.Work.reductions/1` counts a run's execution in a process of its own, with no
  garbage collection in the count (spec/12 §6, #703), so the count is the code's and not
  the history of a process or the load of the machine.
  """
  use ExUnit.Case, async: true

  alias Visualize.Work

  defp build(0, acc), do: acc
  defp build(n, acc), do: build(n - 1, [{n, n * 2} | acc])

  # Allocates about a million words and keeps them, so a process with the default heap
  # collects dozens of times; its collection charge was what moved with load (#703).
  defp allocate, do: build(200_000, []) |> hd()

  test "an allocating run counts the same every time, whatever the caller's heap holds" do
    counts = for _ <- 1..3, do: elem(Work.reductions(&allocate/0), 0)
    held = build(500_000, [])
    counts = counts ++ for _ <- 1..3, do: elem(Work.reductions(&allocate/0), 0)

    assert [_] = Enum.uniq(counts)
    assert length(held) == 500_000
  end

  test "the run is counted in another process, which knows the caller as a task does" do
    caller = self()
    {work, {runner, callers}} = Work.reductions(fn -> {self(), Process.get(:"$callers")} end)

    assert work > 0
    assert runner != caller
    assert hd(callers) == caller
  end

  test "a counted run that collects is an error, not a count" do
    # The first run allocates nothing; the second, sized for that, allocates a million
    # words and must collect.
    runs = :counters.new(1, [])

    grows = fn ->
      :counters.add(runs, 1, 1)
      if :counters.get(runs, 1) > 1, do: allocate(), else: :ok
    end

    assert_raise RuntimeError, ~r/the counted run collected/, fn -> Work.reductions(grows) end
  end

  test "a raise in the function is raised in the caller, with its stack trace" do
    assert_raise ArgumentError, "not a number", fn ->
      Work.reductions(fn -> raise ArgumentError, "not a number" end)
    end
  end

  test "an exit in the function exits the caller with its reason" do
    caller = self()

    {pid, monitor} =
      spawn_monitor(fn ->
        Process.put(:"$callers", [caller])
        Work.reductions(fn -> exit(:gone) end)
      end)

    assert_receive {:DOWN, ^monitor, :process, ^pid, :gone}
  end
end
