defmodule Visualize.Chart.Codec do
  @moduledoc false
  # The JSON form of a design (spec/14 §11): a schema-driven walk in both directions.
  # `encode/1` turns a validated design map into a term Jason writes; `decode/1` turns
  # the term Jason read into a design map for the validator, never failing on a wrong
  # shape — a value the schema cannot place is passed through for the validator to name.
  #
  # A struct is a leaf in both directions (spec/14 §1.4, D-92): a `%Var{}` is written as
  # its tagged term and read back as itself, and no map clause on either side descends
  # into one, so the walk cannot rebuild a struct as a plain map or a map as a struct.

  alias Visualize.Chart.Codec.Tags
  alias Visualize.Chart.{Fact, Fragment, Limits, Migration, Schema, Use, Var, Words}
  alias Visualize.Chart.Validator.Types
  require Tags
  alias Visualize.{Theme, Vocabulary}

  @fixed_slots Theme.default() |> Theme.slots() |> Enum.reject(&(&1 in [:series_1]))
  # A color name read from a document is made an atom only when it is plain words.
  @color_word ~r/^[a-z][a-z0-9_]*$/
  @unary Visualize.Color.Typed.ops()

  # The closed vocabularies a document's strings are looked up in, never made atoms of
  # (spec/14 §9.4, D-195): every key of the schema, of an earlier version and of a fragment's
  # singular wrapper, the theme's
  # fixed slots, a text's anchors, a frame's points, a fact's attributes, the units, the
  # ramps, a fragment's kinds and the color transforms.
  @fixed_slot_names Vocabulary.table(@fixed_slots)
  @anchors Vocabulary.table(Types.anchors())
  @frame_points Vocabulary.table(Types.frame_points())
  @attributes Vocabulary.table(Visualize.Data.Schema.attributes())
  @units Vocabulary.table(Visualize.Units.units())
  @ramps Vocabulary.table(Theme.ramp_names())
  @kinds Vocabulary.table(Fragment.kinds())
  @unary_ops Vocabulary.table(@unary)
  # A color name the library gives is its atom; any other is a name the theme declares, a
  # string (spec/14 §9.4).
  @color_names Vocabulary.table(Theme.library_color_names())
  @theme_names Vocabulary.table(Theme.builtins())
  @palette_names Vocabulary.table(Visualize.Theme.Palette.fixed_names())
  @schemes Vocabulary.table(Visualize.Scale.Color.schemes())
  @projections Vocabulary.table(Visualize.Geo.Projection.types())
  # A series slot is read up to the default `items` bound: a theme holds no more series than
  # a list holds entries, so `series_1` … `series_100000` is the whole set (class (d)).
  @series_bound Limits.defaults().items

  # -- encode ---------------------------------------------------------------------------

  @doc false
  def encode(map), do: node(:design, map)

  defp node(kind, map) do
    Map.new(map, fn {k, v} ->
      case type_of(kind, k, flat?(kind, k, not part?(v))) do
        nil -> {key(k), term(v)}
        type -> {key(k), value(type, v)}
      end
    end)
  end

  # The type a key is written and read by: the schema's, or — for a style's flat keys of an
  # earlier version, and `fill`, `stroke`, `curve` and `effect` written as a shorthand
  # rather than a part — the flat type it had (spec/14 §9, D-172), so a fragment the
  # builder writes in them round-trips and a version 2 document reads typed.
  defp type_of(kind, k, true), do: Migration.legacy_type(kind, k) || schema_type(kind, k)
  defp type_of(kind, k, false), do: schema_type(kind, k) || Migration.legacy_type(kind, k)

  defp schema_type(kind, k) do
    case Schema.key(kind, k) do
      nil -> nil
      spec -> spec.type
    end
  end

  defp flat?(:style, k, shorthand?) when k in [:fill, :stroke, :curve, :effect], do: shorthand?
  defp flat?(_kind, _k, _shorthand?), do: false

  defp part?(v), do: is_map(v) and not is_struct(v)

  # A name as it is written: an atom's spelling, a string as it is (spec/14 §1.4).
  defguardp is_name(v) when is_binary(v) or (is_atom(v) and v not in [nil, true, false])

  defp spell(v) when is_atom(v), do: Atom.to_string(v)
  defp spell(v) when is_binary(v), do: v

  # A key that starts with `$` is written with one more, so data never spells a tag (D-182).
  defp key(k) when is_atom(k), do: k |> Atom.to_string() |> Tags.escape()
  defp key(k), do: k |> to_string() |> Tags.escape()

  defp value(_type, %Var{name: name}), do: Tags.tag("$var", spell(name))
  defp value(_type, %Fact{} = fact), do: term(fact)
  defp value(_type, {:field, f}) when is_name(f), do: Tags.tag("$field", spell(f))

  # A generator call (spec/14 §3.13, §11.2, #654): its name, then its arguments as terms.
  defp value(_type, {:generate, name, args}) when is_name(name) and is_list(args),
    do: Tags.tag("$generate", [spell(name), Enum.map(args, &term/1)])

  defp value(:color, {:paint, name}) when is_name(name),
    do: Tags.tag("$paint", spell(name))

  # A ramp position, and a whole ramp as a color scale's range (spec/14 §11.2, #533).
  defp value(:color, {:ramp, name, t}) when is_atom(name) and is_number(t),
    do: Tags.tag("$ramp", [Atom.to_string(name), t])

  defp value(:ramp, {:ramp, name}) when is_atom(name), do: Tags.tag("$ramp", Atom.to_string(name))

  # A typed color (spec/14 §11.2, #664): a name, a transform with its color first, a blend's
  # list, the contrast ink over a color or over what is under.
  defp value(:color, {:color, name}) when is_name(name),
    do: Tags.tag("$color", spell(name))

  defp value(:color, {op, c, t}) when op in @unary and is_number(t),
    do: Tags.tag("$#{op}", [value(:color, c), t])

  defp value(:color, {:blend, list}) when is_list(list),
    do: Tags.tag("$blend", Enum.map(list, &value(:color, &1)))

  # A theme's pinned steps, `[step, color]` pairs in step order (spec/14 §11.2, #667).
  defp value(:theme_color, steps) when is_map(steps) and not is_struct(steps),
    do:
      Tags.tag(
        "$steps",
        steps |> Enum.sort() |> Enum.map(fn {n, c} -> [n, value(:color, c)] end)
      )

  defp value(:theme_color, v), do: value(:color, v)

  # A theme's counterpart (spec/08 §7.3, #668): its name, or `null` for none.
  defp value(:counterpart, nil), do: nil
  defp value(:counterpart, name) when is_name(name), do: spell(name)

  defp value(:color, {:contrast, :under}), do: Tags.tag("$contrast", "under")
  defp value(:color, {:contrast, c}), do: Tags.tag("$contrast", value(:color, c))

  # A map of colors as `[category, color]` pairs in the categories' term order (spec/14
  # §11.2, D-143): an object's keys are strings, and a category need not be one.
  defp value(:color_map, map) when is_map(map) and not is_struct(map) do
    pairs =
      map
      |> Enum.sort_by(fn {category, _color} -> category end)
      |> Enum.map(fn {category, color} -> [term(category), value(:color, color)] end)

    Tags.tag("$colors", pairs)
  end

  defp value({:node, kind}, v) when is_map(v) and not is_struct(v), do: node(kind, v)
  defp value({:list, t}, v) when is_list(v), do: Enum.map(v, &value(t, &1))

  defp value({:map, t}, v) when is_map(v) and not is_struct(v) do
    Map.new(v, fn {k, e} -> {key(k), value(t, e)} end)
  end

  defp value({:one_of, types}, v) do
    case Schema.select(types, v) do
      nil -> term(v)
      t -> value(t, v)
    end
  end

  defp value(type, v) when type in [:name, :field, :color, :font] and is_atom(v),
    do: Atom.to_string(v)

  defp value({:enum, _}, v) when is_atom(v), do: Atom.to_string(v)
  defp value({:ref, _}, v) when is_name(v), do: spell(v)
  defp value({:ref, _}, {kind, n} = id) when is_atom(kind) and is_integer(n), do: term(id)
  defp value(:slot, v) when is_atom(v), do: Atom.to_string(v)
  defp value(:slot, {:series, i}), do: Tags.tag("$series", i)
  defp value(type, v) when type in [:size, :channel] and is_atom(v), do: Atom.to_string(v)

  # A unit value (spec/14 §3.9, §11.2, #651): the number and the unit's name.
  defp value(type, {n, unit}) when type in [:size, :length] and is_number(n) and is_atom(unit),
    do: Tags.tag("$unit", [n, Atom.to_string(unit)])

  # A channel at its scale's own end (spec/14 §5.2, §11.2, #554).
  defp value(:channel, {:scale, which}) when which in [:min, :max],
    do: Tags.tag("$scale", Atom.to_string(which))

  defp value(type, {:series, i}) when type in [:color, :size, :font], do: Tags.tag("$series", i)
  defp value(:extent, :auto), do: "auto"
  defp value(:extent, v) when is_list(v), do: Enum.map(v, &category/1)
  defp value(:range, :auto), do: "auto"
  defp value(:range, v) when is_list(v), do: Enum.map(v, &range_entry/1)
  defp value(:text, v) when is_binary(v), do: v
  defp value(:text, v) when is_list(v), do: Enum.map(v, &value(:term, &1))
  defp value(:anchor, v) when is_atom(v), do: Atom.to_string(v)
  defp value(:anchor, {:axis, s}) when is_name(s), do: Tags.tag("$axis", spell(s))
  defp value(:anchor, {:frame, c}) when is_atom(c), do: Tags.tag("$frame", Atom.to_string(c))
  defp value(:anchor, {:data, [x, y]}), do: Tags.tag("$data", [term(x), term(y)])

  defp value(:adopted, {:frame, f, s}) when is_name(f) and is_name(s),
    do: Tags.tag("$adopted", [spell(f), spell(s)])

  defp value(:key_order, {:keys, keys}) when is_list(keys),
    do: Tags.tag("$keys", Enum.map(keys, &value(:name, &1)))

  defp value(_type, v), do: term(v)

  # A range's entry (spec/14 §11.2, D-185): a position as its term, a color as a color — an
  # atom a design built in memory still holds bare is the color it can only be there.
  defp range_entry(v) when is_number(v) or is_struct(v), do: term(v)

  defp range_entry(v) when is_atom(v) and v not in [nil, true, false, :none],
    do: value(:color, {:color, v})

  defp range_entry(v), do: value(:color, v)

  defp category(:auto), do: "auto"
  defp category(v), do: term(v)

  defp term(%Var{name: name}), do: Tags.tag("$var", spell(name))

  # A schema fact (spec/14 §7.4, §11.2): the slot, the field and the attribute.
  defp term(%Fact{source: s, field: f, key: k}),
    do: Tags.tag("$fact", Enum.map([s, f, k], &spell/1))

  defp term(%Use{id: {:use, n}} = use) do
    Tags.tag("$use", %{
      "id" => n,
      "ref" => if(use.ref, do: term(use.ref)),
      "mask" => if(use.mask == :all, do: "all", else: Enum.map(use.mask, &term/1)),
      "vars" => term(use.vars),
      "local" => term(use.local),
      "key" => if(use.key, do: spell(use.key)),
      "origin" => if(use.origin, do: term(use.origin))
    })
  end

  defp term({kind, n} = id) when is_atom(kind) and is_integer(n) and n > 0 do
    if kind in Fragment.kinds(), do: Tags.tag("$id", [Atom.to_string(kind), n]), else: id
  end

  defp term({:field, f}) when is_name(f), do: Tags.tag("$field", spell(f))
  defp term(%DateTime{} = dt), do: Tags.tag("$time", DateTime.to_iso8601(dt))
  defp term(v) when is_number(v) or is_binary(v) or is_boolean(v) or is_nil(v), do: v
  defp term(v) when is_atom(v), do: Tags.tag("$atom", Atom.to_string(v))
  defp term(v) when is_list(v), do: Enum.map(v, &term/1)

  defp term(v) when is_map(v) and not is_struct(v) do
    Map.new(v, fn {k, e} -> {key(k), term(e)} end)
  end

  # -- decode ---------------------------------------------------------------------------

  @doc false
  def decode(map) when is_map(map) and not is_struct(map), do: read_node(:design, map)
  @doc false
  def decode(other), do: other

  # One term outside any schema, as a `:term` position writes and reads it (spec/14
  # §11.2): the board's codec (spec/15 §2.2) writes its component ids, its window's times
  # and its variables' values through these, so a board and a design spell a term alike.
  @doc false
  def encode_term(value), do: term(value)
  @doc false
  def decode_term(value), do: read_term(value)

  # A key is looked up in the schema's keys before anything is made of it (spec/14 §9.4,
  # D-195): a key no node kind has stays the string it was and its value is left as parsed,
  # for the validator to report as `:unknown_key` at its own spelling, so a refused document
  # makes no atom from its keys or from anything under them. A key only an earlier version
  # had is read by the type it had there, so the migration that moves it gets typed values
  # (spec/14 §9, #479). A key of another kind is left as parsed too; a singular wrapper's
  # body (`{"style": {…}}`, spec/14 §19.2) is the fragment's, written and read as a term.
  defp read_node(kind, map) do
    Map.new(map, fn {k, v} ->
      case schema_key(k) do
        {:ok, k} ->
          case type_of(kind, k, flat?(kind, k, not json_part?(v))) do
            nil -> {k, unknown_value(kind, k, v)}
            type -> {k, read_at(kind, k, type, v)}
          end

        :error ->
          {k, v}
      end
    end)
  end

  defp schema_key(k) when is_binary(k), do: Vocabulary.fetch(Words.keys(), k)
  defp schema_key(k), do: {:ok, k}

  # A theme's maps are keyed by the library's vocabularies (spec/08 §7.1, §7.7): a ramp, a
  # palette name — the style series up to the bound — and a color, the library's or one the
  # theme declares, which stays a string (spec/14 §9.4).
  defp read_at(:theme, key, {:map, t}, v)
       when key in [:ramps, :colors, :styles] and is_map(v) and not is_struct(v) do
    Map.new(v, fn {name, e} -> {theme_key(key, name_key(name)), read(t, e)} end)
  end

  # A `:name` that holds a library's vocabulary, not a design's name (spec/14 §9.4): a
  # design's built-in theme and a theme's own name, a color scheme, a projection's type.
  defp read_at(kind, key, _type, v)
       when {kind, key} in [{:design, :theme}, {:theme, :name}] and is_binary(v),
       do: Vocabulary.read(@theme_names, v)

  defp read_at(:scale, :range, type, "auto"), do: read(type, "auto")
  defp read_at(:scale, :range, _type, v) when is_binary(v), do: Vocabulary.read(@schemes, v)

  defp read_at(:projection, :type, _type, v) when is_binary(v),
    do: Vocabulary.read(@projections, v)

  defp read_at(_kind, _key, type, v), do: read(type, v)

  defp theme_key(:ramps, name), do: Vocabulary.read(@ramps, name)
  defp theme_key(:colors, name), do: Vocabulary.read(@color_names, name)

  defp theme_key(:styles, name) do
    case Vocabulary.fetch(@palette_names, name) do
      {:ok, found} -> found
      :error -> palette_series(name)
    end
  end

  defp palette_series("style_" <> digits = name) do
    case Integer.parse(digits) do
      {k, ""} when k >= 1 and k <= @series_bound and binary_part(digits, 0, 1) != "0" ->
        Visualize.Theme.Palette.series_name(k)

      _other ->
        name
    end
  end

  defp palette_series(name), do: name

  # A fragment's body is read as a term (spec/14 §19.7).
  defp unknown_value(:design, k, v) do
    if k == :composite or Fragment.singular(k), do: read_term(v), else: v
  end

  defp unknown_value(_kind, _k, v), do: v

  # A JSON object is a part unless it is one tagged term (`{"$paint": …}`), which is a
  # shorthand's value.
  defp json_part?(v) when is_map(v) and map_size(v) == 1,
    do: not String.starts_with?(to_string(hd(Map.keys(v))), "$")

  defp json_part?(v), do: is_map(v)

  # A name-keyed map's key — a source, frame, scale, style, variable, case — is the name's
  # string (spec/14 §1.4, D-195).
  defp name_key(k) when is_binary(k), do: Tags.unescape(k)
  defp name_key(k), do: k

  # A term's key: a schema key's atom where it spells one — a use site's local is a fragment —
  # and otherwise the string, a row's field or a variable's (spec/14 §9.4).
  defp term_key(k) when is_binary(k), do: k |> Tags.unescape() |> Words.key()

  defp term_key(k), do: k

  defp read(_type, %{"$var" => name} = v) when map_size(v) == 1 and is_binary(name),
    do: %Var{name: name}

  defp read(_type, %{"$fact" => _} = v) when map_size(v) == 1, do: read_term(v)

  defp read(_type, %{"$field" => f} = v) when map_size(v) == 1 and is_binary(f),
    do: {:field, f}

  # A generator's name is plain words, or the object is left as it is for the validator to
  # refuse (#645's rule). It is the host's vocabulary: the string, which the registry is
  # read by (spec/14 §3.13, §9.4).
  defp read(_type, %{"$generate" => [name, args]} = v)
       when map_size(v) == 1 and is_binary(name) and is_list(args) do
    if Regex.match?(@color_word, name),
      do: {:generate, name, Enum.map(args, &read_term/1)},
      else: v
  end

  defp read(:color, %{"$paint" => name} = v) when map_size(v) == 1 and is_binary(name),
    do: {:paint, name}

  defp read(:color, %{"$ramp" => [name, t]} = v) when map_size(v) == 1 and is_number(t) do
    case ramp_name(name) do
      nil -> v
      found -> {:ramp, found, t}
    end
  end

  defp read(:theme_color, %{"$steps" => pairs} = v) when map_size(v) == 1 and is_list(pairs) do
    if Enum.all?(pairs, &match?([n, _] when is_integer(n), &1)),
      do: Map.new(pairs, fn [n, c] -> {n, read(:color, c)} end),
      else: v
  end

  defp read(:theme_color, v), do: read(:color, v)

  # A theme's counterpart: a built-in theme's atom, or the string naming one the host holds.
  defp read(:counterpart, name) when is_binary(name), do: Vocabulary.read(@theme_names, name)

  # A color's name: the library's atom — a CSS name, a slot, a role — or the string of a
  # color the theme declares (spec/14 §9.4).
  defp read(:color, %{"$color" => name} = v) when map_size(v) == 1 and is_binary(name) do
    if Regex.match?(@color_word, name),
      do: {:color, color_name(name)},
      else: v
  end

  defp read(:color, %{"$blend" => list} = v) when map_size(v) == 1 and is_list(list),
    do: {:blend, Enum.map(list, &read(:color, &1))}

  defp read(:color, %{"$contrast" => "under"} = v) when map_size(v) == 1, do: {:contrast, :under}

  defp read(:color, %{"$contrast" => c} = v) when map_size(v) == 1,
    do: {:contrast, read(:color, c)}

  # A transform's tag. Any other one-key `$` object is left as the object it is, which is
  # no color, for the validator to refuse: a known tag out of place, or, from a document
  # before version 3, one the table does not have (an unknown tag is refused by the reader in
  # any later one, D-182).
  defp read(:color, %{} = v) when map_size(v) == 1 do
    case Map.to_list(v) do
      [{"$" <> op, [c, t]}] when is_number(t) ->
        case Vocabulary.fetch(@unary_ops, op) do
          :error -> v
          {:ok, found} -> {found, read(:color, c), t}
        end

      [{"$series", i}] ->
        {:series, i}

      [{"$" <> _tag, _value}] ->
        v

      _other ->
        read_term(v)
    end
  end

  defp read(:color_map, %{"$colors" => pairs} = v) when map_size(v) == 1 and is_list(pairs) do
    if Enum.all?(pairs, &match?([_, _], &1)),
      do: Map.new(pairs, fn [category, color] -> {read_term(category), read(:color, color)} end),
      else: v
  end

  defp read(:ramp, %{"$ramp" => name} = v) when map_size(v) == 1 do
    case ramp_name(name) do
      nil -> v
      found -> {:ramp, found}
    end
  end

  defp read({:node, kind}, v) when is_map(v) and not is_struct(v), do: read_node(kind, v)
  defp read({:list, t}, v) when is_list(v), do: Enum.map(v, &read(t, &1))

  defp read({:map, t}, v) when is_map(v) and not is_struct(v) do
    Map.new(v, fn {k, e} -> {name_key(k), read(t, e)} end)
  end

  # A string naming a member of an enumeration alternative is that member, whatever comes
  # first: an axis's `format` is a string or `:duration`, and `"duration"` is the atom
  # (spec/14 §11.1, #554, D-144). Otherwise the first alternative of the value's shape.
  defp read({:one_of, types}, v) do
    case Enum.find(types, &member?(&1, v)) || Enum.find(types, &json_shape?(&1, v)) do
      nil -> read_term(v)
      t -> read(t, v)
    end
  end

  # A name, a field and a channel's field are the strings they are (spec/14 §1.4).
  defp read(type, v) when type in [:name, :field, :channel] and is_binary(v), do: v

  # An enumeration's member is one of its list — or a palette role's `:cue`, which a theme's
  # entry gives a marker's shape (spec/14 §2.6) — and any other string stays one, refused
  # by type.
  defp read({:enum, _allowed}, "cue"), do: :cue
  defp read({:enum, allowed}, v) when is_binary(v), do: Vocabulary.read(allowed, v)
  defp read({:ref, _}, v) when is_binary(v), do: v
  defp read({:ref, _}, %{"$id" => _} = v), do: read_term(v)
  defp read(:slot, v) when is_binary(v), do: slot(v)

  defp read(type, %{"$series" => i} = v)
       when type in [:slot, :color, :size, :font] and map_size(v) == 1,
       do: {:series, i}

  # A unit is one of the library's, so no atom is made from a document (spec/14 §11.2).
  defp read(type, %{"$unit" => [n, unit]} = v)
       when type in [:size, :length] and map_size(v) == 1 and is_number(n) do
    case Vocabulary.fetch(@units, unit) do
      :error -> v
      {:ok, found} -> {n, found}
    end
  end

  # Only the two ends are read as atoms; any other is left for the validator to name.
  defp read(:channel, %{"$scale" => which} = v) when map_size(v) == 1 do
    case which do
      "min" -> {:scale, :min}
      "max" -> {:scale, :max}
      _other -> v
    end
  end

  defp read(:color, "none"), do: :none
  defp read(:color, "contrast"), do: :contrast
  defp read(type, v) when type in [:color, :font, :size] and is_binary(v), do: slot_or_string(v)
  defp read(:extent, "auto"), do: :auto
  defp read(:extent, v) when is_list(v), do: Enum.map(v, &read_category/1)
  defp read(:range, "auto"), do: :auto
  defp read(:range, v) when is_list(v), do: Enum.map(v, &read_range_entry/1)
  defp read(:text, v) when is_binary(v), do: v
  defp read(:text, v) when is_list(v), do: Enum.map(v, &read_term/1)
  defp read(:anchor, v) when is_binary(v), do: Vocabulary.read(@anchors, v)

  defp read(:adopted, %{"$adopted" => [f, s]} = v)
       when map_size(v) == 1 and is_binary(f) and is_binary(s),
       do: {:frame, f, s}

  defp read(:anchor, %{"$axis" => s} = v) when map_size(v) == 1 and is_binary(s),
    do: {:axis, s}

  # A frame point is one of the plot's five; any other is left as the object it is.
  defp read(:anchor, %{"$frame" => c} = v) when map_size(v) == 1 and is_binary(c) do
    case Vocabulary.fetch(@frame_points, c) do
      {:ok, point} -> {:frame, point}
      :error -> v
    end
  end

  defp read(:anchor, %{"$data" => [x, y]} = v) when map_size(v) == 1,
    do: {:data, [read_term(x), read_term(y)]}

  defp read(:key_order, %{"$keys" => keys} = v) when map_size(v) == 1 and is_list(keys),
    do: {:keys, Enum.map(keys, &read(:name, &1))}

  defp read(_type, v), do: read_term(v)

  defp slot_or_string(v) do
    case slot(v) do
      slot when is_atom(slot) -> slot
      _string -> v
    end
  end

  # A slot is one of the theme's fixed slots or a series slot within the bound; any other
  # string stays one, for the validator to refuse by type (spec/14 §9.4).
  defp slot(v) do
    case Vocabulary.fetch(@fixed_slot_names, v) do
      {:ok, slot} -> slot
      :error -> series_slot(v)
    end
  end

  defp series_slot(v), do: Words.series_slot(v)

  # A color's name: the library's — a CSS name, a slot, a role, a series slot within the
  # bound — or the string of one the theme declares.
  defp color_name(name) do
    case Vocabulary.fetch(@color_names, name) do
      {:ok, found} -> found
      :error -> series_slot(name)
    end
  end

  # A ramp's name is one of the theme's four, so no atom is created from a document.
  defp ramp_name(name) when is_binary(name) do
    case Vocabulary.fetch(@ramps, name) do
      {:ok, found} -> found
      :error -> nil
    end
  end

  defp ramp_name(_name), do: nil

  # A range's entry (spec/14 §11.2, D-185): a number or a string as it is, a position's tag
  # — and an atom an earlier document wrote, for `canonical/1` to type — as a term, and
  # anything else as a color.
  defp read_range_entry(v) when is_number(v) or is_binary(v), do: v

  defp read_range_entry(%{} = v)
       when map_size(v) == 1 and
              (is_map_key(v, "$var") or is_map_key(v, "$fact") or
                 is_map_key(v, "$time") or is_map_key(v, "$atom")),
       do: read_term(v)

  defp read_range_entry(v), do: read(:color, v)

  defp read_category("auto"), do: :auto
  defp read_category(v), do: read_term(v)

  defp read_term(%{"$var" => name} = v) when map_size(v) == 1 and is_binary(name),
    do: %Var{name: name}

  # An id's kind must be one a fragment can have, so no atom is created from a document.
  defp read_term(%{"$id" => [kind, n]} = v) when map_size(v) == 1 and is_binary(kind) do
    case Vocabulary.fetch(@kinds, kind) do
      {:ok, found} when is_integer(n) and n > 0 -> {found, n}
      _other -> v
    end
  end

  defp read_term(%{"$use" => %{"id" => n} = use} = v) when map_size(v) == 1 and is_integer(n) do
    %Use{
      id: {:use, n},
      ref: use |> Map.get("ref") |> read_ref(),
      mask: use |> Map.get("mask", []) |> read_mask(),
      vars: use |> Map.get("vars", %{}) |> read_names(),
      local: use |> Map.get("local", %{}) |> read_term(),
      key: use |> Map.get("key") |> read_key(),
      origin: use |> Map.get("origin") |> read_ref()
    }
  end

  # A fact's attribute is one of the feed schema's; its slot and field are names.
  defp read_term(%{"$fact" => [s, f, k]} = v)
       when map_size(v) == 1 and is_binary(s) and is_binary(f) and is_binary(k) do
    case Vocabulary.fetch(@attributes, k) do
      {:ok, key} -> %Fact{source: s, field: f, key: key}
      :error -> v
    end
  end

  defp read_term(%{"$field" => f} = v) when map_size(v) == 1 and is_binary(f),
    do: {:field, f}

  # A category value: the library's atom of its spelling, or the string (D-195).
  defp read_term(%{"$atom" => a} = v) when map_size(v) == 1 and is_binary(a),
    do: Words.word(a)

  defp read_term(%{"$time" => iso} = v) when map_size(v) == 1 and is_binary(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, dt, _offset} -> dt
      {:error, _} -> v
    end
  end

  defp read_term(v) when is_list(v), do: Enum.map(v, &read_term/1)

  defp read_term(v) when is_map(v) and not is_struct(v),
    do: Map.new(v, fn {k, e} -> {term_key(k), read_term(e)} end)

  defp read_term(v), do: v

  # A use site binds variables by name: its keys are the names' strings (spec/14 §19.4).
  defp read_names(vars) when is_map(vars),
    do: Map.new(vars, fn {k, v} -> {name_key(k), read_term(v)} end)

  defp read_names(other), do: read_term(other)

  defp read_ref(nil), do: nil
  defp read_ref(v), do: read_term(v)

  defp read_key(nil), do: nil
  defp read_key(key) when is_binary(key), do: key

  defp read_mask("all"), do: :all
  defp read_mask(paths) when is_list(paths), do: Enum.map(paths, &read_term/1)

  defp member?({:enum, allowed}, v) when is_binary(v),
    do: v in Enum.map(allowed, &Atom.to_string/1)

  defp member?(_type, _v), do: false

  # The JSON shape of each alternative of a `{:one_of, types}`: strings stand for atoms.
  # A tagged object is a term, never a node: an adopted scale (`$adopted`) sits where a
  # scale node may, and must not be read as one (#480).
  defp json_shape?({:node, _}, v), do: is_map(v) and not is_struct(v) and not tagged?(v)
  defp json_shape?(:adopted, v), do: is_map(v) and is_map_key(v, "$adopted") and map_size(v) == 1
  defp json_shape?(:key_order, v), do: is_map(v) and is_map_key(v, "$keys") and map_size(v) == 1
  defp json_shape?(:ramp, v), do: is_map(v) and is_map_key(v, "$ramp") and map_size(v) == 1

  defp json_shape?(:color_map, v),
    do: is_map(v) and is_map_key(v, "$colors") and map_size(v) == 1

  # An enumeration's JSON is a string, so a tagged object beside one is never it (#492).
  defp json_shape?({:enum, _}, v), do: is_binary(v)
  defp json_shape?({:map, _}, v), do: is_map(v) and not is_struct(v)
  defp json_shape?({:list, _}, v), do: is_list(v)
  defp json_shape?(:text, v), do: is_list(v) or is_binary(v)
  defp json_shape?(:extent, v), do: v == "auto" or is_list(v)
  defp json_shape?(:range, v), do: v == "auto" or is_list(v)
  defp json_shape?(:integer, v), do: is_integer(v)
  defp json_shape?(:number, v), do: is_number(v)
  defp json_shape?(:boolean, v), do: is_boolean(v)
  defp json_shape?(:string, v), do: is_binary(v)
  defp json_shape?(:size, v), do: is_number(v) or is_binary(v) or tagged?(v)
  defp json_shape?(:length, v), do: is_number(v) or tagged?(v)
  defp json_shape?(:channel, v), do: is_number(v) or is_binary(v) or tagged?(v)
  defp json_shape?(:term, _), do: true
  defp json_shape?(_atomic, v), do: is_binary(v) or tagged?(v)

  # A one-key `$` object is a tagged term (spec/14 §11.2), never a node.
  defp tagged?(v) when is_map(v) and map_size(v) == 1 do
    v |> Map.keys() |> hd() |> String.starts_with?("$")
  end

  defp tagged?(_), do: false
end
