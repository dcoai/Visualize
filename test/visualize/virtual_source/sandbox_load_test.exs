defmodule Visualize.VirtualSource.SandboxLoadTest do
  # Load changes no verdict (spec/08 §10.5.4, spec/12, #852, D-220): each verdict is taken
  # idle, then with every scheduler saturated by busy processes, and the two must agree.
  # Not async, so the saturation shares the runner with no other test; nothing here asserts
  # a time.
  use ExUnit.Case, async: false

  alias Visualize.Saturate
  alias Visualize.VirtualSource.Sandbox

  # The board demo's `health` (examples/lib/examples/board_demo.ex): each host's state by
  # its newest reading, a statistic and an interpolated label.
  @health """
  fn rows ->
    newest = Enum.at(rows, -1)
    latest = newest.cpu
    mean = rows |> Enum.map(& &1.cpu) |> Visualize.Data.mean() |> Float.round(1)

    state =
      cond do
        latest > 80 -> :bad
        latest > 60 -> :warning
        true -> :good
      end

    %{state: state, note: "\#{newest.host} averaged \#{mean}% over its last \#{Enum.count(rows)}"}
  end
  """

  @runaway "fn _ -> Enum.reduce(1..100_000_000_000_000, 0, fn x, acc -> rem(acc + x, 7) end) end"

  @sum "fn n -> Enum.reduce(1..n, 0, fn x, acc -> acc + x end) end"

  # The verdicts of `calls`, idle and then saturated; the busy processes stopped on exit too.
  defp idle_and_saturated(calls) do
    idle = calls.()
    busy = Saturate.start()
    on_exit(fn -> Saturate.stop(busy) end)
    saturated = calls.()
    :ok = Saturate.stop(busy)
    {idle, saturated}
  end

  defp hosts do
    for host <- ["a", "b", "c", "d"], i <- 1..6, do: %{host: host, cpu: 20.0 + 13 * i}
  end

  test "a real document compiles and runs per identity to the same value at the defaults" do
    batch = fn ->
      {:ok, compiled} = Sandbox.compile(@health)

      groups = Enum.group_by(hosts(), & &1.host)
      Sandbox.run(fn -> Enum.map(groups, fn {h, rows} -> {h, compiled.fun.(rows)} end) end, [])
    end

    {idle, saturated} = idle_and_saturated(batch)

    assert {:ok, [{"a", %{"state" => "bad", "note" => "a averaged 65.5% over its last 6"}} | _]} =
             idle

    assert saturated == idle
  end

  test "a runaway is stopped by the cap, idle and saturated alike" do
    {:ok, compiled} = Sandbox.compile(@runaway)
    run = fn -> Sandbox.run(compiled, [nil], max_reductions: 1_000_000) end

    assert idle_and_saturated(run) ==
             {{:error, :reductions, 1_000_000}, {:error, :reductions, 1_000_000}}
  end

  test "a cap decides by the count: twice the work passes and half fails, at any load" do
    {:ok, compiled} = Sandbox.compile(@sum)
    {work, value} = Visualize.Work.reductions(fn -> compiled.fun.(100_000) end)

    calls = fn ->
      {Sandbox.run(compiled, [100_000], max_reductions: 2 * work),
       Sandbox.run(compiled, [100_000], max_reductions: div(work, 2))}
    end

    verdict = {{:ok, value}, {:error, :reductions, div(work, 2)}}
    assert idle_and_saturated(calls) == {verdict, verdict}
  end

  test "a host's function blocked in receive is hung at the liveness bound, not slow" do
    blocked = fn -> Sandbox.run(fn -> receive(do: (:never_sent -> :ok)) end, [], timeout: 50) end
    assert idle_and_saturated(blocked) == {{:error, :hung, 50}, {:error, :hung, 50}}
  end
end
