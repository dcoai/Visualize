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

  alias Visualize.Chart.Schema.{Design, Frame, Mark, Spec}

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
    :tiles,
    :choice
  ]

  @builtin_styles [:axis, :grid, :label, :title]
  # The flat style of every earlier version (spec/14 §9, D-172): no design is stored in it,
  # but the migration reads it by these types. The builder edits a style in its parts (D-178).
  # `:gradient` is the library's kind for a stored paint (spec/14 §19.2), read as a `:paint`.
  @hidden_kinds [:flat_style, :curve_opts, :gradient]

  # Every kind's table, built once when the library compiles (spec/14 §14.2, D-184): the
  # tables are a function of nothing, and the validator, the stack's merge rules and the
  # builder's forms read them thousands of times in one editing pass. Each table's keys by
  # name stand beside it, so `key/2` is a lookup rather than a scan.
  @tables Map.new(@design_kinds ++ @hidden_kinds, &{&1, Design.describe(&1)})
          |> Map.merge(Map.new(@frame_kinds, &{&1, Frame.describe(&1)}))
          |> Map.merge(Map.new(@mark_kinds, &{&1, Mark.describe(&1)}))
  @by_key Map.new(@tables, fn {kind, specs} -> {kind, Map.new(specs, &{&1.key, &1})} end)
  # Every key any node kind has: the vocabulary a document's keys are read in (spec/14 §9.4).
  @key_names @tables |> Map.values() |> List.flatten() |> Enum.map(& &1.key) |> Enum.uniq()

  @doc "Every node kind of spec/14 §1.2, the design first."
  @spec kinds() :: [kind(), ...]
  def kinds, do: @design_kinds ++ @frame_kinds ++ @mark_kinds

  @doc "The key specs of a node kind, in the order of its table in spec/14."
  @spec describe(kind()) :: [key_spec(), ...]
  def describe(kind) do
    case @tables do
      %{^kind => specs} -> specs
      %{} -> unknown(kind)
    end
  end

  @doc "The spec of one key of a node kind, or `nil` when the node has no such key."
  @spec key(kind(), atom()) :: key_spec() | nil
  def key(kind, key) do
    case @by_key do
      %{^kind => specs} -> Map.get(specs, key)
      %{} -> unknown(kind)
    end
  end

  defp unknown(kind) do
    raise ArgumentError, "not a node kind of the design schema: #{inspect(kind)}"
  end

  @doc false
  # Every key of every node kind, the hidden ones included, once each (spec/14 §9.4, D-195).
  @spec key_names() :: [atom(), ...]
  def key_names, do: @key_names

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
  defdelegate style_stack(), to: Spec

  @doc false
  # The type a named style takes — a `styles` entry, a theme's palette entry (spec/14 §2.6,
  # #658): a style node, the name of another, or a list of names and nodes stacked left to
  # right. A field entry is a site's, so a named style's list holds none.
  @spec style_entry() :: type()
  defdelegate style_entry(), to: Spec

  @doc "The style names every design declares (spec/14 §3.3)."
  @spec builtin_styles() :: [atom(), ...]
  def builtin_styles, do: @builtin_styles

  @doc "The four column types a source's `types` may name (spec/14 §2.3, #369)."
  @spec column_types() :: [atom(), ...]
  defdelegate column_types(), to: Design

  @doc false
  defdelegate curve_types(), to: Design

  @doc false
  defdelegate symbol_types(), to: Design

  @doc false
  defdelegate spec(key, type, facet, opts \\ []), to: Spec

  # The alternative of a `{:one_of, types}` whose shape the value has, or `nil`. The
  # validator reports the chosen alternative's errors and the codec encodes by it.
  @doc false
  def select(types, value), do: Enum.find(types, &shape?(&1, value))

  defp shape?({:node, _}, v), do: is_map(v) and not is_struct(v)
  defp shape?({:map, _}, v), do: is_map(v) and not is_struct(v)
  defp shape?({:list, _}, v), do: is_list(v)
  defp shape?(:text, v), do: is_list(v)
  defp shape?(:extent, v), do: v == :auto or is_list(v)
  defp shape?(:range, v), do: v == :auto or is_list(v)
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
end
