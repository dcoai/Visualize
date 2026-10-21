defmodule Visualize.Chart.Coverage do
  @moduledoc false

  import Visualize.Chart.Names, only: [is_name: 1]
  # Coverage of declared values (spec/14 §7.4, D-194): a mapping by a field — a style
  # stack's `{:field, f}` entry at a mark's `style`, a `:choose` mark's `on` — must have,
  # for every value the field declares (spec/08 §10.1), a style the value names or a case
  # (or an `else`). Checked at application, once the frames are realized and each frame's
  # theme is known; a field that declares no values, or a slot with no schema, is not.

  alias Visualize.Data.Schema
  alias Visualize.Theme

  @doc false
  # Every mapping of the design: `{mark index, slot, :style | :choose, field}`.
  @spec mapped(map()) :: [{non_neg_integer(), atom(), :style | :choose, atom()}]
  def mapped(map) do
    case Map.get(map, :marks) do
      marks when is_list(marks) ->
        marks
        |> Enum.with_index()
        |> Enum.flat_map(fn {mark, i} -> mappings(mark, i) end)

      _none ->
        []
    end
  end

  defp mappings(%{data: data} = mark, i) do
    slot = slot(data)

    if is_name(slot),
      do: for({kind, f} <- fields(mark), do: {i, slot, kind, f}),
      else: []
  end

  defp mappings(_mark, _i), do: []

  @doc false
  # The fields one mark maps by, in order: `{:style, f}` per style stack entry `{:field, f}`,
  # then `{:choose, f}` for a `:choose` mark's `on` (spec/14 §3.6, §5.2).
  @spec fields(map()) :: [{:style | :choose, atom() | String.t()}]
  def fields(mark) do
    styled = for {:field, f} <- List.wrap(Map.get(mark, :style)), is_name(f), do: {:style, f}

    chosen =
      case mark do
        %{type: :choose, on: f} when is_name(f) -> [{:choose, f}]
        _other -> []
      end

    styled ++ chosen
  end

  defp slot(%{source: source}), do: source
  defp slot(source), do: source

  @doc false
  # Every mapping that does not cover its field's values, `{:uncovered, f, missing}` at the
  # mark's `style` or its `cases`.
  @spec faults(map(), %{atom() => Schema.t()}, map()) :: [{list(), term()}]
  def faults(map, schemas, frames) do
    marks = Map.get(map, :marks, [])

    for {i, slot, kind, field} <- mapped(map),
        %Schema{} = schema <- [Map.get(schemas, slot)],
        [_ | _] = values <- [Schema.values(schema, field)],
        missing =
          missing(kind, values, Enum.at(marks, i), map, frame_of(Enum.at(marks, i), frames)),
        missing != [] do
      {[:marks, i, if(kind == :style, do: :style, else: :cases)], {:uncovered, field, missing}}
    end
  end

  defp frame_of(mark, frames) do
    case Map.get(mark, :frame) do
      nil -> frames |> Map.values() |> Enum.min_by(& &1.name)
      name -> Map.fetch!(frames, name)
    end
  end

  defp missing(:style, values, _mark, map, frame) do
    names = Map.keys(Map.get(map, :styles) || %{}) ++ Theme.style_names(frame.theme)
    Enum.reject(values, &named?(names, &1))
  end

  defp missing(:choose, values, mark, _map, _frame) do
    if Map.get(mark, :else),
      do: [],
      else: Enum.reject(values, &named?(Map.keys(Map.get(mark, :cases) || %{}), &1))
  end

  # A value names a style or a case by its spelling, whichever each is (D-195).
  defp named?(names, value) when is_atom(value) or is_binary(value),
    do: Enum.any?(names, &Visualize.Chart.Names.same?(&1, value))

  defp named?(_names, _value), do: false
end
