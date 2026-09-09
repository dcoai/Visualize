defmodule Visualize.Chart.Stack do
  @moduledoc false
  # The cascade of one fragment over another (spec/14 §8.2, D-81, D-82): for every key
  # the higher layer wins. `:override` keys recurse into a node both layers give as a
  # map, exactly as `Visualize.Chart.Compose` does; `:union` keys take the higher layer's
  # entry whole for a name both declare, where composition reports `:conflict`; `:concat`
  # keys append, except that a higher element whose identity equals a lower element's
  # replaces it in place. Nothing can fail, so the result is the fragment itself.

  alias Visualize.Chart.Schema

  @doc false
  @spec cascade(map(), map()) :: map()
  def cascade(a, b) when is_map(a) and is_map(b), do: node(:design, a, b)

  # The identity of one element of a `:concat` key (spec/14 §8.2): a mark's and a label's
  # declared `id`, an axis's `{scale, side}`, and nothing for anything else — a transform
  # is a step of a sequence, and an element with no identity appends.
  @doc false
  @spec identity(Schema.kind(), term()) :: term() | nil
  def identity(kind, element) when is_map(element) and not is_struct(element) do
    case kind do
      :axis -> axis_identity(element)
      kind when kind in [:mark, :label] -> Map.get(element, :id)
      _other -> nil
    end
  end

  def identity(_kind, _element), do: nil

  defp axis_identity(%{scale: scale, side: side}), do: {scale, side}
  defp axis_identity(_axis), do: nil

  defp node(kind, a, b) do
    (Map.keys(a) ++ Map.keys(b))
    |> Enum.uniq()
    |> Map.new(fn k ->
      case {Map.fetch(a, k), Map.fetch(b, k)} do
        {{:ok, va}, {:ok, vb}} -> {k, key(kind, k, va, vb)}
        {{:ok, va}, :error} -> {k, va}
        {:error, {:ok, vb}} -> {k, vb}
      end
    end)
  end

  # A key the schema does not know is `:override`.
  defp key(kind, k, va, vb) do
    case Schema.key(kind, k) do
      nil -> vb
      spec -> rule(spec.merge, spec.type, va, vb)
    end
  end

  defp rule(:concat, type, va, vb) when is_list(va) and is_list(vb) do
    concat(node_kind(type), va, vb)
  end

  # The higher layer's entry replaces the lower's whole: derivation within a style is
  # `extends` (spec/14 §3.5), never the cascade.
  defp rule(:union, _type, va, vb) when is_map(va) and is_map(vb) do
    if node_map?(va) and node_map?(vb), do: Map.merge(va, vb), else: vb
  end

  defp rule(_merge, type, va, vb) do
    if node_map?(va) and node_map?(vb) do
      case node_kind(type) do
        nil -> vb
        kind -> node(kind, va, vb)
      end
    else
      vb
    end
  end

  # The lower's elements and the higher's read as one sequence, each identity keeping its
  # first position and its last value (spec/14 §8.2): that is what makes the cascade
  # associative over `:concat` keys, and it collapses a duplicate identity in either list.
  defp concat(kind, lower, higher) do
    Enum.reduce(lower ++ higher, [], fn element, acc ->
      case identity(kind, element) do
        nil -> acc ++ [element]
        id -> place(kind, acc, id, element)
      end
    end)
  end

  defp place(kind, acc, id, element) do
    case Enum.find_index(acc, &(identity(kind, &1) == id)) do
      nil -> acc ++ [element]
      index -> List.replace_at(acc, index, element)
    end
  end

  defp node_map?(v), do: is_map(v) and not is_struct(v)

  defp node_kind({:node, kind}), do: kind
  defp node_kind({:list, t}), do: node_kind(t)
  defp node_kind({:one_of, types}), do: Enum.find_value(types, &node_kind/1)
  defp node_kind(_type), do: nil
end
