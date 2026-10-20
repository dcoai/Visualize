defmodule Visualize.Hooks.Tooltip.Items do
  @moduledoc false
  # The hit index of a drawing (spec/10 §12.5, #764, D-197): every keyed datum element of
  # a mark with an event — the elements a click on the SVG lands on, by the same `data-row`
  # under the same `data-mark` — as its shape in the chart's user units, so `TooltipHook`
  # resolves a click on a canvas, which draws no element, to the key the SVG would send.
  #
  # One entry per mark, in drawing order: `{"event", "frame", "mark", "items"}`, and each
  # item `[row, kind, …]`, also in drawing order, so the last item under the pointer is
  # the one drawn on top:
  #
  #   * `[row, "r", x, y, w, h]` - a rectangle, axis-aligned in the chart's units
  #   * `[row, "c", cx, cy, r]` - a disc
  #   * `[row, "p", x, y, w, h, d, [a, b, c, d, e, f], fill, width]` - a path: its box in
  #     the chart's units, its `d` in its own, the matrix from its units to the chart's,
  #     whether it is filled, and its stroke's width
  #
  # Any other shape, and a rectangle or a disc under a rotation, a skew or an unequal
  # scale, is its bounding box in the chart's units, or the path it is.

  alias Visualize.IR.{Element, Paint, Path, Transform}

  @identity {1, 0, 0, 1, 0, 0}

  @doc false
  # The index of `tree`, a chart's generated element (`Visualize.Chart.generate/2`), as the
  # JSON the hook reads; `"[]"` for a drawing with no keyed element.
  @spec json(Element.t()) :: String.t()
  def json(%Element{} = tree) do
    tree
    |> entries()
    |> Enum.map_join(",", &mark_json/1)
    |> then(&("[" <> &1 <> "]"))
  end

  @doc false
  # The index as data: `[%{event, frame, mark, items}]`, items as `json/1` writes them.
  @spec entries(Element.t()) :: [map()]
  def entries(%Element{} = tree), do: tree |> marks(@identity, %{}, []) |> Enum.reverse()

  # The marks under an element, its transform composed onto `m` and the paint it inherits
  # laid under its own. A group carrying a mark's event and key opens an entry; its keyed
  # elements are the entry's items.
  defp marks(%Element{} = el, m, paint, acc) do
    {m, paint} = enter(el, m, paint)

    case {Map.get(el.attrs, "data-tooltip-event"), Map.get(el.attrs, "data-mark")} do
      {event, mark} when is_binary(event) and is_binary(mark) ->
        entry = %{
          event: event,
          frame: Map.get(el.attrs, "data-frame"),
          mark: String.to_integer(mark),
          items: []
        }

        entry = Enum.reduce(el.children, entry, &items(&1, m, paint, &2))
        [%{entry | items: Enum.reverse(entry.items)} | acc]

      _other ->
        Enum.reduce(el.children, acc, &marks(&1, m, paint, &2))
    end
  end

  # A keyed element is one item; any other is searched for keyed descendants.
  defp items(%Element{} = el, m, paint, entry) do
    {m, paint} = enter(el, m, paint)

    case Map.get(el.attrs, "data-row") do
      row when is_binary(row) ->
        case shape(el, m, paint) do
          nil -> entry
          shape -> %{entry | items: [[String.to_integer(row) | shape] | entry.items]}
        end

      nil ->
        Enum.reduce(el.children, entry, &items(&1, m, paint, &2))
    end
  end

  # An element's matrix and paint: its transform composed on, its fill and stroke over
  # what its groups set, as SVG inherits them.
  defp enter(%Element{transform: transform, style: style}, m, paint),
    do:
      {compose(m, transform), Map.merge(paint, Map.take(style, [:fill, :stroke, :stroke_width]))}

  # -- shapes -----------------------------------------------------------------------------

  # A rectangle and a disc take the pointer over their stroke too, half its width outside.
  defp shape(%Element{type: :rect} = el, m, paint) do
    pad = stroke_width(paint) / 2

    case {axis_aligned(m), Paint.bounds(el)} do
      {_, nil} -> nil
      {true, box} -> ["r" | transformed_box(grow(box, pad), m)]
      {false, {x, y, w, h}} -> path(rect_path(x, y, w, h), m, true, stroke_width(paint))
    end
  end

  defp shape(%Element{type: :circle, attrs: %{cx: cx, cy: cy, r: r}} = el, m, paint) do
    pad = stroke_width(paint) / 2

    case uniform(m) do
      nil -> ["r" | transformed_box(grow(Paint.bounds(el), pad), m)]
      s -> ["c" | numbers([apply_x(m, cx, cy), apply_y(m, cx, cy), (r + pad) * s])]
    end
  end

  # A path takes the pointer where it is painted: its fill, black when no group sets one,
  # as SVG's, unless it is `none`; and its stroke.
  defp shape(%Element{type: :path, path: %Path{} = p}, m, paint) do
    path(p, m, Map.get(paint, :fill) not in [:none, "none"], stroke_width(paint))
  end

  # A group keyed as one datum (a glyph inside its entrance's group): the box of its shapes.
  defp shape(%Element{type: :group, children: children}, m, _paint) do
    boxes = for child <- children, box = child_box(child, m), box != nil, do: box

    case boxes do
      [] -> nil
      boxes -> ["r" | numbers(union(boxes))]
    end
  end

  defp shape(%Element{} = el, m, _paint) do
    case Paint.bounds(el) do
      nil -> nil
      box -> ["r" | transformed_box(box, m)]
    end
  end

  defp child_box(%Element{type: :group, children: children} = el, m) do
    m = compose(m, el.transform)

    case for(child <- children, box = child_box(child, m), box != nil, do: box) do
      [] -> nil
      boxes -> union(boxes)
    end
  end

  defp child_box(%Element{} = el, m) do
    m = compose(m, el.transform)

    case Paint.bounds(el) do
      nil -> nil
      box -> box |> corners() |> Enum.map(&apply_point(m, &1)) |> bounding()
    end
  end

  defp path(%Path{} = p, m, filled?, width) do
    case Paint.bounds(%Element{type: :path, path: p}) do
      nil ->
        nil

      box ->
        {a, b, c, d, e, f} = m
        pad = width / 2

        {x, y, w, h} =
          box |> corners() |> Enum.map(&apply_point(m, &1)) |> bounding()

        ["p"] ++
          numbers([x - pad, y - pad, w + 2 * pad, h + 2 * pad]) ++
          [Path.to_string(p), numbers([a, b, c, d, e, f]), if(filled?, do: 1, else: 0), width]
    end
  end

  defp rect_path(x, y, w, h),
    do: %Path{commands: [{:M, x, y}, {:L, x + w, y}, {:L, x + w, y + h}, {:L, x, y + h}, :Z]}

  defp stroke_width(style) do
    case Map.get(style, :stroke) do
      s when s in [nil, :none, "none"] -> 0
      _stroke -> if is_number(style[:stroke_width]), do: style[:stroke_width], else: 1
    end
  end

  # -- the affine matrix {a, b, c, d, e, f}, as SVG's and the canvas's -----------------------

  defp compose(m, nil), do: m
  defp compose(m, %Transform{operations: ops}), do: Enum.reduce(ops, m, &multiply(&2, op(&1)))

  defp op({:translate, x, y}), do: {1, 0, 0, 1, x, y}
  defp op({:scale, sx, sy}), do: {sx, 0, 0, sy, 0, 0}

  defp op({:rotate, deg}) do
    {cos, sin} = cos_sin(deg)
    {cos, sin, -sin, cos, 0, 0}
  end

  defp op({:rotate, deg, cx, cy}),
    do: {1, 0, 0, 1, cx, cy} |> multiply(op({:rotate, deg})) |> multiply({1, 0, 0, 1, -cx, -cy})

  defp op({:skew_x, deg}), do: {1, 0, :math.tan(deg * :math.pi() / 180), 1, 0, 0}
  defp op({:skew_y, deg}), do: {1, :math.tan(deg * :math.pi() / 180), 0, 1, 0, 0}
  defp op({:matrix, a, b, c, d, e, f}), do: {a, b, c, d, e, f}

  defp cos_sin(deg) do
    rad = deg * :math.pi() / 180
    {:math.cos(rad), :math.sin(rad)}
  end

  defp multiply({a, b, c, d, e, f}, {a2, b2, c2, d2, e2, f2}) do
    {a * a2 + c * b2, b * a2 + d * b2, a * c2 + c * d2, b * c2 + d * d2, a * e2 + c * f2 + e,
     b * e2 + d * f2 + f}
  end

  defp apply_x({a, _b, c, _d, e, _f}, x, y), do: a * x + c * y + e
  defp apply_y({_a, b, _c, d, _e, f}, x, y), do: b * x + d * y + f
  defp apply_point(m, {x, y}), do: {apply_x(m, x, y), apply_y(m, x, y)}

  @epsilon 1.0e-9
  defp axis_aligned({_a, b, c, _d, _e, _f}), do: abs(b) < @epsilon and abs(c) < @epsilon

  # The one scale of a matrix that scales both axes alike and may rotate, else nil.
  defp uniform({a, b, c, d, _e, _f}) do
    sx = :math.sqrt(a * a + b * b)
    sy = :math.sqrt(c * c + d * d)
    if abs(sx - sy) < @epsilon and abs(a * c + b * d) < @epsilon, do: sx
  end

  defp transformed_box(box, m),
    do: box |> corners() |> Enum.map(&apply_point(m, &1)) |> bounding() |> numbers()

  defp grow({x, y, w, h}, pad), do: {x - pad, y - pad, w + 2 * pad, h + 2 * pad}

  defp corners({x, y, w, h}), do: [{x, y}, {x + w, y}, {x, y + h}, {x + w, y + h}]

  defp bounding(points) do
    {xs, ys} = Enum.unzip(points)
    {x0, x1} = Enum.min_max(xs)
    {y0, y1} = Enum.min_max(ys)
    {x0, y0, x1 - x0, y1 - y0}
  end

  defp union(boxes) do
    boxes |> Enum.flat_map(&corners/1) |> bounding()
  end

  defp numbers({x, y, w, h}), do: numbers([x, y, w, h])
  defp numbers(list) when is_list(list), do: list

  # -- JSON -------------------------------------------------------------------------------

  defp mark_json(%{event: event, frame: frame, mark: mark, items: items}) do
    ~s({"event":#{string(event)},"frame":#{string(frame)},"mark":#{mark},"items":[) <>
      Enum.map_join(items, ",", &item_json/1) <> "]}"
  end

  defp item_json(item), do: "[" <> Enum.map_join(item, ",", &value/1) <> "]"

  defp value(n) when is_number(n), do: Path.format_number(n)
  defp value(list) when is_list(list), do: "[" <> Enum.map_join(list, ",", &value/1) <> "]"
  defp value(s) when is_binary(s), do: string(s)

  defp string(nil), do: "null"

  defp string(text) do
    escaped =
      for <<c::utf8 <- text>>, into: "" do
        case c do
          ?" -> ~S(\")
          ?\\ -> ~S(\\)
          c when c < 0x20 -> "\\u" <> String.pad_leading(Integer.to_string(c, 16), 4, "0")
          c -> <<c::utf8>>
        end
      end

    ~s(") <> escaped <> ~s(")
  end
end
