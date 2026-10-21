defmodule Visualize.Chart.Codec.Tags do
  @moduledoc false
  # The one table of `$` tags (spec/14 §11.2, D-182): every tag a JSON document of this
  # library writes — a design's and a fragment's (`Visualize.Chart.Codec`), a board's
  # `$datum`, a snapshot's `$absent`, and the `$version` stamp — and the tags it no longer
  # writes, retired with what replaced them or renamed to their new spelling.
  #
  # Both directions read it. An encoder writes a tag only through `tag/2`, which refuses at
  # compile time a literal name the table does not list as live, so no tag is written that
  # the reader does not know. Every JSON reader holds the parsed document to the table with
  # `read/2` before decoding: a one-key object whose key starts with a single `$` is always
  # a tag, and one the table does not have is refused at its path, never read as data.
  #
  # Data may have `$` keys — a term is any value — so every map key the codecs write that
  # starts with `$` is escaped with one more (`escape/1`) and read back with one fewer
  # (`unescape/1`). A document before version 3 predates the escape: its `$` keys are data.

  @unary Visualize.Color.Typed.ops()

  # The tags written today. A transform of a color (`$intensity`, `$alpha`, …) is one per
  # operation of `Visualize.Color.Typed.ops/0`, so a new operation is a tag by construction.
  @live ~w($var $field $generate $paint $ramp $color $blend $contrast $steps $colors
           $series $unit $scale $axis $frame $data $adopted $keys $fact $use $id $time $atom
           $per_px $datum $absent $version) ++ Enum.map(@unary, &"$#{&1}")

  # A tag no longer written, refused with what replaced it.
  @retired %{
    "$styles" =>
      "was removed in #644: a style site names a style by data with {:field, f} (spec/14 §3.13)"
  }

  # A tag written under another name now, read as the new one (old => new): the British
  # spellings before #642 (D-183).
  # spelling: allow — the old tag a stored document holds.
  @renamed %{"$colours" => "$colors"}

  # The first version whose documents escape their data's `$` keys.
  @escaped_from 3

  @doc false
  def live, do: @live

  @doc false
  def retired, do: @retired

  @doc false
  def renamed, do: @renamed

  @doc false
  # The one-key object of a tag. A literal name the table does not list as live is a
  # compile error; a computed one must be live when it is called.
  defmacro tag(name, payload) when is_binary(name) do
    if name not in @live do
      raise CompileError,
        file: __CALLER__.file,
        line: __CALLER__.line,
        description: "#{inspect(name)} is not a live tag of Visualize.Chart.Codec.Tags"
    end

    quote do: %{unquote(name) => unquote(payload)}
  end

  defmacro tag(name, payload) do
    quote do: Visualize.Chart.Codec.Tags.tag!(unquote(name), unquote(payload))
  end

  @doc false
  def tag!(name, payload) when name in @live, do: %{name => payload}

  @doc false
  # A map key as a document writes it: a key that starts with `$` gets one more.
  def escape("$" <> _ = key), do: "$" <> key
  def escape(key) when is_binary(key), do: key

  @doc false
  # A map key as a document holds it, read: a key that starts with `$$` loses one.
  def unescape("$$" <> rest), do: "$" <> rest
  def unescape(key), do: key

  @doc false
  # The parsed document held to the table, `version` the document's own (`nil` or not an
  # integer is read as the current one): a renamed tag rewritten to its new name, and every
  # unknown or retired tag an error at the path of its object, in path order. A document
  # before version 3 has its data's `$` keys escaped here, so the decoders read one form.
  @spec read(term(), term()) :: {:ok, term()} | {:error, [{list(), term()}, ...]}
  def read(term, version) do
    escaped? = not (is_integer(version) and version < @escaped_from)

    case walk(term, [], escaped?) do
      {term, []} -> {:ok, term}
      {_term, errors} -> {:error, Enum.sort_by(errors, &elem(&1, 0))}
    end
  end

  defp walk(map, path, escaped?) when is_map(map) and map_size(map) == 1 do
    [{key, value}] = Map.to_list(map)

    case tag_of(key) do
      nil -> data(map, path, escaped?)
      tag -> tagged(tag, value, map, path, escaped?)
    end
  end

  defp walk(map, path, escaped?) when is_map(map), do: data(map, path, escaped?)

  defp walk(list, path, escaped?) when is_list(list) do
    {items, errors} =
      list
      |> Enum.with_index()
      |> Enum.map(fn {item, i} -> walk(item, path ++ [i], escaped?) end)
      |> Enum.unzip()

    {items, Enum.concat(errors)}
  end

  defp walk(leaf, _path, _escaped?), do: {leaf, []}

  defp tagged(tag, value, map, path, escaped?) do
    cond do
      tag in @live ->
        {value, errors} = walk(value, path ++ [tag], escaped?)
        {%{tag => value}, errors}

      new = renamed()[tag] ->
        tagged(new, value, map, path, escaped?)

      why = retired()[tag] ->
        {map, [{path, {:retired_tag, tag, why}}]}

      escaped? ->
        {map, [{path, {:unknown_tag, tag}}]}

      # Before the escape, a one-key object the table does not have was data.
      true ->
        data(map, path, escaped?)
    end
  end

  defp data(map, path, escaped?) do
    {pairs, errors} =
      map
      |> Enum.map(fn {key, value} ->
        {value, errors} = walk(value, path ++ [key], escaped?)
        {{legacy_key(key, escaped?), value}, errors}
      end)
      |> Enum.unzip()

    {Map.new(pairs), Enum.concat(errors)}
  end

  # A data key of a document before the escape is escaped as version 3 writes it, but for
  # a tag's own name: a stamp beside other keys (a board's `$version`) is no data.
  defp legacy_key(key, true), do: key
  defp legacy_key(key, false) when key in @live, do: key
  defp legacy_key(key, false), do: escape(key)

  # A key that starts with a single `$` names a tag; `$$` is an escaped data key.
  defp tag_of("$$" <> _), do: nil
  defp tag_of("$" <> _ = key), do: key
  defp tag_of(_key), do: nil
end
