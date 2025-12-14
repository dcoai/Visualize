defmodule Visualize.Layout.Treemap do
  @moduledoc """
  Treemap layout for hierarchical data as nested rectangles.

  Treemaps display hierarchical data as a set of nested rectangles,
  where the area of each rectangle is proportional to its value.

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

      # Build hierarchy and compute values
      root = Visualize.Layout.Hierarchy.new(data)
        |> Visualize.Layout.Hierarchy.sum(fn d -> d[:value] || 0 end)

      # Apply treemap layout
      treemap = Visualize.Layout.Treemap.new()
        |> Visualize.Layout.Treemap.size([400, 300])
        |> Visualize.Layout.Treemap.padding(2)

      positioned = Visualize.Layout.Treemap.generate(treemap, root)

      # Each node now has x0, y0, x1, y1 coordinates

  ## Tiling Algorithms

  - `:squarify` - Squarified treemap (default, good aspect ratios)
  - `:binary` - Binary split (recursive halving)
  - `:slice` - Horizontal slices
  - `:dice` - Vertical slices
  - `:slice_dice` - Alternating slice/dice by depth

  """

  alias Visualize.Layout.Hierarchy

  defstruct size: {1, 1},
            tile: :squarify,
            padding: 0,
            padding_top: nil,
            padding_right: nil,
            padding_bottom: nil,
            padding_left: nil,
            padding_inner: nil,
            round?: false

  @type tile_algorithm :: :squarify | :binary | :slice | :dice | :slice_dice
  @type t :: %__MODULE__{
          size: {number(), number()},
          tile: tile_algorithm(),
          padding: number(),
          padding_top: number() | nil,
          padding_right: number() | nil,
          padding_bottom: number() | nil,
          padding_left: number() | nil,
          padding_inner: number() | nil,
          round?: boolean()
        }

  @doc "Creates a new treemap layout"
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc "Sets the size of the treemap"
  @spec size(t(), [number()] | {number(), number()}) :: t()
  def size(%__MODULE__{} = treemap, [width, height]) do
    %{treemap | size: {width, height}}
  end

  def size(%__MODULE__{} = treemap, {width, height}) do
    %{treemap | size: {width, height}}
  end

  @doc "Sets the tiling algorithm"
  @spec tile(t(), tile_algorithm()) :: t()
  def tile(%__MODULE__{} = treemap, algorithm)
      when algorithm in [:squarify, :binary, :slice, :dice, :slice_dice] do
    %{treemap | tile: algorithm}
  end

  @doc "Sets uniform padding on all sides"
  @spec padding(t(), number()) :: t()
  def padding(%__MODULE__{} = treemap, p) when is_number(p) do
    %{treemap | padding: p}
  end

  @doc "Sets the inner padding between siblings"
  @spec padding_inner(t(), number()) :: t()
  def padding_inner(%__MODULE__{} = treemap, p) do
    %{treemap | padding_inner: p}
  end

  @doc "Sets the top padding"
  @spec padding_top(t(), number()) :: t()
  def padding_top(%__MODULE__{} = treemap, p) do
    %{treemap | padding_top: p}
  end

  @doc "Sets the right padding"
  @spec padding_right(t(), number()) :: t()
  def padding_right(%__MODULE__{} = treemap, p) do
    %{treemap | padding_right: p}
  end

  @doc "Sets the bottom padding"
  @spec padding_bottom(t(), number()) :: t()
  def padding_bottom(%__MODULE__{} = treemap, p) do
    %{treemap | padding_bottom: p}
  end

  @doc "Sets the left padding"
  @spec padding_left(t(), number()) :: t()
  def padding_left(%__MODULE__{} = treemap, p) do
    %{treemap | padding_left: p}
  end

  @doc "Enables rounding of coordinates to integers"
  @spec round(t(), boolean()) :: t()
  def round(%__MODULE__{} = treemap, round?) do
    %{treemap | round?: round?}
  end

  @doc "Generates the treemap layout"
  @spec generate(t(), Hierarchy.t()) :: Hierarchy.t()
  def generate(%__MODULE__{} = treemap, %Hierarchy{} = root) do
    {width, height} = treemap.size

    # Set root bounds
    root = %{root | x0: 0, y0: 0, x1: width, y1: height}

    # Apply layout recursively
    positioned = layout_node(root, treemap)

    # Round if requested
    if treemap.round? do
      round_node(positioned)
    else
      positioned
    end
  end

  defp layout_node(%Hierarchy{children: nil} = node, _treemap), do: node
  defp layout_node(%Hierarchy{children: []} = node, _treemap), do: node

  defp layout_node(%Hierarchy{} = node, treemap) do
    # Calculate inner bounds after padding
    p = treemap.padding
    pt = treemap.padding_top || p
    pr = treemap.padding_right || p
    pb = treemap.padding_bottom || p
    pl = treemap.padding_left || p

    x0 = node.x0 + pl
    y0 = node.y0 + pt
    x1 = node.x1 - pr
    y1 = node.y1 - pb

    # Skip if no space
    if x1 <= x0 or y1 <= y0 do
      node
    else
      # Tile children
      children_with_values =
        node.children
        |> Enum.filter(fn c -> c.value && c.value > 0 end)

      if Enum.empty?(children_with_values) do
        node
      else
        tiled_children =
          tile_children(children_with_values, x0, y0, x1, y1, treemap)

        # Recurse to layout grandchildren
        laid_out_children = Enum.map(tiled_children, &layout_node(&1, treemap))

        %{node | children: laid_out_children}
      end
    end
  end

  defp tile_children(children, x0, y0, x1, y1, %__MODULE__{tile: tile_type} = treemap) do
    inner_padding = treemap.padding_inner || 0

    case tile_type do
      :squarify -> tile_squarify(children, x0, y0, x1, y1, inner_padding)
      :binary -> tile_binary(children, x0, y0, x1, y1, inner_padding)
      :slice -> tile_slice(children, x0, y0, x1, y1, inner_padding)
      :dice -> tile_dice(children, x0, y0, x1, y1, inner_padding)
      :slice_dice -> tile_slice_dice(children, x0, y0, x1, y1, inner_padding)
    end
  end

  # Squarified treemap algorithm
  defp tile_squarify(children, x0, y0, x1, y1, padding) do
    total_value = Enum.reduce(children, 0, fn c, acc -> acc + c.value end)
    area = (x1 - x0) * (y1 - y0)

    # Scale values to areas
    scaled_children =
      Enum.map(children, fn c ->
        {c, c.value / total_value * area}
      end)

    squarify_recursive(scaled_children, x0, y0, x1, y1, padding, [])
  end

  defp squarify_recursive([], _x0, _y0, _x1, _y1, _padding, acc), do: acc

  defp squarify_recursive(children, x0, y0, x1, y1, padding, acc) do
    width = x1 - x0
    height = y1 - y0

    if width <= 0 or height <= 0 do
      acc
    else
      # Determine layout direction (shorter side)
      horizontal = width < height

      # Greedily add children to row until aspect ratio worsens
      {row, remaining} = build_row(children, width, height, horizontal)

      # Layout the row
      {positioned_row, new_x0, new_y0, new_x1, new_y1} =
        layout_row(row, x0, y0, x1, y1, horizontal, padding)

      # Recurse with remaining children
      squarify_recursive(
        remaining,
        new_x0,
        new_y0,
        new_x1,
        new_y1,
        padding,
        acc ++ positioned_row
      )
    end
  end

  defp build_row(children, width, height, horizontal) do
    side = if horizontal, do: width, else: height

    build_row_recursive(children, side, [], 0, :infinity)
  end

  defp build_row_recursive([], _side, row, _row_sum, _best_ratio) do
    {Enum.reverse(row), []}
  end

  defp build_row_recursive([{child, area} | rest], side, row, row_sum, best_ratio) do
    new_sum = row_sum + area
    new_row = [{child, area} | row]

    # Calculate worst aspect ratio in this row
    worst_ratio = worst_aspect_ratio(new_row, new_sum, side)

    if worst_ratio > best_ratio and row != [] do
      # Adding this child makes it worse, stop here
      {Enum.reverse(row), [{child, area} | rest]}
    else
      # Continue building row
      build_row_recursive(rest, side, new_row, new_sum, worst_ratio)
    end
  end

  defp worst_aspect_ratio(row, row_sum, side) do
    row_side = row_sum / side

    row
    |> Enum.map(fn {_child, area} ->
      child_side = area / row_side
      ratio = Kernel.max(child_side / row_side, row_side / child_side)
      ratio
    end)
    |> Enum.max(fn -> 1 end)
  end

  defp layout_row(row, x0, y0, x1, y1, horizontal, padding) do
    width = x1 - x0
    height = y1 - y0
    row_sum = Enum.reduce(row, 0, fn {_, area}, acc -> acc + area end)

    if horizontal do
      # Layout horizontally, take a slice off the top
      row_height = row_sum / width

      {positioned, _} =
        Enum.map_reduce(row, x0, fn {child, area}, curr_x ->
          child_width = area / row_height
          positioned_child = %{
            child
            | x0: curr_x + padding / 2,
              y0: y0 + padding / 2,
              x1: curr_x + child_width - padding / 2,
              y1: y0 + row_height - padding / 2
          }

          {positioned_child, curr_x + child_width}
        end)

      {positioned, x0, y0 + row_height, x1, y1}
    else
      # Layout vertically, take a slice off the left
      row_width = row_sum / height

      {positioned, _} =
        Enum.map_reduce(row, y0, fn {child, area}, curr_y ->
          child_height = area / row_width
          positioned_child = %{
            child
            | x0: x0 + padding / 2,
              y0: curr_y + padding / 2,
              x1: x0 + row_width - padding / 2,
              y1: curr_y + child_height - padding / 2
          }

          {positioned_child, curr_y + child_height}
        end)

      {positioned, x0 + row_width, y0, x1, y1}
    end
  end

  # Binary split algorithm
  defp tile_binary(children, x0, y0, x1, y1, padding) do
    total_value = Enum.reduce(children, 0, fn c, acc -> acc + c.value end)

    if length(children) == 1 do
      [child] = children

      [
        %{
          child
          | x0: x0 + padding / 2,
            y0: y0 + padding / 2,
            x1: x1 - padding / 2,
            y1: y1 - padding / 2
        }
      ]
    else
      # Find split point closest to half
      {left, right} = split_at_half(children, total_value / 2)

      left_value = Enum.reduce(left, 0, fn c, acc -> acc + c.value end)
      ratio = left_value / total_value

      width = x1 - x0
      height = y1 - y0

      if width > height do
        # Split horizontally
        mid_x = x0 + width * ratio
        tile_binary(left, x0, y0, mid_x, y1, padding) ++
          tile_binary(right, mid_x, y0, x1, y1, padding)
      else
        # Split vertically
        mid_y = y0 + height * ratio
        tile_binary(left, x0, y0, x1, mid_y, padding) ++
          tile_binary(right, x0, mid_y, x1, y1, padding)
      end
    end
  end

  defp split_at_half(children, target) do
    split_recursive(children, target, 0, [], [])
  end

  defp split_recursive([], _target, _sum, left, right) do
    {Enum.reverse(left), Enum.reverse(right)}
  end

  defp split_recursive([child | rest], target, sum, left, right) do
    new_sum = sum + child.value

    if new_sum <= target do
      split_recursive(rest, target, new_sum, [child | left], right)
    else
      # Decide which side gets this child
      if abs(new_sum - target) < abs(sum - target) do
        {Enum.reverse([child | left]), rest ++ Enum.reverse(right)}
      else
        {Enum.reverse(left), [child | rest] ++ Enum.reverse(right)}
      end
    end
  end

  # Slice algorithm (horizontal)
  defp tile_slice(children, x0, y0, x1, y1, padding) do
    total_value = Enum.reduce(children, 0, fn c, acc -> acc + c.value end)
    height = y1 - y0

    {positioned, _} =
      Enum.map_reduce(children, y0, fn child, curr_y ->
        child_height = child.value / total_value * height

        positioned_child = %{
          child
          | x0: x0 + padding / 2,
            y0: curr_y + padding / 2,
            x1: x1 - padding / 2,
            y1: curr_y + child_height - padding / 2
        }

        {positioned_child, curr_y + child_height}
      end)

    positioned
  end

  # Dice algorithm (vertical)
  defp tile_dice(children, x0, y0, x1, y1, padding) do
    total_value = Enum.reduce(children, 0, fn c, acc -> acc + c.value end)
    width = x1 - x0

    {positioned, _} =
      Enum.map_reduce(children, x0, fn child, curr_x ->
        child_width = child.value / total_value * width

        positioned_child = %{
          child
          | x0: curr_x + padding / 2,
            y0: y0 + padding / 2,
            x1: curr_x + child_width - padding / 2,
            y1: y1 - padding / 2
        }

        {positioned_child, curr_x + child_width}
      end)

    positioned
  end

  # Slice-dice algorithm (alternating by depth)
  defp tile_slice_dice(children, x0, y0, x1, y1, padding) do
    if length(children) > 0 do
      depth = hd(children).depth

      if rem(depth, 2) == 0 do
        tile_slice(children, x0, y0, x1, y1, padding)
      else
        tile_dice(children, x0, y0, x1, y1, padding)
      end
    else
      []
    end
  end

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
