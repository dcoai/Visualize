defmodule Visualize.Board.VirtualSourcesRuntimeTest do
  # Virtual sources on the board process (spec/15 §14, D-194): defined when the board
  # starts, pulsed on its turns, read by its cells as any source. Turned only by `tick/1`
  # with `debounce: 0`, so a pulse is in the turn that saw the change.
  use ExUnit.Case, async: true

  @moduletag :capture_log

  alias Visualize.Board
  alias Visualize.Board.{Binding, Server, View}
  alias Visualize.Data.Schema
  alias Visualize.Test.Feeds

  @names ~w(raw doubled t v)a
  setup_all do
    {:ok, names: @names}
  end

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

  @doubled %{
    from: [{:raw, nil}],
    schema: %{t: %{type: :time}, v: %{type: :number}},
    elixir: "fn %{raw: rows} -> Enum.map(rows, fn r -> %{t: r.t, v: 2 / (r.v - 99)} end) end"
  }

  defp rows(n, v \\ 1), do: for(i <- 0..(n - 1), do: %{t: DateTime.add(@t0, i * 60), v: v})

  defp board(sources) do
    Board.from_map!(%{
      cells: %{a: %{x: 0, y: 0, w: 6, h: 3, ref: {:composite, 1}, title: "A"}},
      virtual_sources: sources
    })
  end

  defp start(opts) do
    sup = start_supervised!(Supervisor.child_spec(Visualize.Board.Supervisor, id: make_ref()))
    {feed, agent} = Feeds.scripted(schema: @schema, rows: rows(5))
    Process.unlink(agent)
    on_exit(fn -> if Process.alive?(agent), do: Agent.stop(agent) end)

    defaults = [
      board: board(%{doubled: @doubled}),
      store: %{{:composite, 1} => @line},
      binding: Binding.new(%{{:a, :primary} => :doubled}),
      feeds: %{raw: feed},
      tick: nil,
      debounce: 0,
      clock: fn -> DateTime.add(@t0, 3600) end
    ]

    {Server.start(sup, Keyword.merge(defaults, opts)), agent}
  end

  defp view_until(cell, test) do
    receive do
      {:visualize_board, _board, {:cell, ^cell, %View{} = view}} ->
        if test.(view), do: view, else: view_until(cell, test)
    end
  end

  test "a cell bound to a virtual source draws its answer" do
    {{:ok, board}, _agent} = start([])
    {:ok, _info} = Server.subscribe(board)
    :ok = Server.tick(board)

    view = view_until(:a, &(&1.state == :live))
    assert view.svg =~ ~s(class="mark mark-line")

    info = Server.info(board)
    assert %{state: :live, fault: nil, runs: runs} = info.virtual_sources[[:doubled]]
    assert runs >= 1
  end

  test "a fault keeps the last output, drawn under the down banner" do
    {{:ok, board}, agent} = start([])
    {:ok, _info} = Server.subscribe(board)
    :ok = Server.tick(board)
    view_until(:a, &(&1.state == :live))

    Feeds.set(agent, rows: rows(5, 99))
    :ok = Server.tick(board)

    view = view_until(:a, &match?({:down, _}, &1.state))
    assert view.state == {:down, {:virtual_source, :doubled, :raised}}
    assert view.svg =~ ~s(class="mark mark-line")

    assert Server.info(board).virtual_sources[[:doubled]].fault == %{
             kind: :raised,
             detail: ArithmeticError
           }
  end

  test "sources that cannot be defined refuse the board, at their paths" do
    looped = %{from: [{:looped, nil}], schema: %{v: %{type: :number}}, elixir: "fn x -> [] end"}
    lost = %{from: [{:nowhere, nil}], schema: %{v: %{type: :number}}, elixir: "fn x -> [] end"}

    {answer, _agent} = start(board: board(%{looped: looped, doubled: @doubled}))

    assert answer ==
             {:error,
              {:virtual_sources, [{[:virtual_sources, :looped, :from], {:cycle, [[:looped]]}}]}}

    {answer, _agent} = start(board: board(%{lost: lost, doubled: @doubled}))

    assert answer ==
             {:error,
              {:virtual_sources,
               [{[:virtual_sources, :lost, :from, 0], {:unknown_input, :nowhere}}]}}
  end

  test "a binding to a name that is neither a feed nor a source is still a missing feed" do
    {answer, _agent} = start(binding: Binding.new(%{{:a, :primary} => :absent}))
    assert answer == {:error, {:feeds, [:absent]}}
  end
end
