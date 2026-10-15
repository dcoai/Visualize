defmodule Visualize.Chart.Frame.Defs do
  @moduledoc false
  # The frame's `defs` (spec/14 §2.7, §3.2): one element first in the frame's group
  # holding every gradient the design declares or a style writes inline, and one filter
  # per effect the tree uses, and every `{:paint, name}` in the tree's styles resolved to
  # the paint itself, a `Visualize.IR.Paint` every backend draws — SVG as `url(#id)`, a
  # canvas as a gradient over each element's box (#652, D-175). A gradient written inline
  # is held under the name `Visualize.Chart.Style.Parts.paint_name/1` gives it, a string,
  # beside the declared ones (D-172).

  alias Visualize.Chart.{Schema, Style, Var}
  alias Visualize.IR.{Element, Paint}
  alias Visualize.Units

  # A hatch's angle when it gives none; the schema's `180` is a linear gradient's (spec/14
  # §3.1).
  @hatch_angle 45

  @doc false
  # The `defs` element holding the design's paints and the filters the tree's effects need,
  # or `[]` with neither. A declared paint is always declared; one written in place (a
  # string name) only when the tree draws it — the theme's palette is among the styles it
  # was found in — unless `all: true`, for a compiled chart whose later ticks may draw
  # what this one did not (spec/14 §2.7, #673).
  @spec defs(map(), atom(), Element.t(), keyword()) :: [Element.t()]
  def defs(%{defs: defs, theme: theme}, mode, tree, opts \\ []) do
    prefix = prefix(defs)
    drawn = if Keyword.get(opts, :all, false), do: :all, else: drawn(tree)

    gradients =
      for {name, node} <- Enum.sort_by(defs, fn {name, _} -> name end),
          is_atom(name) or drawn == :all or MapSet.member?(drawn, id(prefix, name)) do
        node |> paint(id(prefix, name), theme, mode) |> Paint.definition()
      end

    case gradients ++ filters(tree) do
      [] -> []
      children -> [Element.defs(children)]
    end
  end

  # The ids of the paints the tree's styles draw.
  defp drawn(%Element{style: style, children: children}) do
    own = for %Paint{id: id} <- [style[:fill], style[:stroke]], into: MapSet.new(), do: id
    Enum.reduce(children, own, &MapSet.union(drawn(&1), &2))
  end

  # One filter per {effect, radius} pair any style in the tree carries (spec/14 §2.7).
  defp filters(tree) do
    tree
    |> effects()
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.map(fn {effect, radius} ->
      Element.filter(Visualize.Backend.SVG.effect_id(effect, radius), [primitive(effect, radius)])
    end)
  end

  defp primitive(:shadow, radius), do: Element.drop_shadow(radius / 2, radius / 2, radius)
  defp primitive(:blur, radius), do: Element.gaussian_blur(radius)

  defp effects(%Element{style: style, children: children}) do
    own =
      case Map.get(style, :effect) do
        effect when effect in [:shadow, :blur] -> [{effect, Map.get(style, :effect_radius) || 3}]
        _none -> []
      end

    own ++ Enum.flat_map(children, &effects/1)
  end

  @doc false
  # The tree with every `{:paint, name}` in a style resolved to its paint for the mode.
  @spec resolve(Element.t(), map(), atom()) :: Element.t()
  def resolve(element, %{defs: defs}, _mode) when map_size(defs) == 0, do: element

  def resolve(element, %{defs: defs, theme: theme}, mode) do
    prefix = prefix(defs)

    walk(element, fn %Element{style: style} = el ->
      %{el | style: Map.new(style, fn {k, v} -> {k, value(v, defs, prefix, theme, mode)} end)}
    end)
  end

  defp walk(%Element{children: children} = element, fun) do
    fun.(%{element | children: Enum.map(children, &walk(&1, fun))})
  end

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
  # A paint's first stop's colour, a literal (spec/14 §5.5): the one colour that stands for
  # a gradient where one colour must — what a label's ink is chosen against; `nil` for an
  # undeclared name.
  @spec literal(atom() | String.t(), map()) :: String.t() | nil
  def literal(name, %{defs: defs, theme: theme}) do
    case Map.fetch(defs, name) do
      # A hatch's ground is what a text over it is read against; with none, nothing is
      # under the text but the page (spec/14 §5.5, #673).
      {:ok, %{type: :hatch} = node} ->
        case Map.get(node, :background) do
          background when background in [nil, :none] -> nil
          background -> Style.colour(background, theme, :literal)
        end

      {:ok, node} ->
        [first | _] = stops(node)
        Style.colour(colour(first), theme, :literal)

      :error ->
        nil
    end
  end

  # -- the paint --------------------------------------------------------------------------

  # The node as the paint every backend draws: its geometry in box units derived from the
  # words a person wrote (spec/14 §2.7), its stops' colours resolved for the mode.
  defp paint(%{type: :hatch} = node, id, theme, mode) do
    size = fn key ->
      Units.resolve(Map.get(node, key, Schema.default(:paint, key)), %{em: theme.font_size})
    end

    background =
      case Map.get(node, :background) do
        background when background in [nil, :none] -> nil
        background -> Style.colour(unvar(background), theme, mode)
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
      color: Style.colour(unvar(Map.fetch!(node, :color)), theme, mode),
      background: background
    }
  end

  defp paint(node, id, theme, mode) do
    stops =
      for stop <- stops(node) do
        {Map.fetch!(stop, :at) * 1.0, Style.colour(colour(stop), theme, mode),
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

  defp colour(stop), do: unvar(Map.fetch!(stop, :color))

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
