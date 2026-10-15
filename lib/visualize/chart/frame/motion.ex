defmodule Visualize.Chart.Frame.Motion do
  @moduledoc false
  # The frame's motion in `:css` output (spec/14 §3.10, D-176): each distinct resolved
  # transition an element carries is a class, `vis-transition-<h>`, and one rule in a
  # `<style>` first in the frame's group, so a hundred bars of one transition carry it once.
  # The rule reaches the element and, at no specificity, everything under it — a mark's
  # group moves its children, and a child's own class still wins. The fill and the stroke
  # of a moving element, and of everything under it, are written `oklch()`, so the browser
  # interpolates them in OKLab. The style ends with the reduced-motion rule, `!important`
  # so no design beats it. In `:literal` mode nothing is written: a canvas reads the keys.

  alias Visualize.IR.{Element, Motion}

  @reduced "@media (prefers-reduced-motion: reduce) { [class*=\"vis-transition-\"], " <>
             "[class*=\"vis-transition-\"] * { transition: none !important; } }"

  @doc false
  # The tree with every transition written as its class, and the `<style>` the classes
  # need — `[]` when the tree moves nothing or the mode is not `:css`.
  @spec apply(Element.t(), atom()) :: {Element.t(), [Element.t()]}
  def apply(tree, :css) do
    case walk(tree, []) do
      {tree, []} ->
        {tree, []}

      {tree, rules} ->
        css =
          rules
          |> Enum.uniq()
          |> Enum.sort()
          |> Enum.map(fn {class, transition} ->
            ".#{class}, :where(.#{class}) * { transition: #{Motion.css_transition(transition)}; }"
          end)

        {tree, [Element.stylesheet(Enum.join(css ++ [@reduced], "\n"))]}
    end
  end

  def apply(tree, _mode), do: {tree, []}

  # `moving` is the colour keys the nearest transition above moves.
  defp walk(%Element{style: style, children: children} = element, moving) do
    {style, rules, moving} =
      case Map.pop(style, :transition) do
        {[_ | _] = transition, style} ->
          class = class(transition)
          moved = for {key, _d, _e} <- transition, key in [:fill, :stroke], do: key
          {add_class(style, class), [{class, transition}], moved}

        {_none, style} ->
          {style, [], moving}
      end

    style =
      Enum.reduce(moving, style, fn key, acc ->
        if Map.has_key?(acc, key), do: Map.update!(acc, key, &Motion.oklch/1), else: acc
      end)

    {children, below} =
      Enum.map_reduce(children, [], fn child, acc ->
        {child, found} = walk(child, moving)
        {child, acc ++ found}
      end)

    {%{element | style: style, children: children}, rules ++ below}
  end

  defp class(transition) do
    "vis-transition-" <>
      (transition |> :erlang.phash2() |> Integer.to_string(36) |> String.downcase())
  end

  defp add_class(style, class) do
    Map.update(style, :class, class, fn own -> own <> " " <> class end)
  end
end
