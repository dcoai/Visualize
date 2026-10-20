defmodule Visualize.Chart.Migration.Named do
  @moduledoc false
  # A design's names as strings (spec/14 §1.4, §9.4, D-195): the step of the migration's walk
  # that reads an atom in a name position as its string, so Elixir input written with atoms
  # — `%{frames: %{main: …}}`, `{:field, :v}`, `var(:unit)` — is the design JSON reads. It
  # rewrites one key's value, its nested nodes already walked: a name, a list or map of
  # names, a name-keyed map's keys, a reference inside a typed term, and a category value.
  # `Atom.to_string/1` makes no atom.

  alias Visualize.Chart.{Fact, Names, Use, Var, Words}

  # The `:name` positions that hold a library's or a host's vocabulary rather than a name the
  # design declares: a scale's color scheme, a projection's type, and a theme's name and its
  # counterparts. They keep the atom Elixir gave them.
  @vocabulary [
    {:scale, :range},
    {:projection, :type},
    {:design, :theme},
    {:theme, :name},
    {:theme, :dark},
    {:theme, :light}
  ]

  @theme_names [{:design, :theme}, {:theme, :name}, {:theme, :dark}, {:theme, :light}]

  # Maps keyed by a library vocabulary, not by names: a theme's ramps, its palette (which a
  # theme cannot add a name to) and its color table, whose names are the library's or the
  # theme's own, matched by spelling (spec/08 §7.1, §7.7).
  @vocabulary_keyed [{:theme, :ramps}, {:theme, :styles}, {:theme, :colors}]

  # Maps keyed by category values, compared by spelling: a `:choose` mark's cases.
  @category_keyed [{:mark, :cases}]

  @name_types [:name, :field, :channel]
  @unary Visualize.Color.Typed.ops()
  @library_colors Map.new(Visualize.Theme.library_color_names(), &{&1, true})

  @doc false
  @spec named(atom(), term(), term(), term()) :: term()
  # A theme is named by a built-in theme's atom, or by the string of one the host holds
  # (spec/14 §9.4): the codec reads a document's the same way.
  def named(kind, key, _type, v) when {kind, key} in @theme_names and is_atom(v) do
    if v in [nil, true, false] or v in Visualize.Theme.builtins(), do: v, else: Atom.to_string(v)
  end

  def named(kind, key, _type, v) when {kind, key} in @vocabulary and is_atom(v), do: v

  # A word typed in a vocabulary position is the library's atom of that spelling, else the
  # string: a theme the host holds, a scheme the validator refuses.
  def named(kind, key, _type, v) when {kind, key} in @vocabulary and is_binary(v),
    do: Words.word(v)

  def named(kind, key, {:map, t}, map) when is_map(map) and not is_struct(map) do
    Map.new(map, fn {k, e} -> {map_key(kind, key, k), value(t, e)} end)
  end

  def named(_kind, _key, type, v), do: value(type, v)

  defp map_key(kind, key, k) when {kind, key} in @vocabulary_keyed, do: k
  defp map_key(kind, key, k) when {kind, key} in @category_keyed, do: Names.category(k)
  defp map_key(_kind, _key, k), do: Names.name(k)

  @doc false
  # A value of `type` with every name in it a string; its nested nodes are walked already.
  @spec value(term(), term()) :: term()
  def value(_type, %Var{name: name} = var), do: %{var | name: Names.name(name)}

  def value(_type, %Fact{source: s, field: f} = fact),
    do: %{fact | source: Names.name(s), field: Names.name(f)}

  def value(_type, %Use{} = site), do: use_site(site)
  def value(_type, {:field, f}), do: {:field, Names.name(f)}

  # A generator's name is held as its string and found in the registry by spelling.
  def value(_type, {:generate, name, args}) when is_list(args),
    do: {:generate, Names.name(name), Enum.map(args, &value(:term, &1))}

  def value(type, v) when type in @name_types and is_atom(v), do: Names.name(v)
  def value({:ref, _kind}, v) when is_atom(v), do: Names.name(v)
  def value({:list, t}, v) when is_list(v), do: Enum.map(v, &value(t, &1))

  def value({:map, t}, v) when is_map(v) and not is_struct(v),
    do: Map.new(v, fn {k, e} -> {Names.name(k), value(t, e)} end)

  def value({:one_of, types}, v) when is_atom(v) and v not in [nil, true, false] do
    if Enum.any?(types, &named_type?/1) and not Enum.any?(types, &member?(&1, v)),
      do: Names.name(v),
      else: v
  end

  def value({:one_of, types}, v) when is_list(v) do
    case Enum.find(types, &match?({:list, _}, &1)) do
      nil -> v
      list_type -> value(list_type, v)
    end
  end

  def value(:key_order, {:keys, keys}) when is_list(keys),
    do: {:keys, Enum.map(keys, &Names.name/1)}

  def value(:adopted, {:frame, f, s}), do: {:frame, Names.name(f), Names.name(s)}
  def value({:one_of, _types}, {:frame, f, s}), do: {:frame, Names.name(f), Names.name(s)}

  # Any other value of a choice is read by the alternative its shape is: a tuple, or a map
  # (a scale's color map, spec/14 §4.3).
  def value({:one_of, types}, v) when is_tuple(v) or (is_map(v) and not is_struct(v)) do
    case Visualize.Chart.Schema.select(types, v) do
      nil -> v
      type -> value(type, v)
    end
  end

  def value(:anchor, {:axis, s}), do: {:axis, Names.name(s)}
  def value(:anchor, {:data, [x, y]}), do: {:data, [value(:term, x), value(:term, y)]}

  def value(type, {:paint, name}) when type in [:color, :theme_color],
    do: {:paint, Names.name(name)}

  # A color's name is the library's atom — a CSS name, a slot, a role — or the string of a
  # color the theme declares (spec/14 §9.4); a transform's operands are colors too.
  def value(_type, {:color, name}) when is_atom(name) and name not in [nil, true, false],
    do: {:color, color_name(name)}

  def value(type, {op, c, t}) when op in @unary, do: {op, value(type, c), t}

  def value(type, {:blend, list}) when is_list(list),
    do: {:blend, Enum.map(list, &value(type, &1))}

  def value(type, {:contrast, c}) when c != :under, do: {:contrast, value(type, c)}

  # A domain's categories are values matched by spelling; `:auto` is the extent's own word.
  def value(:extent, v) when is_list(v), do: Enum.map(v, &category/1)

  def value(:color_map, map) when is_map(map) and not is_struct(map),
    do: Map.new(map, fn {k, c} -> {Names.category(k), c} end)

  # A term outside any schema is read by the library's words (spec/14 §9.4): an atom the
  # library has no word for is a category value, its string.
  def value(:term, v) when is_list(v), do: Enum.map(v, &value(:term, &1))

  def value(:term, v) when is_map(v) and not is_struct(v),
    do: v |> Words.term() |> Map.new(fn {k, e} -> {k, value(:term, e)} end)

  def value(:term, v), do: Words.term(v)
  def value(_type, v) when is_list(v), do: Enum.map(v, &value(:term, &1))
  def value(_type, v), do: v

  defp color_name(name) when is_map_key(@library_colors, name), do: name
  defp color_name(name), do: name |> Atom.to_string() |> Words.series_slot()

  defp category(:auto), do: :auto
  defp category(%Var{} = var), do: value(:term, var)
  defp category(v), do: Names.category(v)

  defp named_type?(t) when t in @name_types, do: true
  defp named_type?({:ref, _kind}), do: true
  defp named_type?(_t), do: false

  defp member?({:enum, allowed}, v), do: v in allowed
  defp member?(_t, _v), do: false

  # A use site's key and the variables it binds are names (spec/14 §19.3); its local and its
  # mask are its fragment's, read where the fragment is composed.
  defp use_site(%Use{key: key, vars: vars, mask: mask, local: local} = site) do
    vars =
      if is_map(vars),
        do: Map.new(vars, fn {k, v} -> {Names.name(k), value(:term, v)} end),
        else: vars

    # A mask's paths and a local's keys are read by the library's words, as the codec reads
    # them: a schema key is its atom and a name its string.
    mask = if is_list(mask), do: Words.term(mask), else: mask
    local = if is_map(local), do: value(:term, local), else: local

    %{site | key: Names.name(key), vars: vars, mask: mask, local: local}
  end
end
