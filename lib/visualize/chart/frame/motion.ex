defmodule Visualize.Chart.Frame.Motion do
  @moduledoc false
  # The frame's motion in `:css` output (spec/14 §3.10, §3.11, D-176): each distinct resolved
  # transition or animation an element carries is a class, and one rule in a `<style>` first
  # in the frame's group, so a hundred bars of one motion carry it once.
  #
  # A transition's class is the element's own, and its rule reaches the element and, at no
  # specificity, everything under it — a mark's group moves its children, and a child's own
  # class still wins. The fill and the stroke of an element whose colour moves, and of
  # everything under it, are written `oklch()`, so the browser interpolates them in OKLab.
  #
  # An animation's class is a wrapper's, `<g class="vis-animation-<h>">` around the element,
  # so the box a spin turns about is the element's as drawn, its own transform included; the
  # style holds the `@keyframes` of each built-in drawn. A host's keyframes name is written as
  # it is, once it is one CSS identifier.
  #
  # The style ends with the reduced-motion rules, `!important` so no design beats them. In
  # `:literal` mode nothing is written: a canvas reads the keys.

  alias Visualize.Chart.Validator
  alias Visualize.IR.{Element, Motion}

  @reduced_transitions "@media (prefers-reduced-motion: reduce) { [class*=\"vis-transition-\"], " <>
                         "[class*=\"vis-transition-\"] * { transition: none !important; } }"
  @reduced_animations "@media (prefers-reduced-motion: reduce) { [class*=\"vis-animation-\"] " <>
                        "{ animation: none !important; } }"

  @doc false
  # The tree with every motion written as its class, and the `<style>` the classes need —
  # `[]` when the tree moves nothing or the mode is not `:css`. Raises `ArgumentError` for a
  # host's keyframes name that is not a CSS identifier (spec/14 §10.3).
  @spec apply(Element.t(), atom()) :: {Element.t(), [Element.t()]}
  def apply(tree, :css) do
    case walk(tree, []) do
      {tree, []} ->
        {tree, []}

      {tree, rules} ->
        rules = rules |> Enum.uniq() |> Enum.sort()
        transitions = for {:transition, class, t} <- rules, do: transition_rule(class, t)
        animations = for {:animation, class, a} <- rules, do: animation_rule(class, a)

        keyframes =
          for {:animation, _class, %{name: name}} <- rules, is_atom(name), uniq: true do
            Motion.css_keyframes(name)
          end

        css =
          transitions ++
            keyframes ++
            animations ++
            if(transitions == [], do: [], else: [@reduced_transitions]) ++
            if(animations == [], do: [], else: [@reduced_animations])

        {tree, [Element.stylesheet(Enum.join(css, "\n"))]}
    end
  end

  def apply(tree, _mode), do: {tree, []}

  defp transition_rule(class, transition),
    do: ".#{class}, :where(.#{class}) * { transition: #{Motion.css_transition(transition)}; }"

  defp animation_rule(class, %{name: name} = animation) do
    if is_binary(name) and not Validator.Motion.identifier?(name) do
      raise ArgumentError,
            "animation name #{inspect(name)} is not a CSS identifier (spec/14 §10.3)"
    end

    ".#{class} { animation: #{Motion.css_animation(animation)}; " <>
      "transform-box: fill-box; transform-origin: center; }"
  end

  # `moving` is the colour keys the nearest transition above moves.
  defp walk(%Element{style: style, children: children} = element, moving) do
    {animation, style} = Map.pop(style, :animation)

    {style, rules, moving} =
      case Map.pop(style, :transition) do
        {[_ | _] = transition, style} ->
          class = class("transition", transition)
          moved = for {key, _d, _e} <- transition, key in [:fill, :stroke], do: key
          {add_class(style, class), [{:transition, class, transition}], moved}

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

    element = %{element | style: style, children: children}

    case animation do
      %{} ->
        class = class("animation", animation)

        {Element.group([element], style: %{class: class}),
         [{:animation, class, animation} | rules] ++ below}

      nil ->
        {element, rules ++ below}
    end
  end

  defp class(kind, motion) do
    "vis-#{kind}-" <> (motion |> :erlang.phash2() |> Integer.to_string(36) |> String.downcase())
  end

  defp add_class(style, class) do
    Map.update(style, :class, class, fn own -> own <> " " <> class end)
  end
end
