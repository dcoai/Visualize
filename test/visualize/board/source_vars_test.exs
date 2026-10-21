defmodule Visualize.Board.SourceVarsTest do
  # A virtual source's variables on the board process (#871, D-228, D-229): the engine is
  # shown every scope's own variables when the board starts and on every `vars/2` and
  # `vars/3`, so a change re-runs the context-taking sources whose cascade it changed, and
  # only those, and their cells redraw. Turned only by `tick/1`.
  use ExUnit.Case, async: true

  @moduletag :capture_log

  alias Visualize.Board
  alias Visualize.Board.{Binding, Server, View}
  alias Visualize.Data.Schema
  alias Visualize.Test.Feeds

  defmodule Host do
    @moduledoc false
    use Visualize.VirtualSources

    # Two arguments: its scope's `k` scales the readings.
    defsource scaled(inputs, context) do
      k = context["vars"]["k"]
      Enum.map(inputs["raw"], &%{t: &1.t, v: &1.v * k})
    end

    # One argument: no variable reaches it.
    defsource(plain(inputs), do: Enum.map(inputs["raw"], &%{t: &1.t, v: &1.v}))
  end

  # A line whose component declares `k`, so a cell may give its own.
  @line %{
    version: 2,
    vars: %{k: %{default: 1}},
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
  @out %{t: %{type: :time}, v: %{type: :number}}
  @scaled %{from: [{:raw, nil}], schema: @out, function: :scaled}

  defp rows, do: for(i <- 0..4, do: %{t: DateTime.add(@t0, i * 60), v: 1})

  defp cell(x, extra),
    do: Map.merge(%{x: x, y: 0, w: 4, h: 3, ref: {:composite, 1}}, extra)

  # The board's `k` is 2; `a` gives its own 3, `b` none, `c` its own 4. Every scope has a
  # context-taking `scaled`, and the board a one-argument `plain`.
  defp board(extra \\ %{}) do
    Board.from_map!(%{
      vars: %{k: 2},
      cells: %{
        a: cell(0, %{vars: %{k: 3}, virtual_sources: Map.merge(%{scaled: @scaled}, extra)}),
        b: cell(4, %{virtual_sources: %{scaled: @scaled}}),
        c: cell(8, %{vars: %{k: 4}, virtual_sources: %{scaled: @scaled}})
      },
      virtual_sources: %{
        scaled: @scaled,
        plain: %{from: [{:raw, nil}], schema: @out, function: :plain}
      }
    })
  end

  defp start(opts \\ []) do
    sup = start_supervised!(Supervisor.child_spec(Visualize.Board.Supervisor, id: make_ref()))
    {feed, agent} = Feeds.scripted(schema: @schema, rows: rows())
    Process.unlink(agent)
    on_exit(fn -> if Process.alive?(agent), do: Agent.stop(agent) end)

    defaults = [
      board: board(),
      store: %{{:composite, 1} => @line},
      binding:
        Binding.new(%{
          {:a, :primary} => :scaled,
          {:b, :primary} => :scaled,
          {:c, :primary} => :scaled
        }),
      feeds: %{raw: feed},
      virtual_sources: [Host],
      tick: nil,
      debounce: 0,
      clock: fn -> DateTime.add(@t0, 3600) end
    ]

    {:ok, board} = Server.start(sup, Keyword.merge(defaults, opts))
    {:ok, _info} = Server.subscribe(board)
    :ok = Server.tick(board)
    board
  end

  defp runs(board) do
    Map.new(Server.info(board).virtual_sources, fn {path, %{runs: n}} -> {path, n} end)
  end

  # What a cell was last handed: its slot's values.
  defp values(board, cell) do
    %{delivery: delivery} = Server.snapshot(board).cells[cell].slots["primary"]
    Enum.map(delivery.rows, & &1["v"])
  end

  defp view_until(cell, test) do
    receive do
      {:visualize_board, _board, {:cell, ^cell, %View{} = view}} ->
        if test.(view), do: view, else: view_until(cell, test)
    end
  end

  test "a source's first run sees its scope's cascade: the board's, a cell's own over it" do
    board = start()

    assert values(board, "a") == List.duplicate(3, 5)
    assert values(board, "b") == List.duplicate(2, 5)
    assert values(board, "c") == List.duplicate(4, 5)
    assert view_until("a", &(&1.state == :live)).svg =~ ~s(class="mark mark-line")
  end

  test "a cell's variable re-runs only that cell's context-taking source, and the cell redraws" do
    board = start()
    before = runs(board)
    first = view_until("a", &(&1.state == :live and is_binary(&1.svg)))

    assert Server.vars(board, :a, %{k: 10}) == :ok

    after_change = runs(board)
    assert after_change[["a", "scaled"]] == before[["a", "scaled"]] + 1
    assert Map.delete(after_change, ["a", "scaled"]) == Map.delete(before, ["a", "scaled"])

    # The pulse ran in the call, and the cell was handed the new shaping before it answered.
    assert values(board, "a") == List.duplicate(10, 5)
    assert values(board, "b") == List.duplicate(2, 5)
    redrawn = view_until("a", &(is_binary(&1.svg) and &1.svg != first.svg))
    assert redrawn.state == :live
    assert Server.info(board).board.cells["a"].vars == %{"k" => 10}
  end

  test "a board variable re-runs the board's context-taking sources and every cell's that sees it" do
    board = start()
    before = runs(board)

    assert Server.vars(board, %{k: 7}) == :ok
    after_change = runs(board)

    # The board's own and `b`'s, which gives no `k` of its own, re-run.
    for path <- [["scaled"], ["b", "scaled"]],
        do: assert(after_change[path] == before[path] + 1, inspect(path))

    # `a` and `c` override `k`; `plain` takes one argument: none re-runs.
    for path <- [["a", "scaled"], ["c", "scaled"], ["plain"]],
        do: assert(after_change[path] == before[path], inspect(path))

    assert values(board, "b") == List.duplicate(7, 5)
    assert values(board, "a") == List.duplicate(3, 5)
  end

  test "a change that changes no value re-runs nothing" do
    board = start()
    before = runs(board)

    assert Server.vars(board, :a, %{k: 3}) == :ok
    assert Server.vars(board, %{k: 2}) == :ok
    assert runs(board) == before
  end

  test "a pulse due later runs on its timer, then the cell redraws" do
    board = start(debounce: 30)
    # The first pulse is due after the debounce too.
    view_until("a", &(&1.state == :live and is_binary(&1.svg)))
    before = runs(board)

    assert Server.vars(board, :a, %{k: 10}) == :ok
    assert runs(board) == before

    view_until("a", fn view ->
      is_binary(view.svg) and values(board, "a") == List.duplicate(10, 5)
    end)

    assert runs(board)[["a", "scaled"]] == before[["a", "scaled"]] + 1
  end

  test "variables the board does not take are refused, nothing changed" do
    board = start()
    before = runs(board)

    assert {:error, errors} = Server.vars(board, :a, %{nope: 1})
    assert Enum.any?(errors, &match?({_path, {:undeclared, :var, "nope"}}, &1))
    assert Server.vars(board, :zz, %{k: 1}) == {:error, [{[:cells, "zz"], :unknown_key}]}

    assert runs(board) == before
    assert Server.info(board).board.cells["a"].vars == %{"k" => 3}
  end

  test "a literal read of a variable the scope does not give is a fault at that source" do
    reads = %{
      from: [{:raw, nil}],
      schema: @out,
      elixir:
        ~S|fn %{raw: rows}, context -> Enum.map(rows, fn r -> %{t: r.t, v: r.v * context["vars"]["m"]} end) end|
    }

    board =
      start(
        board: board(%{reads: reads}),
        binding: Binding.new(%{{:a, :primary} => :reads})
      )

    source = Server.info(board).virtual_sources[["a", "reads"]]
    assert %{state: {:down, {:virtual_source, "reads", :restricted}}, runs: 0} = source
    assert %{kind: :restricted, detail: detail} = source.fault
    assert inspect(detail) =~ ~s({:unknown_var, "m"})

    view = view_until("a", &match?({:down, _}, &1.state))
    assert view.state == {:down, {:virtual_source, "reads", :restricted}}

    # A board variable of that name gives the scope it: the source is checked again, and runs.
    assert Server.vars(board, %{m: 5}) == :ok

    assert %{state: :live, fault: nil, runs: 1} =
             Server.info(board).virtual_sources[["a", "reads"]]

    assert values(board, "a") == List.duplicate(5, 5)
  end
end
