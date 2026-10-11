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

  defp server do
    schema = Schema.new!(%{t: %{type: :time}, v: %{type: :number}})
    rows = for i <- 0..9, do: %{t: DateTime.add(@t0, i * 60), v: i}
    {feed, agent} = Feeds.scripted(schema: schema, rows: rows)
    Process.unlink(agent)
    on_exit(fn -> if Process.alive?(agent), do: Agent.stop(agent) end)
    sup = start_supervised!(Visualize.Board.Supervisor)

    {:ok, pid} =
      Server.start(sup,
        board: board(),
        store: %{{:composite, 1} => @line},
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
      after
        5000 -> flunk("no live view of #{cell}")
      end

    view
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
