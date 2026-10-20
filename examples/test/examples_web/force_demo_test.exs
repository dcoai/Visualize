defmodule ExamplesWeb.ForceDemoTest do
  @moduledoc """
  The force layout in the examples (spec/06 §8.4, #781, work item #836): the gallery's force
  graph writes its step's `alpha` and `ticks`, and `/interaction` runs a live
  `Force.Simulation` it subscribed to from the start, redrawing on each tick, with Reheat and
  Pin the hub reaching the simulation. A square-wave heat input (#848, work item #849)
  drives its `alpha_target`, driven here by the page's own timer messages, never by
  waiting on the clock.
  """
  use ExUnit.Case, async: true

  import Phoenix.ConnTest

  alias ExamplesWeb.{ForceDemo, InteractionLive}
  alias Visualize.Layout.Force.Simulation

  @endpoint ExamplesWeb.Endpoint

  doctest ExamplesWeb.ForceDemo

  test "the force graph's step writes alpha and ticks, the defaults, and draws as before" do
    {design, _rows} = Examples.Charts.ForceGraph.design([])
    assert inspect(design) =~ "alpha: 0.3"
    assert inspect(design) =~ "ticks: 3"
    assert Examples.Charts.ForceGraph.sample_code() =~ "alpha: 0.3, ticks: 3"
  end

  test "the panel renders before the page connects, with no simulation started" do
    html = build_conn() |> get("/interaction") |> html_response(200)
    assert html =~ ~s(id="panel-force")
    assert html =~ "Not started"
    assert length(Regex.scan(~r/<circle [^>]*data-node=/, html)) == 12
  end

  test "a subscriber given at start receives every tick, from the first" do
    {:ok, sim} = ForceDemo.start()
    assert_receive {:force_tick, %{nodes: nodes, links: links}}
    assert length(nodes) == 12
    assert length(links) == 11
    assert Simulation.alpha(sim) < 1.0
  end

  test "a tick redraws the page's graph; Reheat and Pin reach the simulation" do
    {:ok, socket} = InteractionLive.mount(%{}, %{}, %Phoenix.LiveView.Socket{})
    {:ok, sim} = ForceDemo.start()
    socket = Phoenix.Component.assign(socket, :force_sim, sim)

    moved = for node <- socket.assigns.force_nodes, do: %{node | x: node.x + 10}
    {:noreply, socket} = InteractionLive.handle_info({:force_tick, %{nodes: moved}}, socket)
    assert socket.assigns.force_nodes == moved
    assert socket.assigns.force_ticks == 1
    assert is_float(socket.assigns.force_alpha)

    :ok = Simulation.stop(sim)
    {:noreply, socket} = InteractionLive.handle_event("force_reheat", %{}, socket)
    assert Simulation.alpha(sim) > 0.9

    {:noreply, socket} = InteractionLive.handle_event("force_pin", %{}, socket)
    assert socket.assigns.force_pinned
    hub = Enum.find(Simulation.nodes(sim), &(&1.id == "hub"))
    assert {hub.fx, hub.fy} == {180.0, 120.0}

    {:noreply, socket} = InteractionLive.handle_event("force_pin", %{}, socket)
    refute socket.assigns.force_pinned
  end

  # The page as `mount/3` makes it, with its sample clock off as the session can turn it,
  # and a simulation started as a connected page starts its own: the test then sends it
  # the clock's `:force_sample` messages itself, and never waits on the wall clock.
  defp heat_page do
    {:ok, socket} =
      InteractionLive.mount(%{}, %{"force_clock" => false}, %Phoenix.LiveView.Socket{
        assigns: %{__changed__: %{}}
      })

    {:ok, sim} = ForceDemo.start()
    Phoenix.Component.assign(socket, :force_sim, sim)
  end

  defp sample(socket) do
    {:noreply, socket} = InteractionLive.handle_info(:force_sample, socket)
    socket
  end

  test "five periods of the wave: the target follows it, and the window stays bounded" do
    socket = heat_page()
    %{force_sim: sim, force_clock: false} = socket.assigns

    socket =
      Enum.reduce(0..159, socket, fn n, socket ->
        socket = sample(socket)
        a = socket.assigns
        expected = if rem(n, 32) < 16, do: 0.3, else: 0.0
        assert a.force_target == expected
        assert :sys.get_state(sim).alpha_target == expected
        assert length(a.force_samples) == min(n + 1, ForceDemo.window())
        assert %{t: t, input: ^expected, alpha: alpha} = List.last(a.force_samples)
        assert t == n * 0.25
        assert alpha >= 0 and alpha <= 1
        socket
      end)

    # The window is the last 30 s, and both charts draw it on that one time domain.
    %{force_samples: samples, force_charts: charts} = socket.assigns
    assert hd(samples).t == 40 * 0.25
    assert List.last(samples).t == 159 * 0.25
    assert ForceDemo.charts(samples) == charts

    # The input draws as steps: its path has vertical edges (`V`) where the wave switches.
    [input_path] = mark_paths(Visualize.Chart.render(charts.input))
    assert input_path =~ "V"
    assert [_heat_path] = mark_paths(Visualize.Chart.render(charts.heat))
  end

  defp mark_paths(svg) do
    for [_, d] <- Regex.scan(~r/class="mark mark-line"[^>]*><path d="([^"]+)"/, svg), do: d
  end

  test "the page draws both heat charts, empty, before it connects" do
    html = build_conn() |> get("/interaction") |> html_response(200)
    assert html =~ ~s(id="force-input-chart")
    assert html =~ ~s(id="force-heat-chart")
    assert html =~ "Heat input (alpha_target)"
    assert html =~ "Heat (alpha)"
    assert html =~ "Heat input off"
  end

  test "the input off sets the target to 0, and on again the wave resumes" do
    socket = sample(heat_page())
    sim = socket.assigns.force_sim
    assert :sys.get_state(sim).alpha_target == 0.3

    {:noreply, socket} = InteractionLive.handle_event("force_heat", %{}, socket)
    assert %{force_heat_on: false, force_target: +0.0} = socket.assigns
    assert :sys.get_state(sim).alpha_target == 0.0

    socket = sample(socket)
    assert socket.assigns.force_target == 0.0
    assert List.last(socket.assigns.force_samples).input == 0.0

    {:noreply, socket} = InteractionLive.handle_event("force_heat", %{}, socket)
    assert sample(socket).assigns.force_target == 0.3
  end

  test "a page that never connects starts no clock and takes no sample" do
    {:ok, socket} = InteractionLive.mount(%{}, %{}, %Phoenix.LiveView.Socket{})
    refute socket.assigns.force_clock
    assert sample(socket).assigns.force_samples == []
  end

  test "a rising target starts a stopped simulation; a falling one leaves it stopped" do
    {:ok, sim} = ForceDemo.start()
    :ok = Simulation.stop(sim)
    assert ForceDemo.drive(sim, 0.3, 0.0) == 0.0
    refute :sys.get_state(sim).running
    assert ForceDemo.drive(sim, 0.0, 0.3) == 0.3
    assert %{running: true, alpha_target: 0.3} = :sys.get_state(sim)
  end
end
