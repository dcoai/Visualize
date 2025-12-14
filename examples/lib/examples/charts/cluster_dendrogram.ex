defmodule Examples.Charts.ClusterDendrogram do
  @moduledoc "Cluster dendrogram for hierarchical clustering visualization"

  alias Visualize.Layout.{Cluster, Hierarchy}
  alias Visualize.SVG.Element
  alias Examples.ColorPalettes

  @data %{
    name: "Life",
    children: [
      %{name: "Archaea", children: [
        %{name: "Euryarchaeota"},
        %{name: "Crenarchaeota"},
        %{name: "Korarchaeota"}
      ]},
      %{name: "Bacteria", children: [
        %{name: "Proteobacteria"},
        %{name: "Cyanobacteria"},
        %{name: "Firmicutes"},
        %{name: "Actinobacteria"}
      ]},
      %{name: "Eukaryota", children: [
        %{name: "Animals", children: [
          %{name: "Mammals"},
          %{name: "Birds"},
          %{name: "Reptiles"},
          %{name: "Fish"}
        ]},
        %{name: "Plants", children: [
          %{name: "Flowering"},
          %{name: "Conifers"},
          %{name: "Ferns"}
        ]},
        %{name: "Fungi", children: [
          %{name: "Ascomycota"},
          %{name: "Basidiomycota"}
        ]}
      ]}
    ]
  }

  def title, do: "Cluster Dendrogram"
  def description, do: "Tree of life classification"

  def render(opts \\ []) do
    width = opts[:width] || 700
    height = opts[:height] || 400
    margin_left = 60
    margin_right = 120
    margin_top = 20
    margin_bottom = 20
    animation_tick = opts[:animation_tick]

    data = opts[:data] || @data
    palette = opts[:palette] || :default
    colors = ColorPalettes.colors(palette)

    # Build hierarchy
    root = Hierarchy.new(data)

    # Create cluster layout
    cluster = Cluster.new()
      |> Cluster.size([width - margin_left - margin_right, height - margin_top - margin_bottom])

    positioned = Cluster.generate(cluster, root)

    # Get all nodes and links
    all_nodes = get_all_nodes(positioned)
    links = get_links(positioned)

    # Draw links with step/elbow style
    link_elements = Enum.map(links, fn {parent, child} ->
      # Elbow connector: horizontal then vertical
      Element.path(%{
        d: "M#{parent.x},#{parent.y}H#{child.x}V#{child.y}",
        fill: "none",
        stroke: "#999",
        stroke_width: 1
      })
    end)

    # Draw nodes
    node_elements = all_nodes
      |> Enum.with_index()
      |> Enum.map(fn {node, idx} ->
      is_leaf = is_nil(node.children) || Enum.empty?(node.children || [])
      color = Enum.at(colors, rem(idx, length(colors)))

      # Animated node radius
      base_r = if(is_leaf, do: 4, else: 3)
      r = if animation_tick do
        phase = animation_tick * 0.08
        offset = idx * 0.25
        base_r + :math.sin(phase + offset) * 1.5
      else
        base_r
      end

      group = Element.g(%{transform: "translate(#{node.x},#{node.y})"})
        |> Element.append(
          Element.circle(%{
            r: r,
            fill: if(is_leaf, do: color, else: darken(color)),
            stroke: "#fff",
            stroke_width: 1
          })
        )

      # Add labels
      if is_leaf do
        Element.append(group,
          Element.text(%{
            x: 8,
            y: 4,
            text_anchor: "start",
            font_size: 9,
            fill: "#333"
          })
          |> Element.content(node.data.name)
        )
      else
        Element.append(group,
          Element.text(%{
            x: -8,
            y: 4,
            text_anchor: "end",
            font_size: 9,
            fill: "#666"
          })
          |> Element.content(node.data.name)
        )
      end
    end)

    # Compose SVG
    chart_group = Element.g(%{transform: "translate(#{margin_left},#{margin_top})"})
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

  defp darken("#" <> hex) do
    {r, ""} = Integer.parse(String.slice(hex, 0, 2), 16)
    {g, ""} = Integer.parse(String.slice(hex, 2, 2), 16)
    {b, ""} = Integer.parse(String.slice(hex, 4, 2), 16)

    r = trunc(r * 0.6)
    g = trunc(g * 0.6)
    b = trunc(b * 0.6)

    r_hex = Integer.to_string(r, 16) |> String.pad_leading(2, "0")
    g_hex = Integer.to_string(g, 16) |> String.pad_leading(2, "0")
    b_hex = Integer.to_string(b, 16) |> String.pad_leading(2, "0")

    "#" <> r_hex <> g_hex <> b_hex
  end

  def sample_code do
    ~S"""
    alias Visualize.Layout.{Cluster, Hierarchy}

    root = Hierarchy.new(data)

    cluster = Cluster.new()
      |> Cluster.size([width, height])

    positioned = Cluster.generate(cluster, root)

    # Unlike tree layout, all leaves align at same depth
    # Creates dendrogram effect
    """
  end
end
