defmodule Visualize.Chart.Compose do
  @moduledoc false
  # Composition of two fragments by the schema's merge rules (spec/14 §1.5, §8, D-65):
  # `:concat` lists append, `:union` name maps unite with a conflict at a name declared
  # differently by both, `:override` takes the later fragment's value — recursing into a
  # node both fragments give as a map, so a frame's own keys follow their own rules.

  alias Visualize.Chart.{Schema, Validator}

  @doc false
  @spec merge(map(), map()) :: {:ok, map()} | {:error, [Validator.error(), ...]}
  def merge(a, b) when is_map(a) and is_map(b) do
    case node(:design, a, b, []) do
      {merged, []} -> {:ok, merged}
      {_merged, errors} -> {:error, Enum.sort_by(errors, &elem(&1, 0))}
    end
  end

  defp node(kind, a, b, path) do
    keys = Enum.uniq(Map.keys(a) ++ Map.keys(b))

    Enum.reduce(keys, {%{}, []}, fn k, {acc, errors} ->
      case {Map.fetch(a, k), Map.fetch(b, k)} do
        {{:ok, va}, {:ok, vb}} ->
          {v, e} = key(kind, k, va, vb, path ++ [k])
          {Map.put(acc, k, v), errors ++ e}

        {{:ok, va}, :error} ->
          {Map.put(acc, k, va), errors}

        {:error, {:ok, vb}} ->
          {Map.put(acc, k, vb), errors}
      end
    end)
  end

  # A key the schema does not know is `:override`.
  defp key(kind, k, va, vb, path) do
    case Schema.key(kind, k) do
      nil -> {vb, []}
      spec -> rule(spec.merge, spec.type, va, vb, path)
    end
  end

  defp rule(:concat, _type, va, vb, _path) when is_list(va) and is_list(vb), do: {va ++ vb, []}

  defp rule(:union, _type, va, vb, path) when is_map(va) and is_map(vb) do
    keys = Enum.uniq(Map.keys(va) ++ Map.keys(vb))

    Enum.reduce(keys, {%{}, []}, fn name, {acc, errors} ->
      case {Map.fetch(va, name), Map.fetch(vb, name)} do
        {{:ok, x}, {:ok, x}} -> {Map.put(acc, name, x), errors}
        {{:ok, _}, {:ok, y}} -> {Map.put(acc, name, y), errors ++ [{path ++ [name], :conflict}]}
        {{:ok, x}, :error} -> {Map.put(acc, name, x), errors}
        {:error, {:ok, y}} -> {Map.put(acc, name, y), errors}
      end
    end)
  end

  defp rule(_merge, type, va, vb, path)
       when is_map(va) and not is_struct(va) and is_map(vb) and not is_struct(vb) do
    case node_kind(type) do
      nil -> {vb, []}
      kind -> node(kind, va, vb, path)
    end
  end

  defp rule(_merge, _type, _va, vb, _path), do: {vb, []}

  defp node_kind({:node, kind}), do: kind
  defp node_kind({:one_of, types}), do: Enum.find_value(types, &node_kind/1)
  defp node_kind(_type), do: nil
end
