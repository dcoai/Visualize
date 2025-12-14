defmodule Visualize.Contour.Density do
  @moduledoc """
  Kernel density estimation for contour generation from point data.

  Estimates a continuous density surface from scattered points using
  Gaussian kernel density estimation, then generates contours from
  the resulting grid.

  ## Examples

      # Generate density contours from points
      points = [
        %{x: 10, y: 20},
        %{x: 15, y: 25},
        %{x: 12, y: 22},
        # ... more points
      ]

      density = Visualize.Contour.Density.new()
        |> Visualize.Contour.Density.x(fn d -> d.x end)
        |> Visualize.Contour.Density.y(fn d -> d.y end)
        |> Visualize.Contour.Density.size(100, 100)
        |> Visualize.Contour.Density.bandwidth(10)
        |> Visualize.Contour.Density.thresholds(10)

      contours = Visualize.Contour.Density.compute(density, points)

  ## Algorithm

  Uses Gaussian kernel density estimation:
  - For each grid cell, sum the weighted contributions from all points
  - Weight is based on distance using Gaussian kernel: K(u) = exp(-u²/2)
  - Bandwidth controls the smoothness (larger = smoother)

  """

  alias Visualize.Contour

  defstruct x: nil,
            y: nil,
            weight: nil,
            width: 960,
            height: 500,
            cell_size: 4,
            bandwidth: 20,
            thresholds: 20

  @type t :: %__MODULE__{
          x: (any() -> number()) | nil,
          y: (any() -> number()) | nil,
          weight: (any() -> number()) | nil,
          width: pos_integer(),
          height: pos_integer(),
          cell_size: pos_integer(),
          bandwidth: number(),
          thresholds: [number()] | pos_integer()
        }

  @doc "Creates a new density estimator"
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc "Sets the x accessor function"
  @spec x(t(), (any() -> number())) :: t()
  def x(%__MODULE__{} = density, accessor) when is_function(accessor, 1) do
    %{density | x: accessor}
  end

  @doc "Sets the y accessor function"
  @spec y(t(), (any() -> number())) :: t()
  def y(%__MODULE__{} = density, accessor) when is_function(accessor, 1) do
    %{density | y: accessor}
  end

  @doc "Sets the weight accessor function"
  @spec weight(t(), (any() -> number())) :: t()
  def weight(%__MODULE__{} = density, accessor) when is_function(accessor, 1) do
    %{density | weight: accessor}
  end

  @doc "Sets the output dimensions"
  @spec size(t(), pos_integer(), pos_integer()) :: t()
  def size(%__MODULE__{} = density, width, height) do
    %{density | width: width, height: height}
  end

  @doc "Sets the cell size for the density grid"
  @spec cell_size(t(), pos_integer()) :: t()
  def cell_size(%__MODULE__{} = density, size) do
    %{density | cell_size: size}
  end

  @doc """
  Sets the bandwidth (kernel size) for density estimation.

  Larger values produce smoother results but may obscure detail.
  """
  @spec bandwidth(t(), number()) :: t()
  def bandwidth(%__MODULE__{} = density, bw) do
    %{density | bandwidth: bw}
  end

  @doc """
  Sets the threshold values for contour generation.

  Can be a list of specific values or a count (generates that many levels).
  """
  @spec thresholds(t(), [number()] | pos_integer()) :: t()
  def thresholds(%__MODULE__{} = density, values) do
    %{density | thresholds: values}
  end

  @doc """
  Computes density contours from point data.

  Returns a list of contour objects compatible with Visualize.Contour.
  """
  @spec compute(t(), [any()]) :: [Contour.contour_result()]
  def compute(%__MODULE__{} = density, points) when is_list(points) do
    # Use default accessors if not provided
    x_fn = density.x || fn d -> if is_map(d), do: Map.get(d, :x, 0), else: elem(d, 0) end
    y_fn = density.y || fn d -> if is_map(d), do: Map.get(d, :y, 0), else: elem(d, 1) end
    weight_fn = density.weight || fn _ -> 1 end

    # Extract coordinates
    coords = Enum.map(points, fn d ->
      {x_fn.(d), y_fn.(d), weight_fn.(d)}
    end)

    # Compute density grid
    grid = compute_density_grid(coords, density)

    # Generate contours
    grid_width = div(density.width, density.cell_size) + 1
    grid_height = div(density.height, density.cell_size) + 1

    contour = Contour.new()
      |> Contour.size(grid_width, grid_height)
      |> Contour.thresholds(density.thresholds)
      |> Contour.smooth(true)

    contours = Contour.compute(contour, grid)

    # Scale coordinates back to original dimensions
    scale_contours(contours, density.cell_size)
  end

  @doc """
  Renders density contours as SVG paths.
  """
  @spec render(t(), [any()]) :: [%{value: number(), path: String.t()}]
  def render(%__MODULE__{} = density, points) do
    contours = compute(density, points)

    Enum.map(contours, fn %{value: value, coordinates: coords} ->
      path = coordinates_to_path(coords)
      %{value: value, path: path}
    end)
  end

  # ============================================
  # Kernel Density Estimation
  # ============================================

  defp compute_density_grid(coords, density) do
    cell_size = density.cell_size
    grid_width = div(density.width, cell_size) + 1
    grid_height = div(density.height, cell_size) + 1

    # Initialize grid
    grid_size = grid_width * grid_height
    grid = List.duplicate(0.0, grid_size)

    # Radius of influence (3 standard deviations)
    radius = ceil(density.bandwidth * 3 / cell_size)
    bw = density.bandwidth / cell_size

    # For each point, add contribution to nearby grid cells
    Enum.reduce(coords, grid, fn {px, py, weight}, acc_grid ->
      # Convert to grid coordinates
      gx = px / cell_size
      gy = py / cell_size

      # Grid cell range to update
      x0 = max(0, floor(gx) - radius)
      x1 = min(grid_width - 1, ceil(gx) + radius)
      y0 = max(0, floor(gy) - radius)
      y1 = min(grid_height - 1, ceil(gy) + radius)

      # Add Gaussian contribution to each cell
      Enum.reduce(y0..y1, acc_grid, fn cy, grid_y ->
        Enum.reduce(x0..x1, grid_y, fn cx, grid_x ->
          # Distance from point to cell center
          dx = cx - gx
          dy = cy - gy
          d2 = dx * dx + dy * dy

          # Gaussian kernel
          k = weight * gaussian_kernel(d2, bw)

          # Update grid
          idx = cy * grid_width + cx
          List.update_at(grid_x, idx, &(&1 + k))
        end)
      end)
    end)
  end

  # Gaussian kernel: K(u) = exp(-u²/2) / (2π)
  defp gaussian_kernel(d2, bandwidth) do
    u2 = d2 / (bandwidth * bandwidth)
    :math.exp(-u2 / 2) / (2 * :math.pi() * bandwidth * bandwidth)
  end

  defp scale_contours(contours, cell_size) do
    Enum.map(contours, fn %{value: value, type: type, coordinates: coords} ->
      scaled_coords =
        Enum.map(coords, fn polygon ->
          Enum.map(polygon, fn ring ->
            Enum.map(ring, fn [x, y] ->
              [x * cell_size, y * cell_size]
            end)
          end)
        end)

      %{value: value, type: type, coordinates: scaled_coords}
    end)
  end

  defp coordinates_to_path(coords) do
    coords
    |> Enum.map(fn polygon ->
      polygon
      |> Enum.map(fn ring ->
        case ring do
          [[x0, y0] | rest] ->
            start = "M#{format_num(x0)},#{format_num(y0)}"

            lines =
              rest
              |> Enum.map(fn [x, y] -> "L#{format_num(x)},#{format_num(y)}" end)
              |> Enum.join()

            start <> lines <> "Z"

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
