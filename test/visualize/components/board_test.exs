defmodule Visualize.Components.BoardTest do
  @moduledoc """
  A live board in LiveView (spec/15 §9, #575, D-146): the grid at the arrangement for the
  width and its reflow, a cell as its own component carrying `data-vis-cell` and its
  chart's three hooks, every state drawn, `forward/2` routing a board process's messages,
  and the hooks' events turned into calls on the board process.
  """
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Phoenix.LiveView.Socket
  alias Visualize.Board
  alias Visualize.Board.{Binding, Server, State, View}
  alias Visualize.Components.Board, as: Component
  alias Visualize.Components.Board.Cell
  alias Visualize.Data.Schema
  alias Visualize.Event
  alias Visualize.Test.Feeds

  @moduletag :capture_log

  @line %{
    version: 2,
    sources: %{primary: %{fields: [:t, :v]}},
    frames: %{
      main: %{kind: :cartesian, scales: %{x: %{kind: :time}, y: %{kind: :linear}}}
    },
    marks: [%{type: :line, data: :primary, channels: %{x: :t, y: :v}}]
  }

  # A line with its points, whose click is an event, and a mark that names its event
  # `pick`, which the cell keeps for itself (spec/15 §9.2, D-170).
  @points %{
    @line
    | marks: [
        %{type: :line, data: :primary, channels: %{x: :t, y: :v}},
        %{
          type: :circle,
          data: :primary,
          channels: %{x: :t, y: :v},
          tooltip: %{fields: [:v], event: :event_open}
        },
        %{type: :circle, data: :primary, channels: %{x: :t, y: :v}, tooltip: %{event: "pick"}}
      ]
  }

  @t0 ~U[2026-10-11 12:00:00Z]

  defp board do
    Board.from_map!(%{
      meta: %{name: "Ops"},
      sync: "ops",
      window: %{last: 600},
      cells: %{
        latency: %{x: 0, y: 0, w: 8, h: 3, ref: {:composite, 1}, title: "Latency"},
        errors: %{x: 8, y: 0, w: 4, h: 3, ref: {:composite, 1}}
      }
    })
  end

  defp server(design \\ @line) do
    schema = Schema.new!(%{t: %{type: :time}, v: %{type: :number}})
    rows = for i <- 0..9, do: %{t: DateTime.add(@t0, i * 60), v: i}
    {feed, agent} = Feeds.scripted(schema: schema, rows: rows)
    Process.unlink(agent)
    on_exit(fn -> if Process.alive?(agent), do: Agent.stop(agent) end)
    sup = start_supervised!(Visualize.Board.Supervisor)

    {:ok, pid} =
      Server.start(sup,
        board: board(),
        store: %{{:composite, 1} => design},
        binding: Binding.new(%{{:latency, :primary} => :f, {:errors, :primary} => :f}),
        feeds: %{f: feed},
        tick: nil,
        debounce: 0,
        clock: fn -> DateTime.add(@t0, 600) end
      )

    pid
  end

  defp live_view(cell) do
    view =
      receive do
        {:visualize_board, _, {:cell, ^cell, %View{state: :live} = view}} -> view
      end

    view
  end

  # The newest live view of a cell drawn after the drawing `before` (`nil` for any): a click
  # carries the token of the drawing on screen, which is the last one drawn. A pick is a
  # round trip to the cell's process, so every view it sent before answering is already
  # here, and the mailbox is drained without waiting.
  defp latest_view(board, cell, before \\ nil) do
    view = next_view(cell, before)
    _ = Server.pick(board, cell, 0, 0)
    drain(cell, view)
  end

  defp next_view(cell, before) do
    case live_view(cell) do
      %View{drawn: ^before} -> next_view(cell, before)
      view -> view
    end
  end

  defp drain(cell, view) do
    receive do
      {:visualize_board, _, {:cell, ^cell, %View{state: :live} = newer}} -> drain(cell, newer)
    after
      0 -> view
    end
  end

  describe "the board (spec/15 §9.1)" do
    test "the grid lays every cell at its placement, each one tab stop with data-vis-cell" do
      html = render_component(Component, id: "ops", server: self(), board: board())

      assert html =~
               ~s(<section id="ops" class="vis-board" phx-hook="BoardHook" data-board-event="resize")

      assert html =~ ~s(<h2 class="vis-board-title">Ops</h2>)
      assert html =~ "grid-template-columns:repeat(12,minmax(0,1fr));grid-auto-rows:80px;gap:8px"

      assert html =~ ~r/<article id="ops-latency"[^>]*data-vis-cell="latency"[^>]*tabindex="0"/
      assert html =~ ~s(style="grid-column:1 / span 8;grid-row:1 / span 3")
      assert html =~ ~s(style="grid-column:9 / span 4;grid-row:1 / span 3")
      assert html =~ ~s(<h3 class="vis-cell-title">Latency</h3>)

      # Never blank: before a view, a cell draws loading.
      assert html =~ ~s(data-vis-state="loading")
      assert html =~ "Loading…"
    end

    test "below the breakpoint the cells stack in reading order, each across the grid" do
      html = render_component(Component, id: "ops", server: self(), board: board(), width: 500)

      assert html =~ ~s(class="vis-board vis-board-stacked")
      assert html =~ ~s(style="grid-column:1 / span 12;grid-row:1 / span 3")
      assert html =~ ~s(style="grid-column:1 / span 12;grid-row:4 / span 3")

      [first, second] = Regex.scan(~r/data-vis-cell="(\w+)"/, html, capture: :all_but_first)
      assert {first, second} == {["latency"], ["errors"]}
    end
  end

  describe "a cell (spec/15 §9.1)" do
    test "a live cell wraps its chart in the crosshair, the brush and the keyboard hooks" do
      board = server()
      {:ok, _info} = Server.subscribe(board)
      view = live_view(:latency)

      html =
        render_component(Cell,
          id: "ops-latency",
          cell: :latency,
          rect: %{x: 0, y: 0, w: 8, h: 3},
          title: "Latency",
          theme: Visualize.Theme.default(),
          target: 3,
          view: view
        )

      assert html =~ ~s(data-vis-state="live")
      assert html =~ ~s(aria-label="Latency: cell, Enter for its chart")
      assert html =~ ~r/id="ops-latency-crosshair"[^>]*phx-hook="CrosshairHook"/
      assert html =~ ~s(data-vis-sync="ops")
      assert html =~ ~s(data-xs=)

      assert html =~
               ~s(<div id="ops-latency-brush" phx-hook="BrushHook" data-brush-type="x" data-brush-event="brush" data-brush-target="3">)

      assert html =~
               ~r/id="ops-latency-keys" phx-hook="KeyboardHook" tabindex="-1"[^>]*data-keyboard-points=/

      assert html =~ ~s(class="mark mark-line")
      refute html =~ "vis-cell-banner"
    end

    test "the chart sits in a TooltipHook targeted at the cell, inside the keyboard's (D-161)" do
      board = server()
      {:ok, _info} = Server.subscribe(board)
      view = live_view(:latency)

      html =
        render_component(Cell,
          id: "ops-latency",
          cell: :latency,
          rect: %{x: 0, y: 0, w: 8, h: 3},
          title: "Latency",
          theme: Visualize.Theme.default(),
          target: 3,
          view: view
        )

      # The cell's own component, as the keyboard's target names it.
      [_, myself] = Regex.run(~r/data-keyboard-target="([^"]+)"/, html)

      assert html =~
               ~s(<div id="ops-latency-tooltip" phx-hook="TooltipHook" data-tooltip-target="#{myself}" data-tooltip-drawn="#{view.drawn}">)

      assert html =~ ~r/id="ops-latency-keys".*id="ops-latency-tooltip".*<svg/s

      # No sync group on the tooltip: the crosshair shares the board's hover.
      [tooltip] = Regex.run(~r/<div id="ops-latency-tooltip"[^>]*>/, html)
      refute tooltip =~ "data-vis-sync"

      # A loading cell has no chart, so no hook.
      refute cell_html(%View{cell: :a, state: :loading, size: {1, 1}, note: "x"}) =~ "TooltipHook"
    end

    test "a mark's click on a cell reaches the page as one Visualize.Event, its row typed (D-170)" do
      board = server(@points)
      {:ok, _info} = Server.subscribe(board)
      view = latest_view(board, :latency)
      assert view.drawn != nil
      assert view.svg =~ ~s(data-frame="main" data-mark="1" data-tooltip-event="event_open")
      assert view.svg =~ ~s(data-row="2")

      socket = %Socket{
        assigns: %{
          __changed__: %{},
          id: "ops-latency",
          cell: :latency,
          board_id: "ops",
          server: board
        }
      }

      click = fn params ->
        Map.merge(
          %{
            "event" => "event_open",
            "frame" => "main",
            "mark" => 1,
            "row" => 2,
            "drawn" => view.drawn
          },
          params
        )
      end

      assert {:noreply, _} =
               Cell.handle_event(
                 "visualize_event",
                 click.(%{"at" => %{"x" => 140, "y" => 70}, "modifiers" => ["alt"]}),
                 socket
               )

      t2 = DateTime.add(@t0, 120)

      assert_received {:visualize_event, "ops",
                       %Event{
                         event: "event_open",
                         cell: :latency,
                         frame: :main,
                         row: %{t: ^t2, v: 2},
                         item: nil,
                         path: [],
                         at: %{x: _, y: _},
                         value: %{},
                         modifiers: [:alt]
                       }}

      # A click on a drawing the cell no longer holds, a name the mark does not declare, a
      # row the drawing does not have, the cell's own `pick`, or params of another shape:
      # nothing reaches the page.
      Cell.handle_event("visualize_event", click.(%{"drawn" => "0"}), socket)
      Cell.handle_event("visualize_event", click.(%{"event" => "nope"}), socket)
      Cell.handle_event("visualize_event", click.(%{"row" => 99}), socket)
      Cell.handle_event("visualize_event", click.(%{"event" => "pick", "mark" => 2}), socket)
      Cell.handle_event("visualize_event", %{"event" => "event_open"}, socket)
      Cell.handle_event("event_open", %{"id" => "42"}, socket)
      Cell.handle_event("pick", %{"series" => "a", "index" => "b"}, socket)
      refute_received {:visualize_event, _, _}
      refute_received {:visualize_board_event, _, _}

      # The cell draws a new frame: a click on the one before is dropped, not resolved
      # against the new drawing; a click on the new one resolves.
      :ok = Server.resize(board, 700)
      newer = latest_view(board, :latency, view.drawn)
      refute newer.drawn == view.drawn
      Cell.handle_event("visualize_event", click.(%{}), socket)
      refute_received {:visualize_event, _, _}

      Cell.handle_event("visualize_event", click.(%{"drawn" => newer.drawn}), socket)
      assert_received {:visualize_event, "ops", %Event{event: "event_open", row: %{v: 2}}}
    end

    test "every state renders in a cell: alone where there is no chart, a banner over one" do
      theme = Visualize.Theme.default()
      svg = ~s(<svg role="img"><title>chart</title></svg>)

      for state <- [
            {:crashed, :killed},
            {:down, :timeout},
            :loading,
            :no_data,
            {:stale, 120},
            :capped
          ] do
        alone = %View{
          cell: :a,
          state: state,
          size: {300, 160},
          note: State.render(state, theme, {300, 160})
        }

        html = cell_html(alone)
        assert html =~ ~s(data-vis-state="#{State.name(state)}")
        assert html =~ ~s(class="vis-cell-placeholder")
        assert html =~ State.words(state)
        refute html =~ "CrosshairHook"

        over = %View{alone | svg: svg, note: State.banner(state, theme, 300)}
        html = cell_html(over)
        assert html =~ ~s(<div class="vis-cell-banner">)
        assert html =~ "CrosshairHook" and html =~ "<title>chart</title>"
      end
    end
  end

  defp cell_html(view) do
    render_component(Cell,
      id: "ops-a",
      cell: :a,
      rect: %{x: 0, y: 0, w: 6, h: 2},
      title: nil,
      theme: Visualize.Theme.default(),
      target: 1,
      view: view
    )
  end

  describe "the page's part (spec/15 §9.2)" do
    test "forward/2 sends a cell's view to its component and the board's state to the board's" do
      view = %View{cell: :latency, state: :loading, size: {1, 1}}
      Component.forward("ops", {:visualize_board, self(), {:cell, :latency, view}})
      assert_received {:phoenix, :send_update, {{Cell, "ops-latency"}, %{view: ^view}}}

      info = %{window: nil, zone: "Etc/UTC", now: @t0, width: 900, sync: nil}
      Component.forward("ops", {:visualize_board, self(), {:board, info}})
      assert_received {:phoenix, :send_update, {{Component, "ops"}, %{info: ^info}}}

      assert Component.forward("ops", {:other, :message}) == :ignore
      assert Component.cell_id("ops", :latency) == "ops-latency"
    end

    test "the hooks' events become calls on the board process" do
      board = server()
      socket = socket(board)

      assert {:noreply, %{assigns: %{width: 640}}} =
               Component.handle_event("resize", %{"width" => 640}, socket)

      assert Server.info(board).width == 640

      domain = [
        DateTime.to_unix(@t0, :millisecond) + 60_000,
        DateTime.to_unix(@t0, :millisecond) + 300_000
      ]

      [from, to] = Enum.map(domain, &DateTime.from_unix!(&1, :millisecond))
      Component.handle_event("brush", %{"domain" => domain}, socket)
      assert Server.info(board).window == {from, to}

      # A cleared brush is a click as often as an undo: the window stays (spec/15 §13.1).
      Component.handle_event("brush_clear", %{}, socket)
      assert Server.info(board).window == {from, to}
      assert Server.info(board).moved

      Component.handle_event("reset_window", %{}, socket)
      assert Server.info(board).board.window == %{last: 600}
      refute Server.info(board).moved

      # A brush with no domain changes nothing.
      Component.handle_event("brush", %{"x0" => 1, "x1" => 9}, socket)
      assert Server.info(board).board.window == %{last: 600}
      refute_received {:visualize_board_brush, _, _}
    end

    test "with brush: :host the brush and Reset window go to the page, not the board (D-161)" do
      board = server()
      socket = put_in(socket(board).assigns[:brush], :host)
      ms = DateTime.to_unix(@t0, :millisecond)

      Component.handle_event("brush", %{"domain" => [ms + 60_000, ms + 300_000]}, socket)

      from = DateTime.from_unix!(ms + 60_000, :millisecond)
      to = DateTime.from_unix!(ms + 300_000, :millisecond)

      assert_received {:visualize_event, "ops",
                       %Event{event: :brush, cell: nil, row: nil, value: %{domain: [^from, ^to]}}}

      # The board's window is untouched until the page applies it.
      info = Server.info(board)
      assert info.board.window == %{last: 600}
      refute info.moved

      # The page applies it; the header's undo then goes to the page too.
      :ok = Server.window(board, %{from: from, to: to})
      assert Server.info(board).moved

      Component.handle_event("reset_window", %{}, socket)
      assert_received {:visualize_event, "ops", %Event{event: :brush, value: %{domain: nil}}}
      assert Server.info(board).window == {from, to}
      assert Server.info(board).moved

      # A brush without a domain, a reversed one, or a cleared brush sends nothing.
      Component.handle_event("brush", %{"x0" => 1, "x1" => 9}, socket)
      Component.handle_event("brush", %{"domain" => [ms + 9, ms + 1]}, socket)
      Component.handle_event("brush_clear", %{}, socket)
      refute_received {:visualize_event, _, _}
      refute_received {:visualize_board_brush, _, _}
    end

    test "a change of the board's selection reaches the page as :select (D-170)" do
      info = %{window: nil, zone: "Etc/UTC", now: @t0, width: 900, sync: nil, selection: nil}
      socket = %{socket(self()) | assigns: %{socket(self()).assigns | info: info}}

      # The selection held when the page subscribed is not a change.
      assert {:ok, socket} = Component.update(%{info: info}, socket)
      refute_received {:visualize_event, _, _}

      picked = %{info | selection: {:service, "api"}}
      assert {:ok, socket} = Component.update(%{info: picked}, socket)

      assert_received {:visualize_event, "ops",
                       %Event{event: :select, cell: nil, value: %{identity: {:service, "api"}}}}

      # Another message about the board that keeps the selection sends nothing.
      assert {:ok, socket} = Component.update(%{info: %{picked | width: 640}}, socket)
      refute_received {:visualize_event, _, _}

      composite = %{info | selection: %{host: "mx1", iface: "eth0"}}
      assert {:ok, socket} = Component.update(%{info: composite}, socket)
      identity = %{host: "mx1", iface: "eth0"}

      assert_received {:visualize_event, "ops",
                       %Event{event: :select, value: %{identity: ^identity}}}

      assert {:ok, _socket} = Component.update(%{info: info}, socket)
      assert_received {:visualize_event, "ops", %Event{event: :select, value: %{identity: nil}}}
    end

    test "the brush assign defaults to :server and refuses anything else" do
      html = render_component(Component, id: "ops", server: self(), board: board(), brush: :host)
      assert html =~ ~s(<section id="ops")

      assert_raise ArgumentError, ~r/:server or :host, got: :page/, fn ->
        render_component(Component, id: "ops", server: self(), board: board(), brush: :page)
      end
    end

    test "the window is shown in the board's zone" do
      # The window is UTC; Oslo is two hours ahead in October's summer time.
      info = %{
        window: {@t0, DateTime.add(@t0, 600)},
        zone: "Europe/Oslo",
        now: @t0,
        width: 1200,
        sync: nil
      }

      html = render_component(Component, id: "ops", server: self(), board: board(), info: info)

      assert html =~
               ~s[<p class="vis-board-window">2026-10-11 14:00:00 – 2026-10-11 14:10:00 (Europe/Oslo)</p>]
    end
  end

  defp socket(server) do
    %Socket{
      assigns: %{
        __changed__: %{},
        id: "ops",
        server: server,
        board: board(),
        theme: Visualize.Theme.default(),
        title: "Ops",
        width: 1200,
        info: nil,
        subscribed: true,
        myself: %Phoenix.LiveComponent.CID{cid: 1}
      }
    }
  end
end
