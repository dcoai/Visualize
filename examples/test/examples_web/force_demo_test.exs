defmodule ExamplesWeb.ForceDemoTest do
  @moduledoc """
  The force layout in the examples (spec/06 §8.4, #781, work item #836): the gallery's force
  graph writes its step's `alpha` and `ticks`, and `/interaction` runs a live
  `Force.Simulation` it subscribed to from the start, redrawing on each tick, with Reheat and
  Pin the hub reaching the simulation.
  """
  use ExUnit.Case, async: true

  import Phoenix.ConnTest

  alias ExamplesWeb.{ForceDemo, InteractionLive}
  alias Visualize.Layout.Force.Simulation

  @endpoint ExamplesWeb.Endpoint

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
end
