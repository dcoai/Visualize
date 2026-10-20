defmodule Visualize.VirtualSource.Codec do
  @moduledoc false
  # A virtual source's JSON form (spec/08 §10.5.10, D-194), written inside the document
  # that holds it — a board's (spec/15 §2.2) — with spec/14 §11.2's terms and no tag of
  # its own. Wherever a JSON object's string keys would lose a name's spelling (an atom or
  # a string) the form is a list of pairs: the inputs `[[name, window], …]`, the schema
  # `[[name, description], …]` as a snapshot writes one, a box's ranges `[[field, [from,
  # to]], …]`.
  #
  # Decoding never fails on a wrong shape: what it cannot place is passed through for
  # `Visualize.VirtualSource.new/1` to name. A key the source does not know stays a string.

  alias Visualize.Board.Snapshot.Codec, as: SnapshotCodec
  alias Visualize.Chart.Codec
  alias Visualize.Chart.Codec.Tags
  require Tags

  # The source's own keys, looked up and never made atoms of (spec/14 §9.4, D-195).
  @keys Visualize.Vocabulary.table([:id, :from, :schema, :elixir, :function, :per])

  # -- encode ------------------------------------------------------------------------------

  @doc false
  # A source's canonical map form, its id taken off by the holder, as JSON terms.
  def encode(source) when is_map(source) do
    Map.new(source, fn
      {:from, inputs} -> {"from", Enum.map(inputs, &input/1)}
      {:schema, fields} -> {"schema", fields |> SnapshotCodec.schema_json() |> spelled_schema()}
      {:elixir, text} -> {"elixir", text}
      {:function, name} -> {"function", name && to_string(name)}
      {:per, per} -> {"per", per(per)}
      {key, value} -> {Atom.to_string(key), Codec.encode_term(value)}
    end)
  end

  defp input({name, window}), do: [name(name), window(window)]

  # A short id and a path's names are written as atoms were, `{"$atom": name}`, and a
  # feed's own name as its string, so the JSON on disk is what it was (D-195).
  defp name(path) when is_list(path), do: Enum.map(path, &id/1)
  defp name({:feed, name}), do: to_string(name)
  defp name(name) when is_binary(name), do: id(name)
  defp name(name), do: Codec.encode_term(name)

  defp id(name) when is_binary(name), do: Tags.tag("$atom", name)
  defp id(name), do: Codec.encode_term(name)

  defp window(nil), do: nil
  defp window(%{last: n}), do: %{"last" => n}

  defp window(box) do
    Map.new(box, fn
      {:ranges, ranges} ->
        {"ranges",
         Enum.map(ranges, fn {field, range} ->
           [id(field), Enum.map(range, &Codec.encode_term/1)]
         end)}

      {:latest, latest} ->
        {"latest", latest}
    end)
  end

  # The output's fields, and a category field's values, are written as atoms were — the
  # source holds them as strings (D-195) — so the JSON on disk is what it was.
  defp spelled_schema(pairs) when is_list(pairs) do
    Enum.map(pairs, fn [name, description] -> [atom_term(name), spelled(description)] end)
  end

  defp spelled_schema(other), do: other

  defp spelled(description) do
    Map.new(description, fn
      {key, values} when key in ["values", "order"] and is_list(values) ->
        {key, Enum.map(values, &atom_term/1)}

      {"status", pairs} when is_list(pairs) ->
        {"status", Enum.map(pairs, fn [k, v] -> [atom_term(k), v] end)}

      attribute ->
        attribute
    end)
  end

  # A name held as a string, written as the atom it was.
  defp atom_term(name) when is_binary(name), do: Tags.tag("$atom", name)
  defp atom_term(other), do: other

  defp per(nil), do: nil
  defp per(:identity), do: "identity"
  defp per({:identity, name}), do: ["identity", name(name)]

  # -- decode ------------------------------------------------------------------------------

  @doc false
  # A source's JSON object as its map form.
  def decode(term) when is_map(term) do
    Map.new(term, fn {key, value} ->
      case known(key) do
        :from -> {:from, read_inputs(value)}
        :schema -> {:schema, SnapshotCodec.read_schema_json(value)}
        # A host function's name is the host's vocabulary: kept as its string, found in the
        # registry by spelling (spec/08 §10.5.8, D-195).
        :function when is_binary(value) -> {:function, value}
        :per -> {:per, read_per(value)}
        other -> {other, value}
      end
    end)
  end

  def decode(other), do: other

  defp read_inputs(inputs) when is_list(inputs) do
    Enum.map(inputs, fn
      [name, window] -> {read_name(name), read_window(window)}
      other -> other
    end)
  end

  defp read_inputs(other), do: other

  # A name written as an atom is a short id or a path's name, its string; a plain string is
  # a feed's own name (spec/08 §10.5.6, §10.5.10).
  defp read_name(path) when is_list(path), do: Enum.map(path, &read_id/1)
  defp read_name(name) when is_binary(name), do: {:feed, name}
  defp read_name(name), do: read_id(name)

  defp read_id(%{"$atom" => name} = term) when map_size(term) == 1 and is_binary(name), do: name
  defp read_id(other), do: Codec.decode_term(other)

  defp read_window(nil), do: nil
  defp read_window(%{"last" => n} = window) when map_size(window) == 1, do: %{last: n}

  defp read_window(box) when is_map(box) do
    Map.new(box, fn
      {"ranges", ranges} when is_list(ranges) -> {:ranges, read_ranges(ranges)}
      {"latest", latest} -> {:latest, latest}
      other -> other
    end)
  end

  defp read_window(other), do: other

  defp read_ranges(ranges) do
    if Enum.all?(ranges, &match?([_field, range] when is_list(range), &1)) do
      Map.new(ranges, fn [field, range] ->
        {Codec.decode_term(field), Enum.map(range, &Codec.decode_term/1)}
      end)
    else
      ranges
    end
  end

  defp read_per(nil), do: nil
  defp read_per("identity"), do: :identity
  defp read_per(["identity", name]), do: {:identity, read_name(name)}
  defp read_per(other), do: other

  defp known(key) when is_binary(key), do: Visualize.Vocabulary.read(@keys, key)
  defp known(key), do: key
end
