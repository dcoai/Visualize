defmodule Visualize.Chart.Frame.Paints do
  @moduledoc false
  # The design's paints (spec/14 §2.7, §3.2): one `defs` element first in the frame's
  # group holding every gradient, and every `{:paint, name}` in the tree's styles
  # resolved — `url(#id)` for the SVG output, the first stop's colour for a canvas.

  alias Visualize.Chart.{Schema, Style, Var}
  alias Visualize.IR.Element

  @doc false
  # The `defs` element holding the design's gradients, or `[]` with none.
  @spec defs(map(), atom()) :: [Element.t()]
  def defs(%{defs: defs}, _mode) when map_size(defs) == 0, do: []

  def defs(%{defs: defs, theme: theme}, mode) do
    prefix = prefix(defs)

    gradients =
      for {name, node} <- Enum.sort_by(defs, fn {name, _} -> name end) do
        gradient(id(prefix, name), node, theme, mode)
      end

    [Element.defs(gradients)]
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

  # -- the gradient element ---------------------------------------------------------------

  defp gradient(id, node, theme, mode) do
    stops =
      for stop <- stops(node) do
        Element.stop(
          "#{round(Map.fetch!(stop, :offset) * 100)}%",
          Style.colour(colour(stop), theme, mode),
          opacity: Map.get(stop, :opacity, Schema.default(:stop, :opacity))
        )
      end

    case Map.fetch!(node, :kind) do
      :linear ->
        angle = Map.get(node, :angle, Schema.default(:gradient, :angle)) * :math.pi() / 180
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
        [cx, cy] = Map.get(node, :centre, Schema.default(:gradient, :centre))
        r = Map.get(node, :radius, Schema.default(:gradient, :radius))

        id
        |> Element.radial_gradient(cx: cx, cy: cy, r: r, fx: cx, fy: cy, stops: stops)
        |> Element.set_attrs(%{gradient_units: "objectBoundingBox"})
    end
  end

  defp stops(node) do
    case Map.fetch!(node, :stops) do
      %Var{name: name} -> Style.unresolved!(name)
      stops -> Enum.sort_by(stops, &Map.fetch!(&1, :offset))
    end
  end

  defp colour(stop) do
    case Map.fetch!(stop, :colour) do
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
  @spec id(String.t(), atom()) :: String.t()
  def id(prefix, name), do: "vis-paint-#{prefix}-#{name}"
end
