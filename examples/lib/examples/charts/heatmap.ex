defmodule Examples.Charts.Heatmap do
  @moduledoc "Heatmap visualization using color scales"

  alias Visualize.Scale
  alias Visualize.SVG.Element
  alias Examples.ColorPalettes

  @days ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
  @hours (for h <- 0..23, do: "#{h}:00")

  def title, do: "Heatmap"
  def description, do: "Hourly activity by day of week"

  def render(opts \\ []) do
    width = opts[:width] || 600
    height = opts[:height] || 300
    margin = %{top: 30, right: 30, bottom: 50, left: 60}
    palette = opts[:palette] || :default
    gradient = ColorPalettes.gradient(palette)

    chart_width = width - margin.left - margin.right
    chart_height = height - margin.top - margin.bottom

    # Generate sample data (7 days x 24 hours)
    animation_tick = opts[:animation_tick]
    data = if animation_tick do
      generate_animated_data(animation_tick)
    else
      generate_sample_data()
    end

    # Calculate cell dimensions
    cell_width = chart_width / 24
    cell_height = chart_height / 7

    # Find data range for color scale
    all_values = List.flatten(data)
    min_val = Enum.min(all_values)
    max_val = Enum.max(all_values)

    # Create color scale
    color_scale = Scale.Linear.new()
      |> Scale.Linear.domain([min_val, max_val])
      |> Scale.Linear.range([0, 1])

    # Draw cells
    cells = data
      |> Enum.with_index()
      |> Enum.flat_map(fn {row, day_idx} ->
        row
        |> Enum.with_index()
        |> Enum.map(fn {value, hour_idx} ->
          t = Scale.Linear.apply(color_scale, value)
          color = interpolate_gradient(gradient, t)

          Element.rect(%{
            x: hour_idx * cell_width,
            y: day_idx * cell_height,
            width: cell_width - 1,
            height: cell_height - 1,
            fill: color,
            rx: 2
          })
        end)
      end)

    # Day labels (y-axis)
    day_labels = @days
      |> Enum.with_index()
      |> Enum.map(fn {day, i} ->
        Element.text(%{
          x: -10,
          y: i * cell_height + cell_height / 2 + 4,
          text_anchor: "end",
          font_size: 10,
          fill: "#333"
        })
        |> Element.content(day)
      end)

    # Hour labels (x-axis) - show every 4 hours
    hour_labels = [0, 4, 8, 12, 16, 20]
      |> Enum.map(fn h ->
        Element.text(%{
          x: h * cell_width + cell_width / 2,
          y: chart_height + 15,
          text_anchor: "middle",
          font_size: 9,
          fill: "#333"
        })
        |> Element.content(Enum.at(@hours, h))
      end)

    # Color legend
    legend = create_color_legend(min_val, max_val, gradient, chart_width - 100, -20)

    # Compose SVG
    chart_group = Element.g(%{transform: "translate(#{margin.left},#{margin.top})"})
      |> Element.append(cells)
      |> Element.append(day_labels)
      |> Element.append(hour_labels)
      |> Element.append(legend)

    Element.svg(%{width: width, height: height, viewBox: "0 0 #{width} #{height}"})
    |> Element.append(chart_group)
  end

  defp generate_sample_data do
    # Simulate activity patterns (higher during work hours on weekdays)
    for day <- 0..6 do
      for hour <- 0..23 do
        base = if day < 5 do  # weekday
          cond do
            hour >= 9 and hour <= 17 -> 70 + :rand.uniform(30)
            hour >= 7 and hour <= 20 -> 30 + :rand.uniform(30)
            true -> :rand.uniform(20)
          end
        else  # weekend
          cond do
            hour >= 10 and hour <= 22 -> 20 + :rand.uniform(40)
            true -> :rand.uniform(15)
          end
        end
        base
      end
    end
  end

  # Animation: activity waves ripple across the heatmap
  defp generate_animated_data(tick) do
    phase = tick * 0.15
    for day <- 0..6 do
      for hour <- 0..23 do
        # Base pattern with animated wave
        base = if day < 5 do
          cond do
            hour >= 9 and hour <= 17 -> 70
            hour >= 7 and hour <= 20 -> 40
            true -> 15
          end
        else
          cond do
            hour >= 10 and hour <= 22 -> 35
            true -> 10
          end
        end
        # Add wave effect
        wave = 25 * :math.sin((day / 2) + (hour / 4) + phase)
        max(5, min(100, base + wave))
      end
    end
  end

  defp interpolate_gradient(gradient, t) do
    t = max(0, min(1, t))
    n = length(gradient) - 1
    idx = t * n
    lower = trunc(idx)
    upper = min(lower + 1, n)
    local_t = idx - lower

    color1 = Enum.at(gradient, lower)
    color2 = Enum.at(gradient, upper)

    interpolate_color(color1, color2, local_t)
  end

  defp interpolate_color(color1, color2, t) do
    {r1, g1, b1} = parse_hex(color1)
    {r2, g2, b2} = parse_hex(color2)

    r = trunc(r1 + (r2 - r1) * t)
    g = trunc(g1 + (g2 - g1) * t)
    b = trunc(b1 + (b2 - b1) * t)

    r_hex = Integer.to_string(r, 16) |> String.pad_leading(2, "0")
    g_hex = Integer.to_string(g, 16) |> String.pad_leading(2, "0")
    b_hex = Integer.to_string(b, 16) |> String.pad_leading(2, "0")

    "#" <> r_hex <> g_hex <> b_hex
  end

  defp parse_hex("#" <> hex) do
    {r, ""} = Integer.parse(String.slice(hex, 0, 2), 16)
    {g, ""} = Integer.parse(String.slice(hex, 2, 2), 16)
    {b, ""} = Integer.parse(String.slice(hex, 4, 2), 16)
    {r, g, b}
  end

  defp create_color_legend(min_val, max_val, gradient, x, y) do
    gradient_width = 100
    gradient_height = 10

    # Create gradient stops
    stops = for i <- 0..10 do
      t = i / 10
      color = interpolate_gradient(gradient, t)

      Element.rect(%{
        x: i * (gradient_width / 10),
        width: gradient_width / 10 + 1,
        height: gradient_height,
        fill: color
      })
    end

    Element.g(%{transform: "translate(#{x},#{y})"})
    |> Element.append(stops)
    |> Element.append(
      Element.text(%{x: 0, y: gradient_height + 12, font_size: 9, fill: "#333"})
      |> Element.content("#{trunc(min_val)}")
    )
    |> Element.append(
      Element.text(%{x: gradient_width, y: gradient_height + 12, text_anchor: "end", font_size: 9, fill: "#333"})
      |> Element.content("#{trunc(max_val)}")
    )
  end

  def sample_code do
    ~S"""
    alias Visualize.Scale

    # Create color scale
    color_scale = Scale.Linear.new()
      |> Scale.Linear.domain([min, max])
      |> Scale.Linear.range([0, 1])

    # Map value to color
    t = Scale.Linear.apply(color_scale, value)
    color = interpolate_color("#f7fbff", "#08306b", t)

    # Draw cells
    Element.rect(%{x: x, y: y, width: w, height: h, fill: color})
    """
  end
end
