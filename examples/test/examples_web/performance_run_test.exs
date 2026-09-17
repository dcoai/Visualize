defmodule ExamplesWeb.PerformanceRunTest do
  @moduledoc """
  The performance page's frames render off its process (#323): a tick starts a task, a
  tick during a render is skipped, the task's result pushes the frame and schedules the
  next tick, and Stop with a render in flight leaves no push behind.
  """
  use ExUnit.Case, async: true

  alias ExamplesWeb.PerformanceLive, as: Page

  defp started(backend, points) do
    {:ok, s} = Page.mount(%{}, %{}, %Phoenix.LiveView.Socket{})
    {:noreply, s} = Page.handle_event("set_backend", %{"backend" => backend}, s)
    {:noreply, s} = Page.handle_event("update_sliders", %{"data_points" => "#{points}"}, s)
    {:noreply, s} = Page.handle_event("start_test", %{}, s)
    s
  end

  defp events(s), do: for([n, p] <- Phoenix.LiveView.Utils.get_push_events(s), do: {n, Map.keys(p)})

  test "a tick renders in a task, a tick meanwhile is skipped, and the result is the frame" do
    s = started("canvas", 200)
    {:noreply, s} = Page.handle_info(:render_frame, s)
    assert %Task{ref: ref} = s.assigns.render_task
    assert s.assigns.frame == 0

    {:noreply, s} = Page.handle_info(:render_frame, s)
    assert s.assigns.skipped == 1
    assert %Task{ref: ^ref} = s.assigns.render_task

    assert_receive {^ref, result}, 5_000
    assert %{output: output, pushes: [{"canvas_update", _}]} = result
    assert byte_size(output) > 0

    {:noreply, s} = Page.handle_info({ref, result}, s)
    assert s.assigns.render_task == nil
    assert s.assigns.frame == 1
    assert s.assigns.total_bytes == byte_size(output)
    assert [{"canvas_update", [:binary]}] = events(s)
    # The completion scheduled the next tick.
    assert_receive :render_frame, 1_000
  end

  test "Stop with a render in flight terminates it, and a late result is ignored" do
    s = started("svg", 200)
    {:noreply, s} = Page.handle_info(:render_frame, s)
    assert %Task{ref: ref, pid: pid} = s.assigns.render_task
    mon = Process.monitor(pid)

    {:noreply, s} = Page.handle_event("stop_test", %{}, s)
    refute s.assigns.running
    assert s.assigns.render_task == nil
    assert_receive {:DOWN, ^mon, :process, ^pid, _}, 5_000
    refute_received {^ref, _}

    # A result from a render that was cancelled changes nothing.
    {:noreply, same} = Page.handle_info({ref, %{output: "x", pushes: [], compiled: nil, compiled_svg: nil}}, s)
    assert same.assigns.frame == 0
    assert events(same) == []
  end

  test "a render that dies stops the run and says so" do
    s = started("svg", 200)
    {:noreply, s} = Page.handle_info(:render_frame, s)
    %Task{ref: ref} = s.assigns.render_task
    {:noreply, s} = Page.handle_info({:DOWN, ref, :process, self(), {:badarg, []}}, s)
    refute s.assigns.running
    assert s.assigns.render_error =~ "badarg"
  end

  test "the compiled path carries its chart's state through the task" do
    s = started("compiled_binary", 200)
    {:noreply, s} = Page.handle_info(:render_frame, s)
    %Task{ref: ref} = s.assigns.render_task
    assert_receive {^ref, result}, 5_000
    assert %{compiled: %Visualize.Chart.Compiled{}} = result
    {:noreply, s} = Page.handle_info({ref, result}, s)
    assert s.assigns.compiled == result.compiled
  end
end
