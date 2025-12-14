defmodule Examples.Charts.DonutChart do
  @moduledoc "Donut chart example"

  alias Visualize.Shape
  alias Visualize.SVG.Element
  alias Examples.ColorPalettes

  @data [
    %{category: "Product A", revenue: 420000},
    %{category: "Product B", revenue: 280000},
    %{category: "Product C", revenue: 180000},
    %{category: "Product D", revenue: 90000},
    %{category: "Product E", revenue: 30000}
  ]

  def title, do: "Donut Chart"
  def description, do: "Revenue by product category"

  def render(opts \\ []) do
    width = opts[:width] || 400
    height = opts[:height] || 400
    outer_radius = min(width, height) / 2 - 40
    inner_radius = outer_radius * 0.6

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

    total = Enum.sum(Enum.map(data, & &1.revenue))

    # Create pie layout
    pie = Shape.Pie.new()
      |> Shape.Pie.value(fn d -> d.revenue end)
      |> Shape.Pie.pad_angle(0.02)

    arcs_data = Shape.Pie.generate(pie, data)

    # Create arc generator
    arc = Shape.Arc.new()
      |> Shape.Arc.inner_radius(inner_radius)
      |> Shape.Arc.outer_radius(outer_radius)

    # Generate slices
    slices = arcs_data
      |> Enum.with_index()
      |> Enum.map(fn {arc_data, i} ->
        color = Enum.at(colors, rem(i, length(colors)))
        path_data = Shape.Arc.generate(arc, arc_data)

        Element.path(%{d: path_data, fill: color, stroke: "white", stroke_width: 1})
      end)

    # Center label
    text_color = ColorPalettes.text_color(palette)
    center_label = Element.g(%{text_anchor: "middle"})
      |> Element.append(
        Element.text(%{y: -10, font_size: 28, font_weight: "bold", fill: text_color})
        |> Element.content(format_currency(total))
      )
      |> Element.append(
        Element.text(%{y: 15, font_size: 14, fill: text_color})
        |> Element.content("Total Revenue")
      )

    # Legend
    legend = arcs_data
      |> Enum.with_index()
      |> Enum.map(fn {arc_data, i} ->
        color = Enum.at(colors, rem(i, length(colors)))
        y_pos = i * 22

        Element.g(%{transform: "translate(0,#{y_pos})"})
        |> Element.append(Element.rect(%{width: 16, height: 16, fill: color, rx: 2}))
        |> Element.append(
          Element.text(%{x: 22, y: 12, font_size: 12, fill: "#333"})
          |> Element.content(arc_data.data.category)
        )
      end)

    legend_group = Element.g(%{transform: "translate(#{width / 2 + outer_radius + 20},#{height / 2 - 50})"})
      |> Element.append(legend)

    # Build SVG
    chart_group = Element.g(%{transform: "translate(#{width / 2 - 40},#{height / 2})"})
      |> Element.append(slices)
      |> Element.append(center_label)

    Element.svg(%{width: width + 120, height: height, viewBox: "0 0 #{width + 120} #{height}"})
    |> Element.append(chart_group)
    |> Element.append(legend_group)
  end

  defp format_currency(value) do
    "$#{trunc(value / 1000)}K"
  end

  # Animation: vary slice sizes with different phases
  defp animate_data(data, tick) do
    data
    |> Enum.with_index()
    |> Enum.map(fn {item, i} ->
      phase = i * 0.7
      # Vary between 60% and 140% of original value
      multiplier = 1.0 + 0.4 * :math.sin(tick * 0.12 + phase)
      %{item | revenue: item.revenue * multiplier}
    end)
  end

  def sample_code do
    ~S"""
    alias Visualize.Shape

    pie = Shape.Pie.new()
      |> Shape.Pie.value(fn d -> d.revenue end)
      |> Shape.Pie.pad_angle(0.02)

    arc = Shape.Arc.new()
      |> Shape.Arc.inner_radius(inner_radius)
      |> Shape.Arc.outer_radius(outer_radius)

    # Creates donut with center hole
    """
  end
end
