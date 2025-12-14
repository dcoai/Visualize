defmodule Examples.Charts.StackedBarChart do
  @moduledoc "Stacked bar chart using Stack layout"

  alias Visualize.Scale
  alias Visualize.Shape.Stack
  alias Visualize.SVG.Element
  alias Examples.ColorPalettes

  @data [
    %{year: "2019", desktop: 45, mobile: 35, tablet: 15, other: 5},
    %{year: "2020", desktop: 40, mobile: 42, tablet: 13, other: 5},
    %{year: "2021", desktop: 35, mobile: 48, tablet: 12, other: 5},
    %{year: "2022", desktop: 30, mobile: 52, tablet: 12, other: 6},
    %{year: "2023", desktop: 28, mobile: 55, tablet: 11, other: 6}
  ]

  @keys [:desktop, :mobile, :tablet, :other]

  def title, do: "Stacked Bar Chart"
  def description, do: "Device usage trends"

  def render(opts \\ []) do
    width = opts[:width] || 500
    height = opts[:height] || 350
    margin = %{top: 30, right: 100, bottom: 50, left: 50}

    chart_width = width - margin.left - margin.right
    chart_height = height - margin.top - margin.bottom

    base_data = opts[:data] || @data
    keys = @keys
    palette = opts[:palette] || :default
    colors = ColorPalettes.colors(palette)

    # Apply animation if tick is provided
    animation_tick = opts[:animation_tick]
    data = if animation_tick do
      animate_data(base_data, animation_tick)
    else
      base_data
    end

    # Create stack
    stack = Stack.new()
      |> Stack.keys(keys)

    series = Stack.generate(stack, data)

    # Create scales
    years = Enum.map(data, & &1.year)

    x_scale = Scale.Band.new()
      |> Scale.Band.domain(years)
      |> Scale.Band.range([0, chart_width])
      |> Scale.Band.padding(0.2)

    # Find max stacked value
    max_value = series
      |> Enum.flat_map(fn s -> Enum.map(s.points, & &1.y1) end)
      |> Enum.max()

    y_scale = Scale.Linear.new()
      |> Scale.Linear.domain([0, max_value])
      |> Scale.Linear.range([chart_height, 0])

    # Draw stacked bars
    bar_elements = series
      |> Enum.with_index()
      |> Enum.flat_map(fn {s, series_idx} ->
        color = Enum.at(colors, rem(series_idx, length(colors)))

        Enum.map(s.points, fn point ->
          x = Scale.Band.apply(x_scale, point.data.year)
          y0 = Scale.Linear.apply(y_scale, point.y0)
          y1 = Scale.Linear.apply(y_scale, point.y1)

          Element.rect(%{
            x: x,
            y: y1,
            width: Scale.Band.bandwidth(x_scale),
            height: y0 - y1,
            fill: color
          })
        end)
      end)

    # X-axis labels
    x_labels = Enum.map(data, fn d ->
      x = Scale.Band.apply(x_scale, d.year) + Scale.Band.bandwidth(x_scale) / 2

      Element.text(%{
        x: x,
        y: chart_height + 20,
        text_anchor: "middle",
        font_size: 11,
        fill: "#333"
      })
      |> Element.content(d.year)
    end)

    # Y-axis
    y_ticks = for i <- 0..5, do: max_value * i / 5

    y_axis = Enum.map(y_ticks, fn tick ->
      y = Scale.Linear.apply(y_scale, tick)

      Element.g(%{})
      |> Element.append(
        Element.line(%{x1: 0, x2: chart_width, y1: y, y2: y, stroke: "#eee", stroke_width: 1})
      )
      |> Element.append(
        Element.text(%{x: -10, y: y + 4, text_anchor: "end", font_size: 10, fill: "#666"})
        |> Element.content("#{trunc(tick)}%")
      )
    end)

    # Legend
    legend = keys
      |> Enum.with_index()
      |> Enum.map(fn {key, i} ->
        Element.g(%{transform: "translate(#{chart_width + 15},#{i * 20})"})
        |> Element.append(
          Element.rect(%{width: 15, height: 15, fill: Enum.at(colors, rem(i, length(colors)))})
        )
        |> Element.append(
          Element.text(%{x: 20, y: 12, font_size: 10, fill: "#333"})
          |> Element.content(Atom.to_string(key) |> String.capitalize())
        )
      end)

    # Compose SVG
    chart_group = Element.g(%{transform: "translate(#{margin.left},#{margin.top})"})
      |> Element.append(y_axis)
      |> Element.append(bar_elements)
      |> Element.append(x_labels)
      |> Element.append(legend)

    Element.svg(%{width: width, height: height, viewBox: "0 0 #{width} #{height}"})
    |> Element.append(chart_group)
  end

  # Animation: device usage shifts over time
  defp animate_data(data, tick) do
    data
    |> Enum.with_index()
    |> Enum.map(fn {item, i} ->
      phase = i * 0.6
      # Each device category shifts with different phases
      %{
        item |
        desktop: item.desktop * (1.0 + 0.25 * :math.sin(tick * 0.08 + phase)),
        mobile: item.mobile * (1.0 + 0.2 * :math.sin(tick * 0.08 + phase + 1.5)),
        tablet: item.tablet * (1.0 + 0.3 * :math.sin(tick * 0.08 + phase + 3)),
        other: item.other * (1.0 + 0.35 * :math.sin(tick * 0.08 + phase + 4.5))
      }
    end)
  end

  def sample_code do
    ~S"""
    alias Visualize.Shape.Stack

    stack = Stack.new()
      |> Stack.keys([:apples, :oranges, :bananas])

    series = Stack.generate(stack, data)

    # Each series has points with y0 (baseline) and y1 (top)
    Enum.each(series, fn s ->
      Enum.each(s.points, fn point ->
        # point.y0 = baseline
        # point.y1 = top of stack
        # point.data = original datum
      end)
    end)
    """
  end
end
