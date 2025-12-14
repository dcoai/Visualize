defmodule Examples.Charts.ScatterPlot do
  @moduledoc "Scatter plot example"

  alias Visualize.{Scale, Axis}
  alias Visualize.SVG.Element
  alias Examples.ColorPalettes

  # Generate random data points with categories
  @data (for _ <- 1..100 do
    category = Enum.random(["A", "B", "C"])
    %{
      x: :rand.uniform() * 100,
      y: :rand.uniform() * 100,
      size: :rand.uniform() * 20 + 5,
      category: category
    }
  end)

  @categories ["A", "B", "C"]

  def title, do: "Scatter Plot"
  def description, do: "Random data points with categories"

  def render(opts \\ []) do
    width = opts[:width] || 600
    height = opts[:height] || 400
    margin = %{top: 20, right: 20, bottom: 40, left: 50}

    inner_width = width - margin.left - margin.right
    inner_height = height - margin.top - margin.bottom

    base_data = opts[:data] || @data
    palette = opts[:palette] || :default
    colors = ColorPalettes.colors(palette)
    color_map = @categories |> Enum.with_index() |> Enum.map(fn {cat, i} -> {cat, Enum.at(colors, i)} end) |> Map.new()

    # Apply animation if tick is provided
    animation_tick = opts[:animation_tick]
    data = if animation_tick do
      animate_data(base_data, animation_tick)
    else
      base_data
    end

    # Create scales
    x_scale = Scale.Linear.new()
      |> Scale.Linear.domain([0, 100])
      |> Scale.Linear.range([0, inner_width])

    y_scale = Scale.Linear.new()
      |> Scale.Linear.domain([0, 100])
      |> Scale.Linear.range([inner_height, 0])

    # Create axes
    x_axis = Axis.bottom(x_scale) |> Axis.ticks(10)
    y_axis = Axis.left(y_scale) |> Axis.ticks(10)

    # Generate circles
    circles = Enum.map(data, fn d ->
      Element.circle(%{
        cx: Scale.Linear.apply(x_scale, d.x),
        cy: Scale.Linear.apply(y_scale, d.y),
        r: d.size / 5 + 3,
        fill: Map.get(color_map, d.category, "#999"),
        opacity: 0.7
      })
    end)

    # Legend
    legend = color_map
      |> Enum.with_index()
      |> Enum.map(fn {{cat, color}, i} ->
        Element.g(%{transform: "translate(#{inner_width - 60},#{i * 22})"})
        |> Element.append(Element.circle(%{cx: 6, cy: 6, r: 6, fill: color}))
        |> Element.append(
          Element.text(%{x: 18, y: 10, font_size: 12, fill: "#333"})
          |> Element.content("Category #{cat}")
        )
      end)

    # Build chart
    chart_group = Element.g(%{transform: "translate(#{margin.left},#{margin.top})"})
      |> Element.append(circles)
      |> Element.append(legend)
      |> Element.append(
        Element.g(%{transform: "translate(0,#{inner_height})"})
        |> Element.append(Axis.generate(x_axis))
      )
      |> Element.append(Axis.generate(y_axis))

    Element.svg(%{width: width, height: height, viewBox: "0 0 #{width} #{height}"})
    |> Element.append(chart_group)
  end

  # Animation: points drift in circular patterns
  defp animate_data(data, tick) do
    data
    |> Enum.with_index()
    |> Enum.map(fn {item, i} ->
      # Each point orbits in a small circle at its own speed
      speed = 0.05 + (rem(i, 5) * 0.02)
      radius = 5 + rem(i, 3) * 3
      angle = tick * speed + i * 0.5

      new_x = item.x + radius * :math.cos(angle)
      new_y = item.y + radius * :math.sin(angle)

      # Keep within bounds
      new_x = max(5, min(95, new_x))
      new_y = max(5, min(95, new_y))

      %{item | x: new_x, y: new_y}
    end)
  end

  def sample_code do
    ~S"""
    alias Visualize.{Scale, Axis}
    alias Visualize.SVG.Element

    circles = Enum.map(data, fn d ->
      Element.circle(%{
        cx: Scale.Linear.apply(x_scale, d.x),
        cy: Scale.Linear.apply(y_scale, d.y),
        r: d.size,
        fill: color,
        opacity: 0.7
      })
    end)
    """
  end
end
