defmodule Examples.Charts.BarChart do
  @moduledoc "Simple bar chart example"

  alias Visualize.{Scale, Axis, SVG}
  alias Visualize.SVG.Element
  alias Examples.ColorPalettes

  @data [
    %{letter: "A", frequency: 0.08167},
    %{letter: "B", frequency: 0.01492},
    %{letter: "C", frequency: 0.02782},
    %{letter: "D", frequency: 0.04253},
    %{letter: "E", frequency: 0.12702},
    %{letter: "F", frequency: 0.02288},
    %{letter: "G", frequency: 0.02015},
    %{letter: "H", frequency: 0.06094},
    %{letter: "I", frequency: 0.06966},
    %{letter: "J", frequency: 0.00153},
    %{letter: "K", frequency: 0.00772},
    %{letter: "L", frequency: 0.04025},
    %{letter: "M", frequency: 0.02406},
    %{letter: "N", frequency: 0.06749},
    %{letter: "O", frequency: 0.07507},
    %{letter: "P", frequency: 0.01929},
    %{letter: "Q", frequency: 0.00095},
    %{letter: "R", frequency: 0.05987},
    %{letter: "S", frequency: 0.06327},
    %{letter: "T", frequency: 0.09056},
    %{letter: "U", frequency: 0.02758},
    %{letter: "V", frequency: 0.00978},
    %{letter: "W", frequency: 0.02360},
    %{letter: "X", frequency: 0.00150},
    %{letter: "Y", frequency: 0.01974},
    %{letter: "Z", frequency: 0.00074}
  ]

  def title, do: "Bar Chart"
  def description, do: "Letter frequency in English text"

  def render(opts \\ []) do
    width = opts[:width] || 600
    height = opts[:height] || 400
    margin = %{top: 20, right: 20, bottom: 30, left: 40}

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

    # Create scales
    x_scale = Scale.Band.new()
      |> Scale.Band.domain(Enum.map(data, & &1.letter))
      |> Scale.Band.range([0, inner_width])
      |> Scale.Band.padding(0.1)

    max_freq = data |> Enum.map(& &1.frequency) |> Enum.max()

    y_scale = Scale.Linear.new()
      |> Scale.Linear.domain([0, max_freq])
      |> Scale.Linear.range([inner_height, 0])
      |> Scale.Linear.nice()

    # Create axes
    x_axis = Axis.bottom(x_scale)
    y_axis = Axis.left(y_scale)
      |> Axis.ticks(10)
      |> Axis.tick_format(&format_percent/1)

    # Build bars
    bars = data
      |> Enum.with_index()
      |> Enum.map(fn {d, i} ->
        x = Scale.Band.apply(x_scale, d.letter)
        y = Scale.Linear.apply(y_scale, d.frequency)
        bar_height = inner_height - y
        color = Enum.at(colors, rem(i, length(colors)))

        Element.rect(%{
          x: x,
          y: y,
          width: Scale.Band.bandwidth(x_scale),
          height: bar_height,
          fill: color
        })
      end)

    # Create chart group
    chart_group = Element.g(%{transform: "translate(#{margin.left},#{margin.top})"})
      |> Element.append(bars)
      |> Element.append(
        Element.g(%{transform: "translate(0,#{inner_height})"})
        |> Element.append(Axis.generate(x_axis))
      )
      |> Element.append(Axis.generate(y_axis))

    # Build SVG
    Element.svg(%{width: width, height: height, viewBox: "0 0 #{width} #{height}"})
    |> Element.append(chart_group)
  end

  defp format_percent(value) do
    "#{Float.round(value * 100, 1)}%"
  end

  # Animation: smoothly vary frequencies using sine waves
  defp animate_data(data, tick) do
    data
    |> Enum.with_index()
    |> Enum.map(fn {item, i} ->
      # Each bar oscillates at a different phase
      phase = i * 0.3
      # Vary between 50% and 150% of original value
      multiplier = 1.0 + 0.5 * :math.sin(tick * 0.1 + phase)
      %{item | frequency: item.frequency * multiplier}
    end)
  end

  def sample_code do
    ~S"""
    alias Visualize.{Scale, Axis, SVG}
    alias Visualize.SVG.Element

    data = [
      %{letter: "A", frequency: 0.08167},
      %{letter: "B", frequency: 0.01492},
      # ...
    ]

    x_scale = Scale.Band.new()
      |> Scale.Band.domain(Enum.map(data, & &1.letter))
      |> Scale.Band.range([0, inner_width])
      |> Scale.Band.padding(0.1)

    y_scale = Scale.Linear.new()
      |> Scale.Linear.domain([0, max_freq])
      |> Scale.Linear.range([inner_height, 0])

    bars = Enum.map(data, fn d ->
      Element.rect(%{
        x: Scale.Band.apply(x_scale, d.letter),
        y: Scale.Linear.apply(y_scale, d.frequency),
        width: Scale.Band.bandwidth(x_scale),
        height: inner_height - Scale.Linear.apply(y_scale, d.frequency),
        fill: "steelblue"
      })
    end)
    """
  end
end
