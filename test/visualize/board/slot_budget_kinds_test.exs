defmodule Visualize.Board.SlotBudgetKindsTest do
  @moduledoc """
  Every kind of slot binding held to one budget rule (spec/15 §8.2, #872, #873, D-226,
  D-227, D-230): a slot has a budget whatever it is bound to, is handed at most that many
  rows, and draws. Two cells of different widths read one name, so each slot's own budget
  shows in its count.

  The recurrence guard: #864 derived budgets for feed-bound slots only, and a slot bound
  to a virtual source went unbudgeted until its cell was over budget (#872). Every way a
  binding can resolve a slot has a row in `@kinds`; **a binding kind added without a row
  here is the omission this test exists to make visible.**
  """
  use ExUnit.Case, async: true

  @moduletag :capture_log

  alias Visualize.Board
  alias Visualize.Board.{Binding, Server, View}
  alias Visualize.Data.Schema
  alias Visualize.Test.Feeds

  @design %{
    version: 2,
    sources: %{primary: %{fields: [:t, :v]}},
    frames: %{
      main: %{
        kind: :cartesian,
        scales: %{x: %{kind: :linear}, y: %{kind: :linear}},
        axes: [%{scale: :x, side: :bottom}, %{scale: :y, side: :left}]
      }
    },
    marks: [%{type: :line, data: :primary, channels: %{x: :t, y: :v}}]
  }

  @fields %{t: %{type: :number, window: true}, v: %{type: :number}}
  @schema Schema.new!(@fields)
  @ceiling 1_500
  @width 1_200

  # A row-expanding source: three rows for each of its input's, so 1,500 rows in, each
  # asked the ceiling, are 4,500 out — three times the ceiling, legitimately.
  @expanding %{
    from: [{:raw, nil}],
    schema: @fields,
    elixir: """
    fn %{raw: rows} ->
      Enum.flat_map(rows, fn r ->
        [r, %{t: r.t + 0.25, v: r.v + 1}, %{t: r.t + 0.5, v: r.v - 1}]
      end)
    end
    """
  }

  defp rows(n), do: for(t <- 0..(n - 1), do: %{t: t, v: rem(t * 7, 11)})

  # Every-k-th row at the budget it is asked, `reduced_by: :feed`: a feed that honors it.
  defp honoring(all, window, budget) do
    if budget && length(all) > budget do
      step = ceil(length(all) / budget)
      {Enum.take_every(all, step), [reduced_by: :feed, window: window]}
    else
      {all, [window: window]}
    end
  end

  # Each binding kind: the rows its feed holds and whether it honors `:budget`, the
  # virtual sources the board defines, the name both cells' slots are bound to, and what
  # `reduced_by` the wide cell's delivery records. The narrow cell is always reduced by
  # visualize, to its own smaller budget. A new binding kind needs a row here.
  @kinds [
    plain_feed: %{
      rows: 2_000,
      honors: false,
      sources: %{},
      bound: :f,
      wide_by: :visualize
    },
    budget_feed: %{
      rows: 2_000,
      honors: true,
      sources: %{},
      bound: :f,
      wide_by: :feed
    },
    virtual_source: %{
      rows: 1_500,
      honors: false,
      sources: %{src: @expanding},
      bound: :src,
      wide_by: :visualize
    }
  ]

  defp start(kind) do
    sup = start_supervised!(Supervisor.child_spec(Visualize.Board.Supervisor, id: make_ref()))
    all = rows(kind.rows)

    feed_opts =
      if kind.honors,
        do: [supports: [:budget], rows: &honoring(all, &1, &2)],
        else: [rows: all]

    {feed, agent} = Feeds.scripted([schema: @schema] ++ feed_opts)
    Process.unlink(agent)
    on_exit(fn -> if Process.alive?(agent), do: Agent.stop(agent) end)

    board =
      Board.from_map!(%{
        cells: %{
          wide: %{x: 0, y: 0, w: 12, h: 3, ref: {:composite, 1}},
          narrow: %{x: 0, y: 3, w: 3, h: 3, ref: {:composite, 1}}
        },
        virtual_sources: kind.sources
      })

    feed_name = if kind.sources == %{}, do: :f, else: :raw

    {:ok, server} =
      Server.start(sup,
        board: board,
        store: %{{:composite, 1} => @design},
        feeds: %{feed_name => feed},
        binding:
          Binding.new(%{{:wide, :primary} => kind.bound, {:narrow, :primary} => kind.bound}),
        tick: nil,
        debounce: 0,
        width: @width,
        budget: @ceiling,
        clock: fn -> ~U[2026-10-21 12:00:00Z] end
      )

    {:ok, _info} = Server.subscribe(server)
    :ok = Server.tick(server)
    server
  end

  # The first drawn, live view of each of `cells`.
  defp live(cells, seen \\ %{}) do
    if Enum.all?(cells, &Map.has_key?(seen, &1)) do
      seen
    else
      receive do
        {:visualize_board, _board, {:cell, name, %View{state: :live, svg: "<svg" <> _} = view}} ->
          live(cells, Map.put_new(seen, name, view))
      end
    end
  end

  defp held(server, cell),
    do: :sys.get_state(Server.info(server).cells[cell].pid).slots["primary"]

  for {name, kind} <- @kinds do
    @kind kind
    test "#{name}: every slot has its own budget, is handed at most that, and draws" do
      kind = @kind
      server = start(kind)

      views = live(["wide", "narrow"])

      state = :sys.get_state(server)

      # Every bound slot has a budget, whatever its binding resolved to.
      for key <- Map.keys(state.slot_refs),
          do: assert(is_integer(Map.get(state.budgets, key)), "no budget for #{inspect(key)}")

      wide = Map.fetch!(state.budgets, {"wide", "primary"})
      narrow = Map.fetch!(state.budgets, {"narrow", "primary"})
      assert narrow < wide and wide <= @ceiling

      %{delivery: w} = held(server, "wide")
      %{delivery: n} = held(server, "narrow")

      assert length(w.rows) <= wide and length(n.rows) <= narrow
      assert length(n.rows) < length(w.rows)

      # Drawn, each from the rows it was handed.
      assert views["wide"].svg =~ "of #{length(w.rows)} points"
      assert views["narrow"].svg =~ "of #{length(n.rows)} points"
      assert w.reduced_by == kind.wide_by
      assert n.reduced_by == :visualize

      for cell <- ["wide", "narrow"], do: assert(Server.info(server).cells[cell].state == :live)
    end
  end
end
