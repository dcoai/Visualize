defmodule Examples.Charts.BubbleChart do
  @moduledoc "Bubble chart with three dimensions"

  alias Visualize.Scale
  alias Visualize.SVG.Element
  alias Examples.ColorPalettes

  @data [
    %{name: "US", gdp: 21.4, population: 331, region: "Americas"},
    %{name: "China", gdp: 14.7, population: 1412, region: "Asia"},
    %{name: "Japan", gdp: 5.1, population: 126, region: "Asia"},
    %{name: "Germany", gdp: 4.2, population: 83, region: "Europe"},
    %{name: "UK", gdp: 2.8, population: 67, region: "Europe"},
    %{name: "France", gdp: 2.9, population: 67, region: "Europe"},
    %{name: "India", gdp: 2.9, population: 1380, region: "Asia"},
    %{name: "Italy", gdp: 2.1, population: 60, region: "Europe"},
    %{name: "Brazil", gdp: 1.4, population: 213, region: "Americas"},
    %{name: "Canada", gdp: 1.6, population: 38, region: "Americas"},
    %{name: "Russia", gdp: 1.5, population: 144, region: "Europe"},
    %{name: "Australia", gdp: 1.3, population: 26, region: "Oceania"},
    %{name: "Spain", gdp: 1.4, population: 47, region: "Europe"},
    %{name: "Mexico", gdp: 1.1, population: 129, region: "Americas"},
    %{name: "Indonesia", gdp: 1.1, population: 274, region: "Asia"}
  ]

  @regions ["Americas", "Asia", "Europe", "Oceania"]

  def title, do: "Bubble Chart"
  def description, do: "GDP vs Population (bubble = GDP per capita)"

  def render(opts \\ []) do
    width = opts[:width] || 600
    height = opts[:height] || 400
    margin = %{top: 30, right: 120, bottom: 50, left: 70}

    chart_width = width - margin.left - margin.right
    chart_height = height - margin.top - margin.bottom

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

    # Create scales
    x_scale = Scale.Linear.new()
      |> Scale.Linear.domain([0, 1500])
      |> Scale.Linear.range([0, chart_width])

    y_scale = Scale.Linear.new()
      |> Scale.Linear.domain([0, 25])
      |> Scale.Linear.range([chart_height, 0])

    # Bubble size based on GDP per capita
    max_gdp_pc = data
      |> Enum.map(fn d -> d.gdp * 1000 / d.population end)
      |> Enum.max()

    size_scale = Scale.Linear.new()
      |> Scale.Linear.domain([0, max_gdp_pc])
      |> Scale.Linear.range([5, 40])

    # Draw bubbles
    bubbles = data
      |> Enum.sort_by(fn d -> -d.gdp * 1000 / d.population end)  # Draw larger first
      |> Enum.map(fn d ->
        x = Scale.Linear.apply(x_scale, d.population)
        y = Scale.Linear.apply(y_scale, d.gdp)
        gdp_per_capita = d.gdp * 1000 / d.population
        r = Scale.Linear.apply(size_scale, gdp_per_capita)

        region_idx = Enum.find_index(@regions, &(&1 == d.region)) || 0
        color = Enum.at(colors, rem(region_idx, length(colors)))

        group = Element.g(%{})
          |> Element.append(
            Element.circle(%{
              cx: x,
              cy: y,
              r: r,
              fill: color,
              fill_opacity: 0.7,
              stroke: color,
              stroke_width: 1
            })
          )

        # Add label for larger bubbles
        if r > 15 do
          Element.append(group,
            Element.text(%{
              x: x,
              y: y + 4,
              text_anchor: "middle",
              font_size: 9,
              fill: "#333",
              font_weight: "bold"
            })
            |> Element.content(d.name)
          )
        else
          group
        end
      end)

    # X-axis
    x_ticks = [0, 300, 600, 900, 1200, 1500]
    x_axis = Enum.map(x_ticks, fn tick ->
      x = Scale.Linear.apply(x_scale, tick)

      Element.g(%{})
      |> Element.append(
        Element.line(%{x1: x, x2: x, y1: chart_height, y2: chart_height + 5, stroke: "#666"})
      )
      |> Element.append(
        Element.text(%{x: x, y: chart_height + 20, text_anchor: "middle", font_size: 10, fill: "#666"})
        |> Element.content("#{tick}")
      )
    end)

    x_label = Element.text(%{
      x: chart_width / 2,
      y: chart_height + 40,
      text_anchor: "middle",
      font_size: 11,
      fill: "#333"
    })
    |> Element.content("Population (millions)")

    # Y-axis
    y_ticks = [0, 5, 10, 15, 20, 25]
    y_axis = Enum.map(y_ticks, fn tick ->
      y = Scale.Linear.apply(y_scale, tick)

      Element.g(%{})
      |> Element.append(
        Element.line(%{x1: -5, x2: chart_width, y1: y, y2: y, stroke: "#eee"})
      )
      |> Element.append(
        Element.text(%{x: -10, y: y + 4, text_anchor: "end", font_size: 10, fill: "#666"})
        |> Element.content("$#{tick}T")
      )
    end)

    y_label = Element.text(%{
      x: -chart_height / 2,
      y: -50,
      text_anchor: "middle",
      font_size: 11,
      fill: "#333",
      transform: "rotate(-90)"
    })
    |> Element.content("GDP (trillions USD)")

    # Legend
    legend = @regions
      |> Enum.with_index()
      |> Enum.map(fn {region, i} ->
        Element.g(%{transform: "translate(#{chart_width + 20},#{i * 25 + 20})"})
        |> Element.append(
          Element.circle(%{cx: 8, cy: 8, r: 8, fill: Enum.at(colors, rem(i, length(colors))), fill_opacity: 0.7})
        )
        |> Element.append(
          Element.text(%{x: 22, y: 12, font_size: 10, fill: "#333"})
          |> Element.content(region)
        )
      end)

    # Size legend
    size_legend = Element.g(%{transform: "translate(#{chart_width + 20},#{length(@regions) * 25 + 50})"})
      |> Element.append(
        Element.text(%{font_size: 9, fill: "#666"})
        |> Element.content("Size = GDP/capita")
      )

    # Compose SVG
    chart_group = Element.g(%{transform: "translate(#{margin.left},#{margin.top})"})
      |> Element.append(y_axis)
      |> Element.append(x_axis)
      |> Element.append(bubbles)
      |> Element.append(x_label)
      |> Element.append(y_label)
      |> Element.append(legend)
      |> Element.append(size_legend)

    Element.svg(%{width: width, height: height, viewBox: "0 0 #{width} #{height}"})
    |> Element.append(chart_group)
  end

  # Animation: bubbles gently float and pulse
  defp animate_data(data, tick) do
    data
    |> Enum.with_index()
    |> Enum.map(fn {item, i} ->
      phase = i * 0.7
      # Vary GDP slightly (economic fluctuation)
      gdp_mult = 1.0 + 0.15 * :math.sin(tick * 0.08 + phase)
      # Population stays mostly stable with tiny drift
      pop_mult = 1.0 + 0.03 * :math.sin(tick * 0.05 + phase + 2)
      %{item |
        gdp: item.gdp * gdp_mult,
        population: item.population * pop_mult
      }
    end)
  end

  def sample_code do
    ~S"""
    alias Visualize.Scale

    # Three scales for three dimensions
    x_scale = Scale.Linear.new()  # Position X (e.g., population)
    y_scale = Scale.Linear.new()  # Position Y (e.g., GDP)
    size_scale = Scale.Linear.new()  # Bubble radius (e.g., per capita)

    # Draw bubbles
    Element.circle(%{
      cx: Scale.Linear.apply(x_scale, d.x),
      cy: Scale.Linear.apply(y_scale, d.y),
      r: Scale.Linear.apply(size_scale, d.size),
      fill: color
    })
    """
  end
end
