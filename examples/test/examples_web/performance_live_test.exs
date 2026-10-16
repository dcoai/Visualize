defmodule ExamplesWeb.PerformanceLiveTest do
  @moduledoc "The comparison view over the gallery (spec/14 §12.6, #328): a chart picked and compared in a task, or every design in one table."
  use ExUnit.Case, async: true

  alias Examples.Compare
  alias ExamplesWeb.PerformanceLive, as: Page

  import Phoenix.Component, only: [update: 3]

  defp html(s),
    do:
      Phoenix.LiveViewTest.rendered_to_string(Page.render(Map.put(s.assigns, :__changed__, %{})))

  test "the page lists the gallery's charts by title and compares the picked one in a task" do
    {:ok, s} = Page.mount(%{}, %{}, %Phoenix.LiveView.Socket{})
    assert hd(s.assigns.charts).title == "Area Chart"
    assert Enum.any?(s.assigns.charts, &(&1.slug == "scrolling_series"))
    h = html(s)
    assert h =~ ~s(<option value="line" selected>Line Chart</option>)
    refute h =~ "(not yet a design)"

    {:noreply, s} = Page.handle_event("pick", %{"slug" => "bar", "ticks" => "20"}, s)
    {:noreply, s} = Page.handle_event("compare", %{}, s)
    %Task{ref: ref} = s.assigns.task
    assert_receive {^ref, {:rows, rows} = result}
    {:noreply, s} = Page.handle_info({ref, result}, s)
    assert s.assigns.task == nil
    assert [%{backend: :svg, ticks: 20}, %{backend: :canvas, ticks: 20}] = rows
    h = html(s)
    assert h =~ "Bar Chart, 20 ticks per backend"
    assert h =~ "<td>SVG</td>" and h =~ "<td>Canvas</td>"
  end

  # The comparison of every light chart, 20 ticks on each backend, is about 0.7 billion
  # reductions (#469); the wait is inside the test's life, so a slow comparison fails on
  # the receive's own message rather than on ExUnit's timeout.
  @compare_wait 90_000

  @tag timeout: @compare_wait + 30_000
  test "every design compared is one table with a row per chart and backend" do
    {:ok, s} = Page.mount(%{}, %{}, %Phoenix.LiveView.Socket{})
    {:noreply, s} = Page.handle_event("pick", %{"slug" => "line", "ticks" => "20"}, s)
    # The light charts (spec/14 §12.6, #469): a heavy chart is held comparable below at
    # one tick, not run twenty times on every backend here.
    s = update(s, :charts, &Enum.filter(&1, fn c -> Compare.cost(c.module) == :light end))

    {:noreply, s} = Page.handle_event("compare_all", %{}, s)
    %Task{ref: ref} = s.assigns.task
    assert_receive {^ref, {:all, all} = result}, @compare_wait
    {:noreply, s} = Page.handle_info({ref, result}, s)
    # One row per chart and backend: a design of several frames offers SVG alone until
    # #385 (spec/14 §12.1), a streaming one offers three, every other one two.
    backends = Enum.sum(for c <- s.assigns.charts, do: length(Examples.Frames.backends(c.module)))
    assert length(all) == backends
    assert Enum.any?(all, &(&1.slug == "scrolling_series" and &1.backend == :incremental))
    # A design of several frames is compared like any other, its cost the sum of its
    # plots' (#433): three backends, since it streams nothing.
    context = Enum.filter(all, &(&1.slug == "context"))
    assert Enum.map(context, & &1.backend) == [:svg, :canvas]
    assert Enum.all?(context, &(&1.avg_bytes > 0))
    # The canvas row's static bytes are the frames' documents, all four of them.
    assert Enum.find(context, &(&1.backend == :canvas)).static_bytes > 0
    assert html(s) =~ "Every design, 20 ticks per backend"
  end

  test "a heavy chart is comparable: one tick on each of its backends is a row with bytes" do
    heavy =
      for {slug, module} <- ExamplesWeb.ChartLive.charts(),
          Compare.cost(module) == :heavy,
          do: {slug, module}

    assert {"downsampling", Examples.Charts.Downsampling} in heavy
    opts_for = fn tick -> [width: 700, height: 450, palette: :default, animation_tick: tick] end

    for {_slug, module} <- heavy do
      rows = Compare.run(module, opts_for, 1)
      assert Enum.map(rows, & &1.backend) == Examples.Frames.backends(module)
      assert Enum.all?(rows, &(&1.ticks == 1 and &1.avg_bytes > 0))
    end
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
