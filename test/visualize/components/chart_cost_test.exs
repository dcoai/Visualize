defmodule Visualize.Components.ChartCostTest do
  @moduledoc """
  A large interactive grid redraws within D-202's budget (spec/12 §6, #809, #814): a
  2,500-cell band × band grid, one move, on SVG, the JSON canvas and the binary canvas.

  **The work is counted, not timed** (D-114). `Visualize.Work.reductions/1` counts
  `Visualize.Components.Chart.drawn/4` — everything an update draws, which the component
  runs in a process of its own (D-206) — after the drawing before the move, so its caches
  are the ones a page's second move finds. Each is counted twice and the counts must
  agree, as the gallery's are (examples' `gallery_cost_test.exs`). The budget is the
  count measured when #814 set it with a margin under the cost of each defect it guards:
  a band lookup that walks its domain (about 0.9 M more), every item serialized again
  (about 1.4 M more on SVG), the keyboard's points written again (about 0.5 M more).

  **The bytes are the wire's**: the component's LiveView diff for the move, JSON-encoded
  as the socket carries it, uncompressed, at most 200 KB; the drawing sent whole was 1.3
  to 2.8 MB.

  The milliseconds of D-202 are a `:benchmark` test (`mix test --only benchmark`).
  """
  use ExUnit.Case, async: true

  alias Phoenix.LiveView.{Diff, Socket}
  alias Visualize.Chart
  alias Visualize.Components.Chart, as: Component
  alias Visualize.Data.{Delivery, Schema}

  @backends [svg: :svg, json: {:canvas, :json}, binary: {:canvas, :binary}]

  # The count of `drawn/4` for one move when #814 measured it, and a budget a tenth above:
  # at 2,500 cells 3,034,927 on SVG, 3,088,156 on the JSON canvas and 3,163,945 on the
  # binary one; at the Expert board's 480, 595,257, 601,338 and 616,585.
  @budget %{svg: 3_350_000, json: 3_400_000, binary: 3_500_000}
  @expert_budget %{svg: 660_000, json: 670_000, binary: 690_000}

  # Two counts of one drawing agree within half a percent (examples' gallery_cost_test).
  @agree 0.005

  @wire 200_000

  @schema Schema.new!(%{
            row: %{type: :category, identity: true},
            col: %{type: :category, identity: true},
            state: %{type: :category},
            count: %{type: :number}
          })

  # A grid as a host draws a game board: one rect per cell on two band scales, styled by
  # its state, a count on the revealed ones, and a click event with nothing under the
  # pointer (D-200) whose template is the keyboard's readout (D-198).
  defp design(rows, cols) do
    %{
      version: 3,
      sources: %{
        cells: %{
          fields: [:row, :col, :state, :count],
          requires: %{row: [:identity], col: [:identity]}
        }
      },
      styles: %{
        cell: %{stroke: %{color: "#ffffff", width: 2}, transition: %{fill: %{duration: 180}}},
        hidden: %{fill: %{color: "#888888", opacity: 0.45}},
        open: %{fill: %{color: "#888888", opacity: 0.08}}
      },
      frames: %{
        main: %{
          kind: :cartesian,
          margin: %{top: 4, right: 4, bottom: 4, left: 4},
          scales: %{
            x: %{kind: :band, domain: Enum.to_list(0..(cols - 1))},
            y: %{kind: :band, domain: Enum.to_list((rows - 1)..0//-1)}
          }
        }
      },
      marks: [
        %{
          type: :rect,
          data: :cells,
          channels: %{x0: :col, x1: :col, y0: :row, y1: :row},
          style: [:cell, {:field, :state}],
          tooltip: %{
            fields: [:state, :count],
            template: "{state} {count}",
            event: :cell_click,
            show: false
          }
        },
        %{
          type: :text,
          data: %{source: :cells, transforms: [%{op: :filter, field: :count, test: :present}]},
          channels: %{x: :col, y: :row},
          label: %{text: [{:field, :count}], anchor: :middle}
        }
      ]
    }
  end

  # The board with the cells of `open` revealed, a count on every fifth of them.
  defp applied(rows, cols, open) do
    cells =
      for r <- 0..(rows - 1), c <- 0..(cols - 1) do
        open? = MapSet.member?(open, {r, c})
        count = if open? and rem(r + c, 5) == 0, do: rem(r * c, 8) + 1

        %{row: r, col: c, state: if(open?, do: "open", else: "hidden"), count: count}
      end

    {:ok, applied} =
      Chart.apply(design(rows, cols),
        sources: %{cells: Delivery.new(cells, schema: Schema.version(@schema))},
        schemas: Schema.Cache.new([{:cells, @schema}]),
        size: {cols * 24 + 8, rows * 24 + 8}
      )

    applied
  end

  # A board with a corner open, and the move that opens one more cell.
  defp move(rows, cols) do
    open = MapSet.new(for r <- 0..(div(rows, 3) - 1), c <- 0..(div(cols, 3) - 1), do: {r, c})
    {applied(rows, cols, open), applied(rows, cols, MapSet.put(open, {rows - 1, cols - 1}))}
  end

  @empty %{cache: %{}, text_cache: %{}, points_cache: %{}}

  # The second drawing's work, its caches the first's: `{first count, second count}`.
  defp counted({before, now}, backend) do
    last =
      Map.merge(@empty, Map.take(Component.drawn(before, [], backend, @empty), Map.keys(@empty)))

    {first, _} = Visualize.Work.reductions(fn -> Component.drawn(now, [], backend, last) end)
    {second, _} = Visualize.Work.reductions(fn -> Component.drawn(now, [], backend, last) end)
    {first, second}
  end

  defp within!({first, second}, budget, what) do
    assert abs(first - second) <= @agree * min(first, second),
           "#{what}: two counts are #{first} and #{second}: the count is not a property of the code"

    work = max(first, second)
    assert work <= budget, "#{what} costs #{work} reductions, over its budget of #{budget}"
  end

  # One test per backend and board, so no test carries all their work (spec/12 §6, #735).
  for {name, backend} <- @backends do
    @name name
    @backend backend

    test "a 2,500-cell move's drawing on #{name} is within its budget" do
      within!(counted(move(50, 50), @backend), @budget[@name], "2,500 cells on #{@name}")
    end

    test "a 480-cell move's drawing on #{name} is within its budget" do
      within!(counted(move(16, 30), @backend), @expert_budget[@name], "480 cells on #{@name}")
    end
  end

  # The component as LiveView holds it, and its diff as the socket carries it.
  defp updated(socket, chart, opts) do
    {:ok, socket} =
      Component.update(Map.merge(%{id: "grid", chart: chart}, Map.new(opts)), socket)

    socket
  end

  defp diff(socket, prints, components) do
    Diff.render(
      %Socket{},
      Component.render(Map.put(socket.assigns, :myself, 1)),
      prints,
      components
    )
  end

  for {name, opts} <- [
        svg: [],
        json: [backend: :canvas, canvas_format: :json],
        binary: [backend: :canvas]
      ] do
    @opts opts

    test "a 2,500-cell move on #{name} sends at most 200 KB" do
      {before, now} = move(50, 50)
      {:ok, socket} = Component.mount(%Socket{assigns: %{__changed__: %{}}})
      socket = updated(socket, before, @opts)
      {first, prints, components} = diff(socket, Diff.new_fingerprints(), Diff.new_components())
      socket = %{socket | assigns: Map.put(socket.assigns, :__changed__, %{})}

      {moved, _prints, _components} = diff(updated(socket, now, @opts), prints, components)
      bytes = byte_size(Jason.encode!(moved))

      # The first render carries the whole drawing; the move a few items of it.
      assert byte_size(Jason.encode!(first)) > 10 * bytes
      assert bytes <= @wire, "a move sent #{bytes} bytes, over #{@wire}"
    end
  end

  # The words one drawing of `chart` uses, read from outside it as D-216 reads them, in a
  # process whose heap is large enough that it never collects.
  defp need(chart, backend, last) do
    parent = self()
    ref = make_ref()

    pid =
      :erlang.spawn_opt(
        fn ->
          send(parent, {ref, Component.drawn(chart, [], backend, last)})

          receive do
            ^ref -> :ok
          end
        end,
        min_heap_size: 40_000_000,
        min_bin_vheap_size: 1_000_000_000
      )

    receive do
      {^ref, _drawn} ->
        {:garbage_collection_info, info} = Process.info(pid, :garbage_collection_info)
        send(pid, ref)
        assert info[:recent_size] == 0, "the measuring drawing collected"
        info[:heap_size] + info[:old_heap_size]
    end
  end

  # #850: D-206's drawing measured its own heap, which a process reads as its whole block,
  # so each move asked for half as much again as the last was given, and a long game on
  # this board asked the node for 104 GB. The size a drawing carries to the next is a
  # function of its own need (D-216): flat, within a quarter of the need, and never past
  # the bound. The guard is in parts (#858): the sizing rule, a pure function of one
  # measurement, over hundreds of steps without drawing; and the real drawing, for as
  # many moves as the defect needs to show.

  # What the LiveView read of real 50 × 50 moves (`garbage_collection_info`, from outside),
  # each with the size its drawing was given: the first unsized, so it collected; each
  # after it sized by `next_heap/1` of the one before, the board alternating between the
  # two drawings of a move.
  @recorded [
    {nil,
     [
       heap_size: 453_610,
       heap_block_size: 833_026,
       old_heap_size: 0,
       old_heap_block_size: 0,
       recent_size: 453_572,
       stack_size: 4,
       mbuf_size: 18
     ]},
    {7_257_152,
     [
       heap_size: 4_559_219,
       heap_block_size: 7_427_328,
       old_heap_size: 0,
       old_heap_block_size: 0,
       recent_size: 0,
       stack_size: 4,
       mbuf_size: 217_090
     ]},
    {5_699_023,
     [
       heap_size: 4_559_876,
       heap_block_size: 6_189_440,
       old_heap_size: 0,
       old_heap_block_size: 0,
       recent_size: 0,
       stack_size: 4,
       mbuf_size: 217_148
     ]},
    {5_699_845,
     [
       heap_size: 4_559_219,
       heap_block_size: 6_189_440,
       old_heap_size: 0,
       old_heap_block_size: 0,
       recent_size: 0,
       stack_size: 3,
       mbuf_size: 217_087
     ]},
    {5_699_023,
     [
       heap_size: 4_559_876,
       heap_block_size: 6_189_440,
       old_heap_size: 0,
       old_heap_block_size: 0,
       recent_size: 0,
       stack_size: 3,
       mbuf_size: 217_148
     ]},
    {5_699_845,
     [
       heap_size: 4_559_219,
       heap_block_size: 6_189_440,
       old_heap_size: 0,
       old_heap_block_size: 0,
       recent_size: 0,
       stack_size: 3,
       mbuf_size: 217_090
     ]}
  ]

  # The words a drawing used, and whether it collected, from what the LiveView read.
  defp used(info), do: info[:heap_size] + info[:old_heap_size]
  defp collected?(info), do: info[:recent_size] + info[:old_heap_size] > 0

  test "the sizing rule sizes recorded 50 × 50 moves by their need, not by their heap" do
    bound = Component.heap_bound()
    nexts = Enum.map(@recorded, fn {_given, info} -> Component.next_heap(info) end)

    # The recording is the rule's own loop: each size given is the rule's of the one before.
    assert Enum.map(tl(@recorded), &elem(&1, 0)) == Enum.drop(nexts, -1)

    for {{given, info}, next} <- Enum.zip(@recorded, nexts) do
      assert next != nil and next <= bound, "#{inspect(next)} words, past the bound of #{bound}"

      # A drawing given more than it used is read for what it used, never for its block.
      if not collected?(info) do
        assert next >= used(info) and next <= used(info) + div(used(info), 4),
               "a drawing given #{given} words used #{used(info)} and is followed by #{next}"
      end
    end

    # What the first, collecting drawing kept sizes the second over its need.
    [{_, first}, {_, second} | _] = @recorded
    assert collected?(first) and not collected?(second)

    # The size follows the need down as well as up: no size grows past the one before it
    # unless the drawing it measures used more than the one before.
    @recorded
    |> Enum.map(&elem(&1, 1))
    |> Enum.zip(nexts)
    |> Enum.drop(1)
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.each(fn [{a, size_a}, {b, size_b}] ->
      assert used(b) > used(a) or size_b <= size_a,
             "a drawing using #{used(b)} words after one using #{used(a)} " <>
               "is followed by #{size_b}, up from #{size_a}"
    end)
  end

  # What the LiveView reads of a drawing given `given` words (or `nil`, unsized) that uses
  # `need`: one given its need does not collect, reports the words it used, and holds a
  # heap block the BEAM rounded `given` up to, up to an eighth more at these sizes (the
  # recording's are 2 and 9 percent more). One given less collects, and its collection
  # keeps `kept` words, `old` of them on its old heap and the rest on its young one.
  defp measured(given, %{need: need}) when is_integer(given) and given >= need do
    [
      heap_size: need,
      heap_block_size: given + div(given, 8),
      old_heap_size: 0,
      old_heap_block_size: 0,
      recent_size: 0,
      stack_size: 4,
      mbuf_size: 0
    ]
  end

  defp measured(given, %{kept: kept, old: old}) do
    [
      heap_size: kept - old,
      heap_block_size: max(given || 0, 2 * kept),
      old_heap_size: old,
      old_heap_block_size: if(old > 0, do: 2 * old, else: 0),
      recent_size: kept - old,
      stack_size: 4,
      mbuf_size: 0
    ]
  end

  # A drawing that needs `need` words and keeps a `ratio`-th of them when it collects, all
  # on its young heap or, with `old?`, half on its old one: 3 to 9 on the cost test's
  # boards (D-216), 10 on the recording's first move.
  defp step(need, ratio, old? \\ false) do
    kept = max(div(need, ratio), 1)
    %{need: need, kept: kept, old: if(old?, do: div(kept, 2), else: 0)}
  end

  # The rule's loop, closed over the model drawing: each step's drawing is given the size
  # the step before it measured into. `{given, step, next}` per step, the first unsized.
  defp loop(steps) do
    steps
    |> Enum.map_reduce(nil, fn step, given ->
      next = Component.next_heap(measured(given, step))
      {{given, step, next}, next}
    end)
    |> elem(0)
  end

  # What the rule holds over any loop: no size past the bound; no size larger than the one
  # before it unless the drawing it measures needs more than the one before; and a drawing
  # given its need, followed by its need and at most a quarter more.
  defp holds!(trace) do
    bound = Component.heap_bound()

    for {{given, %{need: need}, next}, i} <- Enum.with_index(trace) do
      assert next == nil or next <= bound,
             "step #{i} carries #{next} words, past the bound of #{bound}"

      if given != nil and given >= need and need + div(need, 4) <= bound do
        assert next >= need and next <= need + div(need, 4),
               "step #{i} needs #{need} words, was given #{given} and is followed by #{next}"
      end
    end

    trace
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.with_index(1)
    |> Enum.each(fn {[{_, %{need: before}, size}, {_, %{need: need}, next}], i} ->
      assert size == nil or next == nil or need > before or next <= size,
             "step #{i} needs #{need} words after #{before} and grows the size " <>
               "from #{size} to #{next}"
    end)
  end

  test "the sizing rule settles a constant need within a quarter of it, however long" do
    bound = Component.heap_bound()

    for need <- [2_000, 480_000, 4_559_877, 20_000_000, div(bound * 4, 5)],
        ratio <- [3, 6, 9, 10, 12],
        old? <- [false, true] do
      %{kept: kept} = step = step(need, ratio, old?)
      trace = loop(List.duplicate(step, 400))
      holds!(trace)

      # The first drawing is sized by the BEAM and the second by what the first kept; from
      # the third on, each is sized by the one before it, the same size every time.
      sizes = trace |> Enum.drop(1) |> Enum.map(&elem(&1, 0))
      settled = Enum.drop(sizes, 1)

      cond do
        16 * kept <= bound and need + div(need, 4) <= bound ->
          assert hd(sizes) >= need, "the second drawing of #{need} words collects"

          assert Enum.uniq(settled) == [need + div(need, 4)],
                 "#{need} words settle at #{inspect(Enum.uniq(settled))}"

        # What its collection keeps sizes it past the bound, so it is never sized.
        16 * kept > bound ->
          assert Enum.uniq(sizes) == [nil], "#{need} words is sized past the bound"

        # Sized by what it kept, and unsized by what it then used: `holds!/1` is the claim.
        true ->
          :ok
      end
    end
  end

  test "the sizing rule follows a need that varies, falls and passes the bound" do
    bound = Component.heap_bound()

    # A walk of needs from a fixed seed: a page of charts of every size, in any order.
    {walk, _} =
      Enum.map_reduce(1..600, :rand.seed_s(:exsss, {858, 922, 216}), fn _, seed ->
        {need, seed} = :rand.uniform_s(30_000_000, seed)
        {ratio, seed} = :rand.uniform_s(10, seed)
        {old, seed} = :rand.uniform_s(2, seed)
        {step(need + 1_000, ratio + 2, old == 2), seed}
      end)

    falling = for need <- 20_000_000..10_000//-50_000, do: step(need, 6)
    sawtooth = for _ <- 1..30, need <- [100_000, 5_000_000, 40_000_000], do: step(need, 9, true)
    # Past the bound and back: a drawing too large to size is unsized, then sized again.
    over =
      for need <- [4_559_877, bound, 2 * bound, 4_559_877, bound - 1],
          _ <- 1..40,
          do: step(need, 8)

    for steps <- [walk, falling, sawtooth, over], do: holds!(loop(steps))

    # The walk is long enough to have tried every case of the rule.
    trace = loop(walk)
    assert Enum.any?(trace, fn {given, %{need: need}, _} -> given != nil and given >= need end)
    assert Enum.any?(trace, fn {given, %{need: need}, _} -> given != nil and given < need end)
  end

  # The real drawing, on the 50 × 50 board, for 24 moves: past the tenth, by which D-206's
  # sizing had grown the size about 1.44 times a move.
  test "the drawing's heap settles within half again its need on a 2,500-cell board" do
    {before, now} = move(50, 50)
    last = Map.take(Component.drawn(before, [], :svg, @empty), Map.keys(@empty))
    need = need(now, :svg, last)
    bound = Component.heap_bound()
    {:ok, socket} = Component.mount(%Socket{assigns: %{__changed__: %{}}})

    sizes =
      Enum.map_reduce(1..24, socket, fn i, socket ->
        socket = updated(socket, if(rem(i, 2) == 1, do: now, else: before), [])
        heap = socket.assigns.heap

        # Asserted at every move, so a growing size fails here, long before it asks the
        # node for more than it has.
        assert heap == nil or heap <= bound,
               "move #{i} carries a heap of #{heap} words, past the bound of #{bound}"

        {heap, socket}
      end)
      |> elem(0)

    # The first drawing is sized by the BEAM and the second from what the first kept;
    # from the third on, each is sized by the one before it.
    settled = Enum.drop(sizes, 2)

    assert Enum.all?(settled, &(&1 != nil and &1 >= need and &1 <= div(3 * need, 2))),
           "one move needs #{need} words; the settled sizes run " <>
             "#{inspect(Enum.min_max(settled))}"

    {low, high} = Enum.min_max(settled)
    assert high <= low + div(low, 10), "the size drifts from #{low} to #{high} words"
  end

  # A drawing that collects tells the size it was given nothing about its need: the next
  # size comes from what it kept, so one that always collects is given the same size
  # every time, where D-206 doubled it.
  test "a drawing that always collects is not given a larger heap" do
    drawing = fn ->
      kept = Enum.to_list(1..100_000)
      _dropped = Enum.map(1..200_000, &{&1})
      :erlang.garbage_collect(self(), type: :minor)
      length(kept)
    end

    {100_000, first} = Component.apart(drawing, nil)
    assert first != nil and first <= Component.heap_bound()

    # Asserted at every drawing, so a growing size fails here, before it is requested.
    Enum.reduce(2..40, first, fn i, heap ->
      {100_000, next} = Component.apart(drawing, heap)

      assert next != nil and next <= first + div(first, 10),
             "drawing #{i} is given #{inspect(next)} words where the first was given #{first}"

      next
    end)
  end

  @tag :benchmark
  test "a 2,500-cell move takes at most 100 ms, a 480-cell one 25, on every backend" do
    for {rows, cols, budget} <- [{50, 50, 100}, {16, 30, 25}],
        {name, opts} <- [
          svg: [],
          json: [backend: :canvas, canvas_format: :json],
          binary: [backend: :canvas]
        ] do
      {before, now} = move(rows, cols)

      # Timed in a process of its own that holds what a LiveView holds — the component and
      # the diff's prints — as a page's would: moves back and forth until the drawing's
      # heap has settled (D-206), then the median of five, the update and the diff as #808
      # measured a move.
      task =
        Task.async(fn ->
          {:ok, socket} = Component.mount(%Socket{assigns: %{__changed__: %{}}})
          socket = updated(socket, before, opts)
          {_, prints, components} = diff(socket, Diff.new_fingerprints(), Diff.new_components())

          {times, _} =
            Enum.map_reduce(1..9, {socket, prints, components}, fn i,
                                                                   {socket, prints, components} ->
              chart = if rem(i, 2) == 1, do: now, else: before
              socket = %{socket | assigns: Map.put(socket.assigns, :__changed__, %{})}

              :timer.tc(fn ->
                socket = updated(socket, chart, opts)
                {_, prints, components} = diff(socket, prints, components)
                {socket, prints, components}
              end)
            end)

          times |> Enum.take(-5) |> Enum.sort() |> Enum.at(2)
        end)

      median = Task.await(task, :infinity)

      assert median <= budget * 1000,
             "#{rows} × #{cols} on #{name}: #{div(median, 1000)} ms, over #{budget}"
    end
  end
end
