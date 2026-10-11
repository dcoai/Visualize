defmodule Visualize.Board.RuntimeTest do
  @moduledoc """
  The board runtime (spec/15 §8, #574, D-146): one process per board owning the shared
  state and the feeds, one heap-limited process per cell that the board restarts, every
  cell state drawn, and rows placed by their timestamp.
  """
  use ExUnit.Case, async: true

  # A killed or raising cell is reported by the VM and the supervisor; kept out of the run.
  @moduletag :capture_log

  alias Visualize.Board
  alias Visualize.Board.{Binding, Server, View}
  alias Visualize.Data.Schema
  alias Visualize.Test.Feeds

  @line %{
    version: 2,
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

  @schema Schema.new!(%{t: %{type: :time}, v: %{type: :number}})
  @t0 ~U[2026-10-11 12:00:00Z]

  defp rows(n, shift \\ 0),
    do: for(i <- 0..(n - 1), do: %{t: DateTime.add(@t0, i * 60), v: rem((i + shift) * 7, 11)})

  defp board(extra \\ %{}) do
    Board.from_map!(
      Map.merge(
        %{
          cells: %{
            a: %{x: 0, y: 0, w: 6, h: 3, ref: {:composite, 1}, title: "A"},
            b: %{x: 6, y: 0, w: 6, h: 3, ref: {:composite, 1}, title: "B"}
          }
        },
        extra
      )
    )
  end

  # A board under a supervisor of the test's, turned only by `tick/1`, its now fixed.
  defp start(opts) do
    sup = start_supervised!(Supervisor.child_spec(Visualize.Board.Supervisor, id: make_ref()))

    defaults = [
      board: board(),
      store: %{{:composite, 1} => @line},
      tick: nil,
      clock: fn -> DateTime.add(@t0, 3600) end
    ]

    Server.start(sup, Keyword.merge(defaults, opts))
  end

  defp two_feeds(rows \\ rows(20)) do
    {fa, a} = scripted(schema: @schema, rows: rows)
    {fb, b} = scripted(schema: @schema, rows: rows)
    binding = Binding.new(%{{:a, :primary} => :fa, {:b, :primary} => :fb})
    {%{fa: fa, fb: fb}, binding, a, b}
  end

  # A scripted feed whose agent outlives the test process until the board has stopped, so
  # the board's last unsubscribe reaches it.
  defp scripted(opts) do
    {feed, agent} = Feeds.scripted(opts)
    Process.unlink(agent)
    on_exit(fn -> if Process.alive?(agent), do: Agent.stop(agent) end)
    {feed, agent}
  end

  # The next view of a cell this process receives, within the timeout.
  defp view(cell, timeout \\ 10_000) do
    receive do
      {:visualize_board, _board, {:cell, ^cell, %View{} = view}} -> view
    after
      timeout -> flunk("no view of #{inspect(cell)} within #{timeout} ms")
    end
  end

  # Views of a cell until one satisfies the test.
  defp view_until(cell, test, timeout \\ 10_000) do
    view = view(cell, timeout)
    if test.(view), do: view, else: view_until(cell, test, timeout)
  end

  defp flush_views do
    receive do
      {:visualize_board, _board, _message} -> flush_views()
    after
      50 -> :ok
    end
  end

  describe "starting (spec/15 §8.1–§8.2)" do
    test "every cell draws its chart and sends its view straight to the subscriber" do
      {feeds, binding, _a, _b} = two_feeds()
      {:ok, board} = start(feeds: feeds, binding: binding)
      {:ok, info} = Server.subscribe(board)

      assert info.zone == "Etc/UTC" and info.width == 1200
      assert info.cells |> Map.keys() |> Enum.sort() == [:a, :b]

      a = view_until(:a, &(&1.state == :live))
      assert a.title == "A" and a.note == nil and a.frames >= 1
      assert a.svg =~ ~s(<title id=) and a.svg =~ "A</title>"
      assert a.svg =~ ~s(class="mark mark-line")
      assert a.size == {596.0, 256}
      assert a.crosshair["data-xs"] =~ "[0,"
      assert a.keyboard["data-keyboard-points"] =~ "\"points\""
    end

    test "a board that does not validate, or whose binding names an absent feed, is not started" do
      assert {:error, {:board, [{[:cells, :a, :ref], {:dangling, {:composite, 1}}} | _]}} =
               start(store: %{})

      {feeds, binding, _a, _b} = two_feeds()
      assert start(feeds: Map.delete(feeds, :fb), binding: binding) == {:error, {:feeds, [:fb]}}
    end

    test "the board's group and zone are written into each component (spec/15 §1.5, §6)" do
      {:ok, components} =
        Board.components(board(%{sync: "ops", zone: "Europe/Oslo"}), %{{:composite, 1} => @line})

      %{chart: chart, vars: vars} = components.a
      assert chart.interaction.sync == "ops"
      assert chart.frames.main.scales.x.zone == "Europe/Oslo"
      refute Map.has_key?(chart.frames.main.scales.y, :zone)
      assert vars == %{}
    end

    test "a cell's frame carries its group's sync attributes" do
      {feeds, binding, _a, _b} = two_feeds()
      {:ok, board} = start(board: board(%{sync: "ops"}), feeds: feeds, binding: binding)
      Server.subscribe(board)

      a = view_until(:a, &(&1.state == :live))
      assert a.svg =~ ~s(data-vis-sync="ops")
      assert a.crosshair["data-vis-sync"] == "ops"
    end
  end

  describe "fairness and runaway protection (spec/15 §8.3)" do
    test "a slow cell does not delay the others' frames, and skips to the present when it resumes" do
      {feeds, binding, fa, fb} = two_feeds()
      {:ok, board} = start(feeds: feeds, binding: binding)
      Server.subscribe(board)
      view_until(:a, &(&1.frames == 1))
      first_b = view_until(:b, &(&1.frames == 1))

      # Cell a stops answering, as a cell stuck in a long render does.
      slow = Server.info(board).cells.a.pid
      :sys.suspend(slow)

      for shift <- 1..5 do
        Feeds.set(fa, rows: rows(20, shift))
        Feeds.set(fb, rows: rows(20, shift))
        :ok = Server.tick(board)
        b = view(:b)
        assert b.frames == first_b.frames + shift
      end

      refute_received {:visualize_board, _, {:cell, :a, _view}}

      # Five data messages waited behind the stall; the cell draws only the newest.
      :sys.resume(slow)
      a = view(:a)
      assert a.frames == 2
      refute_receive {:visualize_board, _, {:cell, :a, _view}}, 200
    end

    test "a heap-blowing cell is killed alone, shown crashed, and restarted; the others go on" do
      {small, _} = scripted(schema: @schema, rows: rows(20))
      {big, _} = scripted(schema: @schema, rows: rows(200_000))
      binding = Binding.new(%{{:a, :primary} => :big, {:b, :primary} => :small})

      {:ok, board} =
        start(feeds: %{big: big, small: small}, binding: binding, max_heap: 2_000_000)

      Server.subscribe(board)

      crashed = view_until(:a, &match?({:crashed, _}, &1.state))
      assert crashed.state == {:crashed, :killed}
      assert crashed.svg == nil
      assert crashed.note =~ ~s(data-vis-state="crashed")
      assert crashed.note =~ "Crashed, restarting"

      b = view_until(:b, &(&1.state == :live))
      :ok = Server.tick(board)
      assert Process.alive?(board)
      info = Server.info(board)
      assert info.cells.b.state == :live and is_pid(info.cells.b.pid)

      # Restarted after its backoff, and killed again on the same data.
      again = view_until(:a, &match?({:crashed, _}, &1.state))
      assert again.state == {:crashed, :killed}
      assert Server.info(board).cells.a.restarts >= 2
      assert b.frames >= 1
    end

    test "a cell that raises shows crashed and does not take the board with it" do
      # A string where the time scale needs an instant: the cell's render raises.
      {bad, _} = scripted(schema: @schema, rows: [%{t: "noon", v: 1}, %{t: "one", v: 2}])
      {good, _} = scripted(schema: @schema, rows: rows(20))
      binding = Binding.new(%{{:a, :primary} => :bad, {:b, :primary} => :good})

      {:ok, board} = start(feeds: %{bad: bad, good: good}, binding: binding)
      Server.subscribe(board)
      assert match?({:crashed, _}, view_until(:a, &match?({:crashed, _}, &1.state)).state)
      assert view_until(:b, &(&1.state == :live)).frames >= 1
    end
  end

  describe "cell states in a live board (spec/15 §8.4)" do
    test "unbound, down, empty, stale and capped cells each show their state" do
      {down, _} = scripted(schema: @schema, error: :timeout)
      {empty, _} = scripted(schema: @schema, rows: [])

      {capped, _} =
        scripted(schema: @schema, rows: fn _w, _b -> {rows(5), [capped: true]} end)

      {old, _} = scripted(schema: @schema, rows: rows(5))

      cells =
        for {name, x} <- [unbound: 0, down: 2, empty: 4, capped: 6, old: 8], into: %{} do
          {name, %{x: x, y: 0, w: 2, h: 2, ref: {:composite, 1}}}
        end

      binding =
        Binding.new(%{
          {:down, :primary} => :down,
          {:empty, :primary} => :empty,
          {:capped, :primary} => :capped,
          {:old, :primary} => :old
        })

      {:ok, board} =
        start(
          board: board(%{cells: cells, stale_after: 600}),
          binding: binding,
          feeds: %{down: down, empty: empty, capped: capped, old: old},
          clock: fn -> DateTime.add(@t0, 240 + 60) end
        )

      Server.subscribe(board)

      assert view_until(:unbound, &(&1.state != :loading)).state == {:down, {:unbound, :primary}}
      assert view_until(:down, &(&1.state != :loading)).state == {:down, :timeout}
      assert view_until(:empty, &(&1.state != :loading)).state == :no_data

      capped_view = view_until(:capped, &(&1.state != :loading))
      assert capped_view.state == :capped
      assert capped_view.svg != nil and capped_view.note =~ "vis-cell-banner"

      live = view_until(:old, &(&1.state != :loading))
      assert live.state == :live

      # The board's now moves on; nothing new arrives, and the cell grows stale.
      flush_views()
      Server.stop(board)

      {:ok, board} =
        start(
          board: board(%{cells: Map.take(cells, [:old]), stale_after: 600}),
          binding: Binding.new(%{{:old, :primary} => :old}),
          feeds: %{old: old},
          clock: fn -> DateTime.add(@t0, 240 + 900) end
        )

      Server.subscribe(board)
      stale = view_until(:old, &(&1.state != :loading))
      assert stale.state == {:stale, 900.0}
      assert stale.svg != nil and stale.note =~ "Stale: 15m old"
    end
  end

  describe "the window, the variables and the size (spec/15 §8.2)" do
    test "a window change re-asks every feed, pull and push alike" do
      {pull, pull_agent} = scripted(schema: @schema, rows: rows(20))

      {push, push_agent} =
        scripted(schema: @schema, supports: [:window, :push], rows: rows(20))

      binding = Binding.new(%{{:a, :primary} => :pull, {:b, :primary} => :push})
      {:ok, board} = start(feeds: %{pull: pull, push: push}, binding: binding)
      :ok = Server.tick(board)
      before = {Feeds.calls(pull_agent, :fetch), Feeds.calls(push_agent, :fetch)}

      window = %{from: DateTime.add(@t0, 300), to: DateTime.add(@t0, 900)}
      assert Server.window(board, window) == :ok

      assert {Feeds.calls(pull_agent, :fetch), Feeds.calls(push_agent, :fetch)} ==
               {elem(before, 0) + 1, elem(before, 1) + 1}

      assert Server.info(board).window == {window.from, window.to}

      assert {:error, [{[:window], {:window, :inverted}}]} =
               Server.window(board, %{from: window.to, to: window.from})
    end

    test "a subscriber is told the board's window and zone, resolved at the board's now" do
      {feeds, binding, _a, _b} = two_feeds()

      {:ok, board} =
        start(board: board(%{window: %{last: 600}}), feeds: feeds, binding: binding)

      {:ok, info} = Server.subscribe(board)
      now = DateTime.add(@t0, 3600)
      assert info.window == {DateTime.add(now, -600), now}
      assert info.now == now
    end

    test "a resize recompiles each cell at its new box" do
      {feeds, binding, _a, _b} = two_feeds()
      {:ok, board} = start(feeds: feeds, binding: binding)
      Server.subscribe(board)
      view_until(:a, &(&1.state == :live))

      :ok = Server.resize(board, 600)
      # Below the breakpoint the cells stack, each across the whole width.
      a = view_until(:a, &(&1.size != {596.0, 256}))
      assert a.size == {600.0, 256}
      assert a.svg =~ ~s(viewBox="0 0 600.0 256")
      assert_receive {:visualize_board, ^board, {:board, %{width: 600}}}
    end

    test "new board variables prepare every cell again" do
      design =
        Map.merge(@line, %{
          vars: %{name: %{default: "first"}},
          meta: %{name: "\#{var(:name)}"}
        })

      {feeds, binding, _a, _b} = two_feeds()

      {:ok, board} =
        start(
          store: %{{:composite, 1} => design},
          feeds: feeds,
          binding: binding,
          board: board(%{cells: %{a: %{x: 0, y: 0, w: 6, h: 3, ref: {:composite, 1}}}})
        )

      Server.subscribe(board)
      assert view_until(:a, &(&1.state == :live)).svg =~ "first</title>"
      assert Server.vars(board, %{name: "second"}) == :ok
      assert view_until(:a, &(&1.svg =~ "second")).svg =~ "second</title>"
    end
  end

  describe "rows by timestamp (spec/15 §8.5)" do
    test "out-of-order rows land in order, and a gap beyond continuity breaks the line" do
      schema =
        Schema.new!(%{t: %{type: :time}, v: %{type: :number, continuity: 120}})

      # Shuffled, with ten minutes missing in the middle.
      sent = Enum.shuffle(Enum.reject(rows(20), &(DateTime.diff(&1.t, @t0) in 360..900)))
      {feed, _} = scripted(schema: schema, rows: sent)

      {:ok, board} =
        start(
          board: board(%{cells: %{a: %{x: 0, y: 0, w: 12, h: 3, ref: {:composite, 1}}}}),
          feeds: %{f: feed},
          binding: Binding.new(%{{:a, :primary} => :f})
        )

      Server.subscribe(board)
      a = view_until(:a, &(&1.state == :live))
      [_, d] = Regex.run(~r/class="mark mark-line"[^>]*><path d="([^"]+)"/, a.svg)

      # Two runs, each drawn left to right: the break starts the second with a move.
      runs = String.split(d, "M", trim: true)
      assert length(runs) == 2

      for run <- runs do
        xs =
          run
          |> String.split("L")
          |> Enum.map(fn point ->
            point |> String.split(",") |> hd() |> Float.parse() |> elem(0)
          end)

        assert xs == Enum.sort(xs)
      end
    end
  end
end
