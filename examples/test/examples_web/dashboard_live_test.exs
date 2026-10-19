defmodule ExamplesWeb.DashboardLiveTest do
  @moduledoc """
  The synced dashboard (#467, spec/10 §6.4): three panels of different widths over one
  time axis, each joined to one sync group by its design, each holding a crosshair over a
  brush; one `brush_select` is one server event and summarizes the window; and the page's
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

      # The page gives the brush nothing: the design's `brush: :x` says it in the chart.
      assert page =~ ~s(id="dash-#{id}-brush" phx-hook="BrushHook" phx-update="ignore">)
    end

    refute page =~ "data-brush-extent"
    assert length(Regex.scan(~r/data-vis-brush="x"/, page)) == 3
    assert length(Regex.scan(~r/data-vis-brush-extent="[\d.]+,[\d.]+,[\d.]+,[\d.]+"/, page)) == 3

    # Every panel reads one time axis: the same domain in milliseconds.
    domains =
      for [_, d0, d1] <- Regex.scan(~r/data-vis-sync-x="([^,]+),([^,]+),/, page), uniq: true do
        {d0, d1}
      end

    assert [{d0, _d1}] = domains
    assert d0 == to_string(DateTime.to_unix(~U[2026-01-01 00:00:00Z], :millisecond))
    assert page =~ "No window brushed."
  end

  test "one brush_select is one server event, and the window is summarized for every panel" do
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
    # The window's length in the compound form (Format.duration, style: :compound).
    assert page =~ ~s{<span class="dash-length">(6h)</span>}
    assert page =~ ~s(<strong id="dash-events">1</strong>)

    {:noreply, cleared} = DashboardLive.handle_event("brush_clear", %{}, socket)
    assert cleared.assigns.events == 2
    assert cleared.assigns.window == nil
    assert html(cleared) =~ "No window brushed."
  end

  test "the requests panel's note: two lines in italic, a line height of its own" do
    [requests | _] = mounted().assigns.panels

    assert requests.svg =~
             ~r/<text class="label"[^>]*font-style="italic"[^>]*><tspan x="4">Summed over every region,<\/tspan><tspan dy="1.4em" x="4">sampled every ten minutes<\/tspan><\/text>/
  end

  test "a zone picked: the axes tick on its hours and read its clock, and so does the window" do
    html = build_conn() |> get("/dashboard?zone=Asia/Tokyo") |> html_response(200)
    assert html =~ ~r/aria-current="true"[^>]*>\s*Tokyo\s*</
    for {_name, zone} <- DashboardLive.zones(), zone, do: assert(html =~ "?zone=#{zone}")

    {:ok, tokyo} = DashboardLive.mount(%{"zone" => "Asia/Tokyo"}, %{}, %Phoenix.LiveView.Socket{})
    assert tokyo.assigns.zone == "Asia/Tokyo"
    [requests | _] = tokyo.assigns.panels

    # The day starts at 00:00 UTC, 09:00 in Tokyo: the first tick reads Tokyo's clock.
    [first_utc | _] =
      Regex.scan(~r/<text[^>]*>(\d\d:\d\d)<\/text>/, hd(mounted().assigns.panels).svg)

    [first_tokyo | _] = Regex.scan(~r/<text[^>]*>(\d\d:\d\d)<\/text>/, requests.svg)
    assert first_utc != first_tokyo

    from = DateTime.to_unix(~U[2026-01-01 06:00:00Z], :millisecond)
    to = DateTime.to_unix(~U[2026-01-01 07:30:00Z], :millisecond)

    {:noreply, socket} =
      DashboardLive.handle_event("brush_select", %{"domain" => [from, to]}, tokyo)

    page = html(socket)
    assert page =~ "15:00 – 16:30"
    assert page =~ ~s{<span class="dash-length">(1h 30m)</span>}

    # A zone the page does not offer is UTC.
    assert DashboardLive.zone("Mars/Olympus") == nil
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
