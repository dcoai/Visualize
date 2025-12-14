defmodule Examples.Charts.SankeyDiagram do
  @moduledoc "Sankey diagram showing flow between nodes"

  alias Visualize.Layout.Sankey
  alias Visualize.SVG.Element
  alias Examples.ColorPalettes

  # Energy flow - classic Sankey example
  @nodes [
    %{id: "coal", name: "Coal"},
    %{id: "gas", name: "Natural Gas"},
    %{id: "oil", name: "Oil"},
    %{id: "nuclear", name: "Nuclear"},
    %{id: "solar", name: "Solar"},
    %{id: "electricity", name: "Electricity"},
    %{id: "heating", name: "Heating"},
    %{id: "transport", name: "Transport"},
    %{id: "industry", name: "Industry"},
    %{id: "homes", name: "Homes"}
  ]

  @links [
    # Sources to conversion
    %{source: "coal", target: "electricity", value: 20},
    %{source: "gas", target: "electricity", value: 15},
    %{source: "gas", target: "heating", value: 10},
    %{source: "nuclear", target: "electricity", value: 18},
    %{source: "solar", target: "electricity", value: 8},
    %{source: "oil", target: "transport", value: 25},
    # Conversion to end use
    %{source: "electricity", target: "industry", value: 25},
    %{source: "electricity", target: "homes", value: 20},
    %{source: "electricity", target: "transport", value: 16},
    %{source: "heating", target: "homes", value: 10},
    %{source: "transport", target: "industry", value: 15}
  ]

  def title, do: "Sankey Diagram"
  def description, do: "Energy flow from sources to end use"

  def render(opts \\ []) do
    width = opts[:width] || 700
    height = opts[:height] || 400

    animation_tick = opts[:animation_tick]

    nodes = opts[:nodes] || @nodes
    links = if animation_tick do
      generate_animated_links(animation_tick)
    else
      opts[:links] || @links
    end

    palette = opts[:palette] || :default
    colors = ColorPalettes.colors(palette)

    chart_width = width - 150
    chart_height = height - 50

    # Compute sankey layout
    sankey = Sankey.new()
      |> Sankey.size(chart_width, chart_height)
      |> Sankey.node_width(20)
      |> Sankey.node_padding(15)
      |> Sankey.iterations(32)
      |> Sankey.compute(nodes, links)

    # Find actual bounds and compute scale to fit (check both nodes and links)
    node_y = sankey.nodes |> Enum.flat_map(fn n -> [n.y0, n.y1] end)
    link_y = sankey.links |> Enum.flat_map(fn l -> [l.y0, l.y1, l.y0 + l.width, l.y1 + l.width] end)
    all_y = node_y ++ link_y
    max_y = Enum.max(all_y, fn -> chart_height end)
    y_scale = if max_y > chart_height, do: chart_height / max_y, else: 1.0

    # Scale nodes to fit
    scaled_nodes = Enum.map(sankey.nodes, fn node ->
      %{node |
        y0: node.y0 * y_scale,
        y1: node.y1 * y_scale
      }
    end)

    # Scale links to fit (set path to nil to force regeneration)
    scaled_links = Enum.map(sankey.links, fn link ->
      %{link |
        y0: link.y0 * y_scale,
        y1: link.y1 * y_scale,
        width: link.width * y_scale,
        source_node: %{link.source_node | y0: link.source_node.y0 * y_scale, y1: link.source_node.y1 * y_scale},
        target_node: %{link.target_node | y0: link.target_node.y0 * y_scale, y1: link.target_node.y1 * y_scale},
        path: nil
      }
    end)

    # Draw links
    link_elements = Enum.map(scaled_links, fn link ->
      path_d = Sankey.link_path(link)
      source_idx = Enum.find_index(sankey.nodes, fn n -> n.id == link.source end) || 0
      color = Enum.at(colors, rem(source_idx, length(colors)))

      Element.path(%{
        d: path_d,
        fill: color,
        fill_opacity: 0.4,
        stroke: "none"
      })
    end)

    # Draw nodes
    node_elements = scaled_nodes
      |> Enum.with_index()
      |> Enum.map(fn {node, idx} ->
        color = Enum.at(colors, rem(idx, length(colors)))
        node_height = max(2, node.y1 - node.y0)

        group = Element.g(%{})
          |> Element.append(
            Element.rect(%{
              x: node.x0,
              y: node.y0,
              width: node.x1 - node.x0,
              height: node_height,
              fill: color,
              stroke: "#333",
              stroke_width: 0.5
            })
          )

        # Label on right for left nodes, left for right nodes
        {label_x, text_anchor} = if node.x0 < (width - 150) / 2 do
          {node.x1 + 6, "start"}
        else
          {node.x0 - 6, "end"}
        end

        Element.append(group,
          Element.text(%{
            x: label_x,
            y: node.y0 + node_height / 2 + 4,
            text_anchor: text_anchor,
            font_size: 11,
            fill: "#333"
          })
          |> Element.content(node.name || node.id)
        )
      end)

    # Compose SVG
    chart_group = Element.g(%{transform: "translate(60,25)"})
      |> Element.append(link_elements)
      |> Element.append(node_elements)

    Element.svg(%{width: width, height: height, viewBox: "0 0 #{width} #{height}"})
    |> Element.append(chart_group)
  end

  # Animation: vary flow values with smooth sine waves
  # Each link has its own phase offset for visual interest
  defp generate_animated_links(tick) do
    phase = tick * 0.08

    # Base values for each link with individual phase offsets
    base_links = [
      # Sources to conversion - primary energy fluctuates
      {%{source: "coal", target: "electricity"}, 20, 0.0, 8},
      {%{source: "gas", target: "electricity"}, 15, 0.5, 6},
      {%{source: "gas", target: "heating"}, 10, 1.0, 4},
      {%{source: "nuclear", target: "electricity"}, 18, 1.5, 3},  # Nuclear is more stable
      {%{source: "solar", target: "electricity"}, 8, 2.0, 6},     # Solar varies more (day/night)
      {%{source: "oil", target: "transport"}, 25, 2.5, 8},
      # Conversion to end use - demand fluctuates
      {%{source: "electricity", target: "industry"}, 25, 3.0, 10},
      {%{source: "electricity", target: "homes"}, 20, 3.5, 8},
      {%{source: "electricity", target: "transport"}, 16, 4.0, 6},
      {%{source: "heating", target: "homes"}, 10, 4.5, 5},
      {%{source: "transport", target: "industry"}, 15, 5.0, 6}
    ]

    Enum.map(base_links, fn {link_base, base_value, phase_offset, amplitude} ->
      # Smooth sine wave variation
      variation = :math.sin(phase + phase_offset) * amplitude
      value = max(2, base_value + variation)  # Ensure minimum flow

      Map.put(link_base, :value, value)
    end)
  end

  def sample_code do
    ~S"""
    alias Visualize.Layout.Sankey

    nodes = [
      %{id: "a", name: "Source A"},
      %{id: "b", name: "Target B"}
    ]

    links = [
      %{source: "a", target: "b", value: 10}
    ]

    sankey = Sankey.new()
      |> Sankey.size(width, height)
      |> Sankey.node_width(20)
      |> Sankey.node_padding(10)
      |> Sankey.compute(nodes, links)

    # sankey.nodes have x0, x1, y0, y1
    # sankey.links have path data
    """
  end
end
