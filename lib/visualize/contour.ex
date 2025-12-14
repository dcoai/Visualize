defmodule Visualize.Contour do
  @moduledoc """
  Contour generation using the marching squares algorithm.

  Computes contour polygons from gridded data. Useful for topographic maps,
  density visualizations, and isoline plots.

  ## Examples

      # Create contours from a 2D grid of values
      grid = [
        [0, 0, 0, 0],
        [0, 5, 5, 0],
        [0, 5, 10, 5],
        [0, 0, 5, 0]
      ]

      contours = Visualize.Contour.new()
        |> Visualize.Contour.size(4, 4)
        |> Visualize.Contour.thresholds([2.5, 7.5])
        |> Visualize.Contour.compute(grid)

      # Each contour has: value, type: "MultiPolygon", coordinates

      # For density estimation from points, use Visualize.Contour.Density

  """

  alias Visualize.SVG.Path

  defstruct width: 1,
            height: 1,
            thresholds: [],
            smooth?: true

  @type contour_result :: %{
          value: number(),
          type: String.t(),
          coordinates: [[[{number(), number()}]]]
        }

  @type t :: %__MODULE__{
          width: pos_integer(),
          height: pos_integer(),
          thresholds: [number()] | pos_integer(),
          smooth?: boolean()
        }

  @doc "Creates a new contour generator"
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc "Sets the grid dimensions"
  @spec size(t(), pos_integer(), pos_integer()) :: t()
  def size(%__MODULE__{} = contour, width, height) do
    %{contour | width: width, height: height}
  end

  @doc """
  Sets the threshold values for contour generation.

  Can be a list of specific values or a count (generates that many levels).
  """
  @spec thresholds(t(), [number()] | pos_integer()) :: t()
  def thresholds(%__MODULE__{} = contour, values) do
    %{contour | thresholds: values}
  end

  @doc "Enables or disables smoothing"
  @spec smooth(t(), boolean()) :: t()
  def smooth(%__MODULE__{} = contour, smooth?) do
    %{contour | smooth?: smooth?}
  end

  @doc """
  Computes contours from a 2D grid of values.

  Returns a list of contour objects, each with:
  - value: The threshold value
  - type: "MultiPolygon"
  - coordinates: GeoJSON-style coordinates
  """
  @spec compute(t(), [[number()]]) :: [contour_result()]
  def compute(%__MODULE__{} = contour, grid) do
    # Flatten grid if needed and determine dimensions
    {values, width, height} = normalize_grid(grid, contour)

    # Resolve thresholds
    threshold_values = resolve_thresholds(contour.thresholds, values)

    # Generate contours for each threshold
    Enum.map(threshold_values, fn threshold ->
      polygons = march_squares(values, width, height, threshold, contour.smooth?)

      %{
        value: threshold,
        type: "MultiPolygon",
        coordinates: polygons
      }
    end)
  end

  @doc """
  Renders contours as SVG path data.

  Returns a list of path strings, one per threshold.
  """
  @spec render(t(), [[number()]]) :: [%{value: number(), path: String.t()}]
  def render(%__MODULE__{} = contour, grid) do
    contours = compute(contour, grid)

    Enum.map(contours, fn %{value: value, coordinates: coords} ->
      path = coordinates_to_path(coords)
      %{value: value, path: path}
    end)
  end

  # ============================================
  # Marching Squares Implementation
  # ============================================

  # The 16 cases for marching squares
  # Each case defines which edges have crossings
  # Edges: 0=top, 1=right, 2=bottom, 3=left
  @cases %{
    0 => [],
    1 => [{3, 2}],
    2 => [{2, 1}],
    3 => [{3, 1}],
    4 => [{1, 0}],
    5 => [{3, 0}, {1, 2}],  # Saddle point
    6 => [{2, 0}],
    7 => [{3, 0}],
    8 => [{0, 3}],
    9 => [{0, 2}],
    10 => [{0, 1}, {2, 3}],  # Saddle point
    11 => [{0, 1}],
    12 => [{1, 3}],
    13 => [{1, 2}],
    14 => [{2, 3}],
    15 => []
  }

  defp march_squares(values, width, height, threshold, smooth?) do
    # Pad the grid with low values to ensure contours close at boundaries
    {padded_values, padded_width, padded_height} = pad_grid(values, width, height)

    # Build contour segments on padded grid
    segments = build_segments(padded_values, padded_width, padded_height, threshold, smooth?)

    # Connect segments into rings
    rings = connect_segments(segments)

    # Convert rings to polygon coordinates, adjusting for padding offset
    # Each ring becomes one polygon (outer or hole)
    Enum.map(rings, fn ring ->
      [Enum.map(ring, fn {x, y} ->
        # Offset by -1 to account for padding, and clamp to original bounds
        [max(0, min(width - 1, x - 1)), max(0, min(height - 1, y - 1))]
      end)]
    end)
  end

  # Pad the grid with a border of very low values to close boundary contours
  defp pad_grid(values, width, height) do
    min_val = Enum.min(values) - 1000

    # Create padded grid (width+2 x height+2)
    padded_width = width + 2
    padded_height = height + 2

    padded = for y <- 0..(padded_height - 1), x <- 0..(padded_width - 1) do
      cond do
        # Border cells get minimum value
        x == 0 or y == 0 or x == padded_width - 1 or y == padded_height - 1 ->
          min_val
        # Interior cells get original values (offset by 1)
        true ->
          orig_idx = (y - 1) * width + (x - 1)
          Enum.at(values, orig_idx, min_val)
      end
    end

    {padded, padded_width, padded_height}
  end

  defp build_segments(values, width, height, threshold, smooth?) do
    # Iterate over each cell (excluding boundary)
    for y <- 0..(height - 2),
        x <- 0..(width - 2),
        reduce: [] do
      acc ->
        # Get corner values
        v0 = get_value(values, width, x, y)
        v1 = get_value(values, width, x + 1, y)
        v2 = get_value(values, width, x + 1, y + 1)
        v3 = get_value(values, width, x, y + 1)

        # Determine case (0-15) based on which corners are above threshold
        case_index =
          (if v0 >= threshold, do: 8, else: 0) +
            (if v1 >= threshold, do: 4, else: 0) +
            (if v2 >= threshold, do: 2, else: 0) +
            (if v3 >= threshold, do: 1, else: 0)

        # Get edge crossings for this case
        edges = Map.get(@cases, case_index, [])

        # Convert edge crossings to segments
        new_segments =
          Enum.map(edges, fn {from_edge, to_edge} ->
            from_point = edge_point(x, y, from_edge, v0, v1, v2, v3, threshold, smooth?)
            to_point = edge_point(x, y, to_edge, v0, v1, v2, v3, threshold, smooth?)
            {from_point, to_point}
          end)

        acc ++ new_segments
    end
  end

  defp edge_point(x, y, edge, v0, v1, v2, v3, threshold, smooth?) do
    case edge do
      0 ->
        # Top edge (between v0 and v1)
        t = if smooth?, do: interpolate_t(v0, v1, threshold), else: 0.5
        {x + t, y}

      1 ->
        # Right edge (between v1 and v2)
        t = if smooth?, do: interpolate_t(v1, v2, threshold), else: 0.5
        {x + 1, y + t}

      2 ->
        # Bottom edge (between v3 and v2)
        t = if smooth?, do: interpolate_t(v3, v2, threshold), else: 0.5
        {x + t, y + 1}

      3 ->
        # Left edge (between v0 and v3)
        t = if smooth?, do: interpolate_t(v0, v3, threshold), else: 0.5
        {x, y + t}
    end
  end

  defp interpolate_t(v0, v1, threshold) do
    if v1 == v0 do
      0.5
    else
      (threshold - v0) / (v1 - v0)
    end
  end

  defp get_value(values, width, x, y) do
    index = y * width + x
    Enum.at(values, index, 0)
  end

  defp connect_segments([]), do: []

  defp connect_segments(segments) do
    # Build adjacency map
    {start_map, _end_map} = build_adjacency(segments)

    # Connect segments into rings
    connect_rings(segments, start_map, [])
  end

  defp build_adjacency(segments) do
    Enum.reduce(segments, {%{}, %{}}, fn {from, to}, {start_map, end_map} ->
      start_map = Map.update(start_map, from, [to], &[to | &1])
      end_map = Map.update(end_map, to, [from], &[from | &1])
      {start_map, end_map}
    end)
  end

  defp connect_rings([], _start_map, rings), do: rings

  defp connect_rings([{start_point, next_point} | rest], start_map, rings) do
    # Follow the ring
    {ring, remaining_segments} = follow_ring(start_point, next_point, start_map, rest, [start_point])

    # Update start_map by removing used segments
    new_start_map =
      Enum.reduce(ring, start_map, fn point, map ->
        Map.delete(map, point)
      end)

    connect_rings(remaining_segments, new_start_map, [ring | rings])
  end

  defp follow_ring(start_point, current_point, start_map, segments, ring) do
    ring = ring ++ [current_point]

    if close_enough?(current_point, start_point) and length(ring) > 2 do
      # Ring is closed
      {ring, segments}
    else
      # Find next segment
      case Map.get(start_map, current_point) do
        nil ->
          # No continuation, return what we have
          {ring, segments}

        [next | _] ->
          # Remove this segment from available
          new_segments = Enum.reject(segments, fn {from, _} -> from == current_point end)
          follow_ring(start_point, next, start_map, new_segments, ring)
      end
    end
  end

  defp close_enough?({x1, y1}, {x2, y2}) do
    abs(x1 - x2) < 0.001 and abs(y1 - y2) < 0.001
  end

  defp normalize_grid(grid, contour) when is_list(grid) do
    if is_list(hd(grid)) do
      # 2D array
      height = length(grid)
      width = length(hd(grid))
      values = List.flatten(grid)
      {values, width, height}
    else
      # 1D array, use contour dimensions
      {grid, contour.width, contour.height}
    end
  end

  defp resolve_thresholds(thresholds, _values) when is_list(thresholds), do: thresholds

  defp resolve_thresholds(count, values) when is_integer(count) and count > 0 do
    min_val = Enum.min(values)
    max_val = Enum.max(values)
    step = (max_val - min_val) / (count + 1)

    for i <- 1..count do
      min_val + i * step
    end
  end

  defp resolve_thresholds(_, _), do: []

  defp coordinates_to_path(coords) do
    coords
    |> Enum.map(fn polygon ->
      polygon
      |> Enum.map(fn ring ->
        case ring do
          [[x0, y0] | rest] when rest != [] ->
            start = "M#{format_num(x0)},#{format_num(y0)}"

            lines =
              rest
              |> Enum.map(fn [x, y] -> "L#{format_num(x)},#{format_num(y)}" end)
              |> Enum.join()

            # Only close the path if it's actually a closed ring
            # (last point is close to first point)
            last_point = List.last(rest)
            is_closed = case last_point do
              [x_last, y_last] ->
                abs(x_last - x0) < 0.001 and abs(y_last - y0) < 0.001
              _ ->
                false
            end

            if is_closed do
              start <> lines <> "Z"
            else
              start <> lines
            end

          _ ->
            ""
        end
      end)
      |> Enum.join()
    end)
    |> Enum.join()
  end

  defp format_num(n) when is_float(n), do: Float.round(n, 3) |> Kernel.to_string()
  defp format_num(n), do: Kernel.to_string(n)
end
