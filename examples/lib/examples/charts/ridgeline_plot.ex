defmodule Examples.Charts.RidgelinePlot do
  @moduledoc "Ridgeline plot (joy plot) example"

  alias Visualize.{Scale, Shape}
  alias Visualize.SVG.Element
  alias Examples.ColorPalettes

  # Generate sample distribution data for each ridge
  @num_ridges 8
  @points_per_ridge 50

  def title, do: "Ridgeline Plot"
  def description, do: "Overlapping density distributions"

  def render(opts \\ []) do
    width = opts[:width] || 600
    height = opts[:height] || 400
    margin = %{top: 20, right: 20, bottom: 30, left: 50}

    inner_width = width - margin.left - margin.right
    inner_height = height - margin.top - margin.bottom

    palette = opts[:palette] || :default
    colors = ColorPalettes.colors(palette)

    # Generate animated or static data
    animation_tick = opts[:animation_tick]
    ridges_data = if animation_tick do
      generate_animated_ridges(animation_tick)
    else
      generate_static_ridges()
    end

    num_ridges = length(ridges_data)
    ridge_height = inner_height / num_ridges
    overlap = 0.5  # How much ridges overlap

    # X scale shared across all ridges
    x_scale = Scale.Linear.new()
      |> Scale.Linear.domain([0, 100])
      |> Scale.Linear.range([0, inner_width])

    # Build ridge elements
    ridge_elements = ridges_data
    |> Enum.with_index()
    |> Enum.reverse()  # Draw back to front for proper layering
    |> Enum.map(fn {ridge_data, idx} ->
      y_offset = idx * ridge_height * (1 - overlap)

      y_scale = Scale.Linear.new()
        |> Scale.Linear.domain([0, 80])
        |> Scale.Linear.range([ridge_height, 0])

      # Create area generator
      area = Shape.Area.new()
        |> Shape.Area.x(fn d -> Scale.Linear.apply(x_scale, d.x) end)
        |> Shape.Area.y0(ridge_height)
        |> Shape.Area.y1(fn d -> Scale.Linear.apply(y_scale, d.y) end)
        |> Shape.Area.curve(:basis)

      area_path = Shape.Area.generate(area, ridge_data)

      # Create line for the top edge
      line = Shape.Line.new()
        |> Shape.Line.x(fn d -> Scale.Linear.apply(x_scale, d.x) end)
        |> Shape.Line.y(fn d -> Scale.Linear.apply(y_scale, d.y) end)
        |> Shape.Line.curve(:basis)

      line_path = Shape.Line.generate(line, ridge_data)

      color = Enum.at(colors, rem(idx, length(colors)))

      Element.g(%{transform: "translate(0,#{y_offset})"})
      |> Element.append(
        Element.path(%{d: area_path, fill: color, fill_opacity: 0.85})
      )
      |> Element.append(
        Element.path(%{d: line_path, fill: "none", stroke: color, stroke_width: 1.5})
      )
    end)

    # Build chart
    chart_group = Element.g(%{transform: "translate(#{margin.left},#{margin.top})"})
    chart_group = Enum.reduce(ridge_elements, chart_group, &Element.append(&2, &1))

    Element.svg(%{width: width, height: height, viewBox: "0 0 #{width} #{height}"})
    |> Element.append(chart_group)
  end

  defp generate_static_ridges do
    for ridge <- 0..(@num_ridges - 1) do
      ridge_phase = ridge * 0.4
      for i <- 0..(@points_per_ridge - 1) do
        x = i / (@points_per_ridge - 1) * 100
        # Create wave-like density with multiple peaks
        y = :math.sin(x / 15 + ridge_phase) * 20 +
            :math.cos(x / 10 + ridge_phase * 1.3) * 15 +
            :math.sin(x / 5 + ridge_phase * 0.7) * 10 +
            40
        %{x: x, y: max(0, y)}
      end
    end
  end

  defp generate_animated_ridges(tick) do
    phase = tick * 0.08
    for ridge <- 0..(@num_ridges - 1) do
      ridge_phase = phase + ridge * 0.3
      for i <- 0..(@points_per_ridge - 1) do
        x = i / (@points_per_ridge - 1) * 100
        y = :math.sin(x / 15 + ridge_phase) * 20 +
            :math.cos(x / 10 + ridge_phase * 1.3) * 15 +
            :math.sin(x / 5 + ridge_phase * 0.7) * 10 +
            40
        %{x: x, y: max(0, y)}
      end
    end
  end

  def sample_code do
    ~S"""
    # Ridgeline plots show multiple overlapping distributions
    # Each ridge is an area chart offset vertically

    for {ridge_data, idx} <- Enum.with_index(ridges) do
      y_offset = idx * ridge_height * (1 - overlap)

      area = Shape.Area.new()
        |> Shape.Area.x(fn d -> x_scale(d.x) end)
        |> Shape.Area.y0(ridge_height)
        |> Shape.Area.y1(fn d -> y_scale(d.y) end)
        |> Shape.Area.curve(:basis)

      # Translate each ridge vertically
      Element.g(%{transform: "translate(0,#{y_offset})"})
      |> Element.append(Element.path(%{d: area_path, fill: color}))
    end
    """
  end
end
