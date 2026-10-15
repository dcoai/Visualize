defmodule Visualize.Chart.Transform.Force do
  @moduledoc false
  # The `:force` step of a mark's pipeline (spec/14 §5.4.3, D-110, D-132), and the one
  # run per realization that the marks of one graph share.
  #
  # A step is laid out by `Visualize.Layout.Force.run/1`. `Visualize.Chart.Frame.new/2`
  # lays out every distinct step of its marks once, before anything else reads the rows
  # (`layouts/4`), and holds the layouts in the frame's `forces`; every pipeline that
  # reaches a step during that realization finds its layout there by the step's *run key*
  # (`run/3`) — the node without `output`, and its input. A step that is not there runs
  # cold, as it always did.
  #
  # Cold is the spiral of spec/06 §8.1 at alpha 1 over 300 iterations, from a node
  # source's `x`/`y` where its row has them. Warm is a compiled chart's (spec/14 §12.5):
  # the layout it last drew, by node id, under the step's *graph key* (`graph_key/3`), is
  # the start, reheated to the step's `alpha` for at most its `ticks` iterations at d3's
  # own decay.

  alias Visualize.Chart.Frame.Scales
  alias Visualize.Chart.Schema
  alias Visualize.Chart.Transform.Layout
  alias Visualize.Data.Table
  alias Visualize.IR.Path
  alias Visualize.Layout.Force

  # d3's `alphaDecay`, 1 - 0.001^(1/300): a reheated graph cools as a d3 simulation does,
  # whatever its `ticks`.
  @d3_decay 1 - :math.pow(0.001, 1 / 300)

  @typedoc "A node's carried state: where it is and how it is moving."
  @type motion :: %{x: number(), y: number(), vx: number(), vy: number()}

  @typedoc "A compiled chart's warm state: per graph key, each node's motion by id."
  @type warm :: %{term() => %{term() => motion()}}

  @typedoc "A realization's layouts: per run key, the graph key and the laid-out nodes."
  @type layouts :: %{term() => %{key: term(), nodes: [map()]}}

  @doc false
  # The step: the realization's layout for it when there is one, else a cold run.
  @spec run(map(), [map()], map()) :: [map()]
  def run(node, rows, ctx) do
    graph = graph(node, rows, ctx)

    nodes =
      case Map.fetch(Map.get(ctx, :forces, %{}), run_key(node, graph)) do
        {:ok, %{nodes: nodes}} -> nodes
        :error -> layout(node, graph, nil)
      end

    output(node, graph, nodes)
  end

  @doc false
  # Every distinct `:force` step of `marks`, laid out once: from the warm state of its
  # graph key when `warm` holds one, cold otherwise. `ctx` is the pipeline's context as
  # `Visualize.Chart.Frame.Scales.mark_rows/3` reads it, without layouts, so the rows a
  # step is given are computed as the pipeline computes them.
  @spec layouts([map()], map(), map(), warm()) :: layouts()
  def layouts(marks, sources, ctx, warm) do
    marks
    |> Enum.flat_map(&steps(&1, sources, ctx))
    |> Enum.uniq_by(fn {run_key, _identity, _node, _graph} -> run_key end)
    |> Enum.map_reduce(%{}, fn {run_key, identity, node, graph}, seen ->
      n = Map.get(seen, identity, 0)
      key = {identity, n}

      {{run_key, %{key: key, nodes: layout(node, graph, Map.get(warm, key))}},
       Map.put(seen, identity, n + 1)}
    end)
    |> elem(0)
    |> Map.new()
  end

  @doc false
  # The warm state a realization's layouts leave: each graph's nodes by id, their position
  # and velocity alone. A node the graph no longer has is not in it, so it is forgotten.
  @spec warm(layouts()) :: warm()
  def warm(layouts) do
    Map.new(layouts, fn {_run_key, %{key: key, nodes: nodes}} ->
      {key, Map.new(nodes, &{&1.id, Map.take(&1, [:x, :y, :vx, :vy])})}
    end)
  end

  # The `:force` steps of one mark: each with its run key, its graph's identity, its
  # node and its input graph. A step lacking its required keys is left to the pipeline,
  # which raises for it by name (spec/14 §5.4).
  defp steps(%{data: %{source: source, transforms: transforms} = data} = mark, sources, ctx)
       when is_list(transforms) do
    for {%{op: :force} = node, k} <- Enum.with_index(transforms), complete?(node) do
      before = %{mark | data: %{data | transforms: Enum.take(transforms, k)}}
      rows = Scales.mark_rows(before, sources, ctx)
      graph = graph(node, rows, Map.put(ctx, :sources, sources))
      {run_key(node, graph), identity(source, node), node, graph}
    end
  end

  defp steps(_mark, _sources, _ctx), do: []

  defp complete?(node) do
    Enum.all?(Schema.transform_keys(:force).required, &Map.has_key?(node, &1))
  end

  # A graph across ticks (spec/14 §12.5): its source and what the step reads of it — not
  # its forces, which a tick may change and which perturb the graph rather than make
  # another.
  defp identity(source, node),
    do: {source, node.fields, Map.get(node, :nodes), Map.get(node, :id, :id)}

  # One run of a realization: the step as it is laid out and what it is laid out over.
  defp run_key(node, graph) do
    {Map.delete(node, :output), graph.size, graph.ids, graph.pairs, graph.seeds}
  end

  # The step's input: its node ids in order, the node table, the flows, and the
  # positions a node row seeds (spec/14 §5.4.3).
  defp graph(node, rows, ctx) do
    flows = Layout.flows(node, rows, 1)
    {ids, table} = Layout.nodes(node, flows, ctx)

    %{
      ids: ids,
      table: table,
      flows: flows,
      pairs: Enum.map(flows, fn {s, t, _v} -> {s, t} end),
      size: Map.get(node, :size, ctx.size),
      seeds: seeds(ids, table)
    }
  end

  defp seeds(ids, table) do
    for id <- ids,
        row = Map.get(table, id),
        row != nil,
        x = Table.get(row, :x),
        y = Table.get(row, :y),
        is_number(x) and is_number(y),
        into: %{},
        do: {id, %{x: x, y: y}}
  end

  # -- the layout -------------------------------------------------------------------------

  # Cold: the spiral, or the seeds, at alpha 1 over 300 iterations. Warm: the carried
  # motions, a new node placed by `place/4`, reheated to `alpha` for `ticks` iterations.
  # A graph none of whose nodes is carried has nothing to be warm from, and is cold.
  defp layout(node, graph, warm) do
    known = if warm, do: Map.take(warm, graph.ids), else: %{}
    links = Enum.map(graph.pairs, fn {s, t} -> %{source: s, target: t} end)

    if map_size(known) == 0 do
      nodes = Enum.map(graph.ids, &Map.merge(%{id: &1}, Map.get(graph.seeds, &1, %{})))
      Force.run(nodes: nodes, links: links, forces: forces(node, graph)).nodes
    else
      Force.run(
        nodes: place(graph, known),
        links: links,
        forces: forces(node, graph),
        alpha: Map.get(node, :alpha, Schema.default(:transform, :alpha)),
        iterations: Map.get(node, :ticks, Schema.default(:transform, :ticks)),
        alpha_decay: @d3_decay
      ).nodes
    end
  end

  defp forces(node, %{size: [w, h]}) do
    [
      {:center, x: w / 2, y: h / 2},
      {:many_body, strength: Map.get(node, :strength, Schema.default(:transform, :strength))},
      {:link, distance: Map.get(node, :distance, Schema.default(:transform, :distance))}
    ]
  end

  # Every node at its start: a carried node where it was, moving as it was; a seeded one
  # at its seed; any other at its spiral position (spec/06 §8.1) about the mean of its
  # laid-out neighbors — or of every laid-out node, when it has none — as d3 places a
  # node with no position about the origin (spec/14 §5.4.3). Near its neighbors it
  # neither sits on one nor starts across the graph, where its link would yank it and
  # the center force translate every node by its share of the move.
  defp place(graph, known) do
    center = mean(Map.values(known))

    graph.ids
    |> Enum.with_index()
    |> Enum.map(fn {id, i} ->
      case {Map.fetch(known, id), Map.fetch(graph.seeds, id)} do
        {{:ok, motion}, _} ->
          Map.put(motion, :id, id)

        {:error, {:ok, seed}} ->
          Map.put(seed, :id, id)

        {:error, :error} ->
          laid = for n <- neighbors(graph.pairs, id), m = known[n], m != nil, do: m
          {cx, cy} = if laid == [], do: center, else: mean(laid)
          {dx, dy} = spiral(i)
          %{id: id, x: cx + dx, y: cy + dy}
      end
    end)
  end

  defp neighbors(pairs, id) do
    for {s, t} <- pairs, s == id or t == id, do: if(s == id, do: t, else: s)
  end

  defp mean(motions) do
    n = length(motions)
    {Enum.sum(Enum.map(motions, & &1.x)) / n, Enum.sum(Enum.map(motions, & &1.y)) / n}
  end

  # spec/06 §8.1's initial position of the i-th node, about the origin.
  defp spiral(i) do
    radius = :math.sqrt(0.5 + i) * 10
    angle = i * :math.pi() * (3 - :math.sqrt(5))
    {radius * :math.cos(angle), radius * :math.sin(angle)}
  end

  # -- the rows ---------------------------------------------------------------------------

  defp output(node, graph, nodes) do
    positions = Map.new(nodes, &{&1.id, &1})

    case Map.get(node, :output, :nodes) do
      :nodes ->
        Enum.map(nodes, &Layout.with_node(graph.table, Map.take(&1, [:id, :x, :y])))

      :links ->
        Enum.map(graph.flows, fn {s, t, _v} ->
          %{x: x0, y: y0} = Map.fetch!(positions, s)
          %{x: x1, y: y1} = Map.fetch!(positions, t)
          path = Path.new() |> Path.move_to(x0, y0) |> Path.line_to(x1, y1)
          %{source: s, target: t, x0: x0, y0: y0, x1: x1, y1: y1, path: path}
        end)

      other ->
        raise ArgumentError, ":force yields no #{inspect(other)} (spec/14 §5.4.3)"
    end
  end
end
