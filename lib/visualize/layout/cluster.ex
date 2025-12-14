defmodule Visualize.Layout.Cluster do
  @moduledoc """
  Cluster layout algorithm for dendrogram visualizations.

  Similar to the tree layout, but all leaves are placed at the same depth,
  creating a dendrogram effect useful for hierarchical clustering visualizations.

  ## Examples

      data = %{
        name: "root",
        children: [
          %{name: "A", children: [%{name: "A1"}, %{name: "A2"}]},
          %{name: "B", children: [%{name: "B1"}, %{name: "B2"}, %{name: "B3"}]}
        ]
      }

      root = Visualize.Layout.Hierarchy.new(data)

      cluster = Visualize.Layout.Cluster.new()
        |> Visualize.Layout.Cluster.size([400, 200])

      positioned = Visualize.Layout.Cluster.generate(cluster, root)

  """

  alias Visualize.Layout.Hierarchy

  defstruct size: nil,
            node_size: nil,
            separation: nil

  @type t :: %__MODULE__{
          size: {number(), number()} | nil,
          node_size: {number(), number()} | nil,
          separation: (Hierarchy.t(), Hierarchy.t() -> number()) | nil
        }

  @doc "Creates a new cluster layout"
  @spec new() :: t()
  def new do
    %__MODULE__{
      separation: &default_separation/2
    }
  end

  @doc """
  Sets the size of the layout.

  The cluster will be scaled to fit within [width, height].
  """
  @spec size(t(), [number()] | {number(), number()}) :: t()
  def size(%__MODULE__{} = cluster, [width, height]) do
    %{cluster | size: {width, height}, node_size: nil}
  end

  def size(%__MODULE__{} = cluster, {width, height}) do
    %{cluster | size: {width, height}, node_size: nil}
  end

  @doc """
  Sets the fixed node size.

  Unlike size/2, this sets a fixed spacing between nodes.
  """
  @spec node_size(t(), [number()] | {number(), number()}) :: t()
  def node_size(%__MODULE__{} = cluster, [dx, dy]) do
    %{cluster | node_size: {dx, dy}, size: nil}
  end

  def node_size(%__MODULE__{} = cluster, {dx, dy}) do
    %{cluster | node_size: {dx, dy}, size: nil}
  end

  @doc """
  Sets the separation function between nodes.

  The function receives two leaf nodes and returns the desired separation.
  """
  @spec separation(t(), (Hierarchy.t(), Hierarchy.t() -> number())) :: t()
  def separation(%__MODULE__{} = cluster, func) when is_function(func, 2) do
    %{cluster | separation: func}
  end

  @doc """
  Generates the cluster layout, positioning all nodes.

  Unlike tree layout, all leaves are placed at the same y coordinate.
  """
  @spec generate(t(), Hierarchy.t()) :: Hierarchy.t()
  def generate(%__MODULE__{} = cluster, %Hierarchy{} = root) do
    # Get all leaves
    leaves = Hierarchy.leaves(root)

    # Position leaves with separation
    positioned_leaves = position_leaves(leaves, cluster.separation)

    # Create a map of leaf positions
    leaf_positions = Map.new(positioned_leaves, fn leaf -> {leaf_id(leaf), leaf.x} end)

    # Position internal nodes as midpoint of their children
    root_positioned = position_internal_nodes(root, leaf_positions)

    # Set y based on depth, with leaves at max depth
    max_depth = root.height
    root_with_y = set_y_coordinates(root_positioned, max_depth)

    # Scale to fit size if specified
    scale_to_size(root_with_y, cluster)
  end

  defp position_leaves(leaves, separation) do
    case leaves do
      [] -> []
      [first | rest] ->
        first = %{first | x: 0}

        {positioned, _} =
          Enum.map_reduce(rest, first, fn leaf, prev ->
            spacing = separation.(leaf, prev)
            new_x = prev.x + spacing
            new_leaf = %{leaf | x: new_x}
            {new_leaf, new_leaf}
          end)

        [first | positioned]
    end
  end

  defp leaf_id(leaf) do
    # Create a unique identifier for the leaf
    {leaf.data, leaf.depth}
  end

  defp position_internal_nodes(%Hierarchy{children: nil} = node, leaf_positions) do
    x = Map.get(leaf_positions, leaf_id(node), 0)
    %{node | x: x}
  end

  defp position_internal_nodes(%Hierarchy{children: []} = node, leaf_positions) do
    x = Map.get(leaf_positions, leaf_id(node), 0)
    %{node | x: x}
  end

  defp position_internal_nodes(%Hierarchy{children: children} = node, leaf_positions) do
    # First position all children
    positioned_children = Enum.map(children, &position_internal_nodes(&1, leaf_positions))

    # Node's x is midpoint of first and last child
    first_child = hd(positioned_children)
    last_child = List.last(positioned_children)
    midpoint = (first_child.x + last_child.x) / 2

    %{node | children: positioned_children, x: midpoint}
  end

  defp set_y_coordinates(%Hierarchy{} = node, max_depth) do
    # For cluster layout, leaves are at max_depth, internal nodes at their depth
    y = if is_nil(node.children) or node.children == [] do
      max_depth
    else
      node.depth
    end

    new_children =
      case node.children do
        nil -> nil
        children -> Enum.map(children, &set_y_coordinates(&1, max_depth))
      end

    %{node | y: y, children: new_children}
  end

  defp scale_to_size(root, %__MODULE__{size: nil, node_size: nil}) do
    root
  end

  defp scale_to_size(root, %__MODULE__{size: {width, height}}) do
    nodes = Hierarchy.descendants(root)

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

    kx = if x_range == 0, do: 1, else: width / x_range
    ky = if y_range == 0, do: 1, else: height / y_range

    scale_node(root, min_x, min_y, kx, ky)
  end

  defp scale_to_size(root, %__MODULE__{node_size: {dx, dy}}) do
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
