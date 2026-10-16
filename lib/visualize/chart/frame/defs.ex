defmodule Visualize.Chart.Frame.Defs do
  @moduledoc false
  # The frame's `defs` (spec/14 §2.7, §3.2): one element first in the frame's group
  # holding every gradient the design declares or a style writes inline, and one filter
  # per effect the tree uses, and every `{:paint, name}` in the tree's styles resolved to
  # the paint itself, a `Visualize.IR.Paint` every backend draws — SVG as `url(#id)`, a
  # canvas as a gradient over each element's box (#652, D-175). A gradient written inline
  # reaches the tree as `{:paint, node}`, the node its style resolved to, and is named by
  # `Visualize.Chart.Style.Parts.paint_name/1` of that node, a string, beside the declared
  # ones (D-172, D-186).

  alias Visualize.Chart.{Schema, Style, Var}
  alias Visualize.Chart.Style.Parts
  alias Visualize.IR.{Element, Paint}
  alias Visualize.Units

  # A hatch's angle when it gives none; the schema's `180` is a linear gradient's (spec/14
  # §3.1).
  @hatch_angle 45

  @doc false
  # The `defs` element holding the design's paints and the filters the tree's effects need,
  # or `[]` with neither. A declared paint is always declared; one written in place (a
  # string name) when the tree — resolved by `resolve/3` — draws it, as its style resolved
  # it (D-186): the theme's palette is among the styles searched, so the frame's table
  # alone would declare every role's hatch. With `all: true`, for a compiled chart whose
  # later ticks may draw what this one did not, every one of the table too (spec/14 §2.7,
  # #673).
  @spec defs(map(), atom(), Element.t(), keyword()) :: [Element.t()]
  def defs(%{defs: defs, theme: theme}, mode, tree, opts \\ []) do
    prefix = prefix(defs)

    table =
      for {name, node} <- defs,
          is_atom(name) or Keyword.get(opts, :all, false),
          into: %{},
          do: {name, paint(node, id(prefix, name), theme, mode)}

    known = MapSet.new(table, fn {_name, paint} -> paint.id end)

    # Every other paint the tree draws is one written in place, under its name.
    inline =
      for {id, paint} <- drawn(tree),
          id not in known,
          into: %{},
          do: {String.replace_prefix(id, id(prefix, ""), ""), paint}

    gradients =
      table
      |> Map.merge(inline)
      |> Enum.sort_by(fn {name, _paint} -> name end)
      |> Enum.map(fn {_name, paint} -> Paint.definition(paint) end)

    case gradients ++ filters(tree) do
      [] -> []
      children -> [Element.defs(children)]
    end
  end

  # The paints the tree's styles draw, by id.
  defp drawn(%Element{style: style, children: children}) do
    own = for %Paint{id: id} = paint <- [style[:fill], style[:stroke]], into: %{}, do: {id, paint}
    Enum.reduce(children, own, &Map.merge(drawn(&1), &2))
  end

  # One filter per distinct effect any style in the tree carries: its type and radius, and a
  # shadow's offset and color (spec/14 §2.7, #674).
  defp filters(tree) do
    tree
    |> effects()
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.map(fn {effect, radius, offset, color} ->
      Element.filter(Visualize.Backend.SVG.effect_id(effect, radius, offset, color), [
        primitive(effect, radius, offset, color)
      ])
    end)
  end

  defp primitive(:shadow, radius, nil, color),
    do: primitive(:shadow, radius, [radius / 2, radius / 2], color)

  defp primitive(:shadow, radius, [dx, dy], color), do: Element.drop_shadow(dx, dy, radius, color)
  defp primitive(:blur, radius, _offset, _color), do: Element.gaussian_blur(radius)

  defp effects(%Element{style: style, children: children}) do
    own =
      case Map.get(style, :effect) do
        :shadow ->
          [
            {:shadow, Map.get(style, :effect_radius) || 3, style[:effect_offset],
             style[:effect_color]}
          ]

        :blur ->
          [{:blur, Map.get(style, :effect_radius) || 3, nil, nil}]

        _none ->
          []
      end

    own ++ Enum.flat_map(children, &effects/1)
  end

  @doc false
  # The tree with every `{:paint, name}` and `{:paint, node}` in a style resolved to its
  # paint for the mode.
  @spec resolve(Element.t(), map(), atom()) :: Element.t()
  def resolve(element, %{defs: defs, theme: theme}, mode) do
    prefix = prefix(defs)

    walk(element, fn %Element{style: style} = el ->
      %{el | style: Map.new(style, fn {k, v} -> {k, value(v, defs, prefix, theme, mode)} end)}
    end)
  end

  defp walk(%Element{children: children} = element, fun) do
    fun.(%{element | children: Enum.map(children, &walk(&1, fun))})
  end

  # A gradient written in place, as its style resolved it (spec/14 §3.2, D-186).
  defp value({:paint, %{} = node}, _defs, prefix, theme, mode) when not is_struct(node),
    do: paint(node, id(prefix, Parts.paint_name(node)), theme, mode)

  defp value({:paint, name}, defs, prefix, theme, mode) do
    case Map.fetch(defs, name) do
      {:ok, node} ->
        paint(node, id(prefix, name), theme, mode)

      :error ->
        raise ArgumentError, "paint #{inspect(name)} is not declared under defs (spec/14 §2.7)"
    end
  end

  defp value(value, _defs, _prefix, _theme, _mode), do: value

  @doc false
  # A paint's first stop's color, a literal (spec/14 §5.5): the one color that stands for
  # a gradient where one color must — what a label's ink is chosen against; `nil` for an
  # undeclared name. A gradient written in place is given as its node (D-186).
  @spec literal(atom() | map(), map()) :: String.t() | nil
  def literal(%{} = node, %{theme: theme}) when not is_struct(node), do: node_literal(node, theme)

  def literal(name, %{defs: defs, theme: theme}) do
    case Map.fetch(defs, name) do
      {:ok, node} -> node_literal(node, theme)
      :error -> nil
    end
  end

  # A hatch's ground is what a text over it is read against; with none, nothing is under
  # the text but the page (spec/14 §5.5, #673).
  defp node_literal(%{type: :hatch} = node, theme) do
    case Map.get(node, :background) do
      background when background in [nil, :none] -> nil
      background -> Style.color(background, theme, :literal)
    end
  end

  defp node_literal(node, theme) do
    [first | _] = stops(node)
    Style.color(color(first), theme, :literal)
  end

  # -- the paint --------------------------------------------------------------------------

  # The node as the paint every backend draws: its geometry in box units derived from the
  # words a person wrote (spec/14 §2.7), its stops' colors resolved for the mode.
  defp paint(%{type: :hatch} = node, id, theme, mode) do
    size = fn key ->
      Units.resolve(Map.get(node, key, Schema.default(:paint, key)), %{em: theme.font_size})
    end

    background =
      case Map.get(node, :background) do
        background when background in [nil, :none] -> nil
        background -> Style.color(unvar(background), theme, mode)
      end

    %Paint{
      id: id,
      type: :hatch,
      geometry: %{
        pattern: Map.get(node, :pattern, Schema.default(:paint, :pattern)),
        angle: Map.get(node, :angle, @hatch_angle),
        spacing: size.(:spacing),
        width: size.(:width)
      },
      color: Style.color(unvar(Map.fetch!(node, :color)), theme, mode),
      background: background
    }
  end

  defp paint(node, id, theme, mode) do
    stops =
      for stop <- stops(node) do
        {Map.fetch!(stop, :at) * 1.0, Style.color(color(stop), theme, mode),
         Map.get(stop, :opacity, Schema.default(:stop, :opacity))}
      end

    %Paint{id: id, type: Map.fetch!(node, :type), geometry: geometry(node), stops: stops}
  end

  defp geometry(%{type: :linear} = node) do
    angle = Map.get(node, :angle, Schema.default(:paint, :angle)) * :math.pi() / 180
    {sx, cx} = {:math.sin(angle) / 2, :math.cos(angle) / 2}
    %{x1: tidy(0.5 - sx), y1: tidy(0.5 + cx), x2: tidy(0.5 + sx), y2: tidy(0.5 - cx)}
  end

  defp geometry(%{type: :radial} = node) do
    [cx, cy] = Map.get(node, :center, Schema.default(:paint, :center))
    %{cx: cx, cy: cy, r: Map.get(node, :radius, Schema.default(:paint, :radius))}
  end

  defp stops(node) do
    case Map.fetch!(node, :stops) do
      %Var{name: name} -> Style.unresolved!(name)
      stops -> Enum.sort_by(stops, &Map.fetch!(&1, :at))
    end
  end

  defp color(stop), do: unvar(Map.fetch!(stop, :color))

  defp unvar(%Var{name: name}), do: Style.unresolved!(name)
  defp unvar(value), do: value

  # A coordinate rounded to what the angle means, so 180° is exactly top to bottom.
  defp tidy(n), do: Float.round(n * 1.0, 4)

  @doc false
  # The id prefix the design's paints share: a hash of the defs, so two charts on one
  # page collide only when their paints are the same.
  @spec prefix(map()) :: String.t()
  def prefix(defs), do: defs |> :erlang.phash2() |> Integer.to_string(36) |> String.downcase()

  @doc false
  @spec id(String.t(), atom() | String.t()) :: String.t()
  def id(prefix, name), do: "vis-paint-#{prefix}-#{name}"
end
