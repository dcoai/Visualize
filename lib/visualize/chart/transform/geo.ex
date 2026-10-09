defmodule Visualize.Chart.Transform.Geo do
  @moduledoc false
  # The geo steps of a mark's pipeline (spec/14 §5.4.4): `:projection` through the frame's
  # `Visualize.Geo.Projection`, `:delaunay` and `:voronoi` over pixel points, `:contour`
  # over a grid stretched to the plot, `:density` over pixel points. Every row's shape is
  # a `Visualize.IR.Path` under `path` (D-62).

  alias Visualize.Contour
  alias Visualize.Contour.Density
  alias Visualize.Data.Table
  alias Visualize.Geo.{Delaunay, Projection, Voronoi}
  alias Visualize.Geo.Path, as: GeoPath
  alias Visualize.IR.Path
  alias Visualize.Layout.Hexbin

  @doc false
  @spec run(atom(), map(), [map()], map()) :: [map()]
  def run(:projection, node, rows, ctx), do: projection(node, rows, ctx)
  def run(:delaunay, node, rows, _ctx), do: delaunay(node, rows)
  def run(:voronoi, node, rows, ctx), do: voronoi(node, rows, ctx)
  def run(:contour, node, rows, ctx), do: contour(node, rows, ctx)
  def run(:density, node, rows, ctx), do: density(node, rows, ctx)
  def run(:hexbin, node, rows, _ctx), do: hexbin(node, rows)

  # -- projection -------------------------------------------------------------------------

  # A geometry column: each row gains the projected outline as `path` and its centroid
  # as `x`, `y`; a geometry that projects to nothing is dropped (#349).
  defp projection(%{field: field}, rows, %{projection: %Projection{} = projection}) do
    geo_path = GeoPath.new(projection)

    Enum.flat_map(rows, fn row ->
      geometry = Table.get(row, field)

      case is_map(geometry) and GeoPath.path_and_centroid(geo_path, geometry) do
        {path, {x, y}} -> [Map.merge(row, %{path: path, x: x, y: y})]
        _ -> []
      end
    end)
  end

  defp projection(node, rows, %{projection: %Projection{} = projection}) do
    [lon, lat] = node.fields

    Enum.flat_map(rows, fn row ->
      case {Table.get(row, lon), Table.get(row, lat)} do
        {lo, la} when is_number(lo) and is_number(la) ->
          case Projection.project(projection, lo, la) do
            {x, y} -> [Map.merge(row, %{x: x, y: y})]
            nil -> []
          end

        _ ->
          []
      end
    end)
  end

  defp projection(_node, _rows, _ctx) do
    raise ArgumentError,
          "a :projection transform needs a projection: only a :geo frame has one " <>
            "(spec/14 §5.4.4)"
  end

  # -- hexbin -----------------------------------------------------------------------------

  # The cells of `Visualize.Layout.Hexbin` over the placed points (spec/14 §5.4.4, #348):
  # each with its hexagon, or every input row with its cell's centre and count.
  defp hexbin(node, rows) do
    radius = Map.get(node, :radius, 20)
    placed = points(node, rows)
    cells = Hexbin.bin(Enum.map(placed, &elem(&1, 1)), radius)

    case Map.get(node, :output, :cells) do
      :cells ->
        Enum.map(cells, fn %{x: x, y: y, count: count} ->
          %{x: x, y: y, count: count, path: Hexbin.hexagon(x, y, radius)}
        end)

      :points ->
        by_point = for cell <- cells, point <- cell.points, into: %{}, do: {point, cell}

        Enum.map(placed, fn {row, point} ->
          %{x: cx, y: cy, count: count} = Map.fetch!(by_point, point)
          Map.merge(row, %{cx: cx, cy: cy, count: count})
        end)

      other ->
        raise ArgumentError, ":hexbin yields no #{inspect(other)} (spec/14 §5.4.4)"
    end
  end

  # -- points -----------------------------------------------------------------------------

  # `{row, {x, y}}` for every row with both coordinates, in order.
  defp points(node, rows) do
    [xf, yf] = node.fields

    Enum.flat_map(rows, fn row ->
      case {Table.get(row, xf), Table.get(row, yf)} do
        {x, y} when is_number(x) and is_number(y) -> [{row, {x, y}}]
        _ -> []
      end
    end)
  end

  # -- delaunay ---------------------------------------------------------------------------

  defp delaunay(node, rows) do
    points = node |> points(rows) |> Enum.map(&elem(&1, 1))
    delaunay = Delaunay.new(points)

    case Map.get(node, :output, :triangles) do
      :triangles ->
        delaunay
        |> Delaunay.triangles()
        |> Enum.with_index()
        |> Enum.map(fn {vertices, index} ->
          corners = Enum.map(vertices, &Enum.at(points, &1))
          %{index: index, vertices: vertices, path: polygon(corners)}
        end)

      :hull ->
        hull = Delaunay.hull(delaunay)
        polygon = if length(hull) < 3, do: [], else: Enum.map(hull, &Enum.at(points, &1))
        [%{path: polygon(polygon)}]

      other ->
        raise ArgumentError, ":delaunay yields no #{inspect(other)} (spec/14 §5.4.4)"
    end
  end

  # -- voronoi ----------------------------------------------------------------------------

  defp voronoi(node, rows, ctx) do
    pairs = points(node, rows)
    [w, h] = Map.get(node, :size, ctx.size)
    voronoi = pairs |> Enum.map(&elem(&1, 1)) |> Voronoi.new() |> Voronoi.bounds([0, 0, w, h])

    case Map.get(node, :output, :cells) do
      :cells ->
        pairs
        |> Enum.with_index()
        |> Enum.map(fn {{row, _point}, index} ->
          Map.merge(row, %{index: index, path: polygon(Voronoi.cell(voronoi, index))})
        end)

      :edges ->
        Enum.map(Voronoi.edges(voronoi), fn {{x0, y0}, {x1, y1}} ->
          path = Path.new() |> Path.move_to(x0, y0) |> Path.line_to(x1, y1)
          %{x0: x0, y0: y0, x1: x1, y1: y1, path: path}
        end)

      other ->
        raise ArgumentError, ":voronoi yields no #{inspect(other)} (spec/14 §5.4.4)"
    end
  end

  # -- contour ----------------------------------------------------------------------------

  defp contour(node, rows, ctx) do
    [columns, grid_rows] = node.size
    [w, h] = ctx.size
    sx = w / max(columns - 1, 1)
    sy = h / max(grid_rows - 1, 1)
    values = Enum.map(rows, &(Table.get(&1, node.field) || 0))

    Contour.new()
    |> Contour.size(columns, grid_rows)
    |> Contour.thresholds(Map.get(node, :thresholds, 10))
    |> Contour.compute(values)
    |> rings(fn [x, y] -> {x * sx, y * sy} end)
  end

  # -- density ----------------------------------------------------------------------------

  defp density(node, rows, ctx) do
    weight = Map.get(node, :field)
    [w, h] = Map.get(node, :size, ctx.size)

    points =
      node
      |> points(rows)
      |> Enum.map(fn {row, {x, y}} ->
        %{x: x, y: y, w: if(weight, do: Table.get(row, weight) || 1, else: 1)}
      end)

    Density.new()
    |> Density.x(& &1.x)
    |> Density.y(& &1.y)
    |> Density.weight(& &1.w)
    |> Density.size(w, h)
    |> Density.bandwidth(Map.get(node, :bandwidth, 20))
    |> Density.thresholds(Map.get(node, :thresholds, 20))
    |> Density.compute(points)
    |> rings(fn [x, y] -> {x, y} end)
  end

  # One row per ring of every threshold's MultiPolygon, closed.
  defp rings(contours, point) do
    for %{value: value, coordinates: polygons} <- contours,
        [ring | _] <- polygons,
        do: %{value: value, path: polygon(Enum.map(ring, point))}
  end

  defp polygon([]), do: Path.new()

  defp polygon([{x, y} | rest]) do
    rest
    |> Enum.reduce(Path.move_to(Path.new(), x, y), fn {px, py}, path ->
      Path.line_to(path, px, py)
    end)
    |> Path.close()
  end
end
