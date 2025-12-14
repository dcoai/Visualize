defmodule Examples.Charts.HexbinChart do
  @moduledoc "Hexagonal binning chart for visualizing point density"

  alias Visualize.{Scale, Axis}
  alias Visualize.SVG.Element
  alias Examples.ColorPalettes

  # Generate sample data - clustered points
  @sample_data (
    :rand.seed(:exsss, {42, 42, 42})

    # Create several clusters of points
    cluster1 = for _ <- 1..80 do
      {150 + :rand.normal() * 40, 120 + :rand.normal() * 35}
    end

    cluster2 = for _ <- 1..60 do
      {400 + :rand.normal() * 50, 200 + :rand.normal() * 45}
    end

    cluster3 = for _ <- 1..100 do
      {280 + :rand.normal() * 60, 300 + :rand.normal() * 50}
    end

    cluster4 = for _ <- 1..40 do
      {500 + :rand.normal() * 30, 350 + :rand.normal() * 30}
    end

    # Some scattered points
    scattered = for _ <- 1..50 do
      {:rand.uniform() * 600 + 50, :rand.uniform() * 380 + 30}
    end

    cluster1 ++ cluster2 ++ cluster3 ++ cluster4 ++ scattered
  )

  def title, do: "Hexbin Chart"
  def description, do: "Hexagonal binning for point density visualization"

  def render(opts \\ []) do
    width = opts[:width] || 700
    height = opts[:height] || 450
    animation_tick = opts[:animation_tick]
    palette = opts[:palette] || :default
    colors = ColorPalettes.colors(palette)

    margin = %{top: 20, right: 20, bottom: 40, left: 50}
    inner_width = width - margin.left - margin.right
    inner_height = height - margin.top - margin.bottom

    # Hex radius
    hex_radius = 20

    # Get data (animate by adding jitter)
    data = if animation_tick do
      animate_data(@sample_data, animation_tick)
    else
      @sample_data
    end

    # Scale data to fit in chart area
    {min_x, max_x} = data |> Enum.map(&elem(&1, 0)) |> Enum.min_max()
    {min_y, max_y} = data |> Enum.map(&elem(&1, 1)) |> Enum.min_max()

    x_scale = Scale.Linear.new()
      |> Scale.Linear.domain([min_x - 20, max_x + 20])
      |> Scale.Linear.range([0, inner_width])

    y_scale = Scale.Linear.new()
      |> Scale.Linear.domain([min_y - 20, max_y + 20])
      |> Scale.Linear.range([inner_height, 0])

    # Scale the data points
    scaled_data = Enum.map(data, fn {x, y} ->
      {Scale.Linear.apply(x_scale, x), Scale.Linear.apply(y_scale, y)}
    end)

    # Compute hexbin
    bins = hexbin(scaled_data, hex_radius)

    # Find max count for color scaling
    max_count = bins |> Enum.map(& &1.count) |> Enum.max(fn -> 1 end)

    # Create color scale (use first few colors from palette for gradient effect)
    base_color = Enum.at(colors, 0)

    # Draw hexagons
    hex_elements = Enum.map(bins, fn bin ->
      # Color intensity based on count
      opacity = 0.2 + 0.8 * (bin.count / max_count)

      Element.path(%{
        d: hexagon_path(bin.x, bin.y, hex_radius),
        fill: base_color,
        fill_opacity: opacity,
        stroke: darken(base_color),
        stroke_width: 1,
        stroke_opacity: 0.5
      })
    end)

    # Create axes
    x_axis = Axis.bottom(x_scale) |> Axis.ticks(6)
    y_axis = Axis.left(y_scale) |> Axis.ticks(5)

    # Chart group with margin transform
    chart_group = Element.g(%{transform: "translate(#{margin.left},#{margin.top})"})
      |> Element.append(hex_elements)
      |> Element.append(
        Element.g(%{transform: "translate(0,#{inner_height})"})
        |> Element.append(Axis.generate(x_axis))
      )
      |> Element.append(Axis.generate(y_axis))

    # Title
    title = Element.text(%{
      x: width / 2,
      y: 15,
      text_anchor: "middle",
      font_size: 14,
      font_weight: "bold",
      fill: "#333"
    })
    |> Element.content("Point Density (#{length(data)} points)")

    Element.svg(%{width: width, height: height, viewBox: "0 0 #{width} #{height}"})
    |> Element.append(chart_group)
    |> Element.append(title)
  end

  # Hexagonal binning algorithm
  defp hexbin(points, radius) do
    # Hexagon dimensions
    dx = radius * 2 * :math.sin(:math.pi() / 3)  # horizontal spacing
    dy = radius * 1.5  # vertical spacing

    # Group points into bins
    bins = Enum.reduce(points, %{}, fn {px, py}, acc ->
      # Find which hexagon this point belongs to
      col = px / dx
      row = py / dy

      # Offset for odd rows
      col_offset = if trunc(row) |> rem(2) == 1, do: 0.5, else: 0

      # Round to nearest hex center
      hex_col = round(col - col_offset)
      hex_row = round(row)

      # Compute actual hex center
      cx = (hex_col + (if rem(hex_row, 2) == 1, do: 0.5, else: 0)) * dx
      cy = hex_row * dy

      key = {hex_col, hex_row}

      Map.update(acc, key, %{x: cx, y: cy, count: 1, points: [{px, py}]}, fn bin ->
        %{bin | count: bin.count + 1, points: [{px, py} | bin.points]}
      end)
    end)

    Map.values(bins)
  end

  # Generate SVG path for a flat-topped hexagon
  defp hexagon_path(cx, cy, radius) do
    angles = for i <- 0..5 do
      angle = :math.pi() / 3 * i - :math.pi() / 6
      x = cx + radius * :math.cos(angle)
      y = cy + radius * :math.sin(angle)
      {x, y}
    end

    [{x0, y0} | rest] = angles

    path = "M#{Float.round(x0, 2)},#{Float.round(y0, 2)}"

    rest_path = Enum.map(rest, fn {x, y} ->
      "L#{Float.round(x, 2)},#{Float.round(y, 2)}"
    end)
    |> Enum.join()

    path <> rest_path <> "Z"
  end

  # Animation: add subtle jitter to points
  defp animate_data(data, tick) do
    data
    |> Enum.with_index()
    |> Enum.map(fn {{x, y}, i} ->
      phase = i * 0.3
      jitter_x = 5 * :math.sin(tick * 0.08 + phase)
      jitter_y = 5 * :math.cos(tick * 0.08 + phase + 1.0)
      {x + jitter_x, y + jitter_y}
    end)
  end

  defp darken("#" <> hex) do
    {r, ""} = Integer.parse(String.slice(hex, 0, 2), 16)
    {g, ""} = Integer.parse(String.slice(hex, 2, 2), 16)
    {b, ""} = Integer.parse(String.slice(hex, 4, 2), 16)

    r = trunc(r * 0.7)
    g = trunc(g * 0.7)
    b = trunc(b * 0.7)

    "#" <>
      (Integer.to_string(r, 16) |> String.pad_leading(2, "0")) <>
      (Integer.to_string(g, 16) |> String.pad_leading(2, "0")) <>
      (Integer.to_string(b, 16) |> String.pad_leading(2, "0"))
  end

  def sample_code do
    ~S"""
    # Hexbin groups points into hexagonal bins
    # Each bin's opacity reflects point density

    data = [
      {x1, y1}, {x2, y2}, ...
    ]

    # Hexbin algorithm:
    # 1. Define hex grid with radius
    # 2. Assign each point to nearest hex center
    # 3. Count points per hex
    # 4. Color by count (opacity or color scale)

    hex_radius = 20
    bins = hexbin(scaled_data, hex_radius)

    # Draw hexagons with opacity based on count
    Enum.map(bins, fn bin ->
      opacity = bin.count / max_count
      Element.path(%{
        d: hexagon_path(bin.x, bin.y, radius),
        fill: color,
        fill_opacity: opacity
      })
    end)
    """
  end
end
