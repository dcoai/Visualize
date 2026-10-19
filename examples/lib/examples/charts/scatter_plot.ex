defmodule Examples.Charts.ScatterPlot do
  @moduledoc """
  Scatter plot as a design (#125): one `:circle` mark, colored by category.

  A `:circle`'s `value` channel is its radius in user units and names no scale (spec/14
  §5.2), so the radius is a column of the rows; the color is a `{:field, :category}` on the
  style's `fill`, which is read per element and passed through the frame's `color` scale
  (§3.2), and the legend explains that same scale.

  The legend draws inside the plot area (#136) and prints the category values under a title,
  where the hand-laid one wrote "Category A" per entry.

  Behind the points the chart draws their **Voronoi cells** — each the region nearer its
  point than any other, the target a pointer finds a point by — and the **hull** of their
  **Delaunay** triangulation, the outline the points span (the `:voronoi` and `:delaunay`
  steps, spec/14 §5.4.4). Both are laid in pixels and read no scale, so the chart places
  each point itself through the mapping its axes draw with, as the hexbin chart does, and
  hands the steps the pixel columns `px` and `py`.
  """

  import Visualize.Chart.Build

  alias Examples.Charts.Design

  @margin %{top: 20, right: 20, bottom: 40, left: 50}
  @categories ["A", "B", "C"]

  @data (for _ <- 1..100 do
           %{
             x: :rand.uniform() * 100,
             y: :rand.uniform() * 100,
             size: :rand.uniform() * 20 + 5,
             category: Enum.random(["A", "B", "C"])
           }
         end)

  def title, do: "Scatter Plot"
  def description, do: "Random data points with categories"

  @doc "The design and the rows it binds (spec/14 §16.1)."
  def design(opts \\ []) do
    {width, height} = Design.size(__MODULE__, opts)
    plot = {width - @margin.left - @margin.right, height - @margin.top - @margin.bottom}

    design =
      Design.fold([
        chart(meta: %{name: title(), description: [description()]}),
        source(:points, [:x, :y, :r, :category, :px, :py]),
        style(:point, fill: {:field, :category}, opacity: 0.7),
        style(:cell, fill: :none, stroke: %{color: :grid, width: 1}),
        style(:hull, fill: :none, stroke: %{color: :axis, width: 1, dash: [4, 3]}),
        cartesian(margin: @margin),
        linear_scale(:x, domain: [0, 100]),
        linear_scale(:y, domain: [0, 100]),
        ordinal_scale(:color, domain: @categories),
        axis(:x, :bottom, ticks: 10),
        axis(:y, :left, ticks: 10),
        legend(:color, position: :top_right, title: ["Category"]),
        circle(:points, %{x: :x, y: :y, value: :r}, style: :point, frame: :main)
        | underlay()
      ])

    {design, %{points: rows(opts, plot)}}
  end

  def render(opts \\ []), do: Design.render(__MODULE__, opts)

  # Each point's Voronoi cell, then the hull of the Delaunay triangulation, in pixels: a
  # frame of their own over the same plot, drawn first (`cells` sorts before `main`), so the
  # chart's text alternative reads a Voronoi diagram under a bubble chart rather than a
  # Voronoi diagram alone (spec/14 §21.1).
  defp underlay do
    in_frame(:cells, [
      cartesian(margin: @margin),
      path(voronoi(from(:points), [:px, :py]), %{path: :path}, style: :cell),
      path(delaunay(from(:points), [:px, :py], output: :hull), %{path: :path}, style: :hull)
    ])
  end

  # The radius is a column, because a `:circle`'s `value` is user units and names no scale;
  # and each point's place in pixels, through the axes' own mapping of `[0, 100]`, because
  # the Voronoi and Delaunay steps are laid in pixels and read no scale.
  defp rows(opts, {plot_width, plot_height}) do
    data = opts[:data] || @data

    data =
      case opts[:animation_tick] do
        nil -> data
        tick -> animated(data, tick)
      end

    Enum.map(data, fn point ->
      Map.merge(point, %{
        r: point.size / 5 + 3,
        px: point.x / 100 * plot_width,
        py: plot_height - point.y / 100 * plot_height
      })
    end)
  end

  # Animation: each point orbits in a small circle at its own speed.
  defp animated(data, tick) do
    Enum.with_index(data, fn item, i ->
      angle = tick * (0.05 + rem(i, 5) * 0.02) + i * 0.5
      radius = 5 + rem(i, 3) * 3

      %{
        item
        | x: max(5, min(95, item.x + radius * :math.cos(angle))),
          y: max(5, min(95, item.y + radius * :math.sin(angle)))
      }
    end)
  end

  def sample_code do
    ~S"""
    import Visualize.Chart.Build

    {:ok, design} =
      Visualize.Chart.compose([
        chart(meta: %{name: "Scatter Plot"}),
        # px and py: each point placed in pixels, as the axes map 0..100 onto the plot.
        source(:points, [:x, :y, :r, :category, :px, :py]),

        # A {:field, f} on a color key goes through the `color` scale, per element.
        style(:point, fill: {:field, :category}, opacity: 0.7),
        style(:cell, fill: :none, stroke: %{color: :grid, width: 1}),
        style(:hull, fill: :none, stroke: %{color: :axis, width: 1, dash: [4, 3]}),
        cartesian(margin: %{top: 20, right: 20, bottom: 40, left: 50}),
        linear_scale(:x, domain: [0, 100]),
        linear_scale(:y, domain: [0, 100]),
        ordinal_scale(:color, domain: ["A", "B", "C"]),
        axis(:x, :bottom, ticks: 10),
        axis(:y, :left, ticks: 10),
        legend(:color, position: :top_right, title: ["Category"]),

        # The Voronoi cells and the Delaunay hull, over the pixel columns.
        path(voronoi(from(:points), [:px, :py]), %{path: :path}, style: :cell),
        path(delaunay(from(:points), [:px, :py], output: :hull), %{path: :path}, style: :hull),

        # `value` on a :circle is its radius in user units and names no scale.
        circle(:points, %{x: :x, y: :y, value: :r}, style: :point)
      ])

    {:ok, applied} = Visualize.Chart.apply(design, sources: %{points: data})
    Visualize.Chart.render(applied)
    """
  end
end
