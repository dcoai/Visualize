defmodule Visualize.Layout.Sankey do
  @moduledoc """
  Sankey diagram layout for visualizing flow between nodes.

  Creates flow diagrams where the width of links is proportional
  to the flow quantity. Commonly used for showing energy transfers,
  money flows, or any directed weighted graph.

  The layout is a port of d3-sankey: columns come from the alignment function over the
  longest-path depth of every node, one scale sizes both node heights and link widths,
  and the vertical positions are relaxed towards the ideal link positions with
  two-sided collision resolution.

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
          optional(:depth) => non_neg_integer(),
          optional(:height) => non_neg_integer(),
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
  Sets the node alignment method (d3-sankey's `sankeyLeft`, `sankeyRight`,
  `sankeyCenter` and `sankeyJustify`).

  - `:left` - every node at its depth (longest path from a source)
  - `:right` - every node at `L - height` (longest path to a sink), so sinks share the last column
  - `:center` - a node with incoming links at its depth, a node with only outgoing links one
    column before its nearest target, an isolated node at 0
  - `:justify` - every node without outgoing links in the last column, others at their depth (default)
  """
  @spec node_align(t(), :left | :right | :center | :justify) :: t()
  def node_align(%__MODULE__{} = sankey, align)
      when align in [:left, :right, :center, :justify] do
    %{sankey | node_align: align}
  end

  @doc """
  Sets a custom link sorting function.

  Links are sorted vertically within their source/target nodes by this comparator (true
  when the first link comes first). When `nil`, links follow the vertical order of the
  node at their other end.
  """
  @spec link_sort(t(), (sankey_link(), sankey_link() -> boolean()) | nil) :: t()
  def link_sort(%__MODULE__{} = sankey, sort_fn) do
    %{sankey | link_sort: sort_fn}
  end

  @doc """
  Computes the Sankey layout from nodes and links.

  Returns the sankey struct with computed node positions and link paths.
  """
  @spec compute(t(), [sankey_node()], [sankey_link()]) :: t()
  def compute(%__MODULE__{} = sankey, nodes, links) do
    g =
      sankey
      |> build_graph(nodes, links)
      |> compute_depths()
      |> compute_heights()
      |> compute_columns()
      |> initialize_breadths()
      |> relax()
      |> compute_link_breadths()

    %{sankey | nodes: output_nodes(g, nodes), links: output_links(g, links)}
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
  def generate_link_path(%{
        source_node: source,
        target_node: target,
        y0: y0,
        y1: y1,
        width: width
      }) do
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
  #
  # The graph `g` holds `nodes` (id => node map) and `links` (index => link map) for the
  # links whose endpoints both exist; `ids` is the input order. A node's `source_links`
  # and `target_links` are link indices, in the vertical order the layout settles on.
  # ============================================

  defp build_graph(sankey, nodes, links) do
    ids = Enum.map(nodes, & &1.id)
    known = MapSet.new(ids)

    link_map =
      links
      |> Enum.with_index()
      |> Enum.filter(fn {l, _} ->
        MapSet.member?(known, l.source) and MapSet.member?(known, l.target)
      end)
      |> Map.new(fn {l, i} ->
        {i,
         %{
           index: i,
           source: l.source,
           target: l.target,
           value: l.value,
           width: 0,
           y0: 0,
           y1: 0,
           raw: l
         }}
      end)

    by_source = link_map |> Map.values() |> Enum.group_by(& &1.source, & &1.index)
    by_target = link_map |> Map.values() |> Enum.group_by(& &1.target, & &1.index)

    node_map =
      nodes
      |> Enum.with_index()
      |> Map.new(fn {n, i} ->
        outs = sort_links(Map.get(by_source, n.id, []), link_map, sankey.link_sort)
        ins = sort_links(Map.get(by_target, n.id, []), link_map, sankey.link_sort)
        value = max(sum_values(outs, link_map), sum_values(ins, link_map))

        {n.id,
         %{
           id: n.id,
           index: i,
           value: value,
           source_links: outs,
           target_links: ins,
           depth: 0,
           height: 0,
           layer: 0,
           x0: 0,
           x1: 0,
           y0: 0,
           y1: 0
         }}
      end)

    %{sankey: sankey, ids: ids, nodes: node_map, links: link_map, columns: [], py: 0}
  end

  defp sum_values(indices, links), do: Enum.reduce(indices, 0, &(links[&1].value + &2))

  defp sort_links(indices, _links, nil), do: Enum.sort(indices)

  defp sort_links(indices, links, sort_fn) do
    Enum.sort(indices, fn a, b -> sort_fn.(links[a].raw, links[b].raw) end)
  end

  # Longest path from a source (d3's computeNodeDepths): a node's depth is the round in
  # which it was last reached. A cycle would never settle, so the walk stops after as many
  # rounds as there are nodes and the nodes still pending keep the depth they have.
  defp compute_depths(g), do: longest_path(g, :depth, :source_links, & &1.target)
  defp compute_heights(g), do: longest_path(g, :height, :target_links, & &1.source)

  defp longest_path(g, field, links_field, other) do
    n = map_size(g.nodes)
    walk(g, field, links_field, other, MapSet.new(g.ids), 0, n)
  end

  defp walk(g, _field, _links_field, _other, current, round, limit)
       when round > limit or map_size(current.map) == 0,
       do: g

  defp walk(g, field, links_field, other, current, round, limit) do
    {nodes, next} =
      Enum.reduce(current, {g.nodes, MapSet.new()}, fn id, {nodes, next} ->
        node = Map.put(nodes[id], field, round)
        reached = Enum.map(node[links_field], &other.(g.links[&1]))
        {Map.put(nodes, id, node), Enum.into(reached, next)}
      end)

    walk(%{g | nodes: nodes}, field, links_field, other, next, round + 1, limit)
  end

  # d3's computeNodeLayers: the alignment function picks a column in 0..L for every node.
  defp compute_columns(%{sankey: sankey} = g) do
    x = (g.nodes |> Map.values() |> Enum.map(& &1.depth) |> Enum.max(fn -> 0 end)) + 1
    kx = if x > 1, do: (sankey.width - sankey.node_width) / (x - 1), else: 0

    nodes =
      Map.new(g.nodes, fn {id, node} ->
        column = node |> align(sankey.node_align, x, g) |> floor() |> max(0) |> min(x - 1)
        x0 = column * kx
        {id, %{node | layer: column, x0: x0, x1: x0 + sankey.node_width}}
      end)

    columns =
      g.ids
      |> Enum.map(&nodes[&1])
      |> Enum.group_by(& &1.layer, & &1.id)
      |> Enum.sort()
      |> Enum.map(fn {_, ids} -> ids end)

    max_len = columns |> Enum.map(&length/1) |> Enum.max(fn -> 1 end)

    py =
      if max_len > 1,
        do: min(sankey.node_padding, sankey.height / (max_len - 1)),
        else: sankey.node_padding

    %{g | nodes: nodes, columns: columns, py: py}
  end

  defp align(node, :left, _x, _g), do: node.depth
  defp align(node, :right, x, _g), do: x - 1 - node.height
  defp align(%{source_links: []}, :justify, x, _g), do: x - 1
  defp align(node, :justify, _x, _g), do: node.depth
  defp align(%{target_links: [_ | _]} = node, :center, _x, _g), do: node.depth
  defp align(%{source_links: []}, :center, _x, _g), do: 0

  defp align(node, :center, _x, g) do
    (node.source_links |> Enum.map(&g.nodes[g.links[&1].target].depth) |> Enum.min()) - 1
  end

  # d3's initializeNodeBreadths: one scale `ky` for every column, so a link's width is the
  # share of its node it occupies; each column is then centered vertically.
  defp initialize_breadths(%{sankey: sankey, py: py} = g) do
    ky =
      g.columns
      |> Enum.map(fn ids ->
        total = Enum.reduce(ids, 0, &(g.nodes[&1].value + &2))
        if total > 0, do: (sankey.height - (length(ids) - 1) * py) / total, else: nil
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.min(fn -> 0 end)

    g =
      Enum.reduce(g.columns, g, fn ids, g ->
        {g, y} =
          Enum.reduce(ids, {g, 0}, fn id, {g, y} ->
            node = g.nodes[id]
            y1 = y + node.value * ky

            links =
              Enum.reduce(node.source_links, g.links, fn li, links ->
                put_in(links, [li, :width], links[li].value * ky)
              end)

            {%{g | nodes: Map.put(g.nodes, id, %{node | y0: y, y1: y1}), links: links}, y1 + py}
          end)

        gap = (sankey.height - y + py) / (length(ids) + 1)

        ids
        |> Enum.with_index(1)
        |> Enum.reduce(g, fn {id, i}, g -> shift_node(g, id, gap * i) end)
        |> reorder_links(ids)
      end)

    g
  end

  defp shift_node(g, id, dy) do
    update_in(g, [:nodes, id], &%{&1 | y0: &1.y0 + dy, y1: &1.y1 + dy})
  end

  # Without a link_sort, links leave and enter a node in the vertical order of the node at
  # their other end (ties by input index).
  defp reorder_links(%{sankey: %{link_sort: nil}} = g, ids) do
    Enum.reduce(ids, g, fn id, g ->
      update_in(g, [:nodes, id], fn node ->
        %{
          node
          | source_links: Enum.sort_by(node.source_links, &{g.nodes[g.links[&1].target].y0, &1}),
            target_links: Enum.sort_by(node.target_links, &{g.nodes[g.links[&1].source].y0, &1})
        }
      end)
    end)
  end

  defp reorder_links(g, _ids), do: g

  # d3's reorderNodeLinks: after a node moves, the links of its neighbors are re-sorted.
  defp reorder_node_links(%{sankey: %{link_sort: nil}} = g, id) do
    node = g.nodes[id]
    sources = Enum.map(node.target_links, &g.links[&1].source)
    targets = Enum.map(node.source_links, &g.links[&1].target)
    reorder_links(g, Enum.uniq(sources ++ targets))
  end

  defp reorder_node_links(g, _id), do: g

  defp relax(%{sankey: %{iterations: iterations}} = g) do
    Enum.reduce(0..(iterations - 1)//1, g, fn i, g ->
      alpha = :math.pow(0.99, i)
      beta = max(1 - alpha, (i + 1) / iterations)

      g
      |> relax_right_to_left(alpha, beta)
      |> relax_left_to_right(alpha, beta)
    end)
  end

  defp relax_left_to_right(g, alpha, beta) do
    g.columns
    |> Enum.drop(1)
    |> Enum.reduce(g, fn ids, g ->
      ids
      |> Enum.reduce(g, fn id, g -> pull(g, id, :target_links, &target_top/3, alpha) end)
      |> resolve_collisions(ids, beta)
    end)
  end

  defp relax_right_to_left(g, alpha, beta) do
    g.columns
    |> Enum.reverse()
    |> Enum.drop(1)
    |> Enum.reduce(g, fn ids, g ->
      ids
      |> Enum.reduce(g, fn id, g -> pull(g, id, :source_links, &source_top/3, alpha) end)
      |> resolve_collisions(ids, beta)
    end)
  end

  # Moves a node towards the value-weighted mean of the y0 each of its links would want.
  defp pull(g, id, links_field, ideal, alpha) do
    node = g.nodes[id]

    {y, w} =
      Enum.reduce(node[links_field], {0, 0}, fn li, {y, w} ->
        link = g.links[li]
        {source, target} = {g.nodes[link.source], g.nodes[link.target]}
        v = link.value * (target.layer - source.layer)
        {y + ideal.(g, source, target) * v, w + v}
      end)

    if w > 0 do
      g |> shift_node(id, (y / w - node.y0) * alpha) |> reorder_node_links(id)
    else
      g
    end
  end

  # The target.y0 that would make the link from source to target straight (d3 targetTop).
  defp target_top(g, source, target) do
    y = source.y0 - (length(source.source_links) - 1) * g.py / 2

    y =
      source.source_links
      |> Enum.take_while(&(g.links[&1].target != target.id))
      |> Enum.reduce(y, &(&2 + g.links[&1].width + g.py))

    target.target_links
    |> Enum.take_while(&(g.links[&1].source != source.id))
    |> Enum.reduce(y, &(&2 - g.links[&1].width))
  end

  defp source_top(g, source, target) do
    y = target.y0 - (length(target.target_links) - 1) * g.py / 2

    y =
      target.target_links
      |> Enum.take_while(&(g.links[&1].source != source.id))
      |> Enum.reduce(y, &(&2 + g.links[&1].width + g.py))

    source.source_links
    |> Enum.take_while(&(g.links[&1].target != target.id))
    |> Enum.reduce(y, &(&2 - g.links[&1].width))
  end

  # d3's resolveCollisions: sort the column by y0, push apart from the middle node
  # outwards, then back in from the bottom and the top edges of the diagram.
  defp resolve_collisions(%{sankey: sankey, py: py} = g, ids, alpha) do
    sorted = Enum.sort_by(ids, &{g.nodes[&1].y0, g.nodes[&1].index})
    n = length(sorted)
    i = div(n, 2)
    subject = g.nodes[Enum.at(sorted, i)]

    g
    |> push_up(Enum.take(sorted, i), subject.y0 - py, alpha)
    |> push_down(Enum.drop(sorted, i + 1), subject.y1 + py, alpha)
    |> push_up(sorted, sankey.height, alpha)
    |> push_down(sorted, 0, alpha)
    |> Map.update!(:columns, fn columns ->
      Enum.map(columns, fn column -> if column == ids, do: sorted, else: column end)
    end)
  end

  defp push_down(g, ids, y, alpha) do
    {g, _} =
      Enum.reduce(ids, {g, y}, fn id, {g, y} ->
        dy = (y - g.nodes[id].y0) * alpha
        g = if dy > 1.0e-6, do: shift_node(g, id, dy), else: g
        {g, g.nodes[id].y1 + g.py}
      end)

    g
  end

  defp push_up(g, ids, y, alpha) do
    {g, _} =
      ids
      |> Enum.reverse()
      |> Enum.reduce({g, y}, fn id, {g, y} ->
        dy = (g.nodes[id].y1 - y) * alpha
        g = if dy > 1.0e-6, do: shift_node(g, id, -dy), else: g
        {g, g.nodes[id].y0 - g.py}
      end)

    g
  end

  # Link tops: the running offset from the top of the source node (y0) and of the target
  # node (y1), in the settled link order.
  defp compute_link_breadths(g) do
    links =
      Enum.reduce(g.nodes, g.links, fn {_id, node}, links ->
        {links, _} =
          Enum.reduce(node.source_links, {links, node.y0}, fn li, {links, y} ->
            {put_in(links, [li, :y0], y), y + links[li].width}
          end)

        {links, _} =
          Enum.reduce(node.target_links, {links, node.y0}, fn li, {links, y} ->
            {put_in(links, [li, :y1], y), y + links[li].width}
          end)

        links
      end)

    %{g | links: links}
  end

  defp output_nodes(g, nodes) do
    Enum.map(nodes, fn n ->
      node = g.nodes[n.id]

      Map.merge(n, %{
        index: node.index,
        value: node.value,
        depth: node.depth,
        height: node.height,
        layer: node.layer,
        source_links: Enum.map(node.source_links, &g.links[&1].raw),
        target_links: Enum.map(node.target_links, &g.links[&1].raw),
        x0: node.x0,
        x1: node.x1,
        y0: node.y0,
        y1: node.y1
      })
    end)
  end

  defp output_links(g, links) do
    nodes =
      Map.new(g.nodes, fn {id, node} ->
        {id, Map.take(node, [:id, :x0, :x1, :y0, :y1, :index, :layer, :value])}
      end)

    links
    |> Enum.with_index()
    |> Enum.map(fn {l, i} ->
      case g.links[i] do
        nil ->
          Map.merge(l, %{
            source_index: nil,
            target_index: nil,
            source_node: nil,
            target_node: nil,
            y0: 0,
            y1: 0,
            width: 0,
            path: nil
          })

        link ->
          source = nodes[link.source]
          target = nodes[link.target]

          out =
            Map.merge(l, %{
              source_index: source.index,
              target_index: target.index,
              source_node: source,
              target_node: target,
              y0: link.y0,
              y1: link.y1,
              width: link.width
            })

          Map.put(out, :path, generate_link_path(out))
      end
    end)
  end
end
