defmodule Examples.Charts.CirclePacking do
  @moduledoc "Circle packing layout example"

  alias Visualize.Layout.{Pack, Hierarchy}
  alias Visualize.SVG.Element
  alias Examples.ColorPalettes

  @data %{
    name: "root",
    children: [
      %{name: "Analytics", children: [
        %{name: "Cluster", value: 3500},
        %{name: "Graph", value: 2500},
        %{name: "Optimize", value: 1800}
      ]},
      %{name: "Animate", children: [
        %{name: "Easing", value: 2200},
        %{name: "Tween", value: 1800},
        %{name: "Transition", value: 1400}
      ]},
      %{name: "Data", children: [
        %{name: "Converters", value: 2800},
        %{name: "DataSet", value: 1900},
        %{name: "DataUtil", value: 1100}
      ]},
      %{name: "Display", children: [
        %{name: "Render", value: 3200},
        %{name: "Sprite", value: 2100}
      ]},
      %{name: "Query", children: [
        %{name: "Query", value: 2600},
        %{name: "Methods", value: 1200}
      ]}
    ]
  }

  def title, do: "Circle Packing"
  def description, do: "Hierarchical data as nested circles"

  def render(opts \\ []) do
    width = opts[:width] || 500
    height = opts[:height] || 500
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

    # Create pack layout
    pack = Pack.new()
      |> Pack.size([width, height])
      |> Pack.padding(3)

    positioned = Pack.generate(pack, root)

    # Get all nodes with circles
    circles = get_all_circles(positioned, 0)

    # Draw circles
    circle_elements = Enum.map(circles, fn {node, depth} ->
      color = if node.children && length(node.children) > 0 do
        # Parent circles are semi-transparent
        "rgba(200, 200, 200, 0.3)"
      else
        # Leaf circles get colors based on depth
        Enum.at(colors, rem(depth - 1, length(colors)))
      end

      group = Element.g(%{})
        |> Element.append(
          Element.circle(%{
            cx: node.x,
            cy: node.y,
            r: node.r,
            fill: color,
            stroke: if(node.children, do: "#999", else: "white"),
            stroke_width: 1
          })
        )

      # Add label for leaf nodes
      if is_nil(node.children) || Enum.empty?(node.children || []) do
        if node.r > 20 do
          Element.append(group,
            Element.text(%{
              x: node.x,
              y: node.y + 4,
              text_anchor: "middle",
              font_size: min(12, node.r / 3),
              fill: "white",
              font_weight: "bold"
            })
            |> Element.content(truncate(node.data.name, node.r))
          )
        else
          group
        end
      else
        group
      end
    end)

    Element.svg(%{width: width, height: height, viewBox: "0 0 #{width} #{height}"})
    |> Element.append(circle_elements)
  end

  defp get_all_circles(%Hierarchy{} = node, depth) do
    children_circles = case node.children do
      nil -> []
      [] -> []
      children -> Enum.flat_map(children, &get_all_circles(&1, depth + 1))
    end

    [{node, depth} | children_circles]
  end

  defp truncate(text, radius) do
    max_chars = trunc(radius / 4)
    if String.length(text) > max_chars do
      String.slice(text, 0, max(1, max_chars - 1)) <> ".."
    else
      text
    end
  end

  # Animation: vary circle sizes with pulsing effect
  defp generate_animated_data(tick) do
    phase = tick * 0.07

    %{
      name: "root",
      children: [
        %{name: "Analytics", children: [
          %{name: "Cluster", value: animate_value(3500, phase, 0, 800)},
          %{name: "Graph", value: animate_value(2500, phase, 0.7, 600)},
          %{name: "Optimize", value: animate_value(1800, phase, 1.4, 500)}
        ]},
        %{name: "Animate", children: [
          %{name: "Easing", value: animate_value(2200, phase, 2.1, 550)},
          %{name: "Tween", value: animate_value(1800, phase, 2.8, 450)},
          %{name: "Transition", value: animate_value(1400, phase, 3.5, 350)}
        ]},
        %{name: "Data", children: [
          %{name: "Converters", value: animate_value(2800, phase, 4.2, 700)},
          %{name: "DataSet", value: animate_value(1900, phase, 4.9, 480)},
          %{name: "DataUtil", value: animate_value(1100, phase, 5.6, 280)}
        ]},
        %{name: "Display", children: [
          %{name: "Render", value: animate_value(3200, phase, 6.3, 750)},
          %{name: "Sprite", value: animate_value(2100, phase, 7.0, 520)}
        ]},
        %{name: "Query", children: [
          %{name: "Query", value: animate_value(2600, phase, 7.7, 650)},
          %{name: "Methods", value: animate_value(1200, phase, 8.4, 300)}
        ]}
      ]
    }
  end

  defp animate_value(base, phase, offset, amplitude) do
    trunc(max(200, base + :math.sin(phase + offset) * amplitude))
  end

  def sample_code do
    ~S"""
    alias Visualize.Layout.{Pack, Hierarchy}

    root = Hierarchy.new(data)
      |> Hierarchy.sum(fn d -> d[:value] || 0 end)

    pack = Pack.new()
      |> Pack.size([width, height])
      |> Pack.padding(3)

    positioned = Pack.generate(pack, root)

    # Each node has x, y (center) and r (radius)
    """
  end
end
