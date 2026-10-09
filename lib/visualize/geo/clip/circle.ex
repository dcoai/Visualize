defmodule Visualize.Geo.Clip.Circle do
  @moduledoc false
  # d3-geo's src/clip/circle.js (v3.1.1), with the `circleStream` of src/circle.js it
  # interpolates by: the clip of every projection with a `clip_angle` (spec/07 §2.2.1). A
  # line is cut where it crosses the small circle of that angular radius about the
  # projection's centre — the horizon of the orthographic — and a polygon is closed along
  # the circle, every 2°, as d3 closes it.
  #
  # Points are `{lon, lat}` in degrees in the rotated and centred frame (spec/07 §1.5), as
  # `Visualize.Geo.Clip` says; the spherical arithmetic is d3's, in radians, and an
  # intersection or an interpolated point is d3's radians turned into degrees. A vertex the
  # clip passes through is the float it was given.

  @behaviour Visualize.Geo.Clip

  import Bitwise

  alias Visualize.Geo.{Cartesian, Clip}

  @pi :math.pi()
  @tau 2 * @pi
  @radians @pi / 180
  @degrees 180 / @pi
  # math.js: d3's ε, in radians.
  @epsilon 1.0e-6
  # circle.js:9: the circle is interpolated every 2°.
  @delta 2 * @radians

  defstruct [:radius, :cr, :small_radius, :not_hemisphere]

  @type t :: %__MODULE__{
          radius: float(),
          cr: float(),
          small_radius: boolean(),
          not_hemisphere: boolean()
        }

  @doc false
  # circle.js:7–11, the radius given in degrees as `clipAngle` takes it.
  @spec new(number()) :: t()
  def new(angle) do
    radius = angle * @radians
    cr = :math.cos(radius)
    %__MODULE__{radius: radius, cr: cr, small_radius: cr > 0, not_hemisphere: abs(cr) > @epsilon}
  end

  # circle.js:17–19
  @impl true
  def visible?(%__MODULE__{cr: cr}, lon, lat),
    do: :math.cos(lon * @radians) * :math.cos(lat * @radians) > cr

  # circle.js:176: the circle's south point when it is small, else the antipode's circle's
  # point on the antimeridian.
  @impl true
  def start(%__MODULE__{small_radius: true, radius: radius}), do: {0, -radius * @degrees}
  def start(%__MODULE__{radius: radius}), do: {-180, (radius - @pi) * @degrees}

  # -- clipLine (circle.js:25–97) --

  # The state is d3's `point0`, `c0`, `v0`, `v00` and `clean`; the segments are the
  # buffer's (buffer.js), the newest first and each in reverse. A segment opens on d3's
  # `lineStart`; its `lineEnd` is the buffer's no-op.
  @impl true
  def clip_line(clipper, points) do
    state = %{point0: nil, c0: 0, v0: false, v00: false, clean: 1, lines: []}
    state = Enum.reduce(points, state, &point(clipper, &1, &2))

    # circle.js:93–95
    clean = state.clean ||| if(state.v00 and state.v0, do: 2, else: 0)
    {state.lines |> Enum.map(&Enum.reverse/1) |> Enum.reverse(), clean}
  end

  # circle.js:36–86
  defp point(clipper, point1, state) do
    {lambda, phi} = {elem(point1, 0), elem(point1, 1)}
    v = visible?(clipper, lambda, phi)

    c =
      cond do
        clipper.small_radius -> if v, do: 0, else: code(clipper, lambda, phi)
        v -> code(clipper, lambda + if(lambda < 0, do: 180, else: -180), phi)
        true -> 0
      end

    # circle.js:43: the first point opens a segment if it is visible.
    state =
      case state.point0 do
        nil ->
          state = %{state | v00: v, v0: v}
          if v, do: line_start(state), else: state

        _ ->
          state
      end

    state =
      cond do
        v != state.v0 ->
          # circle.js:49–62: in or out, the line meets the circle between the two points.
          state = %{state | clean: 0}

          {state, point2} =
            if v do
              point2 = intersect(clipper, point1, state.point0)
              {state |> line_start() |> emit(point2), point2}
            else
              point2 = intersect(clipper, state.point0, point1)
              {emit(state, {elem(point2, 0), elem(point2, 1), 2}), point2}
            end

          %{state | point0: point2}

        # circle.js:63–81: two points on the same side whose segment may still cross the
        # circle twice — two outside a small circle, two inside a large one.
        clipper.not_hemisphere and state.point0 != nil and clipper.small_radius != v ->
          case band(c, state.c0) == 0 && intersect_two(clipper, point1, state.point0) do
            {t0, t1} ->
              state = %{state | clean: 0}

              if clipper.small_radius do
                state |> line_start() |> emit(t0) |> emit(t1)
              else
                state |> emit(t1) |> line_start() |> emit({elem(t0, 0), elem(t0, 1), 3})
              end

            _ ->
              state
          end

        true ->
          state
      end

    # circle.js:82–84: a visible point, unless it repeats the point before it.
    state =
      if v and (state.point0 == nil or not point_equal?(state.point0, point1)),
        do: emit(state, {lambda, phi}),
        else: state

    %{state | point0: point1, v0: v, c0: c}
  end

  defp line_start(state), do: %{state | lines: [[] | state.lines]}

  defp emit(%{lines: [line | lines]} = state, point),
    do: %{state | lines: [[point | line] | lines]}

  # pointEqual.js, its ε restated in degrees.
  defp point_equal?(a, b) do
    eps = Clip.epsilon()
    abs(elem(a, 0) - elem(b, 0)) < eps and abs(elem(a, 1) - elem(b, 1)) < eps
  end

  # -- intersect (circle.js:99–162) --

  # The point where the great circle from `a` to `b` meets the clip circle, nearest `a`
  # along the solution of circle.js:122–133. Two polar points have no determinant and d3
  # answers `a` itself (circle.js:113). d3 is only asked this when the two points lie on
  # either side of the circle, where the discriminant is positive but for rounding; where
  # rounding takes it below zero d3 would read a property of `undefined` and throw, and
  # here it is held at zero, the tangent point.
  defp intersect(clipper, a, b) do
    case solve(clipper, a, b) do
      :polar -> {elem(a, 0), elem(a, 1)}
      {u, w, uu, t2, base} -> q(u, w, uu, -:math.sqrt(max(t2, 0.0)), base)
    end
  end

  # Both points where the great circle through `a` and `b` meets the clip circle, when the
  # first of them lies between `a` and `b` (circle.js:137–161), or `nil`.
  defp intersect_two(clipper, a, b) do
    case solve(clipper, a, b) do
      {u, w, uu, t2, base} when t2 >= 0 ->
        t = :math.sqrt(t2)
        q = q(u, w, uu, -t, base)
        if between?(a, b, q), do: {q, q(u, w, uu, t, base)}

      _ ->
        nil
    end
  end

  # circle.js:101–126: the planes n1·p = cr and n2·p = 0 meet along p(t) = A + t·u.
  defp solve(%__MODULE__{cr: cr}, a, b) do
    pa = Cartesian.cartesian({elem(a, 0) * @radians, elem(a, 1) * @radians})
    pb = Cartesian.cartesian({elem(b, 0) * @radians, elem(b, 1) * @radians})
    n1 = {1, 0, 0}
    n2 = Cartesian.cross(pa, pb)
    n2n2 = Cartesian.dot(n2, n2)
    n1n2 = elem(n2, 0)
    determinant = n2n2 - n1n2 * n1n2

    if determinant == 0 do
      :polar
    else
      c1 = cr * n2n2 / determinant
      c2 = -cr * n1n2 / determinant
      u = Cartesian.cross(n1, n2)
      base = add(scale(n1, c1), scale(n2, c2))
      w = Cartesian.dot(base, u)
      uu = Cartesian.dot(u, u)
      {u, w, uu, w * w - uu * (Cartesian.dot(base, base) - 1), base}
    end
  end

  # circle.js:130–133 and 158–159: the point at `(-w ± t) / uu` along the line, in degrees.
  defp q(u, w, uu, t, base), do: u |> scale((-w + t) / uu) |> add(base) |> spherical()

  # circle.js:138–157: whether `q` lies on the arc from `a` to `b`, in radians as d3 tests.
  defp between?(a, b, {q0, q1}) do
    {q0, q1} = {q0 * @radians, q1 * @radians}
    {lambda0, phi0} = {elem(a, 0) * @radians, elem(a, 1) * @radians}
    {lambda1, phi1} = {elem(b, 0) * @radians, elem(b, 1) * @radians}

    {lambda0, lambda1} = if lambda1 < lambda0, do: {lambda1, lambda0}, else: {lambda0, lambda1}
    delta = lambda1 - lambda0
    polar = abs(delta - @pi) < @epsilon
    meridian = polar or delta < @epsilon

    {phi0, phi1} = if not polar and phi1 < phi0, do: {phi1, phi0}, else: {phi0, phi1}

    cond do
      polar ->
        phi0 + phi1 > 0 != q1 < if(abs(q0 - lambda0) < @epsilon, do: phi0, else: phi1)

      meridian ->
        phi0 <= q1 and q1 <= phi1

      true ->
        delta > @pi != (lambda0 <= q0 and q0 <= lambda1)
    end
  end

  # circle.js:166–174: where a point lies against the circle's bounding box, 4 bits.
  defp code(%__MODULE__{small_radius: small, radius: radius}, lon, lat) do
    r = if small, do: radius, else: @pi - radius
    {lambda, phi} = {lon * @radians, lat * @radians}

    horizontal =
      cond do
        lambda < -r -> 1
        lambda > r -> 2
        true -> 0
      end

    vertical =
      cond do
        phi < -r -> 4
        phi > r -> 8
        true -> 0
      end

    horizontal ||| vertical
  end

  # -- interpolate: circleStream (circle.js:13–15; src/circle.js:7–32) --

  # The circle walked from `from` to `to` in `direction`, every 2°, or the whole circle.
  @impl true
  def interpolate(%__MODULE__{radius: radius}, from, to, direction) do
    cos_radius = :math.cos(radius)
    sin_radius = :math.sin(radius)
    step = direction * @delta

    bounds =
      if from == nil do
        {radius + direction * @tau, radius - step / 2}
      else
        with t0 when is_float(t0) <- circle_radius(cos_radius, from),
             t1 when is_float(t1) <- circle_radius(cos_radius, to) do
          if (direction > 0 and t0 < t1) or (direction < 0 and t0 > t1),
            do: {t0 + direction * @tau, t1},
            else: {t0, t1}
        end
      end

    case bounds do
      {t0, t1} -> walk(t0, t1, step, direction, cos_radius, sin_radius, [])
      # A point at the circle's centre has no angle: d3 carries NaN and draws nothing.
      nil -> []
    end
  end

  defp walk(t, t1, step, direction, cos_radius, sin_radius, acc) do
    if (direction > 0 and t > t1) or (direction < 0 and t < t1) do
      point = spherical({cos_radius, -sin_radius * :math.cos(t), -sin_radius * :math.sin(t)})
      walk(t - step, t1, step, direction, cos_radius, sin_radius, [point | acc])
    else
      Enum.reverse(acc)
    end
  end

  # src/circle.js:26–32: the signed angle of a point about the circle's axis.
  defp circle_radius(cos_radius, point) do
    {x, y, z} = Cartesian.cartesian({elem(point, 0) * @radians, elem(point, 1) * @radians})

    case Cartesian.normalize({x - cos_radius, y, z}) do
      nil ->
        nil

      {_, y, z} ->
        radius = acos(-y)
        :math.fmod(if(-z < 0, do: -radius, else: radius) + @tau - @epsilon, @tau)
    end
  end

  # -- cartesian.js and math.js --

  defp scale({x, y, z}, k), do: {x * k, y * k, z * k}
  defp add({a0, a1, a2}, {b0, b1, b2}), do: {a0 + b0, a1 + b1, a2 + b2}

  # cartesian.js:3–5, in degrees.
  defp spherical({x, y, z}), do: {:math.atan2(y, x) * @degrees, asin(z) * @degrees}

  defp acos(x) when x > 1, do: 0.0
  defp acos(x) when x < -1, do: @pi
  defp acos(x), do: :math.acos(x)

  defp asin(x) when x > 1, do: @pi / 2
  defp asin(x) when x < -1, do: -@pi / 2
  defp asin(x), do: :math.asin(x)
end
