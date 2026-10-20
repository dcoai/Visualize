defmodule Visualize.Chart.Validator.Bindings do
  @moduledoc false

  import Visualize.Chart.Names, only: [is_name: 1]
  # A field binding at a style site with no datum (spec/14 §3.2, #766, D-196): a frame
  # `:label`, an axis and a legend draw from no row, so a `{:field, f}` value in a style
  # node there has nothing to read. A stack's `{:field, f}` entry lays nothing there and a
  # generator's field argument reads `nil` (§3.6, §3.13): neither is a binding of a value.

  alias Visualize.Chart.Validator.Types

  @doc false
  # The style sites that draw from no row, by their node kind.
  @spec datumless() :: [atom()]
  def datumless, do: [:label, :axis, :legend]

  @doc false
  # `{:invalid_for, kind}` at each path of `stack` that holds a bound value: a `{:field, f}`
  # inside an inline node, or a reference to a design style that carries one — directly,
  # through `extends` or a list.
  @spec faults(atom(), term(), list(), map()) :: [{list(), {:invalid_for, atom()}}]
  def faults(kind, stack, path, styles) do
    entries =
      if is_list(stack),
        do: stack |> Enum.with_index() |> Enum.map(fn {e, i} -> {e, path ++ [i]} end),
        else: [{stack, path}]

    for {entry, at} <- entries,
        fault <- entry(entry, at, styles),
        do: {fault, {:invalid_for, kind}}
  end

  # An inline node's own values, and the style it extends.
  defp entry(node, at, styles) when is_map(node) and not is_struct(node) do
    parent = Map.get(node, :extends)
    extended = if style?(parent, styles, []), do: [at ++ [:extends]], else: []
    bound(Map.delete(node, :extends), at) ++ extended
  end

  defp entry(name, at, styles) when is_name(name),
    do: if(named?(name, styles, []), do: [at], else: [])

  defp entry(_other, _at, _styles), do: []

  # A design style that carries a binding, followed through `extends` and lists; a name
  # already seen is a cycle, which `Validator.Cycles` reports.
  defp named?(name, styles, seen) when is_map(styles) and not is_struct(styles) do
    Types.name?(name) and name not in seen and
      case Map.get(styles, name) do
        nil -> false
        style -> style?(style, styles, [name | seen])
      end
  end

  defp named?(_name, _styles, _seen), do: false

  defp style?(entries, styles, seen) when is_list(entries),
    do: Enum.any?(entries, &style?(&1, styles, seen))

  defp style?(node, styles, seen) when is_map(node) and not is_struct(node) do
    bound(Map.delete(node, :extends), []) != [] or style?(Map.get(node, :extends), styles, seen)
  end

  defp style?(name, styles, seen) when is_name(name), do: named?(name, styles, seen)
  defp style?(_other, _styles, _seen), do: false

  # The paths of every bound value inside a node; a generator call's arguments are its own.
  defp bound({:field, _}, at), do: [at]
  defp bound({:generate, _name, _args}, _at), do: []

  defp bound(map, at) when is_map(map) and not is_struct(map),
    do: Enum.flat_map(map, fn {k, v} -> bound(v, at ++ [k]) end)

  defp bound(list, at) when is_list(list),
    do: list |> Enum.with_index() |> Enum.flat_map(fn {v, i} -> bound(v, at ++ [i]) end)

  defp bound(_other, _at), do: []
end
