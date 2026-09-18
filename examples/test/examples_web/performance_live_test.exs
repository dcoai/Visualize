defmodule ExamplesWeb.PerformanceLiveTest do
  @moduledoc "The comparison view over the gallery (spec/14 §12.6, #328): a chart picked and compared in a task, or every design in one table."
  use ExUnit.Case, async: true

  alias ExamplesWeb.PerformanceLive, as: Page

  defp html(s), do: Phoenix.LiveViewTest.rendered_to_string(Page.render(Map.put(s.assigns, :__changed__, %{})))

  test "the page lists the gallery's charts, designs first, and compares the picked one in a task" do
    {:ok, s} = Page.mount(%{}, %{}, %Phoenix.LiveView.Socket{})
    assert hd(s.assigns.charts).design?
    assert Enum.any?(s.assigns.charts, &(&1.slug == "scrolling_series"))
    h = html(s)
    assert h =~ ~s(<option value="line" selected>Line Chart</option>)
    refute h =~ "(not yet a design)"

    {:noreply, s} = Page.handle_event("pick", %{"slug" => "bar", "ticks" => "20"}, s)
    {:noreply, s} = Page.handle_event("compare", %{}, s)
    %Task{ref: ref} = s.assigns.task
    assert_receive {^ref, {:rows, rows} = result}, 30_000
    {:noreply, s} = Page.handle_info({ref, result}, s)
    assert s.assigns.task == nil
    assert [%{backend: :svg, ticks: 20}, %{backend: :canvas, ticks: 20}] = rows
    h = html(s)
    assert h =~ "Bar Chart, 20 ticks per backend"
    assert h =~ "<td>SVG</td>" and h =~ "<td>Canvas</td>"
  end

  test "every design compared is one table with a row per chart and backend" do
    {:ok, s} = Page.mount(%{}, %{}, %Phoenix.LiveView.Socket{})
    {:noreply, s} = Page.handle_event("pick", %{"slug" => "line", "ticks" => "20"}, s)
    {:noreply, s} = Page.handle_event("compare_all", %{}, s)
    %Task{ref: ref} = s.assigns.task
    assert_receive {^ref, {:all, all} = result}, 120_000
    {:noreply, s} = Page.handle_info({ref, result}, s)
    designs = Enum.count(s.assigns.charts, & &1.design?)
    assert length(all) >= designs * 2
    assert Enum.any?(all, &(&1.slug == "scrolling_series" and &1.backend == :incremental))
    assert html(s) =~ "Every design, 20 ticks per backend"
  end

  test "a comparison that dies is reported and the page goes on" do
    {:ok, s} = Page.mount(%{}, %{}, %Phoenix.LiveView.Socket{})
    {:noreply, s} = Page.handle_event("compare", %{}, s)
    %Task{ref: ref, pid: pid} = s.assigns.task
    Task.Supervisor.terminate_child(Examples.TaskSupervisor, pid)
    {:noreply, s} = Page.handle_info({:DOWN, ref, :process, pid, :shutdown}, s)
    assert s.assigns.task == nil and s.assigns.error == ":shutdown"
  end
end
