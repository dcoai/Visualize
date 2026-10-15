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

  A style is stored in **compound parts** (spec/14 §3.1, D-172) — `fill`, `stroke`, `font`,
  `text`, `effect`, `marker`, `curve` — and `normalize/1` turns a shorthand or the flat keys
  of an earlier version into them. The element keys are the flat ones they always were:
  `resolve/3` projects the parts onto them, so the IR and the backends read what they read.

  A style is looked up by name with its `extends` chain flattened first — the parent's parts,
  the child's merged over them by `merge/2` (spec/14 §3.5, D-80, D-172) — so no consumer
  sees that key and a resolved node never carries it. A cycle raises `ArgumentError`; the
  validator reports it by path.

  ## Examples

      iex> theme = Visualize.Theme.default()
      iex> Visualize.Chart.Style.resolve(%{stroke: %{color: :axis, width: 2}, curve: :step}, theme, :css)
      %{stroke: "var(--vis-axis, #666666)", stroke_width: 2}
      iex> Visualize.Chart.Style.resolve(%{stroke: :axis, stroke_width: 2, curve: :step}, theme, :css)
      %{stroke: "var(--vis-axis, #666666)", stroke_width: 2}
      iex> Visualize.Chart.Style.resolve(%{stroke: :axis, stroke_dasharray: [2, 2]}, theme, :literal)
      %{stroke: "#666666", stroke_dasharray: "2 2"}

  """

  alias Visualize.Chart.Style.{Generated, Inherited, Motion, Parts, Sizes}
  alias Visualize.Chart.Var
  alias Visualize.Data.Table
  alias Visualize.{Scale, Theme, Units}

  @colour_keys [:fill, :stroke, :effect_color]
  @size_keys [:stroke_width, :opacity, :fill_opacity, :stroke_opacity, :font_size, :symbol_size]
  @font_keys [:font_family]
  @unit_keys [:stroke_width, :font_size, :effect_radius]
  # The built-in styles of spec/14 §3.3, `Visualize.Chart.Schema.builtin_styles/0`.
  @builtin [:axis, :grid, :label, :title]
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
    :font_style,
    :line_height,
    :text_anchor,
    :class,
    :blend,
    :effect,
    :effect_radius,
    :effect_offset,
    :effect_color,
    :vector_effect,
    # A style's motion, resolved (spec/14 §3.10, §3.11, #653).
    :transition,
    :animation,
    :enter,
    :exit
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
    |> Parts.project()
    |> Map.take(@element_keys)
    |> Map.new(fn {key, value} -> {key, value(key, value, theme, mode)} end)
    # A motion part that moves nothing is no key, so a style without one resolves as before.
    |> Map.reject(fn {key, value} ->
      key in [:transition, :animation, :enter, :exit] and value in [[], nil]
    end)
  end

  @doc """
  The map of `resolve/3` with every `{:field, f}` read from the datum (spec/14 §3.4).

  A colour key's reading passes through the frame's `color` scale when the frame
  declares one — a category outside its domain is the scale's `unknown` — and is
  resolved as a theme slot when it is one. A colour is never dropped: a `nil` reading,
  or a scale that yields `nil`, is `:none`, the explicit "no paint" SVG and canvas agree
  on, where an absent fill is black on one and nothing on the other (D-122). Any other
  key's `nil` reading drops the key.
  """
  @spec bind(map(), term(), map(), Theme.mode()) :: map()
  def bind(style, datum, frame, mode) do
    Enum.reduce(style, %{}, fn
      {key, {:field, field}}, acc -> put_reading(acc, key, Table.get(datum, field), frame, mode)
      {key, value}, acc -> Map.put(acc, key, value)
    end)
  end

  defp put_reading(acc, key, nil, _frame, _mode) when key in @colour_keys,
    do: Map.put(acc, key, :none)

  defp put_reading(acc, _key, nil, _frame, _mode), do: acc

  defp put_reading(acc, key, {:paint, _} = paint, _frame, _mode) when key in @colour_keys,
    do: Map.put(acc, key, paint)

  defp put_reading(acc, key, reading, frame, mode) when key in @colour_keys do
    case Map.get(frame.scales, :color) do
      nil -> Map.put(acc, key, color(reading, frame.theme, mode))
      scale -> put_colour(acc, key, Scale.apply(scale, reading), frame.theme, mode)
    end
  end

  # A dash bound to a field is the role's dash when the colour scale maps the reading to a
  # role (spec/14 §21.7), solid — no key — for a role without one.
  defp put_reading(acc, :stroke_dasharray, reading, frame, mode) do
    case role(frame, reading) do
      nil -> Map.put(acc, :stroke_dasharray, value(:stroke_dasharray, reading, frame.theme, mode))
      role -> put_dash(acc, Theme.cue(role).dash)
    end
  end

  defp put_reading(acc, key, reading, frame, mode) do
    Map.put(acc, key, value(key, reading, frame.theme, mode))
  end

  defp put_dash(acc, nil), do: acc
  defp put_dash(acc, dash), do: Map.put(acc, :stroke_dasharray, dash)

  @doc false
  # The role a reading means (spec/14 §21.7): the role the frame's `color` scale maps it to,
  # else the reading itself when it is a role; `nil` otherwise.
  @spec role(map(), term()) :: atom() | nil
  def role(frame, reading) do
    mapped =
      case Map.get(frame.scales, :color) do
        nil -> reading
        scale -> Scale.apply(scale, reading)
      end

    name = colour_name(mapped)
    if name in Theme.role_names(), do: name
  end

  defp put_colour(acc, key, nil, _theme, _mode), do: Map.put(acc, key, :none)

  defp put_colour(acc, key, colour, theme, mode),
    do: Map.put(acc, key, color(colour, theme, mode))

  @doc false
  # The built-in style nodes of spec/14 §3.3, as an author would declare them: the theme's
  # furniture styles of those names (spec/08 §7.7, D-171), the default theme's by default.
  @spec builtin(atom(), Theme.t()) :: map()
  def builtin(name, theme \\ Theme.default()) when name in @builtin do
    Theme.style(theme, name)
  end

  @doc false
  # The declared styles over the theme's whole palette, the built-in four among it: a
  # declared name replaces a palette entry whole, so every palette name is a style
  # reference a design may override (spec/14 §3.3, #637, D-171).
  @spec all(map(), Theme.t()) :: %{atom() => map()}
  def all(declared, theme \\ Theme.default()) do
    theme
    |> Theme.palette()
    |> Map.merge(declared)
    |> Map.new(fn {name, node} -> {name, Parts.normalize(node)} end)
  end

  @doc """
  A style node in the shape it is stored in (spec/14 §3.1, D-172): the flat keys of an
  earlier version moved into their parts, and every shorthand expanded — `fill: :red` is a
  solid paint, `curve: :step` a curve of that type, a gradient's `color` list its stops.

      iex> Visualize.Chart.Style.normalize(%{stroke: :axis, stroke_width: 2})
      %{stroke: %{type: :solid, color: :axis, width: 2}}
      iex> Visualize.Chart.Style.normalize(%{fill: %{type: :linear, color: ["#fff", "#000"]}})
      %{fill: %{type: :linear, stops: [%{at: 0, color: "#fff"}, %{at: 1, color: "#000"}]}}
  """
  @spec normalize(term()) :: term()
  def normalize(node), do: Parts.normalize(node)

  @doc """
  `over` laid on `under` (spec/14 §3.5, D-172): each part merges key by key, so
  `%{stroke: %{width: 3}}` over a dashed red stroke is a dashed red stroke 3 wide — but a
  part whose `type` changes is replaced, keeping only what no type decides (a paint's
  opacity, a stroke's width, dash, join, cap and placement).

      iex> under = Visualize.Chart.Style.normalize(%{stroke: :bad, stroke_dasharray: "4 2"})
      iex> Visualize.Chart.Style.merge(under, %{stroke: %{width: 3}})
      %{stroke: %{type: :solid, color: :bad, dash: "4 2", width: 3}}
      iex> Visualize.Chart.Style.merge(%{fill: %{type: :solid, color: :red, opacity: 0.5}}, %{fill: %{type: :linear, stops: []}})
      %{fill: %{type: :linear, stops: [], opacity: 0.5}}
  """
  @spec merge(map(), map()) :: map()
  def merge(under, over), do: Parts.merge(Parts.normalize(under), Parts.normalize(over))

  @doc """
  A style's parts written as the flat keys an element and a mark's generator read (spec/14
  §3.4, D-172): `fill.color` is `fill`, `stroke.width` is `stroke_width`, `font.size` is
  `font_size`, a curve's type is `curve` and its tension and alpha `curve_opts`. A
  gradient written inline is `{:paint, name}`, drawn from the frame's `defs`. Keys
  already flat pass through, so projecting twice is projecting once.

      iex> Visualize.Chart.Style.project(%{stroke: %{type: :solid, color: :axis, width: 2, dash: [2, 2]}, font: %{size: 12}})
      %{stroke: :axis, stroke_width: 2, stroke_dasharray: [2, 2], font_size: 12}
  """
  @spec project(map()) :: map()
  def project(node), do: Parts.project(node)

  @doc """
  A projected style node with the keys of the parts a mark of `type` does not draw taken
  out (spec/14 §5.6, D-172): a line and a rule draw the stroke, the closed kinds the fill
  and an outline, a symbol its marker too, a text and a label the font and the text
  placement. A part a kind does not draw is ignored, never an error: styles are shared.

      iex> node = %{stroke: :bad, stroke_width: 2, fill: :bad, symbol: :cross}
      iex> Visualize.Chart.Style.drawn(node, :line)
      %{stroke: :bad, stroke_width: 2}
      iex> Visualize.Chart.Style.drawn(node, :rect)
      %{stroke: :bad, stroke_width: 2, fill: :bad}
  """
  @spec drawn(map(), atom()) :: map()
  def drawn(node, type), do: Parts.drawn(node, type)

  @doc false
  # The style node of a **stack** with every entry's `extends` chain flattened — the parent's
  # keys first, the child's over them (spec/14 §3.5) — and the entries then cascaded left to
  # right, the later winning (§3.6). A bare reference is a stack of one by definition, and an
  # inline node is an entry like any other. The empty node when nothing declares it.
  #
  # A `{:field, f}` entry (§3.6) lays nothing here: it is a style named per datum, and
  # `node/3` lays it. Nor does a generator (§3.13), entry or color: it is resolved by a
  # frame, and `node/3` lays it.
  @spec node(%{atom() => map()}, entry | [entry] | nil) :: map()
        when entry: atom() | map() | {:field, atom()} | {:generate, atom(), list()}
  def node(styles, stack), do: node(styles, stack, &no_style/1)

  @doc false
  # `node/2` with each `{:field, f}` entry laid where it stands: `pick` answers the style
  # name the entry names — for one datum, the site's to read (spec/14 §3.6) — or `nil` to
  # lay nothing. A generator is `pick`'s too (§3.13): `{:generate, name, args}` as an entry
  # answers the style it returned, and `{:leaf, call}` for a call at a color the color it
  # returned — `nil` for either lays nothing, the leaf's key left unset.
  #
  # The entries merge in their parts (`merge/2`), and the result is projected onto the flat
  # keys the frame and the marks read (`Visualize.Chart.Style.Parts.project/1`, D-172).
  @spec node(%{atom() => map()}, term(), (term() -> term())) :: map()
  def node(styles, stack, pick), do: styles |> compound(stack, pick) |> Parts.project()

  @doc false
  # `node/3` laid over `base`, the style an element's containers lay under every style it
  # names (spec/14 §3.7, §3.8, D-174), in its parts. An empty base lays nothing, so a design
  # without defaults resolves exactly as `node/3` does.
  #
  # Given what the element inherits (`Visualize.Chart.Style.Inherited`), its unit values are
  # resolved too, measured with the theme it carries (§3.9).
  @spec node(
          %{atom() => map()},
          term(),
          (term() -> term()),
          Inherited.t() | map()
        ) :: map()
  def node(styles, stack, pick, %Inherited{style: base, theme: theme}) do
    own = compound(styles, stack, pick)

    base
    |> Parts.merge(own)
    |> Sizes.resolve(base, own, theme)
    |> Parts.project()
  end

  def node(styles, stack, pick, base) when map_size(base) == 0, do: node(styles, stack, pick)

  def node(styles, stack, pick, base),
    do: base |> Parts.merge(compound(styles, stack, pick)) |> Parts.project()

  @doc false
  # `node/2` laid over `base` (`node/4`).
  @spec over(map(), %{atom() => map()}, term()) :: map()
  def over(base, styles, stack), do: node(styles, stack, &no_style/1, base)

  @doc false
  # `node/4` laid over `base`, `pick` resolving the stack's field entries and generators.
  @spec over(map(), %{atom() => map()}, term(), (term() -> term())) :: map()
  def over(base, styles, stack, pick), do: node(styles, stack, pick, base)

  @doc false
  # `node/3` before the projection: the stack's style in its parts. A list stacks left to
  # right wherever it stands — at the site, as a named style's entry, under `extends`
  # (spec/14 §3.6, #658) — and `seen` carries the names on the way, so a style that reaches
  # itself through a name, a list or an `extends` raises.
  @spec compound(%{atom() => map()}, term(), (term() -> term())) :: map()
  def compound(styles, stack, pick), do: lay(styles, stack, pick, [])

  @doc false
  # The `{:field, f}` entries of a stack, in order (spec/14 §3.6).
  @spec by_data(term()) :: [{:field, atom()}]
  def by_data(stack), do: stack |> List.wrap() |> Enum.filter(&match?({:field, _}, &1))

  @doc """
  The stack with a view-state entry laid at its layer (spec/14 §3.7, D-172): after its names
  and field entries and before a trailing inline node — the site's local edit — so the
  state beats the data's choice and the local edit beats the state.

      iex> Visualize.Chart.Style.with_state([:series, %{stroke: %{width: 5}}], {:field, :state})
      [:series, {:field, :state}, %{stroke: %{width: 5}}]
      iex> Visualize.Chart.Style.with_state(:series, {:field, :state})
      [:series, {:field, :state}]
      iex> Visualize.Chart.Style.with_state(nil, {:field, :state})
      [{:field, :state}]
  """
  @spec with_state(term(), term()) :: list()
  def with_state(stack, entry) do
    case Enum.reverse(List.wrap(stack)) do
      [local | before] when is_map(local) and not is_struct(local) ->
        Enum.reverse(before, [entry, local])

      reversed ->
        Enum.reverse(reversed, [entry])
    end
  end

  defp no_style(_entry), do: nil

  defp lay(_styles, nil, _pick, _seen), do: %{}
  defp lay(_styles, %Var{name: name}, _pick, _seen), do: unresolved!(name)

  defp lay(styles, stack, pick, seen) when is_list(stack) do
    Enum.reduce(stack, %{}, fn entry, resolved ->
      Parts.merge(resolved, lay(styles, entry, pick, seen))
    end)
  end

  defp lay(styles, {:field, _field} = entry, pick, seen) do
    case pick.(entry) do
      nil -> %{}
      name -> named(styles, name, pick, seen)
    end
  end

  # A generator entry lays the style it returned, checked (§3.13): a name, a node or a list.
  defp lay(styles, {:generate, _name, _args} = entry, pick, seen) do
    case pick.(entry) do
      nil -> %{}
      style -> lay(styles, style, pick, seen)
    end
  end

  # An inline node is already the style: only its own `extends` needs laying under it, and
  # a color generator in it its result (§3.13).
  defp lay(styles, inline, pick, seen) when is_map(inline) do
    inline = inline |> Parts.normalize() |> Generated.leaf_resolve(&pick.({:leaf, &1}))

    case Map.fetch(inline, :extends) do
      :error -> inline
      {:ok, parent} -> Parts.merge(lay(styles, parent, pick, seen), Map.delete(inline, :extends))
    end
  end

  defp lay(styles, name, pick, seen), do: named(styles, name, pick, seen)

  # A named style's entry, laid with its name on the way: a node, a name or a list.
  defp named(styles, name, pick, seen) do
    if name in seen, do: cycle!(name)
    lay(styles, Map.get(styles, name, %{}), pick, [name | seen])
  end

  defp cycle!(name) do
    raise ArgumentError,
          "style #{inspect(name)} reaches itself: a cycle through `extends`, a name or a " <>
            "list (spec/14 §3.5, §3.6)"
  end

  @doc false
  # One style value resolved: a slot through the theme, a literal as it is.
  @spec value(atom(), term(), Theme.t(), Theme.mode()) :: term()
  def value(_key, %Var{name: name}, _theme, _mode), do: unresolved!(name)
  # A unit value a style resolved without its containers still reaches the element as a
  # number: an absolute one converted, an `em` against the theme's root (spec/14 §3.9).
  def value(:stroke_dasharray, list, theme, _mode) when is_list(list),
    do: Enum.map_join(list, " ", &sized(&1, theme))

  def value(key, {n, unit} = size, theme, _mode)
      when key in @unit_keys and is_number(n) and is_atom(unit),
      do: sized(size, theme)

  # A paint is the frame's to resolve, once it has its defs (spec/14 §3.2).
  def value(key, {:paint, _name} = paint, _theme, _mode) when key in @colour_keys, do: paint
  # The contrast ink with nothing under the text: the background's, a literal in both modes
  # (§3.2, D-123). A mark's inline label resolves it against its element instead (§5.5).
  def value(key, :contrast, theme, _mode) when key in @colour_keys, do: Theme.ink(theme, nil)

  def value(key, {:contrast, :under}, theme, _mode) when key in @colour_keys,
    do: Theme.ink(theme, nil)

  # A transition is the list of the properties it moves (§3.10, D-176).
  def value(:transition, node, _theme, _mode), do: Motion.transition(node)
  def value(:animation, node, _theme, _mode), do: Motion.animation(node)
  def value(key, node, _theme, _mode) when key in [:enter, :exit], do: Motion.presence(node)
  # The weight words CSS lacks are their numbers; normal and bold are CSS's own (§3.4).
  def value(:font_weight, :light, _theme, _mode), do: 300
  def value(:font_weight, :medium, _theme, _mode), do: 500
  def value(key, value, theme, mode) when key in @colour_keys, do: slot_or(value, theme, mode)
  def value(key, value, theme, mode) when key in @size_keys, do: slot_or(value, theme, mode)
  def value(key, value, theme, mode) when key in @font_keys, do: slot_or(value, theme, mode)
  def value(_key, value, _theme, _mode), do: value

  defp sized(size, theme) do
    if Units.unit?(size), do: Units.resolve(size, %{em: theme.font_size}), else: size
  end

  @doc false
  # A colour a scale yields, resolved when it is a theme slot (spec/14 §4.3).
  @spec color(term(), Theme.t(), Theme.mode()) :: term()
  def color(value, theme, mode), do: slot_or(value, theme, mode)

  @doc false
  # Whether a value is a colour an element can be painted with: a string, `:none`, a typed
  # color (spec/08 §1.9), or a bare name as a scale or a component may still give one.
  @spec color?(term()) :: boolean()
  def color?(value) when is_binary(value) or value == :none, do: true
  def color?({:ramp, name, t}), do: is_atom(name) and is_number(t)
  def color?(value) when is_tuple(value), do: Visualize.Color.value?(value)
  def color?(value), do: is_atom(value) and value not in [nil, true, false]

  @doc false
  # The name a colour reads from the theme's table, when it is one name: `:bad` for
  # `{:color, :bad}` and for a bare `:bad`; `nil` for anything else.
  @spec colour_name(term()) :: atom() | nil
  def colour_name({:color, name}) when is_atom(name), do: name
  def colour_name(name) when is_atom(name) and name not in [nil, true, false, :none], do: name
  def colour_name(_other), do: nil

  defp slot_or(:none, _theme, _mode), do: :none
  # A typed color (spec/08 §1.9, D-173), a name or a transform, through its one door.
  defp slot_or({:color, _} = colour, theme, mode),
    do: Visualize.Color.resolve(colour, theme, mode)

  defp slot_or({:contrast, :under}, theme, _mode), do: Theme.ink(theme, nil)

  defp slot_or(value, theme, mode)
       when is_tuple(value) and elem(value, 0) != :series and elem(value, 0) != :ramp do
    if Visualize.Color.value?(value), do: Visualize.Color.resolve(value, theme, mode), else: value
  end

  defp slot_or({:series, _} = slot, theme, mode), do: Theme.resolve(theme, slot, mode)
  # A ramp position, a meaning the theme renders (spec/14 §3.2, D-135).
  defp slot_or({:ramp, _, _} = position, theme, mode), do: Theme.resolve(theme, position, mode)
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
