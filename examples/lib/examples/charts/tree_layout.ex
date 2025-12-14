defmodule Examples.Charts.TreeLayout do
  @moduledoc "Tree layout for hierarchical node-link diagrams"

  alias Visualize.Layout.{Tree, Hierarchy}
  alias Visualize.SVG.Element
  alias Examples.ColorPalettes

  @data %{
    name: "CEO",
    children: [
      %{name: "CTO", children: [
        %{name: "Dev Lead", children: [
          %{name: "Dev 1"},
          %{name: "Dev 2"},
          %{name: "Dev 3"}
        ]},
        %{name: "QA Lead", children: [
          %{name: "QA 1"},
          %{name: "QA 2"}
        ]}
      ]},
      %{name: "CFO", children: [
        %{name: "Accounting"},
        %{name: "Finance"}
      ]},
      %{name: "COO", children: [
        %{name: "HR"},
        %{name: "Operations", children: [
          %{name: "Ops 1"},
          %{name: "Ops 2"}
        ]}
      ]}
    ]
  }

  def title, do: "Tree Layout"
  def description, do: "Organization hierarchy"

  def render(opts \\ []) do
    width = opts[:width] || 700
    height = opts[:height] || 400
    margin = 40
    animation_tick = opts[:animation_tick]

    data = opts[:data] || @data
    palette = opts[:palette] || :default
    colors = ColorPalettes.colors(palette)

    # Build hierarchy
    root = Hierarchy.new(data)

    # Create tree layout
    tree = Tree.new()
      |> Tree.size([width - margin * 2, height - margin * 2])

    positioned = Tree.generate(tree, root)

    # Get all nodes and links
    all_nodes = get_all_nodes(positioned)
    links = get_links(positioned)

    # Draw links first (underneath nodes)
    link_elements = Enum.map(links, fn {parent, child} ->
      Element.path(%{
        d: "M#{parent.x},#{parent.y}C#{parent.x},#{(parent.y + child.y) / 2} #{child.x},#{(parent.y + child.y) / 2} #{child.x},#{child.y}",
        fill: "none",
        stroke: "#ccc",
        stroke_width: 1.5
      })
    end)

    # Draw nodes
    node_elements = all_nodes
      |> Enum.with_index()
      |> Enum.map(fn {node, idx} ->
      color = Enum.at(colors, rem(idx, length(colors)))

      # Animated node radius
      base_r = 6
      r = if animation_tick do
        phase = animation_tick * 0.08
        offset = idx * 0.3
        base_r + :math.sin(phase + offset) * 2
      else
        base_r
      end

      group = Element.g(%{transform: "translate(#{node.x},#{node.y})"})
        |> Element.append(
          Element.circle(%{
            r: r,
            fill: if(node.children && length(node.children) > 0, do: color, else: lighten(color)),
            stroke: "#fff",
            stroke_width: 2
          })
        )

      # Add label
      text_anchor = if node.children && length(node.children) > 0, do: "middle", else: "start"
      dy = if node.children && length(node.children) > 0, do: -12, else: 4
      dx = if node.children && length(node.children) > 0, do: 0, else: 10

      Element.append(group,
        Element.text(%{
          x: dx,
          y: dy,
          text_anchor: text_anchor,
          font_size: 10,
          fill: "#333"
        })
        |> Element.content(node.data.name)
      )
    end)

    # Compose SVG
    chart_group = Element.g(%{transform: "translate(#{margin},#{margin})"})
      |> Element.append(link_elements)
      |> Element.append(node_elements)

    Element.svg(%{width: width, height: height, viewBox: "0 0 #{width} #{height}"})
    |> Element.append(chart_group)
  end

  defp get_all_nodes(%Hierarchy{} = node) do
    children_nodes = case node.children do
      nil -> []
      [] -> []
      children -> Enum.flat_map(children, &get_all_nodes/1)
    end

    [node | children_nodes]
  end

  defp get_links(%Hierarchy{} = node) do
    case node.children do
      nil -> []
      [] -> []
      children ->
        direct_links = Enum.map(children, fn child -> {node, child} end)
        child_links = Enum.flat_map(children, &get_links/1)
        direct_links ++ child_links
    end
  end

  defp lighten("#" <> hex) do
    {r, ""} = Integer.parse(String.slice(hex, 0, 2), 16)
    {g, ""} = Integer.parse(String.slice(hex, 2, 2), 16)
    {b, ""} = Integer.parse(String.slice(hex, 4, 2), 16)

    r = min(255, trunc(r + (255 - r) * 0.4))
    g = min(255, trunc(g + (255 - g) * 0.4))
    b = min(255, trunc(b + (255 - b) * 0.4))

    r_hex = Integer.to_string(r, 16) |> String.pad_leading(2, "0")
    g_hex = Integer.to_string(g, 16) |> String.pad_leading(2, "0")
    b_hex = Integer.to_string(b, 16) |> String.pad_leading(2, "0")

    "#" <> r_hex <> g_hex <> b_hex
  end

  def sample_code do
    ~S"""
    alias Visualize.Layout.{Tree, Hierarchy}

    data = %{
      name: "root",
      children: [
        %{name: "A", children: [%{name: "A1"}, %{name: "A2"}]},
        %{name: "B"}
      ]
    }

    root = Hierarchy.new(data)

    tree = Tree.new()
      |> Tree.size([width, height])

    positioned = Tree.generate(tree, root)
    # Each node has x, y coordinates
    """
  end
end
