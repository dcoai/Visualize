defmodule Visualize.Chart.Frame.Furniture do
  @moduledoc false
  # The axes and the grid of a frame (spec/14 §4.4, §4.6): each axis a `Visualize.Axis`
  # on the realised scale, placed at its side of the plot area; the grid one hidden group
  # of lines at the tick positions behind the axes; and, in a polar frame, rings and
  # spokes drawn from the plot centre.

  alias Visualize.{Axis, Format, Scale}
  alias Visualize.Chart.Frame
  alias Visualize.Chart.Frame.Position
  alias Visualize.Chart.{Schema, Style}
  alias Visualize.IR.{Element, Path, Transform}

  @stroke_keys [
    :stroke,
    :stroke_width,
    :stroke_dasharray,
    :stroke_linecap,
    :stroke_linejoin,
    :stroke_opacity
  ]
  @text_keys [:fill, :fill_opacity, :text_anchor]
  @group_keys [:opacity, :class, :font_family, :font_size, :font_weight, :font_style]

  @doc false
  # The grid group when any axis asks for one, then the marks given, then one group per
  # axis (cartesian), each stamped with its path among `axes` when `paths?` (spec/14 §4.7).
  @spec cartesian(map(), atom(), [Element.t()], boolean()) :: [Element.t()]
  def cartesian(frame, mode, marks \\ [], paths? \\ false) do
    grid(frame, mode) ++ marks ++ axes(frame, Enum.with_index(frame.axes), mode, paths?)
  end

  @doc false
  # One group at the plot centre holding the polar grid, the marks given, and the ring
  # and spoke axes; an axis on any other scale draws as a cartesian one. Every axis keeps
  # its position among `axes` whichever way it is drawn, so its path is the design's.
  @spec polar(map(), atom(), [Element.t()], boolean()) :: [Element.t()]
  def polar(frame, mode, marks \\ [], paths? \\ false) do
    {polar, other} =
      frame.axes
      |> Enum.with_index()
      |> Enum.split_with(fn {node, _i} -> node.scale in [:angle, :r] end)

    rings =
      for {node, i} <- polar,
          do: frame |> polar_axis(node, mode) |> Frame.stamp([:frame, :axes, i], paths?)

    [centred(frame, polar_grid(frame, mode) ++ marks ++ rings)] ++
      grid(%{frame | axes: Enum.map(other, &elem(&1, 0))}, mode) ++
      axes(frame, other, mode, paths?)
  end

  # The indexed axis nodes drawn and placed, each stamped with its path when asked.
  defp axes(frame, indexed, mode, paths?) do
    for {node, i} <- indexed,
        do: frame |> place_axis(node, mode) |> Frame.stamp([:frame, :axes, i], paths?)
  end

  @doc false
  # The cartesian grid: one hidden group of lines at the tick positions of every axis
  # with `grid: true`, or nothing (spec/14 §4.4).
  @spec grid(map(), atom()) :: [Element.t()]
  def grid(frame, mode), do: grid(frame, Enum.map(frame.axes, &{&1, axis(frame, &1)}), mode)

  @doc false
  # One axis node drawn and placed at its side of the plot area.
  @spec place_axis(map(), map(), atom()) :: Element.t()
  def place_axis(frame, node, mode), do: place(frame, node, axis(frame, node), mode)

  @doc false
  # The axes on `angle` and `r`, then the others, of a polar frame (spec/14 §4.6).
  @spec polar_split(map()) :: {[map()], [map()]}
  def polar_split(frame), do: Enum.split_with(frame.axes, &(&1.scale in [:angle, :r]))

  @doc false
  # The polar grid — spokes and rings — of the axes on `angle` and `r`, or nothing.
  @spec polar_grid(map(), atom()) :: [Element.t()]
  def polar_grid(frame, mode) do
    {polar, _other} = polar_split(frame)
    lines = Enum.flat_map(polar, &polar_grid(frame, &1, axis(frame, &1)))

    if lines == [],
      do: [],
      else: [group(lines, "grid", Style.resolve(style(frame, :grid), frame.theme, mode))]
  end

  @doc false
  # A ring (on `angle`) or a spoke (on `r`) axis about the plot centre.
  @spec polar_axis(map(), map(), atom()) :: Element.t()
  def polar_axis(frame, node, mode), do: polar_axis(frame, node, axis(frame, node), mode)

  @doc false
  # The group at the plot centre that holds a polar frame's grid, marks and polar axes.
  @spec centred(map(), [Element.t()]) :: Element.t()
  def centred(frame, children) do
    Element.group(children,
      style: %{class: "polar"},
      transform: Transform.translate(frame.plot.width / 2, frame.plot.height / 2)
    )
  end

  @doc false
  # The `Visualize.Axis` an axis node describes over the frame's realised scale.
  @spec axis(map(), map()) :: Axis.t()
  def axis(frame, node) do
    scale = Map.fetch!(frame.scales, node.scale)

    Axis
    |> apply(node.side, [scale])
    |> Axis.theme(frame.theme)
    |> Axis.offset(Map.get(node, :offset, Schema.default(:axis, :offset)))
    |> ticks(Map.get(node, :ticks))
    |> format(scale, Map.get(node, :format))
    |> unit(Map.get(node, :prefix), Map.get(node, :unit))
  end

  defp ticks(axis, nil), do: axis
  defp ticks(axis, count) when is_integer(count), do: Axis.ticks(axis, count)
  defp ticks(axis, values) when is_list(values), do: Axis.tick_values(axis, values)

  defp ticks(axis, %{} = spec) do
    axis
    |> ticks(Map.get(spec, :count))
    |> ticks(Map.get(spec, :values))
    |> Axis.tick_size_inner(Map.get(spec, :size_inner, Schema.default(:ticks, :size_inner)))
    |> Axis.tick_size_outer(Map.get(spec, :size_outer, Schema.default(:ticks, :size_outer)))
    |> Axis.tick_padding(Map.get(spec, :padding, Schema.default(:ticks, :padding)))
  end

  defp format(axis, _scale, nil), do: axis

  # A named format no specifier can express (spec/14 §4.4, #191).
  defp format(axis, _scale, :duration) do
    Axis.tick_format(axis, fn v -> if is_number(v), do: Format.duration(v), else: to_string(v) end)
  end

  defp format(axis, %Scale.Time{}, spec), do: Axis.tick_format(axis, &Format.time(&1, spec))

  defp format(axis, _scale, spec) do
    formatter = Format.formatter(spec)
    Axis.tick_format(axis, fn v -> if is_number(v), do: formatter.(v), else: to_string(v) end)
  end

  # The literals around every tick's label — the formatted value, or the default label
  # when there is no format (spec/14 §4.4, #135).
  defp unit(axis, nil, nil), do: axis

  defp unit(axis, prefix, unit) do
    label = axis.tick_format || (&Axis.default_label/1)
    Axis.tick_format(axis, fn v -> (prefix || "") <> label.(v) <> (unit || "") end)
  end

  # -- placement ------------------------------------------------------------------------

  defp place(frame, node, axis, mode) do
    element = axis |> Axis.generate(resolve: mode) |> restyle(frame, node, mode)

    Element.group([element],
      style: %{class: "axis axis-#{node.side}"},
      transform: side_transform(node.side, frame.plot)
    )
  end

  defp side_transform(:bottom, plot), do: Transform.translate(0, plot.height)
  defp side_transform(:right, plot), do: Transform.translate(plot.width, 0)
  defp side_transform(_top_or_left, _plot), do: Transform.translate(0, 0)

  # A style other than the built-in `:axis` reaches the axis's elements by kind, and its
  # `text_angle` turns each tick label about its own point (spec/14 §6.3).
  defp restyle(element, frame, node, mode) do
    name = Map.get(node, :style, Schema.default(:axis, :style))

    if name == :axis and not Map.has_key?(frame.design_styles, :axis) do
      element
    else
      style_node = style(frame, name)

      element
      |> apply_style(Style.resolve(style_node, frame.theme, mode))
      |> Position.rotate_ticks(style_node)
    end
  end

  defp apply_style(%Element{type: :group} = group, style) do
    group
    |> Element.set_style(Map.take(style, @group_keys))
    |> Map.update!(:children, fn children -> Enum.map(children, &apply_style(&1, style)) end)
  end

  defp apply_style(%Element{type: type} = element, style) when type in [:path, :line] do
    Element.set_style(element, Map.take(style, @stroke_keys))
  end

  defp apply_style(%Element{type: :text} = element, style) do
    Element.set_style(element, Map.take(style, @text_keys))
  end

  defp apply_style(element, _style), do: element

  defp style(frame, name), do: Style.node(frame.styles, name)

  # -- grid -----------------------------------------------------------------------------

  defp grid(frame, axes, mode) do
    lines =
      Enum.flat_map(axes, fn {node, axis} ->
        if Map.get(node, :grid, false), do: grid_lines(frame, node, axis), else: []
      end)

    if lines == [] do
      []
    else
      [group(lines, "grid", Style.resolve(style(frame, :grid), frame.theme, mode))]
    end
  end

  defp group(children, class, style) do
    Element.group(children, style: Map.put(style, :class, class), attrs: %{aria_hidden: "true"})
  end

  defp grid_lines(frame, %{side: side}, axis) when side in [:top, :bottom] do
    for v <- tick_values(axis), p = Axis.tick_position(axis, v) do
      Element.line(p, 0, p, frame.plot.height)
    end
  end

  defp grid_lines(frame, _node, axis) do
    for v <- tick_values(axis), p = Axis.tick_position(axis, v) do
      Element.line(0, p, frame.plot.width, p)
    end
  end

  defp tick_values(%Axis{tick_values: values}) when is_list(values), do: values
  defp tick_values(%Axis{scale: scale, ticks: count}), do: Scale.ticks(scale, count || 10)

  # -- polar ----------------------------------------------------------------------------

  defp outer_radius(frame), do: min(frame.plot.width, frame.plot.height) / 2

  # The unit vector of an angle in radians clockwise from 12 o'clock (spec/04 §6.2),
  # rounded so a right angle lands on the axis rather than 1e-16 off it.
  defp unit(angle), do: {crisp(:math.sin(angle)), crisp(-:math.cos(angle))}

  # Six decimals, negative zero folded (D-6): what the polar coordinates print as.
  defp crisp(x) do
    case Float.round(x * 1.0, 6) do
      r when r == 0 -> 0.0
      r -> r
    end
  end

  defp direction(:top), do: {0, -1}
  defp direction(:right), do: {1, 0}
  defp direction(:bottom), do: {0, 1}
  defp direction(:left), do: {-1, 0}

  # The grid of a polar axis (spec/14 §4.6, #390): spokes over the radius band for the
  # angle scale, arcs over the sweep for the radius.
  defp polar_grid(frame, %{grid: true, scale: :angle}, axis) do
    {r0, r1} = radii(frame)

    for v <- tick_values(axis), {ux, uy} = unit(Axis.tick_position(axis, v)) do
      {x0, y0} = inner_end(r0, ux, uy)
      Element.line(x0, y0, crisp(r1 * ux), crisp(r1 * uy))
    end
  end

  defp polar_grid(frame, %{grid: true, scale: :r}, axis) do
    {a0, a1} = sweep(frame)

    for v <- tick_values(axis), r = crisp(Scale.apply(axis.scale, v)), r > 0 do
      arc(r, a0, a1, %{fill: :none})
    end
  end

  defp polar_grid(_frame, _node, _axis), do: []

  # The angle scale's range: the sweep from its start, in radians (§4.3), the full turn
  # when the frame declares none.
  defp sweep(frame) do
    case Map.get(frame.scales, :angle) do
      %{range: [a0, a1]} -> {a0, a1}
      _none -> {0, 2 * :math.pi()}
    end
  end

  # The r scale's range: the band the plot occupies, `[0, R]` when the frame declares none.
  defp radii(frame) do
    case Map.get(frame.scales, :r) do
      %{range: [r0, r1]} -> {min(r0, r1), max(r0, r1)}
      _none -> {0, outer_radius(frame)}
    end
  end

  # A spoke's inner end: the centre itself, printed as the integer it was, when the
  # band starts there — the full-turn output stays byte for byte.
  defp inner_end(r0, _ux, _uy) when r0 == 0, do: {0, 0}
  defp inner_end(r0, ux, uy), do: {crisp(r0 * ux), crisp(r0 * uy)}

  # Whether a sweep is a full turn (or more): drawn as a circle, byte for byte the ring.
  defp full_turn?(a0, a1), do: abs(a1 - a0) >= 2 * :math.pi() - 1.0e-9

  # The arc of a sweep at a radius: a circle on a full turn, else one `A` command from
  # the start to the end, the large-arc flag set past a half turn, clockwise as the sweep
  # runs (§4.6, #390).
  defp arc(r, a0, a1, style) do
    if full_turn?(a0, a1) do
      Element.circle(0, 0, r, style)
    else
      {x0, y0} = unit(a0)
      {x1, y1} = unit(a1)
      large = if abs(a1 - a0) > :math.pi(), do: 1, else: 0
      direction = if a1 > a0, do: 1, else: 0

      Path.new()
      |> Path.move_to(crisp(r * x0), crisp(r * y0))
      |> Path.arc_to(r, r, 0, large, direction, crisp(r * x1), crisp(r * y1))
      |> Element.path(style)
    end
  end

  # An angle axis's radius (§4.4): a fraction of R when at most 1, else user units, R
  # when absent.
  defp axis_radius(frame, node) do
    case Map.get(node, :radius) do
      nil -> outer_radius(frame)
      fraction when fraction <= 1 -> outer_radius(frame) * fraction
      units -> units
    end
  end

  # An r axis's direction: `at` degrees clockwise from 12 o'clock wins over `side`.
  defp spoke_direction(node) do
    case Map.get(node, :at) do
      nil -> direction(node.side)
      degrees -> unit(degrees * :math.pi() / 180)
    end
  end

  defp polar_axis(frame, node, axis, mode) do
    style = Style.resolve(style(frame, Map.get(node, :style, :axis)), frame.theme, mode)
    text_anchor = if node.scale == :angle, do: :middle, else: spoke_anchor(spoke_direction(node))

    group_style =
      %{fill: :none, text_anchor: text_anchor} |> Map.merge(Map.take(style, @group_keys))

    stroke = Map.take(style, @stroke_keys)
    fill = Map.take(style, @text_keys)

    {domain, ticks} =
      case node.scale do
        :angle -> ring(frame, node, axis, stroke, fill)
        :r -> spoke(frame, node, axis, stroke, fill)
      end

    Element.group([domain | ticks],
      style: Map.put(group_style, :class, "axis axis-#{node.scale}"),
      attrs: %{aria_hidden: "true"}
    )
  end

  defp ring(frame, node, axis, stroke, fill) do
    r = axis_radius(frame, node)
    {a0, a1} = sweep(frame)
    inner = axis.tick_size_inner
    pad = axis.tick_padding

    ticks =
      for v <- tick_values(axis), {ux, uy} = unit(Axis.tick_position(axis, v)) do
        line =
          Element.line(
            crisp(r * ux),
            crisp(r * uy),
            crisp((r + inner) * ux),
            crisp((r + inner) * uy),
            stroke
          )

        label =
          tick_text(
            axis,
            v,
            crisp((r + inner + pad) * ux),
            crisp((r + inner + pad) * uy),
            "0.32em",
            fill
          )

        Element.group([line, label], style: %{class: "tick"})
      end

    {arc(r, a0, a1, stroke), ticks}
  end

  defp spoke(frame, node, axis, stroke, fill) do
    {r0, r1} = radii(frame)
    {ux, uy} = spoke_direction(node)
    {px, py} = {-uy, ux}
    inner = axis.tick_size_inner
    pad = axis.tick_padding

    ticks =
      for v <- tick_values(axis), d = crisp(Scale.apply(axis.scale, v)) do
        line =
          Element.line(
            crisp(d * ux),
            crisp(d * uy),
            crisp(d * ux + inner * px),
            crisp(d * uy + inner * py),
            stroke
          )

        {lx, ly} = {crisp(d * ux + (inner + pad) * px), crisp(d * uy + (inner + pad) * py)}
        label = tick_text(axis, v, lx, ly, spoke_dy({px, py}), fill)
        Element.group([line, label], style: %{class: "tick"})
      end

    {x0, y0} = inner_end(r0, ux, uy)
    {Element.line(x0, y0, crisp(r1 * ux), crisp(r1 * uy), stroke), ticks}
  end

  defp spoke_anchor(direction) do
    case {-elem(direction, 1), elem(direction, 0)} do
      {px, _} when px > 0 -> :start
      {px, _} when px < 0 -> :end
      _ -> :middle
    end
  end

  defp spoke_dy({_px, py}) when py > 0, do: "0.71em"
  defp spoke_dy({_px, py}) when py < 0, do: "0em"
  defp spoke_dy(_perpendicular), do: "0.32em"

  defp tick_text(axis, value, x, y, dy, fill) do
    label = if axis.tick_format, do: axis.tick_format.(value), else: Axis.default_label(value)
    Element.text(label, x: x, y: y, dy: dy, style: fill)
  end
end
