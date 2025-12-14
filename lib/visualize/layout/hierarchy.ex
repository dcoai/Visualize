defmodule Visualize.Layout.Hierarchy do
  @moduledoc """
  Hierarchical data structure for tree-based visualizations.

  Provides functions to create and manipulate tree data structures
  that can be used with various layout algorithms (tree, treemap, pack, etc.).

  ## Creating a Hierarchy

  From nested data:

      data = %{
        name: "root",
        children: [
          %{name: "child1", value: 10},
          %{name: "child2", children: [
            %{name: "grandchild", value: 5}
          ]}
        ]
      }

      root = Visualize.Layout.Hierarchy.new(data)

  From tabular data with stratify:

      data = [
        %{id: "root", parent: nil},
        %{id: "child1", parent: "root"},
        %{id: "child2", parent: "root"},
        %{id: "grandchild", parent: "child2"}
      ]

      root = Visualize.Layout.Hierarchy.stratify(data)

  ## Working with Nodes

      # Traverse all nodes
      Visualize.Layout.Hierarchy.each(root, fn node -> IO.inspect(node.data) end)

      # Sum values up the tree
      root = Visualize.Layout.Hierarchy.sum(root, fn d -> d[:value] || 0 end)

      # Count leaves
      root = Visualize.Layout.Hierarchy.count(root)

      # Get all descendants
      nodes = Visualize.Layout.Hierarchy.descendants(root)

      # Get all leaves
      leaves = Visualize.Layout.Hierarchy.leaves(root)

  """

  defstruct [
    :data,
    :parent,
    :children,
    :depth,
    :height,
    :value,
    :id,
    # Layout positions (set by layout algorithms)
    :x,
    :y,
    :x0,
    :y0,
    :x1,
    :y1,
    :r
  ]

  @type t :: %__MODULE__{
          data: any(),
          parent: t() | nil,
          children: [t()] | nil,
          depth: non_neg_integer(),
          height: non_neg_integer(),
          value: number() | nil,
          id: any(),
          x: number() | nil,
          y: number() | nil,
          x0: number() | nil,
          y0: number() | nil,
          x1: number() | nil,
          y1: number() | nil,
          r: number() | nil
        }

  @doc """
  Creates a hierarchy from nested data.

  ## Options

  - `:children` - Function to get children from a node (default: `& &1[:children]` or `& &1.children`)

  """
  @spec new(map(), keyword()) :: t()
  def new(data, opts \\ []) do
    children_fn = Keyword.get(opts, :children, &default_children/1)
    build_node(data, nil, 0, children_fn)
  end

  @doc """
  Creates a hierarchy from flat/tabular data.

  ## Options

  - `:id` - Function to get node ID (default: `& &1[:id]` or `& &1.id`)
  - `:parent_id` - Function to get parent ID (default: `& &1[:parent]` or `& &1.parent`)

  """
  @spec stratify([map()], keyword()) :: t()
  def stratify(data, opts \\ []) do
    id_fn = Keyword.get(opts, :id, &default_id/1)
    parent_fn = Keyword.get(opts, :parent_id, &default_parent/1)

    # Build lookup maps
    nodes_by_id =
      data
      |> Enum.map(fn d -> {id_fn.(d), %{data: d, children: []}} end)
      |> Map.new()

    # Find root and build parent-child relationships
    root_data =
      Enum.find(data, fn d ->
        parent_id = parent_fn.(d)
        is_nil(parent_id) or parent_id == ""
      end)

    if is_nil(root_data) do
      raise ArgumentError, "No root node found (node with nil or empty parent)"
    end

    root_id = id_fn.(root_data)

    # Build children lists
    nodes_with_children =
      Enum.reduce(data, nodes_by_id, fn d, acc ->
        id = id_fn.(d)
        parent_id = parent_fn.(d)

        if parent_id && parent_id != "" && Map.has_key?(acc, parent_id) do
          update_in(acc, [parent_id, :children], fn children ->
            children ++ [Map.get(acc, id)]
          end)
        else
          acc
        end
      end)

    # Convert to hierarchy nodes
    build_stratified_node(Map.get(nodes_with_children, root_id), nil, 0)
  end

  @doc """
  Traverses the hierarchy, calling the function on each node.

  Visits nodes in pre-order (parent before children).
  """
  @spec each(t(), (t() -> any())) :: :ok
  def each(%__MODULE__{} = node, func) do
    func.(node)

    if node.children do
      Enum.each(node.children, &each(&1, func))
    end

    :ok
  end

  @doc """
  Traverses post-order (children before parent) and calls function.
  """
  @spec each_after(t(), (t() -> any())) :: :ok
  def each_after(%__MODULE__{} = node, func) do
    if node.children do
      Enum.each(node.children, &each_after(&1, func))
    end

    func.(node)
    :ok
  end

  @doc """
  Returns all descendant nodes as a flat list (including the node itself).
  """
  @spec descendants(t()) :: [t()]
  def descendants(%__MODULE__{} = node) do
    [node | child_descendants(node.children)]
  end

  defp child_descendants(nil), do: []
  defp child_descendants([]), do: []

  defp child_descendants(children) do
    Enum.flat_map(children, &descendants/1)
  end

  @doc """
  Returns all ancestor nodes (from parent to root).
  """
  @spec ancestors(t()) :: [t()]
  def ancestors(%__MODULE__{parent: nil}), do: []

  def ancestors(%__MODULE__{parent: parent}) do
    [parent | ancestors(parent)]
  end

  @doc """
  Returns all leaf nodes (nodes without children).
  """
  @spec leaves(t()) :: [t()]
  def leaves(%__MODULE__{} = node) do
    node
    |> descendants()
    |> Enum.filter(fn n -> is_nil(n.children) or n.children == [] end)
  end

  @doc """
  Returns the path from this node to the specified target node.
  """
  @spec path(t(), t()) :: [t()]
  def path(%__MODULE__{} = source, %__MODULE__{} = target) do
    source_ancestors = [source | ancestors(source)] |> Enum.reverse()
    target_ancestors = [target | ancestors(target)] |> Enum.reverse()

    # Find common ancestor
    {common_path, source_rest, target_rest} =
      find_common_path(source_ancestors, target_ancestors, [])

    # Build path: source -> common ancestor -> target
    source_path = Enum.reverse(source_rest)
    target_path = target_rest

    Enum.reverse(common_path) ++ source_path ++ target_path
  end

  defp find_common_path([s | s_rest], [t | t_rest], acc) when s == t do
    find_common_path(s_rest, t_rest, [s | acc])
  end

  defp find_common_path(s_rest, t_rest, acc), do: {acc, s_rest, t_rest}

  @doc """
  Returns all links (parent-child pairs) in the hierarchy.

  Returns list of `{source, target}` tuples.
  """
  @spec links(t()) :: [{t(), t()}]
  def links(%__MODULE__{} = node) do
    node
    |> descendants()
    |> Enum.flat_map(fn n ->
      case n.children do
        nil -> []
        [] -> []
        children -> Enum.map(children, fn child -> {n, child} end)
      end
    end)
  end

  @doc """
  Computes the sum of values for each node.

  The value of each node becomes the sum of its own value plus
  all descendant values. Evaluates the value function for leaves.
  """
  @spec sum(t(), (any() -> number())) :: t()
  def sum(%__MODULE__{} = node, value_fn) do
    sum_node(node, value_fn)
  end

  defp sum_node(%__MODULE__{children: nil} = node, value_fn) do
    %{node | value: value_fn.(node.data)}
  end

  defp sum_node(%__MODULE__{children: []} = node, value_fn) do
    %{node | value: value_fn.(node.data)}
  end

  defp sum_node(%__MODULE__{children: children} = node, value_fn) do
    summed_children = Enum.map(children, &sum_node(&1, value_fn))
    child_sum = Enum.reduce(summed_children, 0, fn c, acc -> acc + (c.value || 0) end)
    own_value = value_fn.(node.data)
    %{node | children: summed_children, value: child_sum + own_value}
  end

  @doc """
  Sets each node's value to the count of its leaves.
  """
  @spec count(t()) :: t()
  def count(%__MODULE__{} = node) do
    count_node(node)
  end

  defp count_node(%__MODULE__{children: nil} = node) do
    %{node | value: 1}
  end

  defp count_node(%__MODULE__{children: []} = node) do
    %{node | value: 1}
  end

  defp count_node(%__MODULE__{children: children} = node) do
    counted_children = Enum.map(children, &count_node/1)
    total = Enum.reduce(counted_children, 0, fn c, acc -> acc + c.value end)
    %{node | children: counted_children, value: total}
  end

  @doc """
  Sorts children at each level using the comparator.

  The comparator receives two nodes and returns true if the first
  should come before the second.
  """
  @spec sort(t(), (t(), t() -> boolean())) :: t()
  def sort(%__MODULE__{children: nil} = node, _comparator), do: node
  def sort(%__MODULE__{children: []} = node, _comparator), do: node

  def sort(%__MODULE__{children: children} = node, comparator) do
    sorted_children =
      children
      |> Enum.map(&sort(&1, comparator))
      |> Enum.sort(comparator)

    %{node | children: sorted_children}
  end

  @doc """
  Copies the hierarchy, optionally transforming data.
  """
  @spec copy(t(), (any() -> any()) | nil) :: t()
  def copy(%__MODULE__{} = node, transform \\ nil) do
    copy_node(node, nil, transform)
  end

  defp copy_node(%__MODULE__{} = node, parent, transform) do
    new_data = if transform, do: transform.(node.data), else: node.data

    new_node = %__MODULE__{
      data: new_data,
      parent: parent,
      depth: node.depth,
      height: node.height,
      value: node.value,
      id: node.id,
      x: node.x,
      y: node.y,
      x0: node.x0,
      y0: node.y0,
      x1: node.x1,
      y1: node.y1,
      r: node.r
    }

    children =
      case node.children do
        nil -> nil
        [] -> []
        cs -> Enum.map(cs, &copy_node(&1, new_node, transform))
      end

    %{new_node | children: children}
  end

  # Private helpers

  defp build_node(data, parent, depth, children_fn) do
    children_data = children_fn.(data)

    node = %__MODULE__{
      data: data,
      parent: parent,
      depth: depth,
      height: 0,
      id: Map.get(data, :id) || Map.get(data, :name)
    }

    children =
      case children_data do
        nil ->
          nil

        [] ->
          nil

        list when is_list(list) ->
          Enum.map(list, &build_node(&1, node, depth + 1, children_fn))
      end

    height =
      case children do
        nil -> 0
        [] -> 0
        cs -> 1 + Enum.max(Enum.map(cs, & &1.height))
      end

    %{node | children: children, height: height}
  end

  defp build_stratified_node(%{data: data, children: children_data}, parent, depth) do
    node = %__MODULE__{
      data: data,
      parent: parent,
      depth: depth,
      height: 0,
      id: Map.get(data, :id) || Map.get(data, :name)
    }

    children =
      case children_data do
        [] ->
          nil

        list ->
          Enum.map(list, &build_stratified_node(&1, node, depth + 1))
      end

    height =
      case children do
        nil -> 0
        [] -> 0
        cs -> 1 + Enum.max(Enum.map(cs, & &1.height))
      end

    %{node | children: children, height: height}
  end

  defp default_children(data) when is_map(data) do
    Map.get(data, :children) || Map.get(data, "children")
  end

  defp default_children(_), do: nil

  defp default_id(data) when is_map(data) do
    Map.get(data, :id) || Map.get(data, "id")
  end

  defp default_id(_), do: nil

  defp default_parent(data) when is_map(data) do
    Map.get(data, :parent) || Map.get(data, "parent") ||
      Map.get(data, :parent_id) || Map.get(data, "parent_id")
  end

  defp default_parent(_), do: nil
end
