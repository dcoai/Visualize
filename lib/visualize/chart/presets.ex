defmodule Visualize.Chart.Presets do
  @moduledoc """
  The ten LiveView components as stored designs (spec/14 §15, D-64).

  Each preset is a function from a component's assigns — the keys of its table in spec/10,
  an absent one taking `defaults/1` — to a design map of spec/14: no function reaches the
  map, because the accessor assigns are applied once by `sources/2`, the *assign mapping*,
  into the rows the design's one source (`data`) binds to. `Visualize.Components` and
  `Visualize.Components.Tree` render these designs through `Visualize.Chart.Frame`; a
  design is also a value of its own, storable and bindable to any source with the same
  columns.

  ## Examples

      iex> design =
      ...>   Visualize.Chart.Presets.bar_chart(%{
      ...>     data: [%{name: "a", value: 3}, %{name: "b", value: 5}],
      ...>     x: & &1.name,
      ...>     y: & &1.value
      ...>   })
      iex> design.frames.main.scales
      %{x: %{kind: :band, padding: 0.1}, y: %{kind: :linear, domain: [0, :auto]}}
      iex> hd(design.marks).channels
      %{x0: :x, x1: :x, y0: 0, y1: :y}
      iex> {:ok, _chart} = Visualize.Chart.from_map(design)
      iex> Visualize.Chart.Presets.sources(
      ...>   :bar_chart,
      ...>   %{data: [%{name: "a", value: 3}], x: & &1.name, y: & &1.value}
      ...> )
      %{data: [%{x: "a", y: 3}]}

  """

  import Visualize.Chart.Build

  alias Visualize.Chart
  alias Visualize.Data.Table

  @names [
    :line_chart,
    :bar_chart,
    :horizontal_bar_chart,
    :pie_chart,
    :scatter_plot,
    :area_chart,
    :stacked_bar_chart,
    :tree_diagram,
    :treemap_chart,
    :sunburst_chart
  ]

  @default_margin %{top: 20, right: 20, bottom: 30, left: 40}
  @horizontal_margin %{top: 20, right: 20, bottom: 30, left: 100}
  @tree_margin %{top: 20, right: 120, bottom: 20, left: 120}

  # The assigns every component shares (spec/10 §1.2).
  @shell %{
    animate: false,
    class: nil,
    responsive: false,
    theme: nil,
    title: nil,
    description: nil
  }

  @defaults %{
    line_chart: %{
      width: 600,
      height: 400,
      margin: @default_margin,
      curve: :linear,
      stroke: nil,
      stroke_width: 2,
      show_points: false,
      x_label: nil,
      y_label: nil
    },
    bar_chart: %{width: 600, height: 400, margin: @default_margin, fill: nil, padding: 0.1},
    horizontal_bar_chart: %{
      width: 600,
      height: 400,
      margin: @horizontal_margin,
      fill: nil,
      padding: 0.1
    },
    pie_chart: %{
      label: nil,
      width: 400,
      height: 400,
      inner_radius: 0,
      outer_radius: nil,
      pad_angle: 0.02,
      colors: :category10,
      show_labels: true
    },
    scatter_plot: %{width: 600, height: 400, margin: @default_margin, fill: nil, size: 5},
    area_chart: %{
      width: 600,
      height: 400,
      margin: @default_margin,
      fill: nil,
      fill_opacity: 0.3,
      stroke: nil,
      stroke_width: 2,
      curve: :linear
    },
    stacked_bar_chart: %{
      width: 600,
      height: 400,
      margin: @default_margin,
      colors: :category10,
      padding: 0.1
    },
    tree_diagram: %{
      width: 800,
      height: 600,
      margin: @tree_margin,
      orientation: :horizontal,
      node_radius: 6,
      node_fill: nil,
      node_stroke: nil,
      link_stroke: nil,
      label: nil
    },
    treemap_chart: %{
      width: 800,
      height: 600,
      value: nil,
      label: nil,
      tile: :squarify,
      padding: 2,
      colors: :category10
    },
    sunburst_chart: %{width: 600, height: 600, value: nil, label: nil, colors: :category10}
  }

  @zero_margin %{top: 0, right: 0, bottom: 0, left: 0}
  @hierarchy_fields [:id, :parent, :label, :value, :branch]
  @temporal [DateTime, NaiveDateTime, Date]
  @hierarchies [:tree_diagram, :treemap_chart, :sunburst_chart]

  @typedoc "A preset name: one of `names/0`."
  @type name ::
          :line_chart
          | :bar_chart
          | :horizontal_bar_chart
          | :pie_chart
          | :scatter_plot
          | :area_chart
          | :stacked_bar_chart
          | :tree_diagram
          | :treemap_chart
          | :sunburst_chart

  @typedoc "A component's assigns: the keys of its table in spec/10."
  @type assigns :: %{optional(atom()) => term()}

  @doc "The ten preset names in the order of spec/10 §2.1 and §3.1."
  @spec names() :: [name()]
  def names, do: @names

  @doc """
  The assigns a component's table defaults (spec/10 §2–3), as a map: the one place the
  numbers live, which the components' `attr/3` declarations read.
  """
  @spec defaults(name()) :: assigns()
  def defaults(name) when name in @names, do: Map.merge(@shell, Map.fetch!(@defaults, name))
  def defaults(name), do: unknown!(name)

  @doc "The design of the named preset: the function of that name over `assigns`."
  @spec design(name(), assigns()) :: map()
  def design(name, assigns) when name in @names, do: apply(__MODULE__, name, [assigns])
  def design(name, _assigns), do: unknown!(name)

  @doc """
  The assign mapping (spec/14 §15.2): `%{data: rows}`, the rows the design's source binds
  to — the accessor assigns applied to each row of `data`, or the nested map flattened to
  one row per node for a hierarchy preset.
  """
  @spec sources(name(), assigns()) :: %{data: [map()]}
  def sources(name, assigns) when name in @names, do: %{data: rows(name, assigns(name, assigns))}
  def sources(name, _assigns), do: unknown!(name)

  # -- the chart presets (spec/14 §15.3) --------------------------------------------------

  @doc "The `line_chart` design (spec/14 §15.3, spec/10 §2.2)."
  @spec line_chart(assigns()) :: map()
  def line_chart(assigns) do
    a = assigns(:line_chart, assigns)
    stroke = colour(a.stroke, :series_1)

    points =
      if a.show_points,
        do: [circle(:data, %{x: :x, y: :y}, options: %{radius: 4}, style: :point)],
        else: []

    fold(
      seed(a, [:x, :y]) ++
        [
          style(:line, stroke: stroke, stroke_width: a.stroke_width, curve: a.curve),
          style(:point, fill: stroke),
          cartesian(margin: margin(a)),
          x_scale(a),
          linear_scale(:y),
          axis(:x, :bottom),
          axis(:y, :left),
          line(:data, %{x: :x, y: :y}, style: :line)
        ] ++ points ++ axis_labels(a)
    )
  end

  @doc "The `bar_chart` design (spec/14 §15.3, spec/10 §2.3)."
  @spec bar_chart(assigns()) :: map()
  def bar_chart(assigns) do
    a = assigns(:bar_chart, assigns)

    fold(
      seed(a, [:x, :y]) ++
        [
          style(:bar, fill: colour(a.fill, :series_1)),
          cartesian(margin: margin(a)),
          band_scale(:x, padding: a.padding),
          linear_scale(:y, domain: [0, :auto]),
          axis(:x, :bottom),
          axis(:y, :left),
          rect(:data, %{x0: :x, x1: :x, y0: 0, y1: :y}, style: :bar)
        ]
    )
  end

  @doc "The `horizontal_bar_chart` design (spec/14 §15.3, spec/10 §2.4)."
  @spec horizontal_bar_chart(assigns()) :: map()
  def horizontal_bar_chart(assigns) do
    a = assigns(:horizontal_bar_chart, assigns)
    {_width, height} = plot(a)

    # The `y` range is fixed because `:auto` runs upward and the categories read downward.
    fold(
      seed(a, [:x, :y]) ++
        [
          style(:bar, fill: colour(a.fill, :series_1)),
          cartesian(margin: margin(a)),
          linear_scale(:x, domain: [0, :auto]),
          band_scale(:y, padding: a.padding, range: [0, height]),
          axis(:x, :bottom),
          axis(:y, :left),
          rect(:data, %{x0: 0, x1: :x, y0: :y, y1: :y}, style: :bar)
        ]
    )
  end

  @doc "The `pie_chart` design (spec/14 §15.3, spec/10 §2.5)."
  @spec pie_chart(assigns()) :: map()
  def pie_chart(assigns) do
    a = assigns(:pie_chart, assigns)
    labelled? = a.label != nil
    outer = a.outer_radius || min(a.width, a.height) / 2 - 10

    opts = [
      options: %{inner_radius: a.inner_radius, outer_radius: outer, pad_angle: a.pad_angle},
      style: :slice
    ]

    label = %{text: [{:field, :label}], anchor: :middle, style: :slice_label}
    opts = if labelled? and a.show_labels, do: Keyword.put(opts, :label, label), else: opts

    fold(
      seed(a, [:value, :index] ++ if(labelled?, do: [:label], else: [])) ++
        [
          style(:slice, fill: {:field, :index}, stroke: :background, stroke_width: 2),
          style(:slice_label, fill: :background, font_size: :label_size),
          polar(margin: @zero_margin),
          ordinal_scale(:color, range: a.colors),
          arc(:data, %{value: :value}, opts)
        ]
    )
  end

  @doc "The `scatter_plot` design (spec/14 §15.3, spec/10 §2.6)."
  @spec scatter_plot(assigns()) :: map()
  def scatter_plot(assigns) do
    a = assigns(:scatter_plot, assigns)

    fold(
      seed(a, [:x, :y, :r]) ++
        [
          style(:point, fill: colour(a.fill, :series_1), opacity: 0.7),
          cartesian(margin: margin(a)),
          linear_scale(:x),
          linear_scale(:y),
          axis(:x, :bottom),
          axis(:y, :left),
          circle(:data, %{x: :x, y: :y, value: :r}, style: :point)
        ]
    )
  end

  @doc "The `area_chart` design (spec/14 §15.3, spec/10 §2.7)."
  @spec area_chart(assigns()) :: map()
  def area_chart(assigns) do
    a = assigns(:area_chart, assigns)

    fold(
      seed(a, [:x, :y]) ++
        [
          style(:area,
            fill: colour(a.fill, :series_1),
            fill_opacity: a.fill_opacity,
            curve: a.curve
          ),
          style(:line,
            stroke: colour(a.stroke, :series_1),
            stroke_width: a.stroke_width,
            curve: a.curve
          ),
          cartesian(margin: margin(a)),
          x_scale(a),
          linear_scale(:y, domain: [0, :auto]),
          axis(:x, :bottom),
          axis(:y, :left),
          area(:data, %{x: :x, y: :y}, style: :area),
          line(:data, %{x: :x, y: :y}, style: :line)
        ]
    )
  end

  @doc "The `stacked_bar_chart` design (spec/14 §15.3, spec/10 §2.8)."
  @spec stacked_bar_chart(assigns()) :: map()
  def stacked_bar_chart(assigns) do
    a = assigns(:stacked_bar_chart, assigns)
    keys = Map.fetch!(a, :keys)

    fold(
      seed(a, [:x | keys]) ++
        [
          style(:segment, fill: {:field, :key}),
          cartesian(margin: margin(a)),
          band_scale(:x, padding: a.padding),
          linear_scale(:y, domain: [0, :auto]),
          ordinal_scale(:color, domain: keys, range: a.colors),
          axis(:x, :bottom),
          axis(:y, :left),
          rect(stack(from(:data), keys), %{x0: :x, x1: :x, y0: :y0, y1: :y1}, style: :segment)
        ]
    )
  end

  # -- the hierarchy presets (spec/14 §15.4) ----------------------------------------------

  @doc "The `tree_diagram` design (spec/14 §15.4, spec/10 §3.2)."
  @spec tree_diagram(assigns()) :: map()
  def tree_diagram(assigns) do
    a = assigns(:tree_diagram, assigns)
    {width, height} = plot(a)

    {size, channels} =
      case a.orientation do
        :horizontal -> {[height, width], %{x: :y, y: :x}}
        :vertical -> {[width, height], %{x: :x, y: :y}}
      end

    layout = [id: :id, by: :parent, size: size, orientation: a.orientation]

    # The node's text is the nearest the layer has to the component's circle-and-text
    # group, whose anchor and offset follow the node (spec/14 §15.4, D-70).
    fold(
      seed(a, @hierarchy_fields) ++
        [
          style(:link, fill: :none, stroke: colour(a.link_stroke, :grid), stroke_width: 1.5),
          style(:node,
            fill: colour(a.node_fill, :background),
            stroke: colour(a.node_stroke, :series_1),
            stroke_width: 2
          ),
          cartesian(margin: margin(a)),
          path(tree(from(:data), layout ++ [output: :links]), %{path: :path}, style: :link),
          circle(tree(from(:data), layout ++ [output: :nodes]), channels,
            options: %{radius: a.node_radius},
            label: %{text: [{:field, :label}], anchor: :middle},
            style: :node
          )
        ]
    )
  end

  @doc "The `treemap_chart` design (spec/14 §15.4, spec/10 §3.3)."
  @spec treemap_chart(assigns()) :: map()
  def treemap_chart(assigns) do
    a = assigns(:treemap_chart, assigns)

    # The leaves alone (spec/10 §3.3).
    data =
      from(:data)
      |> treemap(id: :id, by: :parent, field: :value, padding: a.padding, tile: a.tile)
      |> filter(:height, test: :eq, value: 0)

    fold(
      seed(a, @hierarchy_fields) ++
        [
          style(:cell, fill: {:field, :branch}, stroke: :background, stroke_width: 1),
          cartesian(margin: margin(a)),
          branch_scale(a),
          rect(data, %{x0: :x0, x1: :x1, y0: :y0, y1: :y1}, style: :cell)
        ]
    )
  end

  @doc "The `sunburst_chart` design (spec/14 §15.4, spec/10 §3.4)."
  @spec sunburst_chart(assigns()) :: map()
  def sunburst_chart(assigns) do
    a = assigns(:sunburst_chart, assigns)
    radius = min(a.width, a.height) / 2

    # The nodes below the root with a positive extent (spec/10 §3.4), each arc over its
    # own angles (D-69) and labelled at its centroid as the pie is.
    data =
      from(:data)
      |> partition(id: :id, by: :parent, field: :value, size: [2 * :math.pi(), radius])
      |> filter(:depth, test: :gt, value: 0)
      |> filter(:value, test: :gt, value: 0)

    fold(
      seed(a, @hierarchy_fields) ++
        [
          style(:arc, fill: {:field, :branch}, stroke: :background, stroke_width: 1),
          style(:arc_label, fill: :background, font_size: :label_size),
          polar(margin: @zero_margin),
          branch_scale(a),
          arc(data, %{start: :x0, end: :x1, inner: :y0, outer: :y1},
            label: %{text: [{:field, :label}], anchor: :middle, style: :arc_label},
            style: :arc
          )
        ]
    )
  end

  # -- the fold (spec/14 §16.7) -----------------------------------------------------------

  # The fragments of a preset folded into its design; a preset writes no design node of its
  # own, so a fault here is a fault of `Visualize.Chart.compose/2`, not of a preset.
  defp fold(fragments) do
    {:ok, design} = Chart.compose(fragments)
    design
  end

  # The three fragments every preset opens with: the seed with its meta, the one source and
  # the theme, which reaches the frame as an option rather than as a design key (§15.3).
  defp seed(a, fields) do
    meta =
      %{}
      |> put_if(a.title != nil, :name, a.title)
      |> put_if(a.description != nil, :description, [a.description])

    seed = if meta == %{}, do: chart(), else: chart(meta: meta)
    [seed, source(:data, fields), theme(:default)]
  end

  defp axis_labels(a) do
    for {scale, text} <- [x: a.x_label, y: a.y_label], text != nil do
      label({:axis, scale}, [text])
    end
  end

  defp put_if(map, true, key, value), do: Map.put(map, key, value)
  defp put_if(map, false, _key, _value), do: map

  # The margin merged over the component's default (spec/10 §1.2); a hierarchy without a
  # `margin` assign fills its `<svg>`.
  defp margin(a) do
    Map.merge(Map.get(@defaults[a.preset], :margin, @zero_margin), Map.get(a, :margin) || %{})
  end

  defp plot(a) do
    m = margin(a)
    {a.width - m.left - m.right, a.height - m.top - m.bottom}
  end

  # A colour assign: the literal as given, or the theme slot when `nil` (spec/10 §1.2).
  defp colour(nil, slot), do: slot
  defp colour(value, _slot), do: value

  # The `x` scale of a series chart, decided by the first datum (spec/10 §2.2): one of the
  # two choices the assigns force on the design (spec/14 §16.7).
  defp x_scale(a) do
    case Map.get(a, :data, []) |> Table.rows() |> Enum.take(1) do
      [] -> linear_scale(:x)
      [first] -> x_kind(Map.fetch!(a, :x).(first))
    end
  end

  defp x_kind(%mod{}) when mod in @temporal, do: time_scale(:x)
  defp x_kind(n) when is_number(n), do: linear_scale(:x)
  defp x_kind(_category), do: band_scale(:x, padding: 0.1)

  # The colour scale of a hierarchy: one index per child of the root (D-46) — the other
  # choice the assigns force.
  defp branch_scale(a) do
    n = length(children(Map.get(a, :data, %{})))
    ordinal_scale(:color, domain: Enum.to_list(0..(n - 1)//1), range: a.colors)
  end

  # -- the assign mapping (spec/14 §15.2) -------------------------------------------------

  defp rows(name, a) when name in @hierarchies do
    label = Map.get(a, :label) || (&node_name/1)
    value = Map.get(a, :value) || (&leaf_value/1)
    flatten(Map.get(a, :data, %{}), "0", nil, nil, label, value)
  end

  defp rows(name, a) do
    Enum.with_index(Table.rows(Map.get(a, :data, [])), fn d, i -> row(name, a, d, i) end)
  end

  defp row(:scatter_plot, a, d, _i), do: %{x: a.x.(d), y: a.y.(d), r: radius(a.size, d)}

  defp row(:stacked_bar_chart, a, d, _i) do
    Map.new([{:x, a.x.(d)} | Enum.map(Map.fetch!(a, :keys), &{&1, Table.get(d, &1)})])
  end

  defp row(:pie_chart, a, d, i) do
    %{value: a.value.(d), index: i} |> put_if(a.label != nil, :label, a.label && a.label.(d))
  end

  defp row(_chart, a, d, _i), do: %{x: a.x.(d), y: a.y.(d)}

  defp radius(size, _d) when is_number(size), do: size
  defp radius(size, d) when is_function(size, 1), do: size.(d)

  # One row per node in pre-order: the dotted position as `id`, the parent's, the label
  # and value accessors applied to the node, and the root's child it descends from.
  defp flatten(node, id, parent, branch, label, value) do
    row = %{id: id, parent: parent, label: label.(node), value: value.(node), branch: branch}

    children =
      node
      |> children()
      |> Enum.with_index()
      |> Enum.flat_map(fn {child, i} ->
        flatten(child, "#{id}.#{i}", id, branch || i, label, value)
      end)

    [row | children]
  end

  defp children(node), do: node[:children] || node["children"] || []
  defp node_name(data), do: data[:name] || data["name"]
  defp leaf_value(data), do: data[:value] || data["value"] || 0

  # -- assigns ---------------------------------------------------------------------------

  defp assigns(name, assigns) when name in @names do
    name |> defaults() |> Map.merge(Map.new(assigns)) |> Map.put(:preset, name)
  end

  defp unknown!(name) do
    raise ArgumentError,
          "#{inspect(name)} is not a preset; the presets are #{inspect(@names)} (spec/14 §15)"
  end
end
