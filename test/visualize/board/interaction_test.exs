defmodule Visualize.Board.InteractionTest do
  @moduledoc """
  Interaction across a board's cells (spec/15 §13, #545, D-151): a brush sets every
  cell's window through the board and re-asks the feeds, debounced; a selection is
  `{field, value}` read through `links` and drawn as the palette's `:selected` and `:muted` in every cell
  that shows it; a drill target is validated data whose variables come from the picked
  datum.
  """
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  @moduletag :capture_log

  alias Visualize.Board
  alias Visualize.Board.{Binding, Server, View}
  alias Visualize.Components.Board, as: Component
  alias Visualize.Components.Board.Cell
  alias Visualize.Data.Schema
  alias Visualize.Test.Feeds

  # A line and its points, a series per `k`.
  @series %{
    version: 2,
    sources: %{primary: %{fields: [:t, :v, :k]}},
    frames: %{
      main: %{kind: :cartesian, scales: %{x: %{kind: :time}, y: %{kind: :linear}}}
    },
    marks: [
      %{type: :line, data: :primary, channels: %{x: :t, y: :v, series: :k}},
      %{type: :circle, data: :primary, channels: %{x: :t, y: :v, series: :k}}
    ]
  }

  # A bar per `name`, a category the schema types.
  @bars %{
    version: 2,
    sources: %{primary: %{fields: [:name, :v]}},
    frames: %{
      main: %{
        kind: :cartesian,
        scales: %{x: %{kind: :band}, y: %{kind: :linear, domain: [0, 10]}}
      }
    },
    marks: [%{type: :rect, data: :primary, channels: %{x0: :name, x1: :name, y0: 0, y1: :v}}]
  }

  @store %{{:composite, 1} => @series, {:composite, 2} => @bars}

  @series_schema Schema.new!(%{
                   t: %{type: :time},
                   v: %{type: :number},
                   k: %{type: :category}
                 })
  @bars_schema Schema.new!(%{name: %{type: :category}, v: %{type: :number}})
  @t0 ~U[2026-10-11 12:00:00Z]

  # Rows inside whatever window the feed is asked for, so a new window is seen in them.
  defp series_rows(keys) do
    fn window, _budget ->
      from = if window, do: hd(window), else: @t0
      rows = for i <- 0..3, k <- keys, do: %{t: DateTime.add(from, i * 60), v: i + 1, k: k}
      {rows, []}
    end
  end

  defp board(extra \\ %{}) do
    Board.from_map!(
      Map.merge(
        %{
          window: %{last: 3600},
          links: %{name: :k},
          cells: %{
            a: %{x: 0, y: 0, w: 4, h: 3, ref: {:composite, 1}},
            b: %{x: 4, y: 0, w: 4, h: 3, ref: {:composite, 1}},
            c: %{x: 8, y: 0, w: 4, h: 3, ref: {:composite, 2}},
            d: %{x: 0, y: 3, w: 4, h: 3, ref: {:composite, 1}}
          }
        },
        extra
      )
    )
  end

  defp scripted(opts) do
    {feed, agent} = Feeds.scripted(opts)
    Process.unlink(agent)
    on_exit(fn -> if Process.alive?(agent), do: Agent.stop(agent) end)
    {feed, agent}
  end

  # Four cells: a and b one series design over ["p", "q"], c bars over names "p" and "r",
  # and d the series design over keys none of the others has.
  defp start(opts \\ []) do
    {fa, a} = scripted(schema: @series_schema, rows: series_rows(["p", "q"]))
    {fb, b} = scripted(schema: @series_schema, rows: series_rows(["p", "q"]))
    {fc, _c} = scripted(schema: @bars_schema, rows: [%{name: "p", v: 4}, %{name: "r", v: 6}])
    {fd, _d} = scripted(schema: @series_schema, rows: series_rows(["x", "y"]))

    binding =
      Binding.new(%{
        {:a, :primary} => :fa,
        {:b, :primary} => :fb,
        {:c, :primary} => :fc,
        {:d, :primary} => :fd
      })

    sup = start_supervised!(Supervisor.child_spec(Visualize.Board.Supervisor, id: make_ref()))

    defaults = [
      board: board(),
      store: @store,
      binding: binding,
      feeds: %{fa: fa, fb: fb, fc: fc, fd: fd},
      tick: nil,
      debounce: 0,
      clock: fn -> DateTime.add(@t0, 3600) end
    ]

    {:ok, pid} = Server.start(sup, Keyword.merge(defaults, opts))
    {:ok, _info} = Server.subscribe(pid)
    {pid, %{a: a, b: b}}
  end

  # The next view of each named cell that satisfies the test.
  defp views_until(cells, test), do: views_until(cells, test, %{})
  defp views_until([], _test, seen), do: seen

  defp views_until(cells, test, seen) do
    receive do
      {:visualize_board, _board, {:cell, cell, %View{} = view}} ->
        # A cell's name is its string (D-195); the views are keyed as the test asked.
        asked = Enum.find(cells, &(to_string(&1) == cell))

        if asked != nil and test.(view),
          do: views_until(List.delete(cells, asked), test, Map.put(seen, asked, view)),
          else: views_until(cells, test, seen)
    end
  end

  defp board_info_until(test) do
    receive do
      {:visualize_board, _board, {:board, info}} ->
        if test.(info), do: info, else: board_info_until(test)
    end
  end

  # Views of a cell until the row behind its first point starts at `from`.
  defp follows(board, cell, from) do
    name = to_string(cell)

    receive do
      {:visualize_board, _board, {:cell, ^name, %View{}}} ->
        case Server.pick(board, cell, 0, 0) do
          {:ok, %{row: %{t: ^from}}} -> :ok
          _before -> follows(board, cell, from)
        end
    end
  end

  # Every message already in the mailbox, taken.
  defp drained do
    receive do
      message -> [message | drained()]
    after
      0 -> []
    end
  end

  defp live, do: &(&1.state == :live and &1.svg != nil)

  defp dims(svg), do: length(String.split(svg, ~s(opacity="0.25"))) - 1

  describe "the board value (spec/15 §1.2, §1.3, §3)" do
    test "links and a drill node read, round-trip through JSON, and are checked alone" do
      board =
        board(%{
          vars: %{service: "api"},
          cells: %{
            a: %{
              x: 0,
              y: 0,
              w: 4,
              h: 3,
              ref: {:composite, 1},
              drill: %{board: :self, vars: %{service: {:datum, :k}, range: "1h"}}
            }
          }
        })

      assert {:ok, json} = Board.to_json(board)
      assert json =~ ~s("$datum":"k")
      assert Board.from_json(json) == {:ok, board}
      assert Board.from_map(Board.to_map(board)) == {:ok, board}

      cell = fn drill ->
        %{cells: %{a: %{x: 0, y: 0, w: 1, h: 1, ref: {:composite, 1}, drill: drill}}}
      end

      assert {:error, errors} =
               Board.validate(
                 Map.merge(cell.(%{vars: %{s: {:datum, 1}}, extra: 1}), %{links: %{1 => :b}})
               )

      assert {[:cells, "a", :drill, :board], :required} in errors
      assert {[:cells, "a", :drill, :extra], :unknown_key} in errors
      assert {[:cells, "a", :drill, :vars, "s"], {:type, :field}} in errors
      assert {[:links, 1], {:type, :name}} in errors

      assert Board.validate(cell.(%{board: {:board, 1}})) ==
               {:error, [{[:cells, "a", :drill, :board], {:type, :board_ref}}]}

      assert Board.validate(cell.(:detail)) ==
               {:error, [{[:cells, "a", :drill], {:type, {:node, :drill}}}]}

      for ref <- [:self, :detail, "detail", 7],
          do: assert(Board.validate(cell.(%{board: ref})) == :ok)

      assert Board.format_error({[:cells, "a", :drill, :board], {:no_board, :detail}}) ==
               "cells.a.drill.board: names the board :detail, which the host does not hold"
    end

    test "a drill target is refused at validation when the target cannot meet it (spec/15 §13.3)" do
      detail = Board.from_map!(%{vars: %{service: "api"}})

      drilled = fn drill ->
        board(%{
          vars: %{range: "1h"},
          cells: %{
            a: %{x: 0, y: 0, w: 4, h: 3, ref: {:composite, 1}, drill: drill},
            c: %{x: 4, y: 0, w: 4, h: 3, ref: {:composite, 2}}
          }
        })
      end

      good = drilled.(%{board: :detail, vars: %{service: {:datum, :k}}})
      assert Board.validate(good, @store, boards: %{detail: detail}) == :ok

      # A target the host does not hold.
      assert Board.validate(good, @store, boards: %{}) ==
               {:error, [{[:cells, "a", :drill, :board], {:no_board, :detail}}]}

      # A variable the target does not declare, and a field the component has not.
      bad = drilled.(%{board: :detail, vars: %{region: "eu", service: {:datum, :host}}})

      assert Board.validate(bad, @store, boards: fn :detail -> {:ok, detail} end) ==
               {:error,
                [
                  {[:cells, "a", :drill, :vars, "region"], {:undeclared, :var, "region"}},
                  {[:cells, "a", :drill, :vars, "service"], {:undeclared, :field, "host"}}
                ]}

      # `:self` is the board itself, checked with or without `boards:`.
      assert Board.validate(drilled.(%{board: :self, vars: %{range: "5m"}}), @store) == :ok

      assert Board.validate(drilled.(%{board: :self, vars: %{service: "db"}}), @store) ==
               {:error,
                [{[:cells, "a", :drill, :vars, "service"], {:undeclared, :var, "service"}}]}

      # Without `boards:` another board's ref is the host's to check; the runtime is given
      # them, and refuses a board whose drill cannot be met.
      assert Board.validate(good, @store) == :ok

      sup = start_supervised!(Supervisor.child_spec(Visualize.Board.Supervisor, id: make_ref()))

      assert {:error, {:board, [{[:cells, "a", :drill, :board], {:no_board, :detail}}]}} =
               Server.start(sup, board: good, store: @store, tick: nil)
    end

    test "link/2, linked/2 and drill/3 read the board's links and a cell's target" do
      board =
        Board.from_map!(%{
          links: %{name: :service, svc: :service},
          cells: %{
            a: %{
              x: 0,
              y: 0,
              w: 1,
              h: 1,
              ref: {:composite, 1},
              drill: %{board: "detail", vars: %{service: {:datum, :name}, at: {:datum, :t}}}
            },
            b: %{x: 1, y: 0, w: 1, h: 1, ref: {:composite, 1}}
          }
        })

      assert Board.link(board, :svc) == "service"
      assert Board.link(board, :service) == "service"
      assert Board.linked(board, :svc) == ["name", "service", "svc"]
      assert Board.linked(board, :host) == ["host"]

      # Typed values from the datum: a DateTime stays one.
      assert Board.drill(board, :a, %{name: "db", t: @t0}) ==
               {:ok, %{board: "detail", vars: %{"service" => "db", "at" => @t0}}}

      assert Board.drill(board, :b, %{name: "db"}) == :none

      assert Board.drill(board, :a, %{name: "db"}) ==
               {:error, [{[:cells, "a", :drill, :vars, "at"], {:missing, :datum, "t"}}]}
    end
  end

  describe "brush to window (spec/15 §13.1)" do
    test "a brush changes every cell's window and re-asks the feeds; reset restores it" do
      {board, %{a: a, b: b}} = start()
      views_until([:a, :b, :c, :d], live())
      before = {Feeds.calls(a, :fetch), Feeds.calls(b, :fetch)}

      from = DateTime.add(@t0, 600)
      to = DateTime.add(@t0, 1200)
      assert Server.brush(board, %{from: from, to: to}) == :ok

      # Every feed asked once more, for the brushed window.
      assert {Feeds.calls(a, :fetch), Feeds.calls(b, :fetch)} ==
               {elem(before, 0) + 1, elem(before, 1) + 1}

      info = board_info_until(&(&1.window == {from, to}))
      assert info.moved

      # Every series cell follows: each draws again, and the row behind its first point is
      # now the brushed window's first.
      for cell <- [:a, :b, :d], do: follows(board, cell, from)

      assert {:error, [{[:window], {:window, :inverted}}]} =
               Server.brush(board, %{from: to, to: from})

      assert Server.reset_window(board) == :ok
      info = Server.info(board)
      assert info.board.window == %{last: 3600} and not info.moved
    end

    test "rapid brushes are debounced: one refetch, for the last window" do
      # A debounce no run of three back-to-back calls outlasts, however loaded the host.
      {board, %{a: a}} = start(debounce: 1000)
      views_until([:a], live())
      before = Feeds.calls(a, :fetch)

      windows =
        for minutes <- [5, 10, 15] do
          %{from: DateTime.add(@t0, minutes * 60), to: DateTime.add(@t0, minutes * 120)}
        end

      for window <- windows, do: assert(Server.brush(board, window) == :ok)

      # Nothing applied yet: the window waits for the brushes to settle.
      assert Server.info(board).board.window == %{last: 3600}

      last = List.last(windows)
      board_info_until(&(&1.window == {last.from, last.to}))

      # One refetch for three brushes, for the last window.
      assert Feeds.calls(a, :fetch) == before + 1

      # A window set by a call drops a brush still waiting.
      assert Server.brush(board, hd(windows)) == :ok
      assert Server.window(board, %{last: 600}) == :ok
      :ok = Server.tick(board)
      assert Server.info(board).board.window == %{last: 600}
    end
  end

  describe "linked selection (spec/15 §13.2)" do
    test "a selection dims the rest in every cell that shows it, through links, and clears" do
      {board, _agents} = start()
      seen = views_until([:a, :b, :c, :d], live())
      for {_cell, view} <- seen, do: assert(dims(view.svg) == 0)

      assert Server.select(board, {:k, "p"}) == :ok
      assert board_info_until(&(&1.selection == {"k", "p"})).selection == {"k", "p"}

      dimmed = views_until([:a, :b, :c], &(&1.svg != nil and dims(&1.svg) > 0))

      # The series cells dim series q, its path and its four points, and keep p.
      for cell <- [:a, :b] do
        svg = dimmed[cell].svg
        assert dims(svg) == 5

        for [element] <- Regex.scan(~r/<(?:path|circle)[^>]*data-series="p"[^>]*>/, svg),
            do: refute(element =~ "opacity")
      end

      # The bars name it `name`, linked to `k`: the bar "r" is dimmed, "p" is not.
      assert dims(dimmed.c.svg) == 1

      # d shows neither p nor its links: drawn as it was.
      assert Server.select(board, {:name, "p"}) == :ok
      assert Server.info(board).selection == {"k", "p"}
      d = Map.fetch!(seen, :d)
      # A synchronizing call on d: the selections reached it before the pick did.
      {:ok, _row} = Server.pick(board, :d, 0, 0)

      for {:visualize_board, _, {:cell, :d, %View{svg: svg}}} <- drained(),
          do: assert(svg == d.svg)

      assert Server.select(board, nil) == :ok
      board_info_until(&(&1.selection == nil))
      cleared = views_until([:a, :b, :c], &(&1.svg != nil and dims(&1.svg) == 0))
      assert map_size(cleared) == 3
    end

    test "the selection is the palette's :selected, the rest :muted (#638, D-171)" do
      {board, _agents} = start()
      views_until([:a, :c], live())
      assert Server.select(board, {:k, "p"}) == :ok
      drawn = views_until([:a, :c], &(&1.svg != nil and dims(&1.svg) > 0))

      # The line p is heavier in its own color; q is :muted, its own color faded.
      [p] = Regex.run(~r/<path[^>]*data-series="p"[^>]*>/, drawn.a.svg)
      assert p =~ ~s(stroke-width="2")
      assert p =~ ~s{stroke="var(--vis-series-1, }
      refute p =~ "opacity" or p =~ "--vis-text"
      [q] = Regex.run(~r/<path[^>]*data-series="q"[^>]*>/, drawn.a.svg)
      assert q =~ ~s(opacity="0.25")

      # No outline anywhere: :selected has no color or stroke style of its own, so the
      # points and the bar with no stroke draw as they are (#638).
      refute drawn.a.svg =~ "vis-mask-" or drawn.a.svg =~ "--vis-text"
      refute drawn.c.svg =~ "vis-mask-"

      for [point] <- Regex.scan(~r/<circle[^>]*data-series="p"[^>]*>/, drawn.a.svg),
          do: refute(point =~ "stroke=\"" or point =~ "opacity")

      # The bar p, linked through `name`, draws as itself; the bar r fades.
      assert dims(drawn.c.svg) == 1
    end

    test "a design's own :selected and :muted win over the theme's (#638)" do
      styled =
        Map.put(@series, :styles, %{
          selected: %{stroke: :bad, stroke_width: 5},
          muted: %{opacity: 0.5, stroke_dasharray: "2 2"}
        })

      {board, _agents} = start(store: Map.put(@store, {:composite, 1}, styled))
      views_until([:a], live())
      assert Server.select(board, {:k, "p"}) == :ok

      %{a: view} =
        views_until([:a], &(&1.svg != nil and &1.svg =~ ~s(opacity="0.5")))

      [p] = Regex.run(~r/<path[^>]*data-series="p"[^>]*>/, view.svg)
      assert p =~ ~s{stroke="var(--vis-bad,}
      assert p =~ ~s(stroke-width="5")
      [q] = Regex.run(~r/<path[^>]*data-series="q"[^>]*>/, view.svg)
      assert q =~ ~s(opacity="0.5") and q =~ ~s(stroke-dasharray="2 2")
      assert dims(view.svg) == 0
    end

    test "a pick answers the row behind a keyboard point and its identity" do
      {board, _agents} = start()
      views_until([:a, :c], live())

      # Series "q" is the keyboard's second series of cell a; its third point.
      assert {:ok, %{row: row, identity: {"k", "q"}, item: {:line, "q"}, frame: "main"}} =
               Server.pick(board, :a, 1, 2)

      assert %{k: "q", v: 3, t: %DateTime{}} = row

      # A bar names no series: the schema's category field is its identity.
      assert {:ok, %{row: %{name: "r", v: 6}, identity: {"name", "r"}}} =
               Server.pick(board, :c, 0, 1)

      assert Server.pick(board, :a, 9, 0) == :error
      assert Server.pick(board, :nope, 0, 0) == :error
    end

    test "the component turns a pick into a selection, or into a drill the page follows" do
      detail = Board.from_map!(%{vars: %{service: "api"}})

      value =
        board(%{
          cells: %{
            a: %{x: 0, y: 0, w: 4, h: 3, ref: {:composite, 1}},
            b: %{x: 4, y: 0, w: 4, h: 3, ref: {:composite, 1}},
            c: %{
              x: 8,
              y: 0,
              w: 4,
              h: 3,
              ref: {:composite, 2},
              drill: %{board: :detail, vars: %{service: {:datum, :name}}}
            },
            d: %{x: 0, y: 3, w: 4, h: 3, ref: {:composite, 1}}
          }
        })

      {board, _agents} = start(board: value, boards: %{detail: detail})
      views_until([:a, :c], live())

      cell = fn name ->
        %Phoenix.LiveView.Socket{
          assigns: %{
            __changed__: %{},
            id: "ops-#{name}",
            cell: name,
            server: board,
            board: value,
            board_id: "ops"
          }
        }
      end

      Cell.handle_event("pick", %{"series" => 0, "index" => 1}, cell.(:a))
      assert Server.info(board).selection == {"k", "p"}

      Cell.handle_event("pick", %{"series" => 0, "index" => 1}, cell.(:c))

      # The drill reaches the page as one event, with the picked row and its item (D-170).
      assert_received {:visualize_event, "ops",
                       %Visualize.Event{
                         event: :drill,
                         cell: "c",
                         frame: "main",
                         item: {:rect, "r"},
                         path: [{:rect, "r"}],
                         row: %{name: "r", v: 6},
                         value: %{board: :detail, vars: %{"service" => "r"}}
                       }}

      # None of the old messages is sent.
      refute_received {:visualize_board_drill, _, _}

      # The drill did not select.
      assert Server.info(board).selection == {"k", "p"}

      # Escape's event clears it.
      socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}, server: board}}
      Component.handle_event("select_clear", %{}, socket)
      assert Server.info(board).selection == nil
    end

    test "the board's header shows the selection and the undo, and the section marks it" do
      info = %{
        window: {@t0, DateTime.add(@t0, 600)},
        zone: "Etc/UTC",
        now: @t0,
        width: 1200,
        sync: nil,
        selection: {:service, "api"},
        moved: true
      }

      html =
        render_component(Component,
          id: "ops",
          server: self(),
          board: board(),
          info: info
        )

      assert html =~ ~s(data-board-selection="service api")
      assert html =~ "Selected: service api"
      assert html =~ ~s(phx-click="select_clear")
      assert html =~ ~s(phx-click="reset_window")

      html =
        render_component(Component,
          id: "ops",
          server: self(),
          board: board(),
          info: %{info | selection: nil, moved: false}
        )

      refute html =~ "data-board-selection"
      refute html =~ "Reset window"
    end
  end

  describe "declared identity (spec/15 §13.2, D-167)" do
    # A series per interface, `s`, over rows that declare who they are about: a host and
    # an interface together.
    @interfaces %{
      version: 2,
      sources: %{primary: %{fields: [:t, :v, :s, :host, :iface]}},
      frames: %{
        main: %{kind: :cartesian, scales: %{x: %{kind: :time}, y: %{kind: :linear}}}
      },
      marks: [
        %{type: :line, data: :primary, channels: %{x: :t, y: :v, series: :s}},
        %{type: :circle, data: :primary, channels: %{x: :t, y: :v, series: :s}}
      ]
    }

    defp interface_rows do
      fn window, _budget ->
        from = if window, do: hd(window), else: @t0

        rows =
          for i <- 0..3, host <- ["mx1", "mx2"], iface <- ["eth0", "eth1"] do
            %{
              t: DateTime.add(from, i * 60),
              v: i + 1,
              s: "#{host}/#{iface}",
              host: host,
              iface: iface
            }
          end

        {rows, []}
      end
    end

    defp start_identified(schema) do
      {feed, _agent} = scripted(schema: schema, rows: interface_rows())

      value =
        Board.from_map!(%{
          window: %{last: 3600},
          links: %{node: :host},
          cells: %{a: %{x: 0, y: 0, w: 6, h: 3, ref: {:composite, 3}}}
        })

      sup = start_supervised!(Supervisor.child_spec(Visualize.Board.Supervisor, id: make_ref()))

      {:ok, board} =
        Server.start(sup,
          board: value,
          store: %{{:composite, 3} => @interfaces},
          binding: Binding.new(%{{:a, :primary} => :f}),
          feeds: %{f: feed},
          tick: nil,
          debounce: 0,
          clock: fn -> DateTime.add(@t0, 3600) end
        )

      {:ok, _info} = Server.subscribe(board)
      views_until([:a], live())
      board
    end

    @fields %{
      t: %{type: :time},
      v: %{type: :number},
      s: %{type: :category},
      host: %{type: :category},
      iface: %{type: :category}
    }

    test "one declared field is picked before the series inference would be" do
      board = start_identified(Schema.new!(put_in(@fields, [:host, :identity], true)))

      # Series 0 is "mx1/eth0"; inference would have said `{:s, "mx1/eth0"}`.
      assert {:ok, %{identity: {"host", "mx1"}}} = Server.pick(board, :a, 0, 0)
    end

    test "with no declared identity, inference picks as before" do
      board = start_identified(Schema.new!(@fields))
      assert {:ok, %{identity: {"s", "mx1/eth0"}}} = Server.pick(board, :a, 0, 0)
    end

    test "a composite identity is picked as a map, and selects only the rows holding all of it" do
      schema =
        @fields
        |> put_in([:host, :identity], true)
        |> put_in([:iface, :identity], true)
        |> Schema.new!()

      board = start_identified(schema)

      assert {:ok, %{row: row, identity: identity}} = Server.pick(board, :a, 0, 0)
      assert identity == %{"host" => "mx1", "iface" => "eth0"}
      assert %{host: "mx1", iface: "eth0"} = row

      assert Server.select(board, identity) == :ok
      assert board_info_until(&(&1.selection == identity)).selection == identity

      # Three of the four interfaces dim: their paths and four points each. A selection of
      # the host alone would keep mx1's eth1 too.
      %{a: view} = views_until([:a], &(&1.svg != nil and dims(&1.svg) > 0))
      assert dims(view.svg) == 15

      assert Server.select(board, {:host, "mx1"}) == :ok
      %{a: view} = views_until([:a], &(&1.svg != nil and dims(&1.svg) == 10))
      assert dims(view.svg) == 10
    end

    test "a map of one field is the pair; links read each field of a map" do
      board = start_identified(Schema.new!(@fields))

      assert Server.select(board, %{host: "mx1"}) == :ok
      assert Server.info(board).selection == {"host", "mx1"}

      assert Server.select(board, %{node: "mx2", iface: "eth1"}) == :ok
      assert Server.info(board).selection == %{"host" => "mx2", "iface" => "eth1"}
    end

    test "the header reads a composite selection field by field" do
      info = %{
        window: {@t0, DateTime.add(@t0, 600)},
        zone: "Etc/UTC",
        now: @t0,
        width: 1200,
        sync: nil,
        selection: %{iface: "eth0", host: "mx1"},
        moved: false
      }

      html = render_component(Component, id: "ops", server: self(), board: board(), info: info)
      assert html =~ "Selected: host mx1, iface eth0"
    end
  end
end
