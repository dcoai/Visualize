defmodule Examples.Charts.SunburstChart do
  @moduledoc "Sunburst radial partition layout example"

  alias Visualize.Layout.{Partition, Hierarchy}
  alias Visualize.Shape.Arc
  alias Visualize.SVG.Element
  alias Examples.ColorPalettes

  @data %{
    name: "root",
    children: [
      %{name: "Tech", children: [
        %{name: "Software", value: 400},
        %{name: "Hardware", value: 300},
        %{name: "Services", value: 200}
      ]},
      %{name: "Finance", children: [
        %{name: "Banking", value: 350},
        %{name: "Insurance", value: 250}
      ]},
      %{name: "Health", children: [
        %{name: "Pharma", value: 280},
        %{name: "Biotech", value: 180},
        %{name: "Devices", value: 120}
      ]},
      %{name: "Energy", children: [
        %{name: "Oil", value: 220},
        %{name: "Renewable", value: 160}
      ]}
    ]
  }

  def title, do: "Sunburst Chart"
  def description, do: "Radial hierarchical partition"

  def render(opts \\ []) do
    width = opts[:width] || 500
    height = opts[:height] || 500
    radius = min(width, height) / 2 - 10
    animation_tick = opts[:animation_tick]

    data = if animation_tick do
      generate_animated_data(animation_tick)
    else
      opts[:data] || @data
    end

    palette = opts[:palette] || :default
    colors = ColorPalettes.colors(palette)

    # Build hierarchy
    root = Hierarchy.new(data)
      |> Hierarchy.sum(fn d -> d[:value] || 0 end)

    # Create partition layout (radial)
    # x0/x1 will be angles, y0/y1 will be radius levels
    partition = Partition.new()
      |> Partition.size([2 * :math.pi(), radius])

    positioned = Partition.generate(partition, root)

    # Get all nodes
    all_nodes = get_all_nodes(positioned)

    # Draw arcs
    arc_elements = all_nodes
      |> Enum.with_index()
      |> Enum.map(fn {{node, depth}, _i} ->
        if depth == 0 do
          # Skip root
          nil
        else
          color = get_color(node, depth, colors)

          # Convert partition coordinates to arc
          inner_r = node.y0
          outer_r = node.y1
          start_angle = node.x0
          end_angle = node.x1

          arc = Arc.new()
            |> Arc.inner_radius(inner_r)
            |> Arc.outer_radius(outer_r)

          arc_data = %{start_angle: start_angle, end_angle: end_angle}
          path_data = Arc.generate(arc, arc_data)

          group = Element.g(%{})
            |> Element.append(
              Element.path(%{
                d: path_data,
                fill: color,
                stroke: "white",
                stroke_width: 1
              })
            )

          # Add label for larger arcs
          angle_extent = end_angle - start_angle
          if angle_extent > 0.15 && (outer_r - inner_r) > 20 do
            mid_angle = (start_angle + end_angle) / 2 - :math.pi() / 2
            mid_r = (inner_r + outer_r) / 2
            label_x = mid_r * :math.cos(mid_angle)
            label_y = mid_r * :math.sin(mid_angle)

            Element.append(group,
              Element.text(%{
                x: label_x,
                y: label_y + 4,
                text_anchor: "middle",
                font_size: 10,
                fill: "white",
                font_weight: "bold"
              })
              |> Element.content(truncate(node.data.name, (outer_r - inner_r) * angle_extent))
            )
          else
            group
          end
        end
      end)
      |> Enum.filter(& &1)

    chart_group = Element.g(%{transform: "translate(#{width / 2},#{height / 2})"})
      |> Element.append(arc_elements)

    Element.svg(%{width: width, height: height, viewBox: "0 0 #{width} #{height}"})
    |> Element.append(chart_group)
  end

  defp get_all_nodes(%Hierarchy{} = node, depth \\ 0) do
    children_nodes = case node.children do
      nil -> []
      [] -> []
      children -> Enum.flat_map(children, &get_all_nodes(&1, depth + 1))
    end

    [{node, depth} | children_nodes]
  end

  defp get_color(node, depth, colors) do
    # Get root ancestor for color grouping
    if depth == 1 do
      # First level children get their own color
      index = get_sibling_index(node)
      Enum.at(colors, rem(index, length(colors)))
    else
      # Deeper nodes inherit color from parent (darker shade)
      base_index = 0
      base_color = Enum.at(colors, rem(base_index, length(colors)))
      darken(base_color, depth * 0.1)
    end
  end

  defp get_sibling_index(%{parent: nil}), do: 0
  defp get_sibling_index(%{parent: parent, data: data}) do
    case parent.children do
      nil -> 0
      children ->
        Enum.find_index(children, fn c -> c.data.name == data.name end) || 0
    end
  end

  defp darken(hex_color, amount) do
    # Simple darken - just return a slightly darker shade
    alpha = max(0.4, 1 - amount)
    "#{hex_color}#{trunc(alpha * 255) |> Integer.to_string(16) |> String.pad_leading(2, "0")}"
  end

  defp truncate(text, size) do
    max_chars = trunc(size / 6)
    if String.length(text) > max_chars do
      String.slice(text, 0, max(1, max_chars - 1)) <> ".."
    else
      text
    end
  end

  # Animation: vary sector values with smooth waves
  defp generate_animated_data(tick) do
    phase = tick * 0.06

    %{
      name: "root",
      children: [
        %{name: "Tech", children: [
          %{name: "Software", value: animate_value(400, phase, 0, 100)},
          %{name: "Hardware", value: animate_value(300, phase, 0.8, 80)},
          %{name: "Services", value: animate_value(200, phase, 1.6, 60)}
        ]},
        %{name: "Finance", children: [
          %{name: "Banking", value: animate_value(350, phase, 2.4, 90)},
          %{name: "Insurance", value: animate_value(250, phase, 3.2, 70)}
        ]},
        %{name: "Health", children: [
          %{name: "Pharma", value: animate_value(280, phase, 4.0, 75)},
          %{name: "Biotech", value: animate_value(180, phase, 4.8, 50)},
          %{name: "Devices", value: animate_value(120, phase, 5.6, 35)}
        ]},
        %{name: "Energy", children: [
          %{name: "Oil", value: animate_value(220, phase, 6.4, 60)},
          %{name: "Renewable", value: animate_value(160, phase, 7.2, 50)}
        ]}
      ]
    }
  end

  defp animate_value(base, phase, offset, amplitude) do
    trunc(max(30, base + :math.sin(phase + offset) * amplitude))
  end

  def sample_code do
    ~S"""
    alias Visualize.Layout.{Partition, Hierarchy}
    alias Visualize.Shape.Arc

    root = Hierarchy.new(data)
      |> Hierarchy.sum(fn d -> d[:value] || 0 end)

    # Radial partition - x is angle, y is radius
    partition = Partition.new()
      |> Partition.size([2 * :math.pi(), radius])

    positioned = Partition.generate(partition, root)

    # Convert to arcs
    arc = Arc.new()
      |> Arc.inner_radius(node.y0)
      |> Arc.outer_radius(node.y1)
    """
  end
end
