defmodule Visualize.Chart.Migration do
  @moduledoc """
  Schema versions and the migrations between them (spec/14 §9).

  `current/0` is the version this library writes. `migrate/1` steps an older design
  forward one version at a time through the migration registered for each step, so a
  stored design never goes stale. Version 2 is the first step: a design holds its frames
  by name (spec/14 §2.1, §4.1, #383), so a version 1 design's singular `frame` becomes
  `frames: %{main: …}` and the `size` it may still carry is dropped, the render giving one
  now (§4.2, #427). A stored version 1 design therefore keeps working through
  `Visualize.Chart.from_map/1`, which migrates before it validates.
  """

  alias Visualize.Chart.{Schema, Text, Validator}
  alias Visualize.Chart.Style.Parts

  @current 3

  @doc "The schema version this library writes: `#{@current}`."
  @spec current() :: pos_integer()
  def current, do: @current

  @doc """
  The design at the current version.

  A design already there passes through unchanged; an older one is migrated step by
  step; a version above `current/0` is `{:newer_schema, v, current}` (spec/14 §9.1), and
  one below `1`, missing or not an integer is an error at `[:version]` too.
  """
  @spec migrate(term()) :: {:ok, map()} | {:error, [Validator.error(), ...]}
  def migrate(%{version: @current} = map), do: {:ok, canonical(map)}

  def migrate(%{version: v} = map) when is_integer(v) and v >= 1 and v < @current do
    migrate(step(map, v))
  end

  def migrate(%{version: v}) when is_integer(v) and v > @current do
    {:error, [{[:version], {:newer_schema, v, @current}}]}
  end

  def migrate(%{version: v}) when is_integer(v) do
    {:error, [{[:version], {:unsupported_version, v}}]}
  end

  def migrate(%{version: _}), do: {:error, [{[:version], {:type, :integer}}]}

  def migrate(map) when is_map(map) and not is_struct(map) do
    {:error, [{[:version], :required}]}
  end

  def migrate(_), do: {:error, [{[], {:type, {:node, :design}}}]}

  @doc """
  The version gate of spec/14 §9.1 alone: `{:error, {:newer_schema, version, current}}`
  for an integer above `current/0`, else `:ok`.

  It is for a reader that holds a version before it holds a design — a parsed JSON
  document, a fragment document's `"$version"`, a bundle's provenance — so a newer
  document is refused before anything of it is read. Any other version is `:ok` here and
  left to `migrate/1` to judge.

      iex> Visualize.Chart.Migration.readable(4)
      {:error, {:newer_schema, 4, 3}}

      iex> Visualize.Chart.Migration.readable(1)
      :ok
  """
  @spec readable(term()) :: :ok | {:error, {:newer_schema, pos_integer(), pos_integer()}}
  def readable(v) when is_integer(v) and v > @current, do: {:error, {:newer_schema, v, @current}}
  def readable(_version), do: :ok

  # One clause per registered migration, from a version to the next, each pure and
  # yielding the map at `from + 1`.

  # 1 -> 2: `frame` becomes `frames: %{main: …}` and a frame's `size` is dropped, the
  # render giving one (spec/14 §2.1, §4.2, #383, #427). A design with no frame at all is
  # still invalid; the validator says so after the migration, at `[:frames]`.
  defp step(map, 1) do
    map = Map.put(map, :version, 2)

    case Map.pop(map, :frame) do
      {nil, map} -> map
      {frame, map} when is_map(frame) -> Map.put(map, :frames, %{main: Map.delete(frame, :size)})
      {_other, map} -> map
    end
  end

  # 2 -> 3: a style is held in compound parts (spec/14 §3.1, §9, D-172): every flat key of
  # a style node moves into its part, a shorthand is expanded, and a declared gradient
  # takes the paint's words (`type`, `center`, a stop's `at` and `color`). The same rewrite
  # runs in `canonical/1` at every version, so a design a host builds at version 3 in the
  # flat keys is rewritten too; this step makes a stored version 2 design whole on its own.
  defp step(map, 2), do: map |> Map.put(:version, 3) |> canonical()

  defp step(map, from) do
    raise ArgumentError, "no migration from version #{from} for #{inspect(map)}"
  end

  @doc """
  The type a key had in an earlier version, for a key of a `kind` node that the current
  schema no longer has; `nil` for any other key.

  The codec reads a document by the current schema, so a key only an earlier version had
  would be read untyped and its values left as strings. This is what it reads such a key
  by instead, so a document from that version is typed before `migrate/1` reshapes it
  (spec/14 §9, #479). Each entry belongs to the step that removed the key: version 1's
  design-level `frame` is one `:frame` node, which the 1 → 2 step moves to `frames.main`.

      iex> Visualize.Chart.Migration.legacy_type(:design, :frame)
      {:node, :frame}

      iex> Visualize.Chart.Migration.legacy_type(:design, :frames)
      nil
  """
  @spec legacy_type(atom(), atom()) :: Schema.type() | nil
  def legacy_type(:design, :frame), do: {:node, :frame}
  # Version 2's flat style keys and gradient words, which the 2 → 3 step moves (D-172).
  def legacy_type(:style, key), do: flat_type(key)
  def legacy_type(kind, :kind) when kind in [:paint, :gradient], do: {:enum, [:linear, :radial]}
  def legacy_type(kind, :centre) when kind in [:paint, :gradient], do: {:list, :number}
  def legacy_type(:stop, :offset), do: :number
  def legacy_type(:stop, :colour), do: :colour
  def legacy_type(_kind, _key), do: nil

  @doc """
  The type a flat style key of an earlier version had (spec/14 §9, D-172), `nil` for any
  other key: `fill`, `stroke`, `curve` and `effect` are flat when their value is not a part,
  and are read by these types then.

      iex> Visualize.Chart.Migration.flat_type(:stroke_width)
      :size
  """
  @spec flat_type(atom()) :: Schema.type() | nil
  def flat_type(key) do
    if key in Parts.flat_keys(), do: Schema.key(:flat_style, key).type
  end

  @doc ~S"""
  The design in the shape this library writes, within the current version: a `:text`
  given as a list of parts — the form an earlier draft wrote — becomes the string with
  interpolation (spec/14 §7.1), walking the map by the schema so a text is known to be
  one. Every other value passes through as it is.

      iex> Visualize.Chart.Migration.canonical(%{version: 2, labels: [%{anchor: :title, text: ["u: ", Visualize.Chart.var(:unit)]}]})
      %{version: 2, labels: [%{anchor: :title, text: "u: \#{var(:unit)}"}]}
  """
  @spec canonical(map()) :: map()
  def canonical(map) when is_map(map), do: node(:design, map, true)

  @doc """
  `canonical/1` of a node of `kind` alone: a fragment of that kind (spec/14 §19.6).

      iex> Visualize.Chart.Migration.canonical(%{fill: :red, fill_opacity: 0.5}, :style)
      %{fill: %{type: :solid, color: :red, opacity: 0.5}}
  """
  @spec canonical(map(), Schema.kind()) :: map()
  def canonical(map, kind) when is_map(map), do: node(kind, map, true)

  @doc """
  The styles of a node of `kind` in their parts and nothing else rewritten (spec/14 §3.1,
  §9, D-172): what the validator reads, so a design or a fragment written in the flat keys
  validates as the parts it means, while a text given as parts keeps the paths its faults
  are reported at.

      iex> Visualize.Chart.Migration.parts(%{styles: %{s: %{stroke_width: 2}}}, :design)
      %{styles: %{s: %{stroke: %{width: 2}}}}
  """
  @spec parts(map(), Schema.kind()) :: map()
  def parts(map, kind) when is_map(map), do: node(kind, map, false)

  # A style's flat keys and shorthands become its parts, and a paint's gradient words its
  # own (spec/14 §3.1, §9, D-172), before the node is walked by its schema.
  defp node(:style, map, text?) when is_map(map) and not is_struct(map),
    do: walk(:style, Parts.normalize(map), text?)

  defp node(kind, map, text?)
       when kind in [:paint, :gradient] and is_map(map) and not is_struct(map),
       do: walk(:paint, Parts.paint(map), text?)

  defp node(kind, map, text?), do: walk(kind, map, text?)

  defp walk(kind, map, text?) when is_map(map) and not is_struct(map) do
    Map.new(map, fn {k, v} ->
      type = if spec = Schema.key(kind, k), do: spec.type, else: :term
      {k, value(type, v, text?)}
    end)
  end

  defp walk(_kind, value, _text?), do: value

  defp value(:text, parts, true) when is_list(parts), do: Text.unparse(parts)

  defp value({:node, kind}, v, text?) when is_map(v) and not is_struct(v),
    do: node(kind, v, text?)

  defp value({:list, t}, v, text?) when is_list(v), do: Enum.map(v, &value(t, &1, text?))

  defp value({:map, t}, v, text?) when is_map(v) and not is_struct(v),
    do: Map.new(v, fn {k, e} -> {k, value(t, e, text?)} end)

  defp value({:one_of, types}, v, text?) do
    case Schema.select(types, v) do
      nil -> v
      type -> value(type, v, text?)
    end
  end

  defp value(_type, v, _text?), do: v
end
