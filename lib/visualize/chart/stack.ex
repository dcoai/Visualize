defmodule Visualize.Chart.Stack do
  @moduledoc false
  # The cascade of one fragment over another (spec/14 §8.2, D-81, D-82) and the
  # provenance of a stack (§17.1, D-83), which are one walk with two results.
  #
  # For every key the higher layer wins: `:override` keys recurse into a node both layers
  # give as a map, exactly as `Visualize.Chart.Compose` does; `:union` keys take the
  # higher layer's entry whole for a name both declare, where composition reports
  # `:conflict`; `:concat` keys read both lists as one sequence, each identity keeping its
  # first position and its last value. Nothing can fail.
  #
  # `node/4` returns the merged node and the leaf paths the higher layer contributed to
  # it. `cascade/2` drops the second; `explain/1` folds the layers and keeps it, so what
  # provenance reports and what the cascade produces cannot drift.

  alias Visualize.Chart.{Fragment, Migration, Schema, Text, Var}
  alias Visualize.Chart.Style.Parts

  @doc false
  @spec cascade(map(), map()) :: map()
  def cascade(a, b) when is_map(a) and is_map(b), do: :design |> node(a, b, []) |> elem(0)

  @doc false
  @spec explain([{term(), map()}]) :: [map()]
  def explain(layers) when is_list(layers) do
    {stacked, provenance} = fold(layers)

    {:node, :design}
    |> leaves(stacked, [])
    |> Enum.sort()
    |> Enum.map(fn path ->
      {layer, overrode} = Map.fetch!(provenance, path)
      %{path: path, value: at(stacked, path), layer: layer, overrode: overrode}
    end)
  end

  @doc false
  @spec free_vars([{term(), map()}]) :: [map()]
  def free_vars(layers) when is_list(layers) do
    {stacked, provenance} = fold(layers)
    declared = declared_vars(stacked)

    {:node, :design}
    |> variables(stacked, [])
    |> Enum.uniq()
    |> Enum.group_by(fn {_path, _type, name} -> name end)
    |> Enum.map(fn {name, uses} -> free_var(name, uses, declared, provenance) end)
    |> Enum.sort_by(& &1.name)
  end

  defp fold(layers) do
    Enum.reduce(layers, {%{}, %{}}, fn {id, fragment}, {acc, provenance} ->
      {merged, set} = node(:design, acc, fragment, [])
      {merged, Enum.reduce(set, provenance, &record(&1, id, &2))}
    end)
  end

  defp free_var(name, uses, declared, provenance) do
    default = Map.get(declared, name)

    %{
      name: name,
      default: default,
      required: default == nil,
      uses:
        uses
        |> Enum.sort()
        |> Enum.map(fn {path, type, _name} ->
          %{path: path, expects: type, layer: layer_of(provenance, path)}
        end)
    }
  end

  # A declared default of `nil` is no default, as application reads it (spec/14 §2.4).
  defp declared_vars(%{vars: vars}) when is_map(vars) and not is_struct(vars) do
    for {name, %{default: default}} <- vars, default != nil, into: %{}, do: {name, default}
  end

  defp declared_vars(_stacked), do: %{}

  # The layer of the leaf a variable stands in: its own path when it is one, else the
  # enclosing leaf's — a variable inside a text is a part of one (spec/14 §17.2).
  defp layer_of(provenance, path) do
    case {Map.fetch(provenance, path), path} do
      {{:ok, {layer, _overrode}}, _path} -> layer
      {:error, []} -> nil
      {:error, path} -> layer_of(provenance, Enum.drop(path, -1))
    end
  end

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

  # The layer takes the path; the layer that held it before becomes the last of the
  # layers it overrode, so the list reads lowest first (spec/14 §17.1).
  defp record(path, id, provenance) do
    Map.update(provenance, path, {id, []}, fn {previous, overrode} ->
      {id, overrode ++ [previous]}
    end)
  end

  # -- the walk --------------------------------------------------------------------------

  defp node(kind, a, b, path) do
    (Map.keys(a) ++ Map.keys(b))
    |> Enum.uniq()
    |> Enum.reduce({%{}, []}, fn k, {acc, set} ->
      case {Map.fetch(a, k), Map.fetch(b, k)} do
        {{:ok, va}, {:ok, vb}} ->
          {v, s} = key(kind, k, va, vb, path ++ [k])
          {Map.put(acc, k, v), set ++ s}

        {{:ok, va}, :error} ->
          {Map.put(acc, k, va), set}

        {:error, {:ok, vb}} ->
          {Map.put(acc, k, vb), set ++ leaves(type(kind, k), vb, path ++ [k])}
      end
    end)
  end

  # A key the schema does not know is `:override` and is a leaf — except a singular wrapper
  # at the top, `%{style: %{…}}`, which is a node of its kind (spec/14 §19.2), so two style
  # fragments cascade key by key as two styles would.
  defp key(kind, k, va, vb, path) do
    {va, vb} = parts(kind, k, va, vb)

    case spec(kind, k) do
      nil -> {vb, [path]}
      spec -> rule(spec.merge, spec.type, va, vb, path)
    end
  end

  # A style's part written as a shorthand on one side and as a part on the other is the
  # part on both, so they merge key by key as two parts do (spec/14 §3.1, D-172).
  defp parts(:style, k, va, vb) when k in [:fill, :stroke, :curve, :effect] do
    if node_map?(va) != node_map?(vb), do: {part(k, va), part(k, vb)}, else: {va, vb}
  end

  defp parts(_kind, _k, va, vb), do: {va, vb}

  defp part(k, v), do: Map.get(Parts.normalize(%{k => v}), k)

  defp spec(kind, k) do
    case {Schema.key(kind, k), kind} do
      {nil, :design} ->
        case Fragment.singular(k) do
          nil -> nil
          inner -> %{merge: :override, type: {:node, inner}}
        end

      {spec, _kind} ->
        spec
    end
  end

  defp rule(:concat, type, va, vb, path) when is_list(va) and is_list(vb) do
    concat(node_kind(type), element_type(type), va, vb, path)
  end

  # The higher layer's entry replaces the lower's whole: derivation within a style is
  # `extends` (spec/14 §3.5), never the cascade.
  defp rule(:union, type, va, vb, path) when is_map(va) and is_map(vb) do
    if node_map?(va) and node_map?(vb) do
      union(element_type(type), va, vb, path)
    else
      {vb, leaves(type, vb, path)}
    end
  end

  # A `:deep` name map cascades member by member: a frame the higher layer also declares
  # merges key by key, as a singular `frame` node did (spec/14 §8.2, #383).
  defp rule(:deep, type, va, vb, path) when is_map(va) and is_map(vb) do
    with true <- node_map?(va) and node_map?(vb),
         kind when kind != nil <- node_kind(element_type(type)) do
      deep(kind, va, vb, path)
    else
      _other -> {vb, leaves(type, vb, path)}
    end
  end

  defp rule(_merge, type, va, vb, path) do
    with true <- node_map?(va) and node_map?(vb),
         kind when kind != nil <- node_kind(type) do
      # A part whose type changes keeps of the lower only what no type decides (D-172).
      node(kind, Parts.under(kind, va, vb), vb, path)
    else
      _other -> {vb, leaves(type, vb, path)}
    end
  end

  defp deep(kind, va, vb, path) do
    (Map.keys(va) ++ Map.keys(vb))
    |> Enum.uniq()
    |> Enum.reduce({%{}, []}, fn name, {acc, set} ->
      case {Map.fetch(va, name), Map.fetch(vb, name)} do
        {{:ok, x}, {:ok, y}} ->
          {v, s} = node(kind, x, y, path ++ [name])
          {Map.put(acc, name, v), set ++ s}

        {{:ok, x}, :error} ->
          {Map.put(acc, name, x), set}

        {:error, {:ok, y}} ->
          {Map.put(acc, name, y), set ++ leaves({:node, kind}, y, path ++ [name])}
      end
    end)
  end

  defp union(entry_type, va, vb, path) do
    (Map.keys(va) ++ Map.keys(vb))
    |> Enum.uniq()
    |> Enum.reduce({%{}, []}, fn name, {acc, set} ->
      case Map.fetch(vb, name) do
        {:ok, v} -> {Map.put(acc, name, v), set ++ leaves(entry_type, v, path ++ [name])}
        :error -> {Map.put(acc, name, Map.fetch!(va, name)), set}
      end
    end)
  end

  # The lower's elements and the higher's read as one sequence, each identity keeping its
  # first position and its last value (spec/14 §8.2): that is what makes the cascade
  # associative over `:concat` keys, and it collapses a duplicate identity in either list.
  defp concat(kind, element_type, lower, higher, path) do
    merged =
      Enum.reduce(tag(lower, :lower) ++ tag(higher, :higher), [], fn {element, _} = e, acc ->
        case identity(kind, element) do
          nil -> acc ++ [e]
          id -> place(kind, acc, id, e)
        end
      end)

    set =
      for {{element, :higher}, index} <- Enum.with_index(merged),
          leaf <- leaves(element_type, element, path ++ [index]),
          do: leaf

    {Enum.map(merged, &elem(&1, 0)), set}
  end

  defp tag(elements, origin), do: Enum.map(elements, &{&1, origin})

  defp place(kind, acc, id, element) do
    case Enum.find_index(acc, fn {e, _} -> identity(kind, e) == id end) do
      nil -> acc ++ [element]
      index -> List.replace_at(acc, index, element)
    end
  end

  # -- variables -------------------------------------------------------------------------

  # Every `%Var{}` the resolution of spec/14 §7.3 would reach, with the schema's type at
  # its path: the walk descends where `Visualize.Chart.Template.resolve/2` descends and
  # stops where it stops, so `free_vars/1` lists what application will demand and no more.
  defp variables(type, %Var{name: name}, path), do: [{path, type, name}]

  defp variables({:node, kind}, v, path) when is_map(v) and not is_struct(v) do
    Enum.flat_map(v, fn {k, e} -> variables(type(kind, k, e), e, path ++ [k]) end)
  end

  defp variables({:map, t}, v, path) when is_map(v) and not is_struct(v) do
    Enum.flat_map(v, fn {k, e} -> variables(t, e, path ++ [k]) end)
  end

  defp variables({:list, t}, v, path) when is_list(v) do
    v |> Enum.with_index() |> Enum.flat_map(fn {e, i} -> variables(t, e, path ++ [i]) end)
  end

  defp variables({:one_of, types} = t, v, path) do
    case Schema.select(types, v) do
      nil -> []
      ^t -> []
      chosen -> variables(chosen, v, path)
    end
  end

  # A part of a text stands where a text part goes, and that is what it expects (§17.2).
  # A text is one value whichever form it takes (§7.1): its variables stand at the key.
  defp variables(:text, parts, path) when is_list(parts) do
    for %Var{name: name} <- parts, do: {path, :text, name}
  end

  defp variables(:text, string, path) when is_binary(string) do
    case Text.parse(string) do
      {:ok, parts} -> for %Var{name: name} <- parts, do: {path, :text, name}
      {:error, _} -> []
    end
  end

  defp variables(_type, _v, _path), do: []

  # -- leaves ----------------------------------------------------------------------------

  # Every path the walk does not descend into: it descends through a node, a name-keyed
  # declaration and a collection of nodes, and stops everywhere else (spec/14 §17.1).
  defp leaves({:node, kind}, v, path) when is_map(v) and not is_struct(v) do
    Enum.flat_map(v, fn {k, e} -> leaves(type(kind, k, e), e, path ++ [k]) end)
  end

  defp leaves({:map, t}, v, path) when is_map(v) and not is_struct(v) do
    Enum.flat_map(v, fn {k, e} -> leaves(t, e, path ++ [k]) end)
  end

  defp leaves({:list, {:node, _} = t}, v, path) when is_list(v) do
    v |> Enum.with_index() |> Enum.flat_map(fn {e, i} -> leaves(t, e, path ++ [i]) end)
  end

  defp leaves({:one_of, types} = t, v, path) do
    case Schema.select(types, v) do
      nil -> [path]
      ^t -> [path]
      chosen -> leaves(chosen, v, path)
    end
  end

  defp leaves(_type, _v, path), do: [path]

  defp at(value, []), do: value
  defp at(value, [k | rest]) when is_list(value), do: at(Enum.at(value, k), rest)
  defp at(value, [k | rest]) when is_map(value), do: at(Map.fetch!(value, k), rest)

  # -- the schema's word -------------------------------------------------------------------

  defp type(kind, key) do
    case spec(kind, key) do
      nil -> Migration.legacy_type(kind, key) || :term
      spec -> spec.type
    end
  end

  # A style's `fill`, `stroke`, `curve` or `effect` written as a shorthand is the flat key's
  # value, and expects what that key did (spec/14 §9, D-172).
  defp type(:style, key, value) when key in [:fill, :stroke, :curve, :effect] do
    if Parts.flat?(%{key => value}), do: Migration.flat_type(key), else: type(:style, key)
  end

  defp type(kind, key, _value), do: type(kind, key)

  defp node_map?(v), do: is_map(v) and not is_struct(v)

  defp element_type({:list, t}), do: t
  defp element_type({:map, t}), do: t
  defp element_type(type), do: type

  defp node_kind({:node, kind}), do: kind
  defp node_kind({:list, t}), do: node_kind(t)
  defp node_kind({:one_of, types}), do: Enum.find_value(types, &node_kind/1)
  defp node_kind(_type), do: nil
end
