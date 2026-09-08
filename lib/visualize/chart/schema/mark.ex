defmodule Visualize.Chart.Schema.Mark do
  @moduledoc false
  # The marks' node kinds (spec/14 §5): reached through `Visualize.Chart.Schema`.

  import Visualize.Chart.Schema, only: [spec: 3, spec: 4]

  # Type, required channels, optional channels, option keys (spec/14 §5.2-5.3).
  @marks [
    {:line, [:x, :y], [], []},
    {:area, [:x, :y], [:x0, :x1, :y0, :y1], []},
    {:band, [:x0, :x1], [:y], [:height]},
    {:rule, [:x], [], []},
    {:x_band, [:x0, :x1], [], []},
    {:percentile_band, [:x, :median, :inner, :outer], [], []},
    {:rose, [:angle], [:value], [:width, :inner_radius, :outer_radius, :pad_angle]},
    {:symbol, [:x, :y], [:value], []},
    {:arc, [:value], [:inner, :outer],
     [:inner_radius, :outer_radius, :corner_radius, :pad_angle, :start_angle, :end_angle]},
    {:path, [:x, :y], [], []},
    {:rect, [:x0, :x1, :y0, :y1], [:value], [:corner_radius]},
    {:circle, [:x, :y], [:value], [:radius]}
  ]
  @types Enum.map(@marks, &elem(&1, 0))
  @channel_keys [:x, :y, :x0, :x1, :y0, :y1, :value, :angle, :median, :inner, :outer]
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
  @ops [
    :bin,
    :stack,
    :sum,
    :sort,
    :tree,
    :cluster,
    :pack,
    :partition,
    :treemap,
    :chord,
    :sankey,
    :force,
    :contour,
    :density,
    :delaunay,
    :voronoi
  ]
  @orders [:none, :ascending, :descending, :inside_out, :reverse, :appearance]
  @offsets [:none, :expand, :silhouette, :wiggle, :diverging]
  @anchors [:top, :bottom, :left, :right, :start, :middle, :end]

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
      spec(:options, {:node, :options}, :geometry, default: %{}),
      spec(:style, {:ref, :style}, :style),
      spec(:label, {:node, :mark_label}, :content),
      spec(:render, {:enum, [:auto, :svg, :canvas, :binary]}, :geometry, default: :auto)
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
      spec(:as, :name, :binding),
      spec(:thresholds, {:one_of, [:integer, {:list, :number}]}, :geometry),
      spec(:order, {:enum, @orders}, :geometry),
      spec(:offset, {:enum, @offsets}, :geometry),
      spec(:size, {:list, :number}, :geometry),
      spec(:padding, :number, :geometry)
    ]
  end

  def describe(:channels) do
    for key <- @channel_keys, do: spec(key, :channel, :channel)
  end

  def describe(:options) do
    for key <- @option_keys, do: spec(key, :number, :geometry)
  end

  def describe(:mark_label) do
    [
      spec(:text, :text, :content, required: true),
      spec(:anchor, {:enum, @anchors}, :geometry, default: :top),
      spec(:style, {:ref, :style}, :style, default: :label),
      spec(:dx, :number, :geometry, default: 0),
      spec(:dy, :number, :geometry, default: 0)
    ]
  end
end
