# Layouts

**Status:** Implemented

This document specifies the layout algorithms under `Visualize.Layout`: the `Hierarchy` node structure shared by every hierarchical layout; the hierarchical layouts `Tree`, `Cluster`, `Pack`, `Partition` and `Treemap`; the relational layouts `Chord` and `Sankey`; and the force-directed system (`Force`, `Force.Forces`, `Force.Simulation`). Every layout is a pure function of a configuration struct and its input, with the exception of the force simulation, which additionally offers a GenServer that advances the same pure tick function on a timer. Coordinates are in user units (pixels unless stated otherwise); the y axis points down, as in SVG.

## 1. Hierarchy

`Visualize.Layout.Hierarchy` is the tree structure consumed by `Tree`, `Cluster`, `Pack`, `Partition` and `Treemap`. A hierarchy is an immutable tree of `%Hierarchy{}` structs; every operation returns a new root.

### 1.1 Node structure

| Field | Type | Meaning |
|---|---|---|
| `data` | `any()` | The datum the node was built from. |
| `parent` | `t() \| nil` | The parent node as it was when this node was built (see 1.1.1). `nil` for the root. |
| `children` | `[t()] \| nil` | Child nodes in input order. `nil` for a leaf; an empty list MUST be treated as a leaf wherever it occurs. |
| `depth` | `non_neg_integer()` | Distance from the root; the root has depth 0. |
| `height` | `non_neg_integer()` | Greatest distance to a descendant leaf; a leaf has height 0. |
| `value` | `number() \| nil` | Aggregate value set by `sum/2` or `count/1`; `nil` until then. |
| `id` | `any()` | `data[:id]`, else `data[:name]`, else `nil` (atom keys only). |
| `x`, `y` | `number() \| nil` | Position set by `Tree`, `Cluster` and `Pack`. |
| `x0`, `y0`, `x1`, `y1` | `number() \| nil` | Rectangle set by `Partition` and `Treemap`. |
| `r` | `number() \| nil` | Radius set by `Pack`. |

#### 1.1.1 Parent references

`parent` holds the parent struct as it existed at construction time: its `children` is `nil`, its `height` is `0`, and its `value` and layout fields are unset. Layouts and aggregations do not rewrite `parent` links. Consequently `ancestors/1` and `path/2` return construction-time snapshots, and two siblings always have structurally equal `parent` values, which is what the default separation functions of `Tree` and `Cluster` rely on.

### 1.2 Construction

`new/1` and `new/2` build a hierarchy from nested data.

| Option | Default | Meaning |
|---|---|---|
| `:children` | reads `:children`, else `"children"` | Function returning a node's child data, `nil` or `[]` for a leaf. |

`data` MUST be a map. An empty child list produces `children: nil`.

`stratify/1` and `stratify/2` build a hierarchy from a flat list of maps.

| Option | Default | Meaning |
|---|---|---|
| `:id` | reads `:id`, else `"id"` | Function returning a node's identifier. |
| `:parent_id` | reads `:parent`, `"parent"`, `:parent_id`, `"parent_id"` in that order | Function returning the parent identifier; `nil` or `""` marks the root. |

The root is the first datum (in list order) whose parent identifier is `nil` or `""`. If there is none, `stratify/2` raises `ArgumentError`. Children are attached in list order. A datum whose parent identifier names no datum is silently dropped. `stratify/2` MUST attach every datum reachable from the root regardless of the order in which parents and children appear in the input.

> Decision: see spec/13. The current implementation attaches a snapshot of each child taken at the time it is appended to its parent, so grandchildren listed after their parent are lost; for the input `[root, c1, c2, gc(parent: c2)]` the resulting tree has three nodes and height 1.

### 1.3 Aggregation

- `sum/2` sets every node's `value` to `value_fn.(node.data)` plus the sum of its children's values (post-order); `value_fn` is evaluated for internal nodes as well as leaves. A `nil` child value counts as 0.
- `count/1` sets every leaf's `value` to 1 and every internal node's `value` to its number of leaves.
- `sort/2` sorts the children of every node with `Enum.sort/2` using `comparator.(a, b)` (true when `a` sorts before `b`); leaves are returned unchanged.
- `copy/1` and `copy/2` rebuild the tree with fresh parent links, copying every field; when `transform` is given, `data` becomes `transform.(data)` on every node.

### 1.4 Traversal and queries

- `each/2` visits nodes in pre-order (parent before children) and returns `:ok`.
- `each_after/2` visits nodes in post-order and returns `:ok`.
- `descendants/1` returns the node followed by all descendants in pre-order.
- `ancestors/1` returns the parent, grandparent, and so on up to the root (root excluded from its own list; the root yields `[]`).
- `leaves/1` returns the descendants whose `children` is `nil` or `[]`, in pre-order.
- `links/1` returns `{parent, child}` tuples for every parent-child pair in pre-order of the parent.
- `path/2` MUST return the shortest path from `source` to `target`: `[source, ..., lca, ..., target]` where `lca` is the lowest common ancestor, each endpoint included once.

> Decision: see spec/13. The current implementation prefixes the result with every ancestor of the LCA down from the root and then appends the source-side and target-side chains; for two cousins `A1` and `B2` under `root` it returns `[root, A1, A, B, B2]` instead of `[A1, A, root, B, B2]`.

### 1.5 Functions

| Function | Contract |
|---|---|
| `Visualize.Layout.Hierarchy.new/1` | `new(data, [])`. |
| `Visualize.Layout.Hierarchy.new/2` | Builds a hierarchy from nested map data using the `:children` accessor (1.2). |
| `Visualize.Layout.Hierarchy.stratify/1` | `stratify(data, [])`. |
| `Visualize.Layout.Hierarchy.stratify/2` | Builds a hierarchy from a flat list using `:id` and `:parent_id` accessors (1.2); raises `ArgumentError` when no root exists. |
| `Visualize.Layout.Hierarchy.each/2` | Pre-order traversal; returns `:ok`. |
| `Visualize.Layout.Hierarchy.each_after/2` | Post-order traversal; returns `:ok`. |
| `Visualize.Layout.Hierarchy.descendants/1` | Node and all descendants, pre-order. |
| `Visualize.Layout.Hierarchy.ancestors/1` | Parent chain up to the root; `[]` for the root. |
| `Visualize.Layout.Hierarchy.leaves/1` | All leaves, pre-order. |
| `Visualize.Layout.Hierarchy.path/2` | Shortest path from source to target through their lowest common ancestor (1.4). |
| `Visualize.Layout.Hierarchy.links/1` | All `{parent, child}` pairs. |
| `Visualize.Layout.Hierarchy.sum/2` | Sets `value` to own value plus descendants' values. |
| `Visualize.Layout.Hierarchy.count/1` | Sets `value` to the number of leaves. |
| `Visualize.Layout.Hierarchy.sort/2` | Sorts children at every level with a boolean comparator. |
| `Visualize.Layout.Hierarchy.copy/1` | `copy(node, nil)`. |
| `Visualize.Layout.Hierarchy.copy/2` | Deep copy with fresh parent links, optionally transforming `data`. |

## 2. Tree and cluster

`Visualize.Layout.Tree` draws node-link diagrams; `Visualize.Layout.Cluster` draws dendrograms in which every leaf sits at the same depth. Both share one configuration shape.

### 2.1 Configuration

| Field | Default | Meaning |
|---|---|---|
| `size` | `nil` | `{width, height}` to scale the finished layout into. |
| `node_size` | `nil` | `{dx, dy}` fixed spacing per separation unit and per depth level. |
| `separation` | siblings 1, otherwise 2 | `fn a, b -> number end` giving the horizontal gap between adjacent nodes `a` and `b`. |

`new/0` sets only the default separation. `size/2` and `node_size/2` accept a two-element list or a 2-tuple, store a tuple, and each clears the other field: the two modes are mutually exclusive and the last one set wins. `separation/2` requires an arity-2 function.

With neither `size` nor `node_size`, coordinates are raw: `x` in separation units and `y` in depth levels. With `size`, `x` is normalised so the leftmost node is at 0 and the rightmost at `width`, and `y` so the root is at 0 and the deepest level at `height`; a zero extent maps to 0. With `node_size`, `x` and `y` are multiplied by `dx` and `dy` respectively without normalisation.

### 2.2 Tree.generate/2

`generate/2` sets `x` and `y` on every node and returns the new root. `y` is the node's depth (before scaling). `x` MUST be assigned by the Reingold–Tilford tidy-tree algorithm: children of one parent are placed left to right with the gap given by `separation`, each parent is centred over its children, and subtrees are shifted so that no two nodes at the same depth overlap while preserving the separation between adjacent subtrees.

> Decision: see spec/13. The current implementation positions every child list starting at local `x = 0` and never accumulates the parent offset in its second pass, so cousin subtrees overlap: for `root -> [A -> [A1, A2], B -> [B1, B2]]` it produces `A1 = B1 = 0` and `A2 = B2 = 1`.

### 2.3 Cluster.generate/2

`generate/2` positions all leaves first, left to right in pre-order, at `x = 0, s1, s1 + s2, ...` where each `s` is `separation.(leaf, previous_leaf)`. Every internal node is placed at the midpoint of its first and last child. `y` is `root.height` for every leaf and `depth` for every internal node, so all leaves share the bottom row. Scaling then applies as in 2.1. Leaves are matched to their positions by `{data, depth}`; two leaves with equal data at the same depth share a position.

### 2.4 Functions

| Function | Contract |
|---|---|
| `Visualize.Layout.Tree.new/0` | Creates a tree layout with no size, no node size and the default separation. |
| `Visualize.Layout.Tree.size/2` | Sets `size` from a list or tuple and clears `node_size`. |
| `Visualize.Layout.Tree.node_size/2` | Sets `node_size` from a list or tuple and clears `size`. |
| `Visualize.Layout.Tree.separation/2` | Sets the arity-2 separation function. |
| `Visualize.Layout.Tree.generate/2` | Sets `x` and `y` on every node of the hierarchy (2.2). |
| `Visualize.Layout.Cluster.new/0` | Creates a cluster layout with no size, no node size and the default separation. |
| `Visualize.Layout.Cluster.size/2` | Sets `size` from a list or tuple and clears `node_size`. |
| `Visualize.Layout.Cluster.node_size/2` | Sets `node_size` from a list or tuple and clears `size`. |
| `Visualize.Layout.Cluster.separation/2` | Sets the arity-2 separation function, applied between consecutive leaves. |
| `Visualize.Layout.Cluster.generate/2` | Sets `x` and `y` with all leaves at the same depth (2.3). |

## 3. Pack

`Visualize.Layout.Pack` places every node as a circle: leaves sized by value, internal nodes enclosing their children.

### 3.1 Configuration

| Field | Default | Meaning |
|---|---|---|
| `size` | `{1, 1}` | `{width, height}` of the target area. |
| `padding` | `0` | Number, or `fn node -> number end` evaluated on each internal node. |
| `radius` | `nil` | `fn leaf -> number end`; when `nil`, a leaf's radius is `sqrt(value)`, or 1 when `value` is `nil`. |

`size/2` accepts a list or tuple. `radius/2` requires an arity-1 function.

### 3.2 Algorithm

`generate/2` expects `value` to have been set (by `sum/2` or `count/1`) unless `radius` is given. Siblings are packed bottom-up: the children of a node are sorted by descending radius; the first is placed at the origin, the second tangent to its right, and each further circle at the candidate position tangent to some pair of already placed circles that is closest to the origin and overlaps none of them. Sibling circles are separated by `2 * padding` (each circle is inflated by `padding`). When no tangent candidate is free the circle is placed on the enclosing circle of the placed set at a random angle drawn from `:rand`; such layouts are not reproducible.

The enclosing circle of a set of siblings is centred on the middle of their bounding box with radius equal to the greatest centre distance plus that circle's radius; it is not the minimal enclosing circle (`enclose_circles` in `lib/visualize/layout/pack.ex`). The parent's radius is that radius plus `padding`. Children are stored relative to the parent's centre until the final pass.

Finally the root is scaled by `k = min(width, height) / (2 * root.r)` and centred at `{width / 2, height / 2}`; every `x`, `y` and `r` is multiplied by `k` and positions are made absolute. A root with radius 0 (or `nil`) is returned without scaling and with leaf positions unset.

### 3.3 Functions

| Function | Contract |
|---|---|
| `Visualize.Layout.Pack.new/0` | Creates a pack layout with size `{1, 1}`, padding 0 and no radius function. |
| `Visualize.Layout.Pack.size/2` | Sets `size` from a list or tuple. |
| `Visualize.Layout.Pack.padding/2` | Sets a numeric or per-node padding. |
| `Visualize.Layout.Pack.radius/2` | Sets the arity-1 leaf radius function. |
| `Visualize.Layout.Pack.generate/2` | Sets `x`, `y` (centre) and `r` on every node (3.2). |

## 4. Partition

`Visualize.Layout.Partition` produces adjacency diagrams (icicles; sunbursts when `size` is `{2π, radius}` and `x0`/`x1` are read as angles in radians).

### 4.1 Configuration

| Field | Default | Meaning |
|---|---|---|
| `size` | `{1, 1}` | `{width, height}`; each depth level receives `height / (root.height + 1)`. |
| `padding` | `0` | Horizontal gap between adjacent siblings, in the units of `width`. |
| `round?` | `false` | When true, `x0`, `y0`, `x1`, `y1` are rounded with `Kernel.round/1`. |

### 4.2 Algorithm

The root occupies `x0 = 0`, `x1 = width`, `y0 = 0`, `y1 = dy`. Each child of a node receives a share of the parent's horizontal extent, minus `padding * (n - 1)`, proportional to `child.value / sum(children values)`, laid left to right in child order, one level lower. A node with no child of positive value keeps its rectangle and its children untouched. Children whose `value` is `nil` or not greater than 0 MUST be retained in the output with a zero-width rectangle at the position they would occupy.

> Decision: see spec/13. The current implementation filters such children out of the parent's `children` list, so they and their subtrees disappear from the returned hierarchy.

### 4.3 Functions

| Function | Contract |
|---|---|
| `Visualize.Layout.Partition.new/0` | Creates a partition layout with size `{1, 1}`, padding 0 and rounding off. |
| `Visualize.Layout.Partition.size/2` | Sets `size` from a list or tuple. |
| `Visualize.Layout.Partition.padding/2` | Sets the numeric sibling gap. |
| `Visualize.Layout.Partition.round/2` | Enables or disables integer rounding of rectangle coordinates. |
| `Visualize.Layout.Partition.generate/2` | Sets `x0`, `y0`, `x1`, `y1` on every node (4.2). |

## 5. Treemap

`Visualize.Layout.Treemap` nests rectangles whose areas are proportional to `value`.

### 5.1 Configuration

| Field | Default | Meaning |
|---|---|---|
| `size` | `{1, 1}` | `{width, height}` of the root rectangle. |
| `tile` | `:squarify` | One of `:squarify`, `:binary`, `:slice`, `:dice`, `:slice_dice`. |
| `padding` | `0` | Outer padding applied on all four sides of every node before tiling its children. |
| `padding_top`, `padding_right`, `padding_bottom`, `padding_left` | `nil` | Per-side overrides of `padding` when not `nil`. |
| `padding_inner` | `nil` | Gap between sibling tiles: each tile is inset by `padding_inner / 2` on every side (so tiles on the edge of the parent are also inset). `nil` means 0. |
| `round?` | `false` | When true, rectangle coordinates are rounded with `Kernel.round/1`. |

`tile/2` rejects any atom outside the five listed. `padding/2` requires a number.

### 5.2 Algorithm

The root receives `x0 = 0`, `y0 = 0`, `x1 = width`, `y1 = height`. For every node with children the inner rectangle is the node's rectangle shrunk by the four paddings; if it is empty the children are left unpositioned. Children with a positive `value` are tiled into the inner rectangle by the selected algorithm, then laid out recursively. Children whose `value` is `nil` or not greater than 0 MUST be retained with a zero-area rectangle.

> Decision: see spec/13. The current implementation drops such children (and their subtrees) from the returned hierarchy, as `Partition` does.

Tiling algorithms, with `children` in input order and areas scaled so the total equals the inner rectangle's area:

- `:squarify` — rows are filled greedily along the shorter side of the remaining rectangle (a row across the top when the rectangle is taller than wide, otherwise down the left); a child is added to the current row while the worst aspect ratio in the row does not increase.
- `:binary` — children are split into a prefix and suffix whose value sums are as close to equal as possible (cumulative, in order); the split is horizontal (along x) when the rectangle is wider than tall and vertical otherwise, with the split position proportional to the prefix's share; each part is tiled recursively.
- `:slice` — children are stacked top to bottom, each taking the full width and a height proportional to its value.
- `:dice` — children are placed left to right, each taking the full height and a width proportional to its value.
- `:slice_dice` — `:slice` when the children's `depth` is even, `:dice` when odd.

### 5.3 Functions

| Function | Contract |
|---|---|
| `Visualize.Layout.Treemap.new/0` | Creates a treemap with size `{1, 1}`, `:squarify` tiling, zero padding and rounding off. |
| `Visualize.Layout.Treemap.size/2` | Sets `size` from a list or tuple. |
| `Visualize.Layout.Treemap.tile/2` | Sets the tiling algorithm; only the five listed atoms are accepted. |
| `Visualize.Layout.Treemap.padding/2` | Sets the uniform outer padding. |
| `Visualize.Layout.Treemap.padding_inner/2` | Sets the sibling gap. |
| `Visualize.Layout.Treemap.padding_top/2` | Overrides the top outer padding. |
| `Visualize.Layout.Treemap.padding_right/2` | Overrides the right outer padding. |
| `Visualize.Layout.Treemap.padding_bottom/2` | Overrides the bottom outer padding. |
| `Visualize.Layout.Treemap.padding_left/2` | Overrides the left outer padding. |
| `Visualize.Layout.Treemap.round/2` | Enables or disables integer rounding. |
| `Visualize.Layout.Treemap.generate/2` | Sets `x0`, `y0`, `x1`, `y1` on every node (5.2). |

## 6. Chord

`Visualize.Layout.Chord` lays out a square flow matrix as arcs on a circle with ribbons between them.

### 6.1 Configuration

| Field | Default | Meaning |
|---|---|---|
| `pad_angle` | `0` | Gap between consecutive groups, radians. |
| `sort_groups` | `nil` | `fn %{value: a}, %{value: b} -> boolean end` ordering groups around the circle; receives maps holding only `:value`, the group's row sum plus column sum. |
| `sort_subgroups` | `nil` | `fn a, b -> boolean end` ordering the entries within a group's arc by their numeric values. |
| `sort_chords` | `nil` | `fn chord, chord -> boolean end` ordering the returned chord list. |

### 6.2 Input and output

`generate/2` takes `matrix`, a list of `n` rows of `n` numbers where `matrix[i][j]` is the flow from group `i` to group `j`, and returns `%{groups: [group], chords: [chord]}`; an empty matrix yields empty lists.

Angles are in radians, measured clockwise from 12 o'clock (a point at angle `a` and radius `r` is at `{r * sin(a), -r * cos(a)}`). With `total` the sum of all matrix entries, each unit of value spans `k = (2π - n * pad_angle) / total` radians (0 when `total` is 0). Groups are laid out consecutively in sorted order (input order when `sort_groups` is `nil`), each spanning `row_sum * k` followed by `pad_angle`.

A group is `%{index, start_angle, end_angle, value}` with `value` the row sum. Within group `i`, entry `j` occupies a subgroup arc of `matrix[i][j] * k` radians, in column order or in `sort_subgroups` order.

One chord is produced for every pair `i <= j` with `matrix[i][j] > 0` or `matrix[j][i] > 0`, in row-major order: `%{source: %{index: i, start_angle, end_angle, value: matrix[i][j]}, target: %{index: j, start_angle, end_angle, value: matrix[j][i]}}`, where each end's angles are the subgroup arc of the other index within its group. When `i == j` the chord is a self-loop.

### 6.3 Path generators

`arc_path/3` returns an SVG path for a group between `inner_radius` and `outer_radius`, centred on the origin: an inner arc from start to end angle (sweep 1), a line to the outer end point, the outer arc back (sweep 0), then `Z`. The large-arc flag is set when the span exceeds π.

`ribbon_path/2` returns an SVG path for a chord at `radius`: the source arc, a quadratic curve through the origin to the target arc's start, the target arc, a quadratic curve through the origin back to the source start, then `Z`. A self-loop draws the source arc and a single quadratic return.

### 6.4 Functions

| Function | Contract |
|---|---|
| `Visualize.Layout.Chord.new/0` | Creates a chord layout with `pad_angle` 0 and no sort functions. |
| `Visualize.Layout.Chord.pad_angle/2` | Sets the inter-group gap in radians; requires a number. |
| `Visualize.Layout.Chord.sort_groups/2` | Sets or clears the group comparator. |
| `Visualize.Layout.Chord.sort_subgroups/2` | Sets or clears the subgroup value comparator. |
| `Visualize.Layout.Chord.sort_chords/2` | Sets or clears the chord comparator. |
| `Visualize.Layout.Chord.generate/2` | Computes `%{groups, chords}` from a square matrix (6.2). |
| `Visualize.Layout.Chord.arc_path/3` | SVG path for a group annulus sector (6.3). |
| `Visualize.Layout.Chord.ribbon_path/2` | SVG path for a chord ribbon at a radius (6.3). |

## 7. Sankey

`Visualize.Layout.Sankey` positions the nodes and links of a directed weighted graph as a flow diagram.

### 7.1 Configuration

| Field | Default | Meaning |
|---|---|---|
| `width`, `height` | `400`, `300` | Diagram size. |
| `node_width` | `24` | Horizontal extent of every node. |
| `node_padding` | `8` | Vertical gap between nodes in the same layer. |
| `iterations` | `6` | Number of vertical relaxation passes. |
| `node_align` | `:justify` | One of `:left`, `:right`, `:center`, `:justify`. |
| `link_sort` | `nil` | `fn link, link -> boolean end`; accepted and stored but not consulted by `compute/3`. |
| `nodes`, `links` | `[]` | Output of `compute/3`. |

### 7.2 Input

`compute(sankey, nodes, links)` takes `nodes` as maps with a required `:id` (any term) and `links` as maps with required `:source` and `:target` node identifiers and a numeric `:value`. Extra keys are preserved.

### 7.3 Algorithm

Every node's `value` is the greater of its total outgoing and total incoming link value. Layers are assigned by breadth-first traversal from the nodes with no incoming link: a node's layer is one more than the greatest layer among its already-assigned sources at the time it is first reached, and 0 for a source. Nodes unreachable from a source (cycles, isolated nodes) receive layer 0.

Horizontal position: with `L` the greatest layer and `xs = (width - node_width) / L` (0 when `L` is 0), `x0` is `layer * xs` for `:left`; `width - node_width - layer * xs` for `:right`; `x1 = x0 + node_width`. `:justify` MUST place every node without outgoing links in layer `L` and every other node at its layer. `:center` MUST place a node with incoming links at its layer, a node with only outgoing links one layer before its earliest target, and an isolated node at layer 0.

> Decision: see spec/13. The current implementation makes `:justify` identical to `:left` and places every node at `x0 = (width - node_width) / 2` under `:center`, collapsing the diagram into one column.

Vertical position: within each layer, nodes are stacked in input order with heights `value * (height - (n - 1) * node_padding) / layer_total`, so every layer initially fills the full height. Then `iterations` relaxation passes move each node's centre to the value-weighted mean of its neighbours' centres, clamp it to the diagram, push overlapping nodes down in `y0` order, and, if the column overflows, rescale the layer's node heights to fit.

Links: with one global scale `(height - (max_nodes_in_a_layer - 1) * node_padding) / max_layer_total`, each link's `width` is `max(1, value * scale)`. Links are assigned in input order; `y0` is the running offset from the top of the source node and `y1` the running offset from the top of the target node. Each link receives `source_node`, `target_node` (position snapshots), `source_index`, `target_index`, `y0`, `y1`, `width` and `path`. A link naming an unknown node keeps `width` 0 and `path` `nil`.

Output nodes carry their input keys plus `index`, `layer`, `value`, `source_links`, `target_links` (the raw input links), `x0`, `x1`, `y0`, `y1`.

### 7.4 Paths

`generate_link_path/1` draws, for a link with `source_node`, `target_node`, `y0`, `y1`, `width`: move to `{source.x1, y0}`, cubic curve to `{target.x0, y1}` with both control points at the midpoint x, line down by `width`, cubic curve back, `Z`. Any other map yields `""`. `link_path/1` returns the link's `path` when it is a binary, else `generate_link_path/1`. `link_paths/1` maps `link_path/1` over `sankey.links`. `nodes_by_layer/1` returns the nodes grouped into lists by ascending layer.

### 7.5 Functions

| Function | Contract |
|---|---|
| `Visualize.Layout.Sankey.new/0` | Creates a layout with the defaults of 7.1. |
| `Visualize.Layout.Sankey.size/3` | Sets `width` and `height`. |
| `Visualize.Layout.Sankey.node_width/2` | Sets `node_width`. |
| `Visualize.Layout.Sankey.node_padding/2` | Sets `node_padding`. |
| `Visualize.Layout.Sankey.iterations/2` | Sets the relaxation pass count. |
| `Visualize.Layout.Sankey.node_align/2` | Sets the alignment atom. |
| `Visualize.Layout.Sankey.link_sort/2` | Stores a link comparator (not applied by `compute/3`). |
| `Visualize.Layout.Sankey.compute/3` | Computes node and link positions; returns the layout with `nodes` and `links` filled (7.3). |
| `Visualize.Layout.Sankey.link_path/1` | The link's stored path, else a freshly generated one. |
| `Visualize.Layout.Sankey.link_paths/1` | Paths for every link of a computed layout. |
| `Visualize.Layout.Sankey.generate_link_path/1` | Cubic-Bezier ribbon path for a positioned link; `""` otherwise (7.4). |
| `Visualize.Layout.Sankey.nodes_by_layer/1` | Nodes grouped by ascending layer. |

## 8. Force

The force system positions graph nodes by simulated physics. `Visualize.Layout.Force` is the public facade: `run/1` computes a layout synchronously, and every other function delegates to `Visualize.Layout.Force.Simulation`, a GenServer. `Visualize.Layout.Force.Forces` holds the pure force functions used by both.

### 8.1 Nodes and links

A node is a map with a required `:id`. `initialize_nodes` (in both `run/1` and the GenServer) fills in, without overwriting existing keys: `x`, `y` from a phyllotaxis spiral (`radius = sqrt(0.5 + i) * 10`, `angle = i * π * (3 - sqrt(5))` for the node's index `i`), `vx = 0`, `vy = 0`, `fx = nil`, `fy = nil`. A non-`nil` `fx` (`fy`) pins the node's x (y) and zeroes the corresponding velocity at integration time.

A link is a map with `:source` and `:target` holding node ids (or maps with an `:id`), and optional `:distance` and `:strength` overriding the link force's defaults for that link.

Integration: after all forces have been applied, each free coordinate is updated as `v = v * velocity_decay; p = p + v`. `velocity_decay` is therefore the fraction of velocity retained per tick (0.4 by default), not the fraction removed.

### 8.2 Forces

`forces` is a list of `{type, opts}` tuples applied in order each tick; `Forces.apply/5` dispatches on `type` and raises `CaseClauseError` for any other atom. `alpha` is the simulation temperature.

| Type | Option | Default | Effect |
|---|---|---|---|
| `:center` | `:x`, `:y` | `0`, `0` | Translates every node's position (not velocity) so the mean position moves toward `{x, y}` by `strength`; ignores `alpha`. |
| | `:strength` | `1` | |
| `:many_body` | `:strength` | `-30` | Every pair is evaluated directly, O(n²) per tick, with no Barnes–Hut approximation. For each other node at distance `d`, `v += (other - node) * strength * alpha / d²`; negative strength repels. |
| | `:distance_min` | `1` | `d` is clamped to at least this value. |
| | `:distance_max` | `:infinity` | Pairs at `d >= distance_max` are skipped. |
| `:link` | `:distance` | `30` | Target length. |
| | `:strength` | `1` | Spring stiffness. |
| | `:iterations` | `1` | Passes per tick. Per link, with `d` the distance between `pos + vel` of the endpoints, `k = (d - distance) / d * alpha * strength`; the full displacement `delta * k` is added to the source velocity and subtracted from the target velocity. Links whose endpoints are not found are ignored. |
| `:collision` | `:radius` | `10` | Number or `fn node -> number end`. |
| | `:strength` | `1` | |
| | `:iterations` | `1` | Passes per tick. For each overlapping pair (distance less than the sum of radii) the pair MUST be pushed apart along its axis, each node by half of `(r - d) / d * strength * alpha`. |
| `:x` | `:x` | `0` | Number or `fn node -> number end`; `vx += (target - x) * strength * alpha`. |
| | `:strength` | `0.1` | |
| `:y` | `:y` | `0` | Number or function; `vy += (target - y) * strength * alpha`. |
| | `:strength` | `0.1` | |
| `:radial` | `:radius` | `100` | Number or function; `v += (node - centre) * (radius - d) / d * strength * alpha`. |
| | `:x`, `:y` | `0`, `0` | Circle centre. |
| | `:strength` | `0.1` | |

> Decision: see spec/13. The current collision force iterates ordered pairs `i < j` and applies the (halved) displacement only to node `i`; node `j` is never pushed, so the force is asymmetric.

The default force list, used when `:forces` is absent, is `[{:center, x: 0, y: 0}, {:many_body, strength: -30}, {:link, distance: 30}]`.

### 8.3 Synchronous run

`Force.run/1` accepts a keyword list:

| Option | Default | Meaning |
|---|---|---|
| `:nodes` | required | Node maps (8.1). |
| `:links` | `[]` | Link maps. |
| `:forces` | default list | Force configuration (8.2). |
| `:iterations` | `300` | Maximum ticks. |

It fixes `alpha = 1.0`, `alpha_min = 0.001`, `velocity_decay = 0.4` and `alpha_decay = 1 - alpha_min^(1 / iterations)`. Each tick first sets `alpha = alpha * (1 - alpha_decay)`, then applies the forces and integrates; the loop halts before a tick when `alpha < alpha_min` or after `iterations` ticks. It returns `%{nodes: nodes, links: links}` with the input links unchanged.

### 8.4 Simulation GenServer

`Simulation.start_link/1` starts an unnamed GenServer with these options:

| Option | Default | Meaning |
|---|---|---|
| `:nodes` | `[]` | Node maps (8.1). |
| `:links` | `[]` | Link maps. |
| `:forces` | default list | Force configuration. |
| `:alpha` | `1.0` | Initial temperature. |
| `:alpha_min` | `0.001` | The simulation stops when `alpha` falls below this. |
| `:alpha_decay` | `0.0228` | Per-tick approach rate toward `alpha_target` (about 300 ticks to cool). |
| `:alpha_target` | `0` | Value `alpha` converges to. |
| `:velocity_decay` | `0.4` | Velocity retained per tick (8.1). |
| `:auto_start` | `true` | When true the server sends itself `:start_simulation` from `init/1`, which arms the first tick. |

The tick interval is 16 ms. A tick computes `alpha = alpha + (alpha_target - alpha) * alpha_decay`, applies the forces, integrates, and sends every subscriber `{:force_tick, %{nodes: nodes, links: links}}` where `nodes` carry the updated positions and `links` are the stored (unresolved) link maps. After a timer-driven tick the server re-arms the timer if `alpha >= alpha_min`, otherwise it clears `running`.

Client functions: `start/1`, `stop/1`, `restart/1`, `tick/1`, `set_nodes/2`, `set_links/2`, `set_alpha/2`, `set_alpha_target/2`, `fix_node/4`, `unfix_node/2`, `subscribe/2` and `unsubscribe/2` are casts returning `:ok`; `nodes/1`, `links/1` and `alpha/1` are calls. `links/1` returns the links with `:source` and `:target` replaced by the matching node maps (unmatched ids are left as they are). `set_nodes/2` re-runs node initialisation. `tick/1` advances one step regardless of whether the simulation is running and does not touch the timer. `subscribe/2` monitors the subscriber and removes it when it exits. `restart/1` resets `alpha` to 1.0.

### 8.5 State machine

The server state holds `running :: boolean()` and `tick_ref :: reference() | nil`. The following invariants MUST hold after every message:

1. `running` is true if and only if a tick timer is armed (`tick_ref` is non-`nil`).
2. At most one tick timer is armed at any time.
3. `alpha` lies in `[0, 1]`.
4. A timer-driven tick that leaves `alpha < alpha_min` stops the simulation; in steady state this occurs if and only if `alpha_target < alpha_min`, so a target at or above `alpha_min` keeps the simulation running until `stop/1`.
5. `start/1` on a running simulation is a no-op; `stop/1` cancels the timer and clears `running`.
6. `restart/1` on a stopped simulation MUST NOT start it: it resets `alpha` and re-arms the timer only when `running` is already true.

> Decision: see spec/13. Two invariants are currently violable: `handle_info(:start_simulation)` arms a timer and sets `running` without checking whether one is already armed (it is enqueued from `init/1` ahead of any client message, so the overlap is not reachable today, but the guard is absent), and `handle_cast(:restart)` cancels any timer, arms a new one and sets `running: true` unconditionally, so a stopped simulation is started by `restart/1`. In addition `set_alpha/2` and `set_alpha_target/2` do not validate their argument, so invariant 3 can be broken by a client. An ExTLA model (issue #5) will verify these invariants.

### 8.6 Functions

| Function | Contract |
|---|---|
| `Visualize.Layout.Force.run/1` | Synchronously simulates to equilibrium; returns `%{nodes, links}` (8.3). |
| `Visualize.Layout.Force.start_link/1` | Delegates to `Simulation.start_link/1`. |
| `Visualize.Layout.Force.start/1` | Delegates to `Simulation.start/1`. |
| `Visualize.Layout.Force.stop/1` | Delegates to `Simulation.stop/1`. |
| `Visualize.Layout.Force.restart/1` | Delegates to `Simulation.restart/1`. |
| `Visualize.Layout.Force.tick/1` | Delegates to `Simulation.tick/1`. |
| `Visualize.Layout.Force.nodes/1` | Delegates to `Simulation.nodes/1`. |
| `Visualize.Layout.Force.links/1` | Delegates to `Simulation.links/1`. |
| `Visualize.Layout.Force.set_nodes/2` | Delegates to `Simulation.set_nodes/2`. |
| `Visualize.Layout.Force.set_links/2` | Delegates to `Simulation.set_links/2`. |
| `Visualize.Layout.Force.alpha/1` | Delegates to `Simulation.alpha/1`. |
| `Visualize.Layout.Force.set_alpha/2` | Delegates to `Simulation.set_alpha/2`. |
| `Visualize.Layout.Force.set_alpha_target/2` | Delegates to `Simulation.set_alpha_target/2`. |
| `Visualize.Layout.Force.fix_node/4` | Delegates to `Simulation.fix_node/4`. |
| `Visualize.Layout.Force.unfix_node/2` | Delegates to `Simulation.unfix_node/2`. |
| `Visualize.Layout.Force.subscribe/2` | Delegates to `Simulation.subscribe/2`. |
| `Visualize.Layout.Force.unsubscribe/2` | Delegates to `Simulation.unsubscribe/2`. |
| `Visualize.Layout.Force.Forces.apply/5` | `apply(type, nodes, links, alpha, opts)`; dispatches to the force named by `type` (8.2). |
| `Visualize.Layout.Force.Forces.apply_center/3` | `apply_center(nodes, alpha, opts)`: recentres positions. |
| `Visualize.Layout.Force.Forces.apply_many_body/3` | `apply_many_body(nodes, alpha, opts)`: pairwise charge, O(n²). |
| `Visualize.Layout.Force.Forces.apply_link/4` | `apply_link(nodes, links, alpha, opts)`: spring constraints. |
| `Visualize.Layout.Force.Forces.apply_collision/3` | `apply_collision(nodes, alpha, opts)`: separates overlapping circles. |
| `Visualize.Layout.Force.Forces.apply_x/3` | `apply_x(nodes, alpha, opts)`: attracts toward an x. |
| `Visualize.Layout.Force.Forces.apply_y/3` | `apply_y(nodes, alpha, opts)`: attracts toward a y. |
| `Visualize.Layout.Force.Forces.apply_radial/3` | `apply_radial(nodes, alpha, opts)`: attracts toward a circle. |
| `Visualize.Layout.Force.Simulation.start_link/1` | Starts the GenServer with the options of 8.4. |
| `Visualize.Layout.Force.Simulation.child_spec/1` | Supervisor child specification wrapping `start_link/1`. |
| `Visualize.Layout.Force.Simulation.start/1` | Arms the tick timer if not running. |
| `Visualize.Layout.Force.Simulation.stop/1` | Cancels the timer and clears `running`. |
| `Visualize.Layout.Force.Simulation.restart/1` | Resets `alpha` to 1.0 and re-arms the timer of a running simulation (8.5). |
| `Visualize.Layout.Force.Simulation.tick/1` | Advances one tick immediately, independent of the timer. |
| `Visualize.Layout.Force.Simulation.nodes/1` | Returns the current node maps. |
| `Visualize.Layout.Force.Simulation.links/1` | Returns links with `source`/`target` resolved to node maps. |
| `Visualize.Layout.Force.Simulation.set_nodes/2` | Replaces and re-initialises the nodes. |
| `Visualize.Layout.Force.Simulation.set_links/2` | Replaces the links. |
| `Visualize.Layout.Force.Simulation.alpha/1` | Returns the current `alpha`. |
| `Visualize.Layout.Force.Simulation.set_alpha/2` | Sets `alpha`; MUST be within `[0, 1]`. |
| `Visualize.Layout.Force.Simulation.set_alpha_target/2` | Sets `alpha_target`; MUST be within `[0, 1]`. |
| `Visualize.Layout.Force.Simulation.fix_node/4` | Sets `fx`, `fy` on the node with the given id. |
| `Visualize.Layout.Force.Simulation.unfix_node/2` | Clears `fx`, `fy` on the node with the given id. |
| `Visualize.Layout.Force.Simulation.subscribe/2` | Adds and monitors a subscriber pid. |
| `Visualize.Layout.Force.Simulation.unsubscribe/2` | Removes a subscriber pid. |
