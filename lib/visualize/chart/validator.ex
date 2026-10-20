defmodule Visualize.Chart.Validator do
  @moduledoc """
  Validates a design map against the schema (spec/14 §10).

  `validate/1` walks the map with `Visualize.Chart.Schema` and returns every fault it
  finds as `{path, reason}`: the path is the list of keys and indexes from the design to
  the faulty value, `[:marks, 1, :channels, :y]`, and the reason one of the terms of
  spec/14 §10.1. References — scales, styles, sources, variables, fields, theme slots —
  resolve against the design itself, so a design is self-contained or it does not
  validate. `format/1` renders an error as a line a person reads.

  ## Examples

      iex> Visualize.Chart.Validator.validate(%{version: 3})
      {:error, [{[:frames], :required}]}
      iex> Visualize.Chart.Validator.format({[:marks, 1, :channels, :y], :required})
      "marks[1].channels.y: is required"

  """

  alias Visualize.Chart.{Migration, Schema, Urls, Var}

  alias Visualize.Chart.Validator.{
    Context,
    Cycles,
    Defaults,
    Domain,
    Generators,
    Held,
    Palette,
    Types,
    Units,
    Words
  }

  @typedoc """
  Keys and list indexes from the design to a value; `[]` is the design. A path into a
  parsed JSON document refused before it was decoded holds the document's key strings
  (spec/14 §9.2), which `format_path/1` spells alike.
  """
  @type path :: [atom() | String.t() | non_neg_integer()]

  @typedoc "Why a value is at fault (spec/14 §10.1)."
  @type reason ::
          :required
          | :unknown_key
          | {:type, Schema.type()}
          | {:enum, [atom()]}
          | {:undeclared, :scale | :style | :source | :var | :field | :slot | :paint | :generator,
             term()}
          | {:arity, :generator, atom(), non_neg_integer()}
          | {:generated, :style | :color, atom(), term()}
          | {:ref_kind, atom(), atom()}
          | {:invalid_for, atom()}
          | {:unsupported_version, term()}
          | {:newer_schema, pos_integer(), pos_integer()}
          | {:limit, Visualize.Chart.Limits.name(), pos_integer(), number()}
          | {:json, String.t()}
          | {:missing_dependency, :jason}
          | {:unknown_theme, atom()}
          | {:unresolved, :var, atom()}
          | {:var_binding, atom()}
          | {:unbound, :source, atom()}
          | {:missing_field, atom()}
          | :conflict
          | :cycle
          | {:cycle, [term()]}
          | {:template, :unterminated | {:hole, String.t()}}
          | :many_kinds
          | :sweep
          | :radius
          | {:zone, String.t(), Visualize.Scale.Time.zone_error()}
          | {:unit, term(), Visualize.Unit.reason()}
          | {:quantity, Visualize.Quantity.t(), Visualize.Unit.code()}
          | {:sync, :frame_kind | :x_scale, atom() | nil}
          | {:brush, :frame_kind | :x_scale, atom() | nil}
          | {:color_map, atom()}
          | {:polarity, :range}
          | {:tiles, :projection, atom()}
          | {:tiles, :attribution | :url | :subdomains}
          | {:outside_domain, atom(), number() | {:column, atom(), :number | :text | :time}}
          | {:feeds_domain, atom(), number()}
          | {:contract, String.t()}
          | {:undeclared_field, atom(), atom()}
          | {:missing_attribute, atom(), atom(), atom()}
          | {:schema_type, atom(), atom(), atom()}
          | {:type_mismatch, atom(), atom(), :time | :number | :category, atom()}
          | {:no_schema, atom()}
          | {:unknown_schema, term(), String.t()}
          | {:describe, term(), term()}
          | {:schema_version, term(), String.t(), String.t()}

  @type error :: {path(), reason()}

  # A style and its parts, any of whose values may be a channel binding (spec/14 §3.2).
  @style_kinds ~w(style defaults kind_defaults paint stroke font text_layout effect marker curve)a

  @doc """
  `:ok`, or every fault of the design ordered by path; URLs under the application's policy,
  generator names against the application's `config :visualize, generators:`.
  """
  @spec validate(term()) :: :ok | {:error, [error(), ...]}
  def validate(map) when is_map(map) and not is_struct(map),
    do: design(map, Urls.policy(), [])

  def validate(_), do: {:error, [{[], {:type, {:node, :design}}}]}

  @doc """
  `validate/1` of a design with the URL policy of a read (spec/14 §10.3): the
  application's `config :visualize, urls: [...]` made stricter by `urls:` — `http: true`
  only where the application allows `http:`, a `hosts` list within the application's —
  and every generator's name checked against the modules of `generators:` and the
  application's `config :visualize, generators:` (spec/14 §3.13).

      iex> design = %{version: 3, frames: %{main: %{kind: :cartesian}}}
      iex> Visualize.Chart.Validator.validate(design, :design, urls: [hosts: ["tile.example"]])
      :ok
  """
  @spec validate(term(), :design, keyword()) :: :ok | {:error, [error(), ...]}
  def validate(map, :design, opts) when is_map(map) and not is_struct(map) do
    urls = Urls.policy(Keyword.get(opts, :urls, []))
    design(map, urls, Keyword.get(opts, :generators, []))
  end

  def validate(_map, :design, _opts), do: {:error, [{[], {:type, {:node, :design}}}]}

  defp design(map, urls, modules) do
    # Read in the shape this library writes: a style's flat keys are its parts (§3.1, §9).
    map = Migration.parts(map, :design)
    # The registry is built only for a design that names a generator (spec/14 §3.13).
    registry = if Generators.present?(map), do: Visualize.Generators.registry(modules), else: %{}
    ctx = Context.context(map) |> Map.put(:urls, urls) |> Map.put(:generators, registry)

    case node(:design, map, [], ctx) ++ Cycles.cycles(map) ++ Domain.faults(map) do
      [] -> :ok
      errors -> {:error, Enum.sort_by(errors, &elem(&1, 0))}
    end
  end

  @doc """
  `:ok`, or every fault of a fragment read as a kind — **per-kind validity** (spec/14 §19.8).

  A design is validated whole. A composite must be `%{composite: %{uses, vars}}` and nothing
  else, its uses sites. Any other kind is the singular body under its key — `%{style: %{…}}`,
  `%{frames: %{main: %{…}}}` — walked with that kind's schema and no design around it, so a reference
  to a scale, style, source, variable or field the fragment does not declare is not a fault:
  a fragment is a piece, and what it refers to is bound where it is composed. A fragment
  whose one key is not the kind's is refused as `{:type, {:node, kind}}`. A board,
  `%{board: map}`, is read by its own reader, `Visualize.Board.from_map/1`, every fault
  under `[:board | path]` (spec/14 §22.1).
  """
  @spec validate(term(), atom()) :: :ok | {:error, [error(), ...]}
  def validate(map, :design), do: validate(map)

  def validate(%{composite: %{uses: uses, vars: vars} = composite} = map, :composite)
      when is_list(uses) and is_map(vars) and map_size(map) == 1 do
    uses
    |> Enum.with_index()
    |> Enum.reject(fn {use, _index} -> is_struct(use, Visualize.Chart.Use) end)
    |> Enum.map(fn {_use, index} -> {[:composite, :uses, index], {:type, :use}} end)
    |> Kernel.++(Defaults.composite(composite, &validate/2))
    |> case do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  def validate(_map, :composite), do: {:error, [{[], {:type, {:node, :composite}}}]}

  # A board is read by its own reader (spec/14 §22.1, D-152): its version gated, its limits
  # applied and every fault of it alone, each under the wrapper's key.
  def validate(%{board: board} = map, :board) when map_size(map) == 1 do
    case Visualize.Board.from_map(board) do
      {:ok, _board} ->
        :ok

      {:error, errors} ->
        {:error, Enum.map(errors, fn {path, reason} -> {[:board | path], reason} end)}
    end
  end

  def validate(_map, :board), do: {:error, [{[], {:type, {:node, :board}}}]}

  def validate(_map, nil), do: {:error, [{[], :many_kinds}]}

  def validate(map, kind) when is_map(map) and not is_struct(map) and is_atom(kind) do
    case Map.to_list(map) do
      [{^kind, body}] ->
        case as_kind(kind, body) do
          [] -> :ok
          errors -> {:error, Enum.sort_by(errors, &elem(&1, 0))}
        end

      _other ->
        {:error, [{[], {:type, {:node, kind}}}]}
    end
  end

  def validate(_map, kind), do: {:error, [{[], {:type, {:node, kind}}}]}

  # A design key is checked as the design would check it — a theme may be a name — and any
  # other kind is a node of that kind, with nothing to look references up in. A fragment is
  # partial by nature — a frame that says only its width is the point of one — so no key is
  # required of it; required-ness is a property of the design it is flattened into.
  defp as_kind(kind, body) do
    case Schema.key(:design, kind) do
      nil when is_map(body) and not is_struct(body) ->
        node(kind, Migration.parts(body, kind), [kind], Context.open())

      nil ->
        [{[kind], {:type, {:node, kind}}}]

      spec ->
        body = Map.fetch!(Migration.parts(%{kind => body}, :design), kind)
        check_key(:design, spec, body, [kind], Context.open())
    end
  end

  @doc false
  # A value checked as `type` in a fragment's context with `known` laid over it (§19.8):
  # what a generator's result is held to (`Visualize.Chart.Validator.Generators`).
  @spec check_open(Schema.type(), term(), map()) :: [error()]
  def check_open(type, value, known),
    do: Types.check(type, value, [], Map.merge(Context.open(), known))

  @doc "One error as `path: reason` in words; the path in `marks[1].channels.y` form."
  @spec format(error()) :: String.t()
  def format({path, reason}), do: "#{format_path(path)}: #{Words.words(reason)}"

  @doc """
  A path as a person reads it — `design` for the root, else `frame.scales.x`,
  `marks[0].channels` — the one spelling every error, node label and rendered `data-node`
  uses (spec/14 §4.7, §18.5).

      iex> Visualize.Chart.Validator.format_path([:marks, 0, :channels])
      "marks[0].channels"
      iex> Visualize.Chart.Validator.format_path([])
      "design"
  """
  @spec format_path(path()) :: String.t()
  def format_path([]), do: "design"

  def format_path(path) do
    Enum.reduce(path, "", fn
      i, acc when is_integer(i) -> "#{acc}[#{i}]"
      k, "" -> "#{k}"
      k, acc -> "#{acc}.#{k}"
    end)
  end

  # -- nodes ----------------------------------------------------------------------------

  @doc false
  # A node of `kind` at `path`: its unknown keys, its missing required ones, each present
  # key's own faults, then what its keys owe each other (`Validator.Held`).
  @spec node(atom(), map(), path(), map()) :: [error()]
  def node(kind, map, path, ctx) do
    ctx = Context.enter(kind, map, ctx)
    specs = specs(kind, ctx)
    known = Enum.map(specs, & &1.key)

    unknown =
      for k <- Map.keys(map), k not in known, do: {path ++ [k], unknown_reason(kind, k, ctx)}

    missing =
      for s <- specs,
          s.required and not ctx.partial?,
          not Map.has_key?(map, s.key),
          do: {path ++ [s.key], :required}

    present =
      for s <- specs, Map.has_key?(map, s.key) do
        check_key(kind, s, Map.fetch!(map, s.key), path ++ [s.key], ctx)
      end

    unknown ++ missing ++ List.flatten(present) ++ Held.held(kind, map, path, ctx)
  end

  # The channels and options a mark type reads; every key, none required, when the type
  # is unknown (its own error is reported on `type`).
  defp specs(kind, %{mark_type: type} = ctx) when kind in [:channels, :options] and type != nil do
    allowed = allowed(kind, type)
    required = required(kind, type, ctx)

    for s <- Schema.describe(kind), s.key in allowed do
      %{s | required: s.key in required}
    end
  end

  # The keys a transform op reads, the op's required ones required (spec/14 §5.4). A
  # `:projection` reads points through `fields` or geometries through `field` (§5.4.4):
  # `fields` is required unless `field` is given, and a step with both has `field` read
  # as a key the op does not take.
  defp specs(:transform, %{op: op} = ctx) when op != nil do
    %{required: required, optional: optional} = Schema.transform_keys(op)
    {required, optional} = projection_keys(op, required, optional, ctx)

    for s <- Schema.describe(:transform), s.key == :op or s.key in (required ++ optional) do
      %{s | required: s.key == :op or s.key in required, type: as_type(s, op)}
    end
  end

  # A mark or a label says its frame when the design holds more than one (spec/14 §5.1,
  # §6.1, #383): with one frame there is nothing to say and the key means that frame.
  defp specs(kind, %{frame_nodes: frames} = ctx)
       when kind in [:mark, :label] and is_map(frames) and map_size(frames) > 1 do
    for s <- by_type(kind, ctx), do: if(s.key == :frame, do: %{s | required: true}, else: s)
  end

  defp specs(:mark, ctx), do: by_type(:mark, ctx)

  # A fit reads points through `fields` or geometries through `field` (§4.6), as the
  # `:projection` transform does.
  defp specs(:fit, %{transform_keys: keys}) do
    {required, dropped} =
      case {:fields in keys, :field in keys} do
        {true, true} -> {[], [:field]}
        {_, true} -> {[], []}
        {_, false} -> {[:fields], []}
      end

    for s <- Schema.describe(:fit),
        s.key not in dropped,
        do: %{s | required: s.required or s.key in required}
  end

  # A legend of declared values needs no scale (spec/14 §4.5, D-194).
  defp specs(:legend, %{legend_values?: true}) do
    for s <- Schema.describe(:legend),
        do: if(s.key == :scale, do: %{s | required: false}, else: s)
  end

  defp specs(kind, _ctx), do: Schema.describe(kind)

  # A `:tiles` mark reads no rows and names its provider (spec/14 §5.2, #475): `data` is
  # not required of it and `tiles` is.
  defp by_type(:mark, %{mark_type: :tiles}) do
    for s <- Schema.describe(:mark) do
      case s.key do
        :data -> %{s | required: false}
        :tiles -> %{s | required: true}
        _other -> s
      end
    end
  end

  # A `:choose` mark names its field and its cases (spec/14 §5.2, D-194).
  defp by_type(:mark, %{mark_type: :choose}) do
    for s <- Schema.describe(:mark),
        do: if(s.key in [:on, :cases], do: %{s | required: true}, else: s)
  end

  defp by_type(kind, _ctx), do: Schema.describe(kind)

  defp projection_keys(:projection, required, optional, %{transform_keys: keys}) do
    case {:fields in keys, :field in keys} do
      {true, true} -> {required, optional -- [:field]}
      {_, true} -> {required, optional}
      {_, false} -> {[:fields | required], optional -- [:fields]}
    end
  end

  defp projection_keys(_op, required, optional, _ctx), do: {required, optional}

  # `as` is a pair of names for a fold and one name for every other op (spec/14 §5.4).
  defp as_type(%{key: :as}, :fold), do: {:list, :name}
  defp as_type(%{key: :as}, _op), do: :name
  # `n` is a count or the plot's width for `:lttb`, and only a count for `:take`.
  defp as_type(%{key: :n}, :take), do: :integer
  # A sort's order is a direction; a fixed key order is a stack's alone (§5.4, #492).
  defp as_type(%{key: :order, type: {:one_of, [enum | _]}}, :sort), do: enum
  defp as_type(%{type: type}, _op), do: type

  defp allowed(:channels, type) do
    %{required: required, optional: optional} = Schema.channels(type)
    required ++ optional
  end

  defp allowed(:options, type), do: Schema.options(type)

  # An arc's `value` is required unless both `start` and `end` are given, and either of
  # the pair requires the other (spec/14 §5.2, D-69).
  defp required(:channels, :arc, %{channel_keys: keys}) do
    case Enum.filter([:start, :end], &(&1 in keys)) do
      [] -> [:value]
      [_, _] -> []
      [_one] -> [:start, :end]
    end
  end

  # A rule stands at `x`, or — in a polar frame — at a radius `y` (spec/14 §5.2, #391).
  defp required(:channels, :rule, %{channel_keys: keys}) do
    if :y in keys, do: [], else: [:x]
  end

  # A choice's channels are laid over its `:choose` mark's: none is required of it.
  defp required(:channels, _type, %{choice?: true}), do: []
  defp required(:channels, type, _ctx), do: Schema.channels(type).required
  defp required(:options, _type, _ctx), do: []

  defp unknown_reason(kind, key, %{mark_type: type}) when kind in [:channels, :options] do
    if type != nil and Schema.key(kind, key) != nil, do: {:invalid_for, type}, else: :unknown_key
  end

  defp unknown_reason(:transform, key, %{op: op}) when op != nil do
    if Schema.key(:transform, key) != nil, do: {:invalid_for, op}, else: :unknown_key
  end

  defp unknown_reason(:fit, key, _ctx) when key in [:field, :fields], do: {:invalid_for, :fit}
  defp unknown_reason(_kind, _key, _ctx), do: :unknown_key

  # A style value may be a channel binding for any key (spec/14 §3.2); the version must
  # be the one this library writes (spec/14 §9).
  defp check_key(kind, _spec, {:field, _} = ref, path, ctx) when kind in @style_kinds,
    do: Types.check(:field_ref, ref, path, ctx)

  # A color generator (spec/14 §3.13): a paint's `color` and an effect's.
  defp check_key(kind, %{key: :color}, {:generate, _, _} = call, path, ctx)
       when kind in [:paint, :stroke, :effect],
       do: Types.generator(call, path, ctx, :color)

  defp check_key(:design, %{key: :version}, v, path, _ctx) when is_integer(v) do
    cond do
      v == Migration.current() -> []
      v > Migration.current() -> [{path, {:newer_schema, v, Migration.current()}}]
      true -> [{path, {:unsupported_version, v}}]
    end
  end

  # A paint under `defs` is a gradient (spec/14 §2.7, D-172): its `type` and `stops` are
  # required there, where a part of a style may leave them to what it is laid on.
  defp check_key(:design, %{key: :defs} = spec, defs, path, ctx)
       when is_map(defs) and not is_struct(defs) do
    gradients =
      for {name, paint} <- defs, is_map(paint) and not is_struct(paint), at = path ++ [name] do
        Types.gradient(paint, at)
      end

    Types.check(spec.type, defs, path, %{ctx | generators: :refused}) ++ List.flatten(gradients)
  end

  # Strings a style or a theme sends to SVG, CSS or a canvas hold only what their contexts
  # can carry (spec/14 §10.3, #660): a font family no markup, rule or escape characters, a
  # class only CSS class names.
  defp check_key(kind, %{key: key} = spec, family, path, ctx)
       when {kind, key} in [{:font, :family}, {:theme, :font_family}] and is_binary(family) do
    if Regex.match?(~r/[<>\/;{}\\\x00-\x1f\x7f]/, family),
      do: [{path, {:unsafe, :font_family}}],
      else: Types.check(spec.type, family, path, ctx)
  end

  defp check_key(:style, %{key: :class}, class, path, _ctx) when is_binary(class) do
    if Regex.match?(~r/\A-?[_a-zA-Z][_a-zA-Z0-9-]*( +-?[_a-zA-Z][_a-zA-Z0-9-]*)*\z/, class),
      do: [],
      else: [{path, {:unsafe, :class}}]
  end

  # A theme needs at least one series color (spec/08 §7.2).
  defp check_key(:theme, %{key: :series}, [], path, _ctx), do: [{path, :required}]

  # A stored theme's palette entries are style nodes (spec/14 §2.5, #637), a role's `:cue`
  # and an `extends` left to the palette's contracts, which `held(:theme)` measures.
  defp check_key(:theme, %{key: :styles}, styles, path, ctx)
       when is_map(styles) and not is_struct(styles) do
    Enum.flat_map(styles, fn
      {name, entry} when is_map(entry) and not is_struct(entry) ->
        if Types.name?(name),
          do: node(:style, Palette.entry(entry), path ++ [name], ctx),
          else: [{path ++ [name], {:type, :name}}]

      {name, %Var{} = var} ->
        Types.check(:term, var, path ++ [name], ctx)

      # A list of palette names and nodes, or one name (#658): its names are the
      # contract's to hold, its nodes style nodes.
      {name, entries}
      when is_list(entries) or is_binary(entries) or (is_atom(entries) and entries != nil) ->
        entries
        |> List.wrap()
        |> Enum.with_index()
        |> Enum.flat_map(fn
          {entry, i} when is_map(entry) and not is_struct(entry) ->
            node(:style, Palette.entry(entry), path ++ [name, i], ctx)

          {entry, _i} when is_atom(entry) or is_binary(entry) ->
            []

          {_entry, i} ->
            [{path ++ [name, i], {:type, Schema.style_entry()}}]
        end)

      {name, _other} ->
        [{path ++ [name], {:type, {:node, :style}}}]
    end)
  end

  defp check_key(kind, spec, v, path, ctx),
    do: Units.faults(kind, spec.key, v, path) ++ Types.check(spec.type, v, path, ctx)
end
