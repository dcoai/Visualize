defmodule Visualize.Layout.Tree do
  @moduledoc """
  Tree layout algorithm for hierarchical node-link diagrams.

  Implements the Reingold-Tilford "tidy" algorithm for drawing trees.

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
  """
  @spec generate(t(), Hierarchy.t()) :: Hierarchy.t()
  def generate(%__MODULE__{} = tree, %Hierarchy{} = root) do
    # First pass: compute preliminary x positions
    root_with_prelim = first_walk(root, tree.separation)

    # Second pass: compute final positions
    root_positioned = second_walk(root_with_prelim, 0)

    # Scale to fit size if specified
    scale_to_size(root_positioned, tree)
  end

  # First walk: bottom-up, compute preliminary x-coordinates
  defp first_walk(%Hierarchy{children: nil} = node, _sep) do
    %{node | x: 0}
  end

  defp first_walk(%Hierarchy{children: []} = node, _sep) do
    %{node | x: 0}
  end

  defp first_walk(%Hierarchy{children: children} = node, sep) do
    # Process children first
    processed_children = Enum.map(children, &first_walk(&1, sep))

    # Position children
    positioned_children = position_children(processed_children, sep)

    # Node's x is midpoint of first and last child
    first_child = hd(positioned_children)
    last_child = List.last(positioned_children)
    midpoint = (first_child.x + last_child.x) / 2

    %{node | children: positioned_children, x: midpoint}
  end

  defp position_children([first | rest], sep) do
    # First child starts at 0
    first = %{first | x: 0}

    # Position subsequent children
    {positioned, _} =
      Enum.map_reduce(rest, first, fn child, prev ->
        spacing = sep.(child, prev)
        new_x = prev.x + spacing
        new_child = %{child | x: new_x}
        {new_child, new_child}
      end)

    [first | positioned]
  end

  # Second walk: top-down, finalize positions
  defp second_walk(%Hierarchy{} = node, modifier) do
    final_x = node.x + modifier

    new_children =
      case node.children do
        nil ->
          nil

        [] ->
          nil

        children ->
          Enum.map(children, &second_walk(&1, modifier))
      end

    %{node | x: final_x, y: node.depth, children: new_children}
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
