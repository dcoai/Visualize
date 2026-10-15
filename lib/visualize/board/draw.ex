defmodule Visualize.Board.Draw do
  @moduledoc false
  # What a cell draws, as pure functions (spec/15 §8.3, §12.2): the cell process draws
  # through them frame after frame, and a snapshot draws each cell through them once, so a
  # snapshot's cell is the cell's own drawing of the same data, byte for byte.
  #
  # A drawing is: the slots' deliveries placed by their timestamp (`Visualize.Board.Rows`),
  # the component applied at the cell's box and compiled, one compiled chart per frame in
  # drawing order (`z`, then name), each frame stepped once over the placed sources, and
  # the groups inside one accessible root titled with the cell's title, else the chart's
  # summary name. The state's own drawing — the whole cell, or a banner over the chart —
  # is `Visualize.Board.State`'s.

  alias Visualize.Board.{Rows, State, View}
  alias Visualize.Chart
  alias Visualize.Chart.{Compiled, Frame, Summary}
  alias Visualize.Data.{Delivery, Schema}
  alias Visualize.Data.Schema.Cache
  alias Visualize.Hooks.{Crosshair, Keyboard}
  alias Visualize.IR.Element
  alias Visualize.Render

  @doc false
  # Whether the slots can be drawn as a chart: every slot holds a delivery and one has rows.
  def drawable?(slots) do
    map_size(slots) > 0 and
      Enum.all?(slots, fn {_slot, slot} -> match?(%Delivery{}, slot.delivery) end) and
      Enum.any?(slots, fn {_slot, slot} -> slot.delivery.rows != [] end)
  end

  @doc false
  # Each slot's delivery with its rows placed (spec/15 §8.5).
  def sources(slots) do
    Map.new(slots, fn {slot, %{delivery: d, schema: s}} -> {slot, Rows.place(d, s)} end)
  end

  @doc false
  # The component applied to the placed sources and compiled, each frame carried from the
  # compiled chart `previous` held for it (spec/14 §12.5): `{:ok, %{compiled, applied,
  # summary}}`, or application's faults. `previous` is `[]` for a first drawing.
  def compile(
        %{chart: chart, vars: vars, size: size, theme: theme, now: now, slots: slots} = cell,
        sources,
        previous
      ) do
    schemas = Cache.new(for {slot, %{schema: %Schema{} = schema}} <- slots, do: {slot, schema})
    system = Map.get(cell, :system, :as_posted)

    options = [
      sources: sources,
      vars: vars,
      size: size,
      theme: theme,
      system: system,
      schemas: schemas,
      # The board's generators and assigns (spec/14 §3.13, spec/15 §8.3).
      generators: Map.get(cell, :generators, []),
      assigns: Map.get(cell, :assigns, %{})
    ]

    options = if now, do: Keyword.put(options, :now, now), else: options

    with {:ok, applied} <- Chart.apply(chart, options) do
      {:ok, frames} = Chart.compile(applied, motion: :full)
      previous = Map.new(previous)

      compiled =
        for {name, _frame} <- Enum.sort_by(applied.frames, fn {n, f} -> {f.z, to_string(n)} end) do
          fresh = Map.fetch!(frames, name)

          case Map.fetch(previous, name) do
            {:ok, before} -> {name, Compiled.carry(before, fresh)}
            :error -> {name, fresh}
          end
        end

      summary = %{name: Summary.new(applied).name, text: Summary.text(applied)}
      {:ok, %{compiled: compiled, applied: applied, summary: summary}}
    end
  end

  @doc false
  # Every frame stepped over the sources at `at` and drawn inside one accessible root:
  # `{svg, compiled}`, the compiled charts as the step left them.
  def step(compiled, sources, at, %{size: {w, h}, title: title, summary: summary}) do
    {groups, stepped} =
      Enum.map_reduce(compiled, [], fn {name, one}, acc ->
        {group, one} = Compiled.step(one, sources, at: at)
        {group, [{name, one} | acc]}
      end)

    svg =
      Element.root(w, h,
        title: title || summary.name,
        description: summary.text,
        responsive: true,
        children: groups
      )
      |> Render.to_string()

    {svg, Enum.reverse(stepped)}
  end

  @doc false
  # The hooks' attributes from the frame realized over the sources (spec/15 §8.3): the
  # keyboard's for a chart of one frame, the crosshair's for a cartesian one whose first
  # mark has `x` and `y`. `{crosshair, keyboard}`.
  def attrs(applied, sources, theme, size),
    do: applied |> realized(sources, theme, size) |> elem(0)

  @doc false
  # The hooks' attributes, and the chart realized over the sources that a pick reads its
  # keyboard points from (spec/15 §13.2): `{{crosshair, keyboard}, pickable}`, `pickable`
  # `nil` for a chart of more than one frame, which has no keyboard points.
  def realized(%{frames: frames} = applied, sources, theme, size) when map_size(frames) == 1 do
    plain = Map.new(sources, fn {slot, d} -> {slot, Delivery.source(d)} end)

    frame =
      Frame.new(applied.chart,
        sources: plain,
        theme: theme,
        system: applied.frame.system,
        size: size
      )

    pickable = %{applied | frame: frame, sources: plain}
    {{crosshair(frame, applied.chart, plain), Keyboard.attrs(pickable)}, pickable}
  end

  def realized(_applied, _sources, _theme, _size), do: {{%{}, %{}}, nil}

  defp crosshair(%Frame{kind: :cartesian} = frame, %Chart{marks: [mark | _]}, sources) do
    channels = Map.get(mark, :channels, %{})

    if is_map(channels) and Map.has_key?(channels, :x) and Map.has_key?(channels, :y),
      do: Crosshair.attrs(frame, sources),
      else: %{}
  end

  defp crosshair(_frame, _chart, _sources), do: %{}

  @doc false
  # The view of a cell (spec/15 §8.3): its chart's frame, if one is drawn, and its state's
  # own drawing — the whole cell where there is no chart, a banner over one that is not
  # live, nothing over a live one.
  def view(%{name: name, title: title, size: {w, _h} = size, theme: theme}, cell_state, drawn) do
    %{svg: svg, attrs: {crosshair, keyboard}, frames: frames} = drawn

    note =
      cond do
        svg == nil -> State.render(cell_state, theme, size)
        cell_state == :live -> nil
        true -> State.banner(cell_state, theme, w)
      end

    %View{
      cell: name,
      title: title,
      state: cell_state,
      size: size,
      svg: svg,
      note: note,
      crosshair: crosshair,
      keyboard: keyboard,
      frames: frames,
      drawn: Map.get(drawn, :token)
    }
  end

  @doc false
  # A cell's state from what it holds (spec/15 §8.4): invalid when its component could not
  # be applied because a field has a type its scale cannot take (D-153), down when it could
  # not be applied otherwise, loading before any data, else `Visualize.Board.State.of/3`.
  def state({:apply, errors} = fault, _slots, _now, _stale_after) do
    if Enum.any?(errors, &match?({_path, {:type_mismatch, _, _, _, _}}, &1)),
      do: {:invalid, errors},
      else: {:down, fault}
  end

  def state(_fault, nil, _now, _stale_after), do: :loading
  def state(nil, slots, now, stale_after), do: State.of(slots, now, stale_after)

  @doc false
  # One cell drawn once, from nothing held (spec/15 §12.2): what the cell process draws as
  # its first frame of the same slots. `cell` holds `name`, `title`, `chart`, `vars`,
  # `size`, `theme`, `system`, `now`, `stale_after` and `slots` (`nil` before any data).
  def once(cell) do
    blank = %{svg: nil, attrs: {%{}, %{}}, frames: 0}

    {drawn, fault} =
      if cell.slots == nil or not drawable?(cell.slots),
        do: {blank, nil},
        else: first_frame(cell, blank)

    view(cell, state(fault, cell.slots, cell.now, cell.stale_after), drawn)
  end

  defp first_frame(cell, blank) do
    sources = sources(cell.slots)

    case compile(cell, sources, []) do
      {:ok, %{compiled: compiled, applied: applied, summary: summary}} ->
        {svg, _stepped} = step(compiled, sources, 0, Map.put(cell, :summary, summary))
        {%{svg: svg, attrs: attrs(applied, sources, cell.theme, cell.size), frames: 1}, nil}

      {:error, errors} ->
        {blank, {:apply, errors}}
    end
  end
end
