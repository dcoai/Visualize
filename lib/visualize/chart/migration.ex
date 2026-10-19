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

  alias Visualize.Chart.Migration.FilledLines
  alias Visualize.Chart.{Schema, Text, Validator}
  alias Visualize.Chart.Style.{Defaults, Parts}

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
  # A line whose style gave a fill drew the area under it, and a version 3 line draws none,
  # so this step alone also gives such a line an `:area` beneath it (§5.6, #659).
  defp step(map, 2), do: map |> Map.put(:version, 3) |> canonical() |> FilledLines.rewrite()

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
  # The role colors of before #663, which `canonical/1` folds into the color table.
  def legacy_type(:theme, :roles), do: {:map, :color}
  # Version 2's flat style keys and gradient words, which the 2 → 3 step moves (D-172).
  def legacy_type(:style, key), do: flat_type(key)
  def legacy_type(kind, :kind) when kind in [:paint, :gradient], do: {:enum, [:linear, :radial]}
  # spelling: allow — version 2's paint word.
  def legacy_type(kind, :centre) when kind in [:paint, :gradient], do: {:list, :number}
  def legacy_type(:stop, :offset), do: :number
  # spelling: allow — version 2's stop word.
  def legacy_type(:stop, :colour), do: :color
  def legacy_type(_kind, _key), do: nil

  @doc false
  # Every key only an earlier version had, which a step of `migrate/1` reads: the codec
  # reads these as atoms beside the schema's own (spec/14 §9.4, D-195), so a stored document
  # of that version still migrates. Version 1's `frame` and its `size`, before #663's
  # `roles`, version 2's paint and stop words. A key added to `legacy_type/2` or to a step
  # is added here.
  @spec legacy_keys() :: [atom(), ...]
  # spelling: allow — version 2's paint and stop words.
  def legacy_keys, do: [:frame, :size, :roles, :kind, :centre, :offset, :colour]

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
      %{fill: %{type: :solid, color: {:color, :red}, opacity: 0.5}}
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

  # A theme's role colors are names of its color table (spec/08 §7.1, #663, D-135): `roles`
  # is read into `colors`, which wins where both name a color.
  defp node(:theme, %{roles: roles} = map, text?) when is_map(roles) and not is_struct(roles) do
    colors =
      case Map.get(map, :colors) do
        own when is_map(own) and not is_struct(own) -> Map.merge(roles, own)
        _none -> roles
      end

    walk(:theme, map |> Map.delete(:roles) |> Map.put(:colors, colors), text?)
  end

  # A defaults node's parts are read as a style's (spec/14 §3.8, #651); its entries per mark
  # kind are left for the walk, which reads each as a node of parts.
  defp node(:defaults, map, text?) when is_map(map) and not is_struct(map) do
    {entries, parts} = Map.split(map, Defaults.kinds())
    walk(:defaults, Map.merge(Parts.normalize(parts), entries), text?)
  end

  defp node(:kind_defaults, map, text?) when is_map(map) and not is_struct(map),
    do: walk(:kind_defaults, Parts.normalize(map), text?)

  defp node(kind, map, text?)
       when kind in [:paint, :gradient] and is_map(map) and not is_struct(map),
       do: walk(:paint, Parts.paint(map), text?)

  defp node(kind, map, text?), do: walk(kind, map, text?)

  defp walk(kind, map, text?) when is_map(map) and not is_struct(map) do
    map
    |> renamed_themes(kind)
    |> Map.new(fn {k, v} ->
      type = if spec = Schema.key(kind, k), do: spec.type, else: :term
      {k, value(type, v, text?)}
    end)
  end

  defp walk(_kind, value, _text?), do: value

  # A built-in theme spelled in British English before #642 is read by its American name
  # (spec/14 §9, D-183), wherever a theme is named: a design's or a theme document's
  # `theme`, an inline theme's own `name` and its counterparts.
  # spelling: allow — the old name a stored document holds.
  @renamed_themes %{colour_safe: :color_safe}

  defp renamed_themes(map, :design), do: rename_values(map, [:theme])
  defp renamed_themes(map, :theme), do: rename_values(map, [:name, :dark, :light])
  defp renamed_themes(map, _kind), do: map

  defp rename_values(map, keys) do
    Enum.reduce(keys, map, fn key, map ->
      case Map.fetch(map, key) do
        {:ok, name} when is_map_key(@renamed_themes, name) ->
          Map.put(map, key, Map.fetch!(@renamed_themes, name))

        _other ->
          map
      end
    end)
  end

  defp value(:text, parts, true) when is_list(parts), do: Text.unparse(parts)
  defp value(:color, v, _text?), do: color(v)
  # A theme's pinned steps are color strings as they are (#667).
  defp value(:theme_color, v, _text?) when is_map(v) and not is_struct(v), do: v
  defp value(:theme_color, v, _text?), do: color(v)

  defp value(:color_map, v, _text?) when is_map(v) and not is_struct(v),
    do: Map.new(v, fn {category, c} -> {category, color(c)} end)

  # A scale's list range holds positions or colors, and an atom there is a color (spec/14
  # §1.4, §4.3, D-185); a number, a string or a struct passes through `color/1` as it is,
  # and an `:auto`, which no range holds, is left for the validator to name.
  defp value(:range, v, _text?) when is_list(v),
    do: Enum.map(v, fn entry -> if entry == :auto, do: :auto, else: color(entry) end)

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

  # A color position holds a typed color (spec/14 §3.2, #664, D-173): a bare atom is the
  # name it can only mean there, `:contrast` the ink over what is under, and a transform's
  # operands are colors too. `:none` is the one bare word a paint's place keeps.
  @unary Visualize.Color.Typed.ops()

  defp color(:none), do: :none
  defp color(:contrast), do: {:contrast, :under}
  # A palette entry's `:cue` is its own word, left for the palette contract to judge.
  defp color(:cue), do: :cue

  defp color(name) when is_atom(name) and name not in [nil, true, false],
    do: {:color, name}

  defp color({op, c, t}) when op in @unary, do: {op, color(c), t}
  defp color({:blend, list}) when is_list(list), do: {:blend, Enum.map(list, &color/1)}
  defp color({:contrast, :under} = ink), do: ink
  defp color({:contrast, c}), do: {:contrast, color(c)}
  defp color(v), do: v
end
