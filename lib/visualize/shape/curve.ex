defmodule Visualize.Shape.Curve do
  @moduledoc """
  Curve interpolators for line and area generators.

  Curves define how points are connected in a path.
  """

  alias Visualize.SVG.Path

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
  def generate(:catmull_rom, points, opts), do: catmull_rom(points, Keyword.get(opts, :alpha, 0.5))
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

    rest
    |> Enum.reduce({path, x0, y0}, fn {x1, y1}, {acc, x0_prev, y0_prev} ->
      x_mid = x0_prev + (x1 - x0_prev) * t
      acc = acc
        |> Path.horizontal_to(x_mid)
        |> Path.vertical_to(y1)
        |> Path.horizontal_to(x1)
      {acc, x1, y1}
    end)
    |> elem(0)
  end

  @doc "Basis spline interpolation"
  @spec basis([point()]) :: Path.t()
  def basis(points) when length(points) < 3 do
    linear(points)
  end

  def basis([{x0, y0} | _] = points) do
    path = Path.new() |> Path.move_to(x0, y0)

    points
    |> Enum.chunk_every(4, 1, :discard)
    |> Enum.reduce(path, fn chunk, acc ->
      case chunk do
        [{x0, y0}, {x1, y1}, {x2, y2}, {x3, y3}] ->
          # Basis spline control points
          Path.curve_to(
            acc,
            (2 * x0 + x1) / 3,
            (2 * y0 + y1) / 3,
            (x0 + 2 * x1) / 3,
            (y0 + 2 * y1) / 3,
            (x0 + 4 * x1 + x2) / 6,
            (y0 + 4 * y1 + y2) / 6
          )

        _ ->
          acc
      end
    end)
    |> finalize_basis(points)
  end

  defp finalize_basis(path, points) when length(points) >= 2 do
    [{xn_1, yn_1}, {xn, yn}] = Enum.take(points, -2)

    path
    |> Path.curve_to(
      (2 * xn_1 + xn) / 3,
      (2 * yn_1 + yn) / 3,
      (xn_1 + 2 * xn) / 3,
      (yn_1 + 2 * yn) / 3,
      xn,
      yn
    )
  end

  defp finalize_basis(path, _), do: path

  @doc "Cardinal spline interpolation"
  @spec cardinal([point()], number()) :: Path.t()
  def cardinal(points, tension) when length(points) < 3 do
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
  def catmull_rom(points, alpha) when length(points) < 3 do
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
      cp1x = (t1 * t1 * x2 - t2 * t2 * x0 + (2 * t1 * t1 + 3 * t1 * t2 + t2 * t2) * x1) / (3 * t1 * (t1 + t2))
      cp1y = (t1 * t1 * y2 - t2 * t2 * y0 + (2 * t1 * t1 + 3 * t1 * t2 + t2 * t2) * y1) / (3 * t1 * (t1 + t2))
      cp2x = (t3 * t3 * x1 - t2 * t2 * x3 + (2 * t3 * t3 + 3 * t3 * t2 + t2 * t2) * x2) / (3 * t3 * (t3 + t2))
      cp2y = (t3 * t3 * y1 - t2 * t2 * y3 + (2 * t3 * t3 + 3 * t3 * t2 + t2 * t2) * y2) / (3 * t3 * (t3 + t2))

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

  @doc "Natural cubic spline interpolation"
  @spec natural([point()]) :: Path.t()
  def natural(points) when length(points) < 3 do
    linear(points)
  end

  def natural([{x0, y0} | _] = points) do
    n = length(points) - 1
    xs = Enum.map(points, &elem(&1, 0))
    ys = Enum.map(points, &elem(&1, 1))

    # Solve for the spline coefficients
    {ax, bx} = natural_spline_coefficients(xs)
    {ay, by} = natural_spline_coefficients(ys)

    path = Path.new() |> Path.move_to(x0, y0)

    0..(n - 1)
    |> Enum.reduce(path, fn i, acc ->
      x1 = Enum.at(xs, i)
      x2 = Enum.at(xs, i + 1)
      y1 = Enum.at(ys, i)
      y2 = Enum.at(ys, i + 1)

      Path.curve_to(
        acc,
        x1 + Enum.at(ax, i),
        y1 + Enum.at(ay, i),
        x2 - Enum.at(bx, i),
        y2 - Enum.at(by, i),
        x2,
        y2
      )
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
             3 * (m0 + m1) / (2 / m0 + 1 / m1 + 2 / m0 + 1 / m1)
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

  # Natural spline coefficient calculation
  defp natural_spline_coefficients(values) do
    n = length(values) - 1

    if n < 2 do
      {List.duplicate(0, n), List.duplicate(0, n)}
    else
      # Calculate differences
      deltas =
        values
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.map(fn [v0, v1] -> v1 - v0 end)

      # Solve tridiagonal system for second derivatives
      # Simplified: use finite differences
      a = Enum.map(deltas, fn d -> d / 3 end)
      b = Enum.map(deltas, fn d -> d / 3 end)

      {a, b}
    end
  end

  # Add phantom points for spline calculations
  defp add_phantom_points([first | _] = points) do
    last = List.last(points)
    [first] ++ points ++ [last]
  end
end
