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

  alias Visualize.Chart.{Fact, Migration, Schema, Text, Var}
  alias Visualize.Chart.Validator.{Domain, Frames, Palette, Words}
  alias Visualize.Data.Schema, as: FeedSchema
  alias Visualize.Theme

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
          | {:undeclared, :scale | :style | :source | :var | :field | :slot | :paint, term()}
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
          | {:colour_map, atom()}
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

  @frame_anchors [:title, :subtitle, :caption]
  # The plot's four corners and its centre (spec/14 §6.3, #489).
  @frame_points [:top_left, :top_right, :bottom_left, :bottom_right, :center]
  @not_names [nil, true, false]
  # A style and its parts, any of whose values may be a channel binding (spec/14 §3.2).
  @style_kinds [:style, :paint, :stroke, :font, :text_layout, :effect, :marker, :curve]

  @doc "`:ok`, or every fault of the design ordered by path."
  @spec validate(term()) :: :ok | {:error, [error(), ...]}
  def validate(map) when is_map(map) and not is_struct(map) do
    # Read in the shape this library writes: a style's flat keys are its parts (§3.1, §9).
    map = Migration.parts(map, :design)

    case node(:design, map, [], context(map)) ++ cycles(map) ++ Domain.faults(map) do
      [] -> :ok
      errors -> {:error, Enum.sort_by(errors, &elem(&1, 0))}
    end
  end

  def validate(_), do: {:error, [{[], {:type, {:node, :design}}}]}

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
        node(kind, Migration.parts(body, kind), [kind], open_context())

      nil ->
        [{[kind], {:type, {:node, kind}}}]

      spec ->
        body = Map.fetch!(Migration.parts(%{kind => body}, :design), kind)
        check_key(:design, spec, body, [kind], open_context())
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
    frames = if is_map(map[:frames]), do: map[:frames], else: %{}
    one = if map_size(frames) == 1, do: frames |> Map.values() |> hd()
    theme = known_theme(Map.get(map, :theme, Schema.default(:design, :theme)))

    %{
      # A scale name resolves inside a mark's *own* frame (spec/14 §5.1, #383): the
      # design-level context is the single frame's where there is one, and `enter(:mark)`
      # narrows it to the frame the mark names where there are several.
      layout: if(is_map(map[:layout]), do: map[:layout], else: nil),
      frames: declared(map[:frames]),
      frame_nodes: frames,
      scales: declared(one && nested(one, [:scales])),
      frame_kind: one && nested(one, [:kind]),
      frame_node: one,
      # A style reference reaches the design's styles, then the theme's palette (spec/14
      # §3.3, #637): a theme the validator cannot see says how many style series it has.
      styles: union(declared(map[:styles]), Palette.names(theme)),
      open_series: theme == :unknown,
      paints: declared(map[:defs] || %{}),
      sources: source_fields(map[:sources]),
      vars: declared(map[:vars]),
      slots: theme_slots(theme),
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

  # The theme the validator can see: a built-in one, or an inline one that is whole and
  # valid — a variable in it is resolved at application, and an invalid one is already
  # reported on its keys. Its slots and its palette names are what references are checked
  # against (spec/14 §2.5, §3.2, §3.3); any other theme is `:unknown`.
  defp known_theme(name) when is_atom(name) and name not in @not_names,
    do: Theme.builtin(name) || :unknown

  defp known_theme(map) when is_map(map) and not is_struct(map) do
    variable? = Enum.any?(map, fn {_, v} -> is_struct(v, Var) end)

    case node(:theme, map, [], %{open_context() | vars: :unknown}) do
      [] when not variable? -> Theme.new(map)
      _ -> :unknown
    end
  end

  defp known_theme(_), do: :unknown

  defp theme_slots(:unknown), do: :unknown
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

  # What a node's keys owe each other: a source's `types` and `requires` name only its
  # `fields` (§2.3, §7.4).
  defp held(:source, %{fields: fields} = source, path, _ctx) when is_list(fields) do
    for key <- [:types, :requires],
        names = Map.get(source, key),
        is_map(names) and not is_struct(names),
        {name, _value} <- names,
        name?(name),
        name not in fields,
        do: {path ++ [key, name], {:undeclared, :field, name}}
  end

  # An inline theme's ramps, roles and palette entries hold their contracts (spec/08 §7.5,
  # §7.7, D-135, D-171): measured once the keys they are read with are well typed, so a
  # type fault is not reported twice, and only the first breach, as construction refuses
  # at the first.
  defp held(:theme, map, path, _ctx) do
    with ramps when is_map(ramps) <- Map.get(map, :ramps, %{}),
         roles when is_map(roles) <- Map.get(map, :roles, %{}),
         styles when is_map(styles) and not is_struct(styles) <- Map.get(map, :styles, %{}),
         true <- Enum.all?(ramps, fn {_, v} -> is_list(v) and Enum.all?(v, &is_binary/1) end),
         true <- Enum.all?(roles, fn {_, v} -> is_binary(v) end),
         true <- Enum.all?(styles, fn {_, v} -> is_map(v) and not is_struct(v) end),
         theme = Theme.build(Theme.default(), Map.take(map, [:ramps, :roles, :styles])),
         {:error, {kind, name}, message} <- Theme.check(theme) do
      [{path ++ [plural(kind), name], {:contract, message}}]
    else
      _ -> []
    end
  end

  # A layout's weights are positive: a cell of no width is not a cell (spec/14 §2.8, #384).
  defp held(:layout, map, path, _ctx) do
    for key <- [:columns, :rows],
        weights = Map.get(map, key),
        is_list(weights),
        not Enum.all?(weights, &(is_number(&1) and &1 > 0)),
        do: {path ++ [key], {:weight, key}}
  end

  # A sync group and the design's brush read a linear or a time x of a cartesian frame
  # (spec/14 §2.9, D-116, D-143): the hooks map a value by linear interpolation, which is
  # that scale and no other.
  defp held(:interaction, map, path, ctx) do
    for {key, given?} <- [sync: is_binary(Map.get(map, :sync)), brush: Map.get(map, :brush) == :x],
        given?,
        fault <- Frames.linear_x(Map.get(map, :frame), ctx.frame_nodes),
        do: {path ++ [key], Tuple.insert_at(fault, 0, key)}
  end

  # A frame says where it goes once (spec/14 §4.2, §2.8, #384): its box, or its cell on
  # the design's grid, and a cell stays inside that grid.
  defp held(:frame, %{box: _box, cell: _cell}, path, _ctx), do: [{path, :both}]

  defp held(:frame, %{cell: cell} = frame, path, ctx) when is_list(cell) do
    if inside?(cell, Map.get(frame, :span), ctx.layout),
      do: [],
      else: [{path ++ [:cell], :outside}]
  end

  # A needle is a polar frame's mark (spec/14 §5.2, #392): elsewhere its type is invalid.
  defp held(:mark, %{type: :needle}, path, %{frame_kind: kind})
       when kind not in [:polar, :unknown],
       do: [{path ++ [:type], {:invalid_for, :needle}}]

  # A basemap lies under a tile-aligned Mercator projection only (spec/14 §5.2, spec/07
  # §8.1), and its provider's node belongs to it alone.
  defp held(:mark, %{type: :tiles}, path, ctx),
    do: Frames.tiles_frame(ctx.frame_node, path ++ [:type])

  defp held(:mark, %{type: type, tiles: _}, path, _ctx) when is_atom(type),
    do: [{path ++ [:tiles], {:invalid_for, type}}]

  defp held(:tiles, map, path, _ctx) do
    attribution =
      case Map.get(map, :attribution) do
        text when is_binary(text) ->
          if String.trim(text) == "",
            do: [{path ++ [:attribution], {:tiles, :attribution}}],
            else: []

        _other ->
          []
      end

    url =
      case Map.get(map, :url) do
        url when is_binary(url) ->
          missing? = not Enum.all?(["{z}", "{x}", "{y}"], &String.contains?(url, &1))
          empty? = String.contains?(url, "{s}") and Map.get(map, :subdomains) == []

          if(missing?, do: [{path ++ [:url], {:tiles, :url}}], else: []) ++
            if(empty?, do: [{path ++ [:subdomains], {:tiles, :subdomains}}], else: [])

        _other ->
          []
      end

    attribution ++ url
  end

  defp held(:scale, map, path, _ctx) do
    sweep(map, path) ++ zone(map, path) ++ colour_map(map, path) ++ polarity(map, path)
  end

  defp held(:axis, %{radius: radius}, path, _ctx) when is_number(radius) and radius <= 0,
    do: [{path ++ [:radius], :radius}]

  # An axis's measure is a UCUM code Visualize.Unit reads and a quantity of its dimension
  # (spec/14 §4.4, §10.1, D-138). Only values of the right type are checked: a wrong type
  # or quantity is the type check's fault, and a variable is checked once it is bound.
  defp held(:measure, measure, path, _ctx) do
    typed =
      Map.filter(measure, fn
        {:unit, unit} -> is_binary(unit)
        {:quantity, quantity} -> quantity in Visualize.Quantity.all()
        _other -> false
      end)

    case Visualize.Quantity.resolve(typed) do
      {:ok, _resolved} -> []
      {:error, {:unit, code, reason}} -> [{path ++ [:unit], {:unit, code, reason}}]
      {:error, {:quantity, _quantity, _code} = reason} -> [{path ++ [:quantity], reason}]
    end
  end

  defp held(_kind, _map, _path, _ctx), do: []

  # The angle scale's sweep is a turn at most and never nothing; an axis's radius is
  # positive (spec/14 §4.3, §4.4, #390).
  defp sweep(%{sweep: sweep}, path) when is_number(sweep) and (sweep == 0 or abs(sweep) > 360),
    do: [{path ++ [:sweep], :sweep}]

  defp sweep(_scale, _path), do: []

  # A time scale's zone is one the host's time zone database can show (spec/14 §4.3, §10.1,
  # #447): a host without a database, or a name it does not know, is refused by name
  # rather than drawn in UTC (D-115).
  defp zone(%{kind: :time, zone: zone}, path) when is_binary(zone) do
    case Visualize.Scale.Time.check_zone(zone) do
      :ok -> []
      {:error, reason} -> [{path ++ [:zone], {:zone, zone, reason}}]
    end
  end

  defp zone(_scale, _path), do: []

  # A map of colours is an ordinal scale's range (spec/14 §4.3, D-143): it pins categories,
  # and a continuous scale has none.
  defp colour_map(%{kind: kind, range: %{} = range}, path)
       when is_atom(kind) and kind != :ordinal and not is_struct(range),
       do: [{path ++ [:range], {:colour_map, kind}}]

  defp colour_map(_scale, _path), do: []

  # Polarity orders a ramp (spec/14 §4.3, D-143) — a `{:ramp, name}` range, or the `:auto`
  # range of a sequential or a diverging scale, which is its theme ramp; a list or a map
  # already says each colour.
  defp polarity(%{polarity: polarity} = scale, path) when is_atom(polarity) and polarity != nil do
    case {Map.get(scale, :kind), Map.get(scale, :range, :auto)} do
      {_kind, {:ramp, _name}} -> []
      {kind, :auto} when kind in [:sequential, :diverging] -> []
      {_kind, %Var{}} -> []
      {_kind, %Fact{}} -> []
      _other -> [{path ++ [:polarity], {:polarity, :range}}]
    end
  end

  defp polarity(_scale, _path), do: []

  defp enter(:mark, map, ctx) do
    type = map[:type]

    ctx
    |> in_frame(map[:frame])
    |> Map.merge(%{
      mark_type: if(type in Schema.mark_types(), do: type),
      fields: mark_fields(map[:data], ctx),
      datum?: true
    })
  end

  defp enter(:label, map, ctx), do: %{in_frame(ctx, map[:frame]) | datum?: false}

  defp enter(:channels, map, ctx), do: %{ctx | channel_keys: Map.keys(map)}

  defp enter(:transform, map, ctx) do
    op = map[:op]
    %{ctx | op: if(op in Schema.transform_ops(), do: op), transform_keys: Map.keys(map)}
  end

  # Inside a frame, a scale name is that frame's (spec/14 §4.3, #383): its axes and its
  # legend read the scales it declares, whatever the design's other frames declare.
  defp enter(:frame, map, ctx) do
    %{ctx | scales: declared(map[:scales]), frame_kind: map[:kind]}
  end

  defp enter(:fit, map, ctx),
    do: %{ctx | transform_keys: Map.keys(map), fields: fields_of(map[:data], ctx)}

  defp enter(_kind, _map, ctx), do: ctx

  # The scales and the kind a node's scale references resolve against: its own frame's
  # where it names one, the design-level context's otherwise (spec/14 §5.1, §6.1).
  defp in_frame(ctx, nil), do: ctx

  defp in_frame(%{frame_nodes: frames} = ctx, name) when is_map_key(frames, name) do
    node = Map.fetch!(frames, name)

    %{
      ctx
      | scales: declared(nested(node, [:scales])),
        frame_kind: nested(node, [:kind]),
        frame_node: node
    }
  end

  defp in_frame(ctx, _name), do: ctx

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
    do: check(:field_ref, ref, path, ctx)

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
        gradient(paint, at)
      end

    check(spec.type, defs, path, ctx) ++ List.flatten(gradients)
  end

  # A theme needs at least one series colour (spec/08 §7.2).
  defp check_key(:theme, %{key: :series}, [], path, _ctx), do: [{path, :required}]

  # A stored theme's palette entries are style nodes (spec/14 §2.5, #637), a role's `:cue`
  # and an `extends` left to the palette's contracts, which `held(:theme)` measures.
  defp check_key(:theme, %{key: :styles}, styles, path, ctx)
       when is_map(styles) and not is_struct(styles) do
    Enum.flat_map(styles, fn
      {name, entry} when is_map(entry) and not is_struct(entry) ->
        if name?(name),
          do: node(:style, Palette.entry(entry), path ++ [name], ctx),
          else: [{path ++ [name], {:type, :name}}]

      {name, %Var{} = var} ->
        check(:term, var, path ++ [name], ctx)

      {name, _other} ->
        [{path ++ [name], {:type, {:node, :style}}}]
    end)
  end

  defp check_key(_kind, spec, v, path, ctx), do: check(spec.type, v, path, ctx)

  # -- types ----------------------------------------------------------------------------

  defp check(_type, %Var{name: name}, path, ctx), do: ref(:var, name, path, ctx)
  defp check(_type, %Fact{} = fact, path, ctx), do: fact(fact, path, ctx, false)

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

  # A channel naming its scale's own end (spec/14 §5.2, #420); any other `:scale` tuple is
  # a typed fault rather than a silent pass.
  defp check(:channel, {:scale, which}, _path, _ctx) when which in [:min, :max], do: []
  defp check(:channel, {:scale, _other}, path, _ctx), do: [{path, {:type, :channel}}]

  # A scale adopted from another frame (spec/14 §4.3, #384): the frame is declared, it
  # declares the scale, and the chain of adoptions ends at a node rather than returning.
  defp check(:adopted, {:frame, frame, scale} = value, path, ctx) do
    cond do
      not (name?(frame) and name?(scale)) -> [{path, {:type, :adopted}}]
      ctx.frame_nodes == %{} -> []
      true -> adopted(frame, scale, path, ctx, MapSet.new([source(path, value)]))
    end
  end

  defp check(:adopted, _value, path, _ctx), do: [{path, {:type, :adopted}}]

  # A stack's fixed order (spec/14 §5.4.1, #492): series keys, which need not be the
  # step's fields — a listed key the stack lacks is ignored, never a fault.
  defp check(:key_order, {:keys, keys}, path, _ctx) when is_list(keys) do
    if Enum.all?(keys, &name?/1), do: [], else: [{path, {:type, :key_order}}]
  end

  defp check(:key_order, _value, path, _ctx), do: [{path, {:type, :key_order}}]

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

  defp check(:anchor, {:frame, c}, _path, _ctx) when c in @frame_points, do: []

  defp check(:anchor, {:data, [x, y]}, path, _ctx) do
    if term?(x) and term?(y), do: [], else: [{path, {:type, :anchor}}]
  end

  defp check(:colour, v, _path, _ctx) when is_binary(v) or v in [:none, :contrast], do: []
  # A paint names a gradient of `defs` (spec/14 §2.7, §3.2).
  defp check(:colour, {:paint, name}, path, ctx) when is_atom(name),
    do: ref(:paint, name, path, ctx)

  # A ramp position is a meaning the theme renders (spec/14 §3.2, D-135).
  defp check(:colour, {:ramp, name, t}, path, _ctx) do
    if name in Theme.ramp_names() and is_number(t) and t >= 0 and t <= 1,
      do: [],
      else: [{path, {:type, :colour}}]
  end

  defp check(:colour, v, path, ctx), do: slot_or(:colour, v, path, ctx)

  defp check(:ramp, {:ramp, name}, path, _ctx) do
    if name in Theme.ramp_names(), do: [], else: [{path, {:type, :ramp}}]
  end

  # A map of colours (spec/14 §4.3, D-143): each category's colour as a style takes one,
  # checked at the category's own path.
  defp check(:colour_map, map, path, ctx) when is_map(map) and not is_struct(map) do
    Enum.flat_map(map, fn {category, colour} ->
      check(:colour, colour, path ++ [category], ctx)
    end)
  end

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

  # A declared paint's own faults beside its keys' types: no type, a type that is not a
  # gradient, no stops (spec/14 §2.7). A variable stands for what application gives.
  defp gradient(paint, path) do
    type =
      case Map.fetch(paint, :type) do
        :error ->
          [{path ++ [:type], :required}]

        {:ok, %Var{}} ->
          []

        {:ok, t} when t in [:linear, :radial] ->
          []

        # A paint's other types are named here; anything else is the paint's own enum fault.
        {:ok, t} when t in [:none, :solid, :paint] ->
          [{path ++ [:type], {:enum, [:linear, :radial]}}]

        {:ok, _other} ->
          []
      end

    stops = if Map.has_key?(paint, :stops), do: [], else: [{path ++ [:stops], :required}]
    type ++ stops
  end

  defp text_part(part, _path, _ctx) when is_binary(part), do: []
  defp text_part(%Var{name: name}, path, ctx), do: ref(:var, name, path, ctx)
  defp text_part(%Fact{} = fact, path, ctx), do: fact(fact, path, ctx, true)

  defp text_part({:field, _} = part, path, %{datum?: true} = ctx) do
    check(:field_ref, part, path, ctx)
  end

  defp text_part({:field, _}, path, _ctx), do: [{path, {:invalid_for, :label}}]
  defp text_part(_, path, _ctx), do: [{path, {:type, :text}}]

  # A fact of a feed's schema (spec/14 §7.4): a declared slot, one of its fields and an
  # attribute; in a text, an attribute written as words, never `order`'s list or
  # `status`'s map. Whether the schema gives it is application's question.
  defp fact(%Fact{source: s, field: f, key: k}, path, ctx, text?) do
    cond do
      not (name?(s) and name?(f) and name?(k)) ->
        [{path, {:type, :fact}}]

      k not in FeedSchema.attributes() ->
        [{path, {:enum, FeedSchema.attributes()}}]

      text? and k in [:order, :status] ->
        [{path, {:invalid_for, :text}}]

      true ->
        fact_field(s, f, path, ctx.sources)
    end
  end

  defp fact_field(source, field, path, sources) when is_map(sources) do
    case Map.fetch(sources, source) do
      :error -> [{path, {:undeclared, :source, source}}]
      {:ok, fields} when is_list(fields) -> fact_in(source, field, path, field in fields)
      {:ok, _unknown} -> []
    end
  end

  defp fact_field(_source, _field, _path, _unknown), do: []

  defp fact_in(_source, _field, _path, true), do: []
  defp fact_in(source, field, path, false), do: [{path, {:undeclared_field, source, field}}]

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
  # A variable or a fact stands for one member — a threshold at a feed's target (§4.3,
  # §7.4) — and is typed once application has replaced it.
  defp category?(%Var{}), do: true
  defp category?(%Fact{}), do: true
  defp category?(v), do: is_number(v) or is_binary(v) or (name?(v) and v != :auto)

  defp term?(%DateTime{}), do: true
  defp term?(v) when is_number(v) or is_binary(v) or is_atom(v), do: true
  defp term?(v) when is_list(v), do: Enum.all?(v, &term?/1)

  defp term?(v) when is_map(v) and not is_struct(v) do
    Enum.all?(v, fn {k, e} -> name?(k) and term?(e) end)
  end

  defp term?(_), do: false

  # -- references -----------------------------------------------------------------------

  # Where an adoption stands: the frame it is written in and the name it is written
  # under, so a scale adopting itself is a cycle and not an unknown name.
  defp source([:frames, frame | rest], _value) when is_atom(frame) do
    case List.last(rest) do
      name when is_atom(name) -> {frame, name}
      _other -> nil
    end
  end

  defp source(_path, {:frame, frame, scale}), do: {frame, scale}

  defp adopted(frame, scale, path, ctx, seen) do
    cond do
      {frame, scale} in seen ->
        [{path, {:cycle, :scale, scale}}]

      not Map.has_key?(ctx.frame_nodes, frame) ->
        [{path, {:undeclared, :frame, frame}}]

      true ->
        scales = nested(Map.fetch!(ctx.frame_nodes, frame), [:scales]) || %{}

        case Map.fetch(scales, scale) do
          :error -> [{path, {:undeclared, :scale, scale}}]
          {:ok, {:frame, f, s}} -> adopted(f, s, path, ctx, MapSet.put(seen, {frame, scale}))
          {:ok, _node} -> []
        end
    end
  end

  defp ref(:slot, {:series, _}, _path, _ctx), do: []

  # Under a theme the validator cannot see, every style series name may be the host's.
  defp ref(:style, name, path, %{open_series: true} = ctx) do
    if Palette.series?(name), do: [], else: ref_in(:style, name, path, ctx)
  end

  defp ref(kind, name, path, ctx), do: ref_in(kind, name, path, ctx)

  defp ref_in(kind, name, path, ctx) do
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

  # Whether a cell, with its span, lies inside the grid the design declares. A design
  # with no `layout` has one cell, which is the default grid (spec/14 §2.8).
  defp inside?(cell, span, layout) do
    layout = layout || %{}
    columns = length(sizes(layout, :columns))
    rows = length(sizes(layout, :rows))

    with [c, r] when is_integer(c) and is_integer(r) <- cell,
         [dc, dr] <- span || [1, 1],
         true <- is_integer(dc) and is_integer(dr) and dc > 0 and dr > 0 do
      c >= 0 and r >= 0 and c + dc <= columns and r + dr <= rows
    else
      _other -> false
    end
  end

  defp sizes(layout, key) do
    case Map.get(layout, key, [1]) do
      weights when is_list(weights) and weights != [] -> weights
      _other -> [1]
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
  defp plural(:frame), do: :frames
  defp plural(:ramp), do: :ramps
  defp plural(:role), do: :roles
end
