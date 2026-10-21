defmodule Visualize.Board.Snapshot.Codec do
  @moduledoc false
  # The JSON form of a snapshot (spec/15 §12.3): its map form with string keys, stamped
  # `"$version"`. The board is its own JSON form (spec/15 §2.2), each cell's component a
  # design's (spec/14 §11) and the theme a theme node's (spec/14 §9.3), so every document
  # inside a snapshot is spelled as it is on its own. Values JSON has no form for are the
  # tagged terms of spec/14 §11.2.
  #
  # Rows are written **column by column** — `{"fields": [name, …], "rows": [[value, …],
  # …]}` — so a field's name keeps the spelling it had, an atom (`{"$atom": "t"}`) or a
  # string, which a JSON object's keys could not; a row that lacks a field has
  # `{"$absent": true}` in its place. A schema's fields are a list of `[name,
  # description]` pairs for the same reason, and a description's `status`, which maps
  # category values to roles, a list of `[value, role]` pairs.
  #
  # Decoding never fails on a wrong shape: what it cannot place is passed through for the
  # reader to name. A key the snapshot does not know stays a string, so a misspelling makes
  # no atom and is reported at its own spelling.

  alias Visualize.Board.Codec, as: BoardCodec
  alias Visualize.Chart.Codec
  alias Visualize.Chart.Codec.Tags
  require Tags
  alias Visualize.Data.Schema
  alias Visualize.Vocabulary

  @stamp "$version"
  @absent Tags.tag("$absent", true)

  @keys [:board, :now, :window, :width, :theme, :cells]
  @cell_keys [:chart, :vars, :slots, :crashed]
  @slot_keys [:rows, :window, :resolution, :capped, :reduced_by, :version, :schema, :status]
  @statuses [:loading, :live, :stale]

  # The snapshot's own keys and words, looked up and never made atoms of (spec/14 §9.4).
  @key_table Vocabulary.table(@keys)
  @cell_key_table Vocabulary.table(@cell_keys)
  @slot_key_table Vocabulary.table(@slot_keys)
  @status_table Vocabulary.table(@statuses)
  @attribute_table Vocabulary.table(Schema.attributes())
  @entry_table Vocabulary.table(Schema.entry_keys())

  @doc false
  def stamp, do: @stamp

  @doc false
  def keys, do: @keys

  @doc false
  def cell_keys, do: @cell_keys

  @doc false
  def slot_keys, do: @slot_keys

  # -- encode ---------------------------------------------------------------------------

  @doc false
  def encode(%{version: version} = map) do
    %{
      @stamp => version,
      "board" => BoardCodec.encode(map.board),
      "now" => Codec.encode_term(map.now),
      "window" => Codec.encode_term(map.window),
      "width" => map.width,
      "theme" => Map.fetch!(Codec.encode(%{theme: map.theme}), "theme"),
      "cells" => Map.new(map.cells, fn {name, cell} -> {name(name), cell(cell)} end)
    }
  end

  defp cell(cell) do
    %{
      "chart" => Codec.encode(cell.chart),
      "vars" => Map.new(cell.vars, fn {k, v} -> {name(k), Codec.encode_term(v)} end),
      "slots" => slots(cell.slots),
      "crashed" => cell.crashed
    }
  end

  defp slots(nil), do: nil
  defp slots(slots), do: Map.new(slots, fn {name, slot} -> {name(name), slot(slot)} end)

  defp slot(slot) do
    %{
      "rows" => rows(slot.rows),
      "window" => Codec.encode_term(Map.get(slot, :window)),
      "resolution" => Codec.encode_term(Map.get(slot, :resolution)),
      "capped" => Map.get(slot, :capped),
      "reduced_by" => Codec.encode_term(Map.get(slot, :reduced_by)),
      "version" => slot.version,
      "schema" => schema_json(slot.schema),
      "status" => status(slot.status)
    }
  end

  defp rows(nil), do: nil

  defp rows(rows) do
    fields = rows |> Enum.flat_map(&Map.keys/1) |> Enum.uniq()

    %{
      "fields" => Enum.map(fields, &Codec.encode_term/1),
      "rows" =>
        Enum.map(rows, fn row ->
          Enum.map(fields, fn field ->
            case Map.fetch(row, field) do
              {:ok, value} -> Codec.encode_term(value)
              :error -> @absent
            end
          end)
        end)
    }
  end

  @doc false
  # A schema's fields as `[name, description]` pairs; a virtual source writes its schema
  # so too (spec/08 §10.5.10).
  def schema_json(nil), do: nil

  def schema_json(fields) do
    fields
    |> Enum.sort_by(fn {name, _} -> to_string(name) end)
    |> Enum.map(fn {name, description} -> [Codec.encode_term(name), description(description)] end)
  end

  defp description(description) do
    Map.new(description, fn
      {:values, values} when is_list(values) ->
        {"values", Enum.map(values, &value_entry/1)}

      {:status, status} when is_map(status) ->
        {"status",
         Enum.map(status, fn {k, v} -> [Codec.encode_term(k), Codec.encode_term(v)] end)}

      {key, value} ->
        {Atom.to_string(key), Codec.encode_term(value)}
    end)
  end

  # A value entry is the object of its keys, its color in a design's color form; a bare
  # value is its term, never an object with a `value` key (spec/08 §10.5.10, D-224).
  defp value_entry(entry) when is_map(entry) and not is_struct(entry) do
    Map.new(entry, fn
      {:color, color} -> {"color", Codec.encode_color(color)}
      {key, value} -> {to_string(key), Codec.encode_term(value)}
    end)
  end

  defp value_entry(value), do: Codec.encode_term(value)

  defp status({:down, reason}), do: %{"down" => reason}
  defp status(status), do: Atom.to_string(status)

  # -- decode ---------------------------------------------------------------------------

  @doc false
  # A parsed document, its stamp already taken off, as the snapshot's map.
  def decode(term) do
    Map.new(term, fn {key, value} ->
      case known(key, @key_table) do
        :board -> {:board, board(value)}
        :now -> {:now, Codec.decode_term(value)}
        :window -> {:window, Codec.decode_term(value)}
        :theme -> {:theme, theme(value)}
        :cells -> {:cells, names(value, &read_cell/1)}
        other -> {other, value}
      end
    end)
  end

  defp board(term) when is_map(term) do
    {stamp, term} = Map.pop(term, @stamp)
    map = BoardCodec.decode(term)
    if stamp == nil, do: map, else: Map.put(map, :version, stamp)
  end

  defp board(other), do: other

  defp theme(term) when is_map(term), do: Map.fetch!(Codec.decode(%{"theme" => term}), :theme)
  defp theme(other), do: other

  defp read_cell(cell) when is_map(cell) do
    Map.new(cell, fn {key, value} ->
      case known(key, @cell_key_table) do
        :chart -> {:chart, Codec.decode(value)}
        :vars -> {:vars, names(value, &Codec.decode_term/1)}
        :slots -> {:slots, names(value, &read_slot/1)}
        other -> {other, value}
      end
    end)
  end

  defp read_cell(other), do: other

  defp read_slot(slot) when is_map(slot) do
    Map.new(slot, fn {key, value} ->
      case known(key, @slot_key_table) do
        :rows -> {:rows, read_rows(value)}
        :schema -> {:schema, read_schema_json(value)}
        :status -> {:status, read_status(value)}
        key when key in [:window, :resolution, :reduced_by] -> {key, Codec.decode_term(value)}
        other -> {other, value}
      end
    end)
  end

  defp read_slot(other), do: other

  defp read_rows(%{"fields" => fields, "rows" => rows} = term)
       when map_size(term) == 2 and is_list(fields) and is_list(rows) do
    names = Enum.map(fields, &Codec.decode_term/1)

    Enum.map(rows, fn
      values when is_list(values) and length(values) == length(names) ->
        names
        |> Enum.zip(values)
        |> Enum.reject(fn {_name, value} -> value == @absent end)
        |> Map.new(fn {name, value} -> {name, Codec.decode_term(value)} end)

      other ->
        other
    end)
  end

  defp read_rows(other), do: other

  @doc false
  def read_schema_json(pairs) when is_list(pairs) do
    if Enum.all?(pairs, &match?([_name, description] when is_map(description), &1)) do
      Map.new(pairs, fn [name, description] ->
        {Codec.decode_term(name), read_description(description)}
      end)
    else
      pairs
    end
  end

  def read_schema_json(other), do: other

  defp read_description(description) do
    Map.new(description, fn {key, value} ->
      case known(key, @attribute_table) do
        :status when is_list(value) -> {:status, read_pairs(value)}
        :values when is_list(value) -> {:values, Enum.map(value, &read_value_entry/1)}
        key when is_atom(key) -> {key, Codec.decode_term(value)}
        key -> {key, value}
      end
    end)
  end

  # An object with a `value` key is an entry, its keys looked up and never made atoms of: a
  # key no entry has stays its string, for `Schema.new/1` to refuse.
  defp read_value_entry(%{"value" => _} = entry) do
    Map.new(entry, fn {key, value} ->
      case known(key, @entry_table) do
        :color -> {:color, Codec.decode_color(value)}
        :name -> {:name, value}
        key -> {key, Codec.decode_term(value)}
      end
    end)
  end

  defp read_value_entry(value), do: Codec.decode_term(value)

  defp read_pairs(pairs) do
    if Enum.all?(pairs, &match?([_k, _v], &1)),
      do: Map.new(pairs, fn [k, v] -> {Codec.decode_term(k), Codec.decode_term(v)} end),
      else: pairs
  end

  defp read_status(%{"down" => reason} = term) when map_size(term) == 1, do: {:down, reason}

  defp read_status(status) when is_binary(status),
    do: Vocabulary.read(@status_table, status)

  defp read_status(other), do: other

  defp names(map, read) when is_map(map),
    do: Map.new(map, fn {name, value} -> {read_name(name), read.(value)} end)

  defp names(other, _read), do: other

  # A key the snapshot knows, as its atom; any other key as it was read.
  defp known(key, keys) when is_binary(key), do: Vocabulary.read(keys, key)

  defp known(key, _keys), do: key

  # A name that starts with `$` is written with one more and read with one fewer (D-182).
  defp name(key), do: key |> to_string() |> Tags.escape()

  # A cell's, a variable's or a slot's name is its string (D-195).
  defp read_name(key) when is_binary(key), do: Tags.unescape(key)
  defp read_name(key), do: key
end
