defmodule Examples.Charts.LineChart do
  @moduledoc "Line chart example"

  alias Visualize.{Scale, Axis, Shape}
  alias Visualize.SVG.Element
  alias Examples.ColorPalettes

  @data (for i <- 0..50 do
    %{x: i, y: :math.sin(i / 5) * 50 + 50 + :rand.uniform(10) - 5}
  end)

  def title, do: "Line Chart"
  def description, do: "Sine wave with random noise"

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
    data = if animation_tick do
      generate_animated_wave(animation_tick)
    else
      opts[:data] || @data
    end

    # Create scales
    {min_x, max_x} = Enum.min_max_by(data, & &1.x) |> then(fn {a, b} -> {a.x, b.x} end)
    {min_y, max_y} = Enum.min_max_by(data, & &1.y) |> then(fn {a, b} -> {a.y, b.y} end)

    x_scale = Scale.Linear.new()
      |> Scale.Linear.domain([min_x, max_x])
      |> Scale.Linear.range([0, inner_width])

    y_scale = Scale.Linear.new()
      |> Scale.Linear.domain([min_y - 10, max_y + 10])
      |> Scale.Linear.range([inner_height, 0])
      |> Scale.Linear.nice()

    # Create line generator
    line = Shape.Line.new()
      |> Shape.Line.x(fn d -> Scale.Linear.apply(x_scale, d.x) end)
      |> Shape.Line.y(fn d -> Scale.Linear.apply(y_scale, d.y) end)
      |> Shape.Line.curve(:monotone_x)

    path_data = Shape.Line.generate(line, data)

    # Create axes
    x_axis = Axis.bottom(x_scale) |> Axis.ticks(10)
    y_axis = Axis.left(y_scale) |> Axis.ticks(5)

    # Build chart
    chart_group = Element.g(%{transform: "translate(#{margin.left},#{margin.top})"})
      |> Element.append(
        Element.path(%{
          d: path_data,
          fill: "none",
          stroke: hd(colors),
          stroke_width: 2
        })
      )
      |> Element.append(
        Element.g(%{transform: "translate(0,#{inner_height})"})
        |> Element.append(Axis.generate(x_axis))
      )
      |> Element.append(Axis.generate(y_axis))

    Element.svg(%{width: width, height: height, viewBox: "0 0 #{width} #{height}"})
    |> Element.append(chart_group)
  end

  # Animation: create a moving sine wave
  defp generate_animated_wave(tick) do
    phase = tick * 0.15  # Wave moves over time
    for i <- 0..50 do
      # Main wave with secondary harmonic
      y = :math.sin((i / 5) + phase) * 40 +
          :math.sin((i / 3) + phase * 1.5) * 15 +
          50
      %{x: i, y: y}
    end
  end

  def sample_code do
    ~S"""
    alias Visualize.{Scale, Shape}

    line = Shape.Line.new()
      |> Shape.Line.x(fn d -> Scale.Linear.apply(x_scale, d.x) end)
      |> Shape.Line.y(fn d -> Scale.Linear.apply(y_scale, d.y) end)
      |> Shape.Line.curve(:monotone_x)

    path_data = Shape.Line.generate(line, data)

    Element.path(%{
      d: path_data,
      fill: "none",
      stroke: "steelblue",
      stroke_width: 2
    })
    """
  end
end
