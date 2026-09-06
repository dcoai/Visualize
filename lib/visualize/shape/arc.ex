defmodule Visualize.Shape.Arc do
  @moduledoc """
  Arc generator for creating circular or annular sectors.

  Used for pie charts, donut charts, and radial visualizations. The geometry is d3-shape's
  `arc`: `pad_angle` narrows the sector at `pad_radius`, and `corner_radius` rounds its four
  corners with tangent arcs.

  ## Examples

      arc = Visualize.Shape.Arc.new()
        |> Visualize.Shape.Arc.inner_radius(50)
        |> Visualize.Shape.Arc.outer_radius(100)
        |> Visualize.Shape.Arc.corner_radius(8)

      # Generate from angles
      path_data = Visualize.Shape.Arc.generate(arc, %{
        start_angle: 0,
        end_angle: :math.pi() / 2
      })

  """

  alias Visualize.IR.Path

  defstruct inner_radius: 0,
            outer_radius: nil,
            corner_radius: 0,
            start_angle: nil,
            end_angle: nil,
            pad_angle: 0,
            pad_radius: nil

  @type accessor :: (any() -> number()) | number()
  @type t :: %__MODULE__{
          inner_radius: accessor(),
          outer_radius: accessor() | nil,
          corner_radius: accessor(),
          start_angle: accessor() | nil,
          end_angle: accessor() | nil,
          pad_angle: accessor(),
          pad_radius: accessor() | nil
        }

  @pi :math.pi()
  @half_pi :math.pi() / 2
  @tau 2 * :math.pi()
  # d3-shape's tolerance for the sector geometry.
  @epsilon 1.0e-12
  # d3-path's tolerance for "the pen is already there" and "this arc is a full circle".
  @path_epsilon 1.0e-6

  @doc "Creates a new arc generator"
  @spec new() :: t()
  def new do
    %__MODULE__{
      outer_radius: 100,
      start_angle: fn d -> Map.get(d, :start_angle, 0) end,
      end_angle: fn d -> Map.get(d, :end_angle, @tau) end
    }
  end

  @doc "Sets the inner radius"
  @spec inner_radius(t(), accessor()) :: t()
  def inner_radius(%__MODULE__{} = arc, radius) do
    %{arc | inner_radius: normalize_accessor(radius)}
  end

  @doc "Sets the outer radius"
  @spec outer_radius(t(), accessor()) :: t()
  def outer_radius(%__MODULE__{} = arc, radius) do
    %{arc | outer_radius: normalize_accessor(radius)}
  end

  @doc "Sets the corner radius; applied up to half the ring thickness"
  @spec corner_radius(t(), accessor()) :: t()
  def corner_radius(%__MODULE__{} = arc, radius) do
    %{arc | corner_radius: normalize_accessor(radius)}
  end

  @doc "Sets the start angle accessor"
  @spec start_angle(t(), accessor()) :: t()
  def start_angle(%__MODULE__{} = arc, angle) do
    %{arc | start_angle: normalize_accessor(angle)}
  end

  @doc "Sets the end angle accessor"
  @spec end_angle(t(), accessor()) :: t()
  def end_angle(%__MODULE__{} = arc, angle) do
    %{arc | end_angle: normalize_accessor(angle)}
  end

  @doc "Sets the pad angle: the sector is narrowed by half of it on each side"
  @spec pad_angle(t(), accessor()) :: t()
  def pad_angle(%__MODULE__{} = arc, angle) do
    %{arc | pad_angle: normalize_accessor(angle)}
  end

  @doc """
  Sets the radius at which the pad angle is measured.

  The linear gap the padding opens is `pad_radius · pad_angle`, kept constant across the
  ring, so the angular shift is larger on the inner edge than on the outer. `nil` (the
  default) uses `√(r0² + r1²)`, as d3 does.
  """
  @spec pad_radius(t(), accessor() | nil) :: t()
  def pad_radius(%__MODULE__{} = arc, nil), do: %{arc | pad_radius: nil}

  def pad_radius(%__MODULE__{} = arc, radius) do
    %{arc | pad_radius: normalize_accessor(radius)}
  end

  @doc """
  Generates the SVG path data string.

  Note: For backend-agnostic usage, prefer `generate_path/2`
  and render with your chosen backend.
  """
  @spec generate(t(), map() | any()) :: String.t()
  def generate(%__MODULE__{} = arc, data) do
    arc
    |> generate_path(data)
    |> Visualize.Backend.SVG.path_data()
  end

  @doc "Generates a Path struct"
  @spec generate_path(t(), map() | any()) :: Path.t()
  def generate_path(%__MODULE__{} = arc, data) do
    r0 = apply_accessor(arc.inner_radius, data)
    r1 = apply_accessor(arc.outer_radius, data)
    a0 = apply_accessor(arc.start_angle, data) - @half_pi
    a1 = apply_accessor(arc.end_angle, data) - @half_pi
    da = abs(a1 - a0)
    cw = a1 > a0

    # The outer radius is the larger one whichever way the caller named them.
    {r0, r1} = if r1 < r0, do: {r1, r0}, else: {r0, r1}

    cond do
      # Nothing to draw: no outer radius, or no angular extent.
      r1 <= @epsilon or da <= @epsilon ->
        Path.new()

      # Full circle or annulus.
      da > @tau - @epsilon ->
        Path.new()
        |> Path.move_to(r1 * :math.cos(a0), r1 * :math.sin(a0))
        |> arc(0, 0, r1, a0, a1, not cw)
        |> inner_ring(r0, a0, a1, cw)
        |> Path.close()

      true ->
        sector(arc, data, r0, r1, a0, a1, da, cw)
    end
  end

  @doc "Generates a centroid point for the arc"
  @spec centroid(t(), map() | any()) :: {number(), number()}
  def centroid(%__MODULE__{} = arc, data) do
    r0 = apply_accessor(arc.inner_radius, data)
    r1 = apply_accessor(arc.outer_radius, data)
    a0 = apply_accessor(arc.start_angle, data) - @half_pi
    a1 = apply_accessor(arc.end_angle, data) - @half_pi

    r = (r0 + r1) / 2
    a = (a0 + a1) / 2

    {r * :math.cos(a), r * :math.sin(a)}
  end

  defp inner_ring(path, r0, a0, a1, cw) when r0 > @epsilon do
    path
    |> Path.move_to(r0 * :math.cos(a1), r0 * :math.sin(a1))
    |> arc(0, 0, r0, a1, a0, cw)
  end

  defp inner_ring(path, _r0, _a0, _a1, _cw), do: path

  # d3-shape's sector branch. The suffixes follow d3: `a01`/`a11` are the outer ring's
  # start and end after padding, `a00`/`a10` the inner ring's; `x01,y01` is the outer start,
  # `x11,y11` the outer end, `x10,y10` the inner end, `x00,y00` the inner start.
  defp sector(arc, data, r0, r1, a0, a1, da, cw) do
    ap = apply_accessor(arc.pad_angle, data) / 2
    rp = pad_radius_for(arc, data, ap, r0, r1)
    rc = min(abs(r1 - r0) / 2, apply_accessor(arc.corner_radius, data))

    {a00, a10, da0} = padded(a0, a1, da, rp, r0, ap, cw)
    {a01, a11, da1} = padded(a0, a1, da, rp, r1, ap, cw)

    {x01, y01} = polar(r1, a01)
    {x11, y11} = polar(r1, a11)
    {x00, y00} = polar(r0, a00)
    {x10, y10} = polar(r0, a10)

    {rc0, rc1} = restrict_corners(rc, da, r0, r1, {x01, y01}, {x00, y00}, {x11, y11}, {x10, y10})

    Path.new()
    |> outer_edge(da1, rc, rc1, cw, r1, {x00, y00}, {x01, y01}, {x11, y11}, {x10, y10}, a01, a11)
    |> inner_edge(r0, da0, rc, rc0, cw, {x00, y00}, {x01, y01}, {x11, y11}, {x10, y10}, a00, a10)
    |> Path.close()
  end

  defp pad_radius_for(_arc, _data, ap, _r0, _r1) when ap <= @epsilon, do: 0

  defp pad_radius_for(%{pad_radius: nil}, _data, _ap, r0, r1), do: :math.sqrt(r0 * r0 + r1 * r1)
  defp pad_radius_for(%{pad_radius: rp}, data, _ap, _r0, _r1), do: apply_accessor(rp, data)

  # One ring's angles after padding: each end moves inward by `asin(rp / r · sin(ap))`, and
  # a ring the pad would swallow collapses to the sector's mid-angle. d3 reaches the collapse
  # through NaN (`rp / 0`, `asin(> 1)`); here those are explicit.
  defp padded(a0, a1, da, rp, _r, _ap, _cw) when rp <= @epsilon, do: {a0, a1, da}

  defp padded(a0, a1, da, rp, r, ap, cw) do
    s = if r > @epsilon, do: rp / r * :math.sin(ap), else: nil

    p = if s != nil and s <= 1, do: :math.asin(s), else: nil

    if p != nil and da - p * 2 > @epsilon do
      p = if cw, do: p, else: -p
      {a0 + p, a1 - p, da - p * 2}
    else
      mid = (a0 + a1) / 2
      {mid, mid, 0}
    end
  end

  # d3 limits the corner radius by the sector's own geometry when it spans less than a
  # half-turn: the corners must not cross the line through the sector's corners' intersection.
  defp restrict_corners(rc, _da, _r0, _r1, _p01, _p00, _p11, _p10) when rc <= @epsilon,
    do: {rc, rc}

  defp restrict_corners(rc, da, _r0, _r1, _p01, _p00, _p11, _p10) when da >= @pi, do: {rc, rc}

  defp restrict_corners(rc, _da, r0, r1, {x01, y01}, {x00, y00}, {x11, y11}, {x10, y10}) do
    case intersect(x01, y01, x00, y00, x11, y11, x10, y10) do
      nil ->
        {0, 0}

      {ocx, ocy} ->
        ax = x01 - ocx
        ay = y01 - ocy
        bx = x11 - ocx
        by = y11 - ocy

        cos_theta =
          (ax * bx + ay * by) /
            (:math.sqrt(ax * ax + ay * ay) * :math.sqrt(bx * bx + by * by))

        kc = 1 / :math.sin(:math.acos(clamp_unit(cos_theta)) / 2)
        lc = :math.sqrt(ocx * ocx + ocy * ocy)
        {min(rc, (r0 - lc) / (kc - 1)), min(rc, (r1 - lc) / (kc + 1))}
    end
  end

  defp clamp_unit(v), do: v |> max(-1.0) |> min(1.0)

  defp outer_edge(path, da1, _rc, _rc1, _cw, _r1, _p00, {x01, y01}, _p11, _p10, _a01, _a11)
       when da1 <= @epsilon do
    # The sector is collapsed to a line.
    Path.move_to(path, x01, y01)
  end

  defp outer_edge(
         path,
         _da1,
         rc,
         rc1,
         cw,
         r1,
         {x00, y00},
         {x01, y01},
         {x11, y11},
         {x10, y10},
         _,
         _
       )
       when rc1 > @epsilon do
    t0 = corner_tangents(x00, y00, x01, y01, r1, rc1, cw)
    t1 = corner_tangents(x11, y11, x10, y10, r1, rc1, cw)

    path = Path.move_to(path, t0.cx + t0.x01, t0.cy + t0.y01)

    if rc1 < rc do
      # The two corners have merged into one arc.
      arc(path, t0.cx, t0.cy, rc1, atan2(t0.y01, t0.x01), atan2(t1.y01, t1.x01), not cw)
    else
      path
      |> arc(t0.cx, t0.cy, rc1, atan2(t0.y01, t0.x01), atan2(t0.y11, t0.x11), not cw)
      |> arc(
        0,
        0,
        r1,
        atan2(t0.cy + t0.y11, t0.cx + t0.x11),
        atan2(t1.cy + t1.y11, t1.cx + t1.x11),
        not cw
      )
      |> arc(t1.cx, t1.cy, rc1, atan2(t1.y11, t1.x11), atan2(t1.y01, t1.x01), not cw)
    end
  end

  defp outer_edge(path, _da1, _rc, _rc1, cw, r1, _p00, {x01, y01}, _p11, _p10, a01, a11) do
    path |> Path.move_to(x01, y01) |> arc(0, 0, r1, a01, a11, not cw)
  end

  defp inner_edge(path, r0, da0, _rc, _rc0, _cw, _p00, _p01, _p11, {x10, y10}, _a00, _a10)
       when r0 <= @epsilon or da0 <= @epsilon do
    # No inner ring (a circular sector), or an annular sector collapsed by padding.
    Path.line_to(path, x10, y10)
  end

  defp inner_edge(
         path,
         r0,
         _da0,
         rc,
         rc0,
         cw,
         {x00, y00},
         {x01, y01},
         {x11, y11},
         {x10, y10},
         _,
         _
       )
       when rc0 > @epsilon do
    t0 = corner_tangents(x10, y10, x11, y11, r0, -rc0, cw)
    t1 = corner_tangents(x01, y01, x00, y00, r0, -rc0, cw)

    path = Path.line_to(path, t0.cx + t0.x01, t0.cy + t0.y01)

    if rc0 < rc do
      arc(path, t0.cx, t0.cy, rc0, atan2(t0.y01, t0.x01), atan2(t1.y01, t1.x01), not cw)
    else
      path
      |> arc(t0.cx, t0.cy, rc0, atan2(t0.y01, t0.x01), atan2(t0.y11, t0.x11), not cw)
      |> arc(
        0,
        0,
        r0,
        atan2(t0.cy + t0.y11, t0.cx + t0.x11),
        atan2(t1.cy + t1.y11, t1.cx + t1.x11),
        cw
      )
      |> arc(t1.cx, t1.cy, rc0, atan2(t1.y11, t1.x11), atan2(t1.y01, t1.x01), not cw)
    end
  end

  defp inner_edge(path, r0, _da0, _rc, _rc0, cw, _p00, _p01, _p11, _p10, a00, a10) do
    arc(path, 0, 0, r0, a10, a00, cw)
  end

  # d3-shape's `intersect`: where the lines (p0, p1) and (p2, p3) cross, or nil when parallel.
  defp intersect(x0, y0, x1, y1, x2, y2, x3, y3) do
    x10 = x1 - x0
    y10 = y1 - y0
    x32 = x3 - x2
    y32 = y3 - y2
    t = y32 * x10 - x32 * y10

    if t * t < @epsilon do
      nil
    else
      t = (x32 * (y0 - y2) - y32 * (x0 - x2)) / t
      {x0 + t * x10, y0 + t * y10}
    end
  end

  # d3-shape's `cornerTangents`: the centre of the corner circle of radius `rc` tangent to
  # the ring of radius `r1` and to the sector edge from (x0, y0) to (x1, y1), with the two
  # tangent points expressed as offsets from that centre (`x01,y01` on the edge, `x11,y11`
  # on the ring).
  defp corner_tangents(x0, y0, x1, y1, r1, rc, cw) do
    x01 = x0 - x1
    y01 = y0 - y1
    lo = if(cw, do: rc, else: -rc) / :math.sqrt(x01 * x01 + y01 * y01)
    ox = lo * y01
    oy = -lo * x01
    x11 = x0 + ox
    y11 = y0 + oy
    x10 = x1 + ox
    y10 = y1 + oy
    x00 = (x11 + x10) / 2
    y00 = (y11 + y10) / 2
    dx = x10 - x11
    dy = y10 - y11
    d2 = dx * dx + dy * dy
    r = r1 - rc
    dd = x11 * y10 - x10 * y11
    d = if(dy < 0, do: -1, else: 1) * :math.sqrt(max(0, r * r * d2 - dd * dd))
    cx0 = (dd * dy - dx * d) / d2
    cy0 = (-dd * dx - dy * d) / d2
    cx1 = (dd * dy + dx * d) / d2
    cy1 = (-dd * dx + dy * d) / d2
    dx0 = cx0 - x00
    dy0 = cy0 - y00
    dx1 = cx1 - x00
    dy1 = cy1 - y00

    # Pick the closer of the two intersection points.
    {cx, cy} =
      if dx0 * dx0 + dy0 * dy0 > dx1 * dx1 + dy1 * dy1, do: {cx1, cy1}, else: {cx0, cy0}

    %{cx: cx, cy: cy, x01: -ox, y01: -oy, x11: cx * (r1 / r - 1), y11: cy * (r1 / r - 1)}
  end

  # d3-path's `arc`: a line to the arc's start when the pen is elsewhere, then one `A` (or
  # two for a full circle) to its end. `ccw?` is the drawing direction; the SVG sweep flag
  # is its negation.
  defp arc(path, cx, cy, r, a0, a1, ccw?) do
    dx = r * :math.cos(a0)
    dy = r * :math.sin(a0)
    x0 = cx + dx
    y0 = cy + dy
    sweep = if ccw?, do: 0, else: 1
    da = if ccw?, do: a0 - a1, else: a1 - a0

    path =
      case pen(path) do
        nil ->
          Path.move_to(path, x0, y0)

        {px, py} when abs(px - x0) > @path_epsilon or abs(py - y0) > @path_epsilon ->
          Path.line_to(path, x0, y0)

        _ ->
          path
      end

    da = if da < 0, do: :math.fmod(da, @tau) + @tau, else: da

    cond do
      r == 0 ->
        path

      da > @tau - @path_epsilon ->
        path
        |> Path.arc_to(r, r, 0, 1, sweep, cx - dx, cy - dy)
        |> Path.arc_to(r, r, 0, 1, sweep, x0, y0)

      da > @path_epsilon ->
        large = if da >= @pi, do: 1, else: 0
        Path.arc_to(path, r, r, 0, large, sweep, cx + r * :math.cos(a1), cy + r * :math.sin(a1))

      true ->
        path
    end
  end

  defp pen(%Path{commands: []}), do: nil

  defp pen(%Path{commands: commands}) do
    case List.last(commands) do
      {:M, x, y} -> {x, y}
      {:L, x, y} -> {x, y}
      {:A, _, _, _, _, _, x, y} -> {x, y}
    end
  end

  defp polar(r, a), do: {r * :math.cos(a), r * :math.sin(a)}

  defp atan2(y, x), do: :math.atan2(y, x)

  defp normalize_accessor(value) when is_function(value, 1), do: value
  defp normalize_accessor(value) when is_number(value), do: fn _ -> value end
  defp normalize_accessor(value) when is_atom(value), do: fn d -> Map.get(d, value) end

  defp apply_accessor(accessor, data) when is_function(accessor, 1), do: accessor.(data)
  defp apply_accessor(accessor, _data) when is_number(accessor), do: accessor
end
