defmodule Visualize.Layout.Force do
  @moduledoc """
  Force-directed graph layout.

  Provides a physics-based simulation for positioning nodes in a graph.
  The simulation runs as a GenServer, making it suitable for real-time
  updates in LiveView applications.

  ## Basic Usage

      # Define nodes and links
      nodes = [
        %{id: "a"},
        %{id: "b"},
        %{id: "c"}
      ]

      links = [
        %{source: "a", target: "b"},
        %{source: "b", target: "c"}
      ]

      # Start simulation
      {:ok, sim} = Visualize.Layout.Force.start_link(
        nodes: nodes,
        links: links
      )

      # Subscribe to updates in LiveView
      Visualize.Layout.Force.subscribe(sim, self())

  ## LiveView Integration

      def mount(_params, _session, socket) do
        {:ok, sim} = Visualize.Layout.Force.start_link(
          nodes: @nodes,
          links: @links,
          forces: [
            {:center, x: 300, y: 200},
            {:many_body, strength: -100},
            {:link, distance: 50}
          ]
        )

        Visualize.Layout.Force.subscribe(sim, self())

        {:ok, assign(socket, sim: sim, nodes: [], links: [])}
      end

      def handle_info({:force_tick, %{nodes: nodes, links: links}}, socket) do
        {:noreply, assign(socket, nodes: nodes, links: links)}
      end

  ## Available Forces

  - `:center` - Keeps the graph centered
    - `x`, `y`: center coordinates
    - `strength`: how strongly to center (default: 1)

  - `:many_body` - Repulsion/attraction between all nodes
    - `strength`: negative for repulsion, positive for attraction (default: -30)
    - `theta`: Barnes-Hut approximation threshold (default: 0.9)
    - `distance_min`, `distance_max`: distance bounds

  - `:link` - Spring forces between connected nodes
    - `distance`: target distance (default: 30)
    - `strength`: spring strength (default: 1)
    - `iterations`: constraint iterations per tick (default: 1)

  - `:collision` - Prevents node overlap
    - `radius`: node radius or function (default: 10)
    - `strength`: collision strength (default: 1)

  - `:x` - Push nodes toward an x position
    - `x`: target x or function
    - `strength`: force strength (default: 0.1)

  - `:y` - Push nodes toward a y position
    - `y`: target y or function
    - `strength`: force strength (default: 0.1)

  - `:radial` - Push nodes toward a circle
    - `radius`: target radius or function
    - `x`, `y`: circle center
    - `strength`: force strength (default: 0.1)

  """

  alias Visualize.Layout.Force.Simulation

  defdelegate start_link(opts), to: Simulation
  defdelegate start(sim), to: Simulation
  defdelegate stop(sim), to: Simulation
  defdelegate restart(sim), to: Simulation
  defdelegate tick(sim), to: Simulation
  defdelegate nodes(sim), to: Simulation
  defdelegate links(sim), to: Simulation
  defdelegate set_nodes(sim, nodes), to: Simulation
  defdelegate set_links(sim, links), to: Simulation
  defdelegate alpha(sim), to: Simulation
  defdelegate set_alpha(sim, alpha), to: Simulation
  defdelegate set_alpha_target(sim, target), to: Simulation
  defdelegate fix_node(sim, node_id, x, y), to: Simulation
  defdelegate unfix_node(sim, node_id), to: Simulation
  defdelegate subscribe(sim, pid), to: Simulation
  defdelegate unsubscribe(sim, pid), to: Simulation

  @doc """
  Runs a simulation synchronously until it reaches equilibrium.

  Useful for generating static layouts without a GenServer.

  ## Options

  - `:nodes` - list of nodes (required)
  - `:links` - list of links (optional)
  - `:forces` - force configuration (optional)
  - `:iterations` - maximum iterations (default: 300)

  ## Returns

  A map with `:nodes` and `:links` containing final positions.

  ## Examples

      result = Visualize.Layout.Force.run(
        nodes: nodes,
        links: links,
        forces: [{:center, x: 200, y: 200}]
      )

      positioned_nodes = result.nodes

  """
  @spec run(keyword()) :: %{nodes: [map()], links: [map()]}
  def run(opts) do
    nodes = Keyword.fetch!(opts, :nodes)
    links = Keyword.get(opts, :links, [])
    forces = Keyword.get(opts, :forces, default_forces())
    iterations = Keyword.get(opts, :iterations, 300)

    alpha = 1.0
    alpha_min = 0.001
    alpha_decay = 1 - :math.pow(alpha_min, 1 / iterations)
    velocity_decay = 0.4

    # Initialize nodes
    initialized_nodes = initialize_nodes(nodes)

    # Run simulation
    {final_nodes, _alpha} =
      Enum.reduce_while(1..iterations, {initialized_nodes, alpha}, fn _, {nodes, alpha} ->
        if alpha < alpha_min do
          {:halt, {nodes, alpha}}
        else
          new_alpha = alpha * (1 - alpha_decay)
          new_nodes = apply_tick(nodes, links, forces, new_alpha, velocity_decay)
          {:cont, {new_nodes, new_alpha}}
        end
      end)

    %{nodes: final_nodes, links: links}
  end

  defp default_forces do
    [
      {:center, x: 0, y: 0},
      {:many_body, strength: -30},
      {:link, distance: 30}
    ]
  end

  defp initialize_nodes(nodes) do
    nodes
    |> Enum.with_index()
    |> Enum.map(fn {node, i} ->
      {default_x, default_y} = phyllotaxis_position(i)

      node
      |> Map.put_new(:x, default_x)
      |> Map.put_new(:y, default_y)
      |> Map.put_new(:vx, 0)
      |> Map.put_new(:vy, 0)
      |> Map.put_new(:fx, nil)
      |> Map.put_new(:fy, nil)
    end)
  end

  defp phyllotaxis_position(i) do
    radius = :math.sqrt(0.5 + i) * 10
    angle = i * :math.pi() * (3 - :math.sqrt(5))
    {radius * :math.cos(angle), radius * :math.sin(angle)}
  end

  defp apply_tick(nodes, links, forces, alpha, velocity_decay) do
    alias Visualize.Layout.Force.Forces

    # Apply forces
    nodes =
      Enum.reduce(forces, nodes, fn {force_type, opts}, nodes ->
        Forces.apply(force_type, nodes, links, alpha, opts)
      end)

    # Integrate velocities
    Enum.map(nodes, fn node ->
      {x, y, vx, vy} =
        case {node.fx, node.fy} do
          {nil, nil} ->
            vx = node.vx * velocity_decay
            vy = node.vy * velocity_decay
            {node.x + vx, node.y + vy, vx, vy}

          {fx, nil} ->
            vy = node.vy * velocity_decay
            {fx, node.y + vy, 0, vy}

          {nil, fy} ->
            vx = node.vx * velocity_decay
            {node.x + vx, fy, vx, 0}

          {fx, fy} ->
            {fx, fy, 0, 0}
        end

      %{node | x: x, y: y, vx: vx, vy: vy}
    end)
  end
end
