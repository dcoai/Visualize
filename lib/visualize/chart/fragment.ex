defmodule Visualize.Chart.Fragment do
  @moduledoc """
  What a fragment is about, and the ids it refers to (spec/14 §19.2, §19.8).

  A fragment's **kind** is derived, never stored: walk down while the fragment sets exactly
  one key, and the kind is the last node kind reached. A library body says its kind with a
  singular wrapper — `%{style: %{…}}` — and a hand-written fragment says it by the schema's
  own keys; both read the same way here. A fragment about more than one thing at its
  shallowest branching point is `:design`.

  An **id** is `{kind, n}` (§19.2). `refs/1` finds every id a fragment carries, which is
  how a bundle takes the closure of an entry, and `relocate/2` rewrites them through a
  table, which is how an import renumbers (§19.7). Both are deep walks that stop at a
  struct, as every walk over a design does (D-92).

  ## Examples

      iex> Visualize.Chart.Fragment.kind(%{style: %{stroke_width: 5}})
      :style

      iex> Visualize.Chart.Fragment.kind(%{styles: %{series: %{stroke_width: 5}}})
      :style

      iex> Visualize.Chart.Fragment.kind(%{frame: %{axes: [%{scale: :x, side: :bottom}]}})
      :axis

      iex> Visualize.Chart.Fragment.kind(%{frame: %{size: %{width: 1}, margin: %{top: 1}}})
      :frame

      iex> Visualize.Chart.Fragment.kind(%{frame: %{size: %{width: 1}}})
      :size

      iex> Visualize.Chart.Fragment.kind(%{theme: :dark})
      :theme

      iex> Visualize.Chart.Fragment.kind(%{composite: %{uses: []}})
      :composite

      iex> Visualize.Chart.Fragment.kind(%{version: 1, theme: :dark, frame: %{}})
      :design

      iex> Visualize.Chart.Fragment.refs(%{style: [{:style, 3}, %{fill: {:style, 11}}]})
      [{:style, 3}, {:style, 11}]

  """

  alias Visualize.Chart.Schema

  # A library body names its kind with a singular key and nothing else (§19.2). `theme` and
  # `frame` are not here because they are design keys already, and the schema's own walk
  # reaches them; a wrapper is only for a kind the design has no singular key for.
  @singular %{
    style: :style,
    scale: :scale,
    source: :source,
    axis: :axis,
    mark: :mark,
    label: :label,
    var: :var,
    composite: :composite
  }

  @typedoc "An id: the kind of thing, and a number its store never repeats (§19.2)."
  @type id :: {atom(), pos_integer()}

  @doc """
  Every kind a fragment can be, and so every kind an id can carry: the schema's node kinds
  and `:composite` (§19.6).
  """
  @spec kinds() :: [atom(), ...]
  def kinds, do: Enum.uniq(Schema.kinds() ++ Map.values(@singular))

  @doc """
  The kind of a fragment (§19.8): the last node kind reached walking down while exactly one
  key is set. `:design` when the fragment branches at the top.
  """
  @spec kind(map()) :: atom()
  def kind(fragment) when is_map(fragment) and not is_struct(fragment) do
    case Map.to_list(fragment) do
      [{key, value}] ->
        case Schema.key(:design, key) do
          nil -> Map.get(@singular, key, :design)
          spec -> descend(:design, spec.type, value)
        end

      _several ->
        :design
    end
  end

  defp walk(kind, node) when is_map(node) and not is_struct(node) do
    case Map.to_list(node) do
      [{key, value}] ->
        case Schema.key(kind, key) do
          nil -> kind
          spec -> descend(kind, spec.type, value)
        end

      _several ->
        kind
    end
  end

  defp walk(kind, _value), do: kind

  # One node under the key: keep walking. A map or list of nodes with exactly one member:
  # walk into it. Several members: the fragment is about that kind, however many.
  defp descend(_kind, {:node, inner}, value), do: walk(inner, value)

  defp descend(_kind, {:map, {:node, inner}}, value) when is_map(value) do
    case Map.values(value) do
      [only] -> walk(inner, only)
      _several -> inner
    end
  end

  defp descend(_kind, {:list, {:node, inner}}, [only]), do: walk(inner, only)
  defp descend(_kind, {:list, {:node, inner}}, value) when is_list(value), do: inner

  defp descend(kind, {:one_of, alternatives}, value) do
    case Enum.find(alternatives, &match?({:node, _}, &1)) do
      {:node, inner} -> walk(inner, value)
      nil -> kind
    end
  end

  defp descend(kind, _type, _value), do: kind

  @doc """
  Every id a fragment refers to, in the order they are met, once each (§19.7).

  An id is a `{kind, n}` tuple whose kind is one of `kinds/0` and whose `n` is a positive
  integer. A tuple of any other shape — an anchor `{:axis, :y}`, a `{:field, :t}` — is a
  value and is left alone.
  """
  @spec refs(term()) :: [id()]
  def refs(fragment) do
    fragment |> collect([]) |> Enum.reverse() |> Enum.uniq()
  end

  defp collect({kind, n} = id, acc) when is_atom(kind) and is_integer(n) and n > 0 do
    if kind in kinds(), do: [id | acc], else: acc
  end

  defp collect(%_{} = _struct, acc), do: acc

  defp collect(map, acc) when is_map(map),
    do: Enum.reduce(map, acc, fn {_key, value}, acc -> collect(value, acc) end)

  defp collect(list, acc) when is_list(list), do: Enum.reduce(list, acc, &collect/2)
  defp collect(tuple, acc) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> collect(acc)
  defp collect(_leaf, acc), do: acc

  @doc """
  A fragment with every id rewritten through a table, and the ids the table did not carry
  (§19.7). An id that is not in the table is left as it is — it resolves as a mask (§19.2)
  — and is returned so an import can report it.

      iex> table = %{{:style, 11} => {:style, 1}}
      iex> Visualize.Chart.Fragment.relocate(%{style: [{:style, 11}, {:style, 9}]}, table)
      {%{style: [{:style, 1}, {:style, 9}]}, [{:style, 9}]}
  """
  @spec relocate(term(), %{id() => id()}) :: {term(), [id()]}
  def relocate(fragment, table) do
    {rewritten, missed} = rewrite(fragment, table, [])
    {rewritten, missed |> Enum.reverse() |> Enum.uniq()}
  end

  defp rewrite({kind, n} = id, table, missed) when is_atom(kind) and is_integer(n) and n > 0 do
    cond do
      kind not in kinds() -> {id, missed}
      Map.has_key?(table, id) -> {Map.fetch!(table, id), missed}
      true -> {id, [id | missed]}
    end
  end

  defp rewrite(%_{} = struct, _table, missed), do: {struct, missed}

  defp rewrite(map, table, missed) when is_map(map) do
    Enum.reduce(map, {%{}, missed}, fn {key, value}, {acc, missed} ->
      {value, missed} = rewrite(value, table, missed)
      {Map.put(acc, key, value), missed}
    end)
  end

  defp rewrite(list, table, missed) when is_list(list) do
    {values, missed} =
      Enum.reduce(list, {[], missed}, fn value, {acc, missed} ->
        {value, missed} = rewrite(value, table, missed)
        {[value | acc], missed}
      end)

    {Enum.reverse(values), missed}
  end

  defp rewrite(tuple, table, missed) when is_tuple(tuple) do
    {values, missed} = tuple |> Tuple.to_list() |> rewrite(table, missed)
    {List.to_tuple(values), missed}
  end

  defp rewrite(leaf, _table, missed), do: {leaf, missed}
end
