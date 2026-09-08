if Code.ensure_loaded?(Phoenix.Component) do
  defmodule Visualize.Components.Tree do
    @moduledoc """
    Phoenix LiveView function components for hierarchies (spec/10 §3): a node-link tree,
    a treemap and a sunburst.

    Each is a preset design of `Visualize.Chart.Presets` plus an assign mapping (spec/14
    §15.4, D-64, D-70): the nested `data` — a map whose children are under `:children` or
    `"children"` — is flattened to one row per node, the design's transforms (`:tree`,
    `:treemap` or `:partition`, then the `:filter` steps that keep what spec/10 §3 draws)
    lay the rows out, the marks draw them through `Visualize.Chart.Frame.generate/2`, and
    the component prints the elements in the markup spec/10 §3 declares, reading the rows
    beside them for what follows the node — the tree's circle-and-text group, the treemap's
    and the sunburst's label rules. Node labels default to the `:name` or `"name"` of a
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
    - The defaults below are `Visualize.Chart.Presets.defaults/1`.
    """

    use Phoenix.Component

    alias Visualize.Chart.Presets
    alias Visualize.Components.Support
    alias Visualize.IR.Path

    @tree Presets.defaults(:tree_diagram)
    @treemap Presets.defaults(:treemap_chart)
    @sunburst Presets.defaults(:sunburst_chart)

    @doc """
    Renders a node-link tree laid out by the `:tree` transform (`Visualize.Layout.Tree`).

    ## Assigns

    * `data` - the nested map (required)
    * `width`, `height` - pixels (default 800 by 600)
    * `margin` - merged over `%{top: 20, right: 120, bottom: 20, left: 120}`, which
      leaves room for the labels of the root and of the leaves
    * `orientation` - `:horizontal` (root at the left, depth along x) or `:vertical`
      (root at the top) (default `:horizontal`)
    * `node_radius` - (default 6)
    * `node_fill` - fill of leaf circles (default `nil`: the theme's `:background`)
    * `node_stroke` - circle stroke, and the fill of internal nodes (default `nil`: the
      theme's `:series_1`)
    * `link_stroke` - (default `nil`: the theme's `:grid`)
    * `label` - accessor of a node's data; `nil` reads `:name` or `"name"`
    * `animate`, `class`, `responsive`, `theme`, `title`, `description` - per the module
      conventions

    Links are cubic Béziers between parent and child with both control points at the
    midpoint of the depth axis. Horizontal labels sit at `x = −10`, anchored `end`, for
    internal nodes and at `x = 10`, anchored `start`, for leaves; vertical labels are
    centred at `x = 0`.
    """
    attr(:data, :map, required: true)
    attr(:width, :integer, default: @tree.width)
    attr(:height, :integer, default: @tree.height)
    attr(:margin, :map, default: @tree.margin)
    attr(:orientation, :atom, default: @tree.orientation)
    attr(:node_radius, :integer, default: @tree.node_radius)
    attr(:node_fill, :string, default: @tree.node_fill)
    attr(:node_stroke, :string, default: @tree.node_stroke)
    attr(:link_stroke, :string, default: @tree.link_stroke)
    attr(:label, :any, default: @tree.label)
    attr(:animate, :boolean, default: @tree.animate)
    attr(:class, :string, default: @tree.class)
    attr(:responsive, :boolean, default: @tree.responsive)
    attr(:theme, :any, default: @tree.theme)
    attr(:title, :string, default: @tree.title)
    attr(:description, :string, default: @tree.description)

    def tree_diagram(assigns) do
      drawn = Support.draw(:tree_diagram, assigns)
      [links, nodes] = Support.marks(drawn.group)
      [_link_rows, node_rows] = drawn.rows
      orientation = assigns.orientation
      circles = Enum.filter(nodes.children, &(&1.type == :circle))

      # One group per circle at the circle's centre; the text's anchor and offset follow
      # the node (spec/10 §3.2), which is why the group is the component's (spec/14 §15.4).
      groups =
        Enum.zip_with(circles, node_rows, fn circle, n ->
          internal? = n.height > 0

          %{
            transform: "translate(#{fmt(circle.attrs.cx)}, #{fmt(circle.attrs.cy)})",
            fill: if(internal?, do: nodes.style.stroke, else: nodes.style.fill),
            label_x: label_x(orientation, internal?),
            anchor: label_anchor(orientation, internal?),
            label: n.label
          }
        end)

      assigns =
        assign(assigns,
          margin: drawn.margin,
          links: Enum.map(links.children, &link_d/1),
          nodes: groups,
          theme: drawn.theme,
          ids: drawn.ids,
          node_stroke: nodes.style.stroke,
          link_stroke: links.style.stroke,
          text: Support.css(drawn.theme, :text),
          label_size: Support.css(drawn.theme, :label_size),
          transition: Support.transition(assigns.animate)
        )

      ~H"""
      <svg width={@width} height={@height} {Support.svg_attrs(@class, @responsive, @theme, @ids)} viewBox={"0 0 #{@width} #{@height}"}>
        <title :if={@ids.title} id={@ids.title}>{@title}</title>
        <desc :if={@ids.desc} id={@ids.desc}>{@description}</desc>
        <g transform={"translate(#{@margin.left}, #{@margin.top})"}>
          <path :for={d <- @links} d={d} fill="none" stroke={@link_stroke} stroke-width="1.5" {@transition} />
          <g :for={node <- @nodes} transform={node.transform} {@transition}>
            <circle r={@node_radius} fill={node.fill} stroke={@node_stroke} stroke-width="2" />
            <text dy="0.31em" x={node.label_x} text-anchor={node.anchor} font-size={@label_size} fill={@text}>{node.label}</text>
          </g>
        </g>
      </svg>
      """
    end

    @doc """
    Renders a treemap of the hierarchy's leaves laid out by the `:treemap` transform
    (`Visualize.Layout.Treemap`).

    ## Assigns

    * `data` - the nested map with leaf values (required)
    * `width`, `height` - pixels (default 800 by 600); the layout fills the whole `<svg>`
    * `value` - leaf value accessor; `nil` reads `:value` or `"value"`, missing is 0
    * `label` - as `tree_diagram/1`
    * `tile` - a `Visualize.Layout.Treemap.tile/2` algorithm (default `:squarify`)
    * `padding` - uniform cell padding (default 2)
    * `colors` - per the module conventions; each child of the root takes the next colour
      and every leaf beneath it that colour (default `:category10`)
    * `animate`, `class`, `responsive`, `theme`, `title`, `description` - per the module
      conventions

    A `:background`-filled `:label_size` label with a text shadow is drawn at `(x0 + 4, y0 + 14)` in a
    cell wider than 30 and taller than 15, truncated with `…` to fit `cell width − 8`
    at seven pixels a character.
    """
    attr(:data, :map, required: true)
    attr(:width, :integer, default: @treemap.width)
    attr(:height, :integer, default: @treemap.height)
    attr(:value, :any, default: @treemap.value)
    attr(:label, :any, default: @treemap.label)
    attr(:tile, :atom, default: @treemap.tile)
    attr(:padding, :integer, default: @treemap.padding)
    attr(:colors, :any, default: @treemap.colors)
    attr(:animate, :boolean, default: @treemap.animate)
    attr(:class, :string, default: @treemap.class)
    attr(:responsive, :boolean, default: @treemap.responsive)
    attr(:theme, :any, default: @treemap.theme)
    attr(:title, :string, default: @treemap.title)
    attr(:description, :string, default: @treemap.description)

    def treemap_chart(assigns) do
      drawn = Support.draw(:treemap_chart, assigns)
      [cells] = Support.marks(drawn.group)
      [leaves] = drawn.rows
      root_fill = Support.css(drawn.theme, :grid)

      # One cell per `:rect` element — the design filters to the leaves — with the
      # component's label rule over the row (spec/10 §3.3). A root-only hierarchy's cell
      # has no `branch`, so no bound fill, and takes the theme's `:grid`.
      cells =
        Enum.zip_with(cells.children, leaves, fn rect, leaf ->
          %{x: x, y: y, width: width, height: height} = rect.attrs

          %{
            x: fmt(x),
            y: fmt(y),
            width: fmt(width),
            height: fmt(height),
            fill: Map.get(rect.style, :fill, root_fill),
            stroke: cells.style.stroke,
            stroke_width: cells.style.stroke_width,
            label: if(width > 30 and height > 15, do: Support.truncate(leaf.label, width - 8)),
            label_x: fmt(x + 4),
            label_y: fmt(y + 14)
          }
        end)

      assigns =
        assign(assigns,
          cells: cells,
          theme: drawn.theme,
          ids: drawn.ids,
          background: Support.css(drawn.theme, :background),
          label_size: Support.css(drawn.theme, :label_size),
          transition: Support.transition(assigns.animate)
        )

      ~H"""
      <svg width={@width} height={@height} {Support.svg_attrs(@class, @responsive, @theme, @ids)} viewBox={"0 0 #{@width} #{@height}"}>
        <title :if={@ids.title} id={@ids.title}>{@title}</title>
        <desc :if={@ids.desc} id={@ids.desc}>{@description}</desc>
        <%= for cell <- @cells do %>
          <rect x={cell.x} y={cell.y} width={cell.width} height={cell.height} fill={cell.fill} stroke={cell.stroke} stroke-width={cell.stroke_width} {@transition} />
          <text
            :if={cell.label}
            x={cell.label_x}
            y={cell.label_y}
            font-size={@label_size}
            fill={@background}
            style="text-shadow: 0 1px 2px rgba(0,0,0,0.5);"
          >{cell.label}</text>
        <% end %>
      </svg>
      """
    end

    @doc """
    Renders a sunburst: the radial partition of the `:partition` transform
    (`Visualize.Layout.Partition`) with one arc per node below the root.

    ## Assigns

    * `data` - the nested map with leaf values (required)
    * `width`, `height` - pixels (default 600 by 600); the radius is half the smaller
    * `value` - as `treemap_chart/1`
    * `label` - as `tree_diagram/1`; drawn at the centroid of an arc thick enough and long
      enough to hold text
    * `colors` - as `treemap_chart/1`
    * `animate`, `class`, `responsive`, `theme`, `title`, `description` - per the module
      conventions

    Angles are `Visualize.Layout.Partition` over `{2π, radius}`: the root spans the full
    turn, each child a share of its parent's arc proportional to its summed value, and a
    node of value 0 a zero-width slot that draws nothing. Ring radii are
    `depth / (height + 1) · radius`. Each arc is `Visualize.Shape.Arc` — angles clockwise
    from 12 o'clock — as a `<path fill={colour} stroke={:background} stroke-width="1">`.
    """
    attr(:data, :map, required: true)
    attr(:width, :integer, default: @sunburst.width)
    attr(:height, :integer, default: @sunburst.height)
    attr(:value, :any, default: @sunburst.value)
    attr(:label, :any, default: @sunburst.label)
    attr(:colors, :any, default: @sunburst.colors)
    attr(:animate, :boolean, default: @sunburst.animate)
    attr(:class, :string, default: @sunburst.class)
    attr(:responsive, :boolean, default: @sunburst.responsive)
    attr(:theme, :any, default: @sunburst.theme)
    attr(:title, :string, default: @sunburst.title)
    attr(:description, :string, default: @sunburst.description)

    def sunburst_chart(assigns) do
      drawn = Support.draw(:sunburst_chart, assigns)
      [mark] = Support.marks(drawn.group)
      [nodes] = drawn.rows
      {paths, texts} = Enum.split_with(mark.children, &(&1.type == :path))

      # One arc per `:arc` element — the design filters to the nodes below the root with a
      # positive extent — and its label at the mark's own text, the centroid, kept when
      # the row's ring is thick and long enough (spec/10 §3.4).
      arcs =
        Enum.zip_with([paths, texts, nodes], fn [path, text, node] ->
          thickness = node.y1 - node.y0
          length = (node.x1 - node.x0) * (node.y0 + node.y1) / 2

          %{
            d: Support.d(path),
            fill: path.style.fill,
            stroke: mark.style.stroke,
            stroke_width: mark.style.stroke_width,
            label:
              if(thickness > 15 and length > 30, do: Support.truncate(text.content, length - 8)),
            cx: fmt(text.attrs.x),
            cy: fmt(text.attrs.y)
          }
        end)

      assigns =
        assign(assigns,
          arcs: arcs,
          centre: {fmt(drawn.plot.width / 2), fmt(drawn.plot.height / 2)},
          theme: drawn.theme,
          ids: drawn.ids,
          background: Support.css(drawn.theme, :background),
          label_size: Support.css(drawn.theme, :label_size),
          transition: Support.transition(assigns.animate)
        )

      ~H"""
      <svg width={@width} height={@height} {Support.svg_attrs(@class, @responsive, @theme, @ids)} viewBox={"0 0 #{@width} #{@height}"}>
        <title :if={@ids.title} id={@ids.title}>{@title}</title>
        <desc :if={@ids.desc} id={@ids.desc}>{@description}</desc>
        <g transform={"translate(#{elem(@centre, 0)}, #{elem(@centre, 1)})"}>
          <%= for a <- @arcs do %>
            <path d={a.d} fill={a.fill} stroke={a.stroke} stroke-width={a.stroke_width} {@transition} />
            <text
              :if={a.label}
              x={a.cx}
              y={a.cy}
              text-anchor="middle"
              dominant-baseline="middle"
              font-size={@label_size}
              fill={@background}
            >{a.label}</text>
          <% end %>
        </g>
      </svg>
      """
    end

    # The link `d` in the form spec/10 §3.2's goldens hold — the three points of the cubic
    # space-separated — from the layer's path; `Visualize.IR.Path.to_string/1` would
    # comma-separate them.
    defp link_d(%{path: %Path{commands: [{:M, x0, y0}, {:C, cx0, cy0, cx1, cy1, x1, y1}]}}) do
      "M#{fmt(x0)},#{fmt(y0)}C#{fmt(cx0)},#{fmt(cy0)} #{fmt(cx1)},#{fmt(cy1)} " <>
        "#{fmt(x1)},#{fmt(y1)}"
    end

    # Horizontal labels sit beside the node, internal ones to its left (spec/10 §3.2).
    defp label_x(:horizontal, true), do: -10
    defp label_x(:horizontal, false), do: 10
    defp label_x(:vertical, _internal?), do: 0

    defp label_anchor(:horizontal, true), do: "end"
    defp label_anchor(:horizontal, false), do: "start"
    defp label_anchor(:vertical, _internal?), do: "middle"

    defp fmt(number), do: Support.fmt(number)
  end
end
