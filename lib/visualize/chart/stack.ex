defmodule Visualize.Chart.Stack do
  @moduledoc false
  # The cascade of one fragment over another (spec/14 §8.2, D-81): for every key the
  # higher layer wins. `:override` keys recurse into a node both layers give as a map,
  # exactly as `Visualize.Chart.Compose` does; `:union` keys take the higher layer's
  # entry whole for a name both declare, where composition reports `:conflict`; `:concat`
  # keys append. Nothing can fail, so the result is the fragment itself.

  alias Visualize.Chart.Schema

  @doc false
  @spec cascade(map(), map()) :: map()
  def cascade(a, b) when is_map(a) and is_map(b), do: node(:design, a, b)

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

  defp rule(:concat, _type, va, vb) when is_list(va) and is_list(vb), do: va ++ vb

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

  defp node_map?(v), do: is_map(v) and not is_struct(v)

  defp node_kind({:node, kind}), do: kind
  defp node_kind({:one_of, types}), do: Enum.find_value(types, &node_kind/1)
  defp node_kind(_type), do: nil
end
