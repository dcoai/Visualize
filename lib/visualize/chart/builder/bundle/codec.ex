if Code.ensure_loaded?(Phoenix.Component) do
  defmodule Visualize.Chart.Builder.Bundle.Codec do
    @moduledoc false
    # A bundle's map form and its JSON form (spec/14 §19.7, #818, D-217), behind
    # `Visualize.Chart.Builder.Bundle.to_map/1`, `from_map/2`, `to_json/1` and `from_json/2`.
    #
    # The JSON document is the map form with string keys, stamped `"$version"`: the
    # provenance with `exported_at` in ISO 8601 and `store` as D-217 writes it, each entry
    # `{"id", "name", "fragment"}` with the id as `Store.encode_id/1` writes it and the
    # fragment as the document `Fragment.to_json/1` writes, and the board in its own JSON
    # form (spec/15 §2.2). Each part is read by its own reader — the fragment's, the board's
    # — so each is gated and held to the tag table as it is alone, and a bundle cut apart
    # gives a host fragment documents it can store as they are.
    #
    # The map form is read the same way in both directions: the version gates first (the
    # document's stamp, then the provenance's `schema`), then the limits over the whole,
    # then each key, every fault at its path. No atom is made from a document (D-195): a
    # key is looked up in this module's own lists, an id's kind in the fragment kinds.

    alias Visualize.Board
    alias Visualize.Board.Codec, as: BoardCodec
    alias Visualize.Board.Validator, as: BoardValidator
    alias Visualize.Chart.Builder.Bundle
    alias Visualize.Chart.Builder.Store
    alias Visualize.Chart.Codec, as: ChartCodec
    alias Visualize.Chart.Codec.Tags
    alias Visualize.Chart.{Fragment, Limits, Migration}
    alias Visualize.Vocabulary

    @compile {:no_warn_undefined, Jason}

    @stamp "$version"
    @keys [:provenance, :entries, :board]
    @provenance_keys [:store, :exported_at, :schema]
    # An entry's `kind` is derived from its fragment (spec/14 §19.8): a store's entry carries
    # it, and the map form takes one and reads the fragment's instead.
    @entry_keys [:id, :name, :fragment]
    @bundle_words Vocabulary.table(@keys)
    @provenance_words Vocabulary.table(@provenance_keys)
    @entry_words Vocabulary.table(@entry_keys)

    # -- the map form ---------------------------------------------------------------------

    @doc false
    def to_map(%Bundle{} = bundle) do
      %{
        provenance: Map.take(bundle.provenance, @provenance_keys),
        entries: Enum.map(bundle.entries, &Map.take(&1, @entry_keys)),
        board: bundle.board
      }
    end

    @doc false
    def from_map(map, opts) do
      limits = opts |> Keyword.get(:limits, []) |> Limits.new()

      with :ok <- object(map, []),
           :ok <- schema(map),
           :ok <- BoardValidator.done(Limits.structure(map, limits)) do
        read(map, opts)
      end
    end

    defp object(map, _path) when is_map(map) and not is_struct(map), do: :ok
    defp object(_other, path), do: {:error, [{path, {:type, :bundle}}]}

    defp schema(%{provenance: %{schema: schema}}) do
      with {:error, reason} <- Migration.readable(schema),
           do: {:error, [{[:provenance, :schema], reason}]}
    end

    defp schema(_map), do: :ok

    defp read(map, opts) do
      %{provenance: provenance, entries: entries} =
        Map.merge(%{provenance: nil, entries: nil}, map)

      {board, board_faults} = read_board(Map.get(map, :board), opts)

      faults =
        unknown(map, @keys, []) ++
          provenance_faults(provenance) ++ entries_faults(entries) ++ board_faults

      with :ok <- BoardValidator.done(faults) do
        {:ok,
         %Bundle{
           provenance: provenance,
           entries:
             Enum.map(entries, fn entry ->
               %{
                 id: entry.id,
                 name: entry.name,
                 kind: Fragment.kind(entry.fragment),
                 fragment: entry.fragment
               }
             end),
           board: board
         }}
      end
    end

    defp unknown(map, keys, path),
      do: for(key <- Map.keys(map), key not in keys, do: {path ++ [key], :unknown_key})

    defp provenance_faults(nil), do: [{[:provenance], :required}]

    defp provenance_faults(p) when is_map(p) and not is_struct(p) do
      unknown(p, @provenance_keys, [:provenance]) ++
        required(p, @provenance_keys, [:provenance]) ++
        check(p, :store, &term?/1, :term) ++
        check(p, :exported_at, &match?(%DateTime{time_zone: "Etc/UTC"}, &1), :utc_datetime) ++
        check(p, :schema, &(is_integer(&1) and &1 > 0), :pos_integer)
    end

    defp provenance_faults(_other), do: [{[:provenance], {:type, :provenance}}]

    defp required(map, keys, path),
      do: for(key <- keys, not Map.has_key?(map, key), do: {path ++ [key], :required})

    defp check(p, key, ok?, type) do
      case Map.fetch(p, key) do
        {:ok, value} -> if ok?.(value), do: [], else: [{[:provenance, key], {:type, type}}]
        :error -> []
      end
    end

    defp entries_faults(nil), do: [{[:entries], :required}]

    defp entries_faults(entries) when is_list(entries) do
      {faults, _seen} =
        entries
        |> Enum.with_index()
        |> Enum.reduce({[], %{}}, fn {entry, i}, {faults, seen} ->
          {entry_faults(entry, [:entries, i], seen) ++ faults, see(seen, entry, i)}
        end)

      faults
    end

    defp entries_faults(_other), do: [{[:entries], {:type, {:list, :entry}}}]

    defp see(seen, %{id: id}, i), do: Map.put_new(seen, id, i)
    defp see(seen, _entry, _i), do: seen

    defp entry_faults(entry, path, seen) when is_map(entry) and not is_struct(entry) do
      unknown(Map.delete(entry, :kind), @entry_keys, path) ++
        required(entry, @entry_keys, path) ++
        id_faults(entry, path, seen) ++
        field(entry, :name, &is_binary/1, :string, path) ++
        field(entry, :fragment, &(is_map(&1) and not is_struct(&1)), :fragment, path)
    end

    defp entry_faults(_other, path, _seen), do: [{path, {:type, :entry}}]

    defp id_faults(%{id: id}, path, seen) do
      cond do
        not id?(id) -> [{path ++ [:id], {:type, :id}}]
        Map.has_key?(seen, id) -> [{path ++ [:id], {:duplicate, id}}]
        true -> []
      end
    end

    defp id_faults(_entry, _path, _seen), do: []

    defp id?({kind, n}) when is_atom(kind) and is_integer(n) and n > 0,
      do: kind in Fragment.kinds()

    defp id?(_other), do: false

    defp field(entry, key, ok?, type, path) do
      case Map.fetch(entry, key) do
        {:ok, value} -> if ok?.(value), do: [], else: [{path ++ [key], {:type, type}}]
        :error -> []
      end
    end

    # A board is read by the board's own reader and kept in its map form (spec/15 §2.1).
    defp read_board(nil, _opts), do: {nil, []}

    defp read_board(map, opts) do
      case Board.from_map(map, limits: Keyword.get(opts, :limits, [])) do
        {:ok, board} -> {Board.to_map(board), []}
        {:error, errors} -> {nil, prefix(errors, [:board])}
      end
    end

    # A store is named by a string, or by any term the tag table writes (D-217).
    defp term?(%DateTime{}), do: true
    defp term?({kind, n} = id) when is_atom(kind) and is_integer(n), do: id?(id)
    defp term?(v) when is_number(v) or is_binary(v) or is_atom(v), do: true
    defp term?(v) when is_list(v), do: Enum.all?(v, &term?/1)

    defp term?(v) when is_map(v) and not is_struct(v),
      do: Enum.all?(v, fn {k, e} -> (is_atom(k) or is_binary(k)) and term?(e) end)

    defp term?(_other), do: false

    # -- the JSON form --------------------------------------------------------------------

    @doc false
    def to_json(%Bundle{} = bundle) do
      cond do
        not Code.ensure_loaded?(Jason) ->
          {:error, {:missing_dependency, :jason}}

        not term?(Map.get(bundle.provenance, :store)) ->
          {:error, [{[:provenance, :store], {:type, :term}}]}

        true ->
          {:ok, json} = bundle |> document() |> Jason.encode()
          {:ok, json}
      end
    end

    defp document(bundle) do
      %{provenance: p, entries: entries, board: board} = to_map(bundle)

      %{
        @stamp => Migration.current(),
        "provenance" => %{
          "store" => store(Map.get(p, :store)),
          "exported_at" => DateTime.to_iso8601(p.exported_at),
          "schema" => p.schema
        },
        "entries" =>
          Enum.map(entries, fn entry ->
            %{
              "id" => Store.encode_id(entry.id),
              "name" => entry.name,
              "fragment" => Fragment.document(entry.fragment)
            }
          end)
      }
      |> put_board(board)
    end

    # A store named by an atom is named by its spelling, the string a name is (spec/14
    # §1.4, D-195, D-217); any other term is its tagged term.
    defp store(name) when is_atom(name) and name not in [nil, true, false],
      do: Atom.to_string(name)

    defp store(term), do: ChartCodec.encode_term(term)

    defp put_board(document, nil), do: document

    defp put_board(document, board),
      do:
        Map.put(
          document,
          "board",
          board |> Map.put_new(:version, Migration.current()) |> BoardCodec.encode()
        )

    @doc false
    def from_json(json, opts) do
      if Code.ensure_loaded?(Jason) do
        limits = opts |> Keyword.get(:limits, []) |> Limits.new()

        case Jason.decode(json) do
          {:ok, term} when is_map(term) ->
            read_json(term, limits, opts)

          {:ok, other} ->
            {:error, [{[], {:json, "a bundle is an object, got #{inspect(other)}"}}]}

          {:error, error} ->
            {:error, [{[], {:json, Exception.message(error)}}]}
        end
      else
        {:error, {:missing_dependency, :jason}}
      end
    end

    # The stamp, then the provenance's schema, then the limits over the document as it
    # was written — each before a key is decoded — then each part by its own reader.
    defp read_json(term, limits, opts) do
      {stamp, term} = Map.pop(term, @stamp)

      with :ok <- gate(stamp, [@stamp]),
           :ok <- gate(json_schema(term), [:provenance, :schema]),
           :ok <- BoardValidator.done(Limits.structure(term, limits)),
           {:ok, map} <- decode(term, opts) do
        from_map(map, opts)
      end
    end

    defp gate(version, path) do
      with {:error, reason} <- Migration.readable(version), do: {:error, [{path, reason}]}
    end

    defp json_schema(%{"provenance" => %{"schema" => schema}}), do: schema
    defp json_schema(_term), do: nil

    # The document's keys by this module's own words; a key it does not know stays the
    # string it was, for `from_map/2` to report at its own spelling.
    defp decode(term, opts) do
      {map, faults} =
        Enum.reduce(term, {%{}, []}, fn {key, value}, {map, faults} ->
          case Vocabulary.fetch(@bundle_words, key) do
            {:ok, :provenance} -> part(map, faults, :provenance, provenance(value))
            {:ok, :entries} -> part(map, faults, :entries, entries(value, opts))
            {:ok, :board} -> part(map, faults, :board, board(value, opts))
            :error -> {Map.put(map, key, value), faults}
          end
        end)

      with :ok <- BoardValidator.done(faults), do: {:ok, map}
    end

    defp part(map, faults, key, {:ok, value}), do: {Map.put(map, key, value), faults}
    defp part(map, faults, key, {:error, errors}), do: {Map.put(map, key, nil), faults ++ errors}

    defp provenance(p) when is_map(p) do
      Enum.reduce(p, {:ok, %{}}, fn {key, value}, acc ->
        case Vocabulary.fetch(@provenance_words, key) do
          {:ok, :store} -> put(acc, :store, read_store(value))
          {:ok, :exported_at} -> put(acc, :exported_at, read_time(value))
          {:ok, :schema} -> put(acc, :schema, {:ok, value})
          :error -> put(acc, key, {:ok, value})
        end
      end)
    end

    defp provenance(other), do: {:ok, other}

    defp put({:ok, map}, key, {:ok, value}), do: {:ok, Map.put(map, key, value)}
    defp put({:ok, _map}, _key, {:error, errors}), do: {:error, errors}
    defp put({:error, errors}, _key, {:ok, _value}), do: {:error, errors}
    defp put({:error, errors}, _key, {:error, more}), do: {:error, errors ++ more}

    # A string is the store's name; anything else is a term, held to the tag table first
    # (D-182) and read by it, so no atom is made of a document's spelling (D-195).
    defp read_store(name) when is_binary(name), do: {:ok, name}

    defp read_store(term) do
      case Tags.read(term, Migration.current()) do
        {:ok, term} -> {:ok, ChartCodec.decode_term(term)}
        {:error, errors} -> {:error, prefix(errors, [:provenance, :store])}
      end
    end

    defp read_time(iso) when is_binary(iso) do
      case DateTime.from_iso8601(iso) do
        {:ok, time, _offset} -> {:ok, time}
        {:error, _reason} -> {:error, [{[:provenance, :exported_at], {:type, :utc_datetime}}]}
      end
    end

    defp read_time(_other), do: {:error, [{[:provenance, :exported_at], {:type, :utc_datetime}}]}

    defp entries(entries, opts) when is_list(entries) do
      entries
      |> Enum.with_index()
      |> Enum.reduce({:ok, []}, fn {entry, i}, acc ->
        case {acc, entry(entry, [:entries, i], opts)} do
          {{:ok, list}, {:ok, entry}} -> {:ok, [entry | list]}
          {{:ok, _list}, {:error, errors}} -> {:error, errors}
          {{:error, errors}, {:ok, _entry}} -> {:error, errors}
          {{:error, errors}, {:error, more}} -> {:error, errors ++ more}
        end
      end)
      |> case do
        {:ok, list} -> {:ok, Enum.reverse(list)}
        error -> error
      end
    end

    defp entries(other, _opts), do: {:ok, other}

    defp entry(entry, path, opts) when is_map(entry) do
      Enum.reduce(entry, {:ok, %{}}, fn {key, value}, acc ->
        case Vocabulary.fetch(@entry_words, key) do
          {:ok, :id} -> put(acc, :id, read_id(value, path))
          {:ok, :name} -> put(acc, :name, {:ok, value})
          {:ok, :fragment} -> put(acc, :fragment, read_fragment(value, path ++ [:fragment], opts))
          :error -> put(acc, key, {:ok, value})
        end
      end)
    end

    defp entry(other, _path, _opts), do: {:ok, other}

    # An id is read by the store's own reader: its kind one a fragment can have, so no atom
    # is made from a document's kind (D-195).
    defp read_id(string, path) when is_binary(string) do
      case Store.decode_id(string) do
        {:ok, id} -> {:ok, id}
        :error -> {:error, [{path ++ [:id], {:type, :id}}]}
      end
    end

    defp read_id(_other, path), do: {:error, [{path ++ [:id], {:type, :id}}]}

    defp read_fragment(document, path, opts) when is_map(document) do
      case Fragment.read_document(document, opts) do
        {:ok, fragment, _version} -> {:ok, fragment}
        {:error, {:newer_schema, _, _} = reason} -> {:error, [{path ++ [@stamp], reason}]}
        {:error, {_class, errors}} -> {:error, prefix(errors, path)}
      end
    end

    defp read_fragment(_other, path, _opts), do: {:error, [{path, {:type, :fragment}}]}

    defp board(nil, _opts), do: {:ok, nil}

    defp board(document, opts) when is_map(document) do
      case Board.read_document(document, opts) do
        {:ok, board} -> {:ok, Board.to_map(board)}
        {:error, errors} -> {:error, prefix(errors, [:board])}
      end
    end

    defp board(_other, _opts), do: {:error, [{[:board], {:type, :board}}]}

    defp prefix(errors, path), do: Enum.map(errors, fn {at, reason} -> {path ++ at, reason} end)
  end
end
