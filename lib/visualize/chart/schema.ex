defmodule Visualize.Chart.Schema do
  @moduledoc """
  The design schema as data (spec/14 §14.2).

  Every node kind of the design map (spec/14 §1.2) is a list of key specs, each with a
  type (§1.4), a facet (§1.3), a default, whether it is required and a merge rule (§1.5).
  The validator, the JSON codec and the introspection a builder needs all derive from
  these specs, so a key added here reaches every consumer at once (D-58). Which keys are
  style is `keys(:style)`, never a hand-kept list.

  The design-level node kinds live here; the frame's and the marks' tables are in two
  hidden submodules reached only through this one.

  ## Examples

      iex> Visualize.Chart.Schema.key(:mark, :style).facet
      :style
      iex> Visualize.Chart.Schema.default(:frame, :margin)
      %{top: 20, right: 20, bottom: 30, left: 40}
      iex> Visualize.Chart.Schema.channels(:line)
      %{required: [:x, :y], optional: [:series]}

  """

  alias Visualize.Chart.Schema.{Frame, Mark}
  alias Visualize.Data.Schema, as: FeedSchema
  alias Visualize.Theme

  @typedoc "What a key is about (spec/14 §1.3)."
  @type facet :: :binding | :channel | :geometry | :style | :content

  @typedoc "How two fragments combine under a key (spec/14 §1.5)."
  @type merge :: :concat | :union | :deep | :override

  @typedoc "A node kind of the design map (spec/14 §1.2)."
  @type kind :: atom()

  @typedoc "A type term of spec/14 §1.4."
  @type type :: atom() | tuple()

  @typedoc "One key of a node kind."
  @type key_spec :: %{
          key: atom(),
          type: type(),
          facet: facet(),
          default: term(),
          required: boolean(),
          merge: merge(),
          range: {number(), number(), number()} | nil
        }

  @design_kinds [
    :design,
    :meta,
    :source,
    :var,
    :theme,
    :style,
    :defaults,
    :kind_defaults,
    :paint,
    :stroke,
    :font,
    :text_layout,
    :effect,
    :marker,
    :curve,
    :style_transition,
    :part_transition,
    :style_animation,
    :style_enter,
    :style_exit,
    :stop,
    :label,
    :layout,
    :interaction
  ]
  @frame_kinds [
    :frame,
    :margin,
    :scale,
    :axis,
    :ticks,
    :measure,
    :legend,
    :projection,
    :fit,
    :facet,
    :viewport,
    :transition
  ]
  @mark_kinds [
    :mark,
    :data,
    :transform,
    :channels,
    :mark_scales,
    :mark_offset,
    :options,
    :mark_label,
    :tooltip,
    :tiles
  ]

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
  @builtin_styles [:axis, :grid, :label, :title]
  # The flat style of every earlier version (spec/14 §9, D-172): no design is stored in it,
  # but the migration reads it by these types. The builder edits a style in its parts (D-178).
  # `:gradient` is the library's kind for a stored paint (spec/14 §19.2), read as a `:paint`.
  @hidden_kinds [:flat_style, :curve_opts, :gradient]
  @column_types [:time, :number, :category, :text]

  @doc "Every node kind of spec/14 §1.2, the design first."
  @spec kinds() :: [kind(), ...]
  def kinds, do: @design_kinds ++ @frame_kinds ++ @mark_kinds

  @doc "The key specs of a node kind, in the order of its table in spec/14."
  @spec describe(kind()) :: [key_spec(), ...]
  def describe(kind) when kind in @design_kinds, do: design_node(kind)
  def describe(kind) when kind in @frame_kinds, do: Frame.describe(kind)
  def describe(kind) when kind in @mark_kinds, do: Mark.describe(kind)
  def describe(kind) when kind in @hidden_kinds, do: design_node(kind)

  def describe(kind) do
    raise ArgumentError, "not a node kind of the design schema: #{inspect(kind)}"
  end

  @doc "The spec of one key of a node kind, or `nil` when the node has no such key."
  @spec key(kind(), atom()) :: key_spec() | nil
  def key(kind, key), do: Enum.find(describe(kind), &(&1.key == key))

  @doc "Every `{kind, key}` pair carrying the facet, over every node kind (spec/14 §1.3)."
  @spec keys(facet()) :: [{kind(), atom()}]
  def keys(facet) do
    for kind <- kinds(), spec <- describe(kind), spec.facet == facet, do: {kind, spec.key}
  end

  @doc "The keys of one node kind carrying the facet, in table order."
  @spec keys(kind(), facet()) :: [atom()]
  def keys(kind, facet) do
    for spec <- describe(kind), spec.facet == facet, do: spec.key
  end

  @doc "The default of a key, `nil` when it has none or is required."
  @spec default(kind(), atom()) :: term()
  def default(kind, key) do
    case key(kind, key) do
      nil -> nil
      spec -> spec.default
    end
  end

  @doc "The mark types of spec/14 §5.2, in table order."
  @spec mark_types() :: [atom(), ...]
  def mark_types, do: Mark.types()

  @doc "The required and optional channels of a mark type (spec/14 §5.2)."
  @spec channels(atom()) :: %{required: [atom()], optional: [atom()]}
  def channels(type), do: Mark.channels(type)

  @doc "The option keys a mark type reads (spec/14 §5.3)."
  @spec options(atom()) :: [atom()]
  def options(type), do: Mark.options(type)

  @doc "The transform ops of spec/14 §5.4."
  @spec transform_ops() :: [atom(), ...]
  def transform_ops, do: Mark.ops()

  @doc "The required and optional keys of a transform op (spec/14 §5.4)."
  @spec transform_keys(atom()) :: %{required: [atom()], optional: [atom()]}
  def transform_keys(op), do: Mark.transform_keys(op)

  @doc "The scale kinds of spec/14 §4.3."
  @spec scale_kinds() :: [atom(), ...]
  def scale_kinds, do: Frame.scale_kinds()

  @doc """
  The type a style site takes (spec/14 §3.6): a reference, an inline node, a field binding
  `{:field, f}` whose value per datum names a style (#644), a generator call
  `{:generate, name, args}` whose result is a style (§3.13, #654), or a list of those.

  Written once because five keys share it — `mark.style`, `label.style`, `mark_label.style`,
  `axis.style` and `legend.style` — and a sixth would otherwise be a sixth copy.

      iex> {:one_of, alts} = Visualize.Chart.Schema.style_stack()
      iex> {:ref, :style} in alts
      true
  """
  @spec style_stack() :: type()
  def style_stack do
    entry = [{:ref, :style}, {:node, :style}, :generator, :field_ref]
    {:one_of, entry ++ [{:list, {:one_of, entry}}]}
  end

  @doc false
  # The type a named style takes — a `styles` entry, a theme's palette entry (spec/14 §2.6,
  # #658): a style node, the name of another, or a list of names and nodes stacked left to
  # right. A field entry is a site's, so a named style's list holds none.
  @spec style_entry() :: type()
  def style_entry do
    entry = [{:node, :style}, {:ref, :style}]
    {:one_of, entry ++ [{:list, {:one_of, Enum.reverse(entry)}}]}
  end

  @doc "The style names every design declares (spec/14 §3.3)."
  @spec builtin_styles() :: [atom(), ...]
  def builtin_styles, do: @builtin_styles

  @doc "The four column types a source's `types` may name (spec/14 §2.3, #369)."
  @spec column_types() :: [atom(), ...]
  def column_types, do: @column_types

  @doc false
  def curve_types, do: @curve_types

  @doc false
  def symbol_types, do: @symbol_types

  @doc false
  def spec(key, type, facet, opts \\ []) do
    %{
      key: key,
      type: type,
      facet: facet,
      default: Keyword.get(opts, :default),
      required: Keyword.get(opts, :required, false),
      merge: Keyword.get(opts, :merge, :override),
      range: Keyword.get(opts, :range)
    }
  end

  # The alternative of a `{:one_of, types}` whose shape the value has, or `nil`. The
  # validator reports the chosen alternative's errors and the codec encodes by it.
  @doc false
  def select(types, value), do: Enum.find(types, &shape?(&1, value))

  defp shape?({:node, _}, v), do: is_map(v) and not is_struct(v)
  defp shape?({:map, _}, v), do: is_map(v) and not is_struct(v)
  defp shape?({:list, _}, v), do: is_list(v)
  defp shape?(:text, v), do: is_list(v)
  defp shape?(:extent, v), do: v == :auto or is_list(v)
  defp shape?(:integer, v), do: is_integer(v)
  defp shape?(:number, v), do: is_number(v)
  defp shape?(:boolean, v), do: is_boolean(v)
  defp shape?(:string, v), do: is_binary(v)
  defp shape?(:size, v), do: is_number(v) or is_atom(v) or is_tuple(v)
  defp shape?(:length, v), do: is_number(v) or is_tuple(v)
  defp shape?(:channel, v), do: is_number(v) or is_atom(v) or is_tuple(v)
  defp shape?(:field_ref, v), do: is_tuple(v)
  defp shape?(:adopted, v), do: match?({:frame, _f, _s}, v)
  defp shape?(:key_order, v), do: match?({:keys, keys} when is_list(keys), v)
  defp shape?(:ramp, v), do: match?({:ramp, name} when is_atom(name), v)
  # A reference is a name or an id; a field binding beside one is not it (#644).
  defp shape?({:ref, _}, {:field, _field}), do: false
  defp shape?({:ref, _}, {:generate, _name, _args}), do: false
  defp shape?(:generator, v), do: match?({:generate, _, _}, v)
  defp shape?(:color_map, v), do: is_map(v) and not is_struct(v)
  # A theme's color: a color, or the steps it pins of a name (spec/08 §7.1, #667).
  defp shape?(:theme_color, _v), do: true
  # A theme's counterpart in a color scheme: a theme's name, or `nil` for none (#668).
  defp shape?(:counterpart, v), do: is_atom(v)
  # An enumeration is atoms, so a tagged tuple beside one is never read as it (#492).
  defp shape?({:enum, _}, v), do: is_atom(v)
  # A name is an atom, so a string beside one is read as the string it is (D-170).
  defp shape?(:name, v), do: is_atom(v)
  defp shape?(:term, _), do: true
  defp shape?(_atomic, v), do: is_atom(v) or is_tuple(v) or is_binary(v)

  # -- the design-level node kinds ---------------------------------------------------

  defp design_node(:design) do
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

  defp design_node(:layout) do
    [
      spec(:columns, {:list, :number}, :geometry, default: [1]),
      spec(:rows, {:list, :number}, :geometry, default: [1]),
      spec(:gap, :number, :geometry, default: 0)
    ]
  end

  # A sync group shares hover in domain units; `frame` names the frame whose `x` it reads;
  # `brush` is the design's own brush on that frame (spec/14 §2.9, D-116, D-143).
  defp design_node(:interaction) do
    [
      spec(:sync, :string, :binding),
      spec(:frame, {:ref, :frame}, :binding),
      spec(:brush, {:enum, [:x]}, :binding)
    ]
  end

  defp design_node(:meta) do
    [
      spec(:name, :text, :content),
      spec(:description, :text, :content, default: "")
    ]
  end

  defp design_node(:source) do
    [
      spec(:fields, {:list, :field}, :binding, required: true),
      spec(:types, {:map, {:enum, @column_types}}, :binding, default: %{}),
      spec(:default, :name, :binding),
      # The slot's contract with its feed's schema (spec/14 §2.3, §7.4, #552).
      spec(:requires, {:map, {:list, {:enum, FeedSchema.attributes()}}}, :binding, default: %{})
    ]
  end

  defp design_node(:var), do: [spec(:default, :term, :binding)]

  # A paint (spec/14 §2.7, §3.2, D-172): what an area is filled with or a line drawn with,
  # in the words a person uses — a type, then a color or stops and a gradient's geometry,
  # then an opacity. A `fill`, a `stroke` and a `defs` entry are each one.
  defp design_node(:paint), do: paint_keys(true)
  defp design_node(:gradient), do: paint_keys(true)

  # A stroke is a paint with the line it draws; a hatch is a fill, since a stroke's `width`
  # is its line's (spec/14 §3.1, #673).
  defp design_node(:stroke) do
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

  defp design_node(:stop) do
    [
      spec(:at, :number, :style, required: true, range: {0, 1, 0.05}),
      spec(:color, :color, :style, required: true),
      spec(:opacity, :size, :style, default: 1, range: {0, 1, 0.05})
    ]
  end

  defp design_node(:font) do
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
  defp design_node(:text_layout) do
    [
      spec(:anchor, {:enum, [:start, :middle, :end]}, :style),
      spec(:baseline, {:enum, [:top, :middle, :baseline, :bottom]}, :style),
      spec(:offset, {:list, :length}, :style),
      spec(:angle, :number, :style, range: {-180, 180, 5})
    ]
  end

  defp design_node(:effect) do
    [
      spec(:type, {:enum, [:none, :shadow, :blur]}, :style),
      spec(:radius, :size, :style, range: {0, 20, 0.5}),
      # A shadow's offset and color (spec/14 §3.1, #674).
      spec(:offset, {:list, :length}, :style),
      spec(:color, :color, :style)
    ]
  end

  defp design_node(:marker) do
    [
      spec(:shape, {:enum, @symbol_types}, :style),
      spec(:size, :size, :style)
    ]
  end

  defp design_node(:curve) do
    [
      spec(:type, {:enum, @curve_types}, :style),
      spec(:tension, :number, :style),
      spec(:alpha, :number, :style)
    ]
  end

  # A style's transition (spec/14 §3.10, D-176): a duration and an easing for the fill, the
  # stroke and the opacity, or an entry per property. No defaults: a style says what it
  # changes, and the resolver supplies the rest.
  defp design_node(:style_transition) do
    part_transition_keys() ++
      for property <- [:fill, :stroke, :opacity],
          do: spec(property, {:node, :part_transition}, :style)
  end

  defp design_node(:part_transition), do: part_transition_keys()

  # A style's animation (spec/14 §3.11): a built-in's name or the host's, and how it runs.
  defp design_node(:style_animation) do
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
  defp design_node(:style_enter), do: presence_keys([:fade, :grow])
  defp design_node(:style_exit), do: presence_keys([:fade, :shrink, :explode])

  defp design_node(:theme) do
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
  defp design_node(:style) do
    [spec(:extends, {:one_of, [{:ref, :style}, {:list, {:ref, :style}}]}, :style)] ++
      part_keys() ++ [spec(:class, :string, :style)]
  end

  # What a container's elements inherit (spec/14 §3.8, #651, D-174): a style's parts, and
  # one entry per mark type but `:text` — `text` is the part — of the same parts. No
  # `extends` and no `class`: defaults are not a style that is named, derived or stacked.
  defp design_node(:defaults) do
    part_keys() ++
      for(type <- Mark.types() -- [:text], do: spec(type, {:node, :kind_defaults}, :style))
  end

  defp design_node(:kind_defaults), do: part_keys()

  # The flat style every earlier version wrote, one key per element attribute (spec/14 §9,
  # D-172): the types the migration reads them by.
  defp design_node(:flat_style) do
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

  defp design_node(:curve_opts) do
    [
      spec(:tension, :number, :style, default: 0),
      spec(:alpha, :number, :style, default: 0.5)
    ]
  end

  defp design_node(:label) do
    [
      spec(:anchor, :anchor, :content, required: true),
      spec(:text, :text, :content, required: true),
      spec(
        :style,
        style_stack(),
        :style,
        default: :label
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
