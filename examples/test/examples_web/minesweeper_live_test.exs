defmodule ExamplesWeb.MinesweeperLiveTest do
  @moduledoc """
  The `/minesweeper` page (#758) played through its chart. Each move is a click on a cell
  as `TooltipHook` pushes it — the cell's mark and row ordinal, and the token of the
  drawing it landed on — handed to the page's `Visualize.Components.Chart`, which resolves
  it to a `Visualize.Event` whose item is the cell's declared identity (D-167, D-170) and
  sends it to the page, whose clause makes the next game. A seeded game is played so to a
  win and to a loss.

  The examples carry no LiveView test DOM, so the page and its component are driven as
  LiveView drives them — mount, update, the event, the message — as the other pages'
  tests do; the page's markup is read from its first, disconnected render.
  """
  use ExUnit.Case, async: true

  import Phoenix.ConnTest

  alias Examples.Minesweeper
  alias ExamplesWeb.MinesweeperLive
  alias Phoenix.LiveView.Socket
  alias Visualize.Components.Chart, as: Component

  @endpoint ExamplesWeb.Endpoint

  # Seed 42 opened at the center; `Examples.MinesweeperTest` holds its layout exactly.
  @seed 42
  @first {4, 4}

  defp page(mode \\ "reveal") do
    {:ok, socket} =
      MinesweeperLive.mount(%{"seed" => "#{@seed}"}, %{}, %Socket{assigns: %{__changed__: %{}}})

    {:noreply, socket} = MinesweeperLive.handle_event("mode", %{"mode" => mode}, socket)
    socket
  end

  # A click on the cell `{r, c}`: the page's chart drawn by its component, the click the
  # hook sends on that drawing — the rect mark (the frame's first) and the cell's ordinal
  # among the rows, row by row — resolved by the component, and its message handled by the
  # page. `modifiers` are the keys held.
  defp click(socket, {r, c}, modifiers \\ []) do
    component = drawn(socket)

    params = %{
      "event" => "cell_click",
      "frame" => "main",
      "mark" => 0,
      "row" => r * 9 + c,
      "drawn" => component.assigns.drawn,
      "modifiers" => modifiers
    }

    {:noreply, _component} = Component.handle_event("visualize_event", params, component)
    assert_receive {:visualize_event, "mines-chart", event} = message
    assert event.item == {:rect, %{"row" => r, "col" => c}}
    {:noreply, socket} = MinesweeperLive.handle_info(message, socket)
    socket
  end

  defp drawn(socket) do
    {:ok, component} = Component.mount(%Socket{assigns: %{__changed__: %{}}})

    {:ok, component} =
      Component.update(%{id: "mines-chart", chart: socket.assigns.chart}, component)

    component
  end

  # The game the page plays, opened as the page opens it, to read the layout from.
  defp layout, do: Minesweeper.reveal(Minesweeper.new(seed: @seed), @first)

  # Each cell's state, as the chart drew it: the rect's datum, found by its row ordinal.
  defp states(socket) do
    svg = Visualize.Chart.render(socket.assigns.chart, root: true)

    for [_, state, i] <- Regex.scan(~r/data-datum-state="([a-z]+)" data-row="(\d+)"/, svg),
        into: %{} do
      i = String.to_integer(i)
      {{div(i, 9), rem(i, 9)}, state}
    end
  end

  test "the page draws the grid as a design, every cell a declared identity" do
    html = build_conn() |> get("/minesweeper?seed=#{@seed}") |> html_response(200)

    assert html =~ ~s(<h2 class="panel-title">Minesweeper</h2>)
    assert html =~ ~s(id="mines-chart" phx-hook="TooltipHook")
    assert html =~ ~s(data-tooltip-event="cell_click")
    assert html =~ "10 mines left"
    assert html =~ "Click any cell to start"
    assert html =~ ~s(phx-value-mode="flag")
    assert html =~ "New game"

    # 81 cells, each keyed to its row and carrying its identity, row and column together;
    # the motion it has plays through MotionHook.
    assert length(Regex.scan(~r/<rect data-datum="state"/, html)) == 81
    assert html =~ ~s(data-vis-id="main.1.col=4&amp;row=4")
    assert html =~ ~s(phx-hook="MotionHook")
  end

  test "a click is resolved to the cell's identity, and Shift or Flag mode flags" do
    socket = click(page(), @first)
    assert states(socket)[@first] == "revealed"
    assert socket.assigns.game.status == :playing
    assert socket.assigns.started != nil

    # Shift held: the click flags; again, the flag comes off.
    socket = click(socket, {0, 0}, ["shift"])
    assert states(socket)[{0, 0}] == "flagged"
    assert Minesweeper.mines_left(socket.assigns.game) == 9
    socket = click(socket, {0, 0}, ["shift"])
    assert states(socket)[{0, 0}] == "hidden"

    # Flag mode: a plain click flags, and a flag is not revealed through.
    {:noreply, socket} = MinesweeperLive.handle_event("mode", %{"mode" => "flag"}, socket)
    socket = click(socket, {0, 0})
    assert states(socket)[{0, 0}] == "flagged"
    {:noreply, socket} = MinesweeperLive.handle_event("mode", %{"mode" => "reveal"}, socket)
    socket = click(socket, {0, 0})
    assert states(socket)[{0, 0}] == "flagged"
  end

  test "a click on a drawing the page no longer holds is dropped" do
    socket = page()
    stale = drawn(socket)
    socket = click(socket, @first)

    # The component now holds the new drawing; the old token resolves to nothing.
    current = Component.update(%{id: "mines-chart", chart: socket.assigns.chart}, stale)
    {:ok, current} = current
    params = %{"event" => "cell_click", "frame" => "main", "mark" => 0, "row" => 0}

    Component.handle_event(
      "visualize_event",
      Map.put(params, "drawn", stale.assigns.drawn),
      current
    )

    # The event is resolved within the call, so nothing sent by now is nothing sent.
    refute_received {:visualize_event, _, _}
  end

  test "a seeded game played to a win" do
    game = layout()
    socket = click(page(), @first)

    safe = for cell <- Minesweeper.cells(game), not Minesweeper.mine?(game, cell), do: cell
    socket = Enum.reduce(safe, socket, &click(&2, &1))

    assert socket.assigns.game.status == :won
    assert Minesweeper.mines_left(socket.assigns.game) == 0
    states = states(socket)

    for cell <- Minesweeper.cells(game) do
      assert states[cell] == if(Minesweeper.mine?(game, cell), do: "flagged", else: "revealed")
    end

    # The counts are drawn as text in their colors, the flags as triangles.
    svg = Visualize.Chart.render(socket.assigns.chart, root: true)
    assert svg =~ ~r/<text class="mark-text"[^>]*fill="var\(--vis-red, #c23238\)"[^>]*>3<\/text>/
    assert length(Regex.scan(~r/<g class="vis-enter-[0-9a-z]+"><path/, svg)) == 10

    html = static(socket)
    assert html =~ "Cleared: you won"
    assert html =~ "0 mines left"
  end

  test "a seeded game played to a loss" do
    game = layout()

    socket =
      page()
      |> click(@first)
      |> click({1, 1}, ["shift"])
      |> click({0, 1}, ["shift"])
      |> click({0, 0})

    assert socket.assigns.game.status == :lost
    states = states(socket)
    assert states[{0, 0}] == "exploded"
    assert states[{1, 1}] == "flagged"
    assert states[{0, 1}] == "misflagged"

    for cell <- Minesweeper.cells(game) -- [{0, 0}, {1, 1}],
        Minesweeper.mine?(game, cell),
        do: assert(states[cell] == "mine")

    assert static(socket) =~ "Boom: you lost"

    # Nothing moves once it is over; New game starts another, nothing mined.
    assert states(click(socket, {8, 4})) == states
    {:noreply, socket} = MinesweeperLive.handle_event("new", %{}, socket)
    assert socket.assigns.game.status == :ready
    assert Enum.all?(states(socket), fn {_cell, state} -> state == "hidden" end)
  end

  test "the clock ticks while its game goes on, and a tick of a game over or replaced changes nothing" do
    socket = click(page(), @first)
    started = socket.assigns.started

    {:noreply, ticked} = MinesweeperLive.handle_info({:tick, started}, socket)
    assert ticked.assigns.elapsed == 0

    lost = click(socket, {0, 0})
    assert lost.assigns.game.status == :lost
    assert {:noreply, ^lost} = MinesweeperLive.handle_info({:tick, started}, lost)

    {:noreply, socket} = MinesweeperLive.handle_event("new", %{}, socket)
    assert {:noreply, ^socket} = MinesweeperLive.handle_info({:tick, started}, socket)
  end

  test "the design validates, and its cells require the identity the schema declares" do
    assert {:ok, _chart} = Visualize.Chart.from_map(MinesweeperLive.design())
    assert Visualize.Data.Schema.identity(MinesweeperLive.schema()) == [:col, :row]
    assert MinesweeperLive.applied(layout()).schemas["cells"] == MinesweeperLive.schema()
  end

  # The status line as the page renders it for `socket`'s game.
  defp static(socket) do
    %{game: socket.assigns.game, elapsed: socket.assigns.elapsed}
    |> MinesweeperLive.status()
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
  end
end
