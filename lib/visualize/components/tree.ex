if Code.ensure_loaded?(Phoenix.Component) do
  defmodule Visualize.Components.Tree do
    @moduledoc """
    Phoenix LiveView function components for hierarchies (spec/10 §3): a node-link tree,
    a treemap and a sunburst.

    Each takes nested `data` — a map whose children are under `:children` or `"children"`,
    as `Visualize.Layout.Hierarchy.new/1` reads it — and lays it out with the matching
    layout of `Visualize.Layout`. Node labels default to the `:name` or `"name"` of a
    node's data; leaf values to its `:value` or `"value"`.

    ## Usage

        use Phoenix.Component
        import Visualize.Components.Tree

        <.tree_diagram data={@hierarchy} width={800} height={600} />

    ## Conventions

    - A root-only hierarchy is the empty case: the tree draws its one node, the treemap
      one cell, the sunburst nothing but the `<svg>` (the root is never an arc).
    - `colors` is a scheme atom of `Visualize.Scale.Color.schemes/0` or an explicit colour
      list, taken by index and cycled, as in `Visualize.Components`; an unknown scheme or an
      empty list raises `ArgumentError`.
    - `animate={true}` puts `style="transition: all 0.3s ease-in-out;"` on every mark;
      `class` lands on the `<svg>`; coordinates print with at most four decimals.
    """

    use Phoenix.Component

    alias Visualize.Components.Support
    alias Visualize.Layout.{Hierarchy, Partition, Tree, Treemap}
    alias Visualize.{Scale, Shape}

    @tree_margin %{top: 20, right: 120, bottom: 20, left: 120}

    @doc """
    Renders a node-link tree laid out by `Visualize.Layout.Tree`.

    ## Assigns

    * `data` - the nested map (required)
    * `width`, `height` - pixels (default 800 by 600)
    * `margin` - merged over `%{top: 20, right: 120, bottom: 20, left: 120}`, which
      leaves room for the labels of the root and of the leaves
    * `orientation` - `:horizontal` (root at the left, depth along x) or `:vertical`
      (root at the top) (default `:horizontal`)
    * `node_radius` - (default 6)
    * `node_fill` - fill of leaf circles (default `"#fff"`)
    * `node_stroke` - circle stroke, and the fill of internal nodes (default `"steelblue"`)
    * `link_stroke` - (default `"#ccc"`)
    * `label` - accessor of a node's data; `nil` reads `:name` or `"name"`
    * `animate`, `class` - per the module conventions

    Links are cubic Béziers between parent and child with both control points at the
    midpoint of the depth axis. Horizontal labels sit at `x = −10`, anchored `end`, for
    internal nodes and at `x = 10`, anchored `start`, for leaves; vertical labels are
    centred at `x = 0`.
    """
    attr(:data, :map, required: true)
    attr(:width, :integer, default: 800)
    attr(:height, :integer, default: 600)
    attr(:margin, :map, default: @tree_margin)
    attr(:orientation, :atom, default: :horizontal)
    attr(:node_radius, :integer, default: 6)
    attr(:node_fill, :string, default: "#fff")
    attr(:node_stroke, :string, default: "steelblue")
    attr(:link_stroke, :string, default: "#ccc")
    attr(:label, :any, default: nil)
    attr(:animate, :boolean, default: false)
    attr(:class, :string, default: nil)

    def tree_diagram(assigns) do
      {margin, inner_width, inner_height} = Support.frame(assigns, @tree_margin)
      orientation = assigns.orientation

      size =
        case orientation do
          :horizontal -> [inner_height, inner_width]
          :vertical -> [inner_width, inner_height]
        end

      root = Tree.new() |> Tree.size(size) |> Tree.generate(Hierarchy.new(assigns.data))
      label = assigns.label || (&name/1)

      links =
        for {source, target} <- Hierarchy.links(root) do
          link_path(point(source, orientation), point(target, orientation), orientation)
        end

      nodes =
        for node <- Hierarchy.descendants(root) do
          {x, y} = point(node, orientation)
          internal? = internal?(node)

          %{
            transform: "translate(#{fmt(x)}, #{fmt(y)})",
            fill: if(internal?, do: assigns.node_stroke, else: assigns.node_fill),
            label_x: label_x(orientation, internal?),
            anchor: label_anchor(orientation, internal?),
            label: label.(node.data)
          }
        end

      assigns =
        assign(assigns,
          margin: margin,
          links: links,
          nodes: nodes,
          transition: Support.transition(assigns.animate)
        )

      ~H"""
      <svg width={@width} height={@height} {Support.class(@class)} viewBox={"0 0 #{@width} #{@height}"}>
        <g transform={"translate(#{@margin.left}, #{@margin.top})"}>
          <path :for={d <- @links} d={d} fill="none" stroke={@link_stroke} stroke-width="1.5" {@transition} />
          <g :for={node <- @nodes} transform={node.transform} {@transition}>
            <circle r={@node_radius} fill={node.fill} stroke={@node_stroke} stroke-width="2" />
            <text dy="0.31em" x={node.label_x} text-anchor={node.anchor} font-size="12">{node.label}</text>
          </g>
        </g>
      </svg>
      """
    end

    @doc """
    Renders a treemap of the hierarchy's leaves laid out by `Visualize.Layout.Treemap`.

    ## Assigns

    * `data` - the nested map with leaf values (required)
    * `width`, `height` - pixels (default 800 by 600); the layout fills the whole `<svg>`
    * `value` - leaf value accessor; `nil` reads `:value` or `"value"`, missing is 0
    * `label` - as `tree_diagram/1`
    * `tile` - a `Visualize.Layout.Treemap.tile/2` algorithm (default `:squarify`)
    * `padding` - uniform cell padding (default 2)
    * `colors` - per the module conventions; each child of the root takes the next colour
      and every leaf beneath it that colour (default `:category10`)
    * `animate`, `class` - per the module conventions

    A white `font-size="11"` label with a text shadow is drawn at `(x0 + 4, y0 + 14)` in a
    cell wider than 30 and taller than 15, truncated with `…` to fit `cell width − 8`
    at seven pixels a character.
    """
    attr(:data, :map, required: true)
    attr(:width, :integer, default: 800)
    attr(:height, :integer, default: 600)
    attr(:value, :any, default: nil)
    attr(:label, :any, default: nil)
    attr(:tile, :atom, default: :squarify)
    attr(:padding, :integer, default: 2)
    attr(:colors, :any, default: :category10)
    attr(:animate, :boolean, default: false)
    attr(:class, :string, default: nil)

    def treemap_chart(assigns) do
      label = assigns.label || (&name/1)

      root =
        Treemap.new()
        |> Treemap.size({assigns.width, assigns.height})
        |> Treemap.tile(assigns.tile)
        |> Treemap.padding(assigns.padding)
        |> Treemap.generate(summed(assigns.data, assigns.value))

      cells =
        for {node, colour} <- coloured(root, assigns.colors), leaf?(node) do
          width = max(0, node.x1 - node.x0)
          height = max(0, node.y1 - node.y0)

          %{
            x: fmt(node.x0),
            y: fmt(node.y0),
            width: fmt(width),
            height: fmt(height),
            fill: colour,
            label:
              if(width > 30 and height > 15,
                do: Support.truncate(label.(node.data), width - 8)
              ),
            label_x: fmt(node.x0 + 4),
            label_y: fmt(node.y0 + 14)
          }
        end

      assigns = assign(assigns, cells: cells, transition: Support.transition(assigns.animate))

      ~H"""
      <svg width={@width} height={@height} {Support.class(@class)} viewBox={"0 0 #{@width} #{@height}"}>
        <%= for cell <- @cells do %>
          <rect x={cell.x} y={cell.y} width={cell.width} height={cell.height} fill={cell.fill} stroke="white" stroke-width="1" {@transition} />
          <text
            :if={cell.label}
            x={cell.label_x}
            y={cell.label_y}
            font-size="11"
            fill="white"
            style="text-shadow: 0 1px 2px rgba(0,0,0,0.5);"
          >{cell.label}</text>
        <% end %>
      </svg>
      """
    end

    @doc """
    Renders a sunburst: the radial partition of `Visualize.Layout.Partition` with one arc
    per node below the root.

    ## Assigns

    * `data` - the nested map with leaf values (required)
    * `width`, `height` - pixels (default 600 by 600); the radius is half the smaller
    * `value` - as `treemap_chart/1`
    * `label` - as `tree_diagram/1`; drawn at the centroid of an arc thick enough and long
      enough to hold text
    * `colors` - as `treemap_chart/1`
    * `animate`, `class` - per the module conventions

    Angles are `Visualize.Layout.Partition` over `{2π, radius}`: the root spans the full
    turn, each child a share of its parent's arc proportional to its summed value, and a
    node of value 0 a zero-width slot that draws nothing. Ring radii are
    `depth / (height + 1) · radius`. Each arc is `Visualize.Shape.Arc` — angles clockwise
    from 12 o'clock — as a `<path fill={colour} stroke="white" stroke-width="1">`.
    """
    attr(:data, :map, required: true)
    attr(:width, :integer, default: 600)
    attr(:height, :integer, default: 600)
    attr(:value, :any, default: nil)
    attr(:label, :any, default: nil)
    attr(:colors, :any, default: :category10)
    attr(:animate, :boolean, default: false)
    attr(:class, :string, default: nil)

    def sunburst_chart(assigns) do
      label = assigns.label || (&name/1)
      radius = min(assigns.width, assigns.height) / 2

      root =
        Partition.new()
        |> Partition.size({2 * :math.pi(), radius})
        |> Partition.generate(summed(assigns.data, assigns.value))

      arc =
        Shape.arc()
        |> Shape.inner_radius(& &1.y0)
        |> Shape.outer_radius(& &1.y1)
        |> Shape.start_angle(& &1.x0)
        |> Shape.end_angle(& &1.x1)

      arcs =
        for {node, colour} <- coloured(root, assigns.colors),
            node.depth > 0,
            node.x1 - node.x0 > 0 do
          {cx, cy} = Shape.Arc.centroid(arc, node)
          thickness = node.y1 - node.y0
          length = (node.x1 - node.x0) * (node.y0 + node.y1) / 2

          %{
            d: Shape.generate(arc, node),
            fill: colour,
            label:
              if(thickness > 15 and length > 30,
                do: Support.truncate(label.(node.data), length - 8)
              ),
            cx: fmt(cx),
            cy: fmt(cy)
          }
        end

      assigns = assign(assigns, arcs: arcs, transition: Support.transition(assigns.animate))

      ~H"""
      <svg width={@width} height={@height} {Support.class(@class)} viewBox={"0 0 #{@width} #{@height}"}>
        <g transform={"translate(#{fmt(@width / 2)}, #{fmt(@height / 2)})"}>
          <%= for a <- @arcs do %>
            <path d={a.d} fill={a.fill} stroke="white" stroke-width="1" {@transition} />
            <text
              :if={a.label}
              x={a.cx}
              y={a.cy}
              text-anchor="middle"
              dominant-baseline="middle"
              font-size="11"
            >{a.label}</text>
          <% end %>
        </g>
      </svg>
      """
    end

    # The hierarchy with every node's value summed from the leaves.
    defp summed(data, value) do
      value = value || (&leaf_value/1)
      data |> Hierarchy.new() |> Hierarchy.sum(value)
    end

    defp name(data), do: data[:name] || data["name"]
    defp leaf_value(data), do: data[:value] || data["value"] || 0

    defp leaf?(%Hierarchy{children: children}), do: children in [nil, []]
    defp internal?(node), do: not leaf?(node)

    # Every node paired with its colour: the i-th child of the root takes the i-th colour
    # of the palette and hands it down; the root itself takes `"#ddd"`.
    defp coloured(root, colors) do
      children = root.children || []
      palette = Support.palette(colors, length(children))

      [{root, "#ddd"}] ++
        Enum.flat_map(Enum.with_index(children), fn {child, i} ->
          walk(child, Scale.apply(palette, i))
        end)
    end

    defp walk(node, colour) do
      [{node, colour} | Enum.flat_map(node.children || [], &walk(&1, colour))]
    end

    # The layout's `x` runs along the breadth of the tree and `y` along its depth;
    # horizontal puts depth on the page's x axis.
    defp point(node, :horizontal), do: {node.y, node.x}
    defp point(node, :vertical), do: {node.x, node.y}

    defp link_path({sx, sy}, {tx, ty}, :horizontal) do
      mid = fmt((sx + tx) / 2)
      "M#{fmt(sx)},#{fmt(sy)}C#{mid},#{fmt(sy)} #{mid},#{fmt(ty)} #{fmt(tx)},#{fmt(ty)}"
    end

    defp link_path({sx, sy}, {tx, ty}, :vertical) do
      mid = fmt((sy + ty) / 2)
      "M#{fmt(sx)},#{fmt(sy)}C#{fmt(sx)},#{mid} #{fmt(tx)},#{mid} #{fmt(tx)},#{fmt(ty)}"
    end

    defp label_x(:horizontal, true), do: -10
    defp label_x(:horizontal, false), do: 10
    defp label_x(:vertical, _internal?), do: 0

    defp label_anchor(:horizontal, true), do: "end"
    defp label_anchor(:horizontal, false), do: "start"
    defp label_anchor(:vertical, _internal?), do: "middle"

    defp fmt(number), do: Support.fmt(number)
  end
end
