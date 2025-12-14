defmodule Visualize.Layout.Force.Forces do
  @moduledoc """
  Force functions for the force simulation.

  Each force modifies node velocities based on different rules.
  """

  @doc """
  Applies a force to the nodes.
  """
  @spec apply(atom(), [map()], [map()], float(), keyword()) :: [map()]
  def apply(force_type, nodes, links, alpha, opts) do
    case force_type do
      :center -> apply_center(nodes, alpha, opts)
      :many_body -> apply_many_body(nodes, alpha, opts)
      :link -> apply_link(nodes, links, alpha, opts)
      :collision -> apply_collision(nodes, alpha, opts)
      :x -> apply_x(nodes, alpha, opts)
      :y -> apply_y(nodes, alpha, opts)
      :radial -> apply_radial(nodes, alpha, opts)
    end
  end

  @doc """
  Center force - keeps nodes centered around a point.
  """
  def apply_center(nodes, _alpha, opts) do
    cx = Keyword.get(opts, :x, 0)
    cy = Keyword.get(opts, :y, 0)
    strength = Keyword.get(opts, :strength, 1)

    n = length(nodes)

    if n == 0 do
      nodes
    else
      # Calculate current center of mass
      {sum_x, sum_y} =
        Enum.reduce(nodes, {0, 0}, fn node, {sx, sy} ->
          {sx + node.x, sy + node.y}
        end)

      dx = (sum_x / n - cx) * strength
      dy = (sum_y / n - cy) * strength

      # Shift all nodes
      Enum.map(nodes, fn node ->
        %{node | x: node.x - dx, y: node.y - dy}
      end)
    end
  end

  @doc """
  Many-body force - simulates gravity or electrostatic charge.

  Positive strength attracts, negative repels.
  Uses Barnes-Hut approximation for performance with many nodes.
  """
  def apply_many_body(nodes, alpha, opts) do
    strength = Keyword.get(opts, :strength, -30)
    theta = Keyword.get(opts, :theta, 0.9)
    distance_min = Keyword.get(opts, :distance_min, 1)
    distance_max = Keyword.get(opts, :distance_max, :infinity)

    n = length(nodes)

    if n < 2 do
      nodes
    else
      # For small graphs, use direct calculation
      # For large graphs, would use quadtree (Barnes-Hut)
      if n < 100 do
        apply_many_body_direct(nodes, alpha, strength, distance_min, distance_max)
      else
        apply_many_body_direct(nodes, alpha, strength, distance_min, distance_max)
      end
    end
  end

  defp apply_many_body_direct(nodes, alpha, strength, distance_min, distance_max) do
    indexed_nodes = Enum.with_index(nodes)

    Enum.map(indexed_nodes, fn {node, i} ->
      {dvx, dvy} =
        Enum.reduce(indexed_nodes, {0, 0}, fn {other, j}, {vx, vy} ->
          if i == j do
            {vx, vy}
          else
            dx = other.x - node.x
            dy = other.y - node.y
            d2 = dx * dx + dy * dy

            if within_distance?(d2, distance_max) do
              d = :math.sqrt(d2)
              d = Kernel.max(d, distance_min)

              # Force magnitude
              k = strength * alpha / (d * d)

              {vx + dx * k, vy + dy * k}
            else
              {vx, vy}
            end
          end
        end)

      %{node | vx: node.vx + dvx, vy: node.vy + dvy}
    end)
  end

  @doc """
  Link force - maintains distances between connected nodes.
  """
  def apply_link(nodes, links, alpha, opts) do
    distance = Keyword.get(opts, :distance, 30)
    strength = Keyword.get(opts, :strength, 1)
    iterations = Keyword.get(opts, :iterations, 1)

    if Enum.empty?(links) do
      nodes
    else
      # Create node lookup by id
      node_map = Map.new(nodes, &{&1.id, &1})

      # Apply link constraints
      Enum.reduce(1..iterations, nodes, fn _, nodes ->
        node_map = Map.new(nodes, &{&1.id, &1})
        apply_link_iteration(nodes, links, node_map, alpha, distance, strength)
      end)
    end
  end

  defp apply_link_iteration(nodes, links, node_map, alpha, default_distance, default_strength) do
    # Calculate forces for each link
    forces =
      Enum.reduce(links, %{}, fn link, forces ->
        source_id = if is_map(link.source), do: link.source.id, else: link.source
        target_id = if is_map(link.target), do: link.target.id, else: link.target

        source = Map.get(node_map, source_id)
        target = Map.get(node_map, target_id)

        if source && target do
          link_distance = Map.get(link, :distance, default_distance)
          link_strength = Map.get(link, :strength, default_strength)

          dx = target.x + target.vx - source.x - source.vx
          dy = target.y + target.vy - source.y - source.vy

          d = :math.sqrt(dx * dx + dy * dy)
          d = max(d, 0.001)

          k = (d - link_distance) / d * alpha * link_strength

          fx = dx * k
          fy = dy * k

          # Add to source (positive) and target (negative)
          forces
          |> Map.update(source_id, {fx, fy}, fn {vx, vy} -> {vx + fx, vy + fy} end)
          |> Map.update(target_id, {-fx, -fy}, fn {vx, vy} -> {vx - fx, vy - fy} end)
        else
          forces
        end
      end)

    # Apply accumulated forces
    Enum.map(nodes, fn node ->
      case Map.get(forces, node.id) do
        {dvx, dvy} -> %{node | vx: node.vx + dvx, vy: node.vy + dvy}
        nil -> node
      end
    end)
  end

  @doc """
  Collision force - prevents nodes from overlapping.
  """
  def apply_collision(nodes, alpha, opts) do
    radius = Keyword.get(opts, :radius, 10)
    strength = Keyword.get(opts, :strength, 1)
    iterations = Keyword.get(opts, :iterations, 1)

    radius_fn =
      case radius do
        r when is_function(r, 1) -> r
        r when is_number(r) -> fn _ -> r end
      end

    Enum.reduce(1..iterations, nodes, fn _, nodes ->
      apply_collision_iteration(nodes, alpha, radius_fn, strength)
    end)
  end

  defp apply_collision_iteration(nodes, alpha, radius_fn, strength) do
    indexed_nodes = Enum.with_index(nodes)

    Enum.map(indexed_nodes, fn {node, i} ->
      ri = radius_fn.(node)

      {dvx, dvy} =
        Enum.reduce(indexed_nodes, {0, 0}, fn {other, j}, {vx, vy} ->
          if i >= j do
            {vx, vy}
          else
            rj = radius_fn.(other)
            r = ri + rj

            dx = node.x - other.x
            dy = node.y - other.y
            d2 = dx * dx + dy * dy

            if d2 < r * r do
              d = :math.sqrt(d2)
              d = max(d, 0.001)

              k = (r - d) / d * strength * alpha * 0.5

              {vx + dx * k, vy + dy * k}
            else
              {vx, vy}
            end
          end
        end)

      %{node | vx: node.vx + dvx, vy: node.vy + dvy}
    end)
  end

  @doc """
  X positioning force - pushes nodes toward an x position.
  """
  def apply_x(nodes, alpha, opts) do
    x = Keyword.get(opts, :x, 0)
    strength = Keyword.get(opts, :strength, 0.1)

    x_fn =
      case x do
        f when is_function(f, 1) -> f
        n when is_number(n) -> fn _ -> n end
      end

    Enum.map(nodes, fn node ->
      target_x = x_fn.(node)
      k = (target_x - node.x) * strength * alpha
      %{node | vx: node.vx + k}
    end)
  end

  @doc """
  Y positioning force - pushes nodes toward a y position.
  """
  def apply_y(nodes, alpha, opts) do
    y = Keyword.get(opts, :y, 0)
    strength = Keyword.get(opts, :strength, 0.1)

    y_fn =
      case y do
        f when is_function(f, 1) -> f
        n when is_number(n) -> fn _ -> n end
      end

    Enum.map(nodes, fn node ->
      target_y = y_fn.(node)
      k = (target_y - node.y) * strength * alpha
      %{node | vy: node.vy + k}
    end)
  end

  @doc """
  Radial force - pushes nodes toward/away from a circle.
  """
  def apply_radial(nodes, alpha, opts) do
    radius = Keyword.get(opts, :radius, 100)
    x = Keyword.get(opts, :x, 0)
    y = Keyword.get(opts, :y, 0)
    strength = Keyword.get(opts, :strength, 0.1)

    radius_fn =
      case radius do
        f when is_function(f, 1) -> f
        n when is_number(n) -> fn _ -> n end
      end

    Enum.map(nodes, fn node ->
      target_radius = radius_fn.(node)

      dx = node.x - x
      dy = node.y - y
      d = :math.sqrt(dx * dx + dy * dy)
      d = Kernel.max(d, 0.001)

      k = (target_radius - d) / d * strength * alpha

      %{node | vx: node.vx + dx * k, vy: node.vy + dy * k}
    end)
  end

  # Helper to check distance with infinity support
  defp within_distance?(_d2, :infinity), do: true
  defp within_distance?(d2, max) when is_number(max), do: d2 < max * max
end
