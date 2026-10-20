defmodule Visualize.Chart.Schema.Design do
  @moduledoc false
  # The design-level node kinds (spec/14 §1.2–§3): reached through `Visualize.Chart.Schema`,
  # which builds every kind's table from this module, `Schema.Frame` and `Schema.Mark` once,
  # at compile time (D-184).

  import Visualize.Chart.Schema.Spec, only: [spec: 3, spec: 4, style_stack: 0, style_entry: 0]

  alias Visualize.Chart.Schema.Mark
  alias Visualize.Data.Schema, as: FeedSchema
  alias Visualize.Theme

  @curve_types [
    :linear,
    :step,
    :step_before,
    :step_after,
    :basis,
    :cardinal,
    :catmull_rom,
    :monotone_x,
    :monotone_y,
    :natural,
    :cardinal_closed,
    :basis_closed
  ]
  @symbol_types [:circle, :cross, :diamond, :square, :star, :triangle, :wye]
  @weights [:light, :normal, :medium, :bold]
  @blends [:normal, :multiply, :screen, :overlay, :darken, :lighten]
  @column_types [:time, :number, :category, :text]

  @doc false
  def curve_types, do: @curve_types

  @doc false
  def symbol_types, do: @symbol_types

  @doc false
  def column_types, do: @column_types

  @doc false
  # The key specs of a design-level node kind, in the order of its table in spec/14.
  def describe(:design) do
    [
      spec(:version, :integer, :content, required: true),
      spec(:meta, {:node, :meta}, :content, default: %{}),
      spec(:sources, {:map, {:node, :source}}, :binding, default: %{}, merge: :union),
      spec(:vars, {:map, {:node, :var}}, :binding, default: %{}, merge: :union),
      spec(:theme, {:one_of, [:name, {:node, :theme}]}, :style, default: :default),
      spec(:styles, {:map, style_entry()}, :style, default: %{}, merge: :union),
      spec(:defs, {:map, {:node, :paint}}, :style, default: %{}, merge: :union),
      # What every element inherits under its style (spec/14 §3.8, #651).
      spec(:defaults, {:node, :defaults}, :style),
      # The grid the frames are placed on, in place of arithmetic (spec/14 §2.8, #384).
      spec(:layout, {:node, :layout}, :geometry, default: %{}),
      # How the chart behaves beside others on a page: its sync group (spec/14 §2.9, #466).
      spec(:interaction, {:node, :interaction}, :binding, default: %{}),
      spec(:frames, {:map, {:node, :frame}}, :geometry, required: true, merge: :deep),
      spec(:marks, {:list, {:node, :mark}}, :channel, default: [], merge: :concat),
      spec(:labels, {:list, {:node, :label}}, :content, default: [], merge: :concat)
    ]
  end

  def describe(:layout) do
    [
      spec(:columns, {:list, :number}, :geometry, default: [1]),
      spec(:rows, {:list, :number}, :geometry, default: [1]),
      spec(:gap, :number, :geometry, default: 0)
    ]
  end

  # A sync group shares hover in domain units; `frame` names the frame whose `x` it reads;
  # `brush` is the design's own brush on that frame (spec/14 §2.9, D-116, D-143).
  def describe(:interaction) do
    [
      spec(:sync, :string, :binding),
      spec(:frame, {:ref, :frame}, :binding),
      spec(:brush, {:enum, [:x]}, :binding)
    ]
  end

  def describe(:meta) do
    [
      spec(:name, :text, :content),
      spec(:description, :text, :content, default: "")
    ]
  end

  def describe(:source) do
    [
      spec(:fields, {:list, :field}, :binding, required: true),
      spec(:types, {:map, {:enum, @column_types}}, :binding, default: %{}),
      spec(:default, :name, :binding),
      # The slot's contract with its feed's schema (spec/14 §2.3, §7.4, #552).
      spec(:requires, {:map, {:list, {:enum, FeedSchema.attributes()}}}, :binding, default: %{})
    ]
  end

  def describe(:var), do: [spec(:default, :term, :binding)]

  # A paint (spec/14 §2.7, §3.2, D-172): what an area is filled with or a line drawn with,
  # in the words a person uses — a type, then a color or stops and a gradient's geometry,
  # then an opacity. A `fill`, a `stroke` and a `defs` entry are each one.
  def describe(:paint), do: paint_keys(true)
  def describe(:gradient), do: paint_keys(true)

  # A stroke is a paint with the line it draws; a hatch is a fill, since a stroke's `width`
  # is its line's (spec/14 §3.1, #673).
  def describe(:stroke) do
    paint_keys(false) ++
      [
        spec(:width, :size, :style, range: {0, 20, 0.5}),
        # A dash's members may be unit values, never slots (spec/14 §3.9, #651).
        spec(:dash, {:one_of, [:string, {:list, :length}]}, :style),
        spec(:join, {:enum, [:miter, :round, :bevel]}, :style),
        spec(:cap, {:enum, [:butt, :round, :square]}, :style),
        spec(:placement, {:enum, [:center, :inside, :outside, :double]}, :style),
        # The width kept on screen under a scale (spec/14 §3.9, #651).
        spec(:non_scaling, :boolean, :style)
      ]
  end

  def describe(:stop) do
    [
      spec(:at, :number, :style, required: true, range: {0, 1, 0.05}),
      spec(:color, :color, :style, required: true),
      spec(:opacity, :size, :style, default: 1, range: {0, 1, 0.05})
    ]
  end

  def describe(:font) do
    [
      spec(:family, :font, :style),
      spec(:size, :size, :style, range: {6, 72, 1}),
      spec(:weight, {:one_of, [:integer, {:enum, @weights}]}, :style),
      spec(:style, {:enum, [:normal, :italic]}, :style),
      spec(:line_height, :number, :style, range: {0.8, 3, 0.1})
    ]
  end

  # Where a text sits on its point (spec/14 §6.3, §5.5): the flat keys' `text_anchor`,
  # `vertical_align`, `margin_x`/`margin_y` and `text_angle`.
  def describe(:text_layout) do
    [
      spec(:anchor, {:enum, [:start, :middle, :end]}, :style),
      spec(:baseline, {:enum, [:top, :middle, :baseline, :bottom]}, :style),
      spec(:offset, {:list, :length}, :style),
      spec(:angle, :number, :style, range: {-180, 180, 5})
    ]
  end

  def describe(:effect) do
    [
      spec(:type, {:enum, [:none, :shadow, :blur]}, :style),
      spec(:radius, :size, :style, range: {0, 20, 0.5}),
      # A shadow's offset and color (spec/14 §3.1, #674).
      spec(:offset, {:list, :length}, :style),
      spec(:color, :color, :style)
    ]
  end

  def describe(:marker) do
    [
      spec(:shape, {:enum, @symbol_types}, :style),
      spec(:size, :size, :style)
    ]
  end

  def describe(:curve) do
    [
      spec(:type, {:enum, @curve_types}, :style),
      spec(:tension, :number, :style),
      spec(:alpha, :number, :style)
    ]
  end

  # A style's transition (spec/14 §3.10, D-176): a duration and an easing for the fill, the
  # stroke and the opacity, or an entry per property. No defaults: a style says what it
  # changes, and the resolver supplies the rest.
  def describe(:style_transition) do
    part_transition_keys() ++
      for property <- [:fill, :stroke, :opacity],
          do: spec(property, {:node, :part_transition}, :style)
  end

  def describe(:part_transition), do: part_transition_keys()

  # A style's animation (spec/14 §3.11): a built-in's name or the host's, and how it runs.
  def describe(:style_animation) do
    [
      spec(:name, {:one_of, [{:enum, [:pulse, :blink, :shake, :spin]}, :string]}, :style),
      spec(:duration, :number, :style, range: {0, 10_000, 100}),
      spec(:easing, {:enum, Visualize.Ease.names()}, :style),
      spec(:iterations, {:one_of, [:number, {:enum, [:infinite]}]}, :style),
      spec(:delay, :number, :style)
    ]
  end

  # A style's entrance and exit (spec/14 §3.12): a built-in's name or the host's, how long,
  # along which curve.
  def describe(:style_enter), do: presence_keys([:fade, :grow])
  def describe(:style_exit), do: presence_keys([:fade, :shrink, :explode])

  def describe(:theme) do
    theme = Theme.default()

    [
      spec(:name, :name, :style, default: theme.name),
      spec(:series, {:list, :string}, :style, default: theme.series),
      spec(:axis, :string, :style, default: theme.axis),
      spec(:grid, :string, :style, default: theme.grid),
      spec(:text, :string, :style, default: theme.text),
      spec(:background, :string, :style, default: theme.background),
      spec(:surface, :string, :style, default: theme.surface),
      # The meaning-bearing ramps (spec/08 §7.5, #533) and the theme's own color table, the
      # roles' colors among it (§7.1, #663); an inline theme names only what it changes, the
      # rest the default's.
      spec(:ramps, {:map, {:list, :color}}, :style, default: theme.ramps),
      spec(:colors, {:map, :theme_color}, :style, default: theme.colors),
      # The style palette, a palette name to its entry (spec/08 §7.7, spec/14 §2.5, #637):
      # an inline theme names only the entries it changes, the rest the default's.
      spec(:styles, {:map, style_entry()}, :style, default: theme.styles),
      # The theme's own root defaults (spec/08 §7.1, spec/14 §3.8, #651).
      spec(:defaults, {:node, :defaults}, :style, default: theme.defaults),
      spec(:font_family, :string, :style, default: theme.font_family),
      spec(:font_size, :number, :style, default: theme.font_size, range: {6, 72, 1}),
      spec(:label_size, :number, :style, default: theme.label_size, range: {6, 72, 1}),
      spec(:title_size, :number, :style, default: theme.title_size, range: {6, 72, 1}),
      # The built-in theme standing for this one in a dark or a light color scheme
      # (spec/08 §7.3, #668).
      spec(:dark, :counterpart, :style, default: theme.dark),
      spec(:light, :counterpart, :style, default: theme.light)
    ]
  end

  # A style in its parts (spec/14 §3.1, D-172).
  def describe(:style) do
    [spec(:extends, {:one_of, [{:ref, :style}, {:list, {:ref, :style}}]}, :style)] ++
      part_keys() ++ [spec(:class, :string, :style)]
  end

  # What a container's elements inherit (spec/14 §3.8, #651, D-174): a style's parts, and
  # one entry per mark type but `:text` — `text` is the part — of the same parts. No
  # `extends` and no `class`: defaults are not a style that is named, derived or stacked.
  def describe(:defaults) do
    part_keys() ++
      for(type <- Mark.types() -- [:text], do: spec(type, {:node, :kind_defaults}, :style))
  end

  def describe(:kind_defaults), do: part_keys()

  # The flat style every earlier version wrote, one key per element attribute (spec/14 §9,
  # D-172): the types the migration reads them by.
  def describe(:flat_style) do
    [
      spec(:extends, {:ref, :style}, :style),
      spec(:fill, :color, :style),
      spec(:fill_opacity, :size, :style, range: {0, 1, 0.05}),
      spec(:stroke_style, {:enum, [:single, :double, :inside, :outside]}, :style),
      spec(:stroke_width, :size, :style, range: {0, 20, 0.5}),
      spec(:stroke, :color, :style),
      spec(:stroke_opacity, :size, :style, range: {0, 1, 0.05}),
      spec(:stroke_dasharray, {:one_of, [:string, {:list, :number}]}, :style),
      spec(:stroke_linejoin, {:enum, [:miter, :round, :bevel]}, :style),
      spec(:stroke_linecap, {:enum, [:butt, :round, :square]}, :style),
      spec(:font_family, :font, :style),
      spec(:font_size, :size, :style, range: {6, 72, 1}),
      spec(:font_weight, {:one_of, [:integer, {:enum, @weights}]}, :style),
      spec(:font_style, {:enum, [:normal, :italic]}, :style),
      spec(:line_height, :number, :style, range: {0.8, 3, 0.1}),
      spec(:text_anchor, {:enum, [:start, :middle, :end]}, :style),
      spec(:vertical_align, {:enum, [:top, :middle, :baseline, :bottom]}, :style),
      spec(:margin_x, :number, :style, range: {0, 40, 1}),
      spec(:margin_y, :number, :style, range: {0, 40, 1}),
      spec(:text_angle, :number, :style, range: {-180, 180, 5}),
      spec(:opacity, :size, :style, range: {0, 1, 0.05}),
      spec(:blend, {:enum, @blends}, :style),
      spec(:effect, {:enum, [:none, :shadow, :blur]}, :style),
      spec(:effect_radius, :size, :style, range: {0, 20, 0.5}),
      spec(:class, :string, :style),
      spec(:curve, {:enum, @curve_types}, :style),
      spec(:curve_opts, {:node, :curve_opts}, :style),
      spec(:symbol, {:enum, @symbol_types}, :style),
      spec(:symbol_size, :size, :style)
    ]
  end

  def describe(:curve_opts) do
    [
      spec(:tension, :number, :style, default: 0),
      spec(:alpha, :number, :style, default: 0.5)
    ]
  end

  def describe(:label) do
    [
      spec(:anchor, :anchor, :content, required: true),
      spec(:text, :text, :content, required: true),
      spec(
        :style,
        style_stack(),
        :style,
        default: "label"
      ),
      spec(:dx, :number, :geometry, default: 0),
      spec(:dy, :number, :geometry, default: 0),
      spec(:rotate, Mark.rotate_type(), :geometry),
      spec(:id, :name, :content),
      spec(:frame, {:ref, :frame}, :binding),
      # The defaults of the layers and groups it was placed from (spec/14 §3.8, #651).
      spec(:defaults, {:node, :defaults}, :style)
    ]
  end

  # The parts of a style, a style's and a defaults node's alike (spec/14 §3.1, §3.8).
  defp part_keys do
    [
      spec(:fill, {:node, :paint}, :style),
      spec(:stroke, {:node, :stroke}, :style),
      spec(:font, {:node, :font}, :style),
      spec(:text, {:node, :text_layout}, :style),
      spec(:effect, {:node, :effect}, :style),
      spec(:opacity, :size, :style, range: {0, 1, 0.05}),
      spec(:blend, {:enum, @blends}, :style),
      spec(:marker, {:node, :marker}, :style),
      spec(:curve, {:node, :curve}, :style),
      # How a change of the look is reached (spec/14 §3.10, #653).
      spec(:transition, {:node, :style_transition}, :style),
      # A motion run while the style holds (spec/14 §3.11, #653).
      spec(:animation, {:node, :style_animation}, :style),
      # How an element arrives and leaves by its row's identity (spec/14 §3.12, #653).
      spec(:enter, {:node, :style_enter}, :style),
      spec(:exit, {:node, :style_exit}, :style)
    ]
  end

  defp presence_keys(names) do
    [
      spec(:name, {:one_of, [{:enum, names}, :string]}, :style),
      spec(:duration, :number, :style, range: {0, 5000, 50}),
      spec(:easing, {:enum, Visualize.Ease.names()}, :style)
    ]
  end

  # A transition's own keys: how long, along which of `Visualize.Ease`'s curves.
  defp part_transition_keys do
    [
      spec(:duration, :number, :style, range: {0, 5000, 50}),
      spec(:easing, {:enum, Visualize.Ease.names()}, :style)
    ]
  end

  # A paint's keys: `type` decides which of the others it reads — a color for `:solid`,
  # stops and geometry for `:linear` and `:radial`, a color, a pattern and its sizes for
  # `:hatch` (#673), a `defs` name for `:paint` — and `opacity` is every type's. `:none` is
  # no paint. A stroke's paint has no hatch (`hatch?` false).
  defp paint_keys(hatch?) do
    types = [:none, :solid, :linear, :radial] ++ if(hatch?, do: [:hatch], else: []) ++ [:paint]

    [
      spec(:type, {:enum, types}, :style),
      spec(:color, :color, :style),
      spec(:stops, {:list, {:node, :stop}}, :style),
      spec(:angle, :number, :geometry, default: 180, range: {0, 360, 15}),
      spec(:center, {:list, :number}, :geometry, default: [0.5, 0.5]),
      spec(:radius, :number, :geometry, default: 0.5, range: {0, 1, 0.05}),
      spec(:name, {:ref, :paint}, :style),
      spec(:opacity, :size, :style, range: {0, 1, 0.05})
    ] ++ if(hatch?, do: hatch_keys(), else: [])
  end

  defp hatch_keys do
    [
      spec(:pattern, {:enum, [:lines, :crosshatch, :dots]}, :style, default: :lines),
      spec(:spacing, :size, :geometry, default: 6, range: {2, 40, 1}),
      spec(:width, :size, :geometry, default: 1, range: {0.25, 10, 0.25}),
      spec(:background, :color, :style)
    ]
  end
end
