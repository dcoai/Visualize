defmodule Visualize.Chart.Fragment do
  @moduledoc """
  What a fragment is about, and the ids it refers to (spec/14 §19.2, §19.8).

  A fragment's **kind** is derived, never stored: walk down while the fragment sets exactly
  one key, and the kind is the last node kind reached. A library body says its kind with a
  singular wrapper — `%{style: %{…}}` — and a hand-written fragment says it by the schema's
  own keys; both read the same way here. A fragment about more than one thing at its
  shallowest branching point is `:design`.

  An **id** is `{kind, n}` (§19.2). `refs/1` finds every id a fragment carries, which is
  how a bundle takes the closure of an entry, and `relocate/2` rewrites them through a
  table, which is how an import renumbers (§19.7). Both are deep walks that stop at a
  struct, as every walk over a design does (D-92).

  ## Examples

      iex> Visualize.Chart.Fragment.kind(%{style: %{stroke_width: 5}})
      :style

      iex> Visualize.Chart.Fragment.kind(%{styles: %{series: %{stroke_width: 5}}})
      :style

      iex> Visualize.Chart.Fragment.kind(%{frames: %{main: %{axes: [%{scale: :x, side: :bottom}]}}})
      :axis

      iex> Visualize.Chart.Fragment.kind(%{frames: %{main: %{margin: %{top: 1}}}})
      :margin

      iex> Visualize.Chart.Fragment.kind(%{theme: :dark})
      :theme

      iex> Visualize.Chart.Fragment.kind(%{composite: %{uses: []}})
      :composite

      iex> Visualize.Chart.Fragment.kind(%{version: 2, theme: :dark, frames: %{main: %{}}})
      nil

      iex> Visualize.Chart.Fragment.refs(%{style: [{:style, 11}, %{fill: {:style, 3}}]})
      [{:style, 3}, {:style, 11}]

  """

  alias Visualize.Board.Codec, as: BoardCodec
  alias Visualize.Chart.{Codec, Limits, Migration, Schema, Use}

  # Jason is optional (spec/14 §11.1, D-50): as in `Visualize.Chart`, the calls in
  # `to_json/1` and `from_json/1` stay direct and a missing Jason is answered at runtime.
  @compile {:no_warn_undefined, Jason}

  # The schema version a fragment document was written at (spec/14 §9.1): a `$` key, which
  # no design key is (§11.2), so it never collides with a fragment's own `version`.
  @stamp "$version"

  # A library body names its kind with a singular key and nothing else (§19.2). `theme` and
  # `frame` are not here because they are design keys already, and the schema's own walk
  # reaches them; a wrapper is only for a kind the design has no singular key for.
  @singular %{
    style: :style,
    scale: :scale,
    source: :source,
    axis: :axis,
    mark: :mark,
    label: :label,
    var: :var,
    gradient: :gradient,
    composite: :composite,
    # A board is a library entry and never a part of a chart (spec/14 §22.1, D-152): its
    # body is the board's map form, read by `Visualize.Board.from_map/2`.
    board: :board
  }

  @typedoc "An id: the kind of thing, and a number its store never repeats (§19.2)."
  @type id :: {atom(), pos_integer()}

  @doc """
  The path of a design's frame, and its name (spec/14 §2.1, #383): a design holds its
  frames by name, so the builder addresses `frames.<name>` where it used to address
  `frame`. A design with one frame gives that one, whatever it is called; an empty or
  many-framed fragment gives `:main`, the name a migrated design takes (§9).

      iex> Visualize.Chart.Fragment.frame_path(%{frames: %{history: %{kind: :cartesian}}})
      [:frames, :history]

      iex> Visualize.Chart.Fragment.frame_path(%{})
      [:frames, :main]
  """
  @spec frame_path(map()) :: [atom()]
  def frame_path(design), do: [:frames, frame_name(design)]

  @doc "The name of a design's frame; `:main` when it has none or several."
  @spec frame_name(term()) :: atom()
  def frame_name(%{frames: frames}) when is_map(frames) and map_size(frames) == 1 do
    frames |> Map.keys() |> hd()
  end

  def frame_name(_design), do: :main

  @doc """
  The frame a node of a design is drawn in (spec/14 §2.1, §18.16): a mark's or a label's
  own `frame`, else the design's one frame; with several and none said — the validator's
  fault, and a design being built — `main` when there is one, else the first by name, so
  a tool always has a frame to read.

      iex> design = %{frames: %{history: %{}, now: %{}}}
      iex> Visualize.Chart.Fragment.frame_of(design, %{type: :line, frame: :now})
      :now

      iex> Visualize.Chart.Fragment.frame_of(%{frames: %{history: %{}, now: %{}}}, %{type: :line})
      :history

      iex> Visualize.Chart.Fragment.frame_of(%{frames: %{history: %{}}}, nil)
      :history
  """
  @spec frame_of(term(), term()) :: atom()
  def frame_of(_design, %{frame: frame}) when is_atom(frame) and frame != nil, do: frame

  def frame_of(%{frames: frames}, _node) when is_map(frames) and map_size(frames) > 1 do
    if Map.has_key?(frames, :main),
      do: :main,
      else: frames |> Map.keys() |> Enum.min_by(&to_string/1)
  end

  def frame_of(design, _node), do: frame_name(design)

  @doc """
  The kind a singular wrapper key names — `:style` for `style:` — or `nil` for any other
  key, `composite` included (spec/14 §19.2).

      iex> Visualize.Chart.Fragment.singular(:scale)
      :scale

      iex> Visualize.Chart.Fragment.singular(:styles)
      nil

  """
  @spec singular(term()) :: atom() | nil
  def singular(:composite), do: nil
  def singular(key), do: Map.get(@singular, key)

  @doc """
  A singular-wrapper body as `{kind, body}` — `%{style: %{…}}` is `{:style, %{…}}` — or `nil`
  for anything else, a composite included (spec/14 §19.2).

      iex> Visualize.Chart.Fragment.wrapped(%{style: %{stroke_width: 5}})
      {:style, %{stroke_width: 5}}

      iex> Visualize.Chart.Fragment.wrapped(%{styles: %{series: %{}}})
      nil

  """
  @spec wrapped(map()) :: {atom(), map()} | nil
  def wrapped(fragment) when is_map(fragment) and not is_struct(fragment) do
    case Map.to_list(fragment) do
      [{key, body}] when is_map(body) and not is_struct(body) ->
        case singular(key) do
          nil -> nil
          kind -> {kind, body}
        end

      _other ->
        nil
    end
  end

  @doc """
  Every kind a fragment can be, and so every kind an id can carry: the schema's node kinds
  but the design, and `:composite` (§19.6, §19.8). A design is the deployed tier, not a
  kind of fragment.
  """
  @spec kinds() :: [atom(), ...]
  def kinds, do: Enum.uniq((Schema.kinds() -- [:design]) ++ Map.values(@singular))

  @doc """
  The kind of a fragment (§19.8): the last node kind reached walking down while exactly one
  key is set. `nil` when the fragment is many things — it branches at the top, or its one
  key is a design scalar such as `version` — which is no kind of fragment: the thing that
  is many kinds is a composite, whose sites are each one.
  """
  @spec kind(map()) :: atom() | nil
  def kind(fragment) when is_map(fragment) and not is_struct(fragment) do
    case Map.to_list(fragment) do
      [{key, value}] ->
        case Schema.key(:design, key) do
          nil -> Map.get(@singular, key)
          spec -> none(descend(:design, spec.type, value))
        end

      _several ->
        nil
    end
  end

  defp none(:design), do: nil
  defp none(kind), do: kind

  defp walk(kind, node) when is_map(node) and not is_struct(node) do
    case Map.to_list(node) do
      [{key, value}] ->
        case Schema.key(kind, key) do
          nil -> kind
          spec -> descend(kind, spec.type, value)
        end

      _several ->
        kind
    end
  end

  defp walk(kind, _value), do: kind

  # One node under the key: keep walking. A map or list of nodes with exactly one member:
  # walk into it. Several members: the fragment is about that kind, however many.
  defp descend(_kind, {:node, inner}, value), do: walk(inner, value)

  defp descend(_kind, {:map, {:node, inner}}, value) when is_map(value) do
    case Map.values(value) do
      [only] -> walk(inner, only)
      _several -> inner
    end
  end

  # A map whose entries may be a node or something else — a frame's `scales`, an entry of
  # which may be a scale adopted from another frame (spec/14 §4.3, #384).
  defp descend(kind, {:map, {:one_of, _} = inner}, value) when is_map(value) do
    case Map.values(value) do
      [only] -> descend(kind, inner, only)
      _several -> node_kind(inner) || kind
    end
  end

  defp descend(_kind, {:list, {:node, inner}}, [only]), do: walk(inner, only)
  defp descend(_kind, {:list, {:node, inner}}, value) when is_list(value), do: inner

  defp descend(kind, {:one_of, alternatives}, value) do
    case Enum.find(alternatives, &match?({:node, _}, &1)) do
      {:node, inner} -> walk(inner, value)
      nil -> kind
    end
  end

  defp descend(kind, _type, _value), do: kind

  defp node_kind({:one_of, alternatives}) do
    Enum.find_value(alternatives, fn
      {:node, kind} -> kind
      _other -> nil
    end)
  end

  @doc """
  Every id a fragment refers to, once each, sorted (§19.7). Sorted rather than in the order
  met, because the order a map is walked in is the runtime's and not a promise.

  An id is a `{kind, n}` tuple whose kind is one of `kinds/0` and whose `n` is a positive
  integer. A tuple of any other shape — an anchor `{:axis, :y}`, a `{:field, :t}` — is a
  value and is left alone.
  """
  @spec refs(term()) :: [id()]
  def refs(fragment) do
    fragment |> collect([]) |> Enum.uniq() |> Enum.sort()
  end

  defp collect({kind, n} = id, acc) when is_atom(kind) and is_integer(n) and n > 0 do
    if kind in kinds(), do: [id | acc], else: acc
  end

  # A use site holds ids (spec/14 §19.3, #470): the one struct the id walks read, by its
  # parts — never as a map — so a composite's references are seen. Any other struct is
  # a leaf (D-92).
  defp collect(%Use{ref: ref, origin: origin, local: local, vars: vars}, acc),
    do: Enum.reduce([ref, origin, local, vars], acc, &collect/2)

  defp collect(%_{} = _struct, acc), do: acc

  defp collect(map, acc) when is_map(map),
    do: Enum.reduce(map, acc, fn {_key, value}, acc -> collect(value, acc) end)

  defp collect(list, acc) when is_list(list), do: Enum.reduce(list, acc, &collect/2)
  defp collect(tuple, acc) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> collect(acc)
  defp collect(_leaf, acc), do: acc

  @doc """
  A fragment with every id rewritten through a table, and the ids the table did not carry,
  sorted (§19.7). An id that is not in the table is left as it is — it resolves as a mask (§19.2)
  — and is returned so an import can report it.

      iex> table = %{{:style, 11} => {:style, 1}}
      iex> Visualize.Chart.Fragment.relocate(%{style: [{:style, 11}, {:style, 9}]}, table)
      {%{style: [{:style, 1}, {:style, 9}]}, [{:style, 9}]}
  """
  @spec relocate(term(), %{id() => id()}) :: {term(), [id()]}
  def relocate(fragment, table) do
    {rewritten, missed} = rewrite(fragment, table, [])
    {rewritten, missed |> Enum.uniq() |> Enum.sort()}
  end

  @doc """
  A fragment of any kind as the JSON of §11 and §19.7 (#465): use sites as `$use`, ids as
  `$id`, variables as `$var`, and the document stamped `"$version"` with the schema
  version it was written at (spec/14 §9.1). It is not validated as a design — a fragment
  may be partial — so a host that keeps its library in a database can write whatever
  `Store.put/2` hands it. `{:error, {:missing_dependency, :jason}}` without Jason, as
  `Visualize.Chart.to_json/1`. A board, `%{board: map}`, is written in the board's own JSON
  form with its own `"$version"` inside the `board` object, and read back through it
  (spec/14 §22.1).

      iex> {:ok, json} = Visualize.Chart.Fragment.to_json(%{style: %{stroke_width: 5}})
      iex> Visualize.Chart.Fragment.from_json(json)
      {:ok, %{style: %{stroke_width: 5}}}
  """
  @spec to_json(map()) :: {:ok, String.t()} | {:error, {:missing_dependency, :jason}}
  def to_json(fragment) when is_map(fragment) and not is_struct(fragment) do
    if Code.ensure_loaded?(Jason) do
      {:ok, json} =
        fragment |> encoded() |> Map.put(@stamp, Migration.current()) |> Jason.encode()

      {:ok, json}
    else
      {:error, {:missing_dependency, :jason}}
    end
  end

  @doc """
  The fragment `to_json/1` wrote (#465): tagged terms back as `%Visualize.Chart.Use{}`,
  ids, variables and atoms, and the `"$version"` stamp read and dropped. An id whose kind
  is not one a fragment can have is left as it was read, so no atom is made from a
  document's kind. `from_json(to_json(f))` is `f`.

  Before a key is decoded (spec/14 §9.1, §9.2): a stamp, or a design fragment's own
  `"version"`, newer than this library reads is `{:error, {:newer_schema, needs, this}}`,
  and a document over the `depth` or `items` limit is `{:error, {:limits, errors}}`, with
  `limits:` as `Visualize.Chart.from_map/2` takes them. A document with no stamp — written
  before the stamp existed — is read as the current version. `{:error, {:json, message}}`
  for text that is not JSON.
  """
  @spec from_json(String.t(), keyword()) ::
          {:ok, map()}
          | {:error,
             {:json, String.t()}
             | {:newer_schema, pos_integer(), pos_integer()}
             | {:limits, [Visualize.Chart.Validator.error(), ...]}
             | {:missing_dependency, :jason}}
  def from_json(json, opts \\ []) when is_binary(json) do
    with {:ok, fragment, _version} <- read_json(json, opts), do: {:ok, fragment}
  end

  @doc """
  `from_json/2` with the version the document was stamped with: `{:ok, fragment, version}`,
  the current version for a document with no stamp (spec/14 §9.3, D-139). A reader that
  migrates what it reads — a theme document — needs the version to migrate from, which
  `from_json/2` drops. The errors are `from_json/2`'s.

      iex> {:ok, json} = Visualize.Chart.Fragment.to_json(%{theme: %{axis: "#666666"}})
      iex> Visualize.Chart.Fragment.read_json(json)
      {:ok, %{theme: %{axis: "#666666"}}, 2}
  """
  @spec read_json(String.t(), keyword()) ::
          {:ok, map(), pos_integer()}
          | {:error,
             {:json, String.t()}
             | {:newer_schema, pos_integer(), pos_integer()}
             | {:limits, [Visualize.Chart.Validator.error(), ...]}
             | {:missing_dependency, :jason}}
  def read_json(json, opts \\ []) when is_binary(json) do
    if Code.ensure_loaded?(Jason) do
      limits = opts |> Keyword.get(:limits, []) |> Limits.new()

      case Jason.decode(json) do
        {:ok, term} when is_map(term) -> read(term, limits)
        {:ok, other} -> {:error, {:json, "a fragment is an object, got #{inspect(other)}"}}
        {:error, error} -> {:error, {:json, Exception.message(error)}}
      end
    else
      {:error, {:missing_dependency, :jason}}
    end
  end

  defp read(term, limits) do
    {stamp, term} = Map.pop(term, @stamp)

    with :ok <- Migration.readable(stamp),
         :ok <- Migration.readable(Map.get(term, "version")),
         :ok <- Migration.readable(board_stamp(term)) do
      case Limits.structure(term, limits) do
        [] -> {:ok, decoded(term), stamp || Migration.current()}
        errors -> {:error, {:limits, errors}}
      end
    end
  end

  # A board fragment's body is written in the board's own JSON form (spec/15 §2.2), its
  # `"$version"` stamp inside the `board` object, and read back through the board's codec
  # (spec/14 §22.1, D-152): a board is not a node of the design schema.
  defp encoded(%{board: board} = fragment) when map_size(fragment) == 1 and is_map(board) do
    %{"board" => board |> Map.put_new(:version, Migration.current()) |> BoardCodec.encode()}
  end

  defp encoded(fragment), do: Codec.encode(fragment)

  defp board_stamp(%{"board" => board} = term) when map_size(term) == 1 and is_map(board),
    do: Map.get(board, BoardCodec.stamp())

  defp board_stamp(_term), do: nil

  defp decoded(%{"board" => board} = term) when map_size(term) == 1 and is_map(board) do
    {stamp, body} = Map.pop(board, BoardCodec.stamp())
    %{board: body |> BoardCodec.decode() |> Map.put(:version, stamp || Migration.current())}
  end

  defp decoded(term), do: Codec.decode(term)

  defp rewrite({kind, n} = id, table, missed)
       when is_atom(kind) and is_integer(n) and n > 0 do
    cond do
      kind not in kinds() -> {id, missed}
      Map.has_key?(table, id) -> {Map.fetch!(table, id), missed}
      true -> {id, [id | missed]}
    end
  end

  # A use site's ids are rewritten in place and it stays a use (#470).
  defp rewrite(%Use{} = use, table, missed) do
    Enum.reduce([:ref, :origin, :local, :vars], {use, missed}, fn field, {use, missed} ->
      {value, missed} = rewrite(Map.fetch!(use, field), table, missed)
      {Map.put(use, field, value), missed}
    end)
  end

  defp rewrite(%_{} = struct, _table, missed), do: {struct, missed}

  defp rewrite(map, table, missed) when is_map(map) do
    Enum.reduce(map, {%{}, missed}, fn {key, value}, {acc, missed} ->
      {value, missed} = rewrite(value, table, missed)
      {Map.put(acc, key, value), missed}
    end)
  end

  defp rewrite(list, table, missed) when is_list(list) do
    {values, missed} =
      Enum.reduce(list, {[], missed}, fn value, {acc, missed} ->
        {value, missed} = rewrite(value, table, missed)
        {[value | acc], missed}
      end)

    {Enum.reverse(values), missed}
  end

  defp rewrite(tuple, table, missed) when is_tuple(tuple) do
    {values, missed} = tuple |> Tuple.to_list() |> rewrite(table, missed)
    {List.to_tuple(values), missed}
  end

  defp rewrite(leaf, _table, missed), do: {leaf, missed}
end
