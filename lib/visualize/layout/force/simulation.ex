defmodule Visualize.Layout.Force.Simulation do
  @moduledoc """
  Force-directed graph layout simulation using velocity Verlet integration.

  Runs as a GenServer that can broadcast position updates to LiveView
  processes or PubSub topics.

  ## Examples

      nodes = [
        %{id: "a", x: 0, y: 0},
        %{id: "b", x: 100, y: 0},
        %{id: "c", x: 50, y: 100}
      ]

      links = [
        %{source: "a", target: "b"},
        %{source: "b", target: "c"}
      ]

      {:ok, sim} = Visualize.Layout.Force.Simulation.start_link(
        nodes: nodes,
        links: links,
        forces: [
          {:center, x: 200, y: 200},
          {:many_body, strength: -30},
          {:link, distance: 50}
        ]
      )

      # In LiveView, subscribe to updates
      Visualize.Layout.Force.Simulation.subscribe(sim, self())

  """

  use GenServer

  alias Visualize.Layout.Force.Forces

  @default_alpha 1.0
  @default_alpha_min 0.001
  # ~300 iterations to cool
  @default_alpha_decay 0.0228
  @default_alpha_target 0
  @default_velocity_decay 0.4
  # ~60fps
  @tick_interval 16

  defstruct [
    :nodes,
    :links,
    :forces,
    :alpha,
    :alpha_min,
    :alpha_decay,
    :alpha_target,
    :velocity_decay,
    :subscribers,
    :running,
    :tick_ref,
    :tick_tag
  ]

  @type graph_node :: %{
          required(:id) => any(),
          optional(:x) => number(),
          optional(:y) => number(),
          optional(:vx) => number(),
          optional(:vy) => number(),
          optional(:fx) => number() | nil,
          optional(:fy) => number() | nil,
          optional(any()) => any()
        }

  @type graph_link :: %{
          required(:source) => any(),
          required(:target) => any(),
          optional(:strength) => number(),
          optional(:distance) => number(),
          optional(any()) => any()
        }

  @type force_config ::
          {:center, keyword()}
          | {:many_body, keyword()}
          | {:link, keyword()}
          | {:collision, keyword()}
          | {:x, keyword()}
          | {:y, keyword()}
          | {:radial, keyword()}

  # Client API

  @doc """
  Starts a new force simulation.

  ## Options

  - `:nodes` - list of node maps (required)
  - `:links` - list of link maps (optional)
  - `:forces` - list of force configurations (optional)
  - `:alpha` - initial alpha value (default: 1.0)
  - `:alpha_min` - minimum alpha to stop simulation (default: 0.001)
  - `:alpha_decay` - alpha decay rate (default: 0.0228)
  - `:alpha_target` - target alpha (default: 0)
  - `:velocity_decay` - velocity decay (default: 0.4)
  - `:auto_start` - start simulation immediately (default: true)

  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc "Starts the simulation"
  @spec start(GenServer.server()) :: :ok
  def start(sim) do
    GenServer.cast(sim, :start)
  end

  @doc "Stops/pauses the simulation"
  @spec stop(GenServer.server()) :: :ok
  def stop(sim) do
    GenServer.cast(sim, :stop)
  end

  @doc "Resets alpha to 1.0; a running simulation keeps running, a stopped one stays stopped"
  @spec restart(GenServer.server()) :: :ok
  def restart(sim) do
    GenServer.cast(sim, :restart)
  end

  @doc "Manually advance the simulation by one tick"
  @spec tick(GenServer.server()) :: :ok
  def tick(sim) do
    GenServer.cast(sim, :tick)
  end

  @doc "Gets the current nodes"
  @spec nodes(GenServer.server()) :: [graph_node()]
  def nodes(sim) do
    GenServer.call(sim, :get_nodes)
  end

  @doc "Gets the current links with resolved source/target"
  @spec links(GenServer.server()) :: [graph_link()]
  def links(sim) do
    GenServer.call(sim, :get_links)
  end

  @doc "Updates nodes"
  @spec set_nodes(GenServer.server(), [graph_node()]) :: :ok
  def set_nodes(sim, nodes) do
    GenServer.cast(sim, {:set_nodes, nodes})
  end

  @doc "Updates links"
  @spec set_links(GenServer.server(), [graph_link()]) :: :ok
  def set_links(sim, links) do
    GenServer.cast(sim, {:set_links, links})
  end

  @doc "Gets the current alpha"
  @spec alpha(GenServer.server()) :: float()
  def alpha(sim) do
    GenServer.call(sim, :get_alpha)
  end

  @doc "Sets the alpha value, clamped to `[0, 1]`"
  @spec set_alpha(GenServer.server(), float()) :: :ok
  def set_alpha(sim, alpha) do
    GenServer.cast(sim, {:set_alpha, alpha})
  end

  @doc "Sets the target alpha, clamped to `[0, 1]`"
  @spec set_alpha_target(GenServer.server(), float()) :: :ok
  def set_alpha_target(sim, target) do
    GenServer.cast(sim, {:set_alpha_target, target})
  end

  @doc "Fixes a node's position"
  @spec fix_node(GenServer.server(), any(), number(), number()) :: :ok
  def fix_node(sim, node_id, x, y) do
    GenServer.cast(sim, {:fix_node, node_id, x, y})
  end

  @doc "Unfixes a node's position"
  @spec unfix_node(GenServer.server(), any()) :: :ok
  def unfix_node(sim, node_id) do
    GenServer.cast(sim, {:unfix_node, node_id})
  end

  @doc "Subscribe a process to receive tick updates"
  @spec subscribe(GenServer.server(), pid()) :: :ok
  def subscribe(sim, pid) do
    GenServer.cast(sim, {:subscribe, pid})
  end

  @doc "Unsubscribe a process from tick updates"
  @spec unsubscribe(GenServer.server(), pid()) :: :ok
  def unsubscribe(sim, pid) do
    GenServer.cast(sim, {:unsubscribe, pid})
  end

  # Server callbacks

  @impl true
  def init(opts) do
    nodes = opts[:nodes] || []
    links = opts[:links] || []
    forces = opts[:forces] || default_forces()

    # Initialize node positions and velocities
    initialized_nodes = initialize_nodes(nodes)

    state = %__MODULE__{
      nodes: initialized_nodes,
      links: links,
      forces: forces,
      alpha: opts[:alpha] || @default_alpha,
      alpha_min: opts[:alpha_min] || @default_alpha_min,
      alpha_decay: opts[:alpha_decay] || @default_alpha_decay,
      alpha_target: opts[:alpha_target] || @default_alpha_target,
      velocity_decay: opts[:velocity_decay] || @default_velocity_decay,
      subscribers: MapSet.new(),
      running: false,
      tick_ref: nil,
      tick_tag: nil
    }

    # Auto-start unless explicitly disabled
    if Keyword.get(opts, :auto_start, true) do
      send(self(), :start_simulation)
    end

    {:ok, state}
  end

  @impl true
  def handle_cast(:start, %{running: true} = state), do: {:noreply, state}

  def handle_cast(:start, state), do: {:noreply, arm(state)}

  def handle_cast(:stop, state), do: {:noreply, disarm(state)}

  # Alpha goes back to 1.0. The timer discipline is untouched: a running simulation
  # keeps its tick chain, a stopped one stays stopped (spec/06 §8.5, D-14).
  def handle_cast(:restart, state), do: {:noreply, %{state | alpha: @default_alpha}}

  def handle_cast(:tick, state) do
    {:noreply, do_tick(state)}
  end

  def handle_cast({:set_nodes, nodes}, state) do
    {:noreply, %{state | nodes: initialize_nodes(nodes)}}
  end

  def handle_cast({:set_links, links}, state) do
    {:noreply, %{state | links: links}}
  end

  def handle_cast({:set_alpha, alpha}, state) do
    {:noreply, %{state | alpha: clamp_unit(alpha)}}
  end

  def handle_cast({:set_alpha_target, target}, state) do
    {:noreply, %{state | alpha_target: clamp_unit(target)}}
  end

  def handle_cast({:fix_node, node_id, x, y}, state) do
    nodes =
      Enum.map(state.nodes, fn node ->
        if node.id == node_id do
          %{node | fx: x, fy: y}
        else
          node
        end
      end)

    {:noreply, %{state | nodes: nodes}}
  end

  def handle_cast({:unfix_node, node_id}, state) do
    nodes =
      Enum.map(state.nodes, fn node ->
        if node.id == node_id do
          %{node | fx: nil, fy: nil}
        else
          node
        end
      end)

    {:noreply, %{state | nodes: nodes}}
  end

  def handle_cast({:subscribe, pid}, state) do
    Process.monitor(pid)
    {:noreply, %{state | subscribers: MapSet.put(state.subscribers, pid)}}
  end

  def handle_cast({:unsubscribe, pid}, state) do
    {:noreply, %{state | subscribers: MapSet.delete(state.subscribers, pid)}}
  end

  @impl true
  def handle_call(:get_nodes, _from, state) do
    {:reply, state.nodes, state}
  end

  def handle_call(:get_links, _from, state) do
    # Resolve link source/target to actual node references
    node_map = Map.new(state.nodes, &{&1.id, &1})

    resolved_links =
      Enum.map(state.links, fn link ->
        %{
          link
          | source: Map.get(node_map, link.source, link.source),
            target: Map.get(node_map, link.target, link.target)
        }
      end)

    {:reply, resolved_links, state}
  end

  def handle_call(:get_alpha, _from, state) do
    {:reply, state.alpha, state}
  end

  # init/1's deferred start: a no-op when a :start has already armed the timer, so two
  # tick chains can never run (spec/06 §8.5).
  @impl true
  def handle_info(:start_simulation, state), do: {:noreply, arm(state)}

  # Only the tick carrying the current tag is live. A tick from a timer cancelled after
  # its message had already reached the mailbox carries an old tag and is ignored, which
  # is what keeps a stop followed by a start on a single chain.
  def handle_info({:tick, tag}, %{running: true, tick_tag: tag} = state) do
    state = do_tick(state)

    if state.alpha >= state.alpha_min do
      {:noreply, schedule_tick(state)}
    else
      {:noreply, %{state | running: false, tick_ref: nil, tick_tag: nil}}
    end
  end

  def handle_info({:tick, _stale_tag}, state), do: {:noreply, state}

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {:noreply, %{state | subscribers: MapSet.delete(state.subscribers, pid)}}
  end

  # Private functions

  # `arm/1` is idempotent: a running simulation keeps its timer.
  defp arm(%{running: true} = state), do: state
  defp arm(state), do: schedule_tick(%{state | running: true})

  # Cancelling may find the message already delivered; the stale tag makes that harmless.
  defp disarm(state) do
    if state.tick_ref, do: Process.cancel_timer(state.tick_ref)
    %{state | running: false, tick_ref: nil, tick_tag: nil}
  end

  defp schedule_tick(state) do
    tag = make_ref()
    tick_ref = Process.send_after(self(), {:tick, tag}, @tick_interval)
    %{state | tick_ref: tick_ref, tick_tag: tag}
  end

  defp clamp_unit(value) when is_number(value), do: value |> Kernel.max(0) |> Kernel.min(1)

  defp initialize_nodes(nodes) do
    nodes
    |> Enum.with_index()
    |> Enum.map(fn {node, i} ->
      # Initialize with phyllotaxis pattern if no position
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

  # Phyllotaxis pattern for initial positions
  defp phyllotaxis_position(i) do
    radius = :math.sqrt(0.5 + i) * 10
    angle = i * :math.pi() * (3 - :math.sqrt(5))
    {radius * :math.cos(angle), radius * :math.sin(angle)}
  end

  defp default_forces do
    [
      {:center, x: 0, y: 0},
      {:many_body, strength: -30},
      {:link, distance: 30}
    ]
  end

  defp do_tick(state) do
    # Update alpha
    alpha = state.alpha + (state.alpha_target - state.alpha) * state.alpha_decay

    # Apply forces
    nodes = apply_forces(state.nodes, state.links, state.forces, alpha)

    # Apply velocity verlet integration
    nodes = integrate(nodes, state.velocity_decay)

    # Broadcast to subscribers
    broadcast(state.subscribers, nodes, state.links)

    %{state | nodes: nodes, alpha: alpha}
  end

  defp apply_forces(nodes, links, forces, alpha) do
    Enum.reduce(forces, nodes, fn {force_type, opts}, nodes ->
      Forces.apply(force_type, nodes, links, alpha, opts)
    end)
  end

  defp integrate(nodes, velocity_decay) do
    Enum.map(nodes, fn node ->
      # Apply fixed positions if set
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

  defp broadcast(subscribers, nodes, links) do
    message = {:force_tick, %{nodes: nodes, links: links}}

    Enum.each(subscribers, fn pid ->
      send(pid, message)
    end)
  end
end
