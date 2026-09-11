defmodule Visualize.Chart.Refs do
  @moduledoc """
  Reference resolution as one rule (spec/14 §19.6, D-103): every library id at a
  reference site of a flat design is resolved through a store, so that what leaves
  `Visualize.Chart.flatten/2` carries no ids and what the frame draws needs no store.

  A `{:style, n}` at a style site — a mark's, an axis's, a label's `style`, alone or in a
  stack (§3.6) — becomes the entry's body inline, since a style site already takes a node.
  A `{:scale, n}` or `{:source, n}` at a single-valued site — an axis's `scale`, a mark's
  `data`, a mark's `scales.x` — is declared in the design's namespace for the kind under a
  **synthesised key**, `:"scale:4"`, the word the DOM already uses for the id, and the site
  is rewritten to that key. A body that is itself a composite is flattened first.

  An id the store no longer holds is a **mask** at the site (§19.2, D-100): a style entry
  becomes nothing, a single-valued site is removed so the kind's default or the validator's
  fault applies, and the id is reported. Rendering never fails on a stale reference and
  never draws less than it says.
  """

  alias Visualize.Chart.{Composite, Fragment}

  @typedoc "The ids no store could find, each with the path of the site that named it."
  @type missing :: [{[atom() | non_neg_integer()], Fragment.id()}]

  # Where a name-keyed kind is declared in a design, and the kinds resolved here at all.
  @namespaces %{scale: [:frame, :scales], source: [:sources]}
  @resolved [:style, :scale, :source]

  @doc """
  A flat design with every id at a reference site resolved through `fetch`, and the ids
  that were missing.

      iex> lib = %{{:style, 1} => %{style: %{stroke_width: 5}}, {:scale, 4} => %{scale: %{kind: :linear}}}
      iex> design = %{frame: %{axes: [%{scale: {:scale, 4}, side: :left}]}, marks: [%{id: :m, style: [{:style, 1}, %{opacity: 0.5}], scales: %{x: {:scale, 9}}}]}
      iex> {resolved, missing} = Visualize.Chart.Refs.resolve(design, &Map.fetch(lib, &1))
      iex> hd(resolved.frame.axes).scale
      :"scale:4"
      iex> resolved.frame.scales
      %{"scale:4": %{kind: :linear}}
      iex> hd(resolved.marks).style
      [%{stroke_width: 5}, %{opacity: 0.5}]
      iex> {Map.has_key?(hd(resolved.marks).scales, :x), missing}
      {false, [{[:marks, 0, :scales, :x], {:scale, 9}}]}
  """
  @spec resolve(map(), (Fragment.id() -> {:ok, map()} | :error)) :: {map(), missing()}
  def resolve(design, fetch) when is_map(design) do
    {resolved, {declared, missing}} = walk(design, [], fetch, {[], []})

    design =
      Enum.reduce(declared, resolved, fn {kind, key, body}, acc ->
        update_in(acc, Enum.map(@namespaces[kind], &Access.key(&1, %{})), &Map.put(&1, key, body))
      end)

    {design, Enum.reverse(missing)}
  end

  # The walk carries what it declares and what it could not find. A struct is a leaf; a
  # tagged id is resolved where it stands; everything else is walked.
  defp walk(%_{} = struct, _path, _fetch, acc), do: {struct, acc}

  defp walk(map, path, fetch, acc) when is_map(map) do
    Enum.reduce(map, {%{}, acc}, fn {key, value}, {out, acc} ->
      case walk(value, path ++ [key], fetch, acc) do
        {:masked, acc} -> {out, acc}
        {resolved, acc} -> {Map.put(out, key, resolved), acc}
      end
    end)
  end

  defp walk(list, path, fetch, acc) when is_list(list) do
    {items, acc} =
      list
      |> Enum.with_index()
      |> Enum.reduce({[], acc}, fn {item, i}, {out, acc} ->
        case walk(item, path ++ [i], fetch, acc) do
          {:masked, acc} -> {out, acc}
          {resolved, acc} -> {[resolved | out], acc}
        end
      end)

    {Enum.reverse(items), acc}
  end

  defp walk({kind, n} = id, path, fetch, {declared, missing})
       when kind in @resolved and is_integer(n) and n > 0 do
    case body(id, fetch) do
      {:ok, body} when kind == :style ->
        {body, {declared, missing}}

      {:ok, body} ->
        key = :"#{kind}:#{n}"
        {key, {[{kind, key, body} | declared], missing}}

      :error when kind == :style ->
        {%{}, {declared, [{path, id} | missing]}}

      :error ->
        {:masked, {declared, [{path, id} | missing]}}
    end
  end

  defp walk(tuple, path, fetch, acc) when is_tuple(tuple) do
    {items, acc} = walk(Tuple.to_list(tuple), path, fetch, acc)
    {List.to_tuple(items), acc}
  end

  defp walk(leaf, _path, _fetch, acc), do: {leaf, acc}

  # The entry's body: a wrapper's inner node, or — for a composite of that kind — what it
  # flattens to. Anything else the store holds under the id is not a body of the kind.
  defp body({kind, _n} = id, fetch) do
    with {:ok, fragment} <- fetch.(id),
         {:ok, flat, _report} <- Composite.flatten(fragment, fetch),
         {^kind, inner} <- Fragment.wrapped(flat) do
      {:ok, inner}
    else
      _other -> :error
    end
  end
end
