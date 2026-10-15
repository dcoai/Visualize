defmodule Visualize.Chart.Frame.Defs do
  @moduledoc false
  # The frame's `defs` (spec/14 §2.7, §3.2): one element first in the frame's group
  # holding every gradient the design declares or a style writes inline, and one filter
  # per effect the tree uses, and every `{:paint, name}` in the tree's styles resolved —
  # `url(#id)` for the SVG output, the first stop's colour for a canvas. A gradient written
  # inline is held under the name `Visualize.Chart.Style.Parts.paint_name/1` gives it, a
  # string, beside the declared ones (D-172).

  alias Visualize.Chart.{Schema, Style, Var}
  alias Visualize.IR.Element

  @doc false
  # The `defs` element holding the design's gradients and the filters the tree's effects
  # need, or `[]` with neither.
  @spec defs(map(), atom(), Element.t()) :: [Element.t()]
  def defs(%{defs: defs, theme: theme}, mode, tree) do
    prefix = prefix(defs)

    gradients =
      for {name, node} <- Enum.sort_by(defs, fn {name, _} -> name end) do
        gradient(id(prefix, name), node, theme, mode)
      end

    case gradients ++ filters(tree) do
      [] -> []
      children -> [Element.defs(children)]
    end
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
  # The tree with every `{:paint, name}` in a style resolved for the mode.
  @spec resolve(Element.t(), map(), atom()) :: Element.t()
  def resolve(element, %{defs: defs}, _mode) when map_size(defs) == 0, do: element

  def resolve(element, %{defs: defs, theme: theme}, mode) do
    prefix = prefix(defs)

    walk(element, fn %Element{style: style} = el ->
      %{el | style: Map.new(style, fn {k, v} -> {k, paint(v, defs, prefix, theme, mode)} end)}
    end)
  end

  defp walk(%Element{children: children} = element, fun) do
    fun.(%{element | children: Enum.map(children, &walk(&1, fun))})
  end

  defp paint({:paint, name}, defs, prefix, theme, mode) do
    case Map.fetch(defs, name) do
      {:ok, node} when mode == :literal ->
        [first | _] = stops(node)
        Style.colour(colour(first), theme, :literal)

      {:ok, _node} ->
        "url(##{id(prefix, name)})"

      :error ->
        raise ArgumentError, "paint #{inspect(name)} is not declared under defs (spec/14 §2.7)"
    end
  end

  defp paint(value, _defs, _prefix, _theme, _mode), do: value

  @doc false
  # A paint's colour as a canvas draws it — its first stop's, a literal (spec/14 §3.2) — for
  # what reads the colour an element is filled with (§5.5); `nil` for an undeclared name.
  @spec literal(atom() | String.t(), map()) :: String.t() | nil
  def literal(name, %{defs: defs, theme: theme}) do
    case Map.fetch(defs, name) do
      {:ok, node} ->
        [first | _] = stops(node)
        Style.colour(colour(first), theme, :literal)

      :error ->
        nil
    end
  end

  # -- the gradient element ---------------------------------------------------------------

  defp gradient(id, node, theme, mode) do
    stops =
      for stop <- stops(node) do
        Element.stop(
          "#{round(Map.fetch!(stop, :at) * 100)}%",
          Style.colour(colour(stop), theme, mode),
          opacity: Map.get(stop, :opacity, Schema.default(:stop, :opacity))
        )
      end

    case Map.fetch!(node, :type) do
      :linear ->
        angle = Map.get(node, :angle, Schema.default(:paint, :angle)) * :math.pi() / 180
        {sx, cx} = {:math.sin(angle) / 2, :math.cos(angle) / 2}

        id
        |> Element.linear_gradient(
          x1: tidy(0.5 - sx),
          y1: tidy(0.5 + cx),
          x2: tidy(0.5 + sx),
          y2: tidy(0.5 - cx),
          stops: stops
        )
        |> Element.set_attrs(%{gradient_units: "objectBoundingBox"})

      :radial ->
        [cx, cy] = Map.get(node, :center, Schema.default(:paint, :center))
        r = Map.get(node, :radius, Schema.default(:paint, :radius))

        id
        |> Element.radial_gradient(cx: cx, cy: cy, r: r, fx: cx, fy: cy, stops: stops)
        |> Element.set_attrs(%{gradient_units: "objectBoundingBox"})
    end
  end

  defp stops(node) do
    case Map.fetch!(node, :stops) do
      %Var{name: name} -> Style.unresolved!(name)
      stops -> Enum.sort_by(stops, &Map.fetch!(&1, :at))
    end
  end

  defp colour(stop) do
    case Map.fetch!(stop, :color) do
      %Var{name: name} -> Style.unresolved!(name)
      colour -> colour
    end
  end

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
