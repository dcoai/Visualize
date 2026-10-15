defmodule Visualize.Layout.Tree do
  @moduledoc """
  Tree layout algorithm for hierarchical node-link diagrams.

  Implements the Reingold–Tilford "tidy" algorithm as refined by Buchheim, Jünger and
  Leipert (linear time, threads and accumulated shifts), ported from d3-hierarchy's
  `tree`: children of one parent are placed left to right with the gap given by
  `separation`, every parent is centered over its children, and subtrees are shifted so
  that nodes at the same depth never overlap while adjacent subtrees keep their
  separation.

  ## Examples

      # Create hierarchy
      data = %{
        name: "root",
        children: [
          %{name: "A", children: [%{name: "A1"}, %{name: "A2"}]},
          %{name: "B"}
        ]
      }

      root = Visualize.Layout.Hierarchy.new(data)

      # Apply tree layout
      tree = Visualize.Layout.Tree.new()
        |> Visualize.Layout.Tree.size([400, 200])

      positioned = Visualize.Layout.Tree.generate(tree, root)

      # Each node now has x, y coordinates
      Visualize.Layout.Hierarchy.each(positioned, fn node ->
        IO.puts("\#{node.data.name}: (\#{node.x}, \#{node.y})")
      end)

  """

  alias Visualize.Layout.Hierarchy

  # The root's parent in the layout store: d3's fake TreeNode above the root.
  @fake_root 0

  defstruct size: nil,
            node_size: nil,
            separation: nil

  @type t :: %__MODULE__{
          size: {number(), number()} | nil,
          node_size: {number(), number()} | nil,
          separation: (Hierarchy.t(), Hierarchy.t() -> number()) | nil
        }

  @doc "Creates a new tree layout"
  @spec new() :: t()
  def new do
    %__MODULE__{
      separation: &default_separation/2
    }
  end

  @doc """
  Sets the size of the layout.

  The tree will be scaled to fit within [width, height].
  """
  @spec size(t(), [number()] | {number(), number()}) :: t()
  def size(%__MODULE__{} = tree, [width, height]) do
    %{tree | size: {width, height}, node_size: nil}
  end

  def size(%__MODULE__{} = tree, {width, height}) do
    %{tree | size: {width, height}, node_size: nil}
  end

  @doc """
  Sets the fixed node size.

  Unlike size/2, this sets a fixed spacing between nodes rather
  than scaling to fit a container.
  """
  @spec node_size(t(), [number()] | {number(), number()}) :: t()
  def node_size(%__MODULE__{} = tree, [dx, dy]) do
    %{tree | node_size: {dx, dy}, size: nil}
  end

  def node_size(%__MODULE__{} = tree, {dx, dy}) do
    %{tree | node_size: {dx, dy}, size: nil}
  end

  @doc """
  Sets the separation function between nodes.

  The function receives two nodes and returns the desired separation.
  Default is 1 for siblings, 2 for non-siblings.
  """
  @spec separation(t(), (Hierarchy.t(), Hierarchy.t() -> number())) :: t()
  def separation(%__MODULE__{} = tree, func) when is_function(func, 2) do
    %{tree | separation: func}
  end

  @doc """
  Generates the tree layout, positioning all nodes.

  Without `size` or `node_size` the coordinates are raw: `x` in separation units with
  the root at 0, `y` the depth.
  """
  @spec generate(t(), Hierarchy.t()) :: Hierarchy.t()
  def generate(%__MODULE__{} = tree, %Hierarchy{} = root) do
    {store, root_id} = build_store(root)

    store =
      store
      |> walk_after(root_id, &first_walk(&1, &2, tree.separation))
      |> then(fn store -> put_in(store, [@fake_root, :m], -store[root_id].z) end)
      |> walk_before(root_id, &second_walk/2)

    root
    |> assign_positions(store, root_id)
    |> scale_to_size(tree)
  end

  # ------------------------------------------------------------------
  # The layout works on a store of plain maps keyed by pre-order index, the analog of
  # d3's TreeNode wrappers: `z` prelim x, `m` modifier, `c` change, `s` shift, `t` thread
  # (an id or nil), `a` ancestor (an id), `anc` default ancestor (an id or nil), `i` the
  # index among siblings, `parent` and `children` as ids, `node` the hierarchy node.
  # The root's parent is a fake node (id 0) with the root as its only child.
  # ------------------------------------------------------------------

  defp build_store(root) do
    fake = %{parent: nil, children: [1], i: 0, z: 0, m: 0, c: 0, s: 0, t: nil, a: 0, anc: nil}
    {store, _next} = add_node(root, @fake_root, 0, %{@fake_root => fake}, 1)
    {store, 1}
  end

  defp add_node(node, parent_id, i, store, id) do
    entry = %{
      node: node,
      parent: parent_id,
      children: [],
      i: i,
      z: 0,
      m: 0,
      c: 0,
      s: 0,
      t: nil,
      a: id,
      anc: nil
    }

    {store, next, child_ids} =
      (node.children || [])
      |> Enum.with_index()
      |> Enum.reduce({Map.put(store, id, entry), id + 1, []}, fn {child, j}, {st, nxt, ids} ->
        {st, nxt2} = add_node(child, id, j, st, nxt)
        {st, nxt2, [nxt | ids]}
      end)

    {put_in(store, [id, :children], Enum.reverse(child_ids)), next}
  end

  defp walk_after(store, id, fun) do
    store = Enum.reduce(store[id].children, store, &walk_after(&2, &1, fun))
    fun.(store, id)
  end

  defp walk_before(store, id, fun) do
    store = fun.(store, id)
    Enum.reduce(store[id].children, store, &walk_before(&2, &1, fun))
  end

  defp sep(store, a, b, separation), do: separation.(store[a].node, store[b].node)

  defp first_walk(store, v, separation) do
    siblings = store[store[v].parent].children
    w = if store[v].i > 0, do: Enum.at(siblings, store[v].i - 1), else: nil

    store =
      case store[v].children do
        [] ->
          if w, do: put_in(store, [v, :z], store[w].z + sep(store, v, w, separation)), else: store

        children ->
          store = execute_shifts(store, v)
          midpoint = (store[hd(children)].z + store[List.last(children)].z) / 2

          if w do
            z = store[w].z + sep(store, v, w, separation)
            store |> put_in([v, :z], z) |> put_in([v, :m], z - midpoint)
          else
            put_in(store, [v, :z], midpoint)
          end
      end

    parent = store[v].parent
    {ancestor, store} = apportion(store, v, w, store[parent].anc || hd(siblings), separation)
    put_in(store, [parent, :anc], ancestor)
  end

  defp second_walk(store, v) do
    pm = store[store[v].parent].m
    store |> update_in([v, :z], &(&1 + pm)) |> update_in([v, :m], &(&1 + pm))
  end

  defp execute_shifts(store, v) do
    {store, _shift, _change} =
      store[v].children
      |> Enum.reverse()
      |> Enum.reduce({store, 0, 0}, fn w, {st, shift, change} ->
        st = st |> update_in([w, :z], &(&1 + shift)) |> update_in([w, :m], &(&1 + shift))
        change = change + st[w].c
        {st, shift + st[w].s + change, change}
      end)

    store
  end

  defp apportion(store, _v, nil, ancestor, _separation), do: {ancestor, store}

  defp apportion(store, v, w, ancestor, separation) do
    vom = hd(store[store[v].parent].children)
    sums = {store[v].m, store[v].m, store[w].m, store[vom].m}
    contour(store, v, {v, v, w, vom}, sums, ancestor, separation)
  end

  # One step along the four contours: vip/vop the inner and outer contour of the subtree
  # at v, vim/vom the inner and outer contour of the subtrees to its left.
  defp contour(store, v, {vip, vop, vim, vom}, {sip, sop, sim, som}, ancestor, separation) do
    vim2 = next_right(store, vim)
    vip2 = next_left(store, vip)

    if vim2 && vip2 do
      vom2 = next_left(store, vom)
      vop2 = next_right(store, vop)
      store = put_in(store, [vop2, :a], v)

      shift = store[vim2].z + sim - store[vip2].z - sip + sep(store, vim2, vip2, separation)

      {store, sip, sop} =
        if shift > 0 do
          store = move_subtree(store, next_ancestor(store, vim2, v, ancestor), v, shift)
          {store, sip + shift, sop + shift}
        else
          {store, sip, sop}
        end

      sums = {sip + store[vip2].m, sop + store[vop2].m, sim + store[vim2].m, som + store[vom2].m}
      contour(store, v, {vip2, vop2, vim2, vom2}, sums, ancestor, separation)
    else
      store =
        if vim2 && next_right(store, vop) == nil do
          store |> put_in([vop, :t], vim2) |> update_in([vop, :m], &(&1 + sim - sop))
        else
          store
        end

      if vip2 && next_left(store, vom) == nil do
        store = store |> put_in([vom, :t], vip2) |> update_in([vom, :m], &(&1 + sip - som))
        {v, store}
      else
        {ancestor, store}
      end
    end
  end

  defp next_left(store, v) do
    case store[v].children do
      [] -> store[v].t
      [first | _] -> first
    end
  end

  defp next_right(store, v) do
    case store[v].children do
      [] -> store[v].t
      children -> List.last(children)
    end
  end

  defp next_ancestor(store, vim, v, ancestor) do
    if store[store[vim].a].parent == store[v].parent, do: store[vim].a, else: ancestor
  end

  defp move_subtree(store, wm, wp, shift) do
    change = shift / (store[wp].i - store[wm].i)

    store
    |> update_in([wp, :c], &(&1 - change))
    |> update_in([wp, :s], &(&1 + shift))
    |> update_in([wm, :c], &(&1 + change))
    |> update_in([wp, :z], &(&1 + shift))
    |> update_in([wp, :m], &(&1 + shift))
  end

  defp assign_positions(%Hierarchy{} = node, store, id) do
    children =
      case node.children do
        nil -> nil
        [] -> nil
        cs -> Enum.zip_with(cs, store[id].children, &assign_positions(&1, store, &2))
      end

    %{node | x: store[id].z, y: node.depth, children: children}
  end

  # Scale tree to fit specified size
  defp scale_to_size(root, %__MODULE__{size: nil, node_size: nil}) do
    root
  end

  defp scale_to_size(root, %__MODULE__{size: {width, height}}) do
    nodes = Hierarchy.descendants(root)

    # Find extent
    {min_x, max_x} =
      nodes
      |> Enum.map(& &1.x)
      |> Enum.min_max()

    {min_y, max_y} =
      nodes
      |> Enum.map(& &1.y)
      |> Enum.min_max()

    x_range = max_x - min_x
    y_range = max_y - min_y

    # Scale factors
    kx = if x_range == 0, do: 1, else: width / x_range
    ky = if y_range == 0, do: 1, else: height / y_range

    # Apply scaling
    scale_node(root, min_x, min_y, kx, ky)
  end

  defp scale_to_size(root, %__MODULE__{node_size: {dx, dy}}) do
    # With node_size, just multiply by spacing
    scale_node_fixed(root, dx, dy)
  end

  defp scale_node(%Hierarchy{} = node, min_x, min_y, kx, ky) do
    new_x = (node.x - min_x) * kx
    new_y = (node.y - min_y) * ky

    new_children =
      case node.children do
        nil -> nil
        children -> Enum.map(children, &scale_node(&1, min_x, min_y, kx, ky))
      end

    %{node | x: new_x, y: new_y, children: new_children}
  end

  defp scale_node_fixed(%Hierarchy{} = node, dx, dy) do
    new_x = node.x * dx
    new_y = node.y * dy

    new_children =
      case node.children do
        nil -> nil
        children -> Enum.map(children, &scale_node_fixed(&1, dx, dy))
      end

    %{node | x: new_x, y: new_y, children: new_children}
  end

  defp default_separation(a, b) do
    if a.parent == b.parent, do: 1, else: 2
  end
end
