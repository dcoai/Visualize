defmodule Examples.Charts.AreaChart do
  @moduledoc "Area chart example"

  alias Visualize.{Scale, Axis, Shape}
  alias Visualize.SVG.Element
  alias Examples.ColorPalettes

  @data (for i <- 0..30 do
    %{
      x: i,
      y: :math.sin(i / 4) * 30 + 50 + :rand.uniform(10)
    }
  end)

  def title, do: "Area Chart"
  def description, do: "Filled area under curve"

  def render(opts \\ []) do
    width = opts[:width] || 600
    height = opts[:height] || 400
    margin = %{top: 20, right: 20, bottom: 30, left: 50}

    inner_width = width - margin.left - margin.right
    inner_height = height - margin.top - margin.bottom

    palette = opts[:palette] || :default
    color = hd(ColorPalettes.colors(palette))

    # Generate animated or static data
    animation_tick = opts[:animation_tick]
    data = if animation_tick do
      generate_animated_wave(animation_tick)
    else
      opts[:data] || @data
    end

    # Create scales
    {min_x, max_x} = Enum.min_max_by(data, & &1.x) |> then(fn {a, b} -> {a.x, b.x} end)
    {_min_y, max_y} = Enum.min_max_by(data, & &1.y) |> then(fn {a, b} -> {a.y, b.y} end)

    x_scale = Scale.Linear.new()
      |> Scale.Linear.domain([min_x, max_x])
      |> Scale.Linear.range([0, inner_width])

    y_scale = Scale.Linear.new()
      |> Scale.Linear.domain([0, max_y + 10])
      |> Scale.Linear.range([inner_height, 0])
      |> Scale.Linear.nice()

    # Create area generator
    area = Shape.Area.new()
      |> Shape.Area.x(fn d -> Scale.Linear.apply(x_scale, d.x) end)
      |> Shape.Area.y0(inner_height)
      |> Shape.Area.y1(fn d -> Scale.Linear.apply(y_scale, d.y) end)
      |> Shape.Area.curve(:monotone_x)

    area_path = Shape.Area.generate(area, data)

    # Create line for the top edge
    line = Shape.Line.new()
      |> Shape.Line.x(fn d -> Scale.Linear.apply(x_scale, d.x) end)
      |> Shape.Line.y(fn d -> Scale.Linear.apply(y_scale, d.y) end)
      |> Shape.Line.curve(:monotone_x)

    line_path = Shape.Line.generate(line, data)

    # Create axes
    x_axis = Axis.bottom(x_scale) |> Axis.ticks(10)
    y_axis = Axis.left(y_scale) |> Axis.ticks(5)

    # Create gradient
    gradient = Element.defs(%{})
      |> Element.append(
        Element.linearGradient(%{id: "area-gradient", x1: 0, y1: 0, x2: 0, y2: 1})
        |> Element.append(Element.stop(%{offset: "0%", stop_color: color, stop_opacity: 0.8}))
        |> Element.append(Element.stop(%{offset: "100%", stop_color: color, stop_opacity: 0.1}))
      )

    # Build chart
    chart_group = Element.g(%{transform: "translate(#{margin.left},#{margin.top})"})
      |> Element.append(
        Element.path(%{d: area_path, fill: "url(#area-gradient)"})
      )
      |> Element.append(
        Element.path(%{d: line_path, fill: "none", stroke: color, stroke_width: 2})
      )
      |> Element.append(
        Element.g(%{transform: "translate(0,#{inner_height})"})
        |> Element.append(Axis.generate(x_axis))
      )
      |> Element.append(Axis.generate(y_axis))

    Element.svg(%{width: width, height: height, viewBox: "0 0 #{width} #{height}"})
    |> Element.append(gradient)
    |> Element.append(chart_group)
  end

  # Animation: create a moving wave
  defp generate_animated_wave(tick) do
    phase = tick * 0.15
    for i <- 0..30 do
      y = :math.sin((i / 4) + phase) * 30 +
          :math.sin((i / 2) + phase * 1.3) * 10 +
          50
      %{x: i, y: max(5, y)}
    end
  end

  def sample_code do
    ~S"""
    alias Visualize.Shape

    area = Shape.Area.new()
      |> Shape.Area.x(fn d -> x_scale(d.x) end)
      |> Shape.Area.y0(inner_height)  # baseline
      |> Shape.Area.y1(fn d -> y_scale(d.y) end)
      |> Shape.Area.curve(:monotone_x)

    area_path = Shape.Area.generate(area, data)
    """
  end
end
