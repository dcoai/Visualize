if Code.ensure_loaded?(Phoenix.Component) do
  defmodule Visualize.Components.Tree do
    @moduledoc """
    Phoenix LiveView components for hierarchical tree visualizations.

    ## Usage

        import Visualize.Components.Tree

        <.tree_diagram
          data={@hierarchy_data}
          width={800}
          height={600}
        />

    """

    use Phoenix.Component

    alias Visualize.Layout.{Hierarchy, Tree, Treemap}
    alias Visualize.{Scale, Shape, SVG}

    @doc """
    Renders a tree diagram (node-link visualization).

    ## Attributes

    * `data` - Nested map with :children key (required)
    * `width` - Chart width in pixels (default: 800)
    * `height` - Chart height in pixels (default: 600)
    * `margin` - Map with :top, :right, :bottom, :left (optional)
    * `orientation` - :horizontal or :vertical (default: :horizontal)
    * `node_radius` - Radius of node circles (default: 6)
    * `node_fill` - Fill color for nodes (default: "#fff")
    * `node_stroke` - Stroke color for nodes (default: "steelblue")
    * `link_stroke` - Link line color (default: "#ccc")
    * `label` - Accessor for node labels (default: & &1[:name])
    * `animate` - Enable CSS transitions (default: false)

    """
    attr :data, :map, required: true
    attr :width, :integer, default: 800
    attr :height, :integer, default: 600
    attr :margin, :map, default: %{top: 20, right: 120, bottom: 20, left: 120}
    attr :orientation, :atom, default: :horizontal
    attr :node_radius, :integer, default: 6
    attr :node_fill, :string, default: "#fff"
    attr :node_stroke, :string, default: "steelblue"
    attr :link_stroke, :string, default: "#ccc"
    attr :label, :any, default: nil
    attr :animate, :boolean, default: false
    attr :class, :string, default: nil

    def tree_diagram(assigns) do
      margin = Map.merge(%{top: 20, right: 120, bottom: 20, left: 120}, assigns.margin || %{})
      inner_width = assigns.width - margin.left - margin.right
      inner_height = assigns.height - margin.top - margin.bottom

      # Build hierarchy
      root = Hierarchy.new(assigns.data)

      # Apply tree layout
      tree_layout = Tree.new()
                    |> Tree.size(
                      if assigns.orientation == :horizontal do
                        [inner_height, inner_width]
                      else
                        [inner_width, inner_height]
                      end
                    )

      positioned = Tree.generate(tree_layout, root)

      # Get nodes and links
      nodes = Hierarchy.descendants(positioned)
      links = Hierarchy.links(positioned)

      label_fn = assigns.label || fn d -> d[:name] || d["name"] end

      transition_style = if assigns.animate, do: "transition: all 0.3s ease-in-out;", else: ""

      assigns = assign(assigns,
        margin: margin,
        nodes: nodes,
        links: links,
        label_fn: label_fn,
        transition_style: transition_style
      )

      ~H"""
      <svg
        width={@width}
        height={@height}
        class={@class}
        viewBox={"0 0 #{@width} #{@height}"}
      >
        <g transform={"translate(#{@margin.left}, #{@margin.top})"}>
          <%= for {source, target} <- @links do %>
            <path
              d={link_path(source, target, @orientation)}
              fill="none"
              stroke={@link_stroke}
              stroke-width="1.5"
              style={@transition_style}
            />
          <% end %>

          <%= for node <- @nodes do %>
            <g transform={node_transform(node, @orientation)} style={@transition_style}>
              <circle
                r={@node_radius}
                fill={if node.children, do: @node_stroke, else: @node_fill}
                stroke={@node_stroke}
                stroke-width="2"
              />
              <text
                dy="0.31em"
                x={label_x(node, @orientation)}
                text-anchor={label_anchor(node, @orientation)}
                font-size="12"
              ><%= @label_fn.(node.data) %></text>
            </g>
          <% end %>
        </g>
      </svg>
      """
    end

    @doc """
    Renders a treemap visualization.

    ## Attributes

    * `data` - Nested map with :children and :value keys (required)
    * `width` - Chart width in pixels (default: 800)
    * `height` - Chart height in pixels (default: 600)
    * `value` - Accessor for leaf values (default: & &1[:value])
    * `label` - Accessor for labels (default: & &1[:name])
    * `tile` - Tiling algorithm: :squarify, :binary, :slice, :dice (default: :squarify)
    * `padding` - Padding between cells (default: 2)
    * `colors` - Color scheme (default: :category10)
    * `animate` - Enable CSS transitions (default: false)

    """
    attr :data, :map, required: true
    attr :width, :integer, default: 800
    attr :height, :integer, default: 600
    attr :value, :any, default: nil
    attr :label, :any, default: nil
    attr :tile, :atom, default: :squarify
    attr :padding, :integer, default: 2
    attr :colors, :any, default: :category10
    attr :animate, :boolean, default: false
    attr :class, :string, default: nil

    def treemap_chart(assigns) do
      value_fn = assigns.value || fn d -> d[:value] || 0 end
      label_fn = assigns.label || fn d -> d[:name] || d["name"] end

      # Build hierarchy and compute values
      root = Hierarchy.new(assigns.data)
             |> Hierarchy.sum(value_fn)

      # Apply treemap layout
      treemap = Treemap.new()
                |> Treemap.size({assigns.width, assigns.height})
                |> Treemap.tile(assigns.tile)
                |> Treemap.padding(assigns.padding)

      positioned = Treemap.generate(treemap, root)

      # Get leaf nodes for rendering
      leaves = Hierarchy.leaves(positioned)

      # Color scale based on parent
      unique_parents = leaves
                       |> Enum.map(fn n -> if n.parent, do: n.parent.data, else: n.data end)
                       |> Enum.uniq()

      color_scale = Scale.color()
                    |> Scale.scheme(if is_atom(assigns.colors), do: assigns.colors, else: :category10)
                    |> Scale.domain(Enum.to_list(0..(length(unique_parents) - 1)))

      parent_colors = unique_parents
                      |> Enum.with_index()
                      |> Enum.map(fn {p, i} -> {p, Scale.scale(color_scale, i)} end)
                      |> Map.new()

      transition_style = if assigns.animate, do: "transition: all 0.3s ease-in-out;", else: ""

      assigns = assign(assigns,
        leaves: leaves,
        label_fn: label_fn,
        parent_colors: parent_colors,
        transition_style: transition_style
      )

      ~H"""
      <svg
        width={@width}
        height={@height}
        class={@class}
        viewBox={"0 0 #{@width} #{@height}"}
      >
        <%= for node <- @leaves do %>
          <% parent_data = if node.parent, do: node.parent.data, else: node.data %>
          <g>
            <rect
              x={node.x0}
              y={node.y0}
              width={max(0, node.x1 - node.x0)}
              height={max(0, node.y1 - node.y0)}
              fill={Map.get(@parent_colors, parent_data, "#ccc")}
              stroke="white"
              stroke-width="1"
              style={@transition_style}
            />
            <%= if (node.x1 - node.x0) > 30 and (node.y1 - node.y0) > 15 do %>
              <text
                x={node.x0 + 4}
                y={node.y0 + 14}
                font-size="11"
                fill="white"
                style="text-shadow: 0 1px 2px rgba(0,0,0,0.5);"
              ><%= truncate_label(@label_fn.(node.data), node.x1 - node.x0 - 8) %></text>
            <% end %>
          </g>
        <% end %>
      </svg>
      """
    end

    @doc """
    Renders a sunburst (radial treemap) visualization.

    ## Attributes

    * `data` - Nested map with :children and :value keys (required)
    * `width` - Chart width in pixels (default: 600)
    * `height` - Chart height in pixels (default: 600)
    * `value` - Accessor for leaf values (default: & &1[:value])
    * `label` - Accessor for labels (default: & &1[:name])
    * `colors` - Color scheme (default: :category10)
    * `animate` - Enable CSS transitions (default: false)

    """
    attr :data, :map, required: true
    attr :width, :integer, default: 600
    attr :height, :integer, default: 600
    attr :value, :any, default: nil
    attr :label, :any, default: nil
    attr :colors, :any, default: :category10
    attr :animate, :boolean, default: false
    attr :class, :string, default: nil

    def sunburst_chart(assigns) do
      value_fn = assigns.value || fn d -> d[:value] || 0 end
      label_fn = assigns.label || fn d -> d[:name] || d["name"] end

      radius = min(assigns.width, assigns.height) / 2

      # Build hierarchy and compute values
      root = Hierarchy.new(assigns.data)
             |> Hierarchy.sum(value_fn)

      # Get all descendants with computed positions
      nodes = Hierarchy.descendants(root)
      total_value = root.value || 1

      # Compute angular positions for each node
      {positioned_nodes, _} = compute_sunburst_layout(nodes, total_value, 0, 2 * :math.pi())

      # Depth-based radius scale
      max_depth = nodes |> Enum.map(& &1.depth) |> Enum.max(fn -> 0 end)
      depth_scale = fn depth -> depth / (max_depth + 1) * radius end

      # Color scale
      top_level = nodes |> Enum.filter(& &1.depth == 1)
      color_scale = Scale.color()
                    |> Scale.scheme(if is_atom(assigns.colors), do: assigns.colors, else: :category10)
                    |> Scale.domain(Enum.to_list(0..(length(top_level) - 1)))

      node_colors = assign_sunburst_colors(positioned_nodes, color_scale)

      transition_style = if assigns.animate, do: "transition: all 0.3s ease-in-out;", else: ""

      assigns = assign(assigns,
        radius: radius,
        positioned_nodes: positioned_nodes,
        depth_scale: depth_scale,
        node_colors: node_colors,
        label_fn: label_fn,
        transition_style: transition_style
      )

      ~H"""
      <svg
        width={@width}
        height={@height}
        class={@class}
        viewBox={"0 0 #{@width} #{@height}"}
      >
        <g transform={"translate(#{@width / 2}, #{@height / 2})"}>
          <%= for node <- @positioned_nodes do %>
            <%= if node.depth > 0 do %>
              <% inner_r = @depth_scale.(node.depth - 1) %>
              <% outer_r = @depth_scale.(node.depth) %>
              <path
                d={sunburst_arc_path(inner_r, outer_r, node.start_angle, node.end_angle)}
                fill={Map.get(@node_colors, node, "#ccc")}
                stroke="white"
                stroke-width="1"
                style={@transition_style}
              />
            <% end %>
          <% end %>
        </g>
      </svg>
      """
    end

    # Helper functions

    defp node_transform(node, :horizontal), do: "translate(#{node.y}, #{node.x})"
    defp node_transform(node, :vertical), do: "translate(#{node.x}, #{node.y})"

    defp link_path(source, target, :horizontal) do
      "M#{source.y},#{source.x}" <>
      "C#{(source.y + target.y) / 2},#{source.x}" <>
      " #{(source.y + target.y) / 2},#{target.x}" <>
      " #{target.y},#{target.x}"
    end

    defp link_path(source, target, :vertical) do
      "M#{source.x},#{source.y}" <>
      "C#{source.x},#{(source.y + target.y) / 2}" <>
      " #{target.x},#{(source.y + target.y) / 2}" <>
      " #{target.x},#{target.y}"
    end

    defp label_x(node, :horizontal) do
      if node.children, do: -10, else: 10
    end

    defp label_x(node, :vertical) do
      0
    end

    defp label_anchor(node, :horizontal) do
      if node.children, do: "end", else: "start"
    end

    defp label_anchor(_node, :vertical), do: "middle"

    defp truncate_label(label, max_width) do
      chars = trunc(max_width / 7)
      if String.length(label) > chars do
        String.slice(label, 0, max(chars - 1, 0)) <> "…"
      else
        label
      end
    end

    defp compute_sunburst_layout(nodes, total_value, start_angle, end_angle) do
      # Process nodes level by level, computing angles
      root = Enum.find(nodes, & &1.depth == 0)
      root_with_angles = Map.merge(root, %{start_angle: start_angle, end_angle: end_angle})

      process_children([root_with_angles], nodes, total_value)
    end

    defp process_children([], _all_nodes, _total), do: {[], 0}

    defp process_children(parents, all_nodes, total) do
      {result, _} =
        Enum.flat_map_reduce(parents, [], fn parent, acc ->
          children = Enum.filter(all_nodes, fn n ->
            n.parent == get_original_node(parent, all_nodes)
          end)

          if Enum.empty?(children) do
            {[parent], acc}
          else
            angle_range = parent.end_angle - parent.start_angle
            children_total = Enum.reduce(children, 0, fn c, a -> a + (c.value || 0) end)

            {positioned_children, _} =
              Enum.map_reduce(children, parent.start_angle, fn child, curr_angle ->
                child_angle = if children_total > 0 do
                  (child.value || 0) / children_total * angle_range
                else
                  angle_range / length(children)
                end

                positioned = Map.merge(child, %{
                  start_angle: curr_angle,
                  end_angle: curr_angle + child_angle
                })

                {positioned, curr_angle + child_angle}
              end)

            {grandchildren, _} = process_children(positioned_children, all_nodes, total)
            {[parent | grandchildren], acc}
          end
        end)

      {result, 0}
    end

    defp get_original_node(positioned, all_nodes) do
      Enum.find(all_nodes, fn n -> n.data == positioned.data and n.depth == positioned.depth end)
    end

    defp assign_sunburst_colors(nodes, color_scale) do
      top_level = nodes
                  |> Enum.filter(fn n -> Map.get(n, :depth, 0) == 1 end)
                  |> Enum.with_index()

      top_colors = Map.new(top_level, fn {node, i} ->
        {node.data, Scale.scale(color_scale, i)}
      end)

      nodes
      |> Enum.map(fn node ->
        color = find_ancestor_color(node, nodes, top_colors)
        {node, color}
      end)
      |> Map.new()
    end

    defp find_ancestor_color(node, _nodes, top_colors) do
      depth = Map.get(node, :depth, 0)

      cond do
        depth == 0 -> "#ddd"
        depth == 1 -> Map.get(top_colors, node.data, "#ccc")
        true ->
          # Find ancestor at depth 1
          case find_depth_one_ancestor(node) do
            nil -> "#ccc"
            ancestor -> Map.get(top_colors, ancestor.data, "#ccc")
          end
      end
    end

    defp find_depth_one_ancestor(%{parent: nil}), do: nil
    defp find_depth_one_ancestor(%{depth: 1} = node), do: node
    defp find_depth_one_ancestor(%{parent: parent}), do: find_depth_one_ancestor(parent)
    defp find_depth_one_ancestor(_), do: nil

    defp sunburst_arc_path(inner_r, outer_r, start_angle, end_angle) do
      # Adjust angles (SVG starts at 12 o'clock, we want 3 o'clock)
      start_angle = start_angle - :math.pi() / 2
      end_angle = end_angle - :math.pi() / 2

      x0 = outer_r * :math.cos(start_angle)
      y0 = outer_r * :math.sin(start_angle)
      x1 = outer_r * :math.cos(end_angle)
      y1 = outer_r * :math.sin(end_angle)
      x2 = inner_r * :math.cos(end_angle)
      y2 = inner_r * :math.sin(end_angle)
      x3 = inner_r * :math.cos(start_angle)
      y3 = inner_r * :math.sin(start_angle)

      large_arc = if end_angle - start_angle > :math.pi(), do: 1, else: 0

      "M#{x0},#{y0}" <>
      "A#{outer_r},#{outer_r} 0 #{large_arc},1 #{x1},#{y1}" <>
      "L#{x2},#{y2}" <>
      "A#{inner_r},#{inner_r} 0 #{large_arc},0 #{x3},#{y3}" <>
      "Z"
    end
  end
end
