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
  alias Visualize.Theme

  @typedoc "What a key is about (spec/14 §1.3)."
  @type facet :: :binding | :channel | :geometry | :style | :content

  @typedoc "How two fragments combine under a key (spec/14 §1.5)."
  @type merge :: :concat | :union | :override

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

  @design_kinds [:design, :meta, :source, :var, :theme, :style, :curve_opts, :label]
  @frame_kinds [
    :frame,
    :size,
    :margin,
    :scale,
    :axis,
    :ticks,
    :legend,
    :projection,
    :facet,
    :viewport
  ]
  @mark_kinds [
    :mark,
    :data,
    :transform,
    :channels,
    :mark_scales,
    :options,
    :mark_label,
    :tooltip
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
    :natural
  ]
  @symbol_types [:circle, :cross, :diamond, :square, :star, :triangle, :wye]
  @builtin_styles [:axis, :grid, :label, :title]

  @doc "Every node kind of spec/14 §1.2, the design first."
  @spec kinds() :: [kind(), ...]
  def kinds, do: @design_kinds ++ @frame_kinds ++ @mark_kinds

  @doc "The key specs of a node kind, in the order of its table in spec/14."
  @spec describe(kind()) :: [key_spec(), ...]
  def describe(kind) when kind in @design_kinds, do: design_node(kind)
  def describe(kind) when kind in @frame_kinds, do: Frame.describe(kind)
  def describe(kind) when kind in @mark_kinds, do: Mark.describe(kind)

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
  The type a style site takes (spec/14 §3.6): a reference, an inline node, or a list of
  either.

  Written once because five keys share it — `mark.style`, `label.style`, `mark_label.style`,
  `axis.style` and `legend.style` — and a sixth would otherwise be a sixth copy.

      iex> {:one_of, alts} = Visualize.Chart.Schema.style_stack()
      iex> {:ref, :style} in alts
      true
  """
  @spec style_stack() :: type()
  def style_stack do
    {:one_of,
     [{:ref, :style}, {:node, :style}, {:list, {:one_of, [{:ref, :style}, {:node, :style}]}}]}
  end

  @doc "The style names every design declares (spec/14 §3.3)."
  @spec builtin_styles() :: [atom(), ...]
  def builtin_styles, do: @builtin_styles

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
  defp shape?(:channel, v), do: is_number(v) or is_atom(v) or is_tuple(v)
  defp shape?(:field_ref, v), do: is_tuple(v)
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
      spec(:styles, {:map, {:node, :style}}, :style, default: %{}, merge: :union),
      spec(:frame, {:node, :frame}, :geometry, required: true),
      spec(:marks, {:list, {:node, :mark}}, :channel, default: [], merge: :concat),
      spec(:labels, {:list, {:node, :label}}, :content, default: [], merge: :concat)
    ]
  end

  defp design_node(:meta) do
    [
      spec(:name, :string, :content),
      spec(:description, :text, :content, default: [])
    ]
  end

  defp design_node(:source) do
    [
      spec(:fields, {:list, :field}, :binding, required: true),
      spec(:default, :name, :binding)
    ]
  end

  defp design_node(:var), do: [spec(:default, :term, :binding)]

  defp design_node(:theme) do
    theme = Theme.default()

    [
      spec(:name, :name, :style, default: theme.name),
      spec(:series, {:list, :string}, :style, default: theme.series),
      spec(:axis, :string, :style, default: theme.axis),
      spec(:grid, :string, :style, default: theme.grid),
      spec(:text, :string, :style, default: theme.text),
      spec(:background, :string, :style, default: theme.background),
      spec(:font_family, :string, :style, default: theme.font_family),
      spec(:font_size, :number, :style, default: theme.font_size, range: {6, 72, 1}),
      spec(:label_size, :number, :style, default: theme.label_size, range: {6, 72, 1}),
      spec(:title_size, :number, :style, default: theme.title_size, range: {6, 72, 1})
    ]
  end

  defp design_node(:style) do
    [
      spec(:extends, {:ref, :style}, :style),
      spec(:fill, :colour, :style),
      spec(:stroke, :colour, :style),
      spec(:stroke_width, :size, :style, range: {0, 20, 0.5}),
      spec(:stroke_dasharray, {:one_of, [:string, {:list, :number}]}, :style),
      spec(:stroke_linecap, {:enum, [:butt, :round, :square]}, :style),
      spec(:stroke_linejoin, {:enum, [:miter, :round, :bevel]}, :style),
      spec(:opacity, :size, :style, range: {0, 1, 0.05}),
      spec(:fill_opacity, :size, :style, range: {0, 1, 0.05}),
      spec(:stroke_opacity, :size, :style, range: {0, 1, 0.05}),
      spec(:font_family, :font, :style),
      spec(:font_size, :size, :style, range: {6, 72, 1}),
      spec(:font_weight, {:one_of, [:integer, {:enum, [:normal, :bold]}]}, :style),
      spec(:text_anchor, {:enum, [:start, :middle, :end]}, :style),
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
      spec(:id, :name, :content)
    ]
  end
end
