defmodule Examples.Charts.ClusterDendrogram do
  @moduledoc """
  Cluster dendrogram as a design (#127): a `:cluster` transform under a `:path` mark for
  the links and two `:circle` marks for the nodes.

  The cluster layout puts every leaf at the same depth (spec/14 §5.4.2) and is a step of
  each mark's data pipeline. The tree is drawn **horizontally** — the root at the left,
  the leaves in a column at the right where their names have room — which is
  `size: [height, width]` with `orientation: :horizontal` and the `:circle` marks reading
  `x` from the layout's `y` (D-70); its links take the dendrogram's **elbow**
  (`link: :elbow`), across at the parent's depth and then to the child, so the branches of
  one parent leave it as one line. The nodes are split by a `:filter` on `height`: the
  clades named to the left of their circle, the leaves to the right. The nested map reaches
  the design as a flat node list through `Examples.Charts.Design.nodes/1`; each row also
  carries `r`, the circle's radius, which the animation pulses.
  """

  import Visualize.Chart.Build

  alias Examples.Charts.Design

  @margin %{top: 20, right: 120, bottom: 20, left: 60}
  @radius 4

  @data %{
    name: "Life",
    children: [
      %{
        name: "Archaea",
        children: [
          %{name: "Euryarchaeota"},
          %{name: "Crenarchaeota"},
          %{name: "Korarchaeota"}
        ]
      },
      %{
        name: "Bacteria",
        children: [
          %{name: "Proteobacteria"},
          %{name: "Cyanobacteria"},
          %{name: "Firmicutes"},
          %{name: "Actinobacteria"}
        ]
      },
      %{
        name: "Eukaryota",
        children: [
          %{
            name: "Animals",
            children: [
              %{name: "Mammals"},
              %{name: "Birds"},
              %{name: "Reptiles"},
              %{name: "Fish"}
            ]
          },
          %{
            name: "Plants",
            children: [
              %{name: "Flowering"},
              %{name: "Conifers"},
              %{name: "Ferns"}
            ]
          },
          %{
            name: "Fungi",
            children: [
              %{name: "Ascomycota"},
              %{name: "Basidiomycota"}
            ]
          }
        ]
      }
    ]
  }

  @doc "The size this chart is drawn at when the caller names none (spec/14 §4.2)."
  def size, do: {700, 400}

  def title, do: "Cluster Dendrogram"
  def description, do: "Tree of life classification"

  @doc "The design and the rows it binds (spec/14 §16.1)."
  def design(opts \\ []) do
    {width, height} = Design.size(__MODULE__, opts)
    tree = opts[:data] || @data
    {plot_width, plot_height} = Design.plot(width, height, @margin)

    # Horizontal: the layout runs across the plot's height and down its width (D-70).
    layout = [id: :id, by: :parent, size: [plot_height, plot_width], orientation: :horizontal]
    nodes = cluster(from(:nodes), layout)
    links = cluster(from(:nodes), layout ++ [output: :links, link: :elbow])
    channels = %{x: :y, y: :x, value: :r}

    design =
      Design.fold([
        chart(meta: %{name: title(), description: [description()]}),
        source(:nodes, Design.hierarchy_fields() ++ [:r]),
        style(:link, fill: :none, stroke: :axis, stroke_width: 1),
        style(:clade, fill: :axis, stroke: :background, stroke_width: 1),
        style(:leaf, fill: {:field, :branch}, stroke: :background, stroke_width: 1),
        style(:clade_name, extends: :label, fill: :axis, font_size: 9),
        style(:leaf_name, extends: :label, font_size: 9),
        cartesian(margin: @margin),
        ordinal_scale(:color, domain: Enum.to_list(0..(length(tree[:children] || []) - 1)//1)),
        path(links, %{path: :path}, style: :link),
        # The clades named to the left of their circle, the leaves to the right.
        circle(filter(nodes, :height, test: :gt, value: 0), channels,
          label: %{text: [{:field, :name}], anchor: :left, dx: -4, style: :clade_name},
          style: :clade
        ),
        circle(filter(nodes, :height, test: :eq, value: 0), channels,
          label: %{text: [{:field, :name}], anchor: :right, dx: 4, style: :leaf_name},
          style: :leaf
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
    |> Enum.map(fn {row, i} ->
      Map.put(row, :r, @radius + :math.sin(phase + i * 0.25) * 1.5)
    end)
  end

  def sample_code do
    ~S"""
    import Visualize.Chart.Build

    # Horizontal: the layout runs across the plot's height and down its width (D-70).
    layout = [id: :id, by: :parent, size: [360, 520], orientation: :horizontal]
    nodes = cluster(from(:nodes), layout)
    links = cluster(from(:nodes), layout ++ [output: :links, link: :elbow])

    {:ok, design} =
      Visualize.Chart.compose([
        chart(meta: %{name: "Cluster Dendrogram"}),
        source(:nodes, [:id, :parent, :name, :value, :branch, :r]),
        style(:link, fill: :none, stroke: :axis, stroke_width: 1),
        style(:clade, fill: :axis, stroke: :background),
        style(:leaf, fill: {:field, :branch}, stroke: :background),
        style(:clade_name, extends: :label, fill: :axis, font_size: 9),
        style(:leaf_name, extends: :label, font_size: 9),
        cartesian(margin: %{top: 20, right: 120, bottom: 20, left: 60}),
        ordinal_scale(:color, domain: [0, 1, 2]),
        # The dendrogram's elbows (spec/14 §5.4.2), then the nodes with x from the
        # layout's y and their names to the left of a clade and the right of a leaf.
        path(links, %{path: :path}, style: :link),
        circle(filter(nodes, :height, test: :gt, value: 0), %{x: :y, y: :x, value: :r},
          label: %{text: [{:field, :name}], anchor: :left, dx: -4, style: :clade_name},
          style: :clade
        ),
        circle(filter(nodes, :height, test: :eq, value: 0), %{x: :y, y: :x, value: :r},
          label: %{text: [{:field, :name}], anchor: :right, dx: 4, style: :leaf_name},
          style: :leaf
        )
      ])

    # nodes: one row per node — id, parent (nil for the root), name, value, branch, r.
    {:ok, applied} = Visualize.Chart.apply(design, sources: %{nodes: nodes})
    Visualize.Chart.render(applied)
    """
  end
end
