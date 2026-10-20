defmodule Visualize.Chart.Schema.Mark do
  @moduledoc false
  # The marks' node kinds (spec/14 §5): reached through `Visualize.Chart.Schema`.

  import Visualize.Chart.Schema.Spec, only: [spec: 3, spec: 4, style_stack: 0]

  # Type, required channels, optional channels, option keys (spec/14 §5.2-5.3). `series`
  # is a channel of every type that draws rows (D-126).
  @marks [
    {:line, [:x, :y], [:series], [:closed]},
    {:area, [:x, :y], [:x0, :x1, :y0, :y1, :series], [:closed]},
    {:band, [:x0, :x1], [:y, :series], [:height]},
    {:rule, [], [:x, :y, :series], []},
    {:x_band, [:x0, :x1], [:series], []},
    {:percentile_band, [:x, :median], [:inner_lo, :inner_hi, :outer_lo, :outer_hi], []},
    {:rose, [:angle], [:value, :series], [:width, :inner_radius, :outer_radius, :pad_angle]},
    {:symbol, [:x, :y], [:value, :series], []},
    {:needle, [:x], [:y, :series], [:inner_radius, :width, :tail, :hub, :cap]},
    {:arc, [:value], [:start, :end, :inner, :outer, :series],
     [:inner_radius, :outer_radius, :corner_radius, :pad_angle, :start_angle, :end_angle]},
    {:path, [:path], [:series], []},
    {:rect, [:x0, :x1, :y0, :y1], [:value, :series], [:corner_radius]},
    {:circle, [:x, :y], [:value, :series], [:radius]},
    {:text, [:x, :y], [:value, :series], []},
    # A basemap: no channels, no rows (spec/14 §5.2, #475).
    {:tiles, [], [], []},
    # A choice by value: a child per case at the datum's position (spec/14 §5.2, #643).
    {:choose, [:x, :y], [:series], []}
  ]
  # The types a `:choose` mark's child may be (spec/14 §5.2, D-194).
  @choices [:circle, :symbol, :text, :rect]
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
    :end_angle,
    :tail,
    :hub,
    :cap,
    :closed
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
    {:take, [:n], [:side]},
    {:window, [:field], [:from, :to, :latest]},
    {:spectrum, [:field], [:time, :every, :samples, :window, :detrend, :as]},
    {:lttb, [:fields, :n], []},
    {:m4, [:fields, :width], []},
    {:tree, [], @hierarchy_keys ++ [:orientation, :link]},
    {:cluster, [], @hierarchy_keys ++ [:orientation, :link]},
    {:pack, [], @hierarchy_keys ++ [:padding]},
    {:partition, [], @hierarchy_keys ++ [:padding]},
    {:treemap, [], @hierarchy_keys ++ [:padding, :tile]},
    {:chord, [:fields, :field], [:size, :padding, :output, :nodes, :id]},
    {:sankey, [:fields, :field], [:size, :padding, :output, :nodes, :id]},
    {:force, [:fields],
     [:field, :size, :output, :nodes, :id, :strength, :distance, :alpha, :ticks]},
    {:contour, [:field, :size], [:thresholds]},
    {:density, [:fields], [:field, :size, :bandwidth, :thresholds]},
    {:delaunay, [:fields], [:output]},
    {:voronoi, [:fields], [:size, :output]},
    {:hexbin, [:fields], [:radius, :size, :output]},
    {:projection, [], [:fields, :field]}
  ]
  @ops Enum.map(@transforms, &elem(&1, 0))
  @tests [:eq, :ne, :lt, :lte, :gt, :gte, :present, :absent]
  @orders [:none, :ascending, :descending, :inside_out, :reverse, :appearance]
  @offsets [:none, :expand, :silhouette, :wiggle, :diverging]
  @tiles [:squarify, :binary, :slice, :dice, :slice_dice]
  @outputs [:nodes, :links, :groups, :chords, :triangles, :hull, :cells, :edges, :points]
  # The four edge anchors are the rectangular types' (spec/14 §5.5, #134).
  # The two polar anchors displace along the ray from the center (spec/14 §5.5, #137).
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
  @caps [:point, :round, :flat]
  @count_or_plot {:one_of, [:integer, {:enum, [:plot]}]}

  @doc false
  def rotate_type, do: @rotate

  @doc false
  def types, do: @types

  @doc false
  def choices, do: @choices

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
      spec(:transition, {:node, :transition}, :geometry),
      spec(:tooltip, {:node, :tooltip}, :content),
      # A `:tiles` mark's provider: required of that type, invalid on any other (§5.2).
      spec(:tiles, {:node, :tiles}, :content),
      spec(:id, :name, :content),
      spec(:frame, {:ref, :frame}, :binding),
      # The defaults of the layers and groups it was placed from (spec/14 §3.8, #651).
      spec(:defaults, {:node, :defaults}, :style),
      # A `:choose` mark's field and its children by the field's value (§5.2, D-194).
      spec(:on, :field, :binding),
      spec(:cases, {:map, {:node, :choice}}, :content),
      spec(:else, {:node, :choice}, :content)
    ]
  end

  # A `:choose` mark's child: a mark of a point type without data or frame (§5.2).
  def describe(:choice) do
    [
      spec(:type, {:enum, @choices}, :channel, required: true),
      spec(:channels, {:node, :channels}, :channel, default: %{}),
      spec(:options, {:node, :options}, :geometry, default: %{}),
      spec(:style, style_stack(), :style),
      spec(:label, {:node, :mark_label}, :content)
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
      # A computed order, or one fixed by the series keys (spec/14 §5.4.1, #492).
      spec(:order, {:one_of, [{:enum, @orders}, :key_order]}, :geometry),
      spec(:offset, {:enum, @offsets}, :geometry),
      spec(:size, {:list, :number}, :geometry),
      spec(:padding, :number, :geometry),
      spec(:tile, {:enum, @tiles}, :geometry),
      spec(:orientation, {:enum, [:vertical, :horizontal]}, :geometry, default: :vertical),
      spec(:link, {:enum, [:curve, :elbow, :line]}, :geometry, default: :curve),
      spec(:nodes, {:ref, :source}, :binding),
      spec(:radius, :number, :geometry, default: 20),
      spec(:strength, :number, :geometry, default: -30),
      spec(:distance, :number, :geometry, default: 30),
      # How lively a compiled chart's warm layout is per tick (spec/14 §12.5, D-132).
      spec(:alpha, :number, :geometry, default: 0.3, range: {0, 1, 0.05}),
      spec(:ticks, :integer, :geometry, default: 3, range: {1, 300, 1}),
      spec(:test, {:enum, @tests}, :binding, default: :present),
      spec(:value, :term, :binding),
      spec(:bandwidth, :number, :geometry),
      spec(:output, {:enum, @outputs}, :binding),
      spec(:time, :field, :binding),
      spec(:every, :number, :geometry),
      spec(:samples, :integer, :geometry),
      spec(:window, {:enum, [:hann, :hamming, :none]}, :geometry, default: :hann),
      spec(:detrend, :boolean, :geometry, default: false),
      # A count, or `:plot` — the plot area's width in pixels, read when the step runs
      # (spec/14 §5.4.1, #448); `:take` is held to the integer by the validator.
      spec(:n, @count_or_plot, :geometry),
      spec(:width, @count_or_plot, :geometry),
      spec(:side, {:enum, [:end, :start]}, :geometry, default: :end),
      spec(:from, {:list, :term}, :geometry),
      spec(:to, {:list, :term}, :geometry),
      # Each identity's last row, by the slot's declared identity (spec/14 §5.4.1, D-168).
      spec(:latest, :boolean, :binding, default: false)
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

  # Every option is a number but a needle's cap, an enum (spec/14 §5.3, #392), and a
  # line's or an area's closed, a boolean (#393).
  def describe(:options) do
    for key <- @option_keys do
      case key do
        :cap -> spec(key, {:enum, @caps}, :geometry, default: :point)
        :closed -> spec(key, :boolean, :geometry)
        _number -> spec(key, :number, :geometry)
      end
    end
  end

  # The fields a mark carries on its elements for `TooltipHook` (spec/14 §5.7, D-75).
  def describe(:tooltip) do
    [
      spec(:fields, {:list, :field}, :binding, default: []),
      spec(:template, :string, :content),
      spec(:event, {:one_of, [:name, :string]}, :binding)
    ]
  end

  # A basemap's provider (spec/14 §5.2, #475): the URL template and the attribution are
  # the host's intent, both required.
  def describe(:tiles) do
    [
      spec(:url, :string, :content, required: true),
      spec(:attribution, :string, :content, required: true),
      spec(:subdomains, {:list, :string}, :content, default: ["a", "b", "c"]),
      spec(:max_zoom, :integer, :geometry, default: 19)
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
        default: "label"
      ),
      spec(:dx, :number, :geometry, default: 0),
      spec(:dy, :number, :geometry, default: 0),
      spec(:dr, :number, :geometry, default: 0),
      spec(:rotate, @rotate, :geometry),
      spec(:fit, {:enum, [:none, :truncate, :hide]}, :geometry, default: :none)
    ]
  end
end
