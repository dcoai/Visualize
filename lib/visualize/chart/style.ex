defmodule Visualize.Chart.Style do
  @moduledoc false
  # Style resolution for the declarative layer (spec/14 §3): the four built-in styles
  # derived from the theme's slots, and the mapping of a style node to the style map of
  # a `Visualize.IR.Element`, every slot resolved through `Visualize.Theme.resolve/3` in
  # the mode of the render target. Shared by the frame's furniture now and by the marks
  # of work item 3.

  alias Visualize.Chart.Var
  alias Visualize.Theme

  @colour_keys [:fill, :stroke]
  @size_keys [:stroke_width, :opacity, :fill_opacity, :stroke_opacity, :font_size, :symbol_size]
  @font_keys [:font_family]
  @element_keys [
    :fill,
    :stroke,
    :stroke_width,
    :stroke_dasharray,
    :stroke_linecap,
    :stroke_linejoin,
    :opacity,
    :fill_opacity,
    :stroke_opacity,
    :font_family,
    :font_size,
    :font_weight,
    :text_anchor,
    :class
  ]

  @doc false
  # The built-in style nodes of spec/14 §3.3, as an author would declare them.
  @spec builtin(atom()) :: map()
  def builtin(:axis) do
    %{stroke: :axis, fill: :text, font_family: :font_family, font_size: :font_size}
  end

  def builtin(:grid), do: %{stroke: :grid}
  def builtin(:label), do: %{fill: :text, font_family: :font_family, font_size: :label_size}

  def builtin(:title) do
    Map.merge(builtin(:label), %{font_size: :title_size, font_weight: :bold})
  end

  @doc false
  # The declared styles over the built-in four: a declared name replaces a built-in one
  # whole (spec/14 §3.3).
  @spec all(map()) :: %{atom() => map()}
  def all(declared) do
    Map.merge(Map.new([:axis, :grid, :label, :title], &{&1, builtin(&1)}), declared)
  end

  @doc false
  # The style node of a name, or the empty node when nothing declares it.
  @spec node(%{atom() => map()}, atom()) :: map()
  def node(styles, name), do: Map.get(styles, name, %{})

  @doc false
  # The element style map of a style node: only the keys an element renders, every slot
  # resolved, a dash array joined. A variable in the node is an author error at this
  # point: variables resolve at application (spec/14 §7.3).
  @spec resolve(map(), Theme.t(), Theme.mode()) :: map()
  def resolve(%Var{name: name}, _theme, _mode), do: unresolved!(name)

  def resolve(node, theme, mode) when is_map(node) do
    node
    |> Map.take(@element_keys)
    |> Map.new(fn {key, value} -> {key, value(key, value, theme, mode)} end)
  end

  @doc false
  # One style value resolved: a slot through the theme, a literal as it is.
  @spec value(atom(), term(), Theme.t(), Theme.mode()) :: term()
  def value(_key, %Var{name: name}, _theme, _mode), do: unresolved!(name)
  def value(:stroke_dasharray, list, _theme, _mode) when is_list(list), do: Enum.join(list, " ")
  def value(key, value, theme, mode) when key in @colour_keys, do: slot_or(value, theme, mode)
  def value(key, value, theme, mode) when key in @size_keys, do: slot_or(value, theme, mode)
  def value(key, value, theme, mode) when key in @font_keys, do: slot_or(value, theme, mode)
  def value(_key, value, _theme, _mode), do: value

  @doc false
  # A colour a scale yields, resolved when it is a theme slot (spec/14 §4.3).
  @spec colour(term(), Theme.t(), Theme.mode()) :: term()
  def colour(value, theme, mode), do: slot_or(value, theme, mode)

  @doc false
  # Whether a value is a colour an element can be painted with: a string, `:none` or a
  # theme slot.
  @spec colour?(term()) :: boolean()
  def colour?(value) when is_binary(value) or value == :none, do: true
  def colour?({:series, i}), do: is_integer(i) and i >= 1
  def colour?(value), do: is_atom(value) and value not in [nil, true, false]

  defp slot_or(:none, _theme, _mode), do: :none
  defp slot_or({:series, _} = slot, theme, mode), do: Theme.resolve(theme, slot, mode)
  defp slot_or(slot, theme, mode) when is_atom(slot), do: Theme.resolve(theme, slot, mode)
  defp slot_or(literal, _theme, _mode), do: literal

  @doc false
  @spec unresolved!(atom()) :: no_return()
  def unresolved!(name) do
    raise ArgumentError,
          "variable #{inspect(name)} is unresolved: a frame is built from an applied " <>
            "design (spec/14 §7.3)"
  end
end
