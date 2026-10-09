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

  alias Visualize.Chart.{Fragment, Migration, Schema, Use, Var}
  alias Visualize.Theme

  @fixed_slots Theme.default() |> Theme.slots() |> Enum.reject(&(&1 in [:series_1]))
  @series_slot ~r/^series_[1-9]\d*$/

  # -- encode ---------------------------------------------------------------------------

  @doc false
  def encode(map), do: node(:design, map)

  defp node(kind, map) do
    Map.new(map, fn {k, v} ->
      case Schema.key(kind, k) do
        nil -> {key(k), term(v)}
        spec -> {key(k), value(spec.type, v)}
      end
    end)
  end

  defp key(k) when is_atom(k), do: Atom.to_string(k)
  defp key(k), do: to_string(k)

  defp value(_type, %Var{name: name}), do: %{"$var" => Atom.to_string(name)}
  defp value(_type, {:field, f}) when is_atom(f), do: %{"$field" => Atom.to_string(f)}
  defp value(:colour, {:paint, name}) when is_atom(name), do: %{"$paint" => Atom.to_string(name)}
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

  defp value(_type, v), do: term(v)

  defp category(:auto), do: "auto"
  defp category(v), do: term(v)

  defp term(%Var{name: name}), do: %{"$var" => Atom.to_string(name)}

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

  # A key only an earlier version had is read by the type it had there, so the migration
  # that moves it gets typed values (spec/14 §9, #479); any other unknown key is a term.
  defp read_legacy(kind, k, v) do
    case Migration.legacy_type(kind, k) do
      nil -> read_term(v)
      type -> read(type, v)
    end
  end

  defp read_node(kind, map) do
    Map.new(map, fn {k, v} ->
      k = atom(k)

      case Schema.key(kind, k) do
        nil -> {k, read_legacy(kind, k, v)}
        spec -> {k, read(spec.type, v)}
      end
    end)
  end

  defp atom(k) when is_binary(k), do: String.to_atom(k)
  defp atom(k), do: k

  defp read(_type, %{"$var" => name} = v) when map_size(v) == 1 and is_binary(name),
    do: %Var{name: String.to_atom(name)}

  defp read(_type, %{"$field" => f} = v) when map_size(v) == 1 and is_binary(f),
    do: {:field, String.to_atom(f)}

  defp read(:colour, %{"$paint" => name} = v) when map_size(v) == 1 and is_binary(name),
    do: {:paint, String.to_atom(name)}

  defp read({:node, kind}, v) when is_map(v) and not is_struct(v), do: read_node(kind, v)
  defp read({:list, t}, v) when is_list(v), do: Enum.map(v, &read(t, &1))

  defp read({:map, t}, v) when is_map(v) and not is_struct(v) do
    Map.new(v, fn {k, e} -> {atom(k), read(t, e)} end)
  end

  defp read({:one_of, types}, v) do
    case Enum.find(types, &json_shape?(&1, v)) do
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

  defp read(_type, v), do: read_term(v)

  defp slot_or_string(v) do
    if Regex.match?(@series_slot, v) or v in Enum.map(@fixed_slots, &Atom.to_string/1) do
      String.to_atom(v)
    else
      v
    end
  end

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

  # The JSON shape of each alternative of a `{:one_of, types}`: strings stand for atoms.
  # A tagged object is a term, never a node: an adopted scale (`$adopted`) sits where a
  # scale node may, and must not be read as one (#480).
  defp json_shape?({:node, _}, v), do: is_map(v) and not is_struct(v) and not tagged?(v)
  defp json_shape?(:adopted, v), do: is_map(v) and is_map_key(v, "$adopted") and map_size(v) == 1
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
