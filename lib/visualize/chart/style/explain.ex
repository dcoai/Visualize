defmodule Visualize.Chart.Style.Explain do
  @moduledoc false
  # Where each part of an element's style came from (spec/14 §17.3, #661, D-172): the
  # defaults its containers lay — the theme's root first, every part defined (§3.8, D-174)
  # — then the stack the element is drawn with, entry by entry, each entry's style laid by
  # the same resolution the frame uses (`Visualize.Chart.Style.compound/3`) and recorded
  # with its layer of the precedence order (§3.7), its container or its name, the names it
  # was reached through and, for a style named by data, the field and its reading.
  #
  # A generator (§3.13, D-177) is called as the frame calls it, once per call for the datum,
  # and attributed on the contribution it shaped: a generator entry is a contribution of
  # its own, layer `:generator`; a color generator is listed on the contribution whose
  # style holds it, at its leaf's path. A result that applied nothing is listed too, its
  # `result` `{:fault, reason}`. Nothing is logged: this is a reading.

  alias Visualize.Chart.Style
  alias Visualize.Chart.Style.{Defaults, Generated, Parts}
  alias Visualize.Data.Table
  alias Visualize.Theme.Palette

  @stroked [:line, :rule]
  @marks Visualize.Chart.Schema.mark_types()

  @typedoc "One contribution to a part."
  @type link :: %{
          layer:
            :theme
            | :defaults
            | :kind
            | :mark
            | :palette
            | :style
            | :field
            | :generator
            | :state
            | :inline
            | :local,
          container: term(),
          style: atom() | nil,
          via: [atom()],
          field: {:field, atom()} | nil,
          value: term(),
          set: term(),
          generators: [generator()]
        }

  @typedoc "One generator a contribution was computed with (spec/14 §17.3)."
  @type generator :: %{name: atom(), args: [term()], at: [atom()], result: term()}

  @doc false
  # The parts of the style `stack` lays for an element of `kind`, read against `styles`
  # (declared over the palette) where `declared` are the design's own names; `datum` reads
  # the field entries, and `series` is the mark's own paint for its position, or `nil`.
  # `containers` are the element's, farthest first, each `{name, defaults node}`, the
  # theme's root first. `frame` calls the generators the stack reaches.
  @spec parts(
          map(),
          [atom()],
          term(),
          atom(),
          map() | nil,
          term(),
          [{term(), map() | nil}],
          map()
        ) :: {%{atom() => map()}, [map()]}
  def parts(styles, declared, stack, kind, datum, series, containers, frame) do
    names = names(styles)
    field = fn {:field, field} -> datum && Map.get(names, Table.get(datum, field)) end
    memo = memo(styles, stack, field, datum, frame)

    pick = fn
      {:field, _} = entry -> field.(entry)
      {:leaf, call} -> result(frame, :leaf, call, datum, memo)
      call -> result(frame, :entry, call, datum, memo)
    end

    gen = %{frame: frame, memo: memo, datum: datum, field: field}
    entries = List.wrap(stack)
    last = length(entries) - 1

    links =
      entries
      |> Enum.with_index()
      |> Enum.flat_map(fn {entry, i} ->
        contribution(entry, i == last, styles, declared, pick, datum)
        |> Enum.map(fn {link, node} -> {attributed(link, entry, styles, gen), node} end)
      end)
      |> with_paint(kind, series)
      |> then(&(defaults(containers, kind) ++ &1))

    value = Enum.reduce(links, %{}, fn {_link, node}, acc -> Parts.merge(acc, node) end)

    parts =
      Map.new(value, fn {part, resolved} ->
        chain =
          for {link, node} <- links, Map.has_key?(node, part), do: Map.put(link, :set, node[part])

        {part, %{value: resolved, drawn: drawn?(part, kind), chain: chain}}
      end)

    # Every generator called for the element, each with the layer of its contribution: a
    # result that applied nothing set no part, so it is seen here.
    generators =
      for {link, _node} <- links,
          generator <- link.generators,
          do: Map.put(generator, :layer, link.layer)

    {parts, generators}
  end

  defp contribution(nil, _last?, _styles, _declared, _pick, _datum), do: []

  defp contribution({:field, field} = entry, _last?, styles, _declared, pick, datum) do
    case pick.(entry) do
      nil ->
        []

      name ->
        layer = if name in Palette.states(), do: :state, else: :field
        reading = Table.get(datum, field)
        [{link(layer, name, via(styles, name), entry, reading), lay(styles, name, pick)}]
    end
  end

  # A generator entry (§3.13): the style it returned, laid at layer `:generator` — named
  # when the result is a name — or no contribution for a result that applied nothing.
  defp contribution({:generate, _, _} = call, _last?, styles, _declared, pick, _datum) do
    case pick.(call) do
      nil ->
        [{link(:generator, nil, [], nil, nil), %{}}]

      name when is_atom(name) ->
        [{link(:generator, name, via(styles, name), nil, name), lay(styles, name, pick)}]

      style ->
        [{link(:generator, nil, refs(style, styles, []), nil, style), lay(styles, style, pick)}]
    end
  end

  defp contribution(inline, last?, styles, _declared, pick, _datum)
       when is_map(inline) and not is_struct(inline) do
    layer = if last?, do: :local, else: :inline
    via = inline |> Map.get(:extends) |> refs(styles, [])
    [{link(layer, nil, via, nil, nil), lay(styles, inline, pick)}]
  end

  defp contribution(name, _last?, styles, declared, pick, _datum) when is_atom(name) do
    layer =
      cond do
        name in Palette.states() -> :state
        name in declared -> :style
        true -> :palette
      end

    [{link(layer, name, via(styles, name), nil, nil), lay(styles, name, pick)}]
  end

  defp contribution(_other, _last?, _styles, _declared, _pick, _datum), do: []

  defp link(layer, style, via, field, value) do
    %{
      layer: layer,
      container: nil,
      style: style,
      via: via,
      field: field,
      value: value,
      generators: []
    }
  end

  # The memo of every generator the stack reaches for the datum, each called once.
  defp memo(styles, stack, field, datum, frame) do
    picked = for {:field, _} = entry <- List.wrap(stack), into: %{}, do: {entry, field.(entry)}

    keys =
      for {_place, call} <- Generated.reached(styles, stack, picked),
          do: Generated.key(call, datum)

    Generated.memo(frame.generated || Generated.new(), frame.theme, keys)
  end

  # One call's checked result, `nil` for one that applies nothing.
  defp result(frame, place, call, datum, memo) do
    case Generated.checked(place, Map.fetch!(memo, Generated.key(call, datum)), frame) do
      {:ok, value} -> value
      {:error, _reason} -> nil
    end
  end

  # The generators a contribution was computed with: an entry's own, and each color
  # generator in the styles it lays, at its leaf's path.
  defp attributed(link, {:generate, _, _} = call, _styles, gen),
    do: %{link | generators: [attribution(call, :entry, [], gen)]}

  defp attributed(link, {:field, _} = entry, styles, gen) do
    case gen.field.(entry) do
      nil -> link
      name -> %{link | generators: leaf_attributions(styles, name, gen)}
    end
  end

  defp attributed(link, entry, styles, gen),
    do: %{link | generators: leaf_attributions(styles, entry, gen)}

  defp leaf_attributions(styles, entry, gen) do
    for {at, call} <- leaves(styles, entry, [], []), do: attribution(call, :leaf, at, gen)
  end

  defp attribution({:generate, name, _args} = call, place, at, gen) do
    {^name, args} = key = Generated.key(call, gen.datum)
    raw = Map.fetch!(gen.memo, key)

    result =
      case Generated.checked(place, raw, gen.frame) do
        {:ok, value} -> value
        {:error, reason} -> {:fault, reason}
      end

    %{name: name, args: args, at: at, result: result}
  end

  # Every color generator a style entry lays, with its path in the node that holds it:
  # through names, lists and `extends`, as the resolution lays them.
  defp leaves(styles, entries, at, seen) when is_list(entries),
    do: Enum.flat_map(entries, &leaves(styles, &1, at, seen))

  defp leaves(styles, %{} = node, _at, seen) when not is_struct(node) do
    under =
      case Map.fetch(node, :extends) do
        {:ok, parent} -> leaves(styles, parent, [], seen)
        :error -> []
      end

    under ++ calls(Parts.normalize(Map.delete(node, :extends)), [])
  end

  defp leaves(styles, name, _at, seen) when is_atom(name) and name not in [nil, true, false] do
    if name in seen, do: [], else: leaves(styles, Map.get(styles, name), [], [name | seen])
  end

  defp leaves(_styles, _entry, _at, _seen), do: []

  defp calls({:generate, _, _} = call, at),
    do: if(Generated.call?(call), do: [{at, call}], else: [])

  defp calls(%_{}, _at), do: []

  defp calls(map, at) when is_map(map),
    do: Enum.flat_map(map, fn {key, value} -> calls(value, at ++ [key]) end)

  defp calls(_value, _at), do: []

  # Layers 1 to 3 (§3.7, §3.8): each container's part defaults, then its entry for the
  # element's kind — the theme's part defaults are its root, `:theme`.
  defp defaults(containers, kind) do
    entry_kind = if kind in Defaults.kinds(), do: kind

    for {container, what, node} <- Defaults.contributions(containers, entry_kind) do
      layer =
        cond do
          what == :kind -> :kind
          container == :theme -> :theme
          true -> :defaults
        end

      {%{link(layer, nil, [], nil, nil) | container: container}, node}
    end
  end

  # The style laid as the frame lays it, in its parts.
  defp lay(styles, entry, pick), do: Style.compound(styles, entry, pick)

  # The mark's own paint — the theme's series color for its position — under every
  # contribution, where none gives the paint (spec/14 §5.6).
  defp with_paint(links, kind, {:series, _} = series) when kind in @marks do
    key = if kind in @stroked, do: :stroke, else: :fill

    if Enum.any?(links, fn {_link, node} -> paint?(node, key) end),
      do: links,
      else: [{link(:mark, nil, [], nil, nil), %{key => %{type: :solid, color: series}}} | links]
  end

  defp with_paint(links, _kind, _series), do: links

  defp paint?(node, key) do
    case Map.get(node, key) do
      %{type: _} -> true
      %{color: _} -> true
      _other -> false
    end
  end

  # The names a named style reached others through: its `extends` and its lists' names.
  defp via(styles, name), do: styles |> Map.get(name) |> refs(styles, [name])

  defp refs(entries, styles, seen) when is_list(entries),
    do: Enum.flat_map(entries, &refs(&1, styles, seen))

  defp refs(%{extends: parent} = node, styles, seen) when not is_struct(node),
    do: refs(parent, styles, seen)

  defp refs(name, styles, seen) when is_atom(name) and name not in [nil, true, false] do
    if name in seen, do: [], else: [name | via_of(styles, name, [name | seen])]
  end

  defp refs(_entry, _styles, _seen), do: []

  defp via_of(styles, name, seen), do: styles |> Map.get(name) |> refs(styles, seen)

  defp names(styles) do
    Enum.reduce(Map.keys(styles), %{}, fn name, names ->
      names |> Map.put(name, name) |> Map.put(Atom.to_string(name), name)
    end)
  end

  defp drawn?(part, kind) when kind in @marks, do: part not in Parts.undrawn(kind)
  defp drawn?(_part, _kind), do: true
end
