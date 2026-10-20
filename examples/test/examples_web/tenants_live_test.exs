defmodule ExamplesWeb.TenantsLiveTest do
  @moduledoc """
  The tenant chat (#654, spec/14 §3.13, spec/15 §10): a board of two tenants whose messages
  are drawn in their sender's tenant style by the host's generators, registered in the
  examples' configuration, with the viewer in the board's `assigns:`.
  """
  use ExUnit.Case, async: false

  import Phoenix.ConnTest

  alias ExamplesWeb.TenantsLive
  alias Visualize.Board.Server

  @endpoint ExamplesWeb.Endpoint

  test "the generators are the configuration's, and the designs validate against them" do
    assert Application.get_env(:visualize, :generators) ==
             [Examples.Tenants.Generators, Examples.BoardDemo.Generators]

    assert {:ok, _chart} = Visualize.Chart.from_map(Examples.Tenants.transcript())
    assert {:ok, _chart} = Visualize.Chart.from_map(Examples.Tenants.per_tenant())
  end

  test "the page renders the board's two cells before it connects" do
    html = build_conn() |> get("/tenants") |> html_response(200)

    assert html =~ "<h2 class=\"vis-board-title\">Tenant chat</h2>"
    assert html =~ ~s(data-vis-cell="transcript")
    assert html =~ ~s(data-vis-cell="counts")
    assert html =~ ~s(phx-click="viewer")
  end

  test "each message is drawn in its sender's tenant style, the viewer's own outlined" do
    {:ok, board} = Examples.Tenants.start("acme")
    {:ok, _info} = Server.subscribe(board)
    :ok = Server.tick(board)
    views = views(%{}, [:transcript, :counts])

    transcript = views.transcript.svg
    acme = brand(:royalblue)
    globex = brand(:darkorange)

    # Both tenants' outlines, and Globex's dash: each message its sender's style.
    assert transcript =~ ~s(stroke="#{acme}")
    assert transcript =~ ~s(stroke="#{globex}")
    assert transcript =~ ~s(stroke-dasharray="5 3")
    # The viewer is Acme: its messages carry the heavier outline, Globex's do not.
    assert transcript =~ ~s(stroke-width="2.5")
    assert transcript =~ "Ana: Morning!"

    # The bars take each tenant's brand color.
    assert views.counts.svg =~ ~s(fill="#{acme}")
    assert views.counts.svg =~ ~s(fill="#{globex}")

    Server.unsubscribe(board, self())
    Server.stop(board)
  end

  test "View as restarts the board for the other viewer" do
    {:ok, socket} = TenantsLive.mount(%{}, %{}, %Phoenix.LiveView.Socket{})
    first = socket.assigns.board
    assert socket.assigns.viewer == "acme"

    {:noreply, socket} = TenantsLive.handle_event("viewer", %{"tenant" => "globex"}, socket)
    assert socket.assigns.viewer == "globex"
    refute Process.alive?(first)
    assert Server.info(socket.assigns.board).board.meta.name == "Tenant chat"
    Server.stop(socket.assigns.board)
  end

  # A brand color as a cell's SVG writes it.
  defp brand(name),
    do: Visualize.Color.resolve(Visualize.Color.color(name), Visualize.Theme.default(), :css)

  defp views(seen, []), do: seen

  defp views(seen, waiting) do
    receive do
      {:visualize_board, _board, {:cell, name, %{state: state} = view}} when state != :loading ->
        # A cell is named by its string (D-195); the views are keyed as the test asked.
        case Enum.find(waiting, &(to_string(&1) == name)) do
          nil -> views(seen, waiting)
          cell -> views(Map.put(seen, cell, view), List.delete(waiting, cell))
        end

      {:visualize_board, _board, _other} ->
        views(seen, waiting)
    end
  end
end
