defmodule ExamplesWeb.ForceDemo do
  @moduledoc """
  The interaction page's live force simulation (spec/06 §8.4, #781, work item #836): a
  `Visualize.Layout.Force.Simulation` the page starts when it connects, linked to it and
  subscribed from the start (`subscribers: [self()]`, #483), so every tick reaches the
  page, which redraws the graph and shows the simulation's alpha until it cools and stops.
  *Reheat* restarts it; *Pin the hub* fixes the hub at the center, and frees it again.

  **A heat input** (#848, work item #849). A square wave drives the simulation's
  `alpha_target`: 0.3 for half of each period, then 0. The page samples on its own
  clock, and the wave's phase is the count of samples, not the wall clock. Each sample sets
  the target when the wave has changed. On a rising edge it also calls `start/1`, because
  a target change alone does not arm a simulation that cooled and stopped (spec/06 §8.5).
  Then the sample reads `alpha/1`. Two charts, the input and the heat, draw one rolling
  window of samples on one time axis.
  """

  use Phoenix.Component

  alias Visualize.Chart
  alias Visualize.Layout.Force.Simulation

  @size {360, 240}

  # The heat input: a sample every 250 ms, a period of 32 samples (8 s), on for the first
  # half at 0.3, and a window of 120 samples (30 s) that both charts draw.
  @sample_ms 250
  @period 32
  @level 0.3
  @window 120
  @chart_size {360, 120}
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

  @doc "The milliseconds between two samples of the heat input."
  @spec sample_ms() :: pos_integer()
  def sample_ms, do: @sample_ms

  @doc "The most samples the window holds."
  @spec window() :: pos_integer()
  def window, do: @window

  @doc """
  The heat input at sample `n`: the level for the first half of each period, then 0, or
  always 0 with the input off.

      iex> ExamplesWeb.ForceDemo.input(0, true)
      0.3
      iex> ExamplesWeb.ForceDemo.input(16, true)
      0.0
      iex> ExamplesWeb.ForceDemo.input(32, true)
      0.3
      iex> ExamplesWeb.ForceDemo.input(0, false)
      0.0

  """
  @spec input(non_neg_integer(), boolean()) :: float()
  def input(n, true) when rem(n, @period) < div(@period, 2), do: @level
  def input(_n, _on?), do: 0.0

  @doc """
  Move the simulation's target from `from` to `to`, and return `to`. An unchanged target
  sends nothing. A rise also starts the simulation, since a target change alone does not
  arm one that cooled and stopped (spec/06 §8.5). `start/1` is a no-op on a running one.
  """
  @spec drive(pid(), float(), float()) :: float()
  def drive(_sim, same, same), do: same

  def drive(sim, from, to) do
    :ok = Simulation.set_alpha_target(sim, to)
    if to > from, do: :ok = Simulation.start(sim)
    to
  end

  @doc """
  The window with sample `n` appended (its time in seconds, the input and the heat),
  holding the newest `window/0` samples at most.
  """
  @spec record([map()], non_neg_integer(), float(), float()) :: [map()]
  def record(samples, n, input, alpha) do
    Enum.take(samples ++ [%{t: n * @sample_ms / 1000, input: input, alpha: alpha}], -@window)
  end

  @doc """
  The two charts over the window, applied for `Visualize.Components.Chart`: the input as
  a step line and the heat as a line, each on the same time domain, the window's last
  30 s, and on y in [0, 1], so their edges line up.
  """
  @spec charts([map()]) :: %{input: Chart.Applied.t(), heat: Chart.Applied.t()}
  def charts(samples) do
    span = @window * @sample_ms / 1000
    last = if samples == [], do: 0.0, else: List.last(samples).t
    domain = [max(0.0, last - span), max(span, last)]

    %{
      input: chart(samples, domain, :input, "Heat input (alpha_target)", 2),
      heat: chart(samples, domain, :alpha, "Heat (alpha)", 1)
    }
  end

  defp chart(samples, domain, field, title, series) do
    curve = if field == :input, do: :step_after, else: :linear

    design = %{
      version: 3,
      sources: %{heat: %{fields: [:t, :input, :alpha]}},
      styles: %{line: %{curve: curve, stroke: %{color: {:series, series}, width: 2}}},
      frames: %{
        main: %{
          kind: :cartesian,
          margin: %{top: 24, right: 12, bottom: 28, left: 40},
          scales: %{
            x: %{kind: :linear, domain: domain},
            y: %{kind: :linear, domain: [0, 1]}
          },
          axes: [
            %{scale: :x, side: :bottom, ticks: 6},
            %{scale: :y, side: :left, ticks: 2, grid: true}
          ]
        }
      },
      marks: [%{type: :line, data: :heat, channels: %{x: :t, y: field}, style: :line}],
      labels: [%{anchor: :title, text: [title]}]
    }

    {:ok, applied} =
      Chart.apply(Chart.from_map!(design), sources: %{heat: samples}, size: @chart_size)

    applied
  end

  attr(:nodes, :list, required: true, doc: "the nodes of the last tick, or the start's")
  attr(:links, :list, required: true, doc: "the links, by node id")
  attr(:alpha, :any, required: true, doc: "the simulation's alpha, or `nil` before it runs")
  attr(:ticks, :integer, required: true, doc: "the ticks the page has received")
  attr(:pinned, :boolean, required: true, doc: "whether the hub is pinned")
  attr(:heat_on, :boolean, required: true, doc: "whether the heat input drives the target")
  attr(:target, :float, required: true, doc: "the target the page set last")
  attr(:charts, :map, required: true, doc: "the input and heat charts, from `charts/1`")

  @doc "The graph as SVG, the alpha, the buttons, and the input and heat charts."
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
        <button type="button" phx-click="force_heat" aria-pressed={to_string(@heat_on)}>
          {if @heat_on, do: "Heat input off", else: "Heat input on"}
        </button>
        target
        <strong class="force-target">{:erlang.float_to_binary(@target * 1.0, decimals: 2)}</strong>
      </p>
      <div class="force-row">
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
        <div class="force-heat">
          <.live_component
            module={Visualize.Components.Chart}
            id="force-input-chart"
            chart={@charts.input}
          />
          <.live_component
            module={Visualize.Components.Chart}
            id="force-heat-chart"
            chart={@charts.heat}
          />
        </div>
      </div>
    </div>
    """
  end

  defp round1(v), do: Float.round(v * 1.0, 1)
end
