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
    variables compile again, `carry/2`'d from the compiled chart before. The deliveries are
    first read as a compiled chart's tick reads its sources (spec/14 §12.5): a tensor and
    tuple rows named by the slot's fields, and a delivery its slot cannot read a fault — the
    cell keeps the frame it holds and is `{:invalid, errors}` until one that reads arrives
    (D-232).

  The board's messages are plain sends, never calls, so a slow cell never holds the board:
  `{:data, slots, now}`, `{:now, now}`, `{:size, size}`, `{:component, chart, vars}`,
  `{:selection, selection}` and `{:subscribers, pids, newcomer}`.

  - **The selection** (spec/15 §13.2, D-151, D-171). A cell whose rows hold the board's
    selection draws its data in the palette's view states: its rows gain a
    `:"$vis_state"` column, `:selected` where the selection is and `:muted` elsewhere,
    and each mark with `data` lays `{:field, :"$vis_state"}` in its style stack, the
    style the column names (#644), before a trailing local edit (spec/14 §3.7). A cell that does not hold it draws as before.
  - **A pick**, `{:pick, from, ref, series, index}`, is answered to `from` as `{ref,
    reply}`: the row behind that keyboard point, its identity, item and frame, or `:error`.
  - **A click**, `{:event, from, ref, click}`, is answered the same way (spec/15 §9.2,
    D-170): the `Visualize.Event` of a click on the drawing the cell holds, its row read
    from the rows each mark drew at the last frame, or `:error`. Each frame drawn has a
    token of its own, the view's `drawn`, and a click carrying another is dropped.
  """

  use GenServer, restart: :temporary

  alias Visualize.Board.Draw
  alias Visualize.Chart
  alias Visualize.Chart.{Compiled, Style, Summary}
  alias Visualize.Data.{Schema, Table}
  alias Visualize.Event

  # The column a selection is drawn through: the name of a view state of the palette per
  # row (spec/15 §13.2, D-171).
  @state :"$vis_state"

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
      system: Keyword.get(opts, :system, :as_posted),
      generators: Keyword.get(opts, :generators, []),
      assigns: Keyword.get(opts, :assigns, %{}),
      title: Keyword.get(opts, :title),
      # Its chart root's id on the board (spec/15 §8.3, D-188).
      id: Keyword.get(opts, :id),
      stale_after: Keyword.get(opts, :stale_after),
      subscribers: Keyword.get(opts, :subscribers, []),
      selection: Keyword.get(opts, :selection),
      slots: nil,
      now: nil,
      drawn: nil,
      compiled: nil,
      compiled_from: nil,
      pickable: nil,
      shown: nil,
      token: nil,
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

  def handle_info({:selection, selection}, state) do
    {:noreply, %{state | selection: selection, drawn: nil} |> draw() |> show()}
  end

  def handle_info({:subscribers, pids, newcomer}, state) do
    state = %{state | subscribers: pids}
    if newcomer && state.view, do: send(newcomer, message(state, state.view))
    {:noreply, state}
  end

  # A pick (spec/15 §13.2): the row behind a keyboard point and its identity, answered to
  # the caller under its reference.
  def handle_info({:pick, from, ref, series, index}, state) do
    send(from, {ref, picked(state, series, index)})
    {:noreply, state}
  end

  # A click (spec/15 §9.2, D-170): resolved against the drawing held, answered likewise.
  def handle_info({:event, from, ref, click}, state) do
    send(from, {ref, clicked(state, click)})
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
  # from changed; the frame kept otherwise. A component the data cannot be applied to, and a
  # delivery its slot cannot read (D-232), are faults the state shows, never a raise. The drawing is `Visualize.Board.Draw`'s, which a
  # snapshot draws through too (spec/15 §12.2).
  defp draw(%{slots: nil} = state), do: state

  defp draw(state) do
    cond do
      not Draw.drawable?(state.slots) ->
        %{
          state
          | svg: nil,
            attrs: {%{}, %{}},
            pickable: nil,
            shown: nil,
            token: nil,
            fault: nil,
            drawn: nil
        }

      state.drawn == drawn_from(state) ->
        state

      true ->
        case Draw.read(state.chart, state.slots) do
          {:ok, slots} ->
            drawn_over(%{state | slots: slots}, slots)

          # A delivery its slot cannot read (spec/15 §8.3, D-232): nothing is placed,
          # applied or stepped, and the drawing held stays under the fault.
          {:error, faults} ->
            %{state | fault: {:data, faults}, drawn: drawn_from(state)}
        end
    end
  end

  defp drawn_over(state, slots) do
    placed = Draw.sources(slots)

    {sources, chart} = selected(state, placed)

    case compiled(state, sources, chart) do
      {:ok, state} ->
        step(state, sources)

      {:error, errors} ->
        %{
          state
          | svg: nil,
            attrs: {%{}, %{}},
            pickable: nil,
            shown: nil,
            token: nil,
            fault: {:apply, errors}
        }
    end
  end

  # What the frame is drawn from: the deliveries and their schemas, at a size, for a chart,
  # under a selection.
  defp drawn_from(state) do
    {Map.new(state.slots, fn {slot, %{delivery: d, schema: s}} -> {slot, {d, s}} end), state.size,
     state.chart, state.vars, state.selection}
  end

  # The compiled charts for these sources: the ones held, unless none are, the size, the
  # chart drawn or its variables moved, or a delivery names another schema version; then
  # compiled again and carried from the ones before (spec/14 §12.1, §12.5).
  defp compiled(state, sources, chart) do
    from = {state.size, chart, state.vars}

    fresh? =
      state.compiled != nil and state.compiled_from == from and
        not Enum.any?(state.compiled, fn {_name, c} -> Compiled.stale?(c, sources) end)

    if fresh?, do: {:ok, state}, else: compile(%{state | compiled_from: from}, sources, chart)
  end

  defp compile(state, sources, chart) do
    with {:ok, done} <- Draw.compile(%{state | chart: chart}, sources, state.compiled || []) do
      {:ok, Map.merge(state, done)}
    end
  end

  # -- the selection (spec/15 §13.2) --------------------------------------------------------

  # The sources and the chart a selection is drawn with: when a row of any slot holds it,
  # every row gains the state column and every mark with data lays the view state it
  # names; otherwise the sources and the chart as they were.
  defp selected(%{selection: [_ | _] = selection} = state, sources) do
    if Enum.any?(sources, fn {_slot, d} -> Enum.any?(d.rows, &holds?(&1, selection)) end) do
      put = fn row ->
        Map.put(row, @state, if(holds?(row, selection), do: :selected, else: :muted))
      end

      {Map.new(sources, fn {slot, d} -> {slot, %{d | rows: Enum.map(d.rows, put)}} end),
       stated(state.chart)}
    else
      {sources, state.chart}
    end
  end

  defp selected(state, sources), do: {sources, state.chart}

  # A row holds a selection when, for each of its fields, one of the fields linked to it
  # has that field's value: every field at once for a composite identity (D-167).
  defp holds?(row, selection) do
    Enum.all?(selection, fn %{fields: fields, value: value} ->
      value != nil and Enum.any?(fields, &(Table.get(row, &1) == value))
    end)
  end

  # The style grammar's own style by data (spec/14 §3.6, D-171, #644): the state column,
  # whose value names the style, laid in each data mark's stack at the view states' layer —
  # over its names and field entries, under a trailing local edit (spec/14 §3.7, D-172) —
  # the column declared on every source that declares its fields. The names resolve as any
  # palette name does, so a design's own `selected:` or `muted:` wins over the theme's.
  defp stated(%Chart{marks: marks, sources: sources} = chart) do
    entry = {:field, @state}

    marks =
      Enum.map(marks, fn
        %{data: _} = mark -> Map.put(mark, :style, Style.with_state(Map.get(mark, :style), entry))
        mark -> mark
      end)

    sources =
      Map.new(sources || %{}, fn
        {slot, %{fields: [_ | _] = fields} = node} -> {slot, %{node | fields: fields ++ [@state]}}
        pair -> pair
      end)

    %{chart | marks: marks, sources: sources}
  end

  # The row behind a keyboard point, without the state column, its identity — the one its
  # slot's schema declares (D-167), else the inference of `Visualize.Event.identity/3` —
  # its item and its frame.
  defp picked(%{pickable: nil}, _series, _index), do: :error

  defp picked(state, series, index)
       when is_integer(series) and series >= 0 and is_integer(index) and index >= 0 do
    with %{points: points} <- Enum.at(Summary.points(state.pickable), series),
         %{row: row, mark: mark} <- Enum.at(points, index) do
      row = Map.delete(row, @state)
      identity = Event.identity(mark, row, schema_of(state, mark))

      {:ok,
       %{
         row: row,
         identity: identity,
         item: Event.item(mark, identity),
         frame: state.pickable.frame.name
       }}
    else
      _none -> :error
    end
  end

  defp picked(_state, _series, _index), do: :error

  # A click on the drawing the cell holds (D-170): its token must be the frame's, its
  # frame one of the cell's compiled frames, its mark one that declares its name — never
  # the cell's own `pick` — and its ordinal a row of the rows that mark drew.
  defp clicked(%{token: token} = state, %{drawn: token, event: name} = click)
       when token != nil and name != "pick" do
    with {frame, compiled} <- compiled_frame(state.compiled, click.frame),
         mark when is_map(mark) <- Enum.at(compiled.chart.marks, click.mark) do
      rows = Compiled.rows(compiled, state.shown, click.mark)
      origin = {compiled.margin.left + compiled.box.x, compiled.margin.top + compiled.box.y}

      Event.build(click, mark, rows, schema_of(state, mark), frame, origin,
        cell: state.name,
        row: &Map.delete(&1, @state)
      )
    else
      _none -> :error
    end
  end

  defp clicked(_state, _click), do: :error

  defp compiled_frame(compiled, name) when is_list(compiled) and is_binary(name),
    do: Enum.find(compiled, fn {frame, _compiled} -> to_string(frame) == name end)

  defp compiled_frame(_compiled, _name), do: nil

  defp schema_of(state, mark) do
    # A slot is named by its string (D-195), as the board holds its pools.
    with slot when is_binary(slot) or is_atom(slot) <- slot_of(mark),
         %{schema: %Schema{} = schema} <-
           Map.get(state.slots || %{}, Visualize.Chart.Names.name(slot)) do
      schema
    else
      _none -> nil
    end
  end

  defp slot_of(%{data: %{source: slot}}), do: slot
  defp slot_of(%{data: slot}), do: slot
  defp slot_of(_mark), do: nil

  defp step(state, sources) do
    at = System.monotonic_time(:millisecond)
    {svg, compiled} = Draw.step(state.compiled, sources, at, state)

    {attrs, pickable} = Draw.realized(state.applied, sources, state.theme, state.size)

    %{
      state
      | compiled: compiled,
        svg: svg,
        attrs: attrs,
        pickable: pickable,
        shown: sources,
        token: Integer.to_string(System.unique_integer([:positive, :monotonic])),
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
