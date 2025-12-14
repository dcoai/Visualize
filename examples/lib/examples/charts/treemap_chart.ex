defmodule Examples.Charts.TreemapChart do
  @moduledoc "Treemap chart example"

  alias Visualize.Layout.{Treemap, Hierarchy}
  alias Visualize.SVG.Element
  alias Examples.ColorPalettes

  @data %{
    name: "Flare",
    children: [
      %{name: "Analytics", children: [
        %{name: "Cluster", value: 8500},
        %{name: "Graph", value: 7500},
        %{name: "Optimization", value: 6200}
      ]},
      %{name: "Animate", children: [
        %{name: "Easing", value: 4200},
        %{name: "Interpolate", value: 5800},
        %{name: "Transition", value: 3900}
      ]},
      %{name: "Data", children: [
        %{name: "Converters", value: 4700},
        %{name: "DataSet", value: 3800},
        %{name: "DataUtil", value: 2100}
      ]},
      %{name: "Display", children: [
        %{name: "DirtySprite", value: 3100},
        %{name: "Render", value: 4500}
      ]},
      %{name: "Query", children: [
        %{name: "Query", value: 6800},
        %{name: "Methods", value: 2200}
      ]},
      %{name: "Scale", children: [
        %{name: "Linear", value: 2900},
        %{name: "Log", value: 2500},
        %{name: "Ordinal", value: 2800}
      ]},
      %{name: "Util", children: [
        %{name: "Arrays", value: 3200},
        %{name: "Colors", value: 2100},
        %{name: "Math", value: 2800}
      ]},
      %{name: "Vis", children: [
        %{name: "Axis", value: 4100},
        %{name: "Controls", value: 2600},
        %{name: "Data", value: 3700}
      ]}
    ]
  }

  def title, do: "Treemap"
  def description, do: "Hierarchical data as nested rectangles"

  def render(opts \\ []) do
    width = opts[:width] || 600
    height = opts[:height] || 400
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

    # Create treemap layout
    treemap = Treemap.new()
      |> Treemap.size([width, height])
      |> Treemap.padding(2)
      |> Treemap.round(true)

    positioned = Treemap.generate(treemap, root)

    # Get all leaf nodes
    leaves = get_leaves(positioned)

    # Create rectangles for each leaf
    rects = leaves
      |> Enum.with_index()
      |> Enum.map(fn {node, _i} ->
        # Get parent index for color
        parent_index = get_parent_index(node, positioned)
        color = Enum.at(colors, rem(parent_index, length(colors)))

        rect_width = node.x1 - node.x0
        rect_height = node.y1 - node.y0

        group = Element.g(%{})
          |> Element.append(
            Element.rect(%{
              x: node.x0,
              y: node.y0,
              width: rect_width,
              height: rect_height,
              fill: color,
              stroke: "white",
              stroke_width: 1
            })
          )

        # Add label if there's enough space
        if rect_width > 40 and rect_height > 20 do
          Element.append(group,
            Element.text(%{
              x: node.x0 + 4,
              y: node.y0 + 14,
              font_size: 10,
              fill: "white",
              font_weight: "bold"
            })
            |> Element.content(truncate(node.data.name, rect_width))
          )
        else
          group
        end
      end)

    Element.svg(%{width: width, height: height, viewBox: "0 0 #{width} #{height}"})
    |> Element.append(rects)
  end

  defp get_leaves(%Hierarchy{children: nil} = node), do: [node]
  defp get_leaves(%Hierarchy{children: []} = node), do: [node]
  defp get_leaves(%Hierarchy{children: children}) do
    Enum.flat_map(children, &get_leaves/1)
  end

  defp get_parent_index(node, root) do
    find_parent_index(node, root.children, 0)
  end

  defp find_parent_index(_node, nil, _index), do: 0
  defp find_parent_index(_node, [], _index), do: 0
  defp find_parent_index(node, [parent | rest], index) do
    if contains_node?(parent, node) do
      index
    else
      find_parent_index(node, rest, index + 1)
    end
  end

  defp contains_node?(%Hierarchy{} = parent, %Hierarchy{} = node) do
    parent.data.name == node.data.name or
      (parent.children && Enum.any?(parent.children, &contains_node?(&1, node)))
  end

  defp truncate(text, max_width) do
    max_chars = trunc(max_width / 7)
    if String.length(text) > max_chars do
      String.slice(text, 0, max_chars - 1) <> "..."
    else
      text
    end
  end

  # Animation: vary leaf node values with sine waves
  defp generate_animated_data(tick) do
    phase = tick * 0.06

    %{
      name: "Flare",
      children: [
        %{name: "Analytics", children: [
          %{name: "Cluster", value: animate_value(8500, phase, 0, 2000)},
          %{name: "Graph", value: animate_value(7500, phase, 0.5, 1800)},
          %{name: "Optimization", value: animate_value(6200, phase, 1.0, 1500)}
        ]},
        %{name: "Animate", children: [
          %{name: "Easing", value: animate_value(4200, phase, 1.5, 1200)},
          %{name: "Interpolate", value: animate_value(5800, phase, 2.0, 1400)},
          %{name: "Transition", value: animate_value(3900, phase, 2.5, 1000)}
        ]},
        %{name: "Data", children: [
          %{name: "Converters", value: animate_value(4700, phase, 3.0, 1300)},
          %{name: "DataSet", value: animate_value(3800, phase, 3.5, 1100)},
          %{name: "DataUtil", value: animate_value(2100, phase, 4.0, 600)}
        ]},
        %{name: "Display", children: [
          %{name: "DirtySprite", value: animate_value(3100, phase, 4.5, 900)},
          %{name: "Render", value: animate_value(4500, phase, 5.0, 1200)}
        ]},
        %{name: "Query", children: [
          %{name: "Query", value: animate_value(6800, phase, 5.5, 1600)},
          %{name: "Methods", value: animate_value(2200, phase, 6.0, 700)}
        ]},
        %{name: "Scale", children: [
          %{name: "Linear", value: animate_value(2900, phase, 6.5, 800)},
          %{name: "Log", value: animate_value(2500, phase, 7.0, 700)},
          %{name: "Ordinal", value: animate_value(2800, phase, 7.5, 800)}
        ]},
        %{name: "Util", children: [
          %{name: "Arrays", value: animate_value(3200, phase, 8.0, 900)},
          %{name: "Colors", value: animate_value(2100, phase, 8.5, 600)},
          %{name: "Math", value: animate_value(2800, phase, 9.0, 800)}
        ]},
        %{name: "Vis", children: [
          %{name: "Axis", value: animate_value(4100, phase, 9.5, 1100)},
          %{name: "Controls", value: animate_value(2600, phase, 10.0, 700)},
          %{name: "Data", value: animate_value(3700, phase, 10.5, 1000)}
        ]}
      ]
    }
  end

  defp animate_value(base, phase, offset, amplitude) do
    trunc(max(500, base + :math.sin(phase + offset) * amplitude))
  end

  def sample_code do
    ~S"""
    alias Visualize.Layout.{Treemap, Hierarchy}

    root = Hierarchy.new(data)
      |> Hierarchy.sum(fn d -> d[:value] || 0 end)

    treemap = Treemap.new()
      |> Treemap.size([width, height])
      |> Treemap.padding(2)

    positioned = Treemap.generate(treemap, root)

    # Each node has x0, y0, x1, y1 coordinates
    """
  end
end
