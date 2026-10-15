defmodule Visualize.Board.ExportTest.Viewer do
  @moduledoc false
  # A host's generator that reads the viewer from the assigns (spec/14 §3.13), registered
  # only on the board, never in app config (#681).
  use Visualize.Generators

  defgenerator viewer_stroke(ctx) do
    %{stroke: %{width: if(get_in(ctx, [:assigns, :viewer]) == "globex", do: 3, else: 1)}}
  end
end

defmodule Visualize.Board.ExportTest do
  @moduledoc """
  A board exported (spec/15 §12, #578, D-150): one SVG document whose cells are placed at
  their boxes and embed each cell's own drawing byte for byte, a PNG through resvg, a
  frozen snapshot that draws identically with no feed, store or process, and printed
  pages that fit the paper and split no cell.
  """
  use ExUnit.Case, async: true

  @moduletag :capture_log

  @patience 10_000

  alias Visualize.Board
  alias Visualize.Board.{Binding, Export, Server, Snapshot, State, View}
  alias Visualize.Data.{Delivery, Schema}
  alias Visualize.Test.Feeds

  doctest Visualize.Board.Export

  @line %{
    version: 2,
    meta: %{name: "Wave"},
    sources: %{primary: %{fields: [:t, :v]}},
    frames: %{
      main: %{
        kind: :cartesian,
        scales: %{x: %{kind: :time}, y: %{kind: :linear}},
        axes: [%{scale: :x, side: :bottom}, %{scale: :y, side: :left}]
      }
    },
    marks: [%{type: :line, data: :primary, channels: %{x: :t, y: :v}}]
  }

  @store %{{:composite, 1} => @line}
  @schema Schema.new!(%{t: %{type: :time}, v: %{type: :number}})
  @t0 ~U[2026-10-11 12:00:00Z]

  defp rows(n), do: for(i <- 0..(n - 1), do: %{t: DateTime.add(@t0, i * 60), v: rem(i * 7, 11)})

  defp board(extra \\ %{}) do
    Board.from_map!(
      Map.merge(
        %{
          meta: %{name: "Ops"},
          window: %{last: 3600},
          cells: %{
            a: %{x: 0, y: 0, w: 6, h: 3, ref: {:composite, 1}, title: "A"},
            b: %{x: 6, y: 0, w: 6, h: 3, ref: {:composite, 1}},
            c: %{x: 0, y: 3, w: 12, h: 2, ref: {:composite, 1}, title: "C"}
          }
        },
        extra
      )
    )
  end

  defp pools(board) do
    Map.new(board.cells, fn {name, _cell} ->
      {name, %{primary: Delivery.new(rows(20), schema: Schema.version(@schema))}}
    end)
  end

  defp realized(opts \\ []) do
    board = Keyword.get_lazy(opts, :board, &board/0)

    {:ok, snapshot} =
      Snapshot.realize(
        board,
        @store,
        pools(board),
        Keyword.merge(
          [now: DateTime.add(@t0, 3600), schemas: cache(board)],
          Keyword.delete(opts, :board)
        )
      )

    snapshot
  end

  defp cache(board) do
    Visualize.Data.Schema.Cache.new(for {name, _} <- board.cells, do: {{name, :primary}, @schema})
  end

  # The opening tag of a cell's group, and its translation.
  defp placement(svg, cell) do
    [_, x, y] =
      Regex.run(
        ~r/<g class="vis-board-cell" data-vis-cell="#{cell}"[^>]*transform="translate\(([-\d.]+),([-\d.]+)\)/,
        svg
      )

    {String.to_float(x <> if(String.contains?(x, "."), do: "", else: ".0")),
     String.to_float(y <> if(String.contains?(y, "."), do: "", else: ".0"))}
  end

  describe "one document (spec/15 §12.1)" do
    test "each cell sits at its grid box and embeds its own drawing byte for byte" do
      snapshot = realized(width: 1000)
      svg = Export.svg(snapshot)
      views = Snapshot.views(snapshot)
      %{gap: gap} = Board.layout(snapshot.board)

      assert String.starts_with?(svg, "<svg ") and svg =~ ~s(xmlns="http://www.w3.org/2000/svg")
      assert svg =~ "Ops</title>" and svg =~ "Ops</text>"
      assert svg =~ "2026-10-11 12:00:00 – 2026-10-11 13:00:00 (Etc/UTC)"

      {_, header_bottom} = placement(svg, :a)
      header = header_bottom - gap

      for {name, {x, y, w, h}} <- Board.boxes(snapshot.board, 1000) do
        view = views[name]
        assert view.state == :live and view.size == {w, h}
        assert placement(svg, name) == {x + gap, y + gap + header}

        # The cell's own SVG, unchanged, in a viewport of its own size.
        assert :binary.matches(svg, view.svg) |> length() == 1

        assert svg =~
                 ~s(viewBox="0 0 #{fmt(w)} #{fmt(h)}" preserveAspectRatio="xMidYMid meet">) <>
                   view.svg
      end

      # The titled cells say their title; the document is the grid and a margin wide.
      assert svg =~ ~s(class="vis-cell-title") and svg =~ ">A</text>" and svg =~ ">C</text>"
      assert svg =~ ~s(width="#{1000 + 2 * gap}")
    end

    test "a cell's view is the one a running cell draws of the same data" do
      {feed, agent} = Feeds.scripted(schema: @schema, rows: rows(20))
      Process.unlink(agent)
      on_exit(fn -> if Process.alive?(agent), do: Agent.stop(agent) end)

      {:ok, server} = start(feeds: %{f: feed}, binding: binding([:a, :b, :c], :f))
      {:ok, _info} = Server.subscribe(server)

      live =
        for name <- [:a, :b, :c], into: %{}, do: {name, view_until(name, &(&1.state == :live))}

      snapshot = Server.snapshot(server)
      views = Snapshot.views(snapshot)

      for name <- [:a, :b, :c] do
        assert views[name].svg == live[name].svg
        assert views[name].crosshair == live[name].crosshair
        assert views[name].keyboard == live[name].keyboard
      end

      assert Export.svg(snapshot) =~ live.a.svg
    end

    test "a cell in a state with no chart exports the state's panel, as the component draws it" do
      {feed, agent} = Feeds.scripted(schema: @schema, error: :timeout)
      Process.unlink(agent)
      on_exit(fn -> if Process.alive?(agent), do: Agent.stop(agent) end)

      {:ok, server} = start(feeds: %{down: feed}, binding: binding([:a], :down))
      {:ok, _info} = Server.subscribe(server)

      down = view_until(:a, &(&1.state != :loading))
      assert down.state == {:down, :timeout}
      unbound = view_until(:b, &(&1.state != :loading))

      snapshot = Server.snapshot(server)
      views = Snapshot.views(snapshot)
      assert views.a.svg == nil and views.a.note == down.note
      assert views.b.note == unbound.note

      svg = Export.svg(snapshot)
      assert svg =~ ~s(data-vis-cell="a" data-vis-state="down")
      assert svg =~ down.note and svg =~ "Feed down: :timeout"
    end

    test "a crashed cell exports its crashed panel" do
      snapshot = realized()
      snapshot = put_in(snapshot.cells.b.crashed, ":killed")
      view = Snapshot.views(snapshot).b

      assert view.state == {:crashed, ":killed"} and view.svg == nil
      assert view.note == State.render({:crashed, ":killed"}, snapshot.theme, view.size)
      assert Export.svg(snapshot) =~ ~s(data-vis-cell="b" data-vis-state="crashed")
    end

    test "literal mode leaves no CSS reference" do
      svg = Export.svg(realized(), resolve: :literal)
      refute svg =~ "var(--"
      assert svg =~ ~s(fill="#ffffff")
    end

    @tag :resvg
    test "the PNG renders" do
      assert {:ok, <<137, 80, 78, 71, 13, 10, 26, 10, _::binary>>, _warnings} =
               Export.png(realized(width: 600))
    end
  end

  describe "the snapshot (spec/15 §12.2–§12.3)" do
    test "it reopens from JSON and draws identically, with the board and its feeds gone" do
      {feed, agent} = Feeds.scripted(schema: @schema, rows: rows(20))
      Process.unlink(agent)
      on_exit(fn -> if Process.alive?(agent), do: Agent.stop(agent) end)

      {:ok, server} =
        start(
          board: board(%{zone: "Europe/Oslo", sync: "ops"}),
          feeds: %{f: feed},
          binding: binding([:a, :c], :f),
          theme: Visualize.Theme.dark()
        )

      {:ok, _info} = Server.subscribe(server)
      view_until(:a, &(&1.state == :live))
      snapshot = Server.snapshot(server)
      before = Export.svg(snapshot)
      {:ok, json} = Snapshot.to_json(snapshot)

      ref = Process.monitor(server)
      Server.stop(server)
      assert_receive {:DOWN, ^ref, :process, _, _}, @patience
      Agent.stop(agent)

      assert {:ok, reopened} = Snapshot.from_json(json)
      assert reopened == snapshot
      assert Export.svg(reopened) == before
      assert before =~ "(Europe/Oslo)"
      assert Snapshot.from_map(Snapshot.to_map(snapshot)) == {:ok, snapshot}
    end

    test "rows keep their field names' spelling and a row's missing field stays missing" do
      board = board()

      pools = %{
        a: %{primary: [%{"t" => @t0, "v" => 1}, %{"t" => DateTime.add(@t0, 60)}]},
        b: %{primary: rows(3)},
        c: %{primary: rows(3)}
      }

      {:ok, snapshot} = Snapshot.realize(board, @store, pools, now: @t0)
      {:ok, json} = Snapshot.to_json(snapshot)
      assert {:ok, ^snapshot} = Snapshot.from_json(json)
      assert snapshot.cells.a.slots.primary.delivery.rows == pools.a.primary
    end

    test "a slot bound through its default keeps the source it was bound to" do
      design = put_in(@line, [:sources, :primary, :default], :uptime)
      board = Board.from_map!(%{cells: %{a: %{x: 0, y: 0, w: 6, h: 3, ref: {:composite, 1}}}})
      pools = %{a: %{uptime: rows(5)}}

      {:ok, snapshot} = Snapshot.realize(board, %{{:composite, 1} => design}, pools)
      assert snapshot.cells.a.slots.primary.delivery.rows == rows(5)
      assert Snapshot.views(snapshot).a.state == :live
    end

    test "a newer snapshot is refused by name before anything is read" do
      assert Snapshot.from_json(~s({"$version": 9, "board": 1})) ==
               {:error, [{["$version"], {:newer_schema, 9, 3}}]}

      assert Snapshot.from_map(%{version: 9, cells: :nonsense}) ==
               {:error, [{[:version], {:newer_schema, 9, 3}}]}
    end

    test "the limits hold before a key is read, and every fault is reported by path" do
      map = Snapshot.to_map(realized())

      assert {:error, errors} = Snapshot.from_map(map, limits: [items: 15])
      assert {[:cells, :a, :slots, :primary, :rows], {:limit, :items, 15, 20}} in errors

      broken =
        map
        |> Map.put(:extra, 1)
        |> put_in([:cells, :z], %{chart: @line})
        |> update_in([:cells], &Map.delete(&1, :b))
        |> put_in([:cells, :a, :slots, :primary, :status], :sideways)
        |> put_in([:cells, :c, :chart, :marks], [%{type: :nope}])

      assert {:error, errors} = Snapshot.from_map(broken)
      paths = Enum.map(errors, &elem(&1, 0))
      assert [:extra] in paths
      assert {[:cells, :z], :not_on_board} in errors
      assert {[:cells, :b], :required} in errors
      assert {[:cells, :a, :slots, :primary, :status], {:type, :status}} in errors
      assert Enum.any?(paths, &match?([:cells, :c, :chart, :marks | _], &1))

      assert Snapshot.format_error({[:cells, :z], :not_on_board}) ==
               "cells.z: is not a cell of the snapshot's board"
    end

    test "a realize that fails is the snapshot's failure, under each cell" do
      assert {:error, [{[:cells, :a, :sources, :primary], {:unbound, :source, :primary}} | _]} =
               Snapshot.realize(board(), @store, %{})
    end
  end

  describe "print (spec/15 §12.4)" do
    test "the print theme is paper and keeps every contract" do
      theme = Visualize.Theme.print()
      assert theme.background == "#ffffff" and theme.surface == "#ffffff"
      assert Visualize.Theme.check(theme) == :ok
      assert Visualize.Theme.builtin(:print) == theme
      assert theme.ramps.status == Visualize.Theme.color_safe().ramps.status
      assert Visualize.Theme.ink(theme, nil) == theme.text
    end

    test "every page's cells fit inside its margins, and no cell is split or lost" do
      # Two columns of cells four rows high; `c0` reaches two rows into the next pair, and
      # `c2` starts below it, so `c0`–`c3` share rows and are one band.
      cells =
        for i <- 0..13, into: %{} do
          {:"c#{i}", %{x: rem(i, 2) * 6, y: div(i, 2) * 4, w: 6, h: 4, ref: {:composite, 1}}}
        end
        |> Map.put(:c0, %{x: 0, y: 0, w: 6, h: 6, ref: {:composite, 1}})
        |> Map.put(:c2, %{x: 0, y: 6, w: 6, h: 2, ref: {:composite, 1}})

      board = Board.from_map!(%{cells: cells})

      for paper <- [:a4, :letter], orientation <- [:portrait, :landscape] do
        %{size: {pw, ph}, width: width, pages: pages} =
          Export.paginate(board, paper: paper, orientation: orientation)

        placed = Enum.flat_map(pages, &Map.keys/1)
        assert Enum.sort(placed) == Enum.sort(Map.keys(cells))

        for page <- pages, {_name, {x, y, w, h}} <- page do
          assert x >= 48 - 1.0e-9 and x + w <= pw - 48 + 1.0e-9
          assert y >= 48 and y + h <= ph - 48 + 1.0e-9
        end

        # Cells that share a row share a page; a page narrower than the breakpoint stacks.
        page_of =
          for {page, i} <- Enum.with_index(pages),
              name <- Map.keys(page),
              into: %{},
              do: {name, i}

        if width >= Board.layout(board).breakpoint do
          assert page_of.c0 == page_of.c1 and page_of.c1 == page_of.c2 and
                   page_of.c2 == page_of.c3
        else
          order = board |> Board.arrange(width) |> Enum.map(&elem(&1, 0))
          assert Enum.map(order, &page_of[&1]) == Enum.sort(Enum.map(order, &page_of[&1]))
        end
      end

      assert length(Export.paginate(board).pages) > 1
    end

    test "a band taller than a page is scaled to fit one, its proportions kept" do
      board =
        Board.from_map!(%{cells: %{tall: %{x: 0, y: 0, w: 12, h: 30, ref: {:composite, 1}}}})

      %{size: {pw, ph}, width: width, pages: [page]} = Export.paginate(board)
      {x, y, w, h} = page.tall
      assert y + h <= ph - 48 + 1.0e-9 and x >= 48 and x + w <= pw - 48
      {_, _, bw, bh} = Board.boxes(board, width).tall
      assert_in_delta w / h, bw / bh, 1.0e-9
    end

    test "pages are SVG documents of the paper's size drawing the snapshot in the print theme" do
      snapshot = realized()
      [page | _] = pages = Export.pages(snapshot, paper: :a4)
      assert page =~ ~s(width="210mm") and page =~ ~s(height="297mm")
      assert page =~ "page 1 of #{length(pages)}"
      assert page =~ ">Ops</text>"

      %{width: width} = Export.paginate(snapshot.board)
      views = Snapshot.views(snapshot, width: width, theme: Visualize.Theme.print())
      all = Enum.join(pages)
      for {_name, %View{svg: svg}} <- views, do: assert(all =~ svg)

      landscape = Export.pages(snapshot, paper: :letter, orientation: :landscape)
      assert hd(landscape) =~ ~s(width="11in") and hd(landscape) =~ ~s(height="8.5in")

      html = Export.html(snapshot)
      assert html =~ "@page { size: 210mm 297mm; margin: 0; }"
      assert length(String.split(html, ~s(<section class="vis-page">))) == length(pages) + 1
    end
  end

  # -- the runtime ----------------------------------------------------------------------------

  describe "the board's generators and assigns (spec/15 §12, #681, D-181)" do
    @viewer_line %{
      version: 3,
      sources: %{primary: %{fields: [:t, :v]}},
      frames: %{
        main: %{kind: :cartesian, scales: %{x: %{kind: :time}, y: %{kind: :linear}}}
      },
      marks: [
        %{
          type: :line,
          data: :primary,
          channels: %{x: :t, y: :v},
          style: {:generate, :viewer_stroke, []}
        }
      ]
    }

    @viewer_store %{{:composite, 1} => @viewer_line}
    @gens [generators: [Visualize.Board.ExportTest.Viewer]]

    defp viewer_snapshot do
      board = board()

      {:ok, snapshot} =
        Snapshot.realize(
          board,
          @viewer_store,
          pools(board),
          [now: DateTime.add(@t0, 3600), schemas: cache(board)] ++ @gens
        )

      snapshot
    end

    test "a generator registered only on the board draws in the export" do
      snapshot = viewer_snapshot()

      # Without the board's generators the cells cannot be drawn: the call is unknown.
      refute Snapshot.views(snapshot).a.state == :live
      assert Snapshot.views(snapshot, @gens).a.state == :live
      assert Export.svg(snapshot, @gens) =~ Snapshot.views(snapshot, @gens).a.svg
    end

    test "with the viewer's assigns the export is the viewer's drawing" do
      snapshot = viewer_snapshot()
      globex = Snapshot.views(snapshot, @gens ++ [assigns: %{viewer: "globex"}]).a.svg
      nobody = Snapshot.views(snapshot, @gens).a.svg

      assert globex != nobody
      assert globex =~ ~s(stroke-width="3")
      refute nobody =~ ~s(stroke-width="3")
      assert Export.svg(snapshot, @gens ++ [assigns: %{viewer: "globex"}]) =~ globex

      assert Enum.join(Export.pages(snapshot, @gens ++ [assigns: %{viewer: "globex"}])) =~
               ~s(stroke-width="3")
    end

    test "a running board exports with its own generators and assigns, an option over them" do
      {feed, agent} = Feeds.scripted(schema: @schema, rows: rows(20))
      Process.unlink(agent)
      on_exit(fn -> if Process.alive?(agent), do: Agent.stop(agent) end)

      {:ok, server} =
        start(
          [
            store: @viewer_store,
            feeds: %{f: feed},
            binding: binding([:a, :b, :c], :f),
            assigns: %{viewer: "globex"}
          ] ++ @gens
        )

      {:ok, _info} = Server.subscribe(server)
      live = view_until(:a, &(&1.state == :live))
      assert live.svg =~ ~s(stroke-width="3")

      # The live cell, byte for byte, in the board's own export.
      assert Server.export(server, :svg) =~ live.svg

      assert Server.export(server, :svg) ==
               Export.svg(Server.snapshot(server), [assigns: %{viewer: "globex"}] ++ @gens)

      # An option given wins over the board's: another viewer's export.
      other = Server.export(server, :svg, assigns: %{viewer: "initech"})
      refute other =~ live.svg
      assert Snapshot.views(Server.snapshot(server)).a.state != :live
    end
  end

  defp start(opts) do
    sup = start_supervised!(Supervisor.child_spec(Visualize.Board.Supervisor, id: make_ref()))

    defaults = [
      board: board(),
      store: @store,
      tick: nil,
      clock: fn -> DateTime.add(@t0, 3600) end
    ]

    Server.start(sup, Keyword.merge(defaults, opts))
  end

  defp binding(cells, feed), do: Binding.new(for c <- cells, into: %{}, do: {{c, :primary}, feed})

  defp view_until(cell, test) do
    receive do
      {:visualize_board, _board, {:cell, ^cell, %View{} = view}} ->
        if test.(view), do: view, else: view_until(cell, test)
    after
      @patience -> flunk("no view of #{inspect(cell)} within #{@patience} ms")
    end
  end

  defp fmt(n) when is_integer(n), do: Integer.to_string(n)

  defp fmt(n) do
    rounded = Float.round(n, 3)

    if rounded == trunc(rounded),
      do: Integer.to_string(trunc(rounded)),
      else: Float.to_string(rounded)
  end
end
