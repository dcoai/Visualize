defmodule Visualize.Chart.Codec do
  @moduledoc false
  # The JSON form of a design (spec/14 §11): a schema-driven walk in both directions.
  # `encode/1` turns a validated design map into a term Jason writes; `decode/1` turns
  # the term Jason read into a design map for the validator, never failing on a wrong
  # shape — a value the schema cannot place is passed through for the validator to name.

  alias Visualize.Chart.{Schema, Var}
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
  defp value(:slot, v) when is_atom(v), do: Atom.to_string(v)
  defp value(:slot, {:series, i}), do: %{"$series" => i}
  defp value(type, v) when type in [:size, :channel] and is_atom(v), do: Atom.to_string(v)
  defp value(type, {:series, i}) when type in [:colour, :size, :font], do: %{"$series" => i}
  defp value(:extent, :auto), do: "auto"
  defp value(:extent, v) when is_list(v), do: Enum.map(v, &category/1)
  defp value(:text, v) when is_list(v), do: Enum.map(v, &value(:term, &1))
  defp value(:anchor, v) when is_atom(v), do: Atom.to_string(v)
  defp value(:anchor, {:axis, s}) when is_atom(s), do: %{"$axis" => Atom.to_string(s)}
  defp value(:anchor, {:frame, c}) when is_atom(c), do: %{"$frame" => Atom.to_string(c)}
  defp value(:anchor, {:data, [x, y]}), do: %{"$data" => [term(x), term(y)]}
  defp value(_type, v), do: term(v)

  defp category(:auto), do: "auto"
  defp category(v), do: term(v)

  defp term(%Var{name: name}), do: %{"$var" => Atom.to_string(name)}
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
  def decode(map) when is_map(map), do: read_node(:design, map)
  @doc false
  def decode(other), do: other

  defp read_node(kind, map) do
    Map.new(map, fn {k, v} ->
      k = atom(k)

      case Schema.key(kind, k) do
        nil -> {k, read_term(v)}
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

  defp read({:node, kind}, v) when is_map(v), do: read_node(kind, v)
  defp read({:list, t}, v) when is_list(v), do: Enum.map(v, &read(t, &1))

  defp read({:map, t}, v) when is_map(v) do
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
  defp read(:slot, v) when is_binary(v), do: String.to_atom(v)

  defp read(type, %{"$series" => i} = v)
       when type in [:slot, :colour, :size, :font] and map_size(v) == 1,
       do: {:series, i}

  defp read(:colour, "none"), do: :none
  defp read(type, v) when type in [:colour, :font, :size] and is_binary(v), do: slot_or_string(v)
  defp read(:extent, "auto"), do: :auto
  defp read(:extent, v) when is_list(v), do: Enum.map(v, &read_category/1)
  defp read(:text, v) when is_list(v), do: Enum.map(v, &read_term/1)
  defp read(:anchor, v) when is_binary(v), do: String.to_atom(v)

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
  defp read_term(v) when is_map(v), do: Map.new(v, fn {k, e} -> {atom(k), read_term(e)} end)
  defp read_term(v), do: v

  # The JSON shape of each alternative of a `{:one_of, types}`: strings stand for atoms.
  defp json_shape?({:node, _}, v), do: is_map(v)
  defp json_shape?({:map, _}, v), do: is_map(v)
  defp json_shape?({:list, _}, v), do: is_list(v)
  defp json_shape?(:text, v), do: is_list(v)
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
