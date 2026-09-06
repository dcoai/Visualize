defmodule Visualize.Layout.Partition do
  @moduledoc """
  Partition layout for adjacency diagrams.

  Creates icicle diagrams (rectangular) or sunburst diagrams (radial)
  where the area of each node is proportional to its value.

  Unlike treemaps which show leaf nodes, partition layouts show the
  full hierarchy with each level getting equal vertical/radial space.

  ## Examples

      data = %{
        name: "root",
        children: [
          %{name: "A", value: 100},
          %{name: "B", children: [
            %{name: "B1", value: 50},
            %{name: "B2", value: 75}
          ]}
        ]
      }

      root = Visualize.Layout.Hierarchy.new(data)
        |> Visualize.Layout.Hierarchy.sum(fn d -> d[:value] || 0 end)

      # Rectangular partition (icicle diagram)
      partition = Visualize.Layout.Partition.new()
        |> Visualize.Layout.Partition.size([400, 300])

      positioned = Visualize.Layout.Partition.generate(partition, root)
      # Each node has x0, y0, x1, y1

      # Radial partition (sunburst)
      partition = Visualize.Layout.Partition.new()
        |> Visualize.Layout.Partition.size([2 * :math.pi(), 200])

      positioned = Visualize.Layout.Partition.generate(partition, root)
      # x0/x1 are angles, y0/y1 are radii

  """

  alias Visualize.Layout.Hierarchy

  defstruct size: {1, 1},
            padding: 0,
            round?: false

  @type t :: %__MODULE__{
          size: {number(), number()},
          padding: number(),
          round?: boolean()
        }

  @doc "Creates a new partition layout"
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc """
  Sets the size of the partition layout.

  For rectangular layouts: [width, height]
  For radial layouts (sunburst): [angle_extent, radius]
  """
  @spec size(t(), [number()] | {number(), number()}) :: t()
  def size(%__MODULE__{} = partition, [width, height]) do
    %{partition | size: {width, height}}
  end

  def size(%__MODULE__{} = partition, {width, height}) do
    %{partition | size: {width, height}}
  end

  @doc "Sets padding between siblings"
  @spec padding(t(), number()) :: t()
  def padding(%__MODULE__{} = partition, p) when is_number(p) do
    %{partition | padding: p}
  end

  @doc "Enables rounding coordinates to integers"
  @spec round(t(), boolean()) :: t()
  def round(%__MODULE__{} = partition, round?) do
    %{partition | round?: round?}
  end

  @doc "Generates the partition layout"
  @spec generate(t(), Hierarchy.t()) :: Hierarchy.t()
  def generate(%__MODULE__{} = partition, %Hierarchy{} = root) do
    {width, height} = partition.size

    # Get tree height for depth scaling
    tree_height = root.height + 1

    # Height per level
    dy = height / tree_height

    # Start layout from root
    positioned = layout_node(root, 0, width, 0, dy, partition)

    # Round if requested
    if partition.round? do
      round_node(positioned)
    else
      positioned
    end
  end

  defp layout_node(%Hierarchy{} = node, x0, x1, y0, dy, partition) do
    y1 = y0 + dy

    node = %{node | x0: x0, x1: x1, y0: y0, y1: y1}

    case node.children do
      nil ->
        node

      [] ->
        node

      children ->
        # Every child keeps its slot: one whose value is nil or not positive weighs 0 and
        # receives a zero-width rectangle where it would otherwise sit (d3 behaviour).
        total = Enum.reduce(children, 0, fn c, acc -> acc + weight(c) end)

        pad = partition.padding
        available_width = x1 - x0 - pad * (length(children) - 1)

        {positioned_children, _} =
          Enum.map_reduce(children, x0, fn child, curr_x ->
            child_width = if total == 0, do: 0, else: weight(child) / total * available_width
            positioned = layout_node(child, curr_x, curr_x + child_width, y1, dy, partition)
            {positioned, curr_x + child_width + pad}
          end)

        %{node | children: positioned_children}
    end
  end

  defp weight(%Hierarchy{value: v}) when is_number(v) and v > 0, do: v
  defp weight(_), do: 0

  defp round_node(%Hierarchy{} = node) do
    new_children =
      case node.children do
        nil -> nil
        children -> Enum.map(children, &round_node/1)
      end

    %{
      node
      | x0: if(node.x0, do: Kernel.round(node.x0), else: nil),
        y0: if(node.y0, do: Kernel.round(node.y0), else: nil),
        x1: if(node.x1, do: Kernel.round(node.x1), else: nil),
        y1: if(node.y1, do: Kernel.round(node.y1), else: nil),
        children: new_children
    }
  end
end
