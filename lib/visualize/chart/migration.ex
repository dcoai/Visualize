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

  @current 2

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

      iex> Visualize.Chart.Migration.readable(3)
      {:error, {:newer_schema, 3, 2}}

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
  def legacy_type(_kind, _key), do: nil

  @doc ~S"""
  The design in the shape this library writes, within the current version: a `:text`
  given as a list of parts — the form an earlier draft wrote — becomes the string with
  interpolation (spec/14 §7.1), walking the map by the schema so a text is known to be
  one. Every other value passes through as it is.

      iex> Visualize.Chart.Migration.canonical(%{version: 2, labels: [%{anchor: :title, text: ["u: ", Visualize.Chart.var(:unit)]}]})
      %{version: 2, labels: [%{anchor: :title, text: "u: \#{var(:unit)}"}]}
  """
  @spec canonical(map()) :: map()
  def canonical(map) when is_map(map), do: node(:design, map)

  defp node(kind, map) when is_map(map) and not is_struct(map) do
    Map.new(map, fn {k, v} ->
      type = if spec = Schema.key(kind, k), do: spec.type, else: :term
      {k, value(type, v)}
    end)
  end

  defp value(:text, parts) when is_list(parts), do: Text.unparse(parts)
  defp value({:node, kind}, v) when is_map(v) and not is_struct(v), do: node(kind, v)
  defp value({:list, t}, v) when is_list(v), do: Enum.map(v, &value(t, &1))

  defp value({:map, t}, v) when is_map(v) and not is_struct(v),
    do: Map.new(v, fn {k, e} -> {k, value(t, e)} end)

  defp value({:one_of, types}, v) do
    case Schema.select(types, v) do
      nil -> v
      type -> value(type, v)
    end
  end

  defp value(_type, v), do: v
end
