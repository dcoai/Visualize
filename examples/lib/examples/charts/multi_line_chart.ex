defmodule Examples.Charts.MultiLineChart do
  @moduledoc "Multi-series line chart example"

  alias Visualize.{Scale, Axis, Shape}
  alias Visualize.SVG.Element
  alias Examples.ColorPalettes

  # Generate multiple series
  @data %{
    series_a: for(i <- 0..30, do: %{x: i, y: :math.sin(i / 5) * 30 + 50}),
    series_b: for(i <- 0..30, do: %{x: i, y: :math.cos(i / 5) * 25 + 45}),
    series_c: for(i <- 0..30, do: %{x: i, y: :math.sin(i / 3) * 20 + 60}),
    series_d: for(i <- 0..30, do: %{x: i, y: :math.cos(i / 4) * 15 + 40})
  }

  def title, do: "Multi-line Chart"
  def description, do: "Multiple data series comparison"

  def render(opts \\ []) do
    width = opts[:width] || 600
    height = opts[:height] || 400
    margin = %{top: 20, right: 120, bottom: 30, left: 50}

    inner_width = width - margin.left - margin.right
    inner_height = height - margin.top - margin.bottom

    palette = opts[:palette] || :default
    colors = ColorPalettes.colors(palette)

    # Generate animated or static data
    animation_tick = opts[:animation_tick]
    data = if animation_tick do
      generate_animated_series(animation_tick)
    else
      opts[:data] || @data
    end

    series_keys = Map.keys(data)

    # Find data extent
    all_points = data |> Map.values() |> List.flatten()
    {min_x, max_x} = Enum.min_max_by(all_points, & &1.x) |> then(fn {a, b} -> {a.x, b.x} end)
    {min_y, max_y} = Enum.min_max_by(all_points, & &1.y) |> then(fn {a, b} -> {a.y, b.y} end)

    # Create scales
    x_scale = Scale.Linear.new()
      |> Scale.Linear.domain([min_x, max_x])
      |> Scale.Linear.range([0, inner_width])

    y_scale = Scale.Linear.new()
      |> Scale.Linear.domain([min_y - 10, max_y + 10])
      |> Scale.Linear.range([inner_height, 0])
      |> Scale.Linear.nice()

    # Generate lines for each series
    lines = series_keys
      |> Enum.with_index()
      |> Enum.map(fn {key, i} ->
        color = Enum.at(colors, rem(i, length(colors)))
        series_data = Map.get(data, key)

        line = Shape.Line.new()
          |> Shape.Line.x(fn d -> Scale.Linear.apply(x_scale, d.x) end)
          |> Shape.Line.y(fn d -> Scale.Linear.apply(y_scale, d.y) end)
          |> Shape.Line.curve(:monotone_x)

        path_data = Shape.Line.generate(line, series_data)

        Element.path(%{
          d: path_data,
          fill: "none",
          stroke: color,
          stroke_width: 2
        })
      end)

    # Create axes
    x_axis = Axis.bottom(x_scale) |> Axis.ticks(10)
    y_axis = Axis.left(y_scale) |> Axis.ticks(5)

    # Legend
    legend = series_keys
      |> Enum.with_index()
      |> Enum.map(fn {key, i} ->
        color = Enum.at(colors, rem(i, length(colors)))
        y_pos = i * 22

        Element.g(%{transform: "translate(#{inner_width + 15},#{y_pos})"})
        |> Element.append(
          Element.line(%{x1: 0, y1: 8, x2: 20, y2: 8, stroke: color, stroke_width: 2})
        )
        |> Element.append(
          Element.text(%{x: 26, y: 12, font_size: 12, fill: "#333"})
          |> Element.content(format_key(key))
        )
      end)

    # Build chart
    chart_group = Element.g(%{transform: "translate(#{margin.left},#{margin.top})"})
      |> Element.append(lines)
      |> Element.append(legend)
      |> Element.append(
        Element.g(%{transform: "translate(0,#{inner_height})"})
        |> Element.append(Axis.generate(x_axis))
      )
      |> Element.append(Axis.generate(y_axis))

    Element.svg(%{width: width, height: height, viewBox: "0 0 #{width} #{height}"})
    |> Element.append(chart_group)
  end

  defp format_key(key) do
    key
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  # Animation: moving waves with different frequencies
  defp generate_animated_series(tick) do
    phase = tick * 0.12
    %{
      series_a: for(i <- 0..30, do: %{x: i, y: :math.sin((i / 5) + phase) * 30 + 50}),
      series_b: for(i <- 0..30, do: %{x: i, y: :math.cos((i / 5) + phase * 1.2) * 25 + 45}),
      series_c: for(i <- 0..30, do: %{x: i, y: :math.sin((i / 3) + phase * 0.8) * 20 + 60}),
      series_d: for(i <- 0..30, do: %{x: i, y: :math.cos((i / 4) + phase * 1.5) * 15 + 40})
    }
  end

  def sample_code do
    ~S"""
    alias Visualize.Shape

    # Create multiple line generators
    Enum.map(series_data, fn {key, points} ->
      line = Shape.Line.new()
        |> Shape.Line.x(fn d -> x_scale(d.x) end)
        |> Shape.Line.y(fn d -> y_scale(d.y) end)
        |> Shape.Line.curve(:monotone_x)

      Element.path(%{
        d: Shape.Line.generate(line, points),
        fill: "none",
        stroke: color
      })
    end)
    """
  end
end
