defmodule Visualize.Saturate do
  @moduledoc """
  Every scheduler kept busy on purpose (spec/12, #852, D-220): a test that holds a verdict
  to be the same on a loaded host runs it idle, then again with two busy processes a
  scheduler, and compares the answers. It asserts no time.

  The busy processes compute and allocate nothing, at normal priority, so every other
  process waits its turn behind them, as on a loaded runner. They are linked to the
  process that starts them, so a test that fails takes them with it, and `stop/1` kills
  them; a test calls it from `on_exit/1` too, so none outlives the test.
  """

  @doc "Two busy processes a scheduler, linked to the caller: their pids."
  @spec start() :: [pid(), ...]
  def start do
    for _ <- 1..(System.schedulers_online() * 2), do: spawn_link(fn -> spin(0) end)
  end

  @doc "The busy processes killed, each waited for."
  @spec stop([pid()]) :: :ok
  def stop(pids) do
    for pid <- pids do
      monitor = Process.monitor(pid)
      Process.unlink(pid)
      Process.exit(pid, :kill)
      receive do: ({:DOWN, ^monitor, :process, ^pid, _reason} -> :ok)
    end

    :ok
  end

  defp spin(n), do: spin(rem(n + 1, 1_000_003))
end
