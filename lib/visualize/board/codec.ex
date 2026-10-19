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

  @stamp "$version"
  @datum "$datum"

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

  defp drill_var({name, {:datum, field}}) when is_atom(field),
    do: {name(name), Tags.tag("$datum", Atom.to_string(field))}

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
      case known(key, Validator.board_keys()) do
        :cells -> {:cells, cells(value)}
        :vars -> {:vars, names(value)}
        :window -> {:window, keyed(value, [:last, :from, :to])}
        :meta -> {:meta, keyed(value, Validator.meta_keys())}
        :layout -> {:layout, keyed(value, Validator.layout_keys())}
        :zone -> {:zone, value}
        :sync -> {:sync, value}
        :links -> {:links, links(value)}
        :virtual_sources -> {:virtual_sources, read_sources(value)}
        other -> {other, value}
      end
    end)
  end

  defp cells(cells) when is_map(cells),
    do: Map.new(cells, fn {name, cell} -> {atom(name), read_cell(cell)} end)

  defp cells(other), do: other

  defp read_cell(cell) when is_map(cell) do
    Map.new(cell, fn {key, value} ->
      case known(key, Validator.cell_keys()) do
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
      case known(key, Validator.drill_keys()) do
        :vars -> {:vars, drill_vars(value)}
        other -> {other, Codec.decode_term(value)}
      end
    end)
  end

  defp read_drill(other), do: other

  defp drill_vars(vars) when is_map(vars) do
    Map.new(vars, fn
      {name, %{@datum => field} = v} when map_size(v) == 1 and is_binary(field) ->
        {atom(name), {:datum, String.to_atom(field)}}

      {name, value} ->
        {atom(name), Codec.decode_term(value)}
    end)
  end

  defp drill_vars(other), do: other

  defp read_sources(sources) when is_map(sources),
    do: Map.new(sources, fn {id, source} -> {atom(id), VirtualSourceCodec.decode(source)} end)

  defp read_sources(other), do: other

  defp links(links) when is_map(links),
    do: Map.new(links, fn {from, to} -> {atom(from), atom(to)} end)

  defp links(other), do: other

  defp names(map) when is_map(map),
    do: Map.new(map, fn {name, value} -> {atom(name), Codec.decode_term(value)} end)

  defp names(other), do: other

  defp keyed(map, keys) when is_map(map),
    do: Map.new(map, fn {key, value} -> {known(key, keys), Codec.decode_term(value)} end)

  defp keyed(other, _keys), do: other

  # A key the board knows, as its atom; any other key as it was read.
  defp known(key, keys) when is_binary(key) do
    Enum.find(keys, key, &(Atom.to_string(&1) == key))
  end

  defp known(key, _keys), do: key

  defp atom(key) when is_binary(key), do: key |> Tags.unescape() |> String.to_atom()
  defp atom(key), do: key
end
