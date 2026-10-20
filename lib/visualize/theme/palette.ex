defmodule Visualize.Theme.Palette do
  @moduledoc false

  import Visualize.Chart.Names, only: [is_name: 1]
  # The style palette of a theme (spec/08 §7.7, D-171, D-172): its fixed names in five
  # groups, the built-in entries every built-in theme shares, written in compound parts, and
  # the contracts an entry holds. `check/1` answers the first entry that breaks its
  # contract, with a message naming the term it breaks, or `:ok`; `violations/1` answers
  # every one.

  alias Visualize.Chart.Style.Parts

  @roles [:good, :warning, :bad, :info, :neutral]
  @states [:hover, :focused, :selected, :active, :disabled, :muted, :emphasis, :breakpoint]
  @furniture [:axis, :grid, :label, :title, :caption, :value, :annotation]
  @modifiers [:bold, :italic, :thin, :thick, :dashed, :dotted, :outline]
  @text_furniture @furniture -- [:grid]

  # The parts that carry hue: a paint's color, which everything else an entry says is
  # visible without.
  @paints [:fill, :stroke]
  @size_slots [:font_size, :label_size, :title_size]

  # The ten style series: seven symbols against five dashes, so no two share both and every
  # neighbor, the last beside the first included, differs in its symbol.
  @symbols [:circle, :square, :triangle, :diamond, :cross, :star, :wye]
  @dashes [nil, "8 3", "3 3", "8 3 3 3", "1 3"]

  @series (for k <- 1..10 do
             dash = Enum.at(@dashes, rem(k - 1, length(@dashes)))
             stroke = %{type: :solid, color: {:series, k}, width: 1.5}

             {:"style_#{k}",
              %{
                fill: %{type: :solid, color: {:series, k}},
                stroke: if(dash, do: Map.put(stroke, :dash, dash), else: stroke),
                marker: %{shape: Enum.at(@symbols, rem(k - 1, length(@symbols)))}
              }}
           end)

  @label %{
    fill: %{type: :solid, color: {:color, :text}},
    font: %{family: :font_family, size: :label_size}
  }

  @builtin Map.new(
             @series ++
               Enum.map(@roles, fn role ->
                 {role,
                  %{
                    fill: %{type: :solid, color: {:color, role}},
                    stroke: %{type: :solid, color: {:color, role}, dash: :cue},
                    marker: %{shape: :cue}
                  }}
               end) ++
               [
                 hover: %{stroke: %{type: :solid, color: {:color, :text}, width: 2}},
                 focused: %{
                   stroke: %{type: :solid, color: {:color, :text}, width: 2, dash: "4 2"}
                 },
                 # Heavier only (#638): no color of its own to paint over a stroked mark's.
                 selected: %{stroke: %{width: 2}},
                 active: %{stroke: %{type: :solid, color: {:color, :text}, width: 3}},
                 disabled: %{opacity: 0.4, stroke: %{dash: "2 2"}},
                 # The board's dim of today (spec/15 §13.2), so a muted row looks as it did.
                 muted: %{opacity: 0.25},
                 emphasis: %{stroke: %{width: 3}, font: %{weight: :bold}},
                 breakpoint: %{
                   stroke: %{type: :solid, color: {:color, :bad}, width: 2, dash: "6 2 2 2"}
                 },
                 # The four built-in styles of spec/14 §3.3, exactly as they always were.
                 axis: %{
                   stroke: %{type: :solid, color: {:color, :axis}},
                   fill: %{type: :solid, color: {:color, :text}},
                   font: %{family: :font_family, size: :font_size}
                 },
                 grid: %{stroke: %{type: :solid, color: {:color, :grid}}},
                 label: @label,
                 title: %{
                   @label
                   | font: %{family: :font_family, size: :title_size, weight: :bold}
                 },
                 caption: %{
                   fill: %{type: :solid, color: {:color, :text}},
                   font: %{family: :font_family, size: :font_size, style: :italic}
                 },
                 value: %{
                   fill: %{type: :solid, color: {:color, :text}},
                   font: %{family: :font_family, size: :title_size, weight: :medium}
                 },
                 annotation: %{
                   fill: %{type: :solid, color: {:color, :text}},
                   font: %{family: :font_family, size: :font_size}
                 },
                 # The modifiers (D-172): each changes one thing, to be stacked on a look —
                 # `[:bad, :outline]` is the bad look's outline alone.
                 bold: %{font: %{weight: :bold}},
                 italic: %{font: %{style: :italic}},
                 thin: %{stroke: %{width: 1}},
                 thick: %{stroke: %{width: 3}},
                 dashed: %{stroke: %{dash: "6 3"}},
                 dotted: %{stroke: %{dash: "1 3", cap: :round}},
                 outline: %{fill: %{type: :none}}
               ]
           )

  @doc false
  # The palette every built-in theme defines (spec/08 §7.7).
  @spec builtin() :: %{atom() => map()}
  def builtin, do: @builtin

  # The print theme's role fills (spec/08 §7.2, #673): hatches of the role's color, so a
  # role keeps its meaning on a grayscale copy; `:neutral` stays solid.
  @hatches %{
    good: %{pattern: :lines, angle: 45},
    warning: %{pattern: :lines, angle: 135},
    bad: %{pattern: :crosshatch, angle: 45},
    info: %{pattern: :dots, angle: 45}
  }

  @doc false
  # The palette of the print theme: the built-in one with its role fills hatched.
  @spec print() :: %{atom() => map()}
  def print do
    Enum.reduce(@hatches, @builtin, fn {role, hatch}, palette ->
      fill = Map.merge(%{type: :hatch, color: {:color, role}, spacing: 6, width: 1}, hatch)
      put_in(palette, [role, :fill], fill)
    end)
  end

  @doc false
  @spec roles() :: [atom(), ...]
  def roles, do: @roles

  @doc false
  @spec states() :: [atom(), ...]
  def states, do: @states

  @doc false
  @spec furniture() :: [atom(), ...]
  def furniture, do: @furniture

  @doc false
  @spec modifiers() :: [atom(), ...]
  def modifiers, do: @modifiers

  @doc false
  # The entry `name` of a palette as one style node in its parts (spec/08 §7.7, #658): a
  # node as it is, a name or a list of palette names and nodes stacked left to right by the
  # merge rule — each name the palette's own entry, else the built-in one. `{:error,
  # message}` for a name the palette does not have, a list that reaches itself, or an
  # element that is no style.
  @spec compose(map(), atom()) :: {:ok, map()} | {:error, String.t()}
  def compose(styles, name), do: compose(styles, name, [])

  defp compose(styles, name, seen) do
    entry = Map.get(styles, name) || Map.get(@builtin, name)

    cond do
      name in seen -> {:error, "a list that reaches itself through #{inspect(name)}"}
      entry == nil -> {:error, "#{inspect(name)} in a list is not a name of the palette"}
      true -> layer(styles, entry, [name | seen])
    end
  end

  defp layer(styles, entries, seen) when is_list(entries) do
    Enum.reduce_while(entries, {:ok, %{}}, fn entry, {:ok, node} ->
      case layer(styles, entry, seen) do
        {:ok, laid} -> {:cont, {:ok, Parts.merge(node, laid)}}
        error -> {:halt, error}
      end
    end)
  end

  # A document's entry names a palette style by its string (spec/14 §9.4, D-195): the
  # palette's names are atoms, found by spelling.
  defp layer(styles, name, seen) when is_binary(name) do
    found =
      Enum.find(Map.keys(styles) ++ names(series(styles)), fn key ->
        is_atom(key) and Atom.to_string(key) == name
      end)

    compose(styles, found || name, seen)
  end

  defp layer(styles, name, seen) when is_name(name) and name not in [nil, true, false],
    do: compose(styles, name, seen)

  defp layer(_styles, node, _seen) when is_map(node) and not is_struct(node),
    do: {:ok, Parts.normalize(node)}

  defp layer(_styles, other, _seen),
    do: {:error, "an entry is a style node, a map of style keys, got #{inspect(other)}"}

  @doc false
  # The style series names a palette holds, `:style_1` up to the first gap, in order; the
  # default palette's when it holds none (spec/08 §7.7, Fallback).
  @spec series(map()) :: [atom()]
  def series(styles) do
    case own_series(styles) do
      [] -> own_series(@builtin)
      names -> names
    end
  end

  defp own_series(styles) do
    1
    |> Stream.iterate(&(&1 + 1))
    |> Stream.map(&series_name/1)
    |> Enum.take_while(&Map.has_key?(styles, &1))
  end

  @doc false
  @spec series_name(pos_integer()) :: atom()
  def series_name(k), do: :"style_#{k}"

  @doc false
  # The palette's names but its series, which a theme cannot add to (spec/08 §7.7).
  @spec fixed_names() :: [atom(), ...]
  def fixed_names, do: @roles ++ @states ++ @furniture ++ @modifiers

  @doc false
  # Every name of the palette whose style series is `series`, in the order of §7.7.
  @spec names([atom()]) :: [atom()]
  def names(series), do: series ++ @roles ++ @states ++ @furniture ++ @modifiers

  @doc false
  # `:ok`, or `{:error, {:style, name}, message}` for the first entry that breaks its
  # contract, in the order of `names/1` and then any name the palette does not know.
  @spec check(map()) :: :ok | {:error, {:style, atom()}, String.t()}
  def check(styles) when is_map(styles) do
    case violations(styles) do
      [] -> :ok
      [{subject, message} | _] -> {:error, subject, message}
    end
  end

  @doc false
  # Every entry that breaks its contract, `{{:style, name}, message}`, in `check/1`'s order.
  @spec violations(map()) :: [{{:style, atom()}, String.t()}]
  def violations(styles) when is_map(styles) do
    styles = Map.new(styles, fn {name, entry} -> {name, Parts.normalize(entry)} end)
    own = own_series(styles)
    known = names(own)

    entries =
      for name <- known,
          {:ok, entry} <- [Map.fetch(styles, name)],
          {:error, message} <- [entry(name, entry, styles)],
          do: {{:style, name}, message}

    unknown =
      for name <- styles |> Map.keys() |> Enum.reject(&(&1 in known)) |> Enum.sort(),
          do: {{:style, name}, unknown(name, own)}

    entries ++ neighbors(styles, own) ++ unknown
  end

  # -- one entry ------------------------------------------------------------------------

  # A list — or a name — is held to the contracts by what it stacks into (#658); a node
  # in it, as a node alone, may not use `extends`.
  defp entry(name, entry, styles) when is_list(entry) or (is_atom(entry) and entry != nil) do
    with :ok <- no_extends(List.wrap(entry)),
         {:ok, node} <- layer(styles, entry, [name]) do
      entry(name, node, styles)
    end
  end

  defp entry(_name, entry, _styles) when not is_map(entry) or is_struct(entry),
    do: {:error, "an entry is a style node, a map of style keys, got #{inspect(entry)}"}

  defp entry(_name, %{extends: parent}, _styles),
    do:
      {:error, "a palette entry is flat and may not use extends, got extends: #{inspect(parent)}"}

  defp entry(name, entry, _styles) do
    with :ok <- cues(name, entry), do: group(name, entry)
  end

  defp no_extends(entries) do
    case Enum.find(entries, &match?(%{extends: _}, &1)) do
      nil -> :ok
      %{extends: parent} -> entry(nil, %{extends: parent}, %{})
    end
  end

  # Where a role's cue may stand: its stroke's dash and its marker's shape.
  @cue_keys [{:stroke, :dash}, {:marker, :shape}]

  defp cues(name, entry) do
    found =
      for {part, map} <- Enum.sort(entry),
          is_map(map) and not is_struct(map),
          {key, :cue} <- Enum.sort(map),
          do: {part, key}

    case found do
      [] ->
        :ok

      [at | _] ->
        cond do
          name in @roles and Enum.all?(found, &(&1 in @cue_keys)) ->
            :ok

          name in @roles ->
            {part, key} = Enum.find(found, &(&1 not in @cue_keys))

            {:error,
             ":cue is a role's dash or glyph, only on stroke.dash or marker.shape; got " <>
               "#{part}.#{key}: :cue"}

          true ->
            {part, key} = at

            {:error,
             ":cue is a role's dash or glyph, and #{inspect(name)} is not a role; got " <>
               "#{part}.#{key}: :cue"}
        end
    end
  end

  # The roles' contracts are held by the five as a set, against the theme's colors and
  # background, in `Visualize.Theme.Roles` (#666).
  defp group(role, _entry) when role in @roles, do: :ok

  defp group(state, entry) when state in @states do
    if non_hue_change?(entry),
      do: :ok,
      else:
        {:error,
         "a state style must read without hue, changing at least one of stroke.width, " <>
           "stroke.placement (an outline), opacity, fill.opacity, stroke.opacity, " <>
           "stroke.dash or effect; got #{inspect(entry)}"}
  end

  defp group(:grid, entry) do
    case color(entry, :stroke) do
      value when value in [nil, :none, false, true] ->
        {:error,
         "the grid must resolve a stroke, a color other than :none; got stroke.color: " <>
           inspect(value)}

      _color ->
        :ok
    end
  end

  defp group(text, entry) when text in @text_furniture do
    family = get_in_part(entry, :font, :family)
    size = get_in_part(entry, :font, :size)

    cond do
      not family?(family) ->
        {:error,
         "a text style must resolve a font family, a string or :font_family; got " <>
           "font.family: #{inspect(family)}"}

      not size?(size) ->
        {:error,
         "a text style must resolve a size, a positive number or one of " <>
           "#{Enum.map_join(@size_slots, ", ", &inspect/1)}; got font.size: #{inspect(size)}"}

      true ->
        :ok
    end
  end

  # A modifier changes one thing (D-172), so a stack of them composes without surprise.
  defp group(modifier, entry) when modifier in @modifiers do
    case Map.keys(entry) do
      [_one] ->
        :ok

      keys ->
        {:error,
         "a modifier changes one thing, a single part or key; got " <>
           "#{Enum.map_join(Enum.sort(keys), ", ", &to_string/1)}"}
    end
  end

  # A style series' contract is between neighbors, so it is checked over the whole series.
  defp group(_series, _entry), do: :ok

  # The color a paint part gives, `nil` when it gives none.
  defp color(entry, part) do
    case Map.get(entry, part) do
      %{type: :none} -> :none
      %{color: color} -> color
      _none -> nil
    end
  end

  defp get_in_part(entry, part, key) do
    case Map.get(entry, part) do
      map when is_map(map) and not is_struct(map) -> Map.get(map, key)
      _other -> nil
    end
  end

  # A part that changes how an object looks without hue: present, and not the value that
  # would leave the object as it is.
  defp non_hue_change?(entry) do
    changed?(get_in_part(entry, :stroke, :width), &(&1 != nil)) or
      changed?(get_in_part(entry, :stroke, :placement), &(&1 not in [nil, :center])) or
      changed?(get_in_part(entry, :stroke, :dash), &(&1 not in [nil, "", []])) or
      Enum.any?(
        [
          Map.get(entry, :opacity),
          get_in_part(entry, :fill, :opacity),
          get_in_part(entry, :stroke, :opacity)
        ],
        &(&1 != nil and &1 != 1)
      ) or
      changed?(get_in_part(entry, :effect, :type), &(&1 not in [nil, :none]))
  end

  defp changed?(value, test), do: test.(value)

  defp family?(family) when is_binary(family), do: String.trim(family) != ""
  defp family?(family), do: family == :font_family

  defp size?(size) when is_number(size), do: size > 0
  defp size?(size), do: size in @size_slots

  # -- the series -----------------------------------------------------------------------

  # Each style series entry beside the next, the last beside the first, since `{:style, i}`
  # cycles: they differ in something besides the colors of their fill and stroke. One
  # entry is its own neighbor.
  defp neighbors(styles, own) do
    pairs =
      case own do
        [] -> []
        [one] -> [{one, one}]
        _ -> Enum.zip(own, tl(own) ++ [hd(own)])
      end

    for {a, b} <- pairs,
        {:ok, entry_a} <- [compose(styles, a)],
        {:ok, entry_b} <- [compose(styles, b)],
        hueless(entry_a) == hueless(entry_b),
        do: {{:style, b}, neighbor(a, b)}
  end

  # An entry with the colors of its paints taken out: what it says without hue.
  defp hueless(entry) do
    Map.new(entry, fn
      {part, %{} = paint} when part in @paints and not is_struct(paint) ->
        {part, Map.delete(paint, :color)}

      other ->
        other
    end)
  end

  defp neighbor(a, a),
    do:
      "a style series of one entry has itself for a neighbor and keeps no categories apart " <>
        "without hue; give the theme at least two"

  defp neighbor(a, b),
    do:
      "neighboring style series must differ in something besides the colors of fill and " <>
        "stroke (a dash, a marker, a weight), but #{inspect(a)} and #{inspect(b)} differ " <>
        "only in hue"

  defp unknown(name, own) do
    case series_index(name) do
      k when is_integer(k) and k >= 1 ->
        "the style series runs :style_1 to :style_n with no gap, and " <>
          "#{inspect(series_name(length(own) + 1))} is missing below #{inspect(name)}"

      _ ->
        "is not a name of the palette; a theme cannot add one. The names are the style " <>
          "series :style_1 … :style_n, the roles #{list(@roles)}, the states #{list(@states)}, " <>
          "the furniture #{list(@furniture)} and the modifiers #{list(@modifiers)}"
    end
  end

  defp series_index(name) when is_atom(name) or is_binary(name) do
    with "style_" <> rest <- to_string(name),
         {k, ""} <- Integer.parse(rest) do
      k
    else
      _ -> nil
    end
  end

  defp series_index(_name), do: nil

  defp list(atoms), do: Enum.map_join(atoms, ", ", &inspect/1)
end
