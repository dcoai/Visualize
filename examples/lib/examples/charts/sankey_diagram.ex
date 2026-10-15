defmodule Examples.Charts.SankeyDiagram do
  @moduledoc """
  Sankey diagram as a design (#127): the `:sankey` transform over the flows under a
  `:path` mark for the ribbons and two `:rect` marks for the nodes.

  The layout reads the flows as `source`, `target`, `value` and is a step of each mark's
  data pipeline (spec/14 §5.4.3): `output: :links` yields each ribbon as a ready path,
  painted in its source's color at a light opacity, and `output: :nodes` yields each
  node's four edges, which the `:rect` reads directly. The nodes are split by a `:filter`
  on `height` so the end uses — the last column — are named to the left of their bar and
  every other node to the right, the edge anchors of §5.5. The node ids are the names
  themselves: a node is whatever the flows mention, and the layer derives them.
  """

  import Visualize.Chart.Build

  alias Examples.Charts.Design

  @margin %{top: 25, right: 90, bottom: 25, left: 60}

  # Energy flow — the classic Sankey example: sources to conversion to end use, each flow
  # with the phase and the amplitude its animation breathes by.
  @flows [
    {"Coal", "Electricity", 20, 0.0, 8},
    {"Natural Gas", "Electricity", 15, 0.5, 6},
    {"Natural Gas", "Heating", 10, 1.0, 4},
    {"Nuclear", "Electricity", 18, 1.5, 3},
    {"Solar", "Electricity", 8, 2.0, 6},
    {"Oil", "Transport", 25, 2.5, 8},
    {"Electricity", "Industry", 25, 3.0, 10},
    {"Electricity", "Homes", 20, 3.5, 8},
    {"Electricity", "Transport", 16, 4.0, 6},
    {"Heating", "Homes", 10, 4.5, 5},
    {"Transport", "Industry", 15, 5.0, 6}
  ]

  @doc "The size this chart is drawn at when the caller names none (spec/14 §4.2)."
  def size, do: {700, 400}

  def title, do: "Sankey Diagram"
  def description, do: "Energy flow from sources to end use"

  @doc "The design and the rows it binds (spec/14 §16.1)."
  def design(opts \\ []) do
    {_width, _height} = Design.size(__MODULE__, opts)
    flows = rows(opts)
    # The nodes in the layout's own order: every source, then every target, as first met.
    names = Enum.uniq(Enum.map(flows, & &1.source) ++ Enum.map(flows, & &1.target))

    layout = [padding: 15]
    nodes = sankey(from(:flows), [:source, :target], :value, layout)
    links = sankey(from(:flows), [:source, :target], :value, layout ++ [output: :links])
    edges = %{x0: :x0, x1: :x1, y0: :y0, y1: :y1}

    design =
      Design.fold([
        chart(meta: %{name: title(), description: [description()]}),
        source(:flows, [:source, :target, :value]),
        style(:ribbon, fill: {:field, :source}, fill_opacity: 0.4, stroke: :none),
        style(:node, fill: {:field, :id}, stroke: :text, stroke_width: 0.5),
        style(:name, extends: :label, font_size: 11),
        cartesian(margin: @margin),
        ordinal_scale(:color, domain: names),
        path(links, %{path: :path}, style: :ribbon),
        # Every node named to the right of its bar — but the last column, which nothing
        # leaves, to the left.
        rect(filter(nodes, :height, test: :gt, value: 0), edges,
          label: %{text: [{:field, :id}], anchor: :x1, style: :name},
          style: :node
        ),
        rect(filter(nodes, :height, test: :eq, value: 0), edges,
          label: %{text: [{:field, :id}], anchor: :x0, style: :name},
          style: :node
        )
      ])

    {design, %{flows: flows}}
  end

  def render(opts \\ []), do: Design.render(__MODULE__, opts)

  # The flows as rows; animated, each breathes about its value with its own phase.
  defp rows(opts) do
    case opts[:animation_tick] do
      nil ->
        opts[:flows] ||
          for {s, t, v, _phase, _amplitude} <- @flows, do: %{source: s, target: t, value: v}

      tick ->
        phase = tick * 0.08

        for {s, t, v, offset, amplitude} <- @flows do
          %{source: s, target: t, value: max(2, v + :math.sin(phase + offset) * amplitude)}
        end
    end
  end

  def sample_code do
    ~S"""
    import Visualize.Chart.Build

    nodes = sankey(from(:flows), [:source, :target], :value, padding: 15)
    links = sankey(from(:flows), [:source, :target], :value, padding: 15, output: :links)
    edges = %{x0: :x0, x1: :x1, y0: :y0, y1: :y1}

    {:ok, design} =
      Visualize.Chart.compose([
        chart(meta: %{name: "Sankey Diagram"}),
        source(:flows, [:source, :target, :value]),
        style(:ribbon, fill: {:field, :source}, fill_opacity: 0.4, stroke: :none),
        style(:node, fill: {:field, :id}, stroke: :text, stroke_width: 0.5),
        style(:name, extends: :label, font_size: 11),
        cartesian(margin: %{top: 25, right: 90, bottom: 25, left: 60}),
        ordinal_scale(:color, domain: ["Coal", "Natural Gas", "Oil", "Nuclear", "Solar",
          "Electricity", "Heating", "Transport", "Industry", "Homes"]),
        # The ribbons are ready paths (spec/14 §5.4.3); the nodes read their own edges,
        # named to the right — and the last column, which nothing leaves, to the left.
        path(links, %{path: :path}, style: :ribbon),
        rect(filter(nodes, :height, test: :gt, value: 0), edges,
          label: %{text: [{:field, :id}], anchor: :x1, style: :name},
          style: :node
        ),
        rect(filter(nodes, :height, test: :eq, value: 0), edges,
          label: %{text: [{:field, :id}], anchor: :x0, style: :name},
          style: :node
        )
      ])

    # flows: one row per flow — source, target, value.
    {:ok, applied} = Visualize.Chart.apply(design, sources: %{flows: flows})
    Visualize.Chart.render(applied)
    """
  end
end
