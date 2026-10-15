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

  alias Visualize.Chart.{Fact, Fragment, Migration, Schema, Use, Var}
  alias Visualize.Theme

  @fixed_slots Theme.default() |> Theme.slots() |> Enum.reject(&(&1 in [:series_1]))
  @series_slot ~r/^series_[1-9]\d*$/
  # A color name read from a document is made an atom only when it is plain words.
  @colour_word ~r/^[a-z][a-z0-9_]*$/
  @unary Visualize.Color.Typed.ops()

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

  defp key(k) when is_atom(k), do: Atom.to_string(k)
  defp key(k), do: to_string(k)

  defp value(_type, %Var{name: name}), do: %{"$var" => Atom.to_string(name)}
  defp value(_type, %Fact{} = fact), do: term(fact)
  defp value(_type, {:field, f}) when is_atom(f), do: %{"$field" => Atom.to_string(f)}
  defp value(:colour, {:paint, name}) when is_atom(name), do: %{"$paint" => Atom.to_string(name)}

  # A ramp position, and a whole ramp as a colour scale's range (spec/14 §11.2, #533).
  defp value(:colour, {:ramp, name, t}) when is_atom(name) and is_number(t),
    do: %{"$ramp" => [Atom.to_string(name), t]}

  defp value(:ramp, {:ramp, name}) when is_atom(name), do: %{"$ramp" => Atom.to_string(name)}

  # A typed color (spec/14 §11.2, #664): a name, a transform with its color first, a blend's
  # list, the contrast ink over a color or over what is under.
  defp value(:colour, {:color, name}) when is_atom(name), do: %{"$color" => Atom.to_string(name)}

  defp value(:colour, {op, c, t}) when op in @unary and is_number(t),
    do: %{"$#{op}" => [value(:colour, c), t]}

  defp value(:colour, {:blend, list}) when is_list(list),
    do: %{"$blend" => Enum.map(list, &value(:colour, &1))}

  # A theme's pinned steps, `[step, colour]` pairs in step order (spec/14 §11.2, #667).
  defp value(:theme_colour, steps) when is_map(steps) and not is_struct(steps),
    do: %{"$steps" => steps |> Enum.sort() |> Enum.map(fn {n, c} -> [n, value(:colour, c)] end)}

  defp value(:theme_colour, v), do: value(:colour, v)

  # A theme's counterpart (spec/08 §7.3, #668): its name, or `null` for none.
  defp value(:counterpart, nil), do: nil
  defp value(:counterpart, name) when is_atom(name), do: Atom.to_string(name)

  defp value(:colour, {:contrast, :under}), do: %{"$contrast" => "under"}
  defp value(:colour, {:contrast, c}), do: %{"$contrast" => value(:colour, c)}

  # A map of colours as `[category, colour]` pairs in the categories' term order (spec/14
  # §11.2, D-143): an object's keys are strings, and a category need not be one.
  defp value(:colour_map, map) when is_map(map) and not is_struct(map) do
    pairs =
      map
      |> Enum.sort_by(fn {category, _colour} -> category end)
      |> Enum.map(fn {category, colour} -> [term(category), value(:colour, colour)] end)

    %{"$colours" => pairs}
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

  defp value(type, v) when type in [:name, :field, :colour, :font] and is_atom(v),
    do: Atom.to_string(v)

  defp value({:enum, _}, v) when is_atom(v), do: Atom.to_string(v)
  defp value({:ref, _}, v) when is_atom(v), do: Atom.to_string(v)
  defp value({:ref, _}, {kind, n} = id) when is_atom(kind) and is_integer(n), do: term(id)
  defp value(:slot, v) when is_atom(v), do: Atom.to_string(v)
  defp value(:slot, {:series, i}), do: %{"$series" => i}
  defp value(type, v) when type in [:size, :channel] and is_atom(v), do: Atom.to_string(v)

  # A channel at its scale's own end (spec/14 §5.2, §11.2, #554).
  defp value(:channel, {:scale, which}) when which in [:min, :max],
    do: %{"$scale" => Atom.to_string(which)}

  defp value(type, {:series, i}) when type in [:colour, :size, :font], do: %{"$series" => i}
  defp value(:extent, :auto), do: "auto"
  defp value(:extent, v) when is_list(v), do: Enum.map(v, &category/1)
  defp value(:text, v) when is_binary(v), do: v
  defp value(:text, v) when is_list(v), do: Enum.map(v, &value(:term, &1))
  defp value(:anchor, v) when is_atom(v), do: Atom.to_string(v)
  defp value(:anchor, {:axis, s}) when is_atom(s), do: %{"$axis" => Atom.to_string(s)}
  defp value(:anchor, {:frame, c}) when is_atom(c), do: %{"$frame" => Atom.to_string(c)}
  defp value(:anchor, {:data, [x, y]}), do: %{"$data" => [term(x), term(y)]}

  defp value(:adopted, {:frame, f, s}) when is_atom(f) and is_atom(s),
    do: %{"$adopted" => [Atom.to_string(f), Atom.to_string(s)]}

  defp value(:key_order, {:keys, keys}) when is_list(keys),
    do: %{"$keys" => Enum.map(keys, &value(:name, &1))}

  defp value(_type, v), do: term(v)

  defp category(:auto), do: "auto"
  defp category(v), do: term(v)

  defp term(%Var{name: name}), do: %{"$var" => Atom.to_string(name)}

  # A schema fact (spec/14 §7.4, §11.2): the slot, the field and the attribute.
  defp term(%Fact{source: s, field: f, key: k}),
    do: %{"$fact" => Enum.map([s, f, k], &Atom.to_string/1)}

  defp term(%Use{id: {:use, n}} = use) do
    %{
      "$use" => %{
        "id" => n,
        "ref" => if(use.ref, do: term(use.ref)),
        "mask" => if(use.mask == :all, do: "all", else: Enum.map(use.mask, &term/1)),
        "vars" => term(use.vars),
        "local" => term(use.local),
        "key" => if(use.key, do: Atom.to_string(use.key)),
        "origin" => if(use.origin, do: term(use.origin))
      }
    }
  end

  defp term({kind, n} = id) when is_atom(kind) and is_integer(n) and n > 0 do
    if kind in Fragment.kinds(), do: %{"$id" => [Atom.to_string(kind), n]}, else: id
  end

  defp term({:field, f}) when is_atom(f), do: %{"$field" => Atom.to_string(f)}
  defp term(%DateTime{} = dt), do: %{"$time" => DateTime.to_iso8601(dt)}
  defp term(v) when is_number(v) or is_binary(v) or is_boolean(v) or is_nil(v), do: v
  defp term(v) when is_atom(v), do: %{"$atom" => Atom.to_string(v)}
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

  # A key only an earlier version had is read by the type it had there, so the migration
  # that moves it gets typed values (spec/14 §9, #479); any other unknown key is a term.
  defp read_node(kind, map) do
    Map.new(map, fn {k, v} ->
      k = atom(k)

      case type_of(kind, k, flat?(kind, k, not json_part?(v))) do
        nil -> {k, read_term(v)}
        type -> {k, read(type, v)}
      end
    end)
  end

  # A JSON object is a part unless it is one tagged term (`{"$paint": …}`), which is a
  # shorthand's value.
  defp json_part?(v) when is_map(v) and map_size(v) == 1,
    do: not String.starts_with?(to_string(hd(Map.keys(v))), "$")

  defp json_part?(v), do: is_map(v)

  defp atom(k) when is_binary(k), do: String.to_atom(k)
  defp atom(k), do: k

  defp read(_type, %{"$var" => name} = v) when map_size(v) == 1 and is_binary(name),
    do: %Var{name: String.to_atom(name)}

  defp read(_type, %{"$fact" => _} = v) when map_size(v) == 1, do: read_term(v)

  defp read(_type, %{"$field" => f} = v) when map_size(v) == 1 and is_binary(f),
    do: {:field, String.to_atom(f)}

  defp read(:colour, %{"$paint" => name} = v) when map_size(v) == 1 and is_binary(name),
    do: {:paint, String.to_atom(name)}

  defp read(:colour, %{"$ramp" => [name, t]} = v) when map_size(v) == 1 and is_number(t) do
    case ramp_name(name) do
      nil -> v
      found -> {:ramp, found, t}
    end
  end

  defp read(:theme_colour, %{"$steps" => pairs} = v) when map_size(v) == 1 and is_list(pairs) do
    if Enum.all?(pairs, &match?([n, _] when is_integer(n), &1)),
      do: Map.new(pairs, fn [n, c] -> {n, read(:colour, c)} end),
      else: v
  end

  defp read(:theme_colour, v), do: read(:colour, v)

  defp read(:counterpart, name) when is_binary(name), do: String.to_atom(name)

  defp read(:colour, %{"$color" => name} = v) when map_size(v) == 1 and is_binary(name) do
    if Regex.match?(@colour_word, name), do: {:color, String.to_atom(name)}, else: v
  end

  defp read(:colour, %{"$blend" => list} = v) when map_size(v) == 1 and is_list(list),
    do: {:blend, Enum.map(list, &read(:colour, &1))}

  defp read(:colour, %{"$contrast" => "under"} = v) when map_size(v) == 1, do: {:contrast, :under}

  defp read(:colour, %{"$contrast" => c} = v) when map_size(v) == 1,
    do: {:contrast, read(:colour, c)}

  # A transform's tag; any other one-key `$` object is left as the object it is, which is no
  # color, so the validator refuses it rather than a color be read as data (#645's rule).
  defp read(:colour, %{} = v) when map_size(v) == 1 do
    case Map.to_list(v) do
      [{"$" <> op, [c, t]}] when is_number(t) ->
        case Enum.find(@unary, &(Atom.to_string(&1) == op)) do
          nil -> v
          found -> {found, read(:colour, c), t}
        end

      [{"$series", i}] ->
        {:series, i}

      [{"$" <> _tag, _value}] ->
        v

      _other ->
        read_term(v)
    end
  end

  defp read(:colour_map, %{"$colours" => pairs} = v) when map_size(v) == 1 and is_list(pairs) do
    if Enum.all?(pairs, &match?([_, _], &1)),
      do:
        Map.new(pairs, fn [category, colour] -> {read_term(category), read(:colour, colour)} end),
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
    Map.new(v, fn {k, e} -> {atom(k), read(t, e)} end)
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

  defp read(type, v) when type in [:name, :field, :channel] and is_binary(v),
    do: String.to_atom(v)

  defp read({:enum, _}, v) when is_binary(v), do: String.to_atom(v)
  defp read({:ref, _}, v) when is_binary(v), do: String.to_atom(v)
  defp read({:ref, _}, %{"$id" => _} = v), do: read_term(v)
  defp read(:slot, v) when is_binary(v), do: String.to_atom(v)

  defp read(type, %{"$series" => i} = v)
       when type in [:slot, :colour, :size, :font] and map_size(v) == 1,
       do: {:series, i}

  # Only the two ends are read as atoms; any other is left for the validator to name.
  defp read(:channel, %{"$scale" => which} = v) when map_size(v) == 1 do
    case which do
      "min" -> {:scale, :min}
      "max" -> {:scale, :max}
      _other -> v
    end
  end

  defp read(:colour, "none"), do: :none
  defp read(:colour, "contrast"), do: :contrast
  defp read(type, v) when type in [:colour, :font, :size] and is_binary(v), do: slot_or_string(v)
  defp read(:extent, "auto"), do: :auto
  defp read(:extent, v) when is_list(v), do: Enum.map(v, &read_category/1)
  defp read(:text, v) when is_binary(v), do: v
  defp read(:text, v) when is_list(v), do: Enum.map(v, &read_term/1)
  defp read(:anchor, v) when is_binary(v), do: String.to_atom(v)

  defp read(:adopted, %{"$adopted" => [f, s]} = v)
       when map_size(v) == 1 and is_binary(f) and is_binary(s),
       do: {:frame, String.to_atom(f), String.to_atom(s)}

  defp read(:anchor, %{"$axis" => s} = v) when map_size(v) == 1 and is_binary(s),
    do: {:axis, String.to_atom(s)}

  defp read(:anchor, %{"$frame" => c} = v) when map_size(v) == 1 and is_binary(c),
    do: {:frame, String.to_atom(c)}

  defp read(:anchor, %{"$data" => [x, y]} = v) when map_size(v) == 1,
    do: {:data, [read_term(x), read_term(y)]}

  defp read(:key_order, %{"$keys" => keys} = v) when map_size(v) == 1 and is_list(keys),
    do: {:keys, Enum.map(keys, &read(:name, &1))}

  defp read(_type, v), do: read_term(v)

  defp slot_or_string(v) do
    if Regex.match?(@series_slot, v) or v in Enum.map(@fixed_slots, &Atom.to_string/1) do
      String.to_atom(v)
    else
      v
    end
  end

  # A ramp's name is one of the theme's four, so no atom is created from a document.
  defp ramp_name(name), do: Enum.find(Theme.ramp_names(), &(Atom.to_string(&1) == name))

  defp read_category("auto"), do: :auto
  defp read_category(v), do: read_term(v)

  defp read_term(%{"$var" => name} = v) when map_size(v) == 1 and is_binary(name),
    do: %Var{name: String.to_atom(name)}

  # An id's kind must be one a fragment can have, so no atom is created from a document.
  defp read_term(%{"$id" => [kind, n]} = v) when map_size(v) == 1 and is_binary(kind) do
    case Enum.find(Fragment.kinds(), &(Atom.to_string(&1) == kind)) do
      nil -> v
      found when is_integer(n) and n > 0 -> {found, n}
      _found -> v
    end
  end

  defp read_term(%{"$use" => %{"id" => n} = use} = v) when map_size(v) == 1 and is_integer(n) do
    %Use{
      id: {:use, n},
      ref: use |> Map.get("ref") |> read_ref(),
      mask: use |> Map.get("mask", []) |> read_mask(),
      vars: use |> Map.get("vars", %{}) |> read_term(),
      local: use |> Map.get("local", %{}) |> read_term(),
      key: use |> Map.get("key") |> read_key(),
      origin: use |> Map.get("origin") |> read_ref()
    }
  end

  defp read_term(%{"$fact" => [s, f, k]} = v)
       when map_size(v) == 1 and is_binary(s) and is_binary(f) and is_binary(k),
       do: %Fact{source: String.to_atom(s), field: String.to_atom(f), key: String.to_atom(k)}

  defp read_term(%{"$field" => f} = v) when map_size(v) == 1 and is_binary(f),
    do: {:field, String.to_atom(f)}

  defp read_term(%{"$atom" => a} = v) when map_size(v) == 1 and is_binary(a),
    do: String.to_atom(a)

  defp read_term(%{"$time" => iso} = v) when map_size(v) == 1 and is_binary(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, dt, _offset} -> dt
      {:error, _} -> v
    end
  end

  defp read_term(v) when is_list(v), do: Enum.map(v, &read_term/1)

  defp read_term(v) when is_map(v) and not is_struct(v),
    do: Map.new(v, fn {k, e} -> {atom(k), read_term(e)} end)

  defp read_term(v), do: v

  defp read_ref(nil), do: nil
  defp read_ref(v), do: read_term(v)

  defp read_key(nil), do: nil
  defp read_key(key) when is_binary(key), do: String.to_atom(key)

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

  defp json_shape?(:colour_map, v),
    do: is_map(v) and is_map_key(v, "$colours") and map_size(v) == 1

  # An enumeration's JSON is a string, so a tagged object beside one is never it (#492).
  defp json_shape?({:enum, _}, v), do: is_binary(v)
  defp json_shape?({:map, _}, v), do: is_map(v) and not is_struct(v)
  defp json_shape?({:list, _}, v), do: is_list(v)
  defp json_shape?(:text, v), do: is_list(v) or is_binary(v)
  defp json_shape?(:extent, v), do: v == "auto" or is_list(v)
  defp json_shape?(:integer, v), do: is_integer(v)
  defp json_shape?(:number, v), do: is_number(v)
  defp json_shape?(:boolean, v), do: is_boolean(v)
  defp json_shape?(:string, v), do: is_binary(v)
  defp json_shape?(:size, v), do: is_number(v) or is_binary(v) or tagged?(v)
  defp json_shape?(:channel, v), do: is_number(v) or is_binary(v) or tagged?(v)
  defp json_shape?(:term, _), do: true
  defp json_shape?(_atomic, v), do: is_binary(v) or tagged?(v)

  # A one-key `$` object is a tagged term (spec/14 §11.2), never a node.
  defp tagged?(v) when is_map(v) and map_size(v) == 1 do
    v |> Map.keys() |> hd() |> String.starts_with?("$")
  end

  defp tagged?(_), do: false
end
