defmodule Visualize.Chart.Validator.Types do
  @moduledoc false
  # The validator's value types (spec/14 §10, spec/14 §1): one `check/4` clause per schema
  # type, the parts of a text, the facts of a feed's schema, a generator's arguments, and the
  # references — scales, styles, paints, sources, variables, fields, slots, adopted scales —
  # resolved against the context a walk runs in.

  alias Visualize.Chart.{Fact, Schema, Text, Var}
  alias Visualize.Chart.Validator
  alias Visualize.Chart.Validator.{Colors, Context, Generators, Palette, Units}
  alias Visualize.Theme

  @frame_anchors [:title, :subtitle, :caption]
  @typed_colors [
    :color,
    :intensity,
    :alpha,
    :lighten,
    :darken,
    :saturate,
    :shade,
    :blend,
    :contrast
  ]
  # The plot's four corners and its center (spec/14 §6.3, #489).
  @frame_points [:top_left, :top_right, :bottom_left, :bottom_right, :center]
  @not_names [nil, true, false]

  @doc false
  # A text anchor (spec/14 §6.3): the codec reads a document's anchor in these (§9.4).
  @spec anchors() :: [atom(), ...]
  def anchors, do: @frame_anchors

  @doc false
  # The plot's points a `$frame` anchor names (spec/14 §6.3, #489).
  @spec frame_points() :: [atom(), ...]
  def frame_points, do: @frame_points

  @doc false
  # The faults of `v` read as the schema type `type` at `path`.
  @spec check(Visualize.Chart.Schema.type(), term(), list(), map()) :: [{list(), term()}]
  def check(_type, %Var{name: name}, path, ctx), do: ref(:var, name, path, ctx)
  def check(_type, %Fact{} = fact, path, ctx), do: fact(fact, path, ctx, false)

  def check({:node, kind}, v, path, ctx) when is_map(v) and not is_struct(v) do
    Validator.node(kind, v, path, ctx)
  end

  def check({:list, t}, v, path, ctx) when is_list(v) do
    v |> Enum.with_index() |> Enum.flat_map(fn {e, i} -> check(t, e, path ++ [i], ctx) end)
  end

  def check({:map, t}, v, path, ctx) when is_map(v) and not is_struct(v) do
    Enum.flat_map(v, fn {k, e} ->
      if name?(k), do: check(t, e, path ++ [k], ctx), else: [{path ++ [k], {:type, :name}}]
    end)
  end

  def check({:one_of, types} = t, v, path, ctx) do
    case Schema.select(types, v) do
      nil -> [{path, {:type, t}}]
      type -> check(type, v, path, ctx)
    end
  end

  def check({:enum, allowed}, v, path, _ctx) do
    if v in allowed, do: [], else: [{path, {:enum, allowed}}]
  end

  def check({:ref, kind}, v, path, ctx) when is_atom(v) or is_binary(v) do
    if name?(v), do: ref(kind, v, path, ctx), else: [{path, {:type, {:ref, kind}}}]
  end

  # An id is accepted by its tag alone (spec/14 §19.2, D-100): whether the store holds it is
  # resolution's question, and a missing one is a mask there, not an error here. A tag of
  # the wrong kind is refused now, before anything tries to resolve it.
  def check({:ref, kind}, {kind, n}, _path, _ctx) when is_integer(n) and n > 0, do: []

  def check({:ref, kind}, {other, n}, path, _ctx) when is_atom(other) and is_integer(n),
    do: [{path, {:ref_kind, kind, other}}]

  def check(:field, v, path, ctx) when is_atom(v) or is_binary(v) do
    if name?(v), do: ref(:field, v, path, ctx), else: [{path, {:type, :field}}]
  end

  def check(:field_ref, {:field, f}, path, ctx) when is_atom(f) or is_binary(f) do
    if name?(f), do: ref(:field, f, path, ctx), else: [{path, {:type, :field_ref}}]
  end

  # A generator as a stack entry (spec/14 §3.6, §3.13).
  def check(:generator, v, path, ctx), do: generator(v, path, ctx, :generator)

  def check(:channel, v, _path, _ctx) when is_number(v), do: []

  def check(:channel, v, path, ctx) when is_atom(v) or is_binary(v),
    do: check(:field, v, path, ctx)

  def check(:channel, {:field, _} = v, path, ctx), do: check(:field_ref, v, path, ctx)

  # A channel naming its scale's own end (spec/14 §5.2, #420); any other `:scale` tuple is
  # a typed fault rather than a silent pass.
  def check(:channel, {:scale, which}, _path, _ctx) when which in [:min, :max], do: []
  def check(:channel, {:scale, _other}, path, _ctx), do: [{path, {:type, :channel}}]

  # A scale adopted from another frame (spec/14 §4.3, #384): the frame is declared, it
  # declares the scale, and the chain of adoptions ends at a node rather than returning.
  def check(:adopted, {:frame, frame, scale} = value, path, ctx) do
    cond do
      not (name?(frame) and name?(scale)) -> [{path, {:type, :adopted}}]
      ctx.frame_nodes == %{} -> []
      true -> adopted(frame, scale, path, ctx, MapSet.new([source(path, value)]))
    end
  end

  def check(:adopted, _value, path, _ctx), do: [{path, {:type, :adopted}}]

  # A design's budget (spec/14 §2.10, D-226): rows, or rows per pixel of plot width.
  def check(:budget, n, _path, _ctx) when is_integer(n) and n > 0, do: []
  def check(:budget, {:per_px, k}, _path, _ctx) when is_number(k) and k > 0, do: []
  def check(:budget, _value, path, _ctx), do: [{path, {:type, :budget}}]

  # A stack's fixed order (spec/14 §5.4.1, #492): series keys, which need not be the
  # step's fields — a listed key the stack lacks is ignored, never a fault.
  def check(:key_order, {:keys, keys}, path, _ctx) when is_list(keys) do
    if Enum.all?(keys, &name?/1), do: [], else: [{path, {:type, :key_order}}]
  end

  def check(:key_order, _value, path, _ctx), do: [{path, {:type, :key_order}}]

  def check(:extent, :auto, _path, _ctx), do: []

  def check(:extent, v, path, _ctx) when is_list(v) do
    if extent?(v), do: [], else: [{path, {:type, :extent}}]
  end

  # A scale's range as a list (spec/14 §1.4, §4.3, D-185): each entry a position, or a
  # color checked as a `:color` at its own index.
  def check(:range, :auto, _path, _ctx), do: []

  # `:auto` is a domain's bound, never a range's entry: a scale has nothing to map to there.
  def check(:range, v, path, ctx) when is_list(v) do
    if :auto in v do
      [{path, {:type, :range}}]
    else
      v
      |> Enum.with_index()
      |> Enum.flat_map(fn {entry, i} ->
        if position?(entry), do: [], else: check(:color, entry, path ++ [i], ctx)
      end)
    end
  end

  def check(:text, v, path, ctx) when is_list(v) do
    v |> Enum.with_index() |> Enum.flat_map(fn {part, i} -> text_part(part, path ++ [i], ctx) end)
  end

  # The string form (§7.1): read into parts and checked as parts, at the key's path.
  def check(:text, v, path, ctx) when is_binary(v) do
    case Text.parse(v) do
      {:ok, parts} -> Enum.flat_map(parts, &text_part(&1, path, ctx))
      {:error, reason} -> [{path, {:template, reason}}]
    end
  end

  def check(:anchor, v, _path, _ctx) when v in @frame_anchors, do: []

  def check(:anchor, {:axis, s}, path, ctx) when is_atom(s) or is_binary(s) do
    if name?(s), do: ref(:scale, s, path, ctx), else: [{path, {:type, :anchor}}]
  end

  def check(:anchor, {:frame, c}, _path, _ctx) when c in @frame_points, do: []

  def check(:anchor, {:data, [x, y]}, path, _ctx) do
    if term?(x) and term?(y), do: [], else: [{path, {:type, :anchor}}]
  end

  def check(:color, v, _path, _ctx) when is_binary(v) or v in [:none, :contrast], do: []
  # A paint names a gradient of `defs` (spec/14 §2.7, §3.2).
  def check(:color, {:paint, name}, path, ctx) when is_atom(name) or is_binary(name),
    do: ref(:paint, name, path, ctx)

  # A ramp position is a meaning the theme renders (spec/14 §3.2, D-135).
  def check(:color, {:ramp, name, t}, path, _ctx) do
    if name in Theme.ramp_names() and is_number(t) and t >= 0 and t <= 1,
      do: [],
      else: [{path, {:type, :color}}]
  end

  # A typed color (spec/14 §3.2, spec/08 §1.9, #664): its shape, its literal operands and
  # every name it reads from the theme's color table.
  def check(:color, v, path, ctx) when is_tuple(v) and elem(v, 0) in @typed_colors,
    do: Colors.check(v, path, ctx.colors)

  def check(:color, v, path, ctx), do: slot_or(:color, v, path, ctx)

  def check(:ramp, {:ramp, name}, path, _ctx) do
    if name in Theme.ramp_names(), do: [], else: [{path, {:type, :ramp}}]
  end

  # A theme's counterpart in a color scheme (spec/08 §7.3, #668): a name, or `nil` for none.
  def check(:counterpart, v, _path, _ctx)
      when v == nil or is_binary(v) or (is_atom(v) and not is_boolean(v)),
      do: []

  def check(:counterpart, _v, path, _ctx), do: [{path, {:type, :counterpart}}]

  # A theme's color (spec/08 §7.1, #667): a color, or the steps it pins of a name.
  def check(:theme_color, map, path, _ctx) when is_map(map) and not is_struct(map),
    do: Colors.steps(map, path)

  def check(:theme_color, v, path, ctx), do: check(:color, v, path, ctx)

  # A map of colors (spec/14 §4.3, D-143): each category's color as a style takes one,
  # checked at the category's own path.
  def check(:color_map, map, path, ctx) when is_map(map) and not is_struct(map) do
    Enum.flat_map(map, fn {category, color} ->
      check(:color, color, path ++ [category], ctx)
    end)
  end

  def check(:size, v, path, ctx), do: Units.check(:size, v, path) || slot_or(:size, v, path, ctx)
  def check(:length, v, path, _ctx), do: Units.check(:length, v, path)
  def check(:font, v, _path, _ctx) when is_binary(v), do: []
  def check(:font, v, path, ctx), do: slot_or(:font, v, path, ctx)
  def check(:slot, v, path, ctx), do: slot_or(:slot, v, path, ctx)

  def check(:term, v, path, _ctx) do
    if term?(v), do: [], else: [{path, {:type, :term}}]
  end

  def check(:name, v, _path, _ctx) when is_binary(v) and v != "", do: []
  def check(:name, v, _path, _ctx) when is_atom(v) and v not in @not_names, do: []
  def check(:integer, v, _path, _ctx) when is_integer(v), do: []
  def check(:number, v, _path, _ctx) when is_number(v), do: []
  def check(:boolean, v, _path, _ctx) when is_boolean(v), do: []
  def check(:string, v, _path, _ctx) when is_binary(v), do: []
  def check(type, _v, path, _ctx), do: [{path, {:type, type}}]

  # A declared paint's own faults beside its keys' types: no type, a type that is neither a
  # gradient nor a hatch, a gradient with no stops (spec/14 §2.7, #673). A variable stands for what application gives.
  @doc false
  @spec gradient(map(), list()) :: [{list(), term()}]
  def gradient(paint, path) do
    type =
      case Map.fetch(paint, :type) do
        :error ->
          [{path ++ [:type], :required}]

        {:ok, %Var{}} ->
          []

        {:ok, t} when t in [:linear, :radial, :hatch] ->
          []

        # A paint's other types are named here; anything else is the paint's own enum fault.
        {:ok, t} when t in [:none, :solid, :paint] ->
          [{path ++ [:type], {:enum, [:linear, :radial, :hatch]}}]

        {:ok, _other} ->
          []
      end

    stops =
      if Map.has_key?(paint, :stops) or Map.get(paint, :type) == :hatch,
        do: [],
        else: [{path ++ [:stops], :required}]

    type ++ stops
  end

  # A generator call's faults: its shape, its name against the registry and each argument
  # — a term, or a field binding checked as any is. Where no generator goes the call is the
  # position's own type fault.
  @doc false
  @spec generator(term(), list(), map(), atom()) :: [{list(), term()}]
  def generator(_call, path, %{generators: :refused}, type), do: [{path, {:type, type}}]

  def generator(call, path, ctx, _type) do
    Generators.faults(call, path, ctx.generators, fn
      {:field, _} = ref, at -> check(:field_ref, ref, at, ctx)
      arg, at -> if term?(arg), do: [], else: [{at, {:type, :generator}}]
    end)
  end

  defp text_part(part, _path, _ctx) when is_binary(part), do: []
  defp text_part(%Var{name: name}, path, ctx), do: ref(:var, name, path, ctx)
  defp text_part(%Fact{} = fact, path, ctx), do: fact(fact, path, ctx, true)

  defp text_part({:field, _} = part, path, %{datum?: true} = ctx) do
    check(:field_ref, part, path, ctx)
  end

  defp text_part({:field, _}, path, _ctx), do: [{path, {:invalid_for, :label}}]
  defp text_part(_, path, _ctx), do: [{path, {:type, :text}}]

  # A fact of a feed's schema (spec/14 §7.4): a declared slot, one of its fields and a fact
  # key (D-225); in a text, one written as words, never `order`'s list or the maps of
  # `status`, `names` and `colors`. Whether the schema gives it is application's question.
  defp fact(%Fact{source: s, field: f, key: k}, path, ctx, text?) do
    cond do
      not (name?(s) and name?(f) and name?(k)) ->
        [{path, {:type, :fact}}]

      k not in Fact.keys() ->
        [{path, {:enum, Fact.keys()}}]

      text? and k in [:order, :status, :names, :colors] ->
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
  defp slot?(v), do: is_atom(v) and v not in @not_names

  @doc false
  # A name: a non-empty string (D-195), or an atom other than `nil`, `true` and `false`.
  @spec name?(term()) :: boolean()
  defdelegate name?(v), to: Visualize.Chart.Names

  # `:auto` is a bound, so only a two-element list may carry it (spec/14 §1.4).
  defp extent?(list) do
    Enum.all?(list, &(category?(&1) or &1 == :auto)) and
      (:auto not in list or length(list) == 2)
  end

  # A range's position: what a position scale maps to, or a stand-in typed at application.
  defp position?(v),
    do: is_number(v) or is_struct(v, DateTime) or is_struct(v, Var) or is_struct(v, Fact)

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
  defp source([:frames, frame | rest], _value) when is_binary(frame) or is_atom(frame) do
    case List.last(rest) do
      name when is_binary(name) or is_atom(name) -> {frame, name}
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
        scales = Context.nested(Map.fetch!(ctx.frame_nodes, frame), [:scales]) || %{}

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

  defp undeclared(kind, name, path, true), do: [{path, {:undeclared, kind, name}}]
  defp undeclared(_kind, _name, _path, false), do: []

  @doc false
  # The context key a reference of `kind` is resolved in.
  @spec plural(atom()) :: atom()
  def plural(:scale), do: :scales
  def plural(:style), do: :styles
  def plural(:paint), do: :paints
  def plural(:source), do: :sources
  def plural(:var), do: :vars
  def plural(:field), do: :fields
  def plural(:slot), do: :slots
  def plural(:frame), do: :frames
  def plural(:ramp), do: :ramps
  def plural(:color), do: :colors
end
