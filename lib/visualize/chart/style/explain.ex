defmodule Visualize.Chart.Style.Explain do
  @moduledoc false
  # Where each part of an element's style came from (spec/14 §17.3, #661, D-172): the
  # stack the element is drawn with, entry by entry, each entry's style laid by the same
  # resolution the frame uses (`Visualize.Chart.Style.compound/3`) and recorded with its
  # layer of the precedence order (§3.7), its name, the names it was reached through and,
  # for a style named by data, the field and its reading.

  alias Visualize.Chart.Style
  alias Visualize.Chart.Style.Parts
  alias Visualize.Data.Table
  alias Visualize.Theme.Palette

  @stroked [:line, :rule]
  @marks Visualize.Chart.Schema.mark_types()

  @typedoc "One contribution to a part."
  @type link :: %{
          layer: :mark | :palette | :style | :field | :state | :inline | :local,
          style: atom() | nil,
          via: [atom()],
          field: {:field, atom()} | nil,
          value: term(),
          set: term()
        }

  @doc false
  # The parts of the style `stack` lays for an element of `kind`, read against `styles`
  # (declared over the palette) where `declared` are the design's own names; `datum` reads
  # the field entries, and `series` is the mark's own paint for its position, or `nil`.
  @spec parts(map(), [atom()], term(), atom(), map() | nil, term()) :: %{atom() => map()}
  def parts(styles, declared, stack, kind, datum, series) do
    names = names(styles)
    pick = fn {:field, field} -> datum && Map.get(names, Table.get(datum, field)) end
    entries = List.wrap(stack)
    last = length(entries) - 1

    links =
      entries
      |> Enum.with_index()
      |> Enum.flat_map(fn {entry, i} ->
        contribution(entry, i == last, styles, declared, pick, datum)
      end)
      |> with_paint(kind, series)

    value = Enum.reduce(links, %{}, fn {_link, node}, acc -> Parts.merge(acc, node) end)

    Map.new(value, fn {part, resolved} ->
      chain =
        for {link, node} <- links, Map.has_key?(node, part), do: Map.put(link, :set, node[part])

      {part, %{value: resolved, drawn: drawn?(part, kind), chain: chain}}
    end)
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

  defp link(layer, style, via, field, value),
    do: %{layer: layer, style: style, via: via, field: field, value: value}

  # The style laid as the frame lays it, in its parts.
  defp lay(styles, entry, pick), do: Style.compound(styles, entry, pick)

  # The mark's own paint — the theme's series colour for its position — under every
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
