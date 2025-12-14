defmodule Visualize.Layout.Sankey do
  @moduledoc """
  Sankey diagram layout for visualizing flow between nodes.

  Creates flow diagrams where the width of links is proportional
  to the flow quantity. Commonly used for showing energy transfers,
  money flows, or any directed weighted graph.

  ## Examples

      nodes = [
        %{id: "a", name: "Source A"},
        %{id: "b", name: "Source B"},
        %{id: "c", name: "Target C"},
        %{id: "d", name: "Target D"}
      ]

      links = [
        %{source: "a", target: "c", value: 10},
        %{source: "a", target: "d", value: 5},
        %{source: "b", target: "c", value: 8},
        %{source: "b", target: "d", value: 12}
      ]

      sankey = Visualize.Layout.Sankey.new()
        |> Visualize.Layout.Sankey.size(400, 300)
        |> Visualize.Layout.Sankey.node_width(20)
        |> Visualize.Layout.Sankey.node_padding(10)
        |> Visualize.Layout.Sankey.compute(nodes, links)

      # Access computed positions
      sankey.nodes  # Nodes with x0, x1, y0, y1 coordinates
      sankey.links  # Links with source/target nodes and path data

  """

  alias Visualize.SVG.Path

  defstruct nodes: [],
            links: [],
            width: 400,
            height: 300,
            node_width: 24,
            node_padding: 8,
            iterations: 6,
            node_align: :justify,
            link_sort: nil

  @type sankey_node :: %{
          required(:id) => any(),
          optional(:name) => String.t(),
          optional(:x0) => number(),
          optional(:x1) => number(),
          optional(:y0) => number(),
          optional(:y1) => number(),
          optional(:value) => number(),
          optional(:layer) => non_neg_integer(),
          optional(:source_links) => [map()],
          optional(:target_links) => [map()]
        }

  @type sankey_link :: %{
          required(:source) => any(),
          required(:target) => any(),
          required(:value) => number(),
          optional(:y0) => number(),
          optional(:y1) => number(),
          optional(:width) => number(),
          optional(:path) => String.t()
        }

  @type t :: %__MODULE__{
          nodes: [sankey_node()],
          links: [sankey_link()],
          width: number(),
          height: number(),
          node_width: number(),
          node_padding: number(),
          iterations: non_neg_integer(),
          node_align: :left | :right | :center | :justify,
          link_sort: (sankey_link(), sankey_link() -> boolean()) | nil
        }

  @doc "Creates a new Sankey layout"
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc "Sets the diagram size"
  @spec size(t(), number(), number()) :: t()
  def size(%__MODULE__{} = sankey, width, height) do
    %{sankey | width: width, height: height}
  end

  @doc "Sets the node width"
  @spec node_width(t(), number()) :: t()
  def node_width(%__MODULE__{} = sankey, width) do
    %{sankey | node_width: width}
  end

  @doc "Sets the vertical padding between nodes"
  @spec node_padding(t(), number()) :: t()
  def node_padding(%__MODULE__{} = sankey, padding) do
    %{sankey | node_padding: padding}
  end

  @doc "Sets the number of relaxation iterations"
  @spec iterations(t(), non_neg_integer()) :: t()
  def iterations(%__MODULE__{} = sankey, n) do
    %{sankey | iterations: n}
  end

  @doc """
  Sets the node alignment method.

  - `:left` - Nodes align to the left
  - `:right` - Nodes align to the right
  - `:center` - Nodes are centered
  - `:justify` - Nodes stretch to fill the width (default)
  """
  @spec node_align(t(), :left | :right | :center | :justify) :: t()
  def node_align(%__MODULE__{} = sankey, align) do
    %{sankey | node_align: align}
  end

  @doc """
  Sets a custom link sorting function.

  Links are sorted vertically within their source/target nodes.
  """
  @spec link_sort(t(), (sankey_link(), sankey_link() -> boolean())) :: t()
  def link_sort(%__MODULE__{} = sankey, sort_fn) do
    %{sankey | link_sort: sort_fn}
  end

  @doc """
  Computes the Sankey layout from nodes and links.

  Returns the sankey struct with computed node positions and link paths.
  """
  @spec compute(t(), [sankey_node()], [sankey_link()]) :: t()
  def compute(%__MODULE__{} = sankey, nodes, links) do
    # Build node index
    node_index = build_node_index(nodes)

    # Initialize nodes with metadata
    nodes = initialize_nodes(nodes, links, node_index)

    # Initialize links with references
    links = initialize_links(links, node_index, nodes)

    # Compute node layers (horizontal position)
    nodes = compute_node_layers(nodes)

    # Compute horizontal positions
    nodes = compute_node_x(nodes, sankey)

    # Compute vertical positions
    nodes = compute_node_y(nodes, links, sankey)

    # Compute link positions and paths
    links = compute_link_positions(links, nodes, sankey)

    %{sankey | nodes: nodes, links: links}
  end

  @doc "Generates SVG path data for a link"
  @spec link_path(sankey_link()) :: String.t()
  def link_path(%{path: path}) when is_binary(path), do: path

  def link_path(link) do
    generate_link_path(link)
  end

  @doc "Generates SVG path data for all links"
  @spec link_paths(t()) :: [String.t()]
  def link_paths(%__MODULE__{links: links}) do
    Enum.map(links, &link_path/1)
  end

  @doc """
  Generates a horizontal link path using cubic Bezier curves.

  This creates the characteristic curved flow appearance.
  """
  @spec generate_link_path(sankey_link()) :: String.t()
  def generate_link_path(%{source_node: source, target_node: target, y0: y0, y1: y1, width: width}) do
    x0 = source.x1
    x1 = target.x0

    # Control points for smooth curve
    xi = (x0 + x1) / 2

    Path.new()
    |> Path.move_to(x0, y0)
    |> Path.curve_to(xi, y0, xi, y1, x1, y1)
    |> Path.line_to(x1, y1 + width)
    |> Path.curve_to(xi, y1 + width, xi, y0 + width, x0, y0 + width)
    |> Path.close()
    |> Path.to_string()
  end

  def generate_link_path(_), do: ""

  @doc "Returns the nodes grouped by layer"
  @spec nodes_by_layer(t()) :: [[sankey_node()]]
  def nodes_by_layer(%__MODULE__{nodes: nodes}) do
    nodes
    |> Enum.group_by(& &1.layer)
    |> Enum.sort_by(fn {layer, _} -> layer end)
    |> Enum.map(fn {_, layer_nodes} -> layer_nodes end)
  end

  # ============================================
  # Private Implementation
  # ============================================

  defp build_node_index(nodes) do
    nodes
    |> Enum.with_index()
    |> Enum.map(fn {node, i} -> {node.id, i} end)
    |> Map.new()
  end

  defp initialize_nodes(nodes, links, node_index) do
    # Group links by source and target
    source_links = Enum.group_by(links, & &1.source)
    target_links = Enum.group_by(links, & &1.target)

    Enum.map(nodes, fn node ->
      node_source_links = Map.get(source_links, node.id, [])
      node_target_links = Map.get(target_links, node.id, [])

      # Node value is the max of incoming or outgoing flow
      outgoing = Enum.reduce(node_source_links, 0, fn l, acc -> acc + l.value end)
      incoming = Enum.reduce(node_target_links, 0, fn l, acc -> acc + l.value end)
      value = max(outgoing, incoming)

      Map.merge(node, %{
        index: node_index[node.id],
        source_links: node_source_links,
        target_links: node_target_links,
        value: value,
        layer: nil,
        x0: 0,
        x1: 0,
        y0: 0,
        y1: 0
      })
    end)
  end

  defp initialize_links(links, node_index, nodes) do
    nodes_by_id = Enum.map(nodes, fn n -> {n.id, n} end) |> Map.new()

    Enum.map(links, fn link ->
      Map.merge(link, %{
        source_index: node_index[link.source],
        target_index: node_index[link.target],
        source_node: nodes_by_id[link.source],
        target_node: nodes_by_id[link.target],
        y0: 0,
        y1: 0,
        width: 0,
        path: nil
      })
    end)
  end

  defp compute_node_layers(nodes) do
    # Find nodes with no incoming links (sources)
    # target_ids = all node IDs that appear as targets in links (have incoming links)
    target_ids = nodes |> Enum.flat_map(& &1.source_links) |> Enum.map(& &1.target) |> MapSet.new()

    # Source nodes = nodes that are NOT targets (have no incoming links)
    source_nodes =
      nodes
      |> Enum.filter(fn n -> not MapSet.member?(target_ids, n.id) end)
      |> Enum.map(& &1.id)
      |> MapSet.new()

    # BFS to assign layers
    assign_layers(nodes, source_nodes, %{})
  end

  defp assign_layers(nodes, _to_visit, layers) when map_size(layers) == length(nodes) do
    # All nodes have layers assigned
    Enum.map(nodes, fn node ->
      %{node | layer: Map.get(layers, node.id, 0)}
    end)
  end

  defp assign_layers(nodes, to_visit, layers) do
    if MapSet.size(to_visit) == 0 do
      # Handle cycles or disconnected nodes
      unassigned = Enum.filter(nodes, fn n -> not Map.has_key?(layers, n.id) end)

      if Enum.empty?(unassigned) do
        Enum.map(nodes, fn node ->
          %{node | layer: Map.get(layers, node.id, 0)}
        end)
      else
        # Assign remaining nodes to layer 0
        new_layers =
          Enum.reduce(unassigned, layers, fn n, acc ->
            Map.put(acc, n.id, 0)
          end)

        Enum.map(nodes, fn node ->
          %{node | layer: Map.get(new_layers, node.id, 0)}
        end)
      end
    else
      # Process nodes at current frontier
      {new_layers, next_to_visit} =
        Enum.reduce(to_visit, {layers, MapSet.new()}, fn node_id, {acc_layers, acc_next} ->
          node = Enum.find(nodes, fn n -> n.id == node_id end)

          if node do
            layer =
              if Map.has_key?(acc_layers, node_id) do
                acc_layers[node_id]
              else
                # Layer is max of all source layers + 1
                source_layers =
                  node.target_links
                  |> Enum.map(fn l -> Map.get(acc_layers, l.source, -1) end)
                  |> Enum.filter(&(&1 >= 0))

                if Enum.empty?(source_layers), do: 0, else: Enum.max(source_layers) + 1
              end

            new_acc_layers = Map.put(acc_layers, node_id, layer)

            # Add targets to next iteration
            targets =
              node.source_links
              |> Enum.map(& &1.target)
              |> Enum.filter(fn id -> not Map.has_key?(new_acc_layers, id) end)
              |> MapSet.new()

            {new_acc_layers, MapSet.union(acc_next, targets)}
          else
            {acc_layers, acc_next}
          end
        end)

      assign_layers(nodes, next_to_visit, new_layers)
    end
  end

  defp compute_node_x(nodes, sankey) do
    max_layer = nodes |> Enum.map(& &1.layer) |> Enum.max(fn -> 0 end)

    x_scale =
      if max_layer == 0 do
        0
      else
        (sankey.width - sankey.node_width) / max_layer
      end

    Enum.map(nodes, fn node ->
      x0 =
        case sankey.node_align do
          :left -> node.layer * x_scale
          :right -> sankey.width - sankey.node_width - node.layer * x_scale
          :center -> (sankey.width - sankey.node_width) / 2
          :justify -> node.layer * x_scale
        end

      %{node | x0: x0, x1: x0 + sankey.node_width}
    end)
  end

  defp compute_node_y(nodes, links, sankey) do
    # Group nodes by layer
    by_layer =
      nodes
      |> Enum.group_by(& &1.layer)
      |> Enum.sort_by(fn {layer, _} -> layer end)

    # Initial positioning
    nodes =
      Enum.flat_map(by_layer, fn {_layer, layer_nodes} ->
        total_value = Enum.reduce(layer_nodes, 0, fn n, acc -> acc + n.value end)
        padding_total = (length(layer_nodes) - 1) * sankey.node_padding

        available_height = sankey.height - padding_total
        value_scale = if total_value > 0, do: available_height / total_value, else: 0

        {positioned, _} =
          layer_nodes
          |> Enum.sort_by(& &1.index)
          |> Enum.reduce({[], 0}, fn node, {acc, y} ->
            height = node.value * value_scale
            node = %{node | y0: y, y1: y + height}
            {[node | acc], y + height + sankey.node_padding}
          end)

        Enum.reverse(positioned)
      end)

    # Iterative relaxation
    relax_nodes(nodes, links, sankey)
  end

  defp relax_nodes(nodes, _links, %{iterations: 0}), do: nodes

  defp relax_nodes(nodes, links, sankey) do
    nodes_by_id = Enum.map(nodes, fn n -> {n.id, n} end) |> Map.new()

    # Relax nodes based on link positions
    relaxed =
      Enum.map(nodes, fn node ->
        # Calculate weighted average of connected node positions
        incoming_y =
          node.target_links
          |> Enum.map(fn l ->
            source = Map.get(nodes_by_id, l.source)
            if source, do: {(source.y0 + source.y1) / 2, l.value}, else: nil
          end)
          |> Enum.filter(& &1)

        outgoing_y =
          node.source_links
          |> Enum.map(fn l ->
            target = Map.get(nodes_by_id, l.target)
            if target, do: {(target.y0 + target.y1) / 2, l.value}, else: nil
          end)
          |> Enum.filter(& &1)

        all_weighted = incoming_y ++ outgoing_y

        if Enum.empty?(all_weighted) do
          node
        else
          total_weight = Enum.reduce(all_weighted, 0, fn {_, w}, acc -> acc + w end)
          weighted_y = Enum.reduce(all_weighted, 0, fn {y, w}, acc -> acc + y * w end) / total_weight

          height = node.y1 - node.y0
          new_y0 = weighted_y - height / 2

          # Keep within bounds
          new_y0 = max(0, min(sankey.height - height, new_y0))

          %{node | y0: new_y0, y1: new_y0 + height}
        end
      end)

    # Resolve overlaps
    resolved = resolve_overlaps(relaxed, sankey)

    relax_nodes(resolved, links, %{sankey | iterations: sankey.iterations - 1})
  end

  defp resolve_overlaps(nodes, sankey) do
    # Group by layer and resolve within each layer
    nodes
    |> Enum.group_by(& &1.layer)
    |> Enum.flat_map(fn {_layer, layer_nodes} ->
      sorted = Enum.sort_by(layer_nodes, & &1.y0)

      # First pass: resolve overlaps by pushing down
      {resolved, _} =
        Enum.reduce(sorted, {[], 0}, fn node, {acc, min_y} ->
          y0 = max(node.y0, min_y)
          height = node.y1 - node.y0
          node = %{node | y0: y0, y1: y0 + height}
          {[node | acc], y0 + height + sankey.node_padding}
        end)

      resolved = Enum.reverse(resolved)

      # Second pass: if nodes overflow height, scale them to fit
      max_y = resolved |> Enum.map(& &1.y1) |> Enum.max(fn -> 0 end)
      if max_y > sankey.height do
        total_padding = (length(resolved) - 1) * sankey.node_padding
        available = sankey.height - total_padding
        total_height = resolved |> Enum.map(fn n -> n.y1 - n.y0 end) |> Enum.sum()
        scale = if total_height > 0, do: available / total_height, else: 1.0

        {scaled, _} =
          Enum.reduce(resolved, {[], 0}, fn node, {acc, y} ->
            height = (node.y1 - node.y0) * scale
            node = %{node | y0: y, y1: y + height}
            {[node | acc], y + height + sankey.node_padding}
          end)

        Enum.reverse(scaled)
      else
        resolved
      end
    end)
  end

  defp compute_link_positions(links, nodes, sankey) do
    nodes_by_id = Enum.map(nodes, fn n -> {n.id, n} end) |> Map.new()

    # Calculate value scale per layer (use max layer total for consistency)
    by_layer = Enum.group_by(nodes, & &1.layer)
    max_layer_value = by_layer
      |> Enum.map(fn {_layer, layer_nodes} ->
        Enum.reduce(layer_nodes, 0, fn n, acc -> acc + n.value end)
      end)
      |> Enum.max(fn -> 1 end)

    max_layer_count = by_layer
      |> Enum.map(fn {_layer, layer_nodes} -> length(layer_nodes) end)
      |> Enum.max(fn -> 1 end)

    padding_total = (max_layer_count - 1) * sankey.node_padding
    value_scale = (sankey.height - padding_total) / max_layer_value

    # Track y offset for each node's outgoing/incoming links
    source_y = Enum.map(nodes, fn n -> {n.id, n.y0} end) |> Map.new()
    target_y = Enum.map(nodes, fn n -> {n.id, n.y0} end) |> Map.new()

    {links, _, _} =
      links
      |> Enum.reduce({[], source_y, target_y}, fn link, {acc, src_y, tgt_y} ->
        source = Map.get(nodes_by_id, link.source)
        target = Map.get(nodes_by_id, link.target)

        if source && target do
          width = link.value * value_scale
          width = max(1, width)  # Minimum width

          y0 = Map.get(src_y, link.source, 0)
          y1 = Map.get(tgt_y, link.target, 0)

          link = %{
            link
            | source_node: source,
              target_node: target,
              y0: y0,
              y1: y1,
              width: width
          }

          link = %{link | path: generate_link_path(link)}

          new_src_y = Map.put(src_y, link.source, y0 + width)
          new_tgt_y = Map.put(tgt_y, link.target, y1 + width)

          {[link | acc], new_src_y, new_tgt_y}
        else
          {[link | acc], src_y, tgt_y}
        end
      end)

    Enum.reverse(links)
  end
end
