defmodule Examples.Charts.HorizontalBarChart do
  @moduledoc "Horizontal bar chart example"

  alias Visualize.{Scale, Axis}
  alias Visualize.SVG.Element
  alias Examples.ColorPalettes

  @data [
    %{country: "China", population: 1412},
    %{country: "India", population: 1380},
    %{country: "United States", population: 331},
    %{country: "Indonesia", population: 273},
    %{country: "Pakistan", population: 220},
    %{country: "Brazil", population: 212},
    %{country: "Nigeria", population: 206},
    %{country: "Bangladesh", population: 164}
  ]

  def title, do: "Horizontal Bar Chart"
  def description, do: "World population by country (millions)"

  def render(opts \\ []) do
    width = opts[:width] || 600
    height = opts[:height] || 400
    margin = %{top: 20, right: 30, bottom: 40, left: 100}

    inner_width = width - margin.left - margin.right
    inner_height = height - margin.top - margin.bottom

    base_data = opts[:data] || @data
    palette = opts[:palette] || :default
    colors = ColorPalettes.colors(palette)

    # Apply animation if tick is provided
    animation_tick = opts[:animation_tick]
    data = if animation_tick do
      animate_data(base_data, animation_tick)
    else
      base_data
    end

    # Sort data by population descending
    sorted_data = Enum.sort_by(data, & &1.population, :desc)

    # Create scales
    y_scale = Scale.Band.new()
      |> Scale.Band.domain(Enum.map(sorted_data, & &1.country))
      |> Scale.Band.range([0, inner_height])
      |> Scale.Band.padding(0.2)

    max_pop = sorted_data |> Enum.map(& &1.population) |> Enum.max()

    x_scale = Scale.Linear.new()
      |> Scale.Linear.domain([0, max_pop])
      |> Scale.Linear.range([0, inner_width])
      |> Scale.Linear.nice()

    # Create axes
    x_axis = Axis.bottom(x_scale)
      |> Axis.ticks(5)
      |> Axis.tick_format(&format_population/1)

    y_axis = Axis.left(y_scale)

    # Build bars
    bars = sorted_data
      |> Enum.with_index()
      |> Enum.map(fn {d, i} ->
        y = Scale.Band.apply(y_scale, d.country)
        bar_width = Scale.Linear.apply(x_scale, d.population)
        color = Enum.at(colors, rem(i, length(colors)))

        Element.g(%{})
          |> Element.append(
            Element.rect(%{
              x: 0,
              y: y,
              width: bar_width,
              height: Scale.Band.bandwidth(y_scale),
              fill: color,
              rx: 2
            })
          )
          |> Element.append(
            Element.text(%{
              x: bar_width + 5,
              y: y + Scale.Band.bandwidth(y_scale) / 2 + 4,
              font_size: 11,
              fill: ColorPalettes.text_color(palette)
            })
            |> Element.content("#{d.population}M")
          )
      end)

    # Build chart
    chart_group = Element.g(%{transform: "translate(#{margin.left},#{margin.top})"})
      |> Element.append(bars)
      |> Element.append(
        Element.g(%{transform: "translate(0,#{inner_height})"})
        |> Element.append(Axis.generate(x_axis))
      )
      |> Element.append(Axis.generate(y_axis))

    Element.svg(%{width: width, height: height, viewBox: "0 0 #{width} #{height}"})
    |> Element.append(chart_group)
  end

  defp format_population(value) do
    "#{trunc(value)}M"
  end

  # Animation: bars grow and shrink with different phases
  defp animate_data(data, tick) do
    data
    |> Enum.with_index()
    |> Enum.map(fn {item, i} ->
      phase = i * 0.4
      # Vary between 70% and 130% of original value
      multiplier = 1.0 + 0.3 * :math.sin(tick * 0.1 + phase)
      %{item | population: item.population * multiplier}
    end)
  end

  def sample_code do
    ~S"""
    # Horizontal bar uses Band scale on Y axis
    y_scale = Scale.Band.new()
      |> Scale.Band.domain(categories)
      |> Scale.Band.range([0, inner_height])
      |> Scale.Band.padding(0.2)

    x_scale = Scale.Linear.new()
      |> Scale.Linear.domain([0, max_value])
      |> Scale.Linear.range([0, inner_width])

    # Bars are drawn with width from x_scale
    Element.rect(%{
      x: 0,
      y: y_scale(category),
      width: x_scale(value),
      height: bandwidth
    })
    """
  end
end
