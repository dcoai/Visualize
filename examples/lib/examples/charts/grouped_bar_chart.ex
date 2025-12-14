defmodule Examples.Charts.GroupedBarChart do
  @moduledoc "Grouped bar chart with multiple series"

  alias Visualize.Scale
  alias Visualize.SVG.Element
  alias Examples.ColorPalettes

  @data [
    %{category: "Q1", sales: 120, expenses: 90, profit: 30},
    %{category: "Q2", sales: 150, expenses: 100, profit: 50},
    %{category: "Q3", sales: 180, expenses: 120, profit: 60},
    %{category: "Q4", sales: 200, expenses: 130, profit: 70}
  ]

  @series [:sales, :expenses, :profit]

  def title, do: "Grouped Bar Chart"
  def description, do: "Quarterly financial comparison"

  def render(opts \\ []) do
    width = opts[:width] || 500
    height = opts[:height] || 350
    margin = %{top: 30, right: 100, bottom: 50, left: 60}

    chart_width = width - margin.left - margin.right
    chart_height = height - margin.top - margin.bottom

    base_data = opts[:data] || @data
    series = @series
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
    categories = Enum.map(data, & &1.category)

    x0_scale = Scale.Band.new()
      |> Scale.Band.domain(categories)
      |> Scale.Band.range([0, chart_width])
      |> Scale.Band.padding(0.2)

    x1_scale = Scale.Band.new()
      |> Scale.Band.domain(series)
      |> Scale.Band.range([0, Scale.Band.bandwidth(x0_scale)])
      |> Scale.Band.padding(0.05)

    max_value = data
      |> Enum.flat_map(fn d -> Enum.map(series, &Map.get(d, &1, 0)) end)
      |> Enum.max()

    y_scale = Scale.Linear.new()
      |> Scale.Linear.domain([0, max_value * 1.1])
      |> Scale.Linear.range([chart_height, 0])

    # Draw bars
    bar_groups = Enum.map(data, fn d ->
      group_x = Scale.Band.apply(x0_scale, d.category)

      bars = series
        |> Enum.with_index()
        |> Enum.map(fn {key, i} ->
          value = Map.get(d, key, 0)
          bar_x = group_x + Scale.Band.apply(x1_scale, key)
          bar_y = Scale.Linear.apply(y_scale, value)
          bar_height = chart_height - bar_y

          Element.rect(%{
            x: bar_x,
            y: bar_y,
            width: Scale.Band.bandwidth(x1_scale),
            height: bar_height,
            fill: Enum.at(colors, rem(i, length(colors))),
            rx: 2
          })
        end)

      Element.g(%{}) |> Element.append(bars)
    end)

    # X-axis labels
    x_labels = Enum.map(data, fn d ->
      x = Scale.Band.apply(x0_scale, d.category) + Scale.Band.bandwidth(x0_scale) / 2

      Element.text(%{
        x: x,
        y: chart_height + 20,
        text_anchor: "middle",
        font_size: 11,
        fill: "#333"
      })
      |> Element.content(d.category)
    end)

    # Y-axis
    y_ticks = for i <- 0..5, do: max_value * 1.1 * i / 5

    y_axis = Enum.map(y_ticks, fn tick ->
      y = Scale.Linear.apply(y_scale, tick)

      Element.g(%{})
      |> Element.append(
        Element.line(%{x1: -5, x2: chart_width, y1: y, y2: y, stroke: "#ddd", stroke_width: 1})
      )
      |> Element.append(
        Element.text(%{x: -10, y: y + 4, text_anchor: "end", font_size: 10, fill: "#666"})
        |> Element.content("#{trunc(tick)}")
      )
    end)

    # Legend
    legend = series
      |> Enum.with_index()
      |> Enum.map(fn {key, i} ->
        Element.g(%{transform: "translate(#{chart_width + 20},#{i * 20})"})
        |> Element.append(
          Element.rect(%{width: 15, height: 15, fill: Enum.at(colors, rem(i, length(colors))), rx: 2})
        )
        |> Element.append(
          Element.text(%{x: 20, y: 12, font_size: 11, fill: "#333"})
          |> Element.content(Atom.to_string(key) |> String.capitalize())
        )
      end)

    # Compose SVG
    chart_group = Element.g(%{transform: "translate(#{margin.left},#{margin.top})"})
      |> Element.append(y_axis)
      |> Element.append(bar_groups)
      |> Element.append(x_labels)
      |> Element.append(legend)

    Element.svg(%{width: width, height: height, viewBox: "0 0 #{width} #{height}"})
    |> Element.append(chart_group)
  end

  # Animation: bars grow and shrink with wave effect
  defp animate_data(data, tick) do
    data
    |> Enum.with_index()
    |> Enum.map(fn {item, i} ->
      phase = i * 0.5
      # Each series oscillates with different phase
      %{
        item |
        sales: item.sales * (1.0 + 0.3 * :math.sin(tick * 0.1 + phase)),
        expenses: item.expenses * (1.0 + 0.3 * :math.sin(tick * 0.1 + phase + 1)),
        profit: item.profit * (1.0 + 0.4 * :math.sin(tick * 0.1 + phase + 2))
      }
    end)
  end

  def sample_code do
    ~S"""
    alias Visualize.Scale

    # Outer scale for categories
    x0_scale = Scale.Band.new()
      |> Scale.Band.domain(categories)
      |> Scale.Band.range([0, width])
      |> Scale.Band.padding(0.2)

    # Inner scale for series within each category
    x1_scale = Scale.Band.new()
      |> Scale.Band.domain(series_keys)
      |> Scale.Band.range([0, Scale.Band.bandwidth(x0_scale)])
      |> Scale.Band.padding(0.05)

    # Position each bar
    group_x = Scale.Band.apply(x0_scale, category)
    bar_x = group_x + Scale.Band.apply(x1_scale, series_key)
    """
  end
end
