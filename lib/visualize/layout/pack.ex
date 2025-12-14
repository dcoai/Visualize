defmodule Visualize.Layout.Pack do
  @moduledoc """
  Circle packing layout for hierarchical data.

  Enclosing circles show hierarchical containment, with the area of each
  leaf circle proportional to its value.

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
  Sets the padding between circles.

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

    # Compute radii for leaf nodes
    root_with_radii = compute_radii(root, pack)

    # Pack siblings from leaves up
    packed = pack_node(root_with_radii, pack)

    # Scale and translate to fit size
    if packed.r && packed.r > 0 do
      k = min(width, height) / (2 * packed.r)
      cx = width / 2
      cy = height / 2

      translate_and_scale(packed, cx, cy, k)
    else
      packed
    end
  end

  defp compute_radii(%Hierarchy{children: nil} = node, pack) do
    r = case pack.radius do
      nil -> if node.value, do: :math.sqrt(node.value), else: 1
      func -> func.(node)
    end
    %{node | r: r}
  end

  defp compute_radii(%Hierarchy{children: []} = node, pack) do
    r = case pack.radius do
      nil -> if node.value, do: :math.sqrt(node.value), else: 1
      func -> func.(node)
    end
    %{node | r: r}
  end

  defp compute_radii(%Hierarchy{children: children} = node, pack) do
    children_with_radii = Enum.map(children, &compute_radii(&1, pack))
    %{node | children: children_with_radii}
  end

  defp pack_node(%Hierarchy{children: nil} = node, _pack), do: node
  defp pack_node(%Hierarchy{children: []} = node, _pack), do: node

  defp pack_node(%Hierarchy{children: children} = node, pack) do
    # First pack all children recursively
    packed_children = Enum.map(children, &pack_node(&1, pack))

    # Get padding for this node
    pad = get_padding(pack.padding, node)

    # Pack the children circles
    positioned_children = pack_circles(packed_children, pad)

    # Compute enclosing circle
    {cx, cy, r} = enclose_circles(positioned_children)

    # Translate children relative to parent center
    translated_children = Enum.map(positioned_children, fn child ->
      %{child | x: child.x - cx, y: child.y - cy}
    end)

    %{node | children: translated_children, x: 0, y: 0, r: r + pad}
  end

  defp get_padding(p, _node) when is_number(p), do: p
  defp get_padding(p, node) when is_function(p, 1), do: p.(node)

  # Simple circle packing algorithm
  defp pack_circles([], _pad), do: []
  defp pack_circles([single], _pad), do: [%{single | x: 0, y: 0}]

  defp pack_circles(circles, pad) do
    # Sort by radius descending for better packing
    sorted = Enum.sort_by(circles, & &1.r, :desc)

    # Place circles one by one
    {placed, _} = Enum.reduce(sorted, {[], []}, fn circle, {placed, front} ->
      circle_with_pad = %{circle | r: circle.r + pad}

      case placed do
        [] ->
          # First circle at origin
          new_circle = %{circle | x: 0, y: 0}
          {[new_circle], [{0, 0, circle.r}]}

        [first] ->
          # Second circle to the right
          x = first.x + first.r + circle.r + 2 * pad
          new_circle = %{circle | x: x, y: 0}
          {[new_circle, first], [{first.x, first.y, first.r}, {x, 0, circle.r}]}

        _ ->
          # Find best position
          {x, y} = find_best_position(circle_with_pad.r, placed, pad)
          new_circle = %{circle | x: x, y: y}
          new_front = [{x, y, circle.r} | front]
          {[new_circle | placed], new_front}
      end
    end)

    placed
  end

  defp find_best_position(r, placed, pad) do
    # Try positions tangent to pairs of existing circles
    candidates =
      for c1 <- placed, c2 <- placed, c1 != c2 do
        tangent_positions(c1, c2, r, pad)
      end
      |> List.flatten()
      |> Enum.filter(fn {x, y} ->
        # Check no overlap with existing circles
        Enum.all?(placed, fn c ->
          dx = x - c.x
          dy = y - c.y
          dist = :math.sqrt(dx * dx + dy * dy)
          dist >= r + c.r + pad - 0.001
        end)
      end)

    case candidates do
      [] ->
        # Fallback: place at edge of bounding circle
        {cx, cy, br} = enclose_circles(placed)
        angle = :rand.uniform() * 2 * :math.pi()
        {cx + (br + r + pad) * :math.cos(angle), cy + (br + r + pad) * :math.sin(angle)}

      _ ->
        # Choose position closest to center
        Enum.min_by(candidates, fn {x, y} -> x * x + y * y end)
    end
  end

  defp tangent_positions(c1, c2, r, pad) do
    dx = c2.x - c1.x
    dy = c2.y - c1.y
    d = :math.sqrt(dx * dx + dy * dy)

    r1 = c1.r + r + 2 * pad
    r2 = c2.r + r + 2 * pad

    if d < 0.001 or d > r1 + r2 do
      []
    else
      # Find intersection points of circles centered at c1 and c2
      a = (r1 * r1 - r2 * r2 + d * d) / (2 * d)
      h_sq = r1 * r1 - a * a

      if h_sq < 0 do
        []
      else
        h = :math.sqrt(max(0, h_sq))

        px = c1.x + a * dx / d
        py = c1.y + a * dy / d

        [
          {px + h * dy / d, py - h * dx / d},
          {px - h * dy / d, py + h * dx / d}
        ]
      end
    end
  end

  # Compute minimum enclosing circle using Welzl's algorithm (simplified)
  defp enclose_circles([]), do: {0, 0, 0}
  defp enclose_circles([c]), do: {c.x, c.y, c.r}

  defp enclose_circles(circles) do
    # Simple bounding circle (not optimal but works)
    {min_x, max_x} = circles |> Enum.map(&(&1.x - &1.r)) |> Enum.min_max()
    {min_y, max_y} = circles |> Enum.map(&(&1.y - &1.r)) |> Enum.min_max()

    # Also consider right/bottom edges
    max_x2 = circles |> Enum.map(&(&1.x + &1.r)) |> Enum.max()
    max_y2 = circles |> Enum.map(&(&1.y + &1.r)) |> Enum.max()

    cx = (min_x + max_x2) / 2
    cy = (min_y + max_y2) / 2

    # Radius is distance to farthest circle edge
    r = circles
        |> Enum.map(fn c ->
          dx = c.x - cx
          dy = c.y - cy
          :math.sqrt(dx * dx + dy * dy) + c.r
        end)
        |> Enum.max()

    {cx, cy, r}
  end

  defp translate_and_scale(%Hierarchy{} = node, cx, cy, k) do
    new_x = cx + (node.x || 0) * k
    new_y = cy + (node.y || 0) * k
    new_r = (node.r || 0) * k

    new_children =
      case node.children do
        nil -> nil
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
        nil -> nil
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
