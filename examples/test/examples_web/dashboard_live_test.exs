defmodule ExamplesWeb.DashboardLiveTest do
  @moduledoc """
  The synced dashboard (#467, spec/10 §6.4): three panels of different widths over one
  time axis, each joined to one sync group by its design, each holding a crosshair over a
  brush; one `brush_select` is one server event and summarises the window; and the page's
  render stays within a light chart's cost (#469).
  """
  use ExUnit.Case, async: true

  import Phoenix.ConnTest

  alias ExamplesWeb.DashboardLive

  @endpoint ExamplesWeb.Endpoint

  # A light gallery chart's still-render budget (examples/test/examples/gallery_cost_test.exs):
  # the three panels together stay within it.
  @light_budget 4_000_000

  defp mounted do
    {:ok, socket} = DashboardLive.mount(%{}, %{}, %Phoenix.LiveView.Socket{})
    socket
  end

  defp html(socket) do
    socket.assigns
    |> Map.put(:__changed__, %{})
    |> DashboardLive.render()
    |> Phoenix.LiveViewTest.rendered_to_string()
  end

  test "three panels of different widths join one group, each a crosshair over a brush" do
    page = html(mounted())

    # The design's key reaches every panel's chart and its crosshair.
    assert length(Regex.scan(~r/data-vis-sync="dashboard"/, page)) == 6

    widths =
      for [_, width] <- Regex.scan(~r/data-vis-sync-x="[^,]+,[^,]+,[^,]+,[^,]+,(\d+)"/, page),
          uniq: true,
          do: width

    assert Enum.sort(widths) == ["440", "900"]

    for id <- ~w(requests latency errors) do
      assert page =~ ~s(id="dash-#{id}" phx-hook="CrosshairHook")

      assert page =~
               ~r/id="dash-#{id}-brush" phx-hook="BrushHook" phx-update="ignore" data-brush-type="x" data-brush-extent="[\d.]+,[\d.]+,[\d.]+,[\d.]+"/
    end

    # Every panel reads one time axis: the same domain in milliseconds.
    domains =
      for [_, d0, d1] <- Regex.scan(~r/data-vis-sync-x="([^,]+),([^,]+),/, page), uniq: true do
        {d0, d1}
      end

    assert [{d0, _d1}] = domains
    assert d0 == to_string(DateTime.to_unix(~U[2026-01-01 00:00:00Z], :millisecond))
    assert page =~ "No window brushed."
  end

  test "one brush_select is one server event, and the window is summarised for every panel" do
    from = DateTime.to_unix(~U[2026-01-01 06:00:00Z], :millisecond)
    to = DateTime.to_unix(~U[2026-01-01 12:00:00Z], :millisecond)

    {:noreply, socket} =
      DashboardLive.handle_event("brush_select", %{"domain" => [from, to]}, mounted())

    assert socket.assigns.events == 1

    assert [{"Requests", "req/s", mean, peak}, {"Latency", _, _, _}, {"Errors", _, _, _}] =
             socket.assigns.summary

    assert is_float(mean) and peak >= mean

    page = html(socket)
    assert page =~ "06:00 – 12:00"
    assert page =~ ~s(<strong id="dash-events">1</strong>)

    {:noreply, cleared} = DashboardLive.handle_event("brush_clear", %{}, socket)
    assert cleared.assigns.events == 2
    assert cleared.assigns.window == nil
    assert html(cleared) =~ "No window brushed."
  end

  test "the page is routed, linked from the Client-side Interactions page (#500), and as cheap as a light chart" do
    assert build_conn() |> get("/dashboard") |> html_response(200) =~ "Synced dashboard"
    assert build_conn() |> get("/interaction") |> html_response(200) =~ ~s(href="/dashboard")

    {work, panels} = Visualize.Work.reductions(fn -> DashboardLive.build() end)
    assert length(panels) == 3
    assert work <= @light_budget, "the three panels cost #{work} reductions"
  end

  test "the dashboard is panels: its explanation with the three charts, and the code (#505)" do
    page = html(mounted())

    assert page =~
             ~r/<section id="panel-dashboard" class="panel">\s*<h2 class="panel-title">Synced dashboard<\/h2>\s*<p class="panel-note">/

    assert page =~
             ~r/<section id="panel-code" class="panel">\s*<h2 class="panel-title">The design key and the markup<\/h2>/

    # Each chart is a panel of its own inside the dashboard's, its heading an h3.
    for id <- ~w(requests latency errors) do
      assert page =~
               ~r/<section class="panel dash-panel dash-#{id}">\s*<h3 class="panel-title">.*?<\/h3>\s*<div id="dash-#{id}" phx-hook="CrosshairHook"/s
    end
  end
end
