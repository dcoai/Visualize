defmodule Visualize.Chart.Compiled.Motion do
  @moduledoc false
  # A mark's values easing toward the readings its rows carry, between the ticks of a
  # compiled chart (spec/14 §5.1, §12.5, #417). A scale's transition moves a *domain*
  # (`Visualize.Chart.Compiled.Transition`); this one moves the values themselves, which
  # is what gives a needle its travel.
  #
  # The state per mark is `%{{position, channel} => state}`: where the easing started
  # (`from`), where it goes (`target`), when it started (`since`) and where it is
  # (`shown`). Identity is the row's position among the mark's rows, so a row that
  # arrives is shown at its value and one that departs is forgotten — the state is
  # rebuilt each tick over the rows actually drawn.

  alias Visualize.Chart
  alias Visualize.Chart.Schema
  alias Visualize.Ease

  # `series` groups rows and `path` is geometry already built: neither is a value that
  # travels. Every other channel bound to a numeric field does (spec/14 §12.5).
  @still [:series, :path]

  @typedoc "One channel of one row, mid-travel."
  @type state :: %{from: float(), target: float(), since: integer(), shown: float()}

  @typedoc "What a mark needs to ease: its source, the fields it eases and its node."
  @type motion :: %{source: atom(), fields: [atom()], node: map()}

  @doc false
  # The marks a compiled chart eases, as `%{mark index => motion}`: those with a
  # `transition` node that bind at least one channel to a field.
  @spec marks(Chart.t()) :: %{non_neg_integer() => motion()}
  def marks(%Chart{marks: marks}) do
    for {mark, index} <- Enum.with_index(marks),
        node = Map.get(mark, :transition),
        is_map(node),
        fields = fields(mark),
        fields != [],
        source = source(mark),
        source != nil,
        into: %{},
        do: {index, %{source: source, fields: fields, node: node}}
  end

  @doc false
  # The rows of every easing mark at their shown values and the states after this tick at
  # `at` milliseconds, as `%{mark index => {source name, rows}}` — what
  # `Visualize.Chart.Compiled` substitutes for that mark's source when it draws it.
  @spec apply(%{non_neg_integer() => motion()}, %{non_neg_integer() => map()}, map(), integer()) ::
          {%{non_neg_integer() => {atom(), [map()]}}, %{non_neg_integer() => map()}}
  def apply(motions, states, sources, at) do
    Enum.reduce(motions, {%{}, states}, fn {index, motion}, {moved, states} ->
      {rows, state} = ease(rows(sources, motion.source), Map.get(states, index, %{}), motion, at)
      {Map.put(moved, index, {motion.source, rows}), Map.put(states, index, state)}
    end)
  end

  # Only a list of maps eases: a source given as columns, or one the chart does not bind,
  # is drawn as it is.
  defp rows(sources, name) do
    case Map.get(sources, name) do
      rows when is_list(rows) -> rows
      _other -> []
    end
  end

  # The rows shown, and the state of only the rows shown — a departed row is forgotten by
  # not being carried over.
  defp ease(rows, state, %{fields: fields, node: node}, at) do
    rows
    |> Enum.with_index()
    |> Enum.map_reduce(%{}, fn {row, position}, kept ->
      Enum.reduce(fields, {row, kept}, fn field, {row, kept} ->
        case Map.fetch(row, field) do
          {:ok, value} when is_number(value) ->
            key = {position, field}
            state = step(Map.get(state, key), value * 1.0, node, at)
            {Map.put(row, field, state.shown), Map.put(kept, key, state)}

          _absent_or_not_a_number ->
            {row, kept}
        end
      end)
    end)
  end

  # A value seen for the first time is shown as it is; one that changed is retargeted from
  # where the easing stands, so a reading that moves again mid-travel is not jerked back.
  defp step(nil, value, _node, at), do: %{from: value, target: value, since: at, shown: value}

  defp step(state, value, node, at) do
    shown = position(state, node, at)

    if value == state.target do
      %{state | shown: shown}
    else
      # Shown where the new easing stands on this tick: where it starts, unless it has no
      # duration — reduced motion (spec/14 §21.6) — and is at its target at once.
      moved = %{from: shown, target: value, since: at, shown: shown}
      %{moved | shown: position(moved, node, at)}
    end
  end

  # Where the easing stands at `at`: `from` toward `target` along the curve, done when the
  # duration has passed or is nothing.
  defp position(%{from: from, target: target, since: since}, node, at) do
    duration = Map.get(node, :duration, Schema.default(:transition, :duration))
    easing = Map.get(node, :easing, Schema.default(:transition, :easing))
    t = if duration <= 0, do: 1.0, else: min(1.0, max(0.0, (at - since) / duration))
    from + (target - from) * Kernel.apply(Ease, easing, [t])
  end

  # The channels the mark binds to a field, which are the ones whose value can change.
  defp fields(mark) do
    mark
    |> Map.get(:channels, %{})
    |> Enum.flat_map(fn
      {channel, field} when is_atom(field) and channel not in @still -> [field]
      _constant_or_still -> []
    end)
    |> Enum.uniq()
  end

  defp source(%{data: name}) when is_atom(name), do: name
  defp source(%{data: %{source: name}}) when is_atom(name), do: name
  defp source(_mark), do: nil
end
