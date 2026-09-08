defmodule Visualize.Chart.Style do
  @moduledoc """
  Style resolution for the declarative layer (spec/14 §3.4, D-63): one style node, two
  outputs by the mode of the render target.

  `resolve/3` turns a `:style` node into the style map of a `Visualize.IR.Element`: the
  fourteen element keys, every theme slot resolved through `Visualize.Theme.resolve/3` —
  a CSS custom-property reference in `:css`, the literal a canvas needs in `:literal` —
  a dash-array list joined, a literal passed through. A `{:field, f}` survives it, and
  `bind/4` then reads it from a datum, a colour key's reading through the frame's `color`
  scale when the frame declares one. The frame's furniture and the marks share this
  resolver.

  A style is looked up by name with its `extends` chain flattened first — the parent's keys,
  the child's over them (spec/14 §3.5, D-80) — so no consumer sees that key and a resolved
  node never carries it. A cycle raises `ArgumentError`; the validator reports it by path.

  ## Examples

      iex> theme = Visualize.Theme.default()
      iex> Visualize.Chart.Style.resolve(%{stroke: :axis, stroke_width: 2, curve: :step}, theme, :css)
      %{stroke: "var(--vis-axis, #666666)", stroke_width: 2}
      iex> Visualize.Chart.Style.resolve(%{stroke: :axis, stroke_dasharray: [2, 2]}, theme, :literal)
      %{stroke: "#666666", stroke_dasharray: "2 2"}

  """

  alias Visualize.Chart.Var
  alias Visualize.Data.Table
  alias Visualize.{Scale, Theme}

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

  @doc """
  The element style map of a style node, every slot resolved in `mode` (spec/14 §3.4).

  Only the keys an element renders are kept; `curve`, `curve_opts`, `symbol` and
  `symbol_size` reach the mark's generator instead. A `{:field, f}` is kept for `bind/4`.
  Raises `ArgumentError` for a variable: variables resolve at application (spec/14 §7.3).
  """
  @spec resolve(map(), Theme.t(), Theme.mode()) :: map()
  def resolve(%Var{name: name}, _theme, _mode), do: unresolved!(name)

  def resolve(node, theme, mode) when is_map(node) do
    node
    |> Map.take(@element_keys)
    |> Map.new(fn {key, value} -> {key, value(key, value, theme, mode)} end)
  end

  @doc """
  The map of `resolve/3` with every `{:field, f}` read from the datum (spec/14 §3.4).

  A colour key's reading passes through the frame's `color` scale when the frame
  declares one and is resolved as a theme slot when it is one; a `nil` reading — a
  column the datum lacks, or a category the scale does not hold — drops the key.
  """
  @spec bind(map(), term(), map(), Theme.mode()) :: map()
  def bind(style, datum, frame, mode) do
    Enum.reduce(style, %{}, fn
      {key, {:field, field}}, acc -> put_reading(acc, key, Table.get(datum, field), frame, mode)
      {key, value}, acc -> Map.put(acc, key, value)
    end)
  end

  defp put_reading(acc, _key, nil, _frame, _mode), do: acc

  defp put_reading(acc, key, reading, frame, mode) when key in @colour_keys do
    case Map.get(frame.scales, :color) do
      nil -> Map.put(acc, key, colour(reading, frame.theme, mode))
      scale -> put_colour(acc, key, Scale.apply(scale, reading), frame.theme, mode)
    end
  end

  defp put_reading(acc, key, reading, frame, mode) do
    Map.put(acc, key, value(key, reading, frame.theme, mode))
  end

  defp put_colour(acc, _key, nil, _theme, _mode), do: acc

  defp put_colour(acc, key, colour, theme, mode),
    do: Map.put(acc, key, colour(colour, theme, mode))

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
  # The style node of a name with its `extends` chain flattened — the parent's keys first,
  # the child's over them (spec/14 §3.5) — or the empty node when nothing declares it.
  @spec node(%{atom() => map()}, atom() | nil) :: map()
  def node(_styles, nil), do: %{}
  def node(_styles, %Var{name: name}), do: unresolved!(name)
  def node(styles, name), do: flatten(styles, name, [])

  defp flatten(_styles, %Var{name: name}, _seen), do: unresolved!(name)

  defp flatten(styles, name, seen) do
    if name in seen, do: cycle!(name)

    node = Map.get(styles, name, %{})

    case Map.fetch(node, :extends) do
      :error ->
        node

      {:ok, parent} ->
        Map.merge(flatten(styles, parent, [name | seen]), Map.delete(node, :extends))
    end
  end

  defp cycle!(name) do
    raise ArgumentError,
          "style #{inspect(name)} extends itself: a cycle of `extends` (spec/14 §3.5)"
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
