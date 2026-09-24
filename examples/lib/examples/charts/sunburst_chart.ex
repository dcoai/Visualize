defmodule Examples.Charts.SunburstChart do
  @moduledoc """
  Sunburst chart as a design (#126): a `:partition` transform under one `:arc` mark.

  The radial partition is a step of the mark's data pipeline (spec/14 §5.4.2), and the
  `:arc` reads its four columns directly — `start` and `end` are the sector's own angles and
  `inner` and `outer` its own radii, so no pie is computed (D-69). Two `:filter` steps drop
  the root and the empty sectors, which is the whole of what the hand-written version's
  `if depth == 0` did.

  The nested map reaches the design as a flat node list, which is the shape a hierarchy
  transform reads and the shape `Visualize.Chart.Presets` maps a component's tree into.

  Two deliberate differences from the hand-built version, neither an approximation:

  - **Colour follows the branch**, as `Visualize.Chart.Presets.sunburst_chart/1` does — the
    root child a node descends from. The hand-written scheme gave every node below the first
    ring a darkened shade of one colour, so the outer ring told you nothing.
  - **Labels are fitted to their sector** with `fit: :truncate` (spec/14 §5.5, #138): cut
    to the characters the arc's length at the label's radius holds, ending in `…`.
  """

  import Visualize.Chart.Build

  alias Examples.Charts.Design

  @zero_margin %{top: 0, right: 0, bottom: 0, left: 0}

  @data %{
    name: "root",
    children: [
      %{
        name: "Tech",
        children: [
          %{name: "Software", value: 400},
          %{name: "Hardware", value: 300},
          %{name: "Services", value: 200}
        ]
      },
      %{
        name: "Finance",
        children: [
          %{name: "Banking", value: 350},
          %{name: "Insurance", value: 250}
        ]
      },
      %{
        name: "Health",
        children: [
          %{name: "Pharma", value: 280},
          %{name: "Biotech", value: 180},
          %{name: "Devices", value: 120}
        ]
      },
      %{
        name: "Energy",
        children: [
          %{name: "Oil", value: 220},
          %{name: "Renewable", value: 160}
        ]
      }
    ]
  }

  @doc "The size this chart is drawn at when the caller names none (spec/14 §4.2)."
  def size, do: {500, 500}

  def title, do: "Sunburst Chart"
  def description, do: "Radial hierarchical partition"

  @doc "The design and the rows it binds (spec/14 §16.1)."
  def design(opts \\ []) do
    {width, height} = Design.size(__MODULE__, opts)
    tree = nodes(opts)
    branches = length(children(tree))

    # The nodes below the root with a positive extent, each arc over its own angles.
    data =
      from(:nodes)
      |> partition(
        id: :id,
        by: :parent,
        field: :value,
        size: [2 * :math.pi(), min(width, height) / 2 - 10]
      )
      |> filter(:depth, test: :gt, value: 0)
      |> filter(:value, test: :gt, value: 0)

    design =
      Design.fold([
        chart(meta: %{name: title(), description: [description()]}),
        source(:nodes, Design.hierarchy_fields()),
        style(:sector, fill: {:field, :branch}, stroke: :background, stroke_width: 1),
        style(:sector_label,
          extends: :label,
          fill: :background,
          font_size: 10,
          font_weight: :bold
        ),
        polar(margin: @zero_margin),
        ordinal_scale(:color, domain: Enum.to_list(0..(branches - 1)//1)),
        arc(data, %{start: :x0, end: :x1, inner: :y0, outer: :y1},
          label: %{text: [{:field, :name}], anchor: :middle, fit: :truncate, style: :sector_label},
          style: :sector
        )
      ])

    {design, %{nodes: Design.nodes(tree)}}
  end

  def render(opts \\ []), do: Design.render(__MODULE__, opts)

  defp nodes(opts) do
    case opts[:animation_tick] do
      nil -> opts[:data] || @data
      tick -> animated(tick)
    end
  end

  defp children(node), do: node[:children] || []

  # Animation: vary sector values with smooth waves.
  defp animated(tick) do
    phase = tick * 0.06

    %{
      name: "root",
      children: [
        %{
          name: "Tech",
          children: [
            %{name: "Software", value: wave(400, phase, 0, 100)},
            %{name: "Hardware", value: wave(300, phase, 0.8, 80)},
            %{name: "Services", value: wave(200, phase, 1.6, 60)}
          ]
        },
        %{
          name: "Finance",
          children: [
            %{name: "Banking", value: wave(350, phase, 2.4, 90)},
            %{name: "Insurance", value: wave(250, phase, 3.2, 70)}
          ]
        },
        %{
          name: "Health",
          children: [
            %{name: "Pharma", value: wave(280, phase, 4.0, 75)},
            %{name: "Biotech", value: wave(180, phase, 4.8, 50)},
            %{name: "Devices", value: wave(120, phase, 5.6, 35)}
          ]
        },
        %{
          name: "Energy",
          children: [
            %{name: "Oil", value: wave(220, phase, 6.4, 60)},
            %{name: "Renewable", value: wave(160, phase, 7.2, 50)}
          ]
        }
      ]
    }
  end

  defp wave(base, phase, offset, amplitude) do
    trunc(max(30, base + :math.sin(phase + offset) * amplitude))
  end

  def sample_code do
    ~S"""
    import Visualize.Chart.Build

    # The tree reaches the design as a flat node list, which is what a hierarchy reads.
    rows = [
      %{id: "0", parent: nil, name: "root", value: 0, branch: nil},
      %{id: "0.0", parent: "0", name: "Tech", value: 0, branch: 0},
      %{id: "0.0.0", parent: "0.0", name: "Software", value: 400, branch: 0},
      ...
    ]

    # The layout is a step of the mark's pipeline; the two filters drop the root and the
    # empty sectors.
    data =
      from(:nodes)
      |> partition(id: :id, by: :parent, field: :value, size: [2 * :math.pi(), 240])
      |> filter(:depth, test: :gt, value: 0)
      |> filter(:value, test: :gt, value: 0)

    {:ok, design} =
      Visualize.Chart.compose([
        chart(meta: %{name: "Sunburst Chart"}),
        source(:nodes, [:id, :parent, :name, :value, :branch]),
        style(:sector, fill: {:field, :branch}, stroke: :background, stroke_width: 1),
        style(:sector_label, extends: :label, fill: :background, font_size: 10, font_weight: :bold),
        polar(margin: %{top: 0, right: 0, bottom: 0, left: 0}),
        ordinal_scale(:color, domain: [0, 1, 2, 3]),

        # `start`/`end` and `inner`/`outer` are the sector's own angles and radii: no pie.
        arc(data, %{start: :x0, end: :x1, inner: :y0, outer: :y1},
          label: %{text: [{:field, :name}], anchor: :middle, fit: :truncate, style: :sector_label},
          style: :sector
        )
      ])

    {:ok, applied} = Visualize.Chart.apply(design, sources: %{nodes: rows})
    Visualize.Chart.render(applied)
    """
  end
end
