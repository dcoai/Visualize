defmodule Visualize.Chart.Mark.Strokes do
  @moduledoc false
  # The stroke style of a mark (spec/14 §5.6): how the stroke sits on the edge. `:single`
  # is the element as it is; `:inside` and `:outside` clip a doubled stroke to the shape
  # or to everything but it; `:double` lays a thinner stroke in the fill colour over the
  # first. The style node carries the key — it is not an element key — and the mark
  # reads it here, after its elements are bound.

  alias Visualize.IR.Element
  alias Visualize.Theme

  @open [:line, :rule, :percentile_band]
  @shapes [:path, :rect, :circle, :ellipse, :polygon]

  @doc false
  # The mark's bound elements as the stroke style draws them.
  @spec apply([Element.t()], map()) :: [Element.t()]
  def apply(elements, ctx) do
    case Map.get(ctx.style_node, :stroke_style, :single) do
      :single -> elements
      :double -> Enum.flat_map(elements, &double(&1, width(ctx), gap_colour(ctx)))
      style when style in [:inside, :outside] -> edged(elements, style, ctx)
    end
  end

  # Inside and outside belong to a closed mark; an open one draws single.
  defp edged(elements, _style, %{type: type}) when type in @open, do: elements

  defp edged(elements, :inside, ctx) do
    for element <- elements do
      if element.type in @shapes,
        do:
          element
          |> Element.set_style(%{stroke_width: 2 * width(ctx)})
          |> Element.clip(element, :inside),
        else: element
    end
  end

  defp edged(elements, :outside, ctx) do
    Enum.flat_map(elements, fn element ->
      if element.type in @shapes do
        [
          Element.set_style(element, %{stroke: :none}),
          element
          |> Element.set_style(%{fill: :none, stroke_width: 2 * width(ctx)})
          |> Element.clip(element, :outside)
        ]
      else
        [element]
      end
    end)
  end

  defp double(element, width, colour) do
    if element.type in @shapes,
      do: [
        element,
        Element.set_style(element, %{fill: :none, stroke: colour, stroke_width: width / 3})
      ],
      else: [element]
  end

  # The stroke's width: the style's, `1` when it gives none or a slot the mark cannot read.
  defp width(%{static: static}) do
    case Map.get(static, :stroke_width) do
      n when is_number(n) -> n
      _other -> 1
    end
  end

  # The colour between a double stroke's lines: the paint when the paint is the fill,
  # else the theme's background.
  defp gap_colour(%{paint: {:fill, colour}}) when is_binary(colour), do: colour

  defp gap_colour(%{frame: %{theme: theme}, mode: mode}),
    do: Theme.resolve(theme, :background, mode)
end
