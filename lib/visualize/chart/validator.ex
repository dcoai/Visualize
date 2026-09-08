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

  alias Visualize.Chart.{Migration, Schema, Var}
  alias Visualize.Theme

  @typedoc "Keys and list indexes from the design to a value; `[]` is the design."
  @type path :: [atom() | non_neg_integer()]

  @typedoc "Why a value is at fault (spec/14 §10.1)."
  @type reason ::
          :required
          | :unknown_key
          | {:type, Schema.type()}
          | {:enum, [atom()]}
          | {:undeclared, :scale | :style | :source | :var | :field | :slot, term()}
          | {:invalid_for, atom()}
          | {:unsupported_version, term()}
          | {:json, String.t()}
          | {:missing_dependency, :jason}

  @type error :: {path(), reason()}

  @frame_anchors [:title, :subtitle, :caption]
  @corners [:top_left, :top_right, :bottom_left, :bottom_right]
  @not_names [nil, true, false]

  @doc "`:ok`, or every fault of the design ordered by path."
  @spec validate(term()) :: :ok | {:error, [error(), ...]}
  def validate(map) when is_map(map) and not is_struct(map) do
    case node(:design, map, [], context(map)) do
      [] -> :ok
      errors -> {:error, Enum.sort_by(errors, &elem(&1, 0))}
    end
  end

  def validate(_), do: {:error, [{[], {:type, {:node, :design}}}]}

  @doc "One error as `path: reason` in words; the path in `marks[1].channels.y` form."
  @spec format(error()) :: String.t()
  def format({path, reason}), do: "#{format_path(path)}: #{words(reason)}"

  # -- context: what the design declares -----------------------------------------------

  defp context(map) do
    %{
      scales: declared(nested(map, [:frame, :scales])),
      styles: union(declared(map[:styles]), Schema.builtin_styles()),
      sources: source_fields(map[:sources]),
      vars: declared(map[:vars]),
      slots: slots(Map.get(map, :theme, Schema.default(:design, :theme))),
      mark_type: nil,
      fields: :unknown,
      datum?: false
    }
  end

  defp nested(map, []), do: map
  defp nested(map, [k | rest]) when is_map(map) and not is_struct(map), do: nested(map[k], rest)
  defp nested(_, _), do: nil

  defp declared(map) when is_map(map) and not is_struct(map) do
    map |> Map.keys() |> Enum.filter(&name?/1) |> MapSet.new()
  end

  defp declared(_), do: :unknown

  defp union(:unknown, _), do: :unknown
  defp union(set, more), do: MapSet.union(set, MapSet.new(more))

  defp source_fields(map) when is_map(map) and not is_struct(map) do
    Map.new(map, fn
      {name, %{fields: fields}} when is_list(fields) -> {name, fields}
      {name, _} -> {name, :unknown}
    end)
  end

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
      for s <- specs, s.required, not Map.has_key?(map, s.key), do: {path ++ [s.key], :required}

    present =
      for s <- specs, Map.has_key?(map, s.key) do
        check_key(kind, s, Map.fetch!(map, s.key), path ++ [s.key], ctx)
      end

    unknown ++ missing ++ List.flatten(present)
  end

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
  defp specs(kind, %{mark_type: type}) when kind in [:channels, :options] and type != nil do
    allowed = allowed(kind, type)

    for s <- Schema.describe(kind), s.key in allowed do
      %{s | required: s.key in required(kind, type)}
    end
  end

  defp specs(kind, _ctx), do: Schema.describe(kind)

  defp allowed(:channels, type) do
    %{required: required, optional: optional} = Schema.channels(type)
    required ++ optional
  end

  defp allowed(:options, type), do: Schema.options(type)

  defp required(:channels, type), do: Schema.channels(type).required
  defp required(:options, _type), do: []

  defp unknown_reason(kind, key, %{mark_type: type}) when kind in [:channels, :options] do
    if type != nil and Schema.key(kind, key) != nil, do: {:invalid_for, type}, else: :unknown_key
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

  defp check(:anchor, v, _path, _ctx) when v in @frame_anchors, do: []

  defp check(:anchor, {:axis, s}, path, ctx) when is_atom(s) do
    if name?(s), do: ref(:scale, s, path, ctx), else: [{path, {:type, :anchor}}]
  end

  defp check(:anchor, {:frame, c}, _path, _ctx) when c in @corners, do: []

  defp check(:anchor, {:data, [x, y]}, path, _ctx) do
    if term?(x) and term?(y), do: [], else: [{path, {:type, :anchor}}]
  end

  defp check(:colour, v, _path, _ctx) when is_binary(v) or v == :none, do: []
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
  defp plural(:source), do: :sources
  defp plural(:var), do: :vars
  defp plural(:field), do: :fields
  defp plural(:slot), do: :slots

  # -- formatting -----------------------------------------------------------------------

  defp format_path([]), do: "design"

  defp format_path(path) do
    Enum.reduce(path, "", fn
      i, acc when is_integer(i) -> "#{acc}[#{i}]"
      k, "" -> "#{k}"
      k, acc -> "#{acc}.#{k}"
    end)
  end

  defp words(:required), do: "is required"
  defp words(:unknown_key), do: "is not a key of this node"
  defp words({:type, type}), do: "must be #{type_words(type)}"
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

  defp words({:json, message}), do: "JSON does not parse: #{message}"
  defp words({:missing_dependency, :jason}), do: "needs the optional dependency Jason"

  defp type_words(:integer), do: "an integer"
  defp type_words(:number), do: "a number"
  defp type_words(:boolean), do: "a boolean"
  defp type_words(:string), do: "a string"
  defp type_words(:name), do: "a name (an atom)"
  defp type_words(:field), do: "a field name"
  defp type_words(:field_ref), do: "{:field, name}"
  defp type_words(:channel), do: "a field name, a number or {:field, name}"
  defp type_words(:extent), do: "an extent: :auto, [lo, hi] or a list of categories"
  defp type_words(:text), do: "a list of strings, variables and field references"

  defp type_words(:anchor) do
    "an anchor: :title, :subtitle, :caption, {:axis, scale}, {:frame, corner} or " <>
      "{:data, [x, y]}"
  end

  defp type_words(:colour), do: "a colour string, :none or a theme slot"
  defp type_words(:size), do: "a number or a theme slot"
  defp type_words(:font), do: "a font string or a theme slot"
  defp type_words(:slot), do: "a theme slot"
  defp type_words(:term), do: "a JSON-representable term"
  defp type_words({:enum, allowed}), do: "one of #{list(allowed)}"
  defp type_words({:list, t}), do: "a list of #{type_words(t)}"
  defp type_words({:map, t}), do: "a map from names to #{type_words(t)}"
  defp type_words({:node, kind}), do: "a #{kind} node"
  defp type_words({:ref, kind}), do: "a declared #{kind} name"
  defp type_words({:one_of, types}), do: Enum.map_join(types, " or ", &type_words/1)

  defp list(atoms), do: Enum.map_join(atoms, ", ", &inspect/1)
end
