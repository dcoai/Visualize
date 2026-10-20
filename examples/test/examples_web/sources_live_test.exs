defmodule ExamplesWeb.SourcesLiveTest do
  @moduledoc """
  The Data sources page (spec/08 §6, §11, spec/05 §4, #781, work item #834): an Nx tensor
  through the function components, an Explorer frame summed by a design, a density with
  closed curves, the facts of quantities, and a feed asked for a window box.
  """
  use ExUnit.Case, async: true

  import Phoenix.ConnTest

  alias Examples.Sources

  @endpoint ExamplesWeb.Endpoint

  test "the page renders every panel, the function components drawn from a tensor and a frame" do
    html = build_conn() |> get("/sources") |> html_response(200)

    for id <- ~w(tensor frame density quantities box),
        do: assert(html =~ ~s(id="panel-#{id}"), id)

    # 200 samples as 200 circles of the scatter plot, the walk as a line.
    [scatter | _] = String.split(html, "A random walk")
    assert length(Regex.scan(~r/<circle /, scatter)) >= 200
    assert html =~ ~s(aria-label="Q4 shares")
    assert html =~ "Asia Pacific"
    assert html =~ ~s(id="sources-sales")
    assert html =~ ~s(id="sources-density")
  end

  test "the frame's regions are summed by the :sum step, the axis in dollars, labels turned" do
    svg = Sources.sales_svg()
    totals = Sources.totals()
    assert totals["Asia Pacific"] == 2_190_000
    # One bar per region.
    assert length(Regex.scan(~r/<rect [^>]*height="[\d.]+"[^>]*width/, svg)) >= 5
    assert svg =~ "$1M"
    assert svg =~ "rotate(-30"
  end

  test "the tensor bound to a design draws a circle per sample (D-214)" do
    svg = Sources.samples_svg()
    assert length(Regex.scan(~r/<circle /, svg)) == 200
    html = build_conn() |> get("/sources") |> html_response(200)
    assert html =~ ~s(id="sources-samples")
  end

  test "the density draws rings, and both outlines close" do
    svg = Sources.density_svg()
    assert length(Regex.scan(~r/<path /, svg)) >= 6
    assert length(Regex.scan(~r/d="M[^"]*Z"/, svg)) >= 2
  end

  test "quantities, metric kinds and currency say what the library knows" do
    assert {:angle, :cyclic, {0, 360}, _, _} = List.keyfind(Sources.quantities(), :angle, 0)

    assert {:count, :linear, {0, nil}, %{over_time: false}, %{over_time: true}} =
             List.keyfind(Sources.quantities(), :count, 0)

    assert {"examples.vm.memory.value", :gauge} in Sources.metric_kinds()

    assert %{code: "USD", minor: [{"USD", 2}, {"JPY", 0}, {"BHD", 3}], convert: {:error, _}} =
             Sources.currency()
  end

  test "a window box trims the window, then the region, then keeps each vehicle's latest" do
    now = ~U[2026-01-01 00:10:00Z]
    [{_, _, window}, {_, _, region}, {_, _, latest}] = Sources.boxes(now)

    assert length(window) > length(region)
    assert Enum.all?(region, &(&1.x >= 0 and &1.x <= 50))
    assert Enum.map(latest, & &1.vehicle) |> Enum.uniq() |> length() == length(latest)
    assert length(latest) <= length(Examples.Sources.Vehicles.names())
  end
end
