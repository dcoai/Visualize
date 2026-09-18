defmodule Examples.Charts.CirclePacking do
  @moduledoc """
  Circle packing as a design (#127): a `:pack` transform under two `:circle` marks.

  The packing is a step of the mark's data pipeline (spec/14 §5.4.2), and each `:circle`
  reads its own centre and radius — `value` on a circle is its radius in pixels (§5.2).
  Two marks over the same layout, split by a `:filter` on `height`: the enclosing circles
  (the root and the groups) as translucent rings, and the leaves as filled discs with
  their names at the centre. The nested map reaches the design as a flat node list through
  `Examples.Charts.Design.nodes/1`.

  **Colour follows the branch** — the root child a leaf descends from — where the
  hand-written version coloured leaves by their depth, which in a two-level tree gave every
  leaf the same colour. **Labels are fitted to their circle** with `fit: :truncate`
  (spec/14 §5.5, #138), cut to what the diameter holds, where the hand-written version
  shrank and cut them.
  """

  import Visualize.Chart.Build

  alias Examples.Charts.Design

  @zero_margin %{top: 0, right: 0, bottom: 0, left: 0}

  @data %{
    name: "root",
    children: [
      %{
        name: "Analytics",
        children: [
          %{name: "Cluster", value: 3500},
          %{name: "Graph", value: 2500},
          %{name: "Optimize", value: 1800}
        ]
      },
      %{
        name: "Animate",
        children: [
          %{name: "Easing", value: 2200},
          %{name: "Tween", value: 1800},
          %{name: "Transition", value: 1400}
        ]
      },
      %{
        name: "Data",
        children: [
          %{name: "Converters", value: 2800},
          %{name: "DataSet", value: 1900},
          %{name: "DataUtil", value: 1100}
        ]
      },
      %{
        name: "Display",
        children: [
          %{name: "Render", value: 3200},
          %{name: "Sprite", value: 2100}
        ]
      },
      %{
        name: "Query",
        children: [
          %{name: "Query", value: 2600},
          %{name: "Methods", value: 1200}
        ]
      }
    ]
  }

  def title, do: "Circle Packing"
  def description, do: "Hierarchical data as nested circles"

  @doc "The design and the rows it binds (spec/14 §16.1)."
  def design(opts \\ []) do
    width = opts[:width] || 500
    height = opts[:height] || 500
    tree = opts[:data] || @data
    branches = length(tree[:children] || [])

    packed = pack(from(:nodes), id: :id, by: :parent, field: :value, padding: 3)
    groups = filter(packed, :height, test: :gt, value: 0)
    leaves = filter(packed, :height, test: :eq, value: 0)

    design =
      Design.fold([
        chart(meta: %{name: title(), description: [description()]}),
        source(:nodes, Design.hierarchy_fields()),
        style(:group, fill: :grid, fill_opacity: 0.3, stroke: :axis, stroke_width: 1),
        style(:leaf, fill: {:field, :branch}, stroke: :background, stroke_width: 1),
        style(:leaf_label,
          extends: :label,
          fill: :background,
          font_size: 11,
          font_weight: :bold
        ),
        cartesian(width, height, margin: @zero_margin),
        ordinal_scale(:color, domain: Enum.to_list(0..(branches - 1)//1)),
        # The enclosing circles under the leaves, each over its own centre and radius.
        circle(groups, %{x: :x, y: :y, value: :r}, style: :group),
        circle(leaves, %{x: :x, y: :y, value: :r},
          label: %{text: [{:field, :name}], anchor: :middle, fit: :truncate, style: :leaf_label},
          style: :leaf
        )
      ])

    {design, %{nodes: rows(tree, opts[:animation_tick])}}
  end

  def render(opts \\ []), do: Design.render(__MODULE__, opts)

  defp rows(tree, nil), do: Design.nodes(tree)

  # Animation: each leaf's value pulses about its own with its own phase.
  defp rows(tree, tick) do
    phase = tick * 0.06

    tree
    |> Design.nodes()
    |> Enum.with_index()
    |> Enum.map(fn
      {%{value: value} = row, i} when value > 0 ->
        %{row | value: trunc(max(200, value + :math.sin(phase + i * 0.7) * value / 4))}

      {row, _i} ->
        row
    end)
  end

  def sample_code do
    ~S"""
    import Visualize.Chart.Build

    packed = pack(from(:nodes), id: :id, by: :parent, field: :value, padding: 3)

    {:ok, design} =
      Visualize.Chart.compose([
        chart(meta: %{name: "Circle Packing"}),
        source(:nodes, [:id, :parent, :name, :value, :branch]),
        style(:group, fill: :grid, fill_opacity: 0.3, stroke: :axis),
        style(:leaf, fill: {:field, :branch}, stroke: :background),
        style(:leaf_label, extends: :label, fill: :background, font_size: 11, font_weight: :bold),
        cartesian(500, 500, margin: %{top: 0, right: 0, bottom: 0, left: 0}),
        ordinal_scale(:color, domain: [0, 1, 2, 3, 4]),
        # The enclosing circles, then the leaves over them; `value` is the radius (§5.2).
        circle(filter(packed, :height, test: :gt, value: 0), %{x: :x, y: :y, value: :r},
          style: :group
        ),
        circle(filter(packed, :height, test: :eq, value: 0), %{x: :x, y: :y, value: :r},
          label: %{text: [{:field, :name}], anchor: :middle, fit: :truncate, style: :leaf_label},
          style: :leaf
        )
      ])

    # nodes: one row per node — id, parent (nil for the root), name, value, branch.
    {:ok, applied} = Visualize.Chart.apply(design, sources: %{nodes: nodes})
    Visualize.Chart.render(applied)
    """
  end
end
