defmodule Examples.Charts.ContourPlot do
  @moduledoc """
  Contour plot as a design (#128): the `:contour` transform over a grid of heights under
  one `:path` mark.

  Marching squares is a step of the mark's data pipeline (spec/14 §5.4.4): the rows are
  the grid in row-major order, `field: :z` the height read from each, and the step yields
  one ring per threshold as a ready path scaled to the plot. Each ring's `value` is its
  threshold, and `fill: {:field, :value}` on the style reaches the `:sequential` `color`
  scale (§3.4), so the bands run from the theme's background to its first series color
  and the legend in the right margin (`inside: false`, §4.5, #136) explains the heights.
  """

  import Visualize.Chart.Build

  alias Examples.Charts.Design

  @margin %{top: 20, right: 80, bottom: 20, left: 20}
  @columns 50
  @rows 40
  @thresholds [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8]

  def title, do: "Contour Plot"
  def description, do: "Topographic elevation data"

  @doc "The design and the rows it binds (spec/14 §16.1)."
  def design(opts \\ []) do
    design =
      Design.fold([
        chart(meta: %{name: title(), description: [description()]}),
        source(:grid, [:z]),
        style(:band, fill: {:field, :value}, stroke: :background, stroke_width: 0.3),
        cartesian(margin: @margin),
        sequential_scale(:color, domain: [0, :auto]),
        legend(:color, position: :right, inside: false, title: ["Height"]),
        # One ring per threshold, lowest first, so each band lies over the one beneath it.
        path(
          contour(from(:grid), :z, [@columns, @rows], thresholds: @thresholds),
          %{path: :path},
          style: :band
        )
      ])

    {design, %{grid: rows(opts[:animation_tick])}}
  end

  def render(opts \\ []), do: Design.render(__MODULE__, opts)

  # The grid in row-major order: the sum of three gaussian peaks at each cell. Animated,
  # the peaks orbit and breathe.
  defp rows(tick) do
    peaks = peaks(tick)

    for y <- 0..(@rows - 1), x <- 0..(@columns - 1) do
      z =
        Enum.reduce(peaks, 0, fn {px, py, amplitude, sigma}, acc ->
          d2 = (x - px) * (x - px) + (y - py) * (y - py)
          acc + amplitude * :math.exp(-d2 / (2 * sigma * sigma))
        end)

      %{z: z}
    end
  end

  defp peaks(nil) do
    [
      {@columns * 0.3, @rows * 0.3, 0.8, 8},
      {@columns * 0.7, @rows * 0.6, 0.9, 10},
      {@columns * 0.5, @rows * 0.8, 0.6, 6}
    ]
  end

  defp peaks(tick) do
    phase = tick * 0.08

    [
      {@columns * 0.3 + 5 * :math.cos(phase), @rows * 0.3 + 5 * :math.sin(phase),
       0.7 + 0.2 * :math.sin(phase * 1.5), 8},
      {@columns * 0.7 + 6 * :math.cos(phase + 2), @rows * 0.6 + 6 * :math.sin(phase + 2),
       0.8 + 0.2 * :math.sin(phase * 1.2 + 1), 10},
      {@columns * 0.5 + 4 * :math.cos(phase + 4), @rows * 0.8 + 4 * :math.sin(phase + 4),
       0.5 + 0.2 * :math.sin(phase + 2), 6}
    ]
  end

  def sample_code do
    ~S"""
    import Visualize.Chart.Build

    {:ok, design} =
      Visualize.Chart.compose([
        chart(meta: %{name: "Contour Plot"}),
        # The grid in row-major order, one height per cell.
        source(:grid, [:z]),
        style(:band, fill: {:field, :value}, stroke: :background, stroke_width: 0.3),
        cartesian(margin: %{top: 20, right: 80, bottom: 20, left: 20}),
        sequential_scale(:color, domain: [0, :auto]),
        legend(:color, position: :right, inside: false, title: ["Height"]),
        # Marching squares over a 50 × 40 grid (spec/14 §5.4.4): one ring per threshold,
        # its value the threshold, which the color scale maps to the band's fill.
        path(
          contour(from(:grid), :z, [50, 40], thresholds: [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8]),
          %{path: :path},
          style: :band
        )
      ])

    {:ok, applied} = Visualize.Chart.apply(design, sources: %{grid: grid})
    Visualize.Chart.render(applied)
    """
  end
end
