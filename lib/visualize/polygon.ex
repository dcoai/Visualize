defmodule Visualize.Polygon do
  @moduledoc """
  Utilities for working with polygons.

  Provides functions for computing polygon properties like area,
  centroid, perimeter, and convex hull.

  ## Examples

      polygon = [{0, 0}, {100, 0}, {100, 100}, {0, 100}]

      Visualize.Polygon.area(polygon)      # => 10000.0
      Visualize.Polygon.centroid(polygon)  # => {50.0, 50.0}
      Visualize.Polygon.perimeter(polygon) # => 400.0

      # Convex hull of scattered points
      points = [{0, 0}, {50, 50}, {100, 0}, {100, 100}, {0, 100}]
      Visualize.Polygon.hull(points)  # => [{0, 0}, {100, 0}, {100, 100}, {0, 100}]

  """

  @type point :: {number(), number()}
  @type polygon :: [point()]

  @doc """
  Computes the signed area of a polygon.

  Returns a positive value for counter-clockwise polygons,
  negative for clockwise. Use `abs/1` if you need the absolute area.

  Uses the shoelace formula.
  """
  @spec area(polygon()) :: float()
  def area([]), do: 0.0
  def area([_]), do: 0.0
  def area([_, _]), do: 0.0

  def area(polygon) do
    n = length(polygon)

    sum =
      0..(n - 1)
      |> Enum.reduce(0, fn i, acc ->
        {x0, y0} = Enum.at(polygon, i)
        {x1, y1} = Enum.at(polygon, rem(i + 1, n))
        acc + (x0 * y1 - x1 * y0)
      end)

    sum / 2
  end

  @doc """
  Computes the centroid (center of mass) of a polygon.

  Returns the geometric center of the polygon.
  """
  @spec centroid(polygon()) :: point()
  def centroid([]), do: {0.0, 0.0}
  def centroid([point]), do: point
  def centroid([{x0, y0}, {x1, y1}]), do: {(x0 + x1) / 2, (y0 + y1) / 2}

  def centroid(polygon) do
    n = length(polygon)
    a = area(polygon)

    if abs(a) < 1.0e-10 do
      # Degenerate polygon, return average of points
      {sum_x, sum_y} = Enum.reduce(polygon, {0, 0}, fn {x, y}, {sx, sy} ->
        {sx + x, sy + y}
      end)
      {sum_x / n, sum_y / n}
    else
      {cx, cy} =
        0..(n - 1)
        |> Enum.reduce({0, 0}, fn i, {cx, cy} ->
          {x0, y0} = Enum.at(polygon, i)
          {x1, y1} = Enum.at(polygon, rem(i + 1, n))
          cross = x0 * y1 - x1 * y0
          {cx + (x0 + x1) * cross, cy + (y0 + y1) * cross}
        end)

      k = 1 / (6 * a)
      {cx * k, cy * k}
    end
  end

  @doc """
  Computes the perimeter (total edge length) of a polygon.
  """
  @spec perimeter(polygon()) :: float()
  def perimeter([]), do: 0.0
  def perimeter([_]), do: 0.0

  def perimeter(polygon) do
    n = length(polygon)

    0..(n - 1)
    |> Enum.reduce(0, fn i, acc ->
      {x0, y0} = Enum.at(polygon, i)
      {x1, y1} = Enum.at(polygon, rem(i + 1, n))
      acc + :math.sqrt((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0))
    end)
  end

  @doc """
  Tests if a point is inside a polygon.

  Uses the ray casting algorithm.
  """
  @spec contains?(polygon(), point()) :: boolean()
  def contains?([], _point), do: false
  def contains?([_], _point), do: false
  def contains?([_, _], _point), do: false

  def contains?(polygon, {px, py}) do
    n = length(polygon)

    crossings =
      0..(n - 1)
      |> Enum.count(fn i ->
        {x0, y0} = Enum.at(polygon, i)
        {x1, y1} = Enum.at(polygon, rem(i + 1, n))

        # Check if ray from point crosses this edge
        ((y0 > py) != (y1 > py)) and
          px < (x1 - x0) * (py - y0) / (y1 - y0) + x0
      end)

    rem(crossings, 2) == 1
  end

  @doc """
  Computes the convex hull of a set of points.

  Returns the vertices of the convex hull in counter-clockwise order.
  Uses Andrew's monotone chain algorithm.
  """
  @spec hull([point()]) :: polygon()
  def hull([]), do: []
  def hull([point]), do: [point]
  def hull([p1, p2]), do: [p1, p2]

  def hull(points) do
    # Sort points lexicographically
    sorted = Enum.sort(points)

    # Build lower hull
    lower = build_hull(sorted)

    # Build upper hull
    upper = build_hull(Enum.reverse(sorted))

    # Concatenate (remove last point of each to avoid duplication)
    (Enum.drop(lower, -1) ++ Enum.drop(upper, -1))
    |> Enum.uniq()
  end

  defp build_hull(points) do
    Enum.reduce(points, [], fn point, hull ->
      hull = remove_non_left_turns(hull, point)
      hull ++ [point]
    end)
  end

  defp remove_non_left_turns(hull, _point) when length(hull) < 2, do: hull

  defp remove_non_left_turns(hull, point) do
    [p2, p1 | rest] = Enum.reverse(hull)

    if cross_product(p1, p2, point) <= 0 do
      # Not a left turn, remove p2 and check again
      remove_non_left_turns(Enum.reverse([p1 | rest]), point)
    else
      hull
    end
  end

  defp cross_product({x1, y1}, {x2, y2}, {x3, y3}) do
    (x2 - x1) * (y3 - y1) - (y2 - y1) * (x3 - x1)
  end

  @doc """
  Computes the bounding box of a polygon.

  Returns `{min_x, min_y, max_x, max_y}`.
  """
  @spec bounds(polygon()) :: {number(), number(), number(), number()} | nil
  def bounds([]), do: nil

  def bounds(polygon) do
    {xs, ys} = Enum.unzip(polygon)
    {Enum.min(xs), Enum.min(ys), Enum.max(xs), Enum.max(ys)}
  end

  @doc """
  Computes the length of a polyline (open path).

  Unlike `perimeter/1`, this doesn't close the polygon.
  """
  @spec path_length(polygon()) :: float()
  def path_length([]), do: 0.0
  def path_length([_]), do: 0.0

  def path_length(points) do
    points
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.reduce(0, fn [{x0, y0}, {x1, y1}], acc ->
      acc + :math.sqrt((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0))
    end)
  end
end
