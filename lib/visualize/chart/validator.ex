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

      iex> Visualize.Chart.Validator.validate(%{version: 1})
      {:error, [{[:frame], :required}]}
      iex> Visualize.Chart.Validator.format({[:marks, 1, :channels, :y], :required})
      "marks[1].channels.y: is required"

  """

  alias Visualize.Chart.{Migration, Schema, Text, Var}
  alias Visualize.Theme

  @typedoc "Keys and list indexes from the design to a value; `[]` is the design."
  @type path :: [atom() | non_neg_integer()]

  @typedoc "Why a value is at fault (spec/14 §10.1)."
  @type reason ::
          :required
          | :unknown_key
          | {:type, Schema.type()}
          | {:enum, [atom()]}
          | {:undeclared, :scale | :style | :source | :var | :field | :slot | :paint, term()}
          | {:ref_kind, atom(), atom()}
          | {:invalid_for, atom()}
          | {:unsupported_version, term()}
          | {:json, String.t()}
          | {:missing_dependency, :jason}
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

  @type error :: {path(), reason()}

  @frame_anchors [:title, :subtitle, :caption]
  @corners [:top_left, :top_right, :bottom_left, :bottom_right]
  @not_names [nil, true, false]

  @doc "`:ok`, or every fault of the design ordered by path."
  @spec validate(term()) :: :ok | {:error, [error(), ...]}
  def validate(map) when is_map(map) and not is_struct(map) do
    case node(:design, map, [], context(map)) ++ cycles(map) do
      [] -> :ok
      errors -> {:error, Enum.sort_by(errors, &elem(&1, 0))}
    end
  end

  def validate(_), do: {:error, [{[], {:type, {:node, :design}}}]}

  @doc """
  `:ok`, or every fault of a fragment read as a kind — **per-kind validity** (spec/14 §19.8).

  A design is validated whole. A composite must be `%{composite: %{uses, vars}}` and nothing
  else, its uses sites. Any other kind is the singular body under its key — `%{style: %{…}}`,
  `%{frame: %{…}}` — walked with that kind's schema and no design around it, so a reference
  to a scale, style, source, variable or field the fragment does not declare is not a fault:
  a fragment is a piece, and what it refers to is bound where it is composed. A fragment
  whose one key is not the kind's is refused as `{:type, {:node, kind}}`.
  """
  @spec validate(term(), atom()) :: :ok | {:error, [error(), ...]}
  def validate(map, :design), do: validate(map)

  def validate(%{composite: %{uses: uses, vars: vars}} = map, :composite)
      when is_list(uses) and is_map(vars) and map_size(map) == 1 do
    uses
    |> Enum.with_index()
    |> Enum.reject(fn {use, _index} -> is_struct(use, Visualize.Chart.Use) end)
    |> Enum.map(fn {_use, index} -> {[:composite, :uses, index], {:type, :use}} end)
    |> case do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  def validate(_map, :composite), do: {:error, [{[], {:type, {:node, :composite}}}]}

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
      nil when is_map(body) and not is_struct(body) -> node(kind, body, [kind], open_context())
      nil -> [{[kind], {:type, {:node, kind}}}]
      spec -> check_key(:design, spec, body, [kind], open_context())
    end
  end

  defp open_context do
    %{
      context(%{})
      | scales: :unknown,
        frame_kind: :unknown,
        styles: :unknown,
        paints: :unknown,
        sources: :unknown,
        vars: :unknown,
        slots: :unknown,
        partial?: true
    }
  end

  @doc "One error as `path: reason` in words; the path in `marks[1].channels.y` form."
  @spec format(error()) :: String.t()
  def format({path, reason}), do: "#{format_path(path)}: #{words(reason)}"

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

  # -- style derivation (spec/14 §3.5) --------------------------------------------------

  # A style that reaches itself through `extends` is `:cycle` at its own path; a style that
  # merely extends one that is on a cycle is not at fault and is not reported.
  defp cycles(map) do
    case map[:styles] do
      styles when is_map(styles) and not is_struct(styles) ->
        for {name, _node} <- styles,
            name?(name),
            walk(styles, parent(styles, name), name, []),
            do: {[:styles, name], :cycle}

      _other ->
        []
    end
  end

  defp walk(_styles, nil, _target, _seen), do: false
  defp walk(_styles, target, target, _seen), do: true

  defp walk(styles, name, target, seen) do
    if name in seen,
      do: false,
      else: walk(styles, parent(styles, name), target, [name | seen])
  end

  defp parent(styles, name) do
    case Map.get(styles, name) do
      %{extends: parent} -> if name?(parent), do: parent
      _other -> nil
    end
  end

  # -- context: what the design declares -----------------------------------------------

  defp context(map) do
    %{
      scales: declared(nested(map, [:frame, :scales])),
      frame_kind: nested(map, [:frame, :kind]),
      styles: union(declared(map[:styles]), Schema.builtin_styles()),
      paints: declared(map[:defs] || %{}),
      sources: source_fields(map[:sources]),
      vars: declared(map[:vars]),
      slots: slots(Map.get(map, :theme, Schema.default(:design, :theme))),
      mark_type: nil,
      op: nil,
      transform_keys: [],
      fields: :unknown,
      datum?: false,
      channel_keys: [],
      partial?: false
    }
  end

  defp nested(map, []), do: map
  defp nested(map, [k | rest]) when is_map(map) and not is_struct(map), do: nested(map[k], rest)
  defp nested(_, _), do: nil

  # What a design declares under a key: the names of the map, the empty set when the key is
  # absent (D-113) — a reference into it is then undeclared, never unchecked — and unknown
  # only for a value that is not a map, which is a type fault of its own.
  defp declared(map) when is_map(map) and not is_struct(map) do
    map |> Map.keys() |> Enum.filter(&name?/1) |> MapSet.new()
  end

  defp declared(nil), do: MapSet.new()
  defp declared(_), do: :unknown

  defp union(:unknown, _), do: :unknown
  defp union(set, more), do: MapSet.union(set, MapSet.new(more))

  defp source_fields(map) when is_map(map) and not is_struct(map) do
    Map.new(map, fn
      {name, %{fields: fields}} when is_list(fields) -> {name, fields}
      {name, _} -> {name, :unknown}
    end)
  end

  defp source_fields(nil), do: %{}
  defp source_fields(_), do: :unknown

  defp slots(:default), do: theme_slots(Theme.default())
  defp slots(:dark), do: theme_slots(Theme.dark())

  # An inline theme gives its slots only when it is a whole, valid theme: a variable in
  # it is resolved at application, and an invalid one is already reported on its keys.
  defp slots(map) when is_map(map) and not is_struct(map) do
    variable? = Enum.any?(map, fn {_, v} -> is_struct(v, Var) end)

    case node(:theme, map, [], %{vars: :unknown}) do
      [] when not variable? -> theme_slots(Theme.new(map))
      _ -> :unknown
    end
  end

  defp slots(_), do: :unknown

  defp theme_slots(theme), do: MapSet.new(Theme.slots(theme))

  # -- nodes ----------------------------------------------------------------------------

  defp node(kind, map, path, ctx) do
    ctx = enter(kind, map, ctx)
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

    unknown ++ missing ++ List.flatten(present) ++ held(kind, map, path, ctx)
  end

  # What a node's keys owe each other: a source's `types` names only its `fields` (§2.3).
  defp held(:source, %{fields: fields, types: types}, path, _ctx)
       when is_list(fields) and is_map(types) do
    for {name, _type} <- types,
        name?(name),
        name not in fields,
        do: {path ++ [:types, name], {:undeclared, :field, name}}
  end

  # A needle is a polar frame's mark (spec/14 §5.2, #392): elsewhere its type is invalid.
  defp held(:mark, %{type: :needle}, path, %{frame_kind: kind})
       when kind not in [:polar, :unknown],
       do: [{path ++ [:type], {:invalid_for, :needle}}]

  # The angle scale's sweep is a turn at most and never nothing; an axis's radius is
  # positive (spec/14 §4.3, §4.4, #390).
  defp held(:scale, %{sweep: sweep}, path, _ctx)
       when is_number(sweep) and (sweep == 0 or abs(sweep) > 360),
       do: [{path ++ [:sweep], :sweep}]

  defp held(:axis, %{radius: radius}, path, _ctx) when is_number(radius) and radius <= 0,
    do: [{path ++ [:radius], :radius}]

  defp held(_kind, _map, _path, _ctx), do: []

  defp enter(:mark, map, ctx) do
    type = map[:type]

    %{
      ctx
      | mark_type: if(type in Schema.mark_types(), do: type),
        fields: mark_fields(map[:data], ctx),
        datum?: true
    }
  end

  defp enter(:label, _map, ctx), do: %{ctx | datum?: false}
  defp enter(:channels, map, ctx), do: %{ctx | channel_keys: Map.keys(map)}

  defp enter(:transform, map, ctx) do
    op = map[:op]
    %{ctx | op: if(op in Schema.transform_ops(), do: op), transform_keys: Map.keys(map)}
  end

  defp enter(_kind, _map, ctx), do: ctx

  defp mark_fields(name, ctx) when is_atom(name), do: fields_of(name, ctx)

  defp mark_fields(%{source: name} = data, ctx) when is_map(data) do
    case Map.get(data, :transforms, []) do
      [] -> fields_of(name, ctx)
      _ -> :unknown
    end
  end

  defp mark_fields(_, _), do: :unknown

  defp fields_of(_, %{sources: :unknown}), do: :unknown
  defp fields_of(name, %{sources: sources}), do: Map.get(sources, name, :unknown)

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

  defp specs(kind, _ctx), do: Schema.describe(kind)

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

  defp required(:channels, type, _ctx), do: Schema.channels(type).required
  defp required(:options, _type, _ctx), do: []

  defp unknown_reason(kind, key, %{mark_type: type}) when kind in [:channels, :options] do
    if type != nil and Schema.key(kind, key) != nil, do: {:invalid_for, type}, else: :unknown_key
  end

  defp unknown_reason(:transform, key, %{op: op}) when op != nil do
    if Schema.key(:transform, key) != nil, do: {:invalid_for, op}, else: :unknown_key
  end

  defp unknown_reason(_kind, _key, _ctx), do: :unknown_key

  # A style value may be a channel binding for any key (spec/14 §3.2); the version must
  # be the one this library writes (spec/14 §9).
  defp check_key(:style, _spec, {:field, _} = ref, path, ctx),
    do: check(:field_ref, ref, path, ctx)

  defp check_key(:design, %{key: :version}, v, path, _ctx) when is_integer(v) do
    if v == Migration.current(), do: [], else: [{path, {:unsupported_version, v}}]
  end

  # A theme needs at least one series colour (spec/08 §7.2).
  defp check_key(:theme, %{key: :series}, [], path, _ctx), do: [{path, :required}]

  defp check_key(_kind, spec, v, path, ctx), do: check(spec.type, v, path, ctx)

  # -- types ----------------------------------------------------------------------------

  defp check(_type, %Var{name: name}, path, ctx), do: ref(:var, name, path, ctx)

  defp check({:node, kind}, v, path, ctx) when is_map(v) and not is_struct(v) do
    node(kind, v, path, ctx)
  end

  defp check({:list, t}, v, path, ctx) when is_list(v) do
    v |> Enum.with_index() |> Enum.flat_map(fn {e, i} -> check(t, e, path ++ [i], ctx) end)
  end

  defp check({:map, t}, v, path, ctx) when is_map(v) and not is_struct(v) do
    Enum.flat_map(v, fn {k, e} ->
      if name?(k), do: check(t, e, path ++ [k], ctx), else: [{path ++ [k], {:type, :name}}]
    end)
  end

  defp check({:one_of, types} = t, v, path, ctx) do
    case Schema.select(types, v) do
      nil -> [{path, {:type, t}}]
      type -> check(type, v, path, ctx)
    end
  end

  defp check({:enum, allowed}, v, path, _ctx) do
    if v in allowed, do: [], else: [{path, {:enum, allowed}}]
  end

  defp check({:ref, kind}, v, path, ctx) when is_atom(v) do
    if name?(v), do: ref(kind, v, path, ctx), else: [{path, {:type, {:ref, kind}}}]
  end

  # An id is accepted by its tag alone (spec/14 §19.2, D-100): whether the store holds it is
  # resolution's question, and a missing one is a mask there, not an error here. A tag of
  # the wrong kind is refused now, before anything tries to resolve it.
  defp check({:ref, kind}, {kind, n}, _path, _ctx) when is_integer(n) and n > 0, do: []

  defp check({:ref, kind}, {other, n}, path, _ctx) when is_atom(other) and is_integer(n),
    do: [{path, {:ref_kind, kind, other}}]

  defp check(:field, v, path, ctx) when is_atom(v) do
    if name?(v), do: ref(:field, v, path, ctx), else: [{path, {:type, :field}}]
  end

  defp check(:field_ref, {:field, f}, path, ctx) when is_atom(f) do
    if name?(f), do: ref(:field, f, path, ctx), else: [{path, {:type, :field_ref}}]
  end

  defp check(:channel, v, _path, _ctx) when is_number(v), do: []
  defp check(:channel, v, path, ctx) when is_atom(v), do: check(:field, v, path, ctx)
  defp check(:channel, {:field, _} = v, path, ctx), do: check(:field_ref, v, path, ctx)

  defp check(:extent, :auto, _path, _ctx), do: []

  defp check(:extent, v, path, _ctx) when is_list(v) do
    if extent?(v), do: [], else: [{path, {:type, :extent}}]
  end

  defp check(:text, v, path, ctx) when is_list(v) do
    v |> Enum.with_index() |> Enum.flat_map(fn {part, i} -> text_part(part, path ++ [i], ctx) end)
  end

  # The string form (§7.1): read into parts and checked as parts, at the key's path.
  defp check(:text, v, path, ctx) when is_binary(v) do
    case Text.parse(v) do
      {:ok, parts} -> Enum.flat_map(parts, &text_part(&1, path, ctx))
      {:error, reason} -> [{path, {:template, reason}}]
    end
  end

  defp check(:anchor, v, _path, _ctx) when v in @frame_anchors, do: []

  defp check(:anchor, {:axis, s}, path, ctx) when is_atom(s) do
    if name?(s), do: ref(:scale, s, path, ctx), else: [{path, {:type, :anchor}}]
  end

  defp check(:anchor, {:frame, c}, _path, _ctx) when c in @corners, do: []

  defp check(:anchor, {:data, [x, y]}, path, _ctx) do
    if term?(x) and term?(y), do: [], else: [{path, {:type, :anchor}}]
  end

  defp check(:colour, v, _path, _ctx) when is_binary(v) or v == :none, do: []
  # A paint names a gradient of `defs` (spec/14 §2.7, §3.2).
  defp check(:colour, {:paint, name}, path, ctx) when is_atom(name),
    do: ref(:paint, name, path, ctx)

  defp check(:colour, v, path, ctx), do: slot_or(:colour, v, path, ctx)
  defp check(:size, v, _path, _ctx) when is_number(v), do: []
  defp check(:size, v, path, ctx), do: slot_or(:size, v, path, ctx)
  defp check(:font, v, _path, _ctx) when is_binary(v), do: []
  defp check(:font, v, path, ctx), do: slot_or(:font, v, path, ctx)
  defp check(:slot, v, path, ctx), do: slot_or(:slot, v, path, ctx)

  defp check(:term, v, path, _ctx) do
    if term?(v), do: [], else: [{path, {:type, :term}}]
  end

  defp check(:name, v, _path, _ctx) when is_atom(v) and v not in @not_names, do: []
  defp check(:integer, v, _path, _ctx) when is_integer(v), do: []
  defp check(:number, v, _path, _ctx) when is_number(v), do: []
  defp check(:boolean, v, _path, _ctx) when is_boolean(v), do: []
  defp check(:string, v, _path, _ctx) when is_binary(v), do: []
  defp check(type, _v, path, _ctx), do: [{path, {:type, type}}]

  defp text_part(part, _path, _ctx) when is_binary(part), do: []
  defp text_part(%Var{name: name}, path, ctx), do: ref(:var, name, path, ctx)

  defp text_part({:field, _} = part, path, %{datum?: true} = ctx) do
    check(:field_ref, part, path, ctx)
  end

  defp text_part({:field, _}, path, _ctx), do: [{path, {:invalid_for, :label}}]
  defp text_part(_, path, _ctx), do: [{path, {:type, :text}}]

  defp slot_or(type, v, path, ctx) do
    if slot?(v), do: ref(:slot, v, path, ctx), else: [{path, {:type, type}}]
  end

  defp slot?({:series, i}), do: is_integer(i) and i >= 1
  defp slot?(v), do: name?(v)

  defp name?(v), do: is_atom(v) and v not in @not_names

  # `:auto` is a bound, so only a two-element list may carry it (spec/14 §1.4).
  defp extent?(list) do
    Enum.all?(list, &(category?(&1) or &1 == :auto)) and
      (:auto not in list or length(list) == 2)
  end

  defp category?(%DateTime{}), do: true
  defp category?(v), do: is_number(v) or is_binary(v) or (name?(v) and v != :auto)

  defp term?(%DateTime{}), do: true
  defp term?(v) when is_number(v) or is_binary(v) or is_atom(v), do: true
  defp term?(v) when is_list(v), do: Enum.all?(v, &term?/1)

  defp term?(v) when is_map(v) and not is_struct(v) do
    Enum.all?(v, fn {k, e} -> name?(k) and term?(e) end)
  end

  defp term?(_), do: false

  # -- references -----------------------------------------------------------------------

  defp ref(:slot, {:series, _}, _path, _ctx), do: []

  defp ref(kind, name, path, ctx) do
    case Map.fetch!(ctx, plural(kind)) do
      :unknown ->
        []

      %MapSet{} = set ->
        undeclared(kind, name, path, not MapSet.member?(set, name))

      fields when is_list(fields) ->
        undeclared(kind, name, path, name not in fields)

      sources when is_map(sources) ->
        undeclared(kind, name, path, not Map.has_key?(sources, name))
    end
  end

  defp undeclared(kind, name, path, true), do: [{path, {:undeclared, kind, name}}]
  defp undeclared(_kind, _name, _path, false), do: []

  defp plural(:scale), do: :scales
  defp plural(:style), do: :styles
  defp plural(:paint), do: :paints
  defp plural(:source), do: :sources
  defp plural(:var), do: :vars
  defp plural(:field), do: :fields
  defp plural(:slot), do: :slots

  # -- formatting -----------------------------------------------------------------------

  defp words(:sweep), do: "must be within a turn, and not zero"
  defp words(:radius), do: "must be positive"
  defp words(:required), do: "is required"
  defp words(:unknown_key), do: "is not a key of this node"
  defp words({:type, type}), do: "must be #{type_words(type)}"

  defp words({:ref_kind, wanted, given}),
    do: "is a #{given} id where a #{wanted} was expected"

  defp words({:enum, allowed}), do: "must be one of #{list(allowed)}"

  defp words({:undeclared, :field, name}) do
    "field #{inspect(name)} is not declared by the mark's source"
  end

  defp words({:undeclared, :slot, name}), do: "slot #{inspect(name)} is not a slot of the theme"
  defp words({:undeclared, kind, name}), do: "#{kind} #{inspect(name)} is not declared"
  defp words({:invalid_for, type}), do: "is not read by #{inspect(type)}"

  defp words({:unsupported_version, v}) do
    "version #{inspect(v)} is not supported; the current version is #{Migration.current()}"
  end

  # The builder's need of spec/14 §18.16 (#370), worded here so one reader serves it.
  defp words({:unscaled, field}) do
    "reads #{inspect(field)} through no scale — say what #{inspect(field)} is under data, " <>
      "or declare the scale under frame"
  end

  defp words({:json, message}), do: "JSON does not parse: #{message}"
  defp words({:missing_dependency, :jason}), do: "needs the optional dependency Jason"

  defp words({:unresolved, :var, name}) do
    "variable #{inspect(name)} has no value at application and no default"
  end

  defp words({:var_binding, name}) do
    "variable #{inspect(name)} is bound to another variable; resolution is single level"
  end

  defp words({:unbound, :source, name}) do
    "slot #{inspect(name)} has no source in the pool under its name or its default"
  end

  defp words({:missing_field, field}), do: "has no field #{inspect(field)}"
  defp words(:conflict), do: "is declared differently by two fragments"

  defp words(:cycle), do: "extends itself, directly or through a chain of `extends`"

  # A text that does not read (spec/14 §7.1).
  defp words({:template, :unterminated}), do: ~S|has a #{ with no closing }|

  defp words({:template, {:hole, hole}}),
    do: ~S|has #{| <> hole <> ~S|}, which names neither var(:name) nor field(:name)|

  # A fault of a composite rather than of a node (spec/14 §19.6): the stack reaching itself.
  defp words({:cycle, chain}), do: "the stack refers to itself through #{inspect(chain)}"

  # A map that is many things is no kind of fragment (spec/14 §19.8).
  defp words(:many_kinds),
    do: "is many things at once, which is no kind of fragment; make it a composite of sites"

  defp type_words(:integer), do: "an integer"
  defp type_words(:number), do: "a number"
  defp type_words(:boolean), do: "a boolean"
  defp type_words(:string), do: "a string"
  defp type_words(:name), do: "a name (an atom)"
  defp type_words(:field), do: "a field name"
  defp type_words(:field_ref), do: "{:field, name}"
  defp type_words(:channel), do: "a field name, a number or {:field, name}"
  defp type_words(:extent), do: "an extent: :auto, [lo, hi] or a list of categories"
  defp type_words(:text), do: ~S|a string, with #{var(:name)} for a variable|

  defp type_words(:anchor) do
    "an anchor: :title, :subtitle, :caption, {:axis, scale}, {:frame, corner} or " <>
      "{:data, [x, y]}"
  end

  defp type_words(:colour), do: "a colour string, :none, a theme slot or a paint"
  defp type_words(:size), do: "a number or a theme slot"
  defp type_words(:font), do: "a font string or a theme slot"
  defp type_words(:slot), do: "a theme slot"
  defp type_words(:term), do: "a JSON-representable term"
  defp type_words({:enum, allowed}), do: "one of #{list(allowed)}"
  defp type_words({:list, t}), do: "a list of #{type_words(t)}"
  defp type_words({:map, t}), do: "a map from names to #{type_words(t)}"
  defp type_words({:node, kind}), do: "a #{kind} node"
  defp type_words({:ref, kind}), do: "a declared #{kind} name, or a #{kind} id"
  defp type_words({:one_of, types}), do: Enum.map_join(types, " or ", &type_words/1)

  defp list(atoms), do: Enum.map_join(atoms, ", ", &inspect/1)
end
