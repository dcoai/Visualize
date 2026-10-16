defmodule Visualize.Backend.CanvasBinary.SVG do
  @moduledoc """
  Encodes `Visualize.SVG.Element` trees into the canvas binary format: element geometry,
  presentation attributes, `transform` strings and `d` path strings.
  """

  import Bitwise

  alias Visualize.Backend.Canvas
  alias Visualize.Backend.CanvasBinary.{Opcodes, PathEncoder}
  require Opcodes

  # The tags that draw, and so read the stroke's attributes (spec/09 §4.7).
  @drawn [:rect, :circle, :path, :line]

  # The presentation attributes a `:g` (or the root `:svg`) passes on to what it holds, as
  # SVG inherits them: a descendant's own value wins (spec/09 §4.7, #734, D-192). `opacity`
  # is not among them: it is the group's, its children's global alpha.
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

  # The inherited attributes a style record (spec/09 §4.3.5) carries as canvas state.
  @style_state [:fill, :fill_opacity, :stroke, :stroke_opacity, :stroke_width]

  @doc false
  # A tree as a whole stream (spec/09 §4.2, §4.7): `version` 3 first when any element writes
  # a stroke's dash, cap or join (#693, D-180), and every other tree's records as they were.
  @spec encode_tree(Visualize.SVG.Element.t(), :f32 | :f64) :: binary()
  def encode_tree(element, precision) do
    records = encode_element(element, precision)
    if paint_state?(element), do: <<Opcodes.version()::8, 3::8>> <> records, else: records
  end

  defp paint_state?(%Visualize.SVG.Element{tag: tag, attrs: attrs, children: children}) do
    (tag in [:g, :svg | @drawn] and paint_state(attrs) != <<>>) or
      Enum.any?(children, &paint_state?/1)
  end

  # SVG Element Encoding

  @doc false
  def encode_element(element, precision), do: encode(element, precision, %{})

  # `inherited` is what the groups above pass on: their presentation attributes under the
  # names of `@inherited`, the nearest group's value for each, and `:group_opacity`, the
  # product of their opacities.
  defp encode(%Visualize.SVG.Element{tag: tag} = element, precision, inherited)
       when tag in [:svg, :g] do
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
    # inherits (a fill-opacity over an inherited fill), and its cap, join and dash.
    state =
      IO.iodata_to_binary([transform, group_style(own, effective, opacity), paint_state(attrs)])

    child_data = IO.iodata_to_binary(Enum.map(children, &encode(&1, precision, passed)))

    case state do
      <<>> when not is_map_key(attrs, :transform) or tag == :svg ->
        child_data

      state ->
        <<Opcodes.save()::8, state::binary, child_data::binary, Opcodes.restore()::8>>
    end
  end

  defp encode(%Visualize.SVG.Element{tag: :rect, attrs: attrs}, _precision, inherited) do
    x = Map.get(attrs, :x, 0) |> PathEncoder.to_float()
    y = Map.get(attrs, :y, 0) |> PathEncoder.to_float()
    width = Map.get(attrs, :width, 0) |> PathEncoder.to_float()
    height = Map.get(attrs, :height, 0) |> PathEncoder.to_float()

    geometry =
      <<Opcodes.rects()::8, 1::little-32, x::little-float-64, y::little-float-64,
        width::little-float-64, height::little-float-64>>

    leaf(attrs, inherited, geometry, &encode_svg_draw_commands/1)
  end

  defp encode(%Visualize.SVG.Element{tag: :circle, attrs: attrs}, _precision, inherited) do
    cx = Map.get(attrs, :cx, 0) |> PathEncoder.to_float()
    cy = Map.get(attrs, :cy, 0) |> PathEncoder.to_float()
    r = Map.get(attrs, :r, 0) |> PathEncoder.to_float()

    geometry =
      <<Opcodes.circles()::8, 1::little-32, cx::little-float-64, cy::little-float-64,
        r::little-float-64>>

    leaf(attrs, inherited, geometry, &encode_svg_draw_commands/1)
  end

  defp encode(%Visualize.SVG.Element{tag: :path, attrs: attrs}, precision, inherited) do
    d = Map.get(attrs, :d, "")

    case parse_svg_path(d) do
      [] ->
        <<>>

      commands ->
        geometry = PathEncoder.encode_cubic_path(commands, precision)
        leaf(attrs, inherited, geometry, &encode_svg_draw_commands/1)
    end
  end

  defp encode(%Visualize.SVG.Element{tag: :line, attrs: attrs}, precision, inherited) do
    x1 = Map.get(attrs, :x1, 0) |> PathEncoder.to_float()
    y1 = Map.get(attrs, :y1, 0) |> PathEncoder.to_float()
    x2 = Map.get(attrs, :x2, 0) |> PathEncoder.to_float()
    y2 = Map.get(attrs, :y2, 0) |> PathEncoder.to_float()

    # A move and a line, always stroked.
    geometry = PathEncoder.encode_cubic_path([{:M, x1, y1}, {:L, x2, y2}], precision)
    leaf(attrs, inherited, geometry, fn _effective -> [<<Opcodes.stroke()::8>>] end)
  end

  # Text is not representable in the binary format, and any other tag draws nothing.
  defp encode(_element, _precision, _inherited), do: <<>>

  # A drawing element's records: its style, its geometry and its draws, and with a stroke's
  # dash, cap or join its `paint_state` after the style, all inside `save` … `restore` so
  # they outlive it on no later element (spec/09 §4.7, #693). The style carries what its own
  # attributes set, each combined with what the groups pass on; the draws are its effective
  # attributes', its own over the groups' (#734).
  #
  # Under a group's style state — its fill, stroke or width — a leaf whose own style record
  # changes it is scoped too: the state is the group's for every child, so a later sibling
  # that sets nothing draws in the group's colors, not this leaf's (#742). A tree with no
  # such group is the stream it was.
  defp leaf(attrs, inherited, geometry, draws) do
    effective = Map.merge(inherited, presentation(attrs))
    style = leaf_style(attrs, effective)
    draws = draws.(effective)
    group_state? = Enum.any?(@style_state, &Map.has_key?(inherited, &1))

    case paint_state(attrs) do
      <<>> when style == <<>> or not group_state? ->
        IO.iodata_to_binary([style, geometry | draws])

      state ->
        IO.iodata_to_binary([
          <<Opcodes.save()::8>>,
          style,
          state,
          geometry,
          draws,
          <<Opcodes.restore()::8>>
        ])
    end
  end

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
    stroke_dasharray: :"stroke-dasharray"
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
  # alone make.
  defp leaf_style(attrs, effective) do
    opacity = Map.get(attrs, :opacity)
    touched? = &(touches?(attrs, &1) or opacity != nil)

    style_record(
      touched?.([:fill, :fill_opacity]),
      {effective[:fill], alpha(effective[:fill_opacity], opacity)},
      touched?.([:stroke, :stroke_opacity]),
      {effective[:stroke], alpha(effective[:stroke_opacity], opacity)},
      attr(attrs, :stroke_width),
      nil
    )
  end

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
    fields = [
      {0x01, fill? and has_color?(fill) and rgba(parse_color(fill, fill_alpha))},
      {0x02, stroke? and has_color?(stroke) and rgba(parse_color(stroke, stroke_alpha))},
      {0x04, width != nil and <<PathEncoder.to_float(width)::little-float-32>>},
      {0x08, alpha != nil and <<alpha::little-float-32>>}
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

  defp encode_svg_transform(transform_str) when is_binary(transform_str) do
    cond do
      String.starts_with?(transform_str, "translate(") ->
        case Regex.run(~r/translate\(([-\d.]+),?\s*([-\d.]+)?\)/, transform_str) do
          [_, x_str] ->
            x = parse_number_string(x_str)
            <<Opcodes.transform()::8, 0x01::8, x::little-float-64, 0.0::little-float-64>>

          [_, x_str, y_str] ->
            x = parse_number_string(x_str)
            y = parse_number_string(y_str)
            <<Opcodes.transform()::8, 0x01::8, x::little-float-64, y::little-float-64>>

          _ ->
            <<>>
        end

      String.starts_with?(transform_str, "scale(") ->
        case Regex.run(~r/scale\(([-\d.]+),?\s*([-\d.]+)?\)/, transform_str) do
          [_, s_str] ->
            s = parse_number_string(s_str)

            <<Opcodes.transform()::8, 0x03::8, 0.0::little-float-64, 0.0::little-float-64,
              s::little-float-64, s::little-float-64>>

          [_, sx_str, sy_str] ->
            sx = parse_number_string(sx_str)
            sy = parse_number_string(sy_str)

            <<Opcodes.transform()::8, 0x03::8, 0.0::little-float-64, 0.0::little-float-64,
              sx::little-float-64, sy::little-float-64>>

          _ ->
            <<>>
        end

      true ->
        <<>>
    end
  end

  defp encode_svg_transform(_), do: <<>>

  defp parse_number_string(str) do
    case Float.parse(str) do
      {f, _} ->
        f

      :error ->
        case Integer.parse(str) do
          {i, _} -> i * 1.0
          :error -> 0.0
        end
    end
  end

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
end
