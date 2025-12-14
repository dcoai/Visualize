defmodule Examples.Charts.RadialBarChart do
  @moduledoc "Radial bar chart example"

  alias Visualize.{Scale, Shape}
  alias Visualize.SVG.Element
  alias Examples.ColorPalettes

  @data [
    %{name: "Monday", value: 85},
    %{name: "Tuesday", value: 72},
    %{name: "Wednesday", value: 90},
    %{name: "Thursday", value: 65},
    %{name: "Friday", value: 78},
    %{name: "Saturday", value: 45},
    %{name: "Sunday", value: 35}
  ]

  def title, do: "Radial Bar Chart"
  def description, do: "Weekly activity levels"

  def render(opts \\ []) do
    width = opts[:width] || 400
    height = opts[:height] || 400
    inner_radius = 50
    outer_radius = min(width, height) / 2 - 40

    base_data = opts[:data] || @data
    palette = opts[:palette] || :default
    gradient = ColorPalettes.gradient(palette)

    # Apply animation if tick is provided
    animation_tick = opts[:animation_tick]
    data = if animation_tick do
      animate_data(base_data, animation_tick)
    else
      base_data
    end

    n = length(data)

    # Create scales
    angle_scale = fn i -> i * 2 * :math.pi() / n - :math.pi() / 2 end

    max_value = data |> Enum.map(& &1.value) |> Enum.max()

    radius_scale = Scale.Linear.new()
      |> Scale.Linear.domain([0, max_value])
      |> Scale.Linear.range([inner_radius, outer_radius])

    color_scale = Scale.Linear.new()
      |> Scale.Linear.domain([0, max_value])
      |> Scale.Linear.range([0, 1])

    # Generate arcs
    arcs = data
      |> Enum.with_index()
      |> Enum.map(fn {d, i} ->
        start_angle = angle_scale.(i) + 0.05
        end_angle = angle_scale.(i + 1) - 0.05
        r = Scale.Linear.apply(radius_scale, d.value)

        # Color based on value using palette gradient
        t = Scale.Linear.apply(color_scale, d.value)
        color = ColorPalettes.interpolate_gradient(palette, t)

        arc = Shape.Arc.new()
          |> Shape.Arc.inner_radius(inner_radius)
          |> Shape.Arc.outer_radius(r)
          |> Shape.Arc.start_angle(start_angle + :math.pi() / 2)
          |> Shape.Arc.end_angle(end_angle + :math.pi() / 2)

        arc_data = %{start_angle: start_angle + :math.pi() / 2, end_angle: end_angle + :math.pi() / 2}
        path_data = Shape.Arc.generate(arc, arc_data)

        Element.path(%{d: path_data, fill: color, stroke: "white", stroke_width: 1})
      end)

    # Generate labels
    labels = data
      |> Enum.with_index()
      |> Enum.map(fn {d, i} ->
        angle = (angle_scale.(i) + angle_scale.(i + 1)) / 2
        label_radius = outer_radius + 15
        x = label_radius * :math.cos(angle)
        y = label_radius * :math.sin(angle)

        # Rotate text to follow arc
        rotation = angle * 180 / :math.pi()
        text_anchor = if angle > :math.pi() / 2 or angle < -:math.pi() / 2, do: "end", else: "start"
        rotation = if text_anchor == "end", do: rotation + 180, else: rotation

        Element.text(%{
          x: x,
          y: y,
          text_anchor: text_anchor,
          font_size: 11,
          fill: "#333",
          transform: "rotate(#{rotation},#{x},#{y})"
        })
        |> Element.content(d.name)
      end)

    # Center value label
    total = Enum.sum(Enum.map(data, & &1.value))
    avg = Float.round(total / n, 1)

    center_label = Element.g(%{text_anchor: "middle"})
      |> Element.append(
        Element.text(%{y: -5, font_size: 24, font_weight: "bold", fill: "#333"})
        |> Element.content("#{avg}")
      )
      |> Element.append(
        Element.text(%{y: 15, font_size: 12, fill: "#666"})
        |> Element.content("Average")
      )

    # Build SVG
    chart_group = Element.g(%{transform: "translate(#{width / 2},#{height / 2})"})
      |> Element.append(arcs)
      |> Element.append(labels)
      |> Element.append(center_label)

    Element.svg(%{width: width, height: height, viewBox: "0 0 #{width} #{height}"})
    |> Element.append(chart_group)
  end

  # Animation: activity levels pulse up and down
  defp animate_data(data, tick) do
    data
    |> Enum.with_index()
    |> Enum.map(fn {item, i} ->
      phase = i * 0.9
      # Vary between 50% and 150% of original value
      multiplier = 1.0 + 0.5 * :math.sin(tick * 0.15 + phase)
      new_value = item.value * multiplier
      # Keep within reasonable bounds
      %{item | value: max(10, min(100, new_value))}
    end)
  end

  defp interpolate_color(color1, color2, t) do
    {r1, g1, b1} = parse_hex(color1)
    {r2, g2, b2} = parse_hex(color2)

    r = trunc(r1 + (r2 - r1) * t)
    g = trunc(g1 + (g2 - g1) * t)
    b = trunc(b1 + (b2 - b1) * t)

    r_hex = r |> Integer.to_string(16) |> String.pad_leading(2, "0")
    g_hex = g |> Integer.to_string(16) |> String.pad_leading(2, "0")
    b_hex = b |> Integer.to_string(16) |> String.pad_leading(2, "0")

    "#" <> r_hex <> g_hex <> b_hex
  end

  defp parse_hex("#" <> hex) do
    {r, ""} = Integer.parse(String.slice(hex, 0, 2), 16)
    {g, ""} = Integer.parse(String.slice(hex, 2, 2), 16)
    {b, ""} = Integer.parse(String.slice(hex, 4, 2), 16)
    {r, g, b}
  end

  def sample_code do
    ~S"""
    alias Visualize.Shape

    arc = Shape.Arc.new()
      |> Shape.Arc.inner_radius(inner_radius)
      |> Shape.Arc.outer_radius(value_radius)
      |> Shape.Arc.start_angle(start_angle)
      |> Shape.Arc.end_angle(end_angle)

    # Radial bars are just arcs with different outer radii
    path_data = Shape.Arc.generate(arc, arc_data)
    """
  end
end
