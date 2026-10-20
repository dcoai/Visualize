defmodule Visualize.Render.Segments do
  @moduledoc """
  A drawing as keyed segments, so that what a change did not touch is neither written
  again nor sent again (spec/09 §1.4, #813, D-203).

  A segment is one element's part of a backend's output: the text of an element drawn
  alone — a mark's item, a label, an axis's line — or the start or the end of a group or
  of the root around its children. Read in order, the segments' texts are the backend's
  output, byte for byte (`text/2`): SVG markup, the `:json` canvas commands without the
  brackets around them, or the binary canvas stream in base64, one piece of the stream per
  segment.

  Each segment is keyed. An element that names its identity (`data-vis-id`, spec/14
  §3.10, D-167) is keyed by it, `"id:" <> identity`, so a thing keeps its key wherever the
  rows put it; a group's start and end by its path from the root — the index of each
  element among its parent's children, `"r/2/0"` — followed by `<` and `>`; and any other
  element by its group's path, `~` and a hash of the element and the style it inherits, so
  an element keeps its key when one before it comes or goes. A key is never repeated: a
  second element of one key is keyed as the first with `#2`, and so on. A hash only names
  a key: a text is reused only for an element equal to the last one under it.

  `Visualize.Components.Chart` sends a drawing as a LiveView comprehension keyed by these
  keys, so a move that changes three cells of a grid sends three segments (D-203).

  ## The cache

  Every function takes the cache the previous call returned and returns the next one: an
  element drawn alone whose key, element and inherited style are the same as last time is
  not written again, its text is the one written then. A cache is only an economy — the
  segments are the same with `%{}` — and holds what the last drawing held, nothing older.

      iex> tree = Visualize.IR.Element.group([Visualize.IR.Element.rect(0, 0, 10, 10, %{fill: "red"})])
      iex> {segments, _cache} = Visualize.Render.Segments.svg(tree, %{})
      iex> Enum.map(segments, &elem(&1, 1))
      ["<g>", ~s(<rect fill="red" height="10" width="10" x="0" y="0"/>), "</g>"]
      iex> [{"r<", _}, {"r~" <> _hash, _}, {"r>", _}] = segments
      iex> Visualize.Render.Segments.text(segments, :svg) == Visualize.Render.to_string(tree, backend: :svg)
      true
  """

  alias Visualize.Backend.{Canvas, CanvasBinary, SVG}
  alias Visualize.Backend.Canvas.Output
  alias Visualize.IR.Element

  @typedoc "A segment's key: an identity's, or a path's."
  @type key :: String.t()

  @typedoc "The segments of a drawing, in drawing order."
  @type t :: [{key(), String.t()}]

  @typedoc "What the last call wrote, by key: opaque."
  @type cache :: map()

  @doc "The tree's SVG markup as segments: their texts concatenated are `Visualize.Render.to_string(tree, backend: :svg)`."
  @spec svg(Element.t(), cache()) :: {t(), cache()}
  def svg(%Element{} = tree, cache) when is_map(cache) do
    step = fn element, nil ->
      case SVG.segment(element) do
        {:leaf, text} -> {:leaf, text}
        {:node, open, close, children} -> {:node, open, close, children, nil}
      end
    end

    run(tree, :svg, step, &IO.iodata_to_binary/1, nil, cache)
  end

  @doc """
  The tree's `:json` canvas commands as segments, each its elements' commands as JSON
  objects joined by commas, a segment of no commands left out: joined by commas and put in
  brackets they are `Visualize.Render.to_string(tree, backend: :canvas, format: :json)`.
  """
  @spec json(Element.t(), cache()) :: {t(), cache()}
  def json(%Element{} = tree, cache) when is_map(cache) do
    encode = &IO.iodata_to_binary(Output.json_items(&1))
    run(tree, :json, &Canvas.segment/2, encode, %{}, cache)
  end

  @doc """
  The tree's binary canvas stream as segments, each a piece of the stream in base64, the
  stream's head — its version and paint records — the first, and a segment of no records
  left out: decoded and concatenated they are the stream of
  `Visualize.Backend.CanvasBinary.encode_element!/1`.
  """
  @spec binary(Element.t(), cache()) :: {t(), cache()}
  def binary(%Element{} = tree, cache) when is_map(cache) do
    {head, ctx} = CanvasBinary.segment_head(tree)
    step = fn element, inherited -> CanvasBinary.segment(element, ctx, inherited) end
    # The records of the body are encoded against the tree's paints: another set of paints
    # is another stream, and nothing of the last one is kept.
    cache = if Map.get(cache, :context) == ctx, do: cache, else: %{}
    {segments, next} = run(tree, :binary, step, &Base.encode64/1, %{}, cache)
    head = if head == <<>>, do: [], else: [{"head", Base.encode64(head)}]
    {head ++ segments, Map.put(next, :context, ctx)}
  end

  @doc """
  The output the segments are of: the SVG markup, the `:json` commands, or the binary
  stream in base64.
  """
  @spec text(t(), :svg | :json | :binary) :: String.t()
  def text(segments, :svg), do: Enum.map_join(segments, &elem(&1, 1))
  def text(segments, :json), do: "[" <> Enum.map_join(segments, ",", &elem(&1, 1)) <> "]"

  def text(segments, :binary),
    do:
      segments
      |> Enum.map(&Base.decode64!(elem(&1, 1)))
      |> IO.iodata_to_binary()
      |> Base.encode64()

  # A cache is kept per output: one written for another is not read.
  defp entries(%{output: output, entries: entries}, output), do: entries
  defp entries(_cache, _output), do: %{}

  defp run(tree, output, step, encode, inherited, cache) do
    state = %{out: [], seen: %{}, cached: entries(cache, output), next: %{}}
    state = walk(tree, "", "r", inherited, step, encode, state)
    {Enum.reverse(state.out), %{output: output, entries: state.next}}
  end

  # `parent` is the path of the group the element is drawn in, `path` the element's own.
  # A group or the root is its start, its children and its end, keyed by its path; any
  # other element is one segment.
  defp walk(
         %Element{type: type, clip: nil, attrs: attrs} = element,
         _parent,
         path,
         inherited,
         step,
         encode,
         state
       )
       when type in [:group, :root] and not is_map_key(attrs, "data-vis-id") do
    case step.(element, inherited) do
      {:node, open, close, children, within} ->
        state = emit(state, path <> "<", encode.(open))

        state =
          children
          |> Enum.with_index()
          |> Enum.reduce(state, fn {child, i}, acc ->
            walk(child, path, path <> "/" <> Integer.to_string(i), within, step, encode, acc)
          end)

        emit(state, path <> ">", encode.(close))

      # An empty group the backend writes whole.
      {:leaf, written} ->
        emit(state, path, encode.(written))
    end
  end

  # An element drawn alone: its text from the last drawing when the element and the style
  # it inherits are the same as then, compared whole — a text is never reused for an
  # element that only hashes alike.
  defp walk(element, parent, _path, inherited, step, encode, state) do
    {key, state} = key(element, parent, inherited, state)

    case state.cached do
      %{^key => {^element, ^inherited, text} = entry} ->
        emit(%{state | next: Map.put(state.next, key, entry)}, key, text)

      _other ->
        {:leaf, written} = step.(element, inherited)
        text = encode.(written)
        emit(%{state | next: Map.put(state.next, key, {element, inherited, text})}, key, text)
    end
  end

  # An identity's key; any other element's its group's path and a hash of what it draws,
  # so an element keeps its key when one before it comes or goes, and one drawn
  # differently is another (spec/09 §1.4, D-203).
  defp key(%Element{attrs: %{"data-vis-id" => id}}, _parent, _inherited, state),
    do: unique("id:" <> id, state)

  defp key(element, parent, inherited, state),
    do: unique(parent <> "~" <> Integer.to_string(:erlang.phash2({element, inherited})), state)

  defp unique(key, %{seen: seen} = state) do
    case seen do
      %{^key => n} -> unique_from(key, n + 1, %{state | seen: Map.put(seen, key, n + 1)})
      _new -> {key, %{state | seen: Map.put(seen, key, 1)}}
    end
  end

  defp unique_from(key, n, %{seen: seen} = state) do
    candidate = key <> "#" <> Integer.to_string(n)

    if Map.has_key?(seen, candidate),
      do: unique_from(key, n + 1, state),
      else: {candidate, %{state | seen: Map.put(seen, candidate, 1)}}
  end

  # An empty text — a root's start in a canvas stream, a group with nothing to set — is
  # not a segment.
  defp emit(state, _key, ""), do: state
  defp emit(state, key, text), do: %{state | out: [{key, text} | state.out]}
end
