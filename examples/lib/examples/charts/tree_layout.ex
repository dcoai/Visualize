defmodule Examples.Charts.TreeLayout do
  @moduledoc """
  Tree layout as a design (#127): a `:tree` transform under a `:path` mark for the links
  and two `:circle` marks for the nodes.

  The Reingold–Tilford layout is a step of each mark's data pipeline (spec/14 §5.4.2): the
  `:path` mark reads the `:links` rows, each a ready cubic from parent to child, and the
  `:circle` marks read the `:nodes` rows' own `x` and `y`, in pixels of the plot, through
  no scale. The nodes are split by a `:filter` on `height` so the people with reports are
  named above their circle and the leaves below theirs — one anchor per mark, as
  `Visualize.Chart.Presets.tree_diagram/1` labels its nodes. The nested map reaches the
  design as a flat node list through `Examples.Charts.Design.nodes/1`; each row also
  carries `r`, the circle's radius, which the animation pulses.
  """

  import Visualize.Chart.Build

  alias Examples.Charts.Design

  @margin %{top: 40, right: 40, bottom: 40, left: 40}
  @radius 6

  @data %{
    name: "CEO",
    children: [
      %{
        name: "CTO",
        children: [
          %{
            name: "Dev Lead",
            children: [
              %{name: "Dev 1"},
              %{name: "Dev 2"},
              %{name: "Dev 3"}
            ]
          },
          %{
            name: "QA Lead",
            children: [
              %{name: "QA 1"},
              %{name: "QA 2"}
            ]
          }
        ]
      },
      %{
        name: "CFO",
        children: [
          %{name: "Accounting"},
          %{name: "Finance"}
        ]
      },
      %{
        name: "COO",
        children: [
          %{name: "HR"},
          %{
            name: "Operations",
            children: [
              %{name: "Ops 1"},
              %{name: "Ops 2"}
            ]
          }
        ]
      }
    ]
  }

  def title, do: "Tree Layout"
  def description, do: "Organization hierarchy"

  @doc "The design and the rows it binds (spec/14 §16.1)."
  def design(opts \\ []) do
    width = opts[:width] || 700
    height = opts[:height] || 400
    tree = opts[:data] || @data

    layout = [id: :id, by: :parent]
    nodes = tree(from(:nodes), layout)
    links = tree(from(:nodes), layout ++ [output: :links])

    design =
      Design.fold([
        chart(meta: %{name: title(), description: [description()]}),
        source(:nodes, Design.hierarchy_fields() ++ [:r]),
        style(:link, fill: :none, stroke: :grid, stroke_width: 1.5),
        style(:manager, fill: :series_1, stroke: :background, stroke_width: 2),
        style(:report, fill: :background, stroke: :series_1, stroke_width: 2),
        style(:name, extends: :label, font_size: 10),
        cartesian(width, height, margin: @margin),
        path(links, %{path: :path}, style: :link),
        # Those with reports named above their circle, the leaves below theirs.
        circle(filter(nodes, :height, test: :gt, value: 0), %{x: :x, y: :y, value: :r},
          label: %{text: [{:field, :name}], anchor: :top, dy: -4, style: :name},
          style: :manager
        ),
        circle(filter(nodes, :height, test: :eq, value: 0), %{x: :x, y: :y, value: :r},
          label: %{text: [{:field, :name}], anchor: :bottom, dy: 4, style: :name},
          style: :report
        )
      ])

    {design, %{nodes: rows(tree, opts[:animation_tick])}}
  end

  def render(opts \\ []), do: Design.render(__MODULE__, opts)

  defp rows(tree, nil), do: Enum.map(Design.nodes(tree), &Map.put(&1, :r, @radius))

  # Animation: each node's radius pulses with its own phase.
  defp rows(tree, tick) do
    phase = tick * 0.08

    tree
    |> Design.nodes()
    |> Enum.with_index()
    |> Enum.map(fn {row, i} -> Map.put(row, :r, @radius + :math.sin(phase + i * 0.3) * 2) end)
  end

  def sample_code do
    ~S"""
    import Visualize.Chart.Build

    nodes = tree(from(:nodes), id: :id, by: :parent)
    links = tree(from(:nodes), id: :id, by: :parent, output: :links)

    {:ok, design} =
      Visualize.Chart.compose([
        chart(meta: %{name: "Tree Layout"}),
        source(:nodes, [:id, :parent, :name, :value, :branch, :r]),
        style(:link, fill: :none, stroke: :grid, stroke_width: 1.5),
        style(:manager, fill: :series_1, stroke: :background, stroke_width: 2),
        style(:report, fill: :background, stroke: :series_1, stroke_width: 2),
        style(:name, extends: :label, font_size: 10),
        cartesian(700, 400, margin: %{top: 40, right: 40, bottom: 40, left: 40}),
        # The links are ready cubics, stroked and unfilled; the nodes' x and y are pixels
        # (spec/14 §5.4.2).
        path(links, %{path: :path}, style: :link),
        circle(filter(nodes, :height, test: :gt, value: 0), %{x: :x, y: :y, value: :r},
          label: %{text: [{:field, :name}], anchor: :top, dy: -4, style: :name},
          style: :manager
        ),
        circle(filter(nodes, :height, test: :eq, value: 0), %{x: :x, y: :y, value: :r},
          label: %{text: [{:field, :name}], anchor: :bottom, dy: 4, style: :name},
          style: :report
        )
      ])

    # nodes: one row per node — id, parent (nil for the root), name, value, branch, r.
    {:ok, applied} = Visualize.Chart.apply(design, sources: %{nodes: nodes})
    Visualize.Chart.render(applied)
    """
  end
end
