defmodule Visualize.Board.BudgetTest do
  @moduledoc """
  Each slot's budget derived from its plot width and its marks' types, a design's
  `budget` overriding it and the board's `budget:` capping both, and one fetch per feed at
  the largest budget with each slot reduced to its own (spec/15 §8.2, #864, D-226).
  """
  use ExUnit.Case, async: true

  alias Visualize.Board
  alias Visualize.Board.{Binding, Budget, Server}
  alias Visualize.Chart
  alias Visualize.Data.Schema
  alias Visualize.Test.Feeds

  doctest Budget

  @t0 ~U[2026-10-11 12:00:00Z]
  @schema Schema.new!(%{t: %{type: :time}, v: %{type: :number}})

  defp design(marks, extra \\ %{}) do
    Map.merge(
      %{
        version: 3,
        sources: %{primary: %{fields: [:t, :v]}},
        frames: %{
          main: %{
            kind: :cartesian,
            margin: %{left: 40, right: 20, top: 10, bottom: 20},
            scales: %{x: %{kind: :time}, y: %{kind: :linear}}
          }
        },
        marks: marks
      },
      extra
    )
  end

  @line %{type: :line, data: :primary, channels: %{x: :t, y: :v}}
  @bar %{type: :rect, data: :primary, channels: %{x0: :t, x1: :t, y0: 0, y1: :v}}
  @point %{type: :circle, data: :primary, channels: %{x: :t, y: :v}}

  defp chart(marks, extra \\ %{}), do: Chart.from_map!(design(marks, extra))

  describe "the derivation (spec/15 §8.2)" do
    test "a line or an area is four rows per pixel of plot width, a bar one per two, a point one" do
      # A 560 px cell less 40 + 20 of margin is a 500 px plot.
      assert Budget.slot(chart([@line]), %{}, "primary", {560, 300}, nil) == 2000
      assert Budget.slot(chart([%{@line | type: :area}]), %{}, "primary", {560, 300}, nil) == 2000
      assert Budget.slot(chart([@bar]), %{}, "primary", {560, 300}, nil) == 250
      assert Budget.slot(chart([@point]), %{}, "primary", {560, 300}, nil) == 500
      # A fractional plot is whole pixels, rounded up.
      assert Budget.slot(chart([@bar]), %{}, "primary", {561.5, 300}, nil) == 251
    end

    test "a slot's budget is the largest of its marks' needs, not their sum" do
      assert Budget.slot(chart([@bar, @point, @line]), %{}, "primary", {560, 300}, nil) == 2000
      assert Budget.slot(chart([@bar, @point]), %{}, "primary", {560, 300}, nil) == 500
    end

    test "a mark's frame is its own: a frame's box and margin narrow its plot" do
      frames = %{
        left: %{kind: :cartesian, box: [0, 0, 0.5, 1], margin: %{left: 0, right: 0}},
        right: %{kind: :cartesian, box: [0.5, 0, 0.5, 1], margin: %{left: 50, right: 50}}
      }

      bars = chart([Map.put(@bar, :frame, :right)], %{frames: frames})
      # The right half of a 600 px cell is 300 px, less 100 of margin.
      assert Budget.slot(bars, %{}, "primary", {600, 300}, nil) == 100
    end

    test "a margin a variable gives is read at the cell's variables, else its default" do
      extra = %{vars: %{m: %{default: %{left: 0, right: 0}}}}
      chart = chart([@point], extra)
      chart = put_in(chart.frames["main"].margin, Chart.var(:m))
      assert Budget.slot(chart, %{}, "primary", {560, 300}, nil) == 560

      assert Budget.slot(chart, %{"m" => %{left: 100, right: 60}}, "primary", {560, 300}, nil) ==
               400
    end

    test "a design's budget overrides the derivation, and the ceiling caps both" do
      assert Budget.slot(chart([@line], %{budget: 300}), %{}, "primary", {560, 300}, nil) == 300

      per_px = chart([@line], %{budget: {:per_px, 0.5}})
      assert Budget.slot(per_px, %{}, "primary", {560, 300}, nil) == 250

      assert Budget.slot(chart([@line]), %{}, "primary", {560, 300}, 1200) == 1200
      assert Budget.slot(chart([@line], %{budget: 300}), %{}, "primary", {560, 300}, 100) == 100
      assert Budget.slot(per_px, %{}, "primary", {560, 300}, 100) == 100
      # Under a ceiling above it, the derivation stands.
      assert Budget.slot(chart([@bar]), %{}, "primary", {560, 300}, 5000) == 250
    end

    test "a slot no mark reads is asked the ceiling" do
      assert Budget.slot(chart([]), %{}, "primary", {560, 300}, nil) == nil
      assert Budget.slot(chart([]), %{}, "primary", {560, 300}, 700) == 700
      assert Budget.slot(chart([], %{budget: 90}), %{}, "primary", {560, 300}, 700) == 90
    end

    test "a feed is asked the largest of its slots', the ceiling when unbound or read by a source" do
      refs = %{{"a", "p"} => {:feed, :f}, {"b", "p"} => {:feed, :f}, {"c", "p"} => {:feed, :g}}
      budgets = %{{"a", "p"} => 100, {"b", "p"} => 400, {"c", "p"} => 50}

      assert Budget.feeds([:f, :g, :h], budgets, refs, [], 1000) == %{f: 400, g: 50, h: 1000}
      assert Budget.feeds([:f, :g], budgets, refs, [:g], 1000) == %{f: 400, g: 1000}
      assert Budget.feeds([:f], %{budgets | {"a", "p"} => nil}, refs, [], 1000) == %{f: nil}
    end

    test "every bound slot has a budget, a virtual source's as a feed's; an unbound one none (D-230)" do
      components = Map.new(~w(a b c), &{&1, %{chart: chart([@line]), vars: %{}}})
      needs = %{"a" => ["primary"], "b" => ["primary"], "c" => ["primary"]}
      refs = %{{"a", "primary"} => {:feed, :f}, {"b", "primary"} => {:source, ["s"]}}
      boxes = %{"a" => {0, 0, 560, 300}, "b" => {0, 0, 260, 300}, "c" => {0, 0, 560, 300}}

      assert Budget.slots(components, needs, refs, boxes, nil) ==
               %{{"a", "primary"} => 2000, {"b", "primary"} => 800}

      assert Budget.slots(components, needs, refs, boxes, 1000) ==
               %{{"a", "primary"} => 1000, {"b", "primary"} => 800}
    end

    test "a feed's budget counts only the feed-bound slots; a source's slots are in none (D-230)" do
      refs = %{
        {"a", "p"} => {:feed, :f},
        {"b", "p"} => {:source, ["s"]},
        {"c", "p"} => {:source, ["c", "s"]}
      }

      budgets = %{{"a", "p"} => 100, {"b", "p"} => 900, {"c", "p"} => nil}

      # `:g` is read by the source: it is asked the ceiling, whatever the source's slots ask.
      assert Budget.feeds([:f, :g], budgets, refs, [:g], 1000) == %{f: 100, g: 1000}
      assert Budget.feeds([:f, :g], budgets, refs, [:g], nil) == %{f: 100, g: nil}
    end
  end

  describe "the design key (spec/14 §2.10)" do
    test "a budget is a positive integer or {:per_px, k}; anything else is a fault at its path" do
      assert {:ok, %{budget: 40}} = Chart.from_map(design([@line], %{budget: 40}))

      assert {:ok, %{budget: {:per_px, 2}}} =
               Chart.from_map(design([@line], %{budget: {:per_px, 2}}))

      for bad <- [0, -3, 1.5, :wide, {:per_px, 0}, {:per_px, "2"}, {:per_pixel, 2}] do
        assert {:error, [{[:budget], {:type, :budget}}]} =
                 Chart.from_map(design([@line], %{budget: bad})),
               "#{inspect(bad)} was accepted"
      end
    end

    test "the builder's field reads a budget as typed, and nothing else" do
      parse = &Visualize.Chart.Builder.Editor.parse(:budget, &1)
      assert parse.("300") == {:ok, 300}
      assert parse.("{:per_px, 0.5}") == {:ok, {:per_px, 0.5}}
      assert parse.("wide") == :error
      assert parse.("{:per_px, x}") == :error
    end

    test "the JSON round trip: an integer as itself, per pixel tagged, none absent" do
      for budget <- [40, {:per_px, 0.5}] do
        chart = chart([@line], %{budget: budget})
        {:ok, json} = Chart.to_json(chart)
        assert {:ok, %{budget: ^budget}} = Chart.from_json(json)
      end

      {:ok, json} = Chart.to_json(chart([@line], %{budget: {:per_px, 0.5}}))
      assert json =~ ~s("budget":{"$per_px":0.5})

      {:ok, json} = Chart.to_json(chart([@line]))
      refute json =~ "budget"

      {:ok, json} = Chart.to_json(chart([@line], %{budget: {:per_px, 0.5}}))
      bad = String.replace(json, "0.5", ~s("half"))
      assert {:error, [{[:budget], {:type, :budget}}]} = Chart.from_json(bad)
    end
  end

  # -- the board ------------------------------------------------------------------------

  defp rows(n), do: for(i <- 0..(n - 1), do: %{t: DateTime.add(@t0, i), v: rem(i * 7, 11)})

  # A feed that tells the test the budget of each fetch.
  defp scripted(opts) do
    test = self()
    rows = Keyword.fetch!(opts, :rows)

    answer = fn _window, budget ->
      send(test, {:fetched, Keyword.fetch!(opts, :name), budget})

      if :budget in Keyword.get(opts, :supports, []) and budget,
        do: {Enum.take(rows, budget), [reduced_by: :feed]},
        else: {rows, []}
    end

    {feed, agent} = Feeds.scripted(Keyword.merge(opts, rows: answer, schema: @schema))
    Process.unlink(agent)
    on_exit(fn -> if Process.alive?(agent), do: Agent.stop(agent) end)
    {feed, agent}
  end

  defp start(opts) do
    sup = start_supervised!(Supervisor.child_spec(Visualize.Board.Supervisor, id: make_ref()))
    defaults = [tick: nil, clock: fn -> DateTime.add(@t0, 3600) end]
    Server.start(sup, Keyword.merge(defaults, opts))
  end

  defp two_cells(store_marks) do
    board =
      Board.from_map!(%{
        cells: %{
          wide: %{x: 0, y: 0, w: 8, h: 3, ref: {:composite, 1}},
          narrow: %{x: 8, y: 0, w: 4, h: 3, ref: {:composite, 1}}
        }
      })

    {board, %{{:composite, 1} => design(store_marks)}}
  end

  # A cell's plot width on the board at `width`: its box less the design's 60 px of margin.
  defp plot(board, cell, width) do
    {_x, _y, w, _h} = Board.boxes(board, width)[cell]
    ceil(w - 60)
  end

  defp slot(board, cell), do: Server.snapshot(board).cells[cell].slots["primary"].delivery

  describe "one fetch per feed, each slot reduced to its own (spec/15 §8.2)" do
    test "two cells of different widths on one feed: one fetch at the larger, each slot its own" do
      {board, store} = two_cells([@line])
      {feed, agent} = scripted(name: :f, rows: rows(10_000))
      binding = Binding.new(%{{:wide, :primary} => :f, {:narrow, :primary} => :f})
      {:ok, server} = start(board: board, store: store, feeds: %{f: feed}, binding: binding)
      :ok = Server.tick(server)

      wide = 4 * plot(board, "wide", 1200)
      narrow = 4 * plot(board, "narrow", 1200)
      assert wide > narrow

      # Two turns, a pull feed polled once in each, and each fetch at the wide cell's budget.
      assert Feeds.calls(agent, :fetch) == 2
      assert_received {:fetched, :f, ^wide}
      assert_received {:fetched, :f, ^wide}
      refute_received {:fetched, :f, _other}

      %{rows: wide_rows, reduced_by: :visualize} = slot(server, "wide")
      %{rows: narrow_rows, reduced_by: :visualize} = slot(server, "narrow")
      assert length(wide_rows) <= wide and length(wide_rows) > narrow
      assert length(narrow_rows) <= narrow
    end

    test "a budget-honoring feed is not reduced again at the budget it was asked, only below it" do
      {board, store} = two_cells([@bar])
      {feed, _agent} = scripted(name: :f, supports: [:budget], rows: rows(10_000))
      binding = Binding.new(%{{:wide, :primary} => :f, {:narrow, :primary} => :f})
      {:ok, server} = start(board: board, store: store, feeds: %{f: feed}, binding: binding)
      :ok = Server.tick(server)

      wide = ceil(plot(board, "wide", 1200) / 2)
      narrow = ceil(plot(board, "narrow", 1200) / 2)
      assert_received {:fetched, :f, ^wide}

      assert %{reduced_by: :feed, rows: rows} = slot(server, "wide")
      assert length(rows) == wide
      assert %{reduced_by: :visualize, rows: rows} = slot(server, "narrow")
      assert length(rows) <= narrow
    end

    test "the ceiling caps the asked budget, and a nil ceiling leaves the derived one" do
      {board, store} = two_cells([@line])
      {feed, _agent} = scripted(name: :f, rows: rows(10_000))
      binding = Binding.new(%{{:wide, :primary} => :f, {:narrow, :primary} => :f})

      {:ok, server} =
        start(board: board, store: store, feeds: %{f: feed}, binding: binding, budget: 500)

      :ok = Server.tick(server)
      assert_received {:fetched, :f, 500}
      # Both slots are at the ceiling, so neither is reduced below the feed's delivery.
      assert length(slot(server, "wide").rows) == 500
      assert length(slot(server, "narrow").rows) == 500
    end

    test "a resize refetches a :budget feed whose largest budget changed, and refinishes any other" do
      board =
        Board.from_map!(%{
          cells: %{
            honors: %{x: 0, y: 0, w: 6, h: 3, ref: {:composite, 1}},
            plain: %{x: 6, y: 0, w: 6, h: 3, ref: {:composite, 1}}
          }
        })

      store = %{{:composite, 1} => design([@point])}

      # Push feeds are fetched only when asked again, never polled.
      {honors, honors_agent} =
        scripted(name: :h, supports: [:budget, :push], rows: rows(10_000))

      {plain, plain_agent} = scripted(name: :p, supports: [:push], rows: rows(10_000))
      binding = Binding.new(%{{:honors, :primary} => :h, {:plain, :primary} => :p})

      {:ok, server} =
        start(board: board, store: store, feeds: %{h: honors, p: plain}, binding: binding)

      :ok = Server.tick(server)
      before = plot(board, "plain", 1200)
      assert length(slot(server, "plain").rows) == before
      assert {Feeds.calls(honors_agent, :fetch), Feeds.calls(plain_agent, :fetch)} == {1, 1}

      # Below the breakpoint each cell spans the board: a wider plot, a larger budget.
      :ok = Server.resize(server, 700)
      :ok = Server.tick(server)
      after_resize = plot(board, "plain", 700)
      assert after_resize != before

      assert_received {:fetched, :h, ^after_resize}
      assert {Feeds.calls(honors_agent, :fetch), Feeds.calls(plain_agent, :fetch)} == {2, 1}
      assert length(slot(server, "honors").rows) == after_resize
      assert length(slot(server, "plain").rows) == after_resize
    end
  end
end
