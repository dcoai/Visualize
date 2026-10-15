defmodule Visualize.IR.Paint do
  @moduledoc """
  A paint that is not one colour: the value of an element's `:fill` or `:stroke` when it is
  a gradient (spec/02 §2.1, #652, D-175).

  `id` names the definition an SVG document holds for it — the SVG backend writes
  `url(#id)` and the producer puts `definition/1` in a `:defs` — and `geometry` is in the
  units of the element's bounding box, `0` to `1` across it (SVG's `objectBoundingBox`):
  `%{x1, y1, x2, y2}` for a `:linear` gradient, the line it runs along, and `%{cx, cy, r}`
  for a `:radial` one, centred at its focus. `stops` are `{at, colour, opacity}` in `at`
  order. A canvas builds the paint over each element's tight bounding box, `bounds/1`
  (spec/09 §3.3.3).

      iex> paint = %Visualize.IR.Paint{id: "fade", type: :linear,
      ...>   geometry: %{x1: 0.5, y1: 0.0, x2: 0.5, y2: 1.0},
      ...>   stops: [{0.0, "#3b6fa8", 0.8}, {1.0, "#3b6fa8", 0.1}]}
      iex> Visualize.IR.Paint.url(paint)
      "url(#fade)"
  """

  alias Visualize.Backend.Canvas.Arc
  alias Visualize.Color
  alias Visualize.IR.{Element, Path}

  @enforce_keys [:id, :type, :geometry, :stops]
  defstruct [:id, :type, :geometry, :stops]

  @type stop :: {number(), String.t(), number()}

  @type t :: %__MODULE__{
          id: String.t(),
          type: :linear | :radial,
          geometry: %{atom() => number()},
          stops: [stop()]
        }

  @typedoc "A box `{x, y, width, height}` in an element's user units."
  @type box :: {number(), number(), number(), number()}

  @doc "What SVG writes for the paint: `url(#<id>)`."
  @spec url(t()) :: String.t()
  def url(%__MODULE__{id: id}), do: "url(##{id})"

  @doc """
  The `:linear_gradient` or `:radial_gradient` element that defines the paint under its
  id, in `objectBoundingBox` units, with one `:stop` per stop.
  """
  @spec definition(t()) :: Element.t()
  def definition(%__MODULE__{id: id, type: :linear, geometry: g} = paint) do
    id
    |> Element.linear_gradient(
      x1: g.x1,
      y1: g.y1,
      x2: g.x2,
      y2: g.y2,
      stops: stop_elements(paint)
    )
    |> Element.set_attrs(%{gradient_units: "objectBoundingBox"})
  end

  def definition(%__MODULE__{id: id, type: :radial, geometry: g} = paint) do
    id
    |> Element.radial_gradient(
      cx: g.cx,
      cy: g.cy,
      r: g.r,
      fx: g.cx,
      fy: g.cy,
      stops: stop_elements(paint)
    )
    |> Element.set_attrs(%{gradient_units: "objectBoundingBox"})
  end

  defp stop_elements(%__MODULE__{stops: stops}) do
    for {at, colour, opacity} <- stops,
        do: Element.stop("#{round(at * 100)}%", colour, opacity: opacity)
  end

  @doc false
  # The colour a canvas fills a text with: the first stop's (spec/09 §3.3.3).
  @spec first_colour(t()) :: String.t()
  def first_colour(%__MODULE__{stops: [{_at, colour, _opacity} | _]}), do: colour

  @doc false
  # A stop as RGBA bytes, its opacity multiplied into the alpha; a colour
  # `Visualize.Color.parse/1` cannot read is opaque black (spec/09 §4.6).
  @spec rgba(stop()) :: {0..255, 0..255, 0..255, 0..255}
  def rgba({_at, colour, opacity}) do
    {r, g, b, a} =
      case Color.parse(colour) do
        %Color{} = parsed -> Color.to_rgba(parsed)
        nil -> {0, 0, 0, 1.0}
      end

    {r, g, b, round(a * opacity * 255)}
  end

  @doc false
  # The stops as a canvas takes them, `[[at, "rgba(r,g,b,a)"]]` (spec/09 §3.3.3).
  @spec canvas_stops(t()) :: [[number() | String.t()]]
  def canvas_stops(%__MODULE__{stops: stops}) do
    for {at, _colour, _opacity} = stop <- stops do
      {r, g, b, a} = rgba(stop)
      [at, "rgba(#{r},#{g},#{b},#{Path.format_number(a / 255)})"]
    end
  end

  @doc false
  # A linear gradient's line in user units over `box`: the exact image of the box-unit
  # gradient, from where it is 0 to where it is 1 (spec/09 §3.3.3, D-175). The box is an
  # affine map, so the gradient stays linear; its gradient vector in user units is
  # `g = (dx / w, dy / h) / (d·d)` and the line runs from the image of its start to
  # `P₀ + g / |g|²`.
  @spec linear_line(t(), box()) :: {number(), number(), number(), number()}
  def linear_line(%__MODULE__{type: :linear, geometry: g}, {x, y, w, h}) do
    {dx, dy} = {g.x2 - g.x1, g.y2 - g.y1}
    dd = dx * dx + dy * dy
    {gx, gy} = {dx / w / dd, dy / h / dd}
    gg = gx * gx + gy * gy
    {x0, y0} = {x + g.x1 * w, y + g.y1 * h}
    {x0, y0, x0 + gx / gg, y0 + gy / gg}
  end

  # -- bounds -----------------------------------------------------------------------------

  @doc """
  The tight bounding box `{x, y, width, height}` of a shape element in its own user units:
  a path's curves and arcs by their extremes, never their control points — what SVG's
  `objectBoundingBox` is measured over. `nil` for an element that is not a shape, or a
  shape with no points.

      iex> Visualize.IR.Paint.bounds(Visualize.IR.Element.circle(10, 20, 5))
      {5, 15, 10, 10}
  """
  @spec bounds(Element.t()) :: box() | nil
  def bounds(%Element{type: :rect, attrs: %{x: x, y: y, width: w, height: h}}),
    do: {min(x, x + w), min(y, y + h), abs(w), abs(h)}

  def bounds(%Element{type: :circle, attrs: %{cx: cx, cy: cy, r: r}}),
    do: {cx - r, cy - r, 2 * r, 2 * r}

  def bounds(%Element{type: :ellipse, attrs: %{cx: cx, cy: cy, rx: rx, ry: ry}}),
    do: {cx - rx, cy - ry, 2 * rx, 2 * ry}

  def bounds(%Element{type: :line, attrs: %{x1: x1, y1: y1, x2: x2, y2: y2}}),
    do: box([{x1, y1}, {x2, y2}])

  def bounds(%Element{type: type, attrs: attrs}) when type in [:polyline, :polygon],
    do: box(Map.get(attrs, :points) || [])

  def bounds(%Element{type: :path, path: %Path{} = path}), do: path |> points() |> box()
  def bounds(%Element{}), do: nil

  defp box([]), do: nil

  defp box(points) do
    {xs, ys} = Enum.unzip(points)
    {x0, x1} = Enum.min_max(xs)
    {y0, y1} = Enum.min_max(ys)
    {x0, y0, x1 - x0, y1 - y0}
  end

  # The points that bound a path: every end point, and each curve's and arc's extremes.
  defp points(path) do
    %Path{commands: commands} = Path.absolute(path)

    {points, _} =
      Enum.flat_map_reduce(commands, {{0, 0}, {0, 0}}, fn
        {:M, x, y}, _ ->
          {[{x, y}], {{x, y}, {x, y}}}

        {:L, x, y}, {cur, start} ->
          {[cur, {x, y}], {{x, y}, start}}

        {:C, x1, y1, x2, y2, x, y}, {cur, start} ->
          {cubic(cur, {x1, y1}, {x2, y2}, {x, y}), {{x, y}, start}}

        {:Q, x1, y1, x, y}, {cur, start} ->
          {quadratic(cur, {x1, y1}, {x, y}), {{x, y}, start}}

        {:A, rx, ry, rot, large, sweep, x, y}, {cur, start} ->
          {arc(cur, {x, y}, rx, ry, rot, large, sweep), {{x, y}, start}}

        :Z, {_cur, start} ->
          {[], {start, start}}
      end)

    points
  end

  # A cubic's end points and its points where either coordinate's derivative is zero.
  defp cubic(p0, p1, p2, p3) do
    ts =
      Enum.flat_map([&elem(&1, 0), &elem(&1, 1)], fn c ->
        {a, b, d, e} = {c.(p0), c.(p1), c.(p2), c.(p3)}
        roots(3 * (-a + 3 * b - 3 * d + e), 6 * (a - 2 * b + d), 3 * (b - a))
      end)

    [p0, p3 | for(t <- ts, t > 0 and t < 1, do: bezier3(p0, p1, p2, p3, t))]
  end

  defp quadratic({x0, y0} = p0, {x1, y1} = p1, {x2, y2} = p2) do
    ts =
      for {a, b, c} <- [{x0, x1, x2}, {y0, y1, y2}],
          a - 2 * b + c != 0,
          do: (a - b) / (a - 2 * b + c)

    [p0, p2 | for(t <- ts, t > 0 and t < 1, do: bezier2(p0, p1, p2, t))]
  end

  # The real roots of `a·t² + b·t + c` (a linear one when `a` is zero).
  defp roots(a, b, c) when a == 0, do: if(b == 0, do: [], else: [-c / b])

  defp roots(a, b, c) do
    disc = b * b - 4 * a * c

    if disc < 0,
      do: [],
      else: [(-b + :math.sqrt(disc)) / (2 * a), (-b - :math.sqrt(disc)) / (2 * a)]
  end

  defp bezier3({x0, y0}, {x1, y1}, {x2, y2}, {x3, y3}, t) do
    s = 1 - t
    {a, b, c, d} = {s * s * s, 3 * s * s * t, 3 * s * t * t, t * t * t}
    {a * x0 + b * x1 + c * x2 + d * x3, a * y0 + b * y1 + c * y2 + d * y3}
  end

  defp bezier2({x0, y0}, {x1, y1}, {x2, y2}, t) do
    s = 1 - t
    {s * s * x0 + 2 * s * t * x1 + t * t * x2, s * s * y0 + 2 * s * t * y1 + t * t * y2}
  end

  # An arc by the canvas ellipse it is (`Visualize.Backend.Canvas.Arc`): its end points and
  # the angles where x or y is extreme that its sweep passes.
  defp arc(from, to, rx, ry, rot, large, sweep) do
    case Arc.to_command(from, to, rx, ry, rot, large, sweep) do
      [{:ellipse, [cx, cy, erx, ery, phi, t1, t2, _ccw]}] ->
        {lo, hi} = {min(t1, t2), max(t1, t2)}
        {cos, sin} = {:math.cos(phi), :math.sin(phi)}
        tx = :math.atan2(-ery * sin, erx * cos)
        ty = :math.atan2(ery * cos, erx * sin)

        extremes =
          for base <- [tx, tx + :math.pi(), ty, ty + :math.pi()],
              k <- -2..2,
              t = base + 2 * k * :math.pi(),
              t > lo and t < hi,
              do:
                {cx + erx * cos * :math.cos(t) - ery * sin * :math.sin(t),
                 cy + erx * sin * :math.cos(t) + ery * cos * :math.sin(t)}

        [from, to | extremes]

      _line_or_nothing ->
        [from, to]
    end
  end
end
