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

  # The source's own keys, looked up and never made atoms of (spec/14 §9.4, D-195).
  @keys Visualize.Vocabulary.table([:id, :from, :schema, :elixir, :function, :per])

  # -- encode ------------------------------------------------------------------------------

  @doc false
  # A source's canonical map form, its id taken off by the holder, as JSON terms.
  def encode(source) when is_map(source) do
    Map.new(source, fn
      {:from, inputs} -> {"from", Enum.map(inputs, &input/1)}
      {:schema, fields} -> {"schema", SnapshotCodec.schema_json(fields)}
      {:elixir, text} -> {"elixir", text}
      {:function, name} -> {"function", name && Atom.to_string(name)}
      {:per, per} -> {"per", per(per)}
      {key, value} -> {Atom.to_string(key), Codec.encode_term(value)}
    end)
  end

  defp input({name, window}), do: [name(name), window(window)]

  defp name(path) when is_list(path), do: Enum.map(path, &Codec.encode_term/1)
  defp name(name), do: Codec.encode_term(name)

  defp window(nil), do: nil
  defp window(%{last: n}), do: %{"last" => n}

  defp window(box) do
    Map.new(box, fn
      {:ranges, ranges} ->
        {"ranges",
         Enum.map(ranges, fn {field, range} ->
           [Codec.encode_term(field), Enum.map(range, &Codec.encode_term/1)]
         end)}

      {:latest, latest} ->
        {"latest", latest}
    end)
  end

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
        # #778 class (a-host): a host function's name, looked up in the host's registry.
        :function when is_binary(value) -> {:function, String.to_atom(value)}
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

  defp read_name(path) when is_list(path), do: Enum.map(path, &Codec.decode_term/1)
  defp read_name(name), do: Codec.decode_term(name)

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
