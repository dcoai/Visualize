defmodule Visualize.Chart.Frame.Position do
  @moduledoc false
  # How a text sits on its point (spec/14 §6.3, §5.5): the position keys of its style
  # node — `vertical_align`, `margin_x`, `margin_y`, `text_angle` — applied to a placed
  # text element, given the placement's outward direction. The keys are the node's, not
  # the element's: nothing here reaches the SVG as an attribute.

  alias Visualize.IR.{Element, Transform}
  alias Visualize.Units

  @typedoc "The outward direction of a placement, as signs, or none."
  @type outward :: {-1 | 0 | 1, -1 | 0 | 1} | nil

  @baselines %{baseline: nil, middle: "0.32em", top: "0.71em", bottom: "-0.25em"}

  @doc false
  # `box` is `{width, height}` of what the text labels, which an offset in `pct` is of
  # (spec/14 §3.9): the labelled element's bounds, or the plot.
  @spec apply(Element.t(), map(), outward(), {number(), number()}) :: Element.t()
  def apply(text, node, outward, box)

  def apply(%Element{type: :text} = text, node, outward, {width, height}) when is_map(node) do
    mx = sized(Map.get(node, :margin_x, 0), width)
    my = sized(Map.get(node, :margin_y, 0), height)

    text
    |> aligned(Map.get(node, :vertical_align))
    |> margined(mx, my, outward)
    |> rotated(Map.get(node, :text_angle, 0))
  end

  def apply(element, _node, _outward, _box), do: element

  defp sized(size, box),
    do: if(Units.unit?(size), do: Units.resolve(size, %{box: box}), else: size)

  @doc false
  # Every tick label of an axis turned about its own point, when the style says so.
  @spec rotate_ticks(Element.t(), map()) :: Element.t()
  def rotate_ticks(element, node) when is_map(node) do
    case Map.get(node, :text_angle, 0) do
      0 -> element
      angle -> walk(element, &rotated(&1, angle))
    end
  end

  defp walk(%Element{type: :text} = text, fun), do: fun.(text)
  defp walk(%Element{children: []} = element, _fun), do: element

  defp walk(%Element{children: children} = element, fun),
    do: %{element | children: Enum.map(children, &walk(&1, fun))}

  defp aligned(text, align) when is_map_key(@baselines, align) do
    case Map.fetch!(@baselines, align) do
      nil -> %{text | attrs: Map.delete(text.attrs, :dy)}
      dy -> %{text | attrs: Map.put(text.attrs, :dy, dy)}
    end
  end

  defp aligned(text, _other), do: text

  defp margined(text, mx, my, {sx, sy})
       when is_number(mx) and is_number(my) and (mx != 0 or my != 0) do
    attrs =
      text.attrs
      |> Map.update(:x, 0, &(&1 + sx * mx))
      |> Map.update(:y, 0, &(&1 + sy * my))

    %{text | attrs: attrs}
  end

  defp margined(text, _mx, _my, _outward), do: text

  defp rotated(text, angle) when is_number(angle) and angle != 0 do
    x = Map.get(text.attrs, :x, 0)
    y = Map.get(text.attrs, :y, 0)
    transform = Transform.rotate(text.transform || Transform.new(), angle, x, y)
    %{text | transform: transform}
  end

  defp rotated(text, _angle), do: text
end
