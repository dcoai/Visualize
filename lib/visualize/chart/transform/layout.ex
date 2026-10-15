defmodule Visualize.Chart.Transform.Layout do
  @moduledoc false
  # The layout steps of a mark's pipeline (spec/14 §5.4.2-5.4.3): the hierarchies over
  # `Visualize.Layout.Hierarchy.stratify/2`, and the graphs — chord, sankey, force — over
  # rows read as flows; the force step is `Visualize.Chart.Transform.Force`'s (D-132). Every position is in the pixels of `size`, and a row that has a
  # shape carries it as a `Visualize.IR.Path` under `path` (D-62).

  alias Visualize.Chart.Transform.Force
  alias Visualize.Data.Table
  alias Visualize.IR.{Path, Transform}
  alias Visualize.Layout.{Chord, Cluster, Hierarchy, Pack, Partition, Sankey, Tree}
  alias Visualize.Layout.Treemap
  alias Visualize.Shape.Arc

  @hierarchies [:tree, :cluster, :pack, :partition, :treemap]
  @ring 0.9

  @doc false
  @spec run(atom(), map(), [map()], map()) :: [map()]
  def run(op, node, rows, ctx) when op in @hierarchies, do: hierarchy(op, node, rows, ctx)
  def run(:chord, node, rows, ctx), do: chord(node, rows, ctx)
  def run(:sankey, node, rows, ctx), do: sankey(node, rows, ctx)
  def run(:force, node, rows, ctx), do: Force.run(node, rows, ctx)

  # -- hierarchies ------------------------------------------------------------------------

  defp hierarchy(op, node, rows, ctx) do
    id = Map.get(node, :id, :id)
    by = Map.get(node, :by, :parent)
    size = Map.get(node, :size, ctx.size)

    root =
      rows
      |> Hierarchy.stratify(id: &Table.get(&1, id), parent_id: &Table.get(&1, by))
      |> aggregate(Map.get(node, :field))

    laid = op |> layout(node, size) |> generate(op, root)

    case Map.get(node, :output, :nodes) do
      :nodes ->
        Enum.map(Hierarchy.descendants(laid), &node_row(op, &1))

      :links ->
        orientation = Map.get(node, :orientation, :vertical)
        shape = Map.get(node, :link, :curve)
        Enum.map(Hierarchy.links(laid), &link_row(op, &1, id, orientation, shape))

      other ->
        raise ArgumentError, "#{inspect(op)} yields no #{inspect(other)} (spec/14 §5.4.2)"
    end
  end

  defp aggregate(root, nil), do: Hierarchy.count(root)
  defp aggregate(root, field), do: Hierarchy.sum(root, &(Table.get(&1, field) || 0))

  defp layout(:tree, _node, size), do: Tree.size(Tree.new(), size)
  defp layout(:cluster, _node, size), do: Cluster.size(Cluster.new(), size)

  defp layout(:pack, node, size),
    do: Pack.new() |> Pack.size(size) |> Pack.padding(Map.get(node, :padding, 0))

  defp layout(:partition, node, size) do
    Partition.new() |> Partition.size(size) |> Partition.padding(Map.get(node, :padding, 0))
  end

  defp layout(:treemap, node, size) do
    Treemap.new()
    |> Treemap.size(size)
    |> Treemap.padding(Map.get(node, :padding, 0))
    |> Treemap.tile(Map.get(node, :tile, :squarify))
  end

  defp generate(layout, :tree, root), do: Tree.generate(layout, root)
  defp generate(layout, :cluster, root), do: Cluster.generate(layout, root)
  defp generate(layout, :pack, root), do: Pack.generate(layout, root)
  defp generate(layout, :partition, root), do: Partition.generate(layout, root)
  defp generate(layout, :treemap, root), do: Treemap.generate(layout, root)

  defp node_row(op, %Hierarchy{} = n) do
    base = %{depth: n.depth, height: n.height, value: n.value}
    Map.merge(n.data, Map.merge(base, Map.take(n, fields(op))))
  end

  defp fields(op) when op in [:tree, :cluster], do: [:x, :y]
  defp fields(:pack), do: [:x, :y, :r]
  defp fields(op) when op in [:partition, :treemap], do: [:x0, :y0, :x1, :y1]

  # The positions are the layout's own in either orientation; only the path is oriented
  # and shaped (spec/14 §5.4.2, D-70).
  defp link_row(op, {parent, child}, id, orientation, shape)
       when op in [:tree, :cluster, :pack] do
    %{
      source: Table.get(parent.data, id),
      target: Table.get(child.data, id),
      x0: parent.x,
      y0: parent.y,
      x1: child.x,
      y1: child.y,
      path: link_path(op, orientation, shape, parent.x, parent.y, child.x, child.y)
    }
  end

  defp link_row(op, _link, _id, _orientation, _shape) do
    raise ArgumentError, "#{inspect(op)} yields no :links (spec/14 §5.4.2)"
  end

  defp link_path(:pack, _orientation, _shape, x0, y0, x1, y1),
    do: Path.new() |> Path.move_to(x0, y0) |> Path.line_to(x1, y1)

  # The cubic between parent and child with both control points at the mid-depth, the
  # dendrogram's elbow across at the parent's depth and then to the child, or the straight
  # segment; horizontal is the same path with the axes swapped (#127).
  defp link_path(_tree_or_cluster, :vertical, :curve, x0, y0, x1, y1) do
    ym = (y0 + y1) / 2
    Path.new() |> Path.move_to(x0, y0) |> Path.curve_to(x0, ym, x1, ym, x1, y1)
  end

  defp link_path(_tree_or_cluster, :horizontal, :curve, x0, y0, x1, y1) do
    ym = (y0 + y1) / 2
    Path.new() |> Path.move_to(y0, x0) |> Path.curve_to(ym, x0, ym, x1, y1, x1)
  end

  defp link_path(_tree_or_cluster, :vertical, :elbow, x0, y0, x1, y1),
    do: Path.new() |> Path.move_to(x0, y0) |> Path.horizontal_to(x1) |> Path.vertical_to(y1)

  defp link_path(_tree_or_cluster, :horizontal, :elbow, x0, y0, x1, y1),
    do: Path.new() |> Path.move_to(y0, x0) |> Path.vertical_to(x1) |> Path.horizontal_to(y1)

  defp link_path(_tree_or_cluster, :vertical, :line, x0, y0, x1, y1),
    do: Path.new() |> Path.move_to(x0, y0) |> Path.line_to(x1, y1)

  defp link_path(_tree_or_cluster, :horizontal, :line, x0, y0, x1, y1),
    do: Path.new() |> Path.move_to(y0, x0) |> Path.line_to(y1, x1)

  # -- flows ------------------------------------------------------------------------------

  # A flow is a row read as `{source, target, value}`; the nodes are the distinct ids over
  # every source and then every target, in order of first appearance.
  @doc false
  @spec flows(map(), [map()], number()) :: [{term(), term(), term()}]
  def flows(node, rows, default) do
    [source, target] = node.fields
    value = Map.get(node, :field)

    Enum.map(rows, fn row ->
      v = if value, do: Table.get(row, value), else: default
      {Table.get(row, source), Table.get(row, target), v || default}
    end)
  end

  # The graph's nodes: `{ids, table}` — without a node source, the distinct ids over
  # every source and then every target with an empty table; with one (`nodes`, spec/14
  # §5.4.3, D-110), the source's rows in its order keyed by `id`, a flow naming an id the
  # table lacks a fault. A node row the layout yields is its table row under the layout's.
  @doc false
  @spec nodes(map(), [{term(), term(), term()}], map()) :: {[term()], map()}
  def nodes(node, flows, ctx) do
    mentioned = Enum.uniq(Enum.map(flows, &elem(&1, 0)) ++ Enum.map(flows, &elem(&1, 1)))

    case Map.get(node, :nodes) do
      nil ->
        {mentioned, %{}}

      name ->
        id = Map.get(node, :id, :id)
        rows = Table.rows(source!(ctx, name, node.op))
        table = Map.new(rows, &{Table.get(&1, id), &1})

        case Enum.reject(mentioned, &Map.has_key?(table, &1)) do
          [] ->
            {Enum.map(rows, &Table.get(&1, id)), table}

          [missing | _] ->
            raise ArgumentError,
                  "a flow of the #{inspect(node.op)} names #{inspect(missing)}, which the " <>
                    "node source #{inspect(name)} lacks (spec/14 §5.4.3)"
        end
    end
  end

  defp source!(ctx, name, op) do
    Map.get(Map.get(ctx, :sources, %{}), name) ||
      raise ArgumentError,
            "the #{inspect(op)} reads its nodes from #{inspect(name)}, which is not bound " <>
              "(spec/14 §5.4.3)"
  end

  @doc false
  @spec with_node(map(), map()) :: map()
  def with_node(table, %{id: id} = row), do: Map.merge(Map.get(table, id, %{}), row)

  # -- chord ------------------------------------------------------------------------------

  defp chord(node, rows, ctx) do
    flows = flows(node, rows, 0)
    {ids, table} = nodes(node, flows, ctx)
    index = ids |> Enum.with_index() |> Map.new()
    n = length(ids)

    matrix =
      Enum.reduce(flows, empty_matrix(n), fn {s, t, v}, m ->
        i = index[s]
        j = index[t]
        List.update_at(m, i, &List.update_at(&1, j, fn cell -> cell + v end))
      end)

    result = Chord.new() |> Chord.pad_angle(Map.get(node, :padding, 0)) |> Chord.generate(matrix)
    # `size` sets the radius only; the centre is the point an `:arc` mark is about, so
    # the ribbons meet the ring however either step is sized (spec/14 §5.4.3, #488).
    [w, h] = Map.get(node, :size, ctx.size)
    r = min(w, h) / 2
    [cx, cy] = ctx.center
    centre = Transform.translate(cx, cy)

    case Map.get(node, :output, :groups) do
      :groups ->
        Enum.map(result.groups, fn g ->
          with_node(table, %{
            index: g.index,
            id: Enum.at(ids, g.index),
            start_angle: g.start_angle,
            end_angle: g.end_angle,
            value: g.value,
            path: Path.transform(group_path(g, r), centre)
          })
        end)

      :chords ->
        Enum.map(result.chords, fn c ->
          %{
            source: Enum.at(ids, c.source.index),
            target: Enum.at(ids, c.target.index),
            source_value: c.source.value,
            target_value: c.target.value,
            path: Path.transform(ribbon_path(c, @ring * r), centre)
          }
        end)

      other ->
        raise ArgumentError, ":chord yields no #{inspect(other)} (spec/14 §5.4.3)"
    end
  end

  defp empty_matrix(n), do: List.duplicate(List.duplicate(0, n), n)

  defp group_path(group, r) do
    Arc.new()
    |> Arc.inner_radius(@ring * r)
    |> Arc.outer_radius(r)
    |> Arc.generate_path(group)
  end

  # The ribbon of `Visualize.Layout.Chord.ribbon_path/2` as an `IR.Path`: the source arc,
  # a quadratic curve through the centre, the target arc, a quadratic curve back.
  defp ribbon_path(chord, r) do
    {sx0, sy0} = point(chord.source.start_angle, r)
    {sx1, sy1} = point(chord.source.end_angle, r)
    source_large = large(chord.source)

    path =
      Path.new()
      |> Path.move_to(sx0, sy0)
      |> Path.arc_to(r, r, 0, source_large, 1, sx1, sy1)

    if chord.source.index == chord.target.index do
      path |> Path.quad_to(0, 0, sx0, sy0) |> Path.close()
    else
      {tx0, ty0} = point(chord.target.start_angle, r)
      {tx1, ty1} = point(chord.target.end_angle, r)

      path
      |> Path.quad_to(0, 0, tx0, ty0)
      |> Path.arc_to(r, r, 0, large(chord.target), 1, tx1, ty1)
      |> Path.quad_to(0, 0, sx0, sy0)
      |> Path.close()
    end
  end

  defp point(angle, r), do: {r * :math.sin(angle), -r * :math.cos(angle)}

  defp large(%{start_angle: a0, end_angle: a1}), do: if(a1 - a0 > :math.pi(), do: 1, else: 0)

  # -- sankey -----------------------------------------------------------------------------

  defp sankey(node, rows, ctx) do
    flows = flows(node, rows, 0)
    {ids, table} = nodes(node, flows, ctx)
    nodes = Enum.map(ids, &%{id: &1})
    links = Enum.map(flows, fn {s, t, v} -> %{source: s, target: t, value: v} end)
    [w, h] = Map.get(node, :size, ctx.size)

    result =
      Sankey.new()
      |> Sankey.size(w, h)
      |> Sankey.node_padding(Map.get(node, :padding, 8))
      |> Sankey.compute(nodes, links)

    case Map.get(node, :output, :nodes) do
      :nodes ->
        Enum.map(
          result.nodes,
          &with_node(
            table,
            Map.take(&1, [:id, :index, :depth, :height, :layer, :value, :x0, :x1, :y0, :y1])
          )
        )

      :links ->
        Enum.map(result.links, fn link ->
          %{
            source: link.source,
            target: link.target,
            value: link.value,
            width: link.width,
            x0: link.source_node.x1,
            y0: link.y0,
            x1: link.target_node.x0,
            y1: link.y1,
            path: sankey_link(link)
          }
        end)

      other ->
        raise ArgumentError, ":sankey yields no #{inspect(other)} (spec/14 §5.4.3)"
    end
  end

  # The ribbon of `Visualize.Layout.Sankey.generate_link_path/1` as an `IR.Path`.
  defp sankey_link(%{source_node: source, target_node: target, y0: y0, y1: y1, width: width}) do
    x0 = source.x1
    x1 = target.x0
    xi = (x0 + x1) / 2

    Path.new()
    |> Path.move_to(x0, y0)
    |> Path.curve_to(xi, y0, xi, y1, x1, y1)
    |> Path.line_to(x1, y1 + width)
    |> Path.curve_to(xi, y1 + width, xi, y0 + width, x0, y0 + width)
    |> Path.close()
  end
end
