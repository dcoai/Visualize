defmodule Visualize.Chart.Schema.Mark do
  @moduledoc false
  # The marks' node kinds (spec/14 §5): reached through `Visualize.Chart.Schema`.

  import Visualize.Chart.Schema, only: [spec: 3, spec: 4, style_stack: 0]

  # Type, required channels, optional channels, option keys (spec/14 §5.2-5.3).
  @marks [
    {:line, [:x, :y], [:series], []},
    {:area, [:x, :y], [:x0, :x1, :y0, :y1, :series], []},
    {:band, [:x0, :x1], [:y], [:height]},
    {:rule, [:x], [], []},
    {:x_band, [:x0, :x1], [], []},
    {:percentile_band, [:x, :median], [:inner_lo, :inner_hi, :outer_lo, :outer_hi], []},
    {:rose, [:angle], [:value], [:width, :inner_radius, :outer_radius, :pad_angle]},
    {:symbol, [:x, :y], [:value], []},
    {:arc, [:value], [:start, :end, :inner, :outer],
     [:inner_radius, :outer_radius, :corner_radius, :pad_angle, :start_angle, :end_angle]},
    {:path, [:path], [], []},
    {:rect, [:x0, :x1, :y0, :y1], [:value], [:corner_radius]},
    {:circle, [:x, :y], [:value], [:radius]},
    {:text, [:x, :y], [:value], []}
  ]
  @types Enum.map(@marks, &elem(&1, 0))
  @channel_keys [
    :x,
    :y,
    :x0,
    :x1,
    :y0,
    :y1,
    :value,
    :angle,
    :start,
    :end,
    :median,
    :inner,
    :outer,
    :inner_lo,
    :inner_hi,
    :outer_lo,
    :outer_hi,
    :series,
    :path
  ]
  @option_keys [
    :height,
    :width,
    :radius,
    :inner_radius,
    :outer_radius,
    :corner_radius,
    :pad_angle,
    :start_angle,
    :end_angle
  ]

  # Op, required keys, optional keys (spec/14 §5.4).
  @hierarchy_keys [:id, :by, :field, :size, :output]
  @transforms [
    {:filter, [:field], [:test, :value]},
    {:bin, [:field], [:thresholds, :as]},
    {:stack, [:fields], [:order, :offset]},
    {:fold, [:fields], [:as]},
    {:sum, [:field], [:by, :as]},
    {:sort, [:field], [:order]},
    {:tree, [], @hierarchy_keys ++ [:orientation, :link]},
    {:cluster, [], @hierarchy_keys ++ [:orientation, :link]},
    {:pack, [], @hierarchy_keys ++ [:padding]},
    {:partition, [], @hierarchy_keys ++ [:padding]},
    {:treemap, [], @hierarchy_keys ++ [:padding, :tile]},
    {:chord, [:fields, :field], [:size, :padding, :output, :nodes, :id]},
    {:sankey, [:fields, :field], [:size, :padding, :output, :nodes, :id]},
    {:force, [:fields], [:field, :size, :output, :nodes, :id, :strength, :distance]},
    {:contour, [:field, :size], [:thresholds]},
    {:density, [:fields], [:field, :size, :bandwidth, :thresholds]},
    {:delaunay, [:fields], [:output]},
    {:voronoi, [:fields], [:size, :output]},
    {:projection, [], [:fields, :field]}
  ]
  @ops Enum.map(@transforms, &elem(&1, 0))
  @tests [:eq, :ne, :lt, :lte, :gt, :gte, :present, :absent]
  @orders [:none, :ascending, :descending, :inside_out, :reverse, :appearance]
  @offsets [:none, :expand, :silhouette, :wiggle, :diverging]
  @tiles [:squarify, :binary, :slice, :dice, :slice_dice]
  @outputs [:nodes, :links, :groups, :chords, :triangles, :hull, :cells, :edges]
  # The four edge anchors are the rectangular types' (spec/14 §5.5, #134).
  # The two polar anchors displace along the ray from the centre (spec/14 §5.5, #137).
  @anchors [
    :top,
    :bottom,
    :left,
    :right,
    :start,
    :middle,
    :end,
    :x0,
    :x1,
    :y0,
    :y1,
    :outward,
    :inward
  ]
  @rotate {:one_of, [:number, {:enum, [:tangent, :radial]}]}

  @doc false
  def rotate_type, do: @rotate

  @doc false
  def types, do: @types

  @doc false
  def ops, do: @ops

  @doc false
  def channels(type) do
    {_, required, optional, _} = mark(type)
    %{required: required, optional: optional}
  end

  @doc false
  def options(type) do
    {_, _, _, options} = mark(type)
    options
  end

  @doc false
  def transform_keys(op) do
    {_, required, optional} =
      List.keyfind(@transforms, op, 0) ||
        raise ArgumentError, "not a transform op: #{inspect(op)}"

    %{required: required, optional: optional}
  end

  defp mark(type) do
    List.keyfind(@marks, type, 0) ||
      raise ArgumentError, "not a mark type: #{inspect(type)}"
  end

  @doc false
  def describe(:mark) do
    [
      spec(:type, {:enum, @types}, :channel, required: true),
      spec(:data, {:one_of, [{:ref, :source}, {:node, :data}]}, :binding, required: true),
      spec(:channels, {:node, :channels}, :channel, default: %{}),
      spec(:scales, {:node, :mark_scales}, :channel, default: %{}),
      spec(:offset, {:node, :mark_offset}, :channel, default: %{}),
      spec(:options, {:node, :options}, :geometry, default: %{}),
      spec(
        :style,
        style_stack(),
        :style
      ),
      spec(:label, {:node, :mark_label}, :content),
      spec(:render, {:enum, [:auto, :svg, :canvas, :binary]}, :geometry, default: :auto),
      spec(:tooltip, {:node, :tooltip}, :content),
      spec(:id, :name, :content)
    ]
  end

  def describe(:data) do
    [
      spec(:source, {:ref, :source}, :binding, required: true),
      spec(:transforms, {:list, {:node, :transform}}, :binding, default: [], merge: :concat)
    ]
  end

  def describe(:transform) do
    [
      spec(:op, {:enum, @ops}, :binding, required: true),
      spec(:field, :field, :binding),
      spec(:fields, {:list, :field}, :binding),
      spec(:by, :field, :binding),
      spec(:id, :field, :binding),
      spec(:as, {:one_of, [:name, {:list, :name}]}, :binding),
      spec(:thresholds, {:one_of, [:integer, {:list, :number}]}, :geometry),
      spec(:order, {:enum, @orders}, :geometry),
      spec(:offset, {:enum, @offsets}, :geometry),
      spec(:size, {:list, :number}, :geometry),
      spec(:padding, :number, :geometry),
      spec(:tile, {:enum, @tiles}, :geometry),
      spec(:orientation, {:enum, [:vertical, :horizontal]}, :geometry, default: :vertical),
      spec(:link, {:enum, [:curve, :elbow, :line]}, :geometry, default: :curve),
      spec(:nodes, {:ref, :source}, :binding),
      spec(:strength, :number, :geometry, default: -30),
      spec(:distance, :number, :geometry, default: 30),
      spec(:test, {:enum, @tests}, :binding, default: :present),
      spec(:value, :term, :binding),
      spec(:bandwidth, :number, :geometry),
      spec(:output, {:enum, @outputs}, :binding)
    ]
  end

  def describe(:channels) do
    for key <- @channel_keys, do: spec(key, :channel, :channel)
  end

  # The scale names of the frame kinds' tables (spec/14 §4.3), each renamed to a declared
  # scale by a mark's `scales` node (§5.1).
  def describe(:mark_scales) do
    for key <- [:x, :y, :angle, :r, :color, :x_offset, :y_offset],
        do: spec(key, {:ref, :scale}, :channel)
  end

  # A band within a band (spec/14 §5.1, D-109): the field that places a datum within its
  # band on a family, read through the family's offset scale.
  def describe(:mark_offset) do
    for key <- [:x, :y], do: spec(key, :field, :channel)
  end

  def describe(:options) do
    for key <- @option_keys, do: spec(key, :number, :geometry)
  end

  # The fields a mark carries on its elements for `TooltipHook` (spec/14 §5.7, D-75).
  def describe(:tooltip) do
    [
      spec(:fields, {:list, :field}, :binding, default: []),
      spec(:template, :string, :content),
      spec(:event, :name, :binding)
    ]
  end

  def describe(:mark_label) do
    [
      spec(:text, :text, :content, required: true),
      spec(:anchor, {:enum, @anchors}, :geometry, default: :top),
      spec(
        :style,
        style_stack(),
        :style,
        default: :label
      ),
      spec(:dx, :number, :geometry, default: 0),
      spec(:dy, :number, :geometry, default: 0),
      spec(:dr, :number, :geometry, default: 0),
      spec(:rotate, @rotate, :geometry)
    ]
  end
end
