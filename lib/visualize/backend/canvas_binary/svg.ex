defmodule Visualize.Backend.CanvasBinary.SVG do
  @moduledoc """
  Encodes `Visualize.SVG.Element` trees into the canvas binary format: element geometry,
  presentation attributes, `transform` strings, `d` path strings and `points` lists, and the
  `clip-path`, `mask` and `filter` references and `mix-blend-mode` an element draws with
  (spec/09 §4.7).
  """

  import Bitwise

  alias Visualize.Backend.{Canvas, CanvasBinary}
  alias Visualize.Backend.CanvasBinary.{Opcodes, PathEncoder}
  alias Visualize.Backend.CanvasBinary.SVG.Defs
  alias Visualize.IR.Transform
  alias Visualize.SVG.Element
  require Opcodes

  # The tags that draw, and so read the stroke's attributes (spec/09 §4.7).
  @drawn [:rect, :circle, :ellipse, :path, :line, :polyline, :polygon]

  # The presentation attributes a `:g` (or the root `:svg`) passes on to what it holds, as
  # SVG inherits them: a descendant's own value wins (spec/09 §4.7, #734, D-192). `opacity`
  # is not among them: it is the group's, its children's global alpha. Nor are a clip, a
  # mask, a filter, a blend or a vector effect, which SVG does not inherit.
  @inherited [
    :fill,
    :fill_opacity,
    :stroke,
    :stroke_opacity,
    :stroke_width,
    :stroke_linecap,
    :stroke_linejoin,
    :stroke_dasharray
  ]

  @doc false
  # A tree as a whole stream (spec/09 §4.2, §4.7): the least version its records need first
  # — 4 when an element is clipped or blended (D-211), 3 when one writes a stroke's dash, cap
  # or join (#693, D-180), 2 when one is filtered — and every other tree's records as they
  # were.
  @spec encode_tree(Element.t(), :f32 | :f64) :: binary()
  def encode_tree(element, precision) do
    ctx = %{precision: precision, ids: Defs.ids(element)}
    records = encode(element, ctx, %{})

    case version(element, ctx) do
      nil -> records
      version -> <<Opcodes.version()::8, version::8>> <> records
    end
  end

  defp version(element, ctx) do
    uses = uses(element, ctx)

    cond do
      :clip in uses or :blend in uses -> 4
      :paint_state in uses -> 3
      :effect in uses -> 2
      true -> nil
    end
  end

  # The records of version 2 and above the drawn elements of a tree write: the groups and
  # the drawing elements, never what a definition holds.
  defp uses(%Element{tag: tag, attrs: attrs, children: children}, ctx)
       when tag in [:g, :svg | @drawn] do
    own =
      for {use, used?} <- [
            clip: tag != :svg and Defs.clips(references(attrs), ctx.ids) != [],
            blend: blend(attrs) != nil,
            paint_state: paint_state(attrs) != <<>>,
            effect: Defs.effect(attr(attrs, :filter), ctx.ids) != <<>>
          ],
          used?,
          do: use

    Enum.reduce(children, MapSet.new(own), &MapSet.union(uses(&1, ctx), &2))
  end

  defp uses(_element, _ctx), do: MapSet.new()

  defp references(attrs), do: %{clip_path: attr(attrs, :clip_path), mask: attr(attrs, :mask)}

  # SVG Element Encoding

  # A clipped or masked group or drawing element (spec/09 §4.7, §4.3.18, D-211): in its own
  # user space, as SVG resolves a clip — `save`, its transform, each clip's shape and its
  # `clip` record, then its own records without the transform, `restore`. A reference the
  # records cannot express draws nothing of itself (spec/09 §4.7).
  defp encode(%Element{tag: tag, attrs: attrs} = element, ctx, inherited)
       when tag in [:g | @drawn] do
    case Defs.clips(references(attrs), ctx.ids) do
      [] ->
        draw(element, ctx, inherited)

      clips ->
        bare = %{element | attrs: Map.drop(attrs, [:transform, :clip_path, :"clip-path", :mask])}

        IO.iodata_to_binary([
          <<Opcodes.save()::8>>,
          encode_svg_transform(Map.get(attrs, :transform)),
          for {keep, shape} <- clips do
            [geometry(shape, ctx.precision), <<Opcodes.clip()::8, keep(keep)::8>>]
          end,
          draw(bare, ctx, inherited),
          <<Opcodes.restore()::8>>
        ])
    end
  end

  defp encode(element, ctx, inherited), do: draw(element, ctx, inherited)

  defp keep(:inside), do: 0x01
  defp keep(:outside), do: 0x02

  # `inherited` is what the groups above pass on: their presentation attributes under the
  # names of `@inherited`, the nearest group's value for each, and `:group_opacity`, the
  # product of their opacities.
  defp draw(%Element{tag: tag} = element, ctx, inherited) when tag in [:svg, :g] do
    %{attrs: attrs, children: children} = element
    own = presentation(attrs)
    effective = Map.merge(inherited, own)
    opacity = group_opacity(attrs, inherited)
    passed = if opacity, do: Map.put(effective, :group_opacity, opacity), else: effective

    # A root draws nothing of its own transform: its `viewBox` places it.
    transform =
      case {tag, Map.get(attrs, :transform)} do
        {:g, transform} when transform != nil -> encode_svg_transform(transform)
        _ -> <<>>
      end

    # The group's state, which its children draw in: what it sets, combined with what it
    # inherits (a fill-opacity over an inherited fill), its effect, its cap, join and dash,
    # and its blend.
    state =
      IO.iodata_to_binary([
        transform,
        group_style(own, effective, opacity),
        Defs.effect(attr(attrs, :filter), ctx.ids),
        paint_state(attrs),
        blend_record(attrs)
      ])

    child_data = IO.iodata_to_binary(Enum.map(children, &encode(&1, ctx, passed)))

    case state do
      <<>> when not is_map_key(attrs, :transform) or tag == :svg ->
        child_data

      state ->
        <<Opcodes.save()::8, state::binary, child_data::binary, Opcodes.restore()::8>>
    end
  end

  defp draw(%Element{tag: :rect, attrs: attrs}, ctx, inherited),
    do: leaf(attrs, ctx, inherited, rect_record(attrs), &encode_svg_draw_commands/1)

  defp draw(%Element{tag: :circle, attrs: attrs}, ctx, inherited),
    do: leaf(attrs, ctx, inherited, circle_record(attrs), &encode_svg_draw_commands/1)

  # A path, an ellipse, a polygon and a polyline are drawn as the commands they are (spec/09
  # §4.4, §4.7, #825): one that makes no commands draws nothing.
  defp draw(%Element{tag: tag, attrs: attrs} = element, ctx, inherited)
       when tag in [:path, :ellipse, :polygon, :polyline] do
    case commands(element) do
      [] ->
        <<>>

      commands ->
        geometry = PathEncoder.encode_cubic_path(commands, ctx.precision)
        leaf(attrs, ctx, inherited, geometry, &encode_svg_draw_commands/1)
    end
  end

  defp draw(%Element{tag: :line, attrs: attrs}, ctx, inherited) do
    x1 = Map.get(attrs, :x1, 0) |> PathEncoder.to_float()
    y1 = Map.get(attrs, :y1, 0) |> PathEncoder.to_float()
    x2 = Map.get(attrs, :x2, 0) |> PathEncoder.to_float()
    y2 = Map.get(attrs, :y2, 0) |> PathEncoder.to_float()

    # A move and a line, stroked where its effective stroke is present and never filled: a
    # line has no area, and SVG's stroke is `none` until one is set (spec/09 §4.7, #757).
    geometry = PathEncoder.encode_cubic_path([{:M, x1, y1}, {:L, x2, y2}], ctx.precision)

    leaf(attrs, ctx, inherited, geometry, fn effective ->
      if has_color?(effective[:stroke]), do: [<<Opcodes.stroke()::8>>], else: []
    end)
  end

  # Text is not representable in the binary format, and any other tag draws nothing.
  defp draw(_element, _ctx, _inherited), do: <<>>

  defp rect_record(attrs) do
    x = Map.get(attrs, :x, 0) |> PathEncoder.to_float()
    y = Map.get(attrs, :y, 0) |> PathEncoder.to_float()
    width = Map.get(attrs, :width, 0) |> PathEncoder.to_float()
    height = Map.get(attrs, :height, 0) |> PathEncoder.to_float()

    <<Opcodes.rects()::8, 1::little-32, x::little-float-64, y::little-float-64,
      width::little-float-64, height::little-float-64>>
  end

  defp circle_record(attrs) do
    cx = Map.get(attrs, :cx, 0) |> PathEncoder.to_float()
    cy = Map.get(attrs, :cy, 0) |> PathEncoder.to_float()
    r = Map.get(attrs, :r, 0) |> PathEncoder.to_float()

    <<Opcodes.circles()::8, 1::little-32, cx::little-float-64, cy::little-float-64,
      r::little-float-64>>
  end

  # A clip's shape, its geometry record alone (spec/09 §4.3.18): what it would be drawn with.
  defp geometry(%Element{tag: :rect, attrs: attrs}, _precision), do: rect_record(attrs)
  defp geometry(%Element{tag: :circle, attrs: attrs}, _precision), do: circle_record(attrs)

  defp geometry(%Element{} = shape, precision),
    do: PathEncoder.encode_cubic_path(commands(shape), precision)

  # The commands of a shape drawn as a path: a path's `d`; an ellipse's four cubic
  # quarter-arcs, as the IR encoder writes one (spec/09 §4.4); a polyline's move and lines,
  # and a polygon's, closed. An ellipse without a positive radius, or a list of points
  # without one whole pair, makes none, as SVG renders none.
  defp commands(%Element{tag: :path, attrs: attrs}), do: parse_svg_path(Map.get(attrs, :d, ""))

  defp commands(%Element{tag: :ellipse, attrs: attrs}) do
    [cx, cy, rx, ry] =
      for key <- [:cx, :cy, :rx, :ry], do: attrs |> Map.get(key, 0) |> PathEncoder.to_float()

    if rx > 0 and ry > 0, do: CanvasBinary.ellipse_path(cx, cy, rx, ry).commands, else: []
  end

  defp commands(%Element{tag: tag, attrs: attrs}) when tag in [:polyline, :polygon] do
    case points(Map.get(attrs, :points)) do
      [] ->
        []

      [{x, y} | rest] when tag == :polyline ->
        [{:M, x, y} | for({px, py} <- rest, do: {:L, px, py})]

      [{x, y} | rest] ->
        [{:M, x, y} | for({px, py} <- rest, do: {:L, px, py})] ++ [:Z]
    end
  end

  # A drawing element's records: its transform, its style, its effect, its paint state and
  # its blend, its geometry and its draws (#693, D-211). The style carries what its own
  # attributes set, each combined with what the groups pass on; the draws are its effective
  # attributes', its own over the groups' (#734).
  #
  # A leaf that writes a transform, a style, an effect, a paint state or a blend writes all
  # its records inside `save` … `restore`, its transform first, wherever it stands, so none
  # outlives it on a later sibling, which draws in the state of the groups above it
  # (spec/09 §4.7, #744, #746, D-193, as D-179 for the IR encoders). A leaf that writes none
  # pays nothing.
  defp leaf(attrs, ctx, inherited, geometry, draws) do
    effective = Map.merge(inherited, presentation(attrs))
    draws = draws.(effective)

    setup =
      IO.iodata_to_binary([
        encode_svg_transform(Map.get(attrs, :transform)),
        leaf_style(attrs, effective, draws),
        Defs.effect(attr(attrs, :filter), ctx.ids),
        paint_state(attrs),
        blend_record(attrs)
      ])

    case setup do
      <<>> ->
        IO.iodata_to_binary([geometry | draws])

      setup ->
        IO.iodata_to_binary([
          <<Opcodes.save()::8>>,
          setup,
          geometry,
          draws,
          <<Opcodes.restore()::8>>
        ])
    end
  end

  # The `blend` record (spec/09 §4.3.19) of an element's `mix-blend-mode`, read as an
  # attribute or from its inline `style`, or `<<>>`: `normal` and a word outside the
  # fifteen write nothing, as on the IR encoder.
  defp blend_record(attrs) do
    case blend(attrs) do
      nil -> <<>>
      mode -> <<Opcodes.blend()::8, mode::8>>
    end
  end

  defp blend(attrs) do
    word = attr(attrs, :mix_blend_mode) || inline_style(Map.get(attrs, :style), "mix-blend-mode")
    CanvasBinary.blend_mode(word)
  end

  # A declaration's value in an inline `style`: the last one of the property, as CSS reads
  # them, without `!important`.
  defp inline_style(style, property) when is_binary(style) do
    style
    |> String.split(";")
    |> Enum.flat_map(fn declaration ->
      case String.split(declaration, ":", parts: 2) do
        [name, value] ->
          if String.trim(name) |> String.downcase() == property,
            do: [value |> String.replace("!important", "") |> String.trim()],
            else: []

        _other ->
          []
      end
    end)
    |> List.last()
  end

  defp inline_style(_style, _property), do: nil

  @caps %{"butt" => 0, "round" => 1, "square" => 2}
  @joins %{"miter" => 0, "round" => 1, "bevel" => 2}

  # Version 3's `paint_state` record with the cap, the join and the dash an element's
  # attributes set (spec/09 §4.3.17): the opacities are folded into the colors here, so
  # its alpha bits are never set; `<<>>` when it sets none of the three.
  defp paint_state(attrs) do
    fields = [
      {0x04, word(attr(attrs, :stroke_linecap), @caps)},
      {0x08, word(attr(attrs, :stroke_linejoin), @joins)},
      {0x10, dash(Canvas.dash(attr(attrs, :stroke_dasharray)))}
    ]

    case for {bit, bytes} <- fields, is_binary(bytes), do: {bit, bytes} do
      [] ->
        <<>>

      set ->
        flags = Enum.reduce(set, 0, fn {bit, _}, acc -> acc ||| bit end)

        IO.iodata_to_binary([
          <<Opcodes.paint_state()::8, flags::8>> | Enum.map(set, &elem(&1, 1))
        ])
    end
  end

  @hyphenated %{
    fill: :fill,
    stroke: :stroke,
    fill_opacity: :"fill-opacity",
    stroke_opacity: :"stroke-opacity",
    stroke_width: :"stroke-width",
    stroke_linecap: :"stroke-linecap",
    stroke_linejoin: :"stroke-linejoin",
    stroke_dasharray: :"stroke-dasharray",
    clip_path: :"clip-path",
    mask: :mask,
    filter: :filter,
    mix_blend_mode: :"mix-blend-mode",
    vector_effect: :"vector-effect"
  }

  # An attribute under its underscore name or its hyphenated one.
  defp attr(attrs, key), do: Map.get(attrs, key) || Map.get(attrs, Map.fetch!(@hyphenated, key))

  # The inherited presentation attributes an element sets, under their underscore names.
  defp presentation(attrs) do
    for key <- @inherited, value = attr(attrs, key), value != nil, into: %{}, do: {key, value}
  end

  # A group's opacity times the groups' above it, or nil when it sets none: a group's
  # opacity composites the group in SVG, and here it is its children's global alpha, exact
  # where they do not overlap (D-192).
  defp group_opacity(attrs, inherited) do
    case Map.get(attrs, :opacity) do
      nil -> nil
      opacity -> PathEncoder.to_float(opacity) * Map.get(inherited, :group_opacity, 1.0)
    end
  end

  defp word(value, table) when is_atom(value) and value != nil,
    do: word(Atom.to_string(value), table)

  defp word(value, table) when is_binary(value) do
    case Map.fetch(table, value) do
      {:ok, n} -> <<n::8>>
      :error -> nil
    end
  end

  defp word(_absent, _table), do: nil

  defp dash(pattern) when is_list(pattern) and length(pattern) < 256,
    do:
      IO.iodata_to_binary([<<length(pattern)::8>> | Enum.map(pattern, &<<&1::little-float-32>>)])

  defp dash(_absent), do: nil

  # A drawing element's style record: the fill where its own attributes touch the fill (its
  # color, its opacity, or the element's `opacity`), the stroke where they touch the stroke
  # (likewise), the width where it sets one. Each color is the effective one at the
  # effective paint opacity times the element's `opacity`, as SVG multiplies them (#742), so
  # a fill set under a group's fill-opacity takes it and a translucent element's stroke is
  # translucent too. With nothing inherited it is the record the element's attributes
  # alone make. An element that strokes with `vector-effect="non-scaling-stroke"` writes its
  # effective width, `1` where none is set, with bit 4, after its own transform (D-211).
  defp leaf_style(attrs, effective, draws) do
    opacity = Map.get(attrs, :opacity)
    touched? = &(touches?(attrs, &1) or opacity != nil)

    width =
      if non_scaling?(attrs) and <<Opcodes.stroke()::8>> in draws,
        do: {:non_scaling, effective[:stroke_width] || 1},
        else: attr(attrs, :stroke_width)

    style_record(
      touched?.([:fill, :fill_opacity]),
      {effective[:fill], alpha(effective[:fill_opacity], opacity)},
      touched?.([:stroke, :stroke_opacity]),
      {effective[:stroke], alpha(effective[:stroke_opacity], opacity)},
      width,
      nil
    )
  end

  defp non_scaling?(attrs),
    do: attr(attrs, :vector_effect) in ["non-scaling-stroke", :non_scaling_stroke]

  # A group's style record: as a leaf's, over what the group sets, and its opacity as the
  # record's global alpha (bit 3), the groups' above it multiplied in.
  defp group_style(own, effective, opacity) do
    style_record(
      touches?(own, [:fill, :fill_opacity]),
      {effective[:fill], effective[:fill_opacity]},
      touches?(own, [:stroke, :stroke_opacity]),
      {effective[:stroke], effective[:stroke_opacity] || 1.0},
      own[:stroke_width],
      opacity
    )
  end

  defp touches?(attrs, keys), do: Enum.any?(keys, &(attr(attrs, &1) != nil))

  # A paint's opacity times the element's, `1.0` for either that is absent.
  defp alpha(paint, element), do: opacity_float(paint) * opacity_float(element)

  defp opacity_float(nil), do: 1.0
  defp opacity_float(n) when is_number(n), do: n * 1.0

  defp opacity_float(s) when is_binary(s) do
    case Float.parse(s) do
      {f, _} -> f
      :error -> 1.0
    end
  end

  # The style record (spec/09 §4.3.5) with the fields given, `<<>>` when it sets none: a
  # fill or a stroke whose color is absent or `none` sets no field.
  defp style_record(fill?, {fill, fill_alpha}, stroke?, {stroke, stroke_alpha}, width, alpha) do
    {width, non_scaling?} =
      case width do
        {:non_scaling, w} -> {w, true}
        w -> {w, false}
      end

    fields = [
      {0x01, fill? and has_color?(fill) and rgba(parse_color(fill, fill_alpha))},
      {0x02, stroke? and has_color?(stroke) and rgba(parse_color(stroke, stroke_alpha))},
      {0x04, width != nil and <<PathEncoder.to_float(width)::little-float-32>>},
      {0x08, alpha != nil and <<alpha::little-float-32>>},
      {0x10, non_scaling? and <<>>}
    ]

    case for {bit, bytes} <- fields, is_binary(bytes), do: {bit, bytes} do
      [] ->
        <<>>

      set ->
        flags = Enum.reduce(set, 0, fn {bit, _}, acc -> acc ||| bit end)
        IO.iodata_to_binary([<<Opcodes.style()::8, flags::8>> | Enum.map(set, &elem(&1, 1))])
    end
  end

  defp rgba({r, g, b, a}), do: <<r::8, g::8, b::8, a::8>>

  defp has_color?(nil), do: false
  defp has_color?(:none), do: false
  defp has_color?("none"), do: false
  defp has_color?(_), do: true

  # The draws of an element's effective attributes: a fill where it has a fill and a stroke
  # where it has a stroke. A missing fill is not filled, as on every canvas (D-122), where
  # SVG's initial value would paint it black (spec/09 §4.7).
  defp encode_svg_draw_commands(effective) do
    for {paint, opcode} <- [fill: Opcodes.fill(), stroke: Opcodes.stroke()],
        has_color?(effective[paint]),
        do: <<opcode::8>>
  end

  # The `transform` attribute as SVG reads it (spec/09 §4.7, #746): the whole list, each
  # operation into its `Visualize.IR.Transform` operation, written as the IR encoder writes
  # a transform. A list in error is ignored, as SVG ignores it, and so is an empty one.
  defp encode_svg_transform(transform) when is_binary(transform) do
    case transform_operations(transform, []) do
      {:ok, []} -> <<>>
      {:ok, ops} -> CanvasBinary.encode_transform(%Transform{operations: ops})
      :error -> <<>>
    end
  end

  defp encode_svg_transform(_absent), do: <<>>

  @transform_op ~r/\A[\s,]*(matrix|translate|scale|rotate|skewX|skewY)\s*\(([^)]*)\)/
  @transform_number ~r/\A[+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?/

  defp transform_operations(str, acc) do
    case {String.trim(str), Regex.run(@transform_op, str)} do
      {"", _} ->
        {:ok, Enum.reverse(acc)}

      {_, [whole, name, args]} ->
        with {:ok, numbers} <- transform_numbers(String.trim(args), []),
             {:ok, op} <- transform_operation(name, numbers) do
          transform_operations(binary_slice(str, byte_size(whole)..-1//1), [op | acc])
        end

      {_, nil} ->
        :error
    end
  end

  # The numbers of one operation, separated by commas or whitespace.
  defp transform_numbers("", acc), do: {:ok, Enum.reverse(acc)}

  defp transform_numbers(str, acc) do
    case Regex.run(@transform_number, str) do
      [number] ->
        rest = binary_slice(str, byte_size(number)..-1//1)
        rest = Regex.replace(~r/\A\s*,?\s*/, rest, "")
        transform_numbers(rest, [transform_number(number) | acc])

      nil ->
        :error
    end
  end

  # `Float.parse/1` wants a digit before the point: `.5` and `-.5` read as `0.5`, `-0.5`.
  defp transform_number(number) do
    {n, _} = number |> String.replace(~r/\A([+-]?)\./, "\\g{1}0.") |> Float.parse()
    n
  end

  defp transform_operation("matrix", [a, b, c, d, e, f]), do: {:ok, {:matrix, a, b, c, d, e, f}}
  defp transform_operation("translate", [x]), do: {:ok, {:translate, x, 0.0}}
  defp transform_operation("translate", [x, y]), do: {:ok, {:translate, x, y}}
  defp transform_operation("scale", [s]), do: {:ok, {:scale, s, s}}
  defp transform_operation("scale", [sx, sy]), do: {:ok, {:scale, sx, sy}}
  defp transform_operation("rotate", [a]), do: {:ok, {:rotate, a}}
  defp transform_operation("rotate", [a, cx, cy]), do: {:ok, {:rotate, a, cx, cy}}
  defp transform_operation("skewX", [a]), do: {:ok, {:skew_x, a}}
  defp transform_operation("skewY", [a]), do: {:ok, {:skew_y, a}}
  defp transform_operation(_name, _numbers), do: :error

  defp parse_svg_path(""), do: []

  defp parse_svg_path(d) when is_binary(d) do
    # Simple SVG path parser
    d
    |> String.trim()
    |> parse_path_commands([])
  end

  defp parse_path_commands("", acc), do: Enum.reverse(acc)

  defp parse_path_commands(str, acc) do
    str = String.trim_leading(str)

    cond do
      str == "" ->
        Enum.reverse(acc)

      String.starts_with?(str, "M") ->
        {x, y, rest} = parse_two_numbers(String.slice(str, 1..-1//1))
        parse_path_commands(rest, [{:M, x, y} | acc])

      String.starts_with?(str, "m") ->
        {dx, dy, rest} = parse_two_numbers(String.slice(str, 1..-1//1))
        parse_path_commands(rest, [{:m, dx, dy} | acc])

      String.starts_with?(str, "L") ->
        {x, y, rest} = parse_two_numbers(String.slice(str, 1..-1//1))
        parse_path_commands(rest, [{:L, x, y} | acc])

      String.starts_with?(str, "l") ->
        {dx, dy, rest} = parse_two_numbers(String.slice(str, 1..-1//1))
        parse_path_commands(rest, [{:l, dx, dy} | acc])

      String.starts_with?(str, "H") ->
        {x, rest} = parse_one_number(String.slice(str, 1..-1//1))
        parse_path_commands(rest, [{:H, x} | acc])

      String.starts_with?(str, "h") ->
        {dx, rest} = parse_one_number(String.slice(str, 1..-1//1))
        parse_path_commands(rest, [{:h, dx} | acc])

      String.starts_with?(str, "V") ->
        {y, rest} = parse_one_number(String.slice(str, 1..-1//1))
        parse_path_commands(rest, [{:V, y} | acc])

      String.starts_with?(str, "v") ->
        {dy, rest} = parse_one_number(String.slice(str, 1..-1//1))
        parse_path_commands(rest, [{:v, dy} | acc])

      String.starts_with?(str, "C") ->
        {x1, y1, x2, y2, x, y, rest} = parse_six_numbers(String.slice(str, 1..-1//1))
        parse_path_commands(rest, [{:C, x1, y1, x2, y2, x, y} | acc])

      String.starts_with?(str, "c") ->
        {dx1, dy1, dx2, dy2, dx, dy, rest} = parse_six_numbers(String.slice(str, 1..-1//1))
        parse_path_commands(rest, [{:c, dx1, dy1, dx2, dy2, dx, dy} | acc])

      String.starts_with?(str, "Q") ->
        {x1, y1, x, y, rest} = parse_four_numbers(String.slice(str, 1..-1//1))
        parse_path_commands(rest, [{:Q, x1, y1, x, y} | acc])

      String.starts_with?(str, "q") ->
        {dx1, dy1, dx, dy, rest} = parse_four_numbers(String.slice(str, 1..-1//1))
        parse_path_commands(rest, [{:q, dx1, dy1, dx, dy} | acc])

      String.starts_with?(str, "A") ->
        {rx, ry, rotation, large_arc, sweep, x, y, rest} =
          parse_arc_numbers(String.slice(str, 1..-1//1))

        parse_path_commands(rest, [{:A, rx, ry, rotation, large_arc, sweep, x, y} | acc])

      String.starts_with?(str, "a") ->
        {rx, ry, rotation, large_arc, sweep, dx, dy, rest} =
          parse_arc_numbers(String.slice(str, 1..-1//1))

        parse_path_commands(rest, [{:a, rx, ry, rotation, large_arc, sweep, dx, dy} | acc])

      String.starts_with?(str, "Z") or String.starts_with?(str, "z") ->
        parse_path_commands(String.slice(str, 1..-1//1), [:Z | acc])

      true ->
        # Try to parse implicit lineto (numbers after moveto)
        case parse_number(str) do
          {nil, _} ->
            Enum.reverse(acc)

          {x, rest} ->
            {y, rest2} = parse_one_number(rest)
            parse_path_commands(rest2, [{:L, x, y} | acc])
        end
    end
  end

  defp parse_one_number(str) do
    {n, rest} = parse_number(String.trim_leading(str))
    {n || 0, rest}
  end

  defp parse_two_numbers(str) do
    {x, rest} = parse_number(String.trim_leading(str))
    {y, rest2} = parse_number(String.trim_leading(rest))
    {x || 0, y || 0, rest2}
  end

  defp parse_four_numbers(str) do
    {a, rest} = parse_number(String.trim_leading(str))
    {b, rest} = parse_number(String.trim_leading(rest))
    {c, rest} = parse_number(String.trim_leading(rest))
    {d, rest} = parse_number(String.trim_leading(rest))
    {a || 0, b || 0, c || 0, d || 0, rest}
  end

  defp parse_six_numbers(str) do
    {a, rest} = parse_number(String.trim_leading(str))
    {b, rest} = parse_number(String.trim_leading(rest))
    {c, rest} = parse_number(String.trim_leading(rest))
    {d, rest} = parse_number(String.trim_leading(rest))
    {e, rest} = parse_number(String.trim_leading(rest))
    {f, rest} = parse_number(String.trim_leading(rest))
    {a || 0, b || 0, c || 0, d || 0, e || 0, f || 0, rest}
  end

  defp parse_arc_numbers(str) do
    {rx, rest} = parse_number(String.trim_leading(str))
    {ry, rest} = parse_number(String.trim_leading(rest))
    {rotation, rest} = parse_number(String.trim_leading(rest))
    {large_arc, rest} = parse_number(String.trim_leading(rest))
    {sweep, rest} = parse_number(String.trim_leading(rest))
    {x, rest} = parse_number(String.trim_leading(rest))
    {y, rest} = parse_number(String.trim_leading(rest))

    {rx || 0, ry || 0, rotation || 0, trunc(large_arc || 0), trunc(sweep || 0), x || 0, y || 0,
     rest}
  end

  defp parse_number(str) do
    str = str |> String.trim_leading() |> String.replace(~r/^,\s*/, "")

    case Regex.run(~r/^(-?[\d.]+(?:e[-+]?\d+)?)/, str) do
      [match, num_str] ->
        num =
          case Float.parse(num_str) do
            {n, _} -> n
            :error -> 0.0
          end

        rest = String.slice(str, String.length(match)..-1//1)
        {num, rest}

      _ ->
        {nil, str}
    end
  end

  defp alpha_byte(alpha), do: trunc(opacity_float(alpha) * 255)

  # A color is parsed by `Visualize.Color.parse/1` (an atom by its name); its alpha is the
  # supplied opacity times the alpha the color syntax carries (`rgba()`, `#rgba`,
  # `#rrggbbaa`), as SVG multiplies them (#742). `"none"` is transparent; anything
  # unparseable is black.
  defp parse_color("none", _opacity), do: {0, 0, 0, 0}

  defp parse_color(color, opacity) when is_atom(color),
    do: parse_color(Atom.to_string(color), opacity)

  defp parse_color(color, opacity) when is_binary(color) do
    case Visualize.Color.parse(color) do
      %Visualize.Color{opacity: own} = parsed ->
        {r, g, b, _} = Visualize.Color.to_rgba(parsed)
        {r, g, b, alpha_byte(own * opacity_float(opacity))}

      nil ->
        {0, 0, 0, alpha_byte(opacity)}
    end
  end

  # A `points` list: a string of numbers, separated by commas or whitespace and paired in
  # order, an odd last one dropped as SVG drops it; or a list of `{x, y}`. A string that
  # does not read is in error, which SVG renders up to.
  defp points(points) when is_list(points),
    do: for({x, y} <- points, do: {PathEncoder.to_float(x), PathEncoder.to_float(y)})

  defp points(points) when is_binary(points) do
    points
    |> String.trim()
    |> point_numbers([])
    |> Enum.chunk_every(2, 2, :discard)
    |> Enum.map(fn [x, y] -> {x, y} end)
  end

  defp points(_absent), do: []

  defp point_numbers("", acc), do: Enum.reverse(acc)

  defp point_numbers(str, acc) do
    case Regex.run(@transform_number, str) do
      [number] ->
        rest = binary_slice(str, byte_size(number)..-1//1)
        point_numbers(Regex.replace(~r/\A\s*,?\s*/, rest, ""), [transform_number(number) | acc])

      nil ->
        Enum.reverse(acc)
    end
  end
end
