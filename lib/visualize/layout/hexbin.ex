defmodule Visualize.Layout.Hexbin do
  @moduledoc """
  Hexagonal binning of points in the plane (spec/06 §9, #348): d3-hexbin's lattice of
  flat-topped hexagons, the columns `2 r sin(π/3)` apart and the rows `1.5 r`, every odd
  row offset by half a column. The lattice is in the coordinates of the points, so a chart
  bins pixels.

  ## Examples

      iex> [cell] = Visualize.Layout.Hexbin.bin([{1, 1}, {-1, 2}], 20)
      iex> {cell.x, cell.y, cell.count}
      {0.0, 0.0, 2}

  """

  alias Visualize.IR.Path

  @typedoc "A non-empty cell: its centre, its count and its points in input order."
  @type cell :: %{x: float(), y: float(), count: pos_integer(), points: [{number(), number()}]}

  @doc """
  The non-empty cells of the lattice over `points`, in lattice order (row, then column).
  """
  @spec bin([{number(), number()}], number()) :: [cell()]
  def bin(points, radius) when is_number(radius) and radius > 0 do
    dx = radius * 2 * :math.sin(:math.pi() / 3)
    dy = radius * 1.5

    points
    |> Enum.group_by(fn {x, y} ->
      row = round(y / dy)
      offset = if rem(row, 2) == 0, do: 0.0, else: 0.5
      {row, round(x / dx - offset)}
    end)
    |> Enum.sort_by(fn {key, _} -> key end)
    |> Enum.map(fn {{row, col}, members} ->
      offset = if rem(row, 2) == 0, do: 0.0, else: 0.5
      %{x: (col + offset) * dx, y: row * dy, count: length(members), points: members}
    end)
  end

  @doc """
  The closed flat-topped hexagon of `radius` at the centre, its first vertex at bearing
  −30° (the upper right), then clockwise on screen.
  """
  @spec hexagon(number(), number(), number()) :: Path.t()
  def hexagon(cx, cy, radius) do
    [{x0, y0} | rest] =
      for i <- 0..5 do
        angle = :math.pi() / 3 * i - :math.pi() / 6
        {cx + radius * :math.cos(angle), cy + radius * :math.sin(angle)}
      end

    rest
    |> Enum.reduce(Path.move_to(Path.new(), x0, y0), fn {x, y}, path ->
      Path.line_to(path, x, y)
    end)
    |> Path.close()
  end
end
