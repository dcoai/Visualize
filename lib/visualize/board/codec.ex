defmodule Visualize.Board.Codec do
  @moduledoc false
  # The JSON form of a board (spec/15 §2.2): the map form with string keys and the
  # version as the `"$version"` stamp. Terms JSON has no form for — a component id, a
  # window's time, an atom in a variable's value — are spec/14 §11.2's tagged terms,
  # written and read by the design's codec so the two documents spell a term alike.
  #
  # Decoding never fails on a wrong shape: a value it cannot place is passed through for
  # the validator to name. A key the board does not know stays a string, so a misspelling
  # makes no atom and is reported at its own spelling. A cell's name and a variable's name
  # are made atoms, as a design's names are (spec/14 §11.1). A drill variable taken from a
  # datum is the board's own tag, `{"$datum": field}`, and `links` is names to names
  # (spec/15 §2.2, §13). A virtual source, the board's or a cell's, is its own JSON form
  # under its id (spec/08 §10.5.10).

  alias Visualize.Board.Validator
  alias Visualize.Chart.Codec
  alias Visualize.Chart.Codec.Tags
  require Tags
  alias Visualize.VirtualSource.Codec, as: VirtualSourceCodec
  alias Visualize.Vocabulary

  @stamp "$version"
  @datum "$datum"

  # The board's own keys, looked up and never made atoms of (spec/14 §9.4, D-195).
  @board_keys Vocabulary.table(Validator.board_keys())
  @cell_keys Vocabulary.table(Validator.cell_keys())
  @drill_keys Vocabulary.table(Validator.drill_keys())
  @window_keys Vocabulary.table([:last, :from, :to])
  @meta_keys Vocabulary.table(Validator.meta_keys())
  @layout_keys Vocabulary.table(Validator.layout_keys())

  @doc false
  def stamp, do: @stamp

  # -- encode ---------------------------------------------------------------------------

  @doc false
  def encode(%{version: version} = map) do
    map
    |> Map.delete(:version)
    |> Map.new(fn {key, value} -> {Atom.to_string(key), encode(key, value)} end)
    |> Map.put(@stamp, version)
  end

  defp encode(:cells, cells), do: Map.new(cells, fn {name, cell} -> {name(name), cell(cell)} end)
  defp encode(:links, links), do: Map.new(links, fn {from, to} -> {name(from), name(to)} end)
  defp encode(:virtual_sources, sources), do: sources(sources)
  defp encode(_key, value), do: plain(value)

  defp cell(cell) do
    Map.new(cell, fn
      {:drill, %{} = drill} -> {"drill", drill(drill)}
      {:virtual_sources, sources} -> {"virtual_sources", sources(sources)}
      {key, value} -> {Atom.to_string(key), plain(value)}
    end)
  end

  defp drill(drill) do
    Map.new(drill, fn
      {:vars, vars} when is_map(vars) -> {"vars", Map.new(vars, &drill_var/1)}
      {key, value} -> {Atom.to_string(key), Codec.encode_term(value)}
    end)
  end

  defp drill_var({name, {:datum, field}}) when is_atom(field) or is_binary(field),
    do: {name(name), Tags.tag("$datum", to_string(field))}

  defp drill_var({name, value}), do: {name(name), Codec.encode_term(value)}

  # Virtual sources by id, each in its own JSON form (spec/08 §10.5.10).
  defp sources(sources),
    do: Map.new(sources, fn {id, source} -> {name(id), VirtualSourceCodec.encode(source)} end)

  # A map with name keys, its values as tagged terms.
  defp plain(map) when is_map(map) and not is_struct(map),
    do: Map.new(map, fn {key, value} -> {name(key), Codec.encode_term(value)} end)

  defp plain(value), do: Codec.encode_term(value)

  # A name that starts with `$` is written with one more, as a design's keys are (D-182).
  defp name(key) when is_atom(key), do: key |> Atom.to_string() |> Tags.escape()
  defp name(key), do: key |> to_string() |> Tags.escape()

  # -- decode ---------------------------------------------------------------------------

  @doc false
  # A parsed document, its stamp already taken off, as the board map.
  def decode(term) when is_map(term) do
    Map.new(term, fn {key, value} ->
      case known(key, @board_keys) do
        :cells -> {:cells, cells(value)}
        :vars -> {:vars, names(value)}
        :window -> {:window, keyed(value, @window_keys)}
        :meta -> {:meta, keyed(value, @meta_keys)}
        :layout -> {:layout, keyed(value, @layout_keys)}
        :zone -> {:zone, value}
        :sync -> {:sync, value}
        :links -> {:links, links(value)}
        :virtual_sources -> {:virtual_sources, read_sources(value)}
        other -> {other, value}
      end
    end)
  end

  defp cells(cells) when is_map(cells),
    do: Map.new(cells, fn {name, cell} -> {read_name(name), read_cell(cell)} end)

  defp cells(other), do: other

  defp read_cell(cell) when is_map(cell) do
    Map.new(cell, fn {key, value} ->
      case known(key, @cell_keys) do
        :ref -> {:ref, Codec.decode_term(value)}
        :vars -> {:vars, names(value)}
        :drill -> {:drill, read_drill(value)}
        :virtual_sources -> {:virtual_sources, read_sources(value)}
        other -> {other, value}
      end
    end)
  end

  defp read_cell(other), do: other

  defp read_drill(drill) when is_map(drill) do
    Map.new(drill, fn {key, value} ->
      case known(key, @drill_keys) do
        :vars -> {:vars, drill_vars(value)}
        other -> known_value(other, value)
      end
    end)
  end

  defp read_drill(other), do: other

  defp drill_vars(vars) when is_map(vars) do
    Map.new(vars, fn
      {name, %{@datum => field} = v} when map_size(v) == 1 and is_binary(field) ->
        {read_name(name), {:datum, field}}

      {name, value} ->
        {read_name(name), Codec.decode_term(value)}
    end)
  end

  defp drill_vars(other), do: other

  defp read_sources(sources) when is_map(sources),
    do:
      Map.new(sources, fn {id, source} -> {read_name(id), VirtualSourceCodec.decode(source)} end)

  defp read_sources(other), do: other

  defp links(links) when is_map(links),
    do: Map.new(links, fn {from, to} -> {read_name(from), read_name(to)} end)

  defp links(other), do: other

  defp names(map) when is_map(map),
    do: Map.new(map, fn {name, value} -> {read_name(name), Codec.decode_term(value)} end)

  defp names(other), do: other

  defp keyed(map, keys) when is_map(map),
    do: Map.new(map, fn {key, value} -> key |> known(keys) |> known_value(value) end)

  defp keyed(other, _keys), do: other

  # A known key's value is read as a term; an unknown key's is left as parsed, so nothing
  # under a key the board refuses is made an atom (spec/14 §9.4).
  defp known_value(key, value) when is_atom(key), do: {key, Codec.decode_term(value)}
  defp known_value(key, value), do: {key, value}

  # A key the board knows, as its atom; any other key as it was read.
  defp known(key, keys) when is_binary(key), do: Vocabulary.read(keys, key)

  defp known(key, _keys), do: key

  # A cell's, a variable's, a link's or a virtual source's name is its string (D-195).
  defp read_name(key) when is_binary(key), do: Tags.unescape(key)
  defp read_name(key), do: key
end
