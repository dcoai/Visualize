defmodule Visualize.WorkTest do
  @moduledoc """
  `Visualize.Work.reductions/1` counts a run in a process of its own (spec/12 §6, #703),
  so the count is not the history of the process that asks for it.
  """
  use ExUnit.Case, async: true

  alias Visualize.Work

  test "the run is counted in another process, which knows the caller as a task does" do
    caller = self()
    {work, {runner, callers}} = Work.reductions(fn -> {self(), Process.get(:"$callers")} end)

    assert work > 0
    assert runner != caller
    assert hd(callers) == caller
  end

  test "each count starts from a process that has done nothing" do
    # Two runs in one process: the second finds the heap the first grew. Each count of
    # Work's is a new process, so the heap the function sees is the one it starts with.
    {_work, first} = Work.reductions(fn -> Process.info(self(), :total_heap_size) end)
    {_work, second} = Work.reductions(fn -> Process.info(self(), :total_heap_size) end)

    assert first == second
  end

  test "a raise in the function is raised in the caller, with its stack trace" do
    error =
      assert_raise ArgumentError, "not a number", fn ->
        Work.reductions(fn -> raise ArgumentError, "not a number" end)
      end

    assert %ArgumentError{} = error
  end

  test "an exit in the function exits the caller with its reason" do
    caller = self()

    {pid, monitor} =
      spawn_monitor(fn ->
        Process.put(:"$callers", [caller])
        Work.reductions(fn -> exit(:gone) end)
      end)

    assert_receive {:DOWN, ^monitor, :process, ^pid, :gone}, 5_000
  end
end
