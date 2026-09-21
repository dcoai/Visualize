defmodule Visualize.Chart.Schema.Frame do
  @moduledoc false
  # The frame's node kinds (spec/14 §4): reached through `Visualize.Chart.Schema`.

  import Visualize.Chart.Schema, only: [spec: 3, spec: 4, style_stack: 0]

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
      spec(:size, {:node, :size}, :geometry, default: %{width: 600, height: 400}),
      spec(:margin, {:node, :margin}, :geometry,
        default: %{top: 20, right: 20, bottom: 30, left: 40}
      ),
      spec(:scales, {:map, {:node, :scale}}, :geometry, default: %{}, merge: :union),
      spec(:axes, {:list, {:node, :axis}}, :geometry, default: [], merge: :concat),
      spec(:legend, {:node, :legend}, :geometry),
      spec(:projection, {:node, :projection}, :geometry),
      spec(:facet, {:node, :facet}, :binding),
      spec(:viewport, {:node, :viewport}, :geometry)
    ]
  end

  def describe(:size) do
    [
      spec(:width, :number, :geometry, required: true, range: {100, 2000, 10}),
      spec(:height, :number, :geometry, required: true, range: {100, 2000, 10})
    ]
  end

  def describe(:margin) do
    for side <- @sides, do: spec(side, :number, :geometry, default: 0, range: {0, 200, 1})
  end

  def describe(:scale) do
    [
      spec(:kind, {:enum, @scale_kinds}, :geometry, required: true),
      spec(:domain, :extent, :geometry, default: :auto),
      spec(:range, {:one_of, [:extent, :name]}, :geometry, default: :auto),
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
      spec(:transition, {:node, :transition}, :geometry),
      spec(:start, :number, :geometry, default: 0, range: {-360, 360, 5}),
      spec(:sweep, :number, :geometry, default: 360, range: {-360, 360, 5})
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
      spec(:grid, :boolean, :geometry, default: false),
      spec(:offset, :number, :geometry, default: 0),
      spec(:radius, :number, :geometry, range: {0, 1, 0.05}),
      spec(:at, :number, :geometry, range: {-180, 180, 5}),
      spec(
        :style,
        style_stack(),
        :style,
        default: :axis
      )
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

  def describe(:legend) do
    [
      spec(:scale, {:ref, :scale}, :geometry, required: true),
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
      )
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
      spec(:clip_angle, :number, :geometry)
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
