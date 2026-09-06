defmodule Visualize.Layout.Pack do
  @moduledoc """
  Circle packing layout for hierarchical data.

  Enclosing circles show hierarchical containment, with the area of each
  leaf circle proportional to its value.

  The sibling packing is a port of d3-hierarchy's `packSiblings` (the front-chain
  algorithm of Wang et al.) and the enclosing circle of d3's `packEnclose` (Welzl's
  algorithm over a deterministic shuffle), so a layout is a pure function of its input.

  ## Examples

      data = %{
        name: "root",
        children: [
          %{name: "A", value: 100},
          %{name: "B", value: 200},
          %{name: "C", children: [
            %{name: "C1", value: 50},
            %{name: "C2", value: 75}
          ]}
        ]
      }

      root = Visualize.Layout.Hierarchy.new(data)
        |> Visualize.Layout.Hierarchy.sum(fn d -> d[:value] || 0 end)

      pack = Visualize.Layout.Pack.new()
        |> Visualize.Layout.Pack.size([400, 400])
        |> Visualize.Layout.Pack.padding(3)

      positioned = Visualize.Layout.Pack.generate(pack, root)

      # Each node now has x, y (center) and r (radius)

  """

  alias Visualize.Layout.Hierarchy

  defstruct size: {1, 1},
            padding: 0,
            radius: nil

  @type t :: %__MODULE__{
          size: {number(), number()},
          padding: number() | (Hierarchy.t() -> number()),
          radius: (Hierarchy.t() -> number()) | nil
        }

  @doc "Creates a new pack layout"
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc "Sets the size of the pack layout"
  @spec size(t(), [number()] | {number(), number()}) :: t()
  def size(%__MODULE__{} = pack, [width, height]) do
    %{pack | size: {width, height}}
  end

  def size(%__MODULE__{} = pack, {width, height}) do
    %{pack | size: {width, height}}
  end

  @doc """
  Sets the padding between circles, in output units.

  Can be a number or a function that takes a node and returns padding.
  """
  @spec padding(t(), number() | (Hierarchy.t() -> number())) :: t()
  def padding(%__MODULE__{} = pack, p) do
    %{pack | padding: p}
  end

  @doc """
  Sets a custom radius function.

  If not set, radius is computed from the node's value.
  """
  @spec radius(t(), (Hierarchy.t() -> number())) :: t()
  def radius(%__MODULE__{} = pack, func) when is_function(func, 1) do
    %{pack | radius: func}
  end

  @doc "Generates the pack layout"
  @spec generate(t(), Hierarchy.t()) :: Hierarchy.t()
  def generate(%__MODULE__{} = pack, %Hierarchy{} = root) do
    {width, height} = pack.size
    root = compute_radii(root, pack)

    # Two passes, as d3 does when the radius comes from the value: the first, unpadded,
    # finds the root's radius; the second inflates every child by the padding expressed in
    # layout units, so that after scaling siblings are exactly `padding` output units apart.
    unpadded = pack_node(root, fn _ -> 0 end)

    if unpadded.r && unpadded.r > 0 do
      k = unpadded.r / min(width, height)
      packed = pack_node(root, fn node -> padding_of(pack.padding, node) * k end)
      scale = min(width, height) / (2 * packed.r)
      translate_and_scale(packed, width / 2, height / 2, scale)
    else
      unpadded
    end
  end

  defp padding_of(p, _node) when is_number(p), do: p
  defp padding_of(p, node) when is_function(p, 1), do: p.(node)

  defp compute_radii(%Hierarchy{children: children} = node, pack)
       when is_list(children) and children != [] do
    %{node | children: Enum.map(children, &compute_radii(&1, pack))}
  end

  defp compute_radii(%Hierarchy{} = leaf, pack) do
    r =
      case pack.radius do
        nil -> if leaf.value, do: :math.sqrt(leaf.value), else: 1
        func -> func.(leaf)
      end

    %{leaf | r: max(0, r)}
  end

  # d3's packChildren: children are packed with their radii inflated by the padding, the
  # enclosing circle found, then the inflation removed; the parent's radius keeps it.
  defp pack_node(%Hierarchy{children: children} = node, padding_fn)
       when is_list(children) and children != [] do
    packed = Enum.map(children, &pack_node(&1, padding_fn))
    r = padding_fn.(node)

    circles = Enum.map(packed, fn c -> {c.x || 0, c.y || 0, c.r + r} end)
    {placed, enclosing_r} = pack_siblings(circles)

    children =
      Enum.zip_with(packed, placed, fn child, {x, y, _r} -> %{child | x: x, y: y} end)

    %{node | children: children, x: 0, y: 0, r: enclosing_r + r}
  end

  defp pack_node(%Hierarchy{} = leaf, _padding_fn), do: leaf

  # ------------------------------------------------------------------
  # packSiblings: circles are `{x, y, r}`; the front chain is a circular doubly linked
  # list over circle indices kept in two maps. Returns the placed circles (centred on the
  # enclosing circle) and the enclosing radius.
  # ------------------------------------------------------------------

  defp pack_siblings([]), do: {[], 0}
  defp pack_siblings([{_, _, r}]), do: {[{0, 0, r}], r}

  defp pack_siblings([{_, _, ra}, {_, _, rb}]) do
    {[{-rb, 0, ra}, {ra, 0, rb}], ra + rb}
  end

  defp pack_siblings(circles) do
    n = length(circles)
    [{_, _, ra}, {_, _, rb}, {_, _, rc} | _] = circles
    a = {-rb, 0, ra}
    b = {ra, 0, rb}
    c = place(b, a, rc)

    store = %{0 => a, 1 => b, 2 => c}
    chain = %{next: %{0 => 1, 1 => 2, 2 => 0}, prev: %{1 => 0, 2 => 1, 0 => 2}}

    {store, chain, {_a, b}} =
      circles
      |> Enum.drop(3)
      |> Enum.with_index(3)
      |> Enum.reduce({store, chain, {0, 1}}, fn {{_, _, r}, i}, {store, chain, {a, b}} ->
        {store, chain, a, b} = insert(store, chain, a, b, i, r)
        {store, chain, {a, b}}
      end)

    front = Enum.map([b | walk_chain(chain, b, b, [])], &store[&1])
    {ex, ey, er} = enclose(front)

    placed =
      Enum.map(0..(n - 1)//1, fn i ->
        {x, y, r} = store[i]
        {x - ex, y - ey, r}
      end)

    {placed, er}
  end

  # Place circle i tangent to the chain's a and b; if it intersects the chain, advance
  # the (a, b) pair past the offending circle and try again.
  defp insert(store, chain, a, b, i, r) do
    c = place(store[a], store[b], r)

    case first_intersection(store, chain, a, b, c) do
      {:ahead, j} ->
        chain = link(chain, a, j)
        insert(store, chain, a, j, i, r)

      {:behind, k} ->
        chain = link(chain, k, b)
        insert(store, chain, k, b, i, r)

      :none ->
        store = Map.put(store, i, c)
        chain = chain |> link(a, i) |> link(i, b)

        # The chain pair closest to the centroid becomes the next (a, b); d3 starts from
        # the old `a` and considers every chain node but the one just inserted.
        {best, _} =
          walk_chain(chain, i, i, [])
          |> Enum.reduce({a, score(store, chain, a)}, fn j, {best, best_score} ->
            s = score(store, chain, j)
            if s < best_score, do: {j, s}, else: {best, best_score}
          end)

        {store, chain, best, chain.next[best]}
    end
  end

  # d3's search along the front: forward from b and backward from a, choosing the side
  # with the shorter run of radii so far, until the two walks meet.
  defp first_intersection(store, chain, a, b, c) do
    {_, _, ra} = store[a]
    {_, _, rb} = store[b]
    search(store, chain, chain.next[b], chain.prev[a], rb, ra, c)
  end

  # One step of d3's do/while: test the nearer side, advance it, stop once j has passed k.
  defp search(store, chain, j, k, sj, sk, c) do
    if sj <= sk do
      if intersects?(store[j], c) do
        {:ahead, j}
      else
        {_, _, rj} = store[j]
        continue(store, chain, chain.next[j], k, sj + rj, sk, c)
      end
    else
      if intersects?(store[k], c) do
        {:behind, k}
      else
        {_, _, rk} = store[k]
        continue(store, chain, j, chain.prev[k], sj, sk + rk, c)
      end
    end
  end

  defp continue(store, chain, j, k, sj, sk, c) do
    if j == chain.next[k], do: :none, else: search(store, chain, j, k, sj, sk, c)
  end

  defp link(chain, a, b) do
    %{chain | next: Map.put(chain.next, a, b), prev: Map.put(chain.prev, b, a)}
  end

  defp walk_chain(chain, start, current, acc) do
    next = chain.next[current]
    if next == start, do: Enum.reverse(acc), else: walk_chain(chain, start, next, [next | acc])
  end

  # Distance from the origin of the weighted midpoint of a circle and its successor.
  defp score(store, chain, i) do
    {ax, ay, ar} = store[i]
    {bx, by, br} = store[chain.next[i]]
    ab = ar + br
    dx = (ax * br + bx * ar) / ab
    dy = (ay * br + by * ar) / ab
    dx * dx + dy * dy
  end

  # Position of a circle of radius r tangent to b and a, on the outer side of b -> a.
  defp place({bx, by, br}, {ax, ay, ar}, r) do
    dx = bx - ax
    dy = by - ay
    d2 = dx * dx + dy * dy

    if d2 > 0 do
      a2 = (ar + r) * (ar + r)
      b2 = (br + r) * (br + r)

      if a2 > b2 do
        x = (d2 + b2 - a2) / (2 * d2)
        y = :math.sqrt(max(0, b2 / d2 - x * x))
        {bx - x * dx - y * dy, by - x * dy + y * dx, r}
      else
        x = (d2 + a2 - b2) / (2 * d2)
        y = :math.sqrt(max(0, a2 / d2 - x * x))
        {ax + x * dx - y * dy, ay + x * dy + y * dx, r}
      end
    else
      {ax + r, ay, r}
    end
  end

  defp intersects?({ax, ay, ar}, {bx, by, br}) do
    dr = ar + br - 1.0e-6
    dx = bx - ax
    dy = by - ay
    dr > 0 and dr * dr > dx * dx + dy * dy
  end

  # ------------------------------------------------------------------
  # packEnclose: Welzl's algorithm. The shuffle that makes it expected-linear draws from
  # d3's own linear congruential generator, seeded constantly, so the result is fixed.
  # ------------------------------------------------------------------

  @doc false
  @spec enclose([{number(), number(), number()}]) :: {number(), number(), number()}
  def enclose([]), do: {0, 0, 0}

  def enclose(circles) do
    circles = shuffle(circles)
    welzl(circles, circles, [], nil)
  end

  defp welzl(_all, [], _basis, e), do: e

  defp welzl(all, [p | rest], basis, e) do
    if e && encloses_weak?(e, p) do
      welzl(all, rest, basis, e)
    else
      basis = extend_basis(basis, p)
      welzl(all, all, basis, enclose_basis(basis))
    end
  end

  defp extend_basis(basis, p) do
    cond do
      encloses_weak_all?(p, basis) ->
        [p]

      pair =
          Enum.find(
            basis,
            &(encloses_not?(p, &1) and encloses_weak_all?(enclose_basis2(&1, p), basis))
          ) ->
        [pair, p]

      true ->
        triple =
          for {bi, i} <- Enum.with_index(basis),
              {bj, j} <- Enum.with_index(basis),
              i < j,
              encloses_not?(enclose_basis2(bi, bj), p),
              encloses_not?(enclose_basis2(bi, p), bj),
              encloses_not?(enclose_basis2(bj, p), bi),
              encloses_weak_all?(enclose_basis3(bi, bj, p), basis),
              do: [bi, bj, p]

        hd(triple)
    end
  end

  defp encloses_not?({ax, ay, ar}, {bx, by, br}) do
    dr = ar - br
    dx = bx - ax
    dy = by - ay
    dr < 0 or dr * dr < dx * dx + dy * dy
  end

  defp encloses_weak?({ax, ay, ar}, {bx, by, br}) do
    dr = ar - br + max(max(ar, br), 1) * 1.0e-9
    dx = bx - ax
    dy = by - ay
    dr > 0 and dr * dr > dx * dx + dy * dy
  end

  defp encloses_weak_all?(a, basis), do: Enum.all?(basis, &encloses_weak?(a, &1))

  defp enclose_basis([a]), do: a
  defp enclose_basis([a, b]), do: enclose_basis2(a, b)
  defp enclose_basis([a, b, c]), do: enclose_basis3(a, b, c)

  defp enclose_basis2({x1, y1, r1}, {x2, y2, r2}) do
    x21 = x2 - x1
    y21 = y2 - y1
    r21 = r2 - r1
    l = :math.sqrt(x21 * x21 + y21 * y21)

    {(x1 + x2 + x21 / l * r21) / 2, (y1 + y2 + y21 / l * r21) / 2, (l + r1 + r2) / 2}
  end

  defp enclose_basis3({x1, y1, r1}, {x2, y2, r2}, {x3, y3, r3}) do
    a2 = x1 - x2
    a3 = x1 - x3
    b2 = y1 - y2
    b3 = y1 - y3
    c2 = r2 - r1
    c3 = r3 - r1
    d1 = x1 * x1 + y1 * y1 - r1 * r1
    d2 = d1 - x2 * x2 - y2 * y2 + r2 * r2
    d3 = d1 - x3 * x3 - y3 * y3 + r3 * r3
    ab = a3 * b2 - a2 * b3
    xa = (b2 * d3 - b3 * d2) / (ab * 2) - x1
    xb = (b3 * c2 - b2 * c3) / ab
    ya = (a3 * d2 - a2 * d3) / (ab * 2) - y1
    yb = (a2 * c3 - a3 * c2) / ab
    aa = xb * xb + yb * yb - 1
    bb = 2 * (r1 + xa * xb + ya * yb)
    cc = xa * xa + ya * ya - r1 * r1

    r =
      if abs(aa) > 1.0e-6,
        do: -((bb + :math.sqrt(bb * bb - 4 * aa * cc)) / (2 * aa)),
        else: -(cc / bb)

    {x1 + xa + xb * r, y1 + ya + yb * r, r}
  end

  # d3's lcg (a = 1664525, c = 1013904223, m = 2^32, seed 1) driving a Fisher–Yates shuffle.
  defp shuffle(list) do
    {shuffled, _seed} =
      Enum.reduce(length(list)..1//-1, {List.to_tuple(list), 1}, fn m, {tuple, seed} ->
        seed = rem(1_664_525 * seed + 1_013_904_223, 4_294_967_296)
        i = trunc(seed / 4_294_967_296 * m)
        {swap(tuple, m - 1, i), seed}
      end)

    Tuple.to_list(shuffled)
  end

  defp swap(tuple, i, j) do
    a = elem(tuple, i)
    b = elem(tuple, j)
    tuple |> put_elem(i, b) |> put_elem(j, a)
  end

  defp translate_and_scale(%Hierarchy{} = node, cx, cy, k) do
    new_x = cx + (node.x || 0) * k
    new_y = cy + (node.y || 0) * k
    new_r = (node.r || 0) * k

    new_children =
      case node.children do
        nil ->
          nil

        children ->
          Enum.map(children, fn child ->
            # Children are relative to parent
            child_x = new_x + (child.x || 0) * k
            child_y = new_y + (child.y || 0) * k
            translate_and_scale_child(child, child_x, child_y, k)
          end)
      end

    %{node | x: new_x, y: new_y, r: new_r, children: new_children}
  end

  defp translate_and_scale_child(%Hierarchy{} = node, x, y, k) do
    new_r = (node.r || 0) * k

    new_children =
      case node.children do
        nil ->
          nil

        children ->
          Enum.map(children, fn child ->
            child_x = x + (child.x || 0) * k
            child_y = y + (child.y || 0) * k
            translate_and_scale_child(child, child_x, child_y, k)
          end)
      end

    %{node | x: x, y: y, r: new_r, children: new_children}
  end
end
