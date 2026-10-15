defmodule Examples.Charts.HexbinChart do
  @moduledoc """
  Hexbin chart as a design (#348): the `:hexbin` transform over the points under one
  `:path` mark, each cell filled by its count through a `:sequential` `color` scale.

  A hexbin's lattice is laid in pixels — the hexagon's radius is a length on the page, the
  page's slider — so the step reads pixel coordinates (spec/14 §5.4.4) and never a scale
  (D-62). The chart therefore places its points itself, through the same two linear
  mappings the frame's `x` and `y` scales draw their axes with, and hands the step the
  pixel columns; the data columns stay on the rows for the axes' domains. The count reaches
  each cell's fill as `fill: {:field, :count}` (§3.4), and the page's hex size reaches the
  step's `radius` through `design/1`'s `hex_radius` option.
  """

  import Visualize.Chart.Build

  alias Examples.Charts.Design

  @margin %{top: 40, right: 20, bottom: 40, left: 50}
  @pad 20

  # Clustered points, seeded once so the chart holds a golden.
  @points (
            :rand.seed(:exsss, {42, 42, 42})

            clusters = [
              {80, 150, 40, 120, 35},
              {60, 400, 50, 200, 45},
              {100, 280, 60, 300, 50},
              {40, 500, 30, 350, 30}
            ]

            clustered =
              for {n, cx, sx, cy, sy} <- clusters, _ <- 1..n do
                {cx + :rand.normal() * sx, cy + :rand.normal() * sy}
              end

            scattered =
              for _ <- 1..50, do: {:rand.uniform() * 600 + 50, :rand.uniform() * 380 + 30}

            clustered ++ scattered
          )

  @doc "The size this chart is drawn at when the caller names none (spec/14 §4.2)."
  def size, do: {700, 450}

  def title, do: "Hexbin Chart"
  def description, do: "Hexagonal binning for point density visualization"

  @doc "The design and the rows it binds (spec/14 §16.1)."
  def design(opts \\ []) do
    {width, height} = Design.size(__MODULE__, opts)
    radius = opts[:hex_radius] || 20
    points = points(opts[:animation_tick])
    {plot_width, plot_height} = Design.plot(width, height, @margin)
    {min_x, max_x} = points |> Enum.map(&elem(&1, 0)) |> Enum.min_max()
    {min_y, max_y} = points |> Enum.map(&elem(&1, 1)) |> Enum.min_max()
    x_domain = [min_x - @pad, max_x + @pad]
    y_domain = [min_y - @pad, max_y + @pad]

    design =
      Design.fold([
        chart(meta: %{name: title(), description: [description()]}),
        source(:points, [:x, :y, :px, :py]),
        style(:cell, fill: {:field, :count}, stroke: :axis, stroke_opacity: 0.5, stroke_width: 1),
        cartesian(margin: @margin),
        linear_scale(:x, domain: x_domain),
        linear_scale(:y, domain: y_domain),
        sequential_scale(:color, domain: [0, :auto]),
        axis(:x, :bottom, ticks: 6),
        axis(:y, :left, ticks: 5),
        label(:title, ["Point Density (#{length(points)} points)"]),
        # The lattice over the pixel columns; each cell's hexagon filled by its count.
        path(hexbin(from(:points), [:px, :py], radius: radius), %{path: :path}, style: :cell)
      ])

    rows =
      for {x, y} <- points do
        %{
          x: x,
          y: y,
          px: place(x, x_domain, 0, plot_width),
          py: place(y, y_domain, plot_height, 0)
        }
      end

    {design, %{points: rows}}
  end

  def render(opts \\ []), do: Design.render(__MODULE__, opts)

  # The linear mapping the frame's scale draws its axis with (spec/14 §4.3).
  defp place(v, [d0, d1], r0, r1), do: r0 + (v - d0) / (d1 - d0) * (r1 - r0)

  # Animation: every point drifts in a small circle about its place.
  defp points(nil), do: @points

  defp points(tick) do
    Enum.with_index(@points, fn {x, y}, i ->
      phase = i * 0.3
      {x + 5 * :math.sin(tick * 0.08 + phase), y + 5 * :math.cos(tick * 0.08 + phase + 1.0)}
    end)
  end

  def sample_code do
    ~S"""
    import Visualize.Chart.Build

    {:ok, design} =
      Visualize.Chart.compose([
        chart(meta: %{name: "Hexbin Chart"}),
        # Each row carries its data coordinates and, placed by the chart through the same
        # mapping the axes draw with, its pixel coordinates: a hexbin is laid in pixels.
        source(:points, [:x, :y, :px, :py]),
        style(:cell, fill: {:field, :count}, stroke: :axis, stroke_opacity: 0.5, stroke_width: 1),
        cartesian(margin: %{top: 40, right: 20, bottom: 40, left: 50}),
        linear_scale(:x, domain: [30, 670]),
        linear_scale(:y, domain: [10, 430]),
        sequential_scale(:color, domain: [0, :auto]),
        axis(:x, :bottom, ticks: 6),
        axis(:y, :left, ticks: 5),
        label(:title, ["Point Density"]),
        # One row per non-empty cell — its center, its count and its hexagon (spec/14
        # §5.4.4); the count is the cell's fill through the color scale.
        path(hexbin(from(:points), [:px, :py], radius: 20), %{path: :path}, style: :cell)
      ])

    {:ok, applied} = Visualize.Chart.apply(design, sources: %{points: points})
    Visualize.Chart.render(applied)
    """
  end
end
