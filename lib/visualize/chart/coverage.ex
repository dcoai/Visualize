defmodule Visualize.Chart.Coverage do
  @moduledoc false
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

    styled =
      for {:field, f} <- List.wrap(Map.get(mark, :style)), is_atom(f), do: {i, slot, :style, f}

    chosen =
      case mark do
        %{type: :choose, on: f} when is_atom(f) -> [{i, slot, :choose, f}]
        _other -> []
      end

    if is_atom(slot), do: styled ++ chosen, else: []
  end

  defp mappings(_mark, _i), do: []

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
        {:ok, [_ | _] = values} <- [Schema.fetch(schema, field, :values)],
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

  defp named?(names, value) when is_atom(value), do: value in names

  defp named?(names, value) when is_binary(value),
    do: Enum.any?(names, &(Atom.to_string(&1) == value))

  defp named?(_names, _value), do: false
end
