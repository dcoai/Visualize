defmodule Visualize.Theme.Palette do
  @moduledoc false
  # The style palette of a theme (spec/08 §7.7, D-171): its fixed names in four groups, the
  # built-in entries every built-in theme shares, and the contracts an entry holds. `check/1`
  # answers the first entry that breaks its contract, with a message naming the term it
  # breaks, or `:ok`; `violations/1` answers every one.

  @roles [:good, :warning, :bad, :info, :neutral]
  @states [:hover, :focused, :selected, :active, :disabled, :muted, :emphasis, :breakpoint]
  @furniture [:axis, :grid, :label, :title, :caption, :value, :annotation]
  @text_furniture @furniture -- [:grid]

  # The keys that carry hue: everything else an entry says is visible without colour.
  @hue_keys [:fill, :stroke]
  # Where a status role stands on the status ramp, its other spelling (spec/08 §7.3).
  @status_positions %{good: 0, warning: 0.5, bad: 1}
  @size_slots [:font_size, :label_size, :title_size]

  # The ten style series: seven symbols against five dashes, so no two share both and every
  # neighbour, the last beside the first included, differs in its symbol.
  @symbols [:circle, :square, :triangle, :diamond, :cross, :star, :wye]
  @dashes [nil, "8 3", "3 3", "8 3 3 3", "1 3"]

  @series (for k <- 1..10 do
             entry = %{
               fill: {:series, k},
               stroke: {:series, k},
               stroke_width: 1.5,
               symbol: Enum.at(@symbols, rem(k - 1, length(@symbols)))
             }

             dash = Enum.at(@dashes, rem(k - 1, length(@dashes)))
             {:"style_#{k}", if(dash, do: Map.put(entry, :stroke_dasharray, dash), else: entry)}
           end)

  @label %{fill: :text, font_family: :font_family, font_size: :label_size}

  @builtin Map.new(
             @series ++
               Enum.map(@roles, fn role ->
                 {role, %{fill: role, stroke: role, stroke_dasharray: :cue, symbol: :cue}}
               end) ++
               [
                 hover: %{stroke: :text, stroke_width: 2},
                 focused: %{stroke: :text, stroke_width: 2, stroke_dasharray: "4 2"},
                 selected: %{stroke: :text, stroke_width: 2, stroke_style: :outside},
                 active: %{stroke: :text, stroke_width: 3},
                 disabled: %{opacity: 0.4, stroke_dasharray: "2 2"},
                 # The board's dim of today (spec/15 §13.2), so a muted row looks as it did.
                 muted: %{opacity: 0.25},
                 emphasis: %{stroke_width: 3, font_weight: :bold},
                 breakpoint: %{stroke: :bad, stroke_width: 2, stroke_dasharray: "6 2 2 2"},
                 # The four built-in styles of spec/14 §3.3, exactly as they always were.
                 axis: %{
                   stroke: :axis,
                   fill: :text,
                   font_family: :font_family,
                   font_size: :font_size
                 },
                 grid: %{stroke: :grid},
                 label: @label,
                 title: Map.merge(@label, %{font_size: :title_size, font_weight: :bold}),
                 caption: %{
                   fill: :text,
                   font_family: :font_family,
                   font_size: :font_size,
                   font_style: :italic
                 },
                 value: %{
                   fill: :text,
                   font_family: :font_family,
                   font_size: :title_size,
                   font_weight: :medium
                 },
                 annotation: %{fill: :text, font_family: :font_family, font_size: :font_size}
               ]
           )

  @doc false
  # The palette every built-in theme defines (spec/08 §7.7).
  @spec builtin() :: %{atom() => map()}
  def builtin, do: @builtin

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
  # Every name of the palette whose style series is `series`, in the order of §7.7.
  @spec names([atom()]) :: [atom()]
  def names(series), do: series ++ @roles ++ @states ++ @furniture

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
    own = own_series(styles)
    known = names(own)

    entries =
      for name <- known,
          {:ok, entry} <- [Map.fetch(styles, name)],
          {:error, message} <- [entry(name, entry)],
          do: {{:style, name}, message}

    unknown =
      for name <- styles |> Map.keys() |> Enum.reject(&(&1 in known)) |> Enum.sort(),
          do: {{:style, name}, unknown(name, own)}

    entries ++ neighbours(styles, own) ++ unknown
  end

  # -- one entry ------------------------------------------------------------------------

  defp entry(_name, entry) when not is_map(entry) or is_struct(entry),
    do: {:error, "an entry is a style node, a map of style keys, got #{inspect(entry)}"}

  defp entry(_name, %{extends: parent}),
    do:
      {:error, "a palette entry is flat and may not use extends, got extends: #{inspect(parent)}"}

  defp entry(name, entry) do
    with :ok <- cues(name, entry), do: group(name, entry)
  end

  defp cues(name, entry) do
    case Enum.find(Enum.sort(entry), fn {_key, value} -> value == :cue end) do
      nil ->
        :ok

      {key, :cue} when name in @roles and key in [:stroke_dasharray, :symbol] ->
        :ok

      {key, :cue} when name in @roles ->
        {:error,
         ":cue is a role's dash or glyph, only on stroke_dasharray or symbol; got #{key}: :cue"}

      {key, :cue} ->
        {:error,
         ":cue is a role's dash or glyph, and #{inspect(name)} is not a role; got #{key}: :cue"}
    end
  end

  defp group(role, entry) when role in @roles do
    Enum.find_value([:fill, :stroke], :ok, fn key ->
      case Map.fetch(entry, key) do
        :error ->
          nil

        {:ok, value} ->
          if own_role?(role, value),
            do: nil,
            else:
              {:error,
               "a role style paints with its own role, so #{key} must be #{inspect(role)} " <>
                 "or absent; got #{inspect(value)}"}
      end
    end)
  end

  defp group(state, entry) when state in @states do
    if Enum.any?(entry, &non_hue_change?/1),
      do: :ok,
      else:
        {:error,
         "a state style must read without hue, changing at least one of stroke_width, " <>
           "stroke_style (an outline), opacity, fill_opacity, stroke_opacity, " <>
           "stroke_dasharray or effect; got #{inspect(entry)}"}
  end

  defp group(:grid, entry) do
    case Map.get(entry, :stroke) do
      value when value in [nil, :none, false, true] ->
        {:error,
         "the grid must resolve a stroke, a colour other than :none; got #{inspect(value)}"}

      _colour ->
        :ok
    end
  end

  defp group(text, entry) when text in @text_furniture do
    family = Map.get(entry, :font_family)
    size = Map.get(entry, :font_size)

    cond do
      not family?(family) ->
        {:error,
         "a text style must resolve a font family, a string or :font_family; got " <>
           "font_family: #{inspect(family)}"}

      not size?(size) ->
        {:error,
         "a text style must resolve a size, a positive number or one of " <>
           "#{Enum.map_join(@size_slots, ", ", &inspect/1)}; got font_size: #{inspect(size)}"}

      true ->
        :ok
    end
  end

  # A style series' contract is between neighbours, so it is checked over the whole series.
  defp group(_series, _entry), do: :ok

  defp own_role?(role, role), do: true

  defp own_role?(role, {:ramp, :status, t}) when is_number(t),
    do: Map.get(@status_positions, role) == t

  defp own_role?(_role, _value), do: false

  # A key that changes how an object looks without hue: present, and not the value that
  # would leave the object as it is.
  defp non_hue_change?({:stroke_width, value}), do: value != nil
  defp non_hue_change?({:stroke_style, value}), do: value not in [nil, :single]
  defp non_hue_change?({:effect, value}), do: value not in [nil, :none]

  defp non_hue_change?({key, value}) when key in [:opacity, :fill_opacity, :stroke_opacity],
    do: value != nil and value != 1

  defp non_hue_change?({:stroke_dasharray, value}), do: value not in [nil, "", []]
  defp non_hue_change?(_other), do: false

  defp family?(family) when is_binary(family), do: String.trim(family) != ""
  defp family?(family), do: family == :font_family

  defp size?(size) when is_number(size), do: size > 0
  defp size?(size), do: size in @size_slots

  # -- the series -----------------------------------------------------------------------

  # Each style series entry beside the next, the last beside the first, since `{:style, i}`
  # cycles: they differ in a key besides fill and stroke. One entry is its own neighbour.
  defp neighbours(styles, own) do
    pairs =
      case own do
        [] -> []
        [one] -> [{one, one}]
        _ -> Enum.zip(own, tl(own) ++ [hd(own)])
      end

    for {a, b} <- pairs,
        entry_a = Map.fetch!(styles, a),
        entry_b = Map.fetch!(styles, b),
        is_map(entry_a) and is_map(entry_b),
        Map.drop(entry_a, @hue_keys) == Map.drop(entry_b, @hue_keys),
        do: {{:style, b}, neighbour(a, b)}
  end

  defp neighbour(a, a),
    do:
      "a style series of one entry has itself for a neighbour and keeps no categories apart " <>
        "without hue; give the theme at least two"

  defp neighbour(a, b),
    do:
      "neighbouring style series must differ in a key besides fill and stroke (a dash, a " <>
        "symbol, a weight), but #{inspect(a)} and #{inspect(b)} differ only in hue"

  defp unknown(name, own) do
    case series_index(name) do
      k when is_integer(k) and k >= 1 ->
        "the style series runs :style_1 to :style_n with no gap, and " <>
          "#{inspect(series_name(length(own) + 1))} is missing below #{inspect(name)}"

      _ ->
        "is not a name of the palette; a theme cannot add one. The names are the style " <>
          "series :style_1 … :style_n, the roles #{list(@roles)}, the states #{list(@states)} " <>
          "and the furniture #{list(@furniture)}"
    end
  end

  defp series_index(name) when is_atom(name) do
    with "style_" <> rest <- Atom.to_string(name),
         {k, ""} <- Integer.parse(rest) do
      k
    else
      _ -> nil
    end
  end

  defp series_index(_name), do: nil

  defp list(atoms), do: Enum.map_join(atoms, ", ", &inspect/1)
end
