defmodule Examples.Charts.ForceGraph do
  @moduledoc "Force-directed graph layout example"

  alias Visualize.Layout.Force
  alias Visualize.SVG.Element
  alias Examples.ColorPalettes

  @nodes [
    %{id: "A", group: 0}, %{id: "B", group: 0}, %{id: "C", group: 0},
    %{id: "D", group: 1}, %{id: "E", group: 1}, %{id: "F", group: 1},
    %{id: "G", group: 2}, %{id: "H", group: 2}, %{id: "I", group: 2},
    %{id: "J", group: 3}, %{id: "K", group: 3}, %{id: "L", group: 3}
  ]

  @links [
    %{source: "A", target: "B"}, %{source: "A", target: "C"}, %{source: "B", target: "C"},
    %{source: "D", target: "E"}, %{source: "D", target: "F"}, %{source: "E", target: "F"},
    %{source: "G", target: "H"}, %{source: "G", target: "I"}, %{source: "H", target: "I"},
    %{source: "J", target: "K"}, %{source: "J", target: "L"}, %{source: "K", target: "L"},
    %{source: "A", target: "D"}, %{source: "B", target: "G"}, %{source: "C", target: "J"},
    %{source: "E", target: "H"}, %{source: "F", target: "K"}, %{source: "I", target: "L"}
  ]

  def title, do: "Force-Directed Graph"
  def description, do: "Network visualization with physics simulation"

  def render(opts \\ []) do
    width = opts[:width] || 600
    height = opts[:height] || 400

    nodes = opts[:nodes] || @nodes
    links = opts[:links] || @links
    palette = opts[:palette] || :default
    colors = ColorPalettes.colors(palette)
    animation_tick = opts[:animation_tick]

    # Run force simulation synchronously
    result = Force.run(
      nodes: nodes,
      links: links,
      forces: [
        {:center, x: width / 2, y: height / 2},
        {:many_body, strength: -400},
        {:link, distance: 100}
      ],
      iterations: 300
    )

    base_nodes = result.nodes

    # Apply animation jitter if tick is provided
    positioned_nodes = if animation_tick do
      animate_nodes(base_nodes, animation_tick)
    else
      base_nodes
    end

    node_map = Map.new(positioned_nodes, &{&1.id, &1})

    # Draw links
    link_elements = Enum.map(links, fn link ->
      source = Map.get(node_map, link.source)
      target = Map.get(node_map, link.target)

      if source && target do
        Element.line(%{
          x1: source.x,
          y1: source.y,
          x2: target.x,
          y2: target.y,
          stroke: "#999",
          stroke_opacity: 0.6,
          stroke_width: 1.5
        })
      end
    end)
    |> Enum.filter(& &1)

    # Draw nodes
    node_elements = Enum.map(positioned_nodes, fn node ->
      color = Enum.at(colors, rem(node.group, length(colors)))

      Element.g(%{})
      |> Element.append(
        Element.circle(%{
          cx: node.x,
          cy: node.y,
          r: 10,
          fill: color,
          stroke: "#fff",
          stroke_width: 2
        })
      )
      |> Element.append(
        Element.text(%{
          x: node.x,
          y: node.y + 4,
          text_anchor: "middle",
          font_size: 10,
          fill: "#fff",
          font_weight: "bold"
        })
        |> Element.content(node.id)
      )
    end)

    Element.svg(%{width: width, height: height, viewBox: "0 0 #{width} #{height}"})
    |> Element.append(link_elements)
    |> Element.append(node_elements)
  end

  # Animation: nodes gently oscillate around their positions
  defp animate_nodes(nodes, tick) do
    nodes
    |> Enum.with_index()
    |> Enum.map(fn {node, i} ->
      phase = i * 0.8
      # Small circular motion around the equilibrium position
      jitter_x = 8 * :math.sin(tick * 0.12 + phase)
      jitter_y = 8 * :math.cos(tick * 0.12 + phase + 1.5)
      %{node | x: node.x + jitter_x, y: node.y + jitter_y}
    end)
  end

  def sample_code do
    ~S"""
    alias Visualize.Layout.Force

    result = Force.run(
      nodes: nodes,
      links: links,
      forces: [
        {:center, x: width / 2, y: height / 2},
        {:many_body, strength: -200},
        {:link, distance: 60}
      ],
      iterations: 300
    )

    # Each node now has x, y coordinates
    positioned_nodes = result.nodes
    """
  end
end
