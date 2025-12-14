defmodule Examples.Charts.Streamgraph do
  @moduledoc "Streamgraph using Stack with silhouette offset"

  alias Visualize.Scale
  alias Visualize.Shape.{Stack, Area}
  alias Visualize.SVG.Element
  alias Examples.ColorPalettes

  @data (for month <- 1..24 do
    %{
      month: month,
      rock: 20 + :rand.uniform(30) + if(month > 6 and month < 18, do: 20, else: 0),
      pop: 30 + :rand.uniform(25) + if(month > 3 and month < 15, do: 25, else: 0),
      jazz: 15 + :rand.uniform(20),
      classical: 10 + :rand.uniform(15) + if(month > 12, do: 15, else: 0),
      electronic: 25 + :rand.uniform(35) + if(month > 9 and month < 21, do: 20, else: 0),
      hiphop: 20 + :rand.uniform(25) + if(month < 12, do: 10, else: 20)
    }
  end)

  @keys [:rock, :pop, :jazz, :classical, :electronic, :hiphop]

  def title, do: "Streamgraph"
  def description, do: "Music genre popularity over time"

  def render(opts \\ []) do
    width = opts[:width] || 600
    height = opts[:height] || 350
    margin = %{top: 20, right: 100, bottom: 30, left: 40}

    chart_width = width - margin.left - margin.right
    chart_height = height - margin.top - margin.bottom

    keys = @keys
    palette = opts[:palette] || :default
    colors = ColorPalettes.colors(palette)

    # Generate animated or static data
    animation_tick = opts[:animation_tick]
    data = if animation_tick do
      generate_animated_data(animation_tick)
    else
      opts[:data] || @data
    end

    # Create stack with silhouette offset (centers the stream)
    stack = Stack.new()
      |> Stack.keys(keys)
      |> Stack.offset(:silhouette)
      |> Stack.order(:insideout)

    series = Stack.generate(stack, data)

    # Create scales
    x_scale = Scale.Linear.new()
      |> Scale.Linear.domain([1, length(data)])
      |> Scale.Linear.range([0, chart_width])

    # Find y extent (can be negative with silhouette)
    all_y = series
      |> Enum.flat_map(fn s -> Enum.flat_map(s.points, fn p -> [p.y0, p.y1] end) end)

    y_min = Enum.min(all_y)
    y_max = Enum.max(all_y)

    y_scale = Scale.Linear.new()
      |> Scale.Linear.domain([y_min, y_max])
      |> Scale.Linear.range([chart_height, 0])

    # Create area generator
    area = Area.new()
      |> Area.x(fn d -> Scale.Linear.apply(x_scale, d.data.month) end)
      |> Area.y0(fn d -> Scale.Linear.apply(y_scale, d.y0) end)
      |> Area.y1(fn d -> Scale.Linear.apply(y_scale, d.y1) end)
      |> Area.curve(:basis)

    # Draw streams
    stream_elements = series
      |> Enum.with_index()
      |> Enum.map(fn {s, i} ->
        color = Enum.at(colors, rem(i, length(colors)))
        path_d = Area.generate(area, s.points)

        Element.path(%{
          d: path_d,
          fill: color,
          fill_opacity: 0.8,
          stroke: color,
          stroke_width: 0.5
        })
      end)

    # X-axis (months)
    x_ticks = [1, 6, 12, 18, 24]
    x_axis = Enum.map(x_ticks, fn month ->
      x = Scale.Linear.apply(x_scale, month)

      Element.text(%{
        x: x,
        y: chart_height + 20,
        text_anchor: "middle",
        font_size: 10,
        fill: "#666"
      })
      |> Element.content("Month #{month}")
    end)

    # Legend
    legend = keys
      |> Enum.with_index()
      |> Enum.map(fn {key, i} ->
        Element.g(%{transform: "translate(#{chart_width + 15},#{i * 20 + 30})"})
        |> Element.append(
          Element.rect(%{width: 15, height: 15, fill: Enum.at(colors, rem(i, length(colors))), rx: 2})
        )
        |> Element.append(
          Element.text(%{x: 20, y: 12, font_size: 10, fill: "#333"})
          |> Element.content(Atom.to_string(key) |> String.capitalize())
        )
      end)

    # Compose SVG
    chart_group = Element.g(%{transform: "translate(#{margin.left},#{margin.top})"})
      |> Element.append(stream_elements)
      |> Element.append(x_axis)
      |> Element.append(legend)

    Element.svg(%{width: width, height: height, viewBox: "0 0 #{width} #{height}"})
    |> Element.append(chart_group)
  end

  # Animation: flowing music genre popularity waves
  defp generate_animated_data(tick) do
    phase = tick * 0.12
    for month <- 1..24 do
      %{
        month: month,
        rock: 30 + 25 * :math.sin((month / 4) + phase) |> max(10),
        pop: 35 + 20 * :math.sin((month / 5) + phase * 1.3 + 1) |> max(10),
        jazz: 20 + 15 * :math.sin((month / 3) + phase * 0.7 + 2) |> max(10),
        classical: 18 + 12 * :math.sin((month / 6) + phase * 1.1 + 3) |> max(10),
        electronic: 32 + 22 * :math.sin((month / 4) + phase * 0.9 + 4) |> max(10),
        hiphop: 28 + 18 * :math.sin((month / 5) + phase * 1.4 + 5) |> max(10)
      }
    end
  end

  def sample_code do
    ~S"""
    alias Visualize.Shape.{Stack, Area}

    # Streamgraph uses silhouette offset to center
    stack = Stack.new()
      |> Stack.keys(keys)
      |> Stack.offset(:silhouette)  # Centers around zero
      |> Stack.order(:insideout)     # Larger series in middle

    series = Stack.generate(stack, data)

    # Create smooth area shapes
    area = Area.new()
      |> Area.x(fn d -> x_scale(d.data.month) end)
      |> Area.y0(fn d -> y_scale(d.y0) end)
      |> Area.y1(fn d -> y_scale(d.y1) end)
      |> Area.curve(:basis)

    path_d = Area.generate(area, series_points)
    """
  end
end
