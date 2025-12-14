defmodule Examples.Charts.PieChart do
  @moduledoc "Pie chart example"

  alias Visualize.Shape
  alias Visualize.SVG.Element
  alias Examples.ColorPalettes

  @data [
    %{name: "Chrome", value: 64.5},
    %{name: "Safari", value: 18.8},
    %{name: "Firefox", value: 3.1},
    %{name: "Edge", value: 4.9},
    %{name: "Opera", value: 2.3},
    %{name: "Other", value: 6.4}
  ]

  def title, do: "Pie Chart"
  def description, do: "Browser market share"

  def render(opts \\ []) do
    width = opts[:width] || 400
    height = opts[:height] || 400
    radius = min(width, height) / 2 - 40

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

    # Create pie layout
    pie = Shape.Pie.new()
      |> Shape.Pie.value(fn d -> d.value end)
      |> Shape.Pie.sort_values(fn a, b -> a > b end)

    arcs_data = Shape.Pie.generate(pie, data)

    # Create arc generator
    arc = Shape.Arc.new()
      |> Shape.Arc.inner_radius(0)
      |> Shape.Arc.outer_radius(radius)

    label_arc = Shape.Arc.new()
      |> Shape.Arc.inner_radius(radius * 0.6)
      |> Shape.Arc.outer_radius(radius * 0.6)

    # Generate slices
    slices = arcs_data
      |> Enum.with_index()
      |> Enum.map(fn {arc_data, i} ->
        color = Enum.at(colors, rem(i, length(colors)))
        path_data = Shape.Arc.generate(arc, arc_data)
        {label_x, label_y} = Shape.Arc.centroid(label_arc, arc_data)

        slice_group = Element.g(%{})
          |> Element.append(
            Element.path(%{d: path_data, fill: color, stroke: "white", stroke_width: 2})
          )
          |> Element.append(
            Element.text(%{
              x: label_x,
              y: label_y,
              text_anchor: "middle",
              fill: "white",
              font_size: 12,
              font_weight: "bold"
            })
            |> Element.content("#{arc_data.data.name}")
          )

        slice_group
      end)

    # Build SVG
    chart_group = Element.g(%{transform: "translate(#{width / 2},#{height / 2})"})
      |> Element.append(slices)

    Element.svg(%{width: width, height: height, viewBox: "0 0 #{width} #{height}"})
    |> Element.append(chart_group)
  end

  # Animation: vary slice sizes with different phases
  defp animate_data(data, tick) do
    data
    |> Enum.with_index()
    |> Enum.map(fn {item, i} ->
      phase = i * 0.8
      # Vary between 60% and 140% of original value
      multiplier = 1.0 + 0.4 * :math.sin(tick * 0.12 + phase)
      %{item | value: item.value * multiplier}
    end)
  end

  def sample_code do
    ~S"""
    alias Visualize.Shape

    pie = Shape.Pie.new()
      |> Shape.Pie.value(fn d -> d.value end)

    arcs_data = Shape.Pie.generate(pie, data)

    arc = Shape.Arc.new()
      |> Shape.Arc.inner_radius(0)
      |> Shape.Arc.outer_radius(radius)

    Enum.map(arcs_data, fn arc_data ->
      path_data = Shape.Arc.generate(arc, arc_data)
      Element.path(%{d: path_data, fill: color})
    end)
    """
  end
end
