defmodule Examples.Charts.TreemapChart do
  @moduledoc """
  Treemap as a design (#127): a `:treemap` transform under one `:rect` mark.

  The squarified layout is a step of the mark's data pipeline (spec/14 §5.4.2), and the
  `:rect` reads the four edges of each cell directly; a `:filter` step keeps the leaves,
  which is all the hand-written version drew. The nested map reaches the design as a flat
  node list through `Examples.Charts.Design.nodes/1`, the shape a hierarchy transform reads.

  **Color follows the branch** — the root child a cell descends from, as
  `Visualize.Chart.Presets.treemap_chart/1` colors — which is what the hand-written
  version did by looking up each leaf's top-level parent. **Labels are fitted to their
  cell** with `fit: :truncate` (spec/14 §5.5, #138), cut to what the cell's width holds,
  as the hand-written version cut them.
  """

  import Visualize.Chart.Build

  alias Examples.Charts.Design

  @zero_margin %{top: 0, right: 0, bottom: 0, left: 0}

  @data %{
    name: "Flare",
    children: [
      %{
        name: "Analytics",
        children: [
          %{name: "Cluster", value: 8500},
          %{name: "Graph", value: 7500},
          %{name: "Optimization", value: 6200}
        ]
      },
      %{
        name: "Animate",
        children: [
          %{name: "Easing", value: 4200},
          %{name: "Interpolate", value: 5800},
          %{name: "Transition", value: 3900}
        ]
      },
      %{
        name: "Data",
        children: [
          %{name: "Converters", value: 4700},
          %{name: "DataSet", value: 3800},
          %{name: "DataUtil", value: 2100}
        ]
      },
      %{
        name: "Display",
        children: [
          %{name: "DirtySprite", value: 3100},
          %{name: "Render", value: 4500}
        ]
      },
      %{
        name: "Query",
        children: [
          %{name: "Query", value: 6800},
          %{name: "Methods", value: 2200}
        ]
      },
      %{
        name: "Scale",
        children: [
          %{name: "Linear", value: 2900},
          %{name: "Log", value: 2500},
          %{name: "Ordinal", value: 2800}
        ]
      },
      %{
        name: "Util",
        children: [
          %{name: "Arrays", value: 3200},
          %{name: "Colors", value: 2100},
          %{name: "Math", value: 2800}
        ]
      },
      %{
        name: "Vis",
        children: [
          %{name: "Axis", value: 4100},
          %{name: "Controls", value: 2600},
          %{name: "Data", value: 3700}
        ]
      }
    ]
  }

  def title, do: "Treemap"
  def description, do: "Hierarchical data as nested rectangles"

  @doc "The design and the rows it binds (spec/14 §16.1)."
  def design(opts \\ []) do
    {_width, _height} = Design.size(__MODULE__, opts)
    tree = opts[:data] || @data
    branches = length(tree[:children] || [])

    # The leaves alone, each cell over its own edges.
    leaves =
      from(:nodes)
      |> treemap(id: :id, by: :parent, field: :value, padding: 2)
      |> filter(:height, test: :eq, value: 0)

    design =
      Design.fold([
        chart(meta: %{name: title(), description: [description()]}),
        source(:nodes, Design.hierarchy_fields()),
        style(:cell, fill: {:field, :branch}, stroke: :background, stroke_width: 1),
        style(:cell_label, extends: :label, fill: :contrast, font_size: 10),
        cartesian(margin: @zero_margin),
        ordinal_scale(:color, domain: Enum.to_list(0..(branches - 1)//1)),
        rect(leaves, %{x0: :x0, x1: :x1, y0: :y0, y1: :y1},
          label: %{text: [{:field, :name}], anchor: :middle, fit: :truncate, style: :cell_label},
          style: :cell
        )
      ])

    {design, %{nodes: rows(tree, opts[:animation_tick])}}
  end

  def render(opts \\ []), do: Design.render(__MODULE__, opts)

  defp rows(tree, nil), do: Design.nodes(tree)

  # Animation: each leaf's value breathes about its own with its own phase.
  defp rows(tree, tick) do
    phase = tick * 0.06

    tree
    |> Design.nodes()
    |> Enum.with_index()
    |> Enum.map(fn
      {%{value: value} = row, i} when value > 0 ->
        %{row | value: trunc(max(500, value + :math.sin(phase + i * 0.5) * value / 4))}

      {row, _i} ->
        row
    end)
  end

  def sample_code do
    ~S"""
    import Visualize.Chart.Build

    {:ok, design} =
      Visualize.Chart.compose([
        chart(meta: %{name: "Treemap"}),
        source(:nodes, [:id, :parent, :name, :value, :branch]),
        style(:cell, fill: {:field, :branch}, stroke: :background, stroke_width: 1),
        style(:cell_label, extends: :label, fill: :contrast, font_size: 10),
        cartesian(margin: %{top: 0, right: 0, bottom: 0, left: 0}),
        # One color per child of the root; every cell takes its branch's (D-46).
        ordinal_scale(:color, domain: [0, 1, 2, 3, 4, 5, 6, 7]),
        # The squarified layout, then the leaves alone (spec/14 §5.4.2).
        rect(
          from(:nodes)
          |> treemap(id: :id, by: :parent, field: :value, padding: 2)
          |> filter(:height, test: :eq, value: 0),
          %{x0: :x0, x1: :x1, y0: :y0, y1: :y1},
          label: %{text: [{:field, :name}], anchor: :middle, fit: :truncate, style: :cell_label},
          style: :cell
        )
      ])

    # nodes: one row per node — id, parent (nil for the root), name, value, branch.
    {:ok, applied} = Visualize.Chart.apply(design, sources: %{nodes: nodes})
    Visualize.Chart.render(applied)
    """
  end
end
