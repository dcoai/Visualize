defmodule Visualize.Chart.Schema.Frame do
  @moduledoc false
  # The frame's node kinds (spec/14 §4): reached through `Visualize.Chart.Schema`.

  import Visualize.Chart.Schema.Spec, only: [spec: 3, spec: 4, style_stack: 0]

  @frame_kinds [:cartesian, :polar, :geo, :facet]
  @scale_kinds [
    :linear,
    :log,
    :power,
    :sqrt,
    :symlog,
    :time,
    :ordinal,
    :band,
    :quantize,
    :quantile,
    :threshold,
    :sequential,
    :diverging,
    :radial
  ]
  @sides [:top, :right, :bottom, :left]
  @positions [:top_left, :top_right, :bottom_left, :bottom_right, :top, :bottom, :left, :right]

  @doc false
  def scale_kinds, do: @scale_kinds

  @doc false
  def describe(:frame) do
    [
      spec(:kind, {:enum, @frame_kinds}, :geometry, required: true),
      spec(:margin, {:node, :margin}, :geometry,
        default: %{top: 20, right: 20, bottom: 30, left: 40}
      ),
      # A scale is this frame's node, or another frame's scale adopted by name
      # (spec/14 §4.3, #384): `{:frame, f, s}`, which shares that scale's domain.
      spec(:scales, {:map, {:one_of, [{:node, :scale}, :adopted]}}, :geometry,
        default: %{},
        merge: :union
      ),
      spec(:axes, {:list, {:node, :axis}}, :geometry, default: [], merge: :concat),
      spec(:legend, {:node, :legend}, :geometry),
      spec(:projection, {:node, :projection}, :geometry),
      spec(:facet, {:node, :facet}, :binding),
      spec(:viewport, {:node, :viewport}, :geometry),
      # A frame's share of the design's box, its drawing order and what it paints
      # under itself (spec/14 §4.1, §4.2, #383).
      spec(:box, {:list, :number}, :geometry, default: [0, 0, 1, 1]),
      # Where the frame sits on the design's grid, in place of its box (§2.8, #384).
      spec(:cell, {:list, :integer}, :geometry),
      spec(:span, {:list, :integer}, :geometry),
      spec(:z, :integer, :geometry, default: 0),
      spec(:background, :color, :style),
      # What the frame's elements inherit under their styles (spec/14 §3.8, #651).
      spec(:defaults, {:node, :defaults}, :style)
    ]
  end

  def describe(:margin) do
    for side <- @sides, do: spec(side, :number, :geometry, default: 0, range: {0, 200, 1})
  end

  def describe(:scale) do
    [
      spec(:kind, {:enum, @scale_kinds}, :geometry, required: true),
      spec(:domain, :extent, :geometry, default: :auto),
      # A list is positions or colors (§1.4, D-185); a map of colors pins each category by
      # name: a schema's `status` (§4.3, D-143).
      spec(:range, {:one_of, [:range, :ramp, :color_map, :name]}, :geometry, default: :auto),
      spec(:nice, :boolean, :geometry, default: false),
      spec(:clamp, :boolean, :geometry, default: false),
      spec(:base, :number, :geometry, default: 10),
      spec(:exponent, :number, :geometry, default: 1),
      spec(:constant, :number, :geometry, default: 1),
      spec(:padding, :number, :geometry, default: 0),
      spec(:padding_inner, :number, :geometry),
      spec(:padding_outer, :number, :geometry),
      spec(:align, :number, :geometry, default: 0.5),
      spec(:round, :boolean, :geometry, default: false),
      spec(:unknown, :term, :geometry),
      # Which end of the domain is better, placing a ramp range by worth (§4.3, D-143).
      spec(:polarity, {:enum, Visualize.Data.Schema.polarities()}, :geometry),
      spec(:transition, {:node, :transition}, :geometry),
      spec(:start, :number, :geometry, default: 0, range: {-360, 360, 5}),
      spec(:sweep, :number, :geometry, default: 360, range: {-360, 360, 5}),
      # A time scale's display zone, an IANA name; `nil` is UTC (spec/03 §7.4, #447).
      spec(:zone, :string, :geometry)
    ]
  end

  def describe(:axis) do
    [
      spec(:scale, {:ref, :scale}, :geometry, required: true),
      spec(:side, {:enum, @sides}, :geometry, required: true),
      spec(:ticks, {:one_of, [:integer, {:list, :term}, {:node, :ticks}]}, :geometry),
      spec(:format, {:one_of, [:string, {:enum, [:duration]}]}, :content),
      spec(:prefix, :string, :content),
      spec(:unit, :string, :content),
      spec(:measure, {:node, :measure}, :content),
      spec(:grid, :boolean, :geometry, default: false),
      spec(:offset, :number, :geometry, default: 0),
      spec(:radius, :number, :geometry, range: {0, 1, 0.05}),
      spec(:at, :number, :geometry, range: {-180, 180, 5}),
      spec(
        :style,
        style_stack(),
        :style,
        default: :axis
      ),
      # The defaults of the layers and groups it was placed from (spec/14 §3.8, #651).
      spec(:defaults, {:node, :defaults}, :style)
    ]
  end

  def describe(:ticks) do
    [
      spec(:count, :integer, :geometry),
      spec(:values, {:list, :term}, :content),
      spec(:size_inner, :number, :geometry, default: 6),
      spec(:size_outer, :number, :geometry, default: 6),
      spec(:padding, :number, :geometry, default: 3)
    ]
  end

  # What the values on an axis's scale are: a UCUM code and one of the fixed quantities
  # (spec/14 §4.4, spec/05 §4, D-138) — facts about the data, the shape of a field
  # description's `unit` and `quantity`, which a feed's schema will supply (#535).
  def describe(:measure) do
    [
      spec(:unit, :string, :content),
      spec(:quantity, {:enum, Visualize.Quantity.all()}, :content)
    ]
  end

  def describe(:legend) do
    [
      spec(:scale, {:ref, :scale}, :geometry, required: true),
      # The declared values a legend lists in place of a scale's ticks (§4.5, D-194).
      spec(:values, {:list, :term}, :content),
      spec(:position, {:enum, @positions}, :geometry, default: :top_right),
      spec(:inside, :boolean, :geometry, default: true),
      spec(:title, :text, :content, default: ""),
      spec(:prefix, :string, :content),
      spec(:unit, :string, :content),
      spec(
        :style,
        style_stack(),
        :style,
        default: :label
      ),
      # A top or bottom legend wraps to the plot's width, and a label can be cut to a
      # count of characters, the full text kept (§4.5, D-169).
      spec(:wrap, :boolean, :geometry, default: true),
      spec(:max_label, :integer, :geometry, range: {1, 80, 1})
    ]
  end

  def describe(:projection) do
    [
      spec(:type, :name, :geometry, required: true),
      spec(:scale, :number, :geometry),
      spec(:translate, {:list, :number}, :geometry),
      spec(:center, {:list, :number}, :geometry),
      spec(:rotate, {:list, :number}, :geometry),
      spec(:parallels, {:list, :number}, :geometry),
      spec(:clip_angle, :number, :geometry),
      spec(:fit, {:node, :fit}, :binding)
    ]
  end

  # The view fitted to a source's points or geometries (spec/14 §4.6, #475).
  def describe(:fit) do
    [
      spec(:data, {:ref, :source}, :binding, required: true),
      spec(:fields, {:list, :field}, :binding),
      spec(:field, :field, :binding),
      spec(:padding, :number, :geometry, default: 0)
    ]
  end

  def describe(:facet) do
    [
      spec(:by, :field, :binding, required: true),
      spec(:columns, :integer, :geometry)
    ]
  end

  def describe(:viewport) do
    [
      spec(:scale, {:ref, :scale}, :geometry, required: true),
      spec(:span, :number, :geometry, required: true)
    ]
  end

  # How a moving domain reaches its new extent in a compiled chart (spec/14 §4.3, §12.5).
  def describe(:transition) do
    [
      spec(:duration, :number, :geometry, default: 300),
      spec(:easing, {:enum, Visualize.Ease.names()}, :geometry, default: :cubic_in_out),
      spec(:shrink_after, :number, :geometry, default: 0)
    ]
  end
end
