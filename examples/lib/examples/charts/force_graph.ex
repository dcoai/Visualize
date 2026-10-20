defmodule Examples.Charts.ForceGraph do
  @moduledoc """
  Force-directed graph as a design (#346, D-110): the `:force` transform over the links,
  its nodes read from a second source, under a `:path` mark for the links and a `:circle`
  mark for the nodes.

  A graph is two tables. The links are the mark's source and the nodes reach the step
  through `nodes: :nodes` (spec/14 §5.4.3), so each laid-out node carries its table row —
  here its `group`, which colors it through the `color` scale — and the layout's
  `strength` and `distance` are the step's own keys rather than the fixed ones that packed
  twelve nodes into a blob. Rendered whole, the simulation is a pure function of its
  input, so the design draws the same graph every time.

  Animated, the link distance breathes, `100 + 12 sin(0.1 t)`, and the layout settles
  around the breathing distance **from where it was** (#527, D-132): a run keeps a
  compiled chart on every backend, and its `:force` step is warm there — each tick starts
  from the last tick's positions and velocities, reheated to the step's `alpha` for its
  few `ticks` of iterations — so the graph swells and settles in place as one graph. The
  breathing changes a mark's transform, so each tick is compiled again and
  `Examples.Frames` carries the layout across (spec/14 §12.5). Laid out cold every frame,
  as it was, the graph relaxed from scratch each tick into whichever equilibrium it fell
  into, a node jumping by up to 327 px; warm, no node moves by more than about 11 px a
  tick. The hand-written version jittered each node about its rest position by hand — a
  node's position is the layout's.
  """

  import Visualize.Chart.Build

  alias Examples.Charts.Design

  @zero_margin %{top: 0, right: 0, bottom: 0, left: 0}

  @nodes [
    %{id: "A", group: 0},
    %{id: "B", group: 0},
    %{id: "C", group: 0},
    %{id: "D", group: 1},
    %{id: "E", group: 1},
    %{id: "F", group: 1},
    %{id: "G", group: 2},
    %{id: "H", group: 2},
    %{id: "I", group: 2},
    %{id: "J", group: 3},
    %{id: "K", group: 3},
    %{id: "L", group: 3}
  ]

  @links [
    %{source: "A", target: "B"},
    %{source: "A", target: "C"},
    %{source: "B", target: "C"},
    %{source: "D", target: "E"},
    %{source: "D", target: "F"},
    %{source: "E", target: "F"},
    %{source: "G", target: "H"},
    %{source: "G", target: "I"},
    %{source: "H", target: "I"},
    %{source: "J", target: "K"},
    %{source: "J", target: "L"},
    %{source: "K", target: "L"},
    %{source: "A", target: "D"},
    %{source: "B", target: "G"},
    %{source: "C", target: "J"},
    %{source: "E", target: "H"},
    %{source: "F", target: "K"},
    %{source: "I", target: "L"}
  ]

  def title, do: "Force-Directed Graph"
  def description, do: "Network visualization with physics simulation"

  @doc "The design and the rows it binds (spec/14 §16.1)."
  def design(opts \\ []) do
    # Animated, the link distance breathes; a run's warm layout settles around it from
    # where it was (#527, D-132).
    distance =
      case opts[:animation_tick] do
        nil -> 100
        tick -> 100 + 12 * :math.sin(tick * 0.1)
      end

    # A running chart keeps the layout warm (#527, D-132): each tick reheats it to `alpha`
    # and runs `ticks` iterations from where it was. These are the defaults, written out.
    layout = [nodes: :nodes, strength: -400, distance: distance, alpha: 0.3, ticks: 3]

    design =
      Design.fold([
        chart(meta: %{name: title(), description: [description()]}),
        source(:nodes, [:id, :group]),
        source(:links, [:source, :target]),
        style(:link, fill: :none, stroke: :axis, stroke_opacity: 0.6, stroke_width: 1.5),
        style(:node, fill: {:field, :group}, stroke: :background, stroke_width: 2),
        style(:id, extends: :label, fill: :contrast, font_size: 10, font_weight: :bold),
        cartesian(margin: @zero_margin),
        ordinal_scale(:color, domain: [0, 1, 2, 3]),
        path(force(from(:links), [:source, :target], layout ++ [output: :links]), %{path: :path},
          style: :link
        ),
        circle(force(from(:links), [:source, :target], layout), %{x: :x, y: :y},
          options: %{radius: 10},
          label: %{text: [{:field, :id}], anchor: :middle, fit: :hide, style: :id},
          style: :node
        )
      ])

    {design, %{nodes: opts[:nodes] || @nodes, links: opts[:links] || @links}}
  end

  def render(opts \\ []), do: Design.render(__MODULE__, opts)

  def sample_code do
    ~S"""
    import Visualize.Chart.Build

    # A graph is two tables: the links are the mark's source, the nodes a second one the
    # step reads through `nodes:` (spec/14 §5.4.3), so a laid-out node carries its group.
    # Animated, the layout is warm: each tick reheats it to `alpha` and runs `ticks`
    # iterations from where it was (#527), so the graph settles in place.
    layout = [nodes: :nodes, strength: -400, distance: 100, alpha: 0.3, ticks: 3]

    {:ok, design} =
      Visualize.Chart.compose([
        chart(meta: %{name: "Force-Directed Graph"}),
        source(:nodes, [:id, :group]),
        source(:links, [:source, :target]),
        style(:link, fill: :none, stroke: :axis, stroke_opacity: 0.6, stroke_width: 1.5),
        style(:node, fill: {:field, :group}, stroke: :background, stroke_width: 2),
        style(:id, extends: :label, fill: :contrast, font_size: 10, font_weight: :bold),
        cartesian(margin: %{top: 0, right: 0, bottom: 0, left: 0}),
        ordinal_scale(:color, domain: [0, 1, 2, 3]),
        path(force(from(:links), [:source, :target], layout ++ [output: :links]),
          %{path: :path}, style: :link),
        circle(force(from(:links), [:source, :target], layout), %{x: :x, y: :y},
          options: %{radius: 10},
          label: %{text: [{:field, :id}], anchor: :middle, fit: :hide, style: :id},
          style: :node
        )
      ])

    {:ok, applied} = Visualize.Chart.apply(design, sources: %{nodes: nodes, links: links})
    Visualize.Chart.render(applied)
    """
  end
end
