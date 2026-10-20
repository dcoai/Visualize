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
