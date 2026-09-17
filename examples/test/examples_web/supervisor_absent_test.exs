defmodule ExamplesWeb.SupervisorAbsentTest do
  @moduledoc """
  A run whose task supervisor is not running says so instead of crashing the view (#340):
  a server started before `Examples.TaskSupervisor` joined the application's tree has the
  new code and the old tree. These tests stop the supervisor, so they run alone.
  """
  use ExUnit.Case, async: false

  alias Examples.Run
  alias ExamplesWeb.ChartLive
  alias ExamplesWeb.PerformanceLive

  setup do
    # Take the supervisor down for the test and bring it back after: Examples.Supervisor
    # restarts it on demand, so terminate + restart is the tidy way.
    :ok = Supervisor.terminate_child(Examples.Supervisor, Examples.TaskSupervisor)
    on_exit(fn -> {:ok, _} = Supervisor.restart_child(Examples.Supervisor, Examples.TaskSupervisor) end)
    :ok
  end

  test "Run.supervisor/0 says what to do, and rendering fails open" do
    assert {:error, message} = Run.supervisor()
    assert message =~ "restart the server"
    run = Run.new() |> Run.start(0, 0) |> Run.rendering(fn -> :never end)
    refute run.running
    assert run.error =~ "Examples.TaskSupervisor"
    assert run.task == nil
  end

  test "Start and Compare on a chart page leave the view alive with the message in the drawer" do
    {:ok, s} = ChartLive.mount(%{"chart" => "line"}, %{}, %Phoenix.LiveView.Socket{})
    {:noreply, s} = ChartLive.handle_event("drawer_toggle", %{}, s)
    {:noreply, s} = ChartLive.handle_event("run_start", %{}, s)
    refute s.assigns.run.running
    assert s.assigns.run.error =~ "restart the server"
    {:noreply, s} = ChartLive.handle_event("run_compare", %{}, s)
    assert s.assigns.compare_task == nil
    html = Phoenix.LiveViewTest.rendered_to_string(ChartLive.render(Map.put(s.assigns, :__changed__, %{})))
    assert html =~ "the task supervisor is not running"
  end

  test "the performance view reports it too" do
    {:ok, s} = PerformanceLive.mount(%{}, %{}, %Phoenix.LiveView.Socket{})
    {:noreply, s} = PerformanceLive.handle_event("compare", %{}, s)
    assert s.assigns.task == nil and s.assigns.error =~ "restart the server"
  end
end
