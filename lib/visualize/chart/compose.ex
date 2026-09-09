defmodule Visualize.Chart.Compose do
  @moduledoc false
  # Composition of two fragments by the schema's merge rules (spec/14 §1.5, §8, D-65):
  # `:concat` lists append, `:union` name maps unite with a conflict at a name declared
  # differently by both, `:override` takes the later fragment's value — recursing into a
  # node both fragments give as a map, so a frame's own keys follow their own rules.
  #
  # A struct is a leaf of every walk (spec/14 §1.4, D-92): a `%Var{}` stands *for* a value
  # rather than being one, so it is never descended into and never merged as a map, even
  # though Elixir says it is one. At a `:union` key that makes it a whole value two
  # fragments can disagree about, which is `:conflict` at the key's own path.

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
    if node_map?(va) and node_map?(vb), do: union(va, vb, path), else: whole(va, vb, path)
  end

  defp rule(_merge, type, va, vb, path) when is_map(va) and is_map(vb) do
    with true <- node_map?(va) and node_map?(vb),
         kind when kind != nil <- node_kind(type) do
      node(kind, va, vb, path)
    else
      _other -> {vb, []}
    end
  end

  defp rule(_merge, _type, _va, vb, _path), do: {vb, []}

  defp union(va, vb, path) do
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

  # A `:union` key either fragment gives as a struct carries no names to unite, so it is
  # one value: taken once where the two agree, `:conflict` at the key's path where they
  # do not — the disagreement `compose/2` exists to report (spec/14 §8.1, D-92).
  defp whole(v, v, _path), do: {v, []}
  defp whole(_va, vb, path), do: {vb, [{path, :conflict}]}

  defp node_map?(v), do: is_map(v) and not is_struct(v)

  defp node_kind({:node, kind}), do: kind
  defp node_kind({:one_of, types}), do: Enum.find_value(types, &node_kind/1)
  defp node_kind(_type), do: nil
end
