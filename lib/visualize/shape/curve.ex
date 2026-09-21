defmodule Visualize.Shape.Curve do
  @moduledoc """
  Curve interpolators for line and area generators.

  Curves define how points are connected in a path.
  """

  alias Visualize.IR.Path

  @type point :: {number(), number()}
  @type curve_type ::
          :linear
          | :step
          | :step_before
          | :step_after
          | :basis
          | :cardinal
          | :catmull_rom
          | :monotone_x
          | :monotone_y
          | :natural
          | :cardinal_closed
          | :basis_closed

  @doc """
  Generates path commands for a list of points using the specified curve type.
  """
  @spec generate(curve_type(), [point()], keyword()) :: Path.t()
  def generate(curve_type, points, opts \\ [])

  def generate(_curve_type, [], _opts), do: Path.new()
  def generate(_curve_type, [_], _opts), do: Path.new()

  def generate(:linear, points, _opts), do: linear(points)
  def generate(:step, points, _opts), do: step(points, 0.5)
  def generate(:step_before, points, _opts), do: step(points, 0)
  def generate(:step_after, points, _opts), do: step(points, 1)
  def generate(:basis, points, _opts), do: basis(points)
  def generate(:cardinal, points, opts), do: cardinal(points, Keyword.get(opts, :tension, 0))

  def generate(:catmull_rom, points, opts),
    do: catmull_rom(points, Keyword.get(opts, :alpha, 0.5))

  def generate(:basis_closed, points, _opts), do: basis_closed(points)

  def generate(:cardinal_closed, points, opts),
    do: cardinal_closed(points, Keyword.get(opts, :tension, 0))

  def generate(:monotone_x, points, _opts), do: monotone_x(points)
  def generate(:monotone_y, points, _opts), do: monotone_y(points)
  def generate(:natural, points, _opts), do: natural(points)

  @doc "Linear interpolation - straight lines between points"
  @spec linear([point()]) :: Path.t()
  def linear([{x0, y0} | rest]) do
    path = Path.new() |> Path.move_to(x0, y0)

    Enum.reduce(rest, path, fn {x, y}, acc ->
      Path.line_to(acc, x, y)
    end)
  end

  @doc "Step interpolation with configurable step position"
  @spec step([point()], number()) :: Path.t()
  def step([{x0, y0} | rest], t) do
    path = Path.new() |> Path.move_to(x0, y0)

    # `x_pen` is where the pen sits horizontally; `x_prev` is the previous data point.
    # Consecutive horizontals merge, so a step path never carries a zero-length or
    # redundant segment (the same output D3 produces).
    {path, x_pen, x_last} =
      Enum.reduce(rest, {path, x0, x0}, fn {x1, y1}, {acc, x_pen, x_prev} ->
        x_mid = x_prev + (x1 - x_prev) * t

        acc =
          acc
          |> horizontal_unless_same(x_pen, x_mid)
          |> Path.vertical_to(y1)

        {acc, x_mid, x1}
      end)

    horizontal_unless_same(path, x_pen, x_last)
  end

  defp horizontal_unless_same(path, from, to) when from == to, do: path
  defp horizontal_unless_same(path, _from, to), do: Path.horizontal_to(path, to)

  @doc "Basis spline interpolation"
  @spec basis([point()]) :: Path.t()
  def basis(points) when length(points) < 3 do
    linear(points)
  end

  # d3-shape's curveBasis: a uniform cubic B-spline with the endpoints interpolated. `M p0`,
  # `L (5p0 + p1)/6`, one `C` per point from the third on, a closing `C` to
  # `(p[n-2] + 5p[n-1])/6`, then `L p[n-1]` — n − 1 curves for n points (D-33).
  def basis([{x0, y0}, {x1, y1} | _] = points) do
    path =
      Path.new() |> Path.move_to(x0, y0) |> Path.line_to((5 * x0 + x1) / 6, (5 * y0 + y1) / 6)

    path =
      points
      |> Enum.chunk_every(3, 1, :discard)
      |> Enum.reduce(path, fn [{ax, ay}, {bx, by}, {cx, cy}], acc ->
        Path.curve_to(
          acc,
          (2 * ax + bx) / 3,
          (2 * ay + by) / 3,
          (ax + 2 * bx) / 3,
          (ay + 2 * by) / 3,
          (ax + 4 * bx + cx) / 6,
          (ay + 4 * by + cy) / 6
        )
      end)

    [{px, py}, {qx, qy}] = Enum.take(points, -2)

    path
    |> Path.curve_to(
      (2 * px + qx) / 3,
      (2 * py + qy) / 3,
      (px + 2 * qx) / 3,
      (py + 2 * qy) / 3,
      (px + 5 * qx) / 6,
      (py + 5 * qy) / 6
    )
    |> Path.line_to(qx, qy)
  end

  @doc "The B-spline as a closed loop (spec/04 §5.3, #393): d3-shape's curveBasisClosed"
  @spec basis_closed([point()]) :: Path.t()
  def basis_closed(points) when length(points) < 3, do: points |> linear() |> Path.close()

  def basis_closed(points) do
    n = length(points)
    at = fn i -> Enum.at(points, Integer.mod(i, n)) end
    {sx, sy} = knot(at.(n - 2), at.(n - 1), at.(0))
    path = Path.new() |> Path.move_to(sx, sy)

    0..(n - 1)
    |> Enum.reduce(path, fn i, acc ->
      {ax, ay} = at.(i - 1)
      {bx, by} = at.(i)
      {kx, ky} = knot(at.(i - 1), at.(i), at.(i + 1))

      Path.curve_to(
        acc,
        (2 * ax + bx) / 3,
        (2 * ay + by) / 3,
        (ax + 2 * bx) / 3,
        (ay + 2 * by) / 3,
        kx,
        ky
      )
    end)
    |> Path.close()
  end

  # The B-spline's knot between three control points.
  defp knot({ax, ay}, {bx, by}, {cx, cy}), do: {(ax + 4 * bx + cx) / 6, (ay + 4 * by + cy) / 6}

  @doc "The cardinal spline as a closed loop (spec/04 §5.3, #393): d3-shape's curveCardinalClosed"
  @spec cardinal_closed([point()], number()) :: Path.t()
  def cardinal_closed(points, _tension) when length(points) < 3,
    do: points |> linear() |> Path.close()

  def cardinal_closed([{x0, y0} | _] = points, tension) do
    k = (1 - tension) / 6
    n = length(points)
    at = fn i -> Enum.at(points, Integer.mod(i, n)) end
    path = Path.new() |> Path.move_to(x0, y0)

    0..(n - 1)
    |> Enum.reduce(path, fn i, acc ->
      {x0, y0} = at.(i - 1)
      {x1, y1} = at.(i)
      {x2, y2} = at.(i + 1)
      {x3, y3} = at.(i + 2)

      Path.curve_to(
        acc,
        x1 + k * (x2 - x0),
        y1 + k * (y2 - y0),
        x2 + k * (x1 - x3),
        y2 + k * (y1 - y3),
        x2,
        y2
      )
    end)
    |> Path.close()
  end

  @doc "Cardinal spline interpolation"
  @spec cardinal([point()], number()) :: Path.t()
  def cardinal(points, _tension) when length(points) < 3 do
    linear(points)
  end

  def cardinal([{x0, y0} | _] = points, tension) do
    k = (1 - tension) / 6
    path = Path.new() |> Path.move_to(x0, y0)

    points
    |> add_phantom_points()
    |> Enum.chunk_every(4, 1, :discard)
    |> Enum.reduce(path, fn [{x0, y0}, {x1, y1}, {x2, y2}, {x3, y3}], acc ->
      Path.curve_to(
        acc,
        x1 + k * (x2 - x0),
        y1 + k * (y2 - y0),
        x2 + k * (x1 - x3),
        y2 + k * (y1 - y3),
        x2,
        y2
      )
    end)
  end

  @doc "Catmull-Rom spline interpolation"
  @spec catmull_rom([point()], number()) :: Path.t()
  def catmull_rom(points, _alpha) when length(points) < 3 do
    linear(points)
  end

  def catmull_rom([{x0, y0} | _] = points, alpha) do
    path = Path.new() |> Path.move_to(x0, y0)

    points
    |> add_phantom_points()
    |> Enum.chunk_every(4, 1, :discard)
    |> Enum.reduce(path, fn [{x0, y0}, {x1, y1}, {x2, y2}, {x3, y3}], acc ->
      # Compute distances
      d1 = :math.sqrt(:math.pow(x1 - x0, 2) + :math.pow(y1 - y0, 2))
      d2 = :math.sqrt(:math.pow(x2 - x1, 2) + :math.pow(y2 - y1, 2))
      d3 = :math.sqrt(:math.pow(x3 - x2, 2) + :math.pow(y3 - y2, 2))

      # Avoid division by zero
      d1 = max(d1, 0.0001)
      d2 = max(d2, 0.0001)
      d3 = max(d3, 0.0001)

      # Parameterized distances
      t1 = :math.pow(d1, alpha)
      t2 = :math.pow(d2, alpha)
      t3 = :math.pow(d3, alpha)

      # Control points
      cp1x =
        (t1 * t1 * x2 - t2 * t2 * x0 + (2 * t1 * t1 + 3 * t1 * t2 + t2 * t2) * x1) /
          (3 * t1 * (t1 + t2))

      cp1y =
        (t1 * t1 * y2 - t2 * t2 * y0 + (2 * t1 * t1 + 3 * t1 * t2 + t2 * t2) * y1) /
          (3 * t1 * (t1 + t2))

      cp2x =
        (t3 * t3 * x1 - t2 * t2 * x3 + (2 * t3 * t3 + 3 * t3 * t2 + t2 * t2) * x2) /
          (3 * t3 * (t3 + t2))

      cp2y =
        (t3 * t3 * y1 - t2 * t2 * y3 + (2 * t3 * t3 + 3 * t3 * t2 + t2 * t2) * y2) /
          (3 * t3 * (t3 + t2))

      Path.curve_to(acc, cp1x, cp1y, cp2x, cp2y, x2, y2)
    end)
  end

  @doc "Monotone interpolation in x (preserves monotonicity)"
  @spec monotone_x([point()]) :: Path.t()
  def monotone_x(points) when length(points) < 3 do
    linear(points)
  end

  def monotone_x([{x0, y0} | _] = points) do
    path = Path.new() |> Path.move_to(x0, y0)

    # Calculate tangents
    tangents = monotone_tangents(points, :x)

    points
    |> Enum.zip(tangents)
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.reduce(path, fn [{{x0, y0}, t0}, {{x1, y1}, t1}], acc ->
      dx = x1 - x0

      Path.curve_to(
        acc,
        x0 + dx / 3,
        y0 + t0 * dx / 3,
        x1 - dx / 3,
        y1 - t1 * dx / 3,
        x1,
        y1
      )
    end)
  end

  @doc "Monotone interpolation in y (preserves monotonicity)"
  @spec monotone_y([point()]) :: Path.t()
  def monotone_y(points) when length(points) < 3 do
    linear(points)
  end

  def monotone_y(points) do
    # Swap x and y, apply monotone_x, then swap back in the path
    swapped = Enum.map(points, fn {x, y} -> {y, x} end)
    monotone_x_swapped(swapped)
  end

  defp monotone_x_swapped([{x0, y0} | _] = points) do
    path = Path.new() |> Path.move_to(y0, x0)

    tangents = monotone_tangents(points, :x)

    points
    |> Enum.zip(tangents)
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.reduce(path, fn [{{x0, y0}, t0}, {{x1, y1}, t1}], acc ->
      dx = x1 - x0
      # Swap coordinates in the curve
      Path.curve_to(
        acc,
        y0 + t0 * dx / 3,
        x0 + dx / 3,
        y1 - t1 * dx / 3,
        x1 - dx / 3,
        y1,
        x1
      )
    end)
  end

  @doc """
  Natural cubic spline interpolation.

  The spline through every point with zero second derivative at both ends, as d3-shape's
  `curveNatural`. The Bézier control points come from the tridiagonal system solved by
  `control_points/1`, once for the x coordinates and once for the y coordinates.
  """
  @spec natural([point()]) :: Path.t()
  def natural(points) when length(points) < 3 do
    linear(points)
  end

  def natural([{x0, y0} | rest] = points) do
    {ax, bx} = points |> Enum.map(&elem(&1, 0)) |> control_points()
    {ay, by} = points |> Enum.map(&elem(&1, 1)) |> control_points()

    path = Path.new() |> Path.move_to(x0, y0)

    [rest, ax, ay, bx, by]
    |> Enum.zip()
    |> Enum.reduce(path, fn {{x, y}, cx1, cy1, cx2, cy2}, acc ->
      Path.curve_to(acc, cx1, cy1, cx2, cy2, x, y)
    end)
  end

  # Helper to calculate monotone tangents
  defp monotone_tangents(points, _axis) do
    n = length(points)

    # Calculate slopes between consecutive points
    slopes =
      points
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [{x0, y0}, {x1, y1}] ->
        dx = x1 - x0
        if dx == 0, do: 0, else: (y1 - y0) / dx
      end)

    # Calculate tangents using Fritsch-Carlson method
    tangents =
      [hd(slopes)] ++
        (slopes
         |> Enum.chunk_every(2, 1, :discard)
         |> Enum.map(fn [m0, m1] ->
           if m0 * m1 <= 0 do
             0
           else
             # Harmonic mean of slopes for smooth monotone interpolation
             2 * m0 * m1 / (m0 + m1)
           end
         end)) ++
        [List.last(slopes)]

    # Ensure monotonicity
    Enum.zip([slopes ++ [0], tangents])
    |> Enum.map(fn {s, t} ->
      if s == 0 do
        0
      else
        alpha = t / s
        if alpha < 0, do: 0, else: min(3, alpha) * s
      end
    end)
    |> Enum.take(n)
  end

  # d3-shape's `controlPoints`: the first and second Bézier control coordinates of every
  # segment of the natural spline through `values`, from the tridiagonal system
  #
  #     2·p0 + p1          = v0 + 2·v1
  #     p(i−1) + 4·pi + p(i+1) = 4·vi + 2·v(i+1)        0 < i < n−1
  #     2·p(n−2) + 7·p(n−1) = 8·v(n−1) + vn
  #
  # solved by the Thomas algorithm (forward elimination, back substitution). The second
  # control coordinate of segment i is `2·v(i+1) − p(i+1)`, and of the last segment
  # `(vn + p(n−1)) / 2`.
  defp control_points(values) do
    n = length(values) - 1
    v = List.to_tuple(values)

    {sub, diag, rhs} =
      Enum.reduce(0..(n - 1)//1, {[], [], []}, fn i, {a, b, r} ->
        {ai, bi, ri} =
          cond do
            i == 0 -> {0, 2, elem(v, 0) + 2 * elem(v, 1)}
            i == n - 1 -> {2, 7, 8 * elem(v, n - 1) + elem(v, n)}
            true -> {1, 4, 4 * elem(v, i) + 2 * elem(v, i + 1)}
          end

        {[ai | a], [bi | b], [ri | r]}
      end)

    sub = Enum.reverse(sub)
    diag = Enum.reverse(diag)
    rhs = Enum.reverse(rhs)

    # Forward elimination: each row absorbs a multiple of the one above it.
    {diag, rhs} =
      Enum.zip([tl(sub), tl(diag), tl(rhs)])
      |> Enum.reduce({[hd(diag)], [hd(rhs)]}, fn {ai, bi, ri},
                                                 {[b_prev | _] = bs, [r_prev | _] = rs} ->
        m = ai / b_prev
        {[bi - m | bs], [ri - m * r_prev | rs]}
      end)

    # Back substitution, walking the reversed (last-row-first) lists.
    [b_last | diag_rest] = diag
    [r_last | rhs_rest] = rhs
    p_last = r_last / b_last

    first =
      Enum.zip(diag_rest, rhs_rest)
      |> Enum.reduce([p_last], fn {bi, ri}, [p_next | _] = ps ->
        [(ri - p_next) / bi | ps]
      end)

    second =
      first
      |> Enum.with_index()
      |> Enum.map(fn
        {p, i} when i == n - 1 -> (elem(v, n) + p) / 2
        {_p, i} -> 2 * elem(v, i + 1) - Enum.at(first, i + 1)
      end)

    {first, second}
  end

  # Add phantom points for spline calculations
  defp add_phantom_points([first | _] = points) do
    last = List.last(points)
    [first] ++ points ++ [last]
  end
end
