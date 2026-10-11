defmodule Visualize.Board.Cell do
  @moduledoc """
  One cell of a live board, as a process (spec/15 §8.3, D-146).

  A cell process applies, compiles and draws its component, and sends what it shows — a
  `Visualize.Board.View` — straight to the board's subscribers, so no frame crosses the
  board's mailbox. The board (`Visualize.Board.Server`) starts one per cell, `:temporary`
  under a supervisor of its own, monitors it and restarts it with a backoff: a cell that
  dies is shown crashed and started again, alone.

  - **The heap limit.** The cell's first act is `Process.flag(:max_heap_size, …)` with
    `kill: true`, so a design that grows its heap without bound — a 10,000-tick axis, an
    unbounded layout, a slot fed millions of rows — is killed in its own process.
  - **Coalescing.** A data message taken from the mailbox first takes every later one
    behind it and keeps the newest, so a cell that falls behind skips to the present and
    a slow cell drops only its own frames.
  - **Drawing.** With every slot holding a delivery, the rows are placed by their
    timestamp with a break in every gap (`Visualize.Board.Rows`), the component is applied
    at the cell's box and compiled, one compiled chart per frame, and every data change is
    a `Visualize.Chart.Compiled.step/3` per frame inside one accessible root. A delivery
    naming another schema version (`Compiled.stale?/2`), a new size and a new chart or
    variables compile again, `carry/2`'d from the compiled chart before.

  The board's messages are plain sends, never calls, so a slow cell never holds the board:
  `{:data, slots, now}`, `{:now, now}`, `{:size, size}`, `{:component, chart, vars}` and
  `{:subscribers, pids, newcomer}`.
  """

  use GenServer, restart: :temporary

  alias Visualize.Board.Draw
  alias Visualize.Chart.Compiled

  @doc false
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @impl true
  def init(opts) do
    # Before anything else: the cell's whole life is under the limit (spec/15 §8.3).
    Process.flag(:max_heap_size, %{
      size: Keyword.fetch!(opts, :max_heap),
      kill: true,
      error_logger: true,
      include_shared_binaries: false
    })

    state = %{
      name: Keyword.fetch!(opts, :name),
      board: Keyword.fetch!(opts, :board),
      chart: Keyword.fetch!(opts, :chart),
      vars: Keyword.fetch!(opts, :vars),
      size: Keyword.fetch!(opts, :size),
      theme: Keyword.fetch!(opts, :theme),
      title: Keyword.get(opts, :title),
      stale_after: Keyword.get(opts, :stale_after),
      subscribers: Keyword.get(opts, :subscribers, []),
      slots: nil,
      now: nil,
      drawn: nil,
      compiled: nil,
      applied: nil,
      summary: nil,
      svg: nil,
      attrs: {%{}, %{}},
      fault: nil,
      state: :loading,
      view: nil,
      frames: 0
    }

    {:ok, state, {:continue, Keyword.get(opts, :data)}}
  end

  @impl true
  def handle_continue(nil, state), do: {:noreply, show(state)}
  def handle_continue({:data, _slots, _now} = data, state), do: handle_info(data, state)

  @impl true
  def handle_info({:data, slots, now}, state) do
    {slots, now} = newest(slots, now)
    {:noreply, state |> Map.merge(%{slots: slots, now: now}) |> draw() |> show()}
  end

  # Only the board's now moved: the state is decided again — a cell grows stale — and
  # nothing is drawn.
  def handle_info({:now, now}, state) do
    {:noreply, show(%{state | now: now})}
  end

  def handle_info({:size, size}, state) do
    {:noreply, %{state | size: size, drawn: nil} |> draw() |> show()}
  end

  def handle_info({:component, chart, vars}, state) do
    {:noreply, %{state | chart: chart, vars: vars, drawn: nil} |> draw() |> show()}
  end

  def handle_info({:subscribers, pids, newcomer}, state) do
    state = %{state | subscribers: pids}
    if newcomer && state.view, do: send(newcomer, message(state, state.view))
    {:noreply, state}
  end

  # Every later data message behind this one, the newest kept (spec/15 §8.3).
  defp newest(slots, now) do
    receive do
      {:data, slots, now} -> newest(slots, now)
    after
      0 -> {slots, now}
    end
  end

  # -- drawing ------------------------------------------------------------------------------

  # The chart drawn when every slot holds a delivery with rows and anything it is drawn
  # from changed; the frame kept otherwise. A component the data cannot be applied to is a
  # fault the state shows, never a raise. The drawing is `Visualize.Board.Draw`'s, which a
  # snapshot draws through too (spec/15 §12.2).
  defp draw(%{slots: nil} = state), do: state

  defp draw(state) do
    cond do
      not Draw.drawable?(state.slots) ->
        %{state | svg: nil, attrs: {%{}, %{}}, fault: nil, drawn: nil}

      state.drawn == drawn_from(state) ->
        state

      true ->
        sources = Draw.sources(state.slots)

        case compiled(state, sources) do
          {:ok, state} -> step(state, sources)
          {:error, errors} -> %{state | svg: nil, attrs: {%{}, %{}}, fault: {:apply, errors}}
        end
    end
  end

  # What the frame is drawn from: the deliveries and their schemas, at a size, for a chart.
  defp drawn_from(state) do
    {Map.new(state.slots, fn {slot, %{delivery: d, schema: s}} -> {slot, {d, s}} end), state.size,
     state.chart, state.vars}
  end

  # The compiled charts for these sources: the ones held, unless none are, the size or the
  # chart moved, or a delivery names another schema version; then compiled again and
  # carried from the ones before (spec/14 §12.1, §12.5).
  defp compiled(state, sources) do
    {_slots, size, chart, vars} = drawn_from(state)
    previous = state.drawn

    fresh? =
      state.compiled != nil and previous != nil and elem(previous, 1) == size and
        elem(previous, 2) == chart and elem(previous, 3) == vars and
        not Enum.any?(state.compiled, fn {_name, c} -> Compiled.stale?(c, sources) end)

    if fresh?, do: {:ok, state}, else: compile(state, sources)
  end

  defp compile(state, sources) do
    with {:ok, done} <- Draw.compile(state, sources, state.compiled || []) do
      {:ok, Map.merge(state, done)}
    end
  end

  defp step(state, sources) do
    at = System.monotonic_time(:millisecond)
    {svg, compiled} = Draw.step(state.compiled, sources, at, state)

    %{
      state
      | compiled: compiled,
        svg: svg,
        attrs: Draw.attrs(state.applied, sources, state.theme, state.size),
        fault: nil,
        drawn: drawn_from(state),
        frames: state.frames + 1
    }
  end

  # -- showing ------------------------------------------------------------------------------

  # The view of the cell's present state, sent to every subscriber when it changed, and
  # the state reported to the board when that changed.
  defp show(state) do
    cell_state = Draw.state(state.fault, state.slots, state.now, state.stale_after)
    view = Draw.view(state, cell_state, state)

    if view != state.view do
      Enum.each(state.subscribers, &send(&1, message(state, view)))
    end

    if cell_state != state.state, do: send(state.board, {:cell_state, state.name, cell_state})

    %{state | view: view, state: cell_state}
  end

  defp message(state, view), do: {:visualize_board, state.board, {:cell, state.name, view}}
end
