defmodule Examples.Charts.StackedAreaChart do
  @moduledoc "Stacked area chart example"

  alias Visualize.{Scale, Axis, Shape}
  alias Visualize.SVG.Element
  alias Examples.ColorPalettes

  @data (for i <- 0..20 do
    %{
      x: i,
      apples: :rand.uniform(30) + 10,
      oranges: :rand.uniform(25) + 15,
      bananas: :rand.uniform(20) + 5,
      grapes: :rand.uniform(15) + 10,
      pears: :rand.uniform(10) + 5
    }
  end)

  def title, do: "Stacked Area Chart"
  def description, do: "Fruit production over time"

  def render(opts \\ []) do
    width = opts[:width] || 600
    height = opts[:height] || 400
    margin = %{top: 20, right: 100, bottom: 30, left: 50}

    inner_width = width - margin.left - margin.right
    inner_height = height - margin.top - margin.bottom

    palette = opts[:palette] || :default
    colors = ColorPalettes.colors(palette)
    keys = [:apples, :oranges, :bananas, :grapes, :pears]

    # Generate animated or static data
    animation_tick = opts[:animation_tick]
    data = if animation_tick do
      generate_animated_data(animation_tick)
    else
      opts[:data] || @data
    end

    # Create stack generator
    stack = Shape.Stack.new()
      |> Shape.Stack.keys(keys)

    series = Shape.Stack.generate(stack, data)

    # Find max y value across all series
    max_y = series
      |> Enum.flat_map(fn s -> Enum.map(s.points, & &1.y1) end)
      |> Enum.max()

    # Create scales
    {min_x, max_x} = {0, length(data) - 1}

    x_scale = Scale.Linear.new()
      |> Scale.Linear.domain([min_x, max_x])
      |> Scale.Linear.range([0, inner_width])

    y_scale = Scale.Linear.new()
      |> Scale.Linear.domain([0, max_y])
      |> Scale.Linear.range([inner_height, 0])
      |> Scale.Linear.nice()

    # Generate stacked areas
    areas = series
      |> Enum.with_index()
      |> Enum.map(fn {s, i} ->
        color = Enum.at(colors, rem(i, length(colors)))

        # Create area generator for this series
        area = Shape.Area.new()
          |> Shape.Area.x(fn p -> Scale.Linear.apply(x_scale, p.index) end)
          |> Shape.Area.y0(fn p -> Scale.Linear.apply(y_scale, p.y0) end)
          |> Shape.Area.y1(fn p -> Scale.Linear.apply(y_scale, p.y1) end)
          |> Shape.Area.curve(:monotone_x)

        path_data = Shape.Area.generate(area, s.points)

        Element.path(%{d: path_data, fill: color, opacity: 0.8})
      end)

    # Create axes
    x_axis = Axis.bottom(x_scale) |> Axis.ticks(10)
    y_axis = Axis.left(y_scale) |> Axis.ticks(5)

    # Legend
    legend = keys
      |> Enum.with_index()
      |> Enum.map(fn {key, i} ->
        color = Enum.at(colors, rem(i, length(colors)))
        y_pos = i * 22

        Element.g(%{transform: "translate(#{inner_width + 15},#{y_pos})"})
        |> Element.append(Element.rect(%{width: 16, height: 16, fill: color, rx: 2}))
        |> Element.append(
          Element.text(%{x: 22, y: 12, font_size: 12, fill: "#333"})
          |> Element.content(Atom.to_string(key) |> String.capitalize())
        )
      end)

    # Build chart
    chart_group = Element.g(%{transform: "translate(#{margin.left},#{margin.top})"})
      |> Element.append(areas)
      |> Element.append(legend)
      |> Element.append(
        Element.g(%{transform: "translate(0,#{inner_height})"})
        |> Element.append(Axis.generate(x_axis))
      )
      |> Element.append(Axis.generate(y_axis))

    Element.svg(%{width: width, height: height, viewBox: "0 0 #{width} #{height}"})
    |> Element.append(chart_group)
  end

  # Animation: flowing waves for each fruit category
  defp generate_animated_data(tick) do
    phase = tick * 0.1
    for i <- 0..20 do
      %{
        x: i,
        apples: 20 + 15 * :math.sin((i / 4) + phase) |> max(5),
        oranges: 25 + 12 * :math.sin((i / 5) + phase * 1.2 + 1) |> max(5),
        bananas: 15 + 10 * :math.sin((i / 3) + phase * 0.8 + 2) |> max(5),
        grapes: 18 + 8 * :math.sin((i / 6) + phase * 1.5 + 3) |> max(5),
        pears: 12 + 6 * :math.sin((i / 4) + phase * 0.9 + 4) |> max(5)
      }
    end
  end

  def sample_code do
    ~S"""
    alias Visualize.Shape

    stack = Shape.Stack.new()
      |> Shape.Stack.keys([:apples, :oranges, :bananas])

    series = Shape.Stack.generate(stack, data)

    # Each series has .points with y0 (baseline) and y1 (top)
    Enum.map(series, fn s ->
      area = Shape.Area.new()
        |> Shape.Area.y0(fn p -> y_scale(p.y0) end)
        |> Shape.Area.y1(fn p -> y_scale(p.y1) end)

      Shape.Area.generate(area, s.points)
    end)
    """
  end
end
