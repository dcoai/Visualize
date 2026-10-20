defmodule ExamplesWeb.ForceDemo do
  @moduledoc """
  The interaction page's live force simulation (spec/06 §8.4, #781, work item #836): a
  `Visualize.Layout.Force.Simulation` the page starts when it connects, linked to it and
  subscribed from the start (`subscribers: [self()]`, #483), so every tick reaches the
  page, which redraws the graph and shows the simulation's alpha until it cools and stops.
  *Reheat* restarts it; *Pin the hub* fixes the hub at the center, and frees it again.
  """

  use Phoenix.Component

  alias Visualize.Layout.Force.Simulation

  @size {360, 240}
  @hub "hub"
  @nodes ["hub" | for(i <- 1..11, do: "n#{i}")]

  @doc "The graph: a hub and eleven nodes, each linked to the hub or to its neighbor."
  @spec graph() :: {[map()], [map()]}
  def graph do
    {w, h} = @size

    nodes =
      for {id, i} <- Enum.with_index(@nodes) do
        a = i * 2 * :math.pi() / length(@nodes)
        %{id: id, x: w / 2 + 20 * :math.cos(a), y: h / 2 + 20 * :math.sin(a)}
      end

    links =
      for {id, i} <- Enum.with_index(@nodes), id != @hub do
        target = if rem(i, 3) == 1, do: @hub, else: Enum.at(@nodes, i - 1)
        %{source: id, target: target}
      end

    {nodes, links}
  end

  @doc "The simulation, started linked to the caller and subscribed from its first tick."
  @spec start() :: {:ok, pid()}
  def start do
    {nodes, links} = graph()
    {w, h} = @size

    Simulation.start_link(
      nodes: nodes,
      links: links,
      forces: [{:center, x: w / 2, y: h / 2}, {:many_body, strength: -60}, {:link, distance: 34}],
      subscribers: [self()]
    )
  end

  @doc "Heat the simulation again and run it: `restart/1` sets alpha to 1, `start/1` runs."
  @spec reheat(pid()) :: :ok
  def reheat(sim) do
    :ok = Simulation.restart(sim)
    Simulation.start(sim)
  end

  @doc "Pin the hub at the center, or free it, and reheat so the graph moves."
  @spec pin(pid(), boolean()) :: :ok
  def pin(sim, true) do
    {w, h} = @size
    :ok = Simulation.fix_node(sim, @hub, w / 2, h / 2)
    reheat(sim)
  end

  def pin(sim, false) do
    :ok = Simulation.unfix_node(sim, @hub)
    reheat(sim)
  end

  attr(:nodes, :list, required: true, doc: "the nodes of the last tick, or the start's")
  attr(:links, :list, required: true, doc: "the links, by node id")
  attr(:alpha, :any, required: true, doc: "the simulation's alpha, or `nil` before it runs")
  attr(:ticks, :integer, required: true, doc: "the ticks the page has received")
  attr(:pinned, :boolean, required: true, doc: "whether the hub is pinned")

  @doc "The graph as SVG, the alpha and the buttons."
  def panel(assigns) do
    assigns = assign(assigns, at: Map.new(assigns.nodes, &{&1.id, &1}), size: @size, hub: @hub)

    ~H"""
    <div id="force-graph" class="force-demo">
      <p class="force-status">
        <span :if={@alpha == nil}>Not started: the simulation runs once the page connects.</span>
        <span :if={@alpha != nil}>
          alpha
          <strong class="force-alpha">{:erlang.float_to_binary(@alpha * 1.0, decimals: 3)}</strong>
          after <span class="force-ticks">{@ticks}</span>
          ticks{if @alpha < 0.001, do: " — cooled, stopped", else: ""}
        </span>
        <button type="button" phx-click="force_reheat">Reheat</button>
        <button type="button" phx-click="force_pin" aria-pressed={to_string(@pinned)}>
          {if @pinned, do: "Free the hub", else: "Pin the hub"}
        </button>
      </p>
      <svg
        class="force-graph"
        viewBox={"0 0 #{elem(@size, 0)} #{elem(@size, 1)}"}
        width={elem(@size, 0)}
        height={elem(@size, 1)}
        role="img"
        aria-label="A force simulation, live"
      >
        <line
          :for={link <- @links}
          :if={@at[link.source] && @at[link.target]}
          x1={round1(@at[link.source].x)}
          y1={round1(@at[link.source].y)}
          x2={round1(@at[link.target].x)}
          y2={round1(@at[link.target].y)}
          stroke="#999"
          stroke-width="1.5"
        />
        <circle
          :for={node <- @nodes}
          cx={round1(node.x)}
          cy={round1(node.y)}
          r={if node.id == @hub, do: 9, else: 6}
          fill={if node.id == @hub, do: "#d62728", else: "#3b6fa8"}
          stroke="#fff"
          stroke-width="1.5"
          data-node={node.id}
        />
      </svg>
    </div>
    """
  end

  defp round1(v), do: Float.round(v * 1.0, 1)
end
