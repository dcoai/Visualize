defmodule Visualize.Chart.Style.Parts do
  @moduledoc false
  # The compound parts of a style node (spec/14 §3.1, D-172): the shape a style is stored
  # in, the merge rule that lays one over another, and the projection onto the flat keys an
  # element and a mark's generator read.
  #
  # A style holds `fill`, `stroke`, `font`, `text`, `effect`, `marker` and `curve` as parts,
  # each a map, beside the whole-element keys `opacity`, `blend` and `class`. `normalize/1`
  # turns any accepted spelling into that shape: a shorthand (`fill: :red`, `curve: :step`),
  # and the flat keys every earlier version wrote (`stroke_width: 2`), which this module is
  # the one table of. `merge/2` lays a node over another part by part, key by key, a change
  # of a part's `type` replacing what that type alone means. `project/1` writes the parts
  # back as the flat keys, which is all the frame, the marks and the backends ever read: the
  # grammar changed shape, and the drawing did not.

  # Each flat key of the earlier versions, as the part and the key it now is. `margin_x` and
  # `margin_y` are the two halves of the text's `offset`, and `curve_opts` is the curve's
  # own keys, so those three are handled beside the table.
  @flat %{
    fill: {:fill, :color},
    fill_opacity: {:fill, :opacity},
    stroke: {:stroke, :color},
    stroke_opacity: {:stroke, :opacity},
    stroke_width: {:stroke, :width},
    stroke_dasharray: {:stroke, :dash},
    stroke_linejoin: {:stroke, :join},
    stroke_linecap: {:stroke, :cap},
    stroke_style: {:stroke, :placement},
    font_family: {:font, :family},
    font_size: {:font, :size},
    font_weight: {:font, :weight},
    font_style: {:font, :style},
    line_height: {:font, :line_height},
    text_anchor: {:text, :anchor},
    vertical_align: {:text, :baseline},
    text_angle: {:text, :angle},
    effect: {:effect, :type},
    effect_radius: {:effect, :radius},
    symbol: {:marker, :shape},
    symbol_size: {:marker, :size},
    curve: {:curve, :type}
  }
  @flat_keys Map.keys(@flat) ++ [:margin_x, :margin_y, :curve_opts]

  # The motion parts merge key by key too (spec/14 §3.10, #653).
  @parts [
    :fill,
    :stroke,
    :font,
    :text,
    :effect,
    :marker,
    :curve,
    :transition,
    :animation,
    :enter,
    :exit
  ]
  @paints [:fill, :stroke]
  @paint_types [:none, :solid, :linear, :radial, :hatch, :paint]
  @gradients [:linear, :radial]
  # The paints the frame draws from its `defs`: the gradients and the hatch (#673).
  @drawn [:hatch | @gradients]

  # The keys a part keeps when a later node changes its `type`: what does not depend on the
  # type. A paint's colour or stops and a gradient's geometry do, and go; its opacity and a
  # stroke's line do not, and stay.
  @kept %{
    fill: [:opacity],
    stroke: [:opacity, :width, :dash, :join, :cap, :placement, :non_scaling],
    effect: [],
    curve: []
  }

  # A stroke's placement under the name the flat key used for its default.
  @placements %{single: :center}
  @stroke_styles %{center: :single}

  @doc false
  @spec parts() :: [atom(), ...]
  def parts, do: @parts

  @doc false
  # The flat keys of every earlier version (spec/14 §9, D-172).
  @spec flat_keys() :: [atom(), ...]
  def flat_keys, do: @flat_keys

  @doc false
  # The element keys the fill and the stroke project to (spec/14 §3.1): every key a backend
  # paints an element with, which the canvas parity test holds each canvas to (#675).
  @spec paint_keys() :: [atom(), ...]
  def paint_keys, do: for({key, {part, _}} <- @flat, part in @paints, do: key) |> Enum.sort()

  @doc false
  # Whether a node carries a flat key: none of the current shape's keys share a name with
  # one except `fill`, `stroke`, `curve` and `effect`, which are flat — a shorthand — when
  # their value is what the flat key took: a colour, or a curve's or an effect's name. Any
  # other value that is not a part is left for the validator to name where it stands.
  @spec flat?(term()) :: boolean()
  def flat?(node) when is_map(node) and not is_struct(node) do
    Enum.any?(node, fn {key, value} -> flat_key?(key, value) end)
  end

  def flat?(_node), do: false

  defp flat_key?(key, value) when key in @paints, do: colour?(value)
  defp flat_key?(key, value) when key in [:curve, :effect], do: is_atom(value) or var?(value)
  defp flat_key?(key, _value), do: key in @flat_keys

  @doc false
  # Whether a value is one a flat colour key took, and so a paint's shorthand.
  @spec colour?(term()) :: boolean()
  def colour?(value) when is_binary(value), do: true
  def colour?(value) when is_atom(value), do: value not in [nil, true, false]
  def colour?({:series, _i}), do: true
  def colour?({:ramp, _name, _t}), do: true
  def colour?({:field, _f}), do: true
  def colour?({:paint, _name}), do: true
  # A color generator (spec/14 §3.13): `fill: generate(…)` is a solid paint of it.
  def colour?({:generate, _name, _args}), do: true
  def colour?(value) when is_tuple(value), do: Visualize.Color.Typed.tagged?(value)
  def colour?(value), do: var?(value)

  defp var?(value), do: is_struct(value, Visualize.Chart.Var)

  # -- normalize ------------------------------------------------------------------------

  @doc false
  # The node in the stored shape: flat keys moved into their parts, every shorthand
  # expanded, every gradient's stops written out. A node already in that shape is returned
  # as it is; anything that is not a style node (a reference, a variable) passes through.
  @spec normalize(term()) :: term()
  def normalize(node) when is_map(node) and not is_struct(node) do
    # The stored shape is the common case — every palette entry, every migrated design —
    # and a style is looked up once per distinct choice per frame: answer it unrebuilt.
    if stored?(node), do: node, else: rebuild(node)
  end

  def normalize(node), do: node

  defp stored?(node) do
    Enum.all?(node, fn
      {key, value} when key in @paints -> stored_paint?(value)
      {:effect, %{type: _}} -> true
      {key, value} -> not flat_key?(key, value)
    end)
  end

  defp stored_paint?(%{type: type} = paint) when not is_struct(paint) do
    # spelling: allow — version 2's paint word.
    not Map.has_key?(paint, :kind) and not Map.has_key?(paint, :centre) and
      not (type in @gradients and is_list(Map.get(paint, :color))) and
      stored_stops?(Map.get(paint, :stops))
  end

  defp stored_paint?(paint) when is_map(paint) and not is_struct(paint),
    do: not Map.has_key?(paint, :color) and stored_paint?(Map.put(paint, :type, nil))

  defp stored_paint?(_value), do: false

  defp stored_stops?(stops) when is_list(stops),
    do:
      Enum.all?(
        stops,
        # spelling: allow — version 2's stop word.
        &(not is_map(&1) or not (Map.has_key?(&1, :offset) or Map.has_key?(&1, :colour)))
      )

  defp stored_stops?(_stops), do: true

  defp rebuild(node) do
    {flat, rest} = Map.split_with(node, fn {key, value} -> flat_key?(key, value) end)
    flat = Map.reject(flat, fn {_key, value} -> value == nil end)

    rest
    |> Map.new(fn {key, value} -> {key, part(key, value)} end)
    |> lay_flat(flat)
  end

  defp part(key, value) when key in @paints and is_map(value) and not is_struct(value),
    do: paint(value)

  defp part(key, value) when key in @paints, do: if(colour?(value), do: paint(value), else: value)
  defp part(:effect, value) when is_map(value) and not is_struct(value), do: typed(value)
  defp part(:curve, value) when is_map(value) and not is_struct(value), do: value
  defp part(_key, value), do: value

  defp lay_flat(node, flat) when map_size(flat) == 0, do: node

  defp lay_flat(node, flat) do
    from_flat =
      Enum.reduce(flat, %{}, fn
        {:margin_x, value}, acc ->
          offset(acc, 0, value)

        {:margin_y, value}, acc ->
          offset(acc, 1, value)

        {:curve_opts, opts}, acc when is_map(opts) and not is_struct(opts) ->
          into(acc, :curve, opts)

        {:curve_opts, _opts}, acc ->
          acc

        {key, value}, acc ->
          flat_value(acc, Map.fetch!(@flat, key), value)
      end)
      |> Map.new(fn {key, value} -> {key, part(key, value)} end)

    # A part the node already spells as one takes the flat keys beside it over it.
    node
    |> Map.merge(from_flat, fn
      _key, own, flat when is_map(own) and not is_struct(own) -> Map.merge(own, flat)
      _key, _own, flat -> flat
    end)
    |> keep_unmoved(flat)
  end

  # `curve_opts` held as a variable is a whole node nothing can split; it stays as written.
  defp keep_unmoved(node, flat) do
    case Map.fetch(flat, :curve_opts) do
      {:ok, opts} when not (is_map(opts) and not is_struct(opts)) ->
        Map.put(node, :curve_opts, opts)

      _ ->
        node
    end
  end

  defp flat_value(acc, {:fill, :color}, value),
    do: Map.update(acc, :fill, paint(value), &Map.merge(&1, paint(value)))

  defp flat_value(acc, {:stroke, :color}, value),
    do: Map.update(acc, :stroke, paint(value), &Map.merge(&1, paint(value)))

  defp flat_value(acc, {:stroke, :placement}, value),
    do: put_in_part(acc, :stroke, :placement, Map.get(@placements, value, value))

  defp flat_value(acc, {:effect, :type}, value), do: put_in_part(acc, :effect, :type, value)
  defp flat_value(acc, {part, key}, value), do: put_in_part(acc, part, key, value)

  defp put_in_part(acc, part, key, value) do
    Map.update(acc, part, %{key => value}, &Map.put(&1, key, value))
  end

  defp into(acc, part, map), do: Map.update(acc, part, map, &Map.merge(&1, map))

  defp offset(acc, index, value) do
    Map.update(acc, :text, %{offset: put_at([0, 0], index, value)}, fn text ->
      Map.put(text, :offset, put_at(Map.get(text, :offset, [0, 0]), index, value))
    end)
  end

  defp put_at(list, index, value) when is_list(list), do: List.replace_at(list, index, value)
  defp put_at(_other, index, value), do: List.replace_at([0, 0], index, value)

  @doc false
  # A paint in the stored shape (spec/14 §3.2): a shorthand expanded — `:none`, a colour,
  # a field binding, a variable or `{:paint, name}` — and a map with its type inferred
  # where its colour says it (`:solid` for one colour), the keys of a declared gradient of
  # version 2 renamed (`kind`, `centre`, a stop's `offset` and `colour`), and a gradient's
  # `color` list written out as evenly spaced stops.
  @spec paint(term()) :: term()
  def paint(:none), do: %{type: :none}
  def paint({:paint, name}), do: %{type: :paint, name: name}

  def paint(map) when is_map(map) and not is_struct(map) do
    map
    |> rename(:kind, :type)
    # spelling: allow — version 2's paint word.
    |> rename(:centre, :center)
    |> stops()
    |> typed()
  end

  def paint(nil), do: nil
  def paint(colour), do: %{type: :solid, color: colour}

  defp rename(map, old, new) do
    case Map.pop(map, old) do
      {nil, map} -> map
      {value, map} -> Map.put_new(map, new, value)
    end
  end

  # A gradient's `color` list is its stops, evenly spaced; explicit `stops` win.
  defp stops(%{type: type, color: colours} = map) when type in @gradients and is_list(colours) do
    map = Map.delete(map, :color)
    if Map.has_key?(map, :stops), do: stops(map), else: Map.put(map, :stops, spaced(colours))
  end

  defp stops(%{stops: stops} = map) when is_list(stops),
    do: %{map | stops: Enum.map(stops, &stop/1)}

  defp stops(map), do: map

  defp spaced([colour]), do: [%{at: 0, color: colour}]

  defp spaced(colours) do
    last = length(colours) - 1

    colours
    |> Enum.with_index()
    |> Enum.map(fn {colour, i} -> %{at: tidy(i / last), color: colour} end)
  end

  defp tidy(at) when at == trunc(at), do: trunc(at)
  defp tidy(at), do: Float.round(at, 4)

  defp stop(stop) when is_map(stop) and not is_struct(stop),
    # spelling: allow — version 2's stop word.
    do: stop |> rename(:offset, :at) |> rename(:colour, :color)

  defp stop(stop), do: stop

  # One colour and no type is a solid paint; anything else keeps what it says.
  defp typed(%{type: _} = map), do: map

  defp typed(%{color: colour} = map) when not is_list(colour),
    do: Map.put(map, :type, :solid)

  defp typed(map), do: map

  # -- merge ----------------------------------------------------------------------------

  @doc false
  # `over` laid on `under`, both in the stored shape (spec/14 §3.5, §3.6, D-172): every
  # top-level key the later wins, except a part, which merges key by key — unless the two
  # name different `type`s, when the later's part replaces the earlier's but for the keys no
  # type decides (`@kept`).
  @spec merge(map(), map()) :: map()
  def merge(under, over) do
    Map.merge(under, over, fn
      key, a, b when key in @parts -> merge_part(key, a, b)
      _key, _a, b -> b
    end)
  end

  defp merge_part(key, %{type: t1} = a, %{type: t2} = b)
       when not is_struct(a) and not is_struct(b) and t1 != t2 do
    a |> Map.take(Map.get(@kept, key, [])) |> Map.merge(b)
  end

  defp merge_part(_key, a, b)
       when is_map(a) and not is_struct(a) and is_map(b) and not is_struct(b),
       do: Map.merge(a, b)

  defp merge_part(_key, _a, b), do: b

  @doc false
  # What of a lower part of schema kind `kind` a higher one keeps under it: all of it,
  # unless the two name different types, when only what no type decides (`merge/2`'s rule,
  # for a walk that merges the rest key by key itself — the fragment cascade).
  @spec under(atom(), map(), map()) :: map()
  def under(kind, %{type: t1} = lower, %{type: t2}) when t1 != t2 do
    part = if kind == :paint, do: :fill, else: kind
    Map.take(lower, Map.get(@kept, part, []))
  end

  def under(_kind, lower, _higher), do: lower

  # -- project --------------------------------------------------------------------------

  @doc false
  # The node's parts written as the flat keys the frame, the marks and the backends read
  # (spec/14 §3.4, D-172). A gradient is drawn by the frame from its `defs`: it projects to
  # `{:paint, name}` under the name `paint_name/1` gives it. Keys already flat pass through,
  # so projecting twice is projecting once.
  @spec project(map()) :: map()
  def project(node) when is_map(node) do
    Enum.reduce(node, %{}, fn {key, value}, acc -> project(acc, key, value) end)
  end

  defp project(acc, key, %{} = paint, prefix) when not is_struct(paint) do
    Enum.reduce(paint, acc, fn
      {:type, :none}, acc ->
        Map.put(acc, key, :none)

      {:type, _type}, acc ->
        acc

      {:color, colour}, acc ->
        if solid?(paint), do: Map.put(acc, key, colour), else: acc

      {:name, name}, acc ->
        if paint[:type] == :paint, do: Map.put(acc, key, {:paint, name}), else: acc

      {:opacity, opacity}, acc ->
        Map.put(acc, :"#{prefix}opacity", opacity)

      # A hatch's width is its lines', drawn from the frame's defs (#673).
      {:width, width}, acc ->
        if paint[:type] == :hatch, do: acc, else: Map.put(acc, :stroke_width, width)

      {:dash, dash}, acc ->
        Map.put(acc, :stroke_dasharray, dash)

      {:join, join}, acc ->
        Map.put(acc, :stroke_linejoin, join)

      {:cap, cap}, acc ->
        Map.put(acc, :stroke_linecap, cap)

      {:placement, p}, acc ->
        Map.put(acc, :stroke_style, Map.get(@stroke_styles, p, p))

      # A stroke kept its width on screen (spec/14 §3.9, #651); `false` is the default.
      {:non_scaling, true}, acc ->
        Map.put(acc, :vector_effect, :non_scaling_stroke)

      {_geometry, _value}, acc ->
        acc
    end)
    |> gradient(key, paint)
  end

  defp project(acc, key, paint) when key in @paints and is_map(paint) and not is_struct(paint),
    do: project(acc, key, paint, "#{key}_")

  defp project(acc, :font, font) when is_map(font) and not is_struct(font) do
    Enum.reduce(font, acc, fn
      {:family, v}, acc -> Map.put(acc, :font_family, v)
      {:size, v}, acc -> Map.put(acc, :font_size, v)
      {:weight, v}, acc -> Map.put(acc, :font_weight, v)
      {:style, v}, acc -> Map.put(acc, :font_style, v)
      {:line_height, v}, acc -> Map.put(acc, :line_height, v)
      {_other, _v}, acc -> acc
    end)
  end

  defp project(acc, :text, text) when is_map(text) and not is_struct(text) do
    Enum.reduce(text, acc, fn
      {:anchor, v}, acc -> Map.put(acc, :text_anchor, v)
      {:baseline, v}, acc -> Map.put(acc, :vertical_align, v)
      {:angle, v}, acc -> Map.put(acc, :text_angle, v)
      {:offset, [x, y]}, acc -> acc |> Map.put(:margin_x, x) |> Map.put(:margin_y, y)
      {_other, _v}, acc -> acc
    end)
  end

  defp project(acc, :effect, effect) when is_map(effect) and not is_struct(effect) do
    Enum.reduce(effect, acc, fn
      {:type, v}, acc -> Map.put(acc, :effect, v)
      {:radius, v}, acc -> Map.put(acc, :effect_radius, v)
      {:offset, v}, acc -> Map.put(acc, :effect_offset, v)
      {:color, v}, acc -> Map.put(acc, :effect_color, v)
      {_other, _v}, acc -> acc
    end)
  end

  defp project(acc, :marker, marker) when is_map(marker) and not is_struct(marker) do
    Enum.reduce(marker, acc, fn
      {:shape, v}, acc -> Map.put(acc, :symbol, v)
      {:size, v}, acc -> Map.put(acc, :symbol_size, v)
      {_other, _v}, acc -> acc
    end)
  end

  defp project(acc, :curve, curve) when is_map(curve) and not is_struct(curve) do
    {type, opts} = Map.pop(curve, :type)
    acc = if type == nil, do: acc, else: Map.put(acc, :curve, type)
    if map_size(opts) == 0, do: acc, else: Map.put(acc, :curve_opts, opts)
  end

  defp project(acc, key, value), do: Map.put(acc, key, value)

  defp solid?(paint), do: Map.get(paint, :type, :solid) == :solid

  defp gradient(acc, key, %{type: type} = paint) when type in @drawn,
    do: Map.put(acc, key, {:paint, paint_name(paint)})

  defp gradient(acc, _key, _paint), do: acc

  # -- the parts a mark kind draws ------------------------------------------------------

  # The projected keys of each part a kind may not draw (spec/14 §5.6, D-172).
  @projected %{
    fill: [:fill, :fill_opacity],
    marker: [:symbol, :symbol_size],
    font: [:font_family, :font_size, :font_weight, :font_style, :line_height],
    text: [:text_anchor, :vertical_align, :margin_x, :margin_y, :text_angle]
  }
  @stroked [:line, :rule]

  @doc false
  # A projected style node without the keys of the parts a mark of `type` does not draw:
  # a line and a rule draw no fill, only a symbol draws a marker, only a text and a label
  # a font and a text placement. A part a kind does not draw is ignored, never an error.
  @spec drawn(map(), atom()) :: map()
  def drawn(node, type),
    do: Map.drop(node, Enum.flat_map(undrawn(type), &Map.fetch!(@projected, &1)))

  @doc false
  # The parts a mark of `type` does not draw (spec/14 §5.6).
  @spec undrawn(atom()) :: [atom()]
  def undrawn(type) when type in @stroked, do: [:fill, :marker, :font, :text]
  def undrawn(:symbol), do: [:font, :text]
  def undrawn(:text), do: [:marker]
  def undrawn(_closed), do: [:marker, :font, :text]

  # -- gradients written inline ---------------------------------------------------------

  @doc false
  # The name an inline gradient is drawn under in its frame's `defs`: a hash of what it
  # draws, a string so that a design can never make an atom of it, and the same for the
  # same gradient wherever it is written.
  @spec paint_name(map()) :: String.t()
  def paint_name(paint) do
    "p" <> (paint |> drawn() |> :erlang.phash2() |> Integer.to_string(36) |> String.downcase())
  end

  # What a gradient draws: its opacity is the element's, not the gradient's.
  defp drawn(paint), do: Map.delete(paint, :opacity)

  @doc false
  # Every gradient the style nodes write inline, by the name `paint_name/1` gives it, as a
  # declared paint is held under `defs` (spec/14 §2.7, §3.2).
  @spec inline_paints([term()]) :: %{String.t() => map()}
  def inline_paints(nodes) do
    for node <- nodes,
        node <- [normalize(node)],
        is_map(node) and not is_struct(node),
        key <- @paints,
        %{type: type} = paint <- [Map.get(node, key)],
        type in @drawn,
        into: %{},
        do: {paint_name(paint), drawn(paint)}
  end

  @doc false
  @spec paint_types() :: [atom(), ...]
  def paint_types, do: @paint_types
end
